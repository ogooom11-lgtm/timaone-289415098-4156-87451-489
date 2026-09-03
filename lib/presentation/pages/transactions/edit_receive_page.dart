import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_database.dart';

class EditReceivePage extends StatefulWidget {
  final AppDatabase db;
  final Transaction transaction;
  final int userId;

  const EditReceivePage({
    super.key,
    required this.db,
    required this.transaction,
    required this.userId,
  });

  @override
  State<EditReceivePage> createState() => _EditReceivePageState();
}

class _EditReceivePageState extends State<EditReceivePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _accountController;
  late final TextEditingController _amountController;
  int? _selectedCurrencyId;
  List<Currency> _currencies = [];

  @override
  void initState() {
    super.initState();
    _accountController = TextEditingController(
      text: widget.transaction.beneficiary ?? "",
    );
    _amountController = TextEditingController(
      text: widget.transaction.amount.toString(),
    );
    _selectedCurrencyId = widget.transaction.currencyId;
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final list = await widget.db.getAllCurrencies();
    if (!mounted) return;
    setState(() => _currencies = list);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _selectedCurrencyId == null) {
      return;
    }

    final old = widget.transaction;
    final changes = <String, String>{
      "اسم الحساب": _accountController.text.trim(),
      "المبلغ": _amountController.text.trim(),
      "العملة": _selectedCurrencyId.toString(),
    };

    await widget.db.updateTransaction(
      old.id,
      TransactionsCompanion(
        beneficiary: drift.Value(changes["اسم الحساب"]!),
        amount: drift.Value(double.parse(changes["المبلغ"]!)),
        currencyId: drift.Value(int.parse(changes["العملة"]!)),
        status: const drift.Value("قيد التسليم"),
      ),
    );

    await _recordChanges(old, changes);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _recordChanges(
    Transaction old,
    Map<String, String> changes,
  ) async {
    final oldValues = {
      "اسم الحساب": old.beneficiary ?? "",
      "المبلغ": old.amount.toString(),
      "العملة": old.currencyId.toString(),
    };

    for (final entry in changes.entries) {
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
    _accountController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تعديل حركة استلام")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _accountController,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[\u0600-\u06FFa-zA-Z0-9 ]'),
                ),
              ],
              decoration: const InputDecoration(labelText: "اسم الحساب"),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? "مطلوب" : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(labelText: "المبلغ"),
              validator: (value) =>
                  value == null || double.tryParse(value) == null
                  ? "مطلوب رقم صالح"
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
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
              onChanged: (value) => setState(() => _selectedCurrencyId = value),
              validator: (value) => value == null ? "مطلوب" : null,
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
