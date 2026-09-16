import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DeviceSettings {
  static const _fileName = 'tima_device_settings.json';

  static Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  static Future<File> settingsFileForBackup() => _settingsFile();

  static Future<Map<String, dynamic>> _read() async {
    final file = await _settingsFile();
    if (!await file.exists()) return <String, dynamic>{};

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return <String, dynamic>{};
    }

    return <String, dynamic>{};
  }

  static Future<void> _write(Map<String, dynamic> data) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode(data));
  }

  // --- Public Methods to read/write custom JSON settings ---
  static Future<Map<String, dynamic>> readAll() => _read();
  static Future<void> writeAll(Map<String, dynamic> data) => _write(data);

  // --- Reconciliations Ledger / Snapshots ---
  static Future<List<Map<String, dynamic>>> getReconciliations() async {
    final data = await _read();
    final value = data['reconciliations'];
    if (value is List) {
      return List<Map<String, dynamic>>.from(
        value.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  }

  static Future<void> saveReconciliations(
    List<Map<String, dynamic>> list,
  ) async {
    final data = await _read();
    data['reconciliations'] = list;
    await _write(data);
  }

  // --- Reconciliation selection (kept until the user explicitly clears it) ---
  static Future<Set<int>> reconciliationSelection() async {
    final data = await _read();
    final value = data['reconciliationSelection'];
    if (value is! List) return <int>{};
    return value.whereType<num>().map((item) => item.toInt()).toSet();
  }

  static Future<void> saveReconciliationSelection(Set<int> ids) async {
    final data = await _read();
    data['reconciliationSelection'] = ids.toList()..sort();
    await _write(data);
  }

  static Future<void> clearReconciliationSelection() async {
    final data = await _read();
    data.remove('reconciliationSelection');
    await _write(data);
  }

  static Future<int?> rememberedUserId() async {
    final data = await _read();
    final value = data['rememberedUserId'];
    return value is int ? value : null;
  }

  static Future<void> rememberUser(int userId) async {
    final data = await _read();
    data['rememberedUserId'] = userId;
    await _write(data);
  }

  static Future<void> clearRememberedUser() async {
    final data = await _read();
    data.remove('rememberedUserId');
    await _write(data);
  }

  static Future<String> themeModeName() async {
    final data = await _read();
    final value = data['themeMode'];
    return value is String ? value : 'system';
  }

  static Future<void> saveThemeModeName(String themeModeName) async {
    final data = await _read();
    data['themeMode'] = themeModeName;
    await _write(data);
  }

  // --- Sound preference ---
  /// أصوات التطبيق مفعّلة افتراضياً ما لم يكتمها المستخدم.
  static Future<bool> getSoundEnabled() async {
    final data = await _read();
    return data['soundEnabled'] != false;
  }

  static Future<void> setSoundEnabled(bool value) async {
    final data = await _read();
    data['soundEnabled'] = value;
    await _write(data);
  }

  // --- Office setup wizard completion ---
  static Future<bool> isOfficeSetupCompleted() async {
    final data = await _read();
    return data['officeSetupCompleted'] == true;
  }

  static Future<void> markOfficeSetupCompleted() async {
    final data = await _read();
    data['officeSetupCompleted'] = true;
    data['officeSetupCompletedAt'] = DateTime.now().toIso8601String();
    await _write(data);
  }

  static Future<void> clearOfficeSetupFlag() async {
    final data = await _read();
    data.remove('officeSetupCompleted');
    data.remove('officeSetupCompletedAt');
    await _write(data);
  }

  // --- Office identity and first-run configuration ---
  static Future<String?> officeName() async {
    final data = await _read();
    final value = data['officeName'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static Future<void> saveOfficeName(String name) async {
    final data = await _read();
    data['officeName'] = name.trim();
    await _write(data);
  }

  static Future<String?> telegramBotToken() async {
    final data = await _read();
    final value = data['telegramBotToken'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static Future<String?> telegramChatId() async {
    final data = await _read();
    final value = data['telegramChatId'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static Future<void> saveTelegramConfig({
    required String token,
    required String chatId,
  }) async {
    final data = await _read();
    if (token.trim().isEmpty || chatId.trim().isEmpty) {
      data.remove('telegramBotToken');
      data.remove('telegramChatId');
    } else {
      data['telegramBotToken'] = token.trim();
      data['telegramChatId'] = chatId.trim();
    }
    await _write(data);
  }

  // --- Bill / denomination inventory counts ---
  static Future<int> getBillCount(int currencyId, double denom) async {
    final data = await _read();
    final key = 'bill_count_${currencyId}_$denom';
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static Future<void> setBillCount(
    int currencyId,
    double denom,
    int count,
  ) async {
    final data = await _read();
    data['bill_count_${currencyId}_$denom'] = count < 0 ? 0 : count;
    await _write(data);
  }

  /// يحفظ خريطة فئات لعملة واحدة دفعة واحدة.
  static Future<void> setBillCountsForCurrency(
    int currencyId,
    Map<double, int> counts,
  ) async {
    final data = await _read();
    counts.forEach((denom, count) {
      data['bill_count_${currencyId}_$denom'] = count < 0 ? 0 : count;
    });
    await _write(data);
  }

  // --- Default printer ---
  static Future<String?> defaultPrinterName() async {
    final data = await _read();
    final value = data['defaultPrinterName'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static Future<void> saveDefaultPrinterName(String? name) async {
    final data = await _read();
    if (name == null || name.trim().isEmpty) {
      data.remove('defaultPrinterName');
    } else {
      data['defaultPrinterName'] = name.trim();
    }
    await _write(data);
  }

  // --- Receipt (إيصال الطباعة) preferences ---
  /// الإعدادات الكاملة للإيصال كما حفظتها `ReceiptSettings.save()`.
  static Future<Map<String, dynamic>> receiptSettings() async {
    final data = await _read();
    final value = data['receiptSettings'];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static Future<void> saveReceiptSettings(Map<String, dynamic> value) async {
    final data = await _read();
    data['receiptSettings'] = value;
    await _write(data);
  }

  // --- إعدادات تنبيهات الصندوق ---
  /// تفعيل/تعطيل تنبيهات الصندوق بالكامل.
  static Future<bool> alertsEnabled() async {
    final data = await _read();
    final v = data['alertsEnabled'];
    return v is bool ? v : true;
  }

  static Future<void> setAlertsEnabled(bool value) async {
    final data = await _read();
    data['alertsEnabled'] = value;
    await _write(data);
  }

  /// التنبيه عند نفاد فئة من الفئات (وصول عددها إلى صفر).
  static Future<bool> alertOnEmptyDenom() async {
    final data = await _read();
    final v = data['alertOnEmptyDenom'];
    return v is bool ? v : true;
  }

  static Future<void> setAlertOnEmptyDenom(bool value) async {
    final data = await _read();
    data['alertOnEmptyDenom'] = value;
    await _write(data);
  }

  /// إرسال التنبيهات إلى تيليغرام (يتطلب ربط البوت).
  static Future<bool> alertViaTelegram() async {
    final data = await _read();
    final v = data['alertViaTelegram'];
    return v is bool ? v : false;
  }

  static Future<void> setAlertViaTelegram(bool value) async {
    final data = await _read();
    data['alertViaTelegram'] = value;
    await _write(data);
  }

  /// حدّ الرصيد المنخفض لعملة — 0 يعني غير مفعّل.
  static Future<double> minBalanceFor(int currencyId) async {
    final data = await _read();
    final v = data['alert_min_balance_$currencyId'];
    if (v is num) return v.toDouble();
    return 0;
  }

  static Future<void> setMinBalanceFor(int currencyId, double value) async {
    final data = await _read();
    if (value <= 0) {
      data.remove('alert_min_balance_$currencyId');
    } else {
      data['alert_min_balance_$currencyId'] = value;
    }
    await _write(data);
  }

  /// كل حدود الأرصدة المفعّلة: currencyId → الحد.
  static Future<Map<int, double>> allMinBalances() async {
    final data = await _read();
    final out = <int, double>{};
    data.forEach((k, v) {
      if (k.startsWith('alert_min_balance_') && v is num) {
        final id = int.tryParse(k.substring('alert_min_balance_'.length));
        if (id != null) out[id] = v.toDouble();
      }
    });
    return out;
  }
}
