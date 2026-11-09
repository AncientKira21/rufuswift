import Foundation
#if os(macOS)
import CryptoKit
#endif

enum ImageChecksums {
    static func calculate(_ url: URL) throws -> String {
        #if os(macOS)
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var md5 = Insecure.MD5()
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()
        var sha512 = SHA512()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            md5.update(data: data)
            sha1.update(data: data)
            sha256.update(data: data)
            sha512.update(data: data)
        }
        return [
            "MD5: " + hex(md5.finalize()), "SHA-1: " + hex(sha1.finalize()),
            "SHA-256: " + hex(sha256.finalize()), "SHA-512: " + hex(sha512.finalize())
        ].joined(separator: "\n")
        #elseif os(Windows)
        return try PlatformWriter.checksums(url)
        #else
        let names = ["MD5", "SHA-1", "SHA-256", "SHA-512"]
        let tools = ["md5sum", "sha1sum", "sha256sum", "sha512sum"]
        return try zip(names, tools).map { name, tool in
            let result = try runCommand(URL(fileURLWithPath: "/usr/bin/" + tool),
                                        ["--zero", "--", url.path])
            let hash = String(decoding: result.prefix { $0 != 32 }, as: UTF8.self)
            return "\(name): \(hash)"
        }.joined(separator: "\n")
        #endif
    }

    #if os(macOS)
    private static func hex(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
    #endif
}
