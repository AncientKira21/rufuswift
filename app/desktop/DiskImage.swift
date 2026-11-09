import Foundation

struct WriterError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) { errorDescription = message }
}

struct Drive: Codable, CustomStringConvertible, Equatable, Sendable {
    let id: String
    let device: String
    let name: String
    let capacity: Int64
    let blockSize: Int64

    var description: String {
        "\(name) · \(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)) · \(device)"
    }
}

struct DiskImage: Sendable {
    let url: URL
    let size: Int64

    init(_ url: URL) throws {
        let type = url.pathExtension.lowercased()
        guard url.isFileURL, ["img", "dd", "raw", "iso", "dmg", "pkg", "bin", "vhd", "vhdx"].contains(type) else {
            throw WriterError("Choose an uncompressed raw image (.img, .raw, .dd), hybrid ISO (.iso), macOS installer (.dmg, .pkg), or FydeOS image (.bin).")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let count = values.fileSize, count > 0 else {
            throw WriterError("Choose a nonempty image file.")
        }
        if type == "iso" {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let header = [UInt8](try file.read(upToCount: 512) ?? Data())
            let isHybrid = header.count == 512 && header[510] == 0x55 && header[511] == 0xaa &&
                           stride(from: 450, to: 511, by: 16).contains(where: { header[$0] != 0 })
            if !isHybrid {
                try? file.seek(toOffset: 0x8000)
                let volDesc = [UInt8](try file.read(upToCount: 6) ?? Data())
                let isIso9660 = volDesc.count >= 6 && volDesc[1] == 0x43 && volDesc[2] == 0x44 && volDesc[3] == 0x30 && volDesc[4] == 0x30 && volDesc[5] == 0x31
                if !isIso9660 {
                    throw WriterError("This ISO has no disk partition table or ISO9660 volume descriptor.")
                }
            }
        }
        self.url = url
        self.size = Int64(count)
    }
}

func runCommand(_ path: URL, _ arguments: [String]) throws -> Data {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = path
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let detail = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw WriterError(detail.isEmpty ? "Operation failed (\(process.terminationStatus))." : detail)
    }
    return output
}
