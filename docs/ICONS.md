# אייקונים

## מה צריך לייצר

שני קבצים בלבד. כל השאר נגזר מהם אוטומטית.

| קובץ | גודל | רקע | לאן זה הולך |
| --- | --- | --- | --- |
| `mobile/assets/icon/icon.png` | 1024×1024 | אטום | האייקון הריבועי הישן, קצה לקצה |
| `mobile/assets/icon/icon_foreground.png` | 1024×1024 | **שקוף** | שכבת החזית של Adaptive Icon |

לאפליקציית ה-Mac צריך בנוסף `desktop/build/icon.png` בגודל 1024×1024.

## האילוץ שהכי הרבה אנשים מפספסים

אנדרואיד **חותך כשליש מכל צד** של שכבת החזית — כי כל משגר מסכה אותה לצורה
אחרת (עיגול, ריבוע מעוגל, טיפה). כלומר בקובץ 1024×1024, כל מה שחשוב חייב
לשבת בריבוע המרכזי בגודל **~660×660**, והשוליים מסביב צריכים להיות ריקים.

אם תיתן ל-AI לייצר אייקון "מלא" ותשתמש בו כשכבת חזית, הקצוות שלו ייחתכו.

הכלי מרפד את החזית ב-16% מעצמו (`adaptive_icon_foreground_inset`), אז אם
ציירת עם שוליים סבירים אתה מכוסה. אם היצירה יוצאת קטנה מדי — הורד את הערך.

## פרומפטים

הוסף לכל פרומפט את השורות האלה — הן מה שמפריד בין אייקון לתמונה:

> flat vector app icon, single bold silhouette, solid shapes only, no text,
> no letters, no photorealism, no drop shadows, no thin lines, centered
> composition with generous empty margin, must stay legible at 48 pixels,
> 1024x1024

**רעיון א׳ — טבעת הניווט.** הצורה הכי מזוהה עם שלט, ועובדת מצוין כסילואטה:

> A minimalist app icon of a directional pad: one thick circular ring with a
> solid filled circle at its centre, four small triangular arrows carved out of
> the ring at top, bottom, left and right. Deep indigo shape on a transparent
> background.

**רעיון ב׳ — מסך עם גל.** מרמז על טלוויזיה ועל שליטה אלחוטית:

> A minimalist app icon: a rounded-rectangle television screen outline with two
> concentric signal arcs radiating from its top-right corner. Bold even stroke
> weight, deep indigo on a transparent background.

**רעיון ג׳ — כפתור ההפעלה כמסך.** הכי נקי, הכי קל לזיהוי בגודל קטן:

> A minimalist app icon: a power symbol — a thick circle broken at the top with
> a vertical bar rising through the gap — where the circle is subtly squared off
> into a television shape. Deep indigo on a transparent background.

לשכבת **הרקע** אל תשתמש ב-AI: היא מוגדרת כצבע אחיד ב-`pubspec.yaml`
(`adaptive_icon_background: "#0B1020"`). זה נקי יותר וגם קטן יותר.

לגרסת `icon.png` האטומה — קח את אותה יצירה, הנח אותה על אותו צבע רקע, ומלא
את הריבוע קצה לקצה.

## הפקה

```sh
cd mobile
dart run flutter_launcher_icons
```

זה כותב את כל צפיפויות ה-mipmap, את `ic_launcher_adaptive`, ואת שכבת
המונוכרום ל-Themed Icons של אנדרואיד 13+.

## בדיקה לפני שמתחייבים

1. **הקטן ל-48 פיקסלים** והסתכל. אם לא ברור מה זה — הצורה מורכבת מדי.
2. **בדוק את החיתוך:** התקן על הטלפון והחלף צורת אייקונים בהגדרות המשגר.
3. **מצב כהה ובהיר** — הרקע `#0B1020` כהה, אז ודא שהחזית בהירה מספיק.
