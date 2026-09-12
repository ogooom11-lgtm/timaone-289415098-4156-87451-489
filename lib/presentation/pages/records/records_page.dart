import 'dart:math' as math;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
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
import '../transactions/add_exchange_page.dart';
import '../transactions/add_receive_page.dart';
import '../transactions/add_sent_page.dart';

/// أنواع الحركات المعتمدة في السجل.
enum _TxKind { delivery, user, receive, sent, exchange }

_TxKind _kindOf(String type) {
  if (type == 'حركة يوزر') return _TxKind.user;
  if (type.contains('تسليم')) return _TxKind.delivery;
  if (type.contains('استلام')) return _TxKind.receive;
  if (type.contains('مرسلة')) return _TxKind.sent;
  return _TxKind.exchange;
}

/// سياسة الإجراءات المسموحة لكل حركة.
///
/// - تسليم: إلغاء / تعديل / تسليم (إن كانت معلقة)
/// - يوزر: إلغاء / تعديل / تسليم (إن كانت الحالة ملغية)
/// - استلام ومرسلة: تعديل / إلغاء
/// - ومع كل نوع: تراجع عن الإلغاء، وطباعة إيصال في أي وقت.
class _TxPolicy {
  final bool canDeliver;
  final bool canEdit;
  final bool canCancel;
  final bool canRevertCancel;
  final bool canRevertDelivery;
  final bool canPrint;
  final String hint;

  const _TxPolicy({
    required this.canDeliver,
    required this.canEdit,
    required this.canCancel,
    required this.canRevertCancel,
    required this.canRevertDelivery,
    required this.canPrint,
    required this.hint,
  });
}

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
  String _dateFilter = 'من أمس';
  DateTime? _selectedDate;
  String? _statusFilter;
  final Set<int> _expanded = {};

  int _visibleLimit = 20;
  bool _loading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() => _visibleLimit = 20);
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  // -------------------------------------------------------------------
  // الفلترة
  // -------------------------------------------------------------------

  bool _canceledOf(Transaction tx) =>
      tx.movementState == 'ملغية' || tx.status == 'الغاء';

  List<Transaction> get _scopedTransactions {
    final query = _searchController.text.trim();
    final now = DateTime.now();

    return _transactions.where((transaction) {
      final matchesSearch =
          query.isEmpty ||
          (transaction.beneficiary ?? '').contains(query) ||
          transaction.type.contains(query) ||
          transaction.createdByName.contains(query);
      final matchesType =
          _typeFilter == null || transaction.type == _typeFilter;
      final matchesCurrency =
          _currencyFilter == null ||
          transaction.currencyId == _currencyFilter ||
          transaction.targetCurrencyId == _currencyFilter ||
          transaction.feesCurrencyId == _currencyFilter;

      final created = transaction.createdAt.toLocal();
      final matchesDate = switch (_dateFilter) {
        'اليوم' =>
          created.year == now.year &&
              created.month == now.month &&
              created.day == now.day,
        'من أمس' => created.isAfter(
          DateTime(now.year, now.month, now.day).subtract(
            const Duration(days: 1),
          ),
        ),
        'تاريخ محدد' =>
          _selectedDate != null &&
              created.year == _selectedDate!.year &&
              created.month == _selectedDate!.month &&
              created.day == _selectedDate!.day,
        _ => true,
      };

      return matchesSearch && matchesType && matchesCurrency && matchesDate;
    }).toList();
  }

  List<Transaction> get _filteredTransactions {
    final scoped = _scopedTransactions;
    if (_statusFilter == null) return scoped;
    return scoped.where((tx) {
      if (_canceledOf(tx)) return _statusFilter == 'ملغية';
      if (tx.status == 'تم التسليم') return _statusFilter == 'مسلمة';
      return _statusFilter == 'معلقة';
    }).toList();
  }

  Map<String, int> get _statusCounts {
    final counts = {'معلقة': 0, 'مسلمة': 0, 'ملغية': 0};
    for (final tx in _scopedTransactions) {
      if (_canceledOf(tx)) {
        counts['ملغية'] = counts['ملغية']! + 1;
      } else if (tx.status == 'تم التسليم') {
        counts['مسلمة'] = counts['مسلمة']! + 1;
      } else {
        counts['معلقة'] = counts['معلقة']! + 1;
      }
    }
    return counts;
  }

  Map<String, int> get _typeCounts {
    final counts = <String, int>{};
    for (final tx in _transactions) {
      counts[tx.type] = (counts[tx.type] ?? 0) + 1;
    }
    return counts;
  }

  bool get _hasActiveFilters =>
      _typeFilter != null ||
      _currencyFilter != null ||
      _statusFilter != null ||
      _dateFilter != 'من أمس' ||
      _searchController.text.trim().isNotEmpty;

  void _resetFilters() {
    setState(() {
      _typeFilter = null;
      _currencyFilter = null;
      _statusFilter = null;
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
    if (date != null && mounted) {
      setState(() {
        _selectedDate = date;
        _dateFilter = 'تاريخ محدد';
        _visibleLimit = 20;
      });
    }
  }

  // -------------------------------------------------------------------
  // تنسيقات مساعدة
  // -------------------------------------------------------------------

  String _formatDate(DateTime date) =>
      DateFormat('yyyy-MM-dd  HH:mm').format(date.toLocal());

  String _currencyCode(int? id) {
    if (id == null) return '-';
    return _currencies[id]?.code ?? id.toString();
  }

  String _currencyName(int? id) {
    if (id == null) return '-';
    final currency = _currencies[id];
    return currency == null ? id.toString() : CurrencyDenoms.displayName(
      currency,
    );
  }

  String _formatAmount(double value) =>
      NumberFormat('#,##0.##', 'en').format(value);

  IconData _iconOf(_TxKind kind) => switch (kind) {
    _TxKind.delivery => Icons.outbox_rounded,
    _TxKind.user => Icons.person_rounded,
    _TxKind.receive => Icons.move_to_inbox_rounded,
    _TxKind.sent => Icons.send_rounded,
    _TxKind.exchange => Icons.currency_exchange_rounded,
  };

  Color _colorOf(_TxKind kind) => switch (kind) {
    _TxKind.delivery => AppColors.warning,
    _TxKind.user => AppColors.violet,
    _TxKind.receive => AppColors.success,
    _TxKind.sent => AppColors.ocean,
    _TxKind.exchange => AppColors.brandGoldDark,
  };

  _TxPolicy _policyOf(Transaction tx) {
    final canceled = _canceledOf(tx);
    final pending = !canceled && tx.status == 'مضافة';
    final delivered = !canceled && tx.status == 'تم التسليم';

    return switch (_kindOf(tx.type)) {
      _TxKind.delivery => _TxPolicy(
        canDeliver: pending,
        canEdit: true,
        canCancel: !canceled,
        canRevertCancel: canceled,
        canRevertDelivery: delivered,
        canPrint: true,
        hint: 'حركة تسليم: تُسلَّم أو تُعدَّل أو تُلغى، والتراجع متاح دائماً',
      ),
      _TxKind.user => _TxPolicy(
        canDeliver: canceled,
        canEdit: true,
        canCancel: !canceled,
        canRevertCancel: canceled,
        canRevertDelivery: false,
        canPrint: true,
        hint: canceled
            ? 'حركة يوزر ملغية: يمكن تسليمها أو تعديلها أو التراجع عن الإلغاء'
            : 'حركة يوزر: تُلغى أو تُعدَّل، وتُسلَّم بعد الإلغاء',
      ),
      _TxKind.receive => _TxPolicy(
        canDeliver: false,
        canEdit: true,
        canCancel: !canceled,
        canRevertCancel: canceled,
        canRevertDelivery: false,
        canPrint: true,
        hint: 'حركة استلام: تُعدَّل أو تُلغى، مع إمكانية التراجع',
      ),
      _TxKind.sent => _TxPolicy(
        canDeliver: false,
        canEdit: true,
        canCancel: !canceled,
        canRevertCancel: canceled,
        canRevertDelivery: false,
        canPrint: true,
        hint: 'حركة مرسلة: تُعدَّل أو تُلغى، مع إمكانية التراجع',
      ),
      _TxKind.exchange => _TxPolicy(
        canDeliver: false,
        canEdit: true,
        canCancel: !canceled,
        canRevertCancel: canceled,
        canRevertDelivery: false,
        canPrint: true,
        hint: 'حركة تسوية/صرف: تُعدَّل أو تُلغى',
      ),
    };
  }

  void _toast(String message, Color color, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          action: action,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // -------------------------------------------------------------------
  // الإجراءات
  // -------------------------------------------------------------------

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
              const Expanded(child: Text('إلغاء الحركة؟')),
            ],
          ),
          content: Text(
            'ستتحول حركة «${transaction.beneficiary?.isNotEmpty == true ? transaction.beneficiary : transaction.type}» '
            'بمبلغ $amount إلى حالة ملغية. يمكن التراجع عن الإلغاء في أي وقت.',
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

  Future<void> _withBusy(int id, Future<void> Function() action) async {
    setState(() => _busyId = id);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _cancel(Transaction transaction) async {
    if (!await _confirmCancel(transaction)) return;
    await _withBusy(transaction.id, () async {
      await widget.db.updateTransaction(
        transaction.id,
        const TransactionsCompanion(
          movementState: drift.Value('ملغية'),
          status: drift.Value('الغاء'),
        ),
      );
      await widget.db.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: 'وضع الحركة',
          oldValue: transaction.movementState,
          newValue: 'ملغية',
          editedBy: drift.Value(widget.user.username),
        ),
      );
      await _loadData();
    });
    AppSound.play(TimaSound.error);
    _toast(
      'تم إلغاء الحركة — يمكنك التراجع الآن',
      AppColors.error,
      action: SnackBarAction(
        label: 'تراجع',
        textColor: Colors.white,
        onPressed: () => _revertCancellation(transaction),
      ),
    );
  }

  Future<void> _revertCancellation(Transaction transaction) async {
    await _withBusy(transaction.id, () async {
      await widget.db.updateTransaction(
        transaction.id,
        const TransactionsCompanion(
          status: drift.Value('مضافة'),
          movementState: drift.Value('مفعلة'),
        ),
      );
      await widget.db.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: 'تراجع عن الإلغاء',
          oldValue: 'الغاء',
          newValue: 'مضافة',
          editedBy: drift.Value(widget.user.username),
        ),
      );
      await _loadData();
    });
    AppSound.play(TimaSound.success);
    _toast('تم التراجع عن الإلغاء — عادت الحركة معلقة', AppColors.ocean);
  }

  Future<void> _deliver(Transaction transaction) async {
    final currency1 = _currencies[transaction.currencyId];
    if (currency1 == null) {
      _toast('عملة الحركة غير معرّفة', AppColors.error);
      return;
    }

    final stock1 = await CurrencyDenoms.loadStock(currency1);
    if (!mounted) return;
    final counts1 = await showDialog<Map<double, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenomValidatorDialog(
        targetAmount: transaction.amount,
        currency: currency1,
        title: 'تفصيل فئات المبلغ 1 (${currency1.code})',
        mode: DenomDialogMode.outflow,
        availableStock: stock1,
      ),
    );
    if (counts1 == null) return;

    Map<double, int>? counts2;
    Currency? currency2;
    if (transaction.targetAmount != null &&
        transaction.targetAmount! > 0 &&
        transaction.targetCurrencyId != null) {
      currency2 = _currencies[transaction.targetCurrencyId!];
      if (currency2 == null) {
        _toast('عملة المبلغ الثاني غير معرّفة — أضفها من الإعدادات', AppColors.error);
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
          title: 'تفصيل فئات المبلغ 2 (${currency2.code})',
          mode: DenomDialogMode.outflow,
          availableStock: stock2,
        ),
      );
      if (counts2 == null) return;
    }

    final nowStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final denomLines = <String>[
      '[تم التسليم في $nowStr]',
      '[فئات المسلم: ${CurrencyDenoms.formatCounts(counts1)}]',
    ];
    if (counts2 != null && currency2 != null) {
      denomLines.add(
        '[فئات المسلم 2: ${CurrencyDenoms.formatCounts(counts2)} (${currency2.code})]',
      );
    }

    final cleanBase = transaction.note == null
        ? ''
        : transaction.note!
              .replaceAll(RegExp(r'\[تم التسليم في [^\]]+\]'), '')
              .replaceAll(RegExp(r'\[فئات المسلم 2: [^\]]+\]'), '')
              .replaceAll(RegExp(r'\[فئات المسلم: [^\]]+\]'), '')
              .trim();
    final newNote = cleanBase.isEmpty
        ? denomLines.join('\n')
        : '$cleanBase\n${denomLines.join('\n')}';

    await _withBusy(transaction.id, () async {
      await widget.db.updateTransaction(
        transaction.id,
        TransactionsCompanion(
          status: const drift.Value('تم التسليم'),
          movementState: const drift.Value('مفعلة'),
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
          field: 'تغيير الحالة والتسليم',
          oldValue: transaction.status,
          newValue: 'تم التسليم',
          editedBy: drift.Value(widget.user.username),
        ),
      );
      await _loadData();
    });

    AppSound.play(TimaSound.success);
    _toast('تم تسليم الحركة وتحديث مخزون الصندوق', AppColors.success);
    if (!mounted) return;

    final receipt = DeliveryReceiptData.fromTransaction(
      tx: transaction.copyWith(status: 'تم التسليم', note: drift.Value(newNote)),
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

  Future<void> _revertDelivery(Transaction transaction) async {
    final currency1 = _currencies[transaction.currencyId];
    final restored1 = CurrencyDenoms.parseCounts(
      CurrencyDenoms.extractDeliveredDenomsNote(transaction.note),
    );
    if (currency1 != null && restored1.isNotEmpty) {
      await CurrencyDenoms.addStock(currency1, restored1);
    }

    final restored2 = <double, int>{};
    if (transaction.targetCurrencyId != null) {
      final currency2 = _currencies[transaction.targetCurrencyId!];
      restored2.addAll(
        CurrencyDenoms.parseCounts(
          CurrencyDenoms.extractDeliveredDenomsNote2(transaction.note),
        ),
      );
      if (currency2 != null && restored2.isNotEmpty) {
        await CurrencyDenoms.addStock(currency2, restored2);
      }
    }

    final cleanNote = (transaction.note ?? '')
        .replaceAll(RegExp(r'\[تم التسليم في [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم 2: [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم: [^\]]+\]'), '')
        .trim();

    await _withBusy(transaction.id, () async {
      await widget.db.updateTransaction(
        transaction.id,
        TransactionsCompanion(
          status: const drift.Value('مضافة'),
          movementState: const drift.Value('مفعلة'),
          note: drift.Value(cleanNote),
        ),
      );
      await widget.db.insertEdit(
        EditsCompanion.insert(
          transactionId: transaction.id,
          field: 'تراجع عن التسليم',
          oldValue: 'تم التسليم',
          newValue: 'مضافة',
          editedBy: drift.Value(widget.user.username),
        ),
      );
      await _loadData();
    });

    final parts = <String>[
      if (restored1.isNotEmpty) CurrencyDenoms.formatCounts(restored1),
      if (restored2.isNotEmpty) '2: ${CurrencyDenoms.formatCounts(restored2)}',
    ];
    AppSound.play(TimaSound.alert);
    _toast(
      'تم التراجع عن التسليم${parts.isEmpty ? '' : ' وأُعيدت الفئات: ${parts.join(' | ')}'}',
      AppColors.warning,
    );
  }

  Future<void> _edit(Transaction transaction) async {
    final page = switch (_kindOf(transaction.type)) {
      _TxKind.delivery || _TxKind.user => AddDeliveryPage(
        db: widget.db,
        user: widget.user,
        transaction: transaction,
      ),
      _TxKind.receive => AddReceivePage(
        db: widget.db,
        user: widget.user,
        transaction: transaction,
      ),
      _TxKind.sent => AddSentPage(
        db: widget.db,
        user: widget.user,
        transaction: transaction,
      ),
      _TxKind.exchange => AddExchangePage(
        db: widget.db,
        user: widget.user,
        transaction: transaction,
      ),
    };

    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => page));
    await _loadData();
  }

  /// طباعة إيصال لأي حركة وفي أي وقت.
  Future<void> _printReceipt(Transaction transaction) async {
    final currency1 = _currencies[transaction.currencyId];
    if (currency1 == null) {
      _toast('عملة الحركة غير معرّفة — لا يمكن طباعة الإيصال', AppColors.error);
      return;
    }
    final currency2 = transaction.targetCurrencyId == null
        ? null
        : _currencies[transaction.targetCurrencyId];

    final receipt = DeliveryReceiptData.fromStoredTransaction(
      tx: transaction,
      currency1: currency1,
      currency2: currency2,
      createdBy: widget.user.username,
      branch: widget.user.branch,
    );
    await printDeliveryReceipt(context, receipt);
  }

  // -------------------------------------------------------------------
  // الواجهة
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final transactions = _filteredTransactions;
    final visibleCount = math.min(_visibleLimit, transactions.length);
    final hasMore = transactions.length > visibleCount;
    final statusCounts = _statusCounts;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: 'سجل الحركات',
        actions: [
          IconButton(
            tooltip: 'تحديث السجل',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: TimaPageBackground(
        child: _loading
            ? const TimaLoader(message: 'جارٍ تحميل سجل الحركات…')
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
                        child: _buildHeader(context, statusCounts),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: TimaContentWidth(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDims.pagePadding,
                          12,
                          AppDims.pagePadding,
                          0,
                        ),
                        child: _buildFilters(context),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: TimaContentWidth(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDims.pagePadding,
                          12,
                          AppDims.pagePadding,
                          0,
                        ),
                        child: _buildSummary(context, statusCounts),
                      ),
                    ),
                  ),
                  if (transactions.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: TimaEmptyState(
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
                            if (index == visibleCount) {
                              return TimaContentWidth(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
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
                            final policy = _policyOf(transaction);
                            return TimaContentWidth(
                              child: _Staggered(
                                index: index,
                                child: _TransactionRow(
                                  key: ValueKey('tx-${transaction.id}'),
                                  transaction: transaction,
                                  policy: policy,
                                  kind: _kindOf(transaction.type),
                                  icon: _iconOf(_kindOf(transaction.type)),
                                  tint: _colorOf(_kindOf(transaction.type)),
                                  currencyCode: _currencyCode,
                                  currencyName: _currencyName,
                                  formatAmount: _formatAmount,
                                  formatDate: _formatDate,
                                  expanded: _expanded.contains(transaction.id),
                                  busy: _busyId == transaction.id,
                                  onToggle: () => setState(() {
                                    if (_expanded.contains(transaction.id)) {
                                      _expanded.remove(transaction.id);
                                    } else {
                                      _expanded.add(transaction.id);
                                    }
                                  }),
                                  onEdit: () => _edit(transaction),
                                  onCancel: () => _cancel(transaction),
                                  onDeliver: () => _deliver(transaction),
                                  onRevertCancel: () =>
                                      _revertCancellation(transaction),
                                  onRevertDelivery: () =>
                                      _revertDelivery(transaction),
                                  onPrint: () => _printReceipt(transaction),
                                  loadEdits: () => widget.db
                                      .getEditsForTransaction(transaction.id),
                                ),
                              ),
                            );
                          },
                          childCount: visibleCount + (hasMore ? 1 : 0),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Map<String, int> statusCounts) {
    final total = _transactions.length;
    final pending = statusCounts['معلقة'] ?? 0;
    final canceled = statusCounts['ملغية'] ?? 0;

    return TimaHeaderPanel(
      icon: Icons.receipt_long_rounded,
      title: 'سجل الحركات العام',
      subtitle: total == 0
          ? 'لا حركات مسجّلة بعد'
          : '$total حركة مسجّلة — منها $pending بانتظار التسليم',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TimaStatusPill(
            label: 'معلقة $pending',
            color: AppColors.brandGold,
            icon: Icons.pending_actions_rounded,
          ),
          const SizedBox(width: 6),
          TimaStatusPill(
            label: 'ملغية $canceled',
            color: AppColors.error,
            icon: Icons.block_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final typeCounts = _typeCounts;
    final typeOrder = <String>[
      'حركة تسليم',
      'حركة يوزر',
      'حركة استلام',
      'حركة مرسلة',
      'حركة تسوية',
    ];
    final types = [
      ...typeOrder.where(typeCounts.containsKey),
      ...typeCounts.keys.where((t) => !typeOrder.contains(t)),
    ];

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
                    hintText: 'ابحث بالاسم أو نوع الحركة أو اسم المسجّل…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'مسح البحث',
                            icon: const Icon(Icons.close_rounded, size: 17),
                            onPressed: () => setState(
                              () => _searchController.clear(),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 168,
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
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _hasActiveFilters ? _resetFilters : null,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                label: const Text('تصفير'),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ChipButton(
                label: 'كل الأنواع',
                icon: Icons.all_inclusive_rounded,
                count: _transactions.length,
                selected: _typeFilter == null,
                onTap: () => setState(() {
                  _typeFilter = null;
                  _visibleLimit = 20;
                }),
              ),
              ...types.map((type) {
                final kind = _kindOf(type);
                return _ChipButton(
                  label: type,
                  icon: _iconOf(kind),
                  color: _colorOf(kind),
                  count: typeCounts[type] ?? 0,
                  selected: _typeFilter == type,
                  onTap: () => setState(() {
                    _typeFilter = _typeFilter == type ? null : type;
                    _visibleLimit = 20;
                  }),
                );
              }),
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: AppUi.border(context),
              ),
              for (final period in const ['اليوم', 'من أمس', 'الكل'])
                _ChipButton(
                  label: period,
                  icon: Icons.event_rounded,
                  selected: _dateFilter == period,
                  onTap: () => setState(() {
                    _dateFilter = period;
                    _visibleLimit = 20;
                  }),
                ),
              _ChipButton(
                label: _selectedDate == null
                    ? 'تاريخ محدد'
                    : DateFormat('MM-dd').format(_selectedDate!),
                icon: Icons.calendar_month_rounded,
                selected: _dateFilter == 'تاريخ محدد',
                onTap: _pickDate,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, Map<String, int> statusCounts) {
    final transactions = _filteredTransactions;
    final pendingCount = statusCounts['معلقة'] ?? 0;
    final deliveredCount = statusCounts['مسلمة'] ?? 0;
    final canceledCount = statusCounts['ملغية'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.list_alt_rounded,
              size: 16,
              color: AppUi.textSecondary(context),
            ),
            const SizedBox(width: 8),
            Text(
              'عرض ${math.min(_visibleLimit, transactions.length)} من ${transactions.length} حركة',
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
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: 'معلقة',
                value: '$pendingCount',
                icon: Icons.pending_actions_rounded,
                color: AppColors.brandGoldDark,
                selected: _statusFilter == 'معلقة',
                onTap: () => setState(() {
                  _statusFilter = _statusFilter == 'معلقة' ? null : 'معلقة';
                  _visibleLimit = 20;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryTile(
                label: 'مسلمة',
                value: '$deliveredCount',
                icon: Icons.task_alt_rounded,
                color: AppColors.success,
                selected: _statusFilter == 'مسلمة',
                onTap: () => setState(() {
                  _statusFilter = _statusFilter == 'مسلمة' ? null : 'مسلمة';
                  _visibleLimit = 20;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryTile(
                label: 'ملغية',
                value: '$canceledCount',
                icon: Icons.block_rounded,
                color: AppColors.error,
                selected: _statusFilter == 'ملغية',
                onTap: () => setState(() {
                  _statusFilter = _statusFilter == 'ملغية' ? null : 'ملغية';
                  _visibleLimit = 20;
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// بطاقة الحركة
// ---------------------------------------------------------------------------

class _TransactionRow extends StatefulWidget {
  final Transaction transaction;
  final _TxPolicy policy;
  final _TxKind kind;
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

  const _TransactionRow({
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
  State<_TransactionRow> createState() => _TransactionRowState();
}

class _TransactionRowState extends State<_TransactionRow> {
  bool _hovered = false;

  bool get _canceled =>
      widget.transaction.movementState == 'ملغية' ||
      widget.transaction.status == 'الغاء';

  bool get _delivered =>
      !_canceled && widget.transaction.status == 'تم التسليم';

  Color get _statusColor => _canceled
      ? AppColors.error
      : _delivered
      ? AppColors.success
      : AppColors.brandGoldDark;

  String get _statusLabel => _canceled
      ? 'ملغية'
      : (widget.transaction.status.isEmpty ? 'مضافة' : widget.transaction.status);

  @override
  Widget build(BuildContext context) {
    final tint = _canceled
        ? AppColors.neutral500
        : AppUi.tone(context, widget.tint);
    final title = widget.transaction.beneficiary?.isNotEmpty == true
        ? widget.transaction.beneficiary!
        : widget.transaction.type;

    final isExchange = widget.kind == _TxKind.exchange;
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
                                                  ? AppUi.textSecondary(context)
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
        _MiniAction(
          tooltip: 'تسليم الحركة',
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          onTap: widget.onDeliver,
        ),
      if (policy.canPrint)
        _MiniAction(
          tooltip: 'طباعة إيصال',
          icon: Icons.print_rounded,
          color: AppColors.ocean,
          onTap: widget.onPrint,
        ),
      if (policy.canEdit)
        _MiniAction(
          tooltip: 'تعديل الحركة',
          icon: Icons.edit_outlined,
          color: tint,
          onTap: widget.onEdit,
        ),
      if (policy.canRevertCancel)
        _MiniAction(
          tooltip: 'تراجع عن الإلغاء',
          icon: Icons.autorenew_rounded,
          color: AppColors.ocean,
          onTap: widget.onRevertCancel,
        ),
      if (policy.canCancel)
        _MiniAction(
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
              for (final fact in facts)
                SizedBox(width: 268, child: fact),
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
          _ActionButton(
            label: _canceled ? 'تسليم الحركة' : 'تم التسليم',
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
            filled: true,
            onPressed: widget.onDeliver,
          ),
        if (policy.canPrint)
          _ActionButton(
            label: 'طباعة إيصال',
            icon: Icons.print_rounded,
            color: AppColors.ocean,
            onPressed: widget.onPrint,
          ),
        if (policy.canEdit)
          _ActionButton(
            label: 'تعديل الحركة',
            icon: Icons.edit_outlined,
            color: tint,
            onPressed: widget.onEdit,
          ),
        if (policy.canRevertCancel)
          _ActionButton(
            label: 'تراجع عن الإلغاء',
            icon: Icons.autorenew_rounded,
            color: AppColors.ocean,
            filled: true,
            onPressed: widget.onRevertCancel,
          ),
        if (policy.canRevertDelivery)
          _ActionButton(
            label: 'تراجع عن التسليم',
            icon: Icons.history_rounded,
            color: AppColors.warning,
            onPressed: widget.onRevertDelivery,
          ),
        if (policy.canCancel)
          _ActionButton(
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

// ---------------------------------------------------------------------------
// عناصر صغيرة
// ---------------------------------------------------------------------------

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

/// زر فلترة صغير بعدّاد.
class _ChipButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _ChipButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.color,
    this.count,
  });

  @override
  State<_ChipButton> createState() => _ChipButtonState();
}

class _ChipButtonState extends State<_ChipButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? AppColors.brandGreen;
    final tint = AppUi.tone(context, base);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: widget.selected
                ? tint.withValues(alpha: _hovered ? 0.22 : 0.14)
                : (_hovered ? AppUi.hover(context) : AppUi.sunken(context)),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(
              color: widget.selected
                  ? tint.withValues(alpha: 0.6)
                  : AppUi.border(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: tint),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.selected
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: widget.selected
                      ? AppUi.textPrimary(context)
                      : AppUi.textSecondary(context),
                ),
              ),
              if (widget.count != null) ...[
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? tint.withValues(alpha: 0.22)
                        : AppUi.border(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: widget.selected
                          ? tint
                          : AppUi.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة حالة قابلة للنقر (معلقة / مسلمة / ملغية).
class _SummaryTile extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SummaryTile> createState() => _SummaryTileState();
}

class _SummaryTileState extends State<_SummaryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tint = AppUi.tone(context, widget.color);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: widget.selected
                ? tint.withValues(alpha: _hovered ? 0.20 : 0.13)
                : AppUi.surface(context),
            borderRadius: BorderRadius.circular(AppDims.radius),
            border: Border.all(
              color: widget.selected
                  ? tint.withValues(alpha: 0.65)
                  : (_hovered ? tint.withValues(alpha: 0.35) : AppUi.border(
                        context,
                      )),
            ),
            boxShadow: _hovered ? AppUi.softShadow(context) : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppDims.radiusSm),
                ),
                child: Icon(widget.icon, size: 17, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: widget.selected
                            ? AppUi.textPrimary(context)
                            : AppUi.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.value,
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        color: widget.selected
                            ? tint
                            : AppUi.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: widget.selected ? 1 : (_hovered ? 0.6 : 0),
                child: Icon(
                  widget.selected
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                  size: 15,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ظهور تدريجي متدرّج لعناصر القائمة — يريح العين عند التحميل والفلترة.
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
