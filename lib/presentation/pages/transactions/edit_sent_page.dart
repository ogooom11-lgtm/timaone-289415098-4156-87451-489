import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_database.dart';

class EditSentPage extends StatefulWidget {
  final AppDatabase db;
  final Transaction transaction;
  final int userId;

  const EditSentPage({
    super.key,
    required this.db,
    required this.transaction,
    required this.userId,
  });

  @override
  State<EditSentPage> createState() => _EditSentPageState();
}

class _EditSentPageState extends State<EditSentPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _beneficiaryController;
  late final TextEditingController _receivedAmountController;
  late final TextEditingController _sentAmountController;
  late final TextEditingController _exchangeRateController;
  late final TextEditingController _feesController;

  int? _receivedCurrencyId;
  int? _sentCurrencyId;
  int? _feesCurrencyId;
  String _operation = "قص";
  List<Currency> _currencies = [];

  bool get _needsExchange =>
      _receivedCurrencyId != null &&
      _sentCurrencyId != null &&
      _receivedCurrencyId != _sentCurrencyId;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _beneficiaryController = TextEditingController(text: t.beneficiary ?? "");
    _receivedAmountController = TextEditingController(
      text: t.amount.toString(),
    );
    _sentAmountController = TextEditingController(
      text: t.targetAmount?.toString() ?? "",
    );
    _exchangeRateController = TextEditingController(
      text: t.exchangeRate?.toString() ?? "",
    );
    _feesController = TextEditingController(text: t.fees?.toString() ?? "");
    _receivedCurrencyId = t.currencyId;
    _sentCurrencyId = t.targetCurrencyId;
    _feesCurrencyId = t.feesCurrencyId;
    _operation = t.operation ?? "قص";
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final list = await widget.db.getAllCurrencies();
    if (!mounted) return;
    setState(() => _currencies = list);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _receivedCurrencyId == null ||
        _sentCurrencyId == null ||
        _feesCurrencyId == null) {
      _formKey.currentState?.validate();
      return;
    }

    final old = widget.transaction;
    final values = <String, String>{
      "اسم المستفيد": _beneficiaryController.text.trim(),
      "المبلغ المستلم": _receivedAmountController.text.trim(),
      "عملة المبلغ المستلم": _receivedCurrencyId.toString(),
      "المبلغ المرسل": _sentAmountController.text.trim(),
      "عملة المبلغ المرسل": _sentCurrencyId.toString(),
      "أجور الحركة": _feesController.text.trim(),
      "عملة الأجور": _feesCurrencyId.toString(),
      "سعر الصرف": _needsExchange ? _exchangeRateController.text.trim() : "",
      "العملية": _needsExchange ? _operation : "",
    };

    await widget.db.updateTransaction(
      old.id,
      TransactionsCompanion(
        beneficiary: drift.Value(values["اسم المستفيد"]!),
        amount: drift.Value(double.parse(values["المبلغ المستلم"]!)),
        currencyId: drift.Value(int.parse(values["عملة المبلغ المستلم"]!)),
        targetAmount: drift.Value(double.parse(values["المبلغ المرسل"]!)),
        targetCurrencyId: drift.Value(int.parse(values["عملة المبلغ المرسل"]!)),
        fees: drift.Value(double.parse(values["أجور الحركة"]!)),
        feesCurrencyId: drift.Value(int.parse(values["عملة الأجور"]!)),
        exchangeRate: values["سعر الصرف"]!.isEmpty
            ? const drift.Value.absent()
            : drift.Value(double.parse(values["سعر الصرف"]!)),
        operation: values["العملية"]!.isEmpty
            ? const drift.Value.absent()
            : drift.Value(values["العملية"]!),
        status: const drift.Value("قيد التسليم"),
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
      "اسم المستفيد": old.beneficiary ?? "",
      "المبلغ المستلم": old.amount.toString(),
      "عملة المبلغ المستلم": old.currencyId.toString(),
      "المبلغ المرسل": old.targetAmount?.toString() ?? "",
      "عملة المبلغ المرسل": old.targetCurrencyId?.toString() ?? "",
      "أجور الحركة": old.fees?.toString() ?? "",
      "عملة الأجور": old.feesCurrencyId?.toString() ?? "",
      "سعر الصرف": old.exchangeRate?.toString() ?? "",
      "العملية": old.operation ?? "",
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
    _beneficiaryController.dispose();
    _receivedAmountController.dispose();
    _sentAmountController.dispose();
    _exchangeRateController.dispose();
    _feesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تعديل حركة مرسلة")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _beneficiaryController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[\u0600-\u06FFa-zA-Z0-9 ]'),
                ),
              ],
              decoration: const InputDecoration(labelText: "اسم المستفيد"),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? "مطلوب" : null,
            ),
            const SizedBox(height: 12),
            _amountCurrencyRow(
              amountController: _receivedAmountController,
              amountLabel: "المبلغ المستلم",
              selectedCurrencyId: _receivedCurrencyId,
              onCurrencyChanged: (value) =>
                  setState(() => _receivedCurrencyId = value),
            ),
            const SizedBox(height: 12),
            if (_needsExchange) ...[
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
                onChanged: (value) =>
                    setState(() => _operation = value ?? "قص"),
              ),
              const SizedBox(height: 12),
            ],
            _amountCurrencyRow(
              amountController: _sentAmountController,
              amountLabel: "المبلغ المرسل",
              selectedCurrencyId: _sentCurrencyId,
              onCurrencyChanged: (value) =>
                  setState(() => _sentCurrencyId = value),
            ),
            const SizedBox(height: 12),
            _amountCurrencyRow(
              amountController: _feesController,
              amountLabel: "أجور الحركة",
              selectedCurrencyId: _feesCurrencyId,
              onCurrencyChanged: (value) =>
                  setState(() => _feesCurrencyId = value),
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
            decoration: InputDecoration(labelText: amountLabel),
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
                    child: Text(currency.code),
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
