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

## 当前工程阶段与交付进展

- **当前所处阶段**：**Phase 4 已完成（`v0.1` ~ `v0.3` + 真实书源复测补强 + Windows/Android Release 打包与 30MB TXT 性能验证）**
- **工程里程碑**：
  - **Phase 0–3（已完成）**：架构/PRD/数据库 Schema 设计、30MB TXT & QuickJS 双端 PoC 验证、Flutter 工程脚手架搭建（锁定 `qjs: ^0.2.3`）。
  - **Phase 4 M1 `v0.1`（已完成）**：本地大 TXT 流式导入与分章（UTF-8 / GB18030 / UTF-16）、Drift 9 表持久化、自研中文排版分页引擎与 `charOffset` 精准锚点、Windows/Android 双端阅读与交互桥接。
  - **Phase 4 M2 `v0.2`（已完成）**：QuickJS 沙箱与 JS/Legado 双书源引擎、多源聚合搜索/一键换源/4 步调试工作台/正文净化、`.pureread.zip` 本地整库备份与恢复。
  - **Phase 4 M3 `v0.3` & M3.5（已完成）**：本地 EPUB 2/3 解析与封面提取、60/120fps 交互式仿真卷页/纸张纹理/双栏中缝、书架分组管理、纯 Dart AES/DES/SHA/HMAC 加密摘要、`org.jsoup` DOM 桥接与 `:regex` 规则（2,693 条真实书源静态无头支持率达 `90.5%` / 小说类 `95.0%`）。
  - **Release 与性能验证（已完成）**：Windows x64 Release 便携包与 Android R8/ProGuard 压缩 APK 构建与校验通过；30.00 MiB TXT 生产引擎导入实测 **`421–465 ms`**（目标 `< 2.0s`），`191/191` 自动化测试全绿。

---

## 快速构建与测试

```bash
# 安装依赖、静态分析与全量测试
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test

# Windows 桌面端运行与 Release 构建
flutter run -d windows
flutter build windows --release

# Android Release APK 构建（已启用 R8/ProGuard；可按需创建 android/key.properties 配置正式签名）
flutter build apk --release
```

Windows 下也可直接运行 `tool/package_release.ps1` 核验 Release 产物、Android DEX/ABI `.so` 与 `mapping.txt`，并归档便携包与 `SHA256SUMS.txt` 至本地 `dist/` 目录。

---

## 文档导航

| 阶段 | 文档 | 说明 |
| :---: | :--- | :--- |
| Phase 0 | [docs/00-charter.md](./docs/00-charter.md) | 项目章程、范围边界、本机实测环境基线、工程准出标准与已确认决策 |
| Phase 1 | [docs/01-prd.md](./docs/01-prd.md) | 产品需求规格说明书（`v0.1`~`v0.3` MoSCoW 功能与验收标准、量化 NFR、双端布局） |
| Phase 2 | [docs/02-architecture.md](./docs/02-architecture.md) | 系统分层架构、核心 Dart 接口契约、`TextPainter`/Isolate 并发模型、双栏分页与容错设计 |
| Phase 2 | [docs/03-database-schema.md](./docs/03-database-schema.md) | SQLite/Drift 完整 ER 与 9 张表 Schema、索引调优、升级自动备份与 `.pureread.zip` 备份包规范 |
| PoC | [docs/poc/01-txt-pagination-report.md](./docs/poc/01-txt-pagination-report.md) | Phase 0 30MB 大 TXT 流式分章与根 Isolate 增量排版验证报告 |
| PoC | [docs/poc/02-js-provider-report.md](./docs/poc/02-js-provider-report.md) | Phase 0 QuickJS (`qjs: ^0.2.3`) 双端沙箱编译与超时/内存熔断验证报告 |
| M2 | [docs/m2-source-compat-report.md](./docs/m2-source-compat-report.md) | M2 真实书源库（2,693 条）静态解析与 20 源基线实网探测报告 |
| M3 / M3.5 | [docs/m3-compat-update.md](./docs/m3-compat-update.md) | M3 纯 Dart AES/DES 对称加密与 `:regex` 全能规则兼容性更新说明 |
| M3 / M3.5 | [docs/m3-reprobe-compat-report.md](./docs/m3-reprobe-compat-report.md) | M3.5 `org.jsoup`/SHA/HMAC/重定向补强与真实书源复测对比报告 |
| Release | [docs/v0.3-release-and-perf-report.md](./docs/v0.3-release-and-perf-report.md) | `v0.3` Windows/Android Release 打包、ProGuard/R8 审计与 30MB 生产性能压测报告 |
| ADR | [docs/adr/0001-tech-stack-flutter.md](./docs/adr/0001-tech-stack-flutter.md) | ADR-0001：选择 Flutter 作为 Windows + Android 跨端技术栈 |
| ADR | [docs/adr/0002-unified-book-provider.md](./docs/adr/0002-unified-book-provider.md) | ADR-0002：采用统一 `BookProvider` 抽象与多驱动书源架构 |
| ADR | [docs/adr/0003-storage-and-state.md](./docs/adr/0003-storage-and-state.md) | ADR-0003：核心工程依赖与技术组件选型（Drift / Riverpod / GoRouter / Dio / QuickJS） |
