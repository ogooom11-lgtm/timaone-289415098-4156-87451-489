import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../storage/app_database.dart';
import '../storage/device_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/currency_denoms.dart';

/// بيانات إيصال التسليم.
class DeliveryReceiptData {
  final String beneficiary;
  final double amount;
  final String currencyCode;
  final String currencyName;
  final double? amount2;
  final String? currencyCode2;
  final String? currencyName2;
  final Map<double, int> denoms1;
  final Map<double, int>? denoms2;
  final String status;
  final DateTime dateTime;
  final String note;
  final String createdBy;
  final String branch;
  final int? transactionId;

  const DeliveryReceiptData({
    required this.beneficiary,
    required this.amount,
    required this.currencyCode,
    required this.currencyName,
    this.amount2,
    this.currencyCode2,
    this.currencyName2,
    required this.denoms1,
    this.denoms2,
    this.status = 'تم التسليم',
    required this.dateTime,
    this.note = '',
    this.createdBy = '',
    this.branch = '',
    this.transactionId,
  });

  factory DeliveryReceiptData.fromTransaction({
    required Transaction tx,
    required Currency currency1,
    Currency? currency2,
    required Map<double, int> denoms1,
    Map<double, int>? denoms2,
    String createdBy = '',
    String branch = '',
    String? statusOverride,
  }) {
    return DeliveryReceiptData(
      beneficiary: tx.beneficiary?.trim().isNotEmpty == true
          ? tx.beneficiary!.trim()
          : '—',
      amount: tx.amount,
      currencyCode: currency1.code,
      currencyName: CurrencyDenoms.displayName(currency1),
      amount2: tx.targetAmount,
      currencyCode2: currency2?.code,
      currencyName2:
      currency2 == null ? null : CurrencyDenoms.displayName(currency2),
      denoms1: denoms1,
      denoms2: denoms2,
      status: statusOverride ??
          (tx.status.isNotEmpty ? tx.status : 'تم التسليم'),
      dateTime: DateTime.now(),
      note: _cleanNote(tx.note),
      createdBy: createdBy.isNotEmpty ? createdBy : tx.createdByName,
      branch: branch,
      transactionId: tx.id,
    );
  }

  static String _cleanNote(String? note) {
    if (note == null || note.trim().isEmpty) return '';
    return note
        .replaceAll(RegExp(r'\[تم التسليم في [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم 2: [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[فئات المسلم: [^\]]+\]'), '')
        .replaceAll(RegExp(r'\[الفئات المسلمة[^\]]*\]'), '')
        .trim();
  }
}

class DeliveryReceiptService {
  DeliveryReceiptService._();

  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  static Future<void> _ensureFonts() async {
    if (_fontRegular != null && _fontBold != null) return;
    final reg = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final bold = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Bold.ttf',
    );
    _fontRegular = pw.Font.ttf(reg);
    _fontBold = pw.Font.ttf(bold);
  }

  static String _fmtAmount(double v) {
    final f = NumberFormat('#,##0.##', 'en');
    return f.format(v);
  }

  static String _fmtDate(DateTime d) {
    return DateFormat('yyyy/MM/dd HH:mm:ss').format(d.toLocal());
  }

  static String _denomsLines(Map<double, int> counts, String code) {
    final parts = <String>[];
    final keys = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final d in keys) {
      final c = counts[d] ?? 0;
      if (c <= 0) continue;
      final label =
      d == d.roundToDouble() ? d.toInt().toString() : d.toString();
      parts.add('$label $code × $c');
    }
    return parts.isEmpty ? '—' : parts.join('\n');
  }

  static Future<Uint8List?> _logoBytes() async {
    try {
      final data = await rootBundle.load('assets/images/tima_logo.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> buildPdf(DeliveryReceiptData data) async {
    await _ensureFonts();
    final font = _fontRegular!;
    final bold = _fontBold!;

    final doc = pw.Document();
    final logo = await _logoBytes();
    final logoImage = logo == null ? null : pw.MemoryImage(logo);

    final borderColor = PdfColor.fromInt(0xFF222222);
    final green = PdfColor.fromInt(0xFF0B5D4B);
    final gold = PdfColor.fromInt(0xFFE6B84A);

    pw.Widget row(String label, String value, {bool strong = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 78,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 11,
                  color: green,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  font: strong ? bold : font,
                  fontSize: 12,
                ),
                textAlign: pw.TextAlign.right,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget divider() => pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 3),
      height: 1,
      color: PdfColors.grey400,
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderColor, width: 1.3),
              ),
              padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Header: title + logo
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'إيصال تسليم',
                              style: pw.TextStyle(
                                font: bold,
                                fontSize: 16,
                                color: green,
                              ),
                            ),
                            if (data.transactionId != null)
                              pw.Text(
                                'رقم العملية: ${data.transactionId}',
                                style: pw.TextStyle(
                                  font: font,
                                  fontSize: 9,
                                  color: PdfColors.grey700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (logoImage != null)
                        pw.Container(
                          width: 56,
                          height: 36,
                          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                        )
                      else
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: pw.BoxDecoration(
                            color: green,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(
                            'تيما',
                            style: pw.TextStyle(
                              font: bold,
                              color: gold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  divider(),
                  row('الاسم :', data.beneficiary, strong: true),
                  divider(),
                  row(
                    'المبلغ :',
                    '${_fmtAmount(data.amount)}   ${data.currencyName.isNotEmpty ? data.currencyName : data.currencyCode}',
                    strong: true,
                  ),
                  if (data.amount2 != null &&
                      data.amount2! > 0 &&
                      data.currencyCode2 != null) ...[
                    divider(),
                    row(
                      'المبلغ 2 :',
                      '${_fmtAmount(data.amount2!)}   ${data.currencyName2 ?? data.currencyCode2}',
                      strong: true,
                    ),
                  ],
                  divider(),
                  row('الحالة:', data.status),
                  divider(),
                  row('التاريخ:', _fmtDate(data.dateTime)),
                  if (data.createdBy.isNotEmpty) ...[
                    divider(),
                    row('المسلّم:', data.createdBy),
                  ],
                  if (data.branch.isNotEmpty) ...[
                    divider(),
                    row('الفرع:', data.branch),
                  ],
                  divider(),
                  pw.Text(
                    'تفصيل الفئات:',
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 11,
                      color: green,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _denomsLines(data.denoms1, data.currencyCode),
                    style: pw.TextStyle(font: font, fontSize: 11),
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.right,
                  ),
                  if (data.denoms2 != null &&
                      data.currencyCode2 != null &&
                      data.denoms2!.values.any((v) => v > 0)) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'فئات المبلغ 2 (${data.currencyCode2}):',
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 11,
                        color: green,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _denomsLines(data.denoms2!, data.currencyCode2!),
                      style: pw.TextStyle(font: font, fontSize: 11),
                      textDirection: pw.TextDirection.rtl,
                      textAlign: pw.TextAlign.right,
                    ),
                  ],
                  divider(),
                  row(
                    'ملاحظة:',
                    data.note.isEmpty ? 'تم التسليم' : data.note,
                  ),
                  pw.SizedBox(height: 12),
                  pw.Center(
                    child: pw.Text(
                      'تم التسليم',
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 13,
                        color: green,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Center(
                    child: pw.Text(
                      'شكراً لتعاملكم مع تيما',
                      style: pw.TextStyle(
                        font: font,
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  /// بعد نجاح التسليم: يسأل هل تريد طباعة إيصال؟
  static Future<void> offerPrintAfterDelivery(
      BuildContext context,
      DeliveryReceiptData data,
      ) async {
    if (!context.mounted) return;

    final wantPrint = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDims.radiusLg),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              SizedBox(width: 8),
              Expanded(child: Text('تمت العملية بنجاح')),
            ],
          ),
          content: const Text(
            'هل تريد طباعة إيصال التسليم؟',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.print),
              label: const Text('نعم، طباعة'),
            ),
          ],
        ),
      ),
    );

    if (wantPrint != true || !context.mounted) return;
    await printReceipt(context, data);
  }

  /// اختيار طابعة / معاينة / طباعة + حفظ افتراضية.
  static Future<void> printReceipt(
      BuildContext context,
      DeliveryReceiptData data,
      ) async {
    try {
      final bytes = await buildPdf(data);
      final defaultName = await DeviceSettings.defaultPrinterName();

      List<Printer> printers = const [];
      try {
        printers = await Printing.listPrinters();
      } catch (_) {
        printers = const [];
      }

      if (!context.mounted) return;

      // إذا توجد طابعات نعرض قائمة اختيار
      if (printers.isNotEmpty) {
        final selected = await showModalBottomSheet<_PrinterChoice>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'اختر الطابعة',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      if (defaultName != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'الافتراضية: $defaultName',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.neutral600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: printers.length,
                          itemBuilder: (_, i) {
                            final p = printers[i];
                            final isDefault =
                                defaultName != null && p.name == defaultName;
                            return ListTile(
                              leading: Icon(
                                Icons.print,
                                color: isDefault
                                    ? AppColors.brandGold
                                    : AppColors.brandGreen,
                              ),
                              title: Text(p.name),
                              subtitle:
                              isDefault ? const Text('طابعة افتراضية') : null,
                              trailing: IconButton(
                                tooltip: 'تعيين كافتراضية',
                                icon: Icon(
                                  isDefault ? Icons.star : Icons.star_border,
                                  color: AppColors.brandGold,
                                ),
                                onPressed: () async {
                                  await DeviceSettings.saveDefaultPrinterName(
                                    p.name,
                                  );
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'تم تعيين "${p.name}" كطابعة افتراضية',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                              onTap: () => Navigator.pop(
                                ctx,
                                _PrinterChoice(printer: p),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(
                          ctx,
                          const _PrinterChoice(useSystemDialog: true),
                        ),
                        icon: const Icon(Icons.preview),
                        label: const Text('معاينة / حوار النظام'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إلغاء'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        if (selected == null) return;

        if (selected.printer != null) {
          await Printing.directPrintPdf(
            printer: selected.printer!,
            onLayout: (_) async => bytes,
            name: 'delivery_receipt_${data.transactionId ?? DateTime.now().millisecondsSinceEpoch}',
          );
          return;
        }
      }

      // fallback / system dialog / preview
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name:
        'delivery_receipt_${data.transactionId ?? DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الطباعة: $e')),
      );
    }
  }
}

class _PrinterChoice {
  final Printer? printer;
  final bool useSystemDialog;

  const _PrinterChoice({
    this.printer,
    this.useSystemDialog = false,
  });
}


