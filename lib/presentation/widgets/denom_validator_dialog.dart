import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_denoms.dart';
import 'app_ui.dart';

/// حوار جرد/مطابقة الفئات — إدخال بالكتابة + أزرار ± + تعبئة تلقائية.
///
/// عند التسليم (mode = outflow):
/// - تُعطَّل الفئة إذا كانت أكبر من المبلغ المتبقي
/// - تُعطَّل الفئة إذا لم يتوفر منها مخزون في الصندوق
/// - لا يمكن تجاوز العدد المتوفر من كل فئة
class DenomValidatorDialog extends StatefulWidget {
  final double targetAmount;
  final Currency currency;
  final String title;

  /// إذا true يجب أن يطابق المجموع المبلغ المطلوب قبل التأكيد.
  final bool requireMatch;

  /// قيم ابتدائية اختيارية.
  final Map<double, int>? initialCounts;

  /// مخزون الأوراق المتوفر في الصندوق لكل فئة.
  /// null = لا يوجد قيد مخزون (مثلاً عند الاستلام).
  final Map<double, int>? availableStock;

  /// outflow: تسليم من الصندوق (يقيد بالمخزون)
  /// inflow: استلام للصندوق (بدون قيد مخزون)
  final DenomDialogMode mode;

  const DenomValidatorDialog({
    super.key,
    required this.targetAmount,
    required this.currency,
    required this.title,
    this.requireMatch = true,
    this.initialCounts,
    this.availableStock,
    this.mode = DenomDialogMode.inflow,
  });

  @override
  State<DenomValidatorDialog> createState() => _DenomValidatorDialogState();
}

enum DenomDialogMode { inflow, outflow }

class _DenomValidatorDialogState extends State<DenomValidatorDialog> {
  late List<double> _denoms;
  final Map<double, TextEditingController> _controllers = {};
  final Map<double, FocusNode> _focusNodes = {};

  bool get _enforceStock =>
      widget.mode == DenomDialogMode.outflow && widget.availableStock != null;

  @override
  void initState() {
    super.initState();
    _denoms = CurrencyDenoms.forCurrency(widget.currency);
    for (final denom in _denoms) {
      var initial = widget.initialCounts?[denom] ?? 0;
      // لا نبدأ بعدد أعلى من المخزون إن وُجد
      if (_enforceStock) {
        final stock = widget.availableStock![denom] ?? 0;
        if (initial > stock) initial = stock;
      }
      // لا نبدأ بفئة أكبر من المبلغ
      if (denom > widget.targetAmount + 0.001) initial = 0;

      _controllers[denom] = TextEditingController(
        text: initial > 0 ? initial.toString() : '',
      );
      _focusNodes[denom] = FocusNode();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  int _countOf(double denom) {
    final text = _controllers[denom]?.text.trim() ?? '';
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? 0;
  }

  Map<double, int> get _counts {
    return {for (final d in _denoms) d: _countOf(d)};
  }

  double get _currentSum => CurrencyDenoms.sumCounts(_counts);

  int _stockOf(double denom) {
    if (!_enforceStock) return 999999;
    return widget.availableStock![denom] ?? 0;
  }

  /// هل الفئة قابلة للاستخدام أصلاً؟
  bool _isDenomEnabled(double denom) {
    // أكبر من المبلغ المطلوب بالكامل → غير فعالة
    if (denom > widget.targetAmount + 0.001) return false;
    // لا مخزون عند التسليم
    if (_enforceStock && _stockOf(denom) <= 0) return false;
    return true;
  }

  /// الحد الأقصى المسموح لهذه الفئة الآن (حسب المتبقي + المخزون)
  int _maxAllowed(double denom) {
    if (!_isDenomEnabled(denom)) return 0;
    final otherSum = _currentSum - (denom * _countOf(denom));
    final remaining = widget.targetAmount - otherSum;
    if (remaining <= 0) return 0;
    var maxByAmount = (remaining / denom + 1e-9).floor();
    if (maxByAmount < 0) maxByAmount = 0;
    if (_enforceStock) {
      final stock = _stockOf(denom);
      if (maxByAmount > stock) maxByAmount = stock;
    }
    return maxByAmount;
  }

  String? _disabledReason(double denom) {
    if (denom > widget.targetAmount + 0.001) {
      return 'أكبر من المبلغ';
    }
    if (_enforceStock && _stockOf(denom) <= 0) {
      return 'غير متوفرة';
    }
    return null;
  }

  void _setCount(double denom, int count) {
    if (!_isDenomEnabled(denom) && count > 0) return;
    final max = _maxAllowed(denom);
    // عند الزيادة: احترم الحد
    var safe = count;
    if (safe < 0) safe = 0;
    if (safe > max && max >= 0) {
      // إذا كان العدد الحالي ضمن الحد لكن max تغيّر بسبب الحقول الأخرى
      // اسمح بالعدد الحالي إن كان أقل من المخزون
      final stockCap = _enforceStock ? _stockOf(denom) : 999999;
      final otherSum = _currentSum - (denom * _countOf(denom));
      final remaining = widget.targetAmount - otherSum;
      final byAmount = remaining <= 0 ? 0 : (remaining / denom + 1e-9).floor();
      final hardMax = byAmount < stockCap ? byAmount : stockCap;
      safe = safe > hardMax ? hardMax : safe;
      if (safe < 0) safe = 0;
    }
    _controllers[denom]?.text = safe == 0 ? '' : safe.toString();
    setState(() {});
  }

  void _onTyped(double denom, String text) {
    if (!_isDenomEnabled(denom)) {
      _controllers[denom]?.text = '';
      setState(() {});
      return;
    }
    if (text.isEmpty) {
      setState(() {});
      return;
    }
    final parsed = int.tryParse(text) ?? 0;
    final stockCap = _enforceStock ? _stockOf(denom) : 999999;
    if (parsed > stockCap) {
      _controllers[denom]?.text = stockCap == 0 ? '' : stockCap.toString();
      _controllers[denom]?.selection = TextSelection.collapsed(
        offset: _controllers[denom]!.text.length,
      );
    }
    setState(() {});
  }

  // ignore: unused_element
  void _autoFill() {
    final filled = CurrencyDenoms.autoFill(
      widget.targetAmount,
      _denoms,
      availableStock: _enforceStock ? widget.availableStock : null,
    );
    for (final denom in _denoms) {
      final c = filled[denom] ?? 0;
      _controllers[denom]?.text = c == 0 ? '' : c.toString();
    }
    setState(() {});
  }

  // ignore: unused_element
  void _clearAll() {
    for (final c in _controllers.values) {
      c.clear();
    }
    setState(() {});
  }

  String _fmtDenom(double denom) => CurrencyDenoms.fmtDenom(denom);

  @override
  Widget build(BuildContext context) {
    final currentSum = _currentSum;
    final diff = widget.targetAmount - currentSum;
    final isMatched = diff.abs() < 0.01;
    // تحقق إضافي: لا يتجاوز أي عدد المخزون
    var stockOk = true;
    if (_enforceStock) {
      for (final d in _denoms) {
        if (_countOf(d) > _stockOf(d)) {
          stockOk = false;
          break;
        }
      }
    }
    final canConfirm = (!widget.requireMatch || isMatched) && stockOk;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final code = widget.currency.code;

    // نافذة مركزية بعرض محدود: النمط الصحيح على سطح مكتب ويندوز
    // بدلاً من الأوراق المنبثقة من الأسفل المخصّصة للهواتف.
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSecondaryBackground
            : AppColors.lightBackground,
        borderRadius: BorderRadius.circular(AppDims.radiusLg),
        border: Border.all(color: AppUi.border(context)),
        boxShadow: AppUi.raisedShadow(context),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.payments,
                  color: AppColors.brandGold,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.brandGreen,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.mode == DenomDialogMode.outflow) ...[
              const SizedBox(height: 6),
              Text(
                _enforceStock
                    ? 'يُسمح فقط بالفئات المتوفرة في الصندوق والأصغر من/تساوي المبلغ'
                    : 'الفئات الأكبر من المبلغ تُعطَّل تلقائياً',
                style: TextStyle(fontSize: 11, color: AppColors.neutral500),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 10),

            // ملخص الحالة
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isMatched
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppDims.radiusSm),
                border: Border.all(
                  color: isMatched
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'المبلغ المطلوب:',
                        style: TextStyle(fontSize: 13, color: AppColors.neutral500),
                      ),
                      Text(
                        '${widget.targetAmount.toStringAsFixed(2)} $code',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'مجموع الفئات:',
                        style: TextStyle(fontSize: 13, color: AppColors.neutral500),
                      ),
                      Text(
                        '${currentSum.toStringAsFixed(2)} $code',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isMatched
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isMatched
                            ? '✓ الفئات متطابقة'
                            : '⚠ المتبقي: ${diff.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isMatched
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                      if (!isMatched && currentSum > widget.targetAmount)
                        Text(
                          'زيادة: ${(currentSum - widget.targetAmount).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            Text(
              'اكتب عدد الأوراق مباشرة أو استخدم + / − — المجموع يُحسب تلقائياً',
              style: TextStyle(fontSize: 11, color: AppColors.neutral500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _denoms.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final denom = _denoms[index];
                  final count = _countOf(denom);
                  final subtotal = denom * count;
                  final controller = _controllers[denom]!;
                  final enabled = _isDenomEnabled(denom);
                  final reason = _disabledReason(denom);
                  final stock = _enforceStock ? _stockOf(denom) : null;
                  final maxAllowed = _maxAllowed(denom);

                  return Opacity(
                    opacity: enabled ? 1 : 0.45,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: enabled
                              ? AppColors.neutral500.withValues(alpha: 0.25)
                              : AppColors.error.withValues(alpha: 0.25),
                        ),
                        borderRadius: BorderRadius.circular(AppDims.radius),
                        color: !enabled
                            ? (isDark
                                ? Colors.black26
                                : AppColors.neutral500.withValues(alpha: 0.08))
                            : (isDark
                                ? AppColors.darkSecondaryBackground
                                : Colors.white),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 78,
                                child: Text(
                                  '${_fmtDenom(denom)}\n$code',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    height: 1.2,
                                    color: enabled ? null : AppColors.neutral500,
                                    decoration: enabled
                                        ? null
                                        : TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: AppColors.error,
                                  size: 22,
                                ),
                                onPressed: enabled && count > 0
                                    ? () => _setCount(denom, count - 1)
                                    : null,
                              ),
                              SizedBox(
                                width: 72,
                                child: TextField(
                                  controller: controller,
                                  focusNode: _focusNodes[denom],
                                  enabled: enabled,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                    hintText: enabled ? '0' : '—',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppDims.radiusSm),
                                    ),
                                  ),
                                  onChanged: (v) => _onTyped(denom, v),
                                  onTap: enabled
                                      ? () {
                                          controller.selection = TextSelection(
                                            baseOffset: 0,
                                            extentOffset:
                                                controller.text.length,
                                          );
                                        }
                                      : null,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: AppColors.success,
                                  size: 22,
                                ),
                                onPressed: enabled && count < maxAllowed
                                    ? () => _setCount(denom, count + 1)
                                    : null,
                              ),
                              const Spacer(),
                              Text(
                                enabled
                                    ? subtotal.toStringAsFixed(
                                        subtotal == subtotal.roundToDouble()
                                            ? 0
                                            : 2,
                                      )
                                    : '—',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          // سطر توضيحي: متوفر / سبب التعطيل
                          Padding(
                            padding: const EdgeInsets.only(
                              right: 4,
                              left: 4,
                              bottom: 2,
                            ),
                            child: Text(
                              reason != null
                                  ? '✗ $reason'
                                  : (stock != null
                                      ? 'متوفر في الصندوق: $stock ورقة'
                                          '${maxAllowed < stock ? " • الحد الآن: $maxAllowed" : ""}'
                                      : 'متاحة'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: reason != null
                                    ? AppColors.error
                                    : AppColors.slate,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          canConfirm ? AppColors.success : AppColors.neutral500,
                    ),
                    onPressed: canConfirm
                        ? () => Navigator.pop(context, _counts)
                        : null,
                    child: const Text(
                      '✓ تأكيد الفئات',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}
