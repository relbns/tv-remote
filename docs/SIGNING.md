# מפתח החתימה

כל APK חייב להיות חתום. המפתח הזה הוא **זהות האפליקציה**: אנדרואיד מתקין
עדכון על גבי גרסה קיימת רק אם שניהם חתומים באותו מפתח.

אין מנגנון שחזור. גוגל לא מחזיקה עותק, ואי אפשר להנפיק מחדש. אם הוא אובד,
כל מי שהתקין חייב להסיר ולהתקין מחדש — ואיבד את הנתונים המקומיים שלו.
לכן כל המסמך הזה הוא בעצם על גיבוי.

## יצירה

```sh
keytool -genkey -v -keystore ~/tv-remote-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### מה עונים על כל שאלה

**`Enter keystore password:`** — סיסמה **חדשה שאתה ממציא**, לא סיסמה אישית
קיימת. שים לב שלא מופיע כלום על המסך בזמן ההקלדה, אפילו לא כוכביות — זה לא
תקוע, ככה `keytool` מתנהג. שמור אותה מיד במנהל סיסמאות.

**שאלות הזהות** — נצרבות בתעודה אבל אינן נאכפות באפליקציה אישית:

| שאלה | ערך סביר |
| --- | --- |
| `first and last name` | השם שלך |
| `organizational unit` | Enter (ריק) |
| `organization` | שם הפרויקט |
| `City` / `State` | Enter |
| `two-letter country code` | `IL` |
| `Is CN=... correct?` | `yes` |

בשורה האחרונה חייבים להקליד `yes` במלואו. `y` לא יתקבל, והתהליך יחזור לשאול
הכל מחדש.

**`Enter key password for <upload>`** — לחץ Enter כדי שתהיה זהה לסיסמת הקובץ.
זה מה שה-workflow מצפה לו.

### טביעת האצבע

זה המזהה שמאפשר לוודא בעתיד ששחזרת את המפתח הנכון. קח אותו עכשיו:

```sh
keytool -list -v -keystore ~/tv-remote-upload.jks -alias upload | grep -i SHA256
```

## גיבוי

מפתח שקיים בעותק אחד הוא מפתח שאבד. שני עותקים בלתי תלויים הם המינימום.

### עותק מקומי

```sh
mkdir -p ~/Documents/Backups
cp ~/tv-remote-upload.jks ~/Documents/Backups/
```

תיקייה מסונכרנת ל-iCloud או ל-Drive בסדר גמור — הקובץ מוצפן בסיסמה משלו.
**לא** בתוך הריפו: `.gitignore` חוסם `*.jks` ו-`key.properties`, אבל אל תסמוך
על זה לבד.

### כספת סיסמאות

קבצים מצורפים ב-Bitwarden הם תכונת Premium, אבל אין צורך בהם: keystore טיפוסי
הוא ~2.7KB, שהם **~3,700 תווים ב-base64** — הרבה מתחת למגבלת שדה ההערות
(10,000, ובפועל נמוך יותר, כי המגבלה חלה על הערך המוצפן).

```sh
base64 -i ~/tv-remote-upload.jks | pbcopy
```

צור **Secure Note** והדבק. הוסף מעליו את המטא-נתונים — הקובץ לבדו חסר ערך:

```
alias:       upload
storePass:   <הסיסמה>
keyPass:     <אותה סיסמה>
SHA256:      <טביעת האצבע>
נוצר:        2026-09-03
---
<כאן ה-base64>
```

הסקריפט מזהה את המפריד `---` ומשווה את שורת ה-SHA256 לבד.

> **אל תשתמש ב-Bitwarden Send** לזה. הוא נראה מתאים אבל Sends פגים אחרי 31 יום
> לכל היותר. זה שיתוף, לא גיבוי.

הקובץ והסיסמה יושבים באותו פריט, כלומר פריצה לכספת נותנת את שניהם. לאפליקציה
ביתית זו התמורה הנכונה: הסיכון לאבד את המפתח גדול בהרבה. אם זה מפריע, שמור את
הסיסמה בפריט נפרד.

## אימות — אל תדלג

גיבוי שלא נבדק אינו גיבוי. העתק את תוכן ההערה מהכספת, ואז:

```sh
./tools/verify-keystore-backup.sh
```

הסקריפט מפענח את מה שבלוח, קורא את הקובץ המשוחזר, ומשווה את טביעת האצבע שלו
לזו שרשמת בהערה.

**אם הלוח מתנקה אוטומטית** (הגדרה נפוצה במנהלי סיסמאות), הדבק לקובץ והרץ:

```sh
./tools/verify-keystore-backup.sh --file ~/note.txt
```

> זה סקריפט ולא שורת פקודה מסיבה מעשית: העתקת פקודה שקוראת מהלוח, כדי להדביק
> אותה בטרמינל, **דורסת את הלוח** — והבדיקה בודקת את הטקסט של עצמה ונכשלת.
> שם קצר שאפשר להקליד ביד עוקף את זה.

## שימוש בבנייה מקומית

```sh
cat > mobile/android/key.properties <<EOF
storeFile=$HOME/tv-remote-upload.jks
storePassword=<הסיסמה>
keyPassword=<הסיסמה>
keyAlias=upload
EOF

cd mobile && flutter build apk --release
```

בלי `key.properties` הבנייה נופלת חזרה למפתח ה-debug, כדי שקלון טרי של הריפו
עדיין ירוץ. כלומר **בנייה שמצליחה אינה מוכיחה שהיא חתומה נכון** — בדוק:

```sh
# apksigner יושב ב-build-tools ואינו ב-PATH כברירת מחדל
APKSIGNER=$(ls ~/Library/Android/sdk/build-tools/*/apksigner | sort -V | tail -1)
"$APKSIGNER" verify --print-certs \
  mobile/build/app/outputs/flutter-apk/app-release.apk
```

בפלט צריך להופיע ה-DN שלך. אם כתוב `CN=Android Debug` — הבנייה נפלה חזרה
למפתח ה-debug, כלומר `key.properties` לא נמצא או שהנתיב בו שגוי.

> `keytool -printcert -jarfile` **לא** יעבוד כאן: הוא קורא רק חתימת JAR מהדור
> הראשון, ו-APK מודרני חתום בסכימה v2/v3. הוא פשוט לא ידפיס כלום.

## סודות ל-CI

```sh
cd ~/Workspace/tv-remote
base64 -i ~/tv-remote-upload.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_STORE_PASSWORD    # יבקש להדביק
gh secret set ANDROID_KEY_PASSWORD
gh secret set ANDROID_KEY_ALIAS         # הערך: upload
gh secret list
```

השתמש בצורה שמבקשת להדביק, לא ב-`echo "סיסמה" | gh secret set` — השנייה משאירה
את הסיסמה בהיסטוריית ה-shell.

ה-workflow כותב את המפתח לדיסק לצורך הבנייה בלבד; הרנר נמחק אחריה.

## אם המפתח אבד

אין שחזור. מה שנשאר:

1. צור מפתח חדש ו**שנה את `applicationId`** — למשל `co.singalong.tv_remote2`.
   בלי זה אנדרואיד יסרב להתקין על גבי הגרסה הישנה.
2. מי שהתקין צריך להסיר ולהתקין מחדש, ולצמד מחדש את המכשירים.

לכן: גבה, ואמת שהגיבוי עובד.

## תקלות נפוצות

| שגיאה | סיבה |
| --- | --- |
| `Keystore was tampered with, or password was incorrect` | סיסמה שגויה — או שהקובץ נחתך בהעתקה |
| `Alias <upload> does not exist` | ה-alias שונה. בדוק עם `keytool -list -keystore <file>` |
| `error decoding base64 input stream` | הלוח לא מכיל את הגיבוי (נדרס, או נוקה אוטומטית) |
| ה-APK חתום ב-`androiddebugkey` | `key.properties` לא נמצא או שהנתיב בו שגוי |
