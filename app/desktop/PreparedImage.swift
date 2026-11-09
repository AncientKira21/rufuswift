import Foundation

final class PreparedImage: Sendable {
    let url: URL
    let name: String
    let size: Int64
    private let directory: URL?

    init(_ original: URL, inspect: (URL) throws -> Int64) throws {
        name = original.lastPathComponent
        let ext = original.pathExtension.lowercased()
        guard ext == "gz" || ext == "xz" else {
            url = original
            size = try inspect(original)
            directory = nil
            return
        }

        let basename = original.deletingPathExtension().lastPathComponent
        let subExt = URL(fileURLWithPath: basename).pathExtension.lowercased()
        let targetFilename = subExt.isEmpty ? (basename + ".img") : basename

        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("rufus-" + UUID().uuidString)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        let expanded = folder.appendingPathComponent(targetFilename)
        do {
            try Self.expand(original, to: expanded, ext: ext)
            size = try inspect(expanded)
            url = expanded
            directory = folder
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }

    deinit {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private static func expand(_ source: URL, to destination: URL, ext: String) throws {
        #if os(Windows)
        try PlatformWriter.expandGzip(source, to: destination)
        #else
        let tool = Process()
        let errors = Pipe()

        if ext == "xz" {
            let xzCandidates = ["/usr/bin/xz", "/opt/homebrew/bin/xz", "/usr/local/bin/xz"]
            if let xzPath = xzCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                                     attributes: [.posixPermissions: 0o600]) else {
                    throw WriterError("Could not create temporary storage for the expanded image.")
                }
                let file = try FileHandle(forWritingTo: destination)
                defer { try? file.close() }
                tool.executableURL = URL(fileURLWithPath: xzPath)
                tool.arguments = ["-dc", "--", source.path]
                tool.standardOutput = file
                tool.standardError = errors
            } else {
                // Stream decompress with built-in python3 lzma module
                let pyPath = "/usr/bin/python3"
                tool.executableURL = URL(fileURLWithPath: pyPath)
                tool.arguments = [
                    "-c",
                    "import lzma, shutil, sys; shutil.copyfileobj(lzma.open(sys.argv[1], 'rb'), open(sys.argv[2], 'wb'))",
                    source.path,
                    destination.path
                ]
                tool.standardError = errors
            }
        } else {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw WriterError("Could not create temporary storage for the expanded image.")
            }
            let file = try FileHandle(forWritingTo: destination)
            defer { try? file.close() }
            tool.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            tool.arguments = ["-dc", "--", source.path]
            tool.standardOutput = file
            tool.standardError = errors
        }

        try tool.run()
        let details = errors.fileHandleForReading.readDataToEndOfFile()
        tool.waitUntilExit()
        guard tool.terminationStatus == 0 else {
            let error = String(decoding: details, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw WriterError(error.isEmpty ? "Could not expand the compressed image." : error)
        }
        #endif
    }
}
