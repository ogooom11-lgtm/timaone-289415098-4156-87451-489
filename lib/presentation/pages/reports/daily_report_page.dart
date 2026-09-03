import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';

/// صفحة تفاصيل اليوم — إحصائيات كاملة بالعدد والمبالغ حسب العملة.
class DailyReportPage extends StatefulWidget {
  final AppDatabase db;

  const DailyReportPage({super.key, required this.db});

  @override
  State<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends State<DailyReportPage> {
  DateTime _date = DateTime.now();
  List<Transaction> _transactions = [];
  Map<int, Currency> _currencies = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final transactions = await widget.db.getAllTransactions();
    final currencies = await widget.db.getAllCurrencies();
    if (!mounted) return;
    setState(() {
      _transactions = transactions;
      _currencies = {for (final c in currencies) c.id: c};
      _loading = false;
    });
  }

  String _formatArabicDate(DateTime date) {
    final ymd = DateFormat('yyyy-MM-dd').format(date);
    final weekdayEng = DateFormat('EEEE').format(date);
    const weekdaysAr = {
      'Monday': 'الاثنين',
      'Tuesday': 'الثلاثاء',
      'Wednesday': 'الأربعاء',
      'Thursday': 'الخميس',
      'Friday': 'الجمعة',
      'Saturday': 'السبت',
      'Sunday': 'الأحد',
    };
    return '$ymd (${weekdaysAr[weekdayEng] ?? weekdayEng})';
  }

  bool _isSameDay(DateTime d) {
    final local = d.toLocal();
    return local.year == _date.year &&
        local.month == _date.month &&
        local.day == _date.day;
  }

  bool _isCancelled(Transaction t) =>
      t.movementState == 'ملغية' ||
      t.status == 'الغاء' ||
      t.status == 'ملغية';

  bool _isDelivery(String type) =>
      type == 'حركة تسليم' ||
      (type.contains('تسليم') && !type.contains('يوزر'));

  bool _isUser(String type) => type == 'حركة يوزر' || type.contains('يوزر');

  bool _isReceive(String type) =>
      type == 'حركة استلام' || type.contains('استلام');

  bool _isSent(String type) => type == 'حركة مرسلة' || type.contains('مرسلة');

  bool _isExchange(String type) =>
      type == 'حركة تسوية' || type.contains('صرف') || type.contains('تسوية');

  String _codeOf(int? id) {
    if (id == null) return '—';
    return _currencies[id]?.code ?? id.toString();
  }

  List<Transaction> get _dayTransactions =>
      _transactions.where((t) => _isSameDay(t.createdAt)).toList();

  /// كل المعلقة الحالية (ليست فقط اليوم)
  List<Transaction> get _pendingAll => _transactions.where((t) {
        return _isDelivery(t.type) &&
            t.status == 'مضافة' &&
            t.movementState == 'مفعلة';
      }).toList();

  _DayTotals _buildTotals(List<Transaction> dayTxs) {
    final totals = _DayTotals();

    void addAmount(Map<String, double> map, int? currencyId, double? amount) {
      if (currencyId == null || amount == null) return;
      final code = _codeOf(currencyId);
      map[code] = (map[code] ?? 0) + amount.abs();
    }

    for (final t in dayTxs) {
      totals.addedCount++;
      addAmount(totals.addedByCurrency, t.currencyId, t.amount);
      if (t.targetAmount != null && t.targetCurrencyId != null) {
        addAmount(totals.addedByCurrency, t.targetCurrencyId, t.targetAmount);
      }

      if (_isCancelled(t)) {
        totals.cancelledCount++;
        addAmount(totals.cancelledByCurrency, t.currencyId, t.amount);
        if (t.targetAmount != null && t.targetCurrencyId != null) {
          addAmount(
            totals.cancelledByCurrency,
            t.targetCurrencyId,
            t.targetAmount,
          );
        }
        continue;
      }

      final type = t.type;

      if (_isDelivery(type)) {
        totals.deliveryCount++;
        addAmount(totals.deliveryByCurrency, t.currencyId, t.amount);
        if (t.targetAmount != null && t.targetCurrencyId != null) {
          addAmount(
            totals.deliveryByCurrency,
            t.targetCurrencyId,
            t.targetAmount,
          );
        }
        if (t.status == 'تم التسليم') {
          totals.deliveredDoneCount++;
          addAmount(totals.deliveredDoneByCurrency, t.currencyId, t.amount);
          if (t.targetAmount != null && t.targetCurrencyId != null) {
            addAmount(
              totals.deliveredDoneByCurrency,
              t.targetCurrencyId,
              t.targetAmount,
            );
          }
        }
      } else if (_isUser(type)) {
        // يوزر = تسليم مكتمل فوراً
        totals.deliveryCount++;
        totals.deliveredDoneCount++;
        addAmount(totals.deliveryByCurrency, t.currencyId, t.amount);
        addAmount(totals.deliveredDoneByCurrency, t.currencyId, t.amount);
        if (t.targetAmount != null && t.targetCurrencyId != null) {
          addAmount(
            totals.deliveryByCurrency,
            t.targetCurrencyId,
            t.targetAmount,
          );
          addAmount(
            totals.deliveredDoneByCurrency,
            t.targetCurrencyId,
            t.targetAmount,
          );
        }
      } else if (_isReceive(type)) {
        totals.receiveCount++;
        addAmount(totals.receiveByCurrency, t.currencyId, t.amount);
        if (t.targetAmount != null && t.targetCurrencyId != null) {
          addAmount(
            totals.receiveByCurrency,
            t.targetCurrencyId,
            t.targetAmount,
          );
        }
      } else if (_isSent(type)) {
        totals.sentCount++;
        // المستلم من العميل
        addAmount(totals.sentInByCurrency, t.currencyId, t.amount);
        // المرسل
        if (t.targetAmount != null && t.targetCurrencyId != null) {
          addAmount(totals.sentOutByCurrency, t.targetCurrencyId, t.targetAmount);
        }
        if (t.fees != null && t.feesCurrencyId != null) {
          addAmount(totals.feesByCurrency, t.feesCurrencyId, t.fees);
        }
      } else if (_isExchange(type)) {
        totals.exchangeCount++;
        addAmount(totals.exchangeOutByCurrency, t.currencyId, t.amount);
        if (t.targetAmount != null && t.targetCurrencyId != null) {
          addAmount(
            totals.exchangeInByCurrency,
            t.targetCurrencyId,
            t.targetAmount,
          );
        }
      }
    }

    // معلقة (كل الأوقات)
    for (final t in _pendingAll) {
      totals.pendingCount++;
      addAmount(totals.pendingByCurrency, t.currencyId, t.amount);
      if (t.targetAmount != null && t.targetCurrencyId != null) {
        addAmount(totals.pendingByCurrency, t.targetCurrencyId, t.targetAmount);
      }
    }

    return totals;
  }

  void _changeDay(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  String _amountsText(Map<String, double> map) {
    if (map.isEmpty) return '—';
    final keys = map.keys.toList()..sort();
    return keys.map((c) => '${_fmt(map[c]!)} $c').join('  •  ');
  }

  Future<void> _copyReport(_DayTotals totals) async {
    final buffer = StringBuffer()
      ..writeln('📊 تفاصيل اليوم: ${_formatArabicDate(_date)}')
      ..writeln('---------------------------------------')
      ..writeln('إجمالي الحركات المضافة: ${totals.addedCount}')
      ..writeln('  ${_amountsText(totals.addedByCurrency)}')
      ..writeln('تسليم: ${totals.deliveryCount}')
      ..writeln('  ${_amountsText(totals.deliveryByCurrency)}')
      ..writeln('استلام: ${totals.receiveCount}')
      ..writeln('  ${_amountsText(totals.receiveByCurrency)}')
      ..writeln('مرسلة: ${totals.sentCount}')
      ..writeln('  وارد: ${_amountsText(totals.sentInByCurrency)}')
      ..writeln('  صادر: ${_amountsText(totals.sentOutByCurrency)}')
      ..writeln('صرف: ${totals.exchangeCount}')
      ..writeln('  خارج: ${_amountsText(totals.exchangeOutByCurrency)}')
      ..writeln('  داخل: ${_amountsText(totals.exchangeInByCurrency)}')
      ..writeln('تم تسليمها: ${totals.deliveredDoneCount}')
      ..writeln('  ${_amountsText(totals.deliveredDoneByCurrency)}')
      ..writeln('إلغاء: ${totals.cancelledCount}')
      ..writeln('  ${_amountsText(totals.cancelledByCurrency)}')
      ..writeln('معلقة حالياً: ${totals.pendingCount}')
      ..writeln('  ${_amountsText(totals.pendingByCurrency)}');

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ تقرير اليوم')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayTxs = _dayTransactions;
    final totals = _buildTotals(dayTxs);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: 'تفاصيل اليوم',
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'نسخ التقرير',
            onPressed: () => _copyReport(totals),
            icon: const Icon(Icons.copy_all),
          ),
        ],
      ),
      body: TimaPageBackground(
        child: _loading
            ? const TimaLoader(message: 'جارٍ تجهيز التقرير…')
            : RefreshIndicator(
                onRefresh: _load,
                child: Scrollbar(
                  child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppDims.pagePadding,
                    14,
                    AppDims.pagePadding,
                    28,
                  ),
                  children: [
                    TimaContentWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    // شريط اختيار اليوم
                    TimaPanel(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'اليوم السابق',
                            onPressed: () => _changeDay(-1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              borderRadius:
                                  BorderRadius.circular(AppDims.radiusSm),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.calendar_month_rounded,
                                      color: AppUi.accent(context),
                                      size: 17,
                                    ),
                                    const SizedBox(width: 9),
                                    Text(
                                      _formatArabicDate(_date),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppUi.textPrimary(context),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'اليوم التالي',
                            onPressed: () => _changeDay(1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    const TimaSectionTitle(
                      icon: Icons.today,
                      title: 'ملخص حركات اليوم',
                      subtitle: 'العدد + مجموع المبالغ حسب العملة',
                    ),
                    const SizedBox(height: 10),

                    _SummaryCard(
                      icon: Icons.add_circle_outline,
                      color: AppColors.brandGreen,
                      title: 'إجمالي الحركات المضافة',
                      count: totals.addedCount,
                      amounts: totals.addedByCurrency,
                      fmt: _fmt,
                    ),
                    const SizedBox(height: 8),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.05,
                      children: [
                        _TypeCard(
                          title: 'تسليم',
                          icon: Icons.outbox,
                          color: AppColors.warning,
                          count: totals.deliveryCount,
                          amounts: totals.deliveryByCurrency,
                          fmt: _fmt,
                        ),
                        _TypeCard(
                          title: 'استلام',
                          icon: Icons.move_to_inbox,
                          color: AppColors.success,
                          count: totals.receiveCount,
                          amounts: totals.receiveByCurrency,
                          fmt: _fmt,
                        ),
                        _TypeCard(
                          title: 'مرسلة',
                          icon: Icons.send,
                          color: AppColors.info,
                          count: totals.sentCount,
                          amounts: totals.sentInByCurrency,
                          secondaryLabel: 'صادر',
                          secondaryAmounts: totals.sentOutByCurrency,
                          fmt: _fmt,
                        ),
                        _TypeCard(
                          title: 'صرف',
                          icon: Icons.currency_exchange,
                          color: AppColors.violet,
                          count: totals.exchangeCount,
                          amounts: totals.exchangeOutByCurrency,
                          secondaryLabel: 'داخل',
                          secondaryAmounts: totals.exchangeInByCurrency,
                          fmt: _fmt,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _TypeCard(
                            title: 'تم تسليمها',
                            icon: Icons.check_circle_outline,
                            color: AppColors.success,
                            count: totals.deliveredDoneCount,
                            amounts: totals.deliveredDoneByCurrency,
                            fmt: _fmt,
                            tall: false,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TypeCard(
                            title: 'إلغاء',
                            icon: Icons.cancel_outlined,
                            color: AppColors.error,
                            count: totals.cancelledCount,
                            amounts: totals.cancelledByCurrency,
                            fmt: _fmt,
                            tall: false,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    TimaSectionTitle(
                      icon: Icons.hourglass_empty,
                      title: 'الحركات المعلقة حالياً',
                      subtitle: totals.pendingCount == 0
                          ? 'لا توجد معلقة'
                          : '${totals.pendingCount} حركة بانتظار التسليم',
                    ),
                    const SizedBox(height: 10),
                    _SummaryCard(
                      icon: Icons.hourglass_empty,
                      color: AppColors.brandGoldDark,
                      title: 'مجموع المعلقة حسب العملة',
                      count: totals.pendingCount,
                      amounts: totals.pendingByCurrency,
                      fmt: _fmt,
                    ),
                    if (totals.pendingByCurrency.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      TimaPanel(
                        child: Column(
                          children: totals.pendingByCurrency.entries.map((e) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.brandGold.withValues(alpha: 
                                        0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(AppDims.radiusSm),
                                    ),
                                    child: Text(
                                      e.key,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        color: AppColors.brandGoldDark,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'مبالغ معلقة',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _fmt(e.value),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.warning,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    // تفصيل المبالغ لكل عملة في اليوم
                    const SizedBox(height: 20),
                    const TimaSectionTitle(
                      icon: Icons.account_balance_wallet,
                      title: 'تفصيل المبالغ حسب العملة',
                      subtitle: 'ملخص سريع لكل عملة ظهرت اليوم',
                    ),
                    const SizedBox(height: 10),
                    ..._currencyBreakdownCards(totals),

                    const SizedBox(height: 20),
                    TimaSectionTitle(
                      icon: Icons.receipt_long,
                      title: 'سجل حركات اليوم',
                      subtitle: dayTxs.isEmpty
                          ? 'لا توجد حركات'
                          : '${dayTxs.length} حركة',
                    ),
                    const SizedBox(height: 10),
                    if (dayTxs.isEmpty)
                      const TimaPanel(
                        child: Text(
                          'لا توجد حركات مسجّلة في هذا اليوم.',
                          style: TextStyle(color: AppColors.neutral500),
                        ),
                      )
                    else
                      ...dayTxs.map(_txTile),
                        ],
                      ),
                    ),
                  ],
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _currencyBreakdownCards(_DayTotals totals) {
    final codes = <String>{
      ...totals.addedByCurrency.keys,
      ...totals.deliveryByCurrency.keys,
      ...totals.receiveByCurrency.keys,
      ...totals.sentInByCurrency.keys,
      ...totals.sentOutByCurrency.keys,
      ...totals.exchangeInByCurrency.keys,
      ...totals.exchangeOutByCurrency.keys,
      ...totals.deliveredDoneByCurrency.keys,
      ...totals.cancelledByCurrency.keys,
      ...totals.pendingByCurrency.keys,
    }.toList()
      ..sort();

    if (codes.isEmpty) {
      return [
        const TimaPanel(
          child: Text(
            'لا توجد مبالغ لهذا اليوم.',
            style: TextStyle(color: AppColors.neutral500),
          ),
        ),
      ];
    }

    return codes.map((code) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: AppUi.panelDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppDims.radiusSm),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.brandGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (_) {
                    final match = _currencies.values.where((c) => c.code == code);
                    final label = match.isEmpty
                        ? code
                        : CurrencyDenoms.displayName(match.first);
                    return Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            _line('تسليم', totals.deliveryByCurrency[code]),
            _line('استلام', totals.receiveByCurrency[code]),
            _line('مرسلة وارد', totals.sentInByCurrency[code]),
            _line('مرسلة صادر', totals.sentOutByCurrency[code]),
            _line('صرف خارج', totals.exchangeOutByCurrency[code]),
            _line('صرف داخل', totals.exchangeInByCurrency[code]),
            _line('تم تسليمها', totals.deliveredDoneByCurrency[code]),
            _line('إلغاء', totals.cancelledByCurrency[code]),
            _line('معلقة', totals.pendingByCurrency[code]),
          ],
        ),
      );
    }).toList();
  }

  Widget _line(String label, double? value) {
    if (value == null || value.abs() < 0.0001) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.neutral600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            _fmt(value),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _txTile(Transaction tx) {
    final canceled = _isCancelled(tx);
    Color color = AppColors.slate;
    IconData icon = Icons.receipt_long;
    if (_isDelivery(tx.type) || _isUser(tx.type)) {
      color = AppColors.warning;
      icon = Icons.outbox;
    } else if (_isReceive(tx.type)) {
      color = AppColors.success;
      icon = Icons.move_to_inbox;
    } else if (_isSent(tx.type)) {
      color = AppColors.info;
      icon = Icons.send;
    } else if (_isExchange(tx.type)) {
      color = AppColors.violet;
      icon = Icons.currency_exchange;
    }
    if (canceled) {
      color = AppColors.error;
      icon = Icons.cancel;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppUi.panelDecoration(context),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(
          tx.beneficiary ?? tx.type,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        subtitle: Text(
          '${tx.type} • ${DateFormat('HH:mm').format(tx.createdAt.toLocal())} • ${tx.status}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Text(
          '${_fmt(tx.amount)} ${_codeOf(tx.currencyId)}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: canceled ? AppColors.error : null,
          ),
        ),
      ),
    );
  }
}

class _DayTotals {
  int addedCount = 0;
  final Map<String, double> addedByCurrency = {};

  int deliveryCount = 0;
  final Map<String, double> deliveryByCurrency = {};

  int receiveCount = 0;
  final Map<String, double> receiveByCurrency = {};

  int sentCount = 0;
  final Map<String, double> sentInByCurrency = {};
  final Map<String, double> sentOutByCurrency = {};
  final Map<String, double> feesByCurrency = {};

  int exchangeCount = 0;
  final Map<String, double> exchangeInByCurrency = {};
  final Map<String, double> exchangeOutByCurrency = {};

  int deliveredDoneCount = 0;
  final Map<String, double> deliveredDoneByCurrency = {};

  int cancelledCount = 0;
  final Map<String, double> cancelledByCurrency = {};

  int pendingCount = 0;
  final Map<String, double> pendingByCurrency = {};
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final int count;
  final Map<String, double> amounts;
  final String Function(double) fmt;

  const _SummaryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.count,
    required this.amounts,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final amountText = amounts.isEmpty
        ? '—'
        : (amounts.keys.toList()..sort())
            .map((c) => '${fmt(amounts[c]!)} $c')
            .join('  •  ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppUi.panelDecoration(context),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDims.radius),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count حركة',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.neutral500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  amountText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
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

class _TypeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final Map<String, double> amounts;
  final Map<String, double>? secondaryAmounts;
  final String? secondaryLabel;
  final String Function(double) fmt;
  final bool tall;

  const _TypeCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.amounts,
    required this.fmt,
    this.secondaryAmounts,
    this.secondaryLabel,
    this.tall = true,
  });

  String _mapText(Map<String, double> map) {
    if (map.isEmpty) return '—';
    return (map.keys.toList()..sort())
        .map((c) => '${fmt(map[c]!)} $c')
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppUi.surface(context),
        borderRadius: BorderRadius.circular(AppDims.radiusLg),
        border: Border.all(color: AppUi.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDims.radiusSm),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _mapText(amounts),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.neutral600,
              height: 1.25,
            ),
          ),
          if (secondaryAmounts != null && secondaryAmounts!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${secondaryLabel ?? 'إضافي'}:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.neutral500,
              ),
            ),
            Text(
              _mapText(secondaryAmounts!),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.neutral600,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
