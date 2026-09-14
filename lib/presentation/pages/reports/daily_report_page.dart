import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';

/// صفحة تفاصيل اليوم — تصميم عصري: مؤشرات رئيسية أنيقة، تفصيل حسب العملة،
/// وبطاقات حركات قابلة للتوسّع لعرض تفصيل كل حركة.
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

  // ---------- منطق البيانات (مثبت ومجرَّب) ----------

  String _formatArabicDate(DateTime date) {
    final ymd = DateFormat('yyyy/MM/dd').format(date);
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

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    final local = d.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
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
        addAmount(totals.sentInByCurrency, t.currencyId, t.amount);
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

    for (final t in _pendingAll) {
      totals.pendingCount++;
      addAmount(totals.pendingByCurrency, t.currencyId, t.amount);
      if (t.targetAmount != null && t.targetCurrencyId != null) {
        addAmount(totals.pendingByCurrency, t.targetCurrencyId, t.targetAmount);
      }
    }

    return totals;
  }

  void _changeDay(int days) =>
      setState(() => _date = _date.add(Duration(days: days)));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  // ---------- تنسيق ----------

  String _fmt(double v) {
    final abs = v.abs();
    final text = abs == abs.roundToDouble()
        ? abs.toStringAsFixed(0)
        : abs.toStringAsFixed(2);
    final parts = text.split('.');
    final buf = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
      buf.write(parts[0][i]);
    }
    final out = parts.length > 1 ? '${buf.toString()}.${parts[1]}' : buf.toString();
    return v < 0 ? '−$out' : out;
  }

  String _amountsText(Map<String, double> map) {
    if (map.isEmpty) return '—';
    return (map.keys.toList()..sort())
        .map((c) => '${_fmt(map[c]!)} $c')
        .join('  •  ');
  }

  String _inOut(Map<String, double> a, Map<String, double> b, String la, String lb) {
    final parts = <String>[];
    if (a.isNotEmpty) parts.add('$la: ${_amountsText(a)}');
    if (b.isNotEmpty) parts.add('$lb: ${_amountsText(b)}');
    return parts.isEmpty ? '—' : parts.join('\n');
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
      const SnackBar(
        content: Text('تم نسخ تقرير اليوم'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------- الواجهة ----------

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
            tooltip: 'نسخ التقرير',
            onPressed: () => _copyReport(totals),
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
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
                            _DateNav(
                              label: _formatArabicDate(_date),
                              isToday: _isToday(_date),
                              count: dayTxs.length,
                              onPrev: () => _changeDay(-1),
                              onNext: () => _changeDay(1),
                              onPick: _pickDate,
                            ),
                            const SizedBox(height: 16),

                            // المؤشرات الرئيسية.
                            const TimaSectionTitle(
                              icon: Icons.insights_rounded,
                              title: 'مؤشرات اليوم',
                              subtitle: 'العدد ومجموع المبالغ حسب العملة',
                            ),
                            const SizedBox(height: 10),
                            _buildKpis(totals),

                            // تفصيل حسب العملة.
                            const SizedBox(height: 22),
                            const TimaSectionTitle(
                              icon: Icons.account_balance_wallet_rounded,
                              title: 'تفصيل المبالغ حسب العملة',
                              subtitle: 'ملخّص لكل عملة ظهرت اليوم',
                            ),
                            const SizedBox(height: 10),
                            ..._currencyBreakdown(totals),

                            // حركات اليوم (قابلة للتوسّع).
                            const SizedBox(height: 22),
                            TimaSectionTitle(
                              icon: Icons.receipt_long_rounded,
                              title: 'حركات اليوم',
                              subtitle: dayTxs.isEmpty
                                  ? 'لا توجد حركات'
                                  : '${dayTxs.length} حركة — اضغط لعرض التفصيل',
                            ),
                            const SizedBox(height: 10),
                            if (dayTxs.isEmpty)
                              const TimaPanel(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.event_busy_rounded,
                                      color: AppColors.neutral400,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'لا توجد حركات مسجّلة في هذا اليوم.',
                                      style:
                                          TextStyle(color: AppColors.neutral500),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ...dayTxs.asMap().entries.map(
                                    (e) => _Staggered(
                                      index: e.key,
                                      child: _TxCard(
                                        tx: e.value,
                                        code: _codeOf(e.value.currencyId),
                                        targetCode:
                                            _codeOf(e.value.targetCurrencyId),
                                        feesCode: _codeOf(e.value.feesCurrencyId),
                                        canceled: _isCancelled(e.value),
                                        fmt: _fmt,
                                      ),
                                    ),
                                  ),
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

  Widget _buildKpis(_DayTotals t) {
    final kpis = <_Kpi>[
      _Kpi(Icons.add_circle_outline, AppColors.brandGreen, 'إجمالي المضافة',
          t.addedCount, _amountsText(t.addedByCurrency)),
      _Kpi(Icons.outbox_rounded, AppColors.warning, 'تسليم',
          t.deliveryCount, _amountsText(t.deliveryByCurrency)),
      _Kpi(Icons.move_to_inbox_rounded, AppColors.success, 'استلام',
          t.receiveCount, _amountsText(t.receiveByCurrency)),
      _Kpi(Icons.send_rounded, AppColors.info, 'مرسلة', t.sentCount,
          _inOut(t.sentInByCurrency, t.sentOutByCurrency, 'وارد', 'صادر')),
      _Kpi(Icons.currency_exchange_rounded, AppColors.violet, 'صرف',
          t.exchangeCount,
          _inOut(t.exchangeOutByCurrency, t.exchangeInByCurrency, 'خارج', 'داخل')),
      _Kpi(Icons.check_circle_outline_rounded, AppColors.success, 'تم التسليم',
          t.deliveredDoneCount, _amountsText(t.deliveredDoneByCurrency)),
      _Kpi(Icons.cancel_outlined, AppColors.error, 'إلغاء',
          t.cancelledCount, _amountsText(t.cancelledByCurrency)),
      _Kpi(Icons.hourglass_empty_rounded, AppColors.brandGoldDark, 'معلقة',
          t.pendingCount, _amountsText(t.pendingByCurrency)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1100
            ? 4
            : w >= 780
                ? 3
                : w >= 460
                    ? 2
                    : 1;
        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 128,
          ),
          children: kpis.map((k) => _StatTile(kpi: k)).toList(),
        );
      },
    );
  }

  List<Widget> _currencyBreakdown(_DayTotals totals) {
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
      return const [
        TimaPanel(
          child: Text(
            'لا توجد مبالغ لهذا اليوم.',
            style: TextStyle(color: AppColors.neutral500),
          ),
        ),
      ];
    }

    return codes
        .map(
          (code) => _CurrencyCard(
            code: code,
            name: (() {
              final match =
                  _currencies.values.where((c) => c.code == code);
              return match.isEmpty ? code : CurrencyDenoms.displayName(match.first);
            })(),
            rows: [
              _BLine('تسليم', totals.deliveryByCurrency[code], AppColors.warning),
              _BLine('استلام', totals.receiveByCurrency[code], AppColors.success),
              _BLine('مرسلة وارد', totals.sentInByCurrency[code], AppColors.info),
              _BLine('مرسلة صادر', totals.sentOutByCurrency[code], AppColors.info),
              _BLine('صرف خارج', totals.exchangeOutByCurrency[code], AppColors.violet),
              _BLine('صرف داخل', totals.exchangeInByCurrency[code], AppColors.violet),
              _BLine('تم تسليمها', totals.deliveredDoneByCurrency[code], AppColors.success),
              _BLine('إلغاء', totals.cancelledByCurrency[code], AppColors.error),
              _BLine('معلقة', totals.pendingByCurrency[code], AppColors.warning),
            ].where((r) => r.value != null && r.value!.abs() > 0.0001).toList(),
            fmt: _fmt,
          ),
        )
        .toList();
  }
}

// ---------- نماذج مساعدة ----------

class _Kpi {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final String amounts;
  const _Kpi(this.icon, this.color, this.label, this.count, this.amounts);
}

class _BLine {
  final String label;
  final double? value;
  final Color color;
  const _BLine(this.label, this.value, this.color);
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

// ---------- شريط التاريخ ----------

class _DateNav extends StatelessWidget {
  final String label;
  final bool isToday;
  final int count;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  const _DateNav({
    required this.label,
    required this.isToday,
    required this.count,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppUi.surface(context),
        borderRadius: BorderRadius.circular(AppDims.radiusLg),
        border: Border.all(color: AppUi.border(context)),
        boxShadow: AppUi.softShadow(context),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'اليوم السابق',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          Expanded(
            child: InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_rounded, color: accent, size: 18),
                    const SizedBox(width: 9),
                    Text(
                      label,
                      style: TextStyle(
                        color: AppUi.textPrimary(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 9),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppUi.tone(context, AppColors.success)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'اليوم',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppUi.tone(context, AppColors.success),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppUi.sunken(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count حركة',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppUi.textSecondary(context),
              ),
            ),
          ),
          IconButton(
            tooltip: 'اليوم التالي',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    );
  }
}

// ---------- بطاقة مؤشر ----------

class _StatTile extends StatelessWidget {
  final _Kpi kpi;
  const _StatTile({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final color = AppUi.tone(context, kpi.color);
    return Container(
      padding: const EdgeInsets.all(14),
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
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDims.radiusSm),
                ),
                child: Icon(kpi.icon, size: 18, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  kpi.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: AppUi.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '${kpi.count}',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            kpi.amounts,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppUi.textSecondary(context),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- بطاقة تفصيل عملة ----------

class _CurrencyCard extends StatelessWidget {
  final String code;
  final String name;
  final List<_BLine> rows;
  final String Function(double) fmt;

  const _CurrencyCard({
    required this.code,
    required this.name,
    required this.rows,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppUi.panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: AppColors.brandGradient,
                  ),
                  borderRadius: BorderRadius.circular(AppDims.radiusSm),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppUi.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'لا مبالغ مفصّلة',
              style: TextStyle(fontSize: 12, color: AppUi.textSecondary(context)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: rows
                  .map(
                    (r) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppUi.tone(context, r.color)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppDims.radiusSm),
                        border: Border.all(
                          color: AppUi.tone(context, r.color)
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            r.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppUi.textSecondary(context),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            fmt(r.value!),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppUi.tone(context, r.color),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// ---------- بطاقة حركة قابلة للتوسّع ----------

class _TxCard extends StatefulWidget {
  final Transaction tx;
  final String code;
  final String targetCode;
  final String feesCode;
  final bool canceled;
  final String Function(double) fmt;

  const _TxCard({
    required this.tx,
    required this.code,
    required this.targetCode,
    required this.feesCode,
    required this.canceled,
    required this.fmt,
  });

  @override
  State<_TxCard> createState() => _TxCardState();
}

class _TxCardState extends State<_TxCard> {
  bool _expanded = false;
  bool _hover = false;

  ({Color color, IconData icon, String label}) get _visual {
    if (widget.canceled) {
      return (
        color: AppColors.error,
        icon: Icons.cancel_rounded,
        label: 'ملغية',
      );
    }
    final type = widget.tx.type;
    if (type.contains('يوزر')) {
      return (color: AppColors.violet, icon: Icons.person_rounded, label: 'يوزر');
    }
    if (type.contains('تسليم')) {
      return (color: AppColors.warning, icon: Icons.outbox_rounded, label: 'تسليم');
    }
    if (type.contains('استلام')) {
      return (
        color: AppColors.success,
        icon: Icons.move_to_inbox_rounded,
        label: 'استلام',
      );
    }
    if (type.contains('مرسلة')) {
      return (color: AppColors.info, icon: Icons.send_rounded, label: 'مرسلة');
    }
    if (type.contains('تسوية') || type.contains('صرف')) {
      return (
        color: AppColors.teal,
        icon: Icons.currency_exchange_rounded,
        label: 'تسوية',
      );
    }
    return (
      color: AppColors.slate,
      icon: Icons.receipt_long_rounded,
      label: 'حركة',
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual;
    final accent = AppUi.tone(context, v.color);
    final dt = widget.tx.createdAt.toLocal();
    final amount =
        '${widget.fmt(widget.tx.amount)} ${widget.code}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppUi.surface(context),
            borderRadius: BorderRadius.circular(AppDims.radius),
            border: Border.all(
              color: _hover
                  ? accent.withValues(alpha: 0.45)
                  : AppUi.border(context),
            ),
            boxShadow: _hover ? AppUi.raisedShadow(context) : AppUi.softShadow(context),
          ),
          child: Column(
            children: [
              // الرأس.
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(v.icon, color: accent, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.tx.beneficiary?.trim().isNotEmpty == true
                                ? widget.tx.beneficiary!.trim()
                                : v.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppUi.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${v.label} • ${DateFormat('HH:mm').format(dt)} • ${widget.tx.status}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppUi.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      amount,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: widget.canceled
                            ? AppUi.tone(context, AppColors.error)
                            : accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppUi.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),

              // التفاصيل.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: AlignmentDirectional.topCenter,
                child: _expanded ? _details(context) : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    final tx = widget.tx;
    final facts = <(String, String, IconData?, bool)>[
      ('التاريخ', DateFormat('yyyy/MM/dd  HH:mm').format(tx.createdAt.toLocal()),
          Icons.schedule_rounded, false),
      ('النوع', tx.type, Icons.category_rounded, false),
      ('المبلغ', '${widget.fmt(tx.amount)} ${widget.code}',
          Icons.payments_rounded, true),
    ];
    if (tx.targetAmount != null && tx.targetAmount! != 0) {
      facts.add((
        'المبلغ الثاني',
        '${widget.fmt(tx.targetAmount!)} ${widget.targetCode}',
        Icons.swap_horiz_rounded,
        true,
      ));
    }
    if (tx.fees != null && tx.fees! != 0) {
      facts.add((
        'الأجور',
        '${widget.fmt(tx.fees!)} ${widget.feesCode}',
        Icons.account_balance_wallet_rounded,
        false,
      ));
    }
    if (tx.exchangeRate != null && tx.exchangeRate! > 0) {
      facts.add(('السعر', widget.fmt(tx.exchangeRate!), Icons.show_chart_rounded, false));
    }
    facts.add(('الحالة', tx.status, Icons.flag_rounded, false));
    facts.add((
      'وضع الحركة',
      tx.movementState,
      widget.canceled ? Icons.cancel_rounded : Icons.verified_rounded,
      false,
    ));
    facts.add((
      'سجّلها',
      tx.createdByName.isEmpty ? '—' : tx.createdByName,
      Icons.person_rounded,
      false,
    ));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppUi.border(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: facts
                .map(
                  (f) => SizedBox(
                    width: 240,
                    child: TimaKeyValue(
                      label: f.$1,
                      value: f.$2,
                      icon: f.$3,
                      emphasized: f.$4,
                    ),
                  ),
                )
                .toList(),
          ),
          if (tx.note?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppUi.sunken(context),
                borderRadius: BorderRadius.circular(AppDims.radiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 15, color: AppUi.textSecondary(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tx.note!.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppUi.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------- ظهور متدرّج ----------

class _Staggered extends StatefulWidget {
  final Widget child;
  final int index;
  const _Staggered({required this.child, this.index = 0});

  @override
  State<_Staggered> createState() => _StaggeredState();
}

class _StaggeredState extends State<_Staggered>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 40 * widget.index.clamp(0, 12)), _c.forward);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
