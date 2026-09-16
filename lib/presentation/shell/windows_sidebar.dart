import 'package:flutter/material.dart';

import '../../core/storage/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_ui.dart';

class ShellDestination {
  final String route;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const ShellDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class ShellNavGroup {
  final String title;
  final List<ShellDestination> items;

  const ShellNavGroup({required this.title, required this.items});
}

const List<ShellNavGroup> kShellNavGroups = [
  ShellNavGroup(
    title: 'نظرة عامة',
    items: [
      ShellDestination(
        route: '/dashboard',
        label: 'الرئيسية',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
      ),
    ],
  ),
  ShellNavGroup(
    title: 'العمليات',
    items: [
      ShellDestination(
        route: '/add_delivery',
        label: 'حركة تسليم',
        icon: Icons.outbox_outlined,
        selectedIcon: Icons.outbox_rounded,
      ),
      ShellDestination(
        route: '/add_receive',
        label: 'حركة استلام',
        icon: Icons.move_to_inbox_outlined,
        selectedIcon: Icons.move_to_inbox_rounded,
      ),
      ShellDestination(
        route: '/add_sent',
        label: 'حركة مرسلة',
        icon: Icons.send_outlined,
        selectedIcon: Icons.send_rounded,
      ),
      ShellDestination(
        route: '/add_exchange',
        label: 'حركة صرف',
        icon: Icons.currency_exchange_outlined,
        selectedIcon: Icons.currency_exchange_rounded,
      ),
    ],
  ),
  ShellNavGroup(
    title: 'السجلات',
    items: [
      ShellDestination(
        route: '/records',
        label: 'سجل الحركات',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
      ),
      ShellDestination(
        route: '/pending',
        label: 'الحركات المعلقة',
        icon: Icons.hourglass_empty_rounded,
        selectedIcon: Icons.hourglass_full_rounded,
      ),
      ShellDestination(
        route: '/import_pending',
        label: 'استيراد معلقة',
        icon: Icons.upload_file_outlined,
        selectedIcon: Icons.upload_file_rounded,
      ),
    ],
  ),
  ShellNavGroup(
    title: 'الصندوق والتقارير',
    items: [
      ShellDestination(
        route: '/cashbox',
        label: 'الصناديق والأرصدة',
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet_rounded,
      ),
      ShellDestination(
        route: '/daily_report',
        label: 'تقرير اليوم',
        icon: Icons.insert_chart_outlined_rounded,
        selectedIcon: Icons.insert_chart_rounded,
      ),
      ShellDestination(
        route: '/reconciliation',
        label: 'مطابقة الصندوق',
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check_rounded,
      ),
      ShellDestination(
        route: '/office_setup',
        label: 'إعداد المكتب',
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront_rounded,
      ),
      ShellDestination(
        route: '/add_currency',
        label: 'إضافة عملة',
        icon: Icons.add_card_outlined,
        selectedIcon: Icons.add_card_rounded,
      ),
    ],
  ),
  ShellNavGroup(
    title: 'النظام',
    items: [
      ShellDestination(
        route: '/settings',
        label: 'الإعدادات',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
    ],
  ),
];

const Map<String, String> kShellTitles = {
  '/dashboard': 'الرئيسية',
  '/add_delivery': 'حركة تسليم',
  '/add_receive': 'حركة استلام',
  '/add_sent': 'حركة مرسلة',
  '/add_exchange': 'حركة صرف',
  '/records': 'سجل الحركات',
  '/pending': 'الحركات المعلقة',
  '/import_pending': 'استيراد معلقة',
  '/cashbox': 'الصناديق والأرصدة',
  '/currency_detail': 'تفاصيل العملة',
  '/add_currency': 'إضافة عملة',
  '/daily_report': 'تقرير اليوم',
  '/reconciliation': 'مطابقة الصندوق',
  '/office_setup': 'إعداد المكتب',
  '/settings': 'الإعدادات',
};

/// الشريط الجانبي لسطح مكتب ويندوز — قابل للطي، مع مجموعات
/// منظّمة وتلميحات عند التمرير.
class WindowsSidebar extends StatelessWidget {
  final User user;
  final String selectedRoute;
  final ValueChanged<String> onSelect;
  final VoidCallback onLogout;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const WindowsSidebar({
    super.key,
    required this.user,
    required this.selectedRoute,
    required this.onSelect,
    required this.onLogout,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppUi.isDark(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: collapsed
          ? AppDims.sidebarCollapsedWidth
          : AppDims.sidebarWidth,
      decoration: BoxDecoration(
        color: dark ? AppColors.darkSidebar : AppColors.lightSidebar,
        border: BorderDirectional(
          end: BorderSide(color: AppUi.border(context)),
        ),
      ),
      child: Column(
        children: [
          _SidebarBrand(
            collapsed: collapsed,
            onToggleCollapse: onToggleCollapse,
          ),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
              ),
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 6 : 10,
                  vertical: 6,
                ),
                children: [
                  for (final group in kShellNavGroups) ...[
                    if (!collapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                        child: Text(
                          group.title,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: dark
                                ? AppColors.darkTertiaryText
                                : AppColors.lightTertiaryText,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Divider(
                          height: 1,
                          color: AppUi.border(context),
                        ),
                      ),
                    for (final item in group.items)
                      _SidebarTile(
                        item: item,
                        selected: selectedRoute == item.route,
                        collapsed: collapsed,
                        onTap: () => onSelect(item.route),
                      ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppUi.border(context)),
          _SidebarAccount(
            user: user,
            collapsed: collapsed,
            onLogout: onLogout,
          ),
        ],
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const _SidebarBrand({required this.collapsed, this.onToggleCollapse});

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: AppColors.brandGradient,
        ),
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandGreen.withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(
        Icons.account_balance_rounded,
        color: Colors.white,
        size: 19,
      ),
    );

    return Container(
      height: AppDims.titleBarHeight,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppUi.border(context))),
      ),
      child: Row(
        children: [
          if (collapsed)
            Expanded(
              child: Tooltip(
                message: 'توسيع القائمة',
                child: InkWell(
                  onTap: onToggleCollapse,
                  borderRadius: BorderRadius.circular(AppDims.radiusSm),
                  child: Center(child: logo),
                ),
              ),
            )
          else ...[
            logo,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تيما المالي',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppUi.textPrimary(context),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    'إدارة الصناديق والحوالات',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppUi.textSecondary(context),
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (onToggleCollapse != null)
              IconButton(
                tooltip: 'طيّ القائمة',
                onPressed: onToggleCollapse,
                iconSize: 17,
                icon: const Icon(Icons.menu_open_rounded),
              ),
          ],
        ],
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  final ShellDestination item;
  final bool selected;
  final bool collapsed;
  final bool danger;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.collapsed = false,
    // ignore: unused_element_parameter
    this.danger = false,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = AppUi.isDark(context);
    final selected = widget.selected;
    final accent = widget.danger
        ? AppUi.tone(context, AppColors.error)
        : AppUi.accent(context);

    final Color fg;
    if (widget.danger) {
      fg = accent;
    } else if (selected) {
      fg = accent;
    } else {
      fg = _hover
          ? AppUi.textPrimary(context)
          : (dark
                ? AppColors.darkSecondaryText
                : AppColors.lightSecondaryText);
    }

    final Color bg;
    if (selected) {
      bg = dark ? AppColors.darkSelected : AppColors.brandGreenSoft;
    } else if (_hover) {
      bg = widget.danger
          ? accent.withValues(alpha: 0.10)
          : (dark ? AppColors.darkHover : AppColors.lightHover);
    } else {
      bg = Colors.transparent;
    }

    Widget tile = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      height: AppDims.navItemHeight,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
      ),
      child: Row(
        children: [
          // مؤشر التحديد الجانبي (نمط ويندوز 11).
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 3,
            height: selected ? 18 : 0,
            margin: const EdgeInsetsDirectional.only(start: 2, end: 5),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          SizedBox(width: selected ? 0 : 10),
          Icon(
            selected ? widget.item.selectedIcon : widget.item.icon,
            size: 18,
            color: fg,
          ),
          if (!widget.collapsed) ...[
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                widget.item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const Spacer(),
        ],
      ),
    );

    if (widget.collapsed) {
      tile = Tooltip(
        message: widget.item.label,
        preferBelow: false,
        child: tile,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(onTap: widget.onTap, child: tile),
      ),
    );
  }
}

class _SidebarAccount extends StatelessWidget {
  final User user;
  final bool collapsed;
  final VoidCallback onLogout;

  const _SidebarAccount({
    required this.user,
    required this.collapsed,
    required this.onLogout,
  });

  String get _initial =>
      user.username.trim().isEmpty ? '؟' : user.username.trim()[0];

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: AppColors.goldGradient,
        ),
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
      ),
      child: Text(
        _initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          children: [
            Tooltip(
              message: '${user.username} • ${user.branch}',
              preferBelow: false,
              child: avatar,
            ),
            const SizedBox(height: 6),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: onLogout,
              iconSize: 17,
              icon: const Icon(Icons.logout_rounded),
              style: IconButton.styleFrom(
                foregroundColor: AppUi.tone(context, AppColors.error),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppUi.surface(context),
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
          border: Border.all(color: AppUi.border(context)),
        ),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppUi.textPrimary(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  Text(
                    user.branch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppUi.textSecondary(context),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: onLogout,
              iconSize: 17,
              icon: const Icon(Icons.logout_rounded),
              style: IconButton.styleFrom(
                foregroundColor: AppUi.tone(context, AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
