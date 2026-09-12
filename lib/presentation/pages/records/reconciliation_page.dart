import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/device_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';

class ReconciliationPage extends StatefulWidget {
  final AppDatabase db;
  final User user;

  const ReconciliationPage({super.key, required this.db, required this.user});

  @override
  State<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _ReconciliationPageState extends State<ReconciliationPage> {
  bool _loading = true;
  DateTime _lastMatchDate = DateTime(1970);
  Map<String, dynamic> _lastMatchBalances = {};
  String _lastMatchBy = "غير مطابَق بعد";

  // المخازن الأصلية الكاملة للبيانات
  List<Transaction> _allTransactions = [];
  List<Map<String, dynamic>> _allEdits = [];

  // المخازن المفلترة التي سيتم عرضها
  List<Transaction> _filteredTransactions = [];
  List<Map<String, dynamic>> _filteredEdits = [];

  Map<int, Currency> _currencies = {};
  Map<int, Transaction> _allTxMap = {};
  List<Map<String, dynamic>> _matchHistory = [];
  Set<int> _selectedTransactionIds = <int>{};

  // إعدادات الفلترة الجديدة المطلوبة
  String _filterMode = "toNow"; // "toNow", "toLastMatch", "customRange"
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    // 1. تحميل تاريخ المطابقات السابقة
    final history = await DeviceSettings.getReconciliations();
    DateTime lastDate = DateTime(1970);
    Map<String, dynamic> lastBalances = {};
    String lastBy = "النظام (بداية التشغيل)";

    if (history.isNotEmpty) {
      final last = history.last;
      lastDate = DateTime.parse(last['dateTime']);
      lastBalances = Map<String, dynamic>.from(last['balances'] ?? {});
      lastBy = last['matchedBy'] ?? "غير معروف";
    }

    // 2. تحميل العملات والحركات من الداتابيز
    final currenciesList = await widget.db.getAllCurrencies();
    final allTransactions = await widget.db.getAllTransactions();
    final selection = await DeviceSettings.reconciliationSelection();

    _currencies = {for (final c in currenciesList) c.id: c};
    _allTxMap = {for (final t in allTransactions) t.id: t};
    _allTransactions = allTransactions;

    // 3. تحميل كافة التعديلات التاريخية
    final List<Map<String, dynamic>> allEditsList = [];
    try {
      final rawEdits = await widget.db
          .customSelect('SELECT * FROM edits ORDER BY edited_at DESC')
          .get();
      for (final row in rawEdits) {
        final txId = row.read<int>('transaction_id');
        final field = row.read<String>('field');
        final oldValue = row.read<String>('old_value');
        final newValue = row.read<String>('new_value');

        final rawDate = row.data['edited_at'];
        DateTime editedAt = DateTime.now();
        if (rawDate is int) {
          editedAt = DateTime.fromMillisecondsSinceEpoch(rawDate * 1000);
        } else if (rawDate is String) {
          editedAt = DateTime.parse(rawDate);
        }

        final editedBy = row.read<String>('edited_by');

        allEditsList.add({
          'txId': txId,
          'field': field,
          'oldValue': oldValue,
          'newValue': newValue,
          'editedAt': editedAt,
          'editedBy': editedBy,
        });
      }
    } catch (e) {
      debugPrint("Error loading edits: $e");
    }

    _allEdits = allEditsList;

    if (!mounted) return;
    setState(() {
      _lastMatchDate = lastDate;
      _lastMatchBalances = lastBalances;
      _lastMatchBy = lastBy;
      _matchHistory = history.reversed.toList(); // عرض الأحدث أولاً
      _selectedTransactionIds = selection;

      // تطبيق الفلترة لأول مرة
      _applyDateFilters();
      _loading = false;
    });
  }

  Future<void> _toggleTransactionSelection(int id, bool selected) async {
    setState(() {
      if (selected) {
        _selectedTransactionIds.add(id);
      } else {
        _selectedTransactionIds.remove(id);
      }
    });
    await DeviceSettings.saveReconciliationSelection(_selectedTransactionIds);
  }

  Future<void> _clearTransactionSelection() async {
    await DeviceSettings.clearReconciliationSelection();
    if (mounted) setState(() => _selectedTransactionIds.clear());
  }

  // دالة مخصصة لترجمة الأيام للعربية يدوياً
  String _formatArabicDate(DateTime date) {
    final ymd = DateFormat('yyyy-MM-dd').format(date);
    final weekdayEng = DateFormat('EEEE').format(date);
    final Map<String, String> weekdaysAr = {
      'Monday': 'الاثنين',
      'Tuesday': 'الثلاثاء',
      'Wednesday': 'الأربعاء',
      'Thursday': 'الخميس',
      'Friday': 'الجمعة',
      'Saturday': 'السبت',
      'Sunday': 'الأحد',
    };
    final arDay = weekdaysAr[weekdayEng] ?? weekdayEng;
    return "$ymd ($arDay)";
  }

  // تصفية وفرز الحركات والتعديلات بناءً على الخيارات والتواريخ المحددة
  void _applyDateFilters() {
    DateTime start;
    DateTime end;

    if (_filterMode == "toNow") {
      start = _lastMatchDate;
      end = DateTime.now();
    } else if (_filterMode == "toLastMatch") {
      start = _startDate;
      end = _lastMatchDate;
    } else {
      // customRange (بين تاريخين مخصصين)
      start = _startDate;
      end = _endDate;
    }

    // لضمان شمول كامل اليوم من البداية للنهاية
    final filterStart = DateTime(start.year, start.month, start.day, 0, 0, 0);
    final filterEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);

    _filteredTransactions = _allTransactions.where((t) {
      return t.createdAt.isAfter(filterStart) &&
          t.createdAt.isBefore(filterEnd);
    }).toList();

    _filteredEdits = _allEdits.where((e) {
      final DateTime editDate = e['editedAt'];
      return editDate.isAfter(filterStart) && editDate.isBefore(filterEnd);
    }).toList();
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _startDate = date;
        _applyDateFilters();
      });
    }
  }

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _endDate = date;
        _applyDateFilters();
      });
    }
  }

  // حساب الأرصدة الحالية للصندوق بالكامل
  Future<Map<String, double>> _calculateCurrentBalances() async {
    final currencies = await widget.db.getAllCurrencies();
    final transactions = await widget.db.getAllTransactions();
    final Map<String, double> currentBalances = {};

    for (final c in currencies) {
      currentBalances[c.code] = 0.0;
    }

    for (final tx in transactions) {
      if (tx.movementState == "ملغية" ||
          tx.status == "الغاء" ||
          tx.status == "ملغية") {
        continue;
      }

      final currency = _currencies[tx.currencyId];
      if (currency == null) continue;

      final type = tx.type;

      // 1. حركة تسليم
      if (type == "حركة تسليم" || type.contains("تسليم")) {
        if (tx.status == "تم التسليم") {
          currentBalances[currency.code] =
              (currentBalances[currency.code] ?? 0.0) - tx.amount;
        }
      }
      // 2. حركة استلام
      else if (type == "حركة استلام" || type.contains("استلام")) {
        currentBalances[currency.code] =
            (currentBalances[currency.code] ?? 0.0) + tx.amount;
      }
      // 3. حركة مرسلة
      else if (type == "حركة مرسلة" || type.contains("مرسلة")) {
        currentBalances[currency.code] =
            (currentBalances[currency.code] ?? 0.0) + tx.amount;
        if (tx.targetCurrencyId != null && tx.targetAmount != null) {
          final targetCurrency = _currencies[tx.targetCurrencyId!];
          if (targetCurrency != null) {
            currentBalances[targetCurrency.code] =
                (currentBalances[targetCurrency.code] ?? 0.0) -
                tx.targetAmount!;
          }
        }
        if (tx.feesCurrencyId != null && tx.fees != null) {
          final feesCurrency = _currencies[tx.feesCurrencyId!];
          if (feesCurrency != null) {
            currentBalances[feesCurrency.code] =
                (currentBalances[feesCurrency.code] ?? 0.0) + tx.fees!;
          }
        }
      }
      // 4. حركة تسوية (صرف)
      else if (type == "حركة تسوية" || type.contains("صرف")) {
        currentBalances[currency.code] =
            (currentBalances[currency.code] ?? 0.0) - tx.amount;
        if (tx.targetCurrencyId != null && tx.targetAmount != null) {
          final targetCurrency = _currencies[tx.targetCurrencyId!];
          if (targetCurrency != null) {
            currentBalances[targetCurrency.code] =
                (currentBalances[targetCurrency.code] ?? 0.0) +
                tx.targetAmount!;
          }
        }
      }
      // 5. حركة يوزر
      else if (type == "حركة يوزر" || type.contains("يوزر")) {
        currentBalances[currency.code] =
            (currentBalances[currency.code] ?? 0.0) - tx.amount;
      }
    }

    return currentBalances;
  }

  Future<void> _confirmMatching() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_user_rounded, color: AppColors.success),
            SizedBox(width: 8),
            Text("تأكيد مطابقة الرصيد والمسؤول"),
          ],
        ),
        content: Text(
          "هل أنت متأكد من مطابقة الأرصدة الآن؟ سيتم تسجيل اسمك كمستخدم مطابق [${widget.user.username}] وحفظ الأرصدة الحالية كمطابقة جديدة وتصفير كشف الحركات الجديدة.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("تأكيد ومطابقة"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _loading = true);

      // حساب الأرصدة الحالية
      final currentBalances = await _calculateCurrentBalances();

      // بناء سجل المطابقة الجديد وتوثيق اسم المستخدم المطابق بدقة
      final newMatch = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'dateTime': DateTime.now().toIso8601String(),
        'matchedBy': widget.user.username, // حفظ اسم المستخدم بدقة
        'balances': currentBalances,
        'selectedTransactionIds': _selectedTransactionIds.toList(),
      };

      final history = await DeviceSettings.getReconciliations();
      history.add(newMatch);
      await DeviceSettings.saveReconciliations(history);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✓ تم توثيق مطابقة الرصيد بنجاح بواسطة المستخدم المطابق: [${widget.user.username}]",
          ),
          backgroundColor: AppColors.success,
        ),
      );

      await _loadData();
    }
  }

  String _formatDateStr(String isoString) {
    return DateFormat(
      "yyyy-MM-dd HH:mm",
    ).format(DateTime.parse(isoString).toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: "جرد ومطابقة وإغلاق الأرصدة",
        actions: [
          if (_selectedTransactionIds.isNotEmpty)
            TextButton.icon(
              onPressed: _clearTransactionSelection,
              icon: const Icon(Icons.undo_rounded),
              label: Text(
                'تراجع عن التحديد (${_selectedTransactionIds.length})',
              ),
            ),
        ],
      ),
      body: TimaPageBackground(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const TimaHeaderPanel(
                  icon: Icons.fact_check_rounded,
                  title: 'مطابقة وإغلاق الصندوق',
                  subtitle: 'راجع الحركات ثم وثّق الأرصدة الحالية كمطابقة معتمدة.',
                ),
                const SizedBox(height: 16),
                // Section: last matched state banner
                Card(
                  color: isDark
                      ? AppColors.darkSecondaryBackground
                      : AppColors.lightSecondaryBackground,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDims.radius),
                    side: BorderSide(color: AppUi.border(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_rounded,
                              color: AppColors.success,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "حالة المطابقة السابقة والمعتمدة",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "تاريخ آخر مطابقة:",
                              style: TextStyle(
                                color: AppColors.neutral500,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _lastMatchDate == DateTime(1970)
                                  ? "لم تجر أي مطابقة بعد"
                                  : _formatArabicDate(_lastMatchDate),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "المسؤول المطابق السابق:",
                              style: TextStyle(
                                color: AppColors.neutral500,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _lastMatchBy,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.brandGoldDark,
                              ),
                            ),
                          ],
                        ),
                        if (_lastMatchBalances.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            "الأرصدة المغلقة عند آخر مطابقة:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: AppColors.neutral500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: _lastMatchBalances.entries.map((e) {
                              return Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: AppColors.brandGold
                                    .withValues(alpha: 0.08),
                                label: Text(
                                  "${e.key}: ${e.value.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // FILTRATION OPTIONS CARD (جديد وبمنتهى الجودة!)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDims.radius),
                    side: BorderSide(color: AppUi.border(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.date_range_rounded,
                              color: AppColors.brandGold,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              "خيارات تصفية وعرض حركات المطابقة",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _filterMode,
                          decoration: const InputDecoration(
                            labelText: "تحديد فترة العرض",
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: "toNow",
                              child: Text("من آخر مطابقة للآن"),
                            ),
                            DropdownMenuItem(
                              value: "toLastMatch",
                              child: Text("من تاريخ مخصص لآخر مطابقة"),
                            ),
                            DropdownMenuItem(
                              value: "customRange",
                              child: Text("بين تاريخين مخصصين"),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _filterMode = value ?? "toNow";
                              _applyDateFilters();
                            });
                          },
                        ),

                        if (_filterMode != "toNow") ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _pickStartDate,
                                  icon: const Icon(Icons.event),
                                  label: Text(
                                    "البداية: ${DateFormat('yyyy-MM-dd').format(_startDate)}",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              if (_filterMode == "customRange") ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _pickEndDate,
                                    icon: const Icon(Icons.event),
                                    label: Text(
                                      "النهاية: ${DateFormat('yyyy-MM-dd').format(_endDate)}",
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // SECTION: New Executed Transactions
                Row(
                  children: [
                    const Icon(
                      Icons.playlist_add_check_rounded,
                      color: AppColors.brandGold,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "الحركات المالية المنفذة في الفترة المحددة (${_filteredTransactions.length})",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_filteredTransactions.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          "لا توجد حركات مسجلة في الفترة المحددة",
                          style: TextStyle(fontSize: 12, color: AppColors.neutral500),
                        ),
                      ),
                    ),
                  )
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filteredTransactions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final tx = _filteredTransactions[index];
                        final code = _currencies[tx.currencyId]?.code ?? "";
                        return ListTile(
                          dense: true,
                          leading: Checkbox(
                            value: _selectedTransactionIds.contains(tx.id),
                            onChanged: (value) => _toggleTransactionSelection(
                              tx.id,
                              value ?? false,
                            ),
                          ),
                          title: Text(
                            tx.beneficiary ?? tx.type,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "النوع: ${tx.type} • وقت القيد: ${DateFormat('MM-dd HH:mm').format(tx.createdAt.toLocal())}",
                          ),
                          trailing: Text(
                            "${tx.amount} $code",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          onTap: () => _toggleTransactionSelection(
                            tx.id,
                            !_selectedTransactionIds.contains(tx.id),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 20),

                // SECTION: New edits
                Row(
                  children: [
                    const Icon(
                      Icons.history_toggle_off_rounded,
                      color: AppColors.brandGold,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "عمليات تعديل الحركات في الفترة المحددة (${_filteredEdits.length})",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_filteredEdits.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          "لا توجد عمليات تعديل مسجلة في الفترة المحددة",
                          style: TextStyle(fontSize: 12, color: AppColors.neutral500),
                        ),
                      ),
                    ),
                  )
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filteredEdits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final edit = _filteredEdits[index];
                        final tx = _allTxMap[edit['txId']];
                        final beneficiary = tx?.beneficiary ?? "الحركة مجهولة";
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.edit_note_rounded,
                            color: AppColors.ocean,
                          ),
                          title: Text(
                            "تعديل حقل (${edit['field']}) لحركة للمستفيد [$beneficiary]",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          subtitle: Text(
                            "مبلغ الحركة تعدل من: ${edit['oldValue']} ← ليصبح: ${edit['newValue']}\nالمدقق المسؤول: ${edit['editedBy']} في ${DateFormat('MM-dd HH:mm').format(edit['editedAt'].toLocal())}",
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 28),

                // Button: Confirm and Seal balances
                FutureBuilder<Map<String, double>>(
                  future: _calculateCurrentBalances(),
                  builder: (context, snapshot) {
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandGold,
                          foregroundColor: AppColors.brandGreenDark,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppDims.radiusSm),
                          ),
                        ),
                        onPressed: _confirmMatching,
                        icon: const Icon(Icons.fact_check_rounded),
                        label: const Text(
                          "الأرصدة والصندوق مطابق لحد الآن",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // SECTION: Reconciliation History
                const Row(
                  children: [
                    Icon(
                      Icons.history_edu_rounded,
                      color: AppColors.brandGold,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "سجل ومحاضر المطابقات السابقة المعتمدة",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_matchHistory.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          "لا توجد مطبابقات سابقة مسجلة بالدفاتر",
                          style: TextStyle(fontSize: 12, color: AppColors.neutral500),
                        ),
                      ),
                    ),
                  )
                else
                  ..._matchHistory.map((match) {
                    final mapBals = Map<String, dynamic>.from(
                      match['balances'] ?? {},
                    );
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDims.radiusLg),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.bookmark_added_rounded,
                                      color: AppColors.success,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "محضر مطابقة: ${_formatDateStr(match['dateTime'])}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    "المطابِق: [ ${match['matchedBy']} ]", // إظهار المستخدم بوضوح
                                    style: const TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            const Text(
                              "الأرصدة المغلقة والمعتمدة بالمحضر:",
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.neutral500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: mapBals.entries.map((e) {
                                return Chip(
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: AppColors.neutral500.withValues(alpha: 
                                    0.06,
                                  ),
                                  label: Text(
                                    "${e.key}: ${e.value.toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ReconciliationDetailPage(match: match),
                                  ),
                                ),
                                icon: const Icon(Icons.open_in_new_rounded),
                                label: const Text('فتح المحضر في صفحة مستقلة'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
      ),
    );
  }
}

class ReconciliationDetailPage extends StatelessWidget {
  final Map<String, dynamic> match;

  const ReconciliationDetailPage({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final balances = Map<String, dynamic>.from(match['balances'] ?? {});
    final selected =
        (match['selectedTransactionIds'] as List? ?? const []).length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(context, title: 'محضر المطابقة'),
      body: TimaPageBackground(
        child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تاريخ المطابقة: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(match['dateTime']).toLocal())}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text('تمت بواسطة: ${match['matchedBy'] ?? 'غير معروف'}'),
                  if (selected > 0) ...[
                    const SizedBox(height: 8),
                    Text('الحركات المحددة في المحضر: $selected'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'الأرصدة المعتمدة',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...balances.entries.map(
            (entry) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(entry.key)),
                title: Text(entry.key),
                trailing: Text(
                  (entry.value as num).toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
