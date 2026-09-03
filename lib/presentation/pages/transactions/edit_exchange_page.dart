import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_database.dart';

class EditExchangePage extends StatefulWidget {
  final AppDatabase db;
  final Transaction transaction;
  final int userId;

  const EditExchangePage({
    super.key,
    required this.db,
    required this.transaction,
    required this.userId,
  });

  @override
  State<EditExchangePage> createState() => _EditExchangePageState();
}

class _EditExchangePageState extends State<EditExchangePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountFromController;
  late final TextEditingController _amountToController;
  late final TextEditingController _exchangeRateController;

  int? _currencyFromId;
  int? _currencyToId;
  String _operation = "قص";
  List<Currency> _currencies = [];

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _amountFromController = TextEditingController(text: t.amount.toString());
    _amountToController = TextEditingController(
      text: t.targetAmount?.toString() ?? "",
    );
    _exchangeRateController = TextEditingController(
      text: t.exchangeRate?.toString() ?? "",
    );
    _currencyFromId = t.currencyId;
    _currencyToId = t.targetCurrencyId;
    _operation = t.operation ?? "قص";
    _amountFromController.addListener(_calculateAmountTo);
    _exchangeRateController.addListener(_calculateAmountTo);
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final list = await widget.db.getAllCurrencies();
    if (!mounted) return;
    setState(() => _currencies = list);
  }

  void _calculateAmountTo() {
    final amount = double.tryParse(_amountFromController.text);
    final rate = double.tryParse(_exchangeRateController.text);
    if (amount == null || rate == null || rate == 0) return;

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _currencyFromId == null ||
        _currencyToId == null ||
        _currencyFromId == _currencyToId) {
      _formKey.currentState?.validate();
      return;
    }

    final old = widget.transaction;
    final values = <String, String>{
      "العملة من": _currencyFromId.toString(),
      "العملة إلى": _currencyToId.toString(),
      "سعر الصرف": _exchangeRateController.text.trim(),
      "العملية": _operation,
      "المبلغ من": _amountFromController.text.trim(),
      "المبلغ إلى": _amountToController.text.trim(),
    };

    await widget.db.updateTransaction(
      old.id,
      TransactionsCompanion(
        currencyId: drift.Value(int.parse(values["العملة من"]!)),
        targetCurrencyId: drift.Value(int.parse(values["العملة إلى"]!)),
        exchangeRate: drift.Value(double.parse(values["سعر الصرف"]!)),
        operation: drift.Value(values["العملية"]!),
        amount: drift.Value(double.parse(values["المبلغ من"]!)),
        targetAmount: drift.Value(double.parse(values["المبلغ إلى"]!)),
        status: const drift.Value("تم التصريف"),
        movementState: const drift.Value("مفعلة"),
      ),
    );

    await _recordChanges(old, values);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _recordChanges(
    Transaction old,
    Map<String, String> values,
  ) async {
    final oldValues = {
      "العملة من": old.currencyId.toString(),
      "العملة إلى": old.targetCurrencyId?.toString() ?? "",
      "سعر الصرف": old.exchangeRate?.toString() ?? "",
      "العملية": old.operation ?? "",
      "المبلغ من": old.amount.toString(),
      "المبلغ إلى": old.targetAmount?.toString() ?? "",
    };

    for (final entry in values.entries) {
      if (entry.value == oldValues[entry.key]) continue;
      await widget.db.insertEdit(
        EditsCompanion.insert(
          transactionId: old.id,
          field: entry.key,
          oldValue: oldValues[entry.key] ?? "",
          newValue: entry.value,
          editedBy: drift.Value("user_${widget.userId}"),
        ),
      );
    }
  }

  @override
  void dispose() {
    _amountFromController.dispose();
    _amountToController.dispose();
    _exchangeRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تعديل حركة صرف")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              decoration: const InputDecoration(labelText: "سعر الصرف"),
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
              decoration: const InputDecoration(labelText: "العملية"),
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
              decoration: const InputDecoration(labelText: "المبلغ من"),
              validator: (value) =>
                  value == null || double.tryParse(value) == null
                  ? "مطلوب رقم صالح"
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountToController,
              enabled: false,
              decoration: const InputDecoration(labelText: "المبلغ إلى"),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text("تعديل"),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text("إلغاء"),
            ),
          ],
        ),
      ),
    );
  }
}
