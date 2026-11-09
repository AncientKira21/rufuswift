import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 14) {
                    Image(systemName: "externaldrive.badge.bolt")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RufuSwift").font(.title.bold())
                        Text("The Reliable Multi-Platform USB Formatting & Bootable Drive Utility")
                            .foregroundStyle(.secondary)
                        Text("Version 4.6 · Native Swift Edition").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Divider()

                // Credits Section
                GroupBox("Credits & Acknowledgements") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Author & Lead Developer").font(.headline)
                            Text("Ancient Kira").font(.subheadline.weight(.semibold))
                            Text("Swift architecture, native macOS AppKit/SwiftUI interface, SwiftCrossUI desktop port, Linux & Windows writers, and Android SCSI/BOT implementation.")
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Original Rufus Creator").font(.headline)
                            Text("Pete Batard / Akeo Consulting (https://rufus.ie)")
                                .font(.subheadline.weight(.semibold))
                            Text("Creator of the original, industry-standard Rufus utility for Windows. Immense gratitude to Pete Batard for pioneering work on boot media creation, BIOS/UEFI compatibility algorithms, and MBR synthesis.")
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Upstream Projects & Open-Source Libraries").font(.headline)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• FreeDOS Project — Jim Hall and the FreeDOS contributors (Kernel & boot binaries)")
                                Text("• e2fsprogs — Theodore Ts'o (ext2, ext3, and ext4 filesystem drivers & mke2fs)")
                                Text("• wimlib — Eric Biggers (WIM extraction, compression & Windows deployment)")
                                Text("• Syslinux / ISOLINUX — H. Peter Anvin and contributors (hybrid bootloader)")
                                Text("• GRUB & GRUB 2 — Free Software Foundation (multiboot specification)")
                                Text("• libarchive & bsdtar — Tim Kientzle and the NetBSD / libarchive team")
                                Text("• XZ Data Compression / liblzma — Lasse Collin and Igor Pavlov (LZMA SDK)")
                                Text("• FydeOS & ChromiumOS — Fyde Innovations & the open-source Chromium project")
                                Text("• Microsoft Windows ADK — Windows Assessment and Deployment Kit (unattend XML engine)")
                                Text("• OS Distributions — Canonical (Ubuntu), Red Hat & Fedora Project, Debian Project, Linux Mint Team, Arch Linux, Raspberry Pi Foundation, System76 (Pop!_OS), SUSE / openSUSE, Alpine Linux, AlmaLinux, Rocky Linux, Tails Project, and Apple Inc.")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("License").font(.headline)
                            Text("GNU General Public License v3.0 (GPLv3). Free software: you can redistribute it and/or modify it under the terms of the GPLv3.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                // Features Overview
                GroupBox("Key Capabilities") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("• Format USB drives to FAT32, NTFS, exFAT, ext4, and Mac OS Extended (Journaled)")
                        Text("• Create Windows installation drives with UEFI / BIOS support (ARM64 and x64)")
                        Text("• Windows 11 User Experience customizations (Bypass TPM 2.0, Secure Boot, RAM, MSA, BitLocker)")
                        Text("• Create Windows To Go portable drives")
                        Text("• Create FreeDOS bootable drives")
                        Text("• Raw disk imaging (DD) and compressed image writing (.gz and .xz)")
                        Text("• Flash Windows ARM, macOS installers (through Golden Gate), FydeOS (v19–v23), and Linux")
                        Text("• Linux persistent storage support (casper-rw / persistence)")
                        Text("• Sector-by-sector USB drive backup to raw image (.img)")
                        Text("• Surface bad blocks testing & fake flash drive detection")
                        Text("• Checksum verification (MD5, SHA-1, SHA-256, SHA-512)")
                        Text("• Official OS download catalog covering Windows, macOS, FydeOS, and modern Linux distros")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
        .frame(width: 570, alignment: .leading)
    }
}

// MARK: - Checksums View
