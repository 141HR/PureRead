/// Discovery / ranking category entry parsed from an online book source's
/// explore configuration (在线书源发现分类/排行榜条目).
class ExploreCategory {
  final String title;
  final String url;
  final String? group;
  final double? layoutFlexBasisPercent;

  const ExploreCategory({
    required this.title,
    this.url = '',
    this.group,
    this.layoutFlexBasisPercent,
  });

  /// Whether this entry acts as a visual section header rather than a
  /// clickable discovery feed.
  bool get isGroupHeader => url.trim().isEmpty;

  ExploreCategory copyWith({
    String? title,
    String? url,
    String? group,
    double? layoutFlexBasisPercent,
  }) {
    return ExploreCategory(
      title: title ?? this.title,
      url: url ?? this.url,
      group: group ?? this.group,
      layoutFlexBasisPercent:
          layoutFlexBasisPercent ?? this.layoutFlexBasisPercent,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExploreCategory &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          url == other.url &&
          group == other.group &&
          layoutFlexBasisPercent == other.layoutFlexBasisPercent;

  @override
  int get hashCode => Object.hash(title, url, group, layoutFlexBasisPercent);

  @override
  String toString() =>
      'ExploreCategory(title: $title, url: $url, group: $group, '
      'layoutFlexBasisPercent: $layoutFlexBasisPercent)';
}
