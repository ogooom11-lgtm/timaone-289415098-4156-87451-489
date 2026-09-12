/// أدوات نصية للوحة «نص الحافظة»: تقطيع الكلمات، استخراج الأرقام،
/// والتعرّف على العملات من كلمات حرّة منسوخة من رسائل العملاء.
///
/// دوال خالصة بلا أي اعتماد على Flutter حتى يسهل اختبارها.
library;

class ClipboardText {
  const ClipboardText._();

  /// أقصى طول نصّ يُقبل من الحافظة (حماية من لصق ملفات ضخمة بالخطأ).
  static const int maxChars = 4000;

  /// علامات ترقيم تُقصّ من طرفي الكلمة فقط — لا من داخلها، حتى تبقى
  /// «1.500» و«ل.س» و«0933-123» سليمة.
  static const String _edgePunctuation =
      "،,.:;؛!؟?()[]{}<>\"'«»“”‘’…-–—_/\\|*#~`^+=";

  static bool _isEdgePunctuation(String ch) => _edgePunctuation.contains(ch);

  /// يقصّ علامات الترقيم من طرفي الكلمة ويبقي ما بداخلها.
  static String trimPunctuation(String raw) {
    var start = 0;
    var end = raw.length;
    while (start < end && _isEdgePunctuation(raw[start])) {
      start++;
    }
    while (end > start && _isEdgePunctuation(raw[end - 1])) {
      end--;
    }
    return raw.substring(start, end);
  }

  /// يفصل «المبلغ:500» و«محمد،أحمد» إلى كلمتين دون كسر الأرقام مثل 1,500
  /// أو ١،٥٠٠ (الفاصلة اللاتينية والعربية بين رقمين تبقى جزءاً من الرقم).
  static final RegExp _inlineSeparators = RegExp(
    r'[:：;؛]|(?<![\d\u0660-\u0669\u06F0-\u06F9])[,،]|[,،](?![\d\u0660-\u0669\u06F0-\u06F9])',
  );

  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// يقسّم النص إلى أسطر، وكل سطر إلى كلمات نظيفة.
  ///
  /// تُحفظ بنية الأسطر لأن رسائل التحويل عادةً تكون على شكل
  /// «الاسم: …» ثم «المبلغ: …» فيسهل على العين إيجاد الكلمة.
  static List<List<String>> tokenizeLines(String text) {
    final lines = <List<String>>[];
    for (final rawLine in text.split(_lineBreak)) {
      final words = <String>[];
      for (final chunk in rawLine.split(_whitespace)) {
        for (final piece in chunk.split(_inlineSeparators)) {
          final word = trimPunctuation(piece);
          if (word.isNotEmpty) words.add(word);
        }
      }
      if (words.isNotEmpty) lines.add(words);
    }
    return lines;
  }

  /// يحوّل الأرقام العربية الهندية (٠١٢) والفارسية (۰۱۲) إلى لاتينية.
  static String normalizeDigits(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + (rune - 0x0660));
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(0x30 + (rune - 0x06F0));
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// توحيد الحروف العربية للمطابقة المرنة (أ/إ/آ → ا، ة → ه، ى → ي)
  /// مع حذف التشكيل والتطويل وتحويل اللاتيني إلى أحرف صغيرة.
  static String normalizeArabic(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u0652\u0640]'), '')
        .replaceAll(RegExp('[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
  }

  /// هل تبدو الكلمة رقماً (مبلغ، رقم هاتف…)؟ تُستخدم لتلوين الكلمات فقط.
  static bool looksNumeric(String word) {
    final normalized = normalizeDigits(word);
    final digits = RegExp(r'\d').allMatches(normalized).length;
    if (digits == 0) return false;
    final letters = RegExp(r'[A-Za-z\u0600-\u06FF]').allMatches(normalized).length;
    return digits >= letters;
  }

  /// يستخرج أول رقم من النص ويعيده بصيغة يقبلها `double.parse`،
  /// أو `null` إن لم يوجد رقم.
  ///
  /// يتعامل مع الأرقام العربية، وفواصل الآلاف (1,500 / 1.000.000 / ١٬٥٠٠)،
  /// والفاصلة العشرية العربية (٫)، والرموز الملتصقة مثل «500$».
  static String? extractNumber(String text) {
    final normalized = normalizeDigits(text)
        .replaceAll('\u066B', '.') // ٫ فاصلة عشرية عربية
        .replaceAll('\u066C', ',') // ٬ فاصلة آلاف عربية
        .replaceAll('\u060C', ','); // ، فاصلة عربية تُستخدم أحياناً للآلاف

    final match = RegExp(r'\d[\d.,]*').firstMatch(normalized);
    if (match == null) return null;

    final run = match.group(0)!.replaceAll(RegExp(r'[.,]+$'), '');
    final value = double.tryParse(_canonicalNumber(run));
    if (value == null) return null;
    return formatAmount(value);
  }

  /// يحوّل «1,500» و«1.500,25» و«2,5» و«1.000.000» إلى صيغة يفهمها
  /// `double.parse`، وفق العُرف المحلي في كتابة المبالغ.
  static String _canonicalNumber(String run) {
    final lastDot = run.lastIndexOf('.');
    final lastComma = run.lastIndexOf(',');

    if (lastDot >= 0 && lastComma >= 0) {
      // وجود الفاصلين معاً: الأخير عشري والآخر فاصل آلاف
      // (1,500.25 أو 1.500,25).
      final decimal = lastDot > lastComma ? '.' : ',';
      final thousands = decimal == '.' ? ',' : '.';
      final parts = run.replaceAll(thousands, '').split(decimal);
      if (parts.length == 2) return '${parts[0]}.${parts[1]}';
      return parts.join();
    }

    final String separator;
    if (lastDot >= 0) {
      separator = '.';
    } else if (lastComma >= 0) {
      separator = ',';
    } else {
      return run;
    }

    final parts = run.split(separator);
    // أكثر من فاصل واحد ⇒ فواصل آلاف حتماً (1.000.000).
    if (parts.length > 2) return parts.join();

    final head = parts[0];
    final tail = parts[1];
    // «1.500» و«12,500»: ثلاثة أرقام بالضبط بعد فاصل واحد تُقرأ فاصل آلاف
    // كما يكتبها الناس محلياً، ما لم يسبقها صفر أو أكثر من ثلاثة أرقام
    // (0.500 و1234.500 عشرية بوضوح).
    final isThousands =
        tail.length == 3 && head.isNotEmpty && head.length <= 3 && head != '0';
    return isThousands ? '$head$tail' : '$head.$tail';
  }

  /// يعرض المبلغ بلا كسر عشري إن كان صحيحاً: 1500 بدل 1500.0
  static String formatAmount(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// ينظّف النص ليصلح لحقل الاسم (يطابق مرشّح الإدخال في النموذج):
  /// حروف عربية ولاتينية وأرقام ومسافات فقط.
  static String cleanForName(String text) {
    return text
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9 ]'), ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  // -------------------------------------------------------------------
  // التعرّف على العملة
  // -------------------------------------------------------------------

  /// يحاول استنتاج رمز العملة (USD, TRY…) من نص حرّ.
  ///
  /// يفحص أولاً رموز العملات المعرّفة فعلاً في الصندوق [knownCodes]
  /// ككلمة كاملة، ثم الرموز (\$, €, ₺…) والكلمات الشائعة عربياً ولاتينياً.
  /// الكلمات المبهمة (ليرة، دينار، ريال، جنيه) وحدها لا تُحسم.
  static String? detectCurrencyCode(
    String text, {
    Iterable<String> knownCodes = const [],
  }) {
    final normalized = normalizeArabic(text);
    final tokens = normalized
        .split(_whitespace)
        .map(trimPunctuation)
        .where((t) => t.isNotEmpty)
        .toList();

    for (final code in knownCodes) {
      final lower = code.trim().toLowerCase();
      if (lower.isEmpty) continue;
      if (tokens.contains(lower)) return code;
    }

    for (final hint in _hints) {
      for (final symbol in hint.symbols) {
        if (normalized.contains(symbol)) return hint.code;
      }
      for (final word in hint.words) {
        if (tokens.contains(word)) return hint.code;
      }
      for (final token in tokens) {
        if (hint.excludes.contains(token)) continue;
        for (final root in hint.roots) {
          if (token.contains(root)) return hint.code;
        }
      }
    }
    return null;
  }

  static const List<_CurrencyHint> _hints = [
    _CurrencyHint(
      'USD',
      symbols: [r'$'],
      words: ['usd', 'dollar', 'dollars'],
      roots: ['دولار'],
    ),
    _CurrencyHint(
      'EUR',
      symbols: ['€'],
      words: ['eur', 'euro', 'euros'],
      roots: ['يورو'],
    ),
    _CurrencyHint(
      'TRY',
      symbols: ['₺'],
      words: ['try', 'tl', 'lira'],
      roots: ['تركي'],
      excludes: ['تركيا'],
    ),
    _CurrencyHint(
      'SYP',
      words: ['syp', 'sp'],
      roots: ['سوري', 'ل.س'],
      excludes: ['سوريا'],
    ),
    _CurrencyHint(
      'GBP',
      symbols: ['£'],
      words: ['gbp', 'sterling'],
      roots: ['استرليني'],
    ),
    _CurrencyHint(
      'SAR',
      words: ['sar'],
      roots: ['سعودي', 'ر.س'],
      excludes: ['السعوديه'],
    ),
    _CurrencyHint(
      'AED',
      words: ['aed', 'dhs'],
      roots: ['اماراتي', 'درهم'],
    ),
    _CurrencyHint(
      'JOD',
      words: ['jod', 'jd'],
      roots: ['اردني'],
    ),
    _CurrencyHint(
      'QAR',
      words: ['qar'],
      roots: ['قطري', 'ر.ق'],
    ),
    _CurrencyHint(
      'KWD',
      words: ['kwd', 'kd'],
      roots: ['كويتي', 'د.ك'],
    ),
    _CurrencyHint(
      'IQD',
      words: ['iqd'],
      roots: ['عراقي', 'د.ع'],
    ),
    _CurrencyHint(
      'EGP',
      words: ['egp'],
      roots: ['مصري', 'ج.م'],
    ),
    _CurrencyHint(
      'LBP',
      words: ['lbp'],
      roots: ['لبناني', 'ل.ل'],
    ),
    _CurrencyHint(
      'BHD',
      words: ['bhd'],
      roots: ['بحريني', 'د.ب'],
    ),
    _CurrencyHint(
      'OMR',
      words: ['omr'],
      roots: ['عماني', 'ر.ع'],
    ),
  ];
}

/// دلائل التعرّف على عملة واحدة.
class _CurrencyHint {
  final String code;

  /// رموز تُطابَق بالاحتواء في أي موضع (\$، €…).
  final List<String> symbols;

  /// كلمات لاتينية تُطابَق ككلمة كاملة فقط (حتى لا تطابق try داخل country).
  final List<String> words;

  /// جذور عربية تُطابَق بالاحتواء داخل الكلمة لتغطية السوابق واللواحق
  /// (بالدولار، دولارات، التركية).
  final List<String> roots;

  /// كلمات كاملة (بصيغتها المطبَّعة) تحتوي الجذر لكنها لا تعني العملة،
  /// كأسماء الدول: «تركيا» ليست «ليرة تركية».
  final List<String> excludes;

  const _CurrencyHint(
    this.code, {
    this.symbols = const [],
    this.words = const [],
    this.roots = const [],
    this.excludes = const [],
  });
}
