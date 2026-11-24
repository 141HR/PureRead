import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/sanitizer/sanitizer.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24);

  ReplaceRule makeRule({
    required String id,
    required String pattern,
    String replacement = '',
    bool isRegex = true,
    RuleScopeType scopeType = RuleScopeType.global,
    String? scopeTargetId,
    bool enabled = true,
    int sortOrder = 0,
  }) {
    return ReplaceRule(
      id: id,
      name: id,
      pattern: pattern,
      replacement: replacement,
      isRegex: isRegex,
      scopeType: scopeType,
      scopeTargetId: scopeTargetId,
      enabled: enabled,
      sortOrder: sortOrder,
      updatedAt: now,
    );
  }

  group('ContentSanitizerImpl', () {
    test('normalizes CRLF, trims paragraph spaces, and collapses excessive blank lines without inserting indents', () async {
      final sanitizer = ContentSanitizerImpl();
      const raw =
          '\r\n\r\n  　　第一段正文，包含标点。   \r\n'
          '\t  \r\n\r\n\r\n\r\n'
          '　　第二段内容。\t \r\n'
          '  第三段紧邻。\r\n\r\n  \r\n';

      final result = await sanitizer.sanitize(
        raw,
        const SanitizeContext(
          bookId: 'book-1',
          chapterTitle: '第1章',
        ),
      );

      expect(result, equals('第一段正文，包含标点。\n\n第二段内容。\n第三段紧邻。'));
      expect(result.contains('\r'), isFalse);
      expect(result.startsWith('　'), isFalse);
      expect(result.startsWith(' '), isFalse);
    });

    test('applies global -> source -> book rules in sortOrder and filters disabled or out-of-scope rules', () async {
      final rules = <ReplaceRule>[
        // Book rule with lower sortOrder (0) must still run AFTER global (10) & source (5)
        makeRule(
          id: 'book-tag',
          pattern: 'STAGE2',
          replacement: 'CLEAN',
          isRegex: false,
          scopeType: RuleScopeType.book,
          scopeTargetId: 'book-1',
          sortOrder: 0,
        ),
        // Other book rule must be ignored
        makeRule(
          id: 'other-book',
          pattern: 'CLEAN',
          replacement: 'BROKEN',
          isRegex: false,
          scopeType: RuleScopeType.book,
          scopeTargetId: 'book-2',
          sortOrder: 0,
        ),
        // Disabled rule must be ignored
        makeRule(
          id: 'disabled-global',
          pattern: '正文',
          replacement: 'DISABLED',
          isRegex: false,
          scopeType: RuleScopeType.global,
          enabled: false,
          sortOrder: 0,
        ),
        // Source rule transforms STAGE1 -> STAGE2
        makeRule(
          id: 'source-step',
          pattern: 'STAGE1',
          replacement: 'STAGE2',
          isRegex: false,
          scopeType: RuleScopeType.source,
          scopeTargetId: 'src-1',
          sortOrder: 5,
        ),
        // Other source rule must be ignored
        makeRule(
          id: 'other-source',
          pattern: 'STAGE2',
          replacement: 'OTHER_SRC',
          isRegex: false,
          scopeType: RuleScopeType.source,
          scopeTargetId: 'src-999',
          sortOrder: 1,
        ),
        // Global rules ordered by sortOrder 1 -> 10
        makeRule(
          id: 'global-1',
          pattern: 'RAW',
          replacement: 'STEP0',
          isRegex: false,
          scopeType: RuleScopeType.global,
          sortOrder: 1,
        ),
        makeRule(
          id: 'global-2',
          pattern: 'STEP0',
          replacement: 'STAGE1',
          isRegex: false,
          scopeType: RuleScopeType.global,
          sortOrder: 10,
        ),
        // Multi-line regex ad removal leaving blank lines to normalize
        makeRule(
          id: 'global-ad',
          pattern: r'^求月票.*$',
          replacement: '',
          isRegex: true,
          scopeType: RuleScopeType.global,
          sortOrder: 20,
        ),
      ];

      final sanitizer = ContentSanitizerImpl(ruleLoader: (_) async => rules);
      final out = await sanitizer.sanitize(
        '  RAW正文  \r\n求月票推荐票！\r\n  下一段。',
        const SanitizeContext(
          bookId: 'book-1',
          sourceId: 'src-1',
          chapterTitle: '第1章',
        ),
      );

      expect(out, equals('CLEAN正文\n\n下一段。'));
    });

    test('skips malformed regexes safely and maintains bounded compiled regex cache', () async {
      final rules = <ReplaceRule>[
        makeRule(
          id: 'bad-regex-1',
          pattern: '[unclosed',
          replacement: 'X',
          isRegex: true,
          sortOrder: 1,
        ),
        makeRule(
          id: 'bad-regex-2',
          pattern: '(*invalid)',
          replacement: 'Y',
          isRegex: true,
          sortOrder: 2,
        ),
        makeRule(
          id: 'good-regex-1',
          pattern: r'广告\d+',
          replacement: '',
          isRegex: true,
          sortOrder: 3,
        ),
        makeRule(
          id: 'good-regex-2',
          pattern: r'水印[A-Z]+',
          replacement: '',
          isRegex: true,
          sortOrder: 4,
        ),
        makeRule(
          id: 'good-regex-3',
          pattern: r'测试\s*尾注',
          replacement: '',
          isRegex: true,
          sortOrder: 5,
        ),
      ];

      final sanitizer = ContentSanitizerImpl(
        ruleLoader: (_) async => rules,
        maxCachedRegexes: 3,
      );

      final out = await sanitizer.sanitize(
        '开头广告123正文水印XYZ结束测试 尾注',
        const SanitizeContext(bookId: 'b1', chapterTitle: 'ch1'),
      );

      expect(out, equals('开头正文结束'));
      expect(sanitizer.regexCacheSize, lessThanOrEqualTo(3));

      // Re-running reuses cache without throwing on cached malformed regexes
      final out2 = await sanitizer.sanitize(
        '广告99第二段',
        const SanitizeContext(bookId: 'b1', chapterTitle: 'ch2'),
      );
      expect(out2, equals('第二段'));
      expect(sanitizer.regexCacheSize, lessThanOrEqualTo(3));
    });

    test('supports SourceRepository adapter constructor', () async {
      final fakeRepo = _FakeSourceRepository(<ReplaceRule>[
        makeRule(
          id: 'r1',
          pattern: r'【.*?】',
          replacement: '',
          isRegex: true,
        ),
      ]);
      final sanitizer = ContentSanitizerImpl(sourceRepository: fakeRepo);
      final out = await sanitizer.sanitize(
        '【盗版网站】正文开始。',
        const SanitizeContext(bookId: 'b1', chapterTitle: 'ch1'),
      );
      expect(out, equals('正文开始。'));
    });
  });
}

class _FakeSourceRepository implements SourceRepository {
  _FakeSourceRepository(this._rules);

  final List<ReplaceRule> _rules;

  @override
  Future<List<ReplaceRule>> listReplaceRules({
    bool enabledOnly = false,
    String? sourceId,
    String? bookId,
  }) async {
    return _rules
        .where((r) => !enabledOnly || r.enabled)
        .toList(growable: false);
  }

  @override
  Future<void> deleteReplaceRule(String ruleId) async {}

  @override
  Future<void> deleteSource(String sourceId) async {}

  @override
  Future<BookSource?> getSourceById(String sourceId) async => null;

  @override
  Future<List<BookSource>> listSources({bool enabledOnly = false}) async =>
      const <BookSource>[];

  @override
  Future<void> saveReplaceRule(ReplaceRule rule) async {}

  @override
  Future<void> saveSource(BookSource source) async {}

  @override
  Future<void> saveSources(List<BookSource> sources) async {}

  @override
  Stream<List<BookSource>> watchSources() =>
      const Stream<List<BookSource>>.empty();
}
