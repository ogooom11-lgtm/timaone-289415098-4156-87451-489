import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../core/printing/delivery_receipt.dart';
import '../../core/printing/receipt_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'app_ui.dart';

/// نتيجة نافذة الطباعة: الإيصال بعد تطبيق خيارات المستخدم + الطابعة.
class ReceiptPrintRequest {
  final DeliveryReceiptData data;
  final ReceiptSettings settings;
  final Printer? printer;

  const ReceiptPrintRequest({
    required this.data,
    required this.settings,
    required this.printer,
  });
}

/// مسار الطباعة الكامل: يقرأ الإعدادات، يفتح نافذة الخيارات والعدّاد،
/// ثم يُرسل الإيصال إلى الطابعة المعتمدة.
///
/// يُستدعى من أي صفحة عند الضغط على «طباعة إيصال».
Future<void> printDeliveryReceipt(
  BuildContext context,
  DeliveryReceiptData data,
) async {
  try {
    final settings = await ReceiptSettings.load();
    var receipt = data;
    if (receipt.officeName.isEmpty) {
      receipt = receipt.copyWith(
        officeName: await DeliveryReceiptService.officeName(),
      );
    }
    final printers = await DeliveryReceiptService.availablePrinters();
    if (!context.mounted) return;

    final request = await showReceiptPrintDialog(
      context,
      data: receipt,
      settings: settings,
      printers: printers,
    );
    if (request == null) return;

    await DeliveryReceiptService.sendToPrinter(
      data: request.data,
      settings: request.settings,
      printer: request.printer,
    );

    if (!context.mounted) return;
    receiptToast(
      context,
      'أُرسل الإيصال إلى ${request.printer?.name ?? 'حوار الطباعة'}',
      color: AppColors.success,
    );
  } catch (e) {
    if (!context.mounted) return;
    receiptToast(context, 'تعذر الطباعة: $e', color: AppColors.error);
  }
}

/// بعد نجاح التسليم: يسأل ثم يفتح مسار الطباعة.
Future<void> offerReceiptPrintAfterDelivery(
  BuildContext context,
  DeliveryReceiptData data,
) async {
  final wantPrint = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.radiusLg),
          side: BorderSide(color: AppUi.border(ctx)),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppUi.tone(
              ctx,
              AppColors.success,
            )),
            const SizedBox(width: 8),
            const Expanded(child: Text('تمت العملية بنجاح')),
          ],
        ),
        content: const Text(
          'هل تريد طباعة إيصال لهذه الحركة؟',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لاحقاً'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('طباعة الإيصال'),
          ),
        ],
      ),
    ),
  );

  if (wantPrint != true || !context.mounted) return;
  await printDeliveryReceipt(context, data);
}

/// يفتح نافذة خيارات الإيصال مع عدّاد الطباعة التلقائي.
Future<ReceiptPrintRequest?> showReceiptPrintDialog(
  BuildContext context, {
  required DeliveryReceiptData data,
  required ReceiptSettings settings,
  required List<Printer> printers,
}) {
  return showDialog<ReceiptPrintRequest>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ReceiptPrintSheet(
      data: data,
      settings: settings,
      printers: printers,
    ),
  );
}

/// رسالة موحّدة لنتائج الطباعة.
void receiptToast(BuildContext context, String message, {Color? color}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// نافذة الطباعة: ملاحظة اختيارية + مفاتيح إظهار + طابعة + عدّاد.
///
/// العدّاد يُصفَّر عند أي تغيير في الخيارات أو عند الكتابة، وزر
/// «طباعة الآن» (أو Enter) يطبع فوراً.
class ReceiptPrintSheet extends StatefulWidget {
  final DeliveryReceiptData data;
  final ReceiptSettings settings;
  final List<Printer> printers;

  const ReceiptPrintSheet({
    super.key,
    required this.data,
    required this.settings,
    required this.printers,
  });

  @override
  State<ReceiptPrintSheet> createState() => _ReceiptPrintSheetState();
}

class _ReceiptPrintSheetState extends State<ReceiptPrintSheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _noteController;
  late final AnimationController _countdown;
  late ReceiptSettings _settings;
  String? _printerName;
  bool _done = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _noteController = TextEditingController();

    final known = widget.printers.map((p) => p.name).toSet();
    _printerName = known.contains(_settings.printerName)
        ? _settings.printerName
        : null;

    _countdown = AnimationController(
      vsync: this,
      duration: Duration(
        seconds: _settings.countdownSeconds.clamp(
          ReceiptSettings.minCountdownSeconds,
          ReceiptSettings.maxCountdownSeconds,
        ),
      ),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _submit();
    });

    if (_settings.autoPrint) _countdown.forward();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _countdown.dispose();
    super.dispose();
  }

  Printer? get _selectedPrinter {
    for (final printer in widget.printers) {
      if (printer.name == _printerName) return printer;
    }
    return null;
  }

  /// إعادة العدّاد من البداية — تُستدعى عند أي تفاعل من المستخدم.
  void _restartCountdown() {
    if (!_settings.autoPrint || _done) return;
    _countdown.forward(from: 0);
  }

  void _togglePause() {
    if (_done || !_settings.autoPrint) return;
    setState(() {
      if (_countdown.isAnimating) {
        _countdown.stop();
      } else {
        _countdown.forward();
      }
    });
  }

  Future<void> _submit() async {
    if (_done) return;
    _done = true;
    _countdown.stop();
    setState(() => _working = true);
    Navigator.pop(
      context,
      ReceiptPrintRequest(
        data: widget.data.copyWith(note: _noteController.text.trim()),
        settings: _settings,
        printer: _selectedPrinter,
      ),
    );
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    _countdown.stop();
    Navigator.pop(context);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final focused = FocusManager.instance.primaryFocus?.context?.widget;
      if (focused is EditableText) return KeyEventResult.ignored;
      _submit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _updateSettings(ReceiptSettings next) {
    setState(() => _settings = next);
    _restartCountdown();
  }

  Future<void> _saveDefaultPrinter() async {
    await _settings.copyWith(printerName: _printerName).save();
    if (!mounted) return;
    receiptToast(
      context,
      _printerName == null
          ? 'أُلغي اعتماد الطابعة — سيظهر حوار الطباعة كل مرة'
          : 'تم اعتماد "$_printerName" كطابعة للإيصالات',
      color: AppColors.ocean,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Material(
              color: AppUi.elevated(context),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDims.radiusLg),
                side: BorderSide(color: AppUi.borderStrong(context)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                      child: _buildBody(context),
                    ),
                  ),
                  _buildActions(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: AppUi.accentPanelDecoration(
        context,
        start: AppColors.brandGreen,
        end: AppColors.brandGreenDark,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'خيارات الإيصال والطباعة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.data.transactionId == null
                      ? 'اكتب ملاحظة إن أردت، ثم تُطبع تلقائياً'
                      : 'عملية رقم #${widget.data.transactionId} — الملاحظة تُطبع فقط إذا كتبتها',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _summaryStrip(context),
        const SizedBox(height: 14),
        TextField(
          controller: _noteController,
          maxLines: 2,
          minLines: 1,
          onChanged: (_) => _restartCountdown(),
          decoration: const InputDecoration(
            labelText: 'ملاحظة على الإيصال (اختياري)',
            hintText: 'تُطبع فقط إذا كتبت شيئاً هنا…',
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'ما الذي يظهر في الإيصال؟',
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
          children: [
            _OptionChip(
              label: 'تفصيل العملات',
              icon: Icons.grid_view_rounded,
              selected: _settings.showDenominations,
              onTap: () => _updateSettings(
                _settings.copyWith(
                  showDenominations: !_settings.showDenominations,
                ),
              ),
            ),
            _OptionChip(
              label: 'التاريخ والوقت',
              icon: Icons.schedule_rounded,
              selected: _settings.showDateTime,
              onTap: () => _updateSettings(
                _settings.copyWith(showDateTime: !_settings.showDateTime),
              ),
            ),
            _OptionChip(
              label: 'رقم العملية',
              icon: Icons.tag_rounded,
              selected: _settings.showTransactionId,
              onTap: () => _updateSettings(
                _settings.copyWith(
                  showTransactionId: !_settings.showTransactionId,
                ),
              ),
            ),
            _OptionChip(
              label: 'المسلّم',
              icon: Icons.person_rounded,
              selected: _settings.showCreatedBy,
              onTap: () => _updateSettings(
                _settings.copyWith(showCreatedBy: !_settings.showCreatedBy),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildPrinterRow(context),
      ],
    );
  }

  Widget _summaryStrip(BuildContext context) {
    final hasAmount2 =
        widget.data.amount2 != null &&
        widget.data.amount2! > 0 &&
        widget.data.currencyCode2 != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppUi.sunken(context),
        borderRadius: BorderRadius.circular(AppDims.radius),
        border: Border.all(color: AppUi.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.data.beneficiary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppUi.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasAmount2
                      ? '${widget.data.amount} ${widget.data.currencyCode} ← ${widget.data.amount2} ${widget.data.currencyCode2}'
                      : 'مبلغ واحد • ${widget.data.currencyName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppUi.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _countdownDial(context),
        ],
      ),
    );
  }

  Widget _countdownDial(BuildContext context) {
    final accent = AppUi.tone(context, AppColors.brandGoldDark);

    return AnimatedBuilder(
      animation: _countdown,
      builder: (context, _) {
        final remaining = _settings.autoPrint ? 1 - _countdown.value : 1.0;
        final seconds = (remaining * _countdown.duration!.inMilliseconds / 1000)
            .ceil();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 74,
              height: 74,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: remaining.clamp(0.0, 1.0),
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      color: accent,
                      backgroundColor: AppUi.border(context),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _settings.autoPrint ? '$seconds' : '—',
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          color: AppUi.textPrimary(context),
                        ),
                      ),
                      Text(
                        'ثانية',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: AppUi.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            IconButton(
              tooltip: _countdown.isAnimating ? 'إيقاف العدّاد' : 'متابعة العدّاد',
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              onPressed: _settings.autoPrint ? _togglePause : null,
              icon: Icon(
                _countdown.isAnimating
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                color: accent,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPrinterRow(BuildContext context) {
    final names = widget.printers.map((p) => p.name).toList();
    final isDefault =
        _printerName != null && _printerName == _settings.printerName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _printerName,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'الطابعة',
              prefixIcon: Icon(Icons.print_rounded),
            ),
            items: [
              const DropdownMenuItem<String>(
                child: Text('حوار النظام / معاينة'),
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
            onChanged: (value) {
              setState(() => _printerName = value);
              _restartCountdown();
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: isDefault
              ? 'هذه هي الطابعة المعتمدة'
              : 'اعتمدها للطباعة دون سؤال',
          onPressed: _printerName == null || isDefault
              ? null
              : _saveDefaultPrinter,
          icon: Icon(
            isDefault ? Icons.star_rounded : Icons.star_border_rounded,
            color: AppUi.tone(context, AppColors.brandGoldDark),
          ),
        ),
        IconButton(
          tooltip: 'تخصيص الإيصال من الإعدادات',
          onPressed: () {
            // الرسالة أولاً: بعد إغلاق الحوار يصبح السياق غير صالح.
            receiptToast(
              context,
              'خصص الشعار والعدّاد ومحتوى الإيصال من صفحة الإعدادات',
              color: AppColors.ocean,
            );
            _cancel();
          },
          icon: Icon(
            Icons.tune_rounded,
            color: AppUi.tone(context, AppColors.ocean),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppUi.border(context))),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _working ? null : _cancel,
            icon: const Icon(Icons.close_rounded, size: 17),
            label: const Text('إلغاء'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _settings.autoPrint
                  ? 'تُطبع تلقائياً بعد انتهاء العدّاد — Enter للطباعة الآن'
                  : 'الطباعة يدوية: اضغط «طباعة الآن»',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppUi.textSecondary(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(150, AppDims.controlHeight),
            ),
            onPressed: _working ? null : _submit,
            icon: Icon(
              _working ? Icons.hourglass_top_rounded : Icons.print_rounded,
              size: 18,
            ),
            label: const Text('طباعة الآن'),
          ),
        ],
      ),
    );
  }
}

/// زر خيار صغير يتفاعل مع التغيير بأنميشن ناعم.
class _OptionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.tone(context, selected ? AppColors.brandGreen : AppColors.neutral500);

    return _Hoverable(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7.5),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: hovered ? 0.20 : 0.13)
              : (hovered ? AppUi.hover(context) : AppUi.sunken(context)),
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.55)
                : AppUi.border(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? AppUi.textPrimary(context)
                    : AppUi.textSecondary(context),
              ),
            ),
            const SizedBox(width: 5),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: selected
                  ? Icon(Icons.check_circle_rounded, size: 14, color: accent, key: const ValueKey('on'))
                  : Icon(Icons.radio_button_unchecked_rounded, size: 14, color: AppUi.borderStrong(context), key: const ValueKey('off')),
            ),
          ],
        ),
      ),
    );
  }
}

/// غلاف تفاعل بسيط: يتتبع مرور الفأرة ويمرّر الحالة للبناء.
class _Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback onTap;

  const _Hoverable({required this.builder, required this.onTap});

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}
