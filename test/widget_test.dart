import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grate_app/screens/login_screen.dart';
import 'package:grate_app/theme/app_theme.dart';

void main() {
  testWidgets('login screen shows jewellery title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const LoginScreen(),
      ),
    );
    expect(find.text('JEWELLERY MANAGEMENT'), findsOneWidget);
    expect(find.text('LOGIN'), findsWidgets);
  });
}
