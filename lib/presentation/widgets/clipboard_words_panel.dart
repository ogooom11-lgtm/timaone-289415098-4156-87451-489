import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'app_ui.dart';

/// الحقول التي يمكن إرسال كلمات الحافظة إليها.
enum PasteTarget { beneficiary, amount, amount2, currency, currency2, note }

/// أدوات نصية مساعدة للوحة الحافظة.
class ClipboardText {
  const ClipboardText._();

  static final RegExp _splitter = RegExp(r'\s+');
  static final RegExp _edgePunct = RegExp(
    r'''^[،,.:;!؟?()\[\]{}"'«»\-–—_/\\|]+|[،,.:;!؟?()\[\]{}"'«»\-–—_/\\|]+$''',
  );

  /// تقسيم نص الحافظة إلى كلمات نظيفة (بدون علامات ترقيم على الأطراف).
  static List<String> tokenize(String raw) {
    final out = <String>[];
    for (final part in raw.split(_splitter)) {
      final w = part.replaceAll(_edgePunct, '').trim();
      if (w.isNotEmpty) out.add(w);
    }
    return out;
  }

  /// تحويل الأرقام العربية/الفارسية إلى لاتينية وتوحيد الفواصل.
  static String normalizeDigits(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final ai = arabic.indexOf(ch);
      final pi = persian.indexOf(ch);
      if (ai >= 0) {
        buf.write(ai);
      } else if (pi >= 0) {
        buf.write(pi);
      } else if (ch == '٫') {
        buf.write('.');
      } else if (ch == '٬') {
        // فاصل آلاف عربي — يُحذف
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  /// استخراج رقم صالح من نص مثل `1,500.50$` أو `١٢٠٠ دولار`.
  /// يعيد `null` إن لم يحتوِ النص على أي رقم.
  static String? extractNumber(String s) {
    final normalized = normalizeDigits(s).replaceAll(',', '');
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(normalized);
    if (match == null) return null;
    final value = match.group(0)!;
    // إزالة الأصفار البادئة غير الضرورية مع الإبقاء على "0.5"
    final parsed = double.tryParse(value);
    if (parsed == null) return null;
    return parsed == parsed.roundToDouble()
        ? parsed.toInt().toString()
        : parsed.toString();
  }

  /// هل يبدو النص رقماً/مبلغاً؟ (يُستخدم لتلوين الرقائق).
  static bool looksNumeric(String s) {
    final n = normalizeDigits(s);
    return RegExp(r'^[\d.,]+\s*[^\d\s]{0,4}$').hasMatch(n) ||
        RegExp(r'^[^\d\s]{0,4}\s*[\d.,]+$').hasMatch(n);
  }

  /// ما تبقى من النص بعد حذف الرقم — يُستخدم للتعرّف على العملة.
  static String nonNumericPart(String s) {
    return normalizeDigits(s)
        .replaceAll(RegExp(r'[\d.,]+'), ' ')
        .trim();
  }

  /// إبقاء الأحرف المسموحة في حقل الاسم فقط.
  static String sanitizeName(String s) {
    return s
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// حقل يستقبل كلمات الحافظة بالسحب والإفلات.
///
/// يُضاء بإطار خفيف أثناء أي عملية سحب، وبإطار قوي عندما يمرّ العنصر
/// المسحوب فوقه مباشرة.
class TimaDropField extends StatelessWidget {
  final Widget child;
  final ValueChanged<String> onDrop;
  final bool dragging;
  final Color? color;

  const TimaDropField({
    super.key,
    required this.child,
    required this.onDrop,
    this.dragging = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppUi.accent(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data.trim().isNotEmpty,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        final visible = hovering || dragging;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            child,
            // طبقة إضاءة فوق الحقل — لا تغيّر مقاساته.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: visible ? 1 : 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: hovering
                          ? accent.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppDims.radiusSm),
                      border: Border.all(
                        width: hovering ? 2 : 1.5,
                        color: hovering
                            ? accent
                            : accent.withValues(alpha: 0.45),
                      ),
                      boxShadow: hovering
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.30),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// لوحة نص الحافظة: تعرض النص الملصوق ككلمات قابلة للتحديد والسحب.
class ClipboardWordsPanel extends StatefulWidget {
  /// يُستدعى عند إرسال نص إلى حقل عبر أزرار الاختصار.
  final void Function(PasteTarget target, String text) onSend;

  /// يُبلّغ الصفحة ببدء/انتهاء السحب لإضاءة الحقول.
  final ValueChanged<bool>? onDraggingChanged;

  /// هل الحقل الثاني (المبلغ 2) ظاهر؟ يتحكم بظهور زر الاختصار الخاص به.
  final bool showSecondAmount;

  /// قراءة الحافظة تلقائياً عند أول عرض.
  final bool autoPaste;

  /// أقصى ارتفاع لمنطقة الكلمات (يُستخدم في التخطيط الضيق).
  /// إن كان `null` تملأ اللوحة الارتفاع المتاح.
  final double? wordsMaxHeight;

  const ClipboardWordsPanel({
    super.key,
    required this.onSend,
    this.onDraggingChanged,
    this.showSecondAmount = false,
    this.autoPaste = true,
    this.wordsMaxHeight,
  });

  @override
  State<ClipboardWordsPanel> createState() => _ClipboardWordsPanelState();
}

class _ClipboardWordsPanelState extends State<ClipboardWordsPanel>
    with WidgetsBindingObserver {
  final _rawController = TextEditingController();
  List<String> _words = const [];
  final Set<int> _selected = <int>{};
  final Set<int> _used = <int>{};
  bool _loading = false;

  /// آخر نص قُرئ من الحافظة — لتجنّب استبدال تعديلات المستخدم
  /// عند العودة للنافذة إن لم تتغيّر الحافظة.
  String? _lastClipboard;

  @override
  void initState() {
    super.initState();
    _rawController.addListener(_retokenize);
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoPaste) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _paste(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rawController.removeListener(_retokenize);
    _rawController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند العودة إلى النافذة (بعد نسخ رسالة من واتساب مثلاً)
    // نلتقط النص الجديد تلقائياً إن تغيّرت الحافظة.
    if (state == AppLifecycleState.resumed && widget.autoPaste) {
      _paste(silent: true, onlyIfChanged: true);
    }
  }

  void _retokenize() {
    final words = ClipboardText.tokenize(_rawController.text);
    if (_listEquals(words, _words)) return;
    setState(() {
      _words = words;
      _selected.clear();
      _used.clear();
    });
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _paste({bool silent = false, bool onlyIfChanged = false}) async {
    if (!silent) setState(() => _loading = true);
    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    } catch (_) {
      text = null;
    }
    if (!mounted) return;
    if (_loading) setState(() => _loading = false);

    final value = text?.trim() ?? '';
    if (value.isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الحافظة فارغة أو لا تحتوي على نص')),
        );
      }
      return;
    }
    if (onlyIfChanged && value == _lastClipboard) return;
    _lastClipboard = value;
    if (value == _rawController.text.trim()) return;
    _rawController.text = value;
  }

  void _clear() {
    _rawController.clear();
    setState(() {
      _selected.clear();
      _used.clear();
    });
  }

  void _toggle(int index) {
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  /// النص المركّب من الكلمات المحددة بترتيبها في النص الأصلي.
  String get _selectedText {
    final idx = _selected.toList()..sort();
    return idx.map((i) => _words[i]).join(' ');
  }

  /// ما سيُسحب عند مسك رقاقة معينة: كل المحدد إن كانت ضمنه، وإلا هي وحدها.
  String _payloadFor(int index) {
    if (_selected.contains(index)) return _selectedText;
    return _words[index];
  }

  Set<int> _indicesFor(int index) {
    if (_selected.contains(index)) return Set<int>.of(_selected);
    return {index};
  }

  void _markUsed(Set<int> indices) {
    setState(() {
      _used.addAll(indices);
      _selected.removeAll(indices);
    });
  }

  void _send(PasteTarget target) {
    final text = _selectedText;
    if (text.isEmpty) return;
    final indices = Set<int>.of(_selected);
    widget.onSend(target, text);
    _markUsed(indices);
  }

  void _setDragging(bool value) => widget.onDraggingChanged?.call(value);

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);
    final hasWords = _words.isNotEmpty;
    final hasSelection = _selected.isNotEmpty;

    final wordsArea = hasWords
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _words.length; i++) _buildChip(i),
              ],
            ),
          )
        : _EmptyHint(loading: _loading, onPaste: () => _paste());

    return TimaPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: widget.wordsMaxHeight == null
            ? MainAxisSize.max
            : MainAxisSize.min,
        children: [
          // ---- الرأس -------------------------------------------------
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppUi.softFill(context, accent),
                  borderRadius: BorderRadius.circular(AppDims.radiusSm),
                ),
                child: Icon(Icons.content_paste_rounded, color: accent, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'نص الحافظة',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'انقر لتحديد الكلمات ثم اسحبها إلى الحقل',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'لصق من الحافظة',
                onPressed: _loading ? null : () => _paste(),
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.content_paste_go_rounded),
                color: accent,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'مسح',
                onPressed: hasWords ? _clear : null,
                icon: const Icon(Icons.delete_sweep_outlined),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ---- صندوق النص الخام ---------------------------------------
          TextField(
            controller: _rawController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
            decoration: const InputDecoration(
              hintText: 'الصق النص هنا (Ctrl+V) أو اضغط زر اللصق…',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
          ),
          const SizedBox(height: 10),

          // ---- شريط التحديد + أزرار الاختصار -----------------------------
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: hasSelection
                ? _SelectionBar(
                    text: _selectedText,
                    count: _selected.length,
                    showSecondAmount: widget.showSecondAmount,
                    onSend: _send,
                    onClear: () => setState(_selected.clear),
                    onDragStarted: () => _setDragging(true),
                    onDragEnd: () => _setDragging(false),
                    onDropped: () => _markUsed(Set<int>.of(_selected)),
                  )
                : const SizedBox.shrink(),
          ),

          // ---- منطقة الكلمات ------------------------------------------
          if (widget.wordsMaxHeight == null)
            Expanded(child: _wordsBox(context, wordsArea))
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: widget.wordsMaxHeight!,
                minHeight: 72,
              ),
              child: _wordsBox(context, wordsArea),
            ),

          if (hasWords) ...[
            const SizedBox(height: 8),
            Text(
              '${_words.length} كلمة • ${_used.length} مستخدمة',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _wordsBox(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppUi.sunken(context),
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        border: Border.all(color: AppUi.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildChip(int index) {
    final word = _words[index];
    final selected = _selected.contains(index);
    final used = _used.contains(index);
    final numeric = ClipboardText.looksNumeric(word);

    final chip = _WordChip(
      label: word,
      selected: selected,
      used: used,
      numeric: numeric,
      onTap: () => _toggle(index),
    );

    return Draggable<String>(
      data: _payloadFor(index),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        // مسك رقاقة غير محددة يجعلها المحددة الوحيدة لتوضيح ما يُسحب.
        if (!_selected.contains(index)) {
          setState(() {
            _selected
              ..clear()
              ..add(index);
          });
        }
        _setDragging(true);
      },
      onDragEnd: (_) => _setDragging(false),
      onDragCompleted: () => _markUsed(_indicesFor(index)),
      feedback: _DragFeedback(text: _payloadFor(index)),
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      child: chip,
    );
  }
}

// ---------------------------------------------------------------------------
// عناصر داخلية
// ---------------------------------------------------------------------------

class _WordChip extends StatefulWidget {
  final String label;
  final bool selected;
  final bool used;
  final bool numeric;
  final VoidCallback onTap;

  const _WordChip({
    required this.label,
    required this.selected,
    required this.used,
    required this.numeric,
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
    final gold = AppUi.tone(context, AppColors.brandGoldDark);
    final base = widget.numeric ? gold : accent;

    final Color bg;
    final Color fg;
    final Color border;
    if (widget.selected) {
      bg = base;
      fg = Colors.white;
      border = base;
    } else if (widget.used) {
      bg = Colors.transparent;
      fg = AppUi.textSecondary(context).withValues(alpha: 0.55);
      border = AppUi.border(context);
    } else {
      bg = _hover ? AppUi.softFill(context, base) : AppUi.surface(context);
      fg = widget.numeric ? gold : AppUi.textPrimary(context);
      border = _hover ? base.withValues(alpha: 0.6) : AppUi.borderStrong(context);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.used && !widget.selected) ...[
                Icon(Icons.check_rounded, size: 12, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: widget.selected || widget.numeric
                      ? FontWeight.w700
                      : FontWeight.w600,
                  decoration: widget.used && !widget.selected
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  final String text;
  const _DragFeedback({required this.text});

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);
    return Material(
      color: Colors.transparent,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
            boxShadow: AppUi.raisedShadow(context),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator_rounded,
                  color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
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

class _SelectionBar extends StatelessWidget {
  final String text;
  final int count;
  final bool showSecondAmount;
  final ValueChanged<PasteTarget> onSend;
  final VoidCallback onClear;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;
  final VoidCallback onDropped;

  const _SelectionBar({
    required this.text,
    required this.count,
    required this.showSecondAmount,
    required this.onSend,
    required this.onClear,
    required this.onDragStarted,
    required this.onDragEnd,
    required this.onDropped,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppUi.accent(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppUi.softFill(context, accent),
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Draggable<String>(
            data: text,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            onDragStarted: onDragStarted,
            onDragEnd: (_) => onDragEnd(),
            onDragCompleted: onDropped,
            feedback: _DragFeedback(text: text),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Row(
                children: [
                  Icon(Icons.drag_indicator_rounded, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppUi.textPrimary(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TimaStatusPill(
                    label: count == 1 ? 'كلمة' : '$count كلمات',
                    color: accent,
                  ),
                  IconButton(
                    tooltip: 'إلغاء التحديد',
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'اسحب الشريط إلى الحقل، أو أرسل مباشرة:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuickButton(
                icon: Icons.person_outline_rounded,
                label: 'الاسم',
                onTap: () => onSend(PasteTarget.beneficiary),
              ),
              _QuickButton(
                icon: Icons.payments_outlined,
                label: 'المبلغ',
                color: AppColors.brandGoldDark,
                onTap: () => onSend(PasteTarget.amount),
              ),
              if (showSecondAmount)
                _QuickButton(
                  icon: Icons.payments_outlined,
                  label: 'المبلغ 2',
                  color: AppColors.brandGoldDark,
                  onTap: () => onSend(PasteTarget.amount2),
                ),
              _QuickButton(
                icon: Icons.note_alt_outlined,
                label: 'الملاحظات',
                onTap: () => onSend(PasteTarget.note),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _QuickButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppUi.tone(context, color ?? AppUi.accent(context));
    return SizedBox(
      height: 30,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c.withValues(alpha: 0.5)),
          backgroundColor: AppUi.surface(context),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final bool loading;
  final VoidCallback onPaste;
  const _EmptyHint({required this.loading, required this.onPaste});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.content_paste_off_rounded,
              size: 30,
              color: AppUi.textSecondary(context).withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
            Text(
              'لا يوجد نص بعد',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'انسخ رسالة العميل ثم اضغط لصق',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: loading ? null : onPaste,
              icon: const Icon(Icons.content_paste_go_rounded, size: 16),
              label: const Text('لصق من الحافظة'),
            ),
          ],
        ),
      ),
    );
  }
}
