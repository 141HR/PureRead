# PureRead（净读）

> **开源协议**：GPL-3.0  
> **目标平台**：Windows + Android（基于 Flutter 一套代码构建）

**PureRead（净读）** 是一款主打极致中文排版与高刷翻页体验的跨端开源阅读器。项目通过顶层统一 `BookProvider` 架构融合 **本地大 TXT（`v0.1`）**、**本地 EPUB（`v0.3`）**、**轻量化 JS 插件书源** 与 **渐进式 Legado JSON 书源兼容**，专注纯本地单机深度阅读体验与完整备份能力（`v1.0` 暂不包含双端云同步）。

---

## 技术选型与核心决策

- **UI 与跨端框架**：Flutter（`3.47.7` / Dart `3.13.5`）—— 自绘渲染引擎保障 Windows 与 Android 排版一致及 60/120fps 跟手翻页。
- **书源架构**：统一 `BookProvider` 抽象 + 可插拔四驱动（`LocalTxtProvider` / `LocalEpubProvider` / `JsPluginProvider` / `LegadoCompatProvider`）+ 统一正文净化管道（`ContentSanitizer`）。
- **核心设计原则**：以字符偏移量 `charOffset` 而非页码作为进度锚点；大 TXT 流式建索引并按需分片读；纯本地运行、零遥测，不内置任何小说内容或盗版书源。
- **数据与状态选型**：`Drift (SQLite)` + `flutter_riverpod` + `go_router` + `dio`（域名限流）+ 抽象 `JsRuntime` 沙箱（QuickJS）。

---

## 当前工程阶段

- **当前所处阶段**：**Phase 2（系统架构、核心接口契约与 SQLite 数据库 Schema 设计评审）**
- **下一步动作**：评审通过 Phase 2 架构文档后，执行 **Phase 0 PoC 验证（大 TXT 分页性能 + QuickJS 沙箱双端编译）**，随后进入 **Phase 3 Flutter 工程脚手架搭建**。

---

## 文档导航

| 阶段 | 文档 | 说明 |
| :---: | :--- | :--- |
| Phase 0 | [docs/00-charter.md](./docs/00-charter.md) | 项目章程、范围边界、本机实测环境基线、工程准出标准与已确认决策 |
| Phase 1 | [docs/01-prd.md](./docs/01-prd.md) | 产品需求规格说明书（`v0.1`~`v0.3` MoSCoW 功能与验收标准、量化 NFR、双端布局） |
| Phase 2 | [docs/02-architecture.md](./docs/02-architecture.md) | 系统分层架构、核心 Dart 接口契约、`TextPainter`/Isolate 并发模型、双栏分页与容错设计 |
| Phase 2 | [docs/03-database-schema.md](./docs/03-database-schema.md) | SQLite/Drift 完整 ER 与 9 张表 Schema、索引调优、升级自动备份与 `.pureread.zip` 备份包规范 |
| ADR | [docs/adr/0001-tech-stack-flutter.md](./docs/adr/0001-tech-stack-flutter.md) | ADR-0001：选择 Flutter 作为 Windows + Android 跨端技术栈 |
| ADR | [docs/adr/0002-unified-book-provider.md](./docs/adr/0002-unified-book-provider.md) | ADR-0002：采用统一 `BookProvider` 抽象与多驱动书源架构 |
| ADR | [docs/adr/0003-storage-and-state.md](./docs/adr/0003-storage-and-state.md) | ADR-0003：核心工程依赖与技术组件选型（Drift / Riverpod / GoRouter / Dio / QuickJS） |
