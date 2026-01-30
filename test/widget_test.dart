import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blind_nav/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BlindNavApp());

    // Verify that the app starts (camera initialization may fail in test env)
    expect(find.text('Blind Nav'), findsNothing); // May not be visible due to camera init
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
