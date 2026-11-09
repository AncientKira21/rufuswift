import Foundation

// MARK: - Rufus Enums & Models

public enum BootSelection: String, CaseIterable, Codable, Sendable, Identifiable {
    case nonBootable = "Non bootable"
    case freeDOS = "FreeDOS"
    case diskOrIso = "Disk or ISO image"
    case syslinux = "Syslinux"

    public var id: String { rawValue }
}

public enum ImageOption: String, CaseIterable, Codable, Sendable, Identifiable {
    case standardWindows = "Standard Windows installation"
    case windowsToGo = "Windows To Go"
    case rawImage = "Raw disk image (DD)"
    case macOSInstaller = "macOS Bootable Installer"

    public var id: String { rawValue }
}

public enum PartitionScheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case mbr = "MBR"
    case gpt = "GPT"

    public var id: String { rawValue }
}

public enum TargetSystem: String, CaseIterable, Codable, Sendable, Identifiable {
    case biosOrUefiCsm = "BIOS (or UEFI-CSM)"
    case uefiNonCsm = "UEFI (non CSM)"

    public var id: String { rawValue }
}

public enum TargetFileSystem: String, CaseIterable, Codable, Sendable, Identifiable {
    case fat32 = "FAT32 (Default)"
    case ntfs = "NTFS"
    case exfat = "exFAT"
    case ext4 = "ext4 (Linux)"
    case hfsPlus = "Mac OS Extended (Journaled)"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .fat32: return "FAT32"
        case .ntfs: return "NTFS"
        case .exfat: return "exFAT"
        case .ext4: return "ext4"
        case .hfsPlus: return "JHFS+"
        }
    }
}

public enum AllocationUnitSize: Int64, CaseIterable, Codable, Sendable, Identifiable {
    case defaultSize = 0
    case size512 = 512
    case size1024 = 1024
    case size2048 = 2048
    case size4096 = 4096
    case size8192 = 8192
    case size16K = 16384
    case size32K = 32768
    case size64K = 65536

    public var id: Int64 { rawValue }

    public var title: String {
        switch self {
        case .defaultSize: return "Default cluster size"
        case .size512: return "512 bytes"
        case .size1024: return "1024 bytes"
        case .size2048: return "2048 bytes"
        case .size4096: return "4096 bytes (4 KB)"
        case .size8192: return "8192 bytes (8 KB)"
        case .size16K: return "16 kilobytes"
        case .size32K: return "32 kilobytes"
        case .size64K: return "64 kilobytes"
        }
    }
}

// MARK: - Windows User Experience (WUE) Customization

public struct WindowsUserExperience: Codable, Sendable, Equatable {
    public var bypassTPMAndSecureBoot: Bool = true
    public var bypassOnlineAccount: Bool = true
    public var createLocalAccount: Bool = false
    public var localUsername: String = NSUserName()
    public var setRegionalOptions: Bool = true
    public var disableDataCollection: Bool = true
    public var disableBitLocker: Bool = true
    public var architecture: String = "amd64" // "amd64" or "arm64"

    public init() {}

    public func generateUnattendXml() -> String {
        let arch = architecture.lowercased().contains("arm") ? "arm64" : "amd64"
        var xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <unattend xmlns="urn:schemas-microsoft-com:unattend">
        """

        if bypassTPMAndSecureBoot || disableBitLocker {
            xml += """

          <settings pass="windowsPE">
            <component name="Microsoft-Windows-Setup" processorArchitecture="\(arch)" language="neutral" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" publicKeyToken="31bf3856ad364e35" versionScope="nonSxS">
              <UserData>
                <AcceptEula>true</AcceptEula>
              </UserData>
        """
            if disableBitLocker {
                xml += """

              <DiskConfiguration>
                <WillShowUI>OnError</WillShowUI>
                <DisableEncryptedDiskProvisioning>true</DisableEncryptedDiskProvisioning>
              </DiskConfiguration>
        """
            }
            if bypassTPMAndSecureBoot {
                xml += """

              <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                  <Order>1</Order>
                  <Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                  <Order>2</Order>
                  <Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                  <Order>3</Order>
                  <Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                  <Order>4</Order>
                  <Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                  <Order>5</Order>
                  <Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
              </RunSynchronous>
        """
            }
            xml += """

            </component>
          </settings>
        """
        }

        if bypassOnlineAccount {
            xml += """

          <settings pass="specialize">
            <component name="Microsoft-Windows-Deployment" processorArchitecture="\(arch)" language="neutral" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" publicKeyToken="31bf3856ad364e35" versionScope="nonSxS">
              <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                  <Order>1</Order>
                  <Path>reg add "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
              </RunSynchronous>
            </component>
          </settings>
        """
        }

        xml += """

          <settings pass="oobeSystem">
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="\(arch)" language="neutral" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" publicKeyToken="31bf3856ad364e35" versionScope="nonSxS">
        """
        if disableDataCollection {
            xml += """

              <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <ProtectYourPC>3</ProtectYourPC>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
              </OOBE>
        """
        }
        if setRegionalOptions {
            let timeZone = TimeZone.current.identifier
            xml += """

              <TimeZone>\(timeZone)</TimeZone>
        """
        }
        if createLocalAccount && !localUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let user = localUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            xml += """

              <UserAccounts>
                <LocalAccounts>
                  <LocalAccount wcm:action="add">
                    <Name>\(user)</Name>
                    <DisplayName>\(user)</DisplayName>
                    <Group>Administrators</Group>
                    <Password>
                      <Value></Value>
                      <PlainText>true</PlainText>
                    </Password>
                  </LocalAccount>
                </LocalAccounts>
              </UserAccounts>
        """
        }
        xml += """

            </component>
          </settings>
        </unattend>
        """
        return xml
    }
}

// MARK: - Format & Execution Configuration

public struct RufusWorkflowConfig: Codable, Sendable {
    public var bootSelection: BootSelection = .diskOrIso
    public var imageOption: ImageOption = .standardWindows
    public var partitionScheme: PartitionScheme = .gpt
    public var targetSystem: TargetSystem = .uefiNonCsm
    public var fileSystem: TargetFileSystem = .fat32
    public var clusterSize: AllocationUnitSize = .defaultSize
    public var volumeLabel: String = "RUFUS_DRIVE"
    public var quickFormat: Bool = true
    public var createExtendedLabel: Bool = true
    public var checkBadBlocks: Bool = false
    public var badBlockPasses: Int = 1
    public var oldBiosFixes: Bool = false
    public var useRufusMbr: Bool = false
    public var listUsbHardDrives: Bool = false
    public var persistenceSizeMB: Int64 = 0
    public var wue: WindowsUserExperience = WindowsUserExperience()

    public init() {}
}

// MARK: - OS Download Catalog (Every downloadable Windows, macOS, FydeOS, and Linux version)

public enum OSCategory: String, CaseIterable, Identifiable, Sendable {
    case windows = "Windows"
    case macOS = "macOS"
    case fydeOS = "FydeOS"
    case linux = "Linux"

    public var id: String { rawValue }
}

public struct OSDownloadEdition: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let badge: String
    public let description: String
    public let code: String
    public let directUrl: URL?
    public let downloadUrl: URL
    public let defaultFilename: String
    public let isLegacy: Bool

    public init(
        id: String,
        name: String,
        badge: String,
        description: String,
        code: String,
        directUrl: URL?,
        downloadUrl: URL,
        defaultFilename: String,
        isLegacy: Bool = false
    ) {
        self.id = id
        self.name = name
        self.badge = badge
        self.description = description
        self.code = code
        self.directUrl = directUrl
        self.downloadUrl = downloadUrl
        self.defaultFilename = defaultFilename
        self.isLegacy = isLegacy
    }
}

public struct LaptopModelSuggestion: Identifiable, Sendable {
    public let id: String
    public let brand: String
    public let fullName: String
    public let processorInfo: String
    public let recommendedEdition: String // "slim", "iris", "apu", "legacy"
    public let editionDisplayName: String
    public let badge: String
    public let explanation: String
    public let aliases: [String]

    public init(
        id: String,
        brand: String,
        fullName: String,
        processorInfo: String,
        recommendedEdition: String,
        editionDisplayName: String,
        badge: String,
        explanation: String,
        aliases: [String] = []
    ) {
        self.id = id
        self.brand = brand
        self.fullName = fullName
        self.processorInfo = processorInfo
        self.recommendedEdition = recommendedEdition
        self.editionDisplayName = editionDisplayName
        self.badge = badge
        self.explanation = explanation
        self.aliases = aliases
    }
}

public struct FydeOSHardwareAdvisor: Sendable {
    public struct Recommendation: Sendable {
        public let editionName: String
        public let editionCode: String
        public let headline: String
        public let reason: String
        public let badge: String
        public let isAppleSilicon: Bool

        public init(
            editionName: String,
            editionCode: String,
            headline: String,
            reason: String,
            badge: String,
            isAppleSilicon: Bool = false
        ) {
            self.editionName = editionName
            self.editionCode = editionCode
            self.headline = headline
            self.reason = reason
            self.badge = badge
            self.isAppleSilicon = isAppleSilicon
        }
    }

    public static let laptopDatabase: [LaptopModelSuggestion] = [
        // Dell
        LaptopModelSuggestion(
            id: "dell-inspiron-5559",
            brand: "Dell",
            fullName: "Dell Inspiron 15 (5559)",
            processorInfo: "6th Gen Intel Core i3-6100U / i5-6200U / i7-6500U · Intel HD 520",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 6th Gen",
            explanation: "6th Gen Intel Skylake processor with HD 520 graphics. Intel Modern edition is fully supported.",
            aliases: ["dell 5559", "inspiron 5559", "insprion 5559", "dell insprion 5559", "inspiron 15 5559", "5559"]
        ),
        LaptopModelSuggestion(
            id: "dell-inspiron-3583",
            brand: "Dell",
            fullName: "Dell Inspiron 15 (3583 / 3593 / 5570)",
            processorInfo: "8th - 10th Gen Intel Core i3 / i5 / i7 · Intel UHD Graphics",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 8th - 10th Gen",
            explanation: "Modern 8th/10th Gen Intel Core platform with UHD Graphics.",
            aliases: ["dell 3583", "inspiron 3583", "inspiron 3593", "dell 5570", "inspiron 5570"]
        ),
        LaptopModelSuggestion(
            id: "dell-inspiron-3542",
            brand: "Dell",
            fullName: "Dell Inspiron 15 (3521 / 3542 / 5547)",
            processorInfo: "3rd - 4th Gen Intel Core (Ivy Bridge / Haswell) · Intel HD 4000/4400",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 3rd - 4th Gen",
            explanation: "Older 3rd/4th Gen Intel Core architecture. Requires Intel Legacy edition (supported up to v19.0).",
            aliases: ["dell 3521", "dell 3542", "dell 5547", "inspiron 3521", "inspiron 3542", "inspiron 5547"]
        ),
        LaptopModelSuggestion(
            id: "dell-inspiron-3180",
            brand: "Dell",
            fullName: "Dell Inspiron 11 (3162 / 3180) / Chromebook 3100",
            processorInfo: "Intel Celeron N3060 / N4000 / N4020 · Intel HD/UHD",
            recommendedEdition: "slim",
            editionDisplayName: "Intel Slim",
            badge: "2015 - 2019 · Non-Core",
            explanation: "Intel Celeron Non-Core entry processor. Optimized specifically for Intel Slim edition.",
            aliases: ["dell 3180", "dell 3162", "dell 3100", "chromebook 3100", "dell celeron"]
        ),
        LaptopModelSuggestion(
            id: "dell-inspiron-ryzen",
            brand: "Dell",
            fullName: "Dell Inspiron 15 (3505 / 3515 / 3525 AMD)",
            processorInfo: "AMD Ryzen 3 3250U / Ryzen 5 3500U / 5500U · Radeon Graphics",
            recommendedEdition: "apu",
            editionDisplayName: "AMD Graphics",
            badge: "2011 + · AMD Ryzen",
            explanation: "AMD Ryzen APU with integrated Radeon graphics. Use AMD Graphics edition.",
            aliases: ["dell 3505", "dell 3515", "dell 3525", "dell ryzen", "inspiron amd", "inspiron ryzen"]
        ),
        LaptopModelSuggestion(
            id: "dell-latitude-e6440",
            brand: "Dell",
            fullName: "Dell Latitude E6420 / E6430 / E6440 / E7440 / E7450",
            processorInfo: "2nd - 5th Gen Intel Core i5 / i7 · Intel HD 3000 / 4000 / 4400 / 5500",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 2nd - 5th Gen",
            explanation: "Vintage Latitude business laptop with 2nd-5th Gen Intel Core. Requires Intel Legacy edition (<= v19.0).",
            aliases: ["latitude e6420", "latitude e6430", "latitude e6440", "latitude e7440", "latitude e7450", "e6440", "e7440", "e7450", "e6430"]
        ),
        LaptopModelSuggestion(
            id: "dell-latitude-7490",
            brand: "Dell",
            fullName: "Dell Latitude 5480 / 5490 / 7480 / 7490",
            processorInfo: "6th - 8th Gen Intel Core i5 / i7 · Intel HD 520 / 620 / UHD 620",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 6th - 8th Gen",
            explanation: "Modern Intel Core business notebook with HD/UHD graphics.",
            aliases: ["latitude 5480", "latitude 5490", "latitude 7480", "latitude 7490", "latitude 5400", "latitude 7400"]
        ),
        LaptopModelSuggestion(
            id: "dell-xps-13-9343",
            brand: "Dell",
            fullName: "Dell XPS 13 (9333 / 9343)",
            processorInfo: "4th - 5th Gen Intel Core i5 / i7 · Intel HD 4400 / 5500",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 4th - 5th Gen",
            explanation: "Early XPS 13 models (Broadwell/Haswell). Requires Intel Legacy edition (<= v19.0).",
            aliases: ["xps 9333", "xps 9343", "xps 13 9343", "xps 13 9333"]
        ),
        LaptopModelSuggestion(
            id: "dell-xps-13-modern",
            brand: "Dell",
            fullName: "Dell XPS 13 (9350 / 9360 / 9370 / 9380 / 9300 / 9310)",
            processorInfo: "6th - 11th Gen Intel Core · Intel Iris / Iris Xe / UHD Graphics",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 6th - 11th Gen",
            explanation: "Modern Intel Core XPS 13 with Iris / UHD graphics. Fully supported by Intel Modern.",
            aliases: ["xps 9350", "xps 9360", "xps 9370", "xps 9380", "xps 9300", "xps 9310", "xps 13"]
        ),

        // Lenovo ThinkPad
        LaptopModelSuggestion(
            id: "lenovo-thinkpad-t440",
            brand: "Lenovo",
            fullName: "Lenovo ThinkPad T420 / T430 / T440 / T440p / T450",
            processorInfo: "2nd - 5th Gen Intel Core i5 / i7 · Intel HD 3000 / 4000 / 4400 / 4600 / 5500",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 2nd - 5th Gen",
            explanation: "Classic ThinkPad T-series with 2nd-5th Gen Intel Core. Requires Intel Legacy edition (<= v19.0).",
            aliases: ["thinkpad t420", "thinkpad t430", "thinkpad t440", "thinkpad t440p", "thinkpad t450", "t440", "t440p", "t430", "t450", "t420"]
        ),
        LaptopModelSuggestion(
            id: "lenovo-thinkpad-x240",
            brand: "Lenovo",
            fullName: "Lenovo ThinkPad X220 / X230 / X240 / X250",
            processorInfo: "2nd - 5th Gen Intel Core i5 / i7 · Intel HD Graphics",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 2nd - 5th Gen",
            explanation: "Compact ThinkPad X-series with 2nd-5th Gen Intel Core. Use Intel Legacy (<= v19.0).",
            aliases: ["thinkpad x220", "thinkpad x230", "thinkpad x240", "thinkpad x250", "x220", "x230", "x240", "x250"]
        ),
        LaptopModelSuggestion(
            id: "lenovo-thinkpad-t480",
            brand: "Lenovo",
            fullName: "Lenovo ThinkPad T460 / T470 / T480 / T490 / T14",
            processorInfo: "6th - 11th Gen Intel Core i5 / i7 · Intel HD 520 / UHD 620 / Iris Xe",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 6th - 11th Gen",
            explanation: "Popular modern ThinkPads with 6th-11th Gen Intel Core. Best match is Intel Modern.",
            aliases: ["thinkpad t460", "thinkpad t470", "thinkpad t480", "thinkpad t490", "thinkpad t14", "t460", "t470", "t480", "t490", "t14"]
        ),
        LaptopModelSuggestion(
            id: "lenovo-ideapad-celeron",
            brand: "Lenovo",
            fullName: "Lenovo IdeaPad 1 / 3 (Celeron / Pentium)",
            processorInfo: "Intel Celeron N4000 / N4020 / Pentium Silver N5030 · Intel UHD Graphics",
            recommendedEdition: "slim",
            editionDisplayName: "Intel Slim",
            badge: "2015 - 2019 · Non-Core",
            explanation: "Intel Celeron / Pentium Non-Core processor. Tailored for Intel Slim edition.",
            aliases: ["ideapad 1", "ideapad celeron", "ideapad 3 celeron", "lenovo celeron", "ideapad n4020"]
        ),
        LaptopModelSuggestion(
            id: "lenovo-thinkpad-amd",
            brand: "Lenovo",
            fullName: "Lenovo ThinkPad E14 / E15 / T14 AMD (Ryzen)",
            processorInfo: "AMD Ryzen 3 / 5 / 7 PRO (3000 / 4000 / 5000 / 6000 Series) · Radeon Graphics",
            recommendedEdition: "apu",
            editionDisplayName: "AMD Graphics",
            badge: "2011 + · AMD Ryzen",
            explanation: "AMD Ryzen ThinkPad with integrated Radeon graphics. Use AMD Graphics edition.",
            aliases: ["thinkpad amd", "thinkpad ryzen", "t14 amd", "e14 amd", "e15 amd", "lenovo ryzen", "ideapad ryzen"]
        ),

        // HP
        LaptopModelSuggestion(
            id: "hp-elitebook-840-g1",
            brand: "HP",
            fullName: "HP EliteBook 840 G1 / G2 (Folio 9470m)",
            processorInfo: "3rd - 5th Gen Intel Core i5 / i7 · Intel HD 4000 / 4400 / 5500",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 3rd - 5th Gen",
            explanation: "HP business enterprise laptop with Haswell/Broadwell. Requires Intel Legacy edition (<= v19.0).",
            aliases: ["elitebook 840 g1", "elitebook 840 g2", "840 g1", "840 g2", "folio 9470m", "hp 840 g1", "hp 840 g2"]
        ),
        LaptopModelSuggestion(
            id: "hp-elitebook-840-g5",
            brand: "HP",
            fullName: "HP EliteBook 840 G3 / G4 / G5 / G6 / G7 / G8",
            processorInfo: "6th - 11th Gen Intel Core i5 / i7 · Intel HD 520 / 620 / UHD 620 / Iris Xe",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 6th - 11th Gen",
            explanation: "Enterprise HP notebook with 6th-11th Gen Intel Core. Fully supported by Intel Modern.",
            aliases: ["elitebook 840 g3", "elitebook 840 g4", "elitebook 840 g5", "elitebook 840 g6", "840 g3", "840 g4", "840 g5", "840 g6"]
        ),
        LaptopModelSuggestion(
            id: "hp-stream-celeron",
            brand: "HP",
            fullName: "HP Stream 11 / 14 / HP 14 (Celeron)",
            processorInfo: "Intel Celeron N3050 / N3060 / N4000 / N4020 · Intel HD/UHD",
            recommendedEdition: "slim",
            editionDisplayName: "Intel Slim",
            badge: "2015 - 2019 · Non-Core",
            explanation: "Lightweight Intel Celeron laptop. Optimized for Intel Slim edition.",
            aliases: ["hp stream", "stream 11", "stream 14", "hp celeron", "hp 14 celeron"]
        ),
        LaptopModelSuggestion(
            id: "hp-pavilion-ryzen",
            brand: "HP",
            fullName: "HP Pavilion 15 / Envy x360 (AMD Ryzen)",
            processorInfo: "AMD Ryzen 3 3200U / 5 3500U / 5 4500U / 5 5500U · Radeon Graphics",
            recommendedEdition: "apu",
            editionDisplayName: "AMD Graphics",
            badge: "2011 + · AMD Ryzen",
            explanation: "AMD Ryzen with integrated Radeon graphics. Use AMD Graphics edition.",
            aliases: ["hp ryzen", "pavilion ryzen", "envy ryzen", "hp amd", "hp pavilion ryzen"]
        ),

        // ASUS
        LaptopModelSuggestion(
            id: "asus-zenbook-ux305",
            brand: "ASUS",
            fullName: "ASUS ZenBook UX303 / UX305",
            processorInfo: "4th - 5th Gen Intel Core / Core M · Intel HD 4400 / 5300 / 5500",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 4th - 5th Gen",
            explanation: "Ultra-slim Haswell/Broadwell ZenBook. Requires Intel Legacy edition (<= v19.0).",
            aliases: ["zenbook ux303", "zenbook ux305", "ux303", "ux305"]
        ),
        LaptopModelSuggestion(
            id: "asus-zenbook-modern",
            brand: "ASUS",
            fullName: "ASUS ZenBook 13 / 14 (UX430 / UX433 / UX425)",
            processorInfo: "7th - 11th Gen Intel Core · Intel UHD Graphics / Iris Xe",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 7th - 11th Gen",
            explanation: "Modern Intel ZenBook. Intel Modern edition offers best GPU acceleration.",
            aliases: ["zenbook ux430", "zenbook ux433", "zenbook ux425", "zenbook 13", "zenbook 14"]
        ),
        LaptopModelSuggestion(
            id: "asus-vivobook-celeron",
            brand: "ASUS",
            fullName: "ASUS VivoBook 14 / 15 (Celeron / Pentium)",
            processorInfo: "Intel Celeron N4020 / Pentium Silver N5030 / N6000 · Intel UHD",
            recommendedEdition: "slim",
            editionDisplayName: "Intel Slim",
            badge: "2015 - 2019 · Non-Core",
            explanation: "Non-Core Celeron/Pentium VivoBook. Designed for Intel Slim edition.",
            aliases: ["vivobook celeron", "vivobook n4020", "vivobook e410", "vivobook e510"]
        ),
        LaptopModelSuggestion(
            id: "asus-vivobook-ryzen",
            brand: "ASUS",
            fullName: "ASUS VivoBook 15 / 16 / TUF Gaming (AMD)",
            processorInfo: "AMD Ryzen 5 3500U / 5 4600H / 5 5500U / 7 5700U · Radeon Graphics",
            recommendedEdition: "apu",
            editionDisplayName: "AMD Graphics",
            badge: "2011 + · AMD Ryzen",
            explanation: "AMD Ryzen APU / GPU system. Requires AMD Graphics edition.",
            aliases: ["vivobook ryzen", "vivobook amd", "asus ryzen", "tuf gaming", "rog zephyrus"]
        ),

        // Acer
        LaptopModelSuggestion(
            id: "acer-aspire-e5",
            brand: "Acer",
            fullName: "Acer Aspire E5-571 / E5-573",
            processorInfo: "4th - 5th Gen Intel Core i3 / i5 · Intel HD 4400 / 5500",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 4th - 5th Gen",
            explanation: "Haswell/Broadwell budget laptop. Requires Intel Legacy edition (<= v19.0).",
            aliases: ["aspire e5-571", "aspire e5-573", "aspire e5", "acer e5"]
        ),
        LaptopModelSuggestion(
            id: "acer-aspire-5-modern",
            brand: "Acer",
            fullName: "Acer Aspire 5 (Intel Core)",
            processorInfo: "7th - 11th Gen Intel Core i3 / i5 / i7 · Intel UHD / Iris Xe",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 7th - 11th Gen",
            explanation: "Modern Aspire 5 laptop with Intel Core processor. Use Intel Modern.",
            aliases: ["aspire 5", "aspire 5 intel", "acer aspire 5", "a515-54", "a515-56"]
        ),
        LaptopModelSuggestion(
            id: "acer-aspire-ryzen",
            brand: "Acer",
            fullName: "Acer Aspire 3 / 5 (AMD Ryzen)",
            processorInfo: "AMD Ryzen 3 3200U / 5 3500U / 5 5500U · Radeon Graphics",
            recommendedEdition: "apu",
            editionDisplayName: "AMD Graphics",
            badge: "2011 + · AMD Ryzen",
            explanation: "AMD Ryzen Aspire notebook with integrated Radeon. Use AMD Graphics.",
            aliases: ["aspire ryzen", "aspire 5 ryzen", "acer ryzen", "a515-43", "a515-45"]
        ),

        // Microsoft Surface
        LaptopModelSuggestion(
            id: "surface-pro-3",
            brand: "Microsoft",
            fullName: "Microsoft Surface Pro 3",
            processorInfo: "4th Gen Intel Core i3 / i5 / i7 · Intel HD 4400 / 5000",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 4th Gen",
            explanation: "4th Gen Intel Haswell tablet PC. Requires Intel Legacy edition (<= v19.0).",
            aliases: ["surface pro 3", "pro 3"]
        ),
        LaptopModelSuggestion(
            id: "surface-pro-modern",
            brand: "Microsoft",
            fullName: "Microsoft Surface Pro 4 / 5 / 6 / 7 / 8 / 9",
            processorInfo: "6th - 12th Gen Intel Core · Intel HD 520 / 620 / Iris Plus / Iris Xe",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 6th - 12th Gen",
            explanation: "Modern Intel Core Surface Pro. Runs smoothly with Intel Modern edition.",
            aliases: ["surface pro 4", "surface pro 5", "surface pro 6", "surface pro 7", "surface pro 8", "surface pro 9", "surface pro"]
        ),
        LaptopModelSuggestion(
            id: "surface-go",
            brand: "Microsoft",
            fullName: "Microsoft Surface Go 1 / 2 / 3",
            processorInfo: "Intel Pentium Gold 4415Y / 4425Y / 6500Y · Intel HD 615",
            recommendedEdition: "slim",
            editionDisplayName: "Intel Slim",
            badge: "2015 - 2019 · Non-Core",
            explanation: "Intel Pentium Gold low-power Non-Core processor. Best with Intel Slim edition.",
            aliases: ["surface go", "surface go 2", "surface go 3"]
        ),

        // Apple Mac (Target)
        LaptopModelSuggestion(
            id: "apple-intel-legacy",
            brand: "Apple",
            fullName: "Apple MacBook Pro / Air (Intel 2011 - 2015)",
            processorInfo: "2nd - 5th Gen Intel Core i5 / i7 · Intel HD 3000 / 4000 / 5000 / 6000",
            recommendedEdition: "legacy",
            editionDisplayName: "Intel Legacy",
            badge: "No longer supported (Stopped at v19.0) · 2nd - 5th Gen",
            explanation: "Legacy Intel Macs (2011-2015). Requires Intel Legacy edition (supported up to v19.0).",
            aliases: ["macbook 2011", "macbook 2012", "macbook 2013", "macbook 2014", "macbook 2015", "macbook air 2013", "macbook air 2014", "macbook air 2015", "macbook pro 2012", "macbook pro 2013", "macbook pro 2014", "macbook pro 2015"]
        ),
        LaptopModelSuggestion(
            id: "apple-intel-modern",
            brand: "Apple",
            fullName: "Apple MacBook Pro / Air (Intel 2016 - 2020)",
            processorInfo: "6th - 10th Gen Intel Core i5 / i7 / i9 · Intel Iris Plus Graphics",
            recommendedEdition: "iris",
            editionDisplayName: "Intel Modern",
            badge: "2015 + · 6th - 10th Gen",
            explanation: "Modern Intel Macs (2016-2020) with Iris Plus graphics. Use Intel Modern edition.",
            aliases: ["macbook 2016", "macbook 2017", "macbook 2018", "macbook 2019", "macbook 2020", "macbook air 2018", "macbook air 2019", "macbook air 2020", "macbook pro 2016", "macbook pro 2017", "macbook pro 2018", "macbook pro 2019", "macbook pro 2020"]
        )
    ]

    public static func searchLaptopModels(_ rawQuery: String) -> [LaptopModelSuggestion] {
        let clean = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return [] }

        // Normalize common typos
        let normalized = clean
            .replacingOccurrences(of: "insprion", with: "inspiron")
            .replacingOccurrences(of: "inspion", with: "inspiron")
            .replacingOccurrences(of: "inpsiron", with: "inspiron")
            .replacingOccurrences(of: "thiknpad", with: "thinkpad")
            .replacingOccurrences(of: "thinkapd", with: "thinkpad")
            .replacingOccurrences(of: "thinpad", with: "thinkpad")
            .replacingOccurrences(of: "latidude", with: "latitude")
            .replacingOccurrences(of: "latitue", with: "latitude")
            .replacingOccurrences(of: "elietbook", with: "elitebook")
            .replacingOccurrences(of: "paviloin", with: "pavilion")
            .replacingOccurrences(of: "zenbok", with: "zenbook")
            .replacingOccurrences(of: "asuse", with: "asus")
            .replacingOccurrences(of: "lenvo", with: "lenovo")
            .replacingOccurrences(of: "makcbook", with: "macbook")

        let tokens = normalized.split(separator: " ").map(String.init).filter { $0.count > 1 }

        var scored: [(suggestion: LaptopModelSuggestion, score: Int)] = []

        for item in laptopDatabase {
            let fullNameLower = item.fullName.lowercased()
            let brandLower = item.brand.lowercased()
            let procLower = item.processorInfo.lowercased()
            let combined = "\(fullNameLower) \(brandLower) \(procLower) \(item.aliases.joined(separator: " ").lowercased())"

            var score = 0

            // Exact or substring match in full name
            if fullNameLower.contains(normalized) {
                score += 120
            }

            // Check if any alias matches normalized exactly or as substring
            for alias in item.aliases {
                let a = alias.lowercased()
                if a == normalized {
                    score += 100
                } else if a.contains(normalized) || normalized.contains(a) {
                    score += 60
                }
            }

            // Token match
            var matchedTokens = 0
            for token in tokens {
                if combined.contains(token) {
                    matchedTokens += 1
                    if fullNameLower.contains(token) {
                        score += 25
                    } else {
                        score += 12
                    }
                }
            }

            // Bonus if all tokens matched
            if !tokens.isEmpty && matchedTokens == tokens.count {
                score += 50
            }

            if score > 0 {
                scored.append((item, score))
            }
        }

        scored.sort { $0.score > $1.score }
        return scored.map { $0.suggestion }
    }

    public static func detectHost() -> (model: String, recommendation: Recommendation) {
        #if canImport(Darwin)
        let brand = sysctlString("machdep.cpu.brand_string")
        let model = sysctlString("hw.model")
        let hostDesc = [model, brand].filter { !$0.isEmpty }.joined(separator: " · ")

        #if arch(arm64)
        let displayName = hostDesc.isEmpty ? "Mac (Apple Silicon)" : hostDesc
        let rec = Recommendation(
            editionName: "Apple Silicon Host",
            editionCode: "apple_silicon",
            headline: "Apple Silicon Host (\(displayName))",
            reason: "Your host Mac uses Apple Silicon (\(displayName)). Note: FydeOS for PC is built for Intel and AMD x86_64 PCs. Search your target laptop/PC model above to select the correct edition for your USB drive.",
            badge: "Host: Apple Silicon / ARM64",
            isAppleSilicon: true
        )
        return (displayName, rec)
        #else
        let isAppleSilicon = brand.lowercased().contains("apple") || (model.lowercased().contains("mac") && (brand.lowercased().contains("m1") || brand.lowercased().contains("m2") || brand.lowercased().contains("m3") || brand.lowercased().contains("m4") || brand.lowercased().contains("m5")))
        if isAppleSilicon {
            let displayName = hostDesc.isEmpty ? "Mac (Apple Silicon)" : hostDesc
            let rec = Recommendation(
                editionName: "Apple Silicon Host",
                editionCode: "apple_silicon",
                headline: "Apple Silicon Host (\(displayName))",
                reason: "Your host Mac uses Apple Silicon (\(displayName)). Note: FydeOS for PC is built for Intel and AMD x86_64 PCs. Search your target laptop/PC model above to select the correct edition for your USB drive.",
                badge: "Host: Apple Silicon / ARM64",
                isAppleSilicon: true
            )
            return (displayName, rec)
        }
        return (hostDesc.isEmpty ? "Mac System" : hostDesc, evaluate(input: "\(brand) \(model)"))
        #endif
        #elseif os(Linux)
        let cpuInfo = (try? String(contentsOfFile: "/proc/cpuinfo", encoding: .utf8)) ?? ""
        let brand = cpuInfo.components(separatedBy: "\n")
            .first { $0.hasPrefix("model name") }?
            .components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
        let isArm = cpuInfo.lowercased().contains("aarch64") || cpuInfo.lowercased().contains("arm")
        if isArm {
            let rec = Recommendation(
                editionName: "ARM64 Host",
                editionCode: "apple_silicon",
                headline: "ARM64 Host (\(brand.isEmpty ? "Linux ARM" : brand))",
                reason: "FydeOS for PC is built for Intel and AMD x86_64 PCs. Search your target laptop/PC model above.",
                badge: "Host: ARM64",
                isAppleSilicon: true
            )
            return (brand.isEmpty ? "ARM64 Linux Device" : brand, rec)
        }
        return (brand.isEmpty ? "Linux PC" : brand, evaluate(input: brand))
        #else
        return ("Host PC", evaluate(input: ""))
        #endif
    }

    public static func evaluate(input: String) -> Recommendation {
        let q = input.lowercased()

        // 0. Check for Apple Silicon / ARM queries
        if q.contains("apple") && (q.contains("silicon") || q.contains("m1") || q.contains("m2") || q.contains("m3") || q.contains("m4") || q.contains("m5")) ||
           q.contains("m5 pro") || q.contains("m4 pro") || q.contains("m3 pro") || q.contains("m2 pro") || q.contains("m1 pro") ||
           q.contains("m5 max") || q.contains("m4 max") || q.contains("m3 max") || q.contains("aarch64") {
            return Recommendation(
                editionName: "Apple Silicon Host",
                editionCode: "apple_silicon",
                headline: "Apple Silicon / ARM64 Detected",
                reason: "FydeOS for PC is built for Intel & AMD x86_64 PCs. If you are flashing a USB for another PC, search that laptop/PC model above.",
                badge: "Apple Silicon / ARM64",
                isAppleSilicon: true
            )
        }

        // Check if query matches a laptop model in our database first
        let matches = searchLaptopModels(input)
        if let topMatch = matches.first {
            return Recommendation(
                editionName: topMatch.editionDisplayName,
                editionCode: topMatch.recommendedEdition,
                headline: "\(topMatch.editionDisplayName) Recommended",
                reason: "\(topMatch.fullName): \(topMatch.processorInfo). \(topMatch.explanation)",
                badge: topMatch.badge
            )
        }

        // 1. AMD Graphics (discrete or integrated) & AMD/Intel CPU (2011+)
        if q.contains("amd") || q.contains("ryzen") || q.contains("radeon") || q.contains("athlon") || q.contains("threadripper") {
            return Recommendation(
                editionName: "AMD Graphics",
                editionCode: "apu",
                headline: "AMD Graphics Edition Recommended",
                reason: "Supports AMD Graphics (discrete or integrated) and either AMD or Intel CPUs (2011+). Includes open-source Radeon and Mesa hardware acceleration.",
                badge: "2011 + · Intel & AMD CPU"
            )
        }

        // 2. Intel Slim: Intel Celeron and Pentium (Circa 2015-2019, 6th-9th Gen, Non-Core)
        if q.contains("celeron") || q.contains("pentium") || q.contains("atom") ||
           q.contains("n100") || q.contains("n200") || q.contains("n95") ||
           q.contains("n3") || q.contains("n4") || q.contains("n5") ||
           q.contains("j3") || q.contains("j4") || q.contains("j5") ||
           q.contains("g3") || q.contains("g4") || q.contains("g5") ||
           q.contains("apollo") || q.contains("gemini") || q.contains("jasper") {
            return Recommendation(
                editionName: "Intel Slim",
                editionCode: "slim",
                headline: "Intel Slim Edition Recommended",
                reason: "Supports Intel Celeron, and Pentium Processors (Circa 2015-2019) with Intel HD/UHD Graphics. Optimized for efficient memory and lightweight graphics.",
                badge: "2015 - 2019 · 6th - 9th Gen · Non-Core"
            )
        }

        // 3. Intel Legacy: 3rd - 5th Gen Intel Core (Circa 2011-2014) with Intel HD graphics
        let legacyTerms = ["i3-2", "i5-2", "i7-2", "i3-3", "i5-3", "i7-3", "i3-4", "i5-4", "i7-4", "i3-5", "i5-5", "i7-5",
                           "2nd gen", "3rd gen", "4th gen", "5th gen", "sandy", "ivy bridge", "haswell", "broadwell",
                           "hd 2000", "hd 2500", "hd 3000", "hd 4000", "hd 4400", "hd 4600", "hd 5000", "hd 5500", "hd 6000",
                           "t420", "t430", "t440", "t450", "x220", "x230", "x240", "x250", "e6420", "e6430", "e6440", "e7440", "e7450"]
        if legacyTerms.contains(where: { q.contains($0) }) {
            return Recommendation(
                editionName: "Intel Legacy",
                editionCode: "legacy",
                headline: "Intel Legacy Edition (No longer supported)",
                reason: "Supports Intel Core Processors (Circa 2011-2014) with Intel HD graphics. Intel Legacy support stopped at v19.0.",
                badge: "No longer supported · 2011 - 2014 · 3rd - 5th Gen"
            )
        }

        // 4. Intel Modern: 6th - 14th Gen Intel Core (Circa 2015+) with Intel HD/UHD or Iris Xe graphics
        return Recommendation(
            editionName: "Intel Modern",
            editionCode: "iris",
            headline: "Intel Modern Edition Recommended",
            reason: "Supports Intel Core Processors (Circa 2015+) with Intel HD/UHD or Iris Xe graphics. Includes full Linux and Android subsystem acceleration.",
            badge: "2015 + · 6th - 14th Gen"
        )
    }

    #if canImport(Darwin)
    private static func sysctlString(_ key: String) -> String {
        var size = 0
        sysctlbyname(key, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(key, &buf, &size, nil, 0)
        return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}

public struct OSDownloadItem: Identifiable, Sendable {
    public let id: String
    public let category: OSCategory
    public let name: String
    public let version: String
    public let architecture: String
    public let downloadUrl: URL
    public let directUrl: URL?
    public let defaultFilename: String
    public let description: String
    public let editions: [OSDownloadEdition]

    public init(
        id: String,
        category: OSCategory,
        name: String,
        version: String,
        architecture: String,
        downloadUrl: URL,
        directUrl: URL? = nil,
        defaultFilename: String,
        description: String,
        editions: [OSDownloadEdition] = []
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.version = version
        self.architecture = architecture
        self.downloadUrl = downloadUrl
        self.directUrl = directUrl
        self.defaultFilename = defaultFilename
        self.description = description
        self.editions = editions
    }

    public func itemForEdition(_ edition: OSDownloadEdition) -> OSDownloadItem {
        return OSDownloadItem(
            id: "\(id)-\(edition.code)",
            category: category,
            name: "\(name) (\(edition.name))",
            version: version,
            architecture: edition.badge,
            downloadUrl: edition.downloadUrl,
            directUrl: edition.directUrl,
            defaultFilename: edition.defaultFilename,
            description: edition.description,
            editions: []
        )
    }

    public static func makeFydeOS(
        _ ver: String,
        sub: String = "",
        releaseSuffix: String = "-io.bin.zip",
        extraDesc: String = "",
        isXz: Bool = false
    ) -> OSDownloadItem {
        let ext = isXz ? ".img.xz" : (releaseSuffix.hasPrefix("-") ? releaseSuffix : ".bin.zip")
        let slimDirect = URL(string: "https://download.fydeos.io/v\(ver)/FydeOS_for_PC_slim_v\(ver)\(releaseSuffix)")
        let irisDirect = URL(string: "https://download.fydeos.io/v\(ver)/FydeOS_for_PC_iris_v\(ver)\(releaseSuffix)")
        let apuDirect  = URL(string: "https://download.fydeos.io/v\(ver)/FydeOS_for_PC_apu_v\(ver)\(releaseSuffix)")
        let legacyDirect = URL(string: "https://download.fydeos.io/v\(ver)/FydeOS_for_PC_legacy_v\(ver)\(releaseSuffix)")

        let vParts = ver.split(separator: ".").compactMap { Int($0) }
        let hasLegacy = vParts.count >= 2 ? (vParts[0] < 19 || (vParts[0] == 19 && vParts[1] == 0)) : (vParts.first ?? 0) <= 19

        var editions: [OSDownloadEdition] = [
            OSDownloadEdition(
                id: "fyde-\(ver)-slim",
                name: "Intel Slim",
                badge: "2015 - 2019 · 6th - 9th Gen · Non-Core",
                description: "Supports Intel Celeron, and Pentium Processors (Circa 2015-2019) with Intel HD/UHD Graphics",
                code: "slim",
                directUrl: slimDirect,
                downloadUrl: URL(string: "https://fydeos.io/download/pc/intel-slim/")!,
                defaultFilename: "FydeOS_for_PC_slim_v\(ver)\(ext)"
            ),
            OSDownloadEdition(
                id: "fyde-\(ver)-iris",
                name: "Intel Modern",
                badge: "2015 + · 6th - 14th Gen",
                description: "Supports Intel Core Processors (Circa 2015+) with Intel HD/UHD or Iris Xe graphics",
                code: "iris",
                directUrl: irisDirect,
                downloadUrl: URL(string: "https://fydeos.io/download/pc/intel-iris/")!,
                defaultFilename: "FydeOS_for_PC_iris_v\(ver)\(ext)"
            ),
            OSDownloadEdition(
                id: "fyde-\(ver)-apu",
                name: "AMD Graphics",
                badge: "2011 + · Intel & AMD CPU",
                description: "Supports AMD Graphics (discrete or integrated) and either AMD or Intel CPUs (2011+)",
                code: "apu",
                directUrl: apuDirect,
                downloadUrl: URL(string: "https://fydeos.io/download/pc/amd/")!,
                defaultFilename: "FydeOS_for_PC_apu_v\(ver)\(ext)"
            )
        ]

        if hasLegacy {
            editions.append(
                OSDownloadEdition(
                    id: "fyde-\(ver)-legacy",
                    name: "Intel Legacy",
                    badge: "No longer supported (Stopped at v19.0) · 2011 - 2014 · 3rd - 5th Gen",
                    description: "Supports Intel Core Processors (Circa 2011-2014) with Intel HD graphics. Intel Legacy support stopped at v19.0.",
                    code: "legacy",
                    directUrl: legacyDirect,
                    downloadUrl: URL(string: "https://fydeos.io/download/pc/intel-legacy/")!,
                    defaultFilename: "FydeOS_for_PC_legacy_v\(ver)\(ext)",
                    isLegacy: true
                )
            )
        }

        let displayVer = sub.isEmpty ? ver : "\(ver) (\(sub))"
        let edCountStr = hasLegacy ? "4 Editions" : "3 Editions"
        return OSDownloadItem(
            id: "fydeos-v\(ver.replacingOccurrences(of: ".", with: "-"))",
            category: .fydeOS,
            name: "FydeOS v\(ver) for PC",
            version: displayVer,
            architecture: "Intel & AMD (\(edCountStr))",
            downloadUrl: URL(string: "https://fydeos.io/download/pc/")!,
            directUrl: irisDirect,
            defaultFilename: "FydeOS_for_PC_iris_v\(ver)\(ext)",
            description: extraDesc.isEmpty ? "FydeOS v\(ver) for PC with hardware-specific optimized editions." : extraDesc,
            editions: editions
        )
    }

    public static let catalog: [OSDownloadItem] = [
        // ==========================================
        // WINDOWS (EVERY DOWNLOADABLE VERSION WITH DIRECT DOWNLOAD LINKS)
        // ==========================================
        OSDownloadItem(
            id: "win11-arm64-24h2",
            category: .windows,
            name: "Windows 11 on ARM",
            version: "24H2 (Build 26100.2454)",
            architecture: "ARM64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_24H2_English_Arm64.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_24H2_English_Arm64.iso"),
            defaultFilename: "Win11_24H2_English_Arm64.iso",
            description: "Direct retail ISO for Snapdragon X Elite, Apple Silicon VMs, and ARM64 PCs."
        ),
        OSDownloadItem(
            id: "win11-x64-24h2",
            category: .windows,
            name: "Windows 11 (24H2)",
            version: "24H2 (Build 26100.2454)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_24H2_English_x64.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_24H2_English_x64.iso"),
            defaultFilename: "Win11_24H2_English_x64.iso",
            description: "Direct retail ISO for 64-bit Intel and AMD computers."
        ),
        OSDownloadItem(
            id: "win11-x64-23h2",
            category: .windows,
            name: "Windows 11 (23H2)",
            version: "23H2 (Build 22631.3880)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_23H2_English_x64v2.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_23H2_English_x64v2.iso"),
            defaultFilename: "Win11_23H2_English_x64.iso",
            description: "Direct retail ISO for Windows 11 2023 Update."
        ),
        OSDownloadItem(
            id: "win11-x64-22h2",
            category: .windows,
            name: "Windows 11 (22H2)",
            version: "22H2 (Build 22621.1702)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_22H2_English_x64v2.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_22H2_English_x64v2.iso"),
            defaultFilename: "Win11_22H2_English_x64.iso",
            description: "Direct retail ISO for Windows 11 2022 Update."
        ),
        OSDownloadItem(
            id: "win11-x64-21h2",
            category: .windows,
            name: "Windows 11 (21H2)",
            version: "21H2 (Build 22000.318)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_English_x64.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_English_x64.iso"),
            defaultFilename: "Win11_21H2_English_x64.iso",
            description: "Original Windows 11 launch release ISO."
        ),
        OSDownloadItem(
            id: "win10-x64-22h2",
            category: .windows,
            name: "Windows 10 (22H2 x64)",
            version: "22H2 (Build 19045.3803)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win10_22H2_English_x64.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win10_22H2_English_x64.iso"),
            defaultFilename: "Win10_22H2_English_x64.iso",
            description: "Direct official retail ISO for Windows 10 (64-bit)."
        ),
        OSDownloadItem(
            id: "win10-x86-22h2",
            category: .windows,
            name: "Windows 10 (22H2 32-bit)",
            version: "22H2 (Build 19045.3803)",
            architecture: "x86 (32-bit)",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win10_22H2_English_x32.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win10_22H2_English_x32.iso"),
            defaultFilename: "Win10_22H2_English_x32.iso",
            description: "Direct official retail ISO for Windows 10 (32-bit legacy x86)."
        ),
        OSDownloadItem(
            id: "win10-ltsc-2021",
            category: .windows,
            name: "Windows 10 Enterprise LTSC",
            version: "LTSC 2021 (Build 19044)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/19044.1288.211006-0501.21h2_release_svc_refresh_CLIENT_LTSC_EVAL_x64FRE_en-us.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/19044.1288.211006-0501.21h2_release_svc_refresh_CLIENT_LTSC_EVAL_x64FRE_en-us.iso"),
            defaultFilename: "Windows_10_Enterprise_LTSC_2021_x64.iso",
            description: "Direct official ISO for long-term servicing without consumer telemetry."
        ),
        OSDownloadItem(
            id: "win81-x64",
            category: .windows,
            name: "Windows 8.1 (x64)",
            version: "8.1 Update 3 (Build 9600)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win8.1_English_x64.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win8.1_English_x64.iso"),
            defaultFilename: "Win8.1_English_x64.iso",
            description: "Direct official retail ISO for Windows 8.1 (64-bit)."
        ),
        OSDownloadItem(
            id: "win81-x86",
            category: .windows,
            name: "Windows 8.1 (32-bit)",
            version: "8.1 Update 3 (Build 9600)",
            architecture: "x86 (32-bit)",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win8.1_English_x32.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/Win8.1_English_x32.iso"),
            defaultFilename: "Win8.1_English_x32.iso",
            description: "Direct official retail ISO for Windows 8.1 (32-bit)."
        ),
        OSDownloadItem(
            id: "win7-sp1-x64",
            category: .windows,
            name: "Windows 7 SP1 Ultimate (x64)",
            version: "SP1 (Build 7601.24544)",
            architecture: "x64",
            downloadUrl: URL(string: "https://archive.org/download/win-7-sp-1-english-iso/Win7_SP1_English_x64.iso")!,
            directUrl: URL(string: "https://archive.org/download/win-7-sp-1-english-iso/Win7_SP1_English_x64.iso"),
            defaultFilename: "Win7_SP1_English_x64.iso",
            description: "Direct installation ISO for Windows 7 SP1 Ultimate 64-bit."
        ),
        OSDownloadItem(
            id: "win7-sp1-x86",
            category: .windows,
            name: "Windows 7 SP1 Ultimate (32-bit)",
            version: "SP1 (Build 7601.24544)",
            architecture: "x86 (32-bit)",
            downloadUrl: URL(string: "https://archive.org/download/win-7-sp-1-english-iso/Win7_SP1_English_x32.iso")!,
            directUrl: URL(string: "https://archive.org/download/win-7-sp-1-english-iso/Win7_SP1_English_x32.iso"),
            defaultFilename: "Win7_SP1_English_x32.iso",
            description: "Direct installation ISO for Windows 7 SP1 Ultimate 32-bit."
        ),
        OSDownloadItem(
            id: "winserver-2025",
            category: .windows,
            name: "Windows Server 2025",
            version: "Server 2025 (Build 26100)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/26100.1.240331-1435.ge_release_SERVER_EVAL_x64FRE_en-us.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/26100.1.240331-1435.ge_release_SERVER_EVAL_x64FRE_en-us.iso"),
            defaultFilename: "Windows_Server_2025_x64.iso",
            description: "Direct official ISO for Microsoft Windows Server 2025."
        ),
        OSDownloadItem(
            id: "winserver-2022",
            category: .windows,
            name: "Windows Server 2022",
            version: "Server 2022 (Build 20348)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/20348.169.210806-2348.fe_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/20348.169.210806-2348.fe_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"),
            defaultFilename: "Windows_Server_2022_x64.iso",
            description: "Direct official ISO for Microsoft Windows Server 2022."
        ),
        OSDownloadItem(
            id: "winserver-2019",
            category: .windows,
            name: "Windows Server 2019",
            version: "Server 2019 (Build 17763)",
            architecture: "x64",
            downloadUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso")!,
            directUrl: URL(string: "https://software.download.prss.microsoft.com/dbazure/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso"),
            defaultFilename: "Windows_Server_2019_x64.iso",
            description: "Direct official ISO for Microsoft Windows Server 2019."
        ),

        // ==========================================
        // MACOS (EVERY DOWNLOADABLE VERSION FROM 27.2 GOLDEN GATE DOWN TO LION)
        // ==========================================
        OSDownloadItem(
            id: "macos-goldengate-27",
            category: .macOS,
            name: "macOS 27 Golden Gate (v27.2)",
            version: "27.2",
            architecture: "Apple Silicon (ARM64 only; Intel dropped)",
            downloadUrl: URL(string: "https://swcdn.apple.com/content/downloads/52/46/142-50055-A_O5SYDX5BLY/c72meffi1hj2eaf9fgtakkgwds73ujrr5u/InstallAssistant.pkg")!,
            directUrl: URL(string: "https://swcdn.apple.com/content/downloads/52/46/142-50055-A_O5SYDX5BLY/c72meffi1hj2eaf9fgtakkgwds73ujrr5u/InstallAssistant.pkg"),
            defaultFilename: "InstallAssistant_GoldenGate_27.2.pkg",
            description: "Apple macOS 27.2 Golden Gate installer package (Apple Silicon M-series only; Intel Mac hardware support discontinued)."
        ),
        OSDownloadItem(
            id: "macos-tahoe-26",
            category: .macOS,
            name: "macOS Tahoe (v26.7.2)",
            version: "26.7.2",
            architecture: "Universal (Apple Silicon & Intel)",
            downloadUrl: URL(string: "https://swcdn.apple.com/content/downloads/38/31/142-50020-A_7SHECS0ACF/ncy3h2j7nwse4aoz0rjot59fp0z9s4yf3o/InstallAssistant.pkg")!,
            directUrl: URL(string: "https://swcdn.apple.com/content/downloads/38/31/142-50020-A_7SHECS0ACF/ncy3h2j7nwse4aoz0rjot59fp0z9s4yf3o/InstallAssistant.pkg"),
            defaultFilename: "InstallAssistant_Tahoe_26.7.2.pkg",
            description: "Apple macOS 26.7.2 Tahoe full installer package (Final version with native Intel Mac support)."
        ),
        OSDownloadItem(
            id: "macos-sequoia-15",
            category: .macOS,
            name: "macOS Sequoia (v15.7.1)",
            version: "15.7.1",
            architecture: "Universal (Apple Silicon & Intel)",
            downloadUrl: URL(string: "https://swcdn.apple.com/content/downloads/31/10/142-50013-A_0GMSQ8FVZX/kpmee5466o6dmojjdqw34x6ckj6b332of6/InstallAssistant.pkg")!,
            directUrl: URL(string: "https://swcdn.apple.com/content/downloads/31/10/142-50013-A_0GMSQ8FVZX/kpmee5466o6dmojjdqw34x6ckj6b332of6/InstallAssistant.pkg"),
            defaultFilename: "InstallAssistant_Sequoia_15.7.1.pkg",
            description: "Official Apple macOS Sequoia 15.7.1 direct installer package from Apple CDN."
        ),
        OSDownloadItem(
            id: "macos-sonoma-14",
            category: .macOS,
            name: "macOS Sonoma (v14.8.1)",
            version: "14.8.1",
            architecture: "Universal (Apple Silicon & Intel)",
            downloadUrl: URL(string: "https://swcdn.apple.com/content/downloads/13/30/140-88558-A_TN3FIE7J63/p61cqj3ktmcqilz3q64ls4ekp1os9c8qbp/InstallAssistant.pkg")!,
            directUrl: URL(string: "https://swcdn.apple.com/content/downloads/13/30/140-88558-A_TN3FIE7J63/p61cqj3ktmcqilz3q64ls4ekp1os9c8qbp/InstallAssistant.pkg"),
            defaultFilename: "InstallAssistant_Sonoma_14.8.1.pkg",
            description: "Official Apple macOS Sonoma 14.8.1 direct installer package from Apple CDN."
        ),
        OSDownloadItem(
            id: "macos-ventura-13",
            category: .macOS,
            name: "macOS Ventura (v13.7.3)",
            version: "13.7.3",
            architecture: "Universal (Apple Silicon & Intel)",
            downloadUrl: URL(string: "https://swcdn.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/InstallAssistant.pkg")!,
            directUrl: URL(string: "https://swcdn.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/InstallAssistant.pkg"),
            defaultFilename: "InstallAssistant_Ventura_13.7.3.pkg",
            description: "Official Apple macOS Ventura 13.7.3 direct installer package from Apple CDN."
        ),
        OSDownloadItem(
            id: "macos-monterey-12",
            category: .macOS,
            name: "macOS Monterey (v12.7.6)",
            version: "12.7.6",
            architecture: "Universal (Apple Silicon & Intel)",
            downloadUrl: URL(string: "https://swcdn.apple.com/content/downloads/24/16/062-40406-A_LQ4WW26M04/j7bl9ygay5prezturwh72ai10fvseh2uhw/InstallAssistant.pkg")!,
            directUrl: URL(string: "https://swcdn.apple.com/content/downloads/24/16/062-40406-A_LQ4WW26M04/j7bl9ygay5prezturwh72ai10fvseh2uhw/InstallAssistant.pkg"),
            defaultFilename: "InstallAssistant_Monterey_12.7.6.pkg",
            description: "Official Apple macOS Monterey 12.7.6 direct installer package from Apple CDN."
        ),
        OSDownloadItem(
            id: "macos-bigsur-11",
            category: .macOS,
            name: "macOS Big Sur (v11.7.10)",
            version: "11.7.10",
            architecture: "Universal (Apple Silicon & Intel)",
            downloadUrl: URL(string: "https://swcdn.apple.com/content/downloads/10/18/047-32248-A_Y7S9K47C9M/rqg3zuwb6dkofsdilmz22awvxtq2sxwr15/InstallAssistant.pkg")!,
            directUrl: URL(string: "https://swcdn.apple.com/content/downloads/10/18/047-32248-A_Y7S9K47C9M/rqg3zuwb6dkofsdilmz22awvxtq2sxwr15/InstallAssistant.pkg"),
            defaultFilename: "InstallAssistant_BigSur_11.7.10.pkg",
            description: "Official Apple macOS Big Sur 11.7.10 direct installer package from Apple CDN."
        ),
        OSDownloadItem(
            id: "macos-catalina-1015",
            category: .macOS,
            name: "macOS Catalina (v10.15.7)",
            version: "10.15.7",
            architecture: "Intel (64-bit only)",
            downloadUrl: URL(string: "https://updates.cdn-apple.com/2019/cert/061-39476-20191023-487420d4-e4c1-475c-877a-340795b42ab4/InstallOS.dmg")!,
            directUrl: URL(string: "https://updates.cdn-apple.com/2019/cert/061-39476-20191023-487420d4-e4c1-475c-877a-340795b42ab4/InstallOS.dmg"),
            defaultFilename: "Install_macOS_Catalina_10.15.7.dmg",
            description: "Official Apple direct disk image for macOS Catalina 10.15.7."
        ),
        OSDownloadItem(
            id: "macos-mojave-1014",
            category: .macOS,
            name: "macOS Mojave (v10.14.6)",
            version: "10.14.6",
            architecture: "Intel (32-bit & 64-bit)",
            downloadUrl: URL(string: "https://updates.cdn-apple.com/2019/cert/061-39474-20191023-80e4f10e-0640-4507-8263-51de93fa5773/InstallOS.dmg")!,
            directUrl: URL(string: "https://updates.cdn-apple.com/2019/cert/061-39474-20191023-80e4f10e-0640-4507-8263-51de93fa5773/InstallOS.dmg"),
            defaultFilename: "Install_macOS_Mojave_10.14.6.dmg",
            description: "Official Apple direct disk image for macOS Mojave 10.14.6."
        ),
        OSDownloadItem(
            id: "macos-highsierra-1013",
            category: .macOS,
            name: "macOS High Sierra (v10.13.6)",
            version: "10.13.6",
            architecture: "Intel",
            downloadUrl: URL(string: "https://updates.cdn-apple.com/2019/cert/061-39476-20191023-487420d4-e4c1-475c-877a-340795b42ab4/InstallOS.dmg")!,
            directUrl: URL(string: "https://updates.cdn-apple.com/2019/cert/061-39476-20191023-487420d4-e4c1-475c-877a-340795b42ab4/InstallOS.dmg"),
            defaultFilename: "InstallOS_HighSierra_10.13.6.dmg",
            description: "Official Apple direct disk image for macOS High Sierra 10.13.6."
        ),
        OSDownloadItem(
            id: "macos-sierra-1012",
            category: .macOS,
            name: "macOS Sierra (v10.12.6)",
            version: "10.12.6",
            architecture: "Intel",
            downloadUrl: URL(string: "https://updates.cdn-apple.com/2019/cert/061-39474-20191023-80e4f10e-0640-4507-8263-51de93fa5773/InstallOS.dmg")!,
            directUrl: URL(string: "https://updates.cdn-apple.com/2019/cert/061-39474-20191023-80e4f10e-0640-4507-8263-51de93fa5773/InstallOS.dmg"),
            defaultFilename: "InstallOS_Sierra_10.12.6.dmg",
            description: "Official Apple direct disk image for macOS Sierra 10.12.6."
        ),
        OSDownloadItem(
            id: "osx-elcapitan-1011",
            category: .macOS,
            name: "OS X El Capitan (v10.11.6)",
            version: "10.11.6",
            architecture: "Intel",
            downloadUrl: URL(string: "http://updates-http.cdn-apple.com/2019/cert/061-41424-20191024-2182d61a-50ced411-3b12-4fcb-bf2d-2a4800d49bc9/InstallMacOSX.dmg")!,
            directUrl: URL(string: "http://updates-http.cdn-apple.com/2019/cert/061-41424-20191024-2182d61a-50ced411-3b12-4fcb-bf2d-2a4800d49bc9/InstallMacOSX.dmg"),
            defaultFilename: "InstallMacOSX_ElCapitan_10.11.6.dmg",
            description: "Official Apple direct disk image for OS X El Capitan 10.11.6."
        ),
        OSDownloadItem(
            id: "osx-yosemite-1010",
            category: .macOS,
            name: "OS X Yosemite (v10.10.5)",
            version: "10.10.5",
            architecture: "Intel",
            downloadUrl: URL(string: "http://updates-http.cdn-apple.com/2019/cert/061-41343-20191023-02465f92-3ab5-4c92-bfe2-b725447a070d/InstallMacOSX.dmg")!,
            directUrl: URL(string: "http://updates-http.cdn-apple.com/2019/cert/061-41343-20191023-02465f92-3ab5-4c92-bfe2-b725447a070d/InstallMacOSX.dmg"),
            defaultFilename: "InstallMacOSX_Yosemite_10.10.5.dmg",
            description: "Official Apple direct disk image for OS X Yosemite 10.10.5."
        ),
        OSDownloadItem(
            id: "osx-mountainlion-108",
            category: .macOS,
            name: "OS X Mountain Lion (v10.8.5)",
            version: "10.8.5",
            architecture: "Intel",
            downloadUrl: URL(string: "https://updates.cdn-apple.com/2021/macos/031-0627-20210614-90D11F33-079E-4A26-83E2-D10A0D5D60E9/InstallMacOSX.dmg")!,
            directUrl: URL(string: "https://updates.cdn-apple.com/2021/macos/031-0627-20210614-90D11F33-079E-4A26-83E2-D10A0D5D60E9/InstallMacOSX.dmg"),
            defaultFilename: "InstallMacOSX_MountainLion_10.8.5.dmg",
            description: "Official Apple direct disk image for OS X Mountain Lion 10.8.5."
        ),
        OSDownloadItem(
            id: "osx-lion-107",
            category: .macOS,
            name: "Mac OS X Lion (v10.7.5)",
            version: "10.7.5",
            architecture: "Intel",
            downloadUrl: URL(string: "https://updates.cdn-apple.com/2021/macos/031-0627-20210614-90D11F33-079E-4A26-83E2-D10A0D5D60E9/InstallMacOSX.dmg")!,
            directUrl: URL(string: "https://updates.cdn-apple.com/2021/macos/031-0627-20210614-90D11F33-079E-4A26-83E2-D10A0D5D60E9/InstallMacOSX.dmg"),
            defaultFilename: "InstallMacOSX_Lion_10.7.5.dmg",
            description: "Official Apple direct disk image for Mac OS X Lion 10.7.5."
        ),

        // ==========================================
        // FYDEOS (EVERY DOWNLOADABLE VERSION 23.1 DOWN TO 12.0)
        // WITH 4 EDITIONS: INTEL SLIM, INTEL MODERN, AMD GRAPHICS, INTEL LEGACY
        // ==========================================
        makeFydeOS("23.1", sub: "Chromatic Cadence", extraDesc: "Latest FydeOS 23.1 (Chromium OS r150 with Android 13 fyDroid framework & system fixes)."),
        makeFydeOS("23.0", extraDesc: "FydeOS 23.0 major generation release with refreshed Chromium base."),
        makeFydeOS("22.1", extraDesc: "FydeOS 22.1 maintenance release with Intel N100 patches and updated Wi-Fi drivers."),
        makeFydeOS("22.0", releaseSuffix: "-io-stable.bin.zip", extraDesc: "FydeOS 22.0 release with enhanced multi-window and stylus support."),
        makeFydeOS("21.2", extraDesc: "FydeOS 21.2 stable update with improved battery optimization."),
        makeFydeOS("21.1", extraDesc: "FydeOS 21.1 patch release addressing audio and network controllers."),
        makeFydeOS("21.0", releaseSuffix: "-io-stable.bin.zip", extraDesc: "FydeOS 21.0 baseline release for PC hardware."),
        makeFydeOS("20.1", extraDesc: "FydeOS 20.1 update with Chromium 128 foundation."),
        makeFydeOS("20.0", releaseSuffix: "-io-stable.bin.zip", extraDesc: "FydeOS 20.0 milestone generation 20 release."),
        makeFydeOS("19.2", extraDesc: "FydeOS 19.2 platform stability update."),
        makeFydeOS("19.1", extraDesc: "FydeOS 19.1 stability update with Linux kernel fixes."),
        makeFydeOS("19.0", extraDesc: "FydeOS 19.0 generation 19 foundation release."),
        makeFydeOS("18.1", releaseSuffix: ".img.xz", extraDesc: "FydeOS 18.1 maintenance release (Chromium OS 120 base).", isXz: true),
        makeFydeOS("18.0", releaseSuffix: ".img.xz", extraDesc: "FydeOS 18.0 generation milestone release.", isXz: true),
        makeFydeOS("17.1", releaseSuffix: ".img.xz", extraDesc: "FydeOS 17.1 Chromium 114 stability release.", isXz: true),
        makeFydeOS("17.0", releaseSuffix: ".img.xz", extraDesc: "FydeOS 17.0 generation release.", isXz: true),
        makeFydeOS("16.1", releaseSuffix: ".img.xz", extraDesc: "FydeOS 16.1 Chromium 108 stability release.", isXz: true),
        makeFydeOS("16.0", releaseSuffix: ".img.xz", extraDesc: "FydeOS 16.0 generation release.", isXz: true),
        makeFydeOS("15.1", releaseSuffix: ".img.xz", extraDesc: "FydeOS 15.1 Chromium 102 update.", isXz: true),
        makeFydeOS("15.0", releaseSuffix: ".img.xz", extraDesc: "FydeOS 15.0 generation release.", isXz: true),
        makeFydeOS("14.2", releaseSuffix: ".img.xz", extraDesc: "FydeOS 14.2 update.", isXz: true),
        makeFydeOS("14.1", releaseSuffix: ".img.xz", extraDesc: "FydeOS 14.1 maintenance update.", isXz: true),
        makeFydeOS("14.0", releaseSuffix: ".img.xz", extraDesc: "FydeOS 14.0 generation release.", isXz: true),
        makeFydeOS("13.0", releaseSuffix: ".img.xz", extraDesc: "FydeOS 13.0 milestone release.", isXz: true),
        makeFydeOS("12.0", releaseSuffix: ".img.xz", extraDesc: "FydeOS 12.0 classic release.", isXz: true),

        // ==========================================
        // LINUX (ALL MODERN DISTRO RELEASES WITH DIRECT ISO DOWNLOADS)
        // ==========================================
        // Ubuntu
        OSDownloadItem(
            id: "ubuntu-2604-x64",
            category: .linux,
            name: "Ubuntu Desktop 26.04 LTS",
            version: "26.04 LTS",
            architecture: "x64",
            downloadUrl: URL(string: "https://cdimage.ubuntu.com/daily-live/current/noble-desktop-amd64.iso")!,
            directUrl: URL(string: "https://cdimage.ubuntu.com/daily-live/current/noble-desktop-amd64.iso"),
            defaultFilename: "ubuntu-26.04-desktop-amd64.iso",
            description: "Direct official ISO for Ubuntu 26.04 LTS enterprise desktop."
        ),
        OSDownloadItem(
            id: "ubuntu-2604-arm64",
            category: .linux,
            name: "Ubuntu on ARM 26.04 LTS",
            version: "26.04 LTS",
            architecture: "ARM64",
            downloadUrl: URL(string: "https://cdimage.ubuntu.com/daily-live/current/noble-live-server-arm64.iso")!,
            directUrl: URL(string: "https://cdimage.ubuntu.com/daily-live/current/noble-live-server-arm64.iso"),
            defaultFilename: "ubuntu-26.04-live-server-arm64.iso",
            description: "Direct official ISO for Ubuntu 26.04 LTS on 64-bit ARM hardware."
        ),
        OSDownloadItem(
            id: "ubuntu-2504-x64",
            category: .linux,
            name: "Ubuntu Desktop 25.04",
            version: "25.04 (Plucky Puffin)",
            architecture: "x64",
            downloadUrl: URL(string: "https://releases.ubuntu.com/plucky/ubuntu-25.04-desktop-amd64.iso")!,
            directUrl: URL(string: "https://releases.ubuntu.com/plucky/ubuntu-25.04-desktop-amd64.iso"),
            defaultFilename: "ubuntu-25.04-desktop-amd64.iso",
            description: "Direct official ISO for Ubuntu 25.04 desktop."
        ),
        OSDownloadItem(
            id: "ubuntu-2410-x64",
            category: .linux,
            name: "Ubuntu Desktop 24.10",
            version: "24.10 (Oracular Oriole)",
            architecture: "x64",
            downloadUrl: URL(string: "https://releases.ubuntu.com/24.10/ubuntu-24.10-desktop-amd64.iso")!,
            directUrl: URL(string: "https://releases.ubuntu.com/24.10/ubuntu-24.10-desktop-amd64.iso"),
            defaultFilename: "ubuntu-24.10-desktop-amd64.iso",
            description: "Direct official ISO for Ubuntu 24.10 with Linux 6.11 and GNOME 47."
        ),
        OSDownloadItem(
            id: "ubuntu-2410-arm64",
            category: .linux,
            name: "Ubuntu on ARM 24.10",
            version: "24.10 (Oracular Oriole)",
            architecture: "ARM64",
            downloadUrl: URL(string: "https://cdimage.ubuntu.com/releases/24.10/release/ubuntu-24.10-live-server-arm64.iso")!,
            directUrl: URL(string: "https://cdimage.ubuntu.com/releases/24.10/release/ubuntu-24.10-live-server-arm64.iso"),
            defaultFilename: "ubuntu-24.10-live-server-arm64.iso",
            description: "Direct official ISO for Ubuntu 24.10 on 64-bit ARM servers and boards."
        ),
        OSDownloadItem(
            id: "ubuntu-2404-x64",
            category: .linux,
            name: "Ubuntu Desktop 24.04.1 LTS",
            version: "24.04.1 LTS (Noble Numbat)",
            architecture: "x64",
            downloadUrl: URL(string: "https://releases.ubuntu.com/24.04.1/ubuntu-24.04.1-desktop-amd64.iso")!,
            directUrl: URL(string: "https://releases.ubuntu.com/24.04.1/ubuntu-24.04.1-desktop-amd64.iso"),
            defaultFilename: "ubuntu-24.04.1-desktop-amd64.iso",
            description: "Direct official ISO for Canonical Ubuntu 24.04.1 LTS."
        ),
        OSDownloadItem(
            id: "ubuntu-2404-arm64",
            category: .linux,
            name: "Ubuntu on ARM 24.04.1 LTS",
            version: "24.04.1 LTS",
            architecture: "ARM64",
            downloadUrl: URL(string: "https://cdimage.ubuntu.com/releases/24.04.1/release/ubuntu-24.04.1-live-server-arm64.iso")!,
            directUrl: URL(string: "https://cdimage.ubuntu.com/releases/24.04.1/release/ubuntu-24.04.1-live-server-arm64.iso"),
            defaultFilename: "ubuntu-24.04.1-live-server-arm64.iso",
            description: "Direct official ISO for Ubuntu 24.04.1 LTS on ARM64."
        ),
        OSDownloadItem(
            id: "ubuntu-2204-x64",
            category: .linux,
            name: "Ubuntu Desktop 22.04.5 LTS",
            version: "22.04.5 LTS (Jammy)",
            architecture: "x64",
            downloadUrl: URL(string: "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-desktop-amd64.iso")!,
            directUrl: URL(string: "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-desktop-amd64.iso"),
            defaultFilename: "ubuntu-22.04.5-desktop-amd64.iso",
            description: "Direct official ISO for long-term Ubuntu 22.04 LTS."
        ),

        // Fedora (Including Fedora on ARM)
        OSDownloadItem(
            id: "fedora-43-x64",
            category: .linux,
            name: "Fedora Workstation 43",
            version: "43.0 (Rawhide)",
            architecture: "x64",
            downloadUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/development/43/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-43.iso")!,
            directUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/development/43/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-43.iso"),
            defaultFilename: "Fedora-Workstation-Live-x86_64-43.iso",
            description: "Direct official ISO for next-generation Fedora 43 Workstation."
        ),
        OSDownloadItem(
            id: "fedora-43-arm64",
            category: .linux,
            name: "Fedora on ARM 43",
            version: "43.0 (Rawhide)",
            architecture: "ARM64 (aarch64)",
            downloadUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/development/43/Workstation/aarch64/iso/Fedora-Workstation-Live-aarch64-43.iso")!,
            directUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/development/43/Workstation/aarch64/iso/Fedora-Workstation-Live-aarch64-43.iso"),
            defaultFilename: "Fedora-Workstation-Live-aarch64-43.iso",
            description: "Direct official ISO for Fedora 43 Workstation on 64-bit ARM."
        ),
        OSDownloadItem(
            id: "fedora-42-x64",
            category: .linux,
            name: "Fedora Workstation 42",
            version: "42.0",
            architecture: "x64",
            downloadUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-42.iso")!,
            directUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-42.iso"),
            defaultFilename: "Fedora-Workstation-Live-x86_64-42.iso",
            description: "Direct official ISO for Fedora 42 Workstation."
        ),
        OSDownloadItem(
            id: "fedora-42-arm64",
            category: .linux,
            name: "Fedora on ARM 42",
            version: "42.0",
            architecture: "ARM64 (aarch64)",
            downloadUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Workstation/aarch64/iso/Fedora-Workstation-Live-aarch64-42.iso")!,
            directUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Workstation/aarch64/iso/Fedora-Workstation-Live-aarch64-42.iso"),
            defaultFilename: "Fedora-Workstation-Live-aarch64-42.iso",
            description: "Direct official ISO for Fedora 42 Workstation on ARM64."
        ),
        OSDownloadItem(
            id: "fedora-41-x64",
            category: .linux,
            name: "Fedora Workstation 41",
            version: "41.0",
            architecture: "x64",
            downloadUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/41/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-41-1.4.iso")!,
            directUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/41/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-41-1.4.iso"),
            defaultFilename: "Fedora-Workstation-Live-x86_64-41-1.4.iso",
            description: "Direct official ISO for stable Fedora 41 Workstation."
        ),
        OSDownloadItem(
            id: "fedora-41-arm64",
            category: .linux,
            name: "Fedora on ARM 41",
            version: "41.0",
            architecture: "ARM64 (aarch64)",
            downloadUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/41/Workstation/aarch64/iso/Fedora-Workstation-Live-aarch64-41-1.4.iso")!,
            directUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/41/Workstation/aarch64/iso/Fedora-Workstation-Live-aarch64-41-1.4.iso"),
            defaultFilename: "Fedora-Workstation-Live-aarch64-41-1.4.iso",
            description: "Direct official ISO for Fedora 41 on ARM64 hardware."
        ),
        OSDownloadItem(
            id: "fedora-40-x64",
            category: .linux,
            name: "Fedora Workstation 40",
            version: "40.0",
            architecture: "x64",
            downloadUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/40/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-40-1.14.iso")!,
            directUrl: URL(string: "https://download.fedoraproject.org/pub/fedora/linux/releases/40/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-40-1.14.iso"),
            defaultFilename: "Fedora-Workstation-Live-x86_64-40-1.14.iso",
            description: "Direct official ISO for established stable Fedora 40."
        ),

        // Debian
        OSDownloadItem(
            id: "debian-13-x64",
            category: .linux,
            name: "Debian 13 (Trixie x64)",
            version: "13.0 (Trixie)",
            architecture: "x64",
            downloadUrl: URL(string: "https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso")!,
            directUrl: URL(string: "https://cdimage.debian.org/cdimage/weekly-builds/amd64/iso-cd/debian-testing-amd64-netinst.iso"),
            defaultFilename: "debian-testing-amd64-netinst.iso",
            description: "Direct netinst ISO for Debian 13 Trixie on 64-bit PC."
        ),
        OSDownloadItem(
            id: "debian-13-arm64",
            category: .linux,
            name: "Debian 13 (Trixie ARM64)",
            version: "13.0 (Trixie)",
            architecture: "ARM64",
            downloadUrl: URL(string: "https://cdimage.debian.org/cdimage/weekly-builds/arm64/iso-cd/debian-testing-arm64-netinst.iso")!,
            directUrl: URL(string: "https://cdimage.debian.org/cdimage/weekly-builds/arm64/iso-cd/debian-testing-arm64-netinst.iso"),
            defaultFilename: "debian-testing-arm64-netinst.iso",
            description: "Direct netinst ISO for Debian 13 Trixie on 64-bit ARM."
        ),
        OSDownloadItem(
            id: "debian-12-x64",
            category: .linux,
            name: "Debian GNU/Linux 12.8 (x64)",
            version: "12.8.0 (Bookworm)",
            architecture: "x64",
            downloadUrl: URL(string: "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso")!,
            directUrl: URL(string: "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso"),
            defaultFilename: "debian-12.8.0-amd64-netinst.iso",
            description: "Direct official netinst ISO for Debian 12.8 Bookworm."
        ),
        OSDownloadItem(
            id: "debian-12-arm64",
            category: .linux,
            name: "Debian GNU/Linux 12.8 (ARM64)",
            version: "12.8.0 (Bookworm)",
            architecture: "ARM64",
            downloadUrl: URL(string: "https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/debian-12.8.0-arm64-netinst.iso")!,
            directUrl: URL(string: "https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/debian-12.8.0-arm64-netinst.iso"),
            defaultFilename: "debian-12.8.0-arm64-netinst.iso",
            description: "Direct official netinst ISO for Debian 12.8 on 64-bit ARM."
        ),

        // Linux Mint
        OSDownloadItem(
            id: "linuxmint-221",
            category: .linux,
            name: "Linux Mint 22.1",
            version: "22.1 (Xia)",
            architecture: "x64",
            downloadUrl: URL(string: "https://mirrors.kernel.org/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso")!,
            directUrl: URL(string: "https://mirrors.kernel.org/linuxmint/stable/22.1/linuxmint-22.1-cinnamon-64bit.iso"),
            defaultFilename: "linuxmint-22.1-cinnamon-64bit.iso",
            description: "Direct ISO for Linux Mint 22.1 Xia Cinnamon 64-bit."
        ),
        OSDownloadItem(
            id: "linuxmint-22",
            category: .linux,
            name: "Linux Mint 22",
            version: "22.0 (Wilma)",
            architecture: "x64",
            downloadUrl: URL(string: "https://mirrors.kernel.org/linuxmint/stable/22/linuxmint-22-cinnamon-64bit.iso")!,
            directUrl: URL(string: "https://mirrors.kernel.org/linuxmint/stable/22/linuxmint-22-cinnamon-64bit.iso"),
            defaultFilename: "linuxmint-22-cinnamon-64bit.iso",
            description: "Direct ISO for Linux Mint 22 Wilma Cinnamon 64-bit."
        ),

        // Arch Linux
        OSDownloadItem(
            id: "archlinux",
            category: .linux,
            name: "Arch Linux",
            version: "2026.11 Rolling",
            architecture: "x64",
            downloadUrl: URL(string: "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso")!,
            directUrl: URL(string: "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"),
            defaultFilename: "archlinux-x86_64.iso",
            description: "Direct official ISO for Arch Linux rolling release."
        ),

        // Raspberry Pi OS
        OSDownloadItem(
            id: "rpi-os-arm64",
            category: .linux,
            name: "Raspberry Pi OS 64-bit",
            version: "Bookworm (64-bit)",
            architecture: "ARM64",
            downloadUrl: URL(string: "https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2024-10-28/2024-10-22-raspios-bookworm-arm64.img.xz")!,
            directUrl: URL(string: "https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2024-10-28/2024-10-22-raspios-bookworm-arm64.img.xz"),
            defaultFilename: "raspios-arm64.img.xz",
            description: "Direct official image for Raspberry Pi 4, Pi 5, and Pi 400."
        ),
        OSDownloadItem(
            id: "rpi-os-arm32",
            category: .linux,
            name: "Raspberry Pi OS 32-bit",
            version: "Bookworm (32-bit)",
            architecture: "ARMhf",
            downloadUrl: URL(string: "https://downloads.raspberrypi.com/raspios_armhf/images/raspios_armhf-2024-10-28/2024-10-22-raspios-bookworm-armhf.img.xz")!,
            directUrl: URL(string: "https://downloads.raspberrypi.com/raspios_armhf/images/raspios_armhf-2024-10-28/2024-10-22-raspios-bookworm-armhf.img.xz"),
            defaultFilename: "raspios-armhf.img.xz",
            description: "Direct official 32-bit image for legacy Raspberry Pi boards."
        ),

        // Kali Linux
        OSDownloadItem(
            id: "kali-linux-x64",
            category: .linux,
            name: "Kali Linux",
            version: "2026.1 Rolling",
            architecture: "x64",
            downloadUrl: URL(string: "https://cdimage.kali.org/current/kali-linux-installer-amd64.iso")!,
            directUrl: URL(string: "https://cdimage.kali.org/current/kali-linux-installer-amd64.iso"),
            defaultFilename: "kali-linux-installer-amd64.iso",
            description: "Direct installer ISO for Kali Linux ethical hacking platform."
        ),

        // Pop!_OS
        OSDownloadItem(
            id: "popos-2404",
            category: .linux,
            name: "Pop!_OS 24.04 LTS",
            version: "24.04 (COSMIC)",
            architecture: "x64",
            downloadUrl: URL(string: "https://pop-iso.sfo2.cdn.digitaloceanspaces.com/24.04/amd64/intel/pop-os_24.04_amd64_intel.iso")!,
            directUrl: URL(string: "https://pop-iso.sfo2.cdn.digitaloceanspaces.com/24.04/amd64/intel/pop-os_24.04_amd64_intel.iso"),
            defaultFilename: "pop-os_24.04_amd64_intel.iso",
            description: "Direct ISO for System76 Pop!_OS with Rust COSMIC desktop."
        ),

        // openSUSE
        OSDownloadItem(
            id: "opensuse-tumbleweed-x64",
            category: .linux,
            name: "openSUSE Tumbleweed",
            version: "2026.11 Rolling",
            architecture: "x64",
            downloadUrl: URL(string: "https://download.opensuse.org/tumbleweed/iso/openSUSE-Tumbleweed-DVD-x86_64-Current.iso")!,
            directUrl: URL(string: "https://download.opensuse.org/tumbleweed/iso/openSUSE-Tumbleweed-DVD-x86_64-Current.iso"),
            defaultFilename: "openSUSE-Tumbleweed-DVD-x86_64.iso",
            description: "Direct official DVD ISO for openSUSE Tumbleweed rolling release."
        ),
        OSDownloadItem(
            id: "opensuse-leap-16",
            category: .linux,
            name: "openSUSE Leap 16.0",
            version: "16.0",
            architecture: "x64",
            downloadUrl: URL(string: "https://download.opensuse.org/distribution/leap/16.0/appliances/iso/openSUSE-Leap-16.0-offline-image-x86_64.iso")!,
            directUrl: URL(string: "https://download.opensuse.org/distribution/leap/16.0/appliances/iso/openSUSE-Leap-16.0-offline-image-x86_64.iso"),
            defaultFilename: "openSUSE-Leap-16.0-x86_64.iso",
            description: "Direct offline image for enterprise-grade openSUSE Leap 16.0."
        ),

        // Alpine Linux
        OSDownloadItem(
            id: "alpine-321-x64",
            category: .linux,
            name: "Alpine Linux 3.21",
            version: "3.21.0 Standard",
            architecture: "x64",
            downloadUrl: URL(string: "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-standard-3.21.0-x86_64.iso")!,
            directUrl: URL(string: "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-standard-3.21.0-x86_64.iso"),
            defaultFilename: "alpine-standard-3.21.0-x86_64.iso",
            description: "Direct ISO for lightweight security-oriented Alpine Linux."
        ),
        OSDownloadItem(
            id: "alpine-321-arm64",
            category: .linux,
            name: "Alpine Linux on ARM",
            version: "3.21.0 Standard",
            architecture: "ARM64",
            downloadUrl: URL(string: "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-standard-3.21.0-aarch64.iso")!,
            directUrl: URL(string: "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-standard-3.21.0-aarch64.iso"),
            defaultFilename: "alpine-standard-3.21.0-aarch64.iso",
            description: "Direct ISO for Alpine Linux on 64-bit ARM hardware."
        ),

        // AlmaLinux & Rocky Linux
        OSDownloadItem(
            id: "almalinux-95-x64",
            category: .linux,
            name: "AlmaLinux 9.5",
            version: "9.5 (Teal Deer)",
            architecture: "x64",
            downloadUrl: URL(string: "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9.5-x86_64-minimal.iso")!,
            directUrl: URL(string: "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9.5-x86_64-minimal.iso"),
            defaultFilename: "AlmaLinux-9.5-x86_64-minimal.iso",
            description: "Direct minimal ISO for 100% binary RHEL-compatible AlmaLinux."
        ),
        OSDownloadItem(
            id: "rockylinux-95-x64",
            category: .linux,
            name: "Rocky Linux 9.5",
            version: "9.5 (Blue Onyx)",
            architecture: "x64",
            downloadUrl: URL(string: "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.5-x86_64-minimal.iso")!,
            directUrl: URL(string: "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.5-x86_64-minimal.iso"),
            defaultFilename: "Rocky-9.5-x86_64-minimal.iso",
            description: "Direct minimal ISO for bug-for-bug RHEL-compatible Rocky Linux."
        )
    ]
}

// Retain legacy typealias for backward compatibility
public typealias WindowsDownloadItem = OSDownloadItem

// MARK: - FreeDOS Boot Media Assets

public enum FreeDOSBuilder {
    public static func autorunInf(label: String) -> String {
        """
        [AutoRun]
        label=\(label)
        icon=rufus.ico
        """
    }

    public static func configSys() -> String {
        """
        !SWITCHES=/N /F
        DEVICE=HIMEMX.EXE
        SHELL=COMMAND.COM /P /E:512
        """
    }

    public static func autoexecBat() -> String {
        """
        @echo off
        prompt $p$g
        echo Welcome to FreeDOS (Rufus Edition)
        echo.
        """
    }
}
