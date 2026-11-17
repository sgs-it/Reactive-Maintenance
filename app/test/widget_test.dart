import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmcs/main.dart';

void main() {
  testWidgets('Sign-in validates empty credentials on a mobile viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const RmcsApp());
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
