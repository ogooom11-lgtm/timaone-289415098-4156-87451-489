import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/denom_validator_dialog.dart';

class AddReceivePage extends StatefulWidget {
  final AppDatabase db;
  final User user;
  final Transaction? transaction;

  const AddReceivePage({
    super.key,
    required this.db,
    required this.user,
    this.transaction,
  });

  @override
  State<AddReceivePage> createState() => _AddReceivePageState();
}

class _AddReceivePageState extends State<AddReceivePage> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _accountController = TextEditingController();
  final _amountController = TextEditingController();

  // حقول المبلغ والعملة الثانية الاختيارية
  final _amount2Controller = TextEditingController();
  int? _selectedCurrencyId2;
  bool _showSecondAmount = false;

  int? _selectedCurrencyId;
  List<Currency> _currencies = [];

  bool get _isEditMode => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    _loadCurrencies().then((_) {
      if (_isEditMode) {
        final tx = widget.transaction!;
        _accountController.text = tx.beneficiary ?? "";
        _amountController.text = tx.amount.toString();
        _selectedCurrencyId = tx.currencyId;
        _dateController.text = DateFormat(
          'yyyy-MM-dd',
        ).format(tx.createdAt.toLocal());

        if (tx.targetAmount != null && tx.targetCurrencyId != null) {
          _amount2Controller.text = tx.targetAmount.toString();
          _selectedCurrencyId2 = tx.targetCurrencyId;
          _showSecondAmount = true;
        }
        setState(() {});
      } else {
        _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }
    });
  }

  Future<void> _loadCurrencies() async {
    final list = await widget.db.getAllCurrencies();
    if (!mounted) return;
    setState(() => _currencies = list);
  }

  String _formatCounts(Map<double, int> counts) {
    return counts.entries
        .where((e) => e.value > 0)
        .map((e) => "${e.key.toStringAsFixed(0)}x${e.value}")
        .join(", ");
  }

  String _receiveMessage({
    required String account,
    required double amount,
    required Currency currency,
    required Map<double, int> counts,
  }) {
    final details = counts.entries
        .where((entry) => entry.value > 0)
        .map((entry) => '**** من فئة *${entry.key}*')
        .join('\n');
    return 'تم استلام من *$account* *${amount.toStringAsFixed(2)}* *${currency.code}*'
        '${details.isEmpty ? '' : '\nتفصيل الفئات:\n$details'}';
  }

  Future<void> _showReceiveSuccess(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success),
            SizedBox(width: 8),
            Text('تم الاستلام بنجاح'),
          ],
        ),
        content: SelectableText(message),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('نسخ الرسالة'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }

  Future<void> _save({required bool stay}) async {
    if (_currencies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("جاري تحميل العملات... الرجاء المحاولة ثانية"),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate() || _selectedCurrencyId == null) {
      _formKey.currentState?.validate();
      return;
    }

    final beneficiaryText = _accountController.text.trim();
    final amountVal = double.parse(_amountController.text.trim());

    final amount2Val = _showSecondAmount && _amount2Controller.text.isNotEmpty
        ? double.tryParse(_amount2Controller.text.trim())
        : null;
    final currency2Val = _showSecondAmount ? _selectedCurrencyId2 : null;

    final currency1 = _currencies.firstWhere(
      (c) => c.id == _selectedCurrencyId,
    );

    // 1. فئات المقبوضات (تدخل للصندوق)
    final counts1 = await showDialog<Map<double, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenomValidatorDialog(
        targetAmount: amountVal,
        currency: currency1,
        title: "تفصيل فئات المقبوضات (المبلغ 1)",
        mode: DenomDialogMode.inflow,
      ),
    );
    if (counts1 == null) return; // تراجع المستخدم

    // 2. مبلغ ثانٍ اختياري
    Map<double, int>? counts2;
    Currency? currency2;
    if (_showSecondAmount && amount2Val != null && currency2Val != null) {
      currency2 = _currencies.firstWhere((c) => c.id == currency2Val);
      if (!mounted) return;
      counts2 = await showDialog<Map<double, int>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DenomValidatorDialog(
          targetAmount: amount2Val,
          currency: currency2!,
          title: "تفصيل فئات المقبوضات الثانية (المبلغ 2)",
          mode: DenomDialogMode.inflow,
        ),
      );
      if (counts2 == null) return; // تراجع المستخدم
    }

    // بناء الملاحظة الذكية للفئات
    String denomNote =
        "[الفئات المستلمة لـ ${currency1.code}: ${_formatCounts(counts1)}]";
    if (counts2 != null && currency2 != null) {
      denomNote +=
          "\n[الفئات المستلمة لـ ${currency2.code}: ${_formatCounts(counts2)}]";
    }

    // إضافة للمخزون المتوفر
    await CurrencyDenoms.addStock(currency1, counts1);
    if (counts2 != null && currency2 != null) {
      await CurrencyDenoms.addStock(currency2, counts2);
    }

    if (_isEditMode) {
      final oldTx = widget.transaction!;
      final newValues = {
        "beneficiary": beneficiaryText,
        "amount": amountVal.toString(),
        "currencyId": _selectedCurrencyId!.toString(),
        "note": denomNote,
      };

      await widget.db.updateTransaction(
        oldTx.id,
        TransactionsCompanion(
          beneficiary: drift.Value(beneficiaryText),
          amount: drift.Value(amountVal),
          currencyId: drift.Value(_selectedCurrencyId!),
          targetAmount: drift.Value(amount2Val),
          targetCurrencyId: drift.Value(currency2Val),
          note: drift.Value(denomNote),
        ),
      );

      for (final entry in newValues.entries) {
        final field = entry.key;
        final newValue = entry.value;
        String oldValue = "";

        switch (field) {
          case "beneficiary":
            oldValue = oldTx.beneficiary ?? "";
            break;
          case "amount":
            oldValue = oldTx.amount.toString();
            break;
          case "currencyId":
            oldValue = oldTx.currencyId.toString();
            break;
          case "note":
            oldValue = oldTx.note ?? "";
            break;
        }

        if (newValue != oldValue) {
          await widget.db.insertEdit(
            EditsCompanion(
              transactionId: drift.Value(oldTx.id),
              field: drift.Value(field),
              oldValue: drift.Value(oldValue),
              newValue: drift.Value(newValue),
              editedBy: drift.Value(widget.user.username),
            ),
          );
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      await widget.db.insertTransaction(
        TransactionsCompanion.insert(
          userId: widget.user.id,
          currencyId: _selectedCurrencyId!,
          targetCurrencyId: drift.Value(currency2Val),
          targetAmount: drift.Value(amount2Val),
          createdByName: drift.Value(widget.user.username),
          type: "حركة استلام",
          beneficiary: drift.Value(beneficiaryText),
          amount: amountVal,
          note: drift.Value(denomNote),
          movementState: const drift.Value("مفعلة"),
          status: const drift.Value("تم الاستلام"),
        ),
      );

      if (!mounted) return;
      await _showReceiveSuccess(
        _receiveMessage(
          account: beneficiaryText,
          amount: amountVal,
          currency: currency1,
          counts: counts1,
        ),
      );
      if (!mounted) return;
      if (stay) {
        _accountController.clear();
        _amountController.clear();
        _amount2Controller.clear();
        setState(() {
          _selectedCurrencyId = null;
          _selectedCurrencyId2 = null;
          _showSecondAmount = false;
        });
      } else {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _accountController.dispose();
    _amountController.dispose();
    _amount2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: _isEditMode ? "تعديل حركة استلام" : "إضافة حركة استلام",
      ),
      body: TimaPageBackground(
        child: Form(
        key: _formKey,
        child: Scrollbar(
          child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDims.pagePadding,
            vertical: 18,
          ),
          children: [
            TimaContentWidth(
              maxWidth: 880,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            TimaHeaderPanel(
              icon: Icons.move_to_inbox_rounded,
              title: _isEditMode ? "تعديل حركة استلام" : "تسجيل حركة استلام",
              subtitle: "تدخل المبالغ المستلمة إلى الصندوق بعد جرد فئاتها.",
              startColor: AppColors.success,
              endColor: AppColors.brandGreenDark,
            ),
            const SizedBox(height: 16),
            TimaPanel(
              child: Column(
                children: [
            TextFormField(
              controller: _dateController,
              enabled: false,
              decoration: const InputDecoration(
                labelText: "التاريخ",
                prefixIcon: Icon(Icons.calendar_today),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _accountController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[\u0600-\u06FFa-zA-Z0-9 ]'),
                ),
              ],
              decoration: const InputDecoration(
                labelText: "اسم الحساب",
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? "مطلوب" : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: "المبلغ",
                      prefixIcon: Icon(Icons.payments),
                    ),
                    validator: (value) =>
                        value == null ||
                            value.trim().isEmpty ||
                            double.tryParse(value) == null
                        ? "مطلوب رقم صالح"
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedCurrencyId,
                    decoration: const InputDecoration(labelText: "العملة"),
                    items: _currencies
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency.id,
                            child: Text(currency.code),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedCurrencyId = value),
                    validator: (value) => value == null ? "مطلوب" : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Switch to enable Second Amount/Currency (Optional)
            Row(
              children: [
                Checkbox(
                  value: _showSecondAmount,
                  activeColor: AppColors.brandGold,
                  onChanged: (val) {
                    setState(() {
                      _showSecondAmount = val ?? false;
                    });
                  },
                ),
                const Text(
                  "دعم مبلغ ثانٍ وعملة ثانوية بالحركة (اختياري)",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),

            if (_showSecondAmount) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _amount2Controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: "المبلغ 2 (مطلوب عند التفعيل)",
                        prefixIcon: Icon(
                          Icons.payments_outlined,
                          color: AppColors.brandGoldDark,
                        ),
                      ),
                      validator: (value) {
                        if (_showSecondAmount) {
                          if (value == null || value.trim().isEmpty) {
                            return "مطلوب عند تفعيل المبلغ الثاني";
                          }
                          if (double.tryParse(value) == null) {
                            return "أدخل رقماً صالحاً";
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedCurrencyId2,
                      decoration: const InputDecoration(
                        labelText: "العملة 2",
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                      ),
                      items: _currencies
                          .map(
                            (currency) => DropdownMenuItem(
                              value: currency.id,
                              child: Text(
                                currency.code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedCurrencyId2 = value),
                      validator: (value) =>
                          _showSecondAmount && value == null ? "مطلوب" : null,
                    ),
                  ),
                ],
              ),
            ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_isEditMode)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDims.radiusSm),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text("إلغاء التعديل"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandGold,
                        foregroundColor: AppColors.brandGreenDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDims.radiusSm),
                        ),
                      ),
                      onPressed: () => _save(stay: false),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text(
                        "حفظ وتأكيد التعديل",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDims.radiusSm),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text("إلغاء"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDims.radiusSm),
                        ),
                      ),
                      onPressed: () => _save(stay: true),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text(
                        "حفظ وجديد",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDims.radiusSm),
                        ),
                      ),
                      onPressed: () => _save(stay: false),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text(
                        "حفظ وإغلاق",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
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
}
