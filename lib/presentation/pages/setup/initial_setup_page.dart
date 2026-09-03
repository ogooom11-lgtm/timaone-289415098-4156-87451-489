import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';

import '../../../core/services/telegram_notifier.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/device_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../widgets/app_ui.dart';

/// يظهر مرة واحدة فقط قبل شاشة الدخول، ويعرّف المكتب وأول موظف.
class InitialSetupPage extends StatefulWidget {
  final AppDatabase db;

  const InitialSetupPage({super.key, required this.db});

  @override
  State<InitialSetupPage> createState() => _InitialSetupPageState();
}

class _InitialSetupPageState extends State<InitialSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _office = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _telegramToken = TextEditingController();
  final _telegramChat = TextEditingController();
  bool _saving = false;
  bool _showTelegram = false;

  @override
  void dispose() {
    _office.dispose();
    _username.dispose();
    _password.dispose();
    _telegramToken.dispose();
    _telegramChat.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final office = _office.text.trim();
      await DeviceSettings.saveOfficeName(office);
      await DeviceSettings.saveTelegramConfig(
        token: _telegramToken.text,
        chatId: _telegramChat.text,
      );
      try {
        await widget.db.addOffice(office);
      } catch (_) {
        // قد يكون المكتب موجوداً في قاعدة قديمة.
      }
      await widget.db.insertUser(
        UsersCompanion.insert(
          username: _username.text.trim(),
          password: _password.text,
          branch: office,
          role: const drift.Value('user'),
        ),
      );
      // لا ننتظر الشبكة، ولا نسمح لفشل تيليغرام بتعطيل الإعداد.
      TelegramNotifier.officeCreated(office);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر إنشاء الحساب: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TimaPageBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: TimaPanel(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const TimaSectionTitle(
                          icon: Icons.rocket_launch_rounded,
                          title: 'مرحباً بك في تيما المالي',
                          subtitle: 'عرّف مكتبك وأنشئ أول حساب موظف للبدء.',
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _office,
                          decoration: const InputDecoration(
                            labelText: 'اسم المكتب',
                            prefixIcon: Icon(Icons.storefront_rounded),
                          ),
                          validator: (value) =>
                              value == null || value.trim().length < 2
                              ? 'اكتب اسم المكتب'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'الحساب الأول',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _username,
                          decoration: const InputDecoration(
                            labelText: 'اسم المستخدم',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                          validator: (value) =>
                              value == null || value.trim().length < 3
                              ? 'اسم المستخدم يجب أن يكون 3 أحرف على الأقل'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'كلمة المرور',
                            prefixIcon: Icon(Icons.lock_rounded),
                          ),
                          validator: (value) =>
                              value == null || value.length < 4
                              ? 'كلمة المرور يجب أن تكون 4 رموز على الأقل'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _showTelegram,
                          onChanged: (value) =>
                              setState(() => _showTelegram = value),
                          title: const Text('ربط إشعار تيليغرام اختياري'),
                          subtitle: const Text(
                            'تصل رسالة عند إنشاء المكتب، وفشل الإرسال يُتجاهل.',
                          ),
                        ),
                        if (_showTelegram) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _telegramToken,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'رمز البوت',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _telegramChat,
                            decoration: const InputDecoration(
                              labelText: 'معرّف المحادثة',
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _saving ? null : _create,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: const Text('إنشاء المكتب والحساب'),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'بعدها ستسجّل دخولك بهذه البيانات ثم تُكمل العملات والأرصدة الافتتاحية.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
