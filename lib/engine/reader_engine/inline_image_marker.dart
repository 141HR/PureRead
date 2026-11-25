/// Parsed payload from an inline EPUB image placeholder line.
class InlineImageRef {
  const InlineImageRef({
    required this.archivePath,
    this.width = 0,
    this.height = 0,
    this.alt = '',
  });

  final String archivePath;
  final int width;
  final int height;
  final String alt;

  bool get hasDimensions => width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InlineImageRef &&
          runtimeType == other.runtimeType &&
          archivePath == other.archivePath &&
          width == other.width &&
          height == other.height &&
          alt == other.alt;

  @override
  int get hashCode => Object.hash(archivePath, width, height, alt);

  @override
  String toString() =>
      'InlineImageRef(archivePath: $archivePath, width: $width, '
      'height: $height, alt: $alt)';
}

/// Wire contract codec and helpers for standalone EPUB inline image marker
/// lines embedded in extracted chapter text.
class InlineImageMarker {
  const InlineImageMarker._();

  static const String prefix = '\uFFFCprimg:v1:';
  static const String suffix = '\uFFFC';

  static final RegExp _leadingSlashRegex = RegExp(r'^/+');
  static final RegExp _altWhitespaceRegex = RegExp(r'[\r\n\t]+');

  /// Encodes a normalized EPUB image reference into a standalone marker line.
  static String encode({
    required String archivePath,
    int width = 0,
    int height = 0,
    String alt = '',
  }) {
    final normalizedPath = archivePath
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(_leadingSlashRegex, '');
    final safeWidth = width < 0 ? 0 : width;
    final safeHeight = height < 0 ? 0 : height;
    final normalizedAlt = alt.replaceAll(_altWhitespaceRegex, ' ').trim();

    final encodedPath = Uri.encodeComponent(normalizedPath);
    final encodedAlt = Uri.encodeComponent(normalizedAlt);
    return '$prefix$encodedPath|${safeWidth}x$safeHeight|$encodedAlt$suffix';
  }

  /// Parses a single standalone chapter line if it matches [prefix]...[suffix].
  ///
  /// Returns `null` when [rawLine] is plain text or malformed.
  static InlineImageRef? tryParseLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.length <= prefix.length + suffix.length ||
        !trimmed.startsWith(prefix) ||
        !trimmed.endsWith(suffix)) {
      return null;
    }

    final payload = trimmed.substring(
      prefix.length,
      trimmed.length - suffix.length,
    );
    if (payload.contains(suffix)) {
      return null;
    }

    final parts = payload.split('|');
    if (parts.length != 3) {
      return null;
    }

    final String archivePath;
    final String alt;
    try {
      archivePath = Uri.decodeComponent(parts[0]);
      alt = Uri.decodeComponent(parts[2]);
    } on ArgumentError {
      return null;
    }
    if (archivePath.isEmpty) {
      return null;
    }

    final dimParts = parts[1].split('x');
    if (dimParts.length != 2) {
      return null;
    }
    final width = int.tryParse(dimParts[0]);
    final height = int.tryParse(dimParts[1]);
    if (width == null || height == null || width < 0 || height < 0) {
      return null;
    }

    return InlineImageRef(
      archivePath: archivePath,
      width: width,
      height: height,
      alt: alt,
    );
  }

  /// Returns whether [rawLine] is a valid standalone inline image marker.
  static bool isImageLine(String rawLine) => tryParseLine(rawLine) != null;

  /// Strips standalone image marker lines and collapses resulting extra blank
  /// lines cleanly for excerpts, search snippets, and TTS utterances.
  static String stripMarkers(String text) {
    if (text.isEmpty || !text.contains(prefix)) {
      return text;
    }

    final normalized = text.contains('\r')
        ? text.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
        : text;
    final lines = normalized.split('\n');
    final out = <String>[];
    var lastWasBlank = false;

    for (final line in lines) {
      if (isImageLine(line)) {
        continue;
      }
      if (line.trim().isEmpty) {
        if (out.isEmpty || lastWasBlank) {
          continue;
        }
        out.add('');
        lastWasBlank = true;
      } else {
        out.add(line);
        lastWasBlank = false;
      }
    }

    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }

    return out.join('\n');
  }
}
