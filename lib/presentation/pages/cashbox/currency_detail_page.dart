import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/cashbox_balance.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';

/// صفحة مستقلة لتفصيل عملة واحدة.
class CurrencyDetailPage extends StatefulWidget {
  final AppDatabase db;
  final Currency currency;
  final String boxType;
  final bool initialShowAfterDelivery;

  const CurrencyDetailPage({
    super.key,
    required this.db,
    required this.currency,
    this.boxType = 'كامل',
    this.initialShowAfterDelivery = false,
  });

  @override
  State<CurrencyDetailPage> createState() => _CurrencyDetailPageState();
}

class _CurrencyDetailPageState extends State<CurrencyDetailPage> {
  bool _loading = true;
  late bool _showAfterDelivery;
  CurrencyCashSummary? _summary;
  Map<double, int> _stock = {};
  List<Transaction> _pending = [];

  @override
  void initState() {
    super.initState();
    _showAfterDelivery = widget.initialShowAfterDelivery;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summaries = await CashboxBalanceCalculator.calculate(
      widget.db,
      boxType: widget.boxType,
    );
    final summary = summaries[widget.currency.id];
    final stock = await CurrencyDenoms.loadStock(widget.currency);
    final pending = await CashboxBalanceCalculator.pendingDeliveriesForCurrency(
      widget.db,
      widget.currency.id,
    );
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _stock = stock;
      _pending = pending;
      _loading = false;
    });
  }

  String get _code => widget.currency.code;
  String get _name => CurrencyDenoms.displayName(widget.currency);

  double get _stockValue {
    var sum = 0.0;
    _stock.forEach((d, c) => sum += d * c);
    return sum;
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final current = _summary?.currentTotal ?? 0;
    final after = _summary?.afterDeliveryTotal ?? 0;
    final displayed = _showAfterDelivery ? after : current;
    final pendingImpact = after - current;
    final stockDiff = current - _stockValue;
    final stockMatched = stockDiff.abs() < 0.01;
    final isNeg = displayed < 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: _name,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: TimaPageBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                      decoration: AppUi.accentPanelDecoration(context),
                      child: Column(
                        children: [
                          Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(AppDims.radiusLg),
                              border: Border.all(
                                color: AppColors.brandGold.withValues(alpha: 0.6),
                                width: 1.6,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _code,
                              style: const TextStyle(
                                color: AppColors.brandGold,
                                fontWeight: FontWeight.w900,
                                fontSize: 24,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.brandIvory,
                              fontWeight: FontWeight.w900,
                              fontSize: 26,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'صندوق: ${widget.boxType}',
                            style: TextStyle(
                              color: AppColors.brandIvory.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TimaPanel(
                      padding: const EdgeInsets.all(10),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            icon: Icon(Icons.account_balance_wallet, size: 18),
                            label: Text('الحالي'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            icon: Icon(Icons.schedule, size: 18),
                            label: Text('بعد التسليم'),
                          ),
                        ],
                        selected: {_showAfterDelivery},
                        onSelectionChanged: (value) {
                          setState(() => _showAfterDelivery = value.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppUi.surface(context),
                        borderRadius: BorderRadius.circular(AppDims.radiusLg),
                        border: Border.all(color: AppUi.border(context)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _showAfterDelivery
                                ? 'الرصيد بعد تسليم المعلقة'
                                : 'الرصيد الحالي في الصندوق',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.neutral500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _fmt(displayed),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: isNeg
                                  ? AppColors.error
                                  : AppColors.brandGreen,
                            ),
                          ),
                          Text(
                            _code,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandGoldDark,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _MiniCompare(
                                  label: 'الحالي',
                                  value: '${_fmt(current)} $_code',
                                  active: !_showAfterDelivery,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _MiniCompare(
                                  label: 'بعد التسليم',
                                  value: '${_fmt(after)} $_code',
                                  active: _showAfterDelivery,
                                ),
                              ),
                            ],
                          ),
                          if (pendingImpact.abs() > 0.009) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppDims.radius),
                              ),
                              child: Text(
                                pendingImpact < 0
                                    ? 'المعلقة ستخصم ${_fmt(pendingImpact.abs())} $_code'
                                    : 'المعلقة ستضيف ${_fmt(pendingImpact)} $_code',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandGoldDark,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TimaSectionTitle(
                      icon: Icons.payments,
                      title: 'الفئات المتوفرة',
                      subtitle: 'عرض فقط — بدون تعديل يدوي',
                      trailing: TimaStatusPill(
                        label: stockMatched ? 'متطابق' : 'فرق جرد',
                        color: stockMatched
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TimaPanel(
                      child: Column(
                        children: [
                          ...CurrencyDenoms.forCurrency(widget.currency).map((
                            denom,
                          ) {
                            final count = _stock[denom] ?? 0;
                            final sub = denom * count;
                            final has = count > 0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: has
                                    ? AppColors.brandGreenSoft.withValues(alpha: 0.55)
                                    : AppColors.neutral500.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(AppDims.radius),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      CurrencyDenoms.fmtDenom(denom),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: has
                                            ? AppColors.brandGreen
                                            : AppColors.neutral500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      has
                                          ? 'متوفر: $count ورقة'
                                          : 'غير متوفر',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: has
                                            ? AppColors.success
                                            : AppColors.slate,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${_fmt(sub)} $_code',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(height: 18),
                          _kv(
                            'إجمالي قيمة الفئات',
                            '${_fmt(_stockValue)} $_code',
                          ),
                          const SizedBox(height: 8),
                          _kv(
                            'الرصيد الدفتري الحالي',
                            '${_fmt(current)} $_code',
                          ),
                          const SizedBox(height: 8),
                          _kv(
                            stockMatched ? 'حالة المطابقة' : 'فرق الجرد',
                            stockMatched ? 'متطابق ✓' : _fmt(stockDiff),
                            valueColor: stockMatched
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const TimaSectionTitle(
                      icon: Icons.pie_chart,
                      title: 'مصادر الرصيد الحالي',
                    ),
                    const SizedBox(height: 10),
                    TimaPanel(
                      child: (_summary?.byTypeCurrent.isEmpty ?? true)
                          ? const Text(
                              'لا توجد حركات مؤثرة على هذه العملة بعد.',
                              style: TextStyle(color: AppColors.neutral500),
                            )
                          : Column(
                              children: _summary!.byTypeCurrent.entries.map((e) {
                                final neg = e.value < 0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        neg
                                            ? Icons.arrow_downward
                                            : Icons.arrow_upward,
                                        size: 18,
                                        color: neg
                                            ? AppColors.error
                                            : AppColors.success,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(e.key)),
                                      Text(
                                        _fmt(e.value),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: neg
                                              ? AppColors.error
                                              : AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(height: 20),
                    TimaSectionTitle(
                      icon: Icons.hourglass_empty,
                      title: 'الحركات المعلقة',
                      subtitle: _pending.isEmpty
                          ? 'لا توجد معلقة على هذه العملة'
                          : '${_pending.length} حركة بانتظار التسليم',
                    ),
                    const SizedBox(height: 10),
                    if (_pending.isEmpty)
                      const TimaPanel(
                        child: Text(
                          'لا توجد حركات تسليم معلقة مرتبطة بهذه العملة.',
                          style: TextStyle(color: AppColors.neutral500),
                        ),
                      )
                    else
                      ..._pending.map((tx) {
                        final isMain = tx.currencyId == widget.currency.id;
                        final amount =
                            isMain ? tx.amount : (tx.targetAmount ?? 0);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: AppUi.panelDecoration(context),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.warning.withValues(alpha: 0.15),
                              child: const Icon(
                                Icons.outbox,
                                color: AppColors.warning,
                              ),
                            ),
                            title: Text(
                              tx.beneficiary ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              isMain ? 'مبلغ رئيسي' : 'مبلغ فرعي',
                            ),
                            trailing: Text(
                              '-${_fmt(amount)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: AppColors.neutral500, fontSize: 13)),
        Text(
          v,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: valueColor,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _MiniCompare extends StatelessWidget {
  final String label;
  final String value;
  final bool active;

  const _MiniCompare({
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? AppColors.brandGreen.withValues(alpha: 0.1)
            : AppColors.neutral500.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppDims.radius),
        border: Border.all(
          color: active
              ? AppColors.brandGreen.withValues(alpha: 0.25)
              : AppColors.neutral500.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.brandGreen : AppColors.neutral500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: active ? AppColors.brandGreen : AppColors.neutral600,
            ),
          ),
        ],
      ),
    );
  }
}
