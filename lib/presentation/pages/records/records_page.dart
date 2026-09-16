import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import 'transaction_row.dart';
import 'tx_shared.dart';

class RecordsPage extends StatefulWidget {
  final AppDatabase db;
  final User user;

  const RecordsPage({super.key, required this.db, required this.user});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> with TxActions<RecordsPage> {
  @override
  AppDatabase get txDb => widget.db;
  @override
  User get txUser => widget.user;
  @override
  Map<int, Currency> get txCurrencies => _currencies;
  @override
  Future<void> refreshTxData() => _loadData();

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

  /// الحركة المعلقة = حركة تسليم حالتها «مضافة» (لم تُلغَ ولم تُسلَّم).
  /// بقية الأنواع (استلام/مرسلة/تسوية/يوزر) لا تدخل في تبويب المعلقة.
  bool _isPending(Transaction tx) =>
      !_canceledOf(tx) &&
      kindOfTx(tx.type) == TxKind.delivery &&
      tx.status == 'مضافة';

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
      if (_isPending(tx)) return _statusFilter == 'معلقة';
      return false;
    }).toList();
  }

  Map<String, int> get _statusCounts {
    final counts = {'معلقة': 0, 'مسلمة': 0, 'ملغية': 0};
    for (final tx in _scopedTransactions) {
      if (_canceledOf(tx)) {
        counts['ملغية'] = counts['ملغية']! + 1;
      } else if (tx.status == 'تم التسليم') {
        counts['مسلمة'] = counts['مسلمة']! + 1;
      } else if (_isPending(tx)) {
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
                            final policy = policyOfTx(transaction);
                            return TimaContentWidth(
                              child: TxStaggered(
                                index: index,
                                child: TransactionRow(
                                  key: ValueKey('tx-${transaction.id}'),
                                  transaction: transaction,
                                  policy: policy,
                                  kind: kindOfTx(transaction.type),
                                  icon: iconOfTx(kindOfTx(transaction.type)),
                                  tint: colorOfTx(kindOfTx(transaction.type)),
                                  currencyCode: txCurrencyCode,
                                  currencyName: txCurrencyName,
                                  formatAmount: formatTxAmount,
                                  formatDate: formatTxDate,
                                  expanded: _expanded.contains(transaction.id),
                                  busy: busyTxId == transaction.id,
                                  onToggle: () => setState(() {
                                    if (_expanded.contains(transaction.id)) {
                                      _expanded.remove(transaction.id);
                                    } else {
                                      _expanded.add(transaction.id);
                                    }
                                  }),
                                  onEdit: () => editTx(transaction),
                                  onCancel: () => cancelTx(transaction),
                                  onDeliver: () => deliverTx(transaction),
                                  onRevertCancel: () =>
                                      revertCancellation(transaction),
                                  onRevertDelivery: () =>
                                      revertDelivery(transaction),
                                  onPrint: () => printTxReceipt(transaction),
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

  bool get _hasNonSearchFilters =>
      _typeFilter != null ||
      _currencyFilter != null ||
      _statusFilter != null ||
      _dateFilter != 'من أمس';

  Widget _buildFilters(BuildContext context) {
    return TimaPanel(
      padding: const EdgeInsets.all(12),
      child: Row(
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
          Tooltip(
            message: 'الفلاتر',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                OutlinedButton(
                  onPressed: _openFilterDialog,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: _hasNonSearchFilters
                        ? AppColors.brandGreen
                        : null,
                  ),
                ),
                if (_hasNonSearchFilters)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
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
    );
  }

  Future<void> _openFilterDialog() async {
    String? type = _typeFilter;
    int? currency = _currencyFilter;
    String date = _dateFilter;
    DateTime? specific = _selectedDate;
    String? status = _statusFilter;

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

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('تصفية الحركات'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  label('النوع'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ChipButton(
                        label: 'كل الأنواع',
                        icon: Icons.all_inclusive_rounded,
                        count: _transactions.length,
                        selected: type == null,
                        onTap: () => setLocal(() => type = null),
                      ),
                      ...types.map((t) {
                        final kind = kindOfTx(t);
                        return _ChipButton(
                          label: t,
                          icon: iconOfTx(kind),
                          color: colorOfTx(kind),
                          count: typeCounts[t] ?? 0,
                          selected: type == t,
                          onTap: () =>
                              setLocal(() => type = type == t ? null : t),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 16),
                  label('العملة'),
                  DropdownButtonFormField<int?>(
                    value: currency,
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
                        (c) => DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(c.code),
                        ),
                      ),
                    ],
                    onChanged: (value) => setLocal(() => currency = value),
                  ),
                  const SizedBox(height: 16),
                  label('الفترة'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final period in const ['اليوم', 'من أمس', 'الكل'])
                        _ChipButton(
                          label: period,
                          icon: Icons.event_rounded,
                          selected: date == period,
                          onTap: () => setLocal(() => date = period),
                        ),
                      _ChipButton(
                        label: specific == null
                            ? 'تاريخ محدد'
                            : DateFormat('MM-dd').format(specific!),
                        icon: Icons.calendar_month_rounded,
                        selected: date == 'تاريخ محدد',
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: specific ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setLocal(() {
                              specific = picked;
                              date = 'تاريخ محدد';
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  label('الحالة'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ChipButton(
                        label: 'كل الحالات',
                        icon: Icons.all_inclusive_rounded,
                        selected: status == null,
                        onTap: () => setLocal(() => status = null),
                      ),
                      for (final s in const ['معلقة', 'مسلمة', 'ملغية'])
                        _ChipButton(
                          label: s,
                          icon: Icons.flag_rounded,
                          count: _statusCounts[s] ?? 0,
                          selected: status == s,
                          onTap: () =>
                              setLocal(() => status = status == s ? null : s),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setLocal(() {
                type = null;
                currency = null;
                date = 'من أمس';
                specific = null;
                status = null;
              }),
              child: const Text('تصفير'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _typeFilter = type;
                  _currencyFilter = currency;
                  _dateFilter = date;
                  _selectedDate = specific;
                  _statusFilter = status;
                  _visibleLimit = 20;
                });
                Navigator.pop(dialogCtx);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
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
