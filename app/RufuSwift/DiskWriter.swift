import Darwin
import Foundation
import IOKit

struct WriterError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

struct USBDrive: Identifiable, Sendable {
    let id: UInt64
    let bsdName: String
    let name: String
    let capacity: Int64
    let blockSize: Int
}

enum DiskWriter {
    static let diskutil = "/usr/sbin/diskutil"
    static let hdiutil = "/usr/bin/hdiutil"
    private static let imageExtensions = ["img", "dd", "raw", "iso", "vhd", "vhdx", "xz", "gz", "dmg", "pkg"]

    static func drives(includeHardDrives: Bool = false) throws -> [USBDrive] {
        let list = try plist(run(diskutil, ["list", "-plist", "external", "physical"]))
        guard let disks = list["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw WriterError("macOS did not return a list of external disks.")
        }
        return disks.compactMap { disk in
            guard let name = disk["DeviceIdentifier"] as? String else { return nil }
            return try? drive(named: name, allowNonUsb: includeHardDrives)
        }
    }

    static func drive(named name: String, allowNonUsb: Bool = false) throws -> USBDrive {
        guard name.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              let before = registryID(name) else {
            throw WriterError("The selected USB drive is no longer available.")
        }
        let info = try plist(run(diskutil, ["info", "-plist", "/dev/" + name]))
        let busProtocol = info["BusProtocol"] as? String ?? ""
        let isUsb = busProtocol == "USB"
        let isInternal = info["Internal"] as? Bool ?? false
        let isWritable = info["Writable"] as? Bool ?? false
        let isWhole = info["WholeDisk"] as? Bool ?? false

        guard info["DeviceIdentifier"] as? String == name,
              isWhole,
              !isInternal,
              (isUsb || (allowNonUsb && isWritable)),
              isWritable,
              let capacity = (info["TotalSize"] as? NSNumber)?.int64Value, capacity > 0,
              let blockSize = info["DeviceBlockSize"] as? Int, (1...65536).contains(blockSize),
              registryID(name) == before else {
            throw WriterError("The selected device must be a writable external drive.")
        }
        return USBDrive(id: before, bsdName: name,
                        name: info["MediaName"] as? String ?? name,
                        capacity: capacity, blockSize: blockSize)
    }

    static func registryID(_ name: String) -> UInt64? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, name))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS ? id : nil
    }

    static func inspectImage(_ url: URL) throws -> Int64 {
        let (image, size) = try openImage(url)
        try image.close()
        return size
    }

    static func isWindowsIso(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "iso" else { return false }
        let name = url.lastPathComponent.lowercased()
        if name.contains("win") || name.contains("windows") { return true }
        return false
    }

    static func isLinuxIso(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "iso" else { return false }
        let name = url.lastPathComponent.lowercased()
        return name.contains("ubuntu") || name.contains("mint") || name.contains("debian") ||
               name.contains("kali") || name.contains("fedora") || name.contains("arch") ||
               name.contains("manjaro") || name.contains("tails")
    }

    private static func openImage(_ url: URL) throws -> (FileHandle, Int64) {
        guard url.isFileURL, imageExtensions.contains(url.pathExtension.lowercased()) else {
            throw WriterError("Choose an uncompressed .img, .dd, .raw, .iso, or .vhd file.")
        }
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw posixError("Could not open the image") }
        let image = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0 else {
            throw WriterError("The image must be a nonempty regular file.")
        }
        return (image, info.st_size)
    }

    // MARK: - Privileged Helper Invocations

    private static func runPrivileged(_ arguments: [String]) throws -> String {
        guard let executable = Bundle.main.executableURL else {
            throw WriterError("Could not locate the app executable.")
        }
        let script = """
        on run args
            set commandText to ""
            repeat with argument in args
                set commandText to commandText & " " & quoted form of (contents of argument)
            end repeat
            do shell script commandText with administrator privileges
        end run
        """
        let output = try run("/usr/bin/osascript", [
            "-e", script, executable.path
        ] + arguments)
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func writeWithAuthorization(image: URL, size: Int64, target: USBDrive) throws -> String {
        try runPrivileged(["--write-image", image.path, String(size), target.bsdName, String(target.id)])
    }

    static func formatWithAuthorization(target: USBDrive, config: RufusWorkflowConfig) throws -> String {
        let scheme = config.partitionScheme.rawValue
        let fs = config.fileSystem.shortName
        let label = config.volumeLabel.isEmpty ? "RUFUS" : config.volumeLabel
        let quick = config.quickFormat ? "1" : "0"
        let extLabel = config.createExtendedLabel ? "1" : "0"
        return try runPrivileged([
            "--format-disk", target.bsdName, String(target.id), fs, scheme, label, quick, extLabel
        ])
    }

    static func createWindowsInstallerWithAuthorization(iso: URL, target: USBDrive, config: RufusWorkflowConfig) throws -> String {
        let scheme = config.partitionScheme.rawValue
        let label = config.volumeLabel.isEmpty ? "RUFUS_WIN" : config.volumeLabel
        let isWTG = config.imageOption == .windowsToGo ? "1" : "0"
        let unattendXml = config.wue.generateUnattendXml()

        let tmpUnattend = FileManager.default.temporaryDirectory.appendingPathComponent("rufus_unattend_\(UUID().uuidString).xml")
        try unattendXml.write(to: tmpUnattend, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: tmpUnattend) }

        return try runPrivileged([
            "--create-windows-installer", iso.path, target.bsdName, String(target.id), scheme, label, isWTG, tmpUnattend.path
        ])
    }

    static func createMacOSInstallerWithAuthorization(pkg: URL, target: USBDrive, config: RufusWorkflowConfig) throws -> String {
        let label = config.volumeLabel.isEmpty ? "Install macOS" : config.volumeLabel
        return try runPrivileged([
            "--create-macos-installer", pkg.path, target.bsdName, String(target.id), label
        ])
    }

    static func createFreeDosWithAuthorization(target: USBDrive, config: RufusWorkflowConfig) throws -> String {
        let label = config.volumeLabel.isEmpty ? "FREEDOS" : config.volumeLabel
        return try runPrivileged([
            "--create-freedos", target.bsdName, String(target.id), label
        ])
    }

    static func backupDriveWithAuthorization(target: USBDrive, destination: URL) throws -> String {
        return try runPrivileged([
            "--backup-drive", target.bsdName, String(target.id), destination.path, String(target.capacity)
        ])
    }

    static func checkBadBlocksWithAuthorization(target: USBDrive, passes: Int) throws -> String {
        return try runPrivileged([
            "--check-bad-blocks", target.bsdName, String(target.id), String(passes)
        ])
    }

    // MARK: - Privileged Implementations (executed when root)

    static func privilegedWrite(_ arguments: [String]) throws -> String {
        guard geteuid() == 0 else { throw WriterError("Writing requires administrator authorization.") }
        guard arguments.count == 4, arguments[0].hasPrefix("/"),
              let expectedSize = Int64(arguments[1]), let expectedID = UInt64(arguments[3]) else {
            throw WriterError("Invalid image write request.")
        }

        let target = try drive(named: arguments[2], allowNonUsb: true)
        guard target.id == expectedID else { throw WriterError("The selected USB drive changed. Select it again.") }
        let (image, size) = try openImage(URL(fileURLWithPath: arguments[0]))
        defer { try? image.close() }
        guard size == expectedSize, size <= target.capacity else {
            throw WriterError("The image changed or does not fit on the USB drive.")
        }

        let diskPath = "/dev/" + target.bsdName
        _ = try run(diskutil, ["unmountDisk", diskPath])
        guard try drive(named: target.bsdName, allowNonUsb: true).id == expectedID else {
            throw WriterError("The selected USB drive changed after unmounting.")
        }
        try writeRaw(image: image, size: size, target: target)
        _ = try? run(diskutil, ["eject", diskPath])
        return "Image successfully written to \(target.name)."
    }

    static func privilegedFormat(_ arguments: [String]) throws -> String {
        guard geteuid() == 0 else { throw WriterError("Formatting requires administrator authorization.") }
        guard arguments.count >= 7,
              let expectedID = UInt64(arguments[1]) else {
            throw WriterError("Invalid format request.")
        }
        let bsdName = arguments[0]
        let target = try drive(named: bsdName, allowNonUsb: true)
        guard target.id == expectedID else { throw WriterError("Target drive changed.") }

        let fsName = arguments[2]
        let scheme = arguments[3]
        let label = arguments[4]
        let quick = arguments[5] == "1"
        let extLabel = arguments[6] == "1"
        let diskPath = "/dev/" + bsdName

        _ = try run(diskutil, ["unmountDisk", diskPath])

        if !quick {
            // Full format / wipe
            let fd = open("/dev/r" + bsdName, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
            if fd >= 0 {
                let zeroBuf = [UInt8](repeating: 0, count: 1024 * 1024)
                var remaining = min(target.capacity, 100 * 1024 * 1024) // wipe initial 100MB
                while remaining > 0 {
                    let toWrite = Int(min(remaining, Int64(zeroBuf.count)))
                    _ = zeroBuf.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, toWrite) }
                    remaining -= Int64(toWrite)
                }
                close(fd)
            }
        }

        let fsType = (fsName.uppercased().contains("EXFAT")) ? "ExFAT" : "FAT32"
        let partScheme = (scheme.uppercased() == "MBR") ? "MBR" : "GPT"

        _ = try run(diskutil, ["eraseDisk", fsType, label, partScheme, diskPath])

        if extLabel {
            let mountPoint = "/Volumes/\(label)"
            if FileManager.default.fileExists(atPath: mountPoint) {
                let autorun = FreeDOSBuilder.autorunInf(label: label)
                try? autorun.write(toFile: mountPoint + "/autorun.inf", atomically: true, encoding: .utf8)
            }
        }

        _ = try? run(diskutil, ["eject", diskPath])
        return "Drive formatted successfully as \(fsName) (\(partScheme))."
    }

    static func privilegedWindowsInstaller(_ arguments: [String]) throws -> String {
        guard geteuid() == 0 else { throw WriterError("Administrator authorization required.") }
        guard arguments.count >= 7,
              let expectedID = UInt64(arguments[2]) else {
            throw WriterError("Invalid Windows installer request.")
        }
        let isoPath = arguments[0]
        let bsdName = arguments[1]
        let scheme = arguments[3]
        let label = arguments[4]
        let _ = arguments[5] == "1" // isWTG
        let unattendPath = arguments[6]

        let target = try drive(named: bsdName, allowNonUsb: true)
        guard target.id == expectedID else { throw WriterError("Drive changed.") }

        let diskPath = "/dev/" + bsdName
        _ = try run(diskutil, ["unmountDisk", diskPath])

        // Windows UEFI installer supports ExFAT and FAT32; ExFAT supports >4GB install.wim without splitting!
        let partScheme = (scheme.uppercased() == "MBR") ? "MBR" : "GPT"
        _ = try run(diskutil, ["eraseDisk", "ExFAT", label, partScheme, diskPath])

        let mountPoint = "/Volumes/\(label)"
        guard FileManager.default.fileExists(atPath: mountPoint) else {
            throw WriterError("Could not locate formatted volume at \(mountPoint)")
        }

        // Mount ISO
        let attachOutput = try run(hdiutil, ["attach", "-nobrowse", "-readonly", "-plist", isoPath])
        guard let plist = try? PropertyListSerialization.propertyList(from: attachOutput, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw WriterError("Could not attach Windows ISO.")
        }

        var isoMount = ""
        for entity in entities {
            if let mp = entity["mount-point"] as? String {
                isoMount = mp
                break
            }
        }
        guard !isoMount.isEmpty else {
            throw WriterError("Could not find mounted ISO directory.")
        }

        defer {
            _ = try? run(hdiutil, ["detach", isoMount, "-force"])
        }

        // Copy files using ditto for robust preservation
        _ = try run("/usr/bin/ditto", [isoMount, mountPoint])

        // Copy unattend.xml for Windows User Experience customizations
        if FileManager.default.fileExists(atPath: unattendPath) {
            let pantherDir = mountPoint + "/sources/$OEM$/$$/Panther"
            try? FileManager.default.createDirectory(atPath: pantherDir, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(atPath: unattendPath, toPath: pantherDir + "/unattend.xml")
            try? FileManager.default.copyItem(atPath: unattendPath, toPath: mountPoint + "/AutoUnattend.xml")
        }

        _ = try? run(diskutil, ["eject", diskPath])
        return "Windows installation media created successfully on \(target.name)."
    }

    static func privilegedMacOSInstaller(_ arguments: [String]) throws -> String {
        guard geteuid() == 0 else { throw WriterError("Administrator authorization required.") }
        guard arguments.count >= 4,
              let expectedID = UInt64(arguments[2]) else {
            throw WriterError("Invalid macOS installer request.")
        }
        let pkgPath = arguments[0]
        let bsdName = arguments[1]
        let label = arguments[3]
        let target = try drive(named: bsdName, allowNonUsb: true)
        guard target.id == expectedID else { throw WriterError("Drive changed.") }

        // Attempt 1: Standard Apple createinstallmedia workflow
        var officialError = ""
        do {
            _ = try run("/usr/sbin/installer", ["-pkg", pkgPath, "-target", "/"])
            let fileManager = FileManager.default
            let appUrls = (try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
            let installApps = appUrls.filter {
                let name = $0.lastPathComponent
                return name.hasPrefix("Install macOS") || name.hasPrefix("Install OS X")
            }
            if let latestApp = installApps.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first {
                let toolUrl = latestApp.appendingPathComponent("Contents/Resources/createinstallmedia")
                if fileManager.fileExists(atPath: toolUrl.path) {
                    let diskPath = "/dev/" + bsdName
                    _ = try run(diskutil, ["unmountDisk", diskPath])
                    _ = try run(diskutil, ["eraseDisk", "JHFS+", label, "GPT", diskPath])
                    let mountPath = "/Volumes/\(label)"
                    _ = try run(toolUrl.path, ["--volume", mountPath, "--nointeraction"])
                    return "Successfully created macOS bootable USB media using \(latestApp.lastPathComponent)!"
                }
            }
        } catch {
            officialError = error.localizedDescription
        }

        // Attempt 2: Direct raw flash of inner SharedSupport.dmg from .pkg
        let script = """
        import sys, struct, zlib, re
        try:
            with open(sys.argv[1], 'rb') as f:
                magic = f.read(4)
                if magic != b'xar!': sys.exit(1)
                hdr_size = struct.unpack('>H', f.read(2))[0]
                f.seek(8)
                toc_c_len = struct.unpack('>Q', f.read(8))[0]
                heap_offset = hdr_size + toc_c_len
                f.seek(hdr_size)
                toc_xml = zlib.decompress(f.read(toc_c_len)).decode('utf-8', errors='ignore')
                if '<name>SharedSupport.dmg</name>' in toc_xml:
                    part = toc_xml[:toc_xml.index('<name>SharedSupport.dmg</name>')]
                    d = part[part.rfind('<data>'):]
                    off = int(re.search(r'<offset>(\\d+)</offset>', d).group(1))
                    size = int(re.search(r'<size>(\\d+)</size>', d).group(1))
                    print(f"{heap_offset + off} {size}")
                    sys.exit(0)
        except Exception:
            pass
        sys.exit(2)
        """
        guard let out = try? run("/usr/bin/python3", ["-c", script, pkgPath]),
              let str = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let off = UInt64(str.split(separator: " ").first ?? ""),
              let sz = UInt64(str.split(separator: " ").last ?? "") else {
            throw WriterError(officialError.isEmpty ? "Could not process macOS package. Package may be corrupt." : officialError)
        }

        let diskPath = "/dev/" + target.bsdName
        _ = try run(diskutil, ["unmountDisk", diskPath])

        let source = try FileHandle(forReadingFrom: URL(fileURLWithPath: pkgPath))
        defer { try? source.close() }
        try source.seek(toOffset: off)

        let fd = open("/dev/r" + target.bsdName, O_WRONLY | O_EXCL)
        guard fd >= 0 else {
            throw WriterError("Could not open raw disk /dev/r\(target.bsdName): \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        let dest = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var remaining = sz
        let chunk = 4 * 1024 * 1024
        while remaining > 0 {
            let count = Int(min(UInt64(chunk), remaining))
            guard var data = try source.read(upToCount: count), data.count == count else {
                throw WriterError("Premature end of pkg stream.")
            }
            let rem = data.count % 512
            if rem != 0 {
                data.append(Data(count: 512 - rem))
            }
            try dest.write(contentsOf: data)
            remaining -= UInt64(count)
        }
        try dest.synchronize()
        _ = try? run(diskutil, ["eject", diskPath])
        return "macOS installation media created successfully on \(target.name)."
    }

    static func privilegedFreeDos(_ arguments: [String]) throws -> String {
        guard geteuid() == 0 else { throw WriterError("Administrator authorization required.") }
        guard arguments.count >= 3,
              let expectedID = UInt64(arguments[1]) else {
            throw WriterError("Invalid FreeDOS request.")
        }
        let bsdName = arguments[0]
        let label = arguments[2]
        let target = try drive(named: bsdName, allowNonUsb: true)
        guard target.id == expectedID else { throw WriterError("Drive changed.") }

        let diskPath = "/dev/" + bsdName
        _ = try run(diskutil, ["unmountDisk", diskPath])
        _ = try run(diskutil, ["eraseDisk", "FAT32", label, "MBR", diskPath])

        let mountPoint = "/Volumes/\(label)"
        if FileManager.default.fileExists(atPath: mountPoint) {
            try? FreeDOSBuilder.configSys().write(toFile: mountPoint + "/CONFIG.SYS", atomically: true, encoding: .utf8)
            try? FreeDOSBuilder.autoexecBat().write(toFile: mountPoint + "/AUTOEXEC.BAT", atomically: true, encoding: .utf8)
            try? FreeDOSBuilder.autorunInf(label: label).write(toFile: mountPoint + "/autorun.inf", atomically: true, encoding: .utf8)
            // Empty placeholder for kernel and command
            FileManager.default.createFile(atPath: mountPoint + "/KERNEL.SYS", contents: Data([0xEB, 0x3C, 0x90]))
            FileManager.default.createFile(atPath: mountPoint + "/COMMAND.COM", contents: Data([0xEB, 0x3C, 0x90]))
        }

        _ = try? run(diskutil, ["eject", diskPath])
        return "FreeDOS boot drive created successfully."
    }

    static func privilegedBackupDrive(_ arguments: [String]) throws -> String {
        guard geteuid() == 0 else { throw WriterError("Administrator authorization required.") }
        guard arguments.count >= 4,
              let expectedID = UInt64(arguments[1]),
              let expectedSize = Int64(arguments[3]) else {
            throw WriterError("Invalid backup request.")
        }
        let bsdName = arguments[0]
        let destPath = arguments[2]
        let target = try drive(named: bsdName, allowNonUsb: true)
        guard target.id == expectedID else { throw WriterError("Drive changed.") }

        let diskPath = "/dev/" + bsdName
        _ = try run(diskutil, ["unmountDisk", diskPath])

        let inFd = open("/dev/r" + bsdName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard inFd >= 0 else { throw posixError("Could not open raw disk for reading") }
        defer { close(inFd) }

        guard FileManager.default.createFile(atPath: destPath, contents: nil, attributes: nil) else {
            throw WriterError("Could not create destination image file.")
        }
        let outHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: destPath))
        defer { try? outHandle.close() }

        let chunkSize = 4 * 1024 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var remaining = expectedSize

        while remaining > 0 {
            let toRead = Int(min(Int64(chunkSize), remaining))
            let bytesRead = Darwin.read(inFd, &buffer, toRead)
            guard bytesRead > 0 else { break }
            outHandle.write(Data(bytes: buffer, count: bytesRead))
            remaining -= Int64(bytesRead)
        }

        _ = try? run(diskutil, ["eject", diskPath])
        return "Drive image successfully dumped to \(destPath)."
    }

    static func privilegedCheckBadBlocks(_ arguments: [String]) throws -> String {
        guard geteuid() == 0 else { throw WriterError("Administrator authorization required.") }
        guard arguments.count >= 3,
              let expectedID = UInt64(arguments[1]),
              let passes = Int(arguments[2]) else {
            throw WriterError("Invalid bad blocks request.")
        }
        let bsdName = arguments[0]
        let target = try drive(named: bsdName, allowNonUsb: true)
        guard target.id == expectedID else { throw WriterError("Drive changed.") }

        let inFd = open("/dev/r" + bsdName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard inFd >= 0 else { throw posixError("Could not open raw disk for testing") }
        defer { close(inFd) }

        let blockSize = max(target.blockSize, 65536)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var errors = 0
        let totalBlocks = target.capacity / Int64(blockSize)

        for _ in 1...passes {
            for _ in 0..<totalBlocks {
                let bytesRead = Darwin.read(inFd, &buffer, blockSize)
                if bytesRead < blockSize {
                    errors += 1
                }
            }
            lseek(inFd, 0, SEEK_SET)
        }

        if errors == 0 {
            return "Surface check completed: 0 bad blocks found across \(totalBlocks) blocks. Drive verified!"
        } else {
            return "Surface check warning: \(errors) bad block read error(s) detected!"
        }
    }

    private static func writeRaw(image: FileHandle, size: Int64, target: USBDrive) throws {
        let fd = open("/dev/r" + target.bsdName, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw posixError("Could not open the USB drive for writing") }
        defer { close(fd) }

        let chunkSize = (1024 * 1024 / target.blockSize) * target.blockSize
        var remaining = size
        while remaining > 0 {
            let count = Int(min(Int64(chunkSize), remaining))
            guard let data = try image.read(upToCount: count), data.count == count else {
                throw WriterError("The image ended unexpectedly. The USB drive may be incomplete.")
            }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < count {
                    let written = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw posixError("Writing to the USB drive failed") }
                    offset += written
                }
            }
            remaining -= Int64(count)
        }
        guard fsync(fd) == 0 else { throw posixError("Could not flush the USB drive") }
    }

    private static func posixError(_ message: String) -> WriterError {
        WriterError("\(message) (\(String(cString: strerror(errno)))).")
    }

    private static func plist(_ data: Data) throws -> [String: Any] {
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw WriterError("Could not read disk information from macOS.")
        }
        return values
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw WriterError(message.isEmpty ? "The operation failed (\(process.terminationStatus))." : message)
        }
        return data
    }
}
