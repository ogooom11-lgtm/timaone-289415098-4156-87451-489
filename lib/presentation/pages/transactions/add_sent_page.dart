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
import '../../widgets/transaction_success_dialog.dart';

class AddSentPage extends StatefulWidget {
  final AppDatabase db;
  final User user;
  final Transaction? transaction;

  const AddSentPage({
    super.key,
    required this.db,
    required this.user,
    this.transaction,
  });

  @override
  State<AddSentPage> createState() => _AddSentPageState();
}

class _AddSentPageState extends State<AddSentPage> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _beneficiaryController = TextEditingController();
  final _receivedAmountController = TextEditingController();
  final _sentAmountController = TextEditingController();
  final _exchangeRateController = TextEditingController();
  final _feesController = TextEditingController();

  int? _receivedCurrencyId;
  int? _sentCurrencyId;
  int? _feesCurrencyId;
  String _operation = "قص";
  List<Currency> _currencies = [];

  bool get _isEditMode => widget.transaction != null;

  bool get _needsExchange =>
      _receivedCurrencyId != null &&
      _sentCurrencyId != null &&
      _receivedCurrencyId != _sentCurrencyId;

  @override
  void initState() {
    super.initState();
    _loadCurrencies().then((_) {
      if (_isEditMode) {
        final tx = widget.transaction!;
        _beneficiaryController.text = tx.beneficiary ?? "";
        _receivedAmountController.text = tx.amount.toString();
        _sentAmountController.text = tx.targetAmount?.toString() ?? "";
        _exchangeRateController.text = tx.exchangeRate?.toString() ?? "";
        _feesController.text = tx.fees?.toString() ?? "";
        _receivedCurrencyId = tx.currencyId;
        _sentCurrencyId = tx.targetCurrencyId;
        _feesCurrencyId = tx.feesCurrencyId;
        _operation = tx.operation ?? "قص";
        _dateController.text = DateFormat(
          'yyyy-MM-dd',
        ).format(tx.createdAt.toLocal());
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _receivedCurrencyId == null ||
        _sentCurrencyId == null ||
        _feesCurrencyId == null) {
      _formKey.currentState?.validate();
      return;
    }

    final beneficiaryText = _beneficiaryController.text.trim();
    final receivedVal = double.parse(_receivedAmountController.text.trim());
    final sentVal = double.parse(_sentAmountController.text.trim());
    final feesVal = double.parse(_feesController.text.trim());
    final rateVal = _needsExchange
        ? double.parse(_exchangeRateController.text.trim())
        : null;

    final currency1 = _currencies.firstWhere(
      (c) => c.id == _receivedCurrencyId,
    );

    // فئات الحوالة المقبوضة من العميل (تدخل للصندوق)
    final counts1 = await showDialog<Map<double, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenomValidatorDialog(
        targetAmount: receivedVal,
        currency: currency1,
        title: "تفصيل فئات الحوالة المستلمة من العميل",
        mode: DenomDialogMode.inflow,
      ),
    );
    if (counts1 == null) return; // تراجع المستخدم

    final denomNote =
        "[الفئات المستلمة للحوالة لـ ${currency1.code}: ${_formatCounts(counts1)}]";

    await CurrencyDenoms.addStock(currency1, counts1);

    if (_isEditMode) {
      final oldTx = widget.transaction!;
      final newValues = {
        "beneficiary": beneficiaryText,
        "amount": receivedVal.toString(),
        "currencyId": _receivedCurrencyId!.toString(),
        "targetCurrencyId": _sentCurrencyId!.toString(),
        "targetAmount": sentVal.toString(),
        "exchangeRate": rateVal?.toString() ?? "",
        "operation": _needsExchange ? _operation : "",
        "fees": feesVal.toString(),
        "feesCurrencyId": _feesCurrencyId!.toString(),
        "note": denomNote,
      };

      await widget.db.updateTransaction(
        oldTx.id,
        TransactionsCompanion(
          beneficiary: drift.Value(beneficiaryText),
          amount: drift.Value(receivedVal),
          currencyId: drift.Value(_receivedCurrencyId!),
          targetCurrencyId: drift.Value(_sentCurrencyId),
          targetAmount: drift.Value(sentVal),
          exchangeRate: _needsExchange
              ? drift.Value(rateVal)
              : const drift.Value(null),
          operation: _needsExchange
              ? drift.Value(_operation)
              : const drift.Value(null),
          fees: drift.Value(feesVal),
          feesCurrencyId: drift.Value(_feesCurrencyId),
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
          case "targetCurrencyId":
            oldValue = oldTx.targetCurrencyId?.toString() ?? "";
            break;
          case "targetAmount":
            oldValue = oldTx.targetAmount?.toString() ?? "";
            break;
          case "exchangeRate":
            oldValue = oldTx.exchangeRate?.toString() ?? "";
            break;
          case "operation":
            oldValue = oldTx.operation ?? "";
            break;
          case "fees":
            oldValue = oldTx.fees?.toString() ?? "";
            break;
          case "feesCurrencyId":
            oldValue = oldTx.feesCurrencyId?.toString() ?? "";
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
          currencyId: _receivedCurrencyId!,
          targetCurrencyId: drift.Value(_sentCurrencyId),
          feesCurrencyId: drift.Value(_feesCurrencyId),
          createdByName: drift.Value(widget.user.username),
          type: "حركة مرسلة",
          beneficiary: drift.Value(beneficiaryText),
          amount: receivedVal,
          targetAmount: drift.Value(sentVal),
          exchangeRate: _needsExchange
              ? drift.Value(rateVal)
              : const drift.Value.absent(),
          operation: _needsExchange
              ? drift.Value(_operation)
              : const drift.Value.absent(),
          fees: drift.Value(feesVal),
          note: drift.Value(denomNote),
          movementState: const drift.Value("مفعلة"),
          status: const drift.Value("تم الارسال"),
        ),
      );

      if (!mounted) return;
      final sentCurrency = _currencies.firstWhere(
        (currency) => currency.id == _sentCurrencyId,
      );
      final feesCurrency = _currencies.firstWhere(
        (currency) => currency.id == _feesCurrencyId,
      );
      await showCopyableTransactionSuccess(
        context,
        title: 'تمت الحركة المرسلة بنجاح',
        message:
            'حركة مرسلة\n$beneficiaryText\n'
            'تم الاستلام: ${receivedVal.toStringAsFixed(2)} ${currency1.code}\n'
            'تم الإرسال: ${sentVal.toStringAsFixed(2)} ${sentCurrency.code}\n'
            'الأجور: ${feesVal.toStringAsFixed(2)} ${feesCurrency.code}',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _beneficiaryController.dispose();
    _receivedAmountController.dispose();
    _sentAmountController.dispose();
    _exchangeRateController.dispose();
    _feesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: _isEditMode ? "تعديل حركة مرسلة" : "إضافة حركة مرسلة",
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
            const TimaHeaderPanel(
              icon: Icons.send_rounded,
              title: "حركة حوالة صادرة (مرسلة)",
              subtitle:
                  "تسجل الحركات المرسلة بمبلغ موجب ويتم عد الفئات المستلمة يدوياً للمطابقة.",
              startColor: AppColors.info,
              endColor: AppColors.brandGreenDark,
            ),
            const SizedBox(height: 20),

            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDims.radius),
                side: BorderSide(color: AppUi.border(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _dateController,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: "التاريخ والوقت",
                        prefixIcon: const Icon(
                          Icons.calendar_today,
                          color: AppColors.brandGold,
                        ),
                        fillColor: isDark
                            ? AppColors.darkBackground
                            : AppColors.neutral500.withValues(alpha: 0.04),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _beneficiaryController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\u0600-\u06FFa-zA-Z0-9 ]'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: "اسم مستلم الحوالة (المستفيد)",
                        prefixIcon: Icon(
                          Icons.person,
                          color: AppColors.brandGold,
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? "مطلوب"
                          : null,
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      "المبلغ المستلم من العميل (المبلغ 1):",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.neutral500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _amountCurrencyRow(
                      amountController: _receivedAmountController,
                      amountLabel: "مبلغ الاستلام",
                      selectedCurrencyId: _receivedCurrencyId,
                      onCurrencyChanged: (value) =>
                          setState(() => _receivedCurrencyId = value),
                    ),
                    const SizedBox(height: 16),

                    if (_needsExchange) ...[
                      const Text(
                        "إعدادات تحويل العملة والصرف:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppColors.neutral500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _exchangeRateController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: "سعر صرف الحوالة",
                          prefixIcon: Icon(
                            Icons.price_change,
                            color: AppColors.brandGold,
                          ),
                        ),
                        validator: (value) =>
                            value == null ||
                                value.trim().isEmpty ||
                                double.tryParse(value) == null
                            ? "مطلوب رقم صالح"
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _operation,
                        decoration: const InputDecoration(
                          labelText: "العملية الحسابية",
                          prefixIcon: Icon(
                            Icons.calculate,
                            color: AppColors.brandGold,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "قص",
                            child: Text("قص (تقسيم)"),
                          ),
                          DropdownMenuItem(
                            value: "ضرب",
                            child: Text("ضرب (تضرب)"),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _operation = value ?? "قص"),
                      ),
                      const SizedBox(height: 16),
                    ],

                    const Text(
                      "المبلغ المرسل للمكتب الآخر (المبلغ 2):",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.neutral500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _amountCurrencyRow(
                      amountController: _sentAmountController,
                      amountLabel: "مبلغ الإرسال",
                      selectedCurrencyId: _sentCurrencyId,
                      onCurrencyChanged: (value) =>
                          setState(() => _sentCurrencyId = value),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      "أجور وعمولات الحوالة:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.neutral500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _amountCurrencyRow(
                      amountController: _feesController,
                      amountLabel: "أجور وعمولة التحويل",
                      selectedCurrencyId: _feesCurrencyId,
                      onCurrencyChanged: (value) =>
                          setState(() => _feesCurrencyId = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

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
                    icon: const Icon(Icons.close),
                    label: const Text("إلغاء"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDims.radiusSm),
                      ),
                    ),
                    onPressed: _save,
                    icon: Icon(_isEditMode ? Icons.save : Icons.check),
                    label: Text(
                      _isEditMode
                          ? "حفظ التعديلات"
                          : "تأكيد فئات واستلام الحوالة",
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

  Widget _amountCurrencyRow({
    required TextEditingController amountController,
    required String amountLabel,
    required int? selectedCurrencyId,
    required ValueChanged<int?> onCurrencyChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: amountLabel,
              prefixIcon: const Icon(
                Icons.payments,
                color: AppColors.brandGold,
              ),
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
            value: selectedCurrencyId,
            decoration: const InputDecoration(labelText: "العملة"),
            items: _currencies
                .map(
                  (currency) => DropdownMenuItem(
                    value: currency.id,
                    child: Text(
                      currency.code,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                )
                .toList(),
            onChanged: onCurrencyChanged,
            validator: (value) => value == null ? "مطلوب" : null,
          ),
        ),
      ],
    );
  }
}
