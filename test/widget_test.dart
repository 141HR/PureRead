import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/app/app.dart';
import 'package:pureread/presentation/shells/desktop_shell.dart';
import 'package:pureread/presentation/shells/mobile_shell.dart';

void main() {
  testWidgets('Mobile viewport renders MobileShell and switches tabs', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: PureReadApp()));
    await tester.pumpAndSettle();

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(DesktopShell), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('发现').last);
    await tester.pumpAndSettle();
    expect(find.text('发现与排行榜'), findsOneWidget);
    expect(find.text('前往书源管理'), findsOneWidget);

    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('多源聚合搜索'), findsOneWidget);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('.pureread.zip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Desktop viewport renders DesktopShell and switches navigation rails',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: PureReadApp()));
      await tester.pumpAndSettle();

      expect(find.byType(DesktopShell), findsOneWidget);
      expect(find.byType(MobileShell), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('导入本地 TXT'), findsOneWidget);
      expect(find.text('导入 EPUB'), findsOneWidget);
      expect(find.text('预览阅读器占位页'), findsNothing);

      await tester.tap(find.text('发现').last);
      await tester.pumpAndSettle();
      expect(find.text('发现与排行榜'), findsOneWidget);
      expect(find.text('前往书源管理'), findsOneWidget);

      await tester.tap(find.text('搜索').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('多源聚合搜索'), findsOneWidget);

      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('.pureread.zip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
