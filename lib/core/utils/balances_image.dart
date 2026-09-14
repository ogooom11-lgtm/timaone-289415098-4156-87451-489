import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// صف واحد في صورة الأرصدة.
class BalanceImageRow {
  final String code;
  final String name;
  final double amount;
  final double secondary;
  final String secondaryLabel;
  final double impact;

  const BalanceImageRow({
    required this.code,
    required this.name,
    required this.amount,
    required this.secondary,
    required this.secondaryLabel,
    required this.impact,
  });
}

const _font = 'NotoNaskhArabic';

// لوحة ألوان أنيقة مطابقة لهوية التطبيق (أخضر + ذهبي).
const _green = Color(0xFF0E6B58);
const _greenDark = Color(0xFF07443A);
const _gold = Color(0xFFD4A64A);
const _ink = Color(0xFF17241F);
const _muted = Color(0xFF6E7B76);
const _coral = Color(0xFFCE5B49);
const _line = Color(0xFFE9EEEC);

/// يرسم بطاقة أنيقة لأرصدة الصندوق ويعيد بايتات PNG.
Future<Uint8List> renderBalancesImage({
  required List<BalanceImageRow> rows,
  required String boxTitle,
  required String modeLabel,
}) async {
  const w = 900.0;
  const pad = 44.0;
  const headerH = 176.0;
  const rowH = 104.0;
  const footerH = 76.0;
  final bodyH = rows.isEmpty ? 70.0 : rows.length * rowH;
  final h = headerH + bodyH + footerH;

  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));

  // خلفية البطاقة (مستديرة).
  final card = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, w, h),
    const Radius.circular(30),
  );
  c.save();
  c.clipRRect(card);
  c.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..color = const Color(0xFFFFFFFF),
  );

  // رأس متدرّج أخضر.
  final headerRect = Rect.fromLTWH(0, 0, w, headerH);
  c.drawRect(
    headerRect,
    Paint()
      ..shader = const LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [_green, _greenDark],
      ).createShader(headerRect),
  );
  // خط ذهبي تحت الرأس.
  c.drawRect(
    Rect.fromLTWH(0, headerH - 5, w, 5),
    Paint()..color = _gold,
  );

  final right = w - pad;
  // عنوان + نوع الصندوق + التاريخ (محاذاة لليمين).
  _rtl(c, 'أرصدة الصندوق', right: right, y: 42, size: 36,
      color: Colors.white, weight: FontWeight.w700, maxW: w - pad * 2);
  _rtl(c, boxTitle, right: right, y: 98, size: 21,
      color: _gold, weight: FontWeight.w700, maxW: w - pad * 2);
  final now = DateTime.now();
  final stamp =
      '${DateFormat('yyyy/MM/dd').format(now)}  •  ${DateFormat('hh:mm a').format(now)}';
  _rtl(c, '$modeLabel   •   $stamp', right: right, y: 132, size: 16,
      color: Colors.white.withValues(alpha: 0.82),
      weight: FontWeight.w500, maxW: w - pad * 2);

  // الصفوف.
  var y = headerH + 24.0;
  if (rows.isEmpty) {
    _center(c, 'لا توجد عملات لعرضها', w / 2, y + 8, size: 20,
        color: _muted, weight: FontWeight.w600, maxW: w);
  } else {
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (i > 0) {
        c.drawLine(
          Offset(pad, y - 12),
          Offset(w - pad, y - 12),
          Paint()
            ..color = _line
            ..strokeWidth = 1.6,
        );
      }
      final neg = r.amount < 0;
      final amtColor = neg ? _coral : _green;

      // شارة العملة.
      final badge = RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, y + 14, 86, 52),
        const Radius.circular(12),
      );
      c.drawRRect(badge, Paint()..color = _green.withValues(alpha: 0.10));
      _center(c, r.code, pad + 43, y + 28, size: 19,
          color: _green, weight: FontWeight.w800, maxW: 86);

      // الرصيد (يسار، بجانب الشارة).
      _ltr(c, _money(r.amount), left: pad + 104, y: y + 16, size: 30,
          color: amtColor, weight: FontWeight.w800);

      // الأثر المعلن (إن وُجد) تحت الرصيد.
      if (r.impact.abs() > 0.009) {
        final sign = r.impact < 0 ? '−' : '+';
        _ltr(c, '$sign${_money(r.impact.abs())} بعد التسليم',
            left: pad + 104, y: y + 58, size: 15,
            color: _muted, weight: FontWeight.w600);
      }

      // اسم العملة (يمين).
      _rtl(c, r.name, right: right, y: y + 18, size: 21,
          color: _ink, weight: FontWeight.w700, maxW: w - pad * 2 - 330);
      // الرصيد الثانوي (يمين، تحت الاسم).
      _rtl(c, '${r.secondaryLabel}: ${_money(r.secondary)}',
          right: right, y: y + 56, size: 15,
          color: _muted, weight: FontWeight.w600, maxW: w - pad * 2 - 330);

      y += rowH;
    }
  }

  // التذييل.
  c.drawLine(
    Offset(0, h - footerH),
    Offset(w, h - footerH),
    Paint()
      ..color = _line
      ..strokeWidth = 1.4,
  );
  _rtl(c, 'تيما — نظام إدارة الحوالات', right: right, y: h - footerH + 26,
      size: 16, color: _muted, weight: FontWeight.w600, maxW: w - pad * 2);
  _ltr(c, '${rows.length} عملة', left: pad, y: h - footerH + 26, size: 16,
      color: _muted, weight: FontWeight.w600);

  c.restore();

  final pic = rec.endRecording();
  final img = await pic.toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// ملخّص نصّي للأرصدة (للنسخ إلى الحافظة).
String balancesToText({
  required List<BalanceImageRow> rows,
  required String boxTitle,
  required String modeLabel,
}) {
  final b = StringBuffer();
  final stamp = DateFormat('yyyy/MM/dd  hh:mm a').format(DateTime.now());
  b.writeln('أرصدة الصندوق — $boxTitle');
  b.writeln('$modeLabel  •  $stamp');
  b.writeln('—' * 18);
  for (final r in rows) {
    b.writeln('${r.code}  ${r.name}: ${_money(r.amount)}');
  }
  return b.toString();
}

// ------- مساعدات الرسم -------

void _rtl(
  Canvas c,
  String s, {
  required double right,
  required double y,
  required double size,
  required Color color,
  required FontWeight weight,
  required double maxW,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: _font,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: 1.15,
      ),
    ),
    textDirection: TextDirection.rtl,
    maxLines: 1,
    ellipsis: '…',
  );
  tp.layout(maxWidth: maxW);
  tp.paint(c, Offset(right - tp.width, y));
}

void _ltr(
  Canvas c,
  String s, {
  required double left,
  required double y,
  required double size,
  required Color color,
  required FontWeight weight,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: _font,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: 1.15,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );
  tp.layout();
  tp.paint(c, Offset(left, y));
}

void _center(
  Canvas c,
  String s,
  double cx,
  double y, {
  required double size,
  required Color color,
  required FontWeight weight,
  required double maxW,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontFamily: _font,
        fontSize: size,
        color: color,
        fontWeight: weight,
      ),
    ),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
    maxLines: 1,
  );
  tp.layout(maxWidth: maxW);
  tp.paint(c, Offset(cx - tp.width / 2, y));
}

String _money(double v) {
  final abs = v.abs();
  final text = abs == abs.roundToDouble()
      ? abs.toStringAsFixed(0)
      : abs.toStringAsFixed(2);
  final parts = text.split('.');
  final buf = StringBuffer();
  for (var i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) buf.write(',');
    buf.write(parts[0][i]);
  }
  final out = parts.length > 1 ? '${buf.toString()}.${parts[1]}' : buf.toString();
  return v < 0 ? '−$out' : out;
}
