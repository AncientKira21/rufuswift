import Darwin
import Foundation

let args = Array(CommandLine.arguments.dropFirst())

if let cmd = args.first {
    do {
        switch cmd {
        case "--write-image":
            print(try DiskWriter.privilegedWrite(Array(args.dropFirst())))
            exit(EXIT_SUCCESS)
        case "--format-disk":
            print(try DiskWriter.privilegedFormat(Array(args.dropFirst())))
            exit(EXIT_SUCCESS)
        case "--create-windows-installer":
            print(try DiskWriter.privilegedWindowsInstaller(Array(args.dropFirst())))
            exit(EXIT_SUCCESS)
        case "--create-macos-installer":
            print(try DiskWriter.privilegedMacOSInstaller(Array(args.dropFirst())))
            exit(EXIT_SUCCESS)
        case "--create-freedos":
            print(try DiskWriter.privilegedFreeDos(Array(args.dropFirst())))
            exit(EXIT_SUCCESS)
        case "--backup-drive":
            print(try DiskWriter.privilegedBackupDrive(Array(args.dropFirst())))
            exit(EXIT_SUCCESS)
        case "--check-bad-blocks":
            print(try DiskWriter.privilegedCheckBadBlocks(Array(args.dropFirst())))
            exit(EXIT_SUCCESS)
        default:
            break
        }
    } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(EXIT_FAILURE)
    }
}

RufusApp.main()
