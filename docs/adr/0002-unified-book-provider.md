# ADR-0002：采用统一 `BookProvider` 抽象与多驱动书源架构

- **状态**：已采纳
- **日期**：2026-11-24
- **关联文档**：[项目章程](./../00-charter.md) | [ADR-0001：技术栈选型](./0001-tech-stack-flutter.md)

---

## 1. 背景

本阅读器需同时承载三类来源截然不同的内容：
1. **本地大 TXT 文件**：无网络请求，需流式编码识别与字节偏移分片读取。
2. **现代轻量化 JS 插件书源**：结构简洁、逻辑透明、易于独立调试和维护。
3. **历史遗留的 Legado JSON 书源生态**：社区存量巨大，但规则语言（DSL）极其庞杂，混杂了自定义 CSS 选择器扩展、XPath、JSONPath、`{{}}` 模板、正则替换、`@Header`、GBK 编码以及 `<js>` 调用 `java.*` 宿主 API 等特性。

如果直接在业务层针对某一种来源硬编码逻辑，会导致阅读器与特定解析器强耦合：要么一开始被 Legado 庞大规则拖垮而无法交付阅读体验，要么后期无法平滑兼容社区现成书源。

---

## 2. 最终决策

采用 **“顶层统一契约 + 可插拔多驱动 + 统一正文净化管道”** 的分层架构（方案 3）：

### 2.1 顶层统一接口 `BookProvider`
阅读器核心、书架更新、搜索、缓存调度和阅读视图层**只面向 `BookProvider` 编程**，完全不感知底层书籍来自本地文件、JS 插件还是 Legado 规则：

```text
[阅读 UI / 书架 / 预缓存调度]
               │
               ▼
       BookProvider 接口
  (search / getBookDetail / getToc / getChapterContent)
               │
    ┌──────────┼───────────┬───────────────┐
    ▼          ▼           ▼               ▼
LocalTxt   LocalEpub    JsPlugin     LegadoCompat
Provider   Provider     Provider       Provider
    │          │           │               │
    └──────────┴───────────┴───────────────┘
               ▼
   统一正文净化管道 (ContentSanitizer)
               │
               ▼
   自研排版与分页引擎 (ReaderEngine)
```

同时，每个驱动通过 `ProviderCapabilities` 显式声明自身支持的能力（如 `supportsSearch`、`supportsChangeSource`、`supportsUpdateCheck`、`isLocal`），上层据此动态控制 UI 入口（例如本地书籍不展示在线换源按钮）。

### 2.2 三个核心驱动的职责与演进节奏

| 驱动实现 | 所属里程碑 | 核心设计要点 |
| :--- | :--- | :--- |
| **`LocalTxtProvider`** | **M1（`v0.1`）** | 永不全量加载大文件到内存；导入时流式探测编码（UTF-8 / GB18030 / UTF-16）并扫描章节标题生成字节区间索引 `(byteStart, byteEnd)` 存入 SQLite；阅读时通过 `RandomAccessFile` 按需分片读取指定章节字节。 |
| **`LocalEpubProvider`** | **M3（`v0.3`）** | 解析 EPUB 2/3 容器（ZIP）、OPF 元数据与封面、NCX/NAV 目录树及 XHTML 章节正文抽取；同样以纯文本/结构化段落块流入 `ContentSanitizer` 与 `ReaderEngine`，与 TXT/在线源共享所有排版与主题能力。 |
| **`JsPluginProvider`** | **M2（`v0.2`）** | 每个书源为标准沙箱 JS 模块，约定导出 `search`、`detail`、`toc`、`content` 四个异步/同步契约函数；宿主仅提供受控的 `http`（自动限流与独立 CookieJar）、`html/xpath/css` 解析器、加解密与调试日志采集器。 |
| **`LegadoCompatProvider`** | **M2~M3（`v0.2`–`v0.3`）** | 遵循 **80/20 渐进兼容原则**：第一阶段优先覆盖常规静态站与标准接口所需的规则子集（GET/POST、`@Header`、GBK 转码、基础 CSS/JSONPath/正则 `##` 替换、`{{}}` 变量与高频 `java.*` JS 桥接）；遇到尚未支持的规则（如强依赖 `webView: true` 的复杂 Cloudflare 验证）返回结构化“暂不支持原因”而非静默失败或崩溃。 |

### 2.3 统一正文净化管道（`ContentSanitizer`）
正文净化（去除广告水印、乱码行、多余空白、段落首行标准化）**独立于驱动之外**：
- 所有驱动返回的原始正文统一流入 `ContentSanitizer`。
- 用户配置的正文替换规则（全局规则 + 按书/按源局部规则）对本地 TXT 与在线书源同等生效，且原始缓存与净化展示分离，避免规则误删后无法恢复正文。

---

## 3. 收益与代价

### 收益
- **MVP 风险可控**：`v0.1` 无需任何网络规则解析器即可依托 `LocalTxtProvider` 完成极致排版体验闭环。
- **调试与容错边界清晰**：单条书源解析失败、超时或 JS 沙箱报错严格隔离在对应驱动实例内，配合统一结构化诊断日志，可快速定位是网络失败、规则未命中还是未支持语法。
- **长期扩展性强**：未来新增 EPUB（`LocalEpubProvider`）或 OPDS 书库无需改动阅读器核心和同步层。

### 代价与约束
- 需要维护一套标准化的领域模型（`Book`、`Chapter`、`SearchResult`、`SourceDiagnostics`）和错误码体系，所有驱动必须严格按契约返回标准错误类型。
- `LegadoCompatProvider` 需维护一份公开的**语法兼容矩阵（Compatibility Matrix）**及对应的离线快照回归测试用例，防止后续迭代引入规则回归。
