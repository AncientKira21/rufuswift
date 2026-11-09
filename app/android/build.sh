#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
tools="$sdk/build-tools/${ANDROID_BUILD_TOOLS:-36.0.0}"
platform="$sdk/platforms/android-36/android.jar"
mkdir -p build
stage="$(mktemp -d "$PWD/build/.apk.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/classes" "$stage/dex"

"$tools/aapt2" link -I "$platform" --manifest AndroidManifest.xml -o "$stage/unsigned.apk"
javac --release 8 -classpath "$platform" -d "$stage/classes" src/*.java
jar cf "$stage/classes.jar" -C "$stage/classes" .
"$tools/d8" --lib "$platform" --min-api 30 --output "$stage/dex" "$stage/classes.jar"
(cd "$stage/dex" && zip -q -0 "$stage/unsigned.apk" classes.dex)
"$tools/zipalign" -f 4 "$stage/unsigned.apk" "$stage/aligned.apk"

if [[ ! -f build/debug.keystore ]]; then
    keytool -genkeypair -keystore build/debug.keystore -storepass android -keypass android \
        -alias androiddebugkey -dname 'CN=Rufus Local Build' -keyalg RSA -keysize 2048 -validity 10000
fi
"$tools/apksigner" sign --ks build/debug.keystore --ks-pass pass:android --v4-signing-enabled false \
    --out "$stage/Rufus.apk" "$stage/aligned.apk"
"$tools/apksigner" verify "$stage/Rufus.apk"
out_dir="$PWD/../../build/android"
mkdir -p "$out_dir"
mv "$stage/Rufus.apk" "$out_dir/Rufus.apk"
printf '%s\n' "$out_dir/Rufus.apk"
