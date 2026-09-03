import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_catalog.dart';
import 'app_ui.dart';

/// محرّر فئات ورقية بالنقر بدل كتابتها مفصولة بفواصل.
///
/// يعرض الفئات المتداولة للعملة كرقائق تُنتقى بالنقر، ويسمح بإضافة
/// فئة غير قياسية يدوياً. يُصدر النتيجة كنص مفصول بفواصل عبر
/// [onChanged] حفاظاً على صيغة التخزين `Name|Denominations`.
class DenomPicker extends StatefulWidget {
  /// رمز العملة، لجلب الفئات المقترحة.
  final String code;

  /// الفئات الحالية كنص مفصول بفواصل.
  final String value;

  final ValueChanged<String> onChanged;

  const DenomPicker({
    super.key,
    required this.code,
    required this.value,
    required this.onChanged,
  });

  @override
  State<DenomPicker> createState() => _DenomPickerState();
}

class _DenomPickerState extends State<DenomPicker> {
  final TextEditingController _custom = TextEditingController();
  late List<double> _selected;

  @override
  void initState() {
    super.initState();
    _selected = _parse(widget.value);
  }

  @override
  void didUpdateWidget(covariant DenomPicker old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _selected = _parse(widget.value);
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  List<double> _parse(String raw) {
    final out = raw
        .split(RegExp(r'[,،\s]+'))
        .map((e) => double.tryParse(e.trim()) ?? 0)
        .where((e) => e > 0)
        .toList();
    out.sort((a, b) => b.compareTo(a));
    return out;
  }

  void _emit() {
    widget.onChanged(_selected.map(CurrencySpec.formatDenom).join(', '));
  }

  void _toggle(double value) {
    setState(() {
      if (_selected.contains(value)) {
        _selected.remove(value);
      } else {
        _selected.add(value);
        _selected.sort((a, b) => b.compareTo(a));
      }
    });
    _emit();
  }

  void _addCustom() {
    final v = double.tryParse(_custom.text.trim());
    if (v == null || v <= 0 || _selected.contains(v)) {
      _custom.clear();
      return;
    }
    setState(() {
      _selected.add(v);
      _selected.sort((a, b) => b.compareTo(a));
      _custom.clear();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final spec = currencySpecForCode(widget.code);
    final suggested = spec?.denoms ?? kGenericDenoms;
    // الفئات المختارة التي ليست ضمن المقترحات تُعرض بعدها.
    final extras = _selected.where((d) => !suggested.contains(d)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final d in suggested)
              _Chip(
                label: CurrencySpec.formatDenom(d),
                selected: _selected.contains(d),
                onTap: () => _toggle(d),
              ),
            for (final d in extras)
              _Chip(
                label: CurrencySpec.formatDenom(d),
                selected: true,
                custom: true,
                onTap: () => _toggle(d),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: _custom,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onSubmitted: (_) => _addCustom(),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'فئة أخرى',
                  hintText: '250',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _addCustom,
              child: const Text('إضافة'),
            ),
            const Spacer(),
            Text(
              '${_selected.length} فئة',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _selected.isEmpty
                    ? AppColors.error
                    : AppUi.textSecondary(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool custom;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.custom = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.tone(
      context,
      custom ? AppColors.violet : AppColors.brandGreen,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent : AppUi.sunken(context),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(
              color: selected ? accent : AppUi.border(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : AppUi.textPrimary(context),
            ),
          ),
        ),
      ),
    );
  }
}
