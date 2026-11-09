package org.rufus.swift;

import android.app.*;
import android.content.*;
import android.database.Cursor;
import android.hardware.usb.*;
import android.net.Uri;
import android.os.*;
import android.os.storage.*;
import android.provider.OpenableColumns;
import android.view.View;
import android.view.WindowInsets;
import android.widget.*;
import java.io.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.GZIPInputStream;
import java.util.zip.InflaterInputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class MainActivity extends Activity {
    private static final String USB_PERMISSION = "org.rufus.swift.USB_PERMISSION";
    private UsbManager usb;
    private Spinner driveList, bootList;
    private TextView imageLabel, status;
    private Button choose, refresh, startAction, backup, badBlocks, checksums, download;
    private final List<UsbDevice> drives = new ArrayList<>();
    private Uri image;
    private String imageName;
    private UsbDevice pendingDrive;
    private String pendingAction = "write";
    private boolean busy;
    private boolean pendingAutoFlash = false;
    private File autoDeleteFile = null;

    static final class CatalogEdition {
        final String name, badge, desc, code, directUrl, pageUrl, filename;
        final boolean isLegacy;
        CatalogEdition(String name, String badge, String desc, String code, String directUrl, String pageUrl, String filename, boolean isLegacy) {
            this.name = name; this.badge = badge; this.desc = desc; this.code = code;
            this.directUrl = directUrl; this.pageUrl = pageUrl; this.filename = filename; this.isLegacy = isLegacy;
        }
    }

    static final class CatalogEntry {
        final String name, version, arch, directUrl, pageUrl, filename, desc;
        final List<CatalogEdition> editions;
        CatalogEntry(String name, String version, String arch, String directUrl, String pageUrl, String filename, String desc) {
            this(name, version, arch, directUrl, pageUrl, filename, desc, null);
        }
        CatalogEntry(String name, String version, String arch, String directUrl, String pageUrl, String filename, String desc, List<CatalogEdition> editions) {
            this.name = name; this.version = version; this.arch = arch;
            this.directUrl = directUrl; this.pageUrl = pageUrl;
            this.filename = filename; this.desc = desc; this.editions = editions;
        }
    }

    private static CatalogEntry makeFydeOS(String ver, String sub, String suffix, boolean isXz) {
        String ext = isXz ? ".img.xz" : (suffix.startsWith("-") ? suffix : ".bin.zip");
        String slimDirect = "https://download.fydeos.io/v" + ver + "/FydeOS_for_PC_slim_v" + ver + suffix;
        String irisDirect = "https://download.fydeos.io/v" + ver + "/FydeOS_for_PC_iris_v" + ver + suffix;
        String apuDirect  = "https://download.fydeos.io/v" + ver + "/FydeOS_for_PC_apu_v" + ver + suffix;
        String legacyDirect = "https://download.fydeos.io/v" + ver + "/FydeOS_for_PC_legacy_v" + ver + suffix;

        String[] parts = ver.split("\\.");
        int majorVer = Integer.parseInt(parts[0]);
        int minorVer = parts.length > 1 ? Integer.parseInt(parts[1]) : 0;
        boolean hasLegacy = (majorVer < 19 || (majorVer == 19 && minorVer == 0));

        List<CatalogEdition> eds = new ArrayList<>(Arrays.asList(
            new CatalogEdition("Intel Slim", "2015 - 2019 · 6th - 9th Gen · Non-Core",
                "Supports Intel Celeron, and Pentium Processors (Circa 2015-2019) with Intel HD/UHD Graphics",
                "slim", slimDirect, "https://fydeos.io/download/pc/intel-slim/", "FydeOS_for_PC_slim_v" + ver + ext, false),
            new CatalogEdition("Intel Modern", "2015 + · 6th - 14th Gen",
                "Supports Intel Core Processors (Circa 2015+) with Intel HD/UHD or Iris Xe graphics",
                "iris", irisDirect, "https://fydeos.io/download/pc/intel-iris/", "FydeOS_for_PC_iris_v" + ver + ext, false),
            new CatalogEdition("AMD Graphics", "2011 + · Intel & AMD CPU",
                "Supports AMD Graphics (discrete or integrated) and either AMD or Intel CPUs (2011+)",
                "apu", apuDirect, "https://fydeos.io/download/pc/amd/", "FydeOS_for_PC_apu_v" + ver + ext, false)
        ));

        if (hasLegacy) {
            eds.add(new CatalogEdition("Intel Legacy", "No longer supported (Stopped at v19.0) · 2011 - 2014 · 3rd - 5th Gen",
                "Supports Intel Core Processors (Circa 2011-2014) with Intel HD graphics. Intel Legacy support stopped at v19.0.",
                "legacy", legacyDirect, "https://fydeos.io/download/pc/intel-legacy/", "FydeOS_for_PC_legacy_v" + ver + ext, true));
        }

        String displayVer = sub.isEmpty() ? ver : ver + " (" + sub + ")";
        String edCount = hasLegacy ? "4 Editions" : "3 Editions";
        return new CatalogEntry("FydeOS v" + ver + " for PC", displayVer, "Intel & AMD (" + edCount + ")",
            irisDirect, "https://fydeos.io/download/pc/", "FydeOS_for_PC_iris_v" + ver + ext,
            "FydeOS v" + ver + " with " + edCount + " tailored for your PC hardware.", eds);
    }

    private static final List<CatalogEntry> CATALOG = Arrays.asList(
        new CatalogEntry("Windows 11 (v25H2)", "25H2", "x64",
            "https://software.download.prss.microsoft.com/dbazure/Win11_25H2_English_x64.iso",
            "https://www.microsoft.com/software-download/windows11",
            "Win11_25H2_English_x64.iso", "Official Windows 11 25H2 full multi-edition installation media."),
        new CatalogEntry("Windows 11 on ARM (v25H2)", "25H2", "ARM64",
            "https://software.download.prss.microsoft.com/dbazure/Win11_25H2_Arm64_English.iso",
            "https://www.microsoft.com/software-download/windows11arm64",
            "Win11_25H2_Arm64_English.iso", "Windows 11 25H2 for ARM64 Snapdragon X Elite & WoA devices."),
        new CatalogEntry("Windows 10 (v22H2)", "22H2", "x64",
            "https://software.download.prss.microsoft.com/dbazure/Win10_22H2_English_x64.iso",
            "https://www.microsoft.com/software-download/windows10ISO",
            "Win10_22H2_English_x64.iso", "Official Windows 10 22H2 Home/Pro direct ISO installer."),
        new CatalogEntry("macOS 27 Golden Gate (v27.2)", "27.2", "Apple Silicon (ARM64)",
            "https://swcdn.apple.com/content/downloads/52/46/142-50055-A_O5SYDX5BLY/c72meffi1hj2eaf9fgtakkgwds73ujrr5u/InstallAssistant.pkg",
            "https://support.apple.com/en-us/102662",
            "InstallAssistant_GoldenGate_27.2.pkg", "Apple macOS 27.2 Golden Gate installer package (Apple Silicon M-series only)."),
        new CatalogEntry("macOS Tahoe (v26.7.2)", "26.7.2", "Universal (Apple Silicon & Intel)",
            "https://swcdn.apple.com/content/downloads/38/31/142-50020-A_7SHECS0ACF/ncy3h2j7nwse4aoz0rjot59fp0z9s4yf3o/InstallAssistant.pkg",
            "https://support.apple.com/en-us/102662",
            "InstallAssistant_Tahoe_26.7.2.pkg", "Apple macOS 26.7.2 Tahoe full installer package."),

        // FYDEOS (EVERY DOWNLOADABLE VERSION 23.1 DOWN TO 12.0 WITH 4 EDITIONS)
        makeFydeOS("23.1", "Chromatic Cadence", "-io.bin.zip", false),
        makeFydeOS("23.0", "", "-io.bin.zip", false),
        makeFydeOS("22.1", "", "-io.bin.zip", false),
        makeFydeOS("22.0", "", "-io-stable.bin.zip", false),
        makeFydeOS("21.2", "", "-io.bin.zip", false),
        makeFydeOS("21.1", "", "-io.bin.zip", false),
        makeFydeOS("21.0", "", "-io-stable.bin.zip", false),
        makeFydeOS("20.1", "", "-io.bin.zip", false),
        makeFydeOS("20.0", "", "-io-stable.bin.zip", false),
        makeFydeOS("19.2", "", "-io.bin.zip", false),
        makeFydeOS("19.1", "", "-io.bin.zip", false),
        makeFydeOS("19.0", "", "-io.bin.zip", false),
        makeFydeOS("18.1", "", ".img.xz", true),
        makeFydeOS("18.0", "", ".img.xz", true),
        makeFydeOS("17.1", "", ".img.xz", true),
        makeFydeOS("17.0", "", ".img.xz", true),
        makeFydeOS("16.1", "", ".img.xz", true),
        makeFydeOS("16.0", "", ".img.xz", true),
        makeFydeOS("15.1", "", ".img.xz", true),
        makeFydeOS("15.0", "", ".img.xz", true),
        makeFydeOS("14.2", "", ".img.xz", true),
        makeFydeOS("14.1", "", ".img.xz", true),
        makeFydeOS("14.0", "", ".img.xz", true),
        makeFydeOS("13.0", "", ".img.xz", true),
        makeFydeOS("12.0", "", ".img.xz", true),

        new CatalogEntry("Ubuntu 26.04 LTS Desktop", "26.04", "x64",
            "https://releases.ubuntu.com/noble/ubuntu-24.04.2-desktop-amd64.iso",
            "https://ubuntu.com/download/desktop",
            "ubuntu-desktop-amd64.iso", "Ubuntu Desktop long-term support release with GNOME desktop."),
        new CatalogEntry("Fedora 43 Workstation", "43", "x64",
            "https://download.fedoraproject.org/pub/fedora/linux/releases/41/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-41-1.4.iso",
            "https://fedoraproject.org/workstation/download",
            "Fedora-Workstation-Live-x86_64.iso", "Fedora Workstation live media with pure GNOME and Wayland."),
        new CatalogEntry("Debian 13 'Trixie'", "13.0", "x64",
            "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso",
            "https://www.debian.org/distrib/",
            "debian-amd64-netinst.iso", "Official Debian GNU/Linux netinst installer image."),
        new CatalogEntry("Linux Mint 22 'Wilma'", "22.0", "x64",
            "https://mirrors.kernel.org/linuxmint/stable/22/linuxmint-22-cinnamon-64bit.iso",
            "https://linuxmint.com/download.php",
            "linuxmint-22-cinnamon-64bit.iso", "Linux Mint with modern Cinnamon desktop environment."),
        new CatalogEntry("Arch Linux", "Rolling", "x64",
            "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso",
            "https://archlinux.org/download/",
            "archlinux-x86_64.iso", "Arch Linux rolling release live ISO with archinstall helper.")
    );

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        usb = getSystemService(UsbManager.class);
        LinearLayout root = new LinearLayout(this);
        LinearLayout sidebar = column();
        root.addView(sidebar, new LinearLayout.LayoutParams(dp(130), -1));
        FrameLayout detail = new FrameLayout(this);
        root.addView(detail, new LinearLayout.LayoutParams(0, -1, 1));

        // Screen 1: Drive Creator
        LinearLayout writer = column();
        ScrollView writerScroll = new ScrollView(this);
        writerScroll.addView(writer);
        detail.addView(writerScroll);

        // Screen 2: Download OS Catalog
        LinearLayout catalogLayout = column();
        ScrollView catalogScroll = new ScrollView(this);
        catalogScroll.addView(catalogLayout);
        detail.addView(catalogScroll);
        catalogScroll.setVisibility(View.GONE);

        // Screen 3: About Rufus
        LinearLayout about = column();
        about.addView(text("RufuSwift for Android & ChromeOS", 24));
        about.addView(text("The Reliable Multi-Platform USB Formatting Utility\n\n"
            + "• FAT32 USB Drive Formatting\n"
            + "• Raw & Compressed Disk Image / Hybrid ISO Writing (ISO, IMG, BIN, DMG, GZ, ZIP)\n"
            + "• FydeOS .bin.zip Direct Decompression & USB Flashing\n"
            + "• FreeDOS Bootable Drive Creation\n"
            + "• Full USB Drive Backup / Image Dump\n"
            + "• Bad Blocks Surface Testing & Fake Drive Detection\n"
            + "• Cryptographic Checksums (MD5, SHA-1, SHA-256, SHA-512)\n"
            + "• Direct OS Downloads (Windows, macOS, FydeOS, Linux)\n\n"
            + "Lead Developer: Ancient Kira\n"
            + "Original Rufus Creator: Pete Batard / Akeo Consulting (rufus.ie)", 16));
        detail.addView(about);
        about.setVisibility(View.GONE);

        sidebar.addView(button("Drive Creator", () -> {
            about.setVisibility(View.GONE);
            catalogScroll.setVisibility(View.GONE);
            writerScroll.setVisibility(View.VISIBLE);
        }));
        sidebar.addView(button("Download OS", () -> {
            about.setVisibility(View.GONE);
            writerScroll.setVisibility(View.GONE);
            catalogScroll.setVisibility(View.VISIBLE);
        }));
        sidebar.addView(button("About Rufus", () -> {
            writerScroll.setVisibility(View.GONE);
            catalogScroll.setVisibility(View.GONE);
            about.setVisibility(View.VISIBLE);
        }));

        // Build Drive Creator
        writer.addView(text("RufuSwift - Drive Creator", 24));
        writer.addView(text("Device", 18));
        driveList = new Spinner(this);
        writer.addView(driveList);
        refresh = button("Refresh USB Drives", this::refreshDrives);
        writer.addView(refresh);

        writer.addView(text("Boot selection", 18));
        bootList = new Spinner(this);
        bootList.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
            new String[] {"Disk or ISO image", "Non bootable (Format FAT32)", "FreeDOS Boot Drive"}));
        bootList.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                choose.setVisibility(position == 0 ? View.VISIBLE : View.GONE);
                imageLabel.setVisibility(position == 0 ? View.VISIBLE : View.GONE);
                setBusy(busy);
            }
            @Override public void onNothingSelected(AdapterView<?> parent) {}
        });
        writer.addView(bootList);

        imageLabel = text("No image selected", 15);
        writer.addView(imageLabel);
        choose = button("Choose Image…", () -> {
            Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*")
                .addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(picker, 1);
        });
        writer.addView(choose);

        download = button("Browse OS Catalog…", () -> {
            about.setVisibility(View.GONE);
            writerScroll.setVisibility(View.GONE);
            catalogScroll.setVisibility(View.VISIBLE);
        });
        writer.addView(download);

        checksums = button("Calculate Checksums…", () -> {
            Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*")
                .addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(picker, 2);
        });
        writer.addView(checksums);

        startAction = button("START", this::confirmAction);
        writer.addView(startAction);

        backup = button("Backup Drive to Image", () -> confirmDirect("backup"));
        writer.addView(backup);

        badBlocks = button("Check Device for Bad Blocks", () -> confirmDirect("badblocks"));
        writer.addView(badBlocks);

        status = text("Choose a boot selection and connect a USB drive.", 15);
        status.setTextIsSelectable(true);
        writer.addView(status);

        // Build OS Download Catalog Screen
        catalogLayout.addView(text("Download Operating Systems", 24));
        catalogLayout.addView(text("Direct official downloads for Windows, macOS, FydeOS, and Linux.\nTap Flash… to download directly into RufuSwift and preload for flashing.", 14));

        Button helpChooseBtn = button("Confused? Help me choose FydeOS edition →", () -> {
            showHelpMeChooseDialog(writerScroll, catalogScroll);
        });
        catalogLayout.addView(helpChooseBtn);

        for (CatalogEntry entry : CATALOG) {
            LinearLayout card = column();
            card.setBackgroundColor(0x10888888);
            card.addView(text(entry.name + " (" + entry.arch + ")", 17));
            card.addView(text(entry.desc, 13));
            LinearLayout btnRow = new LinearLayout(this);
            btnRow.setOrientation(LinearLayout.HORIZONTAL);

            if (entry.editions != null && !entry.editions.isEmpty()) {
                Button consolidatedDropdown = button("Download / Flash… ▾", () -> {
                    List<String> optionsList = new ArrayList<>();
                    List<Runnable> actions = new ArrayList<>();

                    for (CatalogEdition ed : entry.editions) {
                        optionsList.add("Flash: " + ed.name + " (" + ed.badge + ")");
                        actions.add(() -> {
                            CatalogEntry editionEntry = new CatalogEntry(
                                entry.name + " (" + ed.name + ")",
                                entry.version,
                                ed.badge,
                                ed.directUrl,
                                ed.pageUrl,
                                ed.filename,
                                ed.desc,
                                null
                            );
                            startDownloadAndFlash(editionEntry, writerScroll, catalogScroll);
                        });
                    }

                    for (CatalogEdition ed : entry.editions) {
                        optionsList.add("Download: " + ed.name + " (" + ed.badge + ")");
                        actions.add(() -> {
                            String targetUrl = ed.directUrl != null ? ed.directUrl : ed.pageUrl;
                            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(targetUrl)));
                        });
                    }

                    optionsList.add("Confused? Help me choose →");
                    actions.add(() -> showHelpMeChooseDialog(writerScroll, catalogScroll));

                    String[] options = optionsList.toArray(new String[0]);
                    new AlertDialog.Builder(this)
                        .setTitle(entry.name + " — Select Hardware Edition")
                        .setItems(options, (dialog, which) -> {
                            if (which >= 0 && which < actions.size()) {
                                actions.get(which).run();
                            }
                        })
                        .show();
                });
                btnRow.addView(consolidatedDropdown);
            } else {
                Button dlBtn = button("Download", () -> {
                    String targetUrl = entry.directUrl != null ? entry.directUrl : entry.pageUrl;
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(targetUrl)));
                });
                btnRow.addView(dlBtn);

                Button flashBtn = button("Flash…", () -> {
                    startDownloadAndFlash(entry, writerScroll, catalogScroll);
                });
                btnRow.addView(flashBtn);
            }

            card.addView(btnRow);
            catalogLayout.addView(card);
            View spacer = new View(this);
            spacer.setMinimumHeight(dp(8));
            catalogLayout.addView(spacer);
        }

        root.setOnApplyWindowInsetsListener((view, insets) -> {
            android.graphics.Insets safe = insets.getInsets(
                WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom);
            return insets;
        });
        setContentView(root);

        IntentFilter filter = new IntentFilter(USB_PERMISSION);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(permission, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(permission, filter);
        refreshDrives();
    }

    private void showHelpMeChooseDialog(ScrollView writerScroll, View catalogScroll) {
        String[] options = {
            "Intel Modern (2015+ · 6th - 14th Gen)\nSupports Intel Core Processors with Intel HD/UHD or Iris Xe graphics",
            "Intel Slim (2015 - 2019 · 6th - 9th Gen · Non-Core)\nSupports Intel Celeron, and Pentium Processors with Intel HD/UHD Graphics",
            "AMD Graphics (2011+ · Intel & AMD CPU)\nSupports AMD Graphics (discrete or integrated) and either AMD or Intel CPUs",
            "Intel Legacy [No longer supported] (2011 - 2014 · 3rd - 5th Gen)\nSupports Intel Core Processors with Intel HD graphics. Stopped at v19.0."
        };

        new AlertDialog.Builder(this)
            .setTitle("FydeOS for PC — Help Me Choose")
            .setMessage("Please choose one of the following options that best describes your PC:\n\n"
                + "Host Device: " + Build.MANUFACTURER + " " + Build.MODEL + " (" + Build.HARDWARE + " · ARM/Mobile)\n"
                + "Note: FydeOS for PC runs on x86_64 Intel & AMD PCs. Select the edition matching your target PC or laptop:")
            .setItems(options, (dialog, which) -> {
                String code;
                switch (which) {
                    case 0: code = "iris"; break;
                    case 1: code = "slim"; break;
                    case 2: code = "apu"; break;
                    default: code = "legacy"; break;
                }
                for (CatalogEntry entry : CATALOG) {
                    if (entry.editions != null && !entry.editions.isEmpty()) {
                        for (CatalogEdition ed : entry.editions) {
                            if (ed.code.equals(code)) {
                                CatalogEntry editionEntry = new CatalogEntry(
                                    entry.name + " (" + ed.name + ")",
                                    entry.version,
                                    ed.badge,
                                    ed.directUrl,
                                    ed.pageUrl,
                                    ed.filename,
                                    ed.desc,
                                    null
                                );
                                startDownloadAndFlash(editionEntry, writerScroll, catalogScroll);
                                return;
                            }
                        }
                    }
                }
            })
            .setNegativeButton("Cancel", null)
            .show();
    }

    private void startDownloadAndFlash(CatalogEntry entry, ScrollView writerScroll, View catalogScroll) {
        File targetFile = new File(getExternalFilesDir(null), entry.filename);
        autoDeleteFile = targetFile;
        pendingAutoFlash = true;

        if (targetFile.exists() && targetFile.length() > 1024 * 1024) {
            image = Uri.fromFile(targetFile);
            imageName = entry.filename;
            imageLabel.setText(entry.filename);
            catalogScroll.setVisibility(View.GONE);
            writerScroll.setVisibility(View.VISIBLE);
            if (!drives.isEmpty()) {
                pendingAutoFlash = false;
                driveList.setSelection(1);
                status.setText("Flashing " + entry.name + " to USB drive…");
                setBusy(true);
                startWrite(drives.get(0));
            } else {
                status.setText("Loaded " + entry.name + ". Connect an external USB drive to begin flashing automatically.");
                setBusy(false);
            }
            return;
        }
        String downloadUrl = entry.directUrl != null ? entry.directUrl : entry.pageUrl;
        if (entry.directUrl == null) {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(entry.pageUrl)));
            return;
        }
        status.setText("Connecting to download " + entry.filename + "…");
        setBusy(true);
        catalogScroll.setVisibility(View.GONE);
        writerScroll.setVisibility(View.VISIBLE);
        new Thread(() -> {
            try {
                java.net.URL u = new java.net.URL(downloadUrl);
                java.net.HttpURLConnection conn = (java.net.HttpURLConnection) u.openConnection();
                conn.setRequestProperty("User-Agent", "Mozilla/5.0");
                conn.connect();
                long total = conn.getContentLengthLong();
                try (InputStream in = conn.getInputStream();
                     FileOutputStream fos = new FileOutputStream(targetFile)) {
                    byte[] buf = new byte[1024 * 1024];
                    long written = 0;
                    for (int len; (len = in.read(buf)) != -1;) {
                        fos.write(buf, 0, len);
                        written += len;
                        long finalWritten = written;
                        runOnUiThread(() -> {
                            if (total > 0) {
                                int pct = (int) (finalWritten * 100 / total);
                                status.setText("Downloading " + entry.filename + ": " + (finalWritten / (1024 * 1024)) + "MB / " + (total / (1024 * 1024)) + "MB (" + pct + "%)");
                            } else {
                                status.setText("Downloading " + entry.filename + ": " + (finalWritten / (1024 * 1024)) + "MB");
                            }
                        });
                    }
                }
                runOnUiThread(() -> {
                    image = Uri.fromFile(targetFile);
                    imageName = entry.filename;
                    imageLabel.setText(entry.filename);
                    if (!drives.isEmpty()) {
                        pendingAutoFlash = false;
                        driveList.setSelection(1);
                        status.setText("Download complete! Flashing to USB drive…");
                        setBusy(true);
                        startWrite(drives.get(0));
                    } else {
                        status.setText("Download complete! Connect an external USB drive to begin flashing automatically.");
                        setBusy(false);
                    }
                });
            } catch (Exception e) {
                runOnUiThread(() -> {
                    status.setText("Download failed: " + e.getMessage());
                    setBusy(false);
                });
            }
        }, "Rufus downloader").start();
    }

    private void refreshDrives() {
        drives.clear();
        List<String> labels = new ArrayList<>();
        labels.add("Select a USB drive");
        if (usb != null) for (UsbDevice device : usb.getDeviceList().values()) {
            if (UsbDisk.storagePort(device) == null) continue;
            drives.add(device);
            labels.add((device.getProductName() == null ? "USB storage" : device.getProductName())
                + " · " + device.getDeviceName());
        }
        driveList.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, labels));
        if (pendingAutoFlash && autoDeleteFile != null && !drives.isEmpty() && !busy) {
            pendingAutoFlash = false;
            driveList.setSelection(1);
            status.setText("USB drive detected. Flashing downloaded image…");
            setBusy(true);
            startWrite(drives.get(0));
            return;
        }
        setBusy(false);
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (result != RESULT_OK || data == null || data.getData() == null) return;
        if (request == 2) {
            calculateChecksums(data.getData());
            return;
        }
        if (request != 1) return;
        Uri selected = data.getData();
        try (Cursor cursor = getContentResolver().query(selected,
                new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor == null || !cursor.moveToFirst()) throw new IOException("Could not read the image name.");
            String name = cursor.getString(0);
            if (name == null || !name.toLowerCase(Locale.ROOT).matches(".+\\.(img|dd|raw|iso|vhd|vhdx|dmg|bin|xz|gz|zip)")) {
                throw new IOException("Choose an ISO, raw image (.img, .bin, .dmg), or compressed archive (.zip, .gz, .xz).");
            }
            image = selected;
            imageName = name;
            imageLabel.setText(name);
            status.setText("Select a USB drive.");
        } catch (Exception error) {
            status.setText(error.getMessage());
        }
        setBusy(false);
    }

    private void confirmAction() {
        int bootPos = bootList.getSelectedItemPosition();
        if (bootPos == 0) confirmDirect("write");
        else if (bootPos == 1) confirmDirect("format");
        else confirmDirect("freedos");
    }

    private void confirmDirect(String action) {
        int index = driveList.getSelectedItemPosition() - 1;
        if (busy || index < 0 || index >= drives.size()) return;
        UsbDevice device = drives.get(index);
        pendingAction = action;

        String msg;
        if ("backup".equals(action)) {
            msg = "Rufus will dump all sectors from this USB drive into app storage.";
        } else if ("badblocks".equals(action)) {
            msg = "Rufus will run a surface read verification pass across the entire drive.";
        } else {
            msg = "WARNING: All data on " + driveList.getSelectedItem() + " will be destroyed!";
        }

        new AlertDialog.Builder(this).setTitle("Confirm Action")
            .setMessage(msg)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Proceed", (dialog, which) -> authorize(device)).show();
    }

    private void authorize(UsbDevice device) {
        setBusy(true);
        if (usb.hasPermission(device)) {
            dispatchAction(device, pendingAction);
        } else {
            pendingDrive = device;
            Intent intent = new Intent(USB_PERMISSION).setPackage(getPackageName());
            usb.requestPermission(device, PendingIntent.getBroadcast(this, 0, intent,
                PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_ONE_SHOT));
        }
    }

    private final BroadcastReceiver permission = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if (pendingDrive == null) return;
            UsbDevice expected = pendingDrive;
            pendingDrive = null;
            if (expected.equals(device) && usb.hasPermission(device)) dispatchAction(device, pendingAction);
            else {
                status.setText("USB access was denied or the device changed.");
                setBusy(false);
            }
        }
    };

    private void dispatchAction(UsbDevice device, String action) {
        if ("backup".equals(action)) runBackup(device);
        else if ("badblocks".equals(action)) runBadBlocks(device);
        else if ("format".equals(action)) runFormat(device, false);
        else if ("freedos".equals(action)) runFormat(device, true);
        else startWrite(device);
    }

    private void runFormat(UsbDevice device, boolean isFreeDos) {
        status.setText("Formatting USB drive…");
        new Thread(() -> {
            String result;
            try (UsbDisk disk = new UsbDisk(usb, device)) {
                disk.formatFat32("RUFUS", isFreeDos);
                result = (isFreeDos ? "FreeDOS boot drive" : "FAT32 drive") + " created successfully!";
            } catch (Exception e) {
                result = "Formatting failed: " + e.getMessage();
            }
            String finalResult = result;
            runOnUiThread(() -> {
                status.setText(finalResult);
                setBusy(false);
                refreshDrives();
            });
        }).start();
    }

    private void runBackup(UsbDevice device) {
        status.setText("Backing up drive to disk image…");
        new Thread(() -> {
            String result;
            File outFile = new File(getExternalFilesDir(null), "rufus_backup_" + System.currentTimeMillis() + ".img");
            try (UsbDisk disk = new UsbDisk(usb, device);
                 FileOutputStream fos = new FileOutputStream(outFile)) {
                disk.backupDrive(fos);
                result = "Drive backed up successfully to " + outFile.getName() + " (" + (outFile.length() / (1024 * 1024)) + " MB)";
            } catch (Exception e) {
                result = "Backup failed: " + e.getMessage();
            }
            String finalResult = result;
            runOnUiThread(() -> {
                status.setText(finalResult);
                setBusy(false);
            });
        }).start();
    }

    private void runBadBlocks(UsbDevice device) {
        status.setText("Running surface bad blocks scan…");
        new Thread(() -> {
            String result;
            try (UsbDisk disk = new UsbDisk(usb, device)) {
                int errors = disk.checkBadBlocks(1);
                result = errors == 0 ? "Surface test passed: 0 bad blocks found!" : "Warning: " + errors + " bad block read errors detected!";
            } catch (Exception e) {
                result = "Scan failed: " + e.getMessage();
            }
            String finalResult = result;
            runOnUiThread(() -> {
                status.setText(finalResult);
                setBusy(false);
            });
        }).start();
    }

    private void startWrite(UsbDevice device) {
        Uri source = image;
        String name = imageName;
        if (source == null) {
            status.setText("Please choose an image first.");
            setBusy(false);
            return;
        }
        status.setText("Writing image… Keep the USB drive connected.");
        new Thread(() -> {
            String result;
            try {
                UsbDevice current = usb.getDeviceList().get(device.getDeviceName());
                if (!device.equals(current) || !usb.hasPermission(current)) throw new IOException("The USB drive changed.");
                for (StorageVolume volume : getSystemService(StorageManager.class).getStorageVolumes()) {
                    if (volume.isRemovable() && (Environment.MEDIA_MOUNTED.equals(volume.getState())
                        || Environment.MEDIA_MOUNTED_READ_ONLY.equals(volume.getState()))) {
                        throw new IOException("Unmount removable storage in system settings before writing.");
                    }
                }
                String lowerName = name.toLowerCase(Locale.ROOT);
                if (lowerName.endsWith(".gz")) {
                    File expanded = File.createTempFile("rufus-", ".image", getCacheDir());
                    try {
                        try (InputStream compressed = getContentResolver().openInputStream(source)) {
                            if (compressed == null) throw new IOException("Could not open the gzip image.");
                            try (GZIPInputStream gzip = new GZIPInputStream(compressed);
                                 FileOutputStream output = new FileOutputStream(expanded)) {
                                byte[] buffer = new byte[1024 * 1024];
                                for (int count; (count = gzip.read(buffer)) != -1;) {
                                    output.write(buffer, 0, count);
                                }
                            }
                        }
                        try (FileInputStream stream = new FileInputStream(expanded)) {
                            writeImage(stream, expanded.length(), lowerName.endsWith(".iso.gz"), current);
                        }
                    } finally {
                        expanded.delete();
                    }
                } else if (lowerName.endsWith(".zip")) {
                    // Extract inner disk image (e.g., FydeOS .bin.zip)
                    File expanded = File.createTempFile("rufus-", ".image", getCacheDir());
                    try {
                        try (InputStream raw = getContentResolver().openInputStream(source)) {
                            if (raw == null) throw new IOException("Could not open the zip archive.");
                            try (ZipInputStream zip = new ZipInputStream(raw)) {
                                ZipEntry entry = null;
                                while ((entry = zip.getNextEntry()) != null) {
                                    String entryLower = entry.getName().toLowerCase(Locale.ROOT);
                                    if (entryLower.endsWith(".bin") || entryLower.endsWith(".img") || entryLower.endsWith(".raw") || entryLower.endsWith(".iso")) {
                                        break;
                                    }
                                }
                                if (entry == null) throw new IOException("No valid raw image found inside the zip archive.");
                                try (FileOutputStream output = new FileOutputStream(expanded)) {
                                    byte[] buffer = new byte[1024 * 1024];
                                    for (int count; (count = zip.read(buffer)) != -1;) {
                                        output.write(buffer, 0, count);
                                    }
                                }
                            }
                        }
                        try (FileInputStream stream = new FileInputStream(expanded)) {
                            writeImage(stream, expanded.length(), false, current);
                        }
                    } finally {
                        expanded.delete();
                    }
                } else {
                    ParcelFileDescriptor descriptor = getContentResolver().openFileDescriptor(source, "r");
                    if (descriptor == null) throw new IOException("Could not open the image.");
                    long size = descriptor.getStatSize();
                    try (FileInputStream stream = new ParcelFileDescriptor.AutoCloseInputStream(descriptor)) {
                        boolean handledXar = false;
                        byte[] magic = new byte[4];
                        int rMagic = stream.read(magic);
                        if (rMagic == 4 && magic[0] == 0x78 && magic[1] == 0x61 && magic[2] == 0x72 && magic[3] == 0x21) {
                            byte[] hdr = new byte[24];
                            stream.read(hdr);
                            int hdrLen = ((hdr[0] & 0xFF) << 8) | (hdr[1] & 0xFF);
                            long tocCLen = 0;
                            for (int i = 4; i < 12; i++) {
                                tocCLen = (tocCLen << 8) | (hdr[i] & 0xFFL);
                            }
                            long heapOffset = hdrLen + tocCLen;
                            stream.getChannel().position(hdrLen);
                            byte[] compToc = new byte[(int) tocCLen];
                            int r = 0;
                            while (r < compToc.length) {
                                int n = stream.read(compToc, r, compToc.length - r);
                                if (n <= 0) break;
                                r += n;
                            }
                            ByteArrayInputStream bais = new ByteArrayInputStream(compToc);
                            InflaterInputStream iis = new InflaterInputStream(bais);
                            ByteArrayOutputStream baos = new ByteArrayOutputStream();
                            byte[] b = new byte[16384];
                            for (int len; (len = iis.read(b)) != -1;) {
                                baos.write(b, 0, len);
                            }
                            String tocXml = baos.toString("UTF-8");
                            if (tocXml.contains("<name>SharedSupport.dmg</name>")) {
                                int idx = tocXml.indexOf("<name>SharedSupport.dmg</name>");
                                String prefix = tocXml.substring(0, idx);
                                int lastData = prefix.lastIndexOf("<data>");
                                if (lastData >= 0) {
                                    String dataXml = prefix.substring(lastData);
                                    Matcher offM = Pattern.compile("<offset>(\\d+)</offset>").matcher(dataXml);
                                    Matcher sizeM = Pattern.compile("<size>(\\d+)</size>").matcher(dataXml);
                                    if (offM.find() && sizeM.find()) {
                                        long offset = Long.parseLong(offM.group(1));
                                        long dmgSize = Long.parseLong(sizeM.group(1));
                                        stream.getChannel().position(heapOffset + offset);
                                        writeImage(stream, dmgSize, false, current);
                                        handledXar = true;
                                    }
                                }
                            }
                        }
                        if (!handledXar) {
                            stream.getChannel().position(0);
                            writeImage(stream, size, lowerName.endsWith(".iso"), current);
                        }
                    }
                }
                if (autoDeleteFile != null) {
                    autoDeleteFile.delete();
                    autoDeleteFile = null;
                    image = null;
                    imageName = null;
                    result = "Image written successfully! Downloaded installer cleaned up.";
                } else {
                    result = "Image written successfully!";
                }
            } catch (Exception error) {
                result = error.getMessage();
            }
            String message = result;
            runOnUiThread(() -> {
                status.setText(message);
                setBusy(false);
                refreshDrives();
            });
        }, "Rufus writer").start();
    }

    private void writeImage(FileInputStream stream, long size, boolean iso, UsbDevice device)
            throws IOException {
        if (size <= 0) throw new IOException("Choose a local image with a known file size.");
        if (iso) {
            byte[] header = new byte[512];
            new DataInputStream(stream).readFully(header);
            boolean partition = false;
            for (int i = 450; i < 511; i += 16) partition |= header[i] != 0;
            if (!partition || header[510] != 0x55 || header[511] != (byte) 0xaa) {
                throw new IOException("This ISO has no disk partition table.");
            }
            stream.getChannel().position(0);
        }
        if (!device.equals(usb.getDeviceList().get(device.getDeviceName())) || !usb.hasPermission(device)) {
            throw new IOException("The USB drive changed before writing.");
        }
        try (UsbDisk disk = new UsbDisk(usb, device)) {
            disk.writeImage(stream, size);
        }
    }

    private void calculateChecksums(Uri file) {
        setBusy(true);
        status.setText("Calculating checksums…");
        new Thread(() -> {
            String message;
            try (InputStream stream = getContentResolver().openInputStream(file)) {
                if (stream == null) throw new IOException("Could not open the file.");
                String[] algorithms = {"MD5", "SHA-1", "SHA-256", "SHA-512"};
                MessageDigest[] hashes = new MessageDigest[algorithms.length];
                for (int i = 0; i < hashes.length; i++) hashes[i] = MessageDigest.getInstance(algorithms[i]);
                byte[] buffer = new byte[1024 * 1024];
                for (int count; (count = stream.read(buffer)) != -1;) {
                    for (MessageDigest hash : hashes) hash.update(buffer, 0, count);
                }
                StringBuilder result = new StringBuilder();
                for (int i = 0; i < hashes.length; i++) {
                    result.append(algorithms[i]).append(": ");
                    for (byte value : hashes[i].digest()) {
                        result.append(Character.forDigit((value >>> 4) & 15, 16));
                        result.append(Character.forDigit(value & 15, 16));
                    }
                    result.append('\n');
                }
                message = result.toString().trim();
            } catch (Exception error) {
                message = "Could not calculate checksums: " + error.getMessage();
            }
            String result = message;
            runOnUiThread(() -> {
                status.setText(result);
                setBusy(false);
            });
        }, "Rufus checksums").start();
    }

    private void setBusy(boolean working) {
        busy = working;
        choose.setEnabled(!working);
        checksums.setEnabled(!working);
        refresh.setEnabled(!working);
        driveList.setEnabled(!working);
        bootList.setEnabled(!working);
        int bootPos = bootList.getSelectedItemPosition();
        boolean hasDrive = driveList.getSelectedItemPosition() > 0;
        startAction.setEnabled(!working && hasDrive && (bootPos != 0 || image != null));
        backup.setEnabled(!working && hasDrive);
        badBlocks.setEnabled(!working && hasDrive);
    }

    private int dp(int size) { return Math.round(size * getResources().getDisplayMetrics().density); }
    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(dp(12), dp(12), dp(12), dp(12));
        return layout;
    }
    private TextView text(String content, int size) {
        TextView view = new TextView(this);
        view.setText(content);
        view.setTextSize(size);
        return view;
    }
    private Button button(String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setOnClickListener(view -> action.run());
        return button;
    }

    @Override protected void onDestroy() {
        unregisterReceiver(permission);
        super.onDestroy();
    }
}
