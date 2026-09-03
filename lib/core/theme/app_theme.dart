import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// أبعاد وثوابت التصميم — مقاسات مضبوطة لسطح مكتب ويندوز
/// (مؤشر فأرة دقيق ⇒ عناصر أصغر وأكثف من الجوال، مع مساحات تنفّس واضحة).
class AppDims {
  const AppDims._();

  /// انحناء الزوايا القياسي للبطاقات واللوحات (نمط ويندوز 11).
  static const double radius = 10;

  /// انحناء أصغر للأزرار والحقول والشارات.
  static const double radiusSm = 7;

  /// انحناء كبير للحوارات واللوحات المميزة.
  static const double radiusLg = 14;

  /// ارتفاع شريط العنوان العلوي.
  static const double titleBarHeight = 48;

  /// عرض الشريط الجانبي الموسّع.
  static const double sidebarWidth = 268;

  /// عرض الشريط الجانبي المطوي.
  static const double sidebarCollapsedWidth = 60;

  /// ارتفاع عنصر التنقل في الشريط الجانبي.
  static const double navItemHeight = 38;

  /// ارتفاع الأزرار القياسي (مناسب للفأرة لا للإصبع).
  static const double controlHeight = 38;

  /// أقصى عرض للمحتوى — يمنع تمدد النصوص على الشاشات العريضة.
  static const double contentMaxWidth = 1180;

  /// حشوة الصفحة الأفقية.
  static const double pagePadding = 20;

  /// المسافة بين الأقسام.
  static const double sectionGap = 22;
}

/// ثيمات التطبيق — فاتح وداكن.
class AppTheme {
  const AppTheme._();

  /// خط احتياطي يضمن تغطية كاملة للحروف العربية على أي جهاز،
  /// مع إبقاء خط النظام (Segoe UI على ويندوز) كخط أساسي
  /// ليبدو التطبيق أصيلاً داخل بيئة ويندوز.
  static const List<String> _fontFallback = <String>['NotoNaskhArabic'];

  static final ThemeData lightTheme = _build(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: AppColors.brandGreen,
      onPrimary: AppColors.neutral0,
      primaryContainer: AppColors.brandGreenSoft,
      onPrimaryContainer: AppColors.brandGreenDark,
      secondary: AppColors.brandGoldDark,
      onSecondary: AppColors.neutral0,
      secondaryContainer: AppColors.brandGoldSoft,
      onSecondaryContainer: AppColors.brandGoldDark,
      tertiary: AppColors.ocean,
      onTertiary: AppColors.neutral0,
      tertiaryContainer: AppColors.oceanSoft,
      onTertiaryContainer: AppColors.ocean,
      error: AppColors.error,
      onError: AppColors.neutral0,
      errorContainer: AppColors.errorSoft,
      onErrorContainer: AppColors.coral,
      surface: AppColors.lightSecondaryBackground,
      onSurface: AppColors.lightPrimaryText,
      surfaceContainerLowest: AppColors.neutral0,
      surfaceContainerLow: AppColors.lightSunken,
      surfaceContainer: AppColors.lightBackground,
      surfaceContainerHigh: AppColors.lightSidebar,
      surfaceContainerHighest: AppColors.lightHover,
      onSurfaceVariant: AppColors.lightSecondaryText,
      outline: AppColors.lightBorder,
      outlineVariant: AppColors.lightBorderStrong,
      shadow: Color(0x1A0D1215),
      inverseSurface: AppColors.neutral900,
      onInverseSurface: AppColors.neutral50,
    ),
    scaffoldBackground: AppColors.lightBackground,
    surface: AppColors.lightSecondaryBackground,
    sunken: AppColors.lightSunken,
    elevated: AppColors.lightElevated,
    hover: AppColors.lightHover,
    border: AppColors.lightBorder,
    borderStrong: AppColors.lightBorderStrong,
    primaryText: AppColors.lightPrimaryText,
    secondaryText: AppColors.lightSecondaryText,
    accent: AppColors.brandGreen,
    onAccent: AppColors.neutral0,
  );

  static final ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.brandGreenLight,
      onPrimary: Color(0xFF04231D),
      primaryContainer: AppColors.darkSelected,
      onPrimaryContainer: AppColors.brandGreenLight,
      secondary: AppColors.brandGoldLight,
      onSecondary: Color(0xFF2A1D05),
      secondaryContainer: Color(0xFF3A2C10),
      onSecondaryContainer: AppColors.brandGoldLight,
      tertiary: Color(0xFF5BA9E8),
      onTertiary: Color(0xFF06253D),
      tertiaryContainer: Color(0xFF12324C),
      onTertiaryContainer: Color(0xFF9CCDF3),
      error: Color(0xFFE87676),
      onError: Color(0xFF3B0E0E),
      errorContainer: Color(0xFF4A1B1B),
      onErrorContainer: Color(0xFFF0A5A5),
      surface: AppColors.darkSecondaryBackground,
      onSurface: AppColors.darkPrimaryText,
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: AppColors.darkSunken,
      surfaceContainer: AppColors.darkSecondaryBackground,
      surfaceContainerHigh: AppColors.darkElevated,
      surfaceContainerHighest: AppColors.darkHover,
      onSurfaceVariant: AppColors.darkSecondaryText,
      outline: AppColors.darkBorder,
      outlineVariant: AppColors.darkBorderStrong,
      shadow: Color(0x66000000),
      inverseSurface: AppColors.neutral100,
      onInverseSurface: AppColors.neutral900,
    ),
    scaffoldBackground: AppColors.darkBackground,
    surface: AppColors.darkSecondaryBackground,
    sunken: AppColors.darkSunken,
    elevated: AppColors.darkElevated,
    hover: AppColors.darkHover,
    border: AppColors.darkBorder,
    borderStrong: AppColors.darkBorderStrong,
    primaryText: AppColors.darkPrimaryText,
    secondaryText: AppColors.darkSecondaryText,
    accent: AppColors.brandGreenLight,
    onAccent: const Color(0xFF04231D),
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color scaffoldBackground,
    required Color surface,
    required Color sunken,
    required Color elevated,
    required Color hover,
    required Color border,
    required Color borderStrong,
    required Color primaryText,
    required Color secondaryText,
    required Color accent,
    required Color onAccent,
  }) {
    final isDark = brightness == Brightness.dark;

    final textTheme = _textTheme(primaryText, secondaryText);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamilyFallback: _fontFallback,
      scaffoldBackgroundColor: scaffoldBackground,
      canvasColor: surface,
      primaryColor: accent,
      shadowColor: colorScheme.shadow,
      dividerColor: border,
      textTheme: textTheme,
      // كثافة مضغوطة قليلاً — الأنسب لمؤشر الفأرة على شاشات المكتب.
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      // تموّج هادئ بدل الوميض الصاخب.
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,

      // ---------------------------------------------------------------
      // الأشرطة والأسطح
      // ---------------------------------------------------------------
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? AppColors.darkTitleBar
            : AppColors.lightTitleBar,
        foregroundColor: primaryText,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppDims.titleBarHeight,
        iconTheme: IconThemeData(color: secondaryText, size: 19),
        actionsIconTheme: IconThemeData(color: secondaryText, size: 19),
        titleTextStyle: textTheme.titleMedium,
        shape: Border(bottom: BorderSide(color: border)),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark
            ? AppColors.darkSidebar
            : AppColors.lightSidebar,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark
            ? AppColors.darkSidebar
            : AppColors.lightSidebar,
        indicatorColor: isDark
            ? AppColors.darkSelected
            : AppColors.brandGreenSoft,
        selectedIconTheme: IconThemeData(color: accent, size: 20),
        unselectedIconTheme: IconThemeData(color: secondaryText, size: 20),
        selectedLabelTextStyle: TextStyle(
          color: primaryText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: secondaryText,
          fontSize: 12,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: colorScheme.shadow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radius),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radiusLg),
          side: BorderSide(color: border),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: primaryText),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        modalElevation: 12,
        showDragHandle: true,
        dragHandleColor: borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDims.radiusLg),
          ),
          side: BorderSide(color: border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radius),
          side: BorderSide(color: border),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: primaryText),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(elevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDims.radius),
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.neutral100 : AppColors.neutral800,
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        textStyle: TextStyle(
          color: isDark ? AppColors.neutral900 : AppColors.neutral50,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ---------------------------------------------------------------
      // حقول الإدخال
      // ---------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sunken,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          color: secondaryText,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: TextStyle(
          color: accent,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: secondaryText.withValues(alpha: 0.7),
          fontSize: 13.5,
        ),
        helperStyle: TextStyle(color: secondaryText, fontSize: 11.5),
        errorStyle: TextStyle(
          color: colorScheme.error,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? accent
              : secondaryText,
        ),
        suffixIconColor: secondaryText,
        border: _inputBorder(border),
        enabledBorder: _inputBorder(border),
        focusedBorder: _inputBorder(accent, width: 1.6),
        errorBorder: _inputBorder(colorScheme.error),
        focusedErrorBorder: _inputBorder(colorScheme.error, width: 1.6),
        disabledBorder: _inputBorder(border.withValues(alpha: 0.5)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.25),
        selectionHandleColor: accent,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(color: primaryText),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(elevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDims.radius),
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),

      // ---------------------------------------------------------------
      // الأزرار
      // ---------------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: _primaryButtonStyle(accent, onAccent, isDark),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _primaryButtonStyle(accent, onAccent, isDark),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? secondaryText.withValues(alpha: 0.5)
                : primaryText,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return isDark ? AppColors.darkPressed : AppColors.lightPressed;
            }
            if (states.contains(WidgetState.hovered)) return hover;
            return surface;
          }),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.hovered)
                  ? borderStrong
                  : border,
            ),
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(
            Size(0, AppDims.controlHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16),
          ),
          iconSize: const WidgetStatePropertyAll(18),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(accent),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return accent.withValues(alpha: 0.14);
            }
            if (states.contains(WidgetState.hovered)) {
              return accent.withValues(alpha: 0.08);
            }
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          minimumSize: const WidgetStatePropertyAll(
            Size(0, AppDims.controlHeight),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          iconSize: const WidgetStatePropertyAll(18),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
            ),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? primaryText
                : secondaryText,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return isDark ? AppColors.darkPressed : AppColors.lightPressed;
            }
            if (states.contains(WidgetState.hovered)) return hover;
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          iconSize: const WidgetStatePropertyAll(19),
          minimumSize: const WidgetStatePropertyAll(Size(34, 34)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(7)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
            ),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark
                  ? AppColors.darkSelected
                  : AppColors.brandGreenSoft;
            }
            if (states.contains(WidgetState.hovered)) return hover;
            return surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? accent
                : secondaryText,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          iconSize: const WidgetStatePropertyAll(17),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
            ),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radius),
        ),
      ),

      // ---------------------------------------------------------------
      // العناصر التفاعلية الأخرى
      // ---------------------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: sunken,
        selectedColor: isDark
            ? AppColors.darkSelected
            : AppColors.brandGreenSoft,
        checkmarkColor: accent,
        secondarySelectedColor: isDark
            ? AppColors.darkSelected
            : AppColors.brandGreenSoft,
        disabledColor: sunken,
        side: BorderSide(color: border),
        labelStyle: TextStyle(
          color: primaryText,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: accent,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: secondaryText,
        textColor: primaryText,
        selectedColor: accent,
        selectedTileColor: isDark
            ? AppColors.darkSelected
            : AppColors.brandGreenSoft,
        horizontalTitleGap: 12,
        minVerticalPadding: 8,
        titleTextStyle: TextStyle(
          color: primaryText,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        subtitleTextStyle: TextStyle(
          color: secondaryText,
          fontSize: 12,
          height: 1.45,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: accent,
        collapsedIconColor: secondaryText,
        textColor: primaryText,
        collapsedTextColor: primaryText,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(onAccent),
        side: BorderSide(color: borderStrong, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        visualDensity: VisualDensity.compact,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : borderStrong,
        ),
        visualDensity: VisualDensity.compact,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onAccent
              : secondaryText,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : sunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : borderStrong,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: sunken,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: border,
        dividerHeight: 1,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: accent,
        unselectedLabelColor: secondaryText,
        overlayColor: WidgetStatePropertyAll(hover),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: accent,
        unselectedItemColor: secondaryText,
        backgroundColor: surface,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 11.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: sunken,
        circularTrackColor: Colors.transparent,
        strokeWidth: 2.6,
        strokeCap: StrokeCap.round,
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 460,
        backgroundColor: isDark ? AppColors.darkElevated : AppColors.neutral800,
        contentTextStyle: const TextStyle(
          color: AppColors.neutral50,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.brandGoldLight,
        elevation: 8,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
          side: BorderSide(
            color: isDark ? AppColors.darkBorderStrong : Colors.transparent,
          ),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return isDark ? AppColors.neutral400 : AppColors.neutral600;
          }
          if (states.contains(WidgetState.hovered)) {
            return isDark ? AppColors.neutral500 : AppColors.neutral400;
          }
          return isDark ? AppColors.darkBorderStrong : AppColors.neutral300;
        }),
        thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 10 : 7,
        ),
        radius: const Radius.circular(6),
        crossAxisMargin: 2,
        mainAxisMargin: 3,
        interactive: true,
        thumbVisibility: const WidgetStatePropertyAll(false),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(sunken),
        headingTextStyle: TextStyle(
          color: secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: TextStyle(color: primaryText, fontSize: 13),
        dividerThickness: 1,
        headingRowHeight: 42,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 52,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: colorScheme.error,
        textColor: AppColors.neutral0,
        smallSize: 7,
        largeSize: 17,
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),

      // ---------------------------------------------------------------
      // الانتقالات — انسيابية وسريعة تليق بسطح المكتب
      // ---------------------------------------------------------------
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDims.radiusSm),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static ButtonStyle _primaryButtonStyle(
    Color accent,
    Color onAccent,
    bool isDark,
  ) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return accent.withValues(alpha: 0.35);
        }
        if (states.contains(WidgetState.pressed)) {
          return Color.alphaBlend(
            Colors.black.withValues(alpha: isDark ? 0.22 : 0.16),
            accent,
          );
        }
        if (states.contains(WidgetState.hovered)) {
          return Color.alphaBlend(
            (isDark ? Colors.black : Colors.white).withValues(alpha: 0.12),
            accent,
          );
        }
        return accent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? onAccent.withValues(alpha: 0.7)
            : onAccent,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: const WidgetStatePropertyAll(
        Size(0, AppDims.controlHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18),
      ),
      iconSize: const WidgetStatePropertyAll(18),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
        ),
      ),
    );
  }

  /// سلّم طباعي متدرّج — عناوين واضحة ونصوص مريحة للقراءة الطويلة.
  static TextTheme _textTheme(Color primary, Color secondary) {
    return TextTheme(
      displaySmall: TextStyle(
        color: primary,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: -0.4,
      ),
      headlineMedium: TextStyle(
        color: primary,
        fontSize: 25,
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        color: primary,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        color: primary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        color: primary,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        color: primary,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      bodyLarge: TextStyle(color: primary, fontSize: 14.5, height: 1.5),
      bodyMedium: TextStyle(color: secondary, fontSize: 13.5, height: 1.5),
      bodySmall: TextStyle(color: secondary, fontSize: 12, height: 1.5),
      labelLarge: TextStyle(
        color: primary,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        color: secondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: secondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }
}
