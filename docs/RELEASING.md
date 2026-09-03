# שחרור גרסה

לפני הפעם הראשונה צריך מפתח חתימה וסודות ב-CI — ראה [SIGNING.md](SIGNING.md).

## מספור

`mobile/pubspec.yaml` מחזיק שורה כזו:

```yaml
version: 0.1.0+1
```

החלק שאחרי ה-`+` הוא `versionCode`, ו**חייב לעלות בכל שחרור** — אנדרואיד מסרב
להתקין עדכון עם מספר שווה או נמוך יותר. החלק שלפניו חייב להתאים לתגית.

## שחרור

```sh
# 1. עדכן את הגרסה
vim mobile/pubspec.yaml        # 0.1.0+1  →  0.2.0+2

git commit -am "גרסה 0.2.0"
git push

# 2. תייג ודחוף
git tag android-v0.2.0
git push origin android-v0.2.0
```

זה מפעיל את `release-android.yml`: בונה APK חתום, יוצר Release, ומצרף אליו את
הקובץ בשם `tv-remote-0.2.0.apk`. מכיוון שהריפו ציבורי, קישור ההורדה עובד לכל
אחד — בלי חשבון GitHub.

לאפליקציית ה-Mac אותו דבר עם `desktop-v0.2.0`, והתוצר הוא DMG.

## תגיות נושאות קידומת

| תגית | מה נבנה |
| --- | --- |
| `android-v*` | APK חתום |
| `desktop-v*` | DMG ל-Apple Silicon |

שתי האפליקציות משתחררות בנפרד מאותו ריפו, וכל workflow מסונן לפי נתיבים כך
שקומיט ב-`desktop/` לא מפעיל בדיקות של `mobile/` ולהפך. שינוי ב-`shared/`
מפעיל את שניהם, כי הוא נצרב לשניהם.

## בנייה מקומית

```sh
cd mobile && flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## ה-DMG לא חתום

אין חשבון מפתחים של Apple, ולכן macOS יחסום את הקובץ בפתיחה הראשונה. לחיצה
ימנית ← **Open** ← **Open** שוב, פעם אחת בלבד. זה מתועד גם בגוף ה-Release.

## מעקב

```sh
gh run list --limit 5      # מצב ה-workflows
gh release list            # שחרורים קיימים
```

אם שחרור נכשל, `gh run view --log-failed` מראה איפה. הסיבה הנפוצה ביותר היא
סוד חסר או שגוי — [SIGNING.md](SIGNING.md#סודות-ל-ci).
