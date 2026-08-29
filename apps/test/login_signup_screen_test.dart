import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apps/screens/login_signup_screen.dart';

void main() {
  Widget createTestWidget({
    Function(String, String, {String? salt})? onLogin,
    Function(String, String, {String? salt})? onSignup,
    Size size = const Size(1200, 800),
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: LoginSignupScreen(
          onLogin: onLogin,
          onSignup: onSignup,
        ),
      ),
    );
  }

  group('LoginSignupScreen Widget & Validation Tests', () {
    testWidgets('renders desktop layout with visual hero banner', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('PassMan'), findsWidgets);
      expect(find.text('End-to-end encrypted'), findsOneWidget);
      expect(find.text('Synced everywhere'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Log in'), findsWidgets);
      expect(find.text('Sign up'), findsWidgets);
    });

    testWidgets('renders mobile layout on narrow viewports', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget(size: const Size(400, 800)));
      await tester.pumpAndSettle();

      expect(find.text('PassMan'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Remember me'), findsOneWidget);
    });

    testWidgets('switches between Log in and Sign up modes', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initial state is Login
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Confirm master password'), findsNothing);

      // Tap Sign up tab
      await tester.tap(find.text('Sign up').first);
      await tester.pumpAndSettle();

      expect(find.text('Create your vault'), findsOneWidget);
      expect(find.text('Confirm master password'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);

      // Tap Log in tab
      await tester.tap(find.text('Log in').first);
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Confirm master password'), findsNothing);
    });

    testWidgets('form validation displays errors for empty and invalid fields', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Submit empty login form
      await tester.tap(find.widgetWithText(InkWell, 'Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Email address is required'), findsOneWidget);
      expect(find.text('Master password is required'), findsOneWidget);

      // Enter invalid email and short password
      await tester.enterText(find.byType(TextFormField).at(0), 'invalid-email');
      await tester.enterText(find.byType(TextFormField).at(1), 'short');
      await tester.tap(find.widgetWithText(InkWell, 'Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Master password must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('sign up validation checks confirm password match', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Switch to Sign up
      await tester.tap(find.text('Sign up').first);
      await tester.pumpAndSettle();

      // Enter valid email and password but mismatched confirm password
      await tester.enterText(find.byType(TextFormField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
      await tester.enterText(find.byType(TextFormField).at(2), 'DifferentPassword!');

      await tester.tap(find.widgetWithText(InkWell, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Master passwords do not match'), findsOneWidget);

      // Fix confirm password
      await tester.enterText(find.byType(TextFormField).at(2), 'Password123!');
      await tester.tap(find.widgetWithText(InkWell, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Master passwords do not match'), findsNothing);
    });

    testWidgets('valid submit triggers callback', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? submittedEmail;
      String? submittedPassword;

      await tester.pumpWidget(createTestWidget(
        onLogin: (email, password, {salt}) {
          submittedEmail = email;
          submittedPassword = password;
        },
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'TestUser@Example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'ValidPassword123!');

      await tester.tap(find.widgetWithText(InkWell, 'Log in'));
      await tester.pumpAndSettle();

      expect(submittedEmail, equals('testuser@example.com'));
      expect(submittedPassword, equals('ValidPassword123!'));
    });
  });
}
