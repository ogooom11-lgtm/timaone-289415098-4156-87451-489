import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/device_settings.dart';
import '../../../core/services/app_sound.dart';
import '../../../core/utils/currency_denoms.dart';
import '../../../core/services/telegram_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/receipt_settings_card.dart';

class SettingsPage extends StatefulWidget {
  final AppDatabase db;
  final User user;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.db,
    required this.user,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<List<Currency>> _currenciesFuture;
  late Future<List<User>> _usersFuture;
  late User _currentUser;

  /// القسم المختار في القائمة الجانبية.
  int _sectionIndex = 0;

  // ---- تفضيلات تنبيهات الصندوق ----
  bool _alertsEnabled = true;
  bool _alertEmptyDenom = true;
  bool _alertViaTg = false;
  final Map<int, TextEditingController> _minCtrl = {};

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _currenciesFuture = widget.db.getAllCurrencies();
    _usersFuture = widget.db.getAllUsers();
    _loadAlertPrefs();
  }

  @override
  void dispose() {
    for (final c in _minCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAlertPrefs() async {
    final enabled = await DeviceSettings.alertsEnabled();
    final empty = await DeviceSettings.alertOnEmptyDenom();
    final tg = await DeviceSettings.alertViaTelegram();
    final mins = await DeviceSettings.allMinBalances();
    if (!mounted) return;
    setState(() {
      _alertsEnabled = enabled;
      _alertEmptyDenom = empty;
      _alertViaTg = tg;
      for (final c in _minCtrl.values) {
        c.dispose();
      }
      _minCtrl.clear();
      mins.forEach((id, v) {
        _minCtrl[id] = TextEditingController(
          text: v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v',
        );
      });
    });
  }

  Future<void> _saveMinBalance(int currencyId) async {
    final raw = _minCtrl[currencyId]?.text.trim() ?? '';
    final value = double.tryParse(raw) ?? 0;
    await DeviceSettings.setMinBalanceFor(currencyId, value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value <= 0
              ? 'تم إيقاف تنبيه الحد الأدنى لهذه العملة'
              : 'تم حفظ الحد الأدنى: $value',
        ),
      ),
    );
  }

  Future<void> _refreshData() async {
    final freshUser = await widget.db.getUserById(_currentUser.id);
    setState(() {
      if (freshUser != null) {
        _currentUser = freshUser;
      }
      _currenciesFuture = widget.db.getAllCurrencies();
      _usersFuture = widget.db.getAllUsers();
    });
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تغيير كلمة المرور"),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(labelText: "كلمة المرور الجديدة"),
            validator: (v) => v == null || v.trim().length < 4
                ? "كلمة المرور يجب أن لا تقل عن 4 رموز"
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text("تغيير"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newPass = controller.text.trim();
      await widget.db.customStatement(
        'UPDATE users SET password = ? WHERE id = ?',
        [newPass, _currentUser.id],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم تغيير كلمة المرور بنجاح")),
      );
      _refreshData();
    }
  }

  // --- Currencies Management Actions (Updated with Denominations!) ---
  Future<void> _addOrEditCurrency({Currency? currency}) async {
    final isEdit = currency != null;

    String initialName = "";
    String initialDenoms = "";
    if (isEdit && currency.name != null) {
      final parts = currency.name!.split('|');
      initialName = parts.first;
      if (parts.length > 1) {
        initialDenoms = parts[1];
      }
    } else if (isEdit) {
      initialName = currency.name ?? "";
    }

    final codeController = TextEditingController(
      text: isEdit ? currency.code : "",
    );
    final nameController = TextEditingController(text: initialName);
    final rateController = TextEditingController(
      text: isEdit ? currency.rate.toString() : "1.0",
    );
    final denomsController = TextEditingController(text: initialDenoms);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? "تعديل العملة والفئات" : "إضافة عملة وفئات جديدة"),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: "رمز العملة (مثل: USD, SYP)",
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? "مطلوب" : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "اسم العملة الكامل بالعربي",
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? "مطلوب" : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: "سعر الصرف الافتراضي",
                  ),
                  validator: (v) => v == null || double.tryParse(v) == null
                      ? "أدخل رقمًا صالحًا"
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: denomsController,
                  decoration: const InputDecoration(
                    labelText: "الفئات الورقية (مفصولة بفاصلة ,)",
                    hintText: "مثال: 500, 200, 100, 50",
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: Text(isEdit ? "تعديل" : "إضافة"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final code = codeController.text.trim().toUpperCase();
      final name = nameController.text.trim();
      final rate = double.parse(rateController.text.trim());
      var denoms = denomsController.text.trim();

      if (denoms.isEmpty) {
        // افتراضيات من سجلّ العملات المركزي بدل قيم مكرّرة هنا.
        denoms = CurrencyDenoms.defaultsTextForCode(code);
      }

      final combinedNameAndDenoms = "$name|$denoms";

      if (isEdit) {
        await widget.db.updateCurrency(
          currency.id,
          CurrenciesCompanion(
            code: drift.Value(code),
            name: drift.Value(combinedNameAndDenoms),
            rate: drift.Value(rate),
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم تعديل العملة وفئاتها الورقية بنجاح"),
          ),
        );
      } else {
        await widget.db.insertCurrency(
          CurrenciesCompanion.insert(
            code: code,
            name: drift.Value(combinedNameAndDenoms),
            rate: drift.Value(rate),
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تم إضافة العملة وحفظ فئاتها الورقية")),
        );
      }
      _refreshData();
    }
  }

  Future<void> _deleteCurrency(Currency currency) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف العملة"),
        content: Text(
          "هل أنت متأكد من حذف العملة (${currency.code})؟ قد يؤدي هذا إلى أخطاء إذا كانت مرتبطة بحركات مالية.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("حذف نهائي"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.db.deleteCurrency(currency.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("تم حذف العملة")));
      _refreshData();
    }
  }

  // --- User management ---
  Future<void> _addNewUser() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final selectedOffice = _currentUser.branch;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("تسجيل مستخدم جديد"),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: "اسم المستخدم",
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "كلمة المرور"),
                    validator: (v) => v == null || v.trim().length < 4
                        ? "مطلوب 4 رموز على الأقل"
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("إلغاء"),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text("إنشاء حساب"),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await widget.db.insertUser(
        UsersCompanion.insert(
          username: usernameController.text.trim(),
          password: passwordController.text.trim(),
          branch: selectedOffice,
          role: const drift.Value('user'),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("تم تسجيل الحساب بنجاح")));
      _refreshData();
    }
  }

  Future<void> _deleteUser(User user) async {
    if (user.id == _currentUser.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("لا يمكنك حذف حسابك الحالي!")),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف حساب المستخدم"),
        content: Text("هل أنت متأكد من حذف الحساب (${user.username}) نهائيًا؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("حذف"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.db.customStatement('DELETE FROM users WHERE id = ?', [
        user.id,
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("تم حذف حساب المستخدم")));
      _refreshData();
    }
  }

  // --- Admin actions: Offices Management ---
  // الدالتان محفوظتان لإعادة تفعيل إدارة المكاتب لاحقاً.
  // ignore: unused_element
  Future<void> _addNewOfficeByAdmin() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("إضافة مكتب عمل جديد في سوريا"),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: "اسم المكتب / الفرع الجديد",
            ),
            validator: (v) => v == null || v.trim().isEmpty ? "مطلوب" : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text("إضافة المكتب"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final officeName = controller.text.trim();
      try {
        await widget.db.addOffice(officeName);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تم إضافة مكتب العمل بنجاح")),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("هذا المكتب موجود بالفعل في قاعدة البيانات!"),
          ),
        );
      }
      _refreshData();
    }
  }

  // ignore: unused_element
  Future<void> _deleteOfficeByAdmin(String officeName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف مكتب العمل"),
        content: Text(
          "هل أنت متأكد من حذف مكتب ($officeName) نهائيًا من قاعدة البيانات؟",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("حذف"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.db.deleteOffice(officeName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("تم حذف مكتب العمل")));
      _refreshData();
    }
  }

  // --- Maintenance actions: Database Reset / Backup ---
  Future<void> _resetDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("⚠️ إعادة تهيئة الحركات والأرصدة"),
        content: const Text(
          "تنبيه هام! سيحذف هذا الخيار جميع الحركات والتعديلات المسجلة، ويصفّر "
          "فئات الصناديق (مخزون الأوراق) نهائياً — مع إبقاء العملات وحسابات "
          "المستخدمين والإعدادات. هل تريد الاستمرار؟",
          style: TextStyle(color: AppColors.error),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("إعادة تهيئة كاملة"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.db.customStatement('DELETE FROM edits');
      await widget.db.customStatement('DELETE FROM transactions');
      await CurrencyDenoms.clearAllStock();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم حذف الحركات والتعديلات وتصفير فئات الصناديق"),
        ),
      );
      _refreshData();
    }
  }

  /// حذف كل البيانات وإعادة التطبيق من الصفر (يبقي حسابات المستخدمين فقط).
  Future<void> _wipeAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("🗑️ حذف البيانات بالكامل"),
        content: const Text(
          "تحذير أخير! سيحذف هذا الخيار كل شيء ويعيد التطبيق من الصفر: جميع "
          "الحركات والتعديلات، فئات الصناديق، كل العملات، كل حسابات المستخدمين "
          "(حتى حسابك)، وإعدادات الطباعة والإيصال وتيليغرام والمطابقات. سيعود "
          "التطبيق إلى شاشة الإعداد الأولى. لا يمكن التراجع — يُنصح بأخذ نسخة "
          "احتياطية أولاً. هل تريد الاستمرار؟",
          style: TextStyle(color: AppColors.error),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("حذف كل البيانات"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 1) كل البيانات من قاعدة البيانات (بما فيها المستخدمون والعملات).
      await widget.db.customStatement('DELETE FROM edits');
      await widget.db.customStatement('DELETE FROM transactions');
      await widget.db.customStatement('DELETE FROM currencies');
      await widget.db.customStatement('DELETE FROM users');
      // 2) فئات الصناديق + كل الإعدادات (طباعة/إيصال/تيليغرام/مطابقات/
      //    المكتب/المستخدم المتذكَّر) ليعود التطبيق كشاشة إعداد أولى.
      final data = await DeviceSettings.readAll();
      data.removeWhere((key, _) => key.startsWith('bill_count_'));
      data.remove('reconciliations');
      data.remove('reconciliationSelection');
      data.remove('telegramBotToken');
      data.remove('telegramChatId');
      data.remove('defaultPrinterName');
      data.remove('receiptSettings');
      data.remove('rememberedUserId');
      data.remove('officeName');
      data.remove('officeSetupCompleted');
      data.remove('officeSetupCompletedAt');
      await DeviceSettings.writeAll(data);
      if (!mounted) return;
      // العودة إلى شاشة الإعداد الأولى كأنه تثبيت جديد.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Future<void> _backupDatabase() async {
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مجلد حفظ النسخة الاحتياطية',
    );
    if (directory == null || !mounted) return;

    try {
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final database = await AppDatabase.databaseFile();
      final settings = await DeviceSettings.settingsFileForBackup();
      final separator = Platform.pathSeparator;
      final backupFiles = <File>[];
      if (await database.exists()) {
        backupFiles.add(
          await database.copy(
            '$directory${separator}tima_backup_$stamp.sqlite',
          ),
        );
      }
      if (await settings.exists()) {
        backupFiles.add(
          await settings.copy(
            '$directory${separator}tima_settings_$stamp.json',
          ),
        );
      }
      final telegramConfigured = await TelegramNotifier.isConfigured();
      final telegramSent = telegramConfigured && backupFiles.isNotEmpty
          ? (await Future.wait(
              backupFiles.map(
                (file) => TelegramNotifier.sendBackupFile(
                  file,
                  caption: 'نسخة احتياطية من تيما المالي — $stamp',
                ),
              ),
            )).every((sent) => sent)
          : false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            telegramConfigured
                ? (telegramSent
                      ? 'تم حفظ النسخة وإرسالها إلى تيليغرام'
                      : 'تم حفظ النسخة محلياً، وتعذر إرسالها إلى تيليغرام')
                : 'تم حفظ النسخة في: $directory — اربط تيليغرام لإرسالها تلقائياً',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء النسخة الاحتياطية: $e')),
      );
    }
  }

  Future<void> _configureTelegram() async {
    final token = TextEditingController(
      text: await DeviceSettings.telegramBotToken() ?? '',
    );
    final chatId = TextEditingController(
      text: await DeviceSettings.telegramChatId() ?? '',
    );
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ربط بوت تيليغرام'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: token,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'رمز البوت'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: chatId,
              decoration: const InputDecoration(labelText: 'معرّف المحادثة'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ الربط'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await DeviceSettings.saveTelegramConfig(
      token: token.text,
      chatId: chatId.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات تيليغرام')));
  }

  static const List<(IconData, String)> _sections = [
    (Icons.person_rounded, 'الحساب'),
    (Icons.palette_rounded, 'المظهر'),
    (Icons.notifications_active_rounded, 'الإشعارات والتنبيهات'),
    (Icons.receipt_long_rounded, 'الإيصال والطباعة'),
    (Icons.currency_exchange_rounded, 'العملات والفئات'),
    (Icons.supervised_user_circle_rounded, 'حسابات الموظفين'),
    (Icons.storefront_rounded, 'المكاتب والفروع'),
    (Icons.settings_backup_restore_rounded, 'البيانات والنسخ'),
    (Icons.info_rounded, 'حول التطبيق'),
  ];

  @override
  Widget build(BuildContext context) {
    final isAdmin = _currentUser.role == "admin";

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(context, title: "الإعدادات"),
      body: TimaPageBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;

            final header = Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.pagePadding,
                16,
                AppDims.pagePadding,
                0,
              ),
              child: TimaContentWidth(
                child: TimaHeaderPanel(
                  icon: Icons.settings_suggest_rounded,
                  title: "إعدادات تيما",
                  subtitle:
                      "المستخدم: ${_currentUser.username} - الفرع: ${_currentUser.branch}",
                  trailing: TimaStatusPill(
                    label: isAdmin ? "مدير" : "مستخدم",
                    color: isAdmin ? AppColors.brandGold : AppColors.ocean,
                    icon: isAdmin
                        ? Icons.admin_panel_settings_rounded
                        : Icons.person_rounded,
                  ),
                ),
              ),
            );

            final content = Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: TimaContentWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _sectionBody(context),
                    ),
                  ),
                ),
              ),
            );

            if (!wide) {
              return Column(
                children: [
                  header,
                  _navHorizontal(context),
                  content,
                ],
              );
            }

            return Column(
              children: [
                header,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 248,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: ListView(
                            padding: const EdgeInsets.only(bottom: 16),
                            children: [
                              for (var i = 0; i < _sections.length; i++)
                                _navItem(context, i),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(width: 1, color: AppUi.border(context)),
                      content,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---- قائمة الأقسام ----

  Widget _navItem(BuildContext context, int i) {
    final selected = i == _sectionIndex;
    final (icon, label) = _sections[i];
    final accent = AppUi.accent(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDims.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
          onTap: () => setState(() => _sectionIndex = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? accent : AppUi.textSecondary(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? accent : AppUi.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navHorizontal(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDims.pagePadding,
        vertical: 10,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _sections.length; i++) ...[
            ChoiceChip(
              avatar: Icon(_sections[i].$1, size: 16),
              label: Text(_sections[i].$2),
              visualDensity: VisualDensity.compact,
              selected: i == _sectionIndex,
              onSelected: (_) => setState(() => _sectionIndex = i),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  // ---- أجسام الأقسام ----

  List<Widget> _sectionBody(BuildContext context) {
    switch (_sectionIndex) {
      case 1:
        return _appearanceSection(context);
      case 2:
        return _alertsSection(context);
      case 3:
        return const [SizedBox(height: 4), ReceiptSettingsCard()];
      case 4:
        return _currenciesSection(context);
      case 5:
        return _usersSection(context);
      case 6:
        return _officesSection(context);
      case 7:
        return _dataSection(context);
      case 8:
        return _aboutSection(context);
      default:
        return _accountSection(context);
    }
  }

  Widget _sectionHeader(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppUi.accent(context)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: AppUi.textSecondary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _accountSection(BuildContext context) {
    return [
      _sectionHeader(context, Icons.person_rounded, 'الحساب', 'بياناتك وكلمة المرور'),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_rounded, size: 20),
              title: const Text("اسم المستخدم"),
              subtitle: Text(_currentUser.username),
            ),
            ListTile(
              leading: const Icon(Icons.store, size: 20),
              title: const Text("مكتب العمل الحالي"),
              subtitle: Text(_currentUser.branch),
            ),
            ListTile(
              leading: const Icon(Icons.lock, size: 20),
              title: const Text("كلمة المرور"),
              subtitle: const Text("••••••••"),
              trailing: FilledButton.tonal(
                onPressed: _changePassword,
                child: const Text("تغيير كلمة المرور"),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.security, size: 20),
              title: const Text("نوع الحساب"),
              subtitle: Text(
                _currentUser.role == "admin" ? "مدير" : "موظف",
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _appearanceSection(BuildContext context) {
    return [
      _sectionHeader(context, Icons.palette_rounded, 'المظهر', 'السمة والأصوات'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "سمة التطبيق",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text("النظام"),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode),
                      label: Text("فاتح"),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode),
                      label: Text("داكن"),
                    ),
                  ],
                  selected: {widget.themeMode},
                  onSelectionChanged: (value) {
                    widget.onThemeModeChanged(value.first);
                  },
                ),
              ),
              const Divider(height: 26),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: AppSound.enabled,
                onChanged: (v) async {
                  await AppSound.setEnabled(v);
                  if (v) AppSound.play(TimaSound.success);
                  if (context.mounted) setState(() {});
                },
                secondary: Icon(
                  AppSound.enabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: AppUi.accent(context),
                ),
                title: const Text(
                  'أصوات التطبيق',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'نغمة تنبيه عند ظهور تحذير الأرصدة، ونغمات النجاح والخطأ',
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _alertsSection(BuildContext context) {
    return [
      _sectionHeader(
        context,
        Icons.notifications_active_rounded,
        'الإشعارات والتنبيهات',
        'تنبيهات الصندوق: الرصيد المنخفض ونفاد الفئات',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _alertsEnabled,
                onChanged: (v) async {
                  await DeviceSettings.setAlertsEnabled(v);
                  if (mounted) setState(() => _alertsEnabled = v);
                },
                secondary: Icon(
                  _alertsEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  color: AppUi.accent(context),
                ),
                title: const Text(
                  'تفعيل تنبيهات الصندوق',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'فحص تلقائي كل 30 ثانية مع إشعار صوتي ورسالة وجرس في الأعلى',
                ),
              ),
              const Divider(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _alertEmptyDenom,
                onChanged: _alertsEnabled
                    ? (v) async {
                        await DeviceSettings.setAlertOnEmptyDenom(v);
                        if (mounted) setState(() => _alertEmptyDenom = v);
                      }
                    : null,
                secondary: const Icon(
                  Icons.money_off_rounded,
                  color: AppColors.warning,
                ),
                title: const Text(
                  'تنبيه عند نفاد فئة',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'يذكّرك عندما تصل كمية فئة من الفئات إلى صفر في أي صندوق',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _alertViaTg,
                onChanged: _alertsEnabled
                    ? (v) async {
                        await DeviceSettings.setAlertViaTelegram(v);
                        if (mounted) setState(() => _alertViaTg = v);
                        if (v &&
                            !await TelegramNotifier.isConfigured() &&
                            mounted) {
                          _configureTelegram();
                        }
                      }
                    : null,
                secondary: const Icon(
                  Icons.send_rounded,
                  color: AppColors.info,
                ),
                title: const Text(
                  'إرسال التنبيهات إلى تيليغرام',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'يرسل التنبيه إلى البوت المرتبط — يتطلب ربط تيليغرام',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      _sectionHeader(
        context,
        Icons.trending_down_rounded,
        'حد الرصيد الأدنى',
        'ينبّهك عندما ينزل الرصيد تحت الحد لكل عملة — 0 يعني الإيقاف',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<List<Currency>>(
            future: _currenciesFuture,
            builder: (context, snapshot) {
              final currencies = snapshot.data ?? [];
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                );
              }
              if (currencies.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text("لا يوجد عملات مسجلة"),
                );
              }
              return Column(
                children: currencies.map((c) {
                  final ctrl = _minCtrl.putIfAbsent(
                    c.id,
                    () => TextEditingController(),
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.brandGold.withValues(
                            alpha: 0.12,
                          ),
                          child: Text(
                            c.code,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'الحد الأدنى ${c.code}',
                              hintText: '0',
                              helperText: 'اتركه 0 للإيقاف',
                            ),
                            onSubmitted: (_) => _saveMinBalance(c.id),
                          ),
                        ),
                        IconButton(
                          tooltip: 'حفظ الحد',
                          onPressed: () => _saveMinBalance(c.id),
                          icon: const Icon(
                            Icons.save_rounded,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ),
    ];
  }

  List<Widget> _currenciesSection(BuildContext context) {
    return [
      _sectionHeader(
        context,
        Icons.currency_exchange_rounded,
        'العملات والفئات',
        'إضافة وتعديل وحذف العملات وفئاتها الورقية',
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(
                Icons.add_circle,
                color: AppColors.brandGreen,
              ),
              title: const Text(
                "إضافة عملة جديدة",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text("الرمز، الاسم، سعر الصرف، الفئات الورقية"),
              onTap: () => _addOrEditCurrency(),
            ),
            const Divider(height: 1),
            FutureBuilder<List<Currency>>(
              future: _currenciesFuture,
              builder: (context, snapshot) {
                final currencies = snapshot.data ?? [];
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  );
                }
                if (currencies.isEmpty) {
                  return const ListTile(
                    title: Text("لا يوجد عملات مسجلة"),
                  );
                }
                return Column(
                  children: currencies.map((currency) {
                    String cleanName = currency.name ?? "عملة غير معروفة";
                    String cleanDenoms = "100, 50, 20, 10, 5, 1";
                    if (currency.name != null &&
                        currency.name!.contains('|')) {
                      final parts = currency.name!.split('|');
                      cleanName = parts.first;
                      cleanDenoms = parts.last;
                    }
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.brandGold.withValues(
                          alpha: 0.12,
                        ),
                        child: Text(
                          currency.code,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      title: Text(cleanName),
                      subtitle: Text(
                        "صرف: ${currency.rate} • الفئات: $cleanDenoms",
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: AppColors.ocean,
                            ),
                            onPressed: () =>
                                _addOrEditCurrency(currency: currency),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: AppColors.error,
                            ),
                            onPressed: () => _deleteCurrency(currency),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _usersSection(BuildContext context) {
    return [
      _sectionHeader(
        context,
        Icons.supervised_user_circle_rounded,
        'حسابات الموظفين',
        'تسجيل حسابات جديدة أو حذفها',
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(
                Icons.person_add,
                color: AppColors.brandGreen,
              ),
              title: const Text(
                "تسجيل مستخدم جديد",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text("يُنشأ الحساب ضمن مكتبك الحالي"),
              onTap: _addNewUser,
            ),
            const Divider(height: 1),
            FutureBuilder<List<User>>(
              future: _usersFuture,
              builder: (context, snapshot) {
                final users = snapshot.data ?? [];
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  );
                }
                return Column(
                  children: users
                      .map(
                        (usr) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.ocean.withValues(
                              alpha: 0.12,
                            ),
                            child: const Icon(
                              Icons.person,
                              color: AppColors.ocean,
                            ),
                          ),
                          title: Text(usr.username),
                          subtitle: Text("المكتب: ${usr.branch}"),
                          trailing: usr.id == _currentUser.id
                              ? const Chip(label: Text("أنت"))
                              : IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: AppColors.error,
                                  ),
                                  onPressed: () => _deleteUser(usr),
                                ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _officesSection(BuildContext context) {
    return [
      _sectionHeader(
        context,
        Icons.storefront_rounded,
        'المكاتب والفروع',
        'إضافة وحذف مكاتب العمل',
      ),
      // إدارة المكاتب معطّلة حالياً بقرار سابق — دوالها محفوظة في الأعلى.
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'إدارة المكاتب معطّلة حالياً.',
            style: TextStyle(color: AppUi.textSecondary(context)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _dataSection(BuildContext context) {
    return [
      _sectionHeader(
        context,
        Icons.settings_backup_restore_rounded,
        'البيانات والنسخ',
        'نسخ احتياطي وتيليغرام وصيانة',
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(
                Icons.backup,
                color: AppColors.brandGreen,
              ),
              title: const Text("إنشاء نسخة احتياطية"),
              subtitle: const Text(
                "حفظ نسخة أمان من قاعدة البيانات محليًا",
              ),
              onTap: _backupDatabase,
            ),
            ListTile(
              leading: const Icon(
                Icons.send_rounded,
                color: AppColors.info,
              ),
              title: const Text('ربط بوت تيليغرام للنسخ الاحتياطي'),
              subtitle: const Text(
                'يرسل النسخة تلقائياً إلى البوت عند حفظها',
              ),
              onTap: _configureTelegram,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.delete_forever,
                color: AppColors.error,
              ),
              title: const Text("إعادة تهيئة الحركات والأرصدة"),
              subtitle: const Text(
                "حذف الحركات والتعديلات وتصفير فئات الصناديق (يبقي العملات والحسابات)",
              ),
              onTap: _resetDatabase,
            ),
            ListTile(
              leading: const Icon(
                Icons.settings_backup_restore,
                color: AppColors.error,
              ),
              title: const Text("حذف البيانات بالكامل"),
              subtitle: const Text(
                "يعيد التطبيق من الصفر: الحركات والفئات والعملات والحسابات وكل الإعدادات",
              ),
              onTap: _wipeAllData,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _aboutSection(BuildContext context) {
    return [
      _sectionHeader(context, Icons.info_rounded, 'حول التطبيق', 'معلومات النسخة'),
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                "تطبيق تيما المالي v1.0.0",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                "نظام محاسبي ذكي لإدارة العملات، الصناديق، والحركات المالية المتقدمة محليًا بشكل تفاعلي وآمن في سوريا.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
