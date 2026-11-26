/// Supported book provider driver types.
enum ProviderType { localTxt, localEpub, jsPlugin, legado }

/// Declares the capabilities supported by a [BookProvider] implementation.
class ProviderCapabilities {
  final bool isLocal;
  final bool supportsSearch;
  final bool supportsUpdateCheck;
  final bool supportsChangeSource;
  final bool supportsExplore;

  const ProviderCapabilities({
    required this.isLocal,
    required this.supportsSearch,
    required this.supportsUpdateCheck,
    required this.supportsChangeSource,
    this.supportsExplore = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderCapabilities &&
          runtimeType == other.runtimeType &&
          isLocal == other.isLocal &&
          supportsSearch == other.supportsSearch &&
          supportsUpdateCheck == other.supportsUpdateCheck &&
          supportsChangeSource == other.supportsChangeSource &&
          supportsExplore == other.supportsExplore;

  @override
  int get hashCode => Object.hash(
        isLocal,
        supportsSearch,
        supportsUpdateCheck,
        supportsChangeSource,
        supportsExplore,
      );

  @override
  String toString() =>
      'ProviderCapabilities(isLocal: $isLocal, supportsSearch: $supportsSearch, '
      'supportsUpdateCheck: $supportsUpdateCheck, '
      'supportsChangeSource: $supportsChangeSource, '
      'supportsExplore: $supportsExplore)';
}
