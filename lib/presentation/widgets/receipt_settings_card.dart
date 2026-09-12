import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/printing/delivery_receipt.dart';
import '../../core/printing/receipt_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'app_ui.dart';
import 'receipt_print_dialog.dart';

/// بطاقة تخصيص الطباعة والإيصالات داخل صفحة الإعدادات.
///
/// كل تغيير يُحفظ فوراً في إعدادات الجهاز، فتصبح نافذة الطباعة جاهزة
/// بخيارات المستخدم بدل سؤاله في كل مرة.
class ReceiptSettingsCard extends StatefulWidget {
  const ReceiptSettingsCard({super.key});

  @override
  State<ReceiptSettingsCard> createState() => _ReceiptSettingsCardState();
}

class _ReceiptSettingsCardState extends State<ReceiptSettingsCard> {
  ReceiptSettings _settings = ReceiptSettings.defaults;
  List<Printer> _printers = const [];
  late final TextEditingController _titleController;
  late final TextEditingController _footerController;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: _settings.title);
    _footerController = TextEditingController(text: _settings.footerMessage);
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await ReceiptSettings.load();
    final printers = await DeliveryReceiptService.availablePrinters();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _printers = printers;
      _titleController.text = settings.title;
      _footerController.text = settings.footerMessage;
      _loading = false;
    });
  }

  Future<void> _apply(ReceiptSettings next, {String? message}) async {
    setState(() {
      _settings = next;
      _saving = true;
    });
    await next.save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (message != null) {
      receiptToast(context, message, color: AppColors.success);
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'اختر صورة الشعار',
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.first.path;
    if (path == null || !mounted) return;
    await _apply(
      _settings.copyWith(logoPath: path, showLogo: true),
      message: 'تم اعتماد الشعار الجديد',
    );
  }

  Future<void> _testPrint() async {
    await _settings.save();
    if (!mounted) return;
    final sample = DeliveryReceiptData(
      beneficiary: 'زبون تجريبي',
      amount: 1250,
      currencyCode: 'USD',
      currencyName: 'دولار أمريكي',
      amount2: 5000,
      currencyCode2: 'TRY',
      currencyName2: 'ليرة تركية',
      denoms1: const {100.0: 10, 50.0: 4, 10.0: 5},
      denoms2: const {200.0: 25},
      status: 'تم التسليم',
      dateTime: DateTime.now(),
      note: '',
      createdBy: 'إعدادات',
      branch: 'المكتب الرئيسي',
      officeName: await DeliveryReceiptService.officeName(),
      transactionId: 9001,
    );
    if (!mounted) return;
    await printDeliveryReceipt(context, sample);
  }

  @override
  Widget build(BuildContext context) {
    return TimaPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TimaSectionTitle(
            icon: Icons.print_rounded,
            title: 'الطباعة والإيصالات',
            subtitle: 'الطابعة المعتمدة، الشعار، محتوى الإيصال، وعدّاد الطباعة',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_saving)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.cloud_done_rounded,
                    size: 16,
                    color: AppUi.textSecondary(context),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _testPrint,
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('طباعة تجريبية'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: TimaLoader(message: 'جارٍ قراءة الطابعات والإعدادات…'),
            )
          else ...[
            _printerSection(context),
            _divider(context),
            _countdownSection(context),
            _divider(context),
            _logoSection(context),
            _divider(context),
            _contentSection(context),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  _titleController.text = ReceiptSettings.defaults.title;
                  _footerController.text = ReceiptSettings.defaults
                      .footerMessage;
                  await _apply(
                    ReceiptSettings.defaults.copyWith(
                      printerName: _settings.printerName,
                    ),
                    message: 'أُعيدت إعدادات الإيصال إلى الافتراضي',
                  );
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('استعادة الإعدادات الافتراضية'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Container(height: 1, color: AppUi.border(context)),
  );

  // --- 1. الطابعة المعتمدة ---
  Widget _printerSection(BuildContext context) {
    final names = _printers.map((p) => p.name).toList();
    final selected = names.contains(_settings.printerName)
        ? _settings.printerName
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingLabel(
          icon: Icons.print_rounded,
          text: 'الطابعة المعتمدة',
          hint: _printers.isEmpty
              ? 'لم يُعثر على طابعة متصلة'
              : 'تُطبع الإيصالات إليها مباشرة دون اختيار في كل مرة',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: selected,
                isDense: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.print_rounded),
                  labelText: 'الطابعة',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    child: Text('حوار النظام / معاينة قبل الطباعة'),
                  ),
                  ...names.map(
                    (name) => DropdownMenuItem<String>(
                      value: name,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => _apply(
                  _settings.copyWith(printerName: value),
                  message: value == null
                      ? 'سيظهر حوار الطباعة قبل كل إيصال'
                      : 'تم اعتماد "$value"',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'إعادة قراءة قائمة الطابعات',
              onPressed: () async {
                setState(() => _loading = true);
                await _load();
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ],
    );
  }

  // --- 2. عدّاد الطباعة ---
  Widget _countdownSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingLabel(
          icon: Icons.timer_outlined,
          text: 'عدّاد الطباعة التلقائية',
          hint: 'بعد الضغط على طباعة يظهر عدّاد، ويتجدد عند أي تغيير في الخيارات',
        ),
        const SizedBox(height: 10),
        _SettingSwitch(
          label: 'طباعة تلقائية بعد انتهاء العدّاد',
          value: _settings.autoPrint,
          onChanged: (v) => _apply(_settings.copyWith(autoPrint: v)),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _settings.autoPrint ? 1 : 0.45,
          child: Row(
            children: [
              const SizedBox(width: 4),
              const Text('مدة العدّاد', style: TextStyle(fontSize: 12.5)),
              Expanded(
                child: Slider(
                  value: _settings.countdownSeconds
                      .clamp(
                        ReceiptSettings.minCountdownSeconds,
                        ReceiptSettings.maxCountdownSeconds,
                      )
                      .toDouble(),
                  min: ReceiptSettings.minCountdownSeconds.toDouble(),
                  max: ReceiptSettings.maxCountdownSeconds.toDouble(),
                  divisions:
                      ReceiptSettings.maxCountdownSeconds -
                      ReceiptSettings.minCountdownSeconds,
                  label: '${_settings.countdownSeconds} ثانية',
                  onChanged: _settings.autoPrint
                      ? (v) => setState(
                          () => _settings = _settings.copyWith(
                            countdownSeconds: v.round(),
                          ),
                        )
                      : null,
                  onChangeEnd: _settings.autoPrint
                      ? (v) => _apply(
                          _settings.copyWith(countdownSeconds: v.round()),
                          message: 'مدة العدّاد ${v.round()} ثانية',
                        )
                      : null,
                ),
              ),
              SizedBox(
                width: 62,
                child: Text(
                  '${_settings.countdownSeconds} ثانية',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppUi.accent(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- 3. الشعار ---
  Widget _logoSection(BuildContext context) {
    final path = _settings.logoPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingLabel(
          icon: Icons.image_outlined,
          text: 'شعار الإيصال',
          hint: 'اختر صورة الشعار وحدد موضعه على الإيصال',
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 92,
              height: 60,
              decoration: BoxDecoration(
                color: AppUi.sunken(context),
                borderRadius: BorderRadius.circular(AppDims.radiusSm),
                border: Border.all(color: AppUi.border(context)),
              ),
              clipBehavior: Clip.antiAlias,
              child: path == null
                  ? Center(
                      child: Image.asset(
                        'assets/images/tima_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.storefront_rounded,
                          color: AppUi.textSecondary(context),
                        ),
                      ),
                    )
                  : Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppUi.tone(context, AppColors.error),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingSwitch(
                    label: 'إظهار الشعار على الإيصال',
                    value: _settings.showLogo,
                    onChanged: (v) =>
                        _apply(_settings.copyWith(showLogo: v)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                        label: Text(
                          path == null ? 'اختيار صورة الشعار' : 'تغيير الصورة',
                        ),
                      ),
                      if (path != null)
                        TextButton.icon(
                          onPressed: () => _apply(
                            _settings.copyWith(logoPath: null),
                            message: 'أُزيل الشعار المخصّص — سيُستخدم شعار تيما',
                          ),
                          icon: const Icon(Icons.delete_outline_rounded, size: 16),
                          label: const Text('إزالة'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'موضع الشعار',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppUi.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ReceiptLogoPosition.values
              .map(
                (position) => _SettingChoice(
                  label: position.label,
                  icon: switch (position) {
                    ReceiptLogoPosition.topRight =>
                      Icons.vertical_align_top_rounded,
                    ReceiptLogoPosition.topLeft =>
                      Icons.vertical_align_top_rounded,
                    ReceiptLogoPosition.topCenter =>
                      Icons.align_vertical_center_rounded,
                    ReceiptLogoPosition.bottom =>
                      Icons.vertical_align_bottom_rounded,
                  },
                  selected: _settings.logoPosition == position,
                  onTap: () => _apply(
                    _settings.copyWith(logoPosition: position),
                    message: 'موضع الشعار: ${position.label}',
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 4),
            const Text('حجم الشعار', style: TextStyle(fontSize: 12.5)),
            Expanded(
              child: Slider(
                value: _settings.logoWidth.clamp(28.0, 110.0),
                min: 28,
                max: 110,
                divisions: (110 - 28) ~/ 2,
                label: '${_settings.logoWidth.round()}',
                onChanged: (v) => setState(
                  () => _settings = _settings.copyWith(logoWidth: v),
                ),
                onChangeEnd: (v) => _apply(
                  _settings.copyWith(logoWidth: v),
                  message: 'حجم الشعار ${v.round()}',
                ),
              ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                '${_settings.logoWidth.round()}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppUi.accent(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- 4. محتوى الإيصال ---
  Widget _contentSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingLabel(
          icon: Icons.receipt_long_rounded,
          text: 'محتوى الإيصال',
          hint: 'الحالة و«المسلّم» مطفأتان افتراضياً، والملاحظة تُكتب وقت الطباعة',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان الإيصال',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                onSubmitted: (v) => _apply(_settings.copyWith(title: v)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _footerController,
                decoration: const InputDecoration(
                  labelText: 'رسالة الختام',
                  prefixIcon: Icon(Icons.waving_hand_rounded),
                ),
                onSubmitted: (v) =>
                    _apply(_settings.copyWith(footerMessage: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SettingChoice(
              label: 'رقم العملية',
              icon: Icons.tag_rounded,
              selected: _settings.showTransactionId,
              onTap: () => _apply(
                _settings.copyWith(
                  showTransactionId: !_settings.showTransactionId,
                ),
              ),
            ),
            _SettingChoice(
              label: 'التاريخ والوقت',
              icon: Icons.schedule_rounded,
              selected: _settings.showDateTime,
              onTap: () => _apply(
                _settings.copyWith(showDateTime: !_settings.showDateTime),
              ),
            ),
            _SettingChoice(
              label: 'تفصيل العملات',
              icon: Icons.grid_view_rounded,
              selected: _settings.showDenominations,
              onTap: () => _apply(
                _settings.copyWith(
                  showDenominations: !_settings.showDenominations,
                ),
              ),
            ),
            _SettingChoice(
              label: 'اسم المكتب',
              icon: Icons.storefront_rounded,
              selected: _settings.showOfficeName,
              onTap: () => _apply(
                _settings.copyWith(showOfficeName: !_settings.showOfficeName),
              ),
            ),
            _SettingChoice(
              label: 'الحالة',
              icon: Icons.flag_outlined,
              selected: _settings.showStatus,
              onTap: () => _apply(
                _settings.copyWith(showStatus: !_settings.showStatus),
              ),
            ),
            _SettingChoice(
              label: 'المسلّم',
              icon: Icons.person_outline_rounded,
              selected: _settings.showCreatedBy,
              onTap: () => _apply(
                _settings.copyWith(showCreatedBy: !_settings.showCreatedBy),
              ),
            ),
            _SettingChoice(
              label: 'الفرع',
              icon: Icons.location_city_rounded,
              selected: _settings.showBranch,
              onTap: () => _apply(
                _settings.copyWith(showBranch: !_settings.showBranch),
              ),
            ),
            _SettingChoice(
              label: 'رسالة الختام',
              icon: Icons.waving_hand_rounded,
              selected: _settings.showFooter,
              onTap: () => _apply(
                _settings.copyWith(showFooter: !_settings.showFooter),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingLabel(
          icon: Icons.straighten_rounded,
          text: 'عرض ورق الطابعة',
          hint: 'الفاتورة الحرارية',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final width in const [58, 80]) ...[
              _SettingChoice(
                label: '$width مم',
                icon: Icons.receipt_rounded,
                selected: _settings.paperWidthMm == width,
                onTap: () => _apply(
                  _settings.copyWith(paperWidthMm: width),
                  message: 'عرض الورق $width مم',
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

/// عنوان قسم فرعي داخل البطاقة.
class _SettingLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final String hint;

  const _SettingLabel({
    required this.icon,
    required this.text,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppUi.accent(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppUi.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppUi.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// مفتاح تبديل بحدود ناعمة.
class _SettingSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppUi.sunken(context),
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        border: Border.all(color: AppUi.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// زر اختيار (مفعّل/غير مفعّل) بأنميشن بسيط.
class _SettingChoice extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SettingChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SettingChoice> createState() => _SettingChoiceState();
}

class _SettingChoiceState extends State<_SettingChoice> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.tone(
      context,
      widget.selected ? AppColors.brandGreen : AppColors.neutral500,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7.5),
          decoration: BoxDecoration(
            color: widget.selected
                ? accent.withValues(alpha: _hovered ? 0.20 : 0.13)
                : (_hovered ? AppUi.hover(context) : AppUi.sunken(context)),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(
              color: widget.selected
                  ? accent.withValues(alpha: 0.55)
                  : AppUi.border(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.selected
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: widget.selected
                      ? AppUi.textPrimary(context)
                      : AppUi.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
