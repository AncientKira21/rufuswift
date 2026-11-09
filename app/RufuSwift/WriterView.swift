import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WriterView: View {
    var onNavigateToDownload: () -> Void
    @Binding var pendingImageUrl: URL?
    @Binding var pendingAutoFlash: Bool

    @State private var drives: [USBDrive] = []
    @State private var selectedID: UInt64?
    @State private var config = RufusWorkflowConfig()

    @State private var selectedImageUrl: URL?
    @State private var preparedImage: PreparedImage?
    @State private var preparing = false
    @State private var autoDeleteUrl: URL? = nil

    @State private var busy = false
    @State private var status = "Choose a boot selection and connect a target USB drive."
    @State private var showingConfirm = false
    @State private var showingWUEModal = false
    @State private var showingAdvanced = false
    @State private var isWindowsIsoSelected = false
    @State private var isLinuxIsoSelected = false

    private var target: USBDrive? { drives.first { $0.id == selectedID } }

    private var readyToExecute: Bool {
        guard let target else { return false }
        switch config.bootSelection {
        case .nonBootable, .freeDOS:
            return !busy && !preparing
        case .diskOrIso:
            guard let image = preparedImage else { return false }
            return !busy && !preparing && image.size <= target.capacity
        case .syslinux:
            return !busy && !preparing
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RufuSwift").font(.largeTitle.bold())
                        Text("The Reliable USB Formatting Utility").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: startBackup) {
                        Label("Backup Drive", systemImage: "arrow.down.doc")
                    }
                    .disabled(target == nil || busy)
                    .help("Dump the selected USB drive to a raw disk image file")

                    Button(action: runBadBlocksCheck) {
                        Label("Bad Blocks", systemImage: "waveform.path.ecg")
                    }
                    .disabled(target == nil || busy)
                    .help("Run bad blocks surface test on the target drive")
                }

                // Device Section
                GroupBox("Device") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Device", selection: $selectedID) {
                                Text(drives.isEmpty ? "No eligible drives found" : "Select a drive")
                                    .tag(nil as UInt64?)
                                ForEach(drives) { drive in
                                    Text("\(drive.name) · \(bytes(drive.capacity)) (\(drive.bsdName))")
                                        .tag(Optional(drive.id))
                                }
                            }
                            .labelsHidden()
                            Button("Refresh", action: refreshDrives)
                                .disabled(busy)
                        }

                        Toggle("List USB Hard Drives (fixed drives)", isOn: $config.listUsbHardDrives)
                            .toggleStyle(.switch)
                            .font(.caption)
                            .onChange(of: config.listUsbHardDrives) { _ in refreshDrives() }
                    }
                    .padding(4)
                }

                // Boot Selection Section
                GroupBox("Boot selection") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker("Boot selection", selection: $config.bootSelection) {
                                ForEach(BootSelection.allCases) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .labelsHidden()

                            if config.bootSelection == .diskOrIso {
                                Button("SELECT…", action: chooseImage)
                                    .disabled(busy || preparing)
                                Button("DOWNLOAD", action: onNavigateToDownload)
                                    .disabled(busy)
                            }
                        }

                        if config.bootSelection == .diskOrIso {
                            HStack {
                                Text(preparedImage?.name ?? "No image selected")
                                    .font(.subheadline)
                                    .foregroundStyle(preparedImage != nil ? .primary : .secondary)
                                    .lineLimit(1)
                                Spacer()
                                if let size = preparedImage?.size {
                                    Text(bytes(size)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                // Image Option (when ISO selected)
                if config.bootSelection == .diskOrIso && isWindowsIsoSelected {
                    GroupBox("Image option") {
                        Picker("Image option", selection: $config.imageOption) {
                            Text(ImageOption.standardWindows.rawValue).tag(ImageOption.standardWindows)
                            Text(ImageOption.windowsToGo.rawValue).tag(ImageOption.windowsToGo)
                        }
                        .labelsHidden()
                        .padding(4)
                    }
                }

                // Linux Persistence Size
                if config.bootSelection == .diskOrIso && isLinuxIsoSelected, let target {
                    GroupBox("Persistent partition size") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(config.persistenceSizeMB) MB")
                                Spacer()
                                Text("Max: \(target.capacity / (1024 * 1024)) MB")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(config.persistenceSizeMB) },
                                set: { config.persistenceSizeMB = Int64($0) }
                            ), in: 0...Double(max(0, (target.capacity - (preparedImage?.size ?? 0)) / (1024 * 1024))))
                        }
                        .padding(4)
                    }
                }

                // Partition Scheme & Target System
                HStack(spacing: 12) {
                    GroupBox("Partition scheme") {
                        Picker("Partition scheme", selection: $config.partitionScheme) {
                            ForEach(PartitionScheme.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .padding(4)
                    }
                    GroupBox("Target system") {
                        Picker("Target system", selection: $config.targetSystem) {
                            ForEach(TargetSystem.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .padding(4)
                    }
                }

                // Format Options
                GroupBox("Format Options") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Volume label:")
                                .frame(width: 90, alignment: .leading)
                            FocusClearingTextField(placeholder: "Volume label", text: $config.volumeLabel)
                                .frame(height: 22)
                        }

                        HStack {
                            Text("File system:")
                                .frame(width: 90, alignment: .leading)
                            Picker("File system", selection: $config.fileSystem) {
                                ForEach(TargetFileSystem.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                        }

                        HStack {
                            Text("Cluster size:")
                                .frame(width: 90, alignment: .leading)
                            Picker("Cluster size", selection: $config.clusterSize) {
                                ForEach(AllocationUnitSize.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }

                        Divider()

                        HStack {
                            Toggle("Quick format", isOn: $config.quickFormat)
                                .toggleStyle(.switch)
                            Spacer()
                            Toggle("Extended label & icon", isOn: $config.createExtendedLabel)
                                .toggleStyle(.switch)
                        }

                        HStack {
                            Toggle("Check device for bad blocks", isOn: $config.checkBadBlocks)
                                .toggleStyle(.switch)
                            if config.checkBadBlocks {
                                Picker("Passes", selection: $config.badBlockPasses) {
                                    Text("1 Pass").tag(1)
                                    Text("2 Passes").tag(2)
                                }
                                .frame(width: 110)
                            }
                        }

                        DisclosureGroup(isExpanded: $showingAdvanced) {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Add fixes for old BIOSes (extra partition, align, etc.)", isOn: $config.oldBiosFixes)
                                    .toggleStyle(.switch)
                                Toggle("Use Rufus MBR with BIOS ID", isOn: $config.useRufusMbr)
                                    .toggleStyle(.switch)
                            }
                            .font(.caption)
                            .padding(.top, 6)
                        } label: {
                            HStack {
                                Text("Advanced drive properties")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingAdvanced.toggle()
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                // Status Bar & Start Button
                HStack(alignment: .center, spacing: 12) {
                    if busy || preparing {
                        ProgressView().controlSize(.small)
                    }
                    Text(status)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("START") {
                        if config.bootSelection == .diskOrIso && isWindowsIsoSelected {
                            showingWUEModal = true
                        } else {
                            showingConfirm = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!readyToExecute)
                }
                .padding(.top, 4)

                // Bottom padding buffer so 100% of the START button shows comfortably without rubberband pull-back
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
        .frame(width: 570)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .task { refreshDrives() }
        .onChange(of: pendingImageUrl) { url in
            if let url {
                let auto = pendingAutoFlash
                pendingAutoFlash = false
                if auto {
                    autoDeleteUrl = url
                }
                selectImage(url: url) {
                    if auto {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if target != nil || !drives.isEmpty {
                                if selectedID == nil { selectedID = drives.first?.id }
                                executeWorkflow()
                            } else {
                                status = "Image ready: \(url.lastPathComponent). Connect an external USB drive to begin flashing automatically."
                            }
                        }
                    }
                }
                pendingImageUrl = nil
            }
        }
        .sheet(isPresented: $showingWUEModal) {
            WindowsUserExperienceSheet(wue: $config.wue, onProceed: {
                showingWUEModal = false
                showingConfirm = true
            }, onCancel: {
                showingWUEModal = false
            })
        }
        .alert("WARNING: ALL DATA ON DRIVE WILL BE DESTROYED", isPresented: $showingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("OK", role: .destructive, action: executeWorkflow)
        } message: {
            if let target {
                Text("To write to \(target.name) (\(target.bsdName), \(bytes(target.capacity))), all partitions on this drive will be deleted and erased.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rufusOpenImage)) { _ in
            chooseImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rufusRefreshDrives)) { _ in
            refreshDrives()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rufusBackupDrive)) { _ in
            startBackup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rufusCheckBadBlocks)) { _ in
            runBadBlocksCheck()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rufusToggleAdvancedOptions)) { _ in
            showingAdvanced.toggle()
        }
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private func refreshDrives() {
        guard !busy else { return }
        let includeHard = config.listUsbHardDrives
        Task {
            do {
                drives = try await Task.detached(priority: .userInitiated) {
                    try DiskWriter.drives(includeHardDrives: includeHard)
                }.value
                if target == nil { selectedID = drives.first?.id }
                if autoDeleteUrl != nil, let drive = drives.first, !busy, preparedImage != nil {
                    if selectedID == nil { selectedID = drive.id }
                    executeWorkflow()
                }
            } catch {
                drives = []
                status = error.localizedDescription
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.message = "Select a bootable ISO, raw image (.img, .dd, .raw), compressed image (.gz, .xz), macOS installer (.dmg, .pkg), or FydeOS image."
        panel.allowedContentTypes = ["iso", "img", "dd", "raw", "gz", "xz", "dmg", "pkg", "vhd"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectImage(url: url)
    }

    private func selectImage(url: URL, completion: (@MainActor () -> Void)? = nil) {
        selectedImageUrl = url
        preparing = true
        preparedImage = nil
        status = "Inspecting image…"

        let isWin = DiskWriter.isWindowsIso(url)
        let isLin = DiskWriter.isLinuxIso(url)
        let filename = url.lastPathComponent.lowercased()
        let isArm = filename.contains("arm") || filename.contains("aarch64")
        let isMac = filename.contains("macos") || filename.contains("installassistant") || filename.hasSuffix(".pkg") || filename.hasSuffix(".dmg")
        let isFyde = filename.contains("fyde")

        isWindowsIsoSelected = isWin
        isLinuxIsoSelected = isLin

        if isWin {
            config.imageOption = .standardWindows
            config.partitionScheme = .gpt
            config.targetSystem = .uefiNonCsm
            config.fileSystem = .exfat
            config.volumeLabel = isArm ? "WIN_ARM" : "WIN_INSTALL"
            config.wue.architecture = isArm ? "arm64" : "amd64"
        } else if isMac {
            config.imageOption = .macOSInstaller
            config.partitionScheme = .gpt
            config.targetSystem = .uefiNonCsm
            config.fileSystem = .hfsPlus
            config.volumeLabel = "Install macOS"
        } else if isFyde {
            config.imageOption = .rawImage
            config.partitionScheme = .gpt
            config.targetSystem = .uefiNonCsm
            config.fileSystem = .fat32
            config.volumeLabel = "FYDEOS"
        } else if isLin {
            config.imageOption = .rawImage
            config.fileSystem = .fat32
            config.volumeLabel = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: ".img", with: "").uppercased()
        }

        Task {
            defer {
                preparing = false
                completion?()
            }
            do {
                preparedImage = try await Task.detached(priority: .userInitiated) {
                    try PreparedImage(url, inspect: DiskWriter.inspectImage)
                }.value
                if isArm && isWin {
                    status = "Ready to create Windows on ARM installation media."
                } else if isFyde {
                    status = "Ready to flash FydeOS disk image."
                } else if isMac {
                    status = "Ready to create macOS bootable media."
                } else {
                    status = "Ready to create media."
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func executeWorkflow() {
        guard let target else { return }
        busy = true
        status = "Performing operation… Please authorize if prompted."
        let currentConfig = config
        let delUrl = autoDeleteUrl

        Task {
            let result: String
            do {
                switch currentConfig.bootSelection {
                case .nonBootable:
                    result = try await Task.detached(priority: .userInitiated) {
                        try DiskWriter.formatWithAuthorization(target: target, config: currentConfig)
                    }.value

                case .freeDOS:
                    result = try await Task.detached(priority: .userInitiated) {
                        try DiskWriter.createFreeDosWithAuthorization(target: target, config: currentConfig)
                    }.value

                case .diskOrIso:
                    guard let image = preparedImage else { throw WriterError("No image prepared") }
                    if isWindowsIsoSelected {
                        result = try await Task.detached(priority: .userInitiated) {
                            try DiskWriter.createWindowsInstallerWithAuthorization(iso: image.url, target: target, config: currentConfig)
                        }.value
                    } else if image.url.pathExtension.lowercased() == "pkg" {
                        result = try await Task.detached(priority: .userInitiated) {
                            try DiskWriter.createMacOSInstallerWithAuthorization(pkg: image.url, target: target, config: currentConfig)
                        }.value
                    } else {
                        // Raw image, DMG, or hybrid ISO (Linux, FydeOS, macOS DMG images)
                        result = try await Task.detached(priority: .userInitiated) {
                            try DiskWriter.writeWithAuthorization(image: image.url, size: image.size, target: target)
                        }.value
                    }

                case .syslinux:
                    result = try await Task.detached(priority: .userInitiated) {
                        try DiskWriter.formatWithAuthorization(target: target, config: currentConfig)
                    }.value
                }

                if let del = delUrl {
                    try? FileManager.default.removeItem(at: del)
                    await MainActor.run {
                        self.autoDeleteUrl = nil
                        self.preparedImage = nil
                        self.selectedImageUrl = nil
                    }
                }
            } catch {
                result = error.localizedDescription
            }

            status = (delUrl != nil && !result.lowercased().contains("error") && !result.lowercased().contains("failed"))
                ? "Flashing completed successfully! Downloaded installer cleaned up. USB drive is ready."
                : result
            busy = false
            refreshDrives()
        }
    }

    private func startBackup() {
        guard let target else { return }
        let savePanel = NSSavePanel()
        savePanel.title = "Save Drive Image"
        savePanel.nameFieldStringValue = "\(target.name.replacingOccurrences(of: " ", with: "_"))_backup.img"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "img")!]
        guard savePanel.runModal() == .OK, let dest = savePanel.url else { return }

        busy = true
        status = "Dumping drive to \(dest.lastPathComponent)…"
        Task {
            defer { busy = false }
            do {
                let msg = try await Task.detached(priority: .userInitiated) {
                    try DiskWriter.backupDriveWithAuthorization(target: target, destination: dest)
                }.value
                status = msg
            } catch {
                status = error.localizedDescription
            }
            refreshDrives()
        }
    }

    private func runBadBlocksCheck() {
        guard let target else { return }
        busy = true
        status = "Running surface bad blocks check on \(target.bsdName)…"
        let passes = config.badBlockPasses
        Task {
            defer { busy = false }
            do {
                let msg = try await Task.detached(priority: .userInitiated) {
                    try DiskWriter.checkBadBlocksWithAuthorization(target: target, passes: passes)
                }.value
                status = msg
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

// MARK: - Windows User Experience (WUE) Modal Sheet

struct WindowsUserExperienceSheet: View {
    @Binding var wue: WindowsUserExperience
    var onProceed: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Windows User Experience").font(.title2.bold())
                Spacer()
                Text(wue.architecture.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(.purple)
                    .cornerRadius(4)
            }
            Text("Customize your Windows installation to bypass hardware checks and streamline setup:").foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Remove requirement for 4GB+ RAM, Secure Boot and TPM 2.0", isOn: $wue.bypassTPMAndSecureBoot)
                    .toggleStyle(.switch)
                Toggle("Remove requirement for an online Microsoft account", isOn: $wue.bypassOnlineAccount)
                    .toggleStyle(.switch)
                Toggle("Create a local account with username:", isOn: $wue.createLocalAccount)
                    .toggleStyle(.switch)
                if wue.createLocalAccount {
                    TextField("Username", text: $wue.localUsername)
                        .textFieldStyle(.roundedBorder)
                        .padding(.leading, 24)
                }
                Toggle("Set regional options to the same values as this user's", isOn: $wue.setRegionalOptions)
                    .toggleStyle(.switch)
                Toggle("Disable data collection (Skip privacy questions)", isOn: $wue.disableDataCollection)
                    .toggleStyle(.switch)
                Toggle("Disable BitLocker automatic device encryption", isOn: $wue.disableBitLocker)
                    .toggleStyle(.switch)
            }
            .padding(.vertical, 6)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("OK", action: onProceed)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
