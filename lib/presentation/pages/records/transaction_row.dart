import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import 'tx_shared.dart';

/// بطاقة الحركة القابلة للتوسيع — نفس البطاقة المستخدمة في سجل الحركات
/// ونتائج البحث في الصفحة الرئيسية.
class TransactionRow extends StatefulWidget {
  final Transaction transaction;
  final TxPolicy policy;
  final TxKind kind;
  final IconData icon;
  final Color tint;
  final String Function(int?) currencyCode;
  final String Function(int?) currencyName;
  final String Function(double) formatAmount;
  final String Function(DateTime) formatDate;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onDeliver;
  final VoidCallback onRevertCancel;
  final VoidCallback onRevertDelivery;
  final VoidCallback onPrint;
  final Future<List<Edit>> Function() loadEdits;

  const TransactionRow({
    super.key,
    required this.transaction,
    required this.policy,
    required this.kind,
    required this.icon,
    required this.tint,
    required this.currencyCode,
    required this.currencyName,
    required this.formatAmount,
    required this.formatDate,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onCancel,
    required this.onDeliver,
    required this.onRevertCancel,
    required this.onRevertDelivery,
    required this.onPrint,
    required this.loadEdits,
  });

  @override
  State<TransactionRow> createState() => _TransactionRowState();
}

class _TransactionRowState extends State<TransactionRow> {
  bool _hovered = false;

  bool get _canceled => txCanceled(widget.transaction);

  bool get _delivered =>
      !_canceled && widget.transaction.status == 'تم التسليم';

  Color get _statusColor => _canceled
      ? AppColors.error
      : _delivered
      ? AppColors.success
      : AppColors.brandGoldDark;

  String get _statusLabel => _canceled
      ? 'ملغية'
      : (widget.transaction.status.isEmpty
            ? 'مضافة'
            : widget.transaction.status);

  @override
  Widget build(BuildContext context) {
    final tint = _canceled
        ? AppColors.neutral500
        : AppUi.tone(context, widget.tint);
    final title = widget.transaction.beneficiary?.isNotEmpty == true
        ? widget.transaction.beneficiary!
        : widget.transaction.type;

    final isExchange = widget.kind == TxKind.exchange;
    final amountText = isExchange
        ? '${widget.formatAmount(widget.transaction.amount)} ${widget.currencyCode(widget.transaction.currencyId)} ← ${widget.formatAmount(widget.transaction.targetAmount ?? 0)} ${widget.currencyCode(widget.transaction.targetCurrencyId)}'
        : '${widget.formatAmount(widget.transaction.amount)} ${widget.currencyCode(widget.transaction.currencyId)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppUi.panelDecoration(
        context,
        borderColor: widget.expanded || _hovered
            ? tint.withValues(alpha: 0.55)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 4,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [tint, tint.withValues(alpha: 0.35)],
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tint.withValues(
                            alpha: _hovered || widget.expanded ? 0.20 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDims.radiusSm,
                          ),
                        ),
                        child: Icon(widget.icon, color: tint, size: 19),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppUi.textPrimary(context),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                decoration: _canceled
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 24,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: _hovered
                                    ? _quickActions(context, tint)
                                    : Row(
                                        key: const ValueKey('meta'),
                                        children: [
                                          Text(
                                            amountText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: _canceled
                                                  ? AppUi.textSecondary(
                                                      context,
                                                    )
                                                  : AppUi.accent(context),
                                              decoration: _canceled
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Flexible(
                                            child: Text(
                                              '${widget.transaction.type} • ${widget.formatDate(widget.transaction.createdAt)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: AppUi.textSecondary(
                                                  context,
                                                ),
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (widget.busy)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: TimaStatusPill(
                            key: ValueKey('status-$_statusLabel'),
                            label: _statusLabel,
                            color: _statusColor,
                          ),
                        ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        turns: widget.expanded ? 0.5 : 0,
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: AppUi.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: widget.expanded
                ? _details(context, tint)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// أزرار سريعة تظهر عند مرور الفأرة بدل سطر التاريخ.
  Widget _quickActions(BuildContext context, Color tint) {
    final policy = widget.policy;
    final items = <Widget>[
      if (policy.canDeliver)
        TxMiniAction(
          tooltip: 'تسليم الحركة',
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          onTap: widget.onDeliver,
        ),
      if (policy.canPrint)
        TxMiniAction(
          tooltip: 'طباعة إيصال',
          icon: Icons.print_rounded,
          color: AppColors.ocean,
          onTap: widget.onPrint,
        ),
      if (policy.canEdit)
        TxMiniAction(
          tooltip: 'تعديل الحركة',
          icon: Icons.edit_outlined,
          color: tint,
          onTap: widget.onEdit,
        ),
      if (policy.canRevertCancel)
        TxMiniAction(
          tooltip: 'تراجع عن الإلغاء',
          icon: Icons.autorenew_rounded,
          color: AppColors.ocean,
          onTap: widget.onRevertCancel,
        ),
      if (policy.canCancel)
        TxMiniAction(
          tooltip: 'إلغاء الحركة',
          icon: Icons.cancel_outlined,
          color: AppColors.error,
          onTap: widget.onCancel,
        ),
    ];

    return Row(
      key: const ValueKey('quick'),
      children: [
        ...items,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${widget.formatAmount(widget.transaction.amount)} '
            '${widget.currencyCode(widget.transaction.currencyId)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _canceled
                  ? AppUi.textSecondary(context)
                  : AppUi.accent(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _details(BuildContext context, Color tint) {
    final tx = widget.transaction;

    final facts = <Widget>[
      TimaKeyValue(
        label: 'التاريخ والوقت',
        value: widget.formatDate(tx.createdAt),
        icon: Icons.schedule_rounded,
      ),
      TimaKeyValue(
        label: 'نوع الحركة',
        value: tx.type,
        icon: widget.icon,
      ),
      TimaKeyValue(
        label: 'الحالة',
        value: _statusLabel,
        icon: Icons.flag_outlined,
        valueColor: AppUi.tone(context, _statusColor),
      ),
      TimaKeyValue(
        label: 'مسجّل الحركة',
        value: tx.createdByName,
        icon: Icons.person_outline_rounded,
      ),
      TimaKeyValue(
        label: 'المبلغ',
        value:
            '${widget.formatAmount(tx.amount)} ${widget.currencyName(tx.currencyId)}',
        icon: Icons.paid_outlined,
        emphasized: true,
      ),
      if (tx.targetAmount != null && tx.targetCurrencyId != null)
        TimaKeyValue(
          label: 'المبلغ الثاني',
          value:
              '${widget.formatAmount(tx.targetAmount!)} ${widget.currencyName(tx.targetCurrencyId)}',
          icon: Icons.swap_horiz_rounded,
        ),
      if (tx.exchangeRate != null)
        TimaKeyValue(
          label: 'سعر الصرف (${tx.operation ?? '-'})',
          value: widget.formatAmount(tx.exchangeRate!),
          icon: Icons.currency_exchange_rounded,
        ),
      if (tx.fees != null)
        TimaKeyValue(
          label: 'الأجور والعمولة',
          value:
              '${widget.formatAmount(tx.fees!)} ${widget.currencyCode(tx.feesCurrencyId)}',
          icon: Icons.request_quote_outlined,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppUi.sunken(context),
        border: Border(top: BorderSide(color: AppUi.border(context))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 2,
            children: [
              for (final fact in facts) SizedBox(width: 268, child: fact),
            ],
          ),
          if (tx.note != null && tx.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppUi.surface(context),
                borderRadius: BorderRadius.circular(AppDims.radiusSm),
                border: Border.all(color: AppUi.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        size: 14,
                        color: AppUi.textSecondary(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ملاحظة وتفاصيل التسليم',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppUi.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    tx.note!.trim(),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppUi.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _actionBar(context, tint),
          const SizedBox(height: 10),
          Text(
            widget.policy.hint,
            style: TextStyle(
              fontSize: 11,
              color: AppUi.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          _auditTrail(context),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context, Color tint) {
    final policy = widget.policy;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (policy.canDeliver)
          TxActionButton(
            label: _canceled ? 'تسليم الحركة' : 'تم التسليم',
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
            filled: true,
            onPressed: widget.onDeliver,
          ),
        if (policy.canPrint)
          TxActionButton(
            label: 'طباعة إيصال',
            icon: Icons.print_rounded,
            color: AppColors.ocean,
            onPressed: widget.onPrint,
          ),
        if (policy.canEdit)
          TxActionButton(
            label: 'تعديل الحركة',
            icon: Icons.edit_outlined,
            color: tint,
            onPressed: widget.onEdit,
          ),
        if (policy.canRevertCancel)
          TxActionButton(
            label: 'تراجع عن الإلغاء',
            icon: Icons.autorenew_rounded,
            color: AppColors.ocean,
            filled: true,
            onPressed: widget.onRevertCancel,
          ),
        if (policy.canRevertDelivery)
          TxActionButton(
            label: 'تراجع عن التسليم',
            icon: Icons.history_rounded,
            color: AppColors.warning,
            onPressed: widget.onRevertDelivery,
          ),
        if (policy.canCancel)
          TxActionButton(
            label: 'إلغاء الحركة',
            icon: Icons.cancel_outlined,
            color: AppColors.error,
            onPressed: widget.onCancel,
          ),
      ],
    );
  }

  Widget _auditTrail(BuildContext context) {
    return FutureBuilder<List<Edit>>(
      future: widget.loadEdits(),
      builder: (context, snapshot) {
        final edits = snapshot.data ?? const <Edit>[];
        if (edits.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppUi.surface(context),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(color: AppUi.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 14,
                    color: AppUi.textSecondary(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'سجل التعديلات (${edits.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppUi.textSecondary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...edits.map(
                (edit) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: AppUi.borderStrong(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${edit.field}: ${edit.oldValue} ← ${edit.newValue}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppUi.textPrimary(context),
                          ),
                        ),
                      ),
                      Text(
                        '${widget.formatDate(edit.editedAt)} • ${edit.editedBy}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppUi.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// زر إجراء مكتوب داخل بطاقة الحركة.
class TxActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onPressed;

  const TxActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.filled = false,
  });

  @override
  State<TxActionButton> createState() => _TxActionButtonState();
}

class _TxActionButtonState extends State<TxActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tint = AppUi.tone(context, widget.color);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.03 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: widget.filled
                ? tint.withValues(alpha: _hovered ? 1 : 0.9)
                : (widget.color.withValues(alpha: _hovered ? 0.18 : 0.10)),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(
              color: widget.filled
                  ? Colors.transparent
                  : widget.color.withValues(alpha: 0.42),
            ),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 15,
                  color: widget.filled ? Colors.white : tint,
                ),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: widget.filled ? Colors.white : tint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// زر أيقونة صغير يظهر عند مرور الفأرة على الحركة.
class TxMiniAction extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const TxMiniAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<TxMiniAction> createState() => _TxMiniActionState();
}

class _TxMiniActionState extends State<TxMiniAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tint = AppUi.tone(context, widget.color);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.only(left: 6),
            width: 26,
            height: 24,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: _hovered ? 0.20 : 0.10),
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
              border: Border.all(
                color: widget.color.withValues(alpha: _hovered ? 0.55 : 0.25),
              ),
            ),
            child: Icon(widget.icon, size: 14, color: tint),
          ),
        ),
      ),
    );
  }
}

/// حركة ظهور متدرّجة لعناصر القائمة.
class TxStaggered extends StatefulWidget {
  final int index;
  final Widget child;

  const TxStaggered({super.key, required this.index, required this.child});

  @override
  State<TxStaggered> createState() => _TxStaggeredState();
}

class _TxStaggeredState extends State<TxStaggered>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _play();
  }

  Future<void> _play() async {
    await Future<void>.delayed(
      Duration(milliseconds: (widget.index % 12) * 26),
    );
    if (mounted) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        ),
        child: widget.child,
      ),
    );
  }
}
