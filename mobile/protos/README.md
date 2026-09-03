# קבצי הפרוטוקול

סכמות ה-protobuf של **Android TV Remote v2**. הפרוטוקול אינו מתועד רשמית על ידי
גוגל; הסכמות האלה פוענחו מהנדסה לאחור על ידי
[louis49/androidtv-remote](https://github.com/louis49/androidtv-remote) (MIT),
ומגיעות לכאן דרך [@kud/androidtv-remote](https://github.com/kud/androidtv-remote).

| קובץ | תפקיד |
| --- | --- |
| `pairingmessage.proto` | לחיצת היד בפורט 6467 — הצגת הקוד על המסך וקבלת התעודה |
| `remotemessage.proto` | הפעלת השלט בפורט 6466 — מקשים, טקסט, אפליקציות, ומצב המכשיר |

## הפקת מחלקות Dart

```sh
cd mobile && tool/gen_proto.sh
```

הפלט נכנס ל-`lib/src/proto/` ו**נשמר בגיט**, כדי ש-CI וקלון טרי לא יצטרכו
`protoc` מותקן.
