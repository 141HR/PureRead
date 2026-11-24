import 'package:flutter_test/flutter_test.dart';
import 'package:poc_js_provider/main.dart';

void main() {
  testWidgets('PocJsProviderApp runs QuickJS probe button cleanly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PocJsProviderApp());
    expect(find.text('PureRead PoC-2: JS Provider'), findsOneWidget);

    await tester.tap(find.text('Run QuickJS Probe'));
    await tester.pump();

    expect(find.text('QuickJS-NG OK: 42'), findsOneWidget);
  });
}
