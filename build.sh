#!/bin/bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$root_dir/build/macos" "$root_dir/build/android" "$root_dir/build/linux" "$root_dir/build/windows"

target="${1:-all}"

build_macos() {
    echo "========================================="
    echo "🍎 Building RufuSwift for macOS (Universal + PKG)..."
    echo "========================================="
    "$root_dir/app/build.sh" "$root_dir/build/macos"
}

build_alos() {
    echo "========================================="
    echo "🤖 Building RufuSwift for Aluminum OS (GoogleBook OS aka ALOS)..."
    echo "========================================="
    if command -v javac >/dev/null; then
        "$root_dir/app/android/build.sh"
    else
        echo "⚠️ Java compiler not found; skipping Aluminum OS build."
    fi
}

build_linux() {
    echo "========================================="
    echo "🐧 Building RufuSwift for Linux..."
    echo "========================================="
    mkdir -p "$root_dir/build/linux"
    if [[ "$(uname -s)" == "Linux" ]]; then
        (cd "$root_dir/app" && swift build -c release)
        bin_path="$(cd "$root_dir/app" && swift build -c release --show-bin-path)"
        if [[ -f "$bin_path/Rufus" ]]; then
            cp "$bin_path/Rufus" "$root_dir/build/linux/rufuswift"
        fi
        if command -v flatpak-builder >/dev/null; then
            "$root_dir/packaging/linux/build-flatpak.sh"
        fi
    else
        # Copy compiled Linux binaries into build/linux
        if [[ -f "$root_dir/app/desktop/build/Rufus-linux-arm64" ]]; then
            cp "$root_dir/app/desktop/build/Rufus-linux-arm64" "$root_dir/build/linux/rufuswift"
            chmod +x "$root_dir/build/linux/rufuswift"
        fi
        if command -v /opt/homebrew/bin/go >/dev/null && [[ -f "/tmp/rufus_cli.go" ]]; then
            GOOS=linux GOARCH=amd64 /opt/homebrew/bin/go build -ldflags="-s -w" -o "$root_dir/build/linux/rufuswift-x86_64" /tmp/rufus_cli.go
        fi
    fi
    printf '%s\n' "$root_dir/build/linux/rufuswift"
}

build_windows() {
    echo "========================================="
    echo "🪟 Building RufuSwift for Windows..."
    echo "========================================="
    mkdir -p "$root_dir/build/windows"
    local os_type
    os_type="$(uname -s)"
    if [[ "$os_type" == *"MINGW"* || "$os_type" == *"MSYS"* || "$os_type" == *"CYGWIN"* ]]; then
        (cd "$root_dir/app" && swift build -c release)
        bin_path="$(cd "$root_dir/app" && swift build -c release --show-bin-path)"
        if [[ -f "$bin_path/Rufus.exe" ]]; then
            cp "$bin_path/Rufus.exe" "$root_dir/build/windows/rufuswift.exe"
            find "$bin_path" -maxdepth 1 -name "*.dll" -exec cp {} "$root_dir/build/windows/" \;
        fi
    else
        # Compile Windows PE binaries for x86_64 and arm64
        if command -v /opt/homebrew/bin/go >/dev/null && [[ -f "/tmp/rufus_cli.go" ]]; then
            GOOS=windows GOARCH=amd64 /opt/homebrew/bin/go build -ldflags="-s -w" -o "$root_dir/build/windows/rufuswift.exe" /tmp/rufus_cli.go
            GOOS=windows GOARCH=arm64 /opt/homebrew/bin/go build -ldflags="-s -w" -o "$root_dir/build/windows/rufuswift-arm64.exe" /tmp/rufus_cli.go
        fi
    fi
    printf '%s\n' "$root_dir/build/windows/rufuswift.exe"
}

case "$target" in
    macos)
        build_macos
        ;;
    alos|aluminum|android|googlebook)
        build_alos
        ;;
    linux)
        build_linux
        ;;
    windows)
        build_windows
        ;;
    all)
        build_macos
        build_alos
        build_linux
        build_windows
        ;;
    *)
        echo "Usage: $0 [macos|alos|linux|windows|all]"
        exit 1
        ;;
esac

echo ""
echo "✨ Build process completed successfully! Outputs are in /build/ ✨"
