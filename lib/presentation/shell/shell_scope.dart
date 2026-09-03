import 'package:flutter/material.dart';

class ShellScope extends InheritedWidget {
  final String currentRoute;
  final void Function(String route, {Object? arguments}) openRoot;
  final void Function(String route, {Object? arguments}) open;
  final VoidCallback goHome;
  final VoidCallback goBack;

  const ShellScope({
    super.key,
    required this.currentRoute,
    required this.openRoot,
    required this.open,
    required this.goHome,
    required this.goBack,
    required super.child,
  });

  static ShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellScope>();
  }

  static ShellScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'ShellScope is missing from the widget tree');
    return scope!;
  }

  bool get isHome => currentRoute == '/dashboard';

  @override
  bool updateShouldNotify(ShellScope oldWidget) {
    return currentRoute != oldWidget.currentRoute;
  }
}

class TimaNav {
  static void open(
    BuildContext context,
    String route, {
    Object? arguments,
    bool replace = true,
  }) {
    final shell = ShellScope.maybeOf(context);
    if (shell != null) {
      if (replace) {
        shell.openRoot(route, arguments: arguments);
      } else {
        shell.open(route, arguments: arguments);
      }
      return;
    }
    Navigator.pushNamed(context, route, arguments: arguments);
  }

  static void back(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    final shell = ShellScope.maybeOf(context);
    if (shell != null && !shell.isHome) {
      shell.goHome();
      return;
    }
    navigator?.maybePop();
  }

  static bool canGoBack(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) return true;
    final shell = ShellScope.maybeOf(context);
    return shell != null && !shell.isHome;
  }
}
