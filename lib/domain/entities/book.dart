import '../value_objects/provider_capabilities.dart';

/// Core book entity corresponding to the `books` table.
class Book {
  final String id;
  final String? sourceId;
  final ProviderType providerType;
  final String? originBookUrl;
  final String? tocUrl;
  final String title;
  final String author;
  final String? coverPath;
  final String intro;
  final String? localFilePath;
  final String? fileEncoding;
  final int? fileSizeBytes;
  final String? fileHash;
  final String? groupId;
  final bool isPinned;
  final int totalChapters;
  final int unreadCount;
  final String lastChapterTitle;
  final DateTime? lastReadAt;
  final DateTime? latestChapterAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Book({
    required this.id,
    this.sourceId,
    required this.providerType,
    this.originBookUrl,
    this.tocUrl,
    required this.title,
    this.author = '',
    this.coverPath,
    this.intro = '',
    this.localFilePath,
    this.fileEncoding,
    this.fileSizeBytes,
    this.fileHash,
    this.groupId,
    this.isPinned = false,
    this.totalChapters = 0,
    this.unreadCount = 0,
    this.lastChapterTitle = '',
    this.lastReadAt,
    this.latestChapterAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Book copyWith({
    String? id,
    String? sourceId,
    ProviderType? providerType,
    String? originBookUrl,
    String? tocUrl,
    String? title,
    String? author,
    String? coverPath,
    String? intro,
    String? localFilePath,
    String? fileEncoding,
    int? fileSizeBytes,
    String? fileHash,
    String? groupId,
    bool clearGroupId = false,
    bool? isPinned,
    int? totalChapters,
    int? unreadCount,
    String? lastChapterTitle,
    DateTime? lastReadAt,
    DateTime? latestChapterAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Book(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      providerType: providerType ?? this.providerType,
      originBookUrl: originBookUrl ?? this.originBookUrl,
      tocUrl: tocUrl ?? this.tocUrl,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      intro: intro ?? this.intro,
      localFilePath: localFilePath ?? this.localFilePath,
      fileEncoding: fileEncoding ?? this.fileEncoding,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      fileHash: fileHash ?? this.fileHash,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      isPinned: isPinned ?? this.isPinned,
      totalChapters: totalChapters ?? this.totalChapters,
      unreadCount: unreadCount ?? this.unreadCount,
      lastChapterTitle: lastChapterTitle ?? this.lastChapterTitle,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      latestChapterAt: latestChapterAt ?? this.latestChapterAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sourceId == other.sourceId &&
          providerType == other.providerType &&
          originBookUrl == other.originBookUrl &&
          tocUrl == other.tocUrl &&
          title == other.title &&
          author == other.author &&
          coverPath == other.coverPath &&
          intro == other.intro &&
          localFilePath == other.localFilePath &&
          fileEncoding == other.fileEncoding &&
          fileSizeBytes == other.fileSizeBytes &&
          fileHash == other.fileHash &&
          groupId == other.groupId &&
          isPinned == other.isPinned &&
          totalChapters == other.totalChapters &&
          unreadCount == other.unreadCount &&
          lastChapterTitle == other.lastChapterTitle &&
          lastReadAt == other.lastReadAt &&
          latestChapterAt == other.latestChapterAt &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hashAll([
        id,
        sourceId,
        providerType,
        originBookUrl,
        tocUrl,
        title,
        author,
        coverPath,
        intro,
        localFilePath,
        fileEncoding,
        fileSizeBytes,
        fileHash,
        groupId,
        isPinned,
        totalChapters,
        unreadCount,
        lastChapterTitle,
        lastReadAt,
        latestChapterAt,
        createdAt,
        updatedAt,
      ]);
}
