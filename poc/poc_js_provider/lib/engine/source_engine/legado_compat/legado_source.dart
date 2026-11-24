import 'dart:convert';

class LegadoSearchRule {
  final String bookList;
  final String name;
  final String author;
  final String bookUrl;
  final String coverUrl;
  final String intro;
  final String lastChapter;
  final String kind;

  const LegadoSearchRule({
    required this.bookList,
    required this.name,
    this.author = '',
    required this.bookUrl,
    this.coverUrl = '',
    this.intro = '',
    this.lastChapter = '',
    this.kind = '',
  });

  factory LegadoSearchRule.fromJson(Map<String, dynamic> json) {
    return LegadoSearchRule(
      bookList: (json['bookList'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      bookUrl: (json['bookUrl'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      intro: (json['intro'] ?? '').toString(),
      lastChapter: (json['lastChapter'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
    );
  }
}

class LegadoBookInfoRule {
  final String name;
  final String author;
  final String intro;
  final String coverUrl;
  final String tocUrl;
  final String lastChapter;
  final String kind;
  final bool webView;

  const LegadoBookInfoRule({
    this.name = '',
    this.author = '',
    this.intro = '',
    this.coverUrl = '',
    this.tocUrl = '',
    this.lastChapter = '',
    this.kind = '',
    this.webView = false,
  });

  factory LegadoBookInfoRule.fromJson(Map<String, dynamic> json) {
    return LegadoBookInfoRule(
      name: (json['name'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      intro: (json['intro'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      tocUrl: (json['tocUrl'] ?? '').toString(),
      lastChapter: (json['lastChapter'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      webView: json['webView'] == true,
    );
  }
}

class LegadoTocRule {
  final String chapterList;
  final String chapterName;
  final String chapterUrl;
  final bool webView;

  const LegadoTocRule({
    required this.chapterList,
    required this.chapterName,
    required this.chapterUrl,
    this.webView = false,
  });

  factory LegadoTocRule.fromJson(Map<String, dynamic> json) {
    return LegadoTocRule(
      chapterList: (json['chapterList'] ?? '').toString(),
      chapterName: (json['chapterName'] ?? '').toString(),
      chapterUrl: (json['chapterUrl'] ?? '').toString(),
      webView: json['webView'] == true,
    );
  }
}

class LegadoContentRule {
  final String content;
  final String replaceRegex;
  final bool webView;

  const LegadoContentRule({
    required this.content,
    this.replaceRegex = '',
    this.webView = false,
  });

  factory LegadoContentRule.fromJson(Map<String, dynamic> json) {
    return LegadoContentRule(
      content: (json['content'] ?? '').toString(),
      replaceRegex: (json['replaceRegex'] ?? '').toString(),
      webView: json['webView'] == true,
    );
  }
}

class LegadoBookSource {
  final String bookSourceName;
  final String bookSourceUrl;
  final String? searchUrl;
  final Map<String, String> headers;
  final String? charset;
  final bool webView;
  final LegadoSearchRule ruleSearch;
  final LegadoBookInfoRule ruleBookInfo;
  final LegadoTocRule ruleToc;
  final LegadoContentRule ruleContent;

  const LegadoBookSource({
    required this.bookSourceName,
    required this.bookSourceUrl,
    this.searchUrl,
    this.headers = const {},
    this.charset,
    this.webView = false,
    required this.ruleSearch,
    required this.ruleBookInfo,
    required this.ruleToc,
    required this.ruleContent,
  });

  factory LegadoBookSource.fromJsonString(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Legado source JSON must be an object');
    }
    return LegadoBookSource.fromJson(
      decoded.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  factory LegadoBookSource.fromJson(Map<String, dynamic> json) {
    return LegadoBookSource(
      bookSourceName: (json['bookSourceName'] ?? 'Unnamed Legado Source').toString(),
      bookSourceUrl: (json['bookSourceUrl'] ?? '').toString(),
      searchUrl: json['searchUrl']?.toString(),
      headers: _parseHeaderField(json['header']),
      charset: _normalizeOptional(json['charset']),
      webView: json['webView'] == true,
      ruleSearch: LegadoSearchRule.fromJson(_asMap(json['ruleSearch'])),
      ruleBookInfo: LegadoBookInfoRule.fromJson(_asMap(json['ruleBookInfo'])),
      ruleToc: LegadoTocRule.fromJson(_asMap(json['ruleToc'])),
      ruleContent: LegadoContentRule.fromJson(_asMap(json['ruleContent'])),
    );
  }

  static Map<String, String> _parseHeaderField(dynamic raw) {
    if (raw == null) return const {};
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    }
    return const {};
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }

  static String? _normalizeOptional(dynamic raw) {
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
