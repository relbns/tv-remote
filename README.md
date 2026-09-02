# שלט טלוויזיה · TV Remote

שלט לממירי Android TV ולטלוויזיות חכמות, לשולחן העבודה ולנייד. שולט במכשירים
ישירות ברשת הביתית — בלי ענן, בלי חשבון, בלי שרת באמצע.

| | |
| --- | --- |
| **desktop/** | אפליקציית שורת־תפריטים ל-macOS (Electron) |
| **mobile/** | אפליקציית Android (Flutter; תיקיית iOS מוכנה לעתיד) |
| **shared/** | קטלוג אפליקציות ומיפוי מקשים — מקור אמת אחד לשני הלקוחות |

## פרוטוקולים נתמכים

| מכשיר | פרוטוקול | פורטים | צימוד |
| --- | --- | --- | --- |
| ממיר yes / Google TV / Android TV | Android TV Remote v2 (protobuf over TLS) | 6466, 6467 | קוד בן 6 תווים |
| טלוויזיית LG (webOS) | SSAP over WebSocket | 3000, 3001 | אישור על המסך |
| טלוויזיית Samsung (Tizen 2016+) | JSON over WebSocket | 8002 | אישור על המסך |

טלוויזיה בלי שליטה ברשת נשלטת דרך הממיר המחובר אליה ב-HDMI, בתקן CEC.

## הנתונים המשותפים

`shared/keys.json` ו-`shared/apps.json` הם מקור האמת. שני הלקוחות **מעתיקים**
אותם פנימה בזמן בנייה — Electron לא יכול לארוז קבצים מחוץ לתיקייתו, ו-Flutter
לא יכול להכריז על asset מחוץ לחבילה. העותקים מיוצרים ומוחרגים מ-git.

```sh
cd desktop && npm run shared     # → desktop/src/shared/
cd mobile  && tool/sync_shared.sh # → mobile/assets/shared/
```

מכיוון ששניהם קוראים את אותה טבלה, מיפוי מקש לא יכול להיווצר שונה בין
הפלטפורמות. `desktop/scripts/check.js` מאמת שכל פקודה שהניתוב מפנה אליה באמת
קיימת בטבלאות.

## פיתוח

```sh
# macOS
cd desktop && npm install && npm start
npm run check                     # בדיקת טעינה ותקינות הנתונים המשותפים

# Android
cd mobile && flutter pub get && flutter run
```

## שחרורים

תגיות נושאות קידומת, כך ששתי האפליקציות משתחררות בנפרד מאותו ריפו:

| תגית | תוצר |
| --- | --- |
| `android-v1.2.0` | APK חתום, מצורף ל-Release |
| `desktop-v1.2.0` | DMG ל-Apple Silicon |

## מדריכים

| | |
| --- | --- |
| [docs/RELEASING.md](docs/RELEASING.md) | מפתח חתימה, בנייה, ושחרור אוטומטי בתגית |
| [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) | הפצה בלי חנות, וחשבון ההפצה המוגבלת החינמי |
| [docs/ICONS.md](docs/ICONS.md) | מה לייצר, פרומפטים ל-AI, והאילוץ של Adaptive Icon |

## רישיון

MIT
