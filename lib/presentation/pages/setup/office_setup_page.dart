import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/device_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_catalog.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/denom_picker.dart';

/// معالج إعداد المكتب بعد أول تشغيل / إنشاء حساب:
/// 1) اختيار/إضافة العملات + فئاتها
/// 2) تسجيل الرصيد الافتتاحي (عدد كل فئة)
class OfficeSetupPage extends StatefulWidget {
  final AppDatabase db;
  final User user;

  const OfficeSetupPage({super.key, required this.db, required this.user});

  @override
  State<OfficeSetupPage> createState() => _OfficeSetupPageState();
}

class _PresetCurrency {
  final String code;
  final String name;
  String denoms;
  bool selected;

  _PresetCurrency({
    required this.code,
    required this.name,
    required this.denoms,
    this.selected = false,
  });
}

class _BalanceRow {
  final Currency currency;
  final List<double> denoms;
  final Map<double, TextEditingController> controllers;

  _BalanceRow({
    required this.currency,
    required this.denoms,
    required this.controllers,
  });

  double get total {
    var sum = 0.0;
    for (final d in denoms) {
      final text = controllers[d]?.text.trim() ?? '';
      final count = int.tryParse(text) ?? 0;
      sum += d * count;
    }
    return sum;
  }

  Map<double, int> get counts {
    final map = <double, int>{};
    for (final d in denoms) {
      final text = controllers[d]?.text.trim() ?? '';
      map[d] = int.tryParse(text) ?? 0;
    }
    return map;
  }

  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
  }
}

class _OfficeSetupPageState extends State<OfficeSetupPage> {
  int _step = 0;
  bool _loading = false;
  bool _saving = false;

  late final List<_PresetCurrency> _presets;
  final _customCode = TextEditingController();
  final _customName = TextEditingController();
  final _customDenoms = TextEditingController();

  List<_BalanceRow> _balanceRows = [];

  @override
  void initState() {
    super.initState();
    // كل العملات الافتراضية من السجلّ المركزي، مفعّلة عند أول تشغيل.
    _presets = [
      for (final spec in kCurrencyCatalog)
        _PresetCurrency(
          code: spec.code,
          name: spec.name,
          denoms: spec.denomsText,
          selected: true,
        ),
    ];
    _bootstrapExisting();
  }

  Future<void> _bootstrapExisting() async {
    setState(() => _loading = true);
    final existing = await widget.db.getAllCurrencies();
    if (existing.isNotEmpty) {
      for (final c in existing) {
        final match = _presets.where((p) => p.code == c.code).toList();
        if (match.isNotEmpty) {
          match.first.selected = true;
          final denoms = CurrencyDenoms.forCurrency(c);
          if (denoms.isNotEmpty) {
            match.first.denoms = denoms
                .map(
                  (e) => e == e.roundToDouble()
                      ? e.toInt().toString()
                      : e.toString(),
                )
                .join(', ');
          }
        } else {
          _presets.add(
            _PresetCurrency(
              code: c.code,
              name: CurrencyDenoms.displayName(c),
              denoms: CurrencyDenoms.forCurrency(c)
                  .map(
                    (e) => e == e.roundToDouble()
                        ? e.toInt().toString()
                        : e.toString(),
                  )
                  .join(', '),
              selected: true,
            ),
          );
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _customCode.dispose();
    _customName.dispose();
    _customDenoms.dispose();
    for (final row in _balanceRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addCustomCurrency() {
    final code = _customCode.text.trim().toUpperCase();
    final name = _customName.text.trim();
    var denoms = _customDenoms.text.trim();
    if (code.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل رمز العملة واسمها')));
      return;
    }
    if (_presets.any((p) => p.code == code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('العملة $code موجودة مسبقاً — فعّلها من القائمة'),
        ),
      );
      return;
    }
    if (denoms.isEmpty) {
      denoms = CurrencyDenoms.defaultsTextForCode(code);
    }
    setState(() {
      _presets.add(
        _PresetCurrency(code: code, name: name, denoms: denoms, selected: true),
      );
      _customCode.clear();
      _customName.clear();
      _customDenoms.clear();
    });
  }

  Future<void> _goToBalanceStep() async {
    final selected = _presets.where((p) => p.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر عملة واحدة على الأقل')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = await widget.db.getAllCurrencies();
      final byCode = {for (final c in existing) c.code.toUpperCase(): c};

      for (final p in selected) {
        final combined = CurrencyDenoms.combineNameAndDenoms(p.name, p.denoms);
        final found = byCode[p.code.toUpperCase()];
        if (found == null) {
          await widget.db.insertCurrency(
            CurrenciesCompanion.insert(
              code: p.code,
              name: drift.Value(combined),
            ),
          );
        } else {
          await widget.db.updateCurrency(
            found.id,
            CurrenciesCompanion(name: drift.Value(combined)),
          );
        }
      }

      // أعد تحميل العملات المختارة فقط لبناء صفوف الرصيد
      final all = await widget.db.getAllCurrencies();
      final selectedCodes = selected.map((e) => e.code.toUpperCase()).toSet();
      final currencies = all
          .where((c) => selectedCodes.contains(c.code.toUpperCase()))
          .toList();

      for (final row in _balanceRows) {
        row.dispose();
      }
      _balanceRows = currencies.map((c) {
        final denoms = CurrencyDenoms.forCurrency(c);
        final controllers = <double, TextEditingController>{
          for (final d in denoms) d: TextEditingController(),
        };
        return _BalanceRow(
          currency: c,
          denoms: denoms,
          controllers: controllers,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _step = 1;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حفظ العملات: $e')));
    }
  }

  Future<void> _finishSetup() async {
    setState(() => _saving = true);
    try {
      for (final row in _balanceRows) {
        final counts = row.counts;
        final total = row.total;

        // حفظ جرد الفئات في إعدادات الجهاز
        await DeviceSettings.setBillCountsForCurrency(row.currency.id, counts);

        // تسجيل رصيد افتتاحي كحركة استلام إن وُجد مبلغ
        if (total > 0.009) {
          final denomNote =
              '[رصيد افتتاحي — الفئات: ${CurrencyDenoms.formatCounts(counts)}]';
          await widget.db.insertTransaction(
            TransactionsCompanion.insert(
              userId: widget.user.id,
              currencyId: row.currency.id,
              createdByName: drift.Value(widget.user.username),
              type: 'حركة استلام',
              beneficiary: const drift.Value('رصيد افتتاحي للصندوق'),
              amount: total,
              note: drift.Value(denomNote),
              movementState: const drift.Value('مفعلة'),
              status: const drift.Value('تم الاستلام'),
            ),
          );
        }
      }

      await DeviceSettings.markOfficeSetupCompleted();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ تم إعداد المكتب والأرصدة الافتتاحية بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
      // الخطوة التالية المطلوبة في الإعداد الأول هي إدخال الحركات المعلقة.
      await Navigator.pushNamed(
        context,
        '/import_pending',
        arguments: widget.user,
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/home',
        (_) => false,
        arguments: widget.user,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر إتمام الإعداد: $e')));
    }
  }

  Future<void> _skipSetup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تخطي الإعداد؟'),
        content: const Text(
          'يمكنك إعداد العملات والأرصدة لاحقاً من القائمة. هل تريد المتابعة بدون رصيد افتتاحي؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تخطي'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DeviceSettings.markOfficeSetupCompleted();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/home',
      (_) => false,
      arguments: widget.user,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: _step == 0 ? 'إعداد المكتب — العملات' : 'الرصيد الافتتاحي',
      ),
      body: TimaPageBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildStepperHeader(),
                  Expanded(
                    child: _step == 0
                        ? _buildCurrenciesStep()
                        : _buildBalanceStep(),
                  ),
                  _buildBottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TimaPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _stepChip(1, 'العملات والفئات', _step == 0),
            Expanded(
              child: Container(
                height: 2,
                color: AppColors.brandGold.withValues(alpha: 0.4),
              ),
            ),
            _stepChip(2, 'الرصيد الافتتاحي', _step == 1),
          ],
        ),
      ),
    );
  }

  Widget _stepChip(int n, String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? AppColors.brandGreen.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDims.radius),
        border: Border.all(
          color: active ? AppColors.brandGreen : AppColors.neutral500.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: active
                ? AppColors.brandGreen
                : AppColors.neutral400,
            child: Text(
              '$n',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.brandGreen : AppColors.neutral500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrenciesStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const TimaSectionTitle(
          icon: Icons.currency_exchange_rounded,
          title: 'اختر عملات المكتب',
          subtitle: 'فعّل العملات التي تتعامل بها وراجع فئاتها الورقية',
        ),
        const SizedBox(height: 12),
        ..._presets.map((p) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: CheckboxListTile(
              value: p.selected,
              onChanged: (v) => setState(() => p.selected = v ?? false),
              title: Text(
                '${p.code} — ${p.name}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'الفئات: ${p.denoms}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (p.selected) ...[
                    const SizedBox(height: 10),
                    DenomPicker(
                      code: p.code,
                      value: p.denoms,
                      onChanged: (v) => setState(() => p.denoms = v),
                    ),
                  ],
                ],
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          );
        }),
        const SizedBox(height: 8),
        TimaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TimaSectionTitle(
                icon: Icons.add_circle_outline,
                title: 'إضافة عملة مخصصة',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _customCode,
                textCapitalization: TextCapitalization.characters,
                // إعادة البناء تُحدّث الفئات المقترحة أسفل النموذج فوراً.
                onChanged: (v) {
                  final spec = currencySpecForCode(v);
                  setState(() {
                    if (spec != null) {
                      if (_customName.text.trim().isEmpty) {
                        _customName.text = spec.name;
                      }
                      _customDenoms.text = spec.denomsText;
                    }
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'الرمز (مثل AED)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _customName,
                decoration: const InputDecoration(
                  labelText: 'الاسم بالعربي',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'الفئات الورقية',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textSecondary(context),
                ),
              ),
              const SizedBox(height: 8),
              DenomPicker(
                code: _customCode.text,
                value: _customDenoms.text,
                onChanged: (v) => _customDenoms.text = v,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _addCustomCurrency,
                icon: const Icon(Icons.add),
                label: const Text('إضافة للعملات المختارة'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildBalanceStep() {
    if (_balanceRows.isEmpty) {
      return const Center(child: Text('لا توجد عملات — ارجع للخطوة السابقة'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _balanceRows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: TimaSectionTitle(
              icon: Icons.account_balance_wallet_rounded,
              title: 'كم معك الآن في الصندوق؟',
              subtitle:
                  'اكتب عدد الأوراق من كل فئة — المجموع يُحسب تلقائياً ويُسجّل كرصيد افتتاحي',
            ),
          );
        }

        final row = _balanceRows[index - 1];
        final code = row.currency.code;
        final name = CurrencyDenoms.displayName(row.currency);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            initiallyExpanded: index == 1,
            title: Text(
              '$code — $name',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'الإجمالي: ${row.total.toStringAsFixed(2)} $code',
              style: TextStyle(
                color: row.total > 0 ? AppColors.success : AppColors.neutral500,
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    ...row.denoms.map((denom) {
                      final controller = row.controllers[denom]!;
                      final count = int.tryParse(controller.text.trim()) ?? 0;
                      final sub = denom * count;
                      final denomLabel = denom == denom.roundToDouble()
                          ? denom.toInt().toString()
                          : denom.toString();

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text(
                                '$denomLabel $code',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppColors.error,
                                size: 20,
                              ),
                              onPressed: count > 0
                                  ? () {
                                      controller.text = (count - 1).toString();
                                      setState(() {});
                                    }
                                  : null,
                            ),
                            SizedBox(
                              width: 70,
                              child: TextField(
                                controller: controller,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '0',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(AppDims.radiusSm),
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                                onTap: () {
                                  controller.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: controller.text.length,
                                  );
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: AppColors.success,
                                size: 20,
                              ),
                              onPressed: () {
                                controller.text = (count + 1).toString();
                                setState(() {});
                              },
                            ),
                            const Spacer(),
                            Text(
                              sub.toStringAsFixed(0),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'مجموع هذه العملة:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${row.total.toStringAsFixed(2)} $code',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.brandGreen,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: AppUi.border(context))),
        ),
        child: Row(
          children: [
            if (_step == 1)
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _step = 0),
                  child: const Text('السابق'),
                ),
              ),
            if (_step == 1) const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        if (_step == 0) {
                          _goToBalanceStep();
                        } else {
                          _finishSetup();
                        }
                      },
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_step == 0 ? Icons.arrow_back : Icons.check_circle),
                label: Text(
                  _step == 0
                      ? 'التالي — الرصيد الافتتاحي'
                      : 'حفظ وإنهاء الإعداد',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
