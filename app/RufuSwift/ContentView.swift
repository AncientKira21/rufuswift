import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selection: SidebarPage? = .writer
    @State private var pendingImageUrl: URL?
    @State private var pendingAutoFlash = false

    private var showingWriter: Bool { selection == .writer || selection == nil }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Drive Creator", systemImage: "externaldrive.fill.badge.plus")
                    .tag(SidebarPage.writer)
                Label("Checksums", systemImage: "number")
                    .tag(SidebarPage.checksums)
                Label("Download ISO", systemImage: "arrow.down.circle.fill")
                    .tag(SidebarPage.downloader)
                Label("About RufuSwift", systemImage: "info.circle")
                    .tag(SidebarPage.about)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(170)
        } detail: {
            ZStack(alignment: .topLeading) {
                WriterView(
                    onNavigateToDownload: { selection = .downloader },
                    pendingImageUrl: $pendingImageUrl,
                    pendingAutoFlash: $pendingAutoFlash
                )
                .opacity(showingWriter ? 1 : 0)
                .disabled(!showingWriter)
                .accessibilityHidden(!showingWriter)

                ChecksumsView()
                    .opacity(selection == .checksums ? 1 : 0)
                    .disabled(selection != .checksums)
                    .accessibilityHidden(selection != .checksums)

                DownloaderView(onSelectImageForFlash: { url, autoFlash in
                    pendingImageUrl = url
                    pendingAutoFlash = autoFlash
                    selection = .writer
                })
                .opacity(selection == .downloader ? 1 : 0)
                .disabled(selection != .downloader)
                .accessibilityHidden(selection != .downloader)

                if selection == .about {
                    AboutView()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rufusNavigatePage)) { notif in
            if let targetPage = notif.object as? SidebarPage {
                selection = targetPage
            }
        }
        .onAppear {
            MenuBarSymbolDecorator.shared.setupIfNeeded()
            DispatchQueue.main.async {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "writer" }) ?? NSApp.keyWindow ?? NSApp.windows.first {
                    window.minSize = NSSize(width: 740, height: 380)
                    window.setContentSize(NSSize(width: 740, height: 380))
                    window.makeFirstResponder(nil)
                }
            }
        }
    }
}

// MARK: - About View with Full Credits


typealias SidebarView = ContentView
