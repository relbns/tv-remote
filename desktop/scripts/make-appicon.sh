#!/usr/bin/env bash
# Build the macOS app icon from the same 1024px artwork the phone app uses, so
# the two platforms are visibly one product. Needs only macOS built-in tools.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/../mobile/assets/icon/icon.png"
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
