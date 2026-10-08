#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${1:-iphoneos}"
arch="${2:-arm64}"
brew list boost >/dev/null 2>&1 || brew install boost
brew list cmake >/dev/null 2>&1 || brew install cmake
mkdir -p NativeBuild
if [ ! -d NativeBuild/libtorrent ]; then
  git clone --depth 1 --branch v2.0.11 --recurse-submodules --shallow-submodules https://github.com/arvidn/libtorrent.git NativeBuild/libtorrent
fi
cmake -S TorrentNative -B "NativeBuild/$sdk" \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES="$arch" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DCMAKE_BUILD_TYPE=Release \
  -DTORRENT_SOURCE="$PWD/NativeBuild/libtorrent" -DBOOST_ROOT="$(brew --prefix boost)"
cmake --build "NativeBuild/$sdk" --parallel 3
libtool -static -o "NativeBuild/$sdk/libJizaTorrentCombined.a" "NativeBuild/$sdk/libJizaTorrent.a" "NativeBuild/$sdk/libtorrent/libtorrent-rasterbar.a"
cp NativeBuild/libtorrent/LICENSE Licenses/libtorrent.txt
