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

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _currenciesFuture = widget.db.getAllCurrencies();
    _usersFuture = widget.db.getAllUsers();
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
          "الحركات والتعديلات، فئات الصناديق، كل العملات، وإعدادات الطباعة "
          "والإيصال وتيليغرام والمطابقات. تبقى حسابات المستخدمين فقط. لا يمكن "
          "التراجع — يُنصح بأخذ نسخة احتياطية أولاً. هل تريد الاستمرار؟",
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
      // 1) كل البيانات المالية من قاعدة البيانات.
      await widget.db.customStatement('DELETE FROM edits');
      await widget.db.customStatement('DELETE FROM transactions');
      await widget.db.customStatement('DELETE FROM currencies');
      // 2) فئات الصناديق + إعدادات الطباعة/الإيصال/تيليغرام/المطابقات.
      final data = await DeviceSettings.readAll();
      data.removeWhere((key, _) => key.startsWith('bill_count_'));
      data.remove('reconciliations');
      data.remove('reconciliationSelection');
      data.remove('telegramBotToken');
      data.remove('telegramChatId');
      data.remove('defaultPrinterName');
      data.remove('receiptSettings');
      await DeviceSettings.writeAll(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم حذف جميع البيانات — بقيت حسابات المستخدمين فقط"),
        ),
      );
      _refreshData();
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

  @override
  Widget build(BuildContext context) {
    final isAdmin = _currentUser.role == "admin";

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: timaMaybeAppBar(context, title: "الإعدادات"),
      body: TimaPageBackground(
        child: Scrollbar(
          child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDims.pagePadding,
            vertical: 16,
          ),
          children: [
            TimaContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            TimaHeaderPanel(
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
            const SizedBox(height: 12),
            // 1. Profile Card
            Card(
                            child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  leading: const Icon(Icons.person, color: AppColors.brandGold),
                  title: const Text(
                    "الملف الشخصي والفرع",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("المستخدم الحالي: ${_currentUser.username}"),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.store, size: 20),
                      title: const Text("مكتب العمل الحالي"),
                      subtitle: Text(_currentUser.branch),
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock, size: 20),
                      title: const Text("كلمة المرور"),
                      subtitle: const Text("••••••••"),
                      trailing: TextButton(
                        onPressed: _changePassword,
                        child: const Text("تغيير كلمة المرور"),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.security, size: 20),
                      title: const Text("نوع الحساب"),
                      subtitle: const Text("موظف"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Theme Preferences Card
            Card(
                            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.palette_rounded,
                          color: AppUi.accent(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "مظهر التطبيق",
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
            const SizedBox(height: 12),

            // 2b. الطباعة والإيصالات — الطابعة المعتمدة والشعار والعدّاد
            const ReceiptSettingsCard(),
            const SizedBox(height: 12),

            // 3. Currencies Card
            Card(
                            child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.currency_exchange,
                    color: AppColors.brandGold,
                  ),
                  title: const Text(
                    "إدارة العملات وأسعار الصرف الفئات",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: IconButton(
                    tooltip: "إضافة عملة جديدة",
                    onPressed: () => _addOrEditCurrency(),
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppColors.brandGreen,
                      size: 28,
                    ),
                  ),
                  children: [
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
                            String cleanName =
                                currency.name ?? "عملة غير معروفة";
                            String cleanDenoms = "100, 50, 20, 10, 5, 1";
                            if (currency.name != null &&
                                currency.name!.contains('|')) {
                              final parts = currency.name!.split('|');
                              cleanName = parts.first;
                              cleanDenoms = parts.last;
                            }
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.brandGold
                                    .withValues(alpha: 0.12),
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
            ),
            const SizedBox(height: 12),

            // 4. Users Management Card
            Card(
                            child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.supervised_user_circle,
                    color: AppColors.brandGold,
                  ),
                  title: const Text(
                    "إدارة حسابات الموظفين",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: IconButton(
                    tooltip: "تسجيل مستخدم جديد",
                    onPressed: _addNewUser,
                    icon: const Icon(
                      Icons.person_add,
                      color: AppColors.brandGreen,
                      size: 28,
                    ),
                  ),
                  children: [
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
                                    backgroundColor: AppColors.ocean.withValues(alpha: 
                                      0.12,
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
            ),
            const SizedBox(height: 12),

            // 5. Admin Only: Offices/Branches Management Card
            if (false)
              Card(
                                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ExpansionTile(
                    leading: const Icon(
                      Icons.storefront,
                      color: AppColors.brandGold,
                    ),
                    title: const Text(
                      "إدارة فروع ومكاتب العمل (Admins)",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: IconButton(
                      tooltip: "إضافة مكتب جديد في سوريا",
                      onPressed: _addNewOfficeByAdmin,
                      icon: const Icon(
                        Icons.add_business,
                        color: AppColors.brandGreen,
                        size: 28,
                      ),
                    ),
                    children: [
                      FutureBuilder<List<String>>(
                        future: widget.db.getOfficeNames(),
                        builder: (context, snapshot) {
                          final offices = snapshot.data ?? [];
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            );
                          }
                          return Column(
                            children: offices
                                .map(
                                  (officeName) => ListTile(
                                    leading: const Icon(
                                      Icons.location_city,
                                      color: AppColors.brandGreen,
                                    ),
                                    title: Text(officeName),
                                    trailing: offices.length <= 1
                                        ? null
                                        : IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: AppColors.error,
                                            ),
                                            onPressed: () =>
                                                _deleteOfficeByAdmin(
                                                  officeName,
                                                ),
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
              ),
            if (isAdmin) const SizedBox(height: 12),

            // 6. Maintenance / Danger Zone Card
            Card(
                            child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.settings_suggest,
                    color: AppColors.brandGold,
                  ),
                  title: const Text(
                    "الصيانة والنسخ الاحتياطي",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                        "يعيد التطبيق من الصفر: الحركات والفئات والعملات والإعدادات (يبقي الحسابات)",
                      ),
                      onTap: _wipeAllData,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 7. About Developer/App Info Card
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
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
