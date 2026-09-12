import 'package:drift/drift.dart' as drift;
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/printing/delivery_receipt.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/receipt_print_dialog.dart';
import '../../widgets/denom_validator_dialog.dart';
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

  Widget _buildSummary() {
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ملخص الحركات المعلقة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text('${_pendingTransactions.length} حركة بانتظار التسليم'),
          const Divider(height: 28),
          ...totals.entries.map(
            (entry) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(entry.key)),
                title: Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('${entry.value.count} حركة'),
                trailing: Text(
                  entry.value.amount.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(Transaction transaction) async {
    await widget.db.updateTransaction(
      transaction.id,
      const TransactionsCompanion(
        movementState: drift.Value("ملغية"),
        status: drift.Value("الغاء"),
      ),
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "✗ تم إلغاء حركة التسليم المعلقة وتحديث حالتها لـ إلغاء",
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
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

    await widget.db.updateTransaction(
      transaction.id,
      TransactionsCompanion(
        status: const drift.Value("تم التسليم"),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      endDrawer: Drawer(child: SafeArea(child: _buildSummary())),
      appBar: timaMaybeAppBar(
        context,
        title: "المعلقة والمتابعة",
        actions: [
          Builder(
            builder: (context) => IconButton(
              tooltip: 'ملخص الحركات',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.summarize_rounded),
            ),
          ),
          IconButton(
            tooltip: 'تصدير Excel',
            onPressed: _pendingTransactions.isEmpty ? null : _exportExcel,
            icon: const Icon(Icons.table_view_rounded),
          ),
          IconButton(
            tooltip: "استيراد من Excel",
            onPressed: () async {
              final result = await Navigator.pushNamed(
                context,
                '/import_pending',
                arguments: widget.user,
              );
              if (result == true) _loadData();
            },
            icon: const Icon(Icons.upload_file_rounded),
          ),
          IconButton(
            tooltip: "تحديث القائمة",
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.pushNamed(
            context,
            '/import_pending',
            arguments: widget.user,
          );
          if (result == true) _loadData();
        },
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('استيراد Excel'),
      ),
      body: TimaPageBackground(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pendingTransactions.isEmpty
          ? Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: TimaHeaderPanel(
                    icon: Icons.hourglass_empty_rounded,
                    title: 'لا توجد حركات معلقة',
                    subtitle: 'جميع حركات التسليم تم إنهاؤها أو إلغاؤها.',
                  ),
                ),
                const Expanded(
                  child: TimaEmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'الصندوق مرتاح حالياً',
                    subtitle: 'يمكنك استيراد حركات معلقة من Excel عند الحاجة.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: FilledButton.icon(
                    onPressed: () async {
                      final result = await Navigator.pushNamed(
                        context,
                        '/import_pending',
                        arguments: widget.user,
                      );
                      if (result == true) _loadData();
                    },
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('استيراد حركات معلقة من Excel'),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pendingTransactions.length,
              itemBuilder: (context, index) {
                final tx = _pendingTransactions[index];
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDims.radius),
                    side: BorderSide(color: AppUi.border(context)),
                  ),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.warning.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.history_toggle_off_rounded,
                        color: AppColors.brandGold,
                      ),
                    ),
                    title: Text(
                      tx.beneficiary ?? "مستفيد غير معروف",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      "المبلغ المطلوب تسليمه: -${tx.amount} ${_currencyCode(tx.currencyId)}",
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandGold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppDims.radiusSm),
                      ),
                      child: const Text(
                        "مضافة (معلقة)",
                        style: TextStyle(
                          color: AppColors.brandGoldDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                        ),
                        title: Text(
                          "تاريخ الإضافة: ${_formatDate(tx.createdAt)}",
                        ),
                        subtitle: Text("مسجل الحركة: ${tx.createdByName}"),
                      ),
                      if (tx.note != null && tx.note!.trim().isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.note_alt_rounded, size: 18),
                          title: const Text("ملاحظة"),
                          subtitle: Text(tx.note!),
                        ),
                      const Divider(indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppDims.radius),
                                  ),
                                ),
                                onPressed: () => _deliver(tx),
                                icon: const Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                ),
                                label: const Text("✓ تسليم الآن"),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(
                                    color: AppColors.error,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppDims.radius),
                                  ),
                                ),
                                onPressed: () => _cancel(tx),
                                icon: const Icon(Icons.cancel, size: 18),
                                label: const Text("✗ إلغاء الحركة"),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        dense: true,
                        title: const Text("تعديل تفاصيل الحركة المعلقة"),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: AppColors.ocean),
                          onPressed: () => _edit(tx),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}

class _PendingCurrencyTotal {
  int count = 0;
  double amount = 0;
}
