#!/usr/bin/env bash
# Build the .icns from the plate make-icons.py draws. That plate carries the
# phone app's ring inside Apple's rounded icon shape — a full-bleed square, which
# is correct on Android, reads as a foreign object in the Dock.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/assets/appicon-1024.png"
out="$here/assets/icon.icns"
work="$(mktemp -d)/icon.iconset"
mkdir -p "$work"
trap 'rm -rf "$(dirname "$work")"' EXIT

for size in 16 32 128 256 512; do
  sips -z $size $size "$src" --out "$work/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$src" --out "$work/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$work" -o "$out"
echo "✓ $out"
