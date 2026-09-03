import 'package:flutter_test/flutter_test.dart';
import 'package:tima_one/presentation/widgets/clipboard_words_panel.dart';

void main() {
  group('ClipboardText.tokenize', () {
    test('يقسم على المسافات والأسطر ويحذف الترقيم من الأطراف', () {
      final words = ClipboardText.tokenize(
        'سلّم للأخ: محمد أحمد، مبلغ 1,500\$ (اليوم).\nشكراً',
      );
      expect(words, [
        'سلّم',
        'للأخ',
        'محمد',
        'أحمد',
        'مبلغ',
        '1,500\$',
        'اليوم',
        'شكراً',
      ]);
    });

    test('النص الفارغ يعطي قائمة فارغة', () {
      expect(ClipboardText.tokenize('   \n  '), isEmpty);
    });
  });

  group('ClipboardText.extractNumber', () {
    test('يستخرج رقماً بفواصل آلاف ورمز عملة', () {
      expect(ClipboardText.extractNumber('1,500.50\$'), '1500.5');
      expect(ClipboardText.extractNumber('\$2,000'), '2000');
    });

    test('يحوّل الأرقام العربية', () {
      expect(ClipboardText.extractNumber('١٢٠٠ دولار'), '1200');
      expect(ClipboardText.extractNumber('٣٫٥'), '3.5');
    });

    test('يعيد null بدون رقم', () {
      expect(ClipboardText.extractNumber('محمد'), isNull);
    });
  });

  group('ClipboardText.looksNumeric', () {
    test('يميّز المبالغ عن الكلمات', () {
      expect(ClipboardText.looksNumeric('1500'), isTrue);
      expect(ClipboardText.looksNumeric('1,500\$'), isTrue);
      expect(ClipboardText.looksNumeric('١٢٠٠'), isTrue);
      expect(ClipboardText.looksNumeric('محمد'), isFalse);
      expect(ClipboardText.looksNumeric('abc123def'), isFalse);
    });
  });

  group('ClipboardText.sanitizeName', () {
    test('يبقي العربية واللاتينية والأرقام فقط', () {
      expect(ClipboardText.sanitizeName('محمد-أحمد (Ali)'), 'محمد أحمد Ali');
    });
  });

  test('nonNumericPart يعيد ما تبقى بعد الرقم', () {
    expect(ClipboardText.nonNumericPart('1500 دولار'), 'دولار');
    expect(ClipboardText.nonNumericPart('\$1,500'), '\$');
  });
}
