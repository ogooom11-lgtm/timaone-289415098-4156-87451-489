import '../storage/device_settings.dart';

/// مواضع الشعار على الإيصال.
///
/// التسميات عربية ومطابقة لما يراه المستخدم في الإعدادات؛ الاتجاه داخل
/// الإيصال RTL، لذا «أعلى اليمين» هي بداية السطر.
enum ReceiptLogoPosition {
  topRight('أعلى اليمين'),
  topLeft('أعلى اليسار'),
  topCenter('أعلى الوسط'),
  bottom('آخر الإيصال');

  const ReceiptLogoPosition(this.label);

  /// التسمية العربية المعروضة في الواجهة.
  final String label;

  static ReceiptLogoPosition fromName(String? name) {
    for (final position in ReceiptLogoPosition.values) {
      if (position.name == name) return position;
    }
    return ReceiptLogoPosition.topRight;
  }
}

/// كل ما يمكن تخصيصه في إيصال الطباعة.
///
/// يُحفظ كاملاً في إعدادات الجهاز، ويُقرأ قبل كل عملية طباعة، فتكون
/// الخيارات المعتمدة جاهزة دون سؤال المستخدم في كل مرة.
class ReceiptSettings {
  /// عنوان الإيصال المطبوع في الترويسة.
  final String title;

  /// رسالة الختام أسفل الإيصال.
  final String footerMessage;

  /// إظهار اسم المكتب فوق العنوان.
  final bool showOfficeName;

  /// إظهار الشعار أصلاً.
  final bool showLogo;

  /// مسار صورة شعار مخصّصة — `null` يعني شعار تيما المدمج.
  final String? logoPath;

  /// موضع الشعار على الإيصال.
  final ReceiptLogoPosition logoPosition;

  /// عرض الشعار بالنقطة (pt) — الارتفاع يُحسب تلقائياً.
  final double logoWidth;

  /// إظهار رقم العملية.
  final bool showTransactionId;

  /// إظهار التاريخ والوقت.
  final bool showDateTime;

  /// إظهار جدول تفصيل الفئات (العملات).
  final bool showDenominations;

  /// إظهار سطر الحالة.
  final bool showStatus;

  /// إظهار سطر «المسلّم».
  final bool showCreatedBy;

  /// إظهار سطر الفرع/المكتب.
  final bool showBranch;

  /// إظهار رسالة الختام.
  final bool showFooter;

  /// عرض ورق الطابعة الحرارية بالمليمتر: 58 أو 80.
  final int paperWidthMm;

  /// بدء عدّاد الطباعة التلقائي بعد فتح نافذة الطباعة.
  final bool autoPrint;

  /// مدة العدّاد بالثواني قبل الطباعة التلقائية.
  final int countdownSeconds;

  /// اسم الطابعة المعتمدة — `null` يعني سؤال المستخدم/حوار النظام.
  final String? printerName;

  const ReceiptSettings({
    this.title = 'إيصال تسليم',
    this.footerMessage = 'شكراً لتعاملكم مع تيما',
    this.showOfficeName = true,
    this.showLogo = true,
    this.logoPath,
    this.logoPosition = ReceiptLogoPosition.topRight,
    this.logoWidth = 56,
    this.showTransactionId = true,
    this.showDateTime = true,
    this.showDenominations = true,
    this.showStatus = false,
    this.showCreatedBy = false,
    this.showBranch = false,
    this.showFooter = true,
    this.paperWidthMm = 80,
    this.autoPrint = true,
    this.countdownSeconds = defaultCountdownSeconds,
    this.printerName,
  });

  /// الإعدادات الافتراضية: بلا حالة ولا «مسلّم»، والعدّاد 3 ثوانٍ.
  static const ReceiptSettings defaults = ReceiptSettings();

  /// العدّاد الافتراضي بالثواني.
  static const int defaultCountdownSeconds = 3;

  static const int minCountdownSeconds = 1;
  static const int maxCountdownSeconds = 15;

  static const Object _unset = Object();

  ReceiptSettings copyWith({
    String? title,
    String? footerMessage,
    bool? showOfficeName,
    bool? showLogo,
    Object? logoPath = _unset,
    ReceiptLogoPosition? logoPosition,
    double? logoWidth,
    bool? showTransactionId,
    bool? showDateTime,
    bool? showDenominations,
    bool? showStatus,
    bool? showCreatedBy,
    bool? showBranch,
    bool? showFooter,
    int? paperWidthMm,
    bool? autoPrint,
    int? countdownSeconds,
    Object? printerName = _unset,
  }) {
    return ReceiptSettings(
      title: title ?? this.title,
      footerMessage: footerMessage ?? this.footerMessage,
      showOfficeName: showOfficeName ?? this.showOfficeName,
      showLogo: showLogo ?? this.showLogo,
      logoPath: identical(logoPath, _unset)
          ? this.logoPath
          : logoPath as String?,
      logoPosition: logoPosition ?? this.logoPosition,
      logoWidth: logoWidth ?? this.logoWidth,
      showTransactionId: showTransactionId ?? this.showTransactionId,
      showDateTime: showDateTime ?? this.showDateTime,
      showDenominations: showDenominations ?? this.showDenominations,
      showStatus: showStatus ?? this.showStatus,
      showCreatedBy: showCreatedBy ?? this.showCreatedBy,
      showBranch: showBranch ?? this.showBranch,
      showFooter: showFooter ?? this.showFooter,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      autoPrint: autoPrint ?? this.autoPrint,
      countdownSeconds: countdownSeconds == null
          ? this.countdownSeconds
          : countdownSeconds.clamp(
              minCountdownSeconds,
              maxCountdownSeconds,
            ),
      printerName: identical(printerName, _unset)
          ? this.printerName
          : printerName as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'footerMessage': footerMessage,
    'showOfficeName': showOfficeName,
    'showLogo': showLogo,
    if (logoPath != null) 'logoPath': logoPath,
    'logoPosition': logoPosition.name,
    'logoWidth': logoWidth,
    'showTransactionId': showTransactionId,
    'showDateTime': showDateTime,
    'showDenominations': showDenominations,
    'showStatus': showStatus,
    'showCreatedBy': showCreatedBy,
    'showBranch': showBranch,
    'showFooter': showFooter,
    'paperWidthMm': paperWidthMm,
    'autoPrint': autoPrint,
    'countdownSeconds': countdownSeconds,
    if (printerName != null) 'printerName': printerName,
  };

  factory ReceiptSettings.fromJson(Map<String, dynamic> json) {
    return ReceiptSettings(
      title: _text(json['title'], defaults.title),
      footerMessage: _text(json['footerMessage'], defaults.footerMessage),
      showOfficeName: _bool(json['showOfficeName'], defaults.showOfficeName),
      showLogo: _bool(json['showLogo'], defaults.showLogo),
      logoPath: _nullableText(json['logoPath']),
      logoPosition: ReceiptLogoPosition.fromName(
        _nullableText(json['logoPosition']),
      ),
      logoWidth: _double(json['logoWidth'], defaults.logoWidth),
      showTransactionId: _bool(
        json['showTransactionId'],
        defaults.showTransactionId,
      ),
      showDateTime: _bool(json['showDateTime'], defaults.showDateTime),
      showDenominations: _bool(
        json['showDenominations'],
        defaults.showDenominations,
      ),
      showStatus: _bool(json['showStatus'], defaults.showStatus),
      showCreatedBy: _bool(json['showCreatedBy'], defaults.showCreatedBy),
      showBranch: _bool(json['showBranch'], defaults.showBranch),
      showFooter: _bool(json['showFooter'], defaults.showFooter),
      paperWidthMm: _int(json['paperWidthMm'], defaults.paperWidthMm) <= 58
          ? 58
          : 80,
      autoPrint: _bool(json['autoPrint'], defaults.autoPrint),
      countdownSeconds: _int(
        json['countdownSeconds'],
        defaults.countdownSeconds,
      ).clamp(minCountdownSeconds, maxCountdownSeconds),
      printerName: _nullableText(json['printerName']),
    );
  }

  /// يقرأ الإعدادات المحفوظة، مع الطابعة المعتمدة من مفتاحها القديم.
  static Future<ReceiptSettings> load() async {
    final settings = ReceiptSettings.fromJson(
      await DeviceSettings.receiptSettings(),
    );
    final printer = await DeviceSettings.defaultPrinterName();
    if (printer == null) return settings;
    return settings.copyWith(printerName: printer);
  }

  /// يحفظ الإعدادات والطابعة المعتمدة معاً.
  Future<void> save() async {
    await DeviceSettings.saveReceiptSettings(toJson());
    await DeviceSettings.saveDefaultPrinterName(printerName);
  }

  static String _text(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static String? _nullableText(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static bool _bool(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  static int _int(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static double _double(Object? value, double fallback) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }
}
