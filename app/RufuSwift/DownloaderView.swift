import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Slidable Category Picker (Slidable by Press & Hold)

enum DownloadCategoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case windows = "Windows"
    case macOS = "macOS"
    case fydeOS = "FydeOS"
    case linux = "Linux"

    var id: String { rawValue }
}

struct SlidableCategoryPicker: View {
    @Binding var selected: DownloadCategoryFilter
    var categories: [DownloadCategoryFilter] = DownloadCategoryFilter.allCases

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    let isSelected = selected == cat
                    Text(cat.rawValue)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                                ? Color.accentColor
                                : Color(nsColor: .controlColor).opacity(0.65)
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                selected = cat
                            }
                        }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let approxWidth: CGFloat = 82.0
                        let x = max(0, gesture.location.x)
                        let index = Int(x / approxWidth)
                        let clamped = min(max(0, index), categories.count - 1)
                        let target = categories[clamped]
                        if selected != target {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                                selected = target
                            }
                        }
                    }
            )
        }
    }
}

// MARK: - In-App Downloader Engine (Direct Download & Auto-Flash)

private final class InAppDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var activeItemId: String? = nil
    @Published var progress: Double = 0.0
    @Published var statusText: String = ""

    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var targetDestination: URL?
    private var onFinished: ((URL) -> Void)?

    func startDownload(item: OSDownloadItem, onCompletion: @escaping (URL) -> Void) {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let destination = downloadsDir.appendingPathComponent(item.defaultFilename)

        if FileManager.default.fileExists(atPath: destination.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
           (attrs[.size] as? Int64 ?? 0) > 5 * 1024 * 1024 {
            // Already downloaded! Preload immediately into Drive Creator
            onCompletion(destination)
            return
        }

        guard let direct = item.directUrl, isEligible(direct) else {
            NSWorkspace.shared.open(item.downloadUrl)
            return
        }
        let downloadSource = direct

        self.activeItemId = item.id
        self.progress = 0.0
        self.statusText = "Connecting…"
        self.targetDestination = destination
        self.onFinished = onCompletion

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.downloadTask(with: downloadSource)
        self.downloadTask = task
        task.resume()
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        activeItemId = nil
        statusText = ""
    }

    func isEligible(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased()
        return path.hasSuffix(".iso") || path.hasSuffix(".pkg") || path.hasSuffix(".dmg") ||
               path.hasSuffix(".img") || path.hasSuffix(".xz") || path.hasSuffix(".gz") ||
               path.hasSuffix(".zip") || path.hasSuffix(".tar.gz")
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            self.progress = pct
            let downloadedStr = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
            let totalStr = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
            self.statusText = "\(downloadedStr) / \(totalStr) (\(Int(pct * 100))%)"
        } else {
            let downloadedStr = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
            self.statusText = "\(downloadedStr) downloaded"
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let dest = targetDestination else { return }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            self.activeItemId = nil
            self.statusText = "Download complete!"
            self.onFinished?(dest)
        } catch {
            self.activeItemId = nil
            self.statusText = "Error saving image: \(error.localizedDescription)"
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let nsErr = error as NSError
            if nsErr.code != NSURLErrorCancelled {
                self.activeItemId = nil
                self.statusText = "Download error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Multi-OS Downloader View (Every Windows, macOS through Golden Gate, FydeOS, Linux)

struct DownloaderView: View {
    var onSelectImageForFlash: ((URL, Bool) -> Void)? = nil
    @StateObject private var downloader = InAppDownloader()
    @State private var selectedFilter: DownloadCategoryFilter = .all
    @State private var searchText = ""
    @State private var showingHelpMeChoose = false
    @State private var selectedHelpItem: OSDownloadItem? = nil

    private var filteredItems: [OSDownloadItem] {
        let base: [OSDownloadItem]
        switch selectedFilter {
        case .all:
            base = OSDownloadItem.catalog
        case .windows:
            base = OSDownloadItem.catalog.filter { $0.category == .windows }
        case .macOS:
            base = OSDownloadItem.catalog.filter { $0.category == .macOS }
        case .fydeOS:
            base = OSDownloadItem.catalog.filter { $0.category == .fydeOS }
        case .linux:
            base = OSDownloadItem.catalog.filter { $0.category == .linux }
        }

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return base
        }
        let query = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(query) ||
            $0.version.lowercased().contains(query) ||
            $0.architecture.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download Operating Systems").font(.title.bold())
                        Text("Direct official downloads for Windows, macOS, FydeOS, and Linux.").foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Slidable Category Pills (Press & hold and slide)
                SlidableCategoryPicker(selected: $selectedFilter)

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search operating systems, versions, or architectures…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                if selectedFilter == .fydeOS {
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FydeOS for PC — Which edition best describes your PC?")
                                .font(.subheadline.bold())
                            Text("Intel Slim, Intel Modern, AMD Graphics, or Intel Legacy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Confused? Help me choose →") {
                            selectedHelpItem = OSDownloadItem.catalog.first { $0.category == .fydeOS }
                            showingHelpMeChoose = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                }

                GroupBox("Available Media (\(filteredItems.count))") {
                    VStack(alignment: .leading, spacing: 10) {
                        if filteredItems.isEmpty {
                            Text("No matching operating systems found.")
                                .foregroundStyle(.secondary)
                                .padding(12)
                        } else {
                            ForEach(filteredItems) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 8) {
                                                Text(item.name).font(.headline)
                                                Text("v\(item.version)")
                                                    .font(.caption.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.12))
                                                    .cornerRadius(4)
                                                Text(item.architecture)
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(badgeColor(for: item.architecture).opacity(0.15))
                                                    .foregroundStyle(badgeColor(for: item.architecture))
                                                    .cornerRadius(4)
                                            }
                                            Text(item.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        HStack(spacing: 8) {
                                            if !item.editions.isEmpty {
                                                // Single consolidated Dropdown Menu for FydeOS (No double chevron, no side-by-side duplicate dropdowns)
                                                Menu {
                                                    Section("Flash to USB Drive") {
                                                        ForEach(item.editions) { edition in
                                                            Button {
                                                                let editionItem = item.itemForEdition(edition)
                                                                downloader.startDownload(item: editionItem) { downloadedUrl in
                                                                    onSelectImageForFlash?(downloadedUrl, true)
                                                                }
                                                            } label: {
                                                                Label("Flash \(edition.name) (\(edition.badge))",
                                                                      systemImage: edition.isLegacy ? "clock.arrow.circlepath" : "bolt.fill")
                                                            }
                                                        }
                                                    }
                                                    Section("Download Image Archive") {
                                                        ForEach(item.editions) { edition in
                                                            Button {
                                                                if let direct = edition.directUrl, downloader.isEligible(direct) {
                                                                    NSWorkspace.shared.open(direct)
                                                                } else {
                                                                    NSWorkspace.shared.open(edition.downloadUrl)
                                                                }
                                                            } label: {
                                                                Label("Download \(edition.name) (\(edition.badge))",
                                                                      systemImage: "arrow.down.circle")
                                                            }
                                                        }
                                                    }
                                                    Divider()
                                                    Button {
                                                        selectedHelpItem = item
                                                        showingHelpMeChoose = true
                                                    } label: {
                                                        Label("Confused? Help me choose →", systemImage: "questionmark.circle")
                                                    }
                                                } label: {
                                                    Text("Download / Flash…")
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(downloader.activeItemId != nil && downloader.activeItemId?.hasPrefix(item.id) != true)
                                            } else {
                                                Button("Download…") {
                                                    // If direct link is eligible, trigger direct download; otherwise open webpage
                                                    if let direct = item.directUrl, downloader.isEligible(direct) {
                                                        NSWorkspace.shared.open(direct)
                                                    } else {
                                                        NSWorkspace.shared.open(item.downloadUrl)
                                                    }
                                                }
                                                .buttonStyle(.borderedProminent)

                                                Button("Flash…") {
                                                    // Downloads image directly in-app, then automatically flashes
                                                    downloader.startDownload(item: item) { downloadedUrl in
                                                        onSelectImageForFlash?(downloadedUrl, true)
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .disabled(downloader.activeItemId != nil && downloader.activeItemId != item.id)
                                                .help("Download this image directly and preload into Drive Creator")
                                            }
                                        }
                                    }

                                    // Active in-app download progress indicator
                                    if downloader.activeItemId == item.id {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ProgressView(value: downloader.progress)
                                                .progressViewStyle(.linear)
                                            HStack {
                                                Text(downloader.statusText)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Button("Cancel") {
                                                    downloader.cancel()
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.mini)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }

                                    if item.id != filteredItems.last?.id {
                                        Divider().padding(.top, 4)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(8)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
        .frame(width: 570, alignment: .leading)
        .sheet(isPresented: $showingHelpMeChoose) {
            if let helpItem = selectedHelpItem ?? OSDownloadItem.catalog.first(where: { $0.category == .fydeOS }) {
                FydeOSHelpMeChooseSheet(
                    targetItem: helpItem,
                    onSelectEditionForDownload: { edition in
                        if let direct = edition.directUrl, downloader.isEligible(direct) {
                            NSWorkspace.shared.open(direct)
                        } else {
                            NSWorkspace.shared.open(edition.downloadUrl)
                        }
                    },
                    onSelectEditionForFlash: { edition in
                        let item = helpItem.itemForEdition(edition)
                        downloader.startDownload(item: item) { downloadedUrl in
                            onSelectImageForFlash?(downloadedUrl, true)
                        }
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rufusShowFydeOSHelp)) { _ in
            selectedFilter = .fydeOS
            selectedHelpItem = OSDownloadItem.catalog.first(where: { $0.category == .fydeOS })
            showingHelpMeChoose = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .rufusFilterFydeOS)) { _ in
            selectedFilter = .fydeOS
        }
    }

    private func badgeColor(for arch: String) -> Color {
        let lower = arch.lowercased()
        if lower.contains("arm") || lower.contains("apple silicon") { return .purple }
        if lower.contains("universal") { return .indigo }
        if lower.contains("x64") { return .blue }
        if lower.contains("x86") || lower.contains("32") { return .orange }
        return .green
    }
}

// MARK: - Interactive FydeOS "Help Me Choose" View

struct FydeOSHelpMeChooseSheet: View {
    let targetItem: OSDownloadItem
    let onSelectEditionForDownload: (OSDownloadEdition) -> Void
    let onSelectEditionForFlash: (OSDownloadEdition) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery: String = ""
    @State private var detectedModel: String = ""
    @State private var baseRecommendation: FydeOSHardwareAdvisor.Recommendation
    @State private var selectedLaptop: LaptopModelSuggestion? = nil
    @State private var lockedSelectionText: String? = nil
    @State private var isHostAppleSilicon: Bool = false
    @FocusState private var isSearchFocused: Bool

    init(targetItem: OSDownloadItem,
         onSelectEditionForDownload: @escaping (OSDownloadEdition) -> Void,
         onSelectEditionForFlash: @escaping (OSDownloadEdition) -> Void) {
        self.targetItem = targetItem
        self.onSelectEditionForDownload = onSelectEditionForDownload
        self.onSelectEditionForFlash = onSelectEditionForFlash
        let host = FydeOSHardwareAdvisor.detectHost()
        _detectedModel = State(initialValue: host.model)
        _baseRecommendation = State(initialValue: host.recommendation)
        _isHostAppleSilicon = State(initialValue: host.recommendation.isAppleSilicon)
    }

    private var matchingSuggestions: [LaptopModelSuggestion] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return FydeOSHardwareAdvisor.searchLaptopModels(trimmed)
    }

    private var currentRecommendation: FydeOSHardwareAdvisor.Recommendation {
        if let selectedLaptop {
            return FydeOSHardwareAdvisor.Recommendation(
                editionName: selectedLaptop.editionDisplayName,
                editionCode: selectedLaptop.recommendedEdition,
                headline: "\(selectedLaptop.editionDisplayName) Recommended",
                reason: "\(selectedLaptop.fullName): \(selectedLaptop.processorInfo). \(selectedLaptop.explanation)",
                badge: selectedLaptop.badge,
                isAppleSilicon: false
            )
        }
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return baseRecommendation
        }
        return FydeOSHardwareAdvisor.evaluate(input: trimmed)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FydeOS for PC")
                        .font(.title2.bold())
                    Text("Please choose one of the following options that best describes your PC")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Search & Detection Box
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search your computer model or processor (e.g. Dell Inspiron 5559, ThinkPad T440, N100, Ryzen 5 5600G)...", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .focused($isSearchFocused)
                                .onSubmit {
                                    isSearchFocused = false
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                }
                                .onChange(of: searchQuery) { newValue in
                                    if let locked = lockedSelectionText, newValue != locked {
                                        // User modified keywords after selection! Immediately re-enable search results
                                        lockedSelectionText = nil
                                        selectedLaptop = nil
                                    }
                                }

                            if !searchQuery.isEmpty {
                                Button(action: {
                                    searchQuery = ""
                                    lockedSelectionText = nil
                                    selectedLaptop = nil
                                    isSearchFocused = true
                                }) {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                        // Interactive Laptop Model Suggestions (Shows whenever matching and user modifies search)
                        if !matchingSuggestions.isEmpty && (selectedLaptop == nil || searchQuery != lockedSelectionText) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SUGGESTED LAPTOP MODELS (CLICK TO SELECT):")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.top, 2)

                                ForEach(matchingSuggestions.prefix(5)) { suggestion in
                                    Button {
                                        selectedLaptop = suggestion
                                        lockedSelectionText = suggestion.fullName
                                        searchQuery = suggestion.fullName
                                        isSearchFocused = false
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "laptopcomputer")
                                                .foregroundStyle(.blue)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(suggestion.fullName)
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.primary)
                                                Text(suggestion.processorInfo)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(suggestion.editionDisplayName)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(editionColor(suggestion.recommendedEdition).opacity(0.15))
                                                .foregroundStyle(editionColor(suggestion.recommendedEdition))
                                                .cornerRadius(4)
                                        }
                                        .padding(8)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        }

                        // Recommendation summary / Architecture warning
                        HStack(alignment: .top, spacing: 8) {
                            if currentRecommendation.isAppleSilicon && searchQuery.isEmpty && selectedLaptop == nil {
                                Image(systemName: "desktopcomputer")
                                    .font(.title3)
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Host Detected: \(detectedModel) (Apple Silicon / ARM64)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                    Text("FydeOS for PC is built for x86_64 Intel & AMD PCs. If you are creating bootable media for an external PC or laptop, search its model name above (e.g. Dell Inspiron 5559, ThinkPad T440, HP Pavilion).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if let selectedLaptop {
                                Image(systemName: "laptopcomputer")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Target PC:")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(selectedLaptop.fullName)
                                            .font(.caption.bold())
                                        Text("→ \(currentRecommendation.editionName) Recommended")
                                            .font(.caption.bold())
                                            .foregroundStyle(.blue)
                                    }
                                    Text(currentRecommendation.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if !searchQuery.isEmpty {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Result for \"\(searchQuery)\":")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(currentRecommendation.headline)
                                            .font(.caption.bold())
                                            .foregroundStyle(.blue)
                                    }
                                    Text(currentRecommendation.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Detected hardware (\(detectedModel)):")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(currentRecommendation.headline)
                                            .font(.caption.bold())
                                            .foregroundStyle(.blue)
                                    }
                                    Text(currentRecommendation.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.2), lineWidth: 1))

                    // 4 Options Grid/Cards exactly matching user specification
                    VStack(spacing: 12) {
                        // 1. Intel Slim
                        editionCard(
                            title: "Intel Slim",
                            code: "slim",
                            badges: ["2015 - 2019", "6th - 9th Gen", "Non-Core"],
                            bodyText: "Supports Intel Celeron, and Pentium Processors (Circa 2015-2019) with Intel HD/UHD Graphics",
                            isLegacy: false
                        )

                        // 2. Intel Modern
                        editionCard(
                            title: "Intel Modern",
                            code: "iris",
                            badges: ["2015 +", "6th - 14th Gen"],
                            bodyText: "Supports Intel Core Processors (Circa 2015+) with Intel HD/UHD or Iris Xe graphics",
                            isLegacy: false
                        )

                        // 3. AMD Graphics
                        editionCard(
                            title: "AMD Graphics",
                            code: "apu",
                            badges: ["2011 +", "Intel & AMD CPU"],
                            bodyText: "Supports AMD Graphics (discrete or integrated) and either AMD or Intel CPUs (2011+)",
                            isLegacy: false
                        )

                        // 4. Intel Legacy
                        editionCard(
                            title: "Intel Legacy",
                            code: "legacy",
                            badges: ["2011 - 2014", "3rd - 5th Gen"],
                            bodyText: "Supports Intel Core Processors (Circa 2011-2014) with Intel HD graphics",
                            isLegacy: true,
                            warningTag: "No longer supported"
                        )
                    }
                }
                .padding(18)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .frame(width: 660, height: 620)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = false
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func editionColor(_ code: String) -> Color {
        switch code {
        case "slim": return .teal
        case "iris": return .blue
        case "apu": return .purple
        case "legacy": return .orange
        default: return .secondary
        }
    }

    @ViewBuilder
    private func editionCard(
        title: String,
        code: String,
        badges: [String],
        bodyText: String,
        isLegacy: Bool,
        warningTag: String? = nil
    ) -> some View {
        let isRec = (currentRecommendation.editionCode == code) && (!currentRecommendation.isAppleSilicon)
        let matchingEdition = targetItem.editions.first { $0.code == code }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let warningTag {
                    Text(warningTag)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(4)
                }

                Text(title)
                    .font(.headline.bold())

                if isRec {
                    Text(selectedLaptop != nil ? "RECOMMENDED FOR \(selectedLaptop!.brand.uppercased())" : "RECOMMENDED")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(badges, id: \.self) { b in
                        Text(b)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                if let edition = matchingEdition {
                    Button("Download") {
                        dismiss()
                        onSelectEditionForDownload(edition)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Flash…") {
                        dismiss()
                        onSelectEditionForFlash(edition)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if isLegacy {
                    // Intel Legacy support stopped at v19.0
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("Intel Legacy support stopped at v19.0 (Not included in FydeOS v\(targetItem.version)).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let v19Item = OSDownloadItem.catalog.first(where: { $0.category == .fydeOS && $0.version.starts(with: "19.0") }),
                           let v19Legacy = v19Item.editions.first(where: { $0.code == "legacy" }) {
                            HStack {
                                Button("Download v19.0 Legacy") {
                                    dismiss()
                                    onSelectEditionForDownload(v19Legacy)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Flash v19.0 Legacy…") {
                                    dismiss()
                                    onSelectEditionForFlash(v19Legacy)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isRec ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isRec ? 2 : 1)
        )
    }
}

// MARK: - Main Drive Creator / Writer View
