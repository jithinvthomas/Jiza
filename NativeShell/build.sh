#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk=${1:?iphoneos or iphonesimulator required}
arch=${2:?architecture required}
case "$sdk" in iphoneos|iphonesimulator) ;; *) echo "Unsupported SDK" >&2; exit 1;; esac
source_commit=d687d2cebdaa71967b3c12bebc8b1858984a6b43
source_sha256=422641dbc42b12970fe4dd87e51198915bcf7424636d177b9238d563a8d73fc5
root="$PWD/NativeBuild/Shell"
mkdir -p "$root"
archive="$root/ios-system-source.tar.gz"
if [ ! -f "$archive" ]; then
    curl --fail --location --retry 3 "https://codeload.github.com/holzschu/ios_system/tar.gz/$source_commit" -o "$archive"
fi
echo "$source_sha256  $archive" | shasum -a 256 -c -
source_dir="$root/source"
mkdir -p "$source_dir"
tar -xzf "$archive" --strip-components=1 -C "$source_dir"
output="$root/$sdk"
mkdir -p "$output"
# Keep the upstream ABI used by the pinned command frameworks, but compile the
# core with command logging disabled for both Debug and Release app builds.
xcodebuild -project "$source_dir/ios_system.xcodeproj" -target ios_system \
    -configuration Release -sdk "$sdk" ARCHS="$arch" ONLY_ACTIVE_ARCH=YES \
    IPHONEOS_DEPLOYMENT_TARGET=16.0 CODE_SIGNING_ALLOWED=NO \
    GCC_PREFIX_HEADER="$PWD/NativeShell/QuietLogging.h" GCC_PRECOMPILE_PREFIX_HEADER=NO \
    CONFIGURATION_BUILD_DIR="$output" > "$root/build-$sdk.log" 2>&1 || {
        tail -100 "$root/build-$sdk.log"; exit 1;
    }
artifact="$PWD/Packages/JizaShell/Artifacts/ios_system.xcframework"
if [ -e "$artifact" ]; then
    echo "Shell artifact already exists; use a fresh checkout for a different SDK." >&2
    exit 1
fi
mkdir -p "$(dirname "$artifact")"
xcodebuild -create-xcframework -framework "$output/ios_system.framework" -output "$artifact"
