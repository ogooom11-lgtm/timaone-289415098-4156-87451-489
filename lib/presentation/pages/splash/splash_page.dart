import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/device_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../setup/initial_setup_page.dart';

class SplashPage extends StatefulWidget {
  final AppDatabase db;

  const SplashPage({super.key, required this.db});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  String _status = 'جارٍ تجهيز النظام…';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _prepareApp();
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  Future<void> _prepareApp() async {
    _setStatus('تهيئة قاعدة البيانات…');
    try {
      await widget.db.ensureInitialData();
    } catch (e) {
      debugPrint('Error seeding database: $e');
    }

    _setStatus('التحقق من الحسابات…');
    final users = await widget.db.getAllUsers();

    try {
      final setupDone = await DeviceSettings.isOfficeSetupCompleted();
      if (!setupDone) {
        final txs = await widget.db.getAllTransactions();
        if (txs.isNotEmpty) {
          await DeviceSettings.markOfficeSetupCompleted();
        }
      }
    } catch (e) {
      debugPrint('Setup migration check failed: $e');
    }

    _setStatus('جارٍ الفتح…');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    if (users.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => InitialSetupPage(db: widget.db)),
      );
      return;
    }

    try {
      final rememberedId = await DeviceSettings.rememberedUserId();
      if (rememberedId != null) {
        final user = await widget.db.getUserById(rememberedId);
        if (user != null && mounted) {
          final setupDone = await DeviceSettings.isOfficeSetupCompleted();
          if (!mounted) return;
          Navigator.pushReplacementNamed(
            context,
            setupDone ? '/home' : '/office_setup',
            arguments: user,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('Remember-me check failed: $e');
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF0B5A4A),
              Color(0xFF07443A),
              Color(0xFF052C26),
            ],
          ),
        ),
        child: Stack(
          children: [
            // هالات ضوئية ناعمة في الخلفية.
            Positioned(
              top: -140,
              right: -100,
              child: _Glow(
                size: 380,
                color: AppColors.brandGreenLight.withValues(alpha: 0.16),
              ),
            ),
            Positioned(
              bottom: -160,
              left: -120,
              child: _Glow(
                size: 420,
                color: AppColors.brandGold.withValues(alpha: 0.10),
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.brandGold.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandGold.withValues(alpha: 0.22),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'تيما المالي',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'إدارة الصناديق والحوالات',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: 168,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.12),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.brandGoldLight,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _status,
                          key: ValueKey(_status),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 22,
              left: 0,
              right: 0,
              child: Text(
                'نسخة سطح المكتب • ويندوز',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.34),
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;

  const _Glow({required this.size, required this.color});

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
