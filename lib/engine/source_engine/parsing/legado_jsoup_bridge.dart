import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Pure-Dart `org.jsoup.Jsoup` DOM bridge for QuickJS execution sessions.
///
/// Parses HTML documents via `package:html`, assigns per-session integer node
/// handles (`int` IDs) for documents and elements, evaluates CSS + common Jsoup
/// extended selectors safely (never throwing uncaught selector errors), and
/// exposes `HostSyncCallback`-compatible `__jsoup*` host functions alongside
/// [jsPrelude] for `org.jsoup.Jsoup`, `Packages.org.jsoup.Jsoup`, `Jsoup`,
/// `importClass`, `Element`, and array-backed `Elements`.
class LegadoJsoupBridge {
  final Map<int, _JsoupNodeEntry> _nodes = <int, _JsoupNodeEntry>{};
  final Map<dom.Node, int> _nodeToId = Map<dom.Node, int>.identity();
  int _nextId = 1;
  bool _disposed = false;

  /// Number of live DOM node handles tracked in this session.
  int get handleCount => _nodes.length;

  /// Whether [dispose] has been called on this bridge.
  bool get isDisposed => _disposed;

  /// Parses [html] (optionally anchored at [baseUri]) and returns the root
  /// document handle ID.
  int parse(String html, [String? baseUri]) {
    if (_disposed) {
      throw StateError('LegadoJsoupBridge has already been disposed.');
    }
    final doc = html_parser.parse(html);
    var resolvedBase = baseUri?.trim() ?? '';
    if (resolvedBase.isEmpty) {
      final baseEl = doc.head?.querySelector('base[href]');
      final baseHref = baseEl?.attributes['href']?.trim() ?? '';
      if (baseHref.isNotEmpty) {
        resolvedBase = baseHref;
      }
    }
    return _registerNode(doc, resolvedBase);
  }

  /// Evaluates a CSS or Jsoup extended [selector] rooted at [nodeId].
  ///
  /// Returns matching element handle IDs in document order, or an empty list
  /// if [nodeId] is invalid or [selector] is malformed/unsupported.
  List<int> select(int nodeId, String selector) {
    final entry = _lookup(nodeId);
    if (entry == null) return const <int>[];
    final matches = _JsoupSelectorEngine.select(entry.node, selector);
    return _registerElements(matches, entry.baseUri);
  }

  /// Evaluates [selector] across multiple root [nodeIds], deduplicating matches
  /// in traversal order.
  List<int> selectMany(List<int> nodeIds, String selector) {
    if (_disposed || nodeIds.isEmpty) return const <int>[];
    final roots = <dom.Node>[];
    var fallbackBaseUri = '';
    final idBaseMap = Map<dom.Element, String>.identity();

    for (final id in nodeIds) {
      final entry = _lookup(id);
      if (entry == null) continue;
      if (fallbackBaseUri.isEmpty && entry.baseUri.isNotEmpty) {
        fallbackBaseUri = entry.baseUri;
      }
      roots.add(entry.node);
      if (entry.node is dom.Element) {
        idBaseMap[entry.node as dom.Element] = entry.baseUri;
      }
    }
    if (roots.isEmpty) return const <int>[];

    final matches = _JsoupSelectorEngine.selectFromRoots(roots, selector);
    final seen = Set<dom.Element>.identity();
    final out = <int>[];
    for (final el in matches) {
      if (seen.add(el)) {
        out.add(_registerNode(el, idBaseMap[el] ?? fallbackBaseUri));
      }
    }
    return out;
  }

  /// Returns the first element matching [selector] rooted at [nodeId], or `null`.
  int? selectFirst(int nodeId, String selector) {
    final ids = select(nodeId, selector);
    return ids.isEmpty ? null : ids.first;
  }

  /// Finds the first element with `id == id` in the subtree rooted at [nodeId].
  int? getElementById(int nodeId, String id) {
    final entry = _lookup(nodeId);
    if (entry == null || id.isEmpty) return null;
    for (final el in _walkElements(entry.node)) {
      if (el.id == id) {
        return _registerNode(el, entry.baseUri);
      }
    }
    return null;
  }

  /// Finds all elements matching [tagName] (case-insensitive, or `*`) in the
  /// subtree rooted at [nodeId].
  List<int> getElementsByTag(int nodeId, String tagName) {
    final entry = _lookup(nodeId);
    final needle = tagName.trim().toLowerCase();
    if (entry == null || needle.isEmpty) return const <int>[];
    final out = <int>[];
    for (final el in _walkElements(entry.node)) {
      if (needle == '*' || el.localName == needle) {
        out.add(_registerNode(el, entry.baseUri));
      }
    }
    return out;
  }

  /// Finds all elements having CSS class [className] in the subtree rooted at
  /// [nodeId].
  List<int> getElementsByClass(int nodeId, String className) {
    final entry = _lookup(nodeId);
    final needle = className.trim();
    if (entry == null || needle.isEmpty) return const <int>[];
    final out = <int>[];
    for (final el in _walkElements(entry.node)) {
      if (_hasCssClass(el, needle)) {
        out.add(_registerNode(el, entry.baseUri));
      }
    }
    return out;
  }

  /// Finds all elements possessing attribute [key] in the subtree rooted at
  /// [nodeId].
  List<int> getElementsByAttribute(int nodeId, String key) {
    final entry = _lookup(nodeId);
    final needle = key.trim();
    if (entry == null || needle.isEmpty) return const <int>[];
    final out = <int>[];
    for (final el in _walkElements(entry.node)) {
      if (_findAttributeValue(el, needle) != null) {
        out.add(_registerNode(el, entry.baseUri));
      }
    }
    return out;
  }

  /// Finds all elements possessing attribute [key] equal to [value] in the
  /// subtree rooted at [nodeId].
  List<int> getElementsByAttributeValue(
    int nodeId,
    String key,
    String value,
  ) {
    final entry = _lookup(nodeId);
    final needle = key.trim();
    if (entry == null || needle.isEmpty) return const <int>[];
    final out = <int>[];
    for (final el in _walkElements(entry.node)) {
      if (_findAttributeValue(el, needle) == value) {
        out.add(_registerNode(el, entry.baseUri));
      }
    }
    return out;
  }

  /// Returns normalized combined text of [nodeId] and its descendants (Jsoup
  /// `Element.text()` semantics).
  String text(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    return _extractNormalizedText(entry.node);
  }

  /// Returns normalized text owned directly by [nodeId] (Jsoup
  /// `Element.ownText()` semantics).
  String ownText(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    return _extractOwnText(entry.node);
  }

  /// Returns the inner HTML of [nodeId] (Jsoup `Element.html()` semantics).
  String html(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    final node = entry.node;
    if (node is dom.Element) return node.innerHtml;
    if (node is dom.Document) return node.outerHtml;
    return '';
  }

  /// Returns the outer HTML of [nodeId].
  String outerHtml(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    final node = entry.node;
    if (node is dom.Element) return node.outerHtml;
    if (node is dom.Document) return node.outerHtml;
    return '';
  }

  /// Returns the value of [attributeKey] on [nodeId], or `''` if absent.
  ///
  /// Supports Jsoup's `abs:<attr>` prefix (e.g. `abs:href`, `abs:src`) by
  /// resolving against the document's `baseUri`.
  String attr(int nodeId, String attributeKey) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    final key = attributeKey.trim();
    if (key.isEmpty) return '';
    if (_hasAbsPrefix(key)) {
      return absUrl(nodeId, key.substring(4));
    }
    final node = entry.node;
    if (node is! dom.Element) return '';
    return _findAttributeValue(node, key) ?? '';
  }

  /// Resolves attribute [attributeKey] (e.g. `href`, `src`) against the
  /// session's `baseUri`. Returns `''` if the attribute is missing or cannot be
  /// resolved to an absolute URL.
  String absUrl(int nodeId, String attributeKey) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    final node = entry.node;
    if (node is! dom.Element) return '';
    final key = attributeKey.trim();
    if (key.isEmpty) return '';
    final raw = (_findAttributeValue(node, key) ?? '').trim();
    if (raw.isEmpty) return '';
    return _resolveAbsoluteUrl(raw, entry.baseUri);
  }

  /// Returns the tag name of [nodeId] (`'#root'` for parsed documents).
  String tagName(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    final node = entry.node;
    if (node is dom.Document) return '#root';
    if (node is dom.Element) return node.localName ?? '';
    return '';
  }

  /// Returns the `id` attribute of [nodeId], or `''`.
  String id(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    final node = entry.node;
    return node is dom.Element ? node.id : '';
  }

  /// Returns the `class` attribute of [nodeId], or `''`.
  String className(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return '';
    final node = entry.node;
    return node is dom.Element ? node.className : '';
  }

  /// Returns `true` if [nodeId] has [attributeKey] (including non-empty
  /// `abs:<attr>` resolution).
  bool hasAttr(int nodeId, String attributeKey) {
    final entry = _lookup(nodeId);
    if (entry == null) return false;
    final key = attributeKey.trim();
    if (key.isEmpty) return false;
    if (_hasAbsPrefix(key)) {
      return absUrl(nodeId, key.substring(4)).isNotEmpty;
    }
    final node = entry.node;
    return node is dom.Element && _findAttributeValue(node, key) != null;
  }

  /// Returns `true` if [nodeId] has CSS class [className].
  bool hasClass(int nodeId, String className) {
    final entry = _lookup(nodeId);
    if (entry == null) return false;
    final needle = className.trim();
    if (needle.isEmpty) return false;
    final node = entry.node;
    return node is dom.Element && _hasCssClass(node, needle);
  }

  /// Detaches [nodeId] cleanly from its parent in the DOM tree.
  void remove(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return;
    if (entry.node is dom.Document) return;
    entry.node.remove();
  }

  /// Returns child element handle IDs of [nodeId].
  List<int> children(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return const <int>[];
    return _registerElements(entry.node.children, entry.baseUri);
  }

  /// Returns the parent node handle ID of [nodeId], or `null` if detached/root.
  int? parent(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return null;
    final p = entry.node.parentNode;
    if (p is dom.Element || p is dom.Document) {
      return _registerNode(p!, entry.baseUri);
    }
    return null;
  }

  /// Returns the next sibling element handle ID of [nodeId], or `null`.
  int? nextElementSibling(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return null;
    final node = entry.node;
    if (node is! dom.Element) return null;
    final sib = node.nextElementSibling;
    return sib == null ? null : _registerNode(sib, entry.baseUri);
  }

  /// Returns the previous sibling element handle ID of [nodeId], or `null`.
  int? previousElementSibling(int nodeId) {
    final entry = _lookup(nodeId);
    if (entry == null) return null;
    final node = entry.node;
    if (node is! dom.Element) return null;
    final sib = node.previousElementSibling;
    return sib == null ? null : _registerNode(sib, entry.baseUri);
  }

  /// Releases all tracked DOM node handles for this session.
  void dispose() {
    _disposed = true;
    _nodes.clear();
    _nodeToId.clear();
  }

  /// Builds synchronous host callbacks (`__jsoup*`) compatible with
  /// `QjsSandboxRuntime(syncHostFunctions: ...)`.
  Map<String, Object? Function(List<Object?>)> buildSyncHostFunctions() {
    return <String, Object? Function(List<Object?>)>{
      '__jsoupParse': (args) =>
          parse(_argString(args, 0), _argOptionalString(args, 1)),
      '__jsoupSelect': (args) {
        final nodeId = _argInt(args, 0);
        if (nodeId == null) return const <int>[];
        return select(nodeId, _argString(args, 1));
      },
      '__jsoupSelectMany': (args) =>
          selectMany(_argIntList(args, 0), _argString(args, 1)),
      '__jsoupSelectFirst': (args) {
        final nodeId = _argInt(args, 0);
        if (nodeId == null) return null;
        return selectFirst(nodeId, _argString(args, 1));
      },
      '__jsoupGetElementById': (args) {
        final nodeId = _argInt(args, 0);
        if (nodeId == null) return null;
        return getElementById(nodeId, _argString(args, 1));
      },
      '__jsoupGetElementsByTag': (args) {
        final nodeId = _argInt(args, 0);
        if (nodeId == null) return const <int>[];
        return getElementsByTag(nodeId, _argString(args, 1));
      },
      '__jsoupGetElementsByClass': (args) {
        final nodeId = _argInt(args, 0);
        if (nodeId == null) return const <int>[];
        return getElementsByClass(nodeId, _argString(args, 1));
      },
      '__jsoupGetElementsByAttribute': (args) {
        final nodeId = _argInt(args, 0);
        if (nodeId == null) return const <int>[];
        return getElementsByAttribute(nodeId, _argString(args, 1));
      },
      '__jsoupGetElementsByAttributeValue': (args) {
        final nodeId = _argInt(args, 0);
        if (nodeId == null) return const <int>[];
        return getElementsByAttributeValue(
          nodeId,
          _argString(args, 1),
          _argString(args, 2),
        );
      },
      '__jsoupText': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : text(nodeId);
      },
      '__jsoupOwnText': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : ownText(nodeId);
      },
      '__jsoupHtml': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : html(nodeId);
      },
      '__jsoupOuterHtml': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : outerHtml(nodeId);
      },
      '__jsoupAttr': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : attr(nodeId, _argString(args, 1));
      },
      '__jsoupAbsUrl': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : absUrl(nodeId, _argString(args, 1));
      },
      '__jsoupTagName': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : tagName(nodeId);
      },
      '__jsoupId': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : id(nodeId);
      },
      '__jsoupClassName': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? '' : className(nodeId);
      },
      '__jsoupHasAttr': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId != null && hasAttr(nodeId, _argString(args, 1));
      },
      '__jsoupHasClass': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId != null && hasClass(nodeId, _argString(args, 1));
      },
      '__jsoupRemove': (args) {
        final nodeId = _argInt(args, 0);
        if (nodeId != null) remove(nodeId);
        return null;
      },
      '__jsoupChildren': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? const <int>[] : children(nodeId);
      },
      '__jsoupParent': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? null : parent(nodeId);
      },
      '__jsoupNextElementSibling': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? null : nextElementSibling(nodeId);
      },
      '__jsoupPreviousElementSibling': (args) {
        final nodeId = _argInt(args, 0);
        return nodeId == null ? null : previousElementSibling(nodeId);
      },
    };
  }

  /// Idempotent ES2020/QuickJS prelude defining `org.jsoup.Jsoup`,
  /// `Packages.org.jsoup.Jsoup`, global `Jsoup`, safe `importClass`, `Element`,
  /// and array-backed `Elements`.
  ///
  /// Uses non-enumerable ES6 class methods (and no `Proxy`) so `for (i in els)`,
  /// `for (el of els)`, `els[i]`, `els.length`, `.map`, `.forEach`, and
  /// `.flatMap` all work cleanly inside hardened QuickJS.
  static const String jsPrelude = r'''
(function(g) {
  if (g.__legadoJsoupInstalled) return;
  g.__legadoJsoupInstalled = true;

  function makeElements(ids) {
    const arr = new Elements();
    if (Array.isArray(ids)) {
      for (let i = 0; i < ids.length; i++) {
        arr.push(new Element(ids[i]));
      }
    }
    return arr;
  }

  class Element {
    constructor(id) {
      Object.defineProperty(this, '__id', {
        value: id,
        writable: false,
        enumerable: false,
        configurable: false
      });
    }
    select(selector) {
      return makeElements(host.__jsoupSelect(this.__id, selector == null ? '' : String(selector)));
    }
    selectFirst(selector) {
      const id = host.__jsoupSelectFirst(this.__id, selector == null ? '' : String(selector));
      return id == null ? null : new Element(id);
    }
    getElementById(id) {
      const found = host.__jsoupGetElementById(this.__id, id == null ? '' : String(id));
      return found == null ? null : new Element(found);
    }
    getElementsByTag(tagName) {
      return makeElements(host.__jsoupGetElementsByTag(this.__id, tagName == null ? '' : String(tagName)));
    }
    getElementsByClass(className) {
      return makeElements(host.__jsoupGetElementsByClass(this.__id, className == null ? '' : String(className)));
    }
    getElementsByAttribute(key) {
      return makeElements(host.__jsoupGetElementsByAttribute(this.__id, key == null ? '' : String(key)));
    }
    getElementsByAttributeValue(key, value) {
      return makeElements(host.__jsoupGetElementsByAttributeValue(
        this.__id,
        key == null ? '' : String(key),
        value == null ? '' : String(value)
      ));
    }
    text() {
      return host.__jsoupText(this.__id);
    }
    ownText() {
      return host.__jsoupOwnText(this.__id);
    }
    html() {
      return host.__jsoupHtml(this.__id);
    }
    outerHtml() {
      return host.__jsoupOuterHtml(this.__id);
    }
    attr(key) {
      return host.__jsoupAttr(this.__id, key == null ? '' : String(key));
    }
    absUrl(key) {
      return host.__jsoupAbsUrl(this.__id, key == null ? '' : String(key));
    }
    tagName() {
      return host.__jsoupTagName(this.__id);
    }
    nodeName() {
      return host.__jsoupTagName(this.__id);
    }
    id() {
      return host.__jsoupId(this.__id);
    }
    className() {
      return host.__jsoupClassName(this.__id);
    }
    hasAttr(key) {
      return Boolean(host.__jsoupHasAttr(this.__id, key == null ? '' : String(key)));
    }
    hasClass(className) {
      return Boolean(host.__jsoupHasClass(this.__id, className == null ? '' : String(className)));
    }
    remove() {
      host.__jsoupRemove(this.__id);
      return this;
    }
    children() {
      return makeElements(host.__jsoupChildren(this.__id));
    }
    child(index) {
      const ch = this.children();
      return ch.get(index);
    }
    parent() {
      const pid = host.__jsoupParent(this.__id);
      return pid == null ? null : new Element(pid);
    }
    nextElementSibling() {
      const nid = host.__jsoupNextElementSibling(this.__id);
      return nid == null ? null : new Element(nid);
    }
    previousElementSibling() {
      const pid = host.__jsoupPreviousElementSibling(this.__id);
      return pid == null ? null : new Element(pid);
    }
    toString() {
      return this.outerHtml();
    }
  }

  class Elements extends Array {
    static get [Symbol.species]() {
      return Array;
    }
    select(selector) {
      const ids = [];
      for (let i = 0; i < this.length; i++) {
        ids.push(this[i].__id);
      }
      return makeElements(host.__jsoupSelectMany(ids, selector == null ? '' : String(selector)));
    }
    selectFirst(selector) {
      const matched = this.select(selector);
      return matched.first();
    }
    text() {
      const parts = [];
      for (let i = 0; i < this.length; i++) {
        const t = this[i].text();
        if (t.length > 0) parts.push(t);
      }
      return parts.join(' ');
    }
    ownText() {
      const parts = [];
      for (let i = 0; i < this.length; i++) {
        const t = this[i].ownText();
        if (t.length > 0) parts.push(t);
      }
      return parts.join(' ');
    }
    html() {
      const parts = [];
      for (let i = 0; i < this.length; i++) {
        parts.push(this[i].html());
      }
      return parts.join('\n');
    }
    outerHtml() {
      const parts = [];
      for (let i = 0; i < this.length; i++) {
        parts.push(this[i].outerHtml());
      }
      return parts.join('\n');
    }
    attr(key) {
      const k = key == null ? '' : String(key);
      for (let i = 0; i < this.length; i++) {
        if (this[i].hasAttr(k)) {
          return this[i].attr(k);
        }
      }
      return '';
    }
    absUrl(key) {
      const k = key == null ? '' : String(key);
      for (let i = 0; i < this.length; i++) {
        const v = this[i].absUrl(k);
        if (v.length > 0) return v;
      }
      return '';
    }
    hasAttr(key) {
      const k = key == null ? '' : String(key);
      for (let i = 0; i < this.length; i++) {
        if (this[i].hasAttr(k)) return true;
      }
      return false;
    }
    hasClass(className) {
      const c = className == null ? '' : String(className);
      for (let i = 0; i < this.length; i++) {
        if (this[i].hasClass(c)) return true;
      }
      return false;
    }
    first() {
      return this.length > 0 ? this[0] : null;
    }
    last() {
      return this.length > 0 ? this[this.length - 1] : null;
    }
    get(index) {
      const i = Number(index);
      if (!Number.isInteger(i) || i < 0 || i >= this.length) return null;
      return this[i];
    }
    size() {
      return this.length;
    }
    eq(index) {
      const out = new Elements();
      const i = Number(index);
      if (Number.isInteger(i)) {
        const resolved = i < 0 ? this.length + i : i;
        if (resolved >= 0 && resolved < this.length) {
          out.push(this[resolved]);
        }
      }
      return out;
    }
    isEmpty() {
      return this.length === 0;
    }
    remove() {
      for (let i = 0; i < this.length; i++) {
        this[i].remove();
      }
      return this;
    }
    eachText() {
      const out = [];
      for (let i = 0; i < this.length; i++) {
        const t = this[i].text();
        if (t.length > 0) out.push(t);
      }
      return out;
    }
    eachAttr(key) {
      const k = key == null ? '' : String(key);
      const out = [];
      for (let i = 0; i < this.length; i++) {
        if (this[i].hasAttr(k)) {
          out.push(this[i].attr(k));
        }
      }
      return out;
    }
    toArray() {
      return Array.from(this);
    }
    toString() {
      return this.outerHtml();
    }
  }

  const Jsoup = {
    parse: function(html, baseUri) {
      const id = host.__jsoupParse(
        html == null ? '' : String(html),
        baseUri == null ? '' : String(baseUri)
      );
      return new Element(id);
    },
    parseBodyFragment: function(html, baseUri) {
      return Jsoup.parse(html, baseUri);
    }
  };

  g.Jsoup = Jsoup;
  g.org = (g.org && typeof g.org === 'object') ? g.org : {};
  g.org.jsoup = (g.org.jsoup && typeof g.org.jsoup === 'object') ? g.org.jsoup : {};
  g.org.jsoup.Jsoup = Jsoup;
  g.org.jsoup.nodes = g.org.jsoup.nodes || { Document: Element, Element: Element };
  g.org.jsoup.select = g.org.jsoup.select || { Elements: Elements };

  g.Packages = (g.Packages && typeof g.Packages === 'object') ? g.Packages : {};
  g.Packages.org = (g.Packages.org && typeof g.Packages.org === 'object') ? g.Packages.org : {};
  g.Packages.org.jsoup = g.org.jsoup;

  if (typeof g.importClass !== 'function') {
    g.importClass = function() {};
  }
})(globalThis);
''';

  _JsoupNodeEntry? _lookup(int nodeId) {
    if (_disposed) return null;
    return _nodes[nodeId];
  }

  int _registerNode(dom.Node node, String baseUri) {
    final existing = _nodeToId[node];
    if (existing != null) {
      return existing;
    }
    final id = _nextId++;
    _nodes[id] = _JsoupNodeEntry(node, baseUri);
    _nodeToId[node] = id;
    return id;
  }

  List<int> _registerElements(Iterable<dom.Element> elements, String baseUri) {
    final out = <int>[];
    for (final el in elements) {
      out.add(_registerNode(el, baseUri));
    }
    return out;
  }

  static int? _argInt(List<Object?> args, int index) {
    if (index >= args.length) return null;
    final val = args[index];
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val.trim());
    return null;
  }

  static List<int> _argIntList(List<Object?> args, int index) {
    if (index >= args.length) return const <int>[];
    final val = args[index];
    if (val is! List) return const <int>[];
    final out = <int>[];
    for (final item in val) {
      if (item is int) {
        out.add(item);
      } else if (item is num) {
        out.add(item.toInt());
      } else if (item is String) {
        final parsed = int.tryParse(item.trim());
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }

  static String _argString(List<Object?> args, int index) {
    if (index >= args.length) return '';
    return args[index]?.toString() ?? '';
  }

  static String? _argOptionalString(List<Object?> args, int index) {
    if (index >= args.length) return null;
    final val = args[index];
    return val?.toString();
  }

  static bool _hasAbsPrefix(String key) =>
      key.length > 4 && key.substring(0, 4).toLowerCase() == 'abs:';
}

class _JsoupNodeEntry {
  final dom.Node node;
  final String baseUri;

  const _JsoupNodeEntry(this.node, this.baseUri);
}

const Set<String> _jsoupBlockTags = <String>{
  'address',
  'article',
  'aside',
  'blockquote',
  'br',
  'dd',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'noscript',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
};

Iterable<dom.Element> _walkElements(dom.Node root) sync* {
  if (root is dom.Element) {
    yield root;
  }
  for (final child in root.nodes) {
    if (child is dom.Element) {
      yield* _walkElements(child);
    }
  }
}

bool _hasCssClass(dom.Element el, String className) {
  final raw = el.className;
  if (raw.isEmpty) return false;
  for (final token in raw.split(_whitespaceSplitRegex)) {
    if (token == className) return true;
  }
  return false;
}

final RegExp _whitespaceSplitRegex = RegExp(r'\s+');

String? _findAttributeValue(dom.Element el, String key) {
  final direct = el.attributes[key];
  if (direct != null) return direct;
  final lower = key.toLowerCase();
  final lowerDirect = el.attributes[lower];
  if (lowerDirect != null) return lowerDirect;
  for (final entry in el.attributes.entries) {
    if (entry.key.toString().toLowerCase() == lower) {
      return entry.value;
    }
  }
  return null;
}

String _resolveAbsoluteUrl(String rawUrl, String baseUri) {
  if (rawUrl.isEmpty) return '';
  final lower = rawUrl.toLowerCase();
  if (lower.startsWith('javascript:') ||
      lower.startsWith('data:') ||
      lower.startsWith('mailto:')) {
    return '';
  }

  final parsedRaw = _tryParseUri(rawUrl);
  if (baseUri.isEmpty) {
    if (parsedRaw != null &&
        parsedRaw.hasScheme &&
        parsedRaw.host.isNotEmpty) {
      return parsedRaw.toString();
    }
    return '';
  }

  final parsedBase = _tryParseUri(baseUri);
  if (parsedBase == null) return '';

  if (parsedRaw != null) {
    try {
      final resolved = parsedBase.resolveUri(parsedRaw);
      return resolved.hasScheme ? resolved.toString() : '';
    } catch (_) {
      return '';
    }
  }

  try {
    return parsedBase.resolve(rawUrl).toString();
  } catch (_) {
    return '';
  }
}

Uri? _tryParseUri(String raw) {
  final direct = Uri.tryParse(raw);
  if (direct != null) return direct;
  return Uri.tryParse(Uri.encodeFull(raw));
}

String _extractNormalizedText(dom.Node root) {
  final collector = _NormalizedTextCollector();
  collector.visitNode(root);
  return collector.finish();
}

String _extractOwnText(dom.Node root) {
  final collector = _NormalizedTextCollector();
  for (final child in root.nodes) {
    if (child is dom.Text) {
      collector.appendText(child.data);
    } else if (child is dom.Element && child.localName == 'br') {
      collector.ensureSpace();
    }
  }
  return collector.finish();
}

class _NormalizedTextCollector {
  final StringBuffer _sb = StringBuffer();
  bool _lastWasWhite = true;

  void ensureSpace() {
    if (_sb.isNotEmpty && !_lastWasWhite) {
      _sb.write(' ');
      _lastWasWhite = true;
    }
  }

  void appendText(String raw) {
    for (var i = 0; i < raw.length; i++) {
      final code = raw.codeUnitAt(i);
      if (_isHtmlWhitespace(code)) {
        if (!_lastWasWhite) {
          _sb.write(' ');
          _lastWasWhite = true;
        }
      } else {
        _sb.writeCharCode(code);
        _lastWasWhite = false;
      }
    }
  }

  void visitNode(dom.Node node) {
    if (node is dom.Text) {
      appendText(node.data);
      return;
    }
    if (node is dom.Element) {
      final tag = node.localName;
      if (tag == 'script' || tag == 'style') return;
      final isBlock = tag != null && _jsoupBlockTags.contains(tag);
      if (isBlock) ensureSpace();
      for (final child in node.nodes) {
        visitNode(child);
      }
      if (isBlock) ensureSpace();
      return;
    }
    if (node is dom.Document || node is dom.DocumentFragment) {
      for (final child in node.nodes) {
        visitNode(child);
      }
    }
  }

  String finish() => _sb.toString().trimRight();

  static bool _isHtmlWhitespace(int code) =>
      code == 0x20 ||
      code == 0x09 ||
      code == 0x0A ||
      code == 0x0D ||
      code == 0x0C;
}

class _JsoupSelectorEngine {
  static List<dom.Element> select(dom.Node root, String rawSelector) =>
      selectFromRoots(<dom.Node>[root], rawSelector);

  static List<dom.Element> selectFromRoots(
    List<dom.Node> roots,
    String rawSelector,
  ) {
    final trimmed = rawSelector.trim();
    if (trimmed.isEmpty || roots.isEmpty) return const <dom.Element>[];

    final group = _parseSelectorGroup(trimmed);
    if (group == null || group.isEmpty) return const <dom.Element>[];

    if (group.length == 1) {
      return _evaluateChainFromRoots(roots, group.first);
    }

    final seen = Set<dom.Element>.identity();
    final combined = <dom.Element>[];
    for (final chain in group) {
      for (final el in _evaluateChainFromRoots(roots, chain)) {
        if (seen.add(el)) {
          combined.add(el);
        }
      }
    }
    return combined;
  }

  static List<dom.Element> _evaluateChainFromRoots(
    List<dom.Node> roots,
    List<_SelectorStep> chain,
  ) {
    if (chain.isEmpty) return const <dom.Element>[];

    var current = <dom.Element>[];
    for (var stepIdx = 0; stepIdx < chain.length; stepIdx++) {
      final step = chain[stepIdx];
      final candidates = <dom.Element>[];
      final seen = Set<dom.Element>.identity();

      if (stepIdx == 0) {
        for (final root in roots) {
          for (final candidate in _expandInitialStep(root, step.combinator)) {
            if (seen.add(candidate) &&
                _matchesCompound(candidate, step.compound)) {
              candidates.add(candidate);
            }
          }
        }
      } else {
        for (final prev in current) {
          for (final candidate in _expandCombinator(prev, step.combinator)) {
            if (seen.add(candidate) &&
                _matchesCompound(candidate, step.compound)) {
              candidates.add(candidate);
            }
          }
        }
      }

      current = _applyPositionals(candidates, step.compound.positionals);
      if (current.isEmpty) return const <dom.Element>[];
    }

    return current;
  }

  static Iterable<dom.Element> _expandInitialStep(
    dom.Node root,
    String combinator,
  ) {
    switch (combinator) {
      case '>':
        return root.children;
      case '+':
        if (root is dom.Element) {
          final sib = root.nextElementSibling;
          return sib == null ? const <dom.Element>[] : <dom.Element>[sib];
        }
        return const <dom.Element>[];
      case '~':
        if (root is dom.Element) {
          return _followingElementSiblings(root);
        }
        return const <dom.Element>[];
      default:
        return _walkElements(root);
    }
  }

  static Iterable<dom.Element> _expandCombinator(
    dom.Element el,
    String combinator,
  ) {
    switch (combinator) {
      case '>':
        return el.children;
      case '+':
        final sib = el.nextElementSibling;
        return sib == null ? const <dom.Element>[] : <dom.Element>[sib];
      case '~':
        return _followingElementSiblings(el);
      case ' ':
      default:
        return _walkDescendants(el);
    }
  }

  static Iterable<dom.Element> _walkDescendants(dom.Element el) sync* {
    for (final child in el.children) {
      yield child;
      yield* _walkDescendants(child);
    }
  }

  static Iterable<dom.Element> _followingElementSiblings(dom.Element el) sync* {
    var cursor = el.nextElementSibling;
    while (cursor != null) {
      yield cursor;
      cursor = cursor.nextElementSibling;
    }
  }

  static List<dom.Element> _applyPositionals(
    List<dom.Element> items,
    List<_PositionalFilter> positionals,
  ) {
    if (positionals.isEmpty || items.isEmpty) return items;
    var current = items;
    for (final filter in positionals) {
      if (current.isEmpty) return const <dom.Element>[];
      switch (filter.kind) {
        case _PositionalKind.eq:
          final raw = filter.index!;
          final idx = raw < 0 ? current.length + raw : raw;
          current = (idx >= 0 && idx < current.length)
              ? <dom.Element>[current[idx]]
              : const <dom.Element>[];
        case _PositionalKind.gt:
          final start = filter.index! + 1;
          current = start <= 0
              ? current
              : (start < current.length
                    ? current.sublist(start)
                    : const <dom.Element>[]);
        case _PositionalKind.lt:
          final end = filter.index!;
          current = end <= 0
              ? const <dom.Element>[]
              : (end >= current.length ? current : current.sublist(0, end));
        case _PositionalKind.first:
          current = <dom.Element>[current.first];
        case _PositionalKind.last:
          current = <dom.Element>[current.last];
        case _PositionalKind.even:
          current = <dom.Element>[
            for (var i = 0; i < current.length; i += 2) current[i],
          ];
        case _PositionalKind.odd:
          current = <dom.Element>[
            for (var i = 1; i < current.length; i += 2) current[i],
          ];
      }
    }
    return current;
  }

  static bool _matchesCompound(dom.Element el, _CompoundSelector compound) {
    final tag = compound.tagName;
    if (tag != null && tag != '*' && el.localName != tag) {
      return false;
    }
    for (final id in compound.ids) {
      if (el.id != id) return false;
    }
    for (final cls in compound.classes) {
      if (!_hasCssClass(el, cls)) return false;
    }
    for (final attr in compound.attrs) {
      if (!_matchesAttr(el, attr)) return false;
    }
    for (final pseudo in compound.pseudos) {
      if (!pseudo.matches(el)) return false;
    }
    return true;
  }

  static bool _matchesChainRightToLeft(
    dom.Element el,
    List<_SelectorStep> chain,
    int stepIndex,
  ) {
    final step = chain[stepIndex];
    if (!_matchesCompound(el, step.compound)) return false;
    if (stepIndex == 0) return true;

    switch (step.combinator) {
      case '>':
        final p = el.parent;
        return p != null && _matchesChainRightToLeft(p, chain, stepIndex - 1);
      case '+':
        final prev = el.previousElementSibling;
        return prev != null &&
            _matchesChainRightToLeft(prev, chain, stepIndex - 1);
      case '~':
        var prev = el.previousElementSibling;
        while (prev != null) {
          if (_matchesChainRightToLeft(prev, chain, stepIndex - 1)) return true;
          prev = prev.previousElementSibling;
        }
        return false;
      case ' ':
      default:
        var anc = el.parent;
        while (anc != null) {
          if (_matchesChainRightToLeft(anc, chain, stepIndex - 1)) return true;
          anc = anc.parent;
        }
        return false;
    }
  }

  static bool _matchesGroupAtElement(
    dom.Element el,
    List<List<_SelectorStep>> group,
  ) {
    for (final chain in group) {
      if (chain.isNotEmpty &&
          _matchesChainRightToLeft(el, chain, chain.length - 1)) {
        return true;
      }
    }
    return false;
  }

  static bool _matchesAttr(dom.Element el, _AttrFilter filter) {
    final actual = _findAttributeValue(el, filter.name);
    if (actual == null) return false;
    if (filter.op.isEmpty) return true;

    if (filter.op == '~=') {
      final regex = filter.regex;
      return regex != null && regex.hasMatch(actual);
    }

    final a = filter.caseInsensitive ? actual.toLowerCase() : actual;
    final v = filter.caseInsensitive ? filter.value.toLowerCase() : filter.value;

    switch (filter.op) {
      case '=':
        return a == v;
      case '!=':
        return a != v;
      case '^=':
        return v.isNotEmpty && a.startsWith(v);
      case r'$=':
        return v.isNotEmpty && a.endsWith(v);
      case '*=':
        return v.isNotEmpty && a.contains(v);
      case '|=':
        return a == v || a.startsWith('$v-');
      default:
        return false;
    }
  }

  static List<List<_SelectorStep>>? _parseSelectorGroup(String input) {
    final branches = _splitTopLevelComma(input);
    if (branches.isEmpty) return null;
    final group = <List<_SelectorStep>>[];
    for (final branch in branches) {
      final chain = _parseChain(branch);
      if (chain == null || chain.isEmpty) return null;
      group.add(chain);
    }
    return group;
  }

  static List<String> _splitTopLevelComma(String input) {
    final parts = <String>[];
    var inSingle = false;
    var inDouble = false;
    var bracketDepth = 0;
    var parenDepth = 0;
    var start = 0;

    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code == 0x5C) {
        i++;
        continue;
      }
      if (code == 0x27 && !inDouble && parenDepth == 0) {
        inSingle = !inSingle;
      } else if (code == 0x22 && !inSingle && parenDepth == 0) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (code == 0x5B) {
          bracketDepth++;
        } else if (code == 0x5D && bracketDepth > 0) {
          bracketDepth--;
        } else if (code == 0x28) {
          parenDepth++;
        } else if (code == 0x29 && parenDepth > 0) {
          parenDepth--;
        } else if (code == 0x2C && bracketDepth == 0 && parenDepth == 0) {
          final seg = input.substring(start, i).trim();
          if (seg.isEmpty) return const <String>[];
          parts.add(seg);
          start = i + 1;
        }
      }
    }
    final tail = input.substring(start).trim();
    if (tail.isEmpty) return const <String>[];
    parts.add(tail);
    return parts;
  }

  static List<_SelectorStep>? _parseChain(String input) {
    final parser = _SelectorParser(input);
    return parser.parseChain();
  }
}

class _SelectorParser {
  final String input;
  int pos = 0;

  _SelectorParser(this.input);

  List<_SelectorStep>? parseChain() {
    final steps = <_SelectorStep>[];
    _skipWhitespace();

    while (pos < input.length) {
      var combinator = '';
      if (steps.isEmpty) {
        if (_isCombinatorChar(input.codeUnitAt(pos))) {
          combinator = input[pos++];
          _skipWhitespace();
        }
      } else {
        final hadWs = _skipWhitespace();
        if (pos >= input.length) break;
        if (_isCombinatorChar(input.codeUnitAt(pos))) {
          combinator = input[pos++];
          _skipWhitespace();
        } else if (hadWs) {
          combinator = ' ';
        } else {
          return null;
        }
      }

      if (pos >= input.length) return null;
      final compound = _parseCompound();
      if (compound == null) return null;
      steps.add(_SelectorStep(combinator, compound));
    }

    return steps;
  }

  _CompoundSelector? _parseCompound() {
    String? tagName;
    final ids = <String>[];
    final classes = <String>[];
    final attrs = <_AttrFilter>[];
    final pseudos = <_PseudoFilter>[];
    final positionals = <_PositionalFilter>[];
    var matchedAnyToken = false;

    while (pos < input.length) {
      final code = input.codeUnitAt(pos);
      if (_isWhitespace(code) || _isCombinatorChar(code)) {
        break;
      }

      if (code == 0x23) {
        // '#'
        pos++;
        final id = _readIdentifier();
        if (id.isEmpty) return null;
        ids.add(id);
        matchedAnyToken = true;
      } else if (code == 0x2E) {
        // '.'
        pos++;
        final cls = _readIdentifier();
        if (cls.isEmpty) return null;
        classes.add(cls);
        matchedAnyToken = true;
      } else if (code == 0x5B) {
        // '['
        final attr = _parseAttribute();
        if (attr == null) return null;
        attrs.add(attr);
        matchedAnyToken = true;
      } else if (code == 0x3A) {
        // ':'
        pos++;
        if (pos < input.length && input.codeUnitAt(pos) == 0x3A) {
          // Pseudo-element like `::before` cannot match DOM elements.
          pos++;
          _readIdentifier();
          if (pos < input.length && input.codeUnitAt(pos) == 0x28) {
            if (_readParenContent() == null) return null;
          }
          pseudos.add(_PseudoFilter.neverMatch);
          matchedAnyToken = true;
          continue;
        }
        final name = _readIdentifier().toLowerCase();
        if (name.isEmpty) return null;
        String? arg;
        if (pos < input.length && input.codeUnitAt(pos) == 0x28) {
          arg = _readParenContent();
          if (arg == null) return null;
        }
        _registerPseudo(name, arg, pseudos, positionals);
        matchedAnyToken = true;
      } else if (!matchedAnyToken && code == 0x2A) {
        // '*'
        pos++;
        tagName = '*';
        matchedAnyToken = true;
      } else if (!matchedAnyToken && _isIdentStart(code)) {
        final tag = _readTagName().toLowerCase();
        if (tag.isEmpty) return null;
        tagName = tag;
        matchedAnyToken = true;
      } else {
        return null;
      }
    }

    if (!matchedAnyToken) return null;
    return _CompoundSelector(
      tagName: tagName,
      ids: ids,
      classes: classes,
      attrs: attrs,
      pseudos: pseudos,
      positionals: positionals,
    );
  }

  _AttrFilter? _parseAttribute() {
    pos++; // consume '['
    var bracketDepth = 1;
    var inSingle = false;
    var inDouble = false;
    final start = pos;

    while (pos < input.length && bracketDepth > 0) {
      final code = input.codeUnitAt(pos);
      if (code == 0x5C && pos + 1 < input.length) {
        pos += 2;
        continue;
      }
      if (code == 0x27 && !inDouble) {
        inSingle = !inSingle;
      } else if (code == 0x22 && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (code == 0x5B) {
          bracketDepth++;
        } else if (code == 0x5D) {
          bracketDepth--;
          if (bracketDepth == 0) {
            final inside = input.substring(start, pos).trim();
            pos++; // consume ']'
            return _buildAttrFilter(inside);
          }
        }
      }
      pos++;
    }
    return null;
  }

  static _AttrFilter? _buildAttrFilter(String inside) {
    if (inside.isEmpty) return null;
    final opMatch = _attrOpRegex.firstMatch(inside);
    if (opMatch == null) {
      if (!_isValidAttrName(inside)) return null;
      return _AttrFilter(name: inside.toLowerCase(), op: '', value: '');
    }

    final name = inside.substring(0, opMatch.start).trim().toLowerCase();
    if (!_isValidAttrName(name)) return null;
    final op = opMatch.group(0)!;
    var rawVal = inside.substring(opMatch.end).trim();

    var caseInsensitive = false;
    if (op != '~=' && rawVal.length >= 2) {
      final ciMatch = RegExp(
        r'''^(['"].*['"])\s+([iIsS])$''',
        dotAll: true,
      ).firstMatch(rawVal);
      if (ciMatch != null) {
        rawVal = ciMatch.group(1)!;
        caseInsensitive = ciMatch.group(2)!.toLowerCase() == 'i';
      }
    }

    final value = _stripOuterQuotes(rawVal);
    RegExp? compiledRegex;
    if (op == '~=') {
      try {
        compiledRegex = RegExp(value);
      } on FormatException {
        compiledRegex = null;
      }
    }

    return _AttrFilter(
      name: name,
      op: op,
      value: value,
      caseInsensitive: caseInsensitive,
      regex: compiledRegex,
    );
  }

  String? _readParenContent() {
    pos++; // consume '('
    final start = pos;
    var depth = 1;
    var inSingle = false;
    var inDouble = false;

    // Check if the argument itself is wrapped in quotes (e.g. :contains("a)b")).
    var firstNonWs = pos;
    while (firstNonWs < input.length &&
        _isWhitespace(input.codeUnitAt(firstNonWs))) {
      firstNonWs++;
    }
    final allowStringMode = firstNonWs < input.length &&
        (input.codeUnitAt(firstNonWs) == 0x22 ||
            input.codeUnitAt(firstNonWs) == 0x27);

    while (pos < input.length && depth > 0) {
      final code = input.codeUnitAt(pos);
      if (code == 0x5C && pos + 1 < input.length) {
        pos += 2;
        continue;
      }
      if (allowStringMode) {
        if (code == 0x27 && !inDouble) {
          inSingle = !inSingle;
          pos++;
          continue;
        }
        if (code == 0x22 && !inSingle) {
          inDouble = !inDouble;
          pos++;
          continue;
        }
      }
      if (!inSingle && !inDouble) {
        if (code == 0x28) {
          depth++;
        } else if (code == 0x29) {
          depth--;
          if (depth == 0) {
            final content = input.substring(start, pos);
            pos++; // consume ')'
            return content;
          }
        }
      }
      pos++;
    }
    return null;
  }

  static void _registerPseudo(
    String name,
    String? rawArg,
    List<_PseudoFilter> pseudos,
    List<_PositionalFilter> positionals,
  ) {
    switch (name) {
      case 'contains':
        final needle = _stripOuterQuotes((rawArg ?? '').trim()).toLowerCase();
        pseudos.add(
          _PseudoFilter(
            (el) => _extractNormalizedText(el).toLowerCase().contains(needle),
          ),
        );
      case 'containsown':
        final needle = _stripOuterQuotes((rawArg ?? '').trim()).toLowerCase();
        pseudos.add(
          _PseudoFilter(
            (el) => _extractOwnText(el).toLowerCase().contains(needle),
          ),
        );
      case 'matches':
        final re = _tryCompileRegex(_stripOuterQuotes((rawArg ?? '').trim()));
        pseudos.add(
          re == null
              ? _PseudoFilter.neverMatch
              : _PseudoFilter((el) => re.hasMatch(_extractNormalizedText(el))),
        );
      case 'matchesown':
        final re = _tryCompileRegex(_stripOuterQuotes((rawArg ?? '').trim()));
        pseudos.add(
          re == null
              ? _PseudoFilter.neverMatch
              : _PseudoFilter((el) => re.hasMatch(_extractOwnText(el))),
        );
      case 'not':
        final group = _JsoupSelectorEngine._parseSelectorGroup(
          (rawArg ?? '').trim(),
        );
        pseudos.add(
          group == null
              ? _PseudoFilter.neverMatch
              : _PseudoFilter(
                  (el) => !_JsoupSelectorEngine._matchesGroupAtElement(el, group),
                ),
        );
      case 'has':
        final group = _JsoupSelectorEngine._parseSelectorGroup(
          (rawArg ?? '').trim(),
        );
        if (group == null) {
          pseudos.add(_PseudoFilter.neverMatch);
        } else {
          pseudos.add(
            _PseudoFilter((el) {
              for (final desc in _JsoupSelectorEngine._walkDescendants(el)) {
                if (_JsoupSelectorEngine._matchesGroupAtElement(desc, group)) {
                  return true;
                }
              }
              return false;
            }),
          );
        }
      case 'eq':
        final idx = int.tryParse((rawArg ?? '').trim());
        if (idx == null) {
          pseudos.add(_PseudoFilter.neverMatch);
        } else {
          positionals.add(_PositionalFilter(_PositionalKind.eq, idx));
        }
      case 'gt':
        final idx = int.tryParse((rawArg ?? '').trim());
        if (idx == null) {
          pseudos.add(_PseudoFilter.neverMatch);
        } else {
          positionals.add(_PositionalFilter(_PositionalKind.gt, idx));
        }
      case 'lt':
        final idx = int.tryParse((rawArg ?? '').trim());
        if (idx == null) {
          pseudos.add(_PseudoFilter.neverMatch);
        } else {
          positionals.add(_PositionalFilter(_PositionalKind.lt, idx));
        }
      case 'first':
        positionals.add(const _PositionalFilter(_PositionalKind.first));
      case 'last':
        positionals.add(const _PositionalFilter(_PositionalKind.last));
      case 'even':
        positionals.add(const _PositionalFilter(_PositionalKind.even));
      case 'odd':
        positionals.add(const _PositionalFilter(_PositionalKind.odd));
      case 'first-child':
        pseudos.add(_PseudoFilter((el) => el.previousElementSibling == null));
      case 'last-child':
        pseudos.add(_PseudoFilter((el) => el.nextElementSibling == null));
      case 'only-child':
        pseudos.add(
          _PseudoFilter(
            (el) =>
                el.previousElementSibling == null &&
                el.nextElementSibling == null,
          ),
        );
      case 'first-of-type':
        pseudos.add(_PseudoFilter((el) => _typeIndex(el) == 1));
      case 'last-of-type':
        pseudos.add(
          _PseudoFilter((el) => _typeIndex(el) == _typeCount(el)),
        );
      case 'only-of-type':
        pseudos.add(_PseudoFilter((el) => _typeCount(el) == 1));
      case 'empty':
        pseudos.add(
          _PseudoFilter(
            (el) => !el.nodes.any(
              (n) =>
                  n is dom.Element ||
                  (n is dom.Text && n.data.isNotEmpty),
            ),
          ),
        );
      case 'root':
        pseudos.add(
          _PseudoFilter(
            (el) => el.localName == 'html' && el.parentNode is dom.Document,
          ),
        );
      case 'nth-child':
        final nth = _NthSpec.tryParse(rawArg ?? '');
        pseudos.add(
          nth == null
              ? _PseudoFilter.neverMatch
              : _PseudoFilter((el) => nth.matches(_siblingIndex(el))),
        );
      case 'nth-last-child':
        final nth = _NthSpec.tryParse(rawArg ?? '');
        pseudos.add(
          nth == null
              ? _PseudoFilter.neverMatch
              : _PseudoFilter((el) => nth.matches(_reverseSiblingIndex(el))),
        );
      default:
        pseudos.add(_PseudoFilter.neverMatch);
    }
  }

  static int _siblingIndex(dom.Element el) {
    var count = 1;
    var cursor = el.previousElementSibling;
    while (cursor != null) {
      count++;
      cursor = cursor.previousElementSibling;
    }
    return count;
  }

  static int _reverseSiblingIndex(dom.Element el) {
    var count = 1;
    var cursor = el.nextElementSibling;
    while (cursor != null) {
      count++;
      cursor = cursor.nextElementSibling;
    }
    return count;
  }

  static int _typeIndex(dom.Element el) {
    final tag = el.localName;
    var count = 1;
    var cursor = el.previousElementSibling;
    while (cursor != null) {
      if (cursor.localName == tag) count++;
      cursor = cursor.previousElementSibling;
    }
    return count;
  }

  static int _typeCount(dom.Element el) {
    final p = el.parentNode;
    if (p == null) return 1;
    final tag = el.localName;
    var count = 0;
    for (final sibling in p.children) {
      if (sibling.localName == tag) count++;
    }
    return count == 0 ? 1 : count;
  }

  static RegExp? _tryCompileRegex(String pattern) {
    if (pattern.isEmpty) return null;
    try {
      return RegExp(pattern);
    } on FormatException {
      return null;
    }
  }

  bool _skipWhitespace() {
    var skipped = false;
    while (pos < input.length && _isWhitespace(input.codeUnitAt(pos))) {
      pos++;
      skipped = true;
    }
    return skipped;
  }

  String _readIdentifier() {
    final sb = StringBuffer();
    while (pos < input.length) {
      final code = input.codeUnitAt(pos);
      if (code == 0x5C && pos + 1 < input.length) {
        pos++;
        sb.writeCharCode(input.codeUnitAt(pos++));
        continue;
      }
      if (_isWhitespace(code) ||
          _isCombinatorChar(code) ||
          code == 0x23 ||
          code == 0x2E ||
          code == 0x5B ||
          code == 0x3A ||
          code == 0x28 ||
          code == 0x29 ||
          code == 0x2C) {
        break;
      }
      sb.writeCharCode(code);
      pos++;
    }
    return sb.toString();
  }

  String _readTagName() {
    final start = pos;
    while (pos < input.length) {
      final code = input.codeUnitAt(pos);
      if (_isIdentChar(code) || code == 0x7C) {
        pos++;
      } else {
        break;
      }
    }
    return input.substring(start, pos);
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 ||
      code == 0x09 ||
      code == 0x0A ||
      code == 0x0D ||
      code == 0x0C;

  static bool _isCombinatorChar(int code) =>
      code == 0x3E || // '>'
      code == 0x2B || // '+'
      code == 0x7E; // '~'

  static bool _isIdentStart(int code) =>
      (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x41 && code <= 0x5A) ||
      code == 0x5F ||
      code == 0x2D ||
      code >= 0x80;

  static bool _isIdentChar(int code) =>
      _isIdentStart(code) || (code >= 0x30 && code <= 0x39);

  static bool _isValidAttrName(String name) =>
      RegExp(r'^[a-zA-Z_:][a-zA-Z0-9_.:-]*$').hasMatch(name);

  static final RegExp _attrOpRegex = RegExp(r'(?:!=|\^=|\$=|\*=|~=|\|=|=)');

  static String _stripOuterQuotes(String raw) {
    if (raw.length >= 2) {
      final first = raw[0];
      final last = raw[raw.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return raw.substring(1, raw.length - 1);
      }
    }
    return raw;
  }
}

class _SelectorStep {
  final String combinator;
  final _CompoundSelector compound;

  const _SelectorStep(this.combinator, this.compound);
}

class _CompoundSelector {
  final String? tagName;
  final List<String> ids;
  final List<String> classes;
  final List<_AttrFilter> attrs;
  final List<_PseudoFilter> pseudos;
  final List<_PositionalFilter> positionals;

  const _CompoundSelector({
    required this.tagName,
    required this.ids,
    required this.classes,
    required this.attrs,
    required this.pseudos,
    required this.positionals,
  });
}

class _AttrFilter {
  final String name;
  final String op;
  final String value;
  final bool caseInsensitive;
  final RegExp? regex;

  const _AttrFilter({
    required this.name,
    required this.op,
    required this.value,
    this.caseInsensitive = false,
    this.regex,
  });
}

class _PseudoFilter {
  static final _PseudoFilter neverMatch = _PseudoFilter((_) => false);

  final bool Function(dom.Element el) matches;

  const _PseudoFilter(this.matches);
}

enum _PositionalKind { eq, gt, lt, first, last, even, odd }

class _PositionalFilter {
  final _PositionalKind kind;
  final int? index;

  const _PositionalFilter(this.kind, [this.index]);
}

class _NthSpec {
  final int a;
  final int b;

  const _NthSpec(this.a, this.b);

  bool matches(int index1Based) {
    if (index1Based < 1) return false;
    if (a == 0) return index1Based == b;
    final diff = index1Based - b;
    if (diff % a != 0) return false;
    return diff ~/ a >= 0;
  }

  static _NthSpec? tryParse(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (normalized.isEmpty) return null;
    if (normalized == 'odd') return const _NthSpec(2, 1);
    if (normalized == 'even') return const _NthSpec(2, 0);

    final simple = int.tryParse(normalized);
    if (simple != null) return _NthSpec(0, simple);

    final match = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(normalized);
    if (match == null) return null;
    final aStr = match.group(1)!;
    final bStr = match.group(2);
    final int a;
    if (aStr.isEmpty || aStr == '+') {
      a = 1;
    } else if (aStr == '-') {
      a = -1;
    } else {
      final parsed = int.tryParse(aStr);
      if (parsed == null) return null;
      a = parsed;
    }
    final b = bStr == null ? 0 : int.tryParse(bStr);
    if (b == null) return null;
    return _NthSpec(a, b);
  }
}
