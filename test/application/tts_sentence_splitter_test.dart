import 'package:flutter_test/flutter_test.dart';
import 'package:pureread/application/reader/tts_sentence_splitter.dart';

void main() {
  group('TtsSentenceSplitter', () {
    test('returns empty list for empty, whitespace, and punctuation-only text', () {
      expect(TtsSentenceSplitter.split(''), isEmpty);
      expect(TtsSentenceSplitter.split('   \n\t\r\n　　  '), isEmpty);
      expect(TtsSentenceSplitter.split('……——***！？「」（）\n---'), isEmpty);
    });

    test('splits Chinese and English sentences while preserving exact UTF-16 offsets', () {
      const chapter =
          '第一章 初遇\r\n'
          '  风起云涌！少年说道：“真的吗？”  \n'
          'Hello world. Version 0.5.0 stays intact! Next?\n'
          '半句分号；结尾句。';

      final utterances = TtsSentenceSplitter.split(chapter);

      expect(
        utterances.map((u) => u.text).toList(),
        equals(<String>[
          '第一章 初遇',
          '风起云涌！',
          '少年说道：“真的吗？”',
          'Hello world.',
          'Version 0.5.0 stays intact!',
          'Next?',
          '半句分号；',
          '结尾句。',
        ]),
      );

      for (var i = 0; i < utterances.length; i++) {
        final u = utterances[i];
        expect(u.index, i);
        expect(
          chapter.substring(u.startCharOffset, u.endCharOffset),
          u.text,
        );
        if (i > 0) {
          expect(
            u.startCharOffset,
            greaterThanOrEqualTo(utterances[i - 1].endCharOffset),
          );
        }
      }
    });

    test('skips Contract A EPUB inline image marker lines while preserving exact offsets', () {
      const img1 = '\uFFFCprimg:v1:OEBPS%2FImages%2F01.jpg|800x600|插图说明\uFFFC';
      const img2 = '  \uFFFCprimg:v1:OEBPS%2FImages%2F02.png|0x0|\uFFFC  ';
      const chapter =
          '开篇第一句。\n'
          '$img1\n'
          '插图后的正文继续！\r\n'
          '$img2\r\n'
          '最后一句。';

      final utterances = TtsSentenceSplitter.split(chapter);

      expect(
        utterances.map((u) => u.text).toList(),
        equals(<String>[
          '开篇第一句。',
          '插图后的正文继续！',
          '最后一句。',
        ]),
      );

      for (final u in utterances) {
        expect(u.text.contains('\uFFFC'), isFalse);
        expect(u.text.contains('primg:'), isFalse);
        expect(
          chapter.substring(u.startCharOffset, u.endCharOffset),
          u.text,
        );
      }

      const imageOnlyChapter = '$img1\n$img2';
      expect(TtsSentenceSplitter.split(imageOnlyChapter), isEmpty);
    });

    test('performs secondary splitting on comma/space when chunk exceeds 120 chars', () {
      final longClause = List<String>.filled(
        6,
        '这是一段超过一百二十个字符的长句子分片测试内容用于验证逗号拆分逻辑',
      ).join('，');
      final englishLong = List<String>.filled(
        20,
        'wordchunk',
      ).join(' ');
      final unpunctuatedEmoji = '${'甲' * 119}😀${'乙' * 20}';
      final chapter = '$longClause。\n$englishLong\n$unpunctuatedEmoji';

      final utterances = TtsSentenceSplitter.split(chapter);
      expect(utterances.length, greaterThanOrEqualTo(6));

      for (final u in utterances) {
        expect(u.text.length, lessThanOrEqualTo(120));
        expect(
          chapter.substring(u.startCharOffset, u.endCharOffset),
          u.text,
        );
      }

      // Ensure surrogate pair around 😀 (UTF-16 length 2) was not torn apart.
      final rejoined = utterances.map((u) => u.text).join();
      expect(rejoined.contains('😀'), isTrue);
    });

    test('findUtteranceIndexForOffset resolves active utterance accurately', () {
      const text = '第一句。第二句。第三句。';
      final utterances = TtsSentenceSplitter.split(text);
      expect(utterances, hasLength(3));

      expect(TtsSentenceSplitter.findUtteranceIndexForOffset(utterances, 0), 0);
      expect(TtsSentenceSplitter.findUtteranceIndexForOffset(utterances, 2), 0);
      expect(TtsSentenceSplitter.findUtteranceIndexForOffset(utterances, 4), 1);
      expect(TtsSentenceSplitter.findUtteranceIndexForOffset(utterances, 10), 2);
      expect(
        TtsSentenceSplitter.findUtteranceIndexForOffset(utterances, 999),
        2,
      );
      expect(TtsSentenceSplitter.findUtteranceIndexForOffset(const [], 10), 0);
    });
  });
}
