import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../widgets/app_ui.dart';

/// استيراد حركات معلقة (غير مستلمة) من Excel أو لصق نصي.
class ImportPendingPage extends StatefulWidget {
  final AppDatabase db;
  final User user;

  const ImportPendingPage({
    super.key,
    required this.db,
    required this.user,
  });

  @override
  State<ImportPendingPage> createState() => _ImportPendingPageState();
}

class _PendingDraft {
  String beneficiary;
  double amount;
  String currencyCode;
  double? amount2;
  String? currencyCode2;
  String note;
  bool selected;

  _PendingDraft({
    required this.beneficiary,
    required this.amount,
    required this.currencyCode,
    this.amount2,
    this.currencyCode2,
    this.note = '',
    // ignore: unused_element_parameter
    this.selected = true,
  });
}

class _ImportPendingPageState extends State<ImportPendingPage> {
  final _pasteController = TextEditingController();
  List<Currency> _currencies = [];
  List<_PendingDraft> _drafts = [];
  bool _loading = true;
  bool _importing = false;
  String? _fileName;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final list = await widget.db.getAllCurrencies();
    if (!mounted) return;
    setState(() {
      _currencies = list;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Currency? _findCurrency(String code) {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return null;
    try {
      return _currencies.firstWhere((e) => e.code.toUpperCase() == c);
    } catch (_) {
      // محاولة مطابقة بالاسم
      try {
        return _currencies.firstWhere(
          (e) => CurrencyDenoms.displayName(e).contains(code.trim()),
        );
      } catch (_) {
        return null;
      }
    }
  }

  /// يفك قيمة خلية Excel (TextCellValue / IntCellValue / ...) إلى قيمة بسيطة.
  dynamic _unwrapCell(dynamic raw) {
    if (raw == null) return null;
    // Data cell wrapper from sheet.rows
    try {
      final dynamic value = (raw as dynamic).value;
      // If raw itself is a CellValue, .value is the primitive/content
      if (value is xls.TextCellValue) return value.value;
      if (value is xls.IntCellValue) return value.value;
      if (value is xls.DoubleCellValue) return value.value;
      if (value is xls.BoolCellValue) return value.value;
      if (value is xls.FormulaCellValue) return value.formula;
      if (value is num || value is String || value is bool) return value;
      if (value != null && value != raw) return _unwrapCell(value);
    } catch (_) {}
    if (raw is xls.TextCellValue) return raw.value;
    if (raw is xls.IntCellValue) return raw.value;
    if (raw is xls.DoubleCellValue) return raw.value;
    if (raw is xls.BoolCellValue) return raw.value;
    if (raw is xls.FormulaCellValue) return raw.formula;
    if (raw is num || raw is String || raw is bool) return raw;
    return raw.toString();
  }

  double? _parseAmount(dynamic raw) {
    final v = _unwrapCell(raw);
    if (v == null) return null;
    if (v is num) return v.toDouble();
    var s = v.toString().trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(',', '').replaceAll('٬', '').replaceAll(' ', '');
    return double.tryParse(s);
  }

  String _cellStr(dynamic raw) {
    final v = _unwrapCell(raw);
    if (v == null) return '';
    return v.toString().trim();
  }

  /// تطبيع اسم العمود للمطابقة المرنة
  String _normHeader(String h) {
    return h
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), '');
  }

  int? _colIndex(List<String> headers, List<String> aliases) {
    final norms = headers.map(_normHeader).toList();
    for (final alias in aliases) {
      final a = _normHeader(alias);
      final i = norms.indexOf(a);
      if (i >= 0) return i;
      // contains
      for (var j = 0; j < norms.length; j++) {
        if (norms[j].contains(a) || a.contains(norms[j])) return j;
      }
    }
    return null;
  }

  List<_PendingDraft> _parseRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];

    // هل الصف الأول عناوين؟
    final first = rows.first.map((e) => _cellStr(e)).toList();
    final looksLikeHeader = first.any((h) {
      final n = _normHeader(h);
      return n.contains('مستفيد') ||
          n.contains('اسم') ||
          n.contains('مبلغ') ||
          n.contains('عمله') ||
          n.contains('beneficiary') ||
          n.contains('amount') ||
          n.contains('currency');
    });

    int start = 0;
    int? iBen;
    int? iAmt;
    int? iCur;
    int? iAmt2;
    int? iCur2;
    int? iNote;

    if (looksLikeHeader) {
      start = 1;
      iBen = _colIndex(first, [
        'المستفيد',
        'اسم المستفيد',
        'الاسم',
        'beneficiary',
        'name',
        'العميل',
      ]);
      iAmt = _colIndex(first, [
        'المبلغ',
        'مبلغ',
        'amount',
        'القيمة',
        'المبلغ1',
      ]);
      iCur = _colIndex(first, [
        'العملة',
        'عمله',
        'currency',
        'كود العملة',
        'رمز',
        'code',
      ]);
      iAmt2 = _colIndex(first, [
        'المبلغ2',
        'مبلغ ثاني',
        'amount2',
        'المبلغ الثاني',
      ]);
      iCur2 = _colIndex(first, [
        'العملة2',
        'عملة ثانية',
        'currency2',
        'العملة الثانية',
      ]);
      iNote = _colIndex(first, [
        'ملاحظة',
        'ملاحظات',
        'note',
        'notes',
        'بيان',
      ]);
    } else {
      // ترتيب افتراضي: مستفيد | مبلغ | عملة | مبلغ2 | عملة2 | ملاحظة
      iBen = 0;
      iAmt = 1;
      iCur = 2;
      iAmt2 = 3;
      iCur2 = 4;
      iNote = 5;
    }

    // إن لم نجد أعمدة أساسية نفترض الترتيب الافتراضي
    iBen ??= 0;
    iAmt ??= 1;
    iCur ??= 2;

    final drafts = <_PendingDraft>[];
    for (var r = start; r < rows.length; r++) {
      final row = rows[r];
      if (row.every((c) => _cellStr(c).isEmpty)) continue;

      String at(int? i) {
        if (i == null || i < 0 || i >= row.length) return '';
        return _cellStr(row[i]);
      }

      final beneficiary = at(iBen);
      final amount = _parseAmount(at(iAmt));
      final currencyCode = at(iCur).toUpperCase();
      final amount2 = iAmt2 != null ? _parseAmount(at(iAmt2)) : null;
      final currencyCode2 =
          iCur2 != null && at(iCur2).isNotEmpty ? at(iCur2).toUpperCase() : null;
      final note = iNote != null ? at(iNote) : '';

      if (beneficiary.isEmpty && (amount == null || amount == 0)) continue;
      if (amount == null || amount <= 0) continue;
      if (currencyCode.isEmpty) continue;

      drafts.add(
        _PendingDraft(
          beneficiary: beneficiary.isEmpty ? '—' : beneficiary,
          amount: amount,
          currencyCode: currencyCode,
          amount2: amount2 != null && amount2 > 0 ? amount2 : null,
          currencyCode2: currencyCode2,
          note: note,
        ),
      );
    }
    return drafts;
  }

  Future<void> _pickExcel() async {
    setState(() {
      _error = null;
      _fileName = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      _fileName = file.name;
      List<int>? bytes = file.bytes;
      // على الموبايل/سطح المكتب قد يأتي المسار بدون bytes
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null) {
        setState(() => _error = 'تعذر قراءة محتوى الملف');
        return;
      }

      List<_PendingDraft> drafts;
      final lower = (file.name).toLowerCase();
      if (lower.endsWith('.csv')) {
        drafts = _parseCsv(utf8.decode(bytes, allowMalformed: true));
      } else {
        drafts = _parseExcelBytes(bytes);
      }

      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        if (drafts.isEmpty) {
          _error =
              'لم يتم العثور على صفوف صالحة. تأكد من الأعمدة: المستفيد، المبلغ، العملة';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'فشل قراءة الملف: $e');
    }
  }

  List<_PendingDraft> _parseExcelBytes(List<int> bytes) {
    final excel = xls.Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];
    final sheet = excel.tables.values.first;
    final rows = <List<dynamic>>[];
    for (final row in sheet.rows) {
      rows.add(row.map((cell) => _unwrapCell(cell)).toList());
    }
    return _parseRows(rows);
  }

  List<_PendingDraft> _parseCsv(String content) {
    final lines = const LineSplitter().convert(content);
    final rows = <List<dynamic>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      // دعم فاصلة أو تاب أو فاصلة منقوطة
      List<String> parts;
      if (line.contains('\t')) {
        parts = line.split('\t');
      } else if (line.contains(';')) {
        parts = line.split(';');
      } else {
        parts = _splitCsvLine(line);
      }
      rows.add(parts);
    }
    return _parseRows(rows);
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    result.add(sb.toString());
    return result;
  }

  void _parsePasted() {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'الصق بيانات أولاً');
      return;
    }
    final drafts = _parseCsv(text);
    setState(() {
      _fileName = 'لصق يدوي';
      _drafts = drafts;
      _error = drafts.isEmpty
          ? 'لم يتم التعرف على صفوف. الصق مثلاً: أحمد|100|USD'
          : null;
    });
  }

  Future<void> _downloadTemplate() async {
    try {
      final excel = xls.Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != 'معلقة') {
        excel.rename(defaultSheet, 'معلقة');
      }
      final sheet = excel['معلقة'];

      final headers = [
        'المستفيد',
        'المبلغ',
        'العملة',
        'المبلغ2',
        'العملة2',
        'ملاحظة',
      ];
      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = xls.TextCellValue(headers[i]);
      }

      final samples = [
        ['محمد أحمد', '500', 'USD', '', '', 'حوالة من دمشق'],
        ['سارة علي', '1000000', 'SYP', '50', 'USD', 'معلقة للتسليم'],
      ];
      for (var r = 0; r < samples.length; r++) {
        for (var c = 0; c < samples[r].length; c++) {
          sheet
              .cell(
                xls.CellIndex.indexByColumnRow(
                  columnIndex: c,
                  rowIndex: r + 1,
                ),
              )
              .value = xls.TextCellValue(samples[r][c]);
        }
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('encode failed');

      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'tima_pending_template.xlsx'));
      await file.writeAsBytes(bytes, flush: true);

      // محاولة الحفظ عبر file_picker إن أمكن (API v11+: static methods)
      try {
        await FilePicker.saveFile(
          dialogTitle: 'حفظ قالب الاستيراد',
          fileName: 'tima_pending_template.xlsx',
          bytes: Uint8List.fromList(bytes),
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
      } catch (_) {
        // على بعض المنصات saveFile غير مدعوم
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنشاء القالب:\n${file.path}'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء القالب: $e')),
      );
    }
  }

  Future<void> _confirmImport() async {
    final selected = _drafts.where((d) => d.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر صفاً واحداً على الأقل')),
      );
      return;
    }

    // تحقق من العملات
    final missing = <String>{};
    for (final d in selected) {
      if (_findCurrency(d.currencyCode) == null) missing.add(d.currencyCode);
      if (d.currencyCode2 != null &&
          d.currencyCode2!.isNotEmpty &&
          _findCurrency(d.currencyCode2!) == null) {
        missing.add(d.currencyCode2!);
      }
    }
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'عملات غير معرّفة في النظام: ${missing.join(', ')}\nأضفها من الإعدادات أولاً',
          ),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستيراد'),
        content: Text(
          'سيتم تسجيل ${selected.length} حركة تسليم معلقة (غير مستلمة بعد).\nهل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استيراد'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _importing = true);
    var count = 0;
    try {
      for (final d in selected) {
        final cur = _findCurrency(d.currencyCode)!;
        final cur2 = d.currencyCode2 != null && d.amount2 != null
            ? _findCurrency(d.currencyCode2!)
            : null;

        final noteParts = <String>[];
        if (d.note.isNotEmpty) noteParts.add(d.note);
        noteParts.add('[مستورد من ${_fileName ?? "ملف"}]');

        await widget.db.insertTransaction(
          TransactionsCompanion.insert(
            userId: widget.user.id,
            currencyId: cur.id,
            targetCurrencyId: cur2 != null
                ? drift.Value(cur2.id)
                : const drift.Value.absent(),
            targetAmount: d.amount2 != null
                ? drift.Value(d.amount2)
                : const drift.Value.absent(),
            createdByName: drift.Value(widget.user.username),
            type: 'حركة تسليم',
            beneficiary: drift.Value(d.beneficiary),
            amount: d.amount,
            note: drift.Value(noteParts.join(' — ')),
            movementState: const drift.Value('مفعلة'),
            status: const drift.Value('مضافة'),
          ),
        );
        count++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ تم استيراد $count حركة معلقة بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاستيراد: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: 'استيراد حركات معلقة',
        actions: [
          IconButton(
            tooltip: 'تحميل قالب Excel',
            onPressed: _downloadTemplate,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: TimaPageBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const TimaSectionTitle(
                    icon: Icons.upload_file_rounded,
                    title: 'رفع ملف أو لصق بيانات',
                    subtitle:
                        'استورد الحركات غير المستلمة دفعة واحدة كـ «حركة تسليم معلقة»',
                  ),
                  const SizedBox(height: 12),
                  TimaPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'الأعمدة المدعومة: المستفيد | المبلغ | العملة | المبلغ2 | العملة2 | ملاحظة',
                          style: TextStyle(fontSize: 12, color: AppColors.neutral500),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _importing ? null : _pickExcel,
                          icon: const Icon(Icons.folder_open),
                          label: Text(
                            _fileName == null
                                ? 'اختيار ملف Excel / CSV'
                                : 'ملف: $_fileName',
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'أو الصق صفوفاً (مفصولة بـ Tab أو فاصلة):',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _pasteController,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText:
                                'محمد أحمد, 500, USD\nسارة, 1000000, SYP, 50, USD, ملاحظة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _importing ? null : _parsePasted,
                          icon: const Icon(Icons.content_paste_go_rounded),
                          label: const Text('تحليل النص الملصوق'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppDims.radiusSm),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ],
                  if (_drafts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'معاينة: ${_drafts.where((d) => d.selected).length}/${_drafts.length}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {
                            for (final d in _drafts) {
                              d.selected = true;
                            }
                          }),
                          child: const Text('تحديد الكل'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            for (final d in _drafts) {
                              d.selected = false;
                            }
                          }),
                          child: const Text('إلغاء الكل'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._drafts.asMap().entries.map((entry) {
                      final i = entry.key;
                      final d = entry.value;
                      final curOk = _findCurrency(d.currencyCode) != null;
                      final cur2Ok = d.currencyCode2 == null ||
                          _findCurrency(d.currencyCode2!) != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: CheckboxListTile(
                          value: d.selected,
                          onChanged: (v) =>
                              setState(() => d.selected = v ?? false),
                          title: Text(
                            d.beneficiary,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${d.amount.toStringAsFixed(2)} ${d.currencyCode}'
                                '${d.amount2 != null ? " + ${d.amount2!.toStringAsFixed(2)} ${d.currencyCode2}" : ""}',
                              ),
                              if (d.note.isNotEmpty)
                                Text(
                                  d.note,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (!curOk || !cur2Ok)
                                Text(
                                  '⚠ عملة غير معرّفة',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          secondary: CircleAvatar(
                            backgroundColor: AppColors.brandGold.withValues(alpha: 0.2),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _importing ? null : _confirmImport,
                      icon: _importing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(
                        'استيراد ${_drafts.where((d) => d.selected).length} حركة معلقة',
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TimaPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ملاحظات',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '• الصفوف تُسجَّل كـ «حركة تسليم» بحالة «مضافة» (معلقة).\n'
                          '• لا تُخصم من الصندوق حتى تؤكد التسليم من تبويب المعلقة.\n'
                          '• رمز العملة يجب أن يطابق عملة مضافة مسبقاً (USD, SYP...).\n'
                          '• يمكنك تحميل قالب Excel من أيقونة التحميل أعلى الصفحة.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
