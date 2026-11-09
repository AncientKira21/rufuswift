import sys, os, time, tarfile, tempfile

def make_ar_header(name, size, mtime=None, mode=0o100644, uid=0, gid=0):
    if mtime is None:
        mtime = int(time.time())
    header = f"{name:<16}{mtime:<12}{uid:<6}{gid:<6}{oct(mode)[2:]:>8}{size:<10}`\n"
    return header.encode('ascii')

def build_deb(bin_path, out_deb, arch="arm64", version="4.6.0"):
    with tempfile.TemporaryDirectory() as tmpdir:
        # 1. debian-binary
        deb_binary = b"2.0\n"

        # 2. control.tar.gz
        control_path = os.path.join(tmpdir, "control.tar.gz")
        control_data = f"""Package: rufuswift
Version: {version}
Section: utils
Priority: optional
Architecture: {arch}
Maintainer: Ancient Kira
Homepage: https://github.com/AncientKira21/rufuswift
Description: Reliable Multi-Platform USB Formatting & Bootable Drive Creator Utility
 RufuSwift is the reliable multi-platform utility that formats USB flash drives,
 creates bootable live media (Windows, Linux, FydeOS, FreeDOS), verifies bad blocks,
 and calculates cryptographic checksums.
""".encode('utf-8')

        with tarfile.open(control_path, "w:gz") as tar:
            ti = tarfile.TarInfo("control")
            ti.size = len(control_data)
            ti.mode = 0o644
            ti.mtime = int(time.time())
            import io
            tar.addfile(ti, io.BytesIO(control_data))

        with open(control_path, "rb") as f:
            control_bytes = f.read()

        # 3. data.tar.gz
        data_path = os.path.join(tmpdir, "data.tar.gz")
        with tarfile.open(data_path, "w:gz") as tar:
            # Add binary
            ti_bin = tarfile.TarInfo("usr/bin/rufuswift")
            ti_bin.size = os.path.getsize(bin_path)
            ti_bin.mode = 0o755
            ti_bin.mtime = int(time.time())
            with open(bin_path, "rb") as bf:
                tar.addfile(ti_bin, bf)

            # Add desktop file if exists
            desktop_src = "packaging/linux/com.ancientkira.rufuswift.desktop"
            if os.path.exists(desktop_src):
                ti_desk = tarfile.TarInfo("usr/share/applications/com.ancientkira.rufuswift.desktop")
                ti_desk.size = os.path.getsize(desktop_src)
                ti_desk.mode = 0o644
                ti_desk.mtime = int(time.time())
                with open(desktop_src, "rb") as df:
                    tar.addfile(ti_desk, df)

            # Add icon if exists
            icon_src = "app/res/icons/rufus-512.png"
            if os.path.exists(icon_src):
                ti_ic = tarfile.TarInfo("usr/share/icons/hicolor/512x512/apps/rufuswift.png")
                ti_ic.size = os.path.getsize(icon_src)
                ti_ic.mode = 0o644
                ti_ic.mtime = int(time.time())
                with open(icon_src, "rb") as icf:
                    tar.addfile(ti_ic, icf)

        with open(data_path, "rb") as f:
            data_bytes = f.read()

        # Assemble GNU AR format (.deb)
        with open(out_deb, "wb") as deb:
            deb.write(b"!<arch>\n")

            # member 1: debian-binary
            deb.write(make_ar_header("debian-binary", len(deb_binary)))
            deb.write(deb_binary)
            if len(deb_binary) % 2 != 0:
                deb.write(b"\n")

            # member 2: control.tar.gz
            deb.write(make_ar_header("control.tar.gz", len(control_bytes)))
            deb.write(control_bytes)
            if len(control_bytes) % 2 != 0:
                deb.write(b"\n")

            # member 3: data.tar.gz
            deb.write(make_ar_header("data.tar.gz", len(data_bytes)))
            deb.write(data_bytes)
            if len(data_bytes) % 2 != 0:
                deb.write(b"\n")

        print(f"Built standard Debian package: {out_deb} ({os.path.getsize(out_deb):,} bytes)")

if __name__ == "__main__":
    if os.path.exists("build/linux/rufuswift"):
        build_deb("build/linux/rufuswift", "build/linux/rufuswift_4.6.0_arm64.deb", arch="arm64")
    if os.path.exists("build/linux/rufuswift-x86_64"):
        build_deb("build/linux/rufuswift-x86_64", "build/linux/rufuswift_4.6.0_amd64.deb", arch="amd64")
