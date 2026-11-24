/// Scope targeting for a [ReplaceRule].
enum RuleScopeType { global, source, book }

/// Content sanitization rule corresponding to the `replace_rules` table.
class ReplaceRule {
  final String id;
  final String name;
  final String groupName;
  final String pattern;
  final String replacement;
  final bool isRegex;
  final RuleScopeType scopeType;
  final String? scopeTargetId;
  final bool enabled;
  final int sortOrder;
  final DateTime updatedAt;

  const ReplaceRule({
    required this.id,
    required this.name,
    this.groupName = '通用',
    required this.pattern,
    this.replacement = '',
    this.isRegex = true,
    this.scopeType = RuleScopeType.global,
    this.scopeTargetId,
    this.enabled = true,
    this.sortOrder = 0,
    required this.updatedAt,
  });

  ReplaceRule copyWith({
    String? id,
    String? name,
    String? groupName,
    String? pattern,
    String? replacement,
    bool? isRegex,
    RuleScopeType? scopeType,
    String? scopeTargetId,
    bool clearScopeTargetId = false,
    bool? enabled,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return ReplaceRule(
      id: id ?? this.id,
      name: name ?? this.name,
      groupName: groupName ?? this.groupName,
      pattern: pattern ?? this.pattern,
      replacement: replacement ?? this.replacement,
      isRegex: isRegex ?? this.isRegex,
      scopeType: scopeType ?? this.scopeType,
      scopeTargetId: clearScopeTargetId
          ? null
          : (scopeTargetId ?? this.scopeTargetId),
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplaceRule &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          groupName == other.groupName &&
          pattern == other.pattern &&
          replacement == other.replacement &&
          isRegex == other.isRegex &&
          scopeType == other.scopeType &&
          scopeTargetId == other.scopeTargetId &&
          enabled == other.enabled &&
          sortOrder == other.sortOrder &&
          updatedAt == other.updatedAt;

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
}
