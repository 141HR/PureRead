import '../value_objects/reading_anchor.dart';

/// Persisted reading progress entity corresponding to `reading_progress`.
class ReadingProgress {
  final String bookId;
  final int chapterIndex;
  final int charOffset;
  final String chapterTitleSnapshot;
  final double progressPercent;
  final int readingDurationSec;
  final DateTime updatedAt;
  final String deviceId;

  const ReadingProgress({
    required this.bookId,
    this.chapterIndex = 0,
    this.charOffset = 0,
    this.chapterTitleSnapshot = '',
    this.progressPercent = 0.0,
    this.readingDurationSec = 0,
    required this.updatedAt,
    this.deviceId = '',
  });

  /// Converts this persisted progress record into a [ReadingAnchor].
  ReadingAnchor toAnchor() => ReadingAnchor(
        chapterIndex: chapterIndex,
        charOffset: charOffset,
        chapterTitleSnapshot: chapterTitleSnapshot,
      );

  ReadingProgress copyWith({
    String? bookId,
    int? chapterIndex,
    int? charOffset,
    String? chapterTitleSnapshot,
    double? progressPercent,
    int? readingDurationSec,
    DateTime? updatedAt,
    String? deviceId,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      charOffset: charOffset ?? this.charOffset,
      chapterTitleSnapshot: chapterTitleSnapshot ?? this.chapterTitleSnapshot,
      progressPercent: progressPercent ?? this.progressPercent,
      readingDurationSec: readingDurationSec ?? this.readingDurationSec,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingProgress &&
          runtimeType == other.runtimeType &&
          bookId == other.bookId &&
          chapterIndex == other.chapterIndex &&
          charOffset == other.charOffset &&
          chapterTitleSnapshot == other.chapterTitleSnapshot &&
          progressPercent == other.progressPercent &&
          readingDurationSec == other.readingDurationSec &&
          updatedAt == other.updatedAt &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(
        bookId,
        chapterIndex,
        charOffset,
        chapterTitleSnapshot,
        progressPercent,
        readingDurationSec,
        updatedAt,
        deviceId,
      );
}
