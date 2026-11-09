#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
output="${1:-$repo_root/build/macos}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"

stage="$(mktemp -d "$output/.rufus-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Rufus.app"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -X "$script_dir/RufuSwift/Info.plist" "$app/Contents/Info.plist"
cp -X "$repo_root/LICENSE.txt" "$app/Contents/Resources/LICENSE.txt"

/usr/bin/sips -s format icns "$script_dir/res/icons/rufus-512.png" \
    --out "$app/Contents/Resources/AppIcon.icns" >/dev/null
cp "$app/Contents/Resources/AppIcon.icns" "$app/Contents/Resources/Rufus.icns"

sdk="$(xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
    xcrun --sdk macosx swiftc -O -sdk "$sdk" -target "$arch-apple-macosx13.0" \
        -module-cache-path "$stage/module-cache" \
        "$script_dir/RufuSwift"/*.swift \
        -o "$stage/Rufus-$arch"
done
xcrun lipo -create "$stage/Rufus-arm64" "$stage/Rufus-x86_64" -output "$app/Contents/MacOS/Rufus"
# Detect signing identity
SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep -o '\"Apple Development:.*\"' | head -n 1 | tr -d '\"' || true)"
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep -o '\"Developer ID Application:.*\"' | head -n 1 | tr -d '\"' || true)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="-"
fi

find "$stage" -name ".DS_Store" -delete
find "$stage" -name "._*" -delete
/usr/bin/xattr -cr "$app" || true
/usr/bin/xattr -d com.apple.FinderInfo "$app" || true
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$app/Contents/MacOS/Rufus"
/usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$app"
/usr/bin/codesign --verify --deep --strict "$app"

if [[ -e "$output/Rufus.app" ]]; then
    rm -rf "$output/Rufus.app"
fi
mv "$app" "$output/Rufus.app"
/usr/bin/xattr -cr "$output/Rufus.app" || true
/usr/bin/xattr -d com.apple.FinderInfo "$output/Rufus.app" || true
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$output/Rufus.app/Contents/MacOS/Rufus"
/usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$output/Rufus.app"
/usr/bin/codesign --verify --deep --strict "$output/Rufus.app"

# Build Installer Package (.pkg)
/usr/bin/pkgbuild \
    --component "$output/Rufus.app" \
    --install-location "/Applications" \
    --identifier "com.ancientkira.rufuswift" \
    --version "4.6.0" \
    "$output/Rufus.pkg"

printf '%s\n' "$output/Rufus.app"
printf '%s\n' "$output/Rufus.pkg"
