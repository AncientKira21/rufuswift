#if os(macOS)
import Darwin
import Foundation
import IOKit

enum PlatformWriter {
    private static let diskutil = "/usr/sbin/diskutil"
    private static let hdiutil = "/usr/bin/hdiutil"

    static func drives(includeHardDrives: Bool = false) throws -> [Drive] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: diskutil)
        process.arguments = ["list", "-plist", "external", "physical"]
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let disks = plist["AllDisksAndPartitions"] as? [[String: Any]] else {
            return []
        }

        return disks.compactMap { disk in
            guard let name = disk["DeviceIdentifier"] as? String,
                  name.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { return nil }
            return try? drive(named: name, includeHardDrives: includeHardDrives)
        }
    }

    private static func drive(named name: String, includeHardDrives: Bool) throws -> Drive {
        guard let id = registryID(name) else {
            throw WriterError("Drive unavailable")
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: diskutil)
        process.arguments = ["info", "-plist", "/dev/" + name]
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["WholeDisk"] as? Bool == true,
              info["Internal"] as? Bool == false,
              let capacity = (info["TotalSize"] as? NSNumber)?.int64Value, capacity > 0 else {
            throw WriterError("Invalid drive info")
        }
        let isUsb = (info["BusProtocol"] as? String) == "USB"
        if !isUsb && !includeHardDrives {
            throw WriterError("Not a USB drive")
        }

        let blockSize = (info["DeviceBlockSize"] as? NSNumber)?.int64Value ?? 512
        let friendlyName = info["MediaName"] as? String ?? name
        return Drive(id: String(id), device: name, name: friendlyName, capacity: capacity, blockSize: blockSize)
    }

    private static func registryID(_ name: String) -> UInt64? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, name))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS ? id : nil
    }

    private static func runScript(_ scriptCmd: String) throws {
        let script = """
        on run args
            set commandText to ""
            repeat with argument in args
                set commandText to commandText & " " & quoted form of (contents of argument)
            end repeat
            do shell script commandText with administrator privileges
        end run
        """
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, "/bin/sh", "-c", scriptCmd]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw WriterError(err.isEmpty ? "Operation failed (\(process.terminationStatus))" : err)
        }
    }

    static func write(_ image: DiskImage, to drive: Drive) throws {
        let targetDev = "/dev/" + drive.device
        let rawDev = "/dev/r" + drive.device
        let unmountCmd = "/usr/sbin/diskutil unmountDisk " + targetDev
        let ddCmd = "/bin/dd if=" + image.url.path + " of=" + rawDev + " bs=4m status=none"
        let ejectCmd = "/usr/sbin/diskutil eject " + targetDev
        try runScript("\(unmountCmd) && \(ddCmd) && \(ejectCmd)")
    }

    static func format(_ drive: Drive, config: RufusWorkflowConfig) throws {
        let targetDev = "/dev/" + drive.device
        let fs = config.fileSystem == .exfat ? "ExFAT" : "FAT32"
        let scheme = config.partitionScheme == .mbr ? "MBR" : "GPT"
        let label = config.volumeLabel.isEmpty ? "RUFUS" : config.volumeLabel
        let unmountCmd = "/usr/sbin/diskutil unmountDisk " + targetDev
        let eraseCmd = "/usr/sbin/diskutil eraseDisk \(fs) \(label) \(scheme) \(targetDev)"
        let ejectCmd = "/usr/sbin/diskutil eject " + targetDev
        try runScript("\(unmountCmd) && \(eraseCmd) && \(ejectCmd)")
    }

    static func createWindowsInstaller(_ image: DiskImage, to drive: Drive, config: RufusWorkflowConfig) throws {
        let targetDev = "/dev/" + drive.device
        let scheme = config.partitionScheme == .mbr ? "MBR" : "GPT"
        let label = config.volumeLabel.isEmpty ? "RUFUS_WIN" : config.volumeLabel
        let unattend = config.wue.generateUnattendXml()

        let tmpUnattend = FileManager.default.temporaryDirectory.appendingPathComponent("rufus_wue_\(UUID().uuidString).xml")
        try unattend.write(to: tmpUnattend, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpUnattend) }

        let cmd = """
        /usr/sbin/diskutil unmountDisk \(targetDev) && \
        /usr/sbin/diskutil eraseDisk ExFAT \(label) \(scheme) \(targetDev) && \
        ISO_MNT=$(/usr/bin/hdiutil attach -nobrowse -readonly '\(image.url.path)' | grep '/Volumes/' | awk '{print $NF}') && \
        /usr/bin/ditto "$ISO_MNT" '/Volumes/\(label)' && \
        mkdir -p '/Volumes/\(label)/sources/$OEM$/$$/Panther' && \
        cp '\(tmpUnattend.path)' '/Volumes/\(label)/sources/$OEM$/$$/Panther/unattend.xml' && \
        cp '\(tmpUnattend.path)' '/Volumes/\(label)/AutoUnattend.xml' && \
        /usr/bin/hdiutil detach "$ISO_MNT" -force && \
        /usr/sbin/diskutil eject \(targetDev)
        """
        try runScript(cmd)
    }

    static func backup(_ drive: Drive, to destination: URL) throws {
        let targetDev = "/dev/" + drive.device
        let rawDev = "/dev/r" + drive.device
        let unmountCmd = "/usr/sbin/diskutil unmountDisk " + targetDev
        let ddCmd = "/bin/dd if=" + rawDev + " of=" + destination.path + " bs=4m status=none"
        let ejectCmd = "/usr/sbin/diskutil eject " + targetDev
        try runScript("\(unmountCmd) && \(ddCmd) && \(ejectCmd)")
    }

    static func checkBadBlocks(_ drive: Drive, passes: Int) throws {
        let rawDev = "/dev/r" + drive.device
        let ddCmd = "/bin/dd if=" + rawDev + " of=/dev/null bs=1m status=none"
        try runScript(ddCmd)
    }

    static func expandGzip(_ source: URL, to destination: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", source.path]
        let outHandle = try FileHandle(forWritingTo: destination)
        defer { try? outHandle.close() }
        process.standardOutput = outHandle
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw WriterError(err.isEmpty ? "Gzip decompression failed" : err)
        }
    }
}
#endif
