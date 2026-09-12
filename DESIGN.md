# نظام تصميم تيما المالي — سطح مكتب ويندوز

مرجع مختصر لقواعد الواجهة بعد إعادة التصميم. الهدف: مظهر أنيق وجذّاب
مناسب لشاشة مكتبية تُستخدم بالفأرة ولوحة المفاتيح، لا بالّلمس.

## المبادئ

1. **مكتبي أولاً.** الأهداف الصغيرة مقبولة (38px)، الكثافة مطلوبة،
   والمؤشر يتفاعل عند المرور (hover). لا نستخدم أنماط الهواتف.
2. **مسطّح مع حدود رفيعة.** الأسطح تُفصل بحدّ بلون `AppUi.border` لا
   بظل مرتفع. لا يوجد أي `elevation` أكبر من صفر في صفحات العرض.
3. **رموز لا أرقام.** كل نصف قطر ومسافة وارتفاع يأتي من `AppDims`.
4. **ألوان من النظام.** لا `Colors.grey/red/blue`. الاستثناء الوحيد هو
   `Colors.white` كلون أمامي فوق تعبئة ملوّنة داكنة.
5. **عربية أولاً.** الاتجاه RTL مفروض من الجذر، والخط `NotoNaskhArabic`.

## الرموز

### المقاسات — `AppDims` في `lib/core/theme/app_theme.dart`

| الرمز | القيمة | الاستخدام |
|---|---|---|
| `radiusSm` | 7 | الأزرار، الشارات، الحقول الصغيرة |
| `radius` | 10 | البطاقات واللوحات — الافتراضي |
| `radiusLg` | 14 | الحوارات واللوحات الرئيسية |
| `titleBarHeight` | 48 | شريط العنوان بمسار التنقل |
| `sidebarWidth` | 268 | الشريط الجانبي مفتوحاً |
| `sidebarCollapsedWidth` | 60 | الشريط الجانبي مطويّاً |
| `navItemHeight` | 38 | عنصر التنقل |
| `controlHeight` | 38 | الأزرار والحقول |
| `contentMaxWidth` | 1180 | أقصى عرض للمحتوى |
| `sidePanelWidth` | 320 | اللوحة الجانبية المساعدة (نص الحافظة) |
| `pagePadding` | 20 | حشو الصفحة الأفقي |
| `sectionGap` | 22 | الفجوة بين الأقسام |

### الألوان — `AppColors` في `lib/core/theme/app_colors.dart`

- **الهوية:** `brandGreen` ‏`0xFF0E6B58` زمردي، `brandGold` ‏`0xFFD4A64A` ذهبي،
  ولكلٍّ تدرّجات `Dark` / `Light` / `Soft`.
- **المحايدات:** سلّم `neutral0` … `neutral950` مع أسماء مختصرة
  `ink` / `slate` / `mist`.
- **الدلالات:** `success` / `error` / `warning` / `info` ولكلٍّ نسخة `Soft`
  تُستخدم كخلفية للشارات.
- **الأسطح:** `lightBackground…lightBorderStrong` و
  `darkBackground…darkBorderStrong`.

## المكوّنات — `lib/presentation/widgets/app_ui.dart`

مساعدات ثابتة تقرأ السمة الحالية:
`AppUi.isDark/border/borderStrong/surface/sunken/elevated/hover/accent/`
`textPrimary/textSecondary/tone/softFill/softShadow/raisedShadow/`
`pageBackground/panelDecoration/accentPanelDecoration`.

عناصر جاهزة:

| المكوّن | الغرض |
|---|---|
| `TimaPageBackground` | خلفية الصفحة المتدرّجة |
| `TimaContentWidth` | تقييد عرض المحتوى على الشاشات العريضة |
| `TimaPanel` | لوحة مسطّحة بحدّ رفيع، تدعم `onTap` |
| `TimaHeaderPanel` | ترويسة متدرّجة بأيقونة وعنوان ووصف |
| `TimaSectionTitle` | عنوان قسم داخل لوحة |
| `TimaStatusPill` | شارة حالة ملوّنة |
| `TimaMetricCard` | بطاقة مؤشّر رقمي للوحة المعلومات |
| `TimaKeyValue` | سطر مفتاح/قيمة |
| `TimaToolbar` | شريط أدوات أفقي |
| `TimaEmptyState` | حالة فراغ بأيقونة ورسالة وإجراء |
| `TimaLoader` | مؤشّر تحميل برسالة |

### لوحة نص الحافظة — `lib/presentation/widgets/clipboard_words_panel.dart`

تعبئة نماذج الحركات من رسالة منسوخة بالسحب والإفلات:

| المكوّن | الغرض |
|---|---|
| `ClipboardWordsPanel` | تقرأ الحافظة تلقائياً وتعرض النص كلمةً كلمة، بتحديد متعدد وسحب |
| `ClipboardDropTarget` | يغلّف حقلاً ليقبل الكلمات المُفلتة مع إبراز/رفض مرئي |
| `ClipboardDragScope` | يبثّ النص المسحوب حالياً لتُبرز الحقول التي تقبله |
| `ClipboardAssignTarget` | زرّ تعبئة سريعة («إلى الاسم») في شريط التحديد |

المنطق النصّي (تقطيع، استخراج أرقام، تعرّف على العملات) في
`lib/core/utils/clipboard_text.dart` بلا اعتماد على Flutter، وله اختبارات في
`test/clipboard_text_test.dart`.

قواعد التفاعل: نقرة = تحديد/إلغاء، Shift+نقرة = مدى، سحب كلمة محدّدة = سحب
التحديد كلّه، نقر مزدوج = تعبئة ذكية (رقم → مبلغ، عملة → عملة، غير ذلك → اسم).
الكلمة المستخدمة تبهت مع علامة ✓. تُقيَّد قراءة الحافظة بالنافذة النشطة
والصفحة الحالية، وتُتجاهل إن كان النص جزءاً مما هو معروض أصلاً.

## القواعد التي يجب الالتزام بها

- **لا `BorderRadius.circular(<رقم>)`** للقيم 8/10/12/14/16/20 — استخدم
  رموز `AppDims`. القيم الصغيرة (3–6) مسموحة للزخارف الدقيقة.
- **تجاوز `shape:` على `Card` يُسقط الحدّ الافتراضي** — أعد
  `side: BorderSide(color: AppUi.border(context))` يدوياً.
- **`withOpacity` مهجور** في Flutter 3.32 — استخدم `withValues(alpha:)`.
- **كل ملف يستخدم `AppDims.`** يجب أن يستورد `core/theme/app_theme.dart`،
  وكل ملف يستخدم `AppColors.` يستورد `core/theme/app_colors.dart`.
- **الحوارات مركزية لا سفلية.** على سطح المكتب نستخدم `showDialog` مع
  `ConstrainedBox`، لا `showModalBottomSheet`.
- **المرشّحات ظاهرة دائماً** كشريط داخل الصفحة، لا داخل ورقة منبثقة.

## الاستجابة للعرض

| الشاشة | السلوك |
|---|---|
| تسجيل الدخول | عمودان عند ‎≥900px، عمود واحد دونها |
| لوحة المعلومات | تخطيط عريض فوق ‎980px |
| شبكة الصناديق | 4 / 3 / 2 / 1 عمود عند ‎≥1280 / ‎≥950 / ‎≥620 / أقل |
| نماذج الحركات | مقيّدة بـ‎ 880px ووسط الشاشة |
| حركة التسليم | لوحة الحافظة بجانب النموذج عند ‎≥1000px، وفوقه دونها |
| بقية الصفحات | مقيّدة بـ‎ `AppDims.contentMaxWidth` |

مقياس النص مثبّت بين ‎0.9 و‎1.2 عبر `MediaQuery.withClampedTextScaling`
في `main.dart`، لذا يمكن للتخطيطات افتراض أبعاد نصّ شبه ثابتة.

## اختصارات لوحة المفاتيح

| الاختصار | الإجراء |
|---|---|
| `F5` | تحديث الصفحة الحالية |
| `Ctrl` + `B` | طيّ الشريط الجانبي أو فتحه |
| `Ctrl` + `H` | العودة إلى لوحة المعلومات |

## التحقّق

بيئة العمل هذه لا تحتوي على Flutter SDK، لذا يُستعاض عن
`flutter analyze` بخمسة فاحصات في `/tmp`:

```bash
python3 /tmp/dartcheck.py $(find lib -name "*.dart") \
  && python3 /tmp/treecheck.py $(find lib -name "*.dart") \
  && python3 /tmp/symcheck.py lib \
  && python3 /tmp/importcheck.py \
  && python3 /tmp/widgetcheck.py
```

تفحص بالترتيب: توازن الأقواس والنصوص، اتساق شجرة الودجات ومطابقة
الإغلاقات، صحّة كل إشارة `Cls.member`، اكتمال الاستيرادات، وصحّة
المعاملات المسمّاة في نداءات مكوّنات `Tima*`.

> ملاحظة: لم يُشغَّل مترجم Dart على هذا الكود. يلزم `flutter analyze`
> و`flutter build windows` على جهاز فيه SDK قبل الإصدار.

### مزالق كشفها المترجم

هذه أخطاء لا تلتقطها الفاحصات النصّية، فانتبه لها عند أي تعديل واسع:

- **`DropdownButtonFormField` يأخذ `value:` لا `initialValue:`** على
  Flutter 3.32. المعامل `initialValue` صحيح على `TextFormField` فقط.
- **لا تُجرِ استبدالاً شاملاً على أسماء الألوان.** `PdfColors` تابعة
  لحزمة `pdf` ولها لوحتها الخاصة؛ مسحٌ عام حوّلها إلى `PdfAppColors`
  وكسر البناء. اقصر أي مسح على `Colors.` المسبوقة بحدّ كلمة.
- **خطأ واحد في التحليل يولّد أخطاءً وهمية بعده** (مثل
  `Illegal character` أو `unused_element`)، فأصلح الأول ثم أعد التحليل
  قبل مطاردة البقية.
