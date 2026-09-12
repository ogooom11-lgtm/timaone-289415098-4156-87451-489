import 'package:flutter_test/flutter_test.dart';
import 'package:tima_one/core/utils/clipboard_text.dart';

void main() {
  group('tokenizeLines', () {
    test('يفصل الأسطر والكلمات ويقصّ الترقيم من الأطراف', () {
      final lines = ClipboardText.tokenizeLines(
        'الاسم: محمد أحمد العلي\nالمبلغ:1,500 دولار\n(500\$) ل.س 25.000',
      );
      expect(lines, [
        ['الاسم', 'محمد', 'أحمد', 'العلي'],
        ['المبلغ', '1,500', 'دولار'],
        ['500\$', 'ل.س', '25.000'],
      ]);
    });

    test('الفاصلة بين رقمين تبقى جزءاً من الرقم، وبين كلمتين تفصلهما', () {
      expect(ClipboardText.tokenizeLines('محمد،أحمد 250,000 ١،٥٠٠'), [
        ['محمد', 'أحمد', '250,000', '١،٥٠٠'],
      ]);
    });

    test('يتجاهل الأسطر الفارغة', () {
      expect(ClipboardText.tokenizeLines('\n\n  \nكلمة\n\n'), [
        ['كلمة'],
      ]);
    });
  });

  group('extractNumber', () {
    const cases = <String, String?>{
      '500': '500',
      '1,500': '1500',
      '1.500': '1500',
      '12,500': '12500',
      '1.500,25': '1500.25',
      '1,500.25': '1500.25',
      '2,5': '2.5',
      '0.500': '0.5',
      '1234.500': '1234.5',
      '1.000.000': '1000000',
      '1,000,000': '1000000',
      '500\$': '500',
      '\$500': '500',
      '٥٠٠': '500',
      '١٬٥٠٠': '1500',
      '٢٫٥': '2.5',
      '١،٥٠٠': '1500',
      'المبلغ:500': '500',
      '500.': '500',
      '99.99': '99.99',
      '1500.00': '1500',
      '25.000': '25000',
      '12.345.678,90': '12345678.9',
      'محمد': null,
      '': null,
    };

    cases.forEach((input, expected) {
      test('"$input" → $expected', () {
        expect(ClipboardText.extractNumber(input), expected);
      });
    });
  });

  group('detectCurrencyCode', () {
    const known = ['USD', 'TRY', 'SYP', 'EUR'];
    const cases = <String, String?>{
      '500 دولار': 'USD',
      'بالدولار': 'USD',
      '\$500': 'USD',
      'usd': 'USD',
      'ليرة تركية': 'TRY',
      'التركي': 'TRY',
      'try': 'TRY',
      'ليرة سورية': 'SYP',
      'ل.س': 'SYP',
      '€': 'EUR',
      'ريال سعودي': 'SAR',
      'درهم': 'AED',
      // أسماء دول وكلمات مبهمة لا تُحسم كعملة
      'تركيا': null,
      'سوريا': null,
      'السعودية': null,
      'ليرة': null,
      'دينار': null,
      'ريال': null,
      'country': null,
      'محمد': null,
      '1500': null,
    };

    cases.forEach((input, expected) {
      test('"$input" → $expected', () {
        expect(
          ClipboardText.detectCurrencyCode(input, knownCodes: known),
          expected,
        );
      });
    });
  });

  group('cleanForName', () {
    test('يزيل الرموز ويطبّع المسافات', () {
      expect(ClipboardText.cleanForName('  محمد-أحمد  (العلي) '), 'محمد أحمد العلي');
    });
  });

  group('looksNumeric', () {
    test('يميّز الأرقام عن الكلمات', () {
      expect(ClipboardText.looksNumeric('1,500'), isTrue);
      expect(ClipboardText.looksNumeric('٥٠٠'), isTrue);
      expect(ClipboardText.looksNumeric('500\$'), isTrue);
      expect(ClipboardText.looksNumeric('محمد'), isFalse);
      expect(ClipboardText.looksNumeric('USD'), isFalse);
    });
  });
}
