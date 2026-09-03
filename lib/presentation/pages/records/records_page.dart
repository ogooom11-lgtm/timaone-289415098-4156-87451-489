import 'package:drift/drift.dart' as drift;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/printing/delivery_receipt.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/denom_validator_dialog.dart';
import '../transactions/add_delivery_page.dart';
import '../transactions/add_exchange_page.dart';
import '../transactions/add_receive_page.dart';
import '../transactions/add_sent_page.dart';

class RecordsPage extends StatefulWidget {
  final AppDatabase db;
  final User user;

  const RecordsPage({super.key, required this.db, required this.user});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  final _searchController = TextEditingController();
  List<Transaction> _transactions = [];
  Map<int, Currency> _currencies = {};
  String? _typeFilter;
  int? _currencyFilter;
  String _dateFilter = "من أمس";
  DateTime? _selectedDate;
  int _visibleLimit = 20;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _visibleLimit = 20));
    _loadData();
  }

  Future<void> _loadData() async {
    final transactions = await widget.db.getAllTransactions();
    final currencies = await widget.db.getAllCurrencies();
    if (!mounted) return;
    setState(() {
      _transactions = transactions;
      _currencies = {for (final c in currencies) c.id: c};
      _loading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Transaction> get _filteredTransactions {
    final query = _searchController.text.trim();
    final now = DateTime.now();

    return _transactions.where((transaction) {
      final matchesSearch =
          query.isEmpty ||
          (transaction.beneficiary ?? "").contains(query) ||
          transaction.type.contains(query);
      final matchesType =
          _typeFilter == null || transaction.type == _typeFilter;
      final matchesCurrency =
          _currencyFilter == null ||
          transaction.currencyId == _currencyFilter ||
          transaction.targetCurrencyId == _currencyFilter ||
          transaction.feesCurrencyId == _currencyFilter;

      final created = transaction.createdAt.toLocal();
      final matchesDate = switch (_dateFilter) {
        "اليوم" =>
          created.year == now.year &&
              created.month == now.month &&
              created.day == now.day,
        "من أمس" => created.isAfter(
          DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 1)),
        ),
        "تاريخ محدد" =>
          _selectedDate != null &&
              created.year == _selectedDate!.year &&
              created.month == _selectedDate!.month &&
              created.day == _selectedDate!.day,
        _ => true,
      };

      return matchesSearch && matchesType && matchesCurrency && matchesDate;
    }).toList();
  }

  String _formatDate(DateTime date) {
    return DateFormat("yyyy-MM-dd HH:mm").format(date.toLocal());
  }

  String _currencyCode(int? id) {
    if (id == null) return "-";
    return _currencies[id]?.code ?? id.toString();
  }

  IconData _iconByType(String type) {
    if (type.contains("تسليم")) return Icons.outbox;
    if (type.contains("استلام")) return Icons.move_to_inbox;
    if (type.contains("مرسلة")) return Icons.send;
    if (type.contains("صرف") || type.contains("تسوية")) {
      return Icons.currency_exchange;
    }
    return Icons.description;
  }

  Color _colorByType(String type) {
    if (type.contains("تسليم")) return AppColors.warning;
    if (type.contains("استلام")) return AppColors.success;
    if (type.contains("مرسلة")) return AppColors.info;
    if (type.contains("صرف") || type.contains("تسوية")) {
      return AppColors.brandGold;
    }
    return AppColors.neutral500;
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
          content: Text("تم إلغاء الحركة وتحديث حالتها إلى (الغاء)"),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deliver(Transaction transaction) async {
    final currency1 = _currencies[transaction.currencyId];
    if (currency1 == null) return;

    // 1) فئات المبلغ الأول
    final stock1 = await CurrencyDenoms.loadStock(currency1);
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

    // 2) فئات المبلغ الثاني إن وُجد
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
    final denomLines = <String>[
      "[تم التسليم في $nowStr]",
      "[فئات المسلم: ${CurrencyDenoms.formatCounts(counts1)}]",
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
    await DeliveryReceiptService.offerPrintAfterDelivery(context, receipt);
  }

  Future<void> _revertDelivery(Transaction transaction) async {
    // 1) إعادة فئات المبلغ 1 + المبلغ 2 إلى مخزون الصندوق
    final currency1 = _currencies[transaction.currencyId];
    final restored1 = CurrencyDenoms.parseCounts(
      CurrencyDenoms.extractDeliveredDenomsNote(transaction.note),
    );
    if (currency1 != null && restored1.isNotEmpty) {
      await CurrencyDenoms.addStock(currency1, restored1);
    }

    Map<double, int> restored2 = {};
    if (transaction.targetCurrencyId != null) {
      final currency2 = _currencies[transaction.targetCurrencyId!];
      restored2 = CurrencyDenoms.parseCounts(
        CurrencyDenoms.extractDeliveredDenomsNote2(transaction.note),
      );
      if (currency2 != null && restored2.isNotEmpty) {
        await CurrencyDenoms.addStock(currency2, restored2);
      }
    }

    // 2) تنظيف الملاحظة وإرجاع الحالة لمعلقة
    String cleanNote = transaction.note ?? "";
    cleanNote = cleanNote
        .replaceAll(RegExp(r'\[تم التسليم في [^\]]+\]'), '')
        .trim();
    cleanNote = cleanNote
        .replaceAll(RegExp(r'\[فئات المسلم 2: [^\]]+\]'), '')
        .trim();
    cleanNote = cleanNote
        .replaceAll(RegExp(r'\[فئات المسلم: [^\]]+\]'), '')
        .trim();

    await widget.db.updateTransaction(
      transaction.id,
      TransactionsCompanion(
        status: const drift.Value("مضافة"), // الرجوع للوضع معلق
        note: drift.Value(cleanNote),
      ),
    );

    await widget.db.insertEdit(
      EditsCompanion.insert(
        transactionId: transaction.id,
        field: "تراجع عن التسليم",
        oldValue: "تم التسليم",
        newValue: "مضافة",
        editedBy: drift.Value(widget.user.username),
      ),
    );
    await _loadData();
    if (mounted) {
      final parts = <String>[];
      if (restored1.isNotEmpty) {
        parts.add(CurrencyDenoms.formatCounts(restored1));
      }
      if (restored2.isNotEmpty) {
        parts.add("2: ${CurrencyDenoms.formatCounts(restored2)}");
      }
      final restoredLabel = parts.isEmpty
          ? ""
          : " وأُعيدت الفئات: ${parts.join(" | ")}";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✓ تم التراجع عن التسليم وإعادة الحركة لمعلقة$restoredLabel",
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _revertCancellation(Transaction transaction) async {
    await widget.db.updateTransaction(
      transaction.id,
      const TransactionsCompanion(
        status: drift.Value("مضافة"), // الرجوع لوضع التعليق مضافة
        movementState: drift.Value("مفعلة"),
      ),
    );

    await widget.db.insertEdit(
      EditsCompanion.insert(
        transactionId: transaction.id,
        field: "تراجع عن الإلغاء",
        oldValue: "الغاء",
        newValue: "مضافة",
        editedBy: drift.Value(widget.user.username),
      ),
    );
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "✓ تم التراجع عن الإلغاء بنجاح وإعادة تفعيل الحركة كحركة معلقة",
          ),
          backgroundColor: AppColors.ocean,
        ),
      );
    }
  }

  Future<void> _edit(Transaction transaction) async {
    Widget page;
    if (transaction.type.contains("تسليم") ||
        transaction.type == "حركة تسليم" ||
        transaction.type == "حركة يوزر") {
      page = AddDeliveryPage(
        db: widget.db,
        user: widget.user,
        transaction: transaction,
      );
    } else if (transaction.type.contains("استلام") ||
        transaction.type == "حركة استلام") {
      page = AddReceivePage(
        db: widget.db,
        user: widget.user,
        transaction: transaction,
      );
    } else if (transaction.type.contains("مرسلة") ||
        transaction.type == "حركة مرسلة") {
      page = AddSentPage(
        db: widget.db,
        user: widget.user,
        transaction: transaction,
      );
    } else {
      page = AddExchangePage(
        db: widget.db,
        user: widget.user,
        transaction: transaction,
      );
    }

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    await _loadData();
  }

  bool get _hasActiveFilters =>
      _typeFilter != null ||
      _currencyFilter != null ||
      _dateFilter != 'من أمس' ||
      _searchController.text.trim().isNotEmpty;

  void _resetFilters() {
    setState(() {
      _typeFilter = null;
      _currencyFilter = null;
      _dateFilter = 'من أمس';
      _selectedDate = null;
      _searchController.clear();
      _visibleLimit = 20;
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _selectedDate = date;
        _dateFilter = 'تاريخ محدد';
        _visibleLimit = 20;
      });
    }
  }

  /// شريط الفلترة — ظاهر دائماً على سطح المكتب (أسرع من فتح نافذة).
  Widget _buildFilterBar() {
    return TimaPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم المستفيد أو نوع الحركة…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'مسح',
                            icon: const Icon(Icons.close_rounded, size: 17),
                            onPressed: () =>
                                setState(() => _searchController.clear()),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _hasActiveFilters ? _resetFilters : null,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('تصفير'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('تحديث'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  value: _typeFilter,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'نوع العملية',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('كل الأنواع')),
                    DropdownMenuItem(
                      value: 'حركة تسليم',
                      child: Text('حركة تسليم'),
                    ),
                    DropdownMenuItem(
                      value: 'حركة استلام',
                      child: Text('حركة استلام'),
                    ),
                    DropdownMenuItem(
                      value: 'حركة مرسلة',
                      child: Text('حركة مرسلة'),
                    ),
                    DropdownMenuItem(
                      value: 'حركة تسوية',
                      child: Text('حركة تسوية / صرف'),
                    ),
                    DropdownMenuItem(
                      value: 'حركة يوزر',
                      child: Text('حركة يوزر'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _typeFilter = value;
                    _visibleLimit = 20;
                  }),
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<int?>(
                  value: _currencyFilter,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'العملة',
                    prefixIcon: Icon(Icons.paid_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('كل العملات'),
                    ),
                    ..._currencies.values.map(
                      (currency) => DropdownMenuItem<int?>(
                        value: currency.id,
                        child: Text(currency.code),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _currencyFilter = value;
                    _visibleLimit = 20;
                  }),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  value: _dateFilter,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'الفترة',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'الكل', child: Text('كل الفترات')),
                    DropdownMenuItem(value: 'اليوم', child: Text('اليوم')),
                    DropdownMenuItem(value: 'من أمس', child: Text('من أمس')),
                    DropdownMenuItem(
                      value: 'تاريخ محدد',
                      child: Text('تاريخ محدد'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _dateFilter = value ?? 'الكل';
                    _visibleLimit = 20;
                  }),
                ),
              ),
              if (_dateFilter == 'تاريخ محدد')
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    _selectedDate == null
                        ? 'اختر التاريخ'
                        : DateFormat('yyyy-MM-dd').format(_selectedDate!),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _filteredTransactions;
    final visibleCount = math.min(_visibleLimit, transactions.length);
    final hasMore = transactions.length > visibleCount;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: 'سجل الحركات العام',
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: TimaPageBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.pagePadding,
                14,
                AppDims.pagePadding,
                0,
              ),
              child: TimaContentWidth(child: _buildFilterBar()),
            ),
            // شريط ملخّص النتائج
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.pagePadding,
                12,
                AppDims.pagePadding,
                0,
              ),
              child: TimaContentWidth(
                child: Row(
                  children: [
                    Icon(
                      Icons.list_alt_rounded,
                      size: 16,
                      color: AppUi.textSecondary(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _loading
                          ? 'جارٍ التحميل…'
                          : 'عرض $visibleCount من ${transactions.length} حركة',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (_hasActiveFilters)
                      const TimaStatusPill(
                        label: 'فلترة مفعّلة',
                        color: AppColors.ocean,
                        icon: Icons.filter_alt_rounded,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const TimaLoader(message: 'جارٍ تحميل السجل…')
                  : transactions.isEmpty
                      ? TimaEmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: _hasActiveFilters
                              ? 'لا نتائج مطابقة'
                              : 'لا توجد حركات',
                          subtitle: _hasActiveFilters
                              ? 'جرّب تعديل معايير البحث أو تصفير الفلاتر.'
                              : 'ستظهر الحركات المالية هنا بعد تسجيلها.',
                          action: _hasActiveFilters
                              ? OutlinedButton.icon(
                                  onPressed: _resetFilters,
                                  icon: const Icon(
                                    Icons.filter_alt_off_outlined,
                                  ),
                                  label: const Text('تصفير الفلاتر'),
                                )
                              : null,
                        )
                      : Scrollbar(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              AppDims.pagePadding,
                              12,
                              AppDims.pagePadding,
                              20,
                            ),
                            itemCount: visibleCount + (hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == visibleCount) {
                                return TimaContentWidth(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: OutlinedButton.icon(
                                      onPressed: () => setState(
                                        () => _visibleLimit += 20,
                                      ),
                                      icon: const Icon(
                                        Icons.expand_more_rounded,
                                      ),
                                      label: Text(
                                        'إظهار المزيد (${transactions.length - visibleCount})',
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final transaction = transactions[index];
                              return TimaContentWidth(
                                child: _TransactionCard(
                                  transaction: transaction,
                                  currencyCode: _currencyCode,
                                  formatDate: _formatDate,
                                  icon: _iconByType(transaction.type),
                                  color: _colorByType(transaction.type),
                                  onEdit: () => _edit(transaction),
                                  onCancel: () => _cancel(transaction),
                                  onDeliver: () => _deliver(transaction),
                                  onRevertDelivery: () =>
                                      _revertDelivery(transaction),
                                  onRevertCancellation: () =>
                                      _revertCancellation(transaction),
                                  loadEdits: () => widget.db
                                      .getEditsForTransaction(transaction.id),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final String Function(int?) currencyCode;
  final String Function(DateTime) formatDate;
  final IconData icon;
  final Color color;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onDeliver;
  final VoidCallback onRevertDelivery;
  final VoidCallback onRevertCancellation;
  final Future<List<Edit>> Function() loadEdits;

  const _TransactionCard({
    required this.transaction,
    required this.currencyCode,
    required this.formatDate,
    required this.icon,
    required this.color,
    required this.onEdit,
    required this.onCancel,
    required this.onDeliver,
    required this.onRevertDelivery,
    required this.onRevertCancellation,
    required this.loadEdits,
  });

  @override
  Widget build(BuildContext context) {
    final isExchange =
        transaction.type == "حركة تسوية" || transaction.type.contains("صرف");
    final title = transaction.beneficiary?.isNotEmpty == true
        ? transaction.beneficiary!
        : transaction.type;

    final isCanceled =
        transaction.movementState == "ملغية" || transaction.status == "الغاء";
    final isPending = transaction.status == "مضافة" && !isCanceled;

    final tint = isCanceled
        ? AppColors.neutral500
        : AppUi.tone(context, color);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppUi.panelDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
          ),
          child: Icon(icon, color: tint, size: 19),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppUi.textPrimary(context),
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            decoration: isCanceled ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Text(
                isExchange
                    ? "${transaction.amount} ${currencyCode(transaction.currencyId)}  ←  ${transaction.targetAmount ?? 0} ${currencyCode(transaction.targetCurrencyId)}"
                    : "${transaction.amount} ${currencyCode(transaction.currencyId)}",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: isCanceled
                      ? AppUi.textSecondary(context)
                      : AppUi.accent(context),
                  decoration: isCanceled ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  formatDate(transaction.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppUi.textSecondary(context),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: TimaStatusPill(
          label: isCanceled ? "إلغاء" : transaction.status,
          color: isCanceled
              ? AppColors.error
              : isPending
              ? AppColors.brandGoldDark
              : AppColors.success,
        ),
        children: [
          ListTile(
            dense: true,
            title: Text("التاريخ والوقت: ${formatDate(transaction.createdAt)}"),
            subtitle: Text(
              "مسجل الحركة: ${transaction.createdByName} • الحالة: ${transaction.status} • النوع: ${transaction.type}",
            ),
          ),

          if (transaction.targetAmount != null &&
              transaction.targetCurrencyId != null &&
              !isExchange)
            ListTile(
              dense: true,
              title: Text(
                "المبلغ 2: ${transaction.targetAmount} ${currencyCode(transaction.targetCurrencyId)}",
              ),
              subtitle: const Text("مبلغ ثانٍ مسجل بالحركة"),
            ),

          if (transaction.exchangeRate != null)
            ListTile(
              dense: true,
              title: Text("سعر الصرف: ${transaction.exchangeRate}"),
              subtitle: Text(
                "العملية الحسابية: ${transaction.operation ?? "-"}",
              ),
            ),
          if (transaction.fees != null)
            ListTile(
              dense: true,
              title: Text(
                "أجور وعمولة الحركة: ${transaction.fees} ${currencyCode(transaction.feesCurrencyId)}",
              ),
            ),
          if (transaction.note != null && transaction.note!.trim().isNotEmpty)
            ListTile(
              dense: true,
              title: const Text("ملاحظة وتفاصيل التسليم"),
              subtitle: Text(transaction.note!),
            ),

          // دقة متناهية: خيارات حركات التسليم التي ليست حركة يوزر
          if (transaction.type == "حركة تسليم")
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إجراءات حركة التسليم والتدقيق',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: AppUi.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // خيار 1: إذا كانت الحالة مضافة (معلقة) -> إظهار "تسليم" و "إلغاء"
                  if (isPending)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: onDeliver,
                            icon: const Icon(Icons.check_circle, size: 16),
                            label: const Text("تم التسليم"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                            ),
                            onPressed: onCancel,
                            icon: const Icon(Icons.cancel, size: 16),
                            label: const Text("الغاء"),
                          ),
                        ),
                      ],
                    ),

                  // خيار 2: إذا كانت الحالة "تم التسليم" -> إظهار "تراجع عن التسليم"
                  if (transaction.status == "تم التسليم")
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onRevertDelivery,
                        icon: const Icon(Icons.history_rounded, size: 16),
                        label: const Text("تراجع عن التسليم (إرجاع لمعلقة)"),
                      ),
                    ),

                  // خيار 3: إذا كانت الحالة "الغاء" أو ملغية -> إظهار "تراجع عن الالغاء"
                  if (isCanceled)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ocean,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onRevertCancellation,
                        icon: const Icon(Icons.autorenew_rounded, size: 16),
                        label: const Text("تراجع عن الالغاء (إرجاع لمعلقة)"),
                      ),
                    ),
                ],
              ),
            ),

          const Divider(indent: 16, endIndent: 16),

          ListTile(
            dense: true,
            title: const Text("التحكم والتعديل"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: "تعديل تفاصيل الحركة",
                  icon: const Icon(Icons.edit_outlined, color: AppColors.ocean),
                  onPressed: onEdit,
                ),
                if (!isCanceled)
                  IconButton(
                    tooltip: "إلغاء الحركة",
                    icon: const Icon(
                      Icons.cancel_outlined,
                      color: AppColors.error,
                    ),
                    onPressed: onCancel,
                  ),
              ],
            ),
          ),

          FutureBuilder<List<Edit>>(
            future: loadEdits(),
            builder: (context, snapshot) {
              final edits = snapshot.data ?? [];
              if (edits.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                color: AppUi.sunken(context),
                child: Column(
                  children: [
                    const ListTile(
                      dense: true,
                      title: Text(
                        "سجل التعديلات والتدقيق على هذه الحركة",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    ...edits.map(
                      (edit) => ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.history_toggle_off_rounded,
                          size: 16,
                        ),
                        title: Text(
                          "${edit.field}: ${edit.oldValue} ← ${edit.newValue}",
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          "${formatDate(edit.editedAt)} - ${edit.editedBy}",
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
