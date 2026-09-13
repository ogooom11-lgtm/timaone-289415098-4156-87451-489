import 'package:drift/drift.dart' as drift;
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/printing/delivery_receipt.dart';
import '../../../core/services/app_sound.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/denom_validator_dialog.dart';
import '../../widgets/receipt_print_dialog.dart';
import '../transactions/add_delivery_page.dart';

class PendingRecordsPage extends StatefulWidget {
  final AppDatabase db;
  final User user;

  const PendingRecordsPage({super.key, required this.db, required this.user});

  @override
  State<PendingRecordsPage> createState() => _PendingRecordsPageState();
}

class _PendingRecordsPageState extends State<PendingRecordsPage> {
  List<Transaction> _pendingTransactions = [];
  Map<int, Currency> _currencies = {};
  bool _loading = true;
  final Set<int> _expanded = {};
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final transactions = await widget.db.getAllTransactions();
    final currencies = await widget.db.getAllCurrencies();

    final filtered = transactions.where((t) {
      return (t.type == "حركة تسليم" || t.type.contains("تسليم")) &&
          t.status == "مضافة" &&
          t.movementState == "مفعلة";
    }).toList();

    if (!mounted) return;
    setState(() {
      _pendingTransactions = filtered;
      _currencies = {for (final c in currencies) c.id: c};
      _loading = false;
    });
  }

  String _formatDate(DateTime date) {
    return DateFormat("yyyy-MM-dd HH:mm").format(date.toLocal());
  }

  String _currencyCode(int? id) {
    if (id == null) return "-";
    return _currencies[id]?.code ?? id.toString();
  }

  String _formatAmount(double value) =>
      NumberFormat('#,##0.##', 'en').format(value);

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _withBusy(int id, Future<void> Function() action) async {
    setState(() => _busyId = id);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// مجاميع المبالغ المعلّقة لكل عملة (الأولى والثانية).
  List<MapEntry<String, _PendingCurrencyTotal>> _currencyTotals() {
    final totals = <String, _PendingCurrencyTotal>{};
    void add(int? id, double? amount) {
      if (id == null || amount == null) return;
      final code = _currencyCode(id);
      final item = totals.putIfAbsent(code, _PendingCurrencyTotal.new);
      item.count++;
      item.amount += amount;
    }

    for (final tx in _pendingTransactions) {
      add(tx.currencyId, tx.amount);
      add(tx.targetCurrencyId, tx.targetAmount);
    }
    final list = totals.entries.toList()
      ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    return list;
  }

  Future<void> _exportExcel() async {
    final excel = xls.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'المعلقة') {
      excel.rename(defaultSheet, 'المعلقة');
    }
    final sheet = excel['المعلقة'];
    const headers = [
      'المستفيد',
      'المبلغ',
      'العملة',
      'المبلغ الثاني',
      'العملة الثانية',
      'تاريخ الإضافة',
      'ملاحظة',
    ];
    for (var column = 0; column < headers.length; column++) {
      sheet
          .cell(
            xls.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
          )
          .value = xls.TextCellValue(
        headers[column],
      );
    }
    for (var row = 0; row < _pendingTransactions.length; row++) {
      final tx = _pendingTransactions[row];
      final values = [
        tx.beneficiary ?? '',
        tx.amount.toString(),
        _currencyCode(tx.currencyId),
        tx.targetAmount?.toString() ?? '',
        _currencyCode(tx.targetCurrencyId),
        _formatDate(tx.createdAt),
        tx.note ?? '',
      ];
      for (var column = 0; column < values.length; column++) {
        sheet
            .cell(
              xls.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: row + 1,
              ),
            )
            .value = xls.TextCellValue(
          values[column],
        );
      }
    }
    final bytes = excel.encode();
    if (bytes == null || !mounted) return;
    final saved = await FilePicker.saveFile(
      dialogTitle: 'تصدير الحركات المعلقة',
      fileName:
          'tima_pending_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
      bytes: Uint8List.fromList(bytes),
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved == null ? 'تم إلغاء التصدير' : 'تم تصدير ملف Excel بنجاح',
        ),
      ),
    );
  }

  Future<bool> _confirmCancel(Transaction transaction) async {
    final amount =
        '${_formatAmount(transaction.amount)} ${_currencyCode(transaction.currencyId)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDims.radiusLg),
            side: BorderSide(color: AppUi.border(ctx)),
          ),
          title: Row(
            children: [
              Icon(
                Icons.report_gmailerrorred_rounded,
                color: AppUi.tone(ctx, AppColors.error),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('إلغاء الحركة المعلقة؟'))],
          ),
          content: Text(
            'ستتحول حركة «${transaction.beneficiary?.isNotEmpty == true ? transaction.beneficiary : 'تسليم'}» '
            'بمبلغ $amount إلى حالة ملغية. يمكن التراجع عن الإلغاء من سجل الحركات.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('عودة'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.cancel_rounded, size: 18),
              label: const Text('نعم، إلغاء الحركة'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _cancel(Transaction transaction) async {
    if (!await _confirmCancel(transaction)) return;
    await _withBusy(transaction.id, () async {
      // الحركة المعلقة لم تُسلَّم بعد فلا فئات لها في الصندوق — يكفي تغيير الوضع.
      await widget.db.updateTransaction(
        transaction.id,
        const TransactionsCompanion(movementState: drift.Value("ملغية")),
      );
      await widget.db.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: "وضع الحركة",
          oldValue: transaction.movementState,
          newValue: "ملغية",
          editedBy: drift.Value(widget.user.username),
        ),
      );
      await _loadData();
    });
    AppSound.play(TimaSound.error);
    _toast('تم إلغاء الحركة المعلقة', AppColors.error);
  }

  Future<void> _deliver(Transaction transaction) async {
    final currency1 = _currencies[transaction.currencyId];
    if (currency1 == null) return;

    // 1) فئات المبلغ الأول — مقيدة بمخزون الصندوق
    final stock1 = await CurrencyDenoms.loadStock(currency1);
    if (!mounted) return;
    final counts1 = await showDialog<Map<double, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenomValidatorDialog(
        targetAmount: transaction.amount,
        currency: currency1,
        title: "تفصيل فئات المبلغ 1 (${currency1.code})",
        mode: DenomDialogMode.outflow,
        availableStock: stock1,
      ),
    );
    if (counts1 == null) return; // تراجع المستخدم

    // 2) فئات المبلغ الثاني إن وُجد — بنفس المنطق
    Map<double, int>? counts2;
    Currency? currency2;
    if (transaction.targetAmount != null &&
        transaction.targetAmount! > 0 &&
        transaction.targetCurrencyId != null) {
      currency2 = _currencies[transaction.targetCurrencyId!];
      if (currency2 == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "عملة المبلغ الثاني غير معرّفة — أضفها من الإعدادات",
              ),
            ),
          );
        }
        return;
      }
      final stock2 = await CurrencyDenoms.loadStock(currency2);
      if (!mounted) return;
      counts2 = await showDialog<Map<double, int>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DenomValidatorDialog(
          targetAmount: transaction.targetAmount!,
          currency: currency2!,
          title: "تفصيل فئات المبلغ 2 (${currency2.code})",
          mode: DenomDialogMode.outflow,
          availableStock: stock2,
        ),
      );
      if (counts2 == null) return; // تراجع المستخدم
    }

    final nowStr = DateFormat("yyyy-MM-dd HH:mm").format(DateTime.now());
    final denomStr1 = CurrencyDenoms.formatCounts(counts1);
    final denomLines = <String>[
      "[تم التسليم في $nowStr]",
      "[فئات المسلم: $denomStr1]",
    ];
    if (counts2 != null && currency2 != null) {
      denomLines.add(
        "[فئات المسلم 2: ${CurrencyDenoms.formatCounts(counts2)} (${currency2.code})]",
      );
    }

    final newNote = transaction.note == null || transaction.note!.trim().isEmpty
        ? denomLines.join("\n")
        : "${transaction.note}\n${denomLines.join("\n")}";

    await _withBusy(transaction.id, () async {
      await widget.db.updateTransaction(
        transaction.id,
        TransactionsCompanion(
          status: const drift.Value("تم التسليم"),
          movementState: const drift.Value("مفعلة"),
          note: drift.Value(newNote),
        ),
      );
      // خصم الفئات المسلمة من مخزون الصندوق (1 + 2)
      await CurrencyDenoms.deductStock(currency1, counts1);
      if (counts2 != null && currency2 != null) {
        await CurrencyDenoms.deductStock(currency2, counts2);
      }
      await widget.db.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: "تغيير الحالة والتسليم",
          oldValue: transaction.status,
          newValue: "تم التسليم",
          editedBy: drift.Value(widget.user.username),
        ),
      );
      await _loadData();
    });

    AppSound.play(TimaSound.success);
    _toast('تم تسليم الحركة وتحديث مخزون الصندوق', AppColors.success);
    if (!mounted) return;

    final receipt = DeliveryReceiptData.fromTransaction(
      tx: transaction.copyWith(
        status: 'تم التسليم',
        note: drift.Value(newNote),
      ),
      currency1: currency1,
      currency2: currency2,
      denoms1: counts1,
      denoms2: counts2,
      createdBy: widget.user.username,
      branch: widget.user.branch,
      statusOverride: 'تم التسليم',
    );
    await offerReceiptPrintAfterDelivery(context, receipt);
  }

  Future<void> _edit(Transaction transaction) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddDeliveryPage(
          db: widget.db,
          user: widget.user,
          transaction: transaction,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _openImport() async {
    final result = await Navigator.pushNamed(
      context,
      '/import_pending',
      arguments: widget.user,
    );
    if (result == true) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final totals = _currencyTotals();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: "الحركات المعلقة",
        actions: [
          IconButton(
            tooltip: 'تصدير Excel',
            onPressed: _pendingTransactions.isEmpty ? null : _exportExcel,
            icon: const Icon(Icons.table_view_rounded),
          ),
          IconButton(
            tooltip: "استيراد من Excel",
            onPressed: _openImport,
            icon: const Icon(Icons.upload_file_rounded),
          ),
          IconButton(
            tooltip: "تحديث القائمة",
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: TimaPageBackground(
        child: _loading
            ? const TimaLoader(message: 'جارٍ تحميل الحركات المعلقة…')
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: TimaContentWidth(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDims.pagePadding,
                          16,
                          AppDims.pagePadding,
                          0,
                        ),
                        child: TimaHeaderPanel(
                          icon: Icons.hourglass_empty_rounded,
                          title: 'الحركات المعلقة',
                          subtitle: _pendingTransactions.isEmpty
                              ? 'لا حركات بانتظار التسليم'
                              : '${_pendingTransactions.length} حركة تسليم بانتظار التسليم',
                          trailing: TimaStatusPill(
                            label: 'معلقة ${_pendingTransactions.length}',
                            color: AppColors.brandGold,
                            icon: Icons.pending_actions_rounded,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (totals.isNotEmpty)
                    SliverToBoxAdapter(
                      child: TimaContentWidth(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppDims.pagePadding,
                            12,
                            AppDims.pagePadding,
                            0,
                          ),
                          child: Row(
                            children: [
                              for (final entry in totals) ...[
                                Expanded(
                                  child: _CurrencyTotalTile(
                                    code: entry.key,
                                    count: entry.value.count,
                                    amount: entry.value.amount,
                                    formatAmount: _formatAmount,
                                  ),
                                ),
                                if (entry != totals.last)
                                  const SizedBox(width: 10),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_pendingTransactions.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: TimaEmptyState(
                        icon: Icons.check_circle_outline_rounded,
                        title: 'الصندوق مرتاح حالياً',
                        subtitle: 'جميع حركات التسليم تم إنهاؤها أو إلغاؤها.',
                        action: FilledButton.icon(
                          onPressed: _openImport,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('استيراد حركات من Excel'),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppDims.pagePadding,
                        12,
                        AppDims.pagePadding,
                        24,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tx = _pendingTransactions[index];
                            return TimaContentWidth(
                              child: _PendingRow(
                                key: ValueKey('pending-${tx.id}'),
                                index: index,
                                transaction: tx,
                                currencyCode: _currencyCode,
                                formatAmount: _formatAmount,
                                formatDate: _formatDate,
                                expanded: _expanded.contains(tx.id),
                                busy: _busyId == tx.id,
                                onToggle: () => setState(() {
                                  if (_expanded.contains(tx.id)) {
                                    _expanded.remove(tx.id);
                                  } else {
                                    _expanded.add(tx.id);
                                  }
                                }),
                                onDeliver: () => _deliver(tx),
                                onEdit: () => _edit(tx),
                                onCancel: () => _cancel(tx),
                                loadEdits: () =>
                                    widget.db.getEditsForTransaction(tx.id),
                              ),
                            );
                          },
                          childCount: _pendingTransactions.length,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _PendingCurrencyTotal {
  int count = 0;
  double amount = 0;
}

// ---------------------------------------------------------------------------
// بطاقة الحركة المعلقة — بنفس تصميم بطاقة سجل الحركات
// ---------------------------------------------------------------------------

class _PendingRow extends StatefulWidget {
  final int index;
  final Transaction transaction;
  final String Function(int?) currencyCode;
  final String Function(double) formatAmount;
  final String Function(DateTime) formatDate;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onDeliver;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Future<List<Edit>> Function() loadEdits;

  const _PendingRow({
    super.key,
    required this.index,
    required this.transaction,
    required this.currencyCode,
    required this.formatAmount,
    required this.formatDate,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onDeliver,
    required this.onEdit,
    required this.onCancel,
    required this.loadEdits,
  });

  @override
  State<_PendingRow> createState() => _PendingRowState();
}

class _PendingRowState extends State<_PendingRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final tint = AppUi.tone(context, AppColors.warning);
    final title = tx.beneficiary?.isNotEmpty == true
        ? tx.beneficiary!
        : 'مستفيد غير معروف';
    final amountText =
        '-${widget.formatAmount(tx.amount)} ${widget.currencyCode(tx.currencyId)}';

    return _Staggered(
      index: widget.index,
      child: Container(
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
                          child: Icon(
                            Icons.outbox_rounded,
                            color: tint,
                            size: 19,
                          ),
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
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 24,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: _hovered
                                      ? _quickActions(context)
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
                                                color: AppColors.error,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Flexible(
                                              child: Text(
                                                '${tx.type} • ${widget.formatDate(tx.createdAt)}',
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
                          const TimaStatusPill(
                            key: ValueKey('status-pending'),
                            label: 'معلقة',
                            color: AppColors.brandGoldDark,
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
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    return Row(
      key: const ValueKey('quick'),
      children: [
        _MiniAction(
          tooltip: 'تسليم الحركة',
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          onTap: widget.onDeliver,
        ),
        _MiniAction(
          tooltip: 'تعديل الحركة',
          icon: Icons.edit_outlined,
          color: AppColors.ocean,
          onTap: widget.onEdit,
        ),
        _MiniAction(
          tooltip: 'إلغاء الحركة',
          icon: Icons.cancel_outlined,
          color: AppColors.error,
          onTap: widget.onCancel,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '-${widget.formatAmount(widget.transaction.amount)} '
            '${widget.currencyCode(widget.transaction.currencyId)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _details(BuildContext context, Color tint) {
    final tx = widget.transaction;
    final has2 = tx.targetAmount != null && tx.targetCurrencyId != null;

    final facts = <Widget>[
      TimaKeyValue(
        label: 'تاريخ الإضافة',
        value: widget.formatDate(tx.createdAt),
        icon: Icons.schedule_rounded,
      ),
      TimaKeyValue(
        label: 'نوع الحركة',
        value: tx.type,
        icon: Icons.outbox_rounded,
      ),
      TimaKeyValue(
        label: 'المبلغ المطلوب تسليمه',
        value:
            '${widget.formatAmount(tx.amount)} ${widget.currencyCode(tx.currencyId)}',
        icon: Icons.paid_outlined,
        emphasized: true,
      ),
      if (has2)
        TimaKeyValue(
          label: 'المبلغ الثاني',
          value:
              '${widget.formatAmount(tx.targetAmount!)} ${widget.currencyCode(tx.targetCurrencyId)}',
          icon: Icons.swap_horiz_rounded,
        ),
      TimaKeyValue(
        label: 'مسجّل الحركة',
        value: tx.createdByName,
        icon: Icons.person_outline_rounded,
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
                        'ملاحظة وتفاصيل الحركة',
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: 'تسليم الحركة',
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                filled: true,
                onPressed: widget.onDeliver,
              ),
              _ActionButton(
                label: 'تعديل الحركة',
                icon: Icons.edit_outlined,
                color: tint,
                onPressed: widget.onEdit,
              ),
              _ActionButton(
                label: 'إلغاء الحركة',
                icon: Icons.cancel_outlined,
                color: AppColors.error,
                onPressed: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'حركة تسليم معلقة: تُسلَّم أو تُعدَّل أو تُلغى.',
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

/// بطاقة مجموع عملة معلّقة.
class _CurrencyTotalTile extends StatelessWidget {
  final String code;
  final int count;
  final double amount;
  final String Function(double) formatAmount;

  const _CurrencyTotalTile({
    required this.code,
    required this.count,
    required this.amount,
    required this.formatAmount,
  });

  @override
  Widget build(BuildContext context) {
    final tint = AppUi.tone(context, AppColors.brandGoldDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppUi.surface(context),
        borderRadius: BorderRadius.circular(AppDims.radius),
        border: Border.all(color: AppUi.border(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
            ),
            child: Center(
              child: Text(
                code,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: tint,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count حركة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatAmount(amount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: AppUi.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// زر إجراء مكتوب داخل بطاقة الحركة.
class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.filled = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
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
class _MiniAction extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MiniAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_MiniAction> createState() => _MiniActionState();
}

class _MiniActionState extends State<_MiniAction> {
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

/// ظهور تدريجي متدرّج لعناصر القائمة.
class _Staggered extends StatefulWidget {
  final int index;
  final Widget child;

  const _Staggered({required this.index, required this.child});

  @override
  State<_Staggered> createState() => _StaggeredState();
}

class _StaggeredState extends State<_Staggered>
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
