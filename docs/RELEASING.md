# שחרור גרסה

## פעם אחת: יצירת מפתח החתימה

כל APK חייב להיות חתום. **המפתח הזה הוא זהות האפליקציה** — אנדרואיד מתקין
עדכון על גבי גרסה קיימת רק אם שניהם חתומים באותו מפתח. אם הוא הולך לאיבוד,
המשתמשים יצטרכו להסיר ולהתקין מחדש, ואיבדת את היסטוריית הנתונים שלהם.

```sh
keytool -genkey -v -keystore ~/tv-remote-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

שמור אותו **מחוץ לריפו** ובגיבוי נפרד (מנהל סיסמאות או כונן מגובה).
`.gitignore` חוסם `*.jks` ו-`key.properties`, אבל אל תסמוך על זה לבד.

## בנייה מקומית

```sh
cat > mobile/android/key.properties <<EOF
storeFile=/Users/benesh/tv-remote-upload.jks
storePassword=...
keyPassword=...
keyAlias=upload
EOF

cd mobile && flutter build apk --release
```

התוצר: `mobile/build/app/outputs/flutter-apk/app-release.apk`.

להתקנה ישירה בטלפון מחובר בכבל:

```sh
adb install -r mobile/build/app/outputs/flutter-apk/app-release.apk
```

## שחרור אוטומטי דרך GitHub

### פעם אחת: הזנת הסודות

```sh
base64 -i ~/tv-remote-upload.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_STORE_PASSWORD
gh secret set ANDROID_KEY_PASSWORD
gh secret set ANDROID_KEY_ALIAS       # upload
```

### בכל גרסה

עדכן את `version:` ב-`mobile/pubspec.yaml`, ואז:

```sh
git tag android-v0.1.0 && git push origin android-v0.1.0
```

ה-workflow בונה APK חתום, יוצר Release ומצרף אליו את הקובץ. מכיוון שהריפו
ציבורי, הקישור להורדה עובד לכל אחד — בלי חשבון GitHub.

לאפליקציית ה-Mac אותו דבר עם `desktop-v0.1.0`, והתוצר הוא DMG.

## מספור גרסאות

`pubspec.yaml` מחזיק `version: 0.1.0+1`. החלק אחרי ה-`+` הוא `versionCode`,
ו**חייב לעלות בכל שחרור** — אנדרואיד מסרב להתקין עדכון עם מספר שווה או נמוך
יותר. התג צריך להתאים לחלק שלפני ה-`+`.
