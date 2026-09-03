/// سجلّ العملات المعتمدة في تيما وفئاتها الورقية المتداولة.
///
/// هذا المصدر الوحيد للحقيقة: صفحة إعداد المكتب وصفحة إضافة عملة
/// وقيم `CurrencyDenoms.defaultsForCode` كلها تقرأ من هنا، حتى لا
/// تتفرّق قوائم الفئات في أنحاء التطبيق وتتناقض.
library;

/// تعريف عملة جاهزة مع فئاتها الورقية.
class CurrencySpec {
  /// رمز الأيزو، مثل `USD`.
  final String code;

  /// الاسم العربي المعروض، مثل `دولار أمريكي`.
  final String name;

  /// رمز العملة المختصر للعرض، مثل `\$` أو `ل.س`.
  final String symbol;

  /// الفئات الورقية المتداولة، مرتّبة تنازلياً.
  final List<double> denoms;

  const CurrencySpec({
    required this.code,
    required this.name,
    required this.symbol,
    required this.denoms,
  });

  /// الفئات كنص مفصول بفواصل — الصيغة المخزّنة في قاعدة البيانات.
  String get denomsText => denoms.map(formatDenom).join(', ');

  /// تنسيق فئة واحدة: يحذف الكسر العشري إن كان الرقم صحيحاً.
  static String formatDenom(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

/// كل العملات المدعومة افتراضياً في تيما.
///
/// الترتيب هو ترتيب العرض في واجهة الإعداد.
const List<CurrencySpec> kCurrencyCatalog = [
  CurrencySpec(
    code: 'USD',
    name: 'دولار أمريكي',
    symbol: r'$',
    denoms: [100, 50, 20, 10, 5, 2, 1],
  ),
  CurrencySpec(
    code: 'TRY',
    name: 'ليرة تركية',
    symbol: '₺',
    denoms: [200, 100, 50, 20, 10, 5],
  ),
  // ملاحظة: الفئات أدناه هي إصدار الليرة السورية الجديد بعد حذف صفرين
  // (تداول ابتداءً من 1 كانون الثاني 2026). الإصدار القديم
  // (5000/2000/1000…) لم يعد قانونياً منذ تموز 2026.
  CurrencySpec(
    code: 'SYP',
    name: 'ليرة سورية',
    symbol: 'ل.س',
    denoms: [500, 200, 100, 50, 25, 10, 5],
  ),
  CurrencySpec(
    code: 'EUR',
    name: 'يورو',
    symbol: '€',
    denoms: [500, 200, 100, 50, 20, 10, 5],
  ),
  CurrencySpec(
    code: 'SAR',
    name: 'ريال سعودي',
    symbol: 'ر.س',
    denoms: [500, 200, 100, 50, 10, 5, 1],
  ),
  CurrencySpec(
    code: 'JOD',
    name: 'دينار أردني',
    symbol: 'د.أ',
    denoms: [50, 20, 10, 5, 1],
  ),
  CurrencySpec(
    code: 'QAR',
    name: 'ريال قطري',
    symbol: 'ر.ق',
    denoms: [500, 200, 100, 50, 10, 5, 1],
  ),
  CurrencySpec(
    code: 'AED',
    name: 'درهم إماراتي',
    symbol: 'د.إ',
    denoms: [1000, 500, 200, 100, 50, 20, 10, 5],
  ),
  CurrencySpec(
    code: 'KWD',
    name: 'دينار كويتي',
    symbol: 'د.ك',
    denoms: [20, 10, 5, 1, 0.5, 0.25],
  ),
  CurrencySpec(
    code: 'GBP',
    name: 'جنيه إسترليني',
    symbol: '£',
    denoms: [50, 20, 10, 5],
  ),
];

/// عملات إضافية معروفة لا تظهر ضمن الافتراضيات، لكن يُقترح لها
/// اسم وفئات تلقائياً إن كتب المستخدم رمزها في صفحة إضافة عملة.
const List<CurrencySpec> kExtraKnownCurrencies = [
  CurrencySpec(
    code: 'IQD',
    name: 'دينار عراقي',
    symbol: 'د.ع',
    denoms: [50000, 25000, 10000, 5000, 1000, 500, 250],
  ),
  CurrencySpec(
    code: 'EGP',
    name: 'جنيه مصري',
    symbol: 'ج.م',
    denoms: [200, 100, 50, 20, 10, 5],
  ),
  CurrencySpec(
    code: 'LBP',
    name: 'ليرة لبنانية',
    symbol: 'ل.ل',
    denoms: [100000, 50000, 20000, 10000, 5000, 1000],
  ),
  CurrencySpec(
    code: 'BHD',
    name: 'دينار بحريني',
    symbol: 'د.ب',
    denoms: [20, 10, 5, 1, 0.5],
  ),
  CurrencySpec(
    code: 'OMR',
    name: 'ريال عماني',
    symbol: 'ر.ع',
    denoms: [50, 20, 10, 5, 1, 0.5, 0.1],
  ),
];

/// يبحث عن عملة بالرمز ضمن الافتراضية ثم الإضافية. يعيد `null` إن لم تُعرف.
CurrencySpec? currencySpecForCode(String code) {
  final upper = code.trim().toUpperCase();
  if (upper.isEmpty) return null;
  for (final spec in kCurrencyCatalog) {
    if (spec.code == upper) return spec;
  }
  for (final spec in kExtraKnownCurrencies) {
    if (spec.code == upper) return spec;
  }
  return null;
}

/// فئات شائعة تُقترح كنقطة بداية لعملة غير معروفة.
const List<double> kGenericDenoms = [500, 200, 100, 50, 20, 10, 5, 1];
