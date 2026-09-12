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

class AddExchangePage extends StatefulWidget {
  final AppDatabase db;
  final User user;
  final Transaction? transaction;

  const AddExchangePage({
    super.key,
    required this.db,
    required this.user,
    this.transaction,
  });

  @override
  State<AddExchangePage> createState() => _AddExchangePageState();
}

class _AddExchangePageState extends State<AddExchangePage> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _amountFromController = TextEditingController();
  final _amountToController = TextEditingController();
  final _exchangeRateController = TextEditingController();

  int? _currencyFromId;
  int? _currencyToId;
  String _operation = "قص";
  List<Currency> _currencies = [];

  bool get _isEditMode => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    _amountFromController.addListener(_calculateAmountTo);
    _exchangeRateController.addListener(_calculateAmountTo);

    _loadCurrencies().then((_) {
      if (_isEditMode) {
        final tx = widget.transaction!;
        _currencyFromId = tx.currencyId;
        _currencyToId = tx.targetCurrencyId;
        _exchangeRateController.text = tx.exchangeRate?.toString() ?? "";
        _operation = tx.operation ?? "قص";
        _amountFromController.text = tx.amount.toString();
        _amountToController.text = tx.targetAmount?.toString() ?? "";
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

  void _calculateAmountTo() {
    final amount = double.tryParse(_amountFromController.text);
    final rate = double.tryParse(_exchangeRateController.text);
    if (amount == null || rate == null || rate == 0) {
      _amountToController.text = "";
      return;
    }

    final result = _operation == "قص" ? amount / rate : amount * rate;
    _amountToController.text = result.toStringAsFixed(2);
  }

  void _swapCurrencies() {
    setState(() {
      final oldFrom = _currencyFromId;
      _currencyFromId = _currencyToId;
      _currencyToId = oldFrom;
    });
  }

  String _formatCounts(Map<double, int> counts) {
    return counts.entries
        .where((e) => e.value > 0)
        .map((e) => "${e.key.toStringAsFixed(0)}x${e.value}")
        .join(", ");
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _currencyFromId == null ||
        _currencyToId == null ||
        _currencyFromId == _currencyToId) {
      _formKey.currentState?.validate();
      return;
    }

    final amountFromVal = double.parse(_amountFromController.text.trim());
    final amountToVal = double.parse(_amountToController.text.trim());
    final rateVal = double.parse(_exchangeRateController.text.trim());

    final currencyFrom = _currencies.firstWhere((c) => c.id == _currencyFromId);
    final currencyTo = _currencies.firstWhere((c) => c.id == _currencyToId);

    // 1. فئات الصادر — مقيدة بمخزون الصندوق
    final stockFrom = await CurrencyDenoms.loadStock(currencyFrom);
    if (!mounted) return;
    final countsFrom = await showDialog<Map<double, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenomValidatorDialog(
        targetAmount: amountFromVal,
        currency: currencyFrom,
        title: "تفصيل فئات المبلغ المسلم (الصادر من الصندوق)",
        mode: DenomDialogMode.outflow,
        availableStock: stockFrom,
      ),
    );
    if (countsFrom == null) return; // تراجع المستخدم

    // 2. فئات الوارد — بدون قيد مخزون (تدخل للصندوق)
    if (!mounted) return;
    final countsTo = await showDialog<Map<double, int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DenomValidatorDialog(
        targetAmount: amountToVal,
        currency: currencyTo,
        title: "تفصيل فئات المبلغ المستلم (الوارد للصندوق)",
        mode: DenomDialogMode.inflow,
      ),
    );
    if (countsTo == null) return; // تراجع المستخدم

    final denomNote =
        "[فئات المسلم لـ ${currencyFrom.code}: ${_formatCounts(countsFrom)}]\n[فئات المستلم لـ ${currencyTo.code}: ${_formatCounts(countsTo)}]";

    // تحديث مخزون الأوراق: خصم الصادر + إضافة الوارد
    await CurrencyDenoms.deductStock(currencyFrom, countsFrom);
    await CurrencyDenoms.addStock(currencyTo, countsTo);

    if (_isEditMode) {
      final oldTx = widget.transaction!;
      final newValues = {
        "currencyId": _currencyFromId!.toString(),
        "targetCurrencyId": _currencyToId!.toString(),
        "amount": amountFromVal.toString(),
        "targetAmount": amountToVal.toString(),
        "exchangeRate": rateVal.toString(),
        "operation": _operation,
        "note": denomNote,
      };

      await widget.db.updateTransaction(
        oldTx.id,
        TransactionsCompanion(
          currencyId: drift.Value(_currencyFromId!),
          targetCurrencyId: drift.Value(_currencyToId),
          amount: drift.Value(amountFromVal),
          targetAmount: drift.Value(amountToVal),
          exchangeRate: drift.Value(rateVal),
          operation: drift.Value(_operation),
          note: drift.Value(denomNote),
        ),
      );

      for (final entry in newValues.entries) {
        final field = entry.key;
        final newValue = entry.value;
        String oldValue = "";

        switch (field) {
          case "currencyId":
            oldValue = oldTx.currencyId.toString();
            break;
          case "targetCurrencyId":
            oldValue = oldTx.targetCurrencyId?.toString() ?? "";
            break;
          case "amount":
            oldValue = oldTx.amount.toString();
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
          currencyId: _currencyFromId!,
          targetCurrencyId: drift.Value(_currencyToId),
          createdByName: drift.Value(widget.user.username),
          type: "حركة تسوية",
          amount: amountFromVal,
          targetAmount: drift.Value(amountToVal),
          exchangeRate: drift.Value(rateVal),
          operation: drift.Value(_operation),
          note: drift.Value(denomNote),
          movementState: const drift.Value("مفعلة"),
          status: const drift.Value("تم التصريف"),
        ),
      );

      if (!mounted) return;
      await showCopyableTransactionSuccess(
        context,
        title: 'تمت حركة الصرف بنجاح',
        message:
            'حركة صرف\n'
            '${amountFromVal.toStringAsFixed(2)} ${currencyFrom.code}\n'
            'إلى ${amountToVal.toStringAsFixed(2)} ${currencyTo.code}\n'
            'سعر الصرف: ${rateVal.toStringAsFixed(4)}',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _amountFromController.dispose();
    _amountToController.dispose();
    _exchangeRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: _isEditMode ? "تعديل حركة صرف" : "إضافة حركة صرف",
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
              icon: Icons.currency_exchange_rounded,
              title: _isEditMode ? "تعديل حركة صرف" : "تسجيل حركة صرف",
              subtitle: "تحويل بين عملتين مع جرد فئات الصادر والوارد.",
              startColor: AppColors.brandGoldDark,
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
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _currencyFromId,
                    decoration: const InputDecoration(labelText: "العملة من"),
                    items: _currencies
                        .where((c) => c.id != _currencyToId)
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency.id,
                            child: Text(currency.code),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _currencyFromId = value),
                    validator: (value) => value == null ? "مطلوب" : null,
                  ),
                ),
                IconButton(
                  onPressed: _swapCurrencies,
                  tooltip: "تبديل",
                  icon: const Icon(Icons.swap_horiz),
                ),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _currencyToId,
                    decoration: const InputDecoration(labelText: "العملة إلى"),
                    items: _currencies
                        .where((c) => c.id != _currencyFromId)
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency.id,
                            child: Text(currency.code),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _currencyToId = value),
                    validator: (value) => value == null ? "مطلوب" : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _exchangeRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: "سعر الصرف",
                prefixIcon: Icon(Icons.price_change),
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
                labelText: "العملية",
                prefixIcon: Icon(Icons.calculate),
              ),
              items: const [
                DropdownMenuItem(value: "قص", child: Text("قص")),
                DropdownMenuItem(value: "ضرب", child: Text("ضرب")),
              ],
              onChanged: (value) {
                setState(() => _operation = value ?? "قص");
                _calculateAmountTo();
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountFromController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: "المبلغ من",
                prefixIcon: Icon(Icons.payments),
              ),
              validator: (value) =>
                  value == null ||
                      value.trim().isEmpty ||
                      double.tryParse(value) == null
                  ? "مطلوب رقم صالح"
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountToController,
              enabled: false,
              decoration: const InputDecoration(
                labelText: "المبلغ إلى",
                prefixIcon: Icon(Icons.payments),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? "يتم حسابه تلقائيًا"
                  : null,
            ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text("إلغاء"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: Icon(_isEditMode ? Icons.save : Icons.check),
                    label: Text(
                      _isEditMode ? "حفظ التعديلات" : "تأكيد فئات الصرف",
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
