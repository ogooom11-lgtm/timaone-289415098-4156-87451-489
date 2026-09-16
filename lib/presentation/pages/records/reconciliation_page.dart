import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';

/// حالة مطابقة العنصر (حركة / صف / علامة).
enum MatchState { none, matched, notMatched }

enum _FileKind { none, pdf, excel }

/// علامة على صفحة PDF — تُحفظ كنِسب من أبعاد الصفحة لتبقى صحيحة مع أي تكبير.
class _PdfMark {
  final double dx;
  final double dy;
  final bool matched;
  const _PdfMark(this.dx, this.dy, this.matched);
}

/// صفحة مطابقة الصندوق — قسمان:
///  • قسم الملف (PDF/Excel) مع إمكانية وضع علامات داخل التطبيق (دون تعديل الملف).
///  • قسم الحركات: زر الفأرة الأيسر = مطابق، الأيمن = غير مطابق.
class ReconciliationPage extends StatefulWidget {
  final AppDatabase db;
  final User user;

  const ReconciliationPage({super.key, required this.db, required this.user});

  @override
  State<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _ReconciliationPageState extends State<ReconciliationPage> {
  // ---- الملف ----
  _FileKind _kind = _FileKind.none;
  String _fileName = '';
  bool _loadingFile = false;
  String? _fileError;
  List<Uint8List> _pdfPages = [];
  List<Size> _pdfSizes = [];
  List<List<String>> _excelRows = [];
  final Map<int, List<_PdfMark>> _pdfMarks = {};
  final Map<int, MatchState> _excelMarks = {};

  // ---- الحركات ----
  List<Transaction> _transactions = [];
  Map<int, Currency> _currencies = {};
  final Map<int, MatchState> _txState = {};
  bool _loadingTx = true;
  String _search = '';
  bool _onlyUnmarked = false;

  /// ترتيب الحركات: dateNew|dateOld|amountHigh|amountLow|name|status
  String _txSort = 'dateNew';

  // ---- التقسيم ----
  double _split = 0.55;

  @override
  void initState() {
    super.initState();
    _loadTx();
  }

  Future<void> _loadTx() async {
    final txs = await widget.db.getAllTransactions();
    final curs = await widget.db.getAllCurrencies();
    if (!mounted) return;
    setState(() {
      _transactions = txs
          .where((t) => t.movementState != 'ملغية' && t.status != 'الغاء')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _currencies = {for (final c in curs) c.id: c};
      _loadingTx = false;
    });
  }

  // ---------------- الملف ----------------

  Future<void> _openFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'xlsx', 'xls'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    setState(() {
      _loadingFile = true;
      _fileError = null;
      _fileName = file.name;
    });

    try {
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) throw Exception('تعذّر قراءة بايتات الملف');

      final ext = file.name.split('.').last.toLowerCase();
      if (ext == 'pdf') {
        final pages = <Uint8List>[];
        final sizes = <Size>[];
        await for (final p in Printing.raster(bytes, dpi: 130)) {
          pages.add(await p.toPng());
          sizes.add(Size(p.width.toDouble(), p.height.toDouble()));
        }
        if (!mounted) return;
        setState(() {
          _kind = _FileKind.pdf;
          _pdfPages = pages;
          _pdfSizes = sizes;
          _pdfMarks.clear();
        });
      } else {
        final excel = xls.Excel.decodeBytes(bytes);
        final rows = <List<String>>[];
        if (excel.tables.isNotEmpty) {
          final sheet = excel.tables.values.first;
          for (final row in sheet.rows) {
            rows.add(row.map<String>((c) => _unwrapCell(c)?.toString() ?? '').toList());
          }
        }
        if (!mounted) return;
        setState(() {
          _kind = _FileKind.excel;
          _excelRows = rows;
          _excelMarks.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _kind = _FileKind.none;
        _fileError = '$e';
      });
      _toast('تعذّر فتح الملف: $e', false);
    } finally {
      if (mounted) setState(() => _loadingFile = false);
    }
  }

  dynamic _unwrapCell(dynamic raw) {
    if (raw == null) return null;
    try {
      final dynamic value = (raw as dynamic).value;
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

  // ---------------- العلامات ----------------

  void _toggle(Map<int, MatchState> map, int key, MatchState s) {
    setState(() {
      if (map[key] == s) {
        map.remove(key);
      } else {
        map[key] = s;
      }
    });
  }

  void _markTx(int id, MatchState s) => _toggle(_txState, id, s);
  void _markRow(int i, MatchState s) => _toggle(_excelMarks, i, s);

  void _addPdfMark(int page, double dx, double dy, bool matched) {
    setState(() {
      (_pdfMarks[page] ??= <_PdfMark>[]).add(_PdfMark(dx, dy, matched));
    });
  }

  void _clearPageMarks(int page) => setState(() => _pdfMarks.remove(page));

  void _resetAll() {
    setState(() {
      _txState.clear();
      _excelMarks.clear();
      _pdfMarks.clear();
    });
    _toast('تم مسح كل العلامات', true);
  }

  String _nameOf(Transaction t) =>
      (t.beneficiary?.trim().isNotEmpty == true) ? t.beneficiary!.trim() : t.type;

  /// نسخ أسماء الحركات (ضمن المعروض حالياً): matched | notMatched | all.
  Future<void> _copyNames(String which, bool withAmounts) async {
    final names = <String>[];
    for (final t in _filteredTx()) {
      final s = _txState[t.id] ?? MatchState.none;
      if (which == 'matched' && s != MatchState.matched) continue;
      if (which == 'notMatched' && s != MatchState.notMatched) continue;
      final name = _nameOf(t);
      names.add(
        withAmounts ? '$name — ${_fmt(t.amount)} ${_code(t.currencyId)}' : name,
      );
    }
    if (names.isEmpty) {
      _toast('لا توجد أسماء للنسخ ضمن المعروض', false);
      return;
    }
    await Clipboard.setData(ClipboardData(text: names.join('\n')));
    if (!mounted) return;
    _toast('تم نسخ ${names.length} اسم', true);
  }

  /// نسخ اسم حركة واحدة.
  Future<void> _copySingleName(String name) async {
    if (name.trim().isEmpty) {
      _toast('لا يوجد اسم للنسخ', false);
      return;
    }
    await Clipboard.setData(ClipboardData(text: name));
    if (!mounted) return;
    _toast('تم نسخ الاسم', true);
  }

  /// تعليم كل الحركات المعروضة حالياً بحالة واحدة (أو مسح علاماتها).
  void _markVisible(MatchState s) {
    setState(() {
      for (final t in _filteredTx()) {
        if (s == MatchState.none) {
          _txState.remove(t.id);
        } else {
          _txState[t.id] = s;
        }
      }
    });
    _toast(
      s == MatchState.none
          ? 'تم مسح علامات الحركات المعروضة'
          : 'تم تعليم الحركات المعروضة',
      true,
    );
  }

  // ---------------- النسخ المتقدم ----------------

  String _code(int? id) => id == null ? '' : (_currencies[id]?.code ?? '');

  String _fmt(double v) {
    final t = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return t;
  }

  Future<void> _copyReport() async {
    final matched = <Transaction>[];
    final notMatched = <Transaction>[];
    for (final t in _transactions) {
      final s = _txState[t.id];
      if (s == MatchState.matched) {
        matched.add(t);
      } else if (s == MatchState.notMatched) {
        notMatched.add(t);
      }
    }
    final unmarked = _transactions.length - matched.length - notMatched.length;

    String line(Transaction t) {
      final when = DateFormat('MM-dd HH:mm').format(t.createdAt.toLocal());
      return '• ${t.beneficiary ?? t.type} — ${_fmt(t.amount)} ${_code(t.currencyId)} ($when)';
    }

    final excelMatched =
        _excelMarks.values.where((s) => s == MatchState.matched).length;
    final excelNot =
        _excelMarks.values.where((s) => s == MatchState.notMatched).length;
    final pdfMarks = _pdfMarks.values.fold<int>(0, (a, b) => a + b.length);

    final b = StringBuffer()
      ..writeln('🧾 تقرير مطابقة الصندوق')
      ..writeln('المستخدم: ${widget.user.username}')
      ..writeln('التاريخ: ${DateFormat('yyyy/MM/dd  HH:mm').format(DateTime.now())}')
      ..writeln('الملف: ${_fileName.isEmpty ? '—' : _fileName}')
      ..writeln('=======================================')
      ..writeln('الحركات المطابقة (${matched.length}):');
    for (final t in matched) {
      b.writeln(line(t));
    }
    b
      ..writeln('')
      ..writeln('الحركات غير المطابقة (${notMatched.length}):');
    for (final t in notMatched) {
      b.writeln(line(t));
    }
    b
      ..writeln('')
      ..writeln('بدون علامة: $unmarked')
      ..writeln('---------------------------------------')
      ..writeln('علامات الملف: Excel مطابق $excelMatched / غير مطابق $excelNot'
          '${_kind == _FileKind.pdf ? ' • علامات PDF: $pdfMarks' : ''}');

    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    _toast('تم نسخ تقرير المطابقة', true);
  }

  void _toast(String msg, bool ok) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ok
              ? AppUi.tone(context, AppColors.success)
              : AppUi.tone(context, AppColors.error),
        ),
      );
  }

  // ---------------- الواجهة ----------------

  @override
  Widget build(BuildContext context) {
    final matched = _txState.values.where((s) => s == MatchState.matched).length;
    final notMatched =
        _txState.values.where((s) => s == MatchState.notMatched).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(
        context,
        title: 'مطابقة الصندوق',
        actions: [
          IconButton(
            tooltip: 'فتح ملف (PDF / Excel)',
            onPressed: _loadingFile ? null : _openFile,
            icon: const Icon(Icons.folder_open_rounded),
          ),
          IconButton(
            tooltip: 'نسخ تقرير المطابقة',
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            tooltip: 'مسح كل العلامات',
            onPressed: _resetAll,
            icon: const Icon(Icons.layers_clear_rounded),
          ),
          IconButton(
            tooltip: 'تحديث الحركات',
            onPressed: _loadTx,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: TimaPageBackground(
        child: Column(
          children: [
            _SummaryBar(
              fileName: _fileName,
              kind: _kind,
              total: _transactions.length,
              matched: matched,
              notMatched: notMatched,
              onOpen: _loadingFile ? null : _openFile,
              loading: _loadingFile,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDims.pagePadding,
                  4,
                  AppDims.pagePadding,
                  AppDims.pagePadding,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final total = constraints.maxWidth;
                    final fileW = (total - 10) * _split;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: fileW,
                          child: _FilePanel(
                            kind: _kind,
                            fileName: _fileName,
                            error: _fileError,
                            pdfPages: _pdfPages,
                            pdfSizes: _pdfSizes,
                            pdfMarks: _pdfMarks,
                            excelRows: _excelRows,
                            excelMarks: _excelMarks,
                            onOpen: _loadingFile ? null : _openFile,
                            onMarkRow: _markRow,
                            onAddPdfMark: _addPdfMark,
                            onClearPageMarks: _clearPageMarks,
                          ),
                        ),
                        _SplitHandle(
                          total: total,
                          onDrag: (dx) {
                            setState(() {
                              // في RTL لوحة الملف يميناً: سحب المقبض يميناً يصغّرها.
                              _split = (_split - dx / total)
                                  .clamp(0.25, 0.75)
                                  .toDouble();
                            });
                          },
                        ),
                        Expanded(
                          child: _TxPanel(
                            loading: _loadingTx,
                            transactions: _filteredTx(),
                            states: _txState,
                            currencies: _currencies,
                            search: _search,
                            onlyUnmarked: _onlyUnmarked,
                            sortMode: _txSort,
                            onSort: (v) => setState(() => _txSort = v),
                            onSearch: (v) => setState(() => _search = v),
                            onToggleUnmarked: (v) =>
                                setState(() => _onlyUnmarked = v),
                            onMark: _markTx,
                            onCopyNames: _copyNames,
                            onCopyName: _copySingleName,
                            onMarkVisible: _markVisible,
                            fmt: _fmt,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Transaction> _filteredTx() {
    final list = _transactions.where((t) {
      if (_onlyUnmarked && _txState.containsKey(t.id)) return false;
      if (_search.trim().isEmpty) return true;
      final q = _search.trim().toLowerCase();
      return (t.beneficiary ?? '').toLowerCase().contains(q) ||
          t.type.toLowerCase().contains(q) ||
          t.amount.toString().contains(q);
    }).toList();

    int statusRank(Transaction t) => switch (_txState[t.id] ?? MatchState.none) {
          MatchState.notMatched => 0,
          MatchState.none => 1,
          MatchState.matched => 2,
        };

    switch (_txSort) {
      case 'dateOld':
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'amountHigh':
        list.sort((a, b) => b.amount.compareTo(a.amount));
      case 'amountLow':
        list.sort((a, b) => a.amount.compareTo(b.amount));
      case 'name':
        list.sort((a, b) => _nameOf(a).compareTo(_nameOf(b)));
      case 'status':
        list.sort((a, b) => statusRank(a).compareTo(statusRank(b)));
      default:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }
}

// ================= شريط الملخص =================

class _SummaryBar extends StatelessWidget {
  final String fileName;
  final _FileKind kind;
  final int total;
  final int matched;
  final int notMatched;
  final VoidCallback? onOpen;
  final bool loading;

  const _SummaryBar({
    required this.fileName,
    required this.kind,
    required this.total,
    required this.matched,
    required this.notMatched,
    required this.onOpen,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final unmarked = total - matched - notMatched;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDims.pagePadding,
        12,
        AppDims.pagePadding,
        8,
      ),
      child: TimaContentWidth(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppUi.surface(context),
            borderRadius: BorderRadius.circular(AppDims.radiusLg),
            border: Border.all(color: AppUi.border(context)),
            boxShadow: AppUi.softShadow(context),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: AppColors.brandGradient,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fact_check_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName.isEmpty ? 'لم يُفتح ملف بعد' : fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: AppUi.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'زر أيسر = مطابق • زر أيمن = غير مطابق • العلامات داخل التطبيق فقط ولا تُحفظ بالملف',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppUi.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Pill(
                label: 'مطابق $matched',
                color: AppUi.tone(context, AppColors.success),
                icon: Icons.check_circle_rounded,
              ),
              const SizedBox(width: 6),
              _Pill(
                label: 'غير مطابق $notMatched',
                color: AppUi.tone(context, AppColors.error),
                icon: Icons.cancel_rounded,
              ),
              const SizedBox(width: 6),
              _Pill(
                label: 'بدون $unmarked',
                color: AppUi.textSecondary(context),
                icon: Icons.help_outline_rounded,
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(kind == _FileKind.none ? 'فتح ملف' : 'تغيير الملف'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Pill({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ================= مقبض التقسيم =================

class _SplitHandle extends StatelessWidget {
  final double total;
  final ValueChanged<double> onDrag;
  const _SplitHandle({required this.total, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 4,
              height: 46,
              decoration: BoxDecoration(
                color: AppUi.border(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================= لوحة الملف =================

class _FilePanel extends StatelessWidget {
  final _FileKind kind;
  final String fileName;
  final String? error;
  final List<Uint8List> pdfPages;
  final List<Size> pdfSizes;
  final Map<int, List<_PdfMark>> pdfMarks;
  final List<List<String>> excelRows;
  final Map<int, MatchState> excelMarks;
  final VoidCallback? onOpen;
  final void Function(int, MatchState) onMarkRow;
  final void Function(int, double, double, bool) onAddPdfMark;
  final void Function(int) onClearPageMarks;

  const _FilePanel({
    required this.kind,
    required this.fileName,
    required this.error,
    required this.pdfPages,
    required this.pdfSizes,
    required this.pdfMarks,
    required this.excelRows,
    required this.excelMarks,
    required this.onOpen,
    required this.onMarkRow,
    required this.onAddPdfMark,
    required this.onClearPageMarks,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppUi.surface(context),
        borderRadius: BorderRadius.circular(AppDims.radiusLg),
        border: Border.all(color: AppUi.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _panelHeader(context),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _panelHeader(BuildContext context) {
    final title = switch (kind) {
      _FileKind.pdf => 'مستند PDF — ${pdfPages.length} صفحة',
      _FileKind.excel => 'جدول Excel — ${excelRows.length} صف',
      _FileKind.none => 'الملف المرجعي',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppUi.border(context))),
        color: AppUi.sunken(context),
      ),
      child: Row(
        children: [
          Icon(
            kind == _FileKind.excel
                ? Icons.table_view_rounded
                : Icons.picture_as_pdf_rounded,
            size: 18,
            color: AppUi.accent(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: AppUi.textPrimary(context),
              ),
            ),
          ),
          if (kind == _FileKind.pdf)
            Text(
              'انقر على الصفحة لوضع علامة',
              style: TextStyle(fontSize: 11, color: AppUi.textSecondary(context)),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (kind == _FileKind.pdf && pdfPages.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: pdfPages.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _PdfPage(
          index: i,
          png: pdfPages[i],
          size: pdfSizes[i],
          marks: pdfMarks[i] ?? const [],
          onAddMark: onAddPdfMark,
          onClear: onClearPageMarks,
        ),
      );
    }
    if (kind == _FileKind.excel && excelRows.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: excelRows.length,
        itemBuilder: (context, i) => _ExcelRow(
          index: i,
          cells: excelRows[i],
          state: excelMarks[i] ?? MatchState.none,
          onMark: onMarkRow,
        ),
      );
    }
    return _EmptyFile(onOpen: onOpen, error: error);
  }
}

class _EmptyFile extends StatelessWidget {
  final VoidCallback? onOpen;
  final String? error;
  const _EmptyFile({required this.onOpen, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: AppUi.tone(context, AppColors.brandGold).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.upload_file_rounded,
                size: 36,
                color: AppUi.tone(context, AppColors.brandGoldDark),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'افتح ملف PDF أو Excel',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppUi.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'اعرض كشف الحساب أو الجدول بجانب الحركات، وضع علامات داخل التطبيق دون أي تعديل على الملف الأصلي.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppUi.textSecondary(context),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: AppUi.tone(context, AppColors.error),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('اختيار ملف'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfPage extends StatelessWidget {
  final int index;
  final Uint8List png;
  final Size size;
  final List<_PdfMark> marks;
  final void Function(int, double, double, bool) onAddMark;
  final void Function(int) onClear;

  const _PdfPage({
    required this.index,
    required this.png,
    required this.size,
    required this.marks,
    required this.onAddMark,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = size.width == 0 ? w : w * size.height / size.width;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'صفحة ${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textSecondary(context),
                  ),
                ),
                const Spacer(),
                if (marks.isNotEmpty)
                  InkWell(
                    onTap: () => onClear(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'مسح علامات الصفحة (${marks.length})',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppUi.tone(context, AppColors.error),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: w,
              height: h,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.memory(png, fit: BoxFit.fill),
                  ),
                  for (final m in marks)
                    Positioned(
                      left: m.dx * w - 13,
                      top: m.dy * h - 13,
                      child: _MarkDot(matched: m.matched),
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => onAddMark(
                        index,
                        d.localPosition.dx / w,
                        d.localPosition.dy / h,
                        true,
                      ),
                      onSecondaryTapDown: (d) => onAddMark(
                        index,
                        d.localPosition.dx / w,
                        d.localPosition.dy / h,
                        false,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MarkDot extends StatelessWidget {
  final bool matched;
  const _MarkDot({required this.matched});

  @override
  Widget build(BuildContext context) {
    final color = matched ? const Color(0xFF1E9E6A) : const Color(0xFFD6453D);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(
        matched ? Icons.check_rounded : Icons.close_rounded,
        size: 16,
        color: Colors.white,
      ),
    );
  }
}

class _ExcelRow extends StatelessWidget {
  final int index;
  final List<String> cells;
  final MatchState state;
  final void Function(int, MatchState) onMark;

  const _ExcelRow({
    required this.index,
    required this.cells,
    required this.state,
    required this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = switch (state) {
      MatchState.matched => AppUi.tone(context, AppColors.success).withValues(alpha: 0.12),
      MatchState.notMatched => AppUi.tone(context, AppColors.error).withValues(alpha: 0.12),
      MatchState.none => Colors.transparent,
    };
    final accent = switch (state) {
      MatchState.matched => AppUi.tone(context, AppColors.success),
      MatchState.notMatched => AppUi.tone(context, AppColors.error),
      MatchState.none => AppUi.border(context),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onMark(index, MatchState.matched),
      onSecondaryTap: () => onMark(index, MatchState.notMatched),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  state == MatchState.matched
                      ? Icons.check_rounded
                      : state == MatchState.notMatched
                          ? Icons.close_rounded
                          : Icons.circle_outlined,
                  size: 14,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    children: [
                      for (var i = 0; i < cells.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            cells[i],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == 0
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: AppUi.textPrimary(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= لوحة الحركات =================

class _TxPanel extends StatelessWidget {
  final bool loading;
  final List<Transaction> transactions;
  final Map<int, MatchState> states;
  final Map<int, Currency> currencies;
  final String search;
  final bool onlyUnmarked;
  final String sortMode;
  final ValueChanged<String> onSort;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onToggleUnmarked;
  final void Function(int, MatchState) onMark;
  final void Function(String, bool) onCopyNames;
  final void Function(String) onCopyName;
  final void Function(MatchState) onMarkVisible;
  final String Function(double) fmt;

  const _TxPanel({
    required this.loading,
    required this.transactions,
    required this.states,
    required this.currencies,
    required this.search,
    required this.onlyUnmarked,
    required this.sortMode,
    required this.onSort,
    required this.onSearch,
    required this.onToggleUnmarked,
    required this.onMark,
    required this.onCopyNames,
    required this.onCopyName,
    required this.onMarkVisible,
    required this.fmt,
  });

  static const _sortLabels = {
    'dateNew': 'الأحدث أولاً',
    'dateOld': 'الأقدم أولاً',
    'amountHigh': 'الأعلى مبلغاً',
    'amountLow': 'الأقل مبلغاً',
    'name': 'حسب الاسم',
    'status': 'حسب الحالة',
  };

  @override
  Widget build(BuildContext context) {
    final iconColor = AppUi.textSecondary(context);
    return Container(
      decoration: BoxDecoration(
        color: AppUi.surface(context),
        borderRadius: BorderRadius.circular(AppDims.radiusLg),
        border: Border.all(color: AppUi.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppUi.border(context))),
              color: AppUi.sunken(context),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 18,
                      color: AppUi.accent(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'الحركات (${transactions.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppUi.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    _MiniToggle(
                      label: 'بدون علامة فقط',
                      value: onlyUnmarked,
                      onChanged: onToggleUnmarked,
                    ),
                    // ترتيب.
                    PopupMenuButton<String>(
                      tooltip: 'فرز وترتيب',
                      initialValue: sortMode,
                      onSelected: onSort,
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.sort_rounded, size: 20, color: iconColor),
                      itemBuilder: (context) => _sortLabels.entries
                          .map(
                            (e) => PopupMenuItem<String>(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                    ),
                    // نسخ الأسماء.
                    PopupMenuButton<String>(
                      tooltip: 'نسخ الأسماء',
                      padding: EdgeInsets.zero,
                      icon:
                          Icon(Icons.copy_all_rounded, size: 20, color: iconColor),
                      onSelected: (v) {
                        switch (v) {
                          case 'matched':
                            onCopyNames('matched', false);
                          case 'notMatched':
                            onCopyNames('notMatched', false);
                          case 'all':
                            onCopyNames('all', false);
                          case 'matchedAmt':
                            onCopyNames('matched', true);
                          case 'notMatchedAmt':
                            onCopyNames('notMatched', true);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'matched',
                          child: Text('نسخ الأسماء المطابقة'),
                        ),
                        PopupMenuItem(
                          value: 'notMatched',
                          child: Text('نسخ الأسماء غير المطابقة'),
                        ),
                        PopupMenuItem(
                          value: 'all',
                          child: Text('نسخ كل الأسماء'),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'matchedAmt',
                          child: Text('المطابقة + المبالغ'),
                        ),
                        PopupMenuItem(
                          value: 'notMatchedAmt',
                          child: Text('غير المطابقة + المبالغ'),
                        ),
                      ],
                    ),
                    // تعليم جماعي.
                    PopupMenuButton<String>(
                      tooltip: 'تعليم جماعي',
                      padding: EdgeInsets.zero,
                      icon:
                          Icon(Icons.done_all_rounded, size: 20, color: iconColor),
                      onSelected: (v) {
                        switch (v) {
                          case 'matched':
                            onMarkVisible(MatchState.matched);
                          case 'notMatched':
                            onMarkVisible(MatchState.notMatched);
                          case 'clear':
                            onMarkVisible(MatchState.none);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'matched',
                          child: Text('تعليم المعروض كمطابق'),
                        ),
                        PopupMenuItem(
                          value: 'notMatched',
                          child: Text('تعليم المعروض كغير مطابق'),
                        ),
                        PopupMenuItem(
                          value: 'clear',
                          child: Text('مسح علامات المعروض'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: onSearch,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'ابحث بالاسم أو النوع أو المبلغ…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDims.radiusSm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const TimaLoader(message: 'جارٍ تحميل الحركات…')
                : transactions.isEmpty
                    ? TimaEmptyState(
                        icon: Icons.inbox_rounded,
                        title: 'لا توجد حركات',
                        subtitle: 'غيّر البحث أو الحدّد «بدون علامة فقط».',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: transactions.length,
                        itemBuilder: (context, i) {
                          final tx = transactions[i];
                          return _TxRow(
                            tx: tx,
                            code: currencies[tx.currencyId]?.code ?? '',
                            state: states[tx.id] ?? MatchState.none,
                            onMark: onMark,
                            onCopyName: onCopyName,
                            fmt: fmt,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _MiniToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: value
              ? AppUi.tone(context, AppColors.brandGold).withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value
                ? AppUi.tone(context, AppColors.brandGold)
                : AppUi.border(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
              size: 14,
              color: value
                  ? AppUi.tone(context, AppColors.brandGoldDark)
                  : AppUi.textSecondary(context),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: value
                    ? AppUi.tone(context, AppColors.brandGoldDark)
                    : AppUi.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  final Transaction tx;
  final String code;
  final MatchState state;
  final void Function(int, MatchState) onMark;
  final void Function(String) onCopyName;
  final String Function(double) fmt;

  const _TxRow({
    required this.tx,
    required this.code,
    required this.state,
    required this.onMark,
    required this.onCopyName,
    required this.fmt,
  });

  ({IconData icon, Color color, String label}) _visual() {
    final t = tx.type;
    if (t.contains('يوزر')) {
      return (icon: Icons.person_rounded, color: AppColors.violet, label: 'يوزر');
    }
    if (t.contains('تسليم')) {
      return (icon: Icons.outbox_rounded, color: AppColors.warning, label: 'تسليم');
    }
    if (t.contains('استلام')) {
      return (
        icon: Icons.move_to_inbox_rounded,
        color: AppColors.success,
        label: 'استلام',
      );
    }
    if (t.contains('مرسلة')) {
      return (icon: Icons.send_rounded, color: AppColors.info, label: 'مرسلة');
    }
    if (t.contains('تسوية') || t.contains('صرف')) {
      return (
        icon: Icons.currency_exchange_rounded,
        color: AppColors.teal,
        label: 'تسوية',
      );
    }
    return (
      icon: Icons.receipt_long_rounded,
      color: AppColors.slate,
      label: 'حركة',
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual();
    final accent = switch (state) {
      MatchState.matched => AppUi.tone(context, AppColors.success),
      MatchState.notMatched => AppUi.tone(context, AppColors.error),
      MatchState.none => AppUi.tone(context, v.color),
    };
    final bg = switch (state) {
      MatchState.matched => AppUi.tone(context, AppColors.success).withValues(alpha: 0.10),
      MatchState.notMatched => AppUi.tone(context, AppColors.error).withValues(alpha: 0.10),
      MatchState.none => Colors.transparent,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onMark(tx.id, MatchState.matched),
      onSecondaryTap: () => onMark(tx.id, MatchState.notMatched),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(v.icon, size: 17, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.beneficiary?.trim().isNotEmpty == true
                          ? tx.beneficiary!.trim()
                          : v.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppUi.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${v.label} • ${DateFormat('MM-dd HH:mm').format(tx.createdAt.toLocal())} • ${tx.status}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppUi.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${fmt(tx.amount)} $code',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: accent,
                ),
              ),
              const SizedBox(width: 4),
              // نسخ اسم هذه الحركة.
              InkWell(
                onTap: () => onCopyName(
                  (tx.beneficiary?.trim().isNotEmpty == true)
                      ? tx.beneficiary!.trim()
                      : tx.type,
                ),
                borderRadius: BorderRadius.circular(6),
                child: Tooltip(
                  message: 'نسخ الاسم',
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: AppUi.textSecondary(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                state == MatchState.matched
                    ? Icons.check_circle_rounded
                    : state == MatchState.notMatched
                        ? Icons.cancel_rounded
                        : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
