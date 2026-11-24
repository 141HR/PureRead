# PureRead（净读）系统架构与核心接口契约（Phase 2）

> **文档状态**：Draft（待评审）  
> **关联文档**：[项目章程](./00-charter.md) | [PRD v1.0](./01-prd.md) | [数据库 Schema](./03-database-schema.md) | [ADR-0003](./adr/0003-storage-and-state.md)

---

## 1. 宏观分层架构与依赖规则

PureRead 采用 **严格单向依赖的分层架构**，确保“极致排版引擎”“多驱动书源引擎”“持久化存储”与“双端自适应 UI”彻底解耦：

```text
┌─────────────────────────────────────────────────────────────────────┐
│ Presentation Layer (lib/presentation/)                              │
│  - 自适应壳层: DesktopShell (侧边栏+分屏) / MobileShell (底部Tab)    │
│  - 阅读画布: ReaderCanvas (CustomPainter / 翻页手势 / 键鼠快捷键)    │
├─────────────────────────────────────────────────────────────────────┤
│ Application Layer (lib/application/)                                │
│  - Riverpod Controllers & UseCases                                  │
│  - 阅读会话控制器 / 书架管理 / 预加载调度器 / 调试台 / 备份恢复服务  │
├─────────────────────────────────────────────────────────────────────┤
│ Domain Layer (lib/domain/)  【纯 Dart，零 Flutter/DB/HTTP 依赖】     │
│  - 核心实体与值对象: Book, ChapterMeta, ReadingAnchor, PageSlice     │
│  - 抽象契约: BookProvider, ReaderPaginator, ContentSanitizer, Repos  │
│  - 密封错误体系: AppFailure                                          │
├──────────────────────────────┬──────────────────────────────────────┤
│ Engine Layer (lib/engine/)   │ Infrastructure Layer (lib/infra...)  │
│  - reader_engine/            │  - Drift SQLite DB & DAOs            │
│    分页器 / 中文禁则 /       │  - 文件存储 (Cache/Fonts/Backups)    │
│    锚点映射 / 三章页缓存环   │  - Dio 限流客户端 & CookieJar         │
│  - source_engine/            │  - QuickJS 沙箱适配器                │
│    local_txt / local_epub /  │  - Platform Bridges                  │
│    js_plugin / legado_compat │    (音量键 / 屏幕常亮 / 窗口控制)     │
│    sanitizer (正文净化管道)  │                                      │
└──────────────────────────────┴──────────────────────────────────────┘
```

### 硬性依赖边界规则
1. `domain/` **禁止**引入 `package:flutter/*`、`drift`、`dio` 等任何框架或基础设施库（仅允许纯 Dart 核心库与不可变模型）。
2. `presentation/` **禁止**直接访问数据库 DAO、文件系统 `File`、HTTP 客户端或编写爬虫/分页算法，所有动作通过 `application/` 层状态控制器发起。
3. `engine/source_engine/` 各驱动彼此隔离，统一实现 `BookProvider` 契约并向上层返回标准的 `AppFailure` 或领域对象。

---

## 2. 推荐仓库目录结构

```text
lib/
├── main.dart
├── app/
│   ├── app.dart                      # MaterialApp.router + 主题响应
│   ├── router.dart                   # GoRouter 声明式路由与双端 ShellRoute
│   └── providers.dart                # 顶层 DI 容器装配
├── domain/
│   ├── entities/                     # Book, ChapterMeta, BookSource, ReplaceRule, ReaderTheme...
│   ├── value_objects/                # ReadingAnchor, PaginationConfig, PageSlice, ProviderCapabilities
│   ├── failures/                     # AppFailure 密封类体系
│   ├── repositories/                 # BookRepository, SourceRepository, ThemeRepository, BackupRepository
│   └── services/                     # BookProvider, ReaderPaginator, ContentSanitizer, JsRuntime
├── application/
│   ├── bookshelf/                    # 书架列表、导入本地书、批量更新检查
│   ├── reader/                       # ReaderSessionController、三章缓存协调、预加载队列调度
│   ├── search/                       # 多源聚合搜索与一键换源比对
│   ├── source_lab/                   # 书源管理与可视化调试工作台状态
│   └── backup/                       # .pureread.zip 导入导出用例
├── engine/
│   ├── reader_engine/
│   │   ├── chinese_typesetting.dart  # 中文避头尾禁则、中英混排间距计算
│   │   ├── paginator_impl.dart       # 增量分页与双栏逻辑页切片
│   │   ├── anchor_mapper.dart        # charOffset <-> PageSlice 双向映射
│   │   └── page_cache_ring.dart      # 上一章/当前章/下一章三章滑动页缓存环
│   └── source_engine/
│       ├── local_txt/                # 编码识别、流式分章扫描、RandomAccessFile 分片读
│       ├── local_epub/               # (v0.3) EPUB 容器、OPF/NCX/XHTML 抽取
│       ├── js_plugin/                # 轻量化 JS 插件书源驱动
│       ├── legado_compat/            # 渐进式 Legado JSON 书源解析与规则引擎
│       └── sanitizer/                # ContentSanitizer 正则净化管道（含防超时守卫）
├── infrastructure/
│   ├── database/                     # Drift 数据库定义、DAOs、Migration 与升级前自动备份
│   ├── storage/                      # AppPathResolver（标准/便携模式）、字体与缓存文件管理
│   ├── network/                      # Dio 实例、域名令牌桶限流器、CookieJar
│   ├── js/                           # QuickJS Runtime 具体适配实现
│   └── platform/                     # Windows 窗口/快捷键/老板键；Android 音量键/沉浸/常亮
└── presentation/
    ├── shells/                       # DesktopShell / MobileShell 自适应布局壳
    ├── bookshelf/                    # 书架页
    ├── reader/                       # 阅读页、CustomPainter 画布、覆盖/平移/滚动/双栏组件、设置面板
    ├── search/                       # 搜索与详情页
    ├── sources/                      # 书源列表、净化规则与调试工作台 UI
    └── settings/                     # 备份恢复与系统设置页
test/
├── domain/
├── engine/
│   ├── reader_engine/                # 字数守恒、标点避头尾、charOffset 重排一致性单测
│   └── source_engine/                # TXT 编码与分章、EPUB、JS 源、Legado 规则单测
├── infrastructure/                   # Drift Migration 与备份恢复集成测试
└── fixtures/                         # 离线 TXT 语料、EPUB 样本、HTML/JSON 书源快照
```

---

## 3. 核心领域契约（MVP 冻结边界）

以下 Dart 接口骨架作为 Phase 2 冻结边界，保障各层可并行开发与独立测试：

### 3.1 统一书籍供给接口 `BookProvider`

```dart
enum ProviderType { localTxt, localEpub, jsPlugin, legado }

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
}

class SourceDebugTrace {
  final String step;          // search / detail / toc / content
  final int elapsedMs;
  final int? httpStatus;
  final String? requestUrl;
  final String? matchedPreview;
  final List<String> logs;
  final String? errorMessage;
  const SourceDebugTrace({...});
}

abstract interface class BookProvider {
  String get providerId;
  ProviderType get type;
  ProviderCapabilities get capabilities;

  Future<({List<BookSearchItem> items, SourceDebugTrace trace})> search(
    String keyword, {
    int page = 1,
    CancellationToken? cancelToken,
  });

  Future<({BookDetail detail, SourceDebugTrace trace})> getBookDetail(
    String bookUrl, {
    CancellationToken? cancelToken,
  });

  Future<({List<ChapterMeta> chapters, SourceDebugTrace trace})> getToc(
    String tocUrl, {
    CancellationToken? cancelToken,
  });

  Future<({ChapterContent content, SourceDebugTrace trace})> getChapterContent(
    ChapterMeta chapter, {
    CancellationToken? cancelToken,
  });
}
```

### 3.2 统一正文净化管道 `ContentSanitizer`

```dart
class SanitizeContext {
  final String bookId;
  final String? sourceId;
  final String chapterTitle;
  const SanitizeContext({required this.bookId, this.sourceId, required this.chapterTitle});
}

abstract interface class ContentSanitizer {
  /// 按优先级顺序应用全局、书源级与单书级净化规则；
  /// 同时执行段首/空行标准化，不修改磁盘上保留的原始正文快照。
  Future<String> sanitize(String rawContent, SanitizeContext context);
}
```

### 3.3 排版与阅读锚点契约

```dart
class ReadingAnchor {
  final int chapterIndex;
  final int charOffset;             // 章节净化后正文中的字符偏移（唯一真实进度锚点）
  final String chapterTitleSnapshot;
  const ReadingAnchor({
    required this.chapterIndex,
    required this.charOffset,
    required this.chapterTitleSnapshot,
  });
}

class PaginationConfig {
  final double columnWidth;         // 单栏宽（双栏模式下为 (viewportWidth - columnGap) / 2）
  final double columnHeight;
  final int columnCount;            // 1 或 2
  final double columnGap;
  final String fontFamily;
  final String? fontFilePath;
  final double fontSize;
  final int fontWeightValue;
  final double lineHeightMultiplier;
  final double paragraphSpacing;
  final double letterSpacing;
  final int paragraphIndentChars;
  final bool enablePunctuationHanging; // 行尾标点避头尾
  final bool enableCjkSpacing;         // 中英数字混排微距
  const PaginationConfig({...});
}

class PageSlice {
  final int chapterIndex;
  final int pageIndex;
  final int startCharOffset;        // 闭区间起点
  final int endCharOffset;          // 开区间终点（满足相邻页端到端严格连续，零丢字零重字）
  final List<LayoutLine> lines;     // 供 CustomPainter 直接绘制的预处理行信息
  const PageSlice({...});
}

abstract interface class ReaderPaginator {
  /// 优先定位并计算包含 targetOffset 的首屏附近页，支持时间片增量补全整章页序列
  Future<List<PageSlice>> paginateChapter({
    required int chapterIndex,
    required String sanitizedText,
    required PaginationConfig config,
    int? priorityCharOffset,
  });
}
```

---

## 4. 关键技术深水区与并发模型

### 4.1 `dart:ui` / `TextPainter` Isolate 约束与破局方案

Flutter 的 `TextPainter` 与 `ParagraphBuilder` 底层依赖 `dart:ui` 原生引擎，**不能在普通后台 `Isolate`（无 UI 上下文）中直接实例化调用**。针对这一硬约束，PureRead 采用 **“计算下沉 Isolate + 主线程时间片增量分页”** 的混合模型：

1. **纯后台 `Isolate` 工作池（CPU / I/O 密集型）**：
   - 30MB+ 本地 TXT 编码识别（UTF-8 / GB18030 / UTF-16）与正则章节字节索引扫描；
   - `RandomAccessFile` 章节分片读取；
   - EPUB ZIP 解包、OPF/NCX XML 与 XHTML 纯文本抽取；
   - 网络抓取、HTML/XPath/JSONPath/Legado 规则解析与 QuickJS 脚本执行；
   - `ContentSanitizer` 正则替换管道（为单条规则设置执行超时与正则保护，防恶意规则 ReDoS 卡死）。
2. **排版分页双策略（将在 Phase 0 PoC-1 实测选优）**：
   - **基线方案（时间片增量分页）**：进入阅读或切换字号时，基于 `ReadingAnchor.charOffset` 估算字符切片窗口，主线程先只对锚点所在段前后排布 2~3 页（目标耗时 `< 8ms`）立即出图；随后利用每帧空闲时间片预算（`<= 4ms/帧`）增量排完当前章全部页并写入「上一章 / 当前章 / 下一章」三章页缓存环，翻页阶段 `CustomPainter` 仅做纯 Canvas 绘制。
   - **可选优化（字宽查表预排版）**：针对当前字体和字号缓存高频汉字、ASCII 字符与标点的排版宽度表，在后台 Isolate 预先完成大致折行与段高估算，主线程仅校验标点避头尾细节。

### 4.2 桌面宽屏双栏分页模型

PureRead 不为双栏单独编写两套折行逻辑，而是采用 **逻辑单页等价复用模型**：
- 当系统判定当前为双栏模式时，将逻辑单页宽计算为 `columnWidth = (contentWidth - columnGap) / 2`；
- 分页器输出统一的线性逻辑页序列 `[P0, P1, P2, ..., Pn]`；
- 桌面画布渲染第 `k` 屏时，左栏绘制 `P_{2k}`，右栏绘制 `P_{2k+1}`（若总页数为奇数且翻到末屏，右栏自然留白）；
- 单/双栏切换、拖拽窗口改变宽度时，直接读取当前左栏（或单栏）的 `startCharOffset` 触发重排与重锚，**天然保证左栏尾字与右栏首字零丢字、零重字**。

### 4.3 在线预加载与域名限流调度器

- **优先级队列**：用户当前阅读请求（点击目录/手动翻页）拥有最高优先级并立即执行；读到第 `N` 章时，调度器低优先级静默入队 `N+1`、`N+2`、`N+3` 章（每章检查 `chapters.is_cached`，已缓存直接跳过）。
- **域名级隔离限流**：按书源主域名（Host）维护独立令牌桶（遵循 `book_sources.rate_limit_ms`，默认例如 500ms/次）与独立 `CookieJar`，避免批量缓存触发反爬封 IP。
- **生命周期取消**：离开阅读页或切换书籍时，通过 `CancellationToken` 自动取消队列中尚未发出的过期预加载任务。

---

## 5. 双端本地存储目录规划

严格遵循 **“元数据进 SQLite，大正文文本进独立缓存文件，严禁把整本小说正文塞入数据库”** 原则，防止数据库体积膨胀导致查询、备份与迁移变慢：

| 目录类别 | 逻辑路径 | 存放内容 | 清理/迁移策略 |
| :--- | :--- | :--- | :--- |
| **持久化数据区** (`AppDataDir`) | `db/pureread.db` | SQLite 主库（书架、章节索引、进度、书源、规则、主题） | 随应用持久化，升级前自动备份 |
| **持久化数据区** | `db/backups/` | 升级前自动生成的历史 DB 快照（滚动保留最近 3 份） | 仅保留最近 3 个版本，防磁盘占满 |
| **持久化数据区** | `fonts/` | 用户手动导入的 `.ttf / .otf` 字体文件 | 可随 `.pureread.zip` 备份包可选导出 |
| **持久化数据区** | `covers/` | 书籍封面图片本地缓存 | 删除书籍时联动清理对应封面 |
| **可重建缓存区** (`AppCacheDir`) | `chapters/{bookId}/{chapterIndex}.txt` | 在线书源抓取后的**原始正文文本**（按需持久化） | 用户“清理缓存”时可安全清除，不影响书架与进度 |
| **可重建缓存区** | `tmp/` | 解包 EPUB 或导入备份包时的临时工作区 | 任务结束或启动时自动清理 |

> **Windows 便携模式预留**：`AppPathResolver` 在启动时若检测到可执行文件同级存在 `portable/` 目录或 `.portable` 标记文件，自动将数据区与缓存区重定向至程序同级 `portable/data/`，否则使用系统标准 `ApplicationSupport` 目录。

---

## 6. 异常隔离与统一错误处理

`domain/failures/` 定义统一的密封错误基类 `AppFailure`，所有引擎层与基础设施层异常必须在边界处转换为可解释的领域错误，**禁止未捕获异常传播到 UI 导致崩溃**：

| 错误类型 | 触发场景示例 | 业务表现与恢复策略 |
| :--- | :--- | :--- |
| `NetworkFailure` | 连接超时、DNS 失败、HTTP 403/404/5xx | 预加载静默记录跳过；前台阅读展示“重试 / 一键换源”引导按钮 |
| `SourceParseFailure` | CSS/XPath/JSONPath 规则未命中关键字段 | 写入 `SourceDebugTrace` 并标记该源最近状态异常；支持单源隔离 |
| `UnsupportedLegadoRuleFailure` | 遇到需要 `webView: true` 或未支持的 `java.*` 方法 | 明确提示“当前源使用了暂未支持的 Legado 高级特性”，建议换源 |
| `JsExecutionFailure` | QuickJS 脚本语法错误、运行时异常或执行超时 | 沙箱强制终止脚本并释放实例，返回结构化 JS 错误栈给调试工作台 |
| `EncodingFailure` | 未知本地 TXT 编码或文件损坏无法解码 | 回退尝试常见编码并提示用户手动指定编码重新导入 |
| `FileAccessFailure` | 原本地 TXT/EPUB 文件被用户移动或删除 | 提示“源文件不存在”并允许重新定位关联本地文件路径 |
| `DatabaseFailure` | 数据库写入/迁移失败 | 触发回滚并提示从 `db/backups/` 恢复最近安全快照 |
