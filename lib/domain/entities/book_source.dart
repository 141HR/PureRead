/// Supported online book source engine types.
enum SourceEngineType { jsPlugin, legado }

/// Health status of a configured [BookSource].
enum SourceCheckStatus { unknown, ok, error, unsupported }

/// Book source definition corresponding to the `book_sources` table.
class BookSource {
  final String id;
  final String name;
  final String groupName;
  final SourceEngineType engineType;
  final String baseUrl;
  final String rawDefinition;
  final bool enabled;
  final int weight;
  final int rateLimitMs;
  final SourceCheckStatus lastCheckStatus;
  final String? lastErrorSummary;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BookSource({
    required this.id,
    required this.name,
    this.groupName = '默认',
    required this.engineType,
    required this.baseUrl,
    required this.rawDefinition,
    this.enabled = true,
    this.weight = 0,
    this.rateLimitMs = 500,
    this.lastCheckStatus = SourceCheckStatus.unknown,
    this.lastErrorSummary,
    required this.createdAt,
    required this.updatedAt,
  });

  BookSource copyWith({
    String? id,
    String? name,
    String? groupName,
    SourceEngineType? engineType,
    String? baseUrl,
    String? rawDefinition,
    bool? enabled,
    int? weight,
    int? rateLimitMs,
    SourceCheckStatus? lastCheckStatus,
    String? lastErrorSummary,
    bool clearLastErrorSummary = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BookSource(
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
      lastErrorSummary: clearLastErrorSummary
          ? null
          : (lastErrorSummary ?? this.lastErrorSummary),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookSource &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          groupName == other.groupName &&
          engineType == other.engineType &&
          baseUrl == other.baseUrl &&
          rawDefinition == other.rawDefinition &&
          enabled == other.enabled &&
          weight == other.weight &&
          rateLimitMs == other.rateLimitMs &&
          lastCheckStatus == other.lastCheckStatus &&
          lastErrorSummary == other.lastErrorSummary &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

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
}
