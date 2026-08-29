import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apps/main.dart';

void main() {
  testWidgets('PassManApp launches and displays login screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: PassManApp()));
    await tester.pumpAndSettle();

    expect(find.text('PassMan'), findsWidgets);
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Sign up'), findsWidgets);
  });
}
