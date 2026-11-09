import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChecksumsView: View {
    @State private var busy = false
    @State private var filename: String?
    @State private var result = "Choose a file to calculate its MD5, SHA-1, SHA-256, and SHA-512 checksums."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Image Checksums").font(.title.bold())
            Text("Verify image integrity with cryptographic digests.").foregroundStyle(.secondary)
            HStack {
                Button("Choose File…", action: chooseFile).disabled(busy)
                if let filename {
                    Text(filename).font(.headline).lineLimit(1)
                }
            }
            ScrollView {
                Text(result)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
            .cornerRadius(6)

            if !busy && filename != nil {
                Button("Copy Checksums to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 570, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: .rufusCalculateChecksums)) { _ in
            chooseFile()
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        filename = url.lastPathComponent
        busy = true
        result = "Calculating checksums…"
        Task {
            defer { busy = false }
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try ImageChecksums.calculate(url)
                }.value
            } catch {
                result = error.localizedDescription
            }
        }
    }
}
