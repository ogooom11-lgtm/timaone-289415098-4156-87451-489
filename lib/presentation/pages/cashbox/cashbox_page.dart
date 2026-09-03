import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/cashbox_balance.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';

/// شاشة الصناديق — بطاقات العملات مع تبديل بين الرصيد الحالي
/// والرصيد المتوقع بعد تنفيذ الحركات المعلّقة.
class CashboxPage extends StatefulWidget {
  final AppDatabase db;

  const CashboxPage({super.key, required this.db});

  @override
  State<CashboxPage> createState() => _CashboxPageState();
}

class _CashboxPageState extends State<CashboxPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// false = الرصيد الحالي | true = بعد تسليم المعلقة
  bool _showAfterDelivery = false;
  int _refreshToken = 0;

  static const _boxes = ['كامل', 'حركات', 'صرف'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _boxes.length, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _refreshToken++);

  Future<void> _openCurrencyDetail(Currency currency, String boxType) async {
    await Navigator.of(context).pushNamed(
      '/currency_detail',
      arguments: {
        'currency': currency,
        'boxType': boxType,
        'showAfterDelivery': _showAfterDelivery,
      },
    );
    if (mounted) _refresh();
  }

  String get _modeLabel =>
      _showAfterDelivery ? 'بعد التسليم' : 'الرصيد الحالي';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: 'الصناديق والأرصدة',
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: TimaPageBackground(
        child: Column(
          children: [
            // ---- شريط التحكم ----
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.pagePadding,
                14,
                AppDims.pagePadding,
                0,
              ),
              child: TimaContentWidth(
                child: TimaPanel(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            icon: Icon(Icons.account_balance_wallet_outlined),
                            label: Text('الرصيد الحالي'),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            icon: Icon(Icons.schedule_rounded),
                            label: Text('بعد التسليم'),
                          ),
                        ],
                        selected: {_showAfterDelivery},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) =>
                            setState(() => _showAfterDelivery = value.first),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showAfterDelivery
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 15,
                            color: AppUi.textSecondary(context),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            _showAfterDelivery
                                ? 'الرصيد المتوقع بعد تنفيذ كل الحركات المعلّقة'
                                : 'الرصيد الفعلي الموجود في الصندوق الآن',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ---- تبويبات نوع الصندوق ----
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.pagePadding,
                14,
                AppDims.pagePadding,
                0,
              ),
              child: TimaContentWidth(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppUi.sunken(context),
                      borderRadius: BorderRadius.circular(AppDims.radiusSm),
                      border: Border.all(color: AppUi.border(context)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _boxes.length; i++)
                          _BoxTab(
                            label: _boxTitle(_boxes[i]),
                            selected: _tabController.index == i,
                            onTap: () => _tabController.animateTo(i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ---- شبكة العملات ----
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  for (final box in _boxes)
                    _CurrencyGrid(
                      key: ValueKey('$box-$_refreshToken-$_showAfterDelivery'),
                      db: widget.db,
                      boxType: box,
                      showAfterDelivery: _showAfterDelivery,
                      modeLabel: _modeLabel,
                      onOpen: (c) => _openCurrencyDetail(c, box),
                      onRefresh: _refresh,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _boxTitle(String box) {
    return switch (box) {
      'كامل' => 'الصندوق الكامل',
      'حركات' => 'صندوق الحركات',
      'صرف' => 'صندوق الصرف',
      _ => box,
    };
  }
}

class _BoxTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BoxTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppUi.surface(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected ? AppUi.border(context) : Colors.transparent,
            ),
            boxShadow: selected ? AppUi.softShadow(context) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accent : AppUi.textSecondary(context),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrencyGrid extends StatelessWidget {
  final AppDatabase db;
  final String boxType;
  final bool showAfterDelivery;
  final String modeLabel;
  final ValueChanged<Currency> onOpen;
  final VoidCallback onRefresh;

  const _CurrencyGrid({
    super.key,
    required this.db,
    required this.boxType,
    required this.showAfterDelivery,
    required this.modeLabel,
    required this.onOpen,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<int, CurrencyCashSummary>>(
      future: CashboxBalanceCalculator.calculate(db, boxType: boxType),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const TimaLoader(message: 'جارٍ حساب الأرصدة…');
        }

        final list = snapshot.data!.values.toList()
          ..sort((a, b) => a.currency.code.compareTo(b.currency.code));

        if (list.isEmpty) {
          return TimaEmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'لا توجد عملات',
            subtitle: 'أضف عملة واحدة على الأقل لعرض أرصدة الصندوق.',
            action: FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/add_currency'),
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('إضافة عملة'),
            ),
          );
        }

        return FutureBuilder<Map<int, double>>(
          future: _loadStockValues(list),
          builder: (context, stockSnap) {
            final stockValues = stockSnap.data ?? {};

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 1280
                    ? 4
                    : width >= 950
                        ? 3
                        : width >= 620
                            ? 2
                            : 1;

                return RefreshIndicator(
                  onRefresh: () async => onRefresh(),
                  child: Scrollbar(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppDims.pagePadding,
                        16,
                        AppDims.pagePadding,
                        24,
                      ),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 172,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final item = list[index];
                        final balance = showAfterDelivery
                            ? item.afterDeliveryTotal
                            : item.currentTotal;
                        final other = showAfterDelivery
                            ? item.currentTotal
                            : item.afterDeliveryTotal;
                        final pendingImpact =
                            item.afterDeliveryTotal - item.currentTotal;
                        final stockVal = stockValues[item.currency.id] ?? 0;
                        final matched =
                            (item.currentTotal - stockVal).abs() < 0.01;

                        return _CurrencyTile(
                          code: item.currency.code,
                          name: item.displayName,
                          balance: balance,
                          modeLabel: modeLabel,
                          secondaryLabel:
                              showAfterDelivery ? 'الحالي' : 'بعد التسليم',
                          secondaryValue: other,
                          pendingImpact: pendingImpact,
                          matched: matched,
                          isNegative: balance < 0,
                          onTap: () => onOpen(item.currency),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<Map<int, double>> _loadStockValues(
    List<CurrencyCashSummary> list,
  ) async {
    final map = <int, double>{};
    for (final item in list) {
      final stock = await CurrencyDenoms.loadStock(item.currency);
      var sum = 0.0;
      stock.forEach((d, c) => sum += d * c);
      map[item.currency.id] = sum;
    }
    return map;
  }
}

class _CurrencyTile extends StatefulWidget {
  final String code;
  final String name;
  final double balance;
  final String modeLabel;
  final String secondaryLabel;
  final double secondaryValue;
  final double pendingImpact;
  final bool matched;
  final bool isNegative;
  final VoidCallback onTap;

  const _CurrencyTile({
    required this.code,
    required this.name,
    required this.balance,
    required this.modeLabel,
    required this.secondaryLabel,
    required this.secondaryValue,
    required this.pendingImpact,
    required this.matched,
    required this.isNegative,
    required this.onTap,
  });

  @override
  State<_CurrencyTile> createState() => _CurrencyTileState();
}

class _CurrencyTileState extends State<_CurrencyTile> {
  bool _hover = false;

  String _fmt(double v) {
    final abs = v.abs();
    final text = abs == abs.roundToDouble()
        ? abs.toStringAsFixed(0)
        : abs.toStringAsFixed(2);
    // فاصل آلاف لتسهيل قراءة المبالغ الكبيرة.
    final parts = text.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    final formatted =
        parts.length > 1 ? '${buffer.toString()}.${parts[1]}' : buffer.toString();
    return v < 0 ? '−$formatted' : formatted;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isNegative
        ? AppUi.tone(context, AppColors.error)
        : AppUi.accent(context);
    final statusColor = widget.matched
        ? AppUi.tone(context, AppColors.success)
        : AppUi.tone(context, AppColors.warning);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: AppUi.surface(context),
            borderRadius: BorderRadius.circular(AppDims.radius),
            border: Border.all(
              color: _hover
                  ? accent.withValues(alpha: 0.5)
                  : AppUi.border(context),
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : AppUi.softShadow(context),
          ),
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // رأس البطاقة: رمز العملة + حالة المطابقة
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                        colors: widget.isNegative
                            ? [AppColors.coral, const Color(0xFFA83A3A)]
                            : AppColors.brandGradient,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppUi.textPrimary(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: widget.matched
                        ? 'الفئات مطابقة للرصيد'
                        : 'الفئات غير مطابقة — يُنصح بالجرد',
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // الرصيد الرئيسي
              Text(
                widget.modeLabel,
                style: TextStyle(
                  color: AppUi.textSecondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _fmt(widget.balance),
                  maxLines: 1,
                  style: TextStyle(
                    color: accent,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppUi.border(context)),
              const SizedBox(height: 9),

              // سطر ثانوي
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.secondaryLabel}: ${_fmt(widget.secondaryValue)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppUi.textSecondary(context),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.pendingImpact.abs() > 0.009)
                    Text(
                      widget.pendingImpact < 0
                          ? '−${_fmt(widget.pendingImpact.abs())}'
                          : '+${_fmt(widget.pendingImpact)}',
                      style: TextStyle(
                        color: AppUi.tone(context, AppColors.warning),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
