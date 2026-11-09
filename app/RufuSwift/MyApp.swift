import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Navigation & Menu Bar Commands

enum SidebarPage: Hashable {
    case writer, checksums, downloader, about
}

// MARK: - macOS 26+ SF Symbols Menu Bar Decorator

@MainActor
final class MenuBarSymbolDecorator {
    static let shared = MenuBarSymbolDecorator()

    private var didSetup = false

    func setupIfNeeded() {
        guard !didSetup else { return }
        didSetup = true

        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        guard osVer.majorVersion >= 26 else { return }

        // Initial application
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.applySymbols()
        }

        // Whenever any menu begins tracking or opens in the macOS menu bar
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MenuBarSymbolDecorator.shared.applySymbols()
            }
        }
    }

    func applySymbols() {
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        guard osVer.majorVersion >= 26 else { return }

        let symbolMap: [String: String] = [
            "Open Disk Image…": "opticaldisc",
            "Download Operating System…": "arrow.down.circle",
            "Save USB Drive to Image (Backup)…": "externaldrive.badge.plus",
            "Calculate Image Checksums…": "number",
            "Drive Creator": "externaldrive.fill.badge.plus",
            "Download Operating Systems": "arrow.down.circle.fill",
            "Checksums Utility": "number",
            "About RufuSwift": "info.circle",
            "Refresh Drive List": "arrow.clockwise",
            "Check Target Drive for Bad Blocks…": "waveform.path.ecg",
            "Toggle Advanced Drive Options": "slider.horizontal.3",
            "Help Me Choose Edition…": "questionmark.circle",
            "Browse All FydeOS Versions": "list.bullet",
            "FydeOS for PC Official Website": "safari",
            "Rufus Documentation & FAQ": "book",
            "Rufus GitHub Repository": "link"
        ]

        func populate(menu: NSMenu) {
            for item in menu.items {
                if let sub = item.submenu {
                    populate(menu: sub)
                }
                if let symbolName = symbolMap[item.title] {
                    if item.image == nil {
                        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.title)
                        img?.isTemplate = true
                        item.image = img
                    }
                }
            }
        }

        if let mainMenu = NSApp.mainMenu {
            populate(menu: mainMenu)
        }
    }
}

extension Notification.Name {
    static let rufusNavigatePage = Notification.Name("rufusNavigatePage")
    static let rufusOpenImage = Notification.Name("rufusOpenImage")
    static let rufusRefreshDrives = Notification.Name("rufusRefreshDrives")
    static let rufusBackupDrive = Notification.Name("rufusBackupDrive")
    static let rufusCheckBadBlocks = Notification.Name("rufusCheckBadBlocks")
    static let rufusCalculateChecksums = Notification.Name("rufusCalculateChecksums")
    static let rufusShowFydeOSHelp = Notification.Name("rufusShowFydeOSHelp")
    static let rufusFilterFydeOS = Notification.Name("rufusFilterFydeOS")
    static let rufusToggleAdvancedOptions = Notification.Name("rufusToggleAdvancedOptions")
}

struct MyApp: App {
    init() {
        MenuBarSymbolDecorator.shared.setupIfNeeded()
    }

    var body: some Scene {
        Window("RufuSwift", id: "writer") {
            ContentView()
                .frame(minWidth: 740, minHeight: 380)
        }
        .defaultSize(width: 740, height: 380)
        .windowResizability(.contentMinSize)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.writer)
                    NotificationCenter.default.post(name: .rufusOpenImage, object: nil)
                } label: {
                    Label("Open Disk Image…", systemImage: "opticaldisc")
                }
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.downloader)
                } label: {
                    Label("Download Operating System…", systemImage: "arrow.down.circle")
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.writer)
                    NotificationCenter.default.post(name: .rufusBackupDrive, object: nil)
                } label: {
                    Label("Save USB Drive to Image (Backup)…", systemImage: "externaldrive.badge.plus")
                }
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.checksums)
                    NotificationCenter.default.post(name: .rufusCalculateChecksums, object: nil)
                } label: {
                    Label("Calculate Image Checksums…", systemImage: "number")
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            // View Menu
            CommandGroup(after: .sidebar) {
                Divider()
                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.writer)
                } label: {
                    Label("Drive Creator", systemImage: "externaldrive.fill.badge.plus")
                }
                .keyboardShortcut("1", modifiers: .command)

                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.downloader)
                } label: {
                    Label("Download Operating Systems", systemImage: "arrow.down.circle.fill")
                }
                .keyboardShortcut("2", modifiers: .command)

                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.checksums)
                } label: {
                    Label("Checksums Utility", systemImage: "number")
                }
                .keyboardShortcut("3", modifiers: .command)

                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.about)
                } label: {
                    Label("About RufuSwift", systemImage: "info.circle")
                }
                .keyboardShortcut("4", modifiers: .command)
            }

            // Drive Menu
            CommandMenu("Drive") {
                Button {
                    NotificationCenter.default.post(name: .rufusRefreshDrives, object: nil)
                } label: {
                    Label("Refresh Drive List", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)

                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.writer)
                    NotificationCenter.default.post(name: .rufusCheckBadBlocks, object: nil)
                } label: {
                    Label("Check Target Drive for Bad Blocks…", systemImage: "waveform.path.ecg")
                }
                .keyboardShortcut("b", modifiers: [.command, .option])

                Divider()

                Button {
                    NotificationCenter.default.post(name: .rufusToggleAdvancedOptions, object: nil)
                } label: {
                    Label("Toggle Advanced Drive Options", systemImage: "slider.horizontal.3")
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
            }

            // FydeOS Menu
            CommandMenu("FydeOS") {
                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.downloader)
                    NotificationCenter.default.post(name: .rufusShowFydeOSHelp, object: nil)
                } label: {
                    Label("Help Me Choose Edition…", systemImage: "questionmark.circle")
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Divider()

                Button {
                    NotificationCenter.default.post(name: .rufusNavigatePage, object: SidebarPage.downloader)
                    NotificationCenter.default.post(name: .rufusFilterFydeOS, object: nil)
                } label: {
                    Label("Browse All FydeOS Versions", systemImage: "list.bullet")
                }

                Divider()

                Button {
                    if let url = URL(string: "https://fydeos.io/download/pc/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("FydeOS for PC Official Website", systemImage: "safari")
                }
            }

            // Help Menu
            CommandGroup(replacing: .help) {
                Button {
                    if let url = URL(string: "https://github.com/pbatard/rufus/wiki/FAQ") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Rufus Documentation & FAQ", systemImage: "book")
                }

                Button {
                    if let url = URL(string: "https://github.com/pbatard/rufus") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Rufus GitHub Repository", systemImage: "link")
                }
            }
        }
    }
}

// MARK: - AppKit Text Field that Clears Focus on Enter & Avoids Auto-Selection


typealias RufusApp = MyApp
