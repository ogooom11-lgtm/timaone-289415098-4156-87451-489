import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/device_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';

class LoginPage extends StatefulWidget {
  final AppDatabase db;

  const LoginPage({super.key, required this.db});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _rememberMe = false;
  bool _loading = false;
  bool _obscure = true;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final user = await widget.db.authenticateUser(
      _usernameController.text,
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text('اسم المستخدم أو كلمة المرور غير صحيحة'),
              ),
            ],
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_rememberMe) {
      await DeviceSettings.rememberUser(user.id);
    } else {
      await DeviceSettings.clearRememberedUser();
    }

    if (!mounted) return;
    final setupDone = await DeviceSettings.isOfficeSetupCompleted();
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      setupDone ? '/home' : '/office_setup',
      arguments: user,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // على الشاشات العريضة: لوحة هوية جانبية + نموذج الدخول.
          final wide = constraints.maxWidth >= 900;

          if (!wide) {
            return TimaPageBackground(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _buildForm(context, compact: true),
                    ),
                  ),
                ),
              ),
            );
          }

          return Row(
            children: [
              const Expanded(flex: 5, child: _BrandPanel()),
              Expanded(
                flex: 4,
                child: TimaPageBackground(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 44,
                        vertical: 32,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: _buildForm(context, compact: false),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, {required bool compact}) {
    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact) ...[
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: AppColors.brandGradient,
                  ),
                  borderRadius: BorderRadius.circular(AppDims.radius),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandGreen.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            'تسجيل الدخول',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 5),
          Text(
            'أدخل بيانات حسابك للمتابعة إلى نظام تيما المالي.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 26),
          TextFormField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            autofocus: true,
            onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              hintText: 'مثال: ahmad',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'أدخل اسم المستخدم'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _login(),
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'إظهار' : 'إخفاء',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'أدخل كلمة المرور' : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _rememberMe,
                  onChanged: (value) =>
                      setState(() => _rememberMe = value ?? false),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                  child: Text(
                    'تذكرني على هذا الجهاز',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _loading ? null : _login,
              icon: _loading
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(_loading ? 'جارٍ التحقق…' : 'دخول'),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 14,
                color: AppUi.textSecondary(context),
              ),
              const SizedBox(width: 6),
              Text(
                'بياناتك محفوظة محلياً على هذا الجهاز',
                style: TextStyle(
                  color: AppUi.textSecondary(context),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (compact) {
      return TimaPanel(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        child: form,
      );
    }

    return form;
  }
}

/// اللوحة اليمنى — هوية التطبيق ومزاياه.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0B5A4A), Color(0xFF07443A), Color(0xFF052C26)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _SoftGlow(
              size: 340,
              color: AppColors.brandGreenLight.withValues(alpha: 0.15),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -100,
            child: _SoftGlow(
              size: 380,
              color: AppColors.brandGold.withValues(alpha: 0.10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppDims.radius),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: const Icon(
                        Icons.account_balance_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'تيما المالي',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                const Text(
                  'إدارة الصناديق\nوالحوالات اليومية',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'نظام مكتبي متكامل يعمل بالكامل على جهازك — بلا إنترنت وبلا اشتراكات.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 14,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 38),
                const _Feature(
                  icon: Icons.speed_rounded,
                  title: 'تسجيل سريع للحركات',
                  subtitle: 'تسليم، استلام، إرسال وصرف بخطوات قليلة',
                ),
                const SizedBox(height: 18),
                const _Feature(
                  icon: Icons.fact_check_rounded,
                  title: 'مطابقة دقيقة للصندوق',
                  subtitle: 'جرد الفئات الورقية ومقارنتها بالرصيد الدفتري',
                ),
                const SizedBox(height: 18),
                const _Feature(
                  icon: Icons.print_rounded,
                  title: 'إيصالات وتقارير جاهزة',
                  subtitle: 'طباعة الإيصالات وتصدير تقارير اليوم',
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 26,
            right: 48,
            child: Text(
              'الإصدار 1.0 • نسخة ويندوز',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.32),
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppDims.radiusSm),
          ),
          child: Icon(
            icon,
            color: AppColors.brandGoldLight,
            size: 18,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SoftGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _SoftGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
