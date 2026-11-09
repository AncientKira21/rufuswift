#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
out_dir="$repo_root/build/linux"
mkdir -p "$out_dir"

version="4.6.0"

build_deb() {
    local arch="$1"
    local bin_source="$2"
    local deb_arch="$3"
    local pkg_name="rufuswift_${version}_${deb_arch}.deb"
    local stage="$(mktemp -d "/tmp/deb-build.XXXXXX")"
    trap 'rm -rf "$stage"' RETURN

    echo "Building Debian package for $deb_arch..."
    mkdir -p "$stage/DEBIAN"
    mkdir -p "$stage/usr/bin"
    mkdir -p "$stage/usr/share/applications"
    mkdir -p "$stage/usr/share/metainfo"
    mkdir -p "$stage/usr/share/icons/hicolor/512x512/apps"

    # Control file
    cat << C_EOF > "$stage/DEBIAN/control"
Package: rufuswift
Version: ${version}
Section: utils
Priority: optional
Architecture: ${deb_arch}
Maintainer: Ancient Kira
Homepage: https://github.com/AncientKira21/rufuswift
Description: Reliable Multi-Platform USB Formatting & Bootable Drive Creator Utility
 RufuSwift is the reliable multi-platform utility that formats USB flash drives,
 creates bootable live media (Windows, Linux, FydeOS, FreeDOS), verifies bad blocks,
 and calculates cryptographic checksums.
C_EOF

    # Install binary
    cp "$bin_source" "$stage/usr/bin/rufuswift"
    chmod 755 "$stage/usr/bin/rufuswift"

    # Desktop entry & metainfo
    if [[ -f "$script_dir/com.ancientkira.rufuswift.desktop" ]]; then
        cp "$script_dir/com.ancientkira.rufuswift.desktop" "$stage/usr/share/applications/"
    fi
    if [[ -f "$script_dir/com.ancientkira.rufuswift.metainfo.xml" ]]; then
        cp "$script_dir/com.ancientkira.rufuswift.metainfo.xml" "$stage/usr/share/metainfo/"
    fi
    if [[ -f "$repo_root/app/res/icons/rufus-512.png" ]]; then
        cp "$repo_root/app/res/icons/rufus-512.png" "$stage/usr/share/icons/hicolor/512x512/apps/rufuswift.png"
    fi

    # Pack into .deb format (ar archive)
    (
        cd "$stage"
        echo "2.0" > debian-binary
        tar -czf control.tar.gz -C DEBIAN control
        tar --exclude='./DEBIAN' --exclude='./debian-binary' --exclude='./control.tar.gz' -czf data.tar.gz usr
        ar -rc "$out_dir/$pkg_name" debian-binary control.tar.gz data.tar.gz
    )

    printf '%s\n' "$out_dir/$pkg_name"
}

if [[ -f "$repo_root/build/linux/rufuswift" ]]; then
    build_deb "aarch64" "$repo_root/build/linux/rufuswift" "arm64"
fi

if [[ -f "$repo_root/build/linux/rufuswift-x86_64" ]]; then
    build_deb "x86_64" "$repo_root/build/linux/rufuswift-x86_64" "amd64"
fi
