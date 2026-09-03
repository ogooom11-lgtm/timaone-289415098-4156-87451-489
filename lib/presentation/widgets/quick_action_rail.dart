import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../shell/shell_scope.dart';
import 'app_ui.dart';

/// إجراء واحد في شريط الوصول السريع.
class QuickAction {
  final String label;
  final IconData icon;
  final String route;
  final Color color;

  const QuickAction({
    required this.label,
    required this.icon,
    required this.route,
    required this.color,
  });
}

/// إجراءات إضافة الحركات الأربعة — الوصول السريع الوحيد في التطبيق.
const List<QuickAction> kQuickActions = [
  QuickAction(
    label: 'حركة تسليم',
    icon: Icons.outbox_rounded,
    route: '/add_delivery',
    color: AppColors.warning,
  ),
  QuickAction(
    label: 'حركة استلام',
    icon: Icons.move_to_inbox_rounded,
    route: '/add_receive',
    color: AppColors.success,
  ),
  QuickAction(
    label: 'حركة مرسلة',
    icon: Icons.send_rounded,
    route: '/add_sent',
    color: AppColors.ocean,
  ),
  QuickAction(
    label: 'حركة صرف',
    icon: Icons.currency_exchange_rounded,
    route: '/add_exchange',
    color: AppColors.brandGold,
  ),
];

/// شريط دوائر ثابت على حافة الشاشة لإضافة الحركات.
///
/// كل إجراء دائرة بأيقونة؛ يظهر النص في بطاقة منزلقة عند مرور مؤشر
/// الفأرة — وهو سلوك مكتبي بحت لا معنى له على الأجهزة اللمسية.
class QuickActionRail extends StatelessWidget {
  final List<QuickAction> actions;

  const QuickActionRail({super.key, this.actions = kQuickActions});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: AppUi.elevated(context).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: AppUi.border(context)),
            boxShadow: AppUi.raisedShadow(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _RailButton(action: actions[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatefulWidget {
  final QuickAction action;

  const _RailButton({required this.action});

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final tinted = AppUi.tone(context, action.color);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // البطاقة النصية تنزلق للخارج عند المرور فقط.
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: _hovered
                ? Padding(
                    padding: const EdgeInsetsDirectional.only(end: 9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: tinted,
                        borderRadius: BorderRadius.circular(AppDims.radiusSm),
                        boxShadow: AppUi.softShadow(context),
                      ),
                      child: Text(
                        action.label,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Semantics(
            button: true,
            label: action.label,
            child: Tooltip(
              // احتياط لقارئات الشاشة ولوحة المفاتيح؛ البطاقة أعلاه هي
              // التلميح المرئي المقصود.
              message: action.label,
              waitDuration: const Duration(milliseconds: 600),
              child: InkWell(
                onTap: () => TimaNav.open(context, action.route),
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hovered
                        ? tinted
                        : tinted.withValues(alpha: 0.14),
                    border: Border.all(
                      color: _hovered
                          ? tinted
                          : tinted.withValues(alpha: 0.42),
                      width: 1.4,
                    ),
                    boxShadow: _hovered ? AppUi.softShadow(context) : null,
                  ),
                  child: Icon(
                    action.icon,
                    size: 20,
                    color: _hovered ? Colors.white : tinted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
