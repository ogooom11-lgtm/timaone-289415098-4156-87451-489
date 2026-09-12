import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/clipboard_text.dart';
import 'app_ui.dart';

/// حمولة السحب والإفلات: النص المجمّع ومعرّفات الكلمات المصدر في اللوحة.
class ClipboardWords {
  final String text;
  final List<int> ids;

  const ClipboardWords(this.text, this.ids);
}

/// هدف تعبئة سريع يظهر كزرّ في شريط التحديد داخل اللوحة
/// («إلى الاسم»، «إلى المبلغ»…) كبديل للسحب بالفأرة.
class ClipboardAssignTarget {
  final String label;
  final IconData icon;

  /// يعيد `true` إن قُبل النص، فتُعلَّم كلماته كمستخدمة في اللوحة.
  final bool Function(String text) onAssign;

  const ClipboardAssignTarget({
    required this.label,
    required this.icon,
    required this.onAssign,
  });
}

/// يبثّ النص المسحوب حالياً من اللوحة إلى كل حقول الإفلات في الصفحة،
/// حتى يُبرز كل حقل نفسه إن كان يقبل هذا النص (`null` = لا سحب جارٍ).
class ClipboardDragScope extends InheritedNotifier<ValueNotifier<String?>> {
  const ClipboardDragScope({
    super.key,
    required ValueNotifier<String?> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static String? draggingText(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ClipboardDragScope>();
    return scope?.notifier?.value;
  }

  static void _set(BuildContext context, String? value) {
    final scope = context.getInheritedWidgetOfExactType<ClipboardDragScope>();
    final notifier = scope?.notifier;
    if (notifier != null && notifier.value != value) notifier.value = value;
  }
}

/// لوحة «نص الحافظة»: تعرض النص المنسوخ مقطّعاً إلى كلمات قابلة للسحب،
/// مع تحديد متعدد (نقرة = تحديد/إلغاء، Shift+نقرة = مدى) لسحب عبارة كاملة،
/// ونقر مزدوج للتعبئة الذكية.
///
/// تقرأ الحافظة تلقائياً عند الفتح وعند العودة إلى النافذة، وتتابعها
/// بفاصل قصير حتى يظهر آخر نصّ منسوخ بلا أي ضغطة زرّ.
class ClipboardWordsPanel extends StatefulWidget {
  final String title;

  /// أزرار التعبئة السريعة في شريط التحديد.
  final List<ClipboardAssignTarget> targets;

  /// نقر مزدوج على كلمة: تعبئة ذكية يقرّرها المستدعي (رقم → مبلغ،
  /// عملة → عملة، غير ذلك → اسم). يعيد `true` إن استُخدمت الكلمة.
  final bool Function(String text)? onQuickAssign;

  /// قراءة الحافظة مباشرة عند إنشاء اللوحة.
  final bool autoLoad;

  /// متابعة تغيّر الحافظة أثناء فتح الصفحة.
  final bool watchClipboard;

  const ClipboardWordsPanel({
    super.key,
    this.title = 'نص الحافظة',
    this.targets = const [],
    this.onQuickAssign,
    this.autoLoad = true,
    this.watchClipboard = true,
  });

  @override
  State<ClipboardWordsPanel> createState() => _ClipboardWordsPanelState();
}

enum _TokenKind { text, number, currency }

class _Token {
  final int id;
  final String text;
  final _TokenKind kind;

  const _Token({required this.id, required this.text, required this.kind});
}

class _ClipboardWordsPanelState extends State<ClipboardWordsPanel>
    with WidgetsBindingObserver {
  static const Duration _watchInterval = Duration(milliseconds: 1500);

  final ScrollController _scroll = ScrollController();
  Timer? _watchTimer;
  ModalRoute<dynamic>? _route;
  bool _reading = false;

  /// النافذة في المقدمة؟ لا نستطلع الحافظة وهي في الخلفية.
  bool _windowActive = true;

  /// آخر نصّ قُرئ من الحافظة — لتجاهل القراءات المكررة.
  String _lastClipboard = '';

  /// سحب جارٍ من اللوحة؛ لا نستبدل الكلمات تحت يد المستخدم.
  bool _dragActive = false;

  String _text = '';
  bool _truncated = false;
  List<_Token> _tokens = const [];
  List<List<_Token>> _lines = const [];
  final Set<int> _selected = {};
  final Set<int> _used = {};
  int? _anchor;

  // كشف النقر المزدوج يدوياً حتى تبقى النقرة المفردة فورية بلا تأخير.
  int? _lastTapId;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoLoad) _loadFromClipboard();
    if (widget.watchClipboard) {
      _watchTimer = Timer.periodic(_watchInterval, (_) => _pollClipboard());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _windowActive = state == AppLifecycleState.resumed;
    // العودة إلى نافذة تيما بعد النسخ من برنامج آخر.
    if (_windowActive && widget.watchClipboard) _pollClipboard();
  }

  // -------------------------------------------------------------------
  // قراءة الحافظة وتقطيع النص
  // -------------------------------------------------------------------

  void _pollClipboard() {
    if (!_windowActive || _dragActive) return;
    // صفحة مغطّاة بحوار أو صفحة أخرى لا تحتاج متابعة الحافظة.
    final route = _route;
    if (route != null && !route.isCurrent) return;
    _loadFromClipboard();
  }

  Future<void> _loadFromClipboard({bool force = false}) async {
    if (_reading) return;
    _reading = true;
    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    } catch (_) {
      text = null;
    } finally {
      _reading = false;
    }
    if (!mounted) return;

    final value = text ?? '';
    if (!force && value == _lastClipboard) return;
    _lastClipboard = value;

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (force) {
        _snack('الحافظة لا تحتوي نصاً. انسخ رسالة الحوالة أولاً (Ctrl+C).');
      }
      return;
    }

    // نسخ جزء من النص المعروض نفسه (مثلاً من حقل عُبّئ منه) ليس نصاً
    // جديداً؛ لا نستبدل اللوحة حتى لا تضيع الكلمات المحدّدة والمستخدمة.
    if (!force && _text.isNotEmpty && _text.contains(trimmed)) return;

    _setText(value);
  }

  void _setText(String raw) {
    var text = raw;
    final truncated = text.length > ClipboardText.maxChars;
    if (truncated) text = text.substring(0, ClipboardText.maxChars);

    final tokens = <_Token>[];
    final lines = <List<_Token>>[];
    for (final words in ClipboardText.tokenizeLines(text)) {
      final row = <_Token>[];
      for (final word in words) {
        final token = _Token(
          id: tokens.length,
          text: word,
          kind: _kindOf(word),
        );
        tokens.add(token);
        row.add(token);
      }
      lines.add(row);
    }

    setState(() {
      _text = text;
      _truncated = truncated;
      _tokens = tokens;
      _lines = lines;
      _selected.clear();
      _used.clear();
      _anchor = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  _TokenKind _kindOf(String word) {
    if (ClipboardText.looksNumeric(word)) return _TokenKind.number;
    if (ClipboardText.detectCurrencyCode(word) != null) {
      return _TokenKind.currency;
    }
    return _TokenKind.text;
  }

  void _clear() {
    // حتى يعود النص نفسه للظهور إن نُسخ مرة أخرى بعد المسح.
    _lastClipboard = '';
    setState(() {
      _text = '';
      _truncated = false;
      _tokens = const [];
      _lines = const [];
      _selected.clear();
      _used.clear();
      _anchor = null;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------------
  // التحديد والسحب
  // -------------------------------------------------------------------

  List<int> get _selectedSorted => _selected.toList()..sort();

  String get _selectionPhrase =>
      _selectedSorted.map((id) => _tokens[id].text).join(' ');

  ClipboardWords get _selectionPayload =>
      ClipboardWords(_selectionPhrase, _selectedSorted);

  /// سحب كلمة محدّدة يحمل التحديد كلّه؛ سحب كلمة غير محدّدة يحملها وحدها.
  ClipboardWords _payloadFor(_Token token) {
    if (_selected.contains(token.id)) return _selectionPayload;
    return ClipboardWords(token.text, [token.id]);
  }

  void _onWordTap(_Token token) {
    final now = DateTime.now();
    final isDouble =
        _lastTapId == token.id &&
        now.difference(_lastTapAt) < kDoubleTapTimeout;
    _lastTapId = token.id;
    _lastTapAt = now;

    if (isDouble && widget.onQuickAssign != null) {
      _lastTapId = null;
      _quickAssign(token);
      return;
    }
    _toggle(token.id);
  }

  void _toggle(int id) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (shift && _anchor != null) {
        final from = _anchor! < id ? _anchor! : id;
        final to = _anchor! < id ? id : _anchor!;
        _selected
          ..clear()
          ..addAll([for (var i = from; i <= to; i++) i]);
      } else {
        if (!_selected.remove(id)) _selected.add(id);
        _anchor = id;
      }
    });
  }

  void _quickAssign(_Token token) {
    final accepted = widget.onQuickAssign!(token.text);
    setState(() {
      // النقرة الأولى من النقر المزدوج بدّلت التحديد؛ نعيده كما كان.
      _selected.remove(token.id);
      if (accepted) _used.add(token.id);
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  /// يُستدعى عندما يقبل أحد الحقول حمولة السحب أو زرّ تعبئة سريعة.
  void _onDropped(ClipboardWords payload) {
    if (!mounted) return;
    setState(() {
      _used.addAll(payload.ids);
      if (_selected.isNotEmpty && payload.ids.toSet().containsAll(_selected)) {
        _selected.clear();
      }
    });
  }

  void _assignSelection(ClipboardAssignTarget target) {
    final payload = _selectionPayload;
    if (payload.text.isEmpty) return;
    if (target.onAssign(payload.text)) _onDropped(payload);
  }

  void _setDragging(String? text) {
    _dragActive = text != null;
    if (!mounted) return;
    ClipboardDragScope._set(context, text);
  }

  Widget _draggable({required ClipboardWords payload, required Widget child}) {
    return _WordDraggable(
      data: payload,
      feedback: _DragFeedback(text: payload.text, count: payload.ids.length),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      onDragStarted: () => _setDragging(payload.text),
      onDragEnd: (_) => _setDragging(null),
      onDragCompleted: () => _onDropped(payload),
      child: child,
    );
  }

  // -------------------------------------------------------------------
  // البناء
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppUi.panelDecoration(context, shadow: false),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Divider(height: 1, thickness: 1, color: AppUi.border(context)),
          Expanded(
            child: _text.isEmpty ? _buildEmpty(context) : _buildWords(context),
          ),
          if (_selected.isNotEmpty) _buildSelectionBar(context),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
      child: TimaSectionTitle(
        icon: Icons.content_paste_rounded,
        title: widget.title,
        subtitle: _text.isEmpty
            ? 'انسخ نصاً ليظهر هنا تلقائياً'
            : '${_tokens.length} كلمة في ${_lines.length} سطر',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'لصق من الحافظة',
              onPressed: () => _loadFromClipboard(force: true),
              icon: const Icon(Icons.content_paste_go_rounded),
            ),
            IconButton(
              tooltip: 'مسح النص',
              onPressed: _text.isEmpty ? null : _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return TimaEmptyState(
      icon: Icons.content_paste_rounded,
      title: 'لا يوجد نص بعد',
      subtitle:
          'انسخ رسالة الحوالة (Ctrl+C) من أي برنامج، وستظهر كلماتها هنا تلقائياً عند العودة إلى تيما.',
      action: FilledButton.icon(
        onPressed: () => _loadFromClipboard(force: true),
        icon: const Icon(Icons.content_paste_go_rounded),
        label: const Text('لصق من الحافظة'),
      ),
    );
  }

  Widget _buildWords(BuildContext context) {
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in _lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final token in line)
                      _draggable(
                        payload: _payloadFor(token),
                        child: _WordChip(
                          text: token.text,
                          kind: token.kind,
                          selected: _selected.contains(token.id),
                          used: _used.contains(token.id),
                          onTap: () => _onWordTap(token),
                        ),
                      ),
                  ],
                ),
              ),
            if (_truncated)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'عُرض أوّل ${ClipboardText.maxChars} حرف من النص فقط.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final accent = AppUi.accent(context);
    final payload = _selectionPayload;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppUi.softFill(context, accent),
        border: Border(top: BorderSide(color: AppUi.border(context))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _draggable(
                  payload: payload,
                  child: _SelectionPill(
                    text: payload.text,
                    count: payload.ids.length,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'إلغاء التحديد',
                onPressed: _clearSelection,
                iconSize: 17,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (widget.targets.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final target in widget.targets)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => _assignSelection(target),
                    icon: Icon(target.icon, size: 15),
                    label: Text('إلى ${target.label}'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final secondary = AppUi.textSecondary(context);
    final style = TextStyle(fontSize: 11, height: 1.45, color: secondary);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: AppUi.sunken(context),
        border: Border(top: BorderSide(color: AppUi.border(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FooterHint(
            icon: Icons.open_with_rounded,
            text:
                'اسحب أي كلمة إلى الحقل المطلوب، أو انقر عدّة كلمات لتحديدها ثم اسحبها معاً (Shift + نقرة لتحديد مدى).',
            style: style,
          ),
          if (widget.onQuickAssign != null) ...[
            const SizedBox(height: 3),
            _FooterHint(
              icon: Icons.bolt_rounded,
              text:
                  'نقر مزدوج: رقم → المبلغ، عملة → العملة، غير ذلك → الاسم.',
              style: style,
            ),
          ],
        ],
      ),
    );
  }
}

class _FooterHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle style;

  const _FooterHint({
    required this.icon,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 12, color: style.color),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// السحب بعتبة حركة مريحة
// ---------------------------------------------------------------------------

/// `Draggable` يبدأ السحب بعد تحريك الفأرة بضعة بكسلات لا بكسلاً واحداً،
/// حتى تبقى النقرة العادية (مع اهتزاز اليد الطبيعي) نقرةً لتحديد الكلمة.
class _WordDraggable extends Draggable<ClipboardWords> {
  const _WordDraggable({
    required super.child,
    required super.feedback,
    required super.data,
    super.childWhenDragging,
    super.onDragStarted,
    super.onDragEnd,
    super.onDragCompleted,
  }) : super(maxSimultaneousDrags: 1);

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return _SlopMultiDragGestureRecognizer(debugOwner: this)..onStart = onStart;
  }
}

class _SlopMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  _SlopMultiDragGestureRecognizer({required super.debugOwner});

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _SlopPointerState(event.position, event.kind, gestureSettings);
  }

  @override
  String get debugDescription => 'clipboard word drag';
}

class _SlopPointerState extends MultiDragPointerState {
  _SlopPointerState(super.initialPosition, super.kind, super.gestureSettings);

  /// عتبة الفأرة؛ الافتراضية في فلاتر بكسل واحد فقط.
  static const double _mouseSlop = 6;

  @override
  void checkForResolutionAfterMove() {
    final delta = pendingDelta;
    if (delta == null) return;
    final slop = kind == PointerDeviceKind.mouse
        ? _mouseSlop
        : computeHitSlop(kind, gestureSettings);
    if (delta.distance > slop) resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}

// ---------------------------------------------------------------------------
// عناصر العرض
// ---------------------------------------------------------------------------

/// كلمة واحدة قابلة للنقر والسحب.
class _WordChip extends StatefulWidget {
  final String text;
  final _TokenKind kind;
  final bool selected;
  final bool used;
  final VoidCallback onTap;

  const _WordChip({
    required this.text,
    required this.kind,
    required this.selected,
    required this.used,
    required this.onTap,
  });

  @override
  State<_WordChip> createState() => _WordChipState();
}

class _WordChipState extends State<_WordChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);
    final isDark = AppUi.isDark(context);

    Color fill;
    Color border;
    Color fg;
    if (widget.selected) {
      fill = accent.withValues(alpha: isDark ? 0.26 : 0.14);
      border = accent;
      fg = accent;
    } else if (widget.kind == _TokenKind.number) {
      fg = AppUi.tone(context, AppColors.brandGoldDark);
      fill = AppUi.softFill(context, AppColors.brandGold);
      border = AppColors.brandGold.withValues(alpha: _hover ? 0.75 : 0.42);
    } else if (widget.kind == _TokenKind.currency) {
      fg = AppUi.tone(context, AppColors.success);
      fill = AppUi.softFill(context, AppColors.success);
      border = fg.withValues(alpha: _hover ? 0.75 : 0.42);
    } else {
      fg = AppUi.textPrimary(context);
      fill = _hover ? AppUi.hover(context) : AppUi.sunken(context);
      border = _hover ? AppUi.borderStrong(context) : AppUi.border(context);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: widget.used ? 0.5 : 1,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AppDims.radiusSm),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.used) ...[
                  Icon(Icons.check_rounded, size: 12, color: fg),
                  const SizedBox(width: 3),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// العبارة المحدّدة — قابلة للسحب ككتلة واحدة.
class _SelectionPill extends StatelessWidget {
  final String text;
  final int count;

  const _SelectionPill({required this.text, required this.count});

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: AppUi.surface(context),
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
          border: Border.all(color: accent),
        ),
        child: Row(
          children: [
            Icon(Icons.drag_indicator_rounded, size: 16, color: accent),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (count > 1) ...[
              const SizedBox(width: 6),
              _CountBadge(count: count, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}

/// الشكل الذي يتبع مؤشر الفأرة أثناء السحب.
class _DragFeedback extends StatelessWidget {
  final String text;
  final int count;

  const _DragFeedback({required this.text, required this.count});

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_indicator_rounded,
              size: 15,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (count > 1) ...[
              const SizedBox(width: 8),
              _CountBadge(count: count, color: Colors.white, onDark: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final bool onDark;

  const _CountBadge({
    required this.count,
    required this.color,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: onDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// هدف الإفلات
// ---------------------------------------------------------------------------

/// يغلّف حقلاً في النموذج ليصبح منطقة إفلات لكلمات اللوحة.
///
/// أثناء السحب يرسم إطاراً خفيفاً حول الحقول التي تقبل النص المسحوب،
/// ويبرز الحقل عند المرور فوقه، ويحمرّ مع رسالة عندما لا تصلح الكلمة له
/// (مثل كلمة بلا رقم لحقل المبلغ)، ثم يومض بالأخضر لحظة قبول الإفلات.
class ClipboardDropTarget extends StatefulWidget {
  final Widget child;

  /// اسم الحقل كما يظهر في شارة «أفلت هنا».
  final String hint;

  /// يستقبل النص المُفلت ويعيد `true` إن استُخدم فعلاً.
  final bool Function(String text) onDrop;

  /// فحص مسبق أثناء السحب؛ `false` تُظهر حالة الرفض عند المرور فوق الحقل.
  final bool Function(String text)? canAccept;
  final String rejectHint;
  final bool enabled;

  const ClipboardDropTarget({
    super.key,
    required this.child,
    required this.hint,
    required this.onDrop,
    this.canAccept,
    this.rejectHint = 'غير مناسب لهذا الحقل',
    this.enabled = true,
  });

  @override
  State<ClipboardDropTarget> createState() => _ClipboardDropTargetState();
}

class _ClipboardDropTargetState extends State<ClipboardDropTarget> {
  Timer? _flashTimer;
  bool _flash = false;

  void _startFlash() {
    _flashTimer?.cancel();
    setState(() => _flash = true);
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  bool _accepts(String text) =>
      widget.enabled && (widget.canAccept?.call(text) ?? true);

  @override
  Widget build(BuildContext context) {
    final draggingText = ClipboardDragScope.draggingText(context);
    final ready = draggingText != null && _accepts(draggingText);
    final accent = AppUi.accent(context);
    final error = Theme.of(context).colorScheme.error;
    final success = AppUi.tone(context, AppColors.success);

    return DragTarget<ClipboardWords>(
      onWillAcceptWithDetails: (details) => _accepts(details.data.text),
      onAcceptWithDetails: (details) {
        if (widget.onDrop(details.data.text)) _startFlash();
      },
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        final rejecting = rejected.isNotEmpty;

        Color ring = Colors.transparent;
        Color fill = Colors.transparent;
        double width = 1.5;
        String? label;
        Color labelColor = accent;

        if (rejecting) {
          ring = error;
          fill = error.withValues(alpha: 0.06);
          width = 2;
          label = widget.rejectHint;
          labelColor = error;
        } else if (hovering) {
          ring = accent;
          fill = accent.withValues(alpha: 0.10);
          width = 2;
          label = 'أفلت هنا: ${widget.hint}';
        } else if (_flash) {
          ring = success;
          fill = success.withValues(alpha: 0.08);
          width = 2;
        } else if (ready) {
          ring = accent.withValues(alpha: 0.45);
          fill = accent.withValues(alpha: 0.03);
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            Positioned(
              left: -3,
              right: -3,
              top: -3,
              bottom: -3,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(AppDims.radius),
                    border: Border.all(color: ring, width: width),
                    boxShadow: hovering
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.22),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
            if (label != null)
              PositionedDirectional(
                top: -11,
                end: 12,
                child: IgnorePointer(
                  child: _DropLabel(text: label, color: labelColor),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DropLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _DropLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
    );
  }
}
