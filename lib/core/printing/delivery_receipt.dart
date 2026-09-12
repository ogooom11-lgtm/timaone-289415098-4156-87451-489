import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../storage/app_database.dart';
import '../storage/device_settings.dart';
import '../utils/currency_denoms.dart';
import 'receipt_settings.dart';

/// بيانات إيصال التسليم.
///
/// ملاحظة: الملاحظة [note] لا تُطبع إلا إذا كتبها المستخدم في نافذة
/// الطباعة، والحالة و«المسلّم» مطفأتان افتراضياً من إعدادات الإيصال.
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
  final String officeName;
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
    this.officeName = '',
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
      currencyName2: currency2 == null
          ? null
          : CurrencyDenoms.displayName(currency2),
      denoms1: denoms1,
      denoms2: denoms2,
      status: statusOverride ?? (tx.status.isNotEmpty ? tx.status : 'تم التسليم'),
      dateTime: DateTime.now(),
      note: _cleanNote(tx.note),
      createdBy: createdBy.isNotEmpty ? createdBy : tx.createdByName,
      branch: branch,
      transactionId: tx.id,
    );
  }

  /// يبني بيانات إيصال من حركة محفوظة في أي وقت (إعادة طباعة).
  ///
  /// الفئات تُستخرج من ملاحظة الحركة إن كانت مسجّلة فيها.
  factory DeliveryReceiptData.fromStoredTransaction({
    required Transaction tx,
    required Currency currency1,
    Currency? currency2,
    String createdBy = '',
    String branch = '',
  }) {
    return DeliveryReceiptData.fromTransaction(
      tx: tx,
      currency1: currency1,
      currency2: currency2,
      denoms1: CurrencyDenoms.parseCounts(
        CurrencyDenoms.extractDeliveredDenomsNote(tx.note),
      ),
      denoms2: CurrencyDenoms.parseCounts(
        CurrencyDenoms.extractDeliveredDenomsNote2(tx.note),
      ),
      createdBy: createdBy,
      branch: branch,
    );
  }

  DeliveryReceiptData copyWith({
    String? beneficiary,
    String? status,
    DateTime? dateTime,
    String? note,
    String? createdBy,
    String? branch,
    String? officeName,
  }) {
    return DeliveryReceiptData(
      beneficiary: beneficiary ?? this.beneficiary,
      amount: amount,
      currencyCode: currencyCode,
      currencyName: currencyName,
      amount2: amount2,
      currencyCode2: currencyCode2,
      currencyName2: currencyName2,
      denoms1: denoms1,
      denoms2: denoms2,
      status: status ?? this.status,
      dateTime: dateTime ?? this.dateTime,
      note: note ?? this.note,
      createdBy: createdBy ?? this.createdBy,
      branch: branch ?? this.branch,
      officeName: officeName ?? this.officeName,
      transactionId: transactionId,
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

/// بناء ملف الإيصال وإرساله إلى الطابعة.
///
/// هذه الطبقة لا تحتوي أي ودجات: الحوارات (خيارات الطباعة والعدّاد) في
/// `lib/presentation/widgets/receipt_print_dialog.dart`.
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
    return DateFormat('yyyy/MM/dd  HH:mm').format(d.toLocal());
  }

  static String _fmtDenom(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toString();

  /// يقرأ الشعار: الصورة المخصّصة إن وُجدت، وإلا شعار تيما المدمج.
  static Future<Uint8List?> _logoBytes(ReceiptSettings settings) async {
    if (!settings.showLogo) return null;

    final path = settings.logoPath;
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) return await file.readAsBytes();
      } catch (_) {
        // صورة مفقودة أو غير مقروءة — نرجع للشعار المدمج.
      }
    }

    try {
      final data = await rootBundle.load('assets/images/tima_logo.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static PdfPageFormat _pageFormat(ReceiptSettings settings) {
    final base = PdfPageFormat.roll80;
    if (settings.paperWidthMm >= 80) return base;
    // 58mm تُشتق من قياس 80mm المعتمد بدل ثوابت قد لا تتوفر في الحزمة.
    return PdfPageFormat(base.width * 58 / 80, base.height);
  }

  /// يبني ملف PDF للإيصال حسب الإعدادات المعتمدة.
  static Future<Uint8List> buildPdf(
    DeliveryReceiptData data,
    ReceiptSettings settings,
  ) async {
    await _ensureFonts();
    final font = _fontRegular!;
    final bold = _fontBold!;

    final doc = pw.Document();
    final logoBytes = await _logoBytes(settings);
    final logoImage = logoBytes == null ? null : pw.MemoryImage(logoBytes);

    final ink = PdfColor.fromInt(0xFF1B1B1B);
    final green = PdfColor.fromInt(0xFF0B5D4B);
    final gold = PdfColor.fromInt(0xFFB8860B);
    final line = PdfColor.fromInt(0xFFB9B9B9);
    final muted = PdfColor.fromInt(0xFF6B6B6B);

    final compact = settings.paperWidthMm <= 58;
    final labelWidth = compact ? 52.0 : 66.0;

    pw.Widget infoRow(String label, String value, {bool strong = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: labelWidth,
              child: pw.Text(
                label,
                style: pw.TextStyle(font: bold, fontSize: 9.5, color: muted),
                textDirection: pw.TextDirection.rtl,
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  font: strong ? bold : font,
                  fontSize: strong ? 11 : 10.5,
                  color: ink,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget hairline({bool dashed = false}) => pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      height: dashed ? 1.2 : 0.8,
      color: line,
    );

    pw.Widget sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: bold, fontSize: 9.5, color: green),
        textDirection: pw.TextDirection.rtl,
      ),
    );

    // --- الترويسة حسب موضع الشعار ---
    pw.Widget titleBlock() => pw.Column(
      crossAxisAlignment: settings.logoPosition ==
              ReceiptLogoPosition.topCenter
          ? pw.CrossAxisAlignment.center
          : pw.CrossAxisAlignment.start,
      children: [
        if (settings.showOfficeName && data.officeName.isNotEmpty)
          pw.Text(
            data.officeName,
            style: pw.TextStyle(font: bold, fontSize: 10.5, color: gold),
            textDirection: pw.TextDirection.rtl,
          ),
        pw.SizedBox(height: 1),
        pw.Text(
          settings.title,
          style: pw.TextStyle(font: bold, fontSize: 15, color: green),
          textDirection: pw.TextDirection.rtl,
        ),
        if (settings.showTransactionId && data.transactionId != null)
          pw.Text(
            'رقم العملية: #${data.transactionId}',
            style: pw.TextStyle(font: font, fontSize: 8.5, color: muted),
            textDirection: pw.TextDirection.rtl,
          ),
      ],
    );

    pw.Widget logoBox() => pw.Container(
      width: settings.logoWidth,
      height: settings.logoWidth * 0.62,
      child: pw.Image(logoImage!, fit: pw.BoxFit.contain),
    );

    pw.Widget header() {
      final hasLogo = logoImage != null;
      if (!hasLogo || settings.logoPosition == ReceiptLogoPosition.bottom) {
        return titleBlock();
      }
      if (settings.logoPosition == ReceiptLogoPosition.topCenter) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            logoBox(),
            pw.SizedBox(height: 4),
            titleBlock(),
          ],
        );
      }
      final isRight = settings.logoPosition == ReceiptLogoPosition.topRight;
      // داخل اتجاه RTL العنصر الأول يقف على اليمين.
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (isRight) logoBox(),
          pw.SizedBox(width: 8),
          pw.Expanded(child: titleBlock()),
          if (!isRight) logoBox(),
        ],
      );
    }

    // --- صندوق المبلغ البارز ---
    pw.Widget amountBox(double amount, String label, String unit) {
      return pw.Container(
        padding: pw.EdgeInsets.symmetric(
          horizontal: compact ? 6 : 9,
          vertical: compact ? 5 : 7,
        ),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: green, width: 0.9),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    label,
                    style: pw.TextStyle(font: font, fontSize: 8.5, color: muted),
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.Text(
                    unit,
                    style: pw.TextStyle(font: bold, fontSize: 9.5, color: green),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
              ),
            ),
            pw.Text(
              _fmtAmount(amount),
              style: pw.TextStyle(
                font: bold,
                fontSize: compact ? 14 : 16,
                color: ink,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
          ],
        ),
      );
    }

    // --- جدول تفصيل الفئات ---
    pw.Widget denomsTable(Map<double, int> counts, String code) {
      final keys = counts.keys.toList()..sort((a, b) => b.compareTo(a));
      final rows = <pw.TableRow>[];

      pw.TextStyle headStyle() => pw.TextStyle(
        font: bold,
        fontSize: 9,
        color: green,
      );
      pw.TextStyle cellStyle({bool strong = false}) => pw.TextStyle(
        font: strong ? bold : font,
        fontSize: 9.5,
        color: ink,
      );

      pw.Widget cell(String text, pw.TextStyle style) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
        child: pw.Text(
          text,
          style: style,
          textDirection: pw.TextDirection.rtl,
        ),
      );

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F1F1)),
          children: [
            cell('الفئة ($code)', headStyle()),
            cell('العدد', headStyle()),
            cell('القيمة', headStyle()),
          ],
        ),
      );

      var total = 0.0;
      for (final denom in keys) {
        final count = counts[denom] ?? 0;
        if (count <= 0) continue;
        final value = denom * count;
        total += value;
        rows.add(
          pw.TableRow(
            children: [
              cell(_fmtDenom(denom), cellStyle()),
              cell('$count', cellStyle()),
              cell(_fmtAmount(value), cellStyle()),
            ],
          ),
        );
      }

      rows.add(
        pw.TableRow(
          children: [
            cell('المجموع', headStyle()),
            cell('', headStyle()),
            cell(_fmtAmount(total), headStyle()),
          ],
        ),
      );

      return pw.Table(
        columnWidths: <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(2.2),
          1: pw.FlexColumnWidth(1.1),
          2: pw.FlexColumnWidth(1.9),
        },
        border: pw.TableBorder.all(color: line, width: 0.5),
        children: rows,
      );
    }

    final hasDenoms1 = data.denoms1.values.any((v) => v > 0);
    final hasDenoms2 =
        data.denoms2 != null && data.denoms2!.values.any((v) => v > 0);
    final hasAmount2 =
        data.amount2 != null && data.amount2! > 0 && data.currencyCode2 != null;
    final note = data.note.trim();

    doc.addPage(
      pw.Page(
        pageFormat: _pageFormat(settings),
        margin: pw.EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 8 : 10,
        ),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: ink, width: 1.1),
                borderRadius: pw.BorderRadius.circular(3),
              ),
              padding: pw.EdgeInsets.fromLTRB(
                compact ? 7 : 10,
                compact ? 7 : 10,
                compact ? 7 : 10,
                compact ? 8 : 11,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  header(),
                  hairline(),

                  // بيانات الحركة
                  infoRow('الاسم :', data.beneficiary, strong: true),
                  if (settings.showDateTime)
                    infoRow('التاريخ :', _fmtDate(data.dateTime)),
                  if (settings.showStatus && data.status.isNotEmpty)
                    infoRow('الحالة :', data.status),
                  if (settings.showCreatedBy && data.createdBy.isNotEmpty)
                    infoRow('المسلّم :', data.createdBy),
                  if (settings.showBranch && data.branch.isNotEmpty)
                    infoRow('المكتب :', data.branch),

                  pw.SizedBox(height: 4),
                  amountBox(
                    data.amount,
                    'المبلغ',
                    data.currencyName.isNotEmpty
                        ? data.currencyName
                        : data.currencyCode,
                  ),
                  if (hasAmount2) ...[
                    pw.SizedBox(height: 4),
                    amountBox(
                      data.amount2!,
                      'المبلغ الثاني',
                      (data.currencyName2 ?? data.currencyCode2)!,
                    ),
                  ],

                  // تفصيل العملات
                  if (settings.showDenominations && (hasDenoms1 || hasDenoms2)) ...[
                    hairline(),
                    sectionTitle('تفصيل العملات'),
                    pw.SizedBox(height: 2),
                    if (hasDenoms1) denomsTable(data.denoms1, data.currencyCode),
                    if (hasDenoms2) ...[
                      pw.SizedBox(height: 5),
                      sectionTitle(
                        'فئات المبلغ الثاني (${data.currencyCode2})',
                      ),
                      pw.SizedBox(height: 2),
                      denomsTable(data.denoms2!, data.currencyCode2!),
                    ],
                  ],

                  // ملاحظة المستخدم — تُطبع فقط إذا كُتبت
                  if (note.isNotEmpty) ...[
                    hairline(),
                    sectionTitle('ملاحظة'),
                    pw.Text(
                      note,
                      style: pw.TextStyle(font: font, fontSize: 10, color: ink),
                      textDirection: pw.TextDirection.rtl,
                      softWrap: true,
                    ),
                  ],

                  pw.SizedBox(height: 10),
                  pw.Center(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3.5,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: green, width: 0.9),
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      child: pw.Text(
                        data.status.isEmpty ? 'تم التسليم' : data.status,
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 11.5,
                          color: green,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ),
                  ),

                  if (settings.showFooter && settings.footerMessage.isNotEmpty) ...[
                    pw.SizedBox(height: 5),
                    pw.Center(
                      child: pw.Text(
                        settings.footerMessage,
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 8.5,
                          color: muted,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ),
                  ],

                  if (settings.showLogo &&
                      logoImage != null &&
                      settings.logoPosition == ReceiptLogoPosition.bottom) ...[
                    pw.SizedBox(height: 8),
                    pw.Center(child: logoBox()),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  /// يبني الإيصال ويُرسله إلى الطابعة المختارة.
  ///
  /// `printer == null` يفتح حوار الطباعة/المعاينة الخاص بالنظام.
  static Future<void> sendToPrinter({
    required DeliveryReceiptData data,
    required ReceiptSettings settings,
    Printer? printer,
    String? jobName,
  }) async {
    final bytes = await buildPdf(data, settings);
    final name =
        jobName ??
        'delivery_receipt_${data.transactionId ?? DateTime.now().millisecondsSinceEpoch}';

    if (printer != null) {
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        name: name,
      );
      return;
    }

    await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
  }

  /// قائمة الطابعات المتاحة — قائمة فارغة عند تعذّر القراءة.
  static Future<List<Printer>> availablePrinters() async {
    try {
      return await Printing.listPrinters();
    } catch (_) {
      return const [];
    }
  }

  /// اسم المكتب المحفوظ في الإعدادات (يُطبع في الترويسة).
  static Future<String> officeName() async =>
      (await DeviceSettings.officeName()) ?? '';
}
