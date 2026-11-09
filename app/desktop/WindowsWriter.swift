#if os(Windows)
import Foundation

enum PlatformWriter {
    private static let powershell = URL(fileURLWithPath:
        (ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows")
            + "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")

    private static func diskFilter(includeHardDrives: Bool) -> String {
        let busFilter = includeHardDrives ? "" : "$_.BusType -eq 'USB' -and"
        return """
        function EligibleDisks {
            Get-Disk | Where-Object {
                \(busFilter) !$_.IsBoot -and !$_.IsSystem -and
                !$_.IsReadOnly -and $_.UniqueId -and $_.Size -gt 0 -and
                $_.LogicalSectorSize -gt 0
            }
        }
        """
    }

    private static func encoded(_ script: String) -> String {
        Data(script.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8($0 >> 8)] }).base64EncodedString()
    }

    private static func run(_ script: String) throws -> Data {
        try runCommand(powershell, ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded("""
        $ErrorActionPreference = 'Stop'
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        \(script)
        """)])
    }

    static func checksums(_ url: URL) throws -> String {
        let path = Data(url.path.utf8).base64EncodedString()
        let output = try run("""
        $path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(path)'))
        if ($path -match '^/[A-Za-z]:/') { $path = $path.Substring(1) }
        $names = @{ MD5 = 'MD5'; SHA1 = 'SHA-1'; SHA256 = 'SHA-256'; SHA512 = 'SHA-512' }
        $stream = [IO.File]::Open($path, 'Open', 'Read', 'Read')
        try {
            foreach ($algorithm in 'MD5', 'SHA1', 'SHA256', 'SHA512') {
                $stream.Position = 0
                $hash = (Get-FileHash -InputStream $stream -Algorithm $algorithm).Hash.ToLowerInvariant()
                '{0}: {1}' -f $names[$algorithm], $hash
            }
        } finally {
            $stream.Dispose()
        }
        """)
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func expandGzip(_ source: URL, to destination: URL) throws {
        let input = Data(source.path.utf8).base64EncodedString()
        let output = Data(destination.path.utf8).base64EncodedString()
        _ = try run("""
        function DecodePath($encoded) {
            $path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
            if ($path -match '^/[A-Za-z]:/') { $path = $path.Substring(1) }
            return $path
        }
        $source = [IO.File]::OpenRead((DecodePath '\(input)'))
        try {
            if ($source.Length -lt 18) { throw 'The gzip image is incomplete.' }
            $source.Position = $source.Length - 4
            $trailer = [byte[]]::new(4)
            if ($source.Read($trailer, 0, 4) -ne 4) { throw 'The gzip trailer is incomplete.' }
            $expected = [BitConverter]::ToUInt32($trailer, 0)
            $source.Position = 0
            $gzip = [IO.Compression.GZipStream]::new($source, 'Decompress', $true)
            try {
                $target = [IO.File]::Open((DecodePath '\(output)'), 'CreateNew', 'Write')
                try {
                    $gzip.CopyTo($target)
                    if (($target.Length % 4294967296L) -ne $expected) {
                        throw 'The gzip image is incomplete or contains multiple members.'
                    }
                } finally { $target.Dispose() }
            } finally { $gzip.Dispose() }
        } finally { $source.Dispose() }
        """)
    }

    static func drives(includeHardDrives: Bool = false) throws -> [Drive] {
        let data = try run("""
        \(diskFilter(includeHardDrives: includeHardDrives))
        $drives = @(EligibleDisks | ForEach-Object {
            @{
                id = "$($_.UniqueId)"
                device = "$($_.Number)"
                name = "$($_.FriendlyName)"
                capacity = $_.Size
                blockSize = $_.LogicalSectorSize
            }
        })
        ConvertTo-Json -InputObject $drives -Compress
        """)
        return try JSONDecoder().decode([Drive].self, from: data)
    }

    static func write(_ image: DiskImage, to drive: Drive) throws {
        guard let number = UInt32(drive.device) else { throw WriterError("Invalid disk number.") }
        let id = Data(drive.id.utf8).base64EncodedString()
        let path = Data(image.url.path.utf8).base64EncodedString()
        _ = try run("""
        \(diskFilter(includeHardDrives: true))
        function SelectedDisk {
            $disk = @(EligibleDisks | Where-Object { $_.Number -eq \(number) -and $_.UniqueId -ceq $id })
            if ($disk.Count -ne 1) { throw 'The USB drive changed.' }
            return $disk[0]
        }

        Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        using Microsoft.Win32.SafeHandles;
        public static class RufusDisk {
            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            public static extern SafeFileHandle CreateFile(string name, uint access,
                uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        }
        '@
        $id = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(id)'))
        $path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(path)'))
        if ($path -match '^/[A-Za-z]:/') { $path = $path.Substring(1) }
        $disk = SelectedDisk
        $source = [IO.File]::Open($path, 'Open', 'Read', 'Read')
        try {
            $streamStart = 0L
            $streamLen = $source.Length

            # Check if this is an Apple installer .pkg (XAR archive with embedded SharedSupport.dmg)
            $magic = [byte[]]::new(4)
            if ($source.Read($magic, 0, 4) -eq 4 -and $magic[0] -eq 0x78 -and $magic[1] -eq 0x61 -and $magic[2] -eq 0x72 -and $magic[3] -eq 0x21) {
                $hdr = [byte[]]::new(24)
                $source.Read($hdr, 0, 24)
                $hdrLen = ([int]$hdr[0] -shl 8) -bor [int]$hdr[1]
                $tocCLen = 0L
                for ($i = 4; $i -lt 12; $i++) { $tocCLen = ($tocCLen -shl 8) -bor [int64]$hdr[$i] }
                $heapOffset = [int64]$hdrLen + $tocCLen

                $source.Position = [int64]$hdrLen
                $compToc = [byte[]]::new($tocCLen)
                $source.Read($compToc, 0, [int]$tocCLen)

                $ms = [IO.MemoryStream]::new($compToc)
                if ($compToc.Length -gt 2) {
                    $ms.Position = 2
                    $deflate = [IO.Compression.DeflateStream]::new($ms, [IO.Compression.CompressionMode]::Decompress)
                    $sr = [IO.StreamReader]::new($deflate, [Text.Encoding]::UTF8)
                    $tocXml = $sr.ReadToEnd()
                    $sr.Dispose()
                    if ($tocXml -match '<name>SharedSupport.dmg</name>') {
                        $idx = $tocXml.IndexOf('<name>SharedSupport.dmg</name>')
                        $prefix = $tocXml.Substring(0, $idx)
                        $lastData = $prefix.LastIndexOf('<data>')
                        if ($lastData -ge 0) {
                            $dataXml = $prefix.Substring($lastData)
                            $offM = [regex]::Match($dataXml, '<offset>(\\d+)</offset>')
                            $lenM = [regex]::Match($dataXml, '<size>(\\d+)</size>')
                            if ($offM.Success -and $lenM.Success) {
                                $streamStart = $heapOffset + [int64]$offM.Groups[1].Value
                                $streamLen = [int64]$lenM.Groups[1].Value
                            }
                        }
                    }
                }
            }

            if ($streamLen -gt $disk.Size) { throw 'The image does not fit on the selected USB drive.' }
            if (!$disk.IsOffline) { $disk | Set-Disk -IsOffline $true }
            $handle = [RufusDisk]::CreateFile('\\\\.\\PhysicalDrive\(number)',
                [uint32]1073741824, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
            if ($handle.IsInvalid) { throw 'Could not open the offline USB drive.' }
            $dest = [IO.FileStream]::new($handle, [IO.FileAccess]::Write)
            try {
                $source.Position = $streamStart
                $bufSize = [int](1048576 - (1048576 % $disk.LogicalSectorSize))
                $buffer = [byte[]]::new($bufSize)
                $remaining = $streamLen
                while ($remaining -gt 0) {
                    $toRead = [int][Math]::Min([int64]$bufSize, $remaining)
                    $read = $source.Read($buffer, 0, $toRead)
                    if ($read -le 0) { break }
                    $padded = $read
                    if (($padded % $disk.LogicalSectorSize) -ne 0) {
                        $padded = [int](($read + $disk.LogicalSectorSize - 1) / $disk.LogicalSectorSize) * $disk.LogicalSectorSize
                        [Array]::Clear($buffer, $read, $padded - $read)
                    }
                    $dest.Write($buffer, 0, $padded)
                    $remaining -= $read
                }
                $dest.Flush($true)
            } finally { $dest.Dispose() }
        } finally {
            $source.Dispose()
            $disk | Set-Disk -IsOffline $false
        }
        """)
    }

    static func format(_ drive: Drive, config: RufusWorkflowConfig) throws {
        guard let number = UInt32(drive.device) else { throw WriterError("Invalid disk number.") }
        let fs = config.fileSystem.shortName
        let style = config.partitionScheme == .gpt ? "GPT" : "MBR"
        let label = config.volumeLabel
        _ = try run("""
        Clear-Disk -Number \(number) -RemoveData -RemoveOEM -Confirm:$false
        Initialize-Disk -Number \(number) -PartitionStyle \(style)
        $part = New-Partition -DiskNumber \(number) -UseMaximumSize -AssignDriveLetter
        Format-Volume -Partition $part -FileSystem \(fs) -NewFileSystemLabel '\(label)' -Confirm:$false
        """)
    }

    static func createWindowsInstaller(_ image: DiskImage, to drive: Drive, config: RufusWorkflowConfig) throws {
        guard let number = UInt32(drive.device) else { throw WriterError("Invalid disk number.") }
        let isoPath = Data(image.url.path.utf8).base64EncodedString()
        let style = config.partitionScheme == .gpt ? "GPT" : "MBR"
        let label = config.volumeLabel
        let unattendXml = Data(config.wue.generateUnattendXml().utf8).base64EncodedString()

        _ = try run("""
        $isoPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(isoPath)'))
        if ($isoPath -match '^/[A-Za-z]:/') { $isoPath = $isoPath.Substring(1) }
        $unattend = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(unattendXml)'))

        Clear-Disk -Number \(number) -RemoveData -RemoveOEM -Confirm:$false
        Initialize-Disk -Number \(number) -PartitionStyle \(style)
        $part = New-Partition -DiskNumber \(number) -UseMaximumSize -AssignDriveLetter
        $vol = Format-Volume -Partition $part -FileSystem 'exFAT' -NewFileSystemLabel '\(label)' -Confirm:$false
        $targetLetter = $vol.DriveLetter + ':'

        $mount = Mount-DiskImage -ImagePath $isoPath -PassThru
        try {
            $isoDrive = ($mount | Get-Volume).DriveLetter + ':\\'
            Copy-Item -Path ($isoDrive + '*') -Destination ($targetLetter + '\\') -Recurse -Force
            $panther = Join-Path $targetLetter 'sources\\$OEM$\\$$\\Panther'
            New-Item -ItemType Directory -Path $panther -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $panther 'unattend.xml'), $unattend)
            [IO.File]::WriteAllText((Join-Path $targetLetter 'AutoUnattend.xml'), $unattend)
        } finally {
            Dismount-DiskImage -ImagePath $isoPath
        }
        """)
    }

    static func backup(_ drive: Drive, to destination: URL) throws {
        guard let number = UInt32(drive.device) else { throw WriterError("Invalid disk number.") }
        let outPath = Data(destination.path.utf8).base64EncodedString()
        _ = try run("""
        $out = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('\(outPath)'))
        if ($out -match '^/[A-Za-z]:/') { $out = $out.Substring(1) }

        Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        using Microsoft.Win32.SafeHandles;
        public static class RufusDiskReader {
            [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            public static extern SafeFileHandle CreateFile(string name, uint access,
                uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        }
        '@
        $handle = [RufusDiskReader]::CreateFile('\\\\.\\PhysicalDrive\(number)',
            [uint32]2147483648, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
        if ($handle.IsInvalid) { throw 'Could not open physical drive for reading.' }
        $src = [IO.FileStream]::new($handle, [IO.FileAccess]::Read)
        $dst = [IO.File]::Open($out, 'Create', 'Write')
        try {
            $src.CopyTo($dst, 4194304)
        } finally {
            $src.Dispose()
            $dst.Dispose()
        }
        """)
    }

    static func checkBadBlocks(_ drive: Drive, passes: Int) throws {
        guard let number = UInt32(drive.device) else { throw WriterError("Invalid disk number.") }
        _ = try run("""
        $disk = Get-Disk -Number \(number)
        $stream = [IO.File]::Open('\\\\.\\PhysicalDrive\(number)', 'Open', 'Read', 'Read')
        try {
            $buffer = [byte[]]::new(65536)
            $total = 0L
            while ($total -lt $disk.Size) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $total += $read
            }
        } finally {
            $stream.Dispose()
        }
        """)
    }
}
#endif
