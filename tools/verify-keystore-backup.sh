#!/usr/bin/env bash
#
# Verify that the keystore backup sitting in your password manager actually
# restores. Copy the note's contents to the clipboard, then run this.
#
# Why a script and not a one-liner: copying a verification command to paste it
# into the terminal replaces the clipboard with the command itself, so the check
# ends up testing its own text. Typing a short script name avoids that entirely.
#
#   ./tools/verify-keystore-backup.sh [alias]
#
set -euo pipefail

alias_name="${1:-upload}"
tmp="$(mktemp -t keystore-verify)"
trap 'rm -f "$tmp"' EXIT

# The note may carry metadata lines above a "---" separator; the payload is
# whatever follows it, or the last non-empty line when there is no separator.
payload="$(pbpaste | awk '
  /^---[[:space:]]*$/ { found = 1; buf = ""; next }
  found { buf = buf $0 }
  END { if (found) print buf }
')"

if [ -z "$payload" ]; then
  payload="$(pbpaste | grep -v '^[[:space:]]*$' | tail -1)"
fi

payload="$(printf '%s' "$payload" | tr -d '[:space:]')"

if [ ${#payload} -lt 100 ]; then
  echo "✗ הלוח מכיל ${#payload} תווים בלבד — זה לא נראה כמו גיבוי." >&2
  echo "  העתקת בטעות את הפקודה במקום את תוכן ההערה מהכספת?" >&2
  exit 1
fi

if ! printf '%s' "$payload" | base64 -D > "$tmp" 2>/dev/null; then
  echo "✗ מה שבלוח אינו base64 תקין." >&2
  exit 1
fi

echo "✓ פוענח ל-$(wc -c < "$tmp" | tr -d ' ') בייט. טביעת האצבע המשוחזרת:"
echo
keytool -list -v -keystore "$tmp" -alias "$alias_name" 2>/dev/null | grep -i "SHA256:" \
  || { echo "✗ keytool לא הצליח לקרוא את הקובץ — הסיסמה שגויה, או ש-alias '$alias_name' לא קיים." >&2; exit 1; }
echo
echo "השווה לשורה שרשמת בהערה. זהה = הגיבוי תקף."
