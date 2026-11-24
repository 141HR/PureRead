import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/domain/domain.dart';
import 'package:pureread/engine/source_engine/local_txt/local_txt.dart';

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('pureread_provider_test_');
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('TxtIsolateWorker', () {
    test('reuses background isolate across sequential & concurrent jobs and disposes cleanly', () async {
      final worker = TxtIsolateWorker();
      final f1 = File('${tmpDir.path}${Platform.pathSeparator}worker_1.txt');
      final f2 = File('${tmpDir.path}${Platform.pathSeparator}worker_2.txt');
      await f1.writeAsBytes(utf8.encode('第1章 一\n内容一\n第2章 二\n内容二\n'));
      await f2.writeAsBytes(gbk.encode('第1章 乙\nGBK内容\n'));

      await worker.warmUpGbkTable();
      expect(worker.isRunning, isTrue);

      final (scan1, scan2, hash1) = await (
        worker.scanFile(f1.path),
        worker.scanFile(f2.path),
        worker.computeFastFileHash(f1.path),
      ).wait;

      expect(scan1.encoding, TxtEncoding.utf8);
      expect(scan1.chapters.length, 2);
      expect(scan2.encoding, TxtEncoding.gb18030);
      expect(scan2.chapters.length, 1);
      expect(hash1, scan1.fileHash);

      await worker.dispose();
      await worker.dispose(); // idempotent
      expect(worker.isDisposed, isTrue);
      expect(worker.isRunning, isFalse);

      expect(() => worker.scanFile(f1.path), throwsStateError);
    });
  });

  group('LocalTxtProvider', () {
    late LocalTxtProvider provider;

    setUp(() {
      provider = LocalTxtProvider();
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('exposes exact localTxt BookProvider capabilities', () {
      expect(provider.providerId, 'local_txt');
      expect(provider.type, ProviderType.localTxt);
      expect(
        provider.capabilities,
        const ProviderCapabilities(
          isLocal: true,
          supportsSearch: false,
          supportsUpdateCheck: false,
          supportsChangeSource: false,
        ),
      );
    });

    test('imports and reads mid-file slices for UTF-8, UTF-8-BOM, GB18030, UTF-16LE, UTF-16BE', () async {
      const content =
          '第1章 起航\r\n开篇内容，包含标点！\r\n'
          '第2章 深海\r\n中段切片测试《PureRead》，无乱码。\r\n'
          '第3章 终幕\r\n尾章内容。\r\n';

      final files = <({String filename, String expectedEncoding, List<int> bytes})>[
        (
          filename: '剑来_utf8.txt',
          expectedEncoding: 'UTF-8',
          bytes: utf8.encode(content),
        ),
        (
          filename: '剑来_utf8bom.txt',
          expectedEncoding: 'UTF-8-BOM',
          bytes: <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)],
        ),
        (
          filename: '剑来_gb18030.txt',
          expectedEncoding: 'GB18030',
          bytes: gbk.encode(content),
        ),
        (
          filename: '剑来_utf16le.txt',
          expectedEncoding: 'UTF-16LE',
          bytes: const Utf16Encoder().encodeUtf16Le(content, true),
        ),
        (
          filename: '剑来_utf16be.txt',
          expectedEncoding: 'UTF-16BE',
          bytes: const Utf16Encoder().encodeUtf16Be(content, true),
        ),
      ];

      for (final spec in files) {
        final file = File('${tmpDir.path}${Platform.pathSeparator}${spec.filename}');
        await file.writeAsBytes(spec.bytes);

        final imported = await provider.importTxtFile(file.path);
        expect(imported.book.providerType, ProviderType.localTxt);
        expect(imported.book.localFilePath, file.path);
        expect(imported.book.fileEncoding, spec.expectedEncoding);
        expect(imported.book.fileSizeBytes, spec.bytes.length);
        expect(imported.book.fileHash, isNotEmpty);
        expect(imported.book.totalChapters, 3);
        expect(imported.book.lastChapterTitle, '第3章 终幕');
        expect(imported.chapters.length, 3);
        expect(imported.chapters[0].url, isNull);

        // Read mid-file slice (chapter 2) via RandomAccessFile
        final text = await provider.readChapterText(
          filePath: file.path,
          encoding: imported.book.fileEncoding!,
          chapter: imported.chapters[1],
        );
        expect(text, startsWith('第2章 深海'));
        expect(text, contains('中段切片测试《PureRead》，无乱码。'));
        expect(text, isNot(contains('\uFEFF')));
        expect(text, isNot(contains('\uFFFD')));
      }
    });

    test('supports forcedEncoding and maps missing files and decoding errors to AppFailure', () async {
      final missingPath = '${tmpDir.path}${Platform.pathSeparator}does_not_exist.txt';
      await expectLater(
        () => provider.importTxtFile(missingPath),
        throwsA(isA<FileAccessFailure>()),
      );

      final dummyChapter = ChapterMeta(
        bookId: 'b1',
        chapterIndex: 0,
        title: 'ch0',
        byteStart: 0,
        byteEnd: 10,
        updatedAt: DateTime.utc(2026, 11, 24),
      );
      await expectLater(
        () => provider.readChapterText(
          filePath: missingPath,
          encoding: 'UTF-8',
          chapter: dummyChapter,
        ),
        throwsA(isA<FileAccessFailure>()),
      );

      // Directory path instead of file -> FileAccessFailure
      await expectLater(
        () => provider.importTxtFile(tmpDir.path),
        throwsA(isA<FileAccessFailure>()),
      );

      // Unsupported forcedEncoding -> EncodingFailure
      final gbkFile = File('${tmpDir.path}${Platform.pathSeparator}forced_gbk.txt');
      await gbkFile.writeAsBytes(gbk.encode('第1章 测试\n中文编码测试内容。\n'));
      await expectLater(
        () => provider.importTxtFile(gbkFile.path, forcedEncoding: 'ISO-8859-99'),
        throwsA(isA<EncodingFailure>()),
      );

      // Valid forcedEncoding works
      final forcedOk = await provider.importTxtFile(gbkFile.path, forcedEncoding: 'gbk');
      expect(forcedOk.book.fileEncoding, 'GB18030');

      // Reading GB18030 bytes strictly as UTF-8 -> EncodingFailure
      await expectLater(
        () => provider.readChapterText(
          filePath: gbkFile.path,
          encoding: 'UTF-8',
          chapter: forcedOk.chapters.first,
        ),
        throwsA(isA<EncodingFailure>()),
      );

      // Unsupported encoding in readChapterText -> EncodingFailure
      await expectLater(
        () => provider.readChapterText(
          filePath: gbkFile.path,
          encoding: 'UNKNOWN',
          chapter: forcedOk.chapters.first,
        ),
        throwsA(isA<EncodingFailure>()),
      );

      // Corrupt binary file -> EncodingFailure on auto-detect import
      final corruptFile = File('${tmpDir.path}${Platform.pathSeparator}corrupt.bin');
      await corruptFile.writeAsBytes(const <int>[
        0x80, 0xFF, 0x00, 0x80, 0xFF, 0x00, 0x80, 0xFF,
        0xC0, 0xAF, 0x00, 0xFE, 0xFF, 0x00, 0x81, 0x01,
      ]);
      await expectLater(
        () => provider.importTxtFile(corruptFile.path),
        throwsA(isA<EncodingFailure>()),
      );

      // Out-of-range or null chapter byte range -> FileAccessFailure
      final outOfBounds = forcedOk.chapters.first.copyWith(byteEnd: 999999);
      await expectLater(
        () => provider.readChapterText(
          filePath: gbkFile.path,
          encoding: 'GB18030',
          chapter: outOfBounds,
        ),
        throwsA(isA<FileAccessFailure>()),
      );

      final missingRange = ChapterMeta(
        bookId: 'b1',
        chapterIndex: 0,
        title: 'no-offsets',
        updatedAt: DateTime.utc(2026, 11, 24),
      );
      await expectLater(
        () => provider.readChapterText(
          filePath: gbkFile.path,
          encoding: 'GB18030',
          chapter: missingRange,
        ),
        throwsA(isA<FileAccessFailure>()),
      );
    });

    test('BookProvider contract methods & CancellationToken behave cleanly', () async {
      final file = File('${tmpDir.path}${Platform.pathSeparator}provider_contract.txt');
      await file.writeAsBytes(utf8.encode('第1章 甲\n内容甲。\n第2章 乙\n内容乙。\n'));

      final searchRes = await provider.search('甲');
      expect(searchRes.items, isEmpty);
      expect(searchRes.trace.step, 'search');

      final detailRes = await provider.getBookDetail(file.path);
      expect(detailRes.detail.title, 'provider_contract');
      expect(detailRes.trace.step, 'detail');

      final tocRes = await provider.getToc(file.path);
      expect(tocRes.chapters.length, 2);
      expect(tocRes.trace.step, 'toc');

      final chapterWithPath = tocRes.chapters[1].copyWith(url: file.path);
      final contentRes = await provider.getChapterContent(chapterWithPath);
      expect(contentRes.content.rawText, contains('内容乙。'));
      expect(contentRes.trace.step, 'content');

      final cancelled = CancellationToken()..cancel();
      await expectLater(
        () => provider.importTxtFile(file.path, cancelToken: cancelled),
        throwsA(isA<CancelledFailure>()),
      );
    });
  });
}
