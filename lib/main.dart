import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/services/app_sound.dart';
import 'core/storage/app_database.dart';
import 'core/storage/device_settings.dart';
import 'core/theme/app_theme.dart';
import 'presentation/pages/auth/login_page.dart';
import 'presentation/pages/auth/register_page.dart';
import 'presentation/pages/cashbox/add_currency_page.dart';
import 'presentation/pages/cashbox/cashbox_page.dart';
import 'presentation/pages/cashbox/currency_detail_page.dart';
import 'presentation/pages/home/home_page.dart';
import 'presentation/pages/records/records_page.dart';
import 'presentation/pages/records/pending_records_page.dart';
import 'presentation/pages/records/reconciliation_page.dart';
import 'presentation/pages/records/import_pending_page.dart';
import 'presentation/pages/reports/daily_report_page.dart';
import 'presentation/pages/settings/settings_page.dart';
import 'presentation/pages/setup/office_setup_page.dart';
import 'presentation/pages/setup/initial_setup_page.dart';
import 'presentation/pages/splash/splash_page.dart';
import 'presentation/pages/transactions/add_delivery_page.dart';
import 'presentation/pages/transactions/add_exchange_page.dart';
import 'presentation/pages/transactions/add_receive_page.dart';
import 'presentation/pages/transactions/add_sent_page.dart';

RandomAccessFile? _singleInstanceLock;

Future<bool> _acquireSingleInstanceLock() async {
  if (!Platform.isWindows) return true;
  try {
    final dir = await getApplicationSupportDirectory();
    final lock = await File(
      '${dir.path}${Platform.pathSeparator}tima.lock',
    ).open(mode: FileMode.write);
    await lock.lock(FileLock.exclusive);
    _singleInstanceLock = lock;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!await _acquireSingleInstanceLock()) return;
  // إبقاء مقبض القفل حيّاً طوال عمر التطبيق.
  if (_singleInstanceLock == null) return;
  await AppSound.load();
  runApp(TimaApp(db: AppDatabase()));
}

class TimaApp extends StatefulWidget {
  final AppDatabase db;

  const TimaApp({super.key, required this.db});

  @override
  State<TimaApp> createState() => _TimaAppState();
}

class _TimaAppState extends State<TimaApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final name = await DeviceSettings.themeModeName();
    if (!mounted) return;
    setState(() => _themeMode = _themeModeFromName(name));
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await DeviceSettings.saveThemeModeName(_themeModeName(mode));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تيما المالي',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      locale: const Locale('ar'),
      initialRoute: '/',
      onGenerateRoute: _route,
      // اتجاه الواجهة من اليمين لليسار في كل التطبيق، مع تثبيت
      // مقياس النص حتى لا تختل التخطيطات بإعدادات ويندوز.
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.2,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Route<dynamic> _route(RouteSettings settings) {
    final args = settings.arguments;
    final user = args is User ? args : null;
    final mapArgs = args is Map ? Map<String, dynamic>.from(args) : null;

    Widget page;
    switch (settings.name) {
      case '/':
        page = SplashPage(db: widget.db);
        break;
      case '/login':
        page = LoginPage(db: widget.db);
        break;
      case '/initial_setup':
        page = InitialSetupPage(db: widget.db);
        break;
      case '/register':
        page = RegisterPage(db: widget.db);
        break;
      case '/home':
        page = user == null
            ? LoginPage(db: widget.db)
            : HomePage(
                db: widget.db,
                user: user,
                themeMode: _themeMode,
                onThemeModeChanged: _changeThemeMode,
              );
        break;
      case '/add_delivery':
        page = user == null
            ? LoginPage(db: widget.db)
            : AddDeliveryPage(db: widget.db, user: user);
        break;
      case '/add_receive':
        page = user == null
            ? LoginPage(db: widget.db)
            : AddReceivePage(db: widget.db, user: user);
        break;
      case '/add_sent':
        page = user == null
            ? LoginPage(db: widget.db)
            : AddSentPage(db: widget.db, user: user);
        break;
      case '/add_exchange':
        page = user == null
            ? LoginPage(db: widget.db)
            : AddExchangePage(db: widget.db, user: user);
        break;
      case '/records':
        page = user == null
            ? LoginPage(db: widget.db)
            : RecordsPage(db: widget.db, user: user);
        break;
      case '/pending':
        page = user == null
            ? LoginPage(db: widget.db)
            : PendingRecordsPage(db: widget.db, user: user);
        break;
      case '/reconciliation': // توجيه مسار المطابقة الجديد
        page = user == null
            ? LoginPage(db: widget.db)
            : ReconciliationPage(db: widget.db, user: user);
        break;
      case '/cashbox':
        page = CashboxPage(db: widget.db);
        break;
      case '/currency_detail':
        final currency = mapArgs?['currency'];
        final boxType = (mapArgs?['boxType'] as String?) ?? 'كامل';
        final showAfter = mapArgs?['showAfterDelivery'] == true;
        if (currency is Currency) {
          page = CurrencyDetailPage(
            db: widget.db,
            currency: currency,
            boxType: boxType,
            initialShowAfterDelivery: showAfter,
          );
        } else {
          page = CashboxPage(db: widget.db);
        }
        break;
      case '/add_currency':
        page = AddCurrencyPage(db: widget.db);
        break;
      case '/daily_report':
        page = DailyReportPage(db: widget.db);
        break;
      case '/settings':
        page = user == null
            ? LoginPage(db: widget.db)
            : SettingsPage(
                db: widget.db,
                user: user,
                themeMode: _themeMode,
                onThemeModeChanged: _changeThemeMode,
              );
        break;
      case '/office_setup':
        page = user == null
            ? LoginPage(db: widget.db)
            : OfficeSetupPage(db: widget.db, user: user);
        break;
      case '/import_pending':
        page = user == null
            ? LoginPage(db: widget.db)
            : ImportPendingPage(db: widget.db, user: user);
        break;
      default:
        page = LoginPage(db: widget.db);
    }

    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  ThemeMode _themeModeFromName(String name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _themeModeName(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}
