import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poc_txt_pagination/main.dart';

void main() {
  testWidgets('ReaderPocScreen renders, turns pages, and toggles 1/2 columns & font size',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const PureReadPaginationPocApp());
    await tester.pumpAndSettle();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.textContaining('cols=1'), findsOneWidget);

    // Increase font size
    await tester.tap(find.byIcon(Icons.text_increase));
    await tester.pumpAndSettle();

    // Toggle to two-column mode
    await tester.tap(find.byIcon(Icons.article));
    await tester.pumpAndSettle();
    expect(find.textContaining('cols=2'), findsOneWidget);

    // Turn page forward if multi-page
    final nextButton = find.widgetWithText(TextButton, 'Next');
    final nextWidget = tester.widget<TextButton>(nextButton);
    if (nextWidget.onPressed != null) {
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('offset=0'), findsNothing);
    }
  });
}
