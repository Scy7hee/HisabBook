
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab_book/main.dart';

void main() {
  testWidgets('HisabBook dashboard and drawer work',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HisabBookApp());

    // Dashboard should be visible.
    expect(find.text('Your money at a glance'), findsOneWidget);

    // Open the navigation drawer.
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();

    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Savings & Goals'), findsOneWidget);
    expect(find.text('Split Expenses'), findsOneWidget);

    // Select a section and verify the drawer closes.
    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();

    expect(find.text('This section is coming soon. '
        'We will build it step by step.'), findsOneWidget);
  });
}
