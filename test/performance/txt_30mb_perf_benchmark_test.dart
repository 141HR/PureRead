import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/reader_engine/reader_engine.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';
import 'package:pureread/engine/source_engine/sanitizer/content_sanitizer_impl.dart';
import 'package:pureread/infrastructure/database/database.dart';
import 'package:pureread/infrastructure/storage/storage.dart';
import 'package:pureread/presentation/reader/simulation_page_curl.dart';

const int _kTargetBytes = 30 * 1024 * 1024; // 30.00 MiB
const int _kChapterCount = 1500;
const int _kExpectedTotalChapters = _kChapterCount + 1; // preface + 1500
const String _kWatermark = '【广告水印：盗版站点 www.fake-ad.test 请勿传播】';

class _GeneratedNovel {
  const _GeneratedNovel({
    required this.filePath,
    required this.encoding,
    required this.fileBytes,
    required this.chapterCount,
    required this.generationMs,
  });

  final String filePath;
  final TxtEncoding encoding;
  final int fileBytes;
  final int chapterCount;
  final double generationMs;
}

class _PerfReport {
  final List<String> lines = <String>[];

  void add(String line) => lines.add(line);

  void emitSummaryBlock() {
    _log('=== 30MB_PERF_SUMMARY_BEGIN ===');
    for (final line in lines) {
      _log(line);
    }
    _log('=== 30MB_PERF_SUMMARY_END ===');
  }
}

void _log(String message) {
  // ignore: avoid_print
  print(message);
}

const List<String> _titleThemes = <String>[
  '青云初雪',
  '星海归途',
  '长夜孤灯',
  '墨染江湖',
  '代码与剑',
  '风起云涌',
  '故人重逢',
  '破晓之光',
  '北境孤城',
  '山海旧约',
];

const List<String> _paragraphPool = <String>[
  '夜色微凉，沈砚合上桌上的《山海残卷》，抬头望向窗外闪烁的霓虹灯光。'
      '终端屏幕上的 PureRead v3.13 引擎仍在静默运行，日志里不断刷新着 1024 与 4096 的字节偏移刻度。'
      '「你确定要在今晚测试这套分页算法吗？」林清音端着热茶走近，「如果出现半个汉字乱码怎么办？」\r\n',
  '第3天清晨，山风依旧带着微凉的气息，他敲下几行 Flutter 命令：第1步校验编码，第2步构建章节索引，第3步统计字符守恒。'
      '窗外细雨淅沥，石板路上的积水倒映着古老牌坊与现代路灯，仿佛两个时代在此交汇！'
      '无论是「行首避头」还是「行尾避尾」，排版细节都决定了长篇阅读的呼吸感。\r\n',
  '“这已经是第7次压测了，数据流依然稳如磐石。”苏牧把玩着手中的青铜令牌（编号 A-2026），'
      '仔细核对清单上的条目：墨水屏适配、双栏布局、UTF-8 与 GB18030 流式识别、以及 RandomAccessFile 随机读取。'
      '远处的钟楼敲响了午夜十二点的钟声，第一缕山风穿过回廊，吹动了案头的书页……\r\n',
  '第12次校验完成，日志未发现任何异常字符。他翻阅《太虚真经》和《九霄星图》的批注：'
      '第一件事便是理清经脉与灵力的流转路径；第二件事则是防范心魔反噬（成功率仅 62.5%）。'
      '“别急，先喝口水，等 Dart Isolate 把三千万字节全部扫完再说！”\r\n',
  '长街尽头传来阵阵马蹄声，镖局的旗帜在暮色中猎猎作响，车队编号分别为 Alpha-01、Beta-02、Gamma-03。'
      '掌柜拨动算盘，嘴里念念有词：「三两银子、五斤熟肉、外加两坛女儿红——总共二十八贯钱，少一文都不行！」'
      '众人哄笑一堂，客栈里的灯火越发明亮温暖。\r\n',
  '在测试脚本运行到第1024行时，监控面板上的帧耗时曲线平稳地维持在 4.2ms 左右，远低于 8.33ms 的 120Hz 阈值。'
      '这就是工程打磨的意义：把复杂的底层编码与断行禁则藏在幕后，留给读者的只有纸张般的宁静与顺滑！'
      '翻过这一页，新的故事才刚刚拉开帷幕。\r\n',
];

String _toChineseNumeral(int n) {
  const digits = <String>['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  if (n <= 0) return '零';
  if (n < 10) return digits[n];
  final buf = StringBuffer();
  final thousands = n ~/ 1000;
  final hundreds = (n % 1000) ~/ 100;
  final tens = (n % 100) ~/ 10;
  final ones = n % 10;

  if (thousands > 0) {
    buf.write('${digits[thousands]}千');
  }
  if (hundreds > 0) {
    buf.write('${digits[hundreds]}百');
  } else if (thousands > 0 && (tens > 0 || ones > 0)) {
    buf.write('零');
  }
  if (tens > 0) {
    if (tens > 1 || thousands > 0 || hundreds > 0) {
      buf.write(digits[tens]);
    }
    buf.write('十');
  } else if (hundreds > 0 && ones > 0) {
    buf.write('零');
  }
  if (ones > 0) {
    buf.write(digits[ones]);
  }
  return buf.toString();
}

String _buildChapterTitle(int index, int totalCount) {
  final theme = _titleThemes[index % _titleThemes.length];
  if (index == 0) {
    return '序章 $theme';
  }
  if (index == totalCount - 1) {
    return '尾声 $theme（2026终章）';
  }
  if (index % 250 == 0) {
    return '第${_toChineseNumeral(index)}回 $theme';
  }
  if (index % 50 == 0) {
    return '第${_toChineseNumeral(index)}章：$theme';
  }
  return '第$index章 $theme（$index）';
}

Future<_GeneratedNovel> _streamGenerateNovel({
  required String outputPath,
  required TxtEncoding encoding,
  int targetBytes = _kTargetBytes,
  int chapterCount = _kChapterCount,
}) async {
  assert(
    encoding == TxtEncoding.utf8 || encoding == TxtEncoding.gb18030,
    'Benchmark generator supports UTF-8 (no BOM) and GB18030.',
  );

  final sw = Stopwatch()..start();
  final file = File(outputPath);
  await file.parent.create(recursive: true);

  final sink = file.openWrite();
  final chunkBuf = BytesBuilder(copy: false);
  const flushThresholdBytes = 256 * 1024;
  var writtenBytes = 0;

  void emitBytes(List<int> bytes) {
    chunkBuf.add(bytes);
    writtenBytes += bytes.length;
    if (chunkBuf.length >= flushThresholdBytes) {
      sink.add(chunkBuf.takeBytes());
    }
  }

  Uint8List encodeText(String text) {
    if (encoding == TxtEncoding.gb18030) {
      return Uint8List.fromList(gbk.encode(text));
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  final encodedParagraphs = _paragraphPool
      .map(encodeText)
      .toList(growable: false);
  final encodedWatermark = encodeText('$_kWatermark\r\n');
  final avgParagraphBytes =
      encodedParagraphs.fold<int>(0, (sum, b) => sum + b.length) ~/
      encodedParagraphs.length;

  emitBytes(
    encodeText(
      '《墨海星图（2026精校版）》\r\n作者：净读性能基准\r\n'
      '简介：用于验证 PureRead（净读）30MiB 本地 TXT 导入、Drift 索引与排版性能的长篇测试小说。\r\n\r\n',
    ),
  );

  final bytesPerChapterTarget = (targetBytes - writtenBytes) ~/ chapterCount;

  for (var i = 0; i < chapterCount; i++) {
    final title = _buildChapterTitle(i, chapterCount);
    final headerBytes = encodeText('$title\r\n');
    emitBytes(headerBytes);
    emitBytes(encodedWatermark);

    var chapterBytes = headerBytes.length + encodedWatermark.length;
    final remainingTarget = targetBytes - writtenBytes;
    final remainingChapters = chapterCount - i;
    final adaptiveTarget = remainingTarget ~/ remainingChapters;
    final desiredChapterBytes = adaptiveTarget > bytesPerChapterTarget
        ? adaptiveTarget
        : bytesPerChapterTarget;

    var pIdx = i;
    while (chapterBytes + avgParagraphBytes <= desiredChapterBytes ||
        (i == chapterCount - 1 && writtenBytes < targetBytes)) {
      final pBytes = encodedParagraphs[pIdx % encodedParagraphs.length];
      emitBytes(pBytes);
      chapterBytes += pBytes.length;
      pIdx++;
    }

    emitBytes(const <int>[0x0D, 0x0A]);
  }

  if (chunkBuf.isNotEmpty) {
    sink.add(chunkBuf.takeBytes());
  }
  await sink.flush();
  await sink.close();
  sw.stop();

  return _GeneratedNovel(
    filePath: outputPath,
    encoding: encoding,
    fileBytes: writtenBytes,
    chapterCount: chapterCount,
    generationMs: sw.elapsedMicroseconds / 1000.0,
  );
}

void _assertCharacterConservation(String chapterText, List<PageSlice> pages) {
  expect(pages, isNotEmpty);
  expect(pages.first.startCharOffset, equals(0));
  expect(pages.last.endCharOffset, equals(chapterText.length));

  final pageJoin = StringBuffer();
  final lineJoin = StringBuffer();

  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    expect(page.pageIndex, equals(i));
    if (i + 1 < pages.length) {
      expect(page.endCharOffset, equals(pages[i + 1].startCharOffset));
    }
    pageJoin.write(
      chapterText.substring(page.startCharOffset, page.endCharOffset),
    );

    if (page.lines.isNotEmpty) {
      expect(page.lines.first.startCharOffset, equals(page.startCharOffset));
      expect(page.lines.last.endCharOffset, equals(page.endCharOffset));
      for (var j = 0; j < page.lines.length; j++) {
        final line = page.lines[j];
        expect(
          line.text,
          equals(
            chapterText.substring(line.startCharOffset, line.endCharOffset),
          ),
        );
        if (j + 1 < page.lines.length) {
          expect(line.endCharOffset, equals(page.lines[j + 1].startCharOffset));
        }
        lineJoin.write(line.text);
      }
    }
  }

  expect(pageJoin.toString(), equals(chapterText));
  expect(lineJoin.toString(), equals(chapterText));
}

String _fmtMs(num ms) => ms.toStringAsFixed(2);
String _fmtMiB(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppPathResolver pathResolver;
  late AppDatabase db;
  late DriftBookRepository bookRepo;
  late DriftSourceRepository sourceRepo;
  late TxtIsolateWorker worker;
  late LocalTxtProvider txtProvider;
  late ContentSanitizerImpl sanitizer;
  late _GeneratedNovel utf8Novel;
  late _GeneratedNovel gbNovel;
  final report = _PerfReport();

  String? utf8BookId;
  String? gbBookId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pureread_30mb_perf_');
    final dataRoot = Directory(p.join(tempDir.path, 'data'));
    final cacheRoot = Directory(p.join(tempDir.path, 'cache'));
    final novelsDir = Directory(p.join(tempDir.path, 'novels'));
    await novelsDir.create(recursive: true);

    pathResolver = AppPathResolver.fromRoots(
      dataRootDir: dataRoot,
      cacheRootDir: cacheRoot,
    );
    await pathResolver.ensureDirectoriesExist();

    db = AppDatabase.forFile(
      pathResolver.databaseFile,
      backupsDirPath: pathResolver.dbBackupsDir.path,
      useBackgroundIsolate: false,
    );
    bookRepo = DriftBookRepository(db);
    sourceRepo = DriftSourceRepository(db);
    worker = TxtIsolateWorker();
    txtProvider = LocalTxtProvider(worker: worker);
    sanitizer = ContentSanitizerImpl(sourceRepository: sourceRepo);

    // Initialize DB schema + seeds and install a global regex watermark rule.
    await bookRepo.listGroups();
    await sourceRepo.saveReplaceRule(
      ReplaceRule(
        id: 'perf-global-watermark',
        name: '清理测试广告水印',
        pattern: r'【广告水印：.*?】',
        replacement: '',
        isRegex: true,
        scopeType: RuleScopeType.global,
        enabled: true,
        sortOrder: 0,
        updatedAt: DateTime.utc(2026, 11, 25),
      ),
    );

    utf8Novel = await _streamGenerateNovel(
      outputPath: p.join(novelsDir.path, 'novel_utf8_30mb.txt'),
      encoding: TxtEncoding.utf8,
    );
    gbNovel = await _streamGenerateNovel(
      outputPath: p.join(novelsDir.path, 'novel_gb18030_30mb.txt'),
      encoding: TxtEncoding.gb18030,
    );

    report.add(
      'CORPUS | UTF-8=${_fmtMiB(utf8Novel.fileBytes)} MiB '
      '(${utf8Novel.fileBytes} B, ${utf8Novel.chapterCount} ch, '
      'gen=${_fmtMs(utf8Novel.generationMs)} ms) | '
      'GB18030=${_fmtMiB(gbNovel.fileBytes)} MiB '
      '(${gbNovel.fileBytes} B, ${gbNovel.chapterCount} ch, '
      'gen=${_fmtMs(gbNovel.generationMs)} ms)',
    );
  });

  tearDownAll(() async {
    report.emitSummaryBlock();
    await txtProvider.dispose();
    await worker.dispose();
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'NFR-A: 30 MiB UTF-8 & GB18030 import + Drift bulk index (< 2,000 ms)',
    () async {
      final specs =
          <({String tag, _GeneratedNovel novel, TxtEncoding expectedEnum})>[
            (
              tag: 'UTF-8',
              novel: utf8Novel,
              expectedEnum: TxtEncoding.utf8,
            ),
            (
              tag: 'GB18030',
              novel: gbNovel,
              expectedEnum: TxtEncoding.gb18030,
            ),
          ];

      for (final spec in specs) {
        final rssBefore = ProcessInfo.currentRss;
        final totalSw = Stopwatch()..start();

        final importSw = Stopwatch()..start();
        final imported = await txtProvider.importTxtFile(spec.novel.filePath);
        importSw.stop();

        final dbSw = Stopwatch()..start();
        await bookRepo.saveBook(imported.book);
        await bookRepo.replaceChapters(imported.book.id, imported.chapters);
        dbSw.stop();

        totalSw.stop();
        final rssAfter = ProcessInfo.currentRss;
        final rssDeltaBytes = rssAfter - rssBefore;

        final importMs = importSw.elapsedMicroseconds / 1000.0;
        final dbIndexMs = dbSw.elapsedMicroseconds / 1000.0;
        final totalMs = totalSw.elapsedMicroseconds / 1000.0;

        if (spec.expectedEnum == TxtEncoding.utf8) {
          utf8BookId = imported.book.id;
        } else {
          gbBookId = imported.book.id;
        }

        expect(
          imported.book.fileSizeBytes,
          greaterThanOrEqualTo(_kTargetBytes),
        );
        expect(imported.book.fileEncoding, spec.expectedEnum.label);
        expect(
          TxtEncoding.tryParse(imported.book.fileEncoding),
          spec.expectedEnum,
        );
        expect(imported.chapters.length, _kExpectedTotalChapters);
        expect(imported.book.totalChapters, _kExpectedTotalChapters);
        expect(imported.book.fileHash, isNotNull);
        expect(imported.book.fileHash, isNotEmpty);

        // Verify contiguous byte slices cover the entire file with zero gaps.
        expect(imported.chapters.first.byteStart, 0);
        for (var i = 0; i < imported.chapters.length; i++) {
          final ch = imported.chapters[i];
          expect(ch.chapterIndex, i);
          expect(ch.byteStart, isNotNull);
          expect(ch.byteEnd, isNotNull);
          expect(ch.byteStart!, lessThan(ch.byteEnd!));
          if (i + 1 < imported.chapters.length) {
            expect(ch.byteEnd, imported.chapters[i + 1].byteStart);
          }
        }
        expect(imported.chapters.last.byteEnd, imported.book.fileSizeBytes);

        expect(
          totalSw.elapsedMilliseconds,
          lessThan(2000),
          reason: '${spec.tag} 30 MiB import + Drift index exceeded 2000 ms',
        );

        report.add(
          'NFR-A [${spec.tag}] | size=${_fmtMiB(imported.book.fileSizeBytes!)} MiB | '
          'encoding=${imported.book.fileEncoding} (${spec.expectedEnum.name}) | '
          'chapters=${imported.chapters.length} | '
          'scanImport=${_fmtMs(importMs)} ms | '
          'driftBulkIndex=${_fmtMs(dbIndexMs)} ms | '
          'total=${_fmtMs(totalMs)} ms (<2000ms) | '
          'rssBefore=${_fmtMiB(rssBefore)} MiB | '
          'rssAfter=${_fmtMiB(rssAfter)} MiB | '
          'rssDelta=${_fmtMiB(rssDeltaBytes)} MiB',
        );
      }
    },
  );

  test(
    'NFR-B: Secondary cold book open to first screen (< 200 ms) for ch#0, ch#750, ch#1500',
    () async {
      expect(utf8BookId, isNotNull);
      expect(gbBookId, isNotNull);

      final theme = DefaultDatabaseSeeds.builtInThemes(
        DateTime.utc(2026, 11, 25),
      ).first;
      final portraitConfig = PaginationGeometryResolver.resolve(
        viewportWidth: 390,
        viewportHeight: 780,
        theme: theme,
      );

      final bookCases = <({String tag, String bookId})>[
        (tag: 'UTF-8', bookId: utf8BookId!),
        (tag: 'GB18030', bookId: gbBookId!),
      ];

      for (final bc in bookCases) {
        final dbSw = Stopwatch()..start();
        final book = await bookRepo.getBookById(bc.bookId);
        final chapters = await bookRepo.listChapters(bc.bookId);
        final progress = await bookRepo.getProgress(bc.bookId);
        dbSw.stop();
        final dbReadMs = dbSw.elapsedMicroseconds / 1000.0;

        expect(book, isNotNull);
        expect(chapters.length, _kExpectedTotalChapters);
        expect(progress, isNull);

        for (final targetIdx in <int>[0, 1, 750, 1500]) {
          final chapter = chapters[targetIdx];
          final coldPaginator = IncrementalTextPaginator();

          final rafSw = Stopwatch()..start();
          final rawText = await txtProvider.readChapterText(
            filePath: book!.localFilePath!,
            encoding: book.fileEncoding!,
            chapter: chapter,
          );
          rafSw.stop();
          final rafMs = rafSw.elapsedMicroseconds / 1000.0;

          final sanitizeSw = Stopwatch()..start();
          final sanitizedText = await sanitizer.sanitize(
            rawText,
            SanitizeContext(bookId: book.id, chapterTitle: chapter.title),
          );
          sanitizeSw.stop();
          final sanitizeMs = sanitizeSw.elapsedMicroseconds / 1000.0;

          FirstScreenResult? firstScreen;
          final firstScreenSw = Stopwatch()..start();
          final pagResult = await coldPaginator.paginateChapterIncremental(
            chapterIndex: chapter.chapterIndex,
            sanitizedText: sanitizedText,
            config: portraitConfig,
            treatFirstLineAsTitle: true,
            onFirstScreen: (fs) {
              firstScreenSw.stop();
              firstScreen = fs;
            },
          );
          final firstScreenMs = firstScreenSw.elapsedMicroseconds / 1000.0;
          final fullPagMs = pagResult.totalComputeMicros / 1000.0;

          final coldOpenTotalMs =
              dbReadMs + rafMs + sanitizeMs + firstScreenMs;

          expect(rawText, isNotEmpty);
          expect(sanitizedText, isNotEmpty);
          expect(sanitizedText, isNot(contains('\uFFFD')));
          expect(sanitizedText, isNot(contains('广告水印')));
          expect(sanitizedText, contains('PureRead'));
          if (targetIdx == 0) {
            expect(sanitizedText, contains('《墨海星图'));
            expect(sanitizedText, contains('。'));
          } else {
            expect(sanitizedText, contains('，'));
            expect(sanitizedText, contains('「'));
          }
          expect(firstScreen, isNotNull);
          expect(firstScreen!.pages, isNotEmpty);
          expect(
            coldOpenTotalMs,
            lessThan(200.0),
            reason:
                '${bc.tag} ch#$targetIdx cold open exceeded 200 ms ($coldOpenTotalMs ms)',
          );

          report.add(
            'NFR-B [${bc.tag} ch#$targetIdx "${chapter.title}"] | '
            'dbRead=${_fmtMs(dbReadMs)} ms | '
            'rafRead=${_fmtMs(rafMs)} ms | '
            'sanitize=${_fmtMs(sanitizeMs)} ms | '
            'firstScreen=${_fmtMs(firstScreenMs)} ms | '
            'coldOpenTotal=${_fmtMs(coldOpenTotalMs)} ms (<200ms) | '
            'fullChapterCompute=${_fmtMs(fullPagMs)} ms (${pagResult.allPages.length} pages)',
          );
        }
      }
    },
  );

  test(
    'NFR-C: Chapter switch & multi-viewport reflow (< 50 ms) + 100% conservation + charOffset 0-drift',
    () async {
      expect(utf8BookId, isNotNull);

      final book = (await bookRepo.getBookById(utf8BookId!))!;
      final ch750 = (await bookRepo.getChapter(book.id, 750))!;
      final ch751 = (await bookRepo.getChapter(book.id, 751))!;

      final raw750 = await txtProvider.readChapterText(
        filePath: book.localFilePath!,
        encoding: book.fileEncoding!,
        chapter: ch750,
      );
      final sanitized750 = await sanitizer.sanitize(
        raw750,
        SanitizeContext(bookId: book.id, chapterTitle: ch750.title),
      );

      final baseTheme = DefaultDatabaseSeeds.builtInThemes(
        DateTime.utc(2026, 11, 25),
      ).first;

      PaginationConfig configFor({
        required double width,
        required double height,
        required double fontSize,
      }) {
        final themed = ReaderTheme(
          id: baseTheme.id,
          name: baseTheme.name,
          isBuiltin: baseTheme.isBuiltin,
          isDark: baseTheme.isDark,
          bgColor: baseTheme.bgColor,
          textColor: baseTheme.textColor,
          secondaryTextColor: baseTheme.secondaryTextColor,
          fontSize: fontSize,
          updatedAt: baseTheme.updatedAt,
        );
        return PaginationGeometryResolver.resolve(
          viewportWidth: width,
          viewportHeight: height,
          theme: themed,
        );
      }

      final portraitCfg = configFor(width: 390, height: 780, fontSize: 18);
      final desktop20Cfg = configFor(width: 1280, height: 800, fontSize: 20);
      final desktop22Cfg = configFor(width: 1280, height: 800, fontSize: 22);
      final narrow15Cfg = configFor(width: 320, height: 620, fontSize: 15);
      final restorePortraitCfg = configFor(
        width: 390,
        height: 780,
        fontSize: 18,
      );

      final paginator = IncrementalTextPaginator();

      // 1. Chapter switch latency (ch#750 -> ch#751)
      final switchSw = Stopwatch()..start();
      final switchedChapter = await bookRepo.getChapter(book.id, 751);
      final raw751 = await txtProvider.readChapterText(
        filePath: book.localFilePath!,
        encoding: book.fileEncoding!,
        chapter: switchedChapter!,
      );
      final sanitized751 = await sanitizer.sanitize(
        raw751,
        SanitizeContext(bookId: book.id, chapterTitle: ch751.title),
      );
      final switchedPages = await paginator.paginateChapter(
        chapterIndex: ch751.chapterIndex,
        sanitizedText: sanitized751,
        config: portraitCfg,
      );
      switchSw.stop();
      final switchMs = switchSw.elapsedMicroseconds / 1000.0;
      _assertCharacterConservation(sanitized751, switchedPages);
      expect(
        switchSw.elapsedMilliseconds,
        lessThan(50),
        reason: 'Chapter switch ch#750->ch#751 exceeded 50 ms ($switchMs ms)',
      );
      report.add(
        'NFR-C [ChapterSwitch ch#750->ch#751] | '
        'wall=${_fmtMs(switchMs)} ms (<50ms) | '
        'pages=${switchedPages.length} | chars=${sanitized751.length}',
      );

      // 2. Multi-viewport reflow sequence on ch#750
      final steps = <({String label, PaginationConfig config})>[
        (label: 'portrait_1col_390x780_18pt', config: portraitCfg),
        (label: 'desktop_2col_1280x800_20pt', config: desktop20Cfg),
        (label: 'desktop_2col_1280x800_22pt', config: desktop22Cfg),
        (label: 'narrow_1col_320x620_15pt', config: narrow15Cfg),
        (label: 'restore_1col_390x780_18pt', config: restorePortraitCfg),
      ];

      late List<PageSlice> initialPortraitPages;
      late List<PageSlice> restoredPortraitPages;
      late int targetCharOffset;

      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final reflowSw = Stopwatch()..start();
        final pages = await paginator.paginateChapter(
          chapterIndex: ch750.chapterIndex,
          sanitizedText: sanitized750,
          config: step.config,
        );
        reflowSw.stop();
        final reflowMs = reflowSw.elapsedMicroseconds / 1000.0;

        _assertCharacterConservation(sanitized750, pages);
        expect(
          reflowSw.elapsedMilliseconds,
          lessThan(50),
          reason: 'Reflow ${step.label} exceeded 50 ms ($reflowMs ms)',
        );

        if (i == 0) {
          initialPortraitPages = pages;
          final midPageIdx = pages.length ~/ 2;
          targetCharOffset = AnchorMapper.getAnchorForPage(
            pages[midPageIdx],
            chapterTitleSnapshot: ch750.title,
          ).charOffset;
          expect(targetCharOffset, greaterThan(0));
        }

        final mappedPageIdx = AnchorMapper.findPageIndexByCharOffset(
          pages,
          targetCharOffset,
        );
        expect(pages[mappedPageIdx].containsOffset(targetCharOffset), isTrue);

        if (step.config.columnCount == 2) {
          final spreadIdx = AnchorMapper.findSpreadIndexByCharOffset(
            pages,
            targetCharOffset,
            columnCount: 2,
          );
          final (left, right) = AnchorMapper.pairSpread(pages, spreadIdx, 2);
          final spreadEnd = right?.endCharOffset ?? left.endCharOffset;
          expect(
            targetCharOffset >= left.startCharOffset &&
                targetCharOffset < spreadEnd,
            isTrue,
          );
        }

        if (i == steps.length - 1) {
          restoredPortraitPages = pages;
        }

        report.add(
          'NFR-C [Reflow ${step.label}] | cols=${step.config.columnCount} | '
          'wall=${_fmtMs(reflowMs)} ms (<50ms) | '
          'pages=${pages.length} | mappedPage=$mappedPageIdx | '
          'conservation=100% (${sanitized750.length} chars)',
        );
      }

      final restoredPageIdx = AnchorMapper.findPageIndexByCharOffset(
        restoredPortraitPages,
        targetCharOffset,
      );
      final restoredAnchor = AnchorMapper.getAnchorForPage(
        restoredPortraitPages[restoredPageIdx],
        chapterTitleSnapshot: ch750.title,
      );
      final charOffsetDrift = (restoredAnchor.charOffset - targetCharOffset)
          .abs();

      expect(restoredPortraitPages.length, equals(initialPortraitPages.length));
      expect(charOffsetDrift, equals(0));

      report.add(
        'NFR-C [RoundTripAnchor] | targetCharOffset=$targetCharOffset | '
        'restoredCharOffset=${restoredAnchor.charOffset} | '
        'drift=$charOffsetDrift chars (==0)',
      );
    },
  );

  test(
    'NFR-D: 120Hz page-curl geometry budget (1,000 iterations portrait & 2-col landscape < 1.0 ms avg)',
    () {
      const iterations = 1000;
      final viewports = <({String label, Size size})>[
        (label: 'portrait_390x780', size: const Size(390, 780)),
        (label: 'landscape_2col_1280x800', size: const Size(1280, 800)),
      ];

      for (final vp in viewports) {
        // Warm up JIT once before timing the 1,000-frame loop.
        PageCurlGeometry.compute(
          size: vp.size,
          progress: 0.5,
          direction: CurlDirection.forward,
        );

        var maxSingleMicros = 0;
        final totalSw = Stopwatch()..start();

        for (var i = 0; i < iterations; i++) {
          final progress = i / (iterations - 1);
          final direction = i.isEven
              ? CurlDirection.forward
              : CurlDirection.backward;
          final frameSw = Stopwatch()..start();
          final g = PageCurlGeometry.compute(
            size: vp.size,
            progress: progress,
            direction: direction,
            dragVector: Offset(-progress, (progress - 0.5) * 0.4),
            touchYNormalized: 0.68,
          );
          frameSw.stop();

          if (frameSw.elapsedMicroseconds > maxSingleMicros) {
            maxSingleMicros = frameSw.elapsedMicroseconds;
          }

          expect(g.creaseAnchor.dx.isFinite, isTrue);
          expect(g.creaseAnchor.dy.isFinite, isTrue);
          expect(g.foldPoint.dx.isFinite, isTrue);
          expect(g.foldPoint.dy.isFinite, isTrue);
          expect(g.curlRadius.isFinite, isTrue);
        }

        totalSw.stop();
        final totalMs = totalSw.elapsedMicroseconds / 1000.0;
        final avgMs = totalMs / iterations;
        final maxMs = maxSingleMicros / 1000.0;

        expect(
          avgMs,
          lessThan(1.0),
          reason:
              '${vp.label} PageCurlGeometry average compute time exceeded 1.0 ms ($avgMs ms)',
        );

        report.add(
          'NFR-D [PageCurl ${vp.label}] | iterations=$iterations | '
          'total=${_fmtMs(totalMs)} ms | '
          'avg=${avgMs.toStringAsFixed(4)} ms (<1.0ms, 120Hz budget 8.33ms) | '
          'max=${maxMs.toStringAsFixed(4)} ms',
        );
      }
    },
  );
}
