import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../shell/shell_scope.dart';

/// أدوات مساعدة للوصول السريع لألوان وأسطح الثيم الحالي.
class AppUi {
  const AppUi._();

  static const double radius = AppDims.radius;
  static const double radiusSm = AppDims.radiusSm;
  static const double radiusLg = AppDims.radiusLg;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// لون الحدود القياسي.
  static Color border(BuildContext context) =>
      isDark(context) ? AppColors.darkBorder : AppColors.lightBorder;

  /// حدود أوضح للعناصر التي تحتاج فصلاً بصرياً أقوى.
  static Color borderStrong(BuildContext context) => isDark(context)
      ? AppColors.darkBorderStrong
      : AppColors.lightBorderStrong;

  /// سطح البطاقات واللوحات.
  static Color surface(BuildContext context) => isDark(context)
      ? AppColors.darkSecondaryBackground
      : AppColors.lightSecondaryBackground;

  /// سطح غائر — حقول الإدخال ورؤوس الجداول.
  static Color sunken(BuildContext context) =>
      isDark(context) ? AppColors.darkSunken : AppColors.lightSunken;

  /// سطح مرتفع — الحوارات والقوائم.
  static Color elevated(BuildContext context) =>
      isDark(context) ? AppColors.darkElevated : AppColors.lightElevated;

  /// لون التمرير بالفأرة.
  static Color hover(BuildContext context) =>
      isDark(context) ? AppColors.darkHover : AppColors.lightHover;

  /// لون الهوية المناسب للوضع الحالي.
  static Color accent(BuildContext context) => isDark(context)
      ? AppColors.brandGreenLight
      : AppColors.brandGreen;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;

  static Color textSecondary(BuildContext context) => isDark(context)
      ? AppColors.darkSecondaryText
      : AppColors.lightSecondaryText;

  /// يضبط شدّة اللون ليبقى مقروءاً في الوضع الداكن.
  static Color tone(BuildContext context, Color color) {
    if (!isDark(context)) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + 0.18).clamp(0.0, 0.82))
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
  }

  /// خلفية خفيفة مشتقة من لون دلالي (شارات، أيقونات).
  static Color softFill(BuildContext context, Color color) =>
      color.withValues(alpha: isDark(context) ? 0.16 : 0.10);

  /// ظل ناعم للبطاقات.
  static List<BoxShadow> softShadow(BuildContext context) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark(context) ? 0.28 : 0.045),
      blurRadius: 14,
      offset: const Offset(0, 3),
    ),
  ];

  /// ظل أوضح للعناصر العائمة.
  static List<BoxShadow> raisedShadow(BuildContext context) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark(context) ? 0.42 : 0.10),
      blurRadius: 26,
      offset: const Offset(0, 10),
    ),
  ];

  /// خلفية الصفحة — تدرّج محايد هادئ بدل اللون المسطح.
  static BoxDecoration pageBackground(BuildContext context) {
    final dark = isDark(context);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const [Color(0xFF121A1E), Color(0xFF10161A)]
            : const [Color(0xFFF6F8FA), Color(0xFFF0F4F6)],
      ),
    );
  }

  static BoxDecoration panelDecoration(
    BuildContext context, {
    Color? color,
    Color? borderColor,
    double? radiusValue,
    bool shadow = true,
  }) {
    return BoxDecoration(
      color: color ?? surface(context),
      borderRadius: BorderRadius.circular(radiusValue ?? radius),
      border: Border.all(color: borderColor ?? border(context)),
      boxShadow: shadow ? softShadow(context) : null,
    );
  }

  /// لوحة بتدرّج لوني — تُستخدم في رؤوس الصفحات.
  static BoxDecoration accentPanelDecoration(
    BuildContext context, {
    Color start = AppColors.brandGreen,
    Color end = AppColors.brandGreenDark,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [start, end],
      ),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: start.withValues(alpha: isDark(context) ? 0.30 : 0.22),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

/// خلفية الصفحة الموحّدة.
class TimaPageBackground extends StatelessWidget {
  final Widget child;

  const TimaPageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppUi.pageBackground(context),
      child: child,
    );
  }
}

/// يحصر المحتوى ضمن عرض مريح للقراءة على الشاشات العريضة.
class TimaContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  const TimaContentWidth({
    super.key,
    required this.child,
    this.maxWidth = AppDims.contentMaxWidth,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// لوحة/بطاقة بيضاء بحدود وظل ناعم — العنصر الأساسي في التخطيط.
class TimaPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double? radius;
  final bool shadow;
  final VoidCallback? onTap;

  const TimaPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.radius,
    this.shadow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = AppUi.panelDecoration(
      context,
      color: color,
      borderColor: borderColor,
      radiusValue: radius,
      shadow: shadow,
    );

    final content = Padding(padding: padding, child: child);

    if (onTap == null) {
      return Container(
        width: double.infinity,
        decoration: decoration,
        child: content,
      );
    }

    return _HoverScale(
      child: Container(
        width: double.infinity,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: AppUi.hover(context),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// رأس صفحة بارز بتدرّج لوني — للعناوين الرئيسية والترحيب.
class TimaHeaderPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color startColor;
  final Color endColor;
  final Widget? trailing;

  const TimaHeaderPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.startColor = AppColors.brandGreen,
    this.endColor = AppColors.brandGreenDark,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppUi.accentPanelDecoration(
        context,
        start: startColor,
        end: endColor,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // زخرفة ضوئية خفيفة تعطي عمقاً للتدرّج.
          PositionedDirectional(
            top: -70,
            end: -40,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          PositionedDirectional(
            bottom: -90,
            start: 60,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppDims.radiusSm),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// عنوان قسم داخل الصفحة.
class TimaSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const TimaSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: AppUi.isDark(context) ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
          ),
          child: Icon(icon, color: accent, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

/// شارة حالة ملوّنة صغيرة.
class TimaStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  const TimaStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final tinted = AppUi.tone(context, color);
    final fg = solid ? Colors.white : tinted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: solid ? color : tinted.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        border: Border.all(
          color: solid ? Colors.transparent : tinted.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fg, size: 13),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة مؤشر رقمي — تُستخدم في لوحة المعلومات والتقارير.
class TimaMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;
  final VoidCallback? onTap;

  const TimaMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tinted = AppUi.tone(context, color);

    return TimaPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tinted.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppDims.radiusSm),
                ),
                child: Icon(icon, color: tinted, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppUi.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: AppUi.textPrimary(context),
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppUi.textSecondary(context),
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// صف "مفتاح / قيمة" مستخدم في بطاقات التفاصيل.
class TimaKeyValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final bool emphasized;

  const TimaKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppUi.textSecondary(context)),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: TextStyle(
              color: AppUi.textSecondary(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? AppUi.textPrimary(context),
                fontSize: emphasized ? 14.5 : 13,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط أدوات أعلى الصفحة داخل الغلاف (بحث، فلترة، أزرار إجراء).
class TimaToolbar extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const TimaToolbar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return TimaPanel(
      padding: padding,
      child: Row(children: children),
    );
  }
}

/// حالة فارغة أنيقة.
class TimaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const TimaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: accent.withValues(
                    alpha: AppUi.isDark(context) ? 0.13 : 0.08,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// مؤشر تحميل موحّد.
class TimaLoader extends StatelessWidget {
  final String? message;

  const TimaLoader({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// تكبير طفيف عند مرور الفأرة — يعطي إحساساً حيّاً بالتفاعل على سطح المكتب.
class _HoverScale extends StatefulWidget {
  final Widget child;

  const _HoverScale({required this.child});

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.012 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// أشرطة العناوين والتنقل
// ---------------------------------------------------------------------------

bool timaInShell(BuildContext context) => ShellScope.maybeOf(context) != null;

/// يبني شريط عنوان للصفحة — ويُلغيه إذا كانت الصفحة داخل غلاف ويندوز
/// ولا تحتاج أزرار إجراءات (لأن الغلاف يعرض العنوان أصلاً).
PreferredSizeWidget? timaMaybeAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  bool showBack = true,
  VoidCallback? onBack,
}) {
  final inShell = timaInShell(context);
  if (inShell && (actions == null || actions.isEmpty)) return null;

  return AppBar(
    automaticallyImplyLeading: false,
    toolbarHeight: AppDims.titleBarHeight,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: inShell
        ? null
        : Border(bottom: BorderSide(color: AppUi.border(context))),
    centerTitle: false,
    titleSpacing: inShell ? 16 : 4,
    leading: inShell || !showBack
        ? null
        : IconButton(
            tooltip: 'رجوع',
            onPressed: onBack ?? () => TimaNav.back(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
    title: inShell
        ? null
        : Text(title, style: Theme.of(context).textTheme.titleMedium),
    actions: [...?actions, const SizedBox(width: 8)],
  );
}

/// شريط عنوان مستقل للصفحات خارج الغلاف.
class TimaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;

  const TimaAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppDims.titleBarHeight);

  @override
  Widget build(BuildContext context) {
    final canGoBack =
        showBack && (onBack != null || TimaNavAware.canGoBack(context));

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: AppDims.titleBarHeight,
      centerTitle: false,
      titleSpacing: canGoBack ? 4 : 16,
      leading: canGoBack
          ? IconButton(
              tooltip: 'رجوع',
              onPressed: onBack ?? () => TimaNavAware.back(context),
              icon: const Icon(Icons.arrow_back_rounded),
            )
          : null,
      title: Text(title),
      actions: [...?actions, const SizedBox(width: 8)],
    );
  }
}

class TimaNavAware {
  const TimaNavAware._();

  static bool canGoBack(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    return navigator != null && navigator.canPop();
  }

  static void back(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator?.maybePop();
  }
}
