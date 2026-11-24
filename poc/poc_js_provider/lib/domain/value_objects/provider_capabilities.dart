/// Supported book provider driver types.
enum ProviderType { localTxt, localEpub, jsPlugin, legado }

/// Declares the capabilities supported by a [BookProvider] implementation.
class ProviderCapabilities {
  final bool isLocal;
  final bool supportsSearch;
  final bool supportsUpdateCheck;
  final bool supportsChangeSource;

  const ProviderCapabilities({
    required this.isLocal,
    required this.supportsSearch,
    required this.supportsUpdateCheck,
    required this.supportsChangeSource,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderCapabilities &&
          runtimeType == other.runtimeType &&
          isLocal == other.isLocal &&
          supportsSearch == other.supportsSearch &&
          supportsUpdateCheck == other.supportsUpdateCheck &&
          supportsChangeSource == other.supportsChangeSource;

  @override
  int get hashCode => Object.hash(
        isLocal,
        supportsSearch,
        supportsUpdateCheck,
        supportsChangeSource,
      );
}
