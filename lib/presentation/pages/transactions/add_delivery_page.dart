import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/printing/delivery_receipt.dart';
import '../../../core/services/app_sound.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/clipboard_text.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/receipt_print_dialog.dart';
import '../../widgets/clipboard_words_panel.dart';
import '../../widgets/denom_validator_dialog.dart';

/// أدنى عرض يُعرض عنده النموذج ولوحة الحافظة جنباً إلى جنب.
const double _kSplitBreakpoint = 1000;

class AddDeliveryPage extends StatefulWidget {
  final AppDatabase db;
  final User user;
  final Transaction? transaction;

  const AddDeliveryPage({
    super.key,
    required this.db,
    required this.user,
    this.transaction,
  });

  @override
  State<AddDeliveryPage> createState() => _AddDeliveryPageState();
}

class _AddDeliveryPageState extends State<AddDeliveryPage> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _beneficiaryController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  // حقول المبلغ والعملة الثانية الاختيارية
  final _amount2Controller = TextEditingController();
  int? _selectedCurrencyId2;
  bool _showSecondAmount = false;

  // خيار نوع الحركة: حركة تسليم (معلقة) أو حركة يوزر (منتهية فوراً بسالب)
  String _deliveryType = "حركة تسليم";

  int? _selectedCurrencyId;
  List<Currency> _currencies = [];

  /// النص المسحوب حالياً من لوحة الحافظة — يُبرز الحقول التي تقبله.
  final ValueNotifier<String?> _dragging = ValueNotifier<String?>(null);
  final ScrollController _formScroll = ScrollController();
  bool _validatedOnce = false;

  bool get _isEditMode => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    _loadCurrencies().then((_) {
      if (_isEditMode) {
        final tx = widget.transaction!;
        _beneficiaryController.text = tx.beneficiary ?? "";
        _amountController.text = tx.amount.toString();
        _noteController.text = tx.note ?? "";
        _selectedCurrencyId = tx.currencyId;
        _deliveryType = tx.type;
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

  Future<void> _showUserDeliverySuccess({
    required String beneficiary,
    required double amount,
    required String currency,
  }) {
    final message =
        'حركة يوزر\n$beneficiary\n${amount.toStringAsFixed(2)} $currency';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success),
            SizedBox(width: 8),
            Text('تمت الحركة بنجاح'),
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
            label: const Text('نسخ المعلومات'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }

  Future<void> _save({bool stay = false}) async {
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
      _validatedOnce = true;
      return;
    }

    final beneficiaryText = _beneficiaryController.text.trim();
    final amountVal = double.parse(_amountController.text.trim());
    final noteText = _noteController.text.trim();

    final amount2Val = _showSecondAmount && _amount2Controller.text.isNotEmpty
        ? double.tryParse(_amount2Controller.text.trim())
        : null;
    final currency2Val = _showSecondAmount ? _selectedCurrencyId2 : null;

    final currency1 = _currencies.firstWhere(
      (c) => c.id == _selectedCurrencyId,
    );
    String finalNote = noteText;

    // جرد وتفصيل فئات حركة يوزر (تُسلَّم فوراً)
    Map<double, int>? userCounts1;
    Map<double, int>? userCounts2;
    Currency? userCurrency2;
    if (_deliveryType == "حركة يوزر") {
      final stock1 = await CurrencyDenoms.loadStock(currency1);
      final counts1 = await showDialog<Map<double, int>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DenomValidatorDialog(
          targetAmount: amountVal,
          currency: currency1,
          title: "تفصيل فئات المبلغ المسلم (حركة يوزر)",
          mode: DenomDialogMode.outflow,
          availableStock: stock1,
        ),
      );
      if (counts1 == null) return; // تراجع المستخدم
      userCounts1 = counts1;

      if (_showSecondAmount && amount2Val != null && currency2Val != null) {
        userCurrency2 = _currencies.firstWhere((c) => c.id == currency2Val);
        final stock2 = await CurrencyDenoms.loadStock(userCurrency2);
        final counts2 = await showDialog<Map<double, int>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => DenomValidatorDialog(
            targetAmount: amount2Val,
            currency: userCurrency2!,
            title: "تفصيل فئات المبلغ المسلم الثاني (حركة يوزر)",
            mode: DenomDialogMode.outflow,
            availableStock: stock2,
          ),
        );
        if (counts2 == null) return; // تراجع المستخدم
        userCounts2 = counts2;
      }

      // بناء الملاحظة الموثقة للفئات المسلمة
      String denomStr =
          "[الفئات المسلمة لـ ${currency1.code}: ${_formatCounts(userCounts1)}]";
      if (userCounts2 != null && userCurrency2 != null) {
        denomStr +=
            "\n[الفئات المسلمة لـ ${userCurrency2.code}: ${_formatCounts(userCounts2)}]";
      }

      finalNote = noteText.isEmpty ? denomStr : "$noteText\n$denomStr";

      // خصم من مخزون الصندوق (حركة يوزر تُسلَّم فوراً)
      await CurrencyDenoms.deductStock(currency1, userCounts1);
      if (userCounts2 != null && userCurrency2 != null) {
        await CurrencyDenoms.deductStock(userCurrency2, userCounts2);
      }
    }

    final defaultStatus = _deliveryType == "حركة تسليم"
        ? "مضافة"
        : "تم التسليم";

    if (_isEditMode) {
      final oldTx = widget.transaction!;
      final newValues = {
        "beneficiary": beneficiaryText,
        "amount": amountVal.toString(),
        "currencyId": _selectedCurrencyId!.toString(),
        "type": _deliveryType,
        "targetAmount": amount2Val?.toString() ?? "",
        "targetCurrencyId": currency2Val?.toString() ?? "",
        "note": finalNote,
      };

      await widget.db.updateTransaction(
        oldTx.id,
        TransactionsCompanion(
          beneficiary: drift.Value(beneficiaryText),
          amount: drift.Value(amountVal),
          currencyId: drift.Value(_selectedCurrencyId!),
          type: drift.Value(_deliveryType),
          targetAmount: drift.Value(amount2Val),
          targetCurrencyId: drift.Value(currency2Val),
          note: finalNote.isNotEmpty
              ? drift.Value(finalNote)
              : const drift.Value(null),
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
          case "type":
            oldValue = oldTx.type;
            break;
          case "targetAmount":
            oldValue = oldTx.targetAmount?.toString() ?? "";
            break;
          case "targetCurrencyId":
            oldValue = oldTx.targetCurrencyId?.toString() ?? "";
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
      final newId = await widget.db.insertTransaction(
        TransactionsCompanion.insert(
          userId: widget.user.id,
          currencyId: _selectedCurrencyId!,
          targetCurrencyId: drift.Value(currency2Val),
          targetAmount: drift.Value(amount2Val),
          createdByName: drift.Value(widget.user.username),
          type: _deliveryType,
          beneficiary: drift.Value(beneficiaryText),
          amount: amountVal,
          note: finalNote.isEmpty
              ? const drift.Value.absent()
              : drift.Value(finalNote),
          movementState: const drift.Value("مفعلة"),
          status: drift.Value(defaultStatus),
        ),
      );

      if (!mounted) return;

      // طباعة إيصال عند حركة يوزر (تسليم فوري)
      if (_deliveryType == "حركة يوزر" && userCounts1 != null) {
        final receipt = DeliveryReceiptData(
          beneficiary: beneficiaryText,
          amount: amountVal,
          currencyCode: currency1.code,
          currencyName: CurrencyDenoms.displayName(currency1),
          amount2: amount2Val,
          currencyCode2: userCurrency2?.code,
          currencyName2: userCurrency2 == null
              ? null
              : CurrencyDenoms.displayName(userCurrency2),
          denoms1: userCounts1,
          denoms2: userCounts2,
          status: "تم التسليم",
          dateTime: DateTime.now(),
          note: noteText,
          createdBy: widget.user.username,
          branch: widget.user.branch,
          transactionId: newId,
        );
        await offerReceiptPrintAfterDelivery(context, receipt);
        if (!mounted) return;
        await _showUserDeliverySuccess(
          beneficiary: beneficiaryText,
          amount: amountVal,
          currency: currency1.code,
        );
      }

      if (!mounted) return;
      if (stay) {
        _beneficiaryController.clear();
        _amountController.clear();
        _amount2Controller.clear();
        _noteController.clear();
        setState(() {
          _selectedCurrencyId = null;
          _selectedCurrencyId2 = null;
          _showSecondAmount = false;
        });
        AppSound.play(TimaSound.success);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تم الحفظ بنجاح وتجهيز واجهة جديدة")),
        );
      } else {
        AppSound.play(TimaSound.success);
        Navigator.pop(context, true);
      }
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _beneficiaryController.dispose();
    _amountController.dispose();
    _amount2Controller.dispose();
    _noteController.dispose();
    _dragging.dispose();
    _formScroll.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // لوحة نص الحافظة — تعبئة الحقول بالسحب والإفلات
  // -------------------------------------------------------------------

  /// إن كان النص يحمل عملة معروفة وموجودة في الصندوق، تُختار تلقائياً.
  int? _currencyIdFromText(String text) {
    final code = ClipboardText.detectCurrencyCode(
      text,
      knownCodes: _currencies.map((c) => c.code),
    );
    if (code == null) return null;
    for (final currency in _currencies) {
      if (currency.code.toUpperCase() == code.toUpperCase()) return currency.id;
    }
    return null;
  }

  /// بعد أول محاولة حفظ فاشلة تُعاد المصادقة عقب كل إفلات، حتى تختفي
  /// رسائل «هذا الحقل مطلوب» فور تعبئة الحقل من اللوحة.
  void _afterDrop() {
    if (_validatedOnce) _formKey.currentState?.validate();
  }

  bool _dropBeneficiary(String text) {
    final cleaned = ClipboardText.cleanForName(text);
    if (cleaned.isEmpty) return false;
    final current = _beneficiaryController.text.trim();
    // الكلمة موجودة أصلاً في الاسم؟ لا نكرّرها.
    if (current.split(' ').contains(cleaned)) return true;
    // إفلات كلمة ثانية يُكمل الاسم بدل استبداله (اسم من عدة كلمات).
    final next = current.isEmpty ? cleaned : '$current $cleaned';
    _beneficiaryController
      ..text = next
      ..selection = TextSelection.collapsed(offset: next.length);
    _afterDrop();
    return true;
  }

  bool _dropAmount(String text, {required bool second}) {
    final number = ClipboardText.extractNumber(text);
    if (number == null) return false;
    final controller = second ? _amount2Controller : _amountController;
    controller
      ..text = number
      ..selection = TextSelection.collapsed(offset: number.length);

    // «500 دولار» تعبّئ المبلغ وتختار العملة معاً.
    final currencyId = _currencyIdFromText(text);
    setState(() {
      if (second) {
        _showSecondAmount = true;
        if (currencyId != null) _selectedCurrencyId2 = currencyId;
      } else if (currencyId != null) {
        _selectedCurrencyId = currencyId;
      }
    });
    _afterDrop();
    return true;
  }

  bool _dropCurrency(String text, {required bool second}) {
    final currencyId = _currencyIdFromText(text);
    if (currencyId == null) return false;
    setState(() {
      if (second) {
        _showSecondAmount = true;
        _selectedCurrencyId2 = currencyId;
      } else {
        _selectedCurrencyId = currencyId;
      }
    });
    _afterDrop();
    return true;
  }

  bool _dropNote(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return false;
    final current = _noteController.text.trimRight();
    final next = current.isEmpty ? cleaned : '$current $cleaned';
    _noteController
      ..text = next
      ..selection = TextSelection.collapsed(offset: next.length);
    return true;
  }

  /// نقر مزدوج على كلمة في اللوحة: تعبئة ذكية حسب نوعها.
  /// رقم → المبلغ الأول، عملة → العملة الأولى، وغير ذلك → يُضاف إلى الاسم.
  /// (المبلغ والعملة الثانيان يُعبّآن بالسحب فقط حتى لا تحدث مفاجآت.)
  bool _quickAssign(String text) {
    if (ClipboardText.extractNumber(text) != null) {
      return _dropAmount(text, second: false);
    }
    final code = ClipboardText.detectCurrencyCode(
      text,
      knownCodes: _currencies.map((c) => c.code),
    );
    if (code != null) {
      if (_dropCurrency(text, second: false)) return true;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('العملة $code غير مضافة في الصندوق.')),
        );
      return false;
    }
    return _dropBeneficiary(text);
  }

  /// نفس أهداف الإفلات كأزرار سريعة في شريط التحديد داخل اللوحة.
  List<ClipboardAssignTarget> get _assignTargets => [
    ClipboardAssignTarget(
      label: 'الاسم',
      icon: Icons.person_outline_rounded,
      onAssign: _dropBeneficiary,
    ),
    ClipboardAssignTarget(
      label: 'المبلغ',
      icon: Icons.payments_outlined,
      onAssign: (text) => _dropAmount(text, second: false),
    ),
    ClipboardAssignTarget(
      label: 'الملاحظات',
      icon: Icons.note_alt_outlined,
      onAssign: _dropNote,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: _isEditMode
            ? "تعديل حركة التسليم/يوزر"
            : "تسجيل حركة تسليم / يوزر",
      ),
      body: TimaPageBackground(
        child: ClipboardDragScope(
          notifier: _dragging,
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // اللوحة الجانبية تظهر بجانب النموذج عند توفر العرض،
                // وفوقه على الشاشات الضيقة.
                final sideBySide = constraints.maxWidth >= _kSplitBreakpoint;
                final panel = SizedBox(
                  width: sideBySide ? AppDims.sidePanelWidth : null,
                  height: sideBySide ? null : 280,
                  child: ClipboardWordsPanel(
                    targets: _assignTargets,
                    onQuickAssign: _quickAssign,
                  ),
                );

                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildFormScroller()),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: AppDims.pagePadding,
                          top: 18,
                          bottom: 18,
                        ),
                        child: panel,
                      ),
                    ],
                  );
                }

                return _buildFormScroller(leading: panel);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// [leading] هي لوحة الحافظة في التخطيط الضيق — تُعرض فوق النموذج
  /// حتى تبقى قريبة من حقلي الاسم والمبلغ.
  Widget _buildFormScroller({Widget? leading}) {
    return Scrollbar(
      controller: _formScroll,
      child: ListView(
        controller: _formScroll,
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
                if (leading != null) ...[
                  leading,
                  const SizedBox(height: AppDims.sectionGap),
                ],
                _buildFormBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TimaHeaderPanel(
          icon: Icons.outbox_rounded,
          title: "أمانة تسليم نقدية أو حركة يوزر",
          subtitle:
              "حركة التسليم تسجل بسالب وتدخل في المعلقة، بينما حركة يوزر تُسلَّم فوراً مع جرد فئاتها.",
        ),
        const SizedBox(height: 20),

        // Select Delivery or User movement type
        if (!_isEditMode) ...[
          const Text(
            "نوع الحركة المالية المطلوب تسجيلها:",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.neutral500,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: "حركة تسليم",
                icon: Icon(Icons.hourglass_empty_rounded),
                label: Text("حركة تسليم (معلقة)"),
              ),
              ButtonSegment(
                value: "حركة يوزر",
                icon: Icon(Icons.check_circle_rounded),
                label: Text("حركة يوزر (مكتملة فوراً)"),
              ),
            ],
            selected: {_deliveryType},
            onSelectionChanged: (value) {
              setState(() => _deliveryType = value.first);
            },
          ),
          const SizedBox(height: 20),
        ],

        // Input Fields Card
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
                // Date (Disabled)
                TextFormField(
                  controller: _dateController,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: "تاريخ الحركة اليوم",
                    prefixIcon: const Icon(
                      Icons.calendar_today_rounded,
                      color: AppColors.brandGold,
                    ),
                    fillColor: isDark
                        ? AppColors.darkBackground
                        : AppColors.neutral500.withValues(alpha: 0.04),
                  ),
                ),
                const SizedBox(height: 16),

                // Beneficiary Name
                ClipboardDropTarget(
                  hint: 'الاسم',
                  onDrop: _dropBeneficiary,
                  child: TextFormField(
                    controller: _beneficiaryController,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[\u0600-\u06FFa-zA-Z0-9 ]'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: _deliveryType == "حركة تسليم"
                          ? "اسم المستفيد بالكامل"
                          : "اسم المستخدم (اليوزر)",
                      prefixIcon: const Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.brandGold,
                      ),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                        ? "هذا الحقل مطلوب"
                        : null,
                  ),
                ),
                const SizedBox(height: 16),

                // Amount 1 and Currency 1 Row
                const Text(
                  "المبلغ الأول (الرئيسي):",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.neutral500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: ClipboardDropTarget(
                        hint: 'المبلغ 1',
                        canAccept: (text) =>
                            ClipboardText.extractNumber(text) != null,
                        rejectHint: 'لا يحتوي رقماً',
                        onDrop: (text) => _dropAmount(text, second: false),
                        child: TextFormField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: "المبلغ 1",
                            prefixIcon: Icon(
                              Icons.payments_outlined,
                              color: AppColors.brandGold,
                            ),
                          ),
                          validator: (value) =>
                              value == null ||
                                  value.trim().isEmpty ||
                                  double.tryParse(value) == null
                              ? "رقم صالح مطلوب"
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipboardDropTarget(
                        hint: 'العملة 1',
                        canAccept: (text) => _currencyIdFromText(text) != null,
                        rejectHint: 'عملة غير معروفة',
                        onDrop: (text) => _dropCurrency(text, second: false),
                        child: DropdownButtonFormField<int>(
                          value: _selectedCurrencyId,
                          decoration: const InputDecoration(
                            labelText: "العملة 1",
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
                              setState(() => _selectedCurrencyId = value),
                          validator: (value) =>
                              value == null ? "مطلوب" : null,
                        ),
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                if (_showSecondAmount) ...[
                  const SizedBox(height: 8),
                  const Text(
                    "المبلغ الثاني (الفرعي):",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.neutral500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: ClipboardDropTarget(
                          hint: 'المبلغ 2',
                          canAccept: (text) =>
                              ClipboardText.extractNumber(text) != null,
                          rejectHint: 'لا يحتوي رقماً',
                          onDrop: (text) => _dropAmount(text, second: true),
                          child: TextFormField(
                            controller: _amount2Controller,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
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
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipboardDropTarget(
                          hint: 'العملة 2',
                          canAccept: (text) =>
                              _currencyIdFromText(text) != null,
                          rejectHint: 'عملة غير معروفة',
                          onDrop: (text) => _dropCurrency(text, second: true),
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
                                _showSecondAmount && value == null
                                ? "مطلوب"
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Notes
                ClipboardDropTarget(
                  hint: 'الملاحظات',
                  onDrop: _dropNote,
                  child: TextFormField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: "ملاحظات وتفاصيل الحركة",
                      prefixIcon: Icon(
                        Icons.note_alt_outlined,
                        color: AppColors.brandGold,
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Action Buttons
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
                  onPressed: () => _save(),
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
          Column(
            children: [
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDims.radiusSm),
                    ),
                  ),
                  onPressed: () => _save(stay: true),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text(
                    "حفظ الحركة وتجهيز حركة جديدة",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
