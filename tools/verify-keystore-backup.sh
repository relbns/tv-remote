#!/usr/bin/env bash
#
# Verify that the keystore backup in your password manager actually restores.
#
#   ./tools/verify-keystore-backup.sh                 # read the clipboard
#   ./tools/verify-keystore-backup.sh --file note.txt # read a file instead
#   ./tools/verify-keystore-backup.sh --alias mykey
#   ./tools/verify-keystore-backup.sh --expect 77:7B:F0:...
#
# When the note itself carries a "SHA256:" line, it is compared automatically —
# nobody should be checking 32 hex pairs by eye.
#
# Why a script and not a one-liner: copying a verification command in order to
# paste it into the terminal replaces the clipboard with the command itself, so
# the check ends up testing its own text.
#
set -euo pipefail

alias_name="upload"
source_file=""
expected=""

while [ $# -gt 0 ]; do
  case "$1" in
    --alias) alias_name="$2"; shift 2 ;;
    --file)  source_file="$2"; shift 2 ;;
    --expect) expected="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "אפשרות לא מוכרת: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$source_file" ]; then
  [ -r "$source_file" ] || { echo "✗ אין קובץ קריא בנתיב: $source_file" >&2; exit 1; }
  raw="$(cat "$source_file")"
  origin="הקובץ $source_file"
else
  raw="$(pbpaste)"
  origin="הלוח"
fi

# The note may carry metadata lines above a "---" separator; the payload is
# whatever follows it, or the last non-empty line when there is no separator.
payload="$(printf '%s\n' "$raw" | awk '
  /^---[[:space:]]*$/ { found = 1; buf = ""; next }
  found { buf = buf $0 }
  END { if (found) print buf }
')"
separator_found="כן"

if [ -z "$payload" ]; then
  separator_found="לא"
  payload="$(printf '%s\n' "$raw" | grep -v '^[[:space:]]*$' | tail -1)"
fi

payload="$(printf '%s' "$payload" | tr -d '[:space:]')"

normalise() { printf '%s' "$1" | tr -d '[:space:]' | tr 'a-f' 'A-F' | sed 's/.*SHA256://'; }

if [ -z "$expected" ]; then
  expected="$(printf '%s\n' "$raw" | grep -i 'SHA256' | head -1 || true)"
fi
expected="$(normalise "$expected")"

describe() {
  echo "  מקור:            $origin"
  echo "  תווים בסך הכל:   $(printf '%s' "$raw" | wc -c | tr -d ' ')"
  echo "  שורות:           $(printf '%s\n' "$raw" | grep -c '' | tr -d ' ')"
  echo "  מפריד --- נמצא:  $separator_found"
  echo "  אורך המטען:      ${#payload}"
  if [ ${#payload} -gt 0 ]; then
    # A masked preview: enough to recognise, not enough to leak.
    echo "  תחילת המטען:     $(printf '%s' "$payload" | cut -c1-14)…"
  fi
}

if [ ${#payload} -lt 100 ]; then
  echo "✗ לא נמצא גיבוי." >&2
  describe >&2
  echo >&2
  echo "  סיבות נפוצות:" >&2
  echo "   · Bitwarden מוגדר לנקות את הלוח אוטומטית אחרי כמה שניות" >&2
  echo "   · נלחץ 'העתק סיסמה' במקום 'העתק הערה' (Copy Note)" >&2
  echo "   · ה-base64 נשמר בשדה מותאם ולא בשדה ההערות" >&2
  echo >&2
  echo "  עוקף: הדבק את ההערה לקובץ והרץ" >&2
  echo "   $0 --file ~/note.txt" >&2
  exit 1
fi

tmp="$(mktemp -t keystore-verify)"
trap 'rm -f "$tmp"' EXIT

if ! printf '%s' "$payload" | base64 -D > "$tmp" 2>/dev/null; then
  echo "✗ המטען אינו base64 תקין." >&2
  describe >&2
  exit 1
fi

echo "✓ פוענח ל-$(wc -c < "$tmp" | tr -d ' ') בייט."
echo

actual_line="$(keytool -list -v -keystore "$tmp" -alias "$alias_name" 2>/dev/null | grep -i "SHA256:" | head -1 || true)"
if [ -z "$actual_line" ]; then
  echo "✗ keytool לא הצליח לקרוא את הקובץ — סיסמה שגויה, או ש-alias '$alias_name' לא קיים." >&2
  exit 1
fi

actual="$(normalise "$actual_line")"
echo "  משוחזר:  $actual"

if [ -z "$expected" ]; then
  echo
  echo "בהערה אין שורת SHA256, אז אין למה להשוות. הרץ על הקובץ המקורי:"
  echo "  keytool -list -v -keystore ~/tv-remote-upload.jks -alias $alias_name | grep -i SHA256"
  echo "והוסף את התוצאה להערה."
  exit 0
fi

echo "  בהערה:   $expected"
echo
if [ "$actual" = "$expected" ]; then
  echo "✓ זהות — הגיבוי תקף וניתן לשחזור."
else
  echo "✗ שונות. מה שבכספת אינו המפתח הזה." >&2
  exit 1
fi
