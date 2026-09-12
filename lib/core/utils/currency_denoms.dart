import '../storage/app_database.dart';
import '../storage/device_settings.dart';
import 'currency_catalog.dart';

/// أدوات مشتركة لاستخراج فئات العملة وتنسيقها ومخزون الأوراق.
class CurrencyDenoms {
  CurrencyDenoms._();

  static String displayName(Currency currency) {
    final name = currency.name;
    if (name == null || name.isEmpty) return currency.code;
    if (name.contains('|')) return name.split('|').first.trim();
    return name;
  }

  static List<double> forCurrency(Currency currency) {
    final name = currency.name;
    if (name != null && name.contains('|')) {
      final parts = name.split('|');
      if (parts.length > 1) {
        final parsed = parts[1]
            .split(RegExp(r'[,،\s]+'))
            .map((e) => double.tryParse(e.trim()) ?? 0)
            .where((e) => e > 0)
            .toList();
        if (parsed.isNotEmpty) {
          parsed.sort((a, b) => b.compareTo(a));
          return parsed;
        }
      }
    }
    return defaultsForCode(currency.code);
  }

  /// الفئات الافتراضية لرمز عملة، من سجلّ العملات المركزي.
  static List<double> defaultsForCode(String code) {
    return currencySpecForCode(code)?.denoms ?? kGenericDenoms;
  }

  /// الاسم العربي الافتراضي لرمز عملة، أو `null` إن كانت غير معروفة.
  static String? defaultNameForCode(String code) {
    return currencySpecForCode(code)?.name;
  }

  static String defaultsTextForCode(String code) {
    return defaultsForCode(code)
        .map((e) => e == e.roundToDouble() ? e.toInt().toString() : e.toString())
        .join(', ');
  }

  static String combineNameAndDenoms(String name, String denomsCsv) {
    final cleaned = denomsCsv
        .split(RegExp(r'[,،]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(', ');
    return '$name|$cleaned';
  }

  static String formatCounts(Map<double, int> counts) {
    final parts = <String>[];
    final keys = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final denom in keys) {
      final count = counts[denom] ?? 0;
      if (count > 0) {
        final d = denom == denom.roundToDouble()
            ? denom.toInt().toString()
            : denom.toString();
        parts.add('$d×$count');
      }
    }
    return parts.isEmpty ? '—' : parts.join(' + ');
  }

  /// يقرأ خريطة الفئات من نص مثل: `100×2 + 50×1` أو `100x2, 50x1`
  static Map<double, int> parseCounts(String? text) {
    final result = <double, int>{};
    if (text == null || text.trim().isEmpty) return result;

    // التقط كل أزواج (فئة × عدد) أو (فئة x عدد)
    final re = RegExp(
      r'(\d+(?:\.\d+)?)\s*[xX×*]\s*(\d+)',
      multiLine: true,
    );
    for (final m in re.allMatches(text)) {
      final denom = double.tryParse(m.group(1)!);
      final count = int.tryParse(m.group(2)!);
      if (denom == null || count == null || count <= 0) continue;
      result[denom] = (result[denom] ?? 0) + count;
    }
    return result;
  }

  /// يستخرج نص فئات المسلم (المبلغ 1) من ملاحظة الحركة.
  static String? extractDeliveredDenomsNote(String? note) {
    if (note == null || note.isEmpty) return null;
    final m = RegExp(r'\[فئات المسلم:\s*([^\]]+)\]').firstMatch(note);
    return m?.group(1);
  }

  /// يستخرج نص فئات المسلم الثاني من ملاحظة الحركة.
  static String? extractDeliveredDenomsNote2(String? note) {
    if (note == null || note.isEmpty) return null;
    final m = RegExp(r'\[فئات المسلم 2:\s*([^\]]+)\]').firstMatch(note);
    return m?.group(1);
  }

  /// يجمع أزواج (رمز العملة ← الفئات) من أسطر مثل `[بادئة USD: 100x1]`.
  static Map<String, Map<double, int>> _allCodeCounts(
    String note,
    String marker,
  ) {
    final re = RegExp(
      RegExp.escape('[$marker') + r'\s*([^\]:]+):\s*([^\]]+)\]',
    );
    final out = <String, Map<double, int>>{};
    for (final m in re.allMatches(note)) {
      out[(m.group(1) ?? '').trim()] = parseCounts(m.group(2));
    }
    return out;
  }

  /// يحسب أثر حركة محفوظة على المخزون حسب نوعها وصيغة ملاحظتها.
  static Map<int, OldStockEffect> oldStockEffects(
    Transaction tx,
    Map<int, Currency> currencies,
  ) {
    final out = <int, OldStockEffect>{};
    final note = tx.note;
    if (note == null || note.trim().isEmpty) return out;
    Currency? byId(int? id) => id == null ? null : currencies[id];

    if (tx.type.contains('تسليم') || tx.type == 'حركة يوزر') {
      final c1 = byId(tx.currencyId);
      final c2 = byId(tx.targetCurrencyId);
      // صيغة التسليم: [فئات المسلم: ...] و[فئات المسلم 2: ... (CODE)]
      var d1 = parseCounts(extractDeliveredDenomsNote(note));
      var d2 = parseCounts(extractDeliveredDenomsNote2(note));
      // صيغة يوزر: [الفئات المسلمة لـ CODE: ...] لكل عملة على حدة.
      if (d1.isEmpty) {
        final byCode = _allCodeCounts(note, 'الفئات المسلمة لـ');
        if (byCode.isNotEmpty) {
          d1 = (c1 != null ? byCode[c1.code] : null) ?? byCode.values.first;
          d2 = (c2 != null ? byCode[c2.code] : null) ?? const {};
        }
      }
      if (c1 != null && d1.isNotEmpty) out[c1.id] = OldStockEffect(d1, false);
      if (c2 != null && d2.isNotEmpty) out[c2.id] = OldStockEffect(d2, false);
      return out;
    }

    if (tx.type == 'حركة تسوية' || tx.type.contains('صرف')) {
      final fromCounts = _allCodeCounts(note, 'فئات المسلم لـ');
      final toCounts = _allCodeCounts(note, 'فئات المستلم لـ');
      final from = byId(tx.currencyId);
      final to = byId(tx.targetCurrencyId);
      if (from != null) {
        final c = fromCounts[from.code] ??
            (fromCounts.isNotEmpty ? fromCounts.values.first : const {});
        if (c.isNotEmpty) out[from.id] = OldStockEffect(c, false);
      }
      if (to != null) {
        final c = toCounts[to.code] ??
            (toCounts.isNotEmpty ? toCounts.values.first : const {});
        if (c.isNotEmpty) out[to.id] = OldStockEffect(c, true);
      }
      return out;
    }

    // استلام / مرسلة — فئات واردة.
    final marker = tx.type.contains('مرسلة')
        ? 'الفئات المستلمة للحوالة لـ'
        : 'الفئات المستلمة لـ';
    final codeCounts = _allCodeCounts(note, marker);
    for (final id in [tx.currencyId, tx.targetCurrencyId]) {
      final cur = byId(id);
      if (cur == null) continue;
      final exact = codeCounts[cur.code];
      if (exact != null && exact.isNotEmpty) {
        out[cur.id] = OldStockEffect(exact, true);
      } else if (id == tx.currencyId && codeCounts.isNotEmpty) {
        out[cur.id] = OldStockEffect(codeCounts.values.first, true);
      }
    }
    // فئات الأجور في الحركة المرسلة — واردة هي أيضاً، وتُدمج مع المستلم
    // إن كانت عملتها مطابقة لعملة الاستلام.
    if (tx.type.contains('مرسلة')) {
      final feeCounts = _allCodeCounts(note, 'فئات الأجور لـ');
      final feesCur = byId(tx.feesCurrencyId);
      if (feesCur != null && feeCounts.isNotEmpty) {
        final fc = feeCounts[feesCur.code] ?? feeCounts.values.first;
        if (fc.isNotEmpty) {
          final existing = out[feesCur.id];
          if (existing != null) {
            final merged = Map<double, int>.from(existing.counts);
            fc.forEach((d, c) => merged[d] = (merged[d] ?? 0) + c);
            out[feesCur.id] = OldStockEffect(merged, true);
          } else {
            out[feesCur.id] = OldStockEffect(fc, true);
          }
        }
      }
    }
    return out;
  }

  /// يعكس أثر حركة قديمة على المخزون — يُستدعى قبل تطبيق تعديل عليها.
  ///
  /// حركة واردة تُخصم فئاتها القديمة، وحركة صادرة تُعاد فئاتها، فيصبح
  /// صافي التغيير مساوياً للفرق بين القديم والجديد فقط.
  static Future<void> reverseOldStock(
    Transaction oldTx,
    Map<int, Currency> currencies,
  ) async {
    final effects = oldStockEffects(oldTx, currencies);
    for (final entry in effects.entries) {
      final cur = currencies[entry.key];
      if (cur == null || entry.value.counts.isEmpty) continue;
      if (entry.value.isInflow) {
        await deductStock(cur, entry.value.counts);
      } else {
        await addStock(cur, entry.value.counts);
      }
    }
  }

  static double sumCounts(Map<double, int> counts) {
    var sum = 0.0;
    counts.forEach((denom, count) => sum += denom * count);
    return sum;
  }

  static String billCountKey(int currencyId, double denom) =>
      'bill_count_${currencyId}_$denom';

  static String fmtDenom(double denom) {
    return denom == denom.roundToDouble()
        ? denom.toInt().toString()
        : denom.toString();
  }

  /// يقرأ مخزون أوراق فئة واحدة لعملة.
  static Future<Map<double, int>> loadStock(Currency currency) async {
    final denoms = forCurrency(currency);
    final data = await DeviceSettings.readAll();
    final map = <double, int>{};
    for (final d in denoms) {
      final key = billCountKey(currency.id, d);
      final value = data[key];
      if (value is int) {
        map[d] = value;
      } else if (value is num) {
        map[d] = value.toInt();
      } else if (value is String) {
        map[d] = int.tryParse(value) ?? 0;
      } else {
        map[d] = 0;
      }
    }
    return map;
  }

  /// خصم من المخزون (تسليم / صرف صادر). لا ينزل تحت الصفر.
  static Future<void> deductStock(
    Currency currency,
    Map<double, int> used,
  ) async {
    if (used.isEmpty) return;
    final data = await DeviceSettings.readAll();
    used.forEach((denom, count) {
      if (count <= 0) return;
      final key = billCountKey(currency.id, denom);
      final current = _asInt(data[key]);
      final next = current - count;
      data[key] = next < 0 ? 0 : next;
    });
    await DeviceSettings.writeAll(data);
  }

  /// إضافة للمخزون (استلام / صرف وارد / رصيد افتتاحي).
  static Future<void> addStock(
    Currency currency,
    Map<double, int> gained,
  ) async {
    if (gained.isEmpty) return;
    final data = await DeviceSettings.readAll();
    gained.forEach((denom, count) {
      if (count <= 0) return;
      final key = billCountKey(currency.id, denom);
      final current = _asInt(data[key]);
      data[key] = current + count;
    });
    await DeviceSettings.writeAll(data);
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// توزيع المبلغ على أكبر الفئات أولاً (greedy)، مع احترام المخزون إن وُجد.
  static Map<double, int> autoFill(
    double amount,
    List<double> denoms, {
    Map<double, int>? availableStock,
  }) {
    final sorted = [...denoms]..sort((a, b) => b.compareTo(a));
    final result = {for (final d in sorted) d: 0};
    var remaining = amount;
    for (final denom in sorted) {
      if (denom <= 0) continue;
      if (denom > remaining + 0.001) continue;
      var maxByAmount = (remaining / denom).floor();
      if (availableStock != null) {
        final stock = availableStock[denom] ?? 0;
        if (stock <= 0) continue;
        if (maxByAmount > stock) maxByAmount = stock;
      }
      if (maxByAmount > 0) {
        result[denom] = maxByAmount;
        remaining -= maxByAmount * denom;
        if (remaining.abs() < 0.001) remaining = 0;
      }
    }
    return result;
  }
}

/// أثر حركة قديمة على مخزون الأوراق: الفئات المسجّلة + اتجاهها.
///
/// يُستخدم عند تعديل حركة سبق أن لامست المخزون، لعكس أثرها القديم
/// قبل تطبيق الفئات الجديدة، فيتحدّث الرصيد بالفرق الصحيح فقط.
class OldStockEffect {
  final Map<double, int> counts;
  final bool isInflow;
  const OldStockEffect(this.counts, this.isInflow);
}
