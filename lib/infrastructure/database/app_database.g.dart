// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BookGroupsTable extends BookGroups
    with TableInfo<$BookGroupsTable, BookGroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    sortOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookGroupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookGroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookGroupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BookGroupsTable createAlias(String alias) {
    return $BookGroupsTable(attachedDatabase, alias);
  }
}

class BookGroupRow extends DataClass implements Insertable<BookGroupRow> {
  final String id;
  final String name;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  const BookGroupRow({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BookGroupsCompanion toCompanion(bool nullToAbsent) {
    return BookGroupsCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookGroupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookGroupRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  BookGroupRow copyWith({
    String? id,
    String? name,
    int? sortOrder,
    int? createdAt,
    int? updatedAt,
  }) => BookGroupRow(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookGroupRow copyWithCompanion(BookGroupsCompanion data) {
    return BookGroupRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookGroupRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortOrder, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookGroupRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BookGroupsCompanion extends UpdateCompanion<BookGroupRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const BookGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookGroupsCompanion.insert({
    required String id,
    required String name,
    this.sortOrder = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookGroupRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookGroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return BookGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BooksTable extends Books with TableInfo<$BooksTable, BookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _providerTypeMeta = const VerificationMeta(
    'providerType',
  );
  @override
  late final GeneratedColumn<String> providerType = GeneratedColumn<String>(
    'provider_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originBookUrlMeta = const VerificationMeta(
    'originBookUrl',
  );
  @override
  late final GeneratedColumn<String> originBookUrl = GeneratedColumn<String>(
    'origin_book_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tocUrlMeta = const VerificationMeta('tocUrl');
  @override
  late final GeneratedColumn<String> tocUrl = GeneratedColumn<String>(
    'toc_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _introMeta = const VerificationMeta('intro');
  @override
  late final GeneratedColumn<String> intro = GeneratedColumn<String>(
    'intro',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileEncodingMeta = const VerificationMeta(
    'fileEncoding',
  );
  @override
  late final GeneratedColumn<String> fileEncoding = GeneratedColumn<String>(
    'file_encoding',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeBytesMeta = const VerificationMeta(
    'fileSizeBytes',
  );
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
    'file_size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileHashMeta = const VerificationMeta(
    'fileHash',
  );
  @override
  late final GeneratedColumn<String> fileHash = GeneratedColumn<String>(
    'file_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES book_groups (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _totalChaptersMeta = const VerificationMeta(
    'totalChapters',
  );
  @override
  late final GeneratedColumn<int> totalChapters = GeneratedColumn<int>(
    'total_chapters',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastChapterTitleMeta = const VerificationMeta(
    'lastChapterTitle',
  );
  @override
  late final GeneratedColumn<String> lastChapterTitle = GeneratedColumn<String>(
    'last_chapter_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<int> lastReadAt = GeneratedColumn<int>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latestChapterAtMeta = const VerificationMeta(
    'latestChapterAt',
  );
  @override
  late final GeneratedColumn<int> latestChapterAt = GeneratedColumn<int>(
    'latest_chapter_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
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
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('provider_type')) {
      context.handle(
        _providerTypeMeta,
        providerType.isAcceptableOrUnknown(
          data['provider_type']!,
          _providerTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_providerTypeMeta);
    }
    if (data.containsKey('origin_book_url')) {
      context.handle(
        _originBookUrlMeta,
        originBookUrl.isAcceptableOrUnknown(
          data['origin_book_url']!,
          _originBookUrlMeta,
        ),
      );
    }
    if (data.containsKey('toc_url')) {
      context.handle(
        _tocUrlMeta,
        tocUrl.isAcceptableOrUnknown(data['toc_url']!, _tocUrlMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('intro')) {
      context.handle(
        _introMeta,
        intro.isAcceptableOrUnknown(data['intro']!, _introMeta),
      );
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    }
    if (data.containsKey('file_encoding')) {
      context.handle(
        _fileEncodingMeta,
        fileEncoding.isAcceptableOrUnknown(
          data['file_encoding']!,
          _fileEncodingMeta,
        ),
      );
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
        _fileSizeBytesMeta,
        fileSizeBytes.isAcceptableOrUnknown(
          data['file_size_bytes']!,
          _fileSizeBytesMeta,
        ),
      );
    }
    if (data.containsKey('file_hash')) {
      context.handle(
        _fileHashMeta,
        fileHash.isAcceptableOrUnknown(data['file_hash']!, _fileHashMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('total_chapters')) {
      context.handle(
        _totalChaptersMeta,
        totalChapters.isAcceptableOrUnknown(
          data['total_chapters']!,
          _totalChaptersMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('last_chapter_title')) {
      context.handle(
        _lastChapterTitleMeta,
        lastChapterTitle.isAcceptableOrUnknown(
          data['last_chapter_title']!,
          _lastChapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    if (data.containsKey('latest_chapter_at')) {
      context.handle(
        _latestChapterAtMeta,
        latestChapterAt.isAcceptableOrUnknown(
          data['latest_chapter_at']!,
          _latestChapterAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      providerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_type'],
      )!,
      originBookUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_book_url'],
      ),
      tocUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}toc_url'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      )!,
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      intro: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intro'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      ),
      fileEncoding: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_encoding'],
      ),
      fileSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size_bytes'],
      ),
      fileHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_hash'],
      ),
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      totalChapters: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_chapters'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      lastChapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_chapter_title'],
      )!,
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_at'],
      ),
      latestChapterAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latest_chapter_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class BookRow extends DataClass implements Insertable<BookRow> {
  final String id;
  final String? sourceId;
  final String providerType;
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
  final int? lastReadAt;
  final int? latestChapterAt;
  final int createdAt;
  final int updatedAt;
  const BookRow({
    required this.id,
    this.sourceId,
    required this.providerType,
    this.originBookUrl,
    this.tocUrl,
    required this.title,
    required this.author,
    this.coverPath,
    required this.intro,
    this.localFilePath,
    this.fileEncoding,
    this.fileSizeBytes,
    this.fileHash,
    this.groupId,
    required this.isPinned,
    required this.totalChapters,
    required this.unreadCount,
    required this.lastChapterTitle,
    this.lastReadAt,
    this.latestChapterAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    map['provider_type'] = Variable<String>(providerType);
    if (!nullToAbsent || originBookUrl != null) {
      map['origin_book_url'] = Variable<String>(originBookUrl);
    }
    if (!nullToAbsent || tocUrl != null) {
      map['toc_url'] = Variable<String>(tocUrl);
    }
    map['title'] = Variable<String>(title);
    map['author'] = Variable<String>(author);
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['intro'] = Variable<String>(intro);
    if (!nullToAbsent || localFilePath != null) {
      map['local_file_path'] = Variable<String>(localFilePath);
    }
    if (!nullToAbsent || fileEncoding != null) {
      map['file_encoding'] = Variable<String>(fileEncoding);
    }
    if (!nullToAbsent || fileSizeBytes != null) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    }
    if (!nullToAbsent || fileHash != null) {
      map['file_hash'] = Variable<String>(fileHash);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    map['total_chapters'] = Variable<int>(totalChapters);
    map['unread_count'] = Variable<int>(unreadCount);
    map['last_chapter_title'] = Variable<String>(lastChapterTitle);
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<int>(lastReadAt);
    }
    if (!nullToAbsent || latestChapterAt != null) {
      map['latest_chapter_at'] = Variable<int>(latestChapterAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      providerType: Value(providerType),
      originBookUrl: originBookUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(originBookUrl),
      tocUrl: tocUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(tocUrl),
      title: Value(title),
      author: Value(author),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      intro: Value(intro),
      localFilePath: localFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(localFilePath),
      fileEncoding: fileEncoding == null && nullToAbsent
          ? const Value.absent()
          : Value(fileEncoding),
      fileSizeBytes: fileSizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSizeBytes),
      fileHash: fileHash == null && nullToAbsent
          ? const Value.absent()
          : Value(fileHash),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      isPinned: Value(isPinned),
      totalChapters: Value(totalChapters),
      unreadCount: Value(unreadCount),
      lastChapterTitle: Value(lastChapterTitle),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      latestChapterAt: latestChapterAt == null && nullToAbsent
          ? const Value.absent()
          : Value(latestChapterAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookRow(
      id: serializer.fromJson<String>(json['id']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      providerType: serializer.fromJson<String>(json['providerType']),
      originBookUrl: serializer.fromJson<String?>(json['originBookUrl']),
      tocUrl: serializer.fromJson<String?>(json['tocUrl']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String>(json['author']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      intro: serializer.fromJson<String>(json['intro']),
      localFilePath: serializer.fromJson<String?>(json['localFilePath']),
      fileEncoding: serializer.fromJson<String?>(json['fileEncoding']),
      fileSizeBytes: serializer.fromJson<int?>(json['fileSizeBytes']),
      fileHash: serializer.fromJson<String?>(json['fileHash']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      totalChapters: serializer.fromJson<int>(json['totalChapters']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      lastChapterTitle: serializer.fromJson<String>(json['lastChapterTitle']),
      lastReadAt: serializer.fromJson<int?>(json['lastReadAt']),
      latestChapterAt: serializer.fromJson<int?>(json['latestChapterAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceId': serializer.toJson<String?>(sourceId),
      'providerType': serializer.toJson<String>(providerType),
      'originBookUrl': serializer.toJson<String?>(originBookUrl),
      'tocUrl': serializer.toJson<String?>(tocUrl),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String>(author),
      'coverPath': serializer.toJson<String?>(coverPath),
      'intro': serializer.toJson<String>(intro),
      'localFilePath': serializer.toJson<String?>(localFilePath),
      'fileEncoding': serializer.toJson<String?>(fileEncoding),
      'fileSizeBytes': serializer.toJson<int?>(fileSizeBytes),
      'fileHash': serializer.toJson<String?>(fileHash),
      'groupId': serializer.toJson<String?>(groupId),
      'isPinned': serializer.toJson<bool>(isPinned),
      'totalChapters': serializer.toJson<int>(totalChapters),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'lastChapterTitle': serializer.toJson<String>(lastChapterTitle),
      'lastReadAt': serializer.toJson<int?>(lastReadAt),
      'latestChapterAt': serializer.toJson<int?>(latestChapterAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  BookRow copyWith({
    String? id,
    Value<String?> sourceId = const Value.absent(),
    String? providerType,
    Value<String?> originBookUrl = const Value.absent(),
    Value<String?> tocUrl = const Value.absent(),
    String? title,
    String? author,
    Value<String?> coverPath = const Value.absent(),
    String? intro,
    Value<String?> localFilePath = const Value.absent(),
    Value<String?> fileEncoding = const Value.absent(),
    Value<int?> fileSizeBytes = const Value.absent(),
    Value<String?> fileHash = const Value.absent(),
    Value<String?> groupId = const Value.absent(),
    bool? isPinned,
    int? totalChapters,
    int? unreadCount,
    String? lastChapterTitle,
    Value<int?> lastReadAt = const Value.absent(),
    Value<int?> latestChapterAt = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => BookRow(
    id: id ?? this.id,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    providerType: providerType ?? this.providerType,
    originBookUrl: originBookUrl.present
        ? originBookUrl.value
        : this.originBookUrl,
    tocUrl: tocUrl.present ? tocUrl.value : this.tocUrl,
    title: title ?? this.title,
    author: author ?? this.author,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    intro: intro ?? this.intro,
    localFilePath: localFilePath.present
        ? localFilePath.value
        : this.localFilePath,
    fileEncoding: fileEncoding.present ? fileEncoding.value : this.fileEncoding,
    fileSizeBytes: fileSizeBytes.present
        ? fileSizeBytes.value
        : this.fileSizeBytes,
    fileHash: fileHash.present ? fileHash.value : this.fileHash,
    groupId: groupId.present ? groupId.value : this.groupId,
    isPinned: isPinned ?? this.isPinned,
    totalChapters: totalChapters ?? this.totalChapters,
    unreadCount: unreadCount ?? this.unreadCount,
    lastChapterTitle: lastChapterTitle ?? this.lastChapterTitle,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    latestChapterAt: latestChapterAt.present
        ? latestChapterAt.value
        : this.latestChapterAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookRow copyWithCompanion(BooksCompanion data) {
    return BookRow(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      providerType: data.providerType.present
          ? data.providerType.value
          : this.providerType,
      originBookUrl: data.originBookUrl.present
          ? data.originBookUrl.value
          : this.originBookUrl,
      tocUrl: data.tocUrl.present ? data.tocUrl.value : this.tocUrl,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      intro: data.intro.present ? data.intro.value : this.intro,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      fileEncoding: data.fileEncoding.present
          ? data.fileEncoding.value
          : this.fileEncoding,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      fileHash: data.fileHash.present ? data.fileHash.value : this.fileHash,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      totalChapters: data.totalChapters.present
          ? data.totalChapters.value
          : this.totalChapters,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      lastChapterTitle: data.lastChapterTitle.present
          ? data.lastChapterTitle.value
          : this.lastChapterTitle,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      latestChapterAt: data.latestChapterAt.present
          ? data.latestChapterAt.value
          : this.latestChapterAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookRow(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('providerType: $providerType, ')
          ..write('originBookUrl: $originBookUrl, ')
          ..write('tocUrl: $tocUrl, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('coverPath: $coverPath, ')
          ..write('intro: $intro, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('fileEncoding: $fileEncoding, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('fileHash: $fileHash, ')
          ..write('groupId: $groupId, ')
          ..write('isPinned: $isPinned, ')
          ..write('totalChapters: $totalChapters, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastChapterTitle: $lastChapterTitle, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('latestChapterAt: $latestChapterAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

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
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookRow &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.providerType == this.providerType &&
          other.originBookUrl == this.originBookUrl &&
          other.tocUrl == this.tocUrl &&
          other.title == this.title &&
          other.author == this.author &&
          other.coverPath == this.coverPath &&
          other.intro == this.intro &&
          other.localFilePath == this.localFilePath &&
          other.fileEncoding == this.fileEncoding &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.fileHash == this.fileHash &&
          other.groupId == this.groupId &&
          other.isPinned == this.isPinned &&
          other.totalChapters == this.totalChapters &&
          other.unreadCount == this.unreadCount &&
          other.lastChapterTitle == this.lastChapterTitle &&
          other.lastReadAt == this.lastReadAt &&
          other.latestChapterAt == this.latestChapterAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BooksCompanion extends UpdateCompanion<BookRow> {
  final Value<String> id;
  final Value<String?> sourceId;
  final Value<String> providerType;
  final Value<String?> originBookUrl;
  final Value<String?> tocUrl;
  final Value<String> title;
  final Value<String> author;
  final Value<String?> coverPath;
  final Value<String> intro;
  final Value<String?> localFilePath;
  final Value<String?> fileEncoding;
  final Value<int?> fileSizeBytes;
  final Value<String?> fileHash;
  final Value<String?> groupId;
  final Value<bool> isPinned;
  final Value<int> totalChapters;
  final Value<int> unreadCount;
  final Value<String> lastChapterTitle;
  final Value<int?> lastReadAt;
  final Value<int?> latestChapterAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.providerType = const Value.absent(),
    this.originBookUrl = const Value.absent(),
    this.tocUrl = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.intro = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.fileEncoding = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.groupId = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.totalChapters = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastChapterTitle = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.latestChapterAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    this.sourceId = const Value.absent(),
    required String providerType,
    this.originBookUrl = const Value.absent(),
    this.tocUrl = const Value.absent(),
    required String title,
    this.author = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.intro = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.fileEncoding = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.fileHash = const Value.absent(),
    this.groupId = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.totalChapters = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastChapterTitle = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.latestChapterAt = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       providerType = Value(providerType),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookRow> custom({
    Expression<String>? id,
    Expression<String>? sourceId,
    Expression<String>? providerType,
    Expression<String>? originBookUrl,
    Expression<String>? tocUrl,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? coverPath,
    Expression<String>? intro,
    Expression<String>? localFilePath,
    Expression<String>? fileEncoding,
    Expression<int>? fileSizeBytes,
    Expression<String>? fileHash,
    Expression<String>? groupId,
    Expression<bool>? isPinned,
    Expression<int>? totalChapters,
    Expression<int>? unreadCount,
    Expression<String>? lastChapterTitle,
    Expression<int>? lastReadAt,
    Expression<int>? latestChapterAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (providerType != null) 'provider_type': providerType,
      if (originBookUrl != null) 'origin_book_url': originBookUrl,
      if (tocUrl != null) 'toc_url': tocUrl,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (coverPath != null) 'cover_path': coverPath,
      if (intro != null) 'intro': intro,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (fileEncoding != null) 'file_encoding': fileEncoding,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (fileHash != null) 'file_hash': fileHash,
      if (groupId != null) 'group_id': groupId,
      if (isPinned != null) 'is_pinned': isPinned,
      if (totalChapters != null) 'total_chapters': totalChapters,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (lastChapterTitle != null) 'last_chapter_title': lastChapterTitle,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (latestChapterAt != null) 'latest_chapter_at': latestChapterAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String?>? sourceId,
    Value<String>? providerType,
    Value<String?>? originBookUrl,
    Value<String?>? tocUrl,
    Value<String>? title,
    Value<String>? author,
    Value<String?>? coverPath,
    Value<String>? intro,
    Value<String?>? localFilePath,
    Value<String?>? fileEncoding,
    Value<int?>? fileSizeBytes,
    Value<String?>? fileHash,
    Value<String?>? groupId,
    Value<bool>? isPinned,
    Value<int>? totalChapters,
    Value<int>? unreadCount,
    Value<String>? lastChapterTitle,
    Value<int?>? lastReadAt,
    Value<int?>? latestChapterAt,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
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
      groupId: groupId ?? this.groupId,
      isPinned: isPinned ?? this.isPinned,
      totalChapters: totalChapters ?? this.totalChapters,
      unreadCount: unreadCount ?? this.unreadCount,
      lastChapterTitle: lastChapterTitle ?? this.lastChapterTitle,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      latestChapterAt: latestChapterAt ?? this.latestChapterAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (providerType.present) {
      map['provider_type'] = Variable<String>(providerType.value);
    }
    if (originBookUrl.present) {
      map['origin_book_url'] = Variable<String>(originBookUrl.value);
    }
    if (tocUrl.present) {
      map['toc_url'] = Variable<String>(tocUrl.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (intro.present) {
      map['intro'] = Variable<String>(intro.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (fileEncoding.present) {
      map['file_encoding'] = Variable<String>(fileEncoding.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (fileHash.present) {
      map['file_hash'] = Variable<String>(fileHash.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (totalChapters.present) {
      map['total_chapters'] = Variable<int>(totalChapters.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (lastChapterTitle.present) {
      map['last_chapter_title'] = Variable<String>(lastChapterTitle.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<int>(lastReadAt.value);
    }
    if (latestChapterAt.present) {
      map['latest_chapter_at'] = Variable<int>(latestChapterAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('providerType: $providerType, ')
          ..write('originBookUrl: $originBookUrl, ')
          ..write('tocUrl: $tocUrl, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('coverPath: $coverPath, ')
          ..write('intro: $intro, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('fileEncoding: $fileEncoding, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('fileHash: $fileHash, ')
          ..write('groupId: $groupId, ')
          ..write('isPinned: $isPinned, ')
          ..write('totalChapters: $totalChapters, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastChapterTitle: $lastChapterTitle, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('latestChapterAt: $latestChapterAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChaptersTable extends Chapters
    with TableInfo<$ChaptersTable, ChapterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteStartMeta = const VerificationMeta(
    'byteStart',
  );
  @override
  late final GeneratedColumn<int> byteStart = GeneratedColumn<int>(
    'byte_start',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteEndMeta = const VerificationMeta(
    'byteEnd',
  );
  @override
  late final GeneratedColumn<int> byteEnd = GeneratedColumn<int>(
    'byte_end',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _epubHrefMeta = const VerificationMeta(
    'epubHref',
  );
  @override
  late final GeneratedColumn<String> epubHref = GeneratedColumn<String>(
    'epub_href',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isCachedMeta = const VerificationMeta(
    'isCached',
  );
  @override
  late final GeneratedColumn<bool> isCached = GeneratedColumn<bool>(
    'is_cached',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_cached" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wordCountMeta = const VerificationMeta(
    'wordCount',
  );
  @override
  late final GeneratedColumn<int> wordCount = GeneratedColumn<int>(
    'word_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    chapterIndex,
    title,
    url,
    byteStart,
    byteEnd,
    epubHref,
    isCached,
    cacheKey,
    wordCount,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapters';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChapterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterIndexMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('byte_start')) {
      context.handle(
        _byteStartMeta,
        byteStart.isAcceptableOrUnknown(data['byte_start']!, _byteStartMeta),
      );
    }
    if (data.containsKey('byte_end')) {
      context.handle(
        _byteEndMeta,
        byteEnd.isAcceptableOrUnknown(data['byte_end']!, _byteEndMeta),
      );
    }
    if (data.containsKey('epub_href')) {
      context.handle(
        _epubHrefMeta,
        epubHref.isAcceptableOrUnknown(data['epub_href']!, _epubHrefMeta),
      );
    }
    if (data.containsKey('is_cached')) {
      context.handle(
        _isCachedMeta,
        isCached.isAcceptableOrUnknown(data['is_cached']!, _isCachedMeta),
      );
    }
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    }
    if (data.containsKey('word_count')) {
      context.handle(
        _wordCountMeta,
        wordCount.isAcceptableOrUnknown(data['word_count']!, _wordCountMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChapterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChapterRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      byteStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_start'],
      ),
      byteEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_end'],
      ),
      epubHref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}epub_href'],
      ),
      isCached: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_cached'],
      )!,
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      ),
      wordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class ChapterRow extends DataClass implements Insertable<ChapterRow> {
  final int id;
  final String bookId;
  final int chapterIndex;
  final String title;
  final String? url;
  final int? byteStart;
  final int? byteEnd;
  final String? epubHref;
  final bool isCached;
  final String? cacheKey;
  final int wordCount;
  final int updatedAt;
  const ChapterRow({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.title,
    this.url,
    this.byteStart,
    this.byteEnd,
    this.epubHref,
    required this.isCached,
    this.cacheKey,
    required this.wordCount,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<String>(bookId);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || byteStart != null) {
      map['byte_start'] = Variable<int>(byteStart);
    }
    if (!nullToAbsent || byteEnd != null) {
      map['byte_end'] = Variable<int>(byteEnd);
    }
    if (!nullToAbsent || epubHref != null) {
      map['epub_href'] = Variable<String>(epubHref);
    }
    map['is_cached'] = Variable<bool>(isCached);
    if (!nullToAbsent || cacheKey != null) {
      map['cache_key'] = Variable<String>(cacheKey);
    }
    map['word_count'] = Variable<int>(wordCount);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      bookId: Value(bookId),
      chapterIndex: Value(chapterIndex),
      title: Value(title),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      byteStart: byteStart == null && nullToAbsent
          ? const Value.absent()
          : Value(byteStart),
      byteEnd: byteEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(byteEnd),
      epubHref: epubHref == null && nullToAbsent
          ? const Value.absent()
          : Value(epubHref),
      isCached: Value(isCached),
      cacheKey: cacheKey == null && nullToAbsent
          ? const Value.absent()
          : Value(cacheKey),
      wordCount: Value(wordCount),
      updatedAt: Value(updatedAt),
    );
  }

  factory ChapterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChapterRow(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      title: serializer.fromJson<String>(json['title']),
      url: serializer.fromJson<String?>(json['url']),
      byteStart: serializer.fromJson<int?>(json['byteStart']),
      byteEnd: serializer.fromJson<int?>(json['byteEnd']),
      epubHref: serializer.fromJson<String?>(json['epubHref']),
      isCached: serializer.fromJson<bool>(json['isCached']),
      cacheKey: serializer.fromJson<String?>(json['cacheKey']),
      wordCount: serializer.fromJson<int>(json['wordCount']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<String>(bookId),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'title': serializer.toJson<String>(title),
      'url': serializer.toJson<String?>(url),
      'byteStart': serializer.toJson<int?>(byteStart),
      'byteEnd': serializer.toJson<int?>(byteEnd),
      'epubHref': serializer.toJson<String?>(epubHref),
      'isCached': serializer.toJson<bool>(isCached),
      'cacheKey': serializer.toJson<String?>(cacheKey),
      'wordCount': serializer.toJson<int>(wordCount),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ChapterRow copyWith({
    int? id,
    String? bookId,
    int? chapterIndex,
    String? title,
    Value<String?> url = const Value.absent(),
    Value<int?> byteStart = const Value.absent(),
    Value<int?> byteEnd = const Value.absent(),
    Value<String?> epubHref = const Value.absent(),
    bool? isCached,
    Value<String?> cacheKey = const Value.absent(),
    int? wordCount,
    int? updatedAt,
  }) => ChapterRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    title: title ?? this.title,
    url: url.present ? url.value : this.url,
    byteStart: byteStart.present ? byteStart.value : this.byteStart,
    byteEnd: byteEnd.present ? byteEnd.value : this.byteEnd,
    epubHref: epubHref.present ? epubHref.value : this.epubHref,
    isCached: isCached ?? this.isCached,
    cacheKey: cacheKey.present ? cacheKey.value : this.cacheKey,
    wordCount: wordCount ?? this.wordCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ChapterRow copyWithCompanion(ChaptersCompanion data) {
    return ChapterRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      title: data.title.present ? data.title.value : this.title,
      url: data.url.present ? data.url.value : this.url,
      byteStart: data.byteStart.present ? data.byteStart.value : this.byteStart,
      byteEnd: data.byteEnd.present ? data.byteEnd.value : this.byteEnd,
      epubHref: data.epubHref.present ? data.epubHref.value : this.epubHref,
      isCached: data.isCached.present ? data.isCached.value : this.isCached,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      wordCount: data.wordCount.present ? data.wordCount.value : this.wordCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChapterRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('byteStart: $byteStart, ')
          ..write('byteEnd: $byteEnd, ')
          ..write('epubHref: $epubHref, ')
          ..write('isCached: $isCached, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('wordCount: $wordCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    chapterIndex,
    title,
    url,
    byteStart,
    byteEnd,
    epubHref,
    isCached,
    cacheKey,
    wordCount,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChapterRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.chapterIndex == this.chapterIndex &&
          other.title == this.title &&
          other.url == this.url &&
          other.byteStart == this.byteStart &&
          other.byteEnd == this.byteEnd &&
          other.epubHref == this.epubHref &&
          other.isCached == this.isCached &&
          other.cacheKey == this.cacheKey &&
          other.wordCount == this.wordCount &&
          other.updatedAt == this.updatedAt);
}

class ChaptersCompanion extends UpdateCompanion<ChapterRow> {
  final Value<int> id;
  final Value<String> bookId;
  final Value<int> chapterIndex;
  final Value<String> title;
  final Value<String?> url;
  final Value<int?> byteStart;
  final Value<int?> byteEnd;
  final Value<String?> epubHref;
  final Value<bool> isCached;
  final Value<String?> cacheKey;
  final Value<int> wordCount;
  final Value<int> updatedAt;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.byteStart = const Value.absent(),
    this.byteEnd = const Value.absent(),
    this.epubHref = const Value.absent(),
    this.isCached = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ChaptersCompanion.insert({
    this.id = const Value.absent(),
    required String bookId,
    required int chapterIndex,
    required String title,
    this.url = const Value.absent(),
    this.byteStart = const Value.absent(),
    this.byteEnd = const Value.absent(),
    this.epubHref = const Value.absent(),
    this.isCached = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.wordCount = const Value.absent(),
    required int updatedAt,
  }) : bookId = Value(bookId),
       chapterIndex = Value(chapterIndex),
       title = Value(title),
       updatedAt = Value(updatedAt);
  static Insertable<ChapterRow> custom({
    Expression<int>? id,
    Expression<String>? bookId,
    Expression<int>? chapterIndex,
    Expression<String>? title,
    Expression<String>? url,
    Expression<int>? byteStart,
    Expression<int>? byteEnd,
    Expression<String>? epubHref,
    Expression<bool>? isCached,
    Expression<String>? cacheKey,
    Expression<int>? wordCount,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (title != null) 'title': title,
      if (url != null) 'url': url,
      if (byteStart != null) 'byte_start': byteStart,
      if (byteEnd != null) 'byte_end': byteEnd,
      if (epubHref != null) 'epub_href': epubHref,
      if (isCached != null) 'is_cached': isCached,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (wordCount != null) 'word_count': wordCount,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ChaptersCompanion copyWith({
    Value<int>? id,
    Value<String>? bookId,
    Value<int>? chapterIndex,
    Value<String>? title,
    Value<String?>? url,
    Value<int?>? byteStart,
    Value<int?>? byteEnd,
    Value<String?>? epubHref,
    Value<bool>? isCached,
    Value<String?>? cacheKey,
    Value<int>? wordCount,
    Value<int>? updatedAt,
  }) {
    return ChaptersCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      title: title ?? this.title,
      url: url ?? this.url,
      byteStart: byteStart ?? this.byteStart,
      byteEnd: byteEnd ?? this.byteEnd,
      epubHref: epubHref ?? this.epubHref,
      isCached: isCached ?? this.isCached,
      cacheKey: cacheKey ?? this.cacheKey,
      wordCount: wordCount ?? this.wordCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (byteStart.present) {
      map['byte_start'] = Variable<int>(byteStart.value);
    }
    if (byteEnd.present) {
      map['byte_end'] = Variable<int>(byteEnd.value);
    }
    if (epubHref.present) {
      map['epub_href'] = Variable<String>(epubHref.value);
    }
    if (isCached.present) {
      map['is_cached'] = Variable<bool>(isCached.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (wordCount.present) {
      map['word_count'] = Variable<int>(wordCount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('byteStart: $byteStart, ')
          ..write('byteEnd: $byteEnd, ')
          ..write('epubHref: $epubHref, ')
          ..write('isCached: $isCached, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('wordCount: $wordCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ReadingProgressRecordsTable extends ReadingProgressRecords
    with TableInfo<$ReadingProgressRecordsTable, ReadingProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'char_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterTitleSnapshotMeta =
      const VerificationMeta('chapterTitleSnapshot');
  @override
  late final GeneratedColumn<String> chapterTitleSnapshot =
      GeneratedColumn<String>(
        'chapter_title_snapshot',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  static const VerificationMeta _progressPercentMeta = const VerificationMeta(
    'progressPercent',
  );
  @override
  late final GeneratedColumn<double> progressPercent = GeneratedColumn<double>(
    'progress_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _readingDurationSecMeta =
      const VerificationMeta('readingDurationSec');
  @override
  late final GeneratedColumn<int> readingDurationSec = GeneratedColumn<int>(
    'reading_duration_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    chapterIndex,
    charOffset,
    chapterTitleSnapshot,
    progressPercent,
    readingDurationSec,
    updatedAt,
    deviceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('char_offset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['char_offset']!, _charOffsetMeta),
      );
    }
    if (data.containsKey('chapter_title_snapshot')) {
      context.handle(
        _chapterTitleSnapshotMeta,
        chapterTitleSnapshot.isAcceptableOrUnknown(
          data['chapter_title_snapshot']!,
          _chapterTitleSnapshotMeta,
        ),
      );
    }
    if (data.containsKey('progress_percent')) {
      context.handle(
        _progressPercentMeta,
        progressPercent.isAcceptableOrUnknown(
          data['progress_percent']!,
          _progressPercentMeta,
        ),
      );
    }
    if (data.containsKey('reading_duration_sec')) {
      context.handle(
        _readingDurationSecMeta,
        readingDurationSec.isAcceptableOrUnknown(
          data['reading_duration_sec']!,
          _readingDurationSecMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  ReadingProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingProgressRow(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      charOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_offset'],
      )!,
      chapterTitleSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title_snapshot'],
      )!,
      progressPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress_percent'],
      )!,
      readingDurationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reading_duration_sec'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
    );
  }

  @override
  $ReadingProgressRecordsTable createAlias(String alias) {
    return $ReadingProgressRecordsTable(attachedDatabase, alias);
  }
}

class ReadingProgressRow extends DataClass
    implements Insertable<ReadingProgressRow> {
  final String bookId;
  final int chapterIndex;
  final int charOffset;
  final String chapterTitleSnapshot;
  final double progressPercent;
  final int readingDurationSec;
  final int updatedAt;
  final String deviceId;
  const ReadingProgressRow({
    required this.bookId,
    required this.chapterIndex,
    required this.charOffset,
    required this.chapterTitleSnapshot,
    required this.progressPercent,
    required this.readingDurationSec,
    required this.updatedAt,
    required this.deviceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['char_offset'] = Variable<int>(charOffset);
    map['chapter_title_snapshot'] = Variable<String>(chapterTitleSnapshot);
    map['progress_percent'] = Variable<double>(progressPercent);
    map['reading_duration_sec'] = Variable<int>(readingDurationSec);
    map['updated_at'] = Variable<int>(updatedAt);
    map['device_id'] = Variable<String>(deviceId);
    return map;
  }

  ReadingProgressRecordsCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressRecordsCompanion(
      bookId: Value(bookId),
      chapterIndex: Value(chapterIndex),
      charOffset: Value(charOffset),
      chapterTitleSnapshot: Value(chapterTitleSnapshot),
      progressPercent: Value(progressPercent),
      readingDurationSec: Value(readingDurationSec),
      updatedAt: Value(updatedAt),
      deviceId: Value(deviceId),
    );
  }

  factory ReadingProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingProgressRow(
      bookId: serializer.fromJson<String>(json['bookId']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      charOffset: serializer.fromJson<int>(json['charOffset']),
      chapterTitleSnapshot: serializer.fromJson<String>(
        json['chapterTitleSnapshot'],
      ),
      progressPercent: serializer.fromJson<double>(json['progressPercent']),
      readingDurationSec: serializer.fromJson<int>(json['readingDurationSec']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'charOffset': serializer.toJson<int>(charOffset),
      'chapterTitleSnapshot': serializer.toJson<String>(chapterTitleSnapshot),
      'progressPercent': serializer.toJson<double>(progressPercent),
      'readingDurationSec': serializer.toJson<int>(readingDurationSec),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deviceId': serializer.toJson<String>(deviceId),
    };
  }

  ReadingProgressRow copyWith({
    String? bookId,
    int? chapterIndex,
    int? charOffset,
    String? chapterTitleSnapshot,
    double? progressPercent,
    int? readingDurationSec,
    int? updatedAt,
    String? deviceId,
  }) => ReadingProgressRow(
    bookId: bookId ?? this.bookId,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    charOffset: charOffset ?? this.charOffset,
    chapterTitleSnapshot: chapterTitleSnapshot ?? this.chapterTitleSnapshot,
    progressPercent: progressPercent ?? this.progressPercent,
    readingDurationSec: readingDurationSec ?? this.readingDurationSec,
    updatedAt: updatedAt ?? this.updatedAt,
    deviceId: deviceId ?? this.deviceId,
  );
  ReadingProgressRow copyWithCompanion(ReadingProgressRecordsCompanion data) {
    return ReadingProgressRow(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      charOffset: data.charOffset.present
          ? data.charOffset.value
          : this.charOffset,
      chapterTitleSnapshot: data.chapterTitleSnapshot.present
          ? data.chapterTitleSnapshot.value
          : this.chapterTitleSnapshot,
      progressPercent: data.progressPercent.present
          ? data.progressPercent.value
          : this.progressPercent,
      readingDurationSec: data.readingDurationSec.present
          ? data.readingDurationSec.value
          : this.readingDurationSec,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressRow(')
          ..write('bookId: $bookId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('charOffset: $charOffset, ')
          ..write('chapterTitleSnapshot: $chapterTitleSnapshot, ')
          ..write('progressPercent: $progressPercent, ')
          ..write('readingDurationSec: $readingDurationSec, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId')
          ..write(')'))
        .toString();
  }

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
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingProgressRow &&
          other.bookId == this.bookId &&
          other.chapterIndex == this.chapterIndex &&
          other.charOffset == this.charOffset &&
          other.chapterTitleSnapshot == this.chapterTitleSnapshot &&
          other.progressPercent == this.progressPercent &&
          other.readingDurationSec == this.readingDurationSec &&
          other.updatedAt == this.updatedAt &&
          other.deviceId == this.deviceId);
}

class ReadingProgressRecordsCompanion
    extends UpdateCompanion<ReadingProgressRow> {
  final Value<String> bookId;
  final Value<int> chapterIndex;
  final Value<int> charOffset;
  final Value<String> chapterTitleSnapshot;
  final Value<double> progressPercent;
  final Value<int> readingDurationSec;
  final Value<int> updatedAt;
  final Value<String> deviceId;
  final Value<int> rowid;
  const ReadingProgressRecordsCompanion({
    this.bookId = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.chapterTitleSnapshot = const Value.absent(),
    this.progressPercent = const Value.absent(),
    this.readingDurationSec = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressRecordsCompanion.insert({
    required String bookId,
    this.chapterIndex = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.chapterTitleSnapshot = const Value.absent(),
    this.progressPercent = const Value.absent(),
    this.readingDurationSec = const Value.absent(),
    required int updatedAt,
    this.deviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingProgressRow> custom({
    Expression<String>? bookId,
    Expression<int>? chapterIndex,
    Expression<int>? charOffset,
    Expression<String>? chapterTitleSnapshot,
    Expression<double>? progressPercent,
    Expression<int>? readingDurationSec,
    Expression<int>? updatedAt,
    Expression<String>? deviceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (charOffset != null) 'char_offset': charOffset,
      if (chapterTitleSnapshot != null)
        'chapter_title_snapshot': chapterTitleSnapshot,
      if (progressPercent != null) 'progress_percent': progressPercent,
      if (readingDurationSec != null)
        'reading_duration_sec': readingDurationSec,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressRecordsCompanion copyWith({
    Value<String>? bookId,
    Value<int>? chapterIndex,
    Value<int>? charOffset,
    Value<String>? chapterTitleSnapshot,
    Value<double>? progressPercent,
    Value<int>? readingDurationSec,
    Value<int>? updatedAt,
    Value<String>? deviceId,
    Value<int>? rowid,
  }) {
    return ReadingProgressRecordsCompanion(
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      charOffset: charOffset ?? this.charOffset,
      chapterTitleSnapshot: chapterTitleSnapshot ?? this.chapterTitleSnapshot,
      progressPercent: progressPercent ?? this.progressPercent,
      readingDurationSec: readingDurationSec ?? this.readingDurationSec,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (charOffset.present) {
      map['char_offset'] = Variable<int>(charOffset.value);
    }
    if (chapterTitleSnapshot.present) {
      map['chapter_title_snapshot'] = Variable<String>(
        chapterTitleSnapshot.value,
      );
    }
    if (progressPercent.present) {
      map['progress_percent'] = Variable<double>(progressPercent.value);
    }
    if (readingDurationSec.present) {
      map['reading_duration_sec'] = Variable<int>(readingDurationSec.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressRecordsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('charOffset: $charOffset, ')
          ..write('chapterTitleSnapshot: $chapterTitleSnapshot, ')
          ..write('progressPercent: $progressPercent, ')
          ..write('readingDurationSec: $readingDurationSec, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, BookmarkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'char_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _excerptMeta = const VerificationMeta(
    'excerpt',
  );
  @override
  late final GeneratedColumn<String> excerpt = GeneratedColumn<String>(
    'excerpt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    chapterIndex,
    charOffset,
    excerpt,
    note,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookmarkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterIndexMeta);
    }
    if (data.containsKey('char_offset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['char_offset']!, _charOffsetMeta),
      );
    } else if (isInserting) {
      context.missing(_charOffsetMeta);
    }
    if (data.containsKey('excerpt')) {
      context.handle(
        _excerptMeta,
        excerpt.isAcceptableOrUnknown(data['excerpt']!, _excerptMeta),
      );
    } else if (isInserting) {
      context.missing(_excerptMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookmarkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookmarkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      charOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_offset'],
      )!,
      excerpt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excerpt'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

class BookmarkRow extends DataClass implements Insertable<BookmarkRow> {
  final String id;
  final String bookId;
  final int chapterIndex;
  final int charOffset;
  final String excerpt;
  final String note;
  final int createdAt;
  const BookmarkRow({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.charOffset,
    required this.excerpt,
    required this.note,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['char_offset'] = Variable<int>(charOffset);
    map['excerpt'] = Variable<String>(excerpt);
    map['note'] = Variable<String>(note);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  BookmarksCompanion toCompanion(bool nullToAbsent) {
    return BookmarksCompanion(
      id: Value(id),
      bookId: Value(bookId),
      chapterIndex: Value(chapterIndex),
      charOffset: Value(charOffset),
      excerpt: Value(excerpt),
      note: Value(note),
      createdAt: Value(createdAt),
    );
  }

  factory BookmarkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookmarkRow(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      charOffset: serializer.fromJson<int>(json['charOffset']),
      excerpt: serializer.fromJson<String>(json['excerpt']),
      note: serializer.fromJson<String>(json['note']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'charOffset': serializer.toJson<int>(charOffset),
      'excerpt': serializer.toJson<String>(excerpt),
      'note': serializer.toJson<String>(note),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  BookmarkRow copyWith({
    String? id,
    String? bookId,
    int? chapterIndex,
    int? charOffset,
    String? excerpt,
    String? note,
    int? createdAt,
  }) => BookmarkRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    charOffset: charOffset ?? this.charOffset,
    excerpt: excerpt ?? this.excerpt,
    note: note ?? this.note,
    createdAt: createdAt ?? this.createdAt,
  );
  BookmarkRow copyWithCompanion(BookmarksCompanion data) {
    return BookmarkRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      charOffset: data.charOffset.present
          ? data.charOffset.value
          : this.charOffset,
      excerpt: data.excerpt.present ? data.excerpt.value : this.excerpt,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookmarkRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('charOffset: $charOffset, ')
          ..write('excerpt: $excerpt, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    chapterIndex,
    charOffset,
    excerpt,
    note,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookmarkRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.chapterIndex == this.chapterIndex &&
          other.charOffset == this.charOffset &&
          other.excerpt == this.excerpt &&
          other.note == this.note &&
          other.createdAt == this.createdAt);
}

class BookmarksCompanion extends UpdateCompanion<BookmarkRow> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<int> chapterIndex;
  final Value<int> charOffset;
  final Value<String> excerpt;
  final Value<String> note;
  final Value<int> createdAt;
  final Value<int> rowid;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.excerpt = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required String id,
    required String bookId,
    required int chapterIndex,
    required int charOffset,
    required String excerpt,
    this.note = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       chapterIndex = Value(chapterIndex),
       charOffset = Value(charOffset),
       excerpt = Value(excerpt),
       createdAt = Value(createdAt);
  static Insertable<BookmarkRow> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<int>? chapterIndex,
    Expression<int>? charOffset,
    Expression<String>? excerpt,
    Expression<String>? note,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (charOffset != null) 'char_offset': charOffset,
      if (excerpt != null) 'excerpt': excerpt,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookmarksCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<int>? chapterIndex,
    Value<int>? charOffset,
    Value<String>? excerpt,
    Value<String>? note,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return BookmarksCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      charOffset: charOffset ?? this.charOffset,
      excerpt: excerpt ?? this.excerpt,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (charOffset.present) {
      map['char_offset'] = Variable<int>(charOffset.value);
    }
    if (excerpt.present) {
      map['excerpt'] = Variable<String>(excerpt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('charOffset: $charOffset, ')
          ..write('excerpt: $excerpt, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookSourcesTable extends BookSources
    with TableInfo<$BookSourcesTable, BookSourceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('默认'),
  );
  static const VerificationMeta _engineTypeMeta = const VerificationMeta(
    'engineType',
  );
  @override
  late final GeneratedColumn<String> engineType = GeneratedColumn<String>(
    'engine_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawDefinitionMeta = const VerificationMeta(
    'rawDefinition',
  );
  @override
  late final GeneratedColumn<String> rawDefinition = GeneratedColumn<String>(
    'raw_definition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<int> weight = GeneratedColumn<int>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _rateLimitMsMeta = const VerificationMeta(
    'rateLimitMs',
  );
  @override
  late final GeneratedColumn<int> rateLimitMs = GeneratedColumn<int>(
    'rate_limit_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(500),
  );
  static const VerificationMeta _lastCheckStatusMeta = const VerificationMeta(
    'lastCheckStatus',
  );
  @override
  late final GeneratedColumn<String> lastCheckStatus = GeneratedColumn<String>(
    'last_check_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _lastErrorSummaryMeta = const VerificationMeta(
    'lastErrorSummary',
  );
  @override
  late final GeneratedColumn<String> lastErrorSummary = GeneratedColumn<String>(
    'last_error_summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    groupName,
    engineType,
    baseUrl,
    rawDefinition,
    enabled,
    weight,
    rateLimitMs,
    lastCheckStatus,
    lastErrorSummary,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookSourceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    }
    if (data.containsKey('engine_type')) {
      context.handle(
        _engineTypeMeta,
        engineType.isAcceptableOrUnknown(data['engine_type']!, _engineTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_engineTypeMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('raw_definition')) {
      context.handle(
        _rawDefinitionMeta,
        rawDefinition.isAcceptableOrUnknown(
          data['raw_definition']!,
          _rawDefinitionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rawDefinitionMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('rate_limit_ms')) {
      context.handle(
        _rateLimitMsMeta,
        rateLimitMs.isAcceptableOrUnknown(
          data['rate_limit_ms']!,
          _rateLimitMsMeta,
        ),
      );
    }
    if (data.containsKey('last_check_status')) {
      context.handle(
        _lastCheckStatusMeta,
        lastCheckStatus.isAcceptableOrUnknown(
          data['last_check_status']!,
          _lastCheckStatusMeta,
        ),
      );
    }
    if (data.containsKey('last_error_summary')) {
      context.handle(
        _lastErrorSummaryMeta,
        lastErrorSummary.isAcceptableOrUnknown(
          data['last_error_summary']!,
          _lastErrorSummaryMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookSourceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookSourceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      )!,
      engineType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine_type'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      rawDefinition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_definition'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weight'],
      )!,
      rateLimitMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rate_limit_ms'],
      )!,
      lastCheckStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_check_status'],
      )!,
      lastErrorSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_summary'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BookSourcesTable createAlias(String alias) {
    return $BookSourcesTable(attachedDatabase, alias);
  }
}

class BookSourceRow extends DataClass implements Insertable<BookSourceRow> {
  final String id;
  final String name;
  final String groupName;
  final String engineType;
  final String baseUrl;
  final String rawDefinition;
  final bool enabled;
  final int weight;
  final int rateLimitMs;
  final String lastCheckStatus;
  final String? lastErrorSummary;
  final int createdAt;
  final int updatedAt;
  const BookSourceRow({
    required this.id,
    required this.name,
    required this.groupName,
    required this.engineType,
    required this.baseUrl,
    required this.rawDefinition,
    required this.enabled,
    required this.weight,
    required this.rateLimitMs,
    required this.lastCheckStatus,
    this.lastErrorSummary,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['group_name'] = Variable<String>(groupName);
    map['engine_type'] = Variable<String>(engineType);
    map['base_url'] = Variable<String>(baseUrl);
    map['raw_definition'] = Variable<String>(rawDefinition);
    map['enabled'] = Variable<bool>(enabled);
    map['weight'] = Variable<int>(weight);
    map['rate_limit_ms'] = Variable<int>(rateLimitMs);
    map['last_check_status'] = Variable<String>(lastCheckStatus);
    if (!nullToAbsent || lastErrorSummary != null) {
      map['last_error_summary'] = Variable<String>(lastErrorSummary);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BookSourcesCompanion toCompanion(bool nullToAbsent) {
    return BookSourcesCompanion(
      id: Value(id),
      name: Value(name),
      groupName: Value(groupName),
      engineType: Value(engineType),
      baseUrl: Value(baseUrl),
      rawDefinition: Value(rawDefinition),
      enabled: Value(enabled),
      weight: Value(weight),
      rateLimitMs: Value(rateLimitMs),
      lastCheckStatus: Value(lastCheckStatus),
      lastErrorSummary: lastErrorSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorSummary),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookSourceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookSourceRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      groupName: serializer.fromJson<String>(json['groupName']),
      engineType: serializer.fromJson<String>(json['engineType']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      rawDefinition: serializer.fromJson<String>(json['rawDefinition']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      weight: serializer.fromJson<int>(json['weight']),
      rateLimitMs: serializer.fromJson<int>(json['rateLimitMs']),
      lastCheckStatus: serializer.fromJson<String>(json['lastCheckStatus']),
      lastErrorSummary: serializer.fromJson<String?>(json['lastErrorSummary']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'groupName': serializer.toJson<String>(groupName),
      'engineType': serializer.toJson<String>(engineType),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'rawDefinition': serializer.toJson<String>(rawDefinition),
      'enabled': serializer.toJson<bool>(enabled),
      'weight': serializer.toJson<int>(weight),
      'rateLimitMs': serializer.toJson<int>(rateLimitMs),
      'lastCheckStatus': serializer.toJson<String>(lastCheckStatus),
      'lastErrorSummary': serializer.toJson<String?>(lastErrorSummary),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  BookSourceRow copyWith({
    String? id,
    String? name,
    String? groupName,
    String? engineType,
    String? baseUrl,
    String? rawDefinition,
    bool? enabled,
    int? weight,
    int? rateLimitMs,
    String? lastCheckStatus,
    Value<String?> lastErrorSummary = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => BookSourceRow(
    id: id ?? this.id,
    name: name ?? this.name,
    groupName: groupName ?? this.groupName,
    engineType: engineType ?? this.engineType,
    baseUrl: baseUrl ?? this.baseUrl,
    rawDefinition: rawDefinition ?? this.rawDefinition,
    enabled: enabled ?? this.enabled,
    weight: weight ?? this.weight,
    rateLimitMs: rateLimitMs ?? this.rateLimitMs,
    lastCheckStatus: lastCheckStatus ?? this.lastCheckStatus,
    lastErrorSummary: lastErrorSummary.present
        ? lastErrorSummary.value
        : this.lastErrorSummary,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookSourceRow copyWithCompanion(BookSourcesCompanion data) {
    return BookSourceRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      engineType: data.engineType.present
          ? data.engineType.value
          : this.engineType,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      rawDefinition: data.rawDefinition.present
          ? data.rawDefinition.value
          : this.rawDefinition,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      weight: data.weight.present ? data.weight.value : this.weight,
      rateLimitMs: data.rateLimitMs.present
          ? data.rateLimitMs.value
          : this.rateLimitMs,
      lastCheckStatus: data.lastCheckStatus.present
          ? data.lastCheckStatus.value
          : this.lastCheckStatus,
      lastErrorSummary: data.lastErrorSummary.present
          ? data.lastErrorSummary.value
          : this.lastErrorSummary,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookSourceRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('groupName: $groupName, ')
          ..write('engineType: $engineType, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('rawDefinition: $rawDefinition, ')
          ..write('enabled: $enabled, ')
          ..write('weight: $weight, ')
          ..write('rateLimitMs: $rateLimitMs, ')
          ..write('lastCheckStatus: $lastCheckStatus, ')
          ..write('lastErrorSummary: $lastErrorSummary, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    groupName,
    engineType,
    baseUrl,
    rawDefinition,
    enabled,
    weight,
    rateLimitMs,
    lastCheckStatus,
    lastErrorSummary,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookSourceRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.groupName == this.groupName &&
          other.engineType == this.engineType &&
          other.baseUrl == this.baseUrl &&
          other.rawDefinition == this.rawDefinition &&
          other.enabled == this.enabled &&
          other.weight == this.weight &&
          other.rateLimitMs == this.rateLimitMs &&
          other.lastCheckStatus == this.lastCheckStatus &&
          other.lastErrorSummary == this.lastErrorSummary &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BookSourcesCompanion extends UpdateCompanion<BookSourceRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> groupName;
  final Value<String> engineType;
  final Value<String> baseUrl;
  final Value<String> rawDefinition;
  final Value<bool> enabled;
  final Value<int> weight;
  final Value<int> rateLimitMs;
  final Value<String> lastCheckStatus;
  final Value<String?> lastErrorSummary;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const BookSourcesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.groupName = const Value.absent(),
    this.engineType = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.rawDefinition = const Value.absent(),
    this.enabled = const Value.absent(),
    this.weight = const Value.absent(),
    this.rateLimitMs = const Value.absent(),
    this.lastCheckStatus = const Value.absent(),
    this.lastErrorSummary = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookSourcesCompanion.insert({
    required String id,
    required String name,
    this.groupName = const Value.absent(),
    required String engineType,
    required String baseUrl,
    required String rawDefinition,
    this.enabled = const Value.absent(),
    this.weight = const Value.absent(),
    this.rateLimitMs = const Value.absent(),
    this.lastCheckStatus = const Value.absent(),
    this.lastErrorSummary = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       engineType = Value(engineType),
       baseUrl = Value(baseUrl),
       rawDefinition = Value(rawDefinition),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookSourceRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? groupName,
    Expression<String>? engineType,
    Expression<String>? baseUrl,
    Expression<String>? rawDefinition,
    Expression<bool>? enabled,
    Expression<int>? weight,
    Expression<int>? rateLimitMs,
    Expression<String>? lastCheckStatus,
    Expression<String>? lastErrorSummary,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (groupName != null) 'group_name': groupName,
      if (engineType != null) 'engine_type': engineType,
      if (baseUrl != null) 'base_url': baseUrl,
      if (rawDefinition != null) 'raw_definition': rawDefinition,
      if (enabled != null) 'enabled': enabled,
      if (weight != null) 'weight': weight,
      if (rateLimitMs != null) 'rate_limit_ms': rateLimitMs,
      if (lastCheckStatus != null) 'last_check_status': lastCheckStatus,
      if (lastErrorSummary != null) 'last_error_summary': lastErrorSummary,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookSourcesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? groupName,
    Value<String>? engineType,
    Value<String>? baseUrl,
    Value<String>? rawDefinition,
    Value<bool>? enabled,
    Value<int>? weight,
    Value<int>? rateLimitMs,
    Value<String>? lastCheckStatus,
    Value<String?>? lastErrorSummary,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return BookSourcesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      groupName: groupName ?? this.groupName,
      engineType: engineType ?? this.engineType,
      baseUrl: baseUrl ?? this.baseUrl,
      rawDefinition: rawDefinition ?? this.rawDefinition,
      enabled: enabled ?? this.enabled,
      weight: weight ?? this.weight,
      rateLimitMs: rateLimitMs ?? this.rateLimitMs,
      lastCheckStatus: lastCheckStatus ?? this.lastCheckStatus,
      lastErrorSummary: lastErrorSummary ?? this.lastErrorSummary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (engineType.present) {
      map['engine_type'] = Variable<String>(engineType.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (rawDefinition.present) {
      map['raw_definition'] = Variable<String>(rawDefinition.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (weight.present) {
      map['weight'] = Variable<int>(weight.value);
    }
    if (rateLimitMs.present) {
      map['rate_limit_ms'] = Variable<int>(rateLimitMs.value);
    }
    if (lastCheckStatus.present) {
      map['last_check_status'] = Variable<String>(lastCheckStatus.value);
    }
    if (lastErrorSummary.present) {
      map['last_error_summary'] = Variable<String>(lastErrorSummary.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookSourcesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('groupName: $groupName, ')
          ..write('engineType: $engineType, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('rawDefinition: $rawDefinition, ')
          ..write('enabled: $enabled, ')
          ..write('weight: $weight, ')
          ..write('rateLimitMs: $rateLimitMs, ')
          ..write('lastCheckStatus: $lastCheckStatus, ')
          ..write('lastErrorSummary: $lastErrorSummary, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReplaceRulesTable extends ReplaceRules
    with TableInfo<$ReplaceRulesTable, ReplaceRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReplaceRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('通用'),
  );
  static const VerificationMeta _patternMeta = const VerificationMeta(
    'pattern',
  );
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replacementMeta = const VerificationMeta(
    'replacement',
  );
  @override
  late final GeneratedColumn<String> replacement = GeneratedColumn<String>(
    'replacement',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isRegexMeta = const VerificationMeta(
    'isRegex',
  );
  @override
  late final GeneratedColumn<bool> isRegex = GeneratedColumn<bool>(
    'is_regex',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_regex" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _scopeTypeMeta = const VerificationMeta(
    'scopeType',
  );
  @override
  late final GeneratedColumn<String> scopeType = GeneratedColumn<String>(
    'scope_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('global'),
  );
  static const VerificationMeta _scopeTargetIdMeta = const VerificationMeta(
    'scopeTargetId',
  );
  @override
  late final GeneratedColumn<String> scopeTargetId = GeneratedColumn<String>(
    'scope_target_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    groupName,
    pattern,
    replacement,
    isRegex,
    scopeType,
    scopeTargetId,
    enabled,
    sortOrder,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'replace_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReplaceRuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    }
    if (data.containsKey('pattern')) {
      context.handle(
        _patternMeta,
        pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta),
      );
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('replacement')) {
      context.handle(
        _replacementMeta,
        replacement.isAcceptableOrUnknown(
          data['replacement']!,
          _replacementMeta,
        ),
      );
    }
    if (data.containsKey('is_regex')) {
      context.handle(
        _isRegexMeta,
        isRegex.isAcceptableOrUnknown(data['is_regex']!, _isRegexMeta),
      );
    }
    if (data.containsKey('scope_type')) {
      context.handle(
        _scopeTypeMeta,
        scopeType.isAcceptableOrUnknown(data['scope_type']!, _scopeTypeMeta),
      );
    }
    if (data.containsKey('scope_target_id')) {
      context.handle(
        _scopeTargetIdMeta,
        scopeTargetId.isAcceptableOrUnknown(
          data['scope_target_id']!,
          _scopeTargetIdMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReplaceRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReplaceRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      )!,
      pattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pattern'],
      )!,
      replacement: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replacement'],
      )!,
      isRegex: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_regex'],
      )!,
      scopeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_type'],
      )!,
      scopeTargetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_target_id'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReplaceRulesTable createAlias(String alias) {
    return $ReplaceRulesTable(attachedDatabase, alias);
  }
}

class ReplaceRuleRow extends DataClass implements Insertable<ReplaceRuleRow> {
  final String id;
  final String name;
  final String groupName;
  final String pattern;
  final String replacement;
  final bool isRegex;
  final String scopeType;
  final String? scopeTargetId;
  final bool enabled;
  final int sortOrder;
  final int updatedAt;
  const ReplaceRuleRow({
    required this.id,
    required this.name,
    required this.groupName,
    required this.pattern,
    required this.replacement,
    required this.isRegex,
    required this.scopeType,
    this.scopeTargetId,
    required this.enabled,
    required this.sortOrder,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['group_name'] = Variable<String>(groupName);
    map['pattern'] = Variable<String>(pattern);
    map['replacement'] = Variable<String>(replacement);
    map['is_regex'] = Variable<bool>(isRegex);
    map['scope_type'] = Variable<String>(scopeType);
    if (!nullToAbsent || scopeTargetId != null) {
      map['scope_target_id'] = Variable<String>(scopeTargetId);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ReplaceRulesCompanion toCompanion(bool nullToAbsent) {
    return ReplaceRulesCompanion(
      id: Value(id),
      name: Value(name),
      groupName: Value(groupName),
      pattern: Value(pattern),
      replacement: Value(replacement),
      isRegex: Value(isRegex),
      scopeType: Value(scopeType),
      scopeTargetId: scopeTargetId == null && nullToAbsent
          ? const Value.absent()
          : Value(scopeTargetId),
      enabled: Value(enabled),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReplaceRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReplaceRuleRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      groupName: serializer.fromJson<String>(json['groupName']),
      pattern: serializer.fromJson<String>(json['pattern']),
      replacement: serializer.fromJson<String>(json['replacement']),
      isRegex: serializer.fromJson<bool>(json['isRegex']),
      scopeType: serializer.fromJson<String>(json['scopeType']),
      scopeTargetId: serializer.fromJson<String?>(json['scopeTargetId']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'groupName': serializer.toJson<String>(groupName),
      'pattern': serializer.toJson<String>(pattern),
      'replacement': serializer.toJson<String>(replacement),
      'isRegex': serializer.toJson<bool>(isRegex),
      'scopeType': serializer.toJson<String>(scopeType),
      'scopeTargetId': serializer.toJson<String?>(scopeTargetId),
      'enabled': serializer.toJson<bool>(enabled),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ReplaceRuleRow copyWith({
    String? id,
    String? name,
    String? groupName,
    String? pattern,
    String? replacement,
    bool? isRegex,
    String? scopeType,
    Value<String?> scopeTargetId = const Value.absent(),
    bool? enabled,
    int? sortOrder,
    int? updatedAt,
  }) => ReplaceRuleRow(
    id: id ?? this.id,
    name: name ?? this.name,
    groupName: groupName ?? this.groupName,
    pattern: pattern ?? this.pattern,
    replacement: replacement ?? this.replacement,
    isRegex: isRegex ?? this.isRegex,
    scopeType: scopeType ?? this.scopeType,
    scopeTargetId: scopeTargetId.present
        ? scopeTargetId.value
        : this.scopeTargetId,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReplaceRuleRow copyWithCompanion(ReplaceRulesCompanion data) {
    return ReplaceRuleRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      replacement: data.replacement.present
          ? data.replacement.value
          : this.replacement,
      isRegex: data.isRegex.present ? data.isRegex.value : this.isRegex,
      scopeType: data.scopeType.present ? data.scopeType.value : this.scopeType,
      scopeTargetId: data.scopeTargetId.present
          ? data.scopeTargetId.value
          : this.scopeTargetId,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReplaceRuleRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('groupName: $groupName, ')
          ..write('pattern: $pattern, ')
          ..write('replacement: $replacement, ')
          ..write('isRegex: $isRegex, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeTargetId: $scopeTargetId, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    groupName,
    pattern,
    replacement,
    isRegex,
    scopeType,
    scopeTargetId,
    enabled,
    sortOrder,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReplaceRuleRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.groupName == this.groupName &&
          other.pattern == this.pattern &&
          other.replacement == this.replacement &&
          other.isRegex == this.isRegex &&
          other.scopeType == this.scopeType &&
          other.scopeTargetId == this.scopeTargetId &&
          other.enabled == this.enabled &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt);
}

class ReplaceRulesCompanion extends UpdateCompanion<ReplaceRuleRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> groupName;
  final Value<String> pattern;
  final Value<String> replacement;
  final Value<bool> isRegex;
  final Value<String> scopeType;
  final Value<String?> scopeTargetId;
  final Value<bool> enabled;
  final Value<int> sortOrder;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ReplaceRulesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.groupName = const Value.absent(),
    this.pattern = const Value.absent(),
    this.replacement = const Value.absent(),
    this.isRegex = const Value.absent(),
    this.scopeType = const Value.absent(),
    this.scopeTargetId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReplaceRulesCompanion.insert({
    required String id,
    required String name,
    this.groupName = const Value.absent(),
    required String pattern,
    this.replacement = const Value.absent(),
    this.isRegex = const Value.absent(),
    this.scopeType = const Value.absent(),
    this.scopeTargetId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       pattern = Value(pattern),
       updatedAt = Value(updatedAt);
  static Insertable<ReplaceRuleRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? groupName,
    Expression<String>? pattern,
    Expression<String>? replacement,
    Expression<bool>? isRegex,
    Expression<String>? scopeType,
    Expression<String>? scopeTargetId,
    Expression<bool>? enabled,
    Expression<int>? sortOrder,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (groupName != null) 'group_name': groupName,
      if (pattern != null) 'pattern': pattern,
      if (replacement != null) 'replacement': replacement,
      if (isRegex != null) 'is_regex': isRegex,
      if (scopeType != null) 'scope_type': scopeType,
      if (scopeTargetId != null) 'scope_target_id': scopeTargetId,
      if (enabled != null) 'enabled': enabled,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReplaceRulesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? groupName,
    Value<String>? pattern,
    Value<String>? replacement,
    Value<bool>? isRegex,
    Value<String>? scopeType,
    Value<String?>? scopeTargetId,
    Value<bool>? enabled,
    Value<int>? sortOrder,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReplaceRulesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      groupName: groupName ?? this.groupName,
      pattern: pattern ?? this.pattern,
      replacement: replacement ?? this.replacement,
      isRegex: isRegex ?? this.isRegex,
      scopeType: scopeType ?? this.scopeType,
      scopeTargetId: scopeTargetId ?? this.scopeTargetId,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (replacement.present) {
      map['replacement'] = Variable<String>(replacement.value);
    }
    if (isRegex.present) {
      map['is_regex'] = Variable<bool>(isRegex.value);
    }
    if (scopeType.present) {
      map['scope_type'] = Variable<String>(scopeType.value);
    }
    if (scopeTargetId.present) {
      map['scope_target_id'] = Variable<String>(scopeTargetId.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReplaceRulesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('groupName: $groupName, ')
          ..write('pattern: $pattern, ')
          ..write('replacement: $replacement, ')
          ..write('isRegex: $isRegex, ')
          ..write('scopeType: $scopeType, ')
          ..write('scopeTargetId: $scopeTargetId, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReaderThemesTable extends ReaderThemes
    with TableInfo<$ReaderThemesTable, ReaderThemeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReaderThemesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isBuiltinMeta = const VerificationMeta(
    'isBuiltin',
  );
  @override
  late final GeneratedColumn<bool> isBuiltin = GeneratedColumn<bool>(
    'is_builtin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_builtin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isDarkMeta = const VerificationMeta('isDark');
  @override
  late final GeneratedColumn<bool> isDark = GeneratedColumn<bool>(
    'is_dark',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dark" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _bgColorMeta = const VerificationMeta(
    'bgColor',
  );
  @override
  late final GeneratedColumn<int> bgColor = GeneratedColumn<int>(
    'bg_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textColorMeta = const VerificationMeta(
    'textColor',
  );
  @override
  late final GeneratedColumn<int> textColor = GeneratedColumn<int>(
    'text_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secondaryTextColorMeta =
      const VerificationMeta('secondaryTextColor');
  @override
  late final GeneratedColumn<int> secondaryTextColor = GeneratedColumn<int>(
    'secondary_text_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bgTexturePathMeta = const VerificationMeta(
    'bgTexturePath',
  );
  @override
  late final GeneratedColumn<String> bgTexturePath = GeneratedColumn<String>(
    'bg_texture_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fontFamilyMeta = const VerificationMeta(
    'fontFamily',
  );
  @override
  late final GeneratedColumn<String> fontFamily = GeneratedColumn<String>(
    'font_family',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('system'),
  );
  static const VerificationMeta _fontPathMeta = const VerificationMeta(
    'fontPath',
  );
  @override
  late final GeneratedColumn<String> fontPath = GeneratedColumn<String>(
    'font_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fontSizeMeta = const VerificationMeta(
    'fontSize',
  );
  @override
  late final GeneratedColumn<double> fontSize = GeneratedColumn<double>(
    'font_size',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(18.0),
  );
  static const VerificationMeta _fontWeightMeta = const VerificationMeta(
    'fontWeight',
  );
  @override
  late final GeneratedColumn<int> fontWeight = GeneratedColumn<int>(
    'font_weight',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(400),
  );
  static const VerificationMeta _lineHeightMeta = const VerificationMeta(
    'lineHeight',
  );
  @override
  late final GeneratedColumn<double> lineHeight = GeneratedColumn<double>(
    'line_height',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1.65),
  );
  static const VerificationMeta _paragraphSpacingMeta = const VerificationMeta(
    'paragraphSpacing',
  );
  @override
  late final GeneratedColumn<double> paragraphSpacing = GeneratedColumn<double>(
    'paragraph_spacing',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(12.0),
  );
  static const VerificationMeta _letterSpacingMeta = const VerificationMeta(
    'letterSpacing',
  );
  @override
  late final GeneratedColumn<double> letterSpacing = GeneratedColumn<double>(
    'letter_spacing',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.2),
  );
  static const VerificationMeta _paragraphIndentCharsMeta =
      const VerificationMeta('paragraphIndentChars');
  @override
  late final GeneratedColumn<int> paragraphIndentChars = GeneratedColumn<int>(
    'paragraph_indent_chars',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _marginHorizontalMeta = const VerificationMeta(
    'marginHorizontal',
  );
  @override
  late final GeneratedColumn<double> marginHorizontal = GeneratedColumn<double>(
    'margin_horizontal',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(20.0),
  );
  static const VerificationMeta _marginVerticalMeta = const VerificationMeta(
    'marginVertical',
  );
  @override
  late final GeneratedColumn<double> marginVertical = GeneratedColumn<double>(
    'margin_vertical',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(24.0),
  );
  static const VerificationMeta _columnModeMeta = const VerificationMeta(
    'columnMode',
  );
  @override
  late final GeneratedColumn<String> columnMode = GeneratedColumn<String>(
    'column_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('auto'),
  );
  static const VerificationMeta _maxContentWidthMeta = const VerificationMeta(
    'maxContentWidth',
  );
  @override
  late final GeneratedColumn<double> maxContentWidth = GeneratedColumn<double>(
    'max_content_width',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(760.0),
  );
  static const VerificationMeta _pageTurnModeMeta = const VerificationMeta(
    'pageTurnMode',
  );
  @override
  late final GeneratedColumn<String> pageTurnMode = GeneratedColumn<String>(
    'page_turn_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cover'),
  );
  static const VerificationMeta _enablePunctuationHangingMeta =
      const VerificationMeta('enablePunctuationHanging');
  @override
  late final GeneratedColumn<bool> enablePunctuationHanging =
      GeneratedColumn<bool>(
        'enable_punctuation_hanging',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("enable_punctuation_hanging" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _enableCjkSpacingMeta = const VerificationMeta(
    'enableCjkSpacing',
  );
  @override
  late final GeneratedColumn<bool> enableCjkSpacing = GeneratedColumn<bool>(
    'enable_cjk_spacing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enable_cjk_spacing" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    isBuiltin,
    isDark,
    bgColor,
    textColor,
    secondaryTextColor,
    bgTexturePath,
    fontFamily,
    fontPath,
    fontSize,
    fontWeight,
    lineHeight,
    paragraphSpacing,
    letterSpacing,
    paragraphIndentChars,
    marginHorizontal,
    marginVertical,
    columnMode,
    maxContentWidth,
    pageTurnMode,
    enablePunctuationHanging,
    enableCjkSpacing,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reader_themes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReaderThemeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_builtin')) {
      context.handle(
        _isBuiltinMeta,
        isBuiltin.isAcceptableOrUnknown(data['is_builtin']!, _isBuiltinMeta),
      );
    }
    if (data.containsKey('is_dark')) {
      context.handle(
        _isDarkMeta,
        isDark.isAcceptableOrUnknown(data['is_dark']!, _isDarkMeta),
      );
    }
    if (data.containsKey('bg_color')) {
      context.handle(
        _bgColorMeta,
        bgColor.isAcceptableOrUnknown(data['bg_color']!, _bgColorMeta),
      );
    } else if (isInserting) {
      context.missing(_bgColorMeta);
    }
    if (data.containsKey('text_color')) {
      context.handle(
        _textColorMeta,
        textColor.isAcceptableOrUnknown(data['text_color']!, _textColorMeta),
      );
    } else if (isInserting) {
      context.missing(_textColorMeta);
    }
    if (data.containsKey('secondary_text_color')) {
      context.handle(
        _secondaryTextColorMeta,
        secondaryTextColor.isAcceptableOrUnknown(
          data['secondary_text_color']!,
          _secondaryTextColorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_secondaryTextColorMeta);
    }
    if (data.containsKey('bg_texture_path')) {
      context.handle(
        _bgTexturePathMeta,
        bgTexturePath.isAcceptableOrUnknown(
          data['bg_texture_path']!,
          _bgTexturePathMeta,
        ),
      );
    }
    if (data.containsKey('font_family')) {
      context.handle(
        _fontFamilyMeta,
        fontFamily.isAcceptableOrUnknown(data['font_family']!, _fontFamilyMeta),
      );
    }
    if (data.containsKey('font_path')) {
      context.handle(
        _fontPathMeta,
        fontPath.isAcceptableOrUnknown(data['font_path']!, _fontPathMeta),
      );
    }
    if (data.containsKey('font_size')) {
      context.handle(
        _fontSizeMeta,
        fontSize.isAcceptableOrUnknown(data['font_size']!, _fontSizeMeta),
      );
    }
    if (data.containsKey('font_weight')) {
      context.handle(
        _fontWeightMeta,
        fontWeight.isAcceptableOrUnknown(data['font_weight']!, _fontWeightMeta),
      );
    }
    if (data.containsKey('line_height')) {
      context.handle(
        _lineHeightMeta,
        lineHeight.isAcceptableOrUnknown(data['line_height']!, _lineHeightMeta),
      );
    }
    if (data.containsKey('paragraph_spacing')) {
      context.handle(
        _paragraphSpacingMeta,
        paragraphSpacing.isAcceptableOrUnknown(
          data['paragraph_spacing']!,
          _paragraphSpacingMeta,
        ),
      );
    }
    if (data.containsKey('letter_spacing')) {
      context.handle(
        _letterSpacingMeta,
        letterSpacing.isAcceptableOrUnknown(
          data['letter_spacing']!,
          _letterSpacingMeta,
        ),
      );
    }
    if (data.containsKey('paragraph_indent_chars')) {
      context.handle(
        _paragraphIndentCharsMeta,
        paragraphIndentChars.isAcceptableOrUnknown(
          data['paragraph_indent_chars']!,
          _paragraphIndentCharsMeta,
        ),
      );
    }
    if (data.containsKey('margin_horizontal')) {
      context.handle(
        _marginHorizontalMeta,
        marginHorizontal.isAcceptableOrUnknown(
          data['margin_horizontal']!,
          _marginHorizontalMeta,
        ),
      );
    }
    if (data.containsKey('margin_vertical')) {
      context.handle(
        _marginVerticalMeta,
        marginVertical.isAcceptableOrUnknown(
          data['margin_vertical']!,
          _marginVerticalMeta,
        ),
      );
    }
    if (data.containsKey('column_mode')) {
      context.handle(
        _columnModeMeta,
        columnMode.isAcceptableOrUnknown(data['column_mode']!, _columnModeMeta),
      );
    }
    if (data.containsKey('max_content_width')) {
      context.handle(
        _maxContentWidthMeta,
        maxContentWidth.isAcceptableOrUnknown(
          data['max_content_width']!,
          _maxContentWidthMeta,
        ),
      );
    }
    if (data.containsKey('page_turn_mode')) {
      context.handle(
        _pageTurnModeMeta,
        pageTurnMode.isAcceptableOrUnknown(
          data['page_turn_mode']!,
          _pageTurnModeMeta,
        ),
      );
    }
    if (data.containsKey('enable_punctuation_hanging')) {
      context.handle(
        _enablePunctuationHangingMeta,
        enablePunctuationHanging.isAcceptableOrUnknown(
          data['enable_punctuation_hanging']!,
          _enablePunctuationHangingMeta,
        ),
      );
    }
    if (data.containsKey('enable_cjk_spacing')) {
      context.handle(
        _enableCjkSpacingMeta,
        enableCjkSpacing.isAcceptableOrUnknown(
          data['enable_cjk_spacing']!,
          _enableCjkSpacingMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReaderThemeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReaderThemeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isBuiltin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_builtin'],
      )!,
      isDark: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dark'],
      )!,
      bgColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bg_color'],
      )!,
      textColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}text_color'],
      )!,
      secondaryTextColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}secondary_text_color'],
      )!,
      bgTexturePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bg_texture_path'],
      ),
      fontFamily: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}font_family'],
      )!,
      fontPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}font_path'],
      ),
      fontSize: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}font_size'],
      )!,
      fontWeight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}font_weight'],
      )!,
      lineHeight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}line_height'],
      )!,
      paragraphSpacing: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}paragraph_spacing'],
      )!,
      letterSpacing: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}letter_spacing'],
      )!,
      paragraphIndentChars: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paragraph_indent_chars'],
      )!,
      marginHorizontal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}margin_horizontal'],
      )!,
      marginVertical: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}margin_vertical'],
      )!,
      columnMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}column_mode'],
      )!,
      maxContentWidth: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_content_width'],
      )!,
      pageTurnMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_turn_mode'],
      )!,
      enablePunctuationHanging: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enable_punctuation_hanging'],
      )!,
      enableCjkSpacing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enable_cjk_spacing'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReaderThemesTable createAlias(String alias) {
    return $ReaderThemesTable(attachedDatabase, alias);
  }
}

class ReaderThemeRow extends DataClass implements Insertable<ReaderThemeRow> {
  final String id;
  final String name;
  final bool isBuiltin;
  final bool isDark;
  final int bgColor;
  final int textColor;
  final int secondaryTextColor;
  final String? bgTexturePath;
  final String fontFamily;
  final String? fontPath;
  final double fontSize;
  final int fontWeight;
  final double lineHeight;
  final double paragraphSpacing;
  final double letterSpacing;
  final int paragraphIndentChars;
  final double marginHorizontal;
  final double marginVertical;
  final String columnMode;
  final double maxContentWidth;
  final String pageTurnMode;
  final bool enablePunctuationHanging;
  final bool enableCjkSpacing;
  final int updatedAt;
  const ReaderThemeRow({
    required this.id,
    required this.name,
    required this.isBuiltin,
    required this.isDark,
    required this.bgColor,
    required this.textColor,
    required this.secondaryTextColor,
    this.bgTexturePath,
    required this.fontFamily,
    this.fontPath,
    required this.fontSize,
    required this.fontWeight,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.letterSpacing,
    required this.paragraphIndentChars,
    required this.marginHorizontal,
    required this.marginVertical,
    required this.columnMode,
    required this.maxContentWidth,
    required this.pageTurnMode,
    required this.enablePunctuationHanging,
    required this.enableCjkSpacing,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['is_builtin'] = Variable<bool>(isBuiltin);
    map['is_dark'] = Variable<bool>(isDark);
    map['bg_color'] = Variable<int>(bgColor);
    map['text_color'] = Variable<int>(textColor);
    map['secondary_text_color'] = Variable<int>(secondaryTextColor);
    if (!nullToAbsent || bgTexturePath != null) {
      map['bg_texture_path'] = Variable<String>(bgTexturePath);
    }
    map['font_family'] = Variable<String>(fontFamily);
    if (!nullToAbsent || fontPath != null) {
      map['font_path'] = Variable<String>(fontPath);
    }
    map['font_size'] = Variable<double>(fontSize);
    map['font_weight'] = Variable<int>(fontWeight);
    map['line_height'] = Variable<double>(lineHeight);
    map['paragraph_spacing'] = Variable<double>(paragraphSpacing);
    map['letter_spacing'] = Variable<double>(letterSpacing);
    map['paragraph_indent_chars'] = Variable<int>(paragraphIndentChars);
    map['margin_horizontal'] = Variable<double>(marginHorizontal);
    map['margin_vertical'] = Variable<double>(marginVertical);
    map['column_mode'] = Variable<String>(columnMode);
    map['max_content_width'] = Variable<double>(maxContentWidth);
    map['page_turn_mode'] = Variable<String>(pageTurnMode);
    map['enable_punctuation_hanging'] = Variable<bool>(
      enablePunctuationHanging,
    );
    map['enable_cjk_spacing'] = Variable<bool>(enableCjkSpacing);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ReaderThemesCompanion toCompanion(bool nullToAbsent) {
    return ReaderThemesCompanion(
      id: Value(id),
      name: Value(name),
      isBuiltin: Value(isBuiltin),
      isDark: Value(isDark),
      bgColor: Value(bgColor),
      textColor: Value(textColor),
      secondaryTextColor: Value(secondaryTextColor),
      bgTexturePath: bgTexturePath == null && nullToAbsent
          ? const Value.absent()
          : Value(bgTexturePath),
      fontFamily: Value(fontFamily),
      fontPath: fontPath == null && nullToAbsent
          ? const Value.absent()
          : Value(fontPath),
      fontSize: Value(fontSize),
      fontWeight: Value(fontWeight),
      lineHeight: Value(lineHeight),
      paragraphSpacing: Value(paragraphSpacing),
      letterSpacing: Value(letterSpacing),
      paragraphIndentChars: Value(paragraphIndentChars),
      marginHorizontal: Value(marginHorizontal),
      marginVertical: Value(marginVertical),
      columnMode: Value(columnMode),
      maxContentWidth: Value(maxContentWidth),
      pageTurnMode: Value(pageTurnMode),
      enablePunctuationHanging: Value(enablePunctuationHanging),
      enableCjkSpacing: Value(enableCjkSpacing),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReaderThemeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReaderThemeRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isBuiltin: serializer.fromJson<bool>(json['isBuiltin']),
      isDark: serializer.fromJson<bool>(json['isDark']),
      bgColor: serializer.fromJson<int>(json['bgColor']),
      textColor: serializer.fromJson<int>(json['textColor']),
      secondaryTextColor: serializer.fromJson<int>(json['secondaryTextColor']),
      bgTexturePath: serializer.fromJson<String?>(json['bgTexturePath']),
      fontFamily: serializer.fromJson<String>(json['fontFamily']),
      fontPath: serializer.fromJson<String?>(json['fontPath']),
      fontSize: serializer.fromJson<double>(json['fontSize']),
      fontWeight: serializer.fromJson<int>(json['fontWeight']),
      lineHeight: serializer.fromJson<double>(json['lineHeight']),
      paragraphSpacing: serializer.fromJson<double>(json['paragraphSpacing']),
      letterSpacing: serializer.fromJson<double>(json['letterSpacing']),
      paragraphIndentChars: serializer.fromJson<int>(
        json['paragraphIndentChars'],
      ),
      marginHorizontal: serializer.fromJson<double>(json['marginHorizontal']),
      marginVertical: serializer.fromJson<double>(json['marginVertical']),
      columnMode: serializer.fromJson<String>(json['columnMode']),
      maxContentWidth: serializer.fromJson<double>(json['maxContentWidth']),
      pageTurnMode: serializer.fromJson<String>(json['pageTurnMode']),
      enablePunctuationHanging: serializer.fromJson<bool>(
        json['enablePunctuationHanging'],
      ),
      enableCjkSpacing: serializer.fromJson<bool>(json['enableCjkSpacing']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'isBuiltin': serializer.toJson<bool>(isBuiltin),
      'isDark': serializer.toJson<bool>(isDark),
      'bgColor': serializer.toJson<int>(bgColor),
      'textColor': serializer.toJson<int>(textColor),
      'secondaryTextColor': serializer.toJson<int>(secondaryTextColor),
      'bgTexturePath': serializer.toJson<String?>(bgTexturePath),
      'fontFamily': serializer.toJson<String>(fontFamily),
      'fontPath': serializer.toJson<String?>(fontPath),
      'fontSize': serializer.toJson<double>(fontSize),
      'fontWeight': serializer.toJson<int>(fontWeight),
      'lineHeight': serializer.toJson<double>(lineHeight),
      'paragraphSpacing': serializer.toJson<double>(paragraphSpacing),
      'letterSpacing': serializer.toJson<double>(letterSpacing),
      'paragraphIndentChars': serializer.toJson<int>(paragraphIndentChars),
      'marginHorizontal': serializer.toJson<double>(marginHorizontal),
      'marginVertical': serializer.toJson<double>(marginVertical),
      'columnMode': serializer.toJson<String>(columnMode),
      'maxContentWidth': serializer.toJson<double>(maxContentWidth),
      'pageTurnMode': serializer.toJson<String>(pageTurnMode),
      'enablePunctuationHanging': serializer.toJson<bool>(
        enablePunctuationHanging,
      ),
      'enableCjkSpacing': serializer.toJson<bool>(enableCjkSpacing),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ReaderThemeRow copyWith({
    String? id,
    String? name,
    bool? isBuiltin,
    bool? isDark,
    int? bgColor,
    int? textColor,
    int? secondaryTextColor,
    Value<String?> bgTexturePath = const Value.absent(),
    String? fontFamily,
    Value<String?> fontPath = const Value.absent(),
    double? fontSize,
    int? fontWeight,
    double? lineHeight,
    double? paragraphSpacing,
    double? letterSpacing,
    int? paragraphIndentChars,
    double? marginHorizontal,
    double? marginVertical,
    String? columnMode,
    double? maxContentWidth,
    String? pageTurnMode,
    bool? enablePunctuationHanging,
    bool? enableCjkSpacing,
    int? updatedAt,
  }) => ReaderThemeRow(
    id: id ?? this.id,
    name: name ?? this.name,
    isBuiltin: isBuiltin ?? this.isBuiltin,
    isDark: isDark ?? this.isDark,
    bgColor: bgColor ?? this.bgColor,
    textColor: textColor ?? this.textColor,
    secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
    bgTexturePath: bgTexturePath.present
        ? bgTexturePath.value
        : this.bgTexturePath,
    fontFamily: fontFamily ?? this.fontFamily,
    fontPath: fontPath.present ? fontPath.value : this.fontPath,
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    paragraphIndentChars: paragraphIndentChars ?? this.paragraphIndentChars,
    marginHorizontal: marginHorizontal ?? this.marginHorizontal,
    marginVertical: marginVertical ?? this.marginVertical,
    columnMode: columnMode ?? this.columnMode,
    maxContentWidth: maxContentWidth ?? this.maxContentWidth,
    pageTurnMode: pageTurnMode ?? this.pageTurnMode,
    enablePunctuationHanging:
        enablePunctuationHanging ?? this.enablePunctuationHanging,
    enableCjkSpacing: enableCjkSpacing ?? this.enableCjkSpacing,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReaderThemeRow copyWithCompanion(ReaderThemesCompanion data) {
    return ReaderThemeRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isBuiltin: data.isBuiltin.present ? data.isBuiltin.value : this.isBuiltin,
      isDark: data.isDark.present ? data.isDark.value : this.isDark,
      bgColor: data.bgColor.present ? data.bgColor.value : this.bgColor,
      textColor: data.textColor.present ? data.textColor.value : this.textColor,
      secondaryTextColor: data.secondaryTextColor.present
          ? data.secondaryTextColor.value
          : this.secondaryTextColor,
      bgTexturePath: data.bgTexturePath.present
          ? data.bgTexturePath.value
          : this.bgTexturePath,
      fontFamily: data.fontFamily.present
          ? data.fontFamily.value
          : this.fontFamily,
      fontPath: data.fontPath.present ? data.fontPath.value : this.fontPath,
      fontSize: data.fontSize.present ? data.fontSize.value : this.fontSize,
      fontWeight: data.fontWeight.present
          ? data.fontWeight.value
          : this.fontWeight,
      lineHeight: data.lineHeight.present
          ? data.lineHeight.value
          : this.lineHeight,
      paragraphSpacing: data.paragraphSpacing.present
          ? data.paragraphSpacing.value
          : this.paragraphSpacing,
      letterSpacing: data.letterSpacing.present
          ? data.letterSpacing.value
          : this.letterSpacing,
      paragraphIndentChars: data.paragraphIndentChars.present
          ? data.paragraphIndentChars.value
          : this.paragraphIndentChars,
      marginHorizontal: data.marginHorizontal.present
          ? data.marginHorizontal.value
          : this.marginHorizontal,
      marginVertical: data.marginVertical.present
          ? data.marginVertical.value
          : this.marginVertical,
      columnMode: data.columnMode.present
          ? data.columnMode.value
          : this.columnMode,
      maxContentWidth: data.maxContentWidth.present
          ? data.maxContentWidth.value
          : this.maxContentWidth,
      pageTurnMode: data.pageTurnMode.present
          ? data.pageTurnMode.value
          : this.pageTurnMode,
      enablePunctuationHanging: data.enablePunctuationHanging.present
          ? data.enablePunctuationHanging.value
          : this.enablePunctuationHanging,
      enableCjkSpacing: data.enableCjkSpacing.present
          ? data.enableCjkSpacing.value
          : this.enableCjkSpacing,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReaderThemeRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('isDark: $isDark, ')
          ..write('bgColor: $bgColor, ')
          ..write('textColor: $textColor, ')
          ..write('secondaryTextColor: $secondaryTextColor, ')
          ..write('bgTexturePath: $bgTexturePath, ')
          ..write('fontFamily: $fontFamily, ')
          ..write('fontPath: $fontPath, ')
          ..write('fontSize: $fontSize, ')
          ..write('fontWeight: $fontWeight, ')
          ..write('lineHeight: $lineHeight, ')
          ..write('paragraphSpacing: $paragraphSpacing, ')
          ..write('letterSpacing: $letterSpacing, ')
          ..write('paragraphIndentChars: $paragraphIndentChars, ')
          ..write('marginHorizontal: $marginHorizontal, ')
          ..write('marginVertical: $marginVertical, ')
          ..write('columnMode: $columnMode, ')
          ..write('maxContentWidth: $maxContentWidth, ')
          ..write('pageTurnMode: $pageTurnMode, ')
          ..write('enablePunctuationHanging: $enablePunctuationHanging, ')
          ..write('enableCjkSpacing: $enableCjkSpacing, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    isBuiltin,
    isDark,
    bgColor,
    textColor,
    secondaryTextColor,
    bgTexturePath,
    fontFamily,
    fontPath,
    fontSize,
    fontWeight,
    lineHeight,
    paragraphSpacing,
    letterSpacing,
    paragraphIndentChars,
    marginHorizontal,
    marginVertical,
    columnMode,
    maxContentWidth,
    pageTurnMode,
    enablePunctuationHanging,
    enableCjkSpacing,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReaderThemeRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.isBuiltin == this.isBuiltin &&
          other.isDark == this.isDark &&
          other.bgColor == this.bgColor &&
          other.textColor == this.textColor &&
          other.secondaryTextColor == this.secondaryTextColor &&
          other.bgTexturePath == this.bgTexturePath &&
          other.fontFamily == this.fontFamily &&
          other.fontPath == this.fontPath &&
          other.fontSize == this.fontSize &&
          other.fontWeight == this.fontWeight &&
          other.lineHeight == this.lineHeight &&
          other.paragraphSpacing == this.paragraphSpacing &&
          other.letterSpacing == this.letterSpacing &&
          other.paragraphIndentChars == this.paragraphIndentChars &&
          other.marginHorizontal == this.marginHorizontal &&
          other.marginVertical == this.marginVertical &&
          other.columnMode == this.columnMode &&
          other.maxContentWidth == this.maxContentWidth &&
          other.pageTurnMode == this.pageTurnMode &&
          other.enablePunctuationHanging == this.enablePunctuationHanging &&
          other.enableCjkSpacing == this.enableCjkSpacing &&
          other.updatedAt == this.updatedAt);
}

class ReaderThemesCompanion extends UpdateCompanion<ReaderThemeRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> isBuiltin;
  final Value<bool> isDark;
  final Value<int> bgColor;
  final Value<int> textColor;
  final Value<int> secondaryTextColor;
  final Value<String?> bgTexturePath;
  final Value<String> fontFamily;
  final Value<String?> fontPath;
  final Value<double> fontSize;
  final Value<int> fontWeight;
  final Value<double> lineHeight;
  final Value<double> paragraphSpacing;
  final Value<double> letterSpacing;
  final Value<int> paragraphIndentChars;
  final Value<double> marginHorizontal;
  final Value<double> marginVertical;
  final Value<String> columnMode;
  final Value<double> maxContentWidth;
  final Value<String> pageTurnMode;
  final Value<bool> enablePunctuationHanging;
  final Value<bool> enableCjkSpacing;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const ReaderThemesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    this.isDark = const Value.absent(),
    this.bgColor = const Value.absent(),
    this.textColor = const Value.absent(),
    this.secondaryTextColor = const Value.absent(),
    this.bgTexturePath = const Value.absent(),
    this.fontFamily = const Value.absent(),
    this.fontPath = const Value.absent(),
    this.fontSize = const Value.absent(),
    this.fontWeight = const Value.absent(),
    this.lineHeight = const Value.absent(),
    this.paragraphSpacing = const Value.absent(),
    this.letterSpacing = const Value.absent(),
    this.paragraphIndentChars = const Value.absent(),
    this.marginHorizontal = const Value.absent(),
    this.marginVertical = const Value.absent(),
    this.columnMode = const Value.absent(),
    this.maxContentWidth = const Value.absent(),
    this.pageTurnMode = const Value.absent(),
    this.enablePunctuationHanging = const Value.absent(),
    this.enableCjkSpacing = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReaderThemesCompanion.insert({
    required String id,
    required String name,
    this.isBuiltin = const Value.absent(),
    this.isDark = const Value.absent(),
    required int bgColor,
    required int textColor,
    required int secondaryTextColor,
    this.bgTexturePath = const Value.absent(),
    this.fontFamily = const Value.absent(),
    this.fontPath = const Value.absent(),
    this.fontSize = const Value.absent(),
    this.fontWeight = const Value.absent(),
    this.lineHeight = const Value.absent(),
    this.paragraphSpacing = const Value.absent(),
    this.letterSpacing = const Value.absent(),
    this.paragraphIndentChars = const Value.absent(),
    this.marginHorizontal = const Value.absent(),
    this.marginVertical = const Value.absent(),
    this.columnMode = const Value.absent(),
    this.maxContentWidth = const Value.absent(),
    this.pageTurnMode = const Value.absent(),
    this.enablePunctuationHanging = const Value.absent(),
    this.enableCjkSpacing = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       bgColor = Value(bgColor),
       textColor = Value(textColor),
       secondaryTextColor = Value(secondaryTextColor),
       updatedAt = Value(updatedAt);
  static Insertable<ReaderThemeRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? isBuiltin,
    Expression<bool>? isDark,
    Expression<int>? bgColor,
    Expression<int>? textColor,
    Expression<int>? secondaryTextColor,
    Expression<String>? bgTexturePath,
    Expression<String>? fontFamily,
    Expression<String>? fontPath,
    Expression<double>? fontSize,
    Expression<int>? fontWeight,
    Expression<double>? lineHeight,
    Expression<double>? paragraphSpacing,
    Expression<double>? letterSpacing,
    Expression<int>? paragraphIndentChars,
    Expression<double>? marginHorizontal,
    Expression<double>? marginVertical,
    Expression<String>? columnMode,
    Expression<double>? maxContentWidth,
    Expression<String>? pageTurnMode,
    Expression<bool>? enablePunctuationHanging,
    Expression<bool>? enableCjkSpacing,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isBuiltin != null) 'is_builtin': isBuiltin,
      if (isDark != null) 'is_dark': isDark,
      if (bgColor != null) 'bg_color': bgColor,
      if (textColor != null) 'text_color': textColor,
      if (secondaryTextColor != null)
        'secondary_text_color': secondaryTextColor,
      if (bgTexturePath != null) 'bg_texture_path': bgTexturePath,
      if (fontFamily != null) 'font_family': fontFamily,
      if (fontPath != null) 'font_path': fontPath,
      if (fontSize != null) 'font_size': fontSize,
      if (fontWeight != null) 'font_weight': fontWeight,
      if (lineHeight != null) 'line_height': lineHeight,
      if (paragraphSpacing != null) 'paragraph_spacing': paragraphSpacing,
      if (letterSpacing != null) 'letter_spacing': letterSpacing,
      if (paragraphIndentChars != null)
        'paragraph_indent_chars': paragraphIndentChars,
      if (marginHorizontal != null) 'margin_horizontal': marginHorizontal,
      if (marginVertical != null) 'margin_vertical': marginVertical,
      if (columnMode != null) 'column_mode': columnMode,
      if (maxContentWidth != null) 'max_content_width': maxContentWidth,
      if (pageTurnMode != null) 'page_turn_mode': pageTurnMode,
      if (enablePunctuationHanging != null)
        'enable_punctuation_hanging': enablePunctuationHanging,
      if (enableCjkSpacing != null) 'enable_cjk_spacing': enableCjkSpacing,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReaderThemesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<bool>? isBuiltin,
    Value<bool>? isDark,
    Value<int>? bgColor,
    Value<int>? textColor,
    Value<int>? secondaryTextColor,
    Value<String?>? bgTexturePath,
    Value<String>? fontFamily,
    Value<String?>? fontPath,
    Value<double>? fontSize,
    Value<int>? fontWeight,
    Value<double>? lineHeight,
    Value<double>? paragraphSpacing,
    Value<double>? letterSpacing,
    Value<int>? paragraphIndentChars,
    Value<double>? marginHorizontal,
    Value<double>? marginVertical,
    Value<String>? columnMode,
    Value<double>? maxContentWidth,
    Value<String>? pageTurnMode,
    Value<bool>? enablePunctuationHanging,
    Value<bool>? enableCjkSpacing,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReaderThemesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      isDark: isDark ?? this.isDark,
      bgColor: bgColor ?? this.bgColor,
      textColor: textColor ?? this.textColor,
      secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
      bgTexturePath: bgTexturePath ?? this.bgTexturePath,
      fontFamily: fontFamily ?? this.fontFamily,
      fontPath: fontPath ?? this.fontPath,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      paragraphIndentChars: paragraphIndentChars ?? this.paragraphIndentChars,
      marginHorizontal: marginHorizontal ?? this.marginHorizontal,
      marginVertical: marginVertical ?? this.marginVertical,
      columnMode: columnMode ?? this.columnMode,
      maxContentWidth: maxContentWidth ?? this.maxContentWidth,
      pageTurnMode: pageTurnMode ?? this.pageTurnMode,
      enablePunctuationHanging:
          enablePunctuationHanging ?? this.enablePunctuationHanging,
      enableCjkSpacing: enableCjkSpacing ?? this.enableCjkSpacing,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isBuiltin.present) {
      map['is_builtin'] = Variable<bool>(isBuiltin.value);
    }
    if (isDark.present) {
      map['is_dark'] = Variable<bool>(isDark.value);
    }
    if (bgColor.present) {
      map['bg_color'] = Variable<int>(bgColor.value);
    }
    if (textColor.present) {
      map['text_color'] = Variable<int>(textColor.value);
    }
    if (secondaryTextColor.present) {
      map['secondary_text_color'] = Variable<int>(secondaryTextColor.value);
    }
    if (bgTexturePath.present) {
      map['bg_texture_path'] = Variable<String>(bgTexturePath.value);
    }
    if (fontFamily.present) {
      map['font_family'] = Variable<String>(fontFamily.value);
    }
    if (fontPath.present) {
      map['font_path'] = Variable<String>(fontPath.value);
    }
    if (fontSize.present) {
      map['font_size'] = Variable<double>(fontSize.value);
    }
    if (fontWeight.present) {
      map['font_weight'] = Variable<int>(fontWeight.value);
    }
    if (lineHeight.present) {
      map['line_height'] = Variable<double>(lineHeight.value);
    }
    if (paragraphSpacing.present) {
      map['paragraph_spacing'] = Variable<double>(paragraphSpacing.value);
    }
    if (letterSpacing.present) {
      map['letter_spacing'] = Variable<double>(letterSpacing.value);
    }
    if (paragraphIndentChars.present) {
      map['paragraph_indent_chars'] = Variable<int>(paragraphIndentChars.value);
    }
    if (marginHorizontal.present) {
      map['margin_horizontal'] = Variable<double>(marginHorizontal.value);
    }
    if (marginVertical.present) {
      map['margin_vertical'] = Variable<double>(marginVertical.value);
    }
    if (columnMode.present) {
      map['column_mode'] = Variable<String>(columnMode.value);
    }
    if (maxContentWidth.present) {
      map['max_content_width'] = Variable<double>(maxContentWidth.value);
    }
    if (pageTurnMode.present) {
      map['page_turn_mode'] = Variable<String>(pageTurnMode.value);
    }
    if (enablePunctuationHanging.present) {
      map['enable_punctuation_hanging'] = Variable<bool>(
        enablePunctuationHanging.value,
      );
    }
    if (enableCjkSpacing.present) {
      map['enable_cjk_spacing'] = Variable<bool>(enableCjkSpacing.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReaderThemesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('isDark: $isDark, ')
          ..write('bgColor: $bgColor, ')
          ..write('textColor: $textColor, ')
          ..write('secondaryTextColor: $secondaryTextColor, ')
          ..write('bgTexturePath: $bgTexturePath, ')
          ..write('fontFamily: $fontFamily, ')
          ..write('fontPath: $fontPath, ')
          ..write('fontSize: $fontSize, ')
          ..write('fontWeight: $fontWeight, ')
          ..write('lineHeight: $lineHeight, ')
          ..write('paragraphSpacing: $paragraphSpacing, ')
          ..write('letterSpacing: $letterSpacing, ')
          ..write('paragraphIndentChars: $paragraphIndentChars, ')
          ..write('marginHorizontal: $marginHorizontal, ')
          ..write('marginVertical: $marginVertical, ')
          ..write('columnMode: $columnMode, ')
          ..write('maxContentWidth: $maxContentWidth, ')
          ..write('pageTurnMode: $pageTurnMode, ')
          ..write('enablePunctuationHanging: $enablePunctuationHanging, ')
          ..write('enableCjkSpacing: $enableCjkSpacing, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSettingRow extends DataClass implements Insertable<AppSettingRow> {
  final String key;
  final String value;
  final int updatedAt;
  const AppSettingRow({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  AppSettingRow copyWith({String? key, String? value, int? updatedAt}) =>
      AppSettingRow(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSettingRow copyWithCompanion(AppSettingsCompanion data) {
    return AppSettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<AppSettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BookGroupsTable bookGroups = $BookGroupsTable(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $ReadingProgressRecordsTable readingProgressRecords =
      $ReadingProgressRecordsTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $BookSourcesTable bookSources = $BookSourcesTable(this);
  late final $ReplaceRulesTable replaceRules = $ReplaceRulesTable(this);
  late final $ReaderThemesTable readerThemes = $ReaderThemesTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final Index idxBooksShelfSort = Index(
    'idx_books_shelf_sort',
    'CREATE INDEX idx_books_shelf_sort ON books (group_id, is_pinned DESC, last_read_at DESC)',
  );
  late final Index idxBooksSourceUrl = Index(
    'idx_books_source_url',
    'CREATE INDEX idx_books_source_url ON books (source_id, origin_book_url)',
  );
  late final Index idxChaptersBookIndex = Index(
    'idx_chapters_book_index',
    'CREATE UNIQUE INDEX idx_chapters_book_index ON chapters (book_id, chapter_index)',
  );
  late final Index idxBookmarksBookPos = Index(
    'idx_bookmarks_book_pos',
    'CREATE INDEX idx_bookmarks_book_pos ON bookmarks (book_id, chapter_index, char_offset)',
  );
  late final Index idxSourcesEnabledWeight = Index(
    'idx_sources_enabled_weight',
    'CREATE INDEX idx_sources_enabled_weight ON book_sources (enabled, weight DESC)',
  );
  late final Index idxReplaceRulesActive = Index(
    'idx_replace_rules_active',
    'CREATE INDEX idx_replace_rules_active ON replace_rules (enabled, scope_type, scope_target_id, sort_order)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    bookGroups,
    books,
    chapters,
    readingProgressRecords,
    bookmarks,
    bookSources,
    replaceRules,
    readerThemes,
    appSettings,
    idxBooksShelfSort,
    idxBooksSourceUrl,
    idxChaptersBookIndex,
    idxBookmarksBookPos,
    idxSourcesEnabledWeight,
    idxReplaceRulesActive,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'book_groups',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('books', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('chapters', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('reading_progress', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookmarks', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$BookGroupsTableCreateCompanionBuilder = BookGroupsCompanion Function({
  required String id,
  required String name,
  Value<int> sortOrder,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$BookGroupsTableUpdateCompanionBuilder = BookGroupsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> sortOrder,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$BookGroupsTableReferences
    extends BaseReferences<_$AppDatabase, $BookGroupsTable, BookGroupRow> {
  $$BookGroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BooksTable, List<BookRow>> _booksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.books,
    aliasName: 'book_groups__id__books__group_id',
  );

  $$BooksTableProcessedTableManager get booksRefs {
    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_booksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BookGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $BookGroupsTable> {
  $$BookGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> booksRefs(
    Expression<bool> Function($$BooksTableFilterComposer f) f,
  ) {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BookGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $BookGroupsTable> {
  $$BookGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookGroupsTable> {
  $$BookGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> booksRefs<T extends Object>(
    Expression<T> Function($$BooksTableAnnotationComposer a) f,
  ) {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BookGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookGroupsTable,
          BookGroupRow,
          $$BookGroupsTableFilterComposer,
          $$BookGroupsTableOrderingComposer,
          $$BookGroupsTableAnnotationComposer,
          $$BookGroupsTableCreateCompanionBuilder,
          $$BookGroupsTableUpdateCompanionBuilder,
          (BookGroupRow, $$BookGroupsTableReferences),
          BookGroupRow,
          PrefetchHooks Function({bool booksRefs})
        > {
  $$BookGroupsTableTableManager(_$AppDatabase db, $BookGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookGroupsCompanion(
                id: id,
                name: name,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BookGroupsCompanion.insert(
                id: id,
                name: name,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookGroupsTable, BookGroupRow>(table),
                  $$BookGroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({booksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (booksRefs) db.books],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (booksRefs)
                    await $_getPrefetchedDataByColumns<
                      BookGroupRow,
                      $BookGroupsTable,
                      BookRow,
                      $BooksTable
                    >(
                      currentTable: table,
                      referencedTable: $$BookGroupsTableReferences
                          ._booksRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$BookGroupsTableReferences(db, table, p0).booksRefs,
                      currentColumn: 'id',
                      referencedColumn: 'group_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$BookGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookGroupsTable,
      BookGroupRow,
      $$BookGroupsTableFilterComposer,
      $$BookGroupsTableOrderingComposer,
      $$BookGroupsTableAnnotationComposer,
      $$BookGroupsTableCreateCompanionBuilder,
      $$BookGroupsTableUpdateCompanionBuilder,
      (BookGroupRow, $$BookGroupsTableReferences),
      BookGroupRow,
      PrefetchHooks Function({bool booksRefs})
    >;
typedef $$BooksTableCreateCompanionBuilder = BooksCompanion Function({
  required String id,
  Value<String?> sourceId,
  required String providerType,
  Value<String?> originBookUrl,
  Value<String?> tocUrl,
  required String title,
  Value<String> author,
  Value<String?> coverPath,
  Value<String> intro,
  Value<String?> localFilePath,
  Value<String?> fileEncoding,
  Value<int?> fileSizeBytes,
  Value<String?> fileHash,
  Value<String?> groupId,
  Value<bool> isPinned,
  Value<int> totalChapters,
  Value<int> unreadCount,
  Value<String> lastChapterTitle,
  Value<int?> lastReadAt,
  Value<int?> latestChapterAt,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$BooksTableUpdateCompanionBuilder = BooksCompanion Function({
  Value<String> id,
  Value<String?> sourceId,
  Value<String> providerType,
  Value<String?> originBookUrl,
  Value<String?> tocUrl,
  Value<String> title,
  Value<String> author,
  Value<String?> coverPath,
  Value<String> intro,
  Value<String?> localFilePath,
  Value<String?> fileEncoding,
  Value<int?> fileSizeBytes,
  Value<String?> fileHash,
  Value<String?> groupId,
  Value<bool> isPinned,
  Value<int> totalChapters,
  Value<int> unreadCount,
  Value<String> lastChapterTitle,
  Value<int?> lastReadAt,
  Value<int?> latestChapterAt,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, BookRow> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BookGroupsTable _groupIdTable(_$AppDatabase db) =>
      db.bookGroups.createAlias('books__group_id__book_groups__id');

  $$BookGroupsTableProcessedTableManager? get groupId {
    final $_column = $_itemColumn<String>('group_id');
    if ($_column == null) return null;
    final manager = $$BookGroupsTableTableManager(
      $_db,
      $_db.bookGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ChaptersTable, List<ChapterRow>>
  _chaptersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.chapters,
    aliasName: 'books__id__chapters__book_id',
  );

  $$ChaptersTableProcessedTableManager get chaptersRefs {
    final manager = $$ChaptersTableTableManager(
      $_db,
      $_db.chapters,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_chaptersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ReadingProgressRecordsTable,
    List<ReadingProgressRow>
  >
  _readingProgressRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.readingProgressRecords,
        aliasName: 'books__id__reading_progress__book_id',
      );

  $$ReadingProgressRecordsTableProcessedTableManager
  get readingProgressRecordsRefs {
    final manager = $$ReadingProgressRecordsTableTableManager(
      $_db,
      $_db.readingProgressRecords,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingProgressRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookmarksTable, List<BookmarkRow>>
  _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookmarks,
    aliasName: 'books__id__bookmarks__book_id',
  );

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager(
      $_db,
      $_db.bookmarks,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originBookUrl => $composableBuilder(
    column: $table.originBookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tocUrl => $composableBuilder(
    column: $table.tocUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileEncoding => $composableBuilder(
    column: $table.fileEncoding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalChapters => $composableBuilder(
    column: $table.totalChapters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastChapterTitle => $composableBuilder(
    column: $table.lastChapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latestChapterAt => $composableBuilder(
    column: $table.latestChapterAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BookGroupsTableFilterComposer get groupId {
    final $$BookGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.bookGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookGroupsTableFilterComposer(
            $db: $db,
            $table: $db.bookGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> chaptersRefs(
    Expression<bool> Function($$ChaptersTableFilterComposer f) f,
  ) {
    final $$ChaptersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableFilterComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> readingProgressRecordsRefs(
    Expression<bool> Function($$ReadingProgressRecordsTableFilterComposer f) f,
  ) {
    final $$ReadingProgressRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgressRecords,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressRecordsTableFilterComposer(
                $db: $db,
                $table: $db.readingProgressRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> bookmarksRefs(
    Expression<bool> Function($$BookmarksTableFilterComposer f) f,
  ) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableFilterComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originBookUrl => $composableBuilder(
    column: $table.originBookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tocUrl => $composableBuilder(
    column: $table.tocUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intro => $composableBuilder(
    column: $table.intro,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileEncoding => $composableBuilder(
    column: $table.fileEncoding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileHash => $composableBuilder(
    column: $table.fileHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalChapters => $composableBuilder(
    column: $table.totalChapters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastChapterTitle => $composableBuilder(
    column: $table.lastChapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latestChapterAt => $composableBuilder(
    column: $table.latestChapterAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BookGroupsTableOrderingComposer get groupId {
    final $$BookGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.bookGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.bookGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get providerType => $composableBuilder(
    column: $table.providerType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originBookUrl => $composableBuilder(
    column: $table.originBookUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tocUrl =>
      $composableBuilder(column: $table.tocUrl, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get intro =>
      $composableBuilder(column: $table.intro, builder: (column) => column);

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileEncoding => $composableBuilder(
    column: $table.fileEncoding,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileHash =>
      $composableBuilder(column: $table.fileHash, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<int> get totalChapters => $composableBuilder(
    column: $table.totalChapters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastChapterTitle => $composableBuilder(
    column: $table.lastChapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get latestChapterAt => $composableBuilder(
    column: $table.latestChapterAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BookGroupsTableAnnotationComposer get groupId {
    final $$BookGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.bookGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> chaptersRefs<T extends Object>(
    Expression<T> Function($$ChaptersTableAnnotationComposer a) f,
  ) {
    final $$ChaptersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chapters,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChaptersTableAnnotationComposer(
            $db: $db,
            $table: $db.chapters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> readingProgressRecordsRefs<T extends Object>(
    Expression<T> Function($$ReadingProgressRecordsTableAnnotationComposer a) f,
  ) {
    final $$ReadingProgressRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgressRecords,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.readingProgressRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> bookmarksRefs<T extends Object>(
    Expression<T> Function($$BookmarksTableAnnotationComposer a) f,
  ) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          BookRow,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (BookRow, $$BooksTableReferences),
          BookRow,
          PrefetchHooks Function({
            bool groupId,
            bool chaptersRefs,
            bool readingProgressRecordsRefs,
            bool bookmarksRefs,
          })
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String> providerType = const Value.absent(),
                Value<String?> originBookUrl = const Value.absent(),
                Value<String?> tocUrl = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String> intro = const Value.absent(),
                Value<String?> localFilePath = const Value.absent(),
                Value<String?> fileEncoding = const Value.absent(),
                Value<int?> fileSizeBytes = const Value.absent(),
                Value<String?> fileHash = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> totalChapters = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<String> lastChapterTitle = const Value.absent(),
                Value<int?> lastReadAt = const Value.absent(),
                Value<int?> latestChapterAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                sourceId: sourceId,
                providerType: providerType,
                originBookUrl: originBookUrl,
                tocUrl: tocUrl,
                title: title,
                author: author,
                coverPath: coverPath,
                intro: intro,
                localFilePath: localFilePath,
                fileEncoding: fileEncoding,
                fileSizeBytes: fileSizeBytes,
                fileHash: fileHash,
                groupId: groupId,
                isPinned: isPinned,
                totalChapters: totalChapters,
                unreadCount: unreadCount,
                lastChapterTitle: lastChapterTitle,
                lastReadAt: lastReadAt,
                latestChapterAt: latestChapterAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> sourceId = const Value.absent(),
                required String providerType,
                Value<String?> originBookUrl = const Value.absent(),
                Value<String?> tocUrl = const Value.absent(),
                required String title,
                Value<String> author = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String> intro = const Value.absent(),
                Value<String?> localFilePath = const Value.absent(),
                Value<String?> fileEncoding = const Value.absent(),
                Value<int?> fileSizeBytes = const Value.absent(),
                Value<String?> fileHash = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> totalChapters = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<String> lastChapterTitle = const Value.absent(),
                Value<int?> lastReadAt = const Value.absent(),
                Value<int?> latestChapterAt = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                sourceId: sourceId,
                providerType: providerType,
                originBookUrl: originBookUrl,
                tocUrl: tocUrl,
                title: title,
                author: author,
                coverPath: coverPath,
                intro: intro,
                localFilePath: localFilePath,
                fileEncoding: fileEncoding,
                fileSizeBytes: fileSizeBytes,
                fileHash: fileHash,
                groupId: groupId,
                isPinned: isPinned,
                totalChapters: totalChapters,
                unreadCount: unreadCount,
                lastChapterTitle: lastChapterTitle,
                lastReadAt: lastReadAt,
                latestChapterAt: latestChapterAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BooksTable, BookRow>(table),
                  $$BooksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                groupId = false,
                chaptersRefs = false,
                readingProgressRecordsRefs = false,
                bookmarksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (chaptersRefs) db.chapters,
                    if (readingProgressRecordsRefs) db.readingProgressRecords,
                    if (bookmarksRefs) db.bookmarks,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (groupId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.groupId,
                            referencedTable: $$BooksTableReferences
                                ._groupIdTable(db),
                            referencedColumn: $$BooksTableReferences
                                ._groupIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (chaptersRefs)
                        await $_getPrefetchedDataByColumns<
                          BookRow,
                          $BooksTable,
                          ChapterRow,
                          $ChaptersTable
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._chaptersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).chaptersRefs,
                          currentColumn: 'id',
                          referencedColumn: 'book_id',
                          typedResults: items,
                        ),
                      if (readingProgressRecordsRefs)
                        await $_getPrefetchedDataByColumns<
                          BookRow,
                          $BooksTable,
                          ReadingProgressRow,
                          $ReadingProgressRecordsTable
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._readingProgressRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).readingProgressRecordsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'book_id',
                          typedResults: items,
                        ),
                      if (bookmarksRefs)
                        await $_getPrefetchedDataByColumns<
                          BookRow,
                          $BooksTable,
                          BookmarkRow,
                          $BookmarksTable
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookmarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookmarksRefs,
                          currentColumn: 'id',
                          referencedColumn: 'book_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      BookRow,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (BookRow, $$BooksTableReferences),
      BookRow,
      PrefetchHooks Function({
        bool groupId,
        bool chaptersRefs,
        bool readingProgressRecordsRefs,
        bool bookmarksRefs,
      })
    >;
typedef $$ChaptersTableCreateCompanionBuilder = ChaptersCompanion Function({
  Value<int> id,
  required String bookId,
  required int chapterIndex,
  required String title,
  Value<String?> url,
  Value<int?> byteStart,
  Value<int?> byteEnd,
  Value<String?> epubHref,
  Value<bool> isCached,
  Value<String?> cacheKey,
  Value<int> wordCount,
  required int updatedAt,
});
typedef $$ChaptersTableUpdateCompanionBuilder = ChaptersCompanion Function({
  Value<int> id,
  Value<String> bookId,
  Value<int> chapterIndex,
  Value<String> title,
  Value<String?> url,
  Value<int?> byteStart,
  Value<int?> byteEnd,
  Value<String?> epubHref,
  Value<bool> isCached,
  Value<String?> cacheKey,
  Value<int> wordCount,
  Value<int> updatedAt,
});

final class $$ChaptersTableReferences
    extends BaseReferences<_$AppDatabase, $ChaptersTable, ChapterRow> {
  $$ChaptersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('chapters__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChaptersTableFilterComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteStart => $composableBuilder(
    column: $table.byteStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteEnd => $composableBuilder(
    column: $table.byteEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get epubHref => $composableBuilder(
    column: $table.epubHref,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCached => $composableBuilder(
    column: $table.isCached,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteStart => $composableBuilder(
    column: $table.byteStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteEnd => $composableBuilder(
    column: $table.byteEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get epubHref => $composableBuilder(
    column: $table.epubHref,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCached => $composableBuilder(
    column: $table.isCached,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChaptersTable> {
  $$ChaptersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<int> get byteStart =>
      $composableBuilder(column: $table.byteStart, builder: (column) => column);

  GeneratedColumn<int> get byteEnd =>
      $composableBuilder(column: $table.byteEnd, builder: (column) => column);

  GeneratedColumn<String> get epubHref =>
      $composableBuilder(column: $table.epubHref, builder: (column) => column);

  GeneratedColumn<bool> get isCached =>
      $composableBuilder(column: $table.isCached, builder: (column) => column);

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<int> get wordCount =>
      $composableBuilder(column: $table.wordCount, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChaptersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChaptersTable,
          ChapterRow,
          $$ChaptersTableFilterComposer,
          $$ChaptersTableOrderingComposer,
          $$ChaptersTableAnnotationComposer,
          $$ChaptersTableCreateCompanionBuilder,
          $$ChaptersTableUpdateCompanionBuilder,
          (ChapterRow, $$ChaptersTableReferences),
          ChapterRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$ChaptersTableTableManager(_$AppDatabase db, $ChaptersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChaptersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChaptersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChaptersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<int?> byteStart = const Value.absent(),
                Value<int?> byteEnd = const Value.absent(),
                Value<String?> epubHref = const Value.absent(),
                Value<bool> isCached = const Value.absent(),
                Value<String?> cacheKey = const Value.absent(),
                Value<int> wordCount = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => ChaptersCompanion(
                id: id,
                bookId: bookId,
                chapterIndex: chapterIndex,
                title: title,
                url: url,
                byteStart: byteStart,
                byteEnd: byteEnd,
                epubHref: epubHref,
                isCached: isCached,
                cacheKey: cacheKey,
                wordCount: wordCount,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bookId,
                required int chapterIndex,
                required String title,
                Value<String?> url = const Value.absent(),
                Value<int?> byteStart = const Value.absent(),
                Value<int?> byteEnd = const Value.absent(),
                Value<String?> epubHref = const Value.absent(),
                Value<bool> isCached = const Value.absent(),
                Value<String?> cacheKey = const Value.absent(),
                Value<int> wordCount = const Value.absent(),
                required int updatedAt,
              }) => ChaptersCompanion.insert(
                id: id,
                bookId: bookId,
                chapterIndex: chapterIndex,
                title: title,
                url: url,
                byteStart: byteStart,
                byteEnd: byteEnd,
                epubHref: epubHref,
                isCached: isCached,
                cacheKey: cacheKey,
                wordCount: wordCount,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChaptersTable, ChapterRow>(table),
                  $$ChaptersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$ChaptersTableReferences._bookIdTable(
                          db,
                        ),
                        referencedColumn: $$ChaptersTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChaptersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChaptersTable,
      ChapterRow,
      $$ChaptersTableFilterComposer,
      $$ChaptersTableOrderingComposer,
      $$ChaptersTableAnnotationComposer,
      $$ChaptersTableCreateCompanionBuilder,
      $$ChaptersTableUpdateCompanionBuilder,
      (ChapterRow, $$ChaptersTableReferences),
      ChapterRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ReadingProgressRecordsTableCreateCompanionBuilder =
    ReadingProgressRecordsCompanion Function({
      required String bookId,
      Value<int> chapterIndex,
      Value<int> charOffset,
      Value<String> chapterTitleSnapshot,
      Value<double> progressPercent,
      Value<int> readingDurationSec,
      required int updatedAt,
      Value<String> deviceId,
      Value<int> rowid,
    });
typedef $$ReadingProgressRecordsTableUpdateCompanionBuilder =
    ReadingProgressRecordsCompanion Function({
      Value<String> bookId,
      Value<int> chapterIndex,
      Value<int> charOffset,
      Value<String> chapterTitleSnapshot,
      Value<double> progressPercent,
      Value<int> readingDurationSec,
      Value<int> updatedAt,
      Value<String> deviceId,
      Value<int> rowid,
    });

final class $$ReadingProgressRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReadingProgressRecordsTable,
          ReadingProgressRow
        > {
  $$ReadingProgressRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('reading_progress__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingProgressRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressRecordsTable> {
  $$ReadingProgressRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitleSnapshot => $composableBuilder(
    column: $table.chapterTitleSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readingDurationSec => $composableBuilder(
    column: $table.readingDurationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressRecordsTable> {
  $$ReadingProgressRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitleSnapshot => $composableBuilder(
    column: $table.chapterTitleSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readingDurationSec => $composableBuilder(
    column: $table.readingDurationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressRecordsTable> {
  $$ReadingProgressRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterTitleSnapshot => $composableBuilder(
    column: $table.chapterTitleSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get readingDurationSec => $composableBuilder(
    column: $table.readingDurationSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressRecordsTable,
          ReadingProgressRow,
          $$ReadingProgressRecordsTableFilterComposer,
          $$ReadingProgressRecordsTableOrderingComposer,
          $$ReadingProgressRecordsTableAnnotationComposer,
          $$ReadingProgressRecordsTableCreateCompanionBuilder,
          $$ReadingProgressRecordsTableUpdateCompanionBuilder,
          (ReadingProgressRow, $$ReadingProgressRecordsTableReferences),
          ReadingProgressRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReadingProgressRecordsTableTableManager(
    _$AppDatabase db,
    $ReadingProgressRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ReadingProgressRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReadingProgressRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<String> chapterTitleSnapshot = const Value.absent(),
                Value<double> progressPercent = const Value.absent(),
                Value<int> readingDurationSec = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressRecordsCompanion(
                bookId: bookId,
                chapterIndex: chapterIndex,
                charOffset: charOffset,
                chapterTitleSnapshot: chapterTitleSnapshot,
                progressPercent: progressPercent,
                readingDurationSec: readingDurationSec,
                updatedAt: updatedAt,
                deviceId: deviceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                Value<int> chapterIndex = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<String> chapterTitleSnapshot = const Value.absent(),
                Value<double> progressPercent = const Value.absent(),
                Value<int> readingDurationSec = const Value.absent(),
                required int updatedAt,
                Value<String> deviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressRecordsCompanion.insert(
                bookId: bookId,
                chapterIndex: chapterIndex,
                charOffset: charOffset,
                chapterTitleSnapshot: chapterTitleSnapshot,
                progressPercent: progressPercent,
                readingDurationSec: readingDurationSec,
                updatedAt: updatedAt,
                deviceId: deviceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReadingProgressRecordsTable, ReadingProgressRow>(
                    table,
                  ),
                  $$ReadingProgressRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$ReadingProgressRecordsTableReferences
                            ._bookIdTable(db),
                        referencedColumn:
                            $$ReadingProgressRecordsTableReferences
                                ._bookIdTable(db)
                                .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReadingProgressRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressRecordsTable,
      ReadingProgressRow,
      $$ReadingProgressRecordsTableFilterComposer,
      $$ReadingProgressRecordsTableOrderingComposer,
      $$ReadingProgressRecordsTableAnnotationComposer,
      $$ReadingProgressRecordsTableCreateCompanionBuilder,
      $$ReadingProgressRecordsTableUpdateCompanionBuilder,
      (ReadingProgressRow, $$ReadingProgressRecordsTableReferences),
      ReadingProgressRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$BookmarksTableCreateCompanionBuilder = BookmarksCompanion Function({
  required String id,
  required String bookId,
  required int chapterIndex,
  required int charOffset,
  required String excerpt,
  Value<String> note,
  required int createdAt,
  Value<int> rowid,
});
typedef $$BookmarksTableUpdateCompanionBuilder = BookmarksCompanion Function({
  Value<String> id,
  Value<String> bookId,
  Value<int> chapterIndex,
  Value<int> charOffset,
  Value<String> excerpt,
  Value<String> note,
  Value<int> createdAt,
  Value<int> rowid,
});

final class $$BookmarksTableReferences
    extends BaseReferences<_$AppDatabase, $BookmarksTable, BookmarkRow> {
  $$BookmarksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('bookmarks__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookmarksTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excerpt => $composableBuilder(
    column: $table.excerpt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excerpt => $composableBuilder(
    column: $table.excerpt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get excerpt =>
      $composableBuilder(column: $table.excerpt, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookmarksTable,
          BookmarkRow,
          $$BookmarksTableFilterComposer,
          $$BookmarksTableOrderingComposer,
          $$BookmarksTableAnnotationComposer,
          $$BookmarksTableCreateCompanionBuilder,
          $$BookmarksTableUpdateCompanionBuilder,
          (BookmarkRow, $$BookmarksTableReferences),
          BookmarkRow,
          PrefetchHooks Function({bool bookId})
        > {
  $$BookmarksTableTableManager(_$AppDatabase db, $BookmarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<String> excerpt = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion(
                id: id,
                bookId: bookId,
                chapterIndex: chapterIndex,
                charOffset: charOffset,
                excerpt: excerpt,
                note: note,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required int chapterIndex,
                required int charOffset,
                required String excerpt,
                Value<String> note = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion.insert(
                id: id,
                bookId: bookId,
                chapterIndex: chapterIndex,
                charOffset: charOffset,
                excerpt: excerpt,
                note: note,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookmarksTable, BookmarkRow>(table),
                  $$BookmarksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.bookId,
                        referencedTable: $$BookmarksTableReferences
                            ._bookIdTable(db),
                        referencedColumn: $$BookmarksTableReferences
                            ._bookIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookmarksTable,
      BookmarkRow,
      $$BookmarksTableFilterComposer,
      $$BookmarksTableOrderingComposer,
      $$BookmarksTableAnnotationComposer,
      $$BookmarksTableCreateCompanionBuilder,
      $$BookmarksTableUpdateCompanionBuilder,
      (BookmarkRow, $$BookmarksTableReferences),
      BookmarkRow,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$BookSourcesTableCreateCompanionBuilder =
    BookSourcesCompanion Function({
      required String id,
      required String name,
      Value<String> groupName,
      required String engineType,
      required String baseUrl,
      required String rawDefinition,
      Value<bool> enabled,
      Value<int> weight,
      Value<int> rateLimitMs,
      Value<String> lastCheckStatus,
      Value<String?> lastErrorSummary,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$BookSourcesTableUpdateCompanionBuilder =
    BookSourcesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> groupName,
      Value<String> engineType,
      Value<String> baseUrl,
      Value<String> rawDefinition,
      Value<bool> enabled,
      Value<int> weight,
      Value<int> rateLimitMs,
      Value<String> lastCheckStatus,
      Value<String?> lastErrorSummary,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$BookSourcesTableFilterComposer
    extends Composer<_$AppDatabase, $BookSourcesTable> {
  $$BookSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engineType => $composableBuilder(
    column: $table.engineType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawDefinition => $composableBuilder(
    column: $table.rawDefinition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rateLimitMs => $composableBuilder(
    column: $table.rateLimitMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCheckStatus => $composableBuilder(
    column: $table.lastCheckStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorSummary => $composableBuilder(
    column: $table.lastErrorSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BookSourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $BookSourcesTable> {
  $$BookSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engineType => $composableBuilder(
    column: $table.engineType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawDefinition => $composableBuilder(
    column: $table.rawDefinition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rateLimitMs => $composableBuilder(
    column: $table.rateLimitMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCheckStatus => $composableBuilder(
    column: $table.lastCheckStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorSummary => $composableBuilder(
    column: $table.lastErrorSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookSourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookSourcesTable> {
  $$BookSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<String> get engineType => $composableBuilder(
    column: $table.engineType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get rawDefinition => $composableBuilder(
    column: $table.rawDefinition,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<int> get rateLimitMs => $composableBuilder(
    column: $table.rateLimitMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCheckStatus => $composableBuilder(
    column: $table.lastCheckStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorSummary => $composableBuilder(
    column: $table.lastErrorSummary,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BookSourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookSourcesTable,
          BookSourceRow,
          $$BookSourcesTableFilterComposer,
          $$BookSourcesTableOrderingComposer,
          $$BookSourcesTableAnnotationComposer,
          $$BookSourcesTableCreateCompanionBuilder,
          $$BookSourcesTableUpdateCompanionBuilder,
          (
            BookSourceRow,
            BaseReferences<_$AppDatabase, $BookSourcesTable, BookSourceRow>,
          ),
          BookSourceRow,
          PrefetchHooks Function()
        > {
  $$BookSourcesTableTableManager(_$AppDatabase db, $BookSourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> groupName = const Value.absent(),
                Value<String> engineType = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String> rawDefinition = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> weight = const Value.absent(),
                Value<int> rateLimitMs = const Value.absent(),
                Value<String> lastCheckStatus = const Value.absent(),
                Value<String?> lastErrorSummary = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookSourcesCompanion(
                id: id,
                name: name,
                groupName: groupName,
                engineType: engineType,
                baseUrl: baseUrl,
                rawDefinition: rawDefinition,
                enabled: enabled,
                weight: weight,
                rateLimitMs: rateLimitMs,
                lastCheckStatus: lastCheckStatus,
                lastErrorSummary: lastErrorSummary,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> groupName = const Value.absent(),
                required String engineType,
                required String baseUrl,
                required String rawDefinition,
                Value<bool> enabled = const Value.absent(),
                Value<int> weight = const Value.absent(),
                Value<int> rateLimitMs = const Value.absent(),
                Value<String> lastCheckStatus = const Value.absent(),
                Value<String?> lastErrorSummary = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BookSourcesCompanion.insert(
                id: id,
                name: name,
                groupName: groupName,
                engineType: engineType,
                baseUrl: baseUrl,
                rawDefinition: rawDefinition,
                enabled: enabled,
                weight: weight,
                rateLimitMs: rateLimitMs,
                lastCheckStatus: lastCheckStatus,
                lastErrorSummary: lastErrorSummary,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookSourcesTable, BookSourceRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $BookSourcesTable,
                    BookSourceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BookSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookSourcesTable,
      BookSourceRow,
      $$BookSourcesTableFilterComposer,
      $$BookSourcesTableOrderingComposer,
      $$BookSourcesTableAnnotationComposer,
      $$BookSourcesTableCreateCompanionBuilder,
      $$BookSourcesTableUpdateCompanionBuilder,
      (
        BookSourceRow,
        BaseReferences<_$AppDatabase, $BookSourcesTable, BookSourceRow>,
      ),
      BookSourceRow,
      PrefetchHooks Function()
    >;
typedef $$ReplaceRulesTableCreateCompanionBuilder =
    ReplaceRulesCompanion Function({
      required String id,
      required String name,
      Value<String> groupName,
      required String pattern,
      Value<String> replacement,
      Value<bool> isRegex,
      Value<String> scopeType,
      Value<String?> scopeTargetId,
      Value<bool> enabled,
      Value<int> sortOrder,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$ReplaceRulesTableUpdateCompanionBuilder =
    ReplaceRulesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> groupName,
      Value<String> pattern,
      Value<String> replacement,
      Value<bool> isRegex,
      Value<String> scopeType,
      Value<String?> scopeTargetId,
      Value<bool> enabled,
      Value<int> sortOrder,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$ReplaceRulesTableFilterComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replacement => $composableBuilder(
    column: $table.replacement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRegex => $composableBuilder(
    column: $table.isRegex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeTargetId => $composableBuilder(
    column: $table.scopeTargetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReplaceRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replacement => $composableBuilder(
    column: $table.replacement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRegex => $composableBuilder(
    column: $table.isRegex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeType => $composableBuilder(
    column: $table.scopeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeTargetId => $composableBuilder(
    column: $table.scopeTargetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReplaceRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReplaceRulesTable> {
  $$ReplaceRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumn<String> get replacement => $composableBuilder(
    column: $table.replacement,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRegex =>
      $composableBuilder(column: $table.isRegex, builder: (column) => column);

  GeneratedColumn<String> get scopeType =>
      $composableBuilder(column: $table.scopeType, builder: (column) => column);

  GeneratedColumn<String> get scopeTargetId => $composableBuilder(
    column: $table.scopeTargetId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReplaceRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReplaceRulesTable,
          ReplaceRuleRow,
          $$ReplaceRulesTableFilterComposer,
          $$ReplaceRulesTableOrderingComposer,
          $$ReplaceRulesTableAnnotationComposer,
          $$ReplaceRulesTableCreateCompanionBuilder,
          $$ReplaceRulesTableUpdateCompanionBuilder,
          (
            ReplaceRuleRow,
            BaseReferences<_$AppDatabase, $ReplaceRulesTable, ReplaceRuleRow>,
          ),
          ReplaceRuleRow,
          PrefetchHooks Function()
        > {
  $$ReplaceRulesTableTableManager(_$AppDatabase db, $ReplaceRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReplaceRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReplaceRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReplaceRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> groupName = const Value.absent(),
                Value<String> pattern = const Value.absent(),
                Value<String> replacement = const Value.absent(),
                Value<bool> isRegex = const Value.absent(),
                Value<String> scopeType = const Value.absent(),
                Value<String?> scopeTargetId = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReplaceRulesCompanion(
                id: id,
                name: name,
                groupName: groupName,
                pattern: pattern,
                replacement: replacement,
                isRegex: isRegex,
                scopeType: scopeType,
                scopeTargetId: scopeTargetId,
                enabled: enabled,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> groupName = const Value.absent(),
                required String pattern,
                Value<String> replacement = const Value.absent(),
                Value<bool> isRegex = const Value.absent(),
                Value<String> scopeType = const Value.absent(),
                Value<String?> scopeTargetId = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReplaceRulesCompanion.insert(
                id: id,
                name: name,
                groupName: groupName,
                pattern: pattern,
                replacement: replacement,
                isRegex: isRegex,
                scopeType: scopeType,
                scopeTargetId: scopeTargetId,
                enabled: enabled,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReplaceRulesTable, ReplaceRuleRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReplaceRulesTable,
                    ReplaceRuleRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReplaceRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReplaceRulesTable,
      ReplaceRuleRow,
      $$ReplaceRulesTableFilterComposer,
      $$ReplaceRulesTableOrderingComposer,
      $$ReplaceRulesTableAnnotationComposer,
      $$ReplaceRulesTableCreateCompanionBuilder,
      $$ReplaceRulesTableUpdateCompanionBuilder,
      (
        ReplaceRuleRow,
        BaseReferences<_$AppDatabase, $ReplaceRulesTable, ReplaceRuleRow>,
      ),
      ReplaceRuleRow,
      PrefetchHooks Function()
    >;
typedef $$ReaderThemesTableCreateCompanionBuilder =
    ReaderThemesCompanion Function({
      required String id,
      required String name,
      Value<bool> isBuiltin,
      Value<bool> isDark,
      required int bgColor,
      required int textColor,
      required int secondaryTextColor,
      Value<String?> bgTexturePath,
      Value<String> fontFamily,
      Value<String?> fontPath,
      Value<double> fontSize,
      Value<int> fontWeight,
      Value<double> lineHeight,
      Value<double> paragraphSpacing,
      Value<double> letterSpacing,
      Value<int> paragraphIndentChars,
      Value<double> marginHorizontal,
      Value<double> marginVertical,
      Value<String> columnMode,
      Value<double> maxContentWidth,
      Value<String> pageTurnMode,
      Value<bool> enablePunctuationHanging,
      Value<bool> enableCjkSpacing,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$ReaderThemesTableUpdateCompanionBuilder =
    ReaderThemesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<bool> isBuiltin,
      Value<bool> isDark,
      Value<int> bgColor,
      Value<int> textColor,
      Value<int> secondaryTextColor,
      Value<String?> bgTexturePath,
      Value<String> fontFamily,
      Value<String?> fontPath,
      Value<double> fontSize,
      Value<int> fontWeight,
      Value<double> lineHeight,
      Value<double> paragraphSpacing,
      Value<double> letterSpacing,
      Value<int> paragraphIndentChars,
      Value<double> marginHorizontal,
      Value<double> marginVertical,
      Value<String> columnMode,
      Value<double> maxContentWidth,
      Value<String> pageTurnMode,
      Value<bool> enablePunctuationHanging,
      Value<bool> enableCjkSpacing,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$ReaderThemesTableFilterComposer
    extends Composer<_$AppDatabase, $ReaderThemesTable> {
  $$ReaderThemesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDark => $composableBuilder(
    column: $table.isDark,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bgColor => $composableBuilder(
    column: $table.bgColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get textColor => $composableBuilder(
    column: $table.textColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get secondaryTextColor => $composableBuilder(
    column: $table.secondaryTextColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bgTexturePath => $composableBuilder(
    column: $table.bgTexturePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fontFamily => $composableBuilder(
    column: $table.fontFamily,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fontPath => $composableBuilder(
    column: $table.fontPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fontSize => $composableBuilder(
    column: $table.fontSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fontWeight => $composableBuilder(
    column: $table.fontWeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lineHeight => $composableBuilder(
    column: $table.lineHeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get paragraphSpacing => $composableBuilder(
    column: $table.paragraphSpacing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get letterSpacing => $composableBuilder(
    column: $table.letterSpacing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paragraphIndentChars => $composableBuilder(
    column: $table.paragraphIndentChars,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get marginHorizontal => $composableBuilder(
    column: $table.marginHorizontal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get marginVertical => $composableBuilder(
    column: $table.marginVertical,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get columnMode => $composableBuilder(
    column: $table.columnMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxContentWidth => $composableBuilder(
    column: $table.maxContentWidth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageTurnMode => $composableBuilder(
    column: $table.pageTurnMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enablePunctuationHanging => $composableBuilder(
    column: $table.enablePunctuationHanging,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enableCjkSpacing => $composableBuilder(
    column: $table.enableCjkSpacing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReaderThemesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReaderThemesTable> {
  $$ReaderThemesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDark => $composableBuilder(
    column: $table.isDark,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bgColor => $composableBuilder(
    column: $table.bgColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get textColor => $composableBuilder(
    column: $table.textColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get secondaryTextColor => $composableBuilder(
    column: $table.secondaryTextColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bgTexturePath => $composableBuilder(
    column: $table.bgTexturePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fontFamily => $composableBuilder(
    column: $table.fontFamily,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fontPath => $composableBuilder(
    column: $table.fontPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fontSize => $composableBuilder(
    column: $table.fontSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fontWeight => $composableBuilder(
    column: $table.fontWeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lineHeight => $composableBuilder(
    column: $table.lineHeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get paragraphSpacing => $composableBuilder(
    column: $table.paragraphSpacing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get letterSpacing => $composableBuilder(
    column: $table.letterSpacing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paragraphIndentChars => $composableBuilder(
    column: $table.paragraphIndentChars,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get marginHorizontal => $composableBuilder(
    column: $table.marginHorizontal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get marginVertical => $composableBuilder(
    column: $table.marginVertical,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get columnMode => $composableBuilder(
    column: $table.columnMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxContentWidth => $composableBuilder(
    column: $table.maxContentWidth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageTurnMode => $composableBuilder(
    column: $table.pageTurnMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enablePunctuationHanging => $composableBuilder(
    column: $table.enablePunctuationHanging,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enableCjkSpacing => $composableBuilder(
    column: $table.enableCjkSpacing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReaderThemesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReaderThemesTable> {
  $$ReaderThemesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isBuiltin =>
      $composableBuilder(column: $table.isBuiltin, builder: (column) => column);

  GeneratedColumn<bool> get isDark =>
      $composableBuilder(column: $table.isDark, builder: (column) => column);

  GeneratedColumn<int> get bgColor =>
      $composableBuilder(column: $table.bgColor, builder: (column) => column);

  GeneratedColumn<int> get textColor =>
      $composableBuilder(column: $table.textColor, builder: (column) => column);

  GeneratedColumn<int> get secondaryTextColor => $composableBuilder(
    column: $table.secondaryTextColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bgTexturePath => $composableBuilder(
    column: $table.bgTexturePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fontFamily => $composableBuilder(
    column: $table.fontFamily,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fontPath =>
      $composableBuilder(column: $table.fontPath, builder: (column) => column);

  GeneratedColumn<double> get fontSize =>
      $composableBuilder(column: $table.fontSize, builder: (column) => column);

  GeneratedColumn<int> get fontWeight => $composableBuilder(
    column: $table.fontWeight,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lineHeight => $composableBuilder(
    column: $table.lineHeight,
    builder: (column) => column,
  );

  GeneratedColumn<double> get paragraphSpacing => $composableBuilder(
    column: $table.paragraphSpacing,
    builder: (column) => column,
  );

  GeneratedColumn<double> get letterSpacing => $composableBuilder(
    column: $table.letterSpacing,
    builder: (column) => column,
  );

  GeneratedColumn<int> get paragraphIndentChars => $composableBuilder(
    column: $table.paragraphIndentChars,
    builder: (column) => column,
  );

  GeneratedColumn<double> get marginHorizontal => $composableBuilder(
    column: $table.marginHorizontal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get marginVertical => $composableBuilder(
    column: $table.marginVertical,
    builder: (column) => column,
  );

  GeneratedColumn<String> get columnMode => $composableBuilder(
    column: $table.columnMode,
    builder: (column) => column,
  );

  GeneratedColumn<double> get maxContentWidth => $composableBuilder(
    column: $table.maxContentWidth,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pageTurnMode => $composableBuilder(
    column: $table.pageTurnMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enablePunctuationHanging => $composableBuilder(
    column: $table.enablePunctuationHanging,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enableCjkSpacing => $composableBuilder(
    column: $table.enableCjkSpacing,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReaderThemesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReaderThemesTable,
          ReaderThemeRow,
          $$ReaderThemesTableFilterComposer,
          $$ReaderThemesTableOrderingComposer,
          $$ReaderThemesTableAnnotationComposer,
          $$ReaderThemesTableCreateCompanionBuilder,
          $$ReaderThemesTableUpdateCompanionBuilder,
          (
            ReaderThemeRow,
            BaseReferences<_$AppDatabase, $ReaderThemesTable, ReaderThemeRow>,
          ),
          ReaderThemeRow,
          PrefetchHooks Function()
        > {
  $$ReaderThemesTableTableManager(_$AppDatabase db, $ReaderThemesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReaderThemesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReaderThemesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReaderThemesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isBuiltin = const Value.absent(),
                Value<bool> isDark = const Value.absent(),
                Value<int> bgColor = const Value.absent(),
                Value<int> textColor = const Value.absent(),
                Value<int> secondaryTextColor = const Value.absent(),
                Value<String?> bgTexturePath = const Value.absent(),
                Value<String> fontFamily = const Value.absent(),
                Value<String?> fontPath = const Value.absent(),
                Value<double> fontSize = const Value.absent(),
                Value<int> fontWeight = const Value.absent(),
                Value<double> lineHeight = const Value.absent(),
                Value<double> paragraphSpacing = const Value.absent(),
                Value<double> letterSpacing = const Value.absent(),
                Value<int> paragraphIndentChars = const Value.absent(),
                Value<double> marginHorizontal = const Value.absent(),
                Value<double> marginVertical = const Value.absent(),
                Value<String> columnMode = const Value.absent(),
                Value<double> maxContentWidth = const Value.absent(),
                Value<String> pageTurnMode = const Value.absent(),
                Value<bool> enablePunctuationHanging = const Value.absent(),
                Value<bool> enableCjkSpacing = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReaderThemesCompanion(
                id: id,
                name: name,
                isBuiltin: isBuiltin,
                isDark: isDark,
                bgColor: bgColor,
                textColor: textColor,
                secondaryTextColor: secondaryTextColor,
                bgTexturePath: bgTexturePath,
                fontFamily: fontFamily,
                fontPath: fontPath,
                fontSize: fontSize,
                fontWeight: fontWeight,
                lineHeight: lineHeight,
                paragraphSpacing: paragraphSpacing,
                letterSpacing: letterSpacing,
                paragraphIndentChars: paragraphIndentChars,
                marginHorizontal: marginHorizontal,
                marginVertical: marginVertical,
                columnMode: columnMode,
                maxContentWidth: maxContentWidth,
                pageTurnMode: pageTurnMode,
                enablePunctuationHanging: enablePunctuationHanging,
                enableCjkSpacing: enableCjkSpacing,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<bool> isBuiltin = const Value.absent(),
                Value<bool> isDark = const Value.absent(),
                required int bgColor,
                required int textColor,
                required int secondaryTextColor,
                Value<String?> bgTexturePath = const Value.absent(),
                Value<String> fontFamily = const Value.absent(),
                Value<String?> fontPath = const Value.absent(),
                Value<double> fontSize = const Value.absent(),
                Value<int> fontWeight = const Value.absent(),
                Value<double> lineHeight = const Value.absent(),
                Value<double> paragraphSpacing = const Value.absent(),
                Value<double> letterSpacing = const Value.absent(),
                Value<int> paragraphIndentChars = const Value.absent(),
                Value<double> marginHorizontal = const Value.absent(),
                Value<double> marginVertical = const Value.absent(),
                Value<String> columnMode = const Value.absent(),
                Value<double> maxContentWidth = const Value.absent(),
                Value<String> pageTurnMode = const Value.absent(),
                Value<bool> enablePunctuationHanging = const Value.absent(),
                Value<bool> enableCjkSpacing = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReaderThemesCompanion.insert(
                id: id,
                name: name,
                isBuiltin: isBuiltin,
                isDark: isDark,
                bgColor: bgColor,
                textColor: textColor,
                secondaryTextColor: secondaryTextColor,
                bgTexturePath: bgTexturePath,
                fontFamily: fontFamily,
                fontPath: fontPath,
                fontSize: fontSize,
                fontWeight: fontWeight,
                lineHeight: lineHeight,
                paragraphSpacing: paragraphSpacing,
                letterSpacing: letterSpacing,
                paragraphIndentChars: paragraphIndentChars,
                marginHorizontal: marginHorizontal,
                marginVertical: marginVertical,
                columnMode: columnMode,
                maxContentWidth: maxContentWidth,
                pageTurnMode: pageTurnMode,
                enablePunctuationHanging: enablePunctuationHanging,
                enableCjkSpacing: enableCjkSpacing,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReaderThemesTable, ReaderThemeRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReaderThemesTable,
                    ReaderThemeRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReaderThemesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReaderThemesTable,
      ReaderThemeRow,
      $$ReaderThemesTableFilterComposer,
      $$ReaderThemesTableOrderingComposer,
      $$ReaderThemesTableAnnotationComposer,
      $$ReaderThemesTableCreateCompanionBuilder,
      $$ReaderThemesTableUpdateCompanionBuilder,
      (
        ReaderThemeRow,
        BaseReferences<_$AppDatabase, $ReaderThemesTable, ReaderThemeRow>,
      ),
      ReaderThemeRow,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSettingRow,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSettingRow,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>,
          ),
          AppSettingRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSettingRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AppSettingsTable,
                    AppSettingRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSettingRow,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSettingRow,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>,
      ),
      AppSettingRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BookGroupsTableTableManager get bookGroups =>
      $$BookGroupsTableTableManager(_db, _db.bookGroups);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db, _db.chapters);
  $$ReadingProgressRecordsTableTableManager get readingProgressRecords =>
      $$ReadingProgressRecordsTableTableManager(
        _db,
        _db.readingProgressRecords,
      );
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
  $$BookSourcesTableTableManager get bookSources =>
      $$BookSourcesTableTableManager(_db, _db.bookSources);
  $$ReplaceRulesTableTableManager get replaceRules =>
      $$ReplaceRulesTableTableManager(_db, _db.replaceRules);
  $$ReaderThemesTableTableManager get readerThemes =>
      $$ReaderThemesTableTableManager(_db, _db.readerThemes);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
