import 'dart:io';

import '../storage/device_settings.dart';

/// إشعارات اختيارية فقط؛ يفشل الطلب بصمت حتى لا يعطل العمل المحلي.
class TelegramNotifier {
  static Future<bool> isConfigured() async {
    return (await DeviceSettings.telegramBotToken()) != null &&
        (await DeviceSettings.telegramChatId()) != null;
  }

  static Future<void> officeCreated(String officeName) async {
    try {
      final token = await DeviceSettings.telegramBotToken();
      final chatId = await DeviceSettings.telegramChatId();
      if (token == null || chatId == null) return;

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final uri = Uri.https(
        'api.telegram.org',
        '/bot$token/sendMessage',
        <String, String>{
          'chat_id': chatId,
          'text': 'تم إنشاء حساب $officeName',
        },
      );
      final request = await client.getUrl(uri);
      await request.close().timeout(const Duration(seconds: 6));
      client.close(force: true);
    } catch (_) {
      // الإشعار لا يجب أن يمنع إنشاء المكتب أو الحساب.
    }
  }

  /// يرسل رسالة نصية (تنبيهات الصندوق) إلى المحادثة المرتبطة بالبوت.
  static Future<void> sendText(String text) async {
    try {
      final token = await DeviceSettings.telegramBotToken();
      final chatId = await DeviceSettings.telegramChatId();
      if (token == null || chatId == null) return;

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final uri = Uri.https(
        'api.telegram.org',
        '/bot$token/sendMessage',
        <String, String>{
          'chat_id': chatId,
          'text': text,
        },
      );
      final request = await client.getUrl(uri);
      await request.close().timeout(const Duration(seconds: 6));
      client.close(force: true);
    } catch (_) {
      // التنبيه الاختياري لا يجب أن يعطّل العمل المحلي.
    }
  }

  /// يرسل ملف النسخة الاحتياطية إلى المحادثة المرتبطة بالبوت.
  /// القيمة false تعني أن الإرسال لم يُضبط أو تعذر، من دون التأثير على النسخة المحلية.
  static Future<bool> sendBackupFile(
    File file, {
    required String caption,
  }) async {
    HttpClient? client;
    try {
      final token = await DeviceSettings.telegramBotToken();
      final chatId = await DeviceSettings.telegramChatId();
      if (token == null || chatId == null || !await file.exists()) return false;

      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(
        Uri.https('api.telegram.org', '/bot$token/sendDocument'),
      );
      final boundary = 'tima_${DateTime.now().microsecondsSinceEpoch}';
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );

      void addField(String name, String value) {
        request.write('--$boundary\r\n');
        request.write('Content-Disposition: form-data; name="$name"\r\n\r\n');
        request.write('$value\r\n');
      }

      addField('chat_id', chatId);
      addField('caption', caption);
      final safeName = file.uri.pathSegments.isEmpty
          ? 'tima_backup.dat'
          : file.uri.pathSegments.last.replaceAll('"', '');
      request.write('--$boundary\r\n');
      request.write(
        'Content-Disposition: form-data; name="document"; filename="$safeName"\r\n',
      );
      request.write('Content-Type: application/octet-stream\r\n\r\n');
      await request.addStream(file.openRead());
      request.write('\r\n--$boundary--\r\n');

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}
