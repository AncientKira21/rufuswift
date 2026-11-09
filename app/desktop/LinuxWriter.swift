#if os(Linux)
import Foundation
import Glibc

enum PlatformWriter {
    private struct BlockDevices: Decodable {
        let blockdevices: [BlockDevice]
    }

    private struct BlockDevice: Decodable {
        let name: String
        let type: String
        let tran: String?
        let model: String?
        let size: Int64
        let ro: Bool
        let logSec: Int64

        enum CodingKeys: String, CodingKey {
            case name, type, tran, model, size, ro
            case logSec = "log-sec"
        }
    }

    static func drives(includeHardDrives: Bool = false) throws -> [Drive] {
        let output = try runCommand(URL(fileURLWithPath: "/usr/bin/lsblk"), [
            "--json", "--bytes", "--nodeps", "--output", "NAME,TYPE,TRAN,MODEL,SIZE,RO,LOG-SEC"
        ])
        return try JSONDecoder().decode(BlockDevices.self, from: output).blockdevices.compactMap { disk in
            guard disk.type == "disk", (disk.tran == "usb" || includeHardDrives), !disk.ro, disk.size > 0,
                  (1...65536).contains(disk.logSec),
                  disk.name.range(of: #"^(sd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$"#, options: .regularExpression) != nil,
                  let id = diskSequence(disk.name) else { return nil }
            let name = disk.model?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Drive(id: id, device: disk.name, name: name ?? disk.name,
                         capacity: disk.size, blockSize: disk.logSec)
        }
    }

    private static func diskSequence(_ name: String) -> String? {
        let path = "/sys/class/block/\(name)/diskseq"
        let number = (try? String(contentsOfFile: path, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let number, UInt64(number) != nil { return number }
        // Fallback to sysfs dev number
        let devPath = "/sys/class/block/\(name)/dev"
        return (try? String(contentsOfFile: devPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ image: DiskImage, to drive: Drive) throws {
        let arguments = [image.url.path, String(image.size), drive.device, drive.id]
        if geteuid() == 0 {
            try writePrivileged(arguments)
        } else {
            let executable = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
            _ = try runCommand(URL(fileURLWithPath: "/usr/bin/pkexec"),
                               [executable.path, "--write-image"] + arguments)
        }
    }

    static func format(_ drive: Drive, config: RufusWorkflowConfig) throws {
        let arguments = [drive.device, drive.id, config.fileSystem.shortName, config.partitionScheme.rawValue, config.volumeLabel, config.quickFormat ? "1" : "0"]
        if geteuid() == 0 {
            try formatPrivileged(arguments)
        } else {
            let executable = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
            _ = try runCommand(URL(fileURLWithPath: "/usr/bin/pkexec"),
                               [executable.path, "--format-disk"] + arguments)
        }
    }

    static func createWindowsInstaller(_ image: DiskImage, to drive: Drive, config: RufusWorkflowConfig) throws {
        let xml = config.wue.generateUnattendXml()
        let tmpFile = "/tmp/rufus_unattend_\(UUID().uuidString).xml"
        try xml.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpFile) }

        let arguments = [image.url.path, drive.device, drive.id, config.partitionScheme.rawValue, config.volumeLabel, tmpFile]
        if geteuid() == 0 {
            try windowsInstallerPrivileged(arguments)
        } else {
            let executable = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
            _ = try runCommand(URL(fileURLWithPath: "/usr/bin/pkexec"),
                               [executable.path, "--create-windows-installer"] + arguments)
        }
    }

    static func backup(_ drive: Drive, to destination: URL) throws {
        let arguments = [drive.device, drive.id, destination.path, String(drive.capacity)]
        if geteuid() == 0 {
            try backupPrivileged(arguments)
        } else {
            let executable = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
            _ = try runCommand(URL(fileURLWithPath: "/usr/bin/pkexec"),
                               [executable.path, "--backup-drive"] + arguments)
        }
    }

    static func checkBadBlocks(_ drive: Drive, passes: Int) throws {
        let arguments = [drive.device, drive.id, String(passes)]
        if geteuid() == 0 {
            try checkBadBlocksPrivileged(arguments)
        } else {
            let executable = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
            _ = try runCommand(URL(fileURLWithPath: "/usr/bin/pkexec"),
                               [executable.path, "--check-bad-blocks"] + arguments)
        }
    }

    // MARK: - Privileged Implementations

    private static func extractDmgOffsetAndSize(from pkgPath: String) -> (UInt64, UInt64)? {
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
        for py in ["/usr/bin/python3", "/usr/bin/python", "python3"] {
            guard let out = try? runCommand(URL(fileURLWithPath: py), ["-c", script, pkgPath]) else { continue }
            let str = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = str.split(separator: " ")
            if parts.count == 2, let off = UInt64(parts[0]), let sz = UInt64(parts[1]) {
                return (off, sz)
            }
        }
        return nil
    }

    static func writePrivileged(_ arguments: [String]) throws {
        guard geteuid() == 0 else { throw WriterError("Writing requires administrator authorization.") }
        guard arguments.count >= 4, let expectedSize = Int64(arguments[1]),
              let drive = try drives(includeHardDrives: true).first(where: { $0.device == arguments[2] && $0.id == arguments[3] }) else {
            throw WriterError("The selected external USB drive changed or is unavailable.")
        }
        let image = try DiskImage(URL(fileURLWithPath: arguments[0]))
        guard image.size == expectedSize else {
            throw WriterError("The image file size changed.")
        }
        let source = try FileHandle(forReadingFrom: image.url)
        defer { try? source.close() }

        var streamStart: UInt64 = 0
        var streamLen: UInt64 = UInt64(image.size)

        // Check for Apple installer .pkg (XAR archive with embedded SharedSupport.dmg)
        let magic = try source.read(upToCount: 4) ?? Data()
        if magic.count == 4 && magic == Data([0x78, 0x61, 0x72, 0x21]) { // "xar!"
            if let (offset, size) = extractDmgOffsetAndSize(from: image.url.path) {
                streamStart = offset
                streamLen = size
            }
        }

        guard Int64(streamLen) <= drive.capacity else {
            throw WriterError("The image does not fit on the selected USB drive.")
        }

        let fd = open("/dev/" + drive.device, O_WRONLY | O_EXCL | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw WriterError("Could not open the USB drive exclusively. Unmount its volumes first. (\(String(cString: strerror(errno))))")
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFBLK,
              diskSequence(drive.device) == drive.id else {
            throw WriterError("The USB drive changed before writing.")
        }
        let destination = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try source.seek(toOffset: streamStart)
        let chunk = max(Int(drive.blockSize), (1024 * 1024 / Int(drive.blockSize)) * Int(drive.blockSize))
        var remaining = streamLen
        while remaining > 0 {
            let count = Int(min(UInt64(chunk), remaining))
            guard var data = try source.read(upToCount: count), data.count == count else {
                throw WriterError("The image ended early. The USB drive may be incomplete.")
            }
            let remainder = data.count % Int(drive.blockSize)
            if remainder != 0 {
                let pad = Int(drive.blockSize) - remainder
                data.append(Data(count: pad))
            }
            try destination.write(contentsOf: data)
            remaining -= UInt64(count)
        }
        try destination.synchronize()
    }

    static func formatPrivileged(_ arguments: [String]) throws {
        guard geteuid() == 0 else { throw WriterError("Administrator privileges required.") }
        let device = arguments[0]
        let devPath = "/dev/" + device
        let fs = arguments[2].lowercased()
        let scheme = arguments[3].lowercased()
        let label = arguments[4]

        // Unmount any existing partitions
        _ = try? runCommand(URL(fileURLWithPath: "/bin/sh"), ["-c", "umount \(devPath)* || true"])
        _ = try? runCommand(URL(fileURLWithPath: "/sbin/wipefs"), ["-a", devPath])

        // Partition with parted
        let partType = scheme == "mbr" ? "msdos" : "gpt"
        _ = try runCommand(URL(fileURLWithPath: "/sbin/parted"), ["-s", devPath, "mklabel", partType])
        _ = try runCommand(URL(fileURLWithPath: "/sbin/parted"), ["-s", devPath, "mkpart", "primary", "1MiB", "100%"])

        let partDev = device.starts(with: "nvme") || device.starts(with: "mmcblk") ? devPath + "p1" : devPath + "1"

        // Format filesystem
        if fs.contains("fat") {
            _ = try runCommand(URL(fileURLWithPath: "/sbin/mkfs.vfat"), ["-F", "32", "-n", label, partDev])
        } else if fs.contains("ntfs") {
            _ = try runCommand(URL(fileURLWithPath: "/sbin/mkfs.ntfs"), ["-f", "-L", label, partDev])
        } else if fs.contains("exfat") {
            _ = try runCommand(URL(fileURLWithPath: "/sbin/mkfs.exfat"), ["-n", label, partDev])
        } else {
            _ = try runCommand(URL(fileURLWithPath: "/sbin/mkfs.ext4"), ["-F", "-L", label, partDev])
        }
    }

    static func windowsInstallerPrivileged(_ arguments: [String]) throws {
        guard geteuid() == 0 else { throw WriterError("Administrator privileges required.") }
        let iso = arguments[0]
        let device = arguments[1]
        let devPath = "/dev/" + device
        let label = arguments[4]
        let unattend = arguments[5]

        // Format as GPT with exFAT/FAT32
        try formatPrivileged([device, arguments[2], "exfat", "gpt", label, "1"])

        let partDev = device.starts(with: "nvme") || device.starts(with: "mmcblk") ? devPath + "p1" : devPath + "1"
        let mountDir = "/tmp/rufus_mnt_\(UUID().uuidString)"
        let isoDir = "/tmp/rufus_iso_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: mountDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: isoDir, withIntermediateDirectories: true)
        defer {
            _ = try? runCommand(URL(fileURLWithPath: "/bin/umount"), [mountDir])
            _ = try? runCommand(URL(fileURLWithPath: "/bin/umount"), [isoDir])
            try? FileManager.default.removeItem(atPath: mountDir)
            try? FileManager.default.removeItem(atPath: isoDir)
        }

        _ = try runCommand(URL(fileURLWithPath: "/bin/mount"), ["-o", "loop,ro", iso, isoDir])
        _ = try runCommand(URL(fileURLWithPath: "/bin/mount"), [partDev, mountDir])
        _ = try runCommand(URL(fileURLWithPath: "/bin/cp"), ["-a", isoDir + "/.", mountDir])

        if FileManager.default.fileExists(atPath: unattend) {
            let panther = mountDir + "/sources/$OEM$/$$/Panther"
            try? FileManager.default.createDirectory(atPath: panther, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(atPath: unattend, toPath: panther + "/unattend.xml")
            try? FileManager.default.copyItem(atPath: unattend, toPath: mountDir + "/AutoUnattend.xml")
        }
    }

    static func backupPrivileged(_ arguments: [String]) throws {
        guard geteuid() == 0 else { throw WriterError("Administrator privileges required.") }
        let device = arguments[0]
        let dest = arguments[2]
        let devPath = "/dev/" + device
        _ = try runCommand(URL(fileURLWithPath: "/bin/dd"), [
            "if=" + devPath, "of=" + dest, "bs=4M", "status=none"
        ])
    }

    static func checkBadBlocksPrivileged(_ arguments: [String]) throws {
        guard geteuid() == 0 else { throw WriterError("Administrator privileges required.") }
        let device = arguments[0]
        let passes = arguments[2]
        let devPath = "/dev/" + device
        _ = try runCommand(URL(fileURLWithPath: "/sbin/badblocks"), [
            "-sv", "-p", passes, devPath
        ])
    }
}
#endif
