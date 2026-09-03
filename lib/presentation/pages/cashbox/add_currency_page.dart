import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' as drift;

import '../../../core/services/app_sound.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_catalog.dart';
import '../../widgets/app_ui.dart';

class AddCurrencyPage extends StatefulWidget {
  final AppDatabase db;
  const AddCurrencyPage({super.key, required this.db});

  @override
  State<AddCurrencyPage> createState() => _AddCurrencyPageState();
}

class _AddCurrencyPageState extends State<AddCurrencyPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _newDenomController = TextEditingController();
  final FocusNode _newDenomFocus = FocusNode();

  /// الفئات المختارة، مرتّبة تنازلياً دائماً.
  final List<double> _denoms = [];

  /// آخر رمز طُبِّقت افتراضياته، حتى لا نطمس تعديلات المستخدم.
  String _appliedPreset = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _nameController.dispose();
    _newDenomController.dispose();
    _newDenomFocus.dispose();
    super.dispose();
  }

  /// يملأ الاسم والفئات تلقائياً عند التعرّف على رمز عملة معروف.
  void _onCodeChanged() {
    final code = _codeController.text.trim().toUpperCase();
    if (code == _appliedPreset) return;
    final spec = currencySpecForCode(code);
    if (spec == null) return;
    setState(() {
      _appliedPreset = code;
      _nameController.text = spec.name;
      _denoms
        ..clear()
        ..addAll(spec.denoms);
    });
  }

  void _applySpec(CurrencySpec spec) {
    setState(() {
      _appliedPreset = spec.code;
      _codeController.text = spec.code;
      _nameController.text = spec.name;
      _denoms
        ..clear()
        ..addAll(spec.denoms);
    });
  }

  void _toggleDenom(double value) {
    setState(() {
      if (_denoms.contains(value)) {
        _denoms.remove(value);
      } else {
        _denoms.add(value);
        _denoms.sort((a, b) => b.compareTo(a));
      }
    });
  }

  void _addTypedDenom() {
    final raw = _newDenomController.text.trim().replaceAll('،', '');
    final value = double.tryParse(raw);
    if (value == null || value <= 0) {
      AppSound.play(TimaSound.error);
      _snack('أدخل رقماً صحيحاً أكبر من صفر', AppColors.error);
      return;
    }
    if (_denoms.contains(value)) {
      _snack('الفئة $raw مضافة أصلاً', AppColors.warning);
      _newDenomController.clear();
      return;
    }
    setState(() {
      _denoms.add(value);
      _denoms.sort((a, b) => b.compareTo(a));
      _newDenomController.clear();
    });
    _newDenomFocus.requestFocus();
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _addCurrency() async {
    final code = _codeController.text.trim().toUpperCase();
    final name = _nameController.text.trim();

    if (code.isEmpty || name.isEmpty) {
      AppSound.play(TimaSound.error);
      _snack('يرجى إدخال رمز العملة واسمها', AppColors.error);
      return;
    }
    if (_denoms.isEmpty) {
      AppSound.play(TimaSound.error);
      _snack('اختر فئة ورقية واحدة على الأقل', AppColors.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final existing = await widget.db.getAllCurrencies();
      if (existing.any((c) => c.code.toUpperCase() == code)) {
        if (!mounted) return;
        AppSound.play(TimaSound.error);
        _snack('العملة $code مضافة مسبقاً', AppColors.error);
        return;
      }

      // الاسم يُخزَّن مدمجاً مع الفئات بالصيغة: Name|Denominations
      final denomsText = _denoms.map(CurrencySpec.formatDenom).join(', ');
      await widget.db.insertCurrency(
        CurrenciesCompanion(
          code: drift.Value(code),
          name: drift.Value('$name|$denomsText'),
        ),
      );

      if (!mounted) return;
      AppSound.play(TimaSound.success);
      _snack('تم إضافة $name وفئاتها بنجاح', AppColors.success);
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final knownCode = currencySpecForCode(_codeController.text);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(context, title: 'إضافة عملة'),
      body: TimaPageBackground(
        child: Scrollbar(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDims.pagePadding,
              vertical: 18,
            ),
            children: [
              TimaContentWidth(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TimaHeaderPanel(
                      icon: Icons.add_card_rounded,
                      title: 'إضافة عملة جديدة',
                      subtitle:
                          'اختر عملة جاهزة بفئاتها، أو أنشئ واحدة وحدّد فئاتها بنقرة.',
                    ),
                    const SizedBox(height: 16),

                    // ---- 1) اختيار سريع من العملات المعروفة ----
                    TimaPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const TimaSectionTitle(
                            icon: Icons.bolt_rounded,
                            title: 'اختيار سريع',
                            subtitle: 'انقر عملة لتعبئة اسمها وفئاتها فوراً',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final spec in [
                                ...kCurrencyCatalog,
                                ...kExtraKnownCurrencies,
                              ])
                                _CurrencyChip(
                                  spec: spec,
                                  selected: _appliedPreset == spec.code,
                                  onTap: () => _applySpec(spec),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ---- 2) هوية العملة ----
                    TimaPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const TimaSectionTitle(
                            icon: Icons.badge_rounded,
                            title: 'هوية العملة',
                            subtitle: 'الرمز الدولي والاسم المعروض',
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 190,
                                child: TextField(
                                  controller: _codeController,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[a-zA-Z]'),
                                    ),
                                    LengthLimitingTextInputFormatter(5),
                                    _UpperCaseFormatter(),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: 'الرمز',
                                    hintText: 'USD',
                                    prefixIcon: const Icon(Icons.tag_rounded),
                                    suffixIcon: knownCode != null
                                        ? const Icon(
                                            Icons.verified_rounded,
                                            color: AppColors.success,
                                            size: 19,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'اسم العملة',
                                    hintText: 'دولار أمريكي',
                                    prefixIcon: Icon(Icons.title_rounded),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ---- 3) الفئات الورقية ----
                    TimaPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TimaSectionTitle(
                            icon: Icons.payments_rounded,
                            title: 'الفئات الورقية',
                            subtitle: 'انقر الفئة لإضافتها أو إزالتها',
                            trailing: TimaStatusPill(
                              label: '${_denoms.length} فئة',
                              color: _denoms.isEmpty
                                  ? AppColors.neutral400
                                  : AppColors.brandGreen,
                              icon: Icons.layers_rounded,
                            ),
                          ),
                          const SizedBox(height: 14),

                          if (knownCode != null) ...[
                            Text(
                              'الفئات المتداولة لـ ${knownCode.name}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppUi.textSecondary(context),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final d in knownCode.denoms)
                                  _DenomChip(
                                    value: d,
                                    symbol: knownCode.symbol,
                                    selected: _denoms.contains(d),
                                    onTap: () => _toggleDenom(d),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          // الفئات المختارة التي ليست ضمن الاقتراحات
                          if (_denoms.any(
                            (d) => knownCode == null
                                ? true
                                : !knownCode.denoms.contains(d),
                          )) ...[
                            Text(
                              'فئات مخصّصة',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppUi.textSecondary(context),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final d in _denoms)
                                  if (knownCode == null ||
                                      !knownCode.denoms.contains(d))
                                    _DenomChip(
                                      value: d,
                                      symbol: knownCode?.symbol ?? '',
                                      selected: true,
                                      onTap: () => _toggleDenom(d),
                                    ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          // إضافة فئة يدوية
                          Row(
                            children: [
                              SizedBox(
                                width: 210,
                                child: TextField(
                                  controller: _newDenomController,
                                  focusNode: _newDenomFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.]'),
                                    ),
                                  ],
                                  onSubmitted: (_) => _addTypedDenom(),
                                  decoration: const InputDecoration(
                                    labelText: 'فئة أخرى',
                                    hintText: '250',
                                    isDense: true,
                                    prefixIcon: Icon(Icons.add_rounded),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: _addTypedDenom,
                                icon: const Icon(
                                  Icons.playlist_add_rounded,
                                  size: 18,
                                ),
                                label: const Text('إضافة'),
                              ),
                              const Spacer(),
                              if (_denoms.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _denoms.clear()),
                                  icon: const Icon(
                                    Icons.clear_all_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('مسح الكل'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _addCurrency,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(
                              _saving ? 'جارٍ الحفظ…' : 'حفظ العملة',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// يحوّل المدخل إلى أحرف كبيرة أثناء الكتابة.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// بطاقة عملة جاهزة في الاختيار السريع.
class _CurrencyChip extends StatelessWidget {
  final CurrencySpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _CurrencyChip({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDims.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : AppUi.sunken(context),
            borderRadius: BorderRadius.circular(AppDims.radius),
            border: Border.all(
              color: selected ? accent : AppUi.border(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                spec.symbol,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: selected ? accent : AppUi.textSecondary(context),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                spec.name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimary(context),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                spec.code,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// فئة ورقية واحدة تُختار بالنقر.
class _DenomChip extends StatelessWidget {
  final double value;
  final String symbol;
  final bool selected;
  final VoidCallback onTap;

  const _DenomChip({
    required this.value,
    required this.symbol,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.tone(context, AppColors.brandGreen);
    final label = CurrencySpec.formatDenom(value);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent : AppUi.sunken(context),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(
              color: selected ? accent : AppUi.border(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 15,
                color: selected ? Colors.white : AppUi.textSecondary(context),
              ),
              const SizedBox(width: 7),
              Text(
                symbol.isEmpty ? label : '$label $symbol',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppUi.textPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
