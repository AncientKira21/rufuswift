#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

build_dir="$repo_root/build/linux/flatpak-build"
export_dir="$repo_root/build/linux/flatpak-repo"
mkdir -p "$build_dir" "$export_dir"

echo "Building Flatpak package for RufuSwift..."
flatpak-builder --force-clean --repo="$export_dir" "$build_dir" "$script_dir/com.ancientkira.rufuswift.yml"
flatpak build-bundle "$export_dir" "$repo_root/build/linux/rufuswift.flatpak" com.ancientkira.rufuswift

echo "Flatpak bundle generated at: $repo_root/build/linux/rufuswift.flatpak"
echo "To install: flatpak install --user $repo_root/build/linux/rufuswift.flatpak"
echo "Or via Flathub: flatpak install rufuswift"
