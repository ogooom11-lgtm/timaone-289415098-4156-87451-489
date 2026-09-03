import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' as drift;
import '../../../core/storage/app_database.dart';

class EditDeliveryPage extends StatefulWidget {
  final AppDatabase db;
  final Transaction transaction;
  final int userId;

  const EditDeliveryPage({
    super.key,
    required this.db,
    required this.transaction,
    required this.userId,
  });

  @override
  State<EditDeliveryPage> createState() => _EditDeliveryPageState();
}

class _EditDeliveryPageState extends State<EditDeliveryPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _beneficiaryController;
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  int? _selectedCurrencyId;
  List<Currency> _currencies = [];

  @override
  void initState() {
    super.initState();
    _beneficiaryController = TextEditingController(
      text: widget.transaction.beneficiary ?? "",
    );
    _amountController = TextEditingController(
      text: widget.transaction.amount.toString(),
    );
    _noteController = TextEditingController(
      text: widget.transaction.note ?? "",
    );
    _selectedCurrencyId = widget.transaction.currencyId;
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final list = await widget.db.getAllCurrencies();
    setState(() => _currencies = list);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _selectedCurrencyId == null) {
      return;
    }

    final oldTx = widget.transaction;
    final newValues = {
      "beneficiary": _beneficiaryController.text.trim(),
      "amount": _amountController.text.trim(),
      "currencyId": _selectedCurrencyId.toString(),
      "note": _noteController.text.trim(),
    };

    // تحديث الجدول
    await widget.db.updateTransaction(
      oldTx.id,
      TransactionsCompanion(
        beneficiary: drift.Value(newValues["beneficiary"]!),
        amount: drift.Value(double.parse(newValues["amount"]!)),
        currencyId: drift.Value(int.parse(newValues["currencyId"]!)),
        note: newValues["note"]!.isNotEmpty
            ? drift.Value(newValues["note"]!)
            : const drift.Value.absent(),
      ),
    );

    // تسجيل التغييرات
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
            editedBy: drift.Value("user_${widget.userId}"),
          ),
        );
      }
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _beneficiaryController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("✏️ تعديل حركة تسليم")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _beneficiaryController,
                decoration: const InputDecoration(
                  labelText: "اسم المستفيد",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? "مطلوب" : null,
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
                decoration: const InputDecoration(
                  labelText: "المبلغ",
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || double.tryParse(v) == null
                    ? "مطلوب رقم صالح"
                    : null,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<int>(
                value: _selectedCurrencyId,
                decoration: const InputDecoration(
                  labelText: "العملة",
                  border: OutlineInputBorder(),
                ),
                items: _currencies
                    .map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.code)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedCurrencyId = val),
                validator: (v) => v == null ? "مطلوب" : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "ملاحظة (اختياري)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _save,
                child: const Text("💾 حفظ التغييرات"),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("❌ إلغاء"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
