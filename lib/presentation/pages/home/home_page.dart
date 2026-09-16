import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/telegram_notifier.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/device_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/cashbox_balance.dart';
import '../../../core/utils/currency_denoms.dart';
import '../records/transaction_row.dart';
import '../records/tx_shared.dart';
import '../../shell/shell_scope.dart';
import '../../shell/windows_sidebar.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/quick_action_rail.dart';
import '../../../core/services/app_sound.dart';
import '../cashbox/add_currency_page.dart';
import '../cashbox/cashbox_page.dart';
import '../cashbox/currency_detail_page.dart';
import '../records/import_pending_page.dart';
import '../records/pending_records_page.dart';
import '../records/reconciliation_page.dart';
import '../records/records_page.dart';
import '../reports/daily_report_page.dart';
import '../settings/settings_page.dart';
import '../setup/office_setup_page.dart';
import '../transactions/add_delivery_page.dart';
import '../transactions/add_exchange_page.dart';
import '../transactions/add_receive_page.dart';
import '../transactions/add_sent_page.dart';

/// غلاف التطبيق الرئيسي على ويندوز:
/// شريط جانبي ثابت + شريط عنوان علوي + منطقة محتوى بملاحة مستقلة.
class HomePage extends StatefulWidget {
  final AppDatabase db;
  final User user;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const HomePage({
    super.key,
    required this.db,
    required this.user,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  String _currentRoute = '/dashboard';
  String _selectedRoute = '/dashboard';
  int _refreshToken = 0;
  bool _sidebarCollapsed = false;

  // ---- التحديث التلقائي وتنبيهات الصندوق ----
  Timer? _autoTimer;
  List<_CashAlert> _activeAlerts = [];
  final Set<String> _notifiedAlertKeys = {};
  bool _checkingAlerts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _autoRefresh());
    Future.delayed(const Duration(seconds: 2), _checkAlerts);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند العودة للتطبيق: تحديث فوري + فحص التنبيهات.
    if (state == AppLifecycleState.resumed) _autoRefresh();
  }

  /// تحديث تلقائي: يفحص تنبيهات الصندوق (واللوحة تحدّث نفسها بهدوء).
  void _autoRefresh() {
    if (!mounted) return;
    _checkAlerts();
  }

  static String _fmtNum(double d) =>
      d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);

  /// يفحص الأرصدة والفئات مقابل حدود التنبيه المحفوظة بالإعدادات.
  Future<void> _checkAlerts() async {
    if (_checkingAlerts) return;
    _checkingAlerts = true;
    try {
      final enabled = await DeviceSettings.alertsEnabled();
      if (!enabled) {
        if (mounted && _activeAlerts.isNotEmpty) {
          setState(() => _activeAlerts = []);
        }
        return;
      }
      final balances = await CashboxBalanceCalculator.calculate(widget.db);
      final minBals = await DeviceSettings.allMinBalances();
      final watchEmpty = await DeviceSettings.alertOnEmptyDenom();

      final alerts = <_CashAlert>[];
      for (final s in balances.values) {
        final id = s.currency.id;
        final code = s.currency.code;
        if (s.currentTotal < 0) {
          alerts.add(
            _CashAlert(
              key: 'neg-$id',
              severe: true,
              title: 'رصيد سالب — $code',
              message:
                  'رصيد الصندوق أصبح بالسالب: ${s.currentTotal.toStringAsFixed(2)}',
            ),
          );
        }
        final min = minBals[id] ?? 0;
        if (min > 0 && s.currentTotal < min) {
          alerts.add(
            _CashAlert(
              key: 'low-$id',
              title: 'رصيد منخفض — $code',
              message:
                  'الرصيد ${s.currentTotal.toStringAsFixed(2)} نزل تحت الحد ${_fmtNum(min)}',
            ),
          );
        }
        if (watchEmpty) {
          final stock = await CurrencyDenoms.loadStock(s.currency);
          stock.forEach((d, c) {
            if (c <= 0) {
              alerts.add(
                _CashAlert(
                  key: 'denom-$id-$d',
                  title: 'فئة نافدة — $code',
                  message: 'الفئة ${_fmtNum(d)} نفدت من الصندوق',
                ),
              );
            }
          });
        }
      }

      final fresh = alerts
          .where((a) => !_notifiedAlertKeys.contains(a.key))
          .toList();
      if (fresh.isNotEmpty && mounted) {
        for (final a in fresh) {
          _notifiedAlertKeys.add(a.key);
        }
        AppSound.play(TimaSound.alert);
        final first = fresh.first;
        final more = fresh.length > 1 ? '  (+${fresh.length - 1} تنبيه آخر)' : '';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('⚠️ ${first.title}: ${first.message}$more'),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
        final viaTg = await DeviceSettings.alertViaTelegram();
        if (viaTg && await TelegramNotifier.isConfigured()) {
          final lines =
              fresh.map((a) => '• ${a.title}: ${a.message}').join('\n');
          await TelegramNotifier.sendText(
            '⚠️ تنبيه صندوق — ${widget.user.branch}\n$lines',
          );
        }
      }
      if (mounted) setState(() => _activeAlerts = alerts);
    } catch (e) {
      debugPrint('alert check error: $e');
    } finally {
      _checkingAlerts = false;
    }
  }

  Future<void> _openAlerts() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.notifications_active_rounded,
          color: AppUi.tone(dialogContext, AppColors.warning),
        ),
        title: const Text('تنبيهات الصندوق'),
        content: SizedBox(
          width: 430,
          child: _activeAlerts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('لا توجد تنبيهات حالياً — كل شيء سليم ✓'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _activeAlerts.length,
                  separatorBuilder: (_, __) => const Divider(height: 14),
                  itemBuilder: (context, i) {
                    final a = _activeAlerts[i];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          a.severe
                              ? Icons.error_rounded
                              : Icons.warning_amber_rounded,
                          size: 18,
                          color: AppUi.tone(
                            context,
                            a.severe ? AppColors.error : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                a.message,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppUi.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openRoot('/cashbox');
            },
            icon: const Icon(Icons.fact_check_rounded),
            label: const Text('فحص الصناديق'),
          ),
        ],
      ),
    );
  }

  String _rootOf(String? route) {
    switch (route) {
      case '/currency_detail':
        return '/cashbox';
      case '/home':
      case '/':
      case null:
        return '/dashboard';
      default:
        return route;
    }
  }

  void _syncRoute(String? route) {
    final next = route == null || route == '/home' ? '/dashboard' : route;
    final selected = _rootOf(next);
    if (next == _currentRoute && selected == _selectedRoute) return;
    setState(() {
      _currentRoute = next;
      _selectedRoute = selected;
    });
  }

  void _openRoot(String route, {Object? arguments}) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    _syncRoute(route);
    nav.popUntil((r) => r.isFirst);
    if (route != '/dashboard' && route != '/home') {
      nav.pushNamed(route, arguments: arguments ?? widget.user);
    }
  }

  void _open(String route, {Object? arguments}) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    _syncRoute(route);
    nav.pushNamed(route, arguments: arguments ?? widget.user);
  }

  void _goHome() => _openRoot('/dashboard');

  void _goBack() {
    final nav = _navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }
    if (_currentRoute != '/dashboard') _goHome();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.logout_rounded,
          color: AppUi.tone(dialogContext, AppColors.error),
          size: 26,
        ),
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد إنهاء الجلسة الحالية والعودة لشاشة الدخول؟'),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('خروج'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await DeviceSettings.clearRememberedUser();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/login', (_) => false);
  }

  void _refresh() => setState(() => _refreshToken++);

  void _toggleSidebar() =>
      setState(() => _sidebarCollapsed = !_sidebarCollapsed);

  void _toggleTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    widget.onThemeModeChanged(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/dashboard';
    final args = settings.arguments;
    final user = args is User ? args : widget.user;
    final mapArgs = args is Map ? Map<String, dynamic>.from(args) : null;

    late final Widget page;
    switch (name) {
      case '/dashboard':
      case '/home':
        page = DashboardPage(
          key: ValueKey('dash-$_refreshToken'),
          db: widget.db,
          user: user,
        );
        break;
      case '/add_delivery':
        page = AddDeliveryPage(db: widget.db, user: user);
        break;
      case '/add_receive':
        page = AddReceivePage(db: widget.db, user: user);
        break;
      case '/add_sent':
        page = AddSentPage(db: widget.db, user: user);
        break;
      case '/add_exchange':
        page = AddExchangePage(db: widget.db, user: user);
        break;
      case '/records':
        page = RecordsPage(
          key: ValueKey('records-$_refreshToken'),
          db: widget.db,
          user: user,
        );
        break;
      case '/pending':
        page = PendingRecordsPage(
          key: ValueKey('pending-$_refreshToken'),
          db: widget.db,
          user: user,
        );
        break;
      case '/import_pending':
        page = ImportPendingPage(db: widget.db, user: user);
        break;
      case '/cashbox':
        page = CashboxPage(key: ValueKey('cash-$_refreshToken'), db: widget.db);
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
        page = DailyReportPage(
          key: ValueKey('report-$_refreshToken'),
          db: widget.db,
        );
        break;
      case '/reconciliation':
        page = ReconciliationPage(db: widget.db, user: user);
        break;
      case '/office_setup':
        page = OfficeSetupPage(db: widget.db, user: user);
        break;
      case '/settings':
        page = SettingsPage(
          db: widget.db,
          user: user,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
        );
        break;
      default:
        page = DashboardPage(db: widget.db, user: user);
    }

    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.014),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _currentRoute != '/dashboard';
    final title = kShellTitles[_currentRoute] ?? 'تيما المالي';

    return ShellScope(
      currentRoute: _currentRoute,
      openRoot: _openRoot,
      open: _open,
      goHome: _goHome,
      goBack: _goBack,
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.f5): const _RefreshIntent(),
          const SingleActivator(LogicalKeyboardKey.keyB, control: true):
              const _ToggleSidebarIntent(),
          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
              const _GoHomeIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _RefreshIntent: CallbackAction<_RefreshIntent>(
              onInvoke: (_) {
                _refresh();
                return null;
              },
            ),
            _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
              onInvoke: (_) {
                _toggleSidebar();
                return null;
              },
            ),
            _GoHomeIntent: CallbackAction<_GoHomeIntent>(
              onInvoke: (_) {
                _goHome();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Row(
                children: [
                  WindowsSidebar(
                    user: widget.user,
                    selectedRoute: _selectedRoute,
                    onSelect: _openRoot,
                    onLogout: _logout,
                    collapsed: _sidebarCollapsed,
                    onToggleCollapse: _toggleSidebar,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _WindowsTitleBar(
                          title: title,
                          breadcrumb: canGoBack ? 'الرئيسية' : null,
                          showBack: canGoBack,
                          onBack: _goBack,
                          onHome: _goHome,
                          alertCount: _activeAlerts.length,
                          onAlerts: _openAlerts,
                          onToggleTheme: _toggleTheme,
                          onSettings: () => _openRoot('/settings'),
                        ),
                        Expanded(
                          child: PopScope(
                            canPop: false,
                            onPopInvokedWithResult: (didPop, _) {
                              if (didPop) return;
                              _goBack();
                            },
                            child: Navigator(
                              key: _navigatorKey,
                              initialRoute: '/dashboard',
                              onGenerateRoute: _onGenerateRoute,
                              observers: [
                                _ShellRouteObserver(onRoute: _syncRoute),
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
        ),
      ),
    );
  }
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

class _GoHomeIntent extends Intent {
  const _GoHomeIntent();
}

/// تنبيه صندوق واحد (رصيد سالب / رصيد منخفض / فئة نافدة).
class _CashAlert {
  final String key;
  final bool severe;
  final String title;
  final String message;

  const _CashAlert({
    required this.key,
    this.severe = false,
    required this.title,
    required this.message,
  });
}

class _ShellRouteObserver extends NavigatorObserver {
  final ValueChanged<String?> onRoute;

  _ShellRouteObserver({required this.onRoute});

  void _emit(Route<dynamic>? route) {
    final name = route?.settings.name;
    WidgetsBinding.instance.addPostFrameCallback((_) => onRoute(name));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _emit(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _emit(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _emit(newRoute);
}

/// شريط العنوان العلوي — مسار التنقل + أدوات سريعة.
class _WindowsTitleBar extends StatelessWidget {
  final String title;
  final String? breadcrumb;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final int alertCount;
  final VoidCallback onAlerts;
  final VoidCallback onToggleTheme;
  final VoidCallback onSettings;

  const _WindowsTitleBar({
    required this.title,
    required this.breadcrumb,
    required this.showBack,
    required this.onBack,
    required this.onHome,
    required this.alertCount,
    required this.onAlerts,
    required this.onToggleTheme,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppUi.isDark(context);

    return Container(
      height: AppDims.titleBarHeight,
      decoration: BoxDecoration(
        color: dark ? AppColors.darkTitleBar : AppColors.lightTitleBar,
        border: Border(bottom: BorderSide(color: AppUi.border(context))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: showBack ? 'رجوع' : 'الرئيسية',
            onPressed: showBack ? onBack : onHome,
            icon: Icon(
              showBack ? Icons.arrow_back_rounded : Icons.home_rounded,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (breadcrumb != null) ...[
                  Flexible(
                    child: InkWell(
                      onTap: onHome,
                      borderRadius: BorderRadius.circular(AppDims.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          breadcrumb!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppUi.textSecondary(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 17,
                    color: AppUi.textSecondary(context),
                  ),
                  const SizedBox(width: 2),
                ],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppUi.textPrimary(context),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: alertCount > 0
                ? 'تنبيهات الصندوق ($alertCount)'
                : 'تنبيهات الصندوق',
            onPressed: onAlerts,
            icon: Badge(
              isLabelVisible: alertCount > 0,
              label: Text('$alertCount'),
              child: Icon(
                alertCount > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
              ),
            ),
          ),
          IconButton(
            tooltip: dark ? 'الوضع الفاتح' : 'الوضع الداكن',
            onPressed: onToggleTheme,
            icon: Icon(
              dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
          ),
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// لوحة المعلومات
// ---------------------------------------------------------------------------

/// عرض المساحة المحجوزة على الحافة لشريط الإجراءات الثابت.
const double _kRailGutter = 78;

class DashboardPage extends StatefulWidget {
  final AppDatabase db;
  final User user;

  const DashboardPage({super.key, required this.db, required this.user});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TxActions<DashboardPage> {
  /// مفاتيح التنبيهات التي سبق أن رنّ لها الصوت، حتى لا يتكرّر
  /// الرنين مع كل إعادة بناء أو تحديث للوحة.
  final Set<String> _announced = {};

  // ---- البحث الشامل والتصفية ----
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _autoTimer;
  String _query = '';
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  int _visibleCount = 20;

  /// خرائط العمل لإجراءات الحركات المشتركة (نفس منطق سجل الحركات).
  Map<int, Currency> _currencies = {};
  final Set<int> _expandedIds = {};

  @override
  AppDatabase get txDb => widget.db;
  @override
  User get txUser => widget.user;
  @override
  Map<int, Currency> get txCurrencies => _currencies;
  @override
  Future<void> refreshTxData() async {
    // إعادة بناء اللوحة تعيد جلب بيانات FutureBuilder تلقائياً.
    if (mounted) setState(() {});
  }

  bool get _searchActive =>
      _query.trim().isNotEmpty ||
      _typeFilter != 'all' ||
      _statusFilter != 'all';

  @override
  void initState() {
    super.initState();
    // تحديث تلقائي هادئ كل 30 ثانية (يعيد جلب البيانات بلا فقدان
    // لحالة البحث أو موضع التمرير).
    _autoTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _visibleCount = 20;
      });
    });
  }

  void _setTypeFilter(String value) => setState(() {
        _typeFilter = value;
        _visibleCount = 20;
      });

  void _setStatusFilter(String value) => setState(() {
        _statusFilter = value;
        _visibleCount = 20;
      });

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _typeFilter = 'all';
      _statusFilter = 'all';
      _visibleCount = 20;
    });
  }

  /// يصفّي الحركات حسب النص + النوع + الحالة (الأحدث أولاً).
  List<Transaction> _applySearch(
    List<Transaction> all,
    Map<int, String> codes,
  ) {
    final q = _query.trim().toLowerCase();
    final out = <Transaction>[];
    for (final t in all) {
      if (!_matchesStatus(t)) continue;
      if (!_matchesType(t)) continue;
      if (q.isNotEmpty && !_matchesQuery(t, q, codes)) continue;
      out.add(t);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  bool _matchesStatus(Transaction t) {
    final cancelled = t.movementState == 'ملغية' || t.status == 'الغاء';
    switch (_statusFilter) {
      case 'active':
        return !cancelled;
      case 'cancelled':
        return cancelled;
      case 'delivered':
        return t.status == 'تم التسليم';
      case 'pending':
        return t.type == 'حركة تسليم' &&
            t.status == 'مضافة' &&
            t.movementState == 'مفعلة';
    }
    return true;
  }

  bool _matchesType(Transaction t) => switch (_typeFilter) {
        'delivery' => t.type == 'حركة تسليم',
        'receive' => t.type == 'حركة استلام',
        'sent' => t.type == 'حركة مرسلة',
        'exchange' => t.type == 'حركة تسوية',
        'user' => t.type == 'حركة يوزر',
        _ => true,
      };

  /// بحث شامل: الاسم، النوع، الحالة، الملاحظة، العملية، المسجّل،
  /// المبلغ، ورموز العملات.
  bool _matchesQuery(Transaction t, String q, Map<int, String> codes) {
    final code = (codes[t.currencyId] ?? '').toLowerCase();
    final target = t.targetCurrencyId == null
        ? ''
        : (codes[t.targetCurrencyId!] ?? '').toLowerCase();
    return (t.beneficiary ?? '').toLowerCase().contains(q) ||
        t.type.toLowerCase().contains(q) ||
        t.status.toLowerCase().contains(q) ||
        (t.operation ?? '').toLowerCase().contains(q) ||
        (t.note ?? '').toLowerCase().contains(q) ||
        t.createdByName.toLowerCase().contains(q) ||
        code.contains(q) ||
        target.contains(q) ||
        t.amount.toStringAsFixed(2).contains(q) ||
        t.amount.toString().contains(q);
  }

  /// نتائج البحث — نفس بطاقة سجل الحركات تماماً بنفس الأزرار والمنطق
  /// (تسليم/إلغاء/تراجع/تعديل/طباعة/سجل التعديلات) عبر TxActions.
  Widget _buildSearchResults(
    BuildContext context,
    List<Transaction> visible,
    int total,
  ) {
    return TimaPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TimaSectionTitle(
            icon: Icons.manage_search_rounded,
            title: 'نتائج البحث',
            subtitle: total == 0
                ? 'لا نتائج مطابقة'
                : 'معروض ${visible.length} من $total',
            trailing: TextButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('مسح البحث'),
            ),
          ),
          const SizedBox(height: 10),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 32,
                    color: AppUi.textSecondary(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'لا توجد حركات مطابقة لهذا البحث',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else ...[
            for (var i = 0; i < visible.length; i++) _searchRow(visible[i], i),
            if (total > visible.length) ...[
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.center,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _visibleCount += 20),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text('عرض المزيد (معروض ${visible.length} من $total)'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _searchRow(Transaction tx, int index) {
    return TxStaggered(
      index: index,
      child: TransactionRow(
        key: ValueKey('dash-tx-${tx.id}'),
        transaction: tx,
        policy: policyOfTx(tx),
        kind: kindOfTx(tx.type),
        icon: iconOfTx(kindOfTx(tx.type)),
        tint: colorOfTx(kindOfTx(tx.type)),
        currencyCode: txCurrencyCode,
        currencyName: txCurrencyName,
        formatAmount: formatTxAmount,
        formatDate: formatTxDate,
        expanded: _expandedIds.contains(tx.id),
        busy: busyTxId == tx.id,
        onToggle: () => setState(() {
          if (_expandedIds.contains(tx.id)) {
            _expandedIds.remove(tx.id);
          } else {
            _expandedIds.add(tx.id);
          }
        }),
        onEdit: () => editTx(tx),
        onCancel: () => cancelTx(tx),
        onDeliver: () => deliverTx(tx),
        onRevertCancel: () => revertCancellation(tx),
        onRevertDelivery: () => revertDelivery(tx),
        onPrint: () => printTxReceipt(tx),
        loadEdits: () => db.getEditsForTransaction(tx.id),
      ),
    );
  }

  AppDatabase get db => widget.db;
  User get user => widget.user;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير';
    if (hour < 17) return 'طاب يومك';
    return 'مساء الخير';
  }

  /// يرنّ مرة واحدة لكل مجموعة تنبيهات جديدة.
  void _announceWarnings(List<CurrencyCashSummary> warnings) {
    if (warnings.isEmpty) return;
    final key = warnings.map((w) => w.currency.code).join(',');
    if (_announced.contains(key)) return;
    _announced.add(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppSound.play(TimaSound.alert);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TimaPageBackground(
      child: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          db.getAllTransactions(),
          CashboxBalanceCalculator.calculate(db),
          db.getAllCurrencies(),
        ]),
        builder: (context, snapshot) {
          // hasData بدل connectionState: التحديث التلقائي يعيد الجلب
          // في الخلفية بلا وميض شاشة تحميل.
          if (!snapshot.hasData) {
            return const TimaLoader(message: 'جارٍ تحميل بيانات اليوم…');
          }

          final data = snapshot.data;
          final transactions = data != null && data.isNotEmpty
              ? data[0] as List<Transaction>
              : <Transaction>[];
          final cash = data != null && data.length > 1
              ? data[1] as Map<int, CurrencyCashSummary>
              : <int, CurrencyCashSummary>{};
          final currencies = data != null && data.length > 2
              ? data[2] as List<Currency>
              : <Currency>[];
          _currencies = {for (final c in currencies) c.id: c};

          final pendingDelivery = transactions
              .where(
                (t) =>
                    t.type == "حركة تسليم" &&
                    t.status == "مضافة" &&
                    t.movementState == "مفعلة",
              )
              .length;

          final today = DateTime.now();
          final todayTransactions = transactions.where((t) {
            final d = t.createdAt.toLocal();
            return d.year == today.year &&
                d.month == today.month &&
                d.day == today.day;
          }).toList();
          final todayCount = todayTransactions.length;

          final warnings = cash.values
              .where(
                (s) => s.currentTotal < 0 || s.afterDeliveryTotal < 0,
              )
              .toList();

          final recent = [...transactions]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final latest = recent.take(6).toList();

          // خرائط رموز العملات للبحث + نتائج البحث الحالية.
          final currencyCodes = <int, String>{
            for (final c in _currencies.values) c.id: c.code,
          };
          final searchResults = _searchActive
              ? _applySearch(transactions, currencyCodes)
              : const <Transaction>[];
          final visibleResults = searchResults.length > _visibleCount
              ? searchResults.sublist(0, _visibleCount)
              : searchResults;

          _announceWarnings(warnings);

          return LayoutBuilder(
            builder: (context, constraints) {
              // مساحة محجوزة لشريط الإجراءات الثابت على الحافة.
              final width = constraints.maxWidth - _kRailGutter;
              final splitLayout = width >= 1050;

              final activitySection = _RecentActivityCard(latest: latest);
              final currencySection = _BalancesCard(summaries: cash.values.toList());

              return Stack(
                children: [
                  Scrollbar(
                child: ListView(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppDims.pagePadding,
                    end: _kRailGutter,
                    top: 18,
                    bottom: 18,
                  ),
                  children: [
                    TimaContentWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TimaHeaderPanel(
                            icon: Icons.waving_hand_rounded,
                            title: '${_greeting()}، ${user.username}',
                            subtitle:
                                'مكتب ${user.branch} • ${_formatToday(today)}',
                            trailing: TimaStatusPill(
                              label: todayCount == 0
                                  ? 'لا حركات اليوم'
                                  : '$todayCount حركة اليوم',
                              color: todayCount == 0
                                  ? AppColors.neutral300
                                  : AppColors.brandGoldLight,
                              icon: Icons.event_available_rounded,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ---- البحث الشامل ----
                          _SearchPanel(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            onClear: _clearSearch,
                            typeFilter: _typeFilter,
                            onTypeFilter: _setTypeFilter,
                            statusFilter: _statusFilter,
                            onStatusFilter: _setStatusFilter,
                            active: _searchActive,
                            resultCount: searchResults.length,
                          ),
                          const SizedBox(height: 16),

                          // ---- نتائج البحث تحلّ محل اللوحة عند البحث ----
                          if (_searchActive) ...[
                            _buildSearchResults(
                              context,
                              visibleResults,
                              searchResults.length,
                            ),
                          ] else ...[
                          // ---- التنبيهات: أعلى الصفحة لأنها الأهم ----
                          if (warnings.isNotEmpty) ...[
                            TimaSectionTitle(
                              icon: Icons.warning_amber_rounded,
                              title: 'تنبيهات الأرصدة',
                              subtitle:
                                  'راجع الأرصدة قبل تنفيذ الحركات المعلّقة',
                              trailing: TimaStatusPill(
                                label: '${warnings.length}',
                                color: AppColors.warning,
                                icon: Icons.notifications_active_rounded,
                                solid: true,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...warnings.map(
                              (summary) => _WarningTile(summary: summary),
                            ),
                            const SizedBox(height: AppDims.sectionGap),
                          ],

                          // ---- المؤشرات ----
                          // امتداد ثابت للارتفاع وحدّ أدنى/أقصى للعرض: تبقى
                          // البطاقات بحجم أنيق مهما ضاقت النافذة، بدل أن
                          // تتضخّم كما يحدث مع نسبة أبعاد ثابتة.
                          GridView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 300,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  mainAxisExtent: 112,
                                ),
                            children: [
                              TimaMetricCard(
                                label: 'حركات اليوم',
                                value: '$todayCount',
                                icon: Icons.today_rounded,
                                color: AppColors.ocean,
                                caption: 'منذ منتصف الليل',
                                onTap: () => TimaNav.open(context, '/records'),
                              ),
                              TimaMetricCard(
                                label: 'تسليم معلّق',
                                value: '$pendingDelivery',
                                icon: Icons.pending_actions_rounded,
                                color: AppColors.warning,
                                caption: 'بانتظار التنفيذ',
                                onTap: () => TimaNav.open(context, '/pending'),
                              ),
                              TimaMetricCard(
                                label: 'إجمالي الحركات',
                                value: '${transactions.length}',
                                icon: Icons.receipt_long_rounded,
                                color: AppColors.success,
                                caption: 'منذ بداية التشغيل',
                                onTap: () => TimaNav.open(context, '/records'),
                              ),
                              TimaMetricCard(
                                label: 'العملات المفعّلة',
                                value: '${cash.length}',
                                icon: Icons.paid_rounded,
                                color: AppColors.violet,
                                caption: warnings.isEmpty
                                    ? 'كل الأرصدة سليمة'
                                    : '${warnings.length} تحتاج مراجعة',
                                onTap: () => TimaNav.open(context, '/cashbox'),
                              ),
                            ],
                          ),


                          // ---- النشاط والأرصدة ----
                          const SizedBox(height: AppDims.sectionGap),
                          if (splitLayout)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: activitySection),
                                  const SizedBox(width: 14),
                                  Expanded(flex: 2, child: currencySection),
                                ],
                              ),
                            )
                          else ...[
                            activitySection,
                            const SizedBox(height: 14),
                            currencySection,
                          ],
                          const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                  ),
                  Positioned.directional(
                    textDirection: Directionality.of(context),
                    end: 0, top: 0, bottom: 0,
                    child: const QuickActionRail(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static String _formatToday(DateTime date) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

// ---------------------------------------------------------------------------
// البحث الشامل والتصفية
// ---------------------------------------------------------------------------

/// مربع البحث + مصافي النوع والحالة.
class _SearchPanel extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String typeFilter;
  final ValueChanged<String> onTypeFilter;
  final String statusFilter;
  final ValueChanged<String> onStatusFilter;
  final bool active;
  final int resultCount;

  const _SearchPanel({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.typeFilter,
    required this.onTypeFilter,
    required this.statusFilter,
    required this.onStatusFilter,
    required this.active,
    required this.resultCount,
  });

  static const List<(String, String)> _types = [
    ('all', 'الكل'),
    ('delivery', 'تسليم'),
    ('receive', 'استلام'),
    ('sent', 'مرسلة'),
    ('exchange', 'تسوية'),
    ('user', 'يوزر'),
  ];

  static const List<(String, String)> _statuses = [
    ('all', 'الكل'),
    ('active', 'مفعلة'),
    ('delivered', 'تم التسليم'),
    ('pending', 'معلقة'),
    ('cancelled', 'ملغية'),
  ];

  @override
  Widget build(BuildContext context) {
    return TimaPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'بحث شامل: الاسم، المبلغ، الملاحظة، العملة، المسجّل…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDims.radiusLg),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.category_rounded,
                size: 15,
                color: AppUi.textSecondary(context),
              ),
              const Text(
                'النوع:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              for (final t in _types)
                ChoiceChip(
                  label: Text(t.$2),
                  selected: typeFilter == t.$1,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                  onSelected: (_) => onTypeFilter(t.$1),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.flag_rounded,
                size: 15,
                color: AppUi.textSecondary(context),
              ),
              const Text(
                'الحالة:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              for (final s in _statuses)
                ChoiceChip(
                  label: Text(s.$2),
                  selected: statusFilter == s.$1,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                  onSelected: (_) => onStatusFilter(s.$1),
                ),
              if (active) ...[
                const SizedBox(width: 8),
                TimaStatusPill(
                  label: '$resultCount نتيجة',
                  color: AppColors.ocean,
                  icon: Icons.filter_alt_rounded,
                  solid: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WarningTile extends StatelessWidget {
  final CurrencyCashSummary summary;

  const _WarningTile({required this.summary});

  @override
  Widget build(BuildContext context) {
    final color = AppUi.tone(context, AppColors.warning);
    final message = summary.afterDeliveryTotal < 0
        ? 'الرصيد بعد تنفيذ المعلّقات غير كافٍ (${summary.afterDeliveryTotal.toStringAsFixed(2)})'
        : 'رصيد الصندوق سالب (${summary.currentTotal.toStringAsFixed(2)})';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: AppUi.isDark(context) ? 0.10 : 0.07),
          borderRadius: BorderRadius.circular(AppDims.radius),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: color, size: 19),
            const SizedBox(width: 11),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: AppUi.textPrimary(context),
                    fontSize: 13,
                    height: 1.45,
                  ),
                  children: [
                    TextSpan(
                      text: '${summary.currency.code}: ',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: message),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => TimaNav.open(context, '/cashbox'),
              child: const Text('فحص'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  final List<Transaction> latest;

  const _RecentActivityCard({required this.latest});

  IconData _iconFor(String type) {
    if (type.contains('تسليم')) return Icons.outbox_rounded;
    if (type.contains('استلام')) return Icons.move_to_inbox_rounded;
    if (type.contains('مرسلة')) return Icons.send_rounded;
    if (type.contains('صرف') || type.contains('تسوية')) {
      return Icons.currency_exchange_rounded;
    }
    return Icons.description_rounded;
  }

  Color _colorFor(String type) {
    if (type.contains('تسليم')) return AppColors.warning;
    if (type.contains('استلام')) return AppColors.success;
    if (type.contains('مرسلة')) return AppColors.ocean;
    if (type.contains('صرف') || type.contains('تسوية')) {
      return AppColors.brandGold;
    }
    return AppColors.neutral500;
  }

  String _time(DateTime date) {
    final local = date.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return TimaPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TimaSectionTitle(
            icon: Icons.history_rounded,
            title: 'آخر الحركات',
            subtitle: 'أحدث ٦ عمليات مسجّلة',
            trailing: TextButton(
              onPressed: () => TimaNav.open(context, '/records'),
              child: const Text('عرض الكل'),
            ),
          ),
          const SizedBox(height: 6),
          if (latest.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 30,
                    color: AppUi.textSecondary(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'لا توجد حركات مسجّلة بعد',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else
            ...latest.map((t) {
              final color = AppUi.tone(context, _colorFor(t.type));
              final title = (t.beneficiary?.trim().isNotEmpty ?? false)
                  ? t.beneficiary!.trim()
                  : t.type;
              final cancelled =
                  t.movementState == 'ملغية' || t.status == 'الغاء';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppDims.radiusSm),
                      ),
                      child: Icon(_iconFor(t.type), color: color, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppUi.textPrimary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              decoration: cancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          Text(
                            '${t.type} • ${_time(t.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppUi.textSecondary(context),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.amount.toStringAsFixed(2),
                      style: TextStyle(
                        color: cancelled
                            ? AppUi.textSecondary(context)
                            : AppUi.textPrimary(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        decoration:
                            cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _BalancesCard extends StatelessWidget {
  final List<CurrencyCashSummary> summaries;

  const _BalancesCard({required this.summaries});

  @override
  Widget build(BuildContext context) {
    final sorted = [...summaries]
      ..sort((a, b) => a.currency.code.compareTo(b.currency.code));
    final visible = sorted.take(6).toList();

    return TimaPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TimaSectionTitle(
            icon: Icons.account_balance_wallet_rounded,
            title: 'أرصدة الصناديق',
            subtitle: 'الرصيد الحالي لكل عملة',
            trailing: TextButton(
              onPressed: () => TimaNav.open(context, '/cashbox'),
              child: const Text('التفاصيل'),
            ),
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Text(
                'لم تُضف أي عملة بعد',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ...visible.map((s) {
              final negative = s.currentTotal < 0;
              final color = negative
                  ? AppUi.tone(context, AppColors.error)
                  : AppUi.textPrimary(context);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5.5),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppUi.sunken(context),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppUi.border(context)),
                      ),
                      child: Text(
                        s.currency.code,
                        style: TextStyle(
                          color: AppUi.textSecondary(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppUi.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      s.currentTotal.toStringAsFixed(2),
                      style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
