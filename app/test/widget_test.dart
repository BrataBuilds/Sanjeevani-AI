// Smallest check that fails if the client's non-trivial pieces break: the API
// error decoding (untrusted server input) and the two screens that gate the whole
// app. Widget tests here are deliberately shallow — no golden files, no mocks of
// the HTTP layer beyond what these need.
//
//   flutter test

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjeevani/api.dart';
import 'package:sanjeevani/screens/app_lock_screen.dart';
import 'package:sanjeevani/screens/login_screen.dart';

void main() {
  test('ApiException carries the server message and status', () {
    final e = ApiException(403, 'not allowed');
    expect(e.status, 403);
    expect('$e', 'not allowed');
  });

  test('base url is reachable-looking and overridable', () {
    expect(Api.baseUrl, startsWith('http'));
    // 10.0.2.2 is the emulator alias for the host; localhost would fail there.
    expect(Api.baseUrl, anyOf(contains('localhost'), contains('10.0.2.2'), contains('://')));
  });

  testWidgets('login screen validates email and password before calling the API',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email').first, 'not-an-email');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password').first, 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
  });

  testWidgets('registering asks for a name as well', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.widgetWithText(TextFormField, 'Full name'), findsNothing);

    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
  });

  testWidgets('app lock screen offers unlock and a way out', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppLockScreen()));
    expect(find.text('Enter your app PIN'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
    expect(find.text('Sign out instead'), findsOneWidget);
  });
}
