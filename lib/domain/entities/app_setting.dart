/// Global key-value application setting corresponding to `app_settings`.
class AppSetting {
  final String key;
  final String value;
  final DateTime updatedAt;

  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSetting &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          value == other.value &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
}
