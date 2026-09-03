#!/usr/bin/env bash
# Guard against shipping an APK that cannot reach the network.
#
# Flutter puts INTERNET in the debug and profile manifests but not the release
# one. A release build without it starts fine and fails every socket, which
# looks like broken code rather than a missing permission — so it is checked
# against the built artifact, not the source.
set -euo pipefail
apk="${1:?שימוש: tool/check_apk.sh <path-to-apk>}"
aapt="$(ls "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt2 | sort -V | tail -1)"

perms="$("$aapt" dump permissions "$apk")"
if ! grep -q "android.permission.INTERNET" <<<"$perms"; then
  echo "✗ ל-APK אין הרשאת INTERNET — האפליקציה לא תוכל להתחבר לאף מכשיר." >&2
  exit 1
fi
echo "✓ הרשאת INTERNET קיימת"
