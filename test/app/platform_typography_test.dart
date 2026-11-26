import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/app/app.dart';
import 'package:pureread/application/bookshelf/bookshelf_controller.dart';
import 'package:pureread/application/core_providers.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/platform_font_resolver.dart';
import 'package:pureread/presentation/bookshelf/bookshelf_page.dart';

void main() {
  group('platform_font_resolver', () {
    test('resolves Microsoft YaHei UI and CJK fallbacks on Windows', () {
      expect(
        resolvePlatformFontFamily(
          null,
          targetPlatform: TargetPlatform.windows,
        ),
        kWindowsPrimaryCjkFontFamily,
      );
      expect(
        resolvePlatformFontFamily(
          '',
          targetPlatform: TargetPlatform.windows,
        ),
        kWindowsPrimaryCjkFontFamily,
      );
      expect(
        resolvePlatformFontFamily(
          'system',
          targetPlatform: TargetPlatform.windows,
        ),
        kWindowsPrimaryCjkFontFamily,
      );
      expect(
        resolvePlatformFontFamily(
          'LXGW WenKai',
          targetPlatform: TargetPlatform.windows,
        ),
        'LXGW WenKai',
      );
      expect(
        resolvePlatformFontFamilyFallback(
          targetPlatform: TargetPlatform.windows,
        ),
        <String>[
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'DengXian',
          'SimHei',
        ],
      );
    });

    test('preserves system defaults and skips Windows fallbacks on Android', () {
      expect(
        resolvePlatformFontFamily(
          null,
          targetPlatform: TargetPlatform.android,
        ),
        isNull,
      );
      expect(
        resolvePlatformFontFamily(
          '',
          targetPlatform: TargetPlatform.android,
        ),
        isNull,
      );
      expect(
        resolvePlatformFontFamily(
          'system',
          targetPlatform: TargetPlatform.android,
        ),
        isNull,
      );
      expect(
        resolvePlatformFontFamily(
          'LXGW WenKai',
          targetPlatform: TargetPlatform.android,
        ),
        'LXGW WenKai',
      );
      expect(
        resolvePlatformFontFamilyFallback(
          targetPlatform: TargetPlatform.android,
        ),
        isNull,
      );
    });
  });

  group('PureReadApp platform typography', () {
    Future<void> seedSampleBook(WidgetTester tester) async {
      final bookshelfElement = tester.element(find.byType(BookshelfPage));
      final container = ProviderScope.containerOf(bookshelfElement);
      final now = DateTime.utc(2026, 11, 26);
      await container.read(bookRepositoryProvider).saveBook(
        Book(
          id: 'sample-book',
          providerType: ProviderType.localTxt,
          title: '雪中悍刀行',
          author: '烽火戏诸侯',
          totalChapters: 10,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await container.read(bookshelfControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Windows PureReadApp applies Microsoft YaHei UI and ChoiceChip inherits it',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1280, 720);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const ProviderScope(child: PureReadApp()));
        await tester.pumpAndSettle();
        await seedSampleBook(tester);

        final bookshelfContext = tester.element(find.byType(BookshelfPage));
        final labelLarge = Theme.of(bookshelfContext).textTheme.labelLarge;
        expect(labelLarge?.fontFamily, 'Microsoft YaHei UI');
        expect(
          labelLarge?.fontFamilyFallback,
          containsAllInOrder(<String>[
            'Microsoft YaHei UI',
            'Microsoft YaHei',
          ]),
        );

        final ungroupedChip = find.widgetWithText(ChoiceChip, '未分组');
        expect(ungroupedChip, findsOneWidget);

        final labelElement = tester.element(
          find.descendant(
            of: ungroupedChip,
            matching: find.text('未分组'),
          ),
        );
        final inheritedStyle = DefaultTextStyle.of(labelElement).style;
        expect(inheritedStyle.fontFamily, 'Microsoft YaHei UI');
        expect(
          inheritedStyle.fontFamilyFallback,
          containsAllInOrder(<String>[
            'Microsoft YaHei UI',
            'Microsoft YaHei',
          ]),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Android PureReadApp does not inject Microsoft YaHei UI',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const ProviderScope(child: PureReadApp()));
        await tester.pumpAndSettle();
        await seedSampleBook(tester);

        final bookshelfContext = tester.element(find.byType(BookshelfPage));
        final labelLarge = Theme.of(bookshelfContext).textTheme.labelLarge;
        expect(labelLarge?.fontFamily, isNot('Microsoft YaHei UI'));
        expect(
          labelLarge?.fontFamilyFallback,
          isNot(contains('Microsoft YaHei UI')),
        );

        final ungroupedChip = find.widgetWithText(ChoiceChip, '未分组');
        expect(ungroupedChip, findsOneWidget);

        final labelElement = tester.element(
          find.descendant(
            of: ungroupedChip,
            matching: find.text('未分组'),
          ),
        );
        final inheritedStyle = DefaultTextStyle.of(labelElement).style;
        expect(inheritedStyle.fontFamily, isNot('Microsoft YaHei UI'));
        expect(
          inheritedStyle.fontFamilyFallback,
          isNot(contains('Microsoft YaHei UI')),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });
}
