# אימות תקציר הצימוד מול מימוש הייחוס

תקציר הצימוד הוא הנקודה היחידה בפרוטוקול שאי אפשר להסיק את נכונותה מקריאת
הקוד — היא חייבת להסכים בייט-בייט עם מימוש שידוע כעובד מול חומרה. הבדיקה
ב-`test/pairing_secret_test.dart` מקבעת תקציר שכבר הושווה כך.

להריץ את ההשוואה מחדש (למשל אחרי שינוי בחישוב):

```sh
DIR=$(mktemp -d)

# 1. Dart מייצר תעודות וכותב את התקציר שלו
XCHECK_DIR="$DIR" flutter test test/crosscheck_digest_test.dart
```

`crosscheck_digest_test.dart` אינו נשמר בריפו כי הוא דורש `XCHECK_DIR` וייכשל
ב-CI. הוא נוצר לפי הצורך: הוא מייצר שתי תעודות, כותב אותן ל-`$DIR`, ומחשב את
התקציר עבור קוד קבוע.

```sh
# 2. Node מחשב את אותו תקציר מאותן תעודות
cd "$DIR"
ln -s /path/to/repo/desktop/node_modules node_modules
node node-reference.mjs "$DIR"
```

`node-reference.mjs` משחזר את מקטעי הבייטים מ-`pairing-manager.ts` של
[kud/androidtv-remote](https://github.com/kud/androidtv-remote), ושואב את
המודולוס והמעריך עם node-forge כפי ש-Node's TLS `getCertificate()` היה מדווח
אותם.

## הפרט שקל לפספס

מימוש הייחוס בונה את המעריך כך:

```js
Buffer.from("0" + exponent.slice(2), "hex")
```

`exponent` מגיע מ-Node בצורה `"0x10001"`. חיתוך שני התווים הראשונים מותיר
`"10001"`, וההוספה של `"0"` מייצרת `"010001"` — כלומר **שלושה** בייטים עבור
65537, לא שניים. השמטת הריפוד מייצרת תקציר תקין למראה שהתיבה תמיד דוחה.

ב-Dart זה `bigIntToBytes`, שמרפד לאורך זוגי.
