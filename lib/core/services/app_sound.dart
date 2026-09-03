import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../storage/device_settings.dart';

/// نغمات تيما المميزة.
enum TimaSound {
  /// تنبيه الأرصدة — ثلاث نغمات صاعدة هادئة.
  alert('sounds/tima_alert.wav'),

  /// نجاح عملية — قفزة خامسة صاعدة.
  success('sounds/tima_success.wav'),

  /// خطأ أو رفض — نغمتان هابطتان.
  error('sounds/tima_error.wav');

  final String asset;
  const TimaSound(this.asset);
}

/// مشغّل الأصوات المخصّصة للتطبيق.
///
/// يحتفظ بمشغّل واحد لكل نغمة حتى لا يتداخل الصوت مع نفسه عند تكرار
/// التنبيه، ويحترم مفتاح كتم الصوت المحفوظ في إعدادات الجهاز.
class AppSound {
  AppSound._();

  static final Map<TimaSound, AudioPlayer> _players = {};
  static bool _enabled = true;
  static bool _loaded = false;

  /// هل الصوت مفعّل حالياً؟
  static bool get enabled => _enabled;

  /// يقرأ تفضيل الصوت المحفوظ. يُستدعى مرة عند إقلاع التطبيق.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _enabled = await DeviceSettings.getSoundEnabled();
    } catch (_) {
      _enabled = true;
    }
  }

  /// يفعّل الصوت أو يكتمه ويحفظ التفضيل.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      await DeviceSettings.setSoundEnabled(value);
    } catch (_) {
      // كتم الصوت تفضيل ثانوي: لا نُفشل العملية إن تعذّر الحفظ.
    }
  }

  /// يشغّل نغمة. لا يرمي استثناءً أبداً — الصوت ليس حرجاً للوظيفة.
  static Future<void> play(TimaSound sound) async {
    if (!_enabled) return;
    try {
      final player = _players.putIfAbsent(sound, () {
        final p = AudioPlayer();
        p.setReleaseMode(ReleaseMode.stop);
        return p;
      });
      await player.stop();
      await player.play(AssetSource(sound.asset), volume: 0.85);
    } catch (e) {
      // منصّات بلا مخرج صوتي، أو ملف مفقود: نتجاهل بصمت.
      debugPrint('AppSound: تعذّر تشغيل ${sound.asset} ($e)');
    }
  }

  /// يحرّر المشغّلات. يُستدعى عند إغلاق التطبيق.
  static Future<void> dispose() async {
    for (final p in _players.values) {
      try {
        await p.dispose();
      } catch (_) {
        // تجاهل: نحن في طريقنا للإغلاق على أي حال.
      }
    }
    _players.clear();
  }
}
