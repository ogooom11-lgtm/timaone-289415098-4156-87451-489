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
