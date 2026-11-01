#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
flutter build linux --release

out="$root/build/linux/package"
stage="$out/zerk-play"
rm -rf "$out"
mkdir -p "$stage"
cp -r build/linux/x64/release/bundle/. "$stage/"
cp linux/packaging/cloud.zerk.play.desktop linux/packaging/cloud.zerk.play.png "$stage/"
tar -C "$out" -czf "$out/ZerkPlay-Public-Linux-x64.tar.gz" zerk-play
sha256sum "$out/ZerkPlay-Public-Linux-x64.tar.gz"
