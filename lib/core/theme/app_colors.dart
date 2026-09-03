import 'package:flutter/material.dart';

/// نظام ألوان "تيما المالي" — مصمم خصيصاً لسطح مكتب ويندوز.
///
/// الفلسفة: خلفيات محايدة هادئة (رمادي فلوينت) + هوية زمردية عميقة
/// + لمسة ذهبية دافئة للتمييز. التباين مضبوط ليكون مريحاً لساعات العمل
/// الطويلة أمام شاشة كبيرة، مع وضوح كامل للأرقام المالية.
class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------
  // هوية العلامة
  // ---------------------------------------------------------------------

  /// الأخضر الزمردي الأساسي — أزرار، روابط، عناصر مفعّلة.
  static const Color brandGreen = Color(0xFF0E6B58);

  /// نسخة داكنة للتدرجات والأسطح البارزة.
  static const Color brandGreenDark = Color(0xFF07443A);

  /// نسخة أفتح تُستخدم في الوضع الداكن حيث يحتاج الأخضر إشراقاً.
  static const Color brandGreenLight = Color(0xFF2FA98D);

  /// خلفية خفيفة جداً بلون الهوية (تظليل، شارات، أيقونات).
  static const Color brandGreenSoft = Color(0xFFE8F5F1);

  /// الذهبي الدافئ — لون التمييز الثانوي.
  static const Color brandGold = Color(0xFFD4A64A);

  /// ذهبي داكن يصلح للنص فوق الخلفيات الفاتحة (تباين كافٍ).
  static const Color brandGoldDark = Color(0xFF97671A);

  /// ذهبي فاتح للوضع الداكن.
  static const Color brandGoldLight = Color(0xFFE9C270);

  /// خلفية ذهبية خفيفة.
  static const Color brandGoldSoft = Color(0xFFFBF3E2);

  /// الأبيض العاجي — نص فوق الأسطح الداكنة.
  static const Color brandIvory = Color(0xFFFAFBFB);

  // ---------------------------------------------------------------------
  // محايدات (سلّم رمادي مائل للأزرق — مريح على شاشات ويندوز)
  // ---------------------------------------------------------------------

  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFF7F9FA);
  static const Color neutral100 = Color(0xFFF1F4F6);
  static const Color neutral200 = Color(0xFFE4E9ED);
  static const Color neutral300 = Color(0xFFD3DBE0);
  static const Color neutral400 = Color(0xFFAAB6BE);
  static const Color neutral500 = Color(0xFF7C8A93);
  static const Color neutral600 = Color(0xFF5A676F);
  static const Color neutral700 = Color(0xFF3D474D);
  static const Color neutral800 = Color(0xFF272F34);
  static const Color neutral900 = Color(0xFF161C20);
  static const Color neutral950 = Color(0xFF0D1215);

  /// النص الأساسي الداكن.
  static const Color ink = neutral900;

  /// النص الثانوي.
  static const Color slate = neutral600;

  /// خلفية محايدة خفيفة.
  static const Color mist = neutral100;

  // ---------------------------------------------------------------------
  // ألوان وظيفية
  // ---------------------------------------------------------------------

  static const Color ocean = Color(0xFF1C6FB8);
  static const Color oceanSoft = Color(0xFFE7F1FA);
  static const Color coral = Color(0xFFCE4C4C);
  static const Color coralSoft = Color(0xFFFBECEC);
  static const Color violet = Color(0xFF6355C9);
  static const Color violetSoft = Color(0xFFEEECFB);
  static const Color teal = Color(0xFF11837A);

  static const Color success = Color(0xFF17835C);
  static const Color successSoft = Color(0xFFE6F5EF);
  static const Color error = coral;
  static const Color errorSoft = coralSoft;
  static const Color warning = Color(0xFFB8781A);
  static const Color warningSoft = Color(0xFFFDF3E3);
  static const Color info = ocean;
  static const Color infoSoft = oceanSoft;

  // ---------------------------------------------------------------------
  // أسطح الوضع الفاتح
  // ---------------------------------------------------------------------

  /// خلفية النافذة الرئيسية.
  static const Color lightBackground = Color(0xFFF2F5F7);

  /// خلفية البطاقات واللوحات.
  static const Color lightSecondaryBackground = neutral0;

  /// سطح مرتفع (قوائم منسدلة، حوارات).
  static const Color lightElevated = neutral0;

  /// سطح غائر (حقول الإدخال، مناطق الجداول).
  static const Color lightSunken = Color(0xFFF7F9FA);

  /// الشريط الجانبي — تأثير "Mica" الخفيف في ويندوز.
  static const Color lightSidebar = Color(0xFFEDF1F3);

  /// شريط العنوان العلوي.
  static const Color lightTitleBar = Color(0xFFF8FAFB);

  static const Color lightPrimaryText = ink;
  static const Color lightSecondaryText = slate;
  static const Color lightTertiaryText = neutral500;

  static const Color lightHover = Color(0xFFE9EEF1);
  static const Color lightPressed = Color(0xFFDFE6EA);
  static const Color lightSelected = brandGreenSoft;

  static const Color lightBorder = Color(0xFFE1E7EB);
  static const Color lightBorderStrong = Color(0xFFCFD8DE);

  // ---------------------------------------------------------------------
  // أسطح الوضع الداكن
  // ---------------------------------------------------------------------

  static const Color darkBackground = Color(0xFF10161A);
  static const Color darkSecondaryBackground = Color(0xFF192126);
  static const Color darkElevated = Color(0xFF1F282E);
  static const Color darkSunken = Color(0xFF141B1F);
  static const Color darkSidebar = Color(0xFF141C21);
  static const Color darkTitleBar = Color(0xFF171F24);

  static const Color darkPrimaryText = Color(0xFFF2F5F6);
  static const Color darkSecondaryText = Color(0xFFA7B4BC);
  static const Color darkTertiaryText = Color(0xFF7D8C95);

  static const Color darkHover = Color(0xFF232D33);
  static const Color darkPressed = Color(0xFF2A353C);
  static const Color darkSelected = Color(0xFF16332C);

  static const Color darkBorder = Color(0xFF2B363D);
  static const Color darkBorderStrong = Color(0xFF3A474F);

  // ---------------------------------------------------------------------
  // اختصارات
  // ---------------------------------------------------------------------

  static const Color primary = brandGreen;
  static const Color secondary = brandGold;

  /// تدرّج الهوية المستخدم في الرؤوس واللوحات المميزة.
  static const List<Color> brandGradient = [
    Color(0xFF0E6B58),
    Color(0xFF07443A),
  ];

  /// تدرّج ذهبي للعناصر الاحتفالية (النجاح، الترحيب).
  static const List<Color> goldGradient = [
    Color(0xFFD4A64A),
    Color(0xFFA9761F),
  ];
}
