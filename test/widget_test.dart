import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grate_app/main.dart';

void main() {
  testWidgets('login screen is the starting screen', (WidgetTester tester) async {
    await tester.pumpWidget(const JewelleryApp());

    expect(find.widgetWithText(ElevatedButton, 'LOGIN'), findsOneWidget);
    expect(find.text('JEWELLERY MANAGEMENT'), findsOneWidget);
  });
}
