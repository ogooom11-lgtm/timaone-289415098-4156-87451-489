import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tima_one/core/theme/app_theme.dart';

void main() {
  test('Tima themes are available', () {
    expect(AppTheme.lightTheme, isA<ThemeData>());
    expect(AppTheme.darkTheme, isA<ThemeData>());
  });
}
