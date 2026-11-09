import DefaultBackend
import Foundation
import SwiftCrossUI
#if canImport(AppKit)
import AppKit
#endif

#if os(Linux)
if let cmd = CommandLine.arguments.dropFirst().first {
    do {
        switch cmd {
        case "--write-image":
            try PlatformWriter.writePrivileged(Array(CommandLine.arguments.dropFirst(2)))
            exit(0)
        case "--format-disk":
            try PlatformWriter.formatPrivileged(Array(CommandLine.arguments.dropFirst(2)))
            exit(0)
        case "--create-windows-installer":
            try PlatformWriter.windowsInstallerPrivileged(Array(CommandLine.arguments.dropFirst(2)))
            exit(0)
        case "--backup-drive":
            try PlatformWriter.backupPrivileged(Array(CommandLine.arguments.dropFirst(2)))
            exit(0)
        case "--check-bad-blocks":
            try PlatformWriter.checkBadBlocksPrivileged(Array(CommandLine.arguments.dropFirst(2)))
            exit(0)
        default:
            break
        }
    } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(1)
    }
}
#endif

MainActor.assumeIsolated { RufusApp.main() }

struct RufusApp: App {
    var body: some Scene {
        WindowGroup("RufuSwift") {
            WriterView()
        }
        .defaultSize(width: 720, height: 380)
    }
}

struct WriterView: View {
    @Environment(\.chooseFile) private var openFile
    @State private var page = "Drive Creator"
    @State private var image: PreparedImage?
    @State private var drives: [Drive] = []
    @State private var selectedDrive: Drive?
    @State private var checksumResult = "Choose a file to calculate its checksums."
    @State private var confirming = false
    @State private var busy = false
    @State private var status = "Choose a boot selection and refresh the USB drive list."
    @State private var pendingAutoFlashUrl: URL? = nil
    @State private var helpMeChooseResult = ""

    // Rufus configuration
    @State private var config = RufusWorkflowConfig()
    @State private var isWindowsIso = false

    private var target: Drive? { drives.first { $0.id == selectedDrive?.id } }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Button("Drive Creator") { page = "Drive Creator" }
                Button("Checksums") { page = "Checksums" }
                Button("Download ISO") { page = "Download ISO" }
                Button("About RufuSwift") { page = "About RufuSwift" }
                Spacer()
            }
            .padding()
        } detail: {
            if page == "Drive Creator" {
                writer
            } else if page == "Checksums" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Checksums")
                    Button("Choose File…") { chooseChecksumFile() }.disabled(busy || confirming)
                    ScrollView { Text(checksumResult) }
                    Spacer()
                }
                .padding()
            } else if page == "Download ISO" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Official Windows, macOS, Linux & FydeOS Downloads")

                    if !helpMeChooseResult.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(helpMeChooseResult)
                            Button("Dismiss Advisor") { helpMeChooseResult = "" }
                        }
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(OSDownloadItem.catalog) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(item.name) (\(item.architecture)) - v\(item.version)")
                                        if item.category == .fydeOS && !item.editions.isEmpty {
                                            Button("Confused? Help me choose →") {
                                                let host = FydeOSHardwareAdvisor.detectHost()
                                                helpMeChooseResult = "FydeOS for PC — Which edition best describes your PC?\n• Intel Slim (2015-2019 · 6th-9th Gen Non-Core): Celeron & Pentium\n• Intel Modern (2015+ · 6th-14th Gen): Core with HD/UHD/Iris Xe\n• AMD Graphics (2011+ · Intel & AMD CPU): AMD Graphics/APUs\n• Intel Legacy [No longer supported] (2011-2014 · 3rd-5th Gen): 3rd-5th Gen Core\n\nDetected on this machine (\(host.model)): RECOMMENDED -> \(host.recommendation.headline)!"
                                            }
                                        }
                                    }

                                    if !item.editions.isEmpty {
                                        Text("Choose Hardware Edition:")
                                        ForEach(item.editions) { edition in
                                            HStack {
                                                Text("• \(edition.name) (\(edition.badge))")
                                                Button("Flash…") {
                                                    startDesktopDownloadAndFlash(item: item.itemForEdition(edition))
                                                }
                                                Button("Download") {
                                                    openBrowserUrl(edition.directUrl ?? edition.downloadUrl)
                                                }
                                            }
                                        }
                                    } else {
                                        HStack {
                                            Button("Download") {
                                                openBrowserUrl(item.directUrl ?? item.downloadUrl)
                                            }
                                            Button("Flash…") {
                                                startDesktopDownloadAndFlash(item: item)
                                            }
                                        }
                                    }

                                    Text(item.description)
                                    Text(item.directUrl?.absoluteString ?? item.downloadUrl.absoluteString)
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("RufuSwift")
                    Text("The Reliable Multi-Platform USB Formatting Utility")
                    Text("Lead Developer: Ancient Kira (Swift port & multi-platform architecture)")
                    Text("Original Rufus Creator: Pete Batard / Akeo Consulting (https://rufus.ie)")
                    Text("Upstream Credits: FreeDOS project, e2fsprogs (Theodore Ts'o), wimlib (Eric Biggers), Syslinux (H. Peter Anvin), GRUB (FSF), FydeOS/ChromiumOS, and open-source Linux distributions.")
                    Text("Features: Drive formatting (FAT32, NTFS, exFAT, ext4, HFS+), Windows installer creation (x64 and ARM64) with TPM/SecureBoot bypass, macOS installers through Golden Gate, FydeOS v19-v23, FreeDOS, persistence, drive backups, and bad-block testing.")
                    Spacer()
                }
                .padding()
            }
        }
    }

    private var writer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RufuSwift - Drive Creator")

            // Drive selection
            HStack {
                Text("Device:")
                Button("Refresh") { refresh() }.disabled(busy || confirming)
            }
            Picker(of: drives, selection: $selectedDrive)
                .disabled(busy || confirming || drives.isEmpty)

            // Boot Selection
            HStack {
                Text("Boot selection:")
                Button(config.bootSelection.rawValue) {
                    cycleBootSelection()
                }
                if config.bootSelection == .diskOrIso {
                    Button("Choose Image…") { chooseImage() }.disabled(busy || confirming)
                }
            }
            if config.bootSelection == .diskOrIso {
                Text(image.map { "\($0.name) · \(bytes($0.size))" } ?? "No image selected")
            }

            // Partition Scheme & Target System
            HStack {
                Text("Partition scheme: \(config.partitionScheme.rawValue)")
                Button("Switch Scheme") {
                    config.partitionScheme = (config.partitionScheme == .gpt) ? .mbr : .gpt
                }
                Spacer()
                Text("Target system: \(config.targetSystem.rawValue)")
            }

            // Format options
            HStack {
                Text("File system: \(config.fileSystem.shortName)")
                Button("Switch File System") {
                    cycleFileSystem()
                }
            }
            HStack {
                Text("Volume label: \(config.volumeLabel)")
                Button("Quick Format: \(config.quickFormat ? "ON" : "OFF")") {
                    config.quickFormat.toggle()
                }
            }

            if isWindowsIso {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Windows User Experience Tweaks (Enabled):")
                    Text("• Bypass TPM 2.0 & Secure Boot checks: \(config.wue.bypassTPMAndSecureBoot ? "YES" : "NO")")
                    Text("• Bypass Online Account (MSA): \(config.wue.bypassOnlineAccount ? "YES" : "NO")")
                    Text("• Disable BitLocker automatic encryption: \(config.wue.disableBitLocker ? "YES" : "NO")")
                    Text("• Disable Telemetry data collection: \(config.wue.disableDataCollection ? "YES" : "NO")")
                }
            }

            // Execution / Actions
            if confirming, let target {
                Text("WARNING: Erase \(target.name)? All data on the drive will be destroyed!")
                HStack {
                    Button("Cancel") { confirming = false }
                    Button("CONFIRM AND START") { executeWorkflow(to: target) }
                }
            } else {
                HStack(spacing: 12) {
                    Button("START") { confirming = true }
                        .disabled(busy || target == nil || (config.bootSelection == .diskOrIso && image == nil))

                    Button("Backup Drive") { backupDrive() }
                        .disabled(busy || target == nil)

                    Button("Check Bad Blocks") { checkBadBlocks() }
                        .disabled(busy || target == nil)
                }
            }

            Text(status)
            Spacer()
        }
        .padding()
    }

    private func cycleBootSelection() {
        switch config.bootSelection {
        case .diskOrIso: config.bootSelection = .nonBootable
        case .nonBootable: config.bootSelection = .freeDOS
        case .freeDOS: config.bootSelection = .diskOrIso
        case .syslinux: config.bootSelection = .diskOrIso
        }
    }

    private func cycleFileSystem() {
        switch config.fileSystem {
        case .fat32: config.fileSystem = .exfat
        case .exfat: config.fileSystem = .ntfs
        case .ntfs: config.fileSystem = .ext4
        case .ext4: config.fileSystem = .hfsPlus
        case .hfsPlus: config.fileSystem = .fat32
        }
    }

    private func chooseChecksumFile() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard let url = await openFile(title: "Choose a file to checksum") else { return }
            checksumResult = "Calculating…"
            do {
                let hashes = try await Task.detached { try ImageChecksums.calculate(url) }.value
                checksumResult = url.lastPathComponent + "\n" + hashes
            } catch {
                checksumResult = error.localizedDescription
            }
        }
    }

    private func prepareImage(url: URL) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                status = "Preparing image…"
                image = try await Task.detached {
                    try PreparedImage(url) { try DiskImage($0).size }
                }.value

                let lower = url.lastPathComponent.lowercased()
                isWindowsIso = lower.contains("win") || lower.contains("windows")
                if isWindowsIso {
                    config.volumeLabel = "WIN_INSTALL"
                    config.fileSystem = .exfat
                    config.partitionScheme = .gpt
                } else if lower.contains("fyde") {
                    config.volumeLabel = "FYDEOS"
                    config.fileSystem = .fat32
                    config.partitionScheme = .gpt
                } else if lower.contains("macos") || lower.hasSuffix(".dmg") || lower.hasSuffix(".pkg") {
                    config.volumeLabel = "Install macOS"
                    config.fileSystem = .hfsPlus
                    config.partitionScheme = .gpt
                }
                status = "Image ready: \(url.lastPathComponent). Select an external USB drive."
            } catch {
                image = nil
                status = error.localizedDescription
            }
        }
    }

    private func chooseImage() {
        Task { @MainActor in
            guard let url = await openFile(title: "Choose a disk image or ISO") else { return }
            prepareImage(url: url)
        }
    }

    private func startDesktopDownloadAndFlash(item: OSDownloadItem) {
        guard let url = item.directUrl else {
            openBrowserUrl(item.downloadUrl)
            return
        }

        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dest = downloadsDir.appendingPathComponent(item.defaultFilename)
        pendingAutoFlashUrl = dest

        if FileManager.default.fileExists(atPath: dest.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
           (attrs[.size] as? Int64 ?? 0) > 1024 * 1024 {
            page = "Drive Creator"
            prepareImage(url: dest)
            if let drive = target ?? drives.first {
                if selectedDrive == nil { selectedDrive = drive }
                executeWorkflow(to: drive, autoDeleteUrl: dest)
            } else {
                status = "Image ready: \(item.defaultFilename). Connect and select a USB drive to flash."
            }
            return
        }

        busy = true
        status = "Connecting to download \(item.defaultFilename)…"
        page = "Drive Creator"

        Task {
            do {
                let (tempUrl, _) = try await URLSession.shared.download(from: url)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempUrl, to: dest)
                await MainActor.run {
                    busy = false
                    prepareImage(url: dest)
                    if let drive = target ?? drives.first {
                        if selectedDrive == nil { selectedDrive = drive }
                        status = "Download complete: \(item.defaultFilename). Flashing to \(drive.name)…"
                        executeWorkflow(to: drive, autoDeleteUrl: dest)
                    } else {
                        status = "Downloaded \(item.defaultFilename). Connect an external USB drive to begin flashing automatically."
                    }
                }
            } catch {
                await MainActor.run {
                    busy = false
                    status = "Download error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func refresh() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                drives = try await Task.detached { try PlatformWriter.drives(includeHardDrives: false) }.value
                if target == nil { selectedDrive = drives.first }
                if let pendingUrl = pendingAutoFlashUrl, let drive = target ?? drives.first, image != nil {
                    executeWorkflow(to: drive, autoDeleteUrl: pendingUrl)
                    return
                }
                status = drives.isEmpty ? "No eligible external USB drives found." : "Select the USB drive to use."
            } catch {
                drives = []
                selectedDrive = nil
                status = error.localizedDescription
            }
        }
    }

    private func executeWorkflow(to drive: Drive, autoDeleteUrl: URL? = nil) {
        confirming = false
        busy = true
        status = "Performing operation… Please wait."
        let currentConfig = config
        let currentImage = image
        let isWin = isWindowsIso
        let deleteTarget = autoDeleteUrl ?? pendingAutoFlashUrl

        Task { @MainActor in
            defer { busy = false }
            do {
                try await Task.detached {
                    switch currentConfig.bootSelection {
                    case .nonBootable, .freeDOS, .syslinux:
                        try PlatformWriter.format(drive, config: currentConfig)
                    case .diskOrIso:
                        guard let prep = currentImage else { throw WriterError("No image selected.") }
                        let source = try DiskImage(prep.url)
                        if isWin {
                            try PlatformWriter.createWindowsInstaller(source, to: drive, config: currentConfig)
                        } else {
                            try PlatformWriter.write(source, to: drive)
                        }
                    }
                }.value

                if let deleteTarget {
                    try? FileManager.default.removeItem(at: deleteTarget)
                    if pendingAutoFlashUrl == deleteTarget {
                        pendingAutoFlashUrl = nil
                    }
                    self.image = nil
                    status = "Operation completed successfully! Downloaded installer cleaned up. Drive is ready."
                } else {
                    status = "Operation completed successfully! Drive is ready."
                }
            } catch {
                status = error.localizedDescription
            }
            refresh()
        }
    }

    private func backupDrive() {
        guard let drive = target else { return }
        busy = true
        status = "Dumping drive to disk image…"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dest = home.appendingPathComponent("\(drive.name)_backup.img")
        Task { @MainActor in
            defer { busy = false }
            do {
                try await Task.detached {
                    try PlatformWriter.backup(drive, to: dest)
                }.value
                status = "Drive backed up successfully to \(dest.lastPathComponent)!"
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func checkBadBlocks() {
        guard let drive = target else { return }
        busy = true
        status = "Checking drive for bad blocks…"
        Task { @MainActor in
            defer { busy = false }
            do {
                try await Task.detached {
                    try PlatformWriter.checkBadBlocks(drive, passes: 1)
                }.value
                status = "Bad blocks check complete. No errors detected."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func openBrowserUrl(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif os(Linux)
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/xdg-open"), arguments: [url.absoluteString])
        #elseif os(Windows)
        _ = try? Process.run(URL(fileURLWithPath: "cmd.exe"), arguments: ["/c", "start", "", url.absoluteString])
        #endif
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
