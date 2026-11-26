<div align="center">

<img src="./android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="PureRead Logo" width="96" />

# PureRead（净读）

**一款主打极致中文排版、高刷跟手翻页与统一书源架构的 Windows + Android 跨端开源阅读器**

[![PureRead CI](https://github.com/141HR/PureRead/actions/workflows/ci.yml/badge.svg)](https://github.com/141HR/PureRead/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/141HR/PureRead)](https://github.com/141HR/PureRead/releases/latest)
[![License: GPL-3.0](https://img.shields.io/github/license/141HR/PureRead)](./LICENSE)
![Platforms](https://img.shields.io/badge/Platforms-Windows%20%7C%20Android-0078D4)
![Flutter](https://img.shields.io/badge/Flutter-3.47.7-02569B)
![Dart](https://img.shields.io/badge/Dart-3.13.5-0175C2)

</div>

---

**PureRead（净读）** 基于 Flutter（`3.47.7` / Dart `3.13.5`）单一代码库构建，围绕统一 `BookProvider` 架构整合 **本地超大 TXT**、**本地 EPUB 2/3**、**轻量化 JS 插件书源** 与 **渐进式 Legado JSON 书源兼容**，专注纯本地、零遥测的沉浸阅读与完整备份能力（`v1.0` 暂不包含双端云同步）。

---

## 核心特性

- **本地超大 TXT 流式引擎**：支持 UTF-8 / GB18030 / UTF-16 自动编码识别，30 MiB 大文件流式分章建索引与按字节偏移分片读取（生产实测 `421–465 ms`），二次冷启动开书 `< 200 ms`。
- **本地 EPUB 2/3 与内联插图**：支持容器/OPF 元数据与封面提取、NCX/NAV 目录树、XHTML 段落解析，以及内联插图提取、尺寸探测、混排分页、LRU 图片缓存与独立大图查看器。
- **自研中文排版与高刷翻页内核**：以 `charOffset` 字符偏移量为唯一进度锚点（缩放窗口、切换字号/双栏零丢字、零重字），支持行尾标点避头尾、中英数字混排微距、Windows 宽屏双栏与 CJK 字体回退优化、Android 仿真卷页与纸张纹理。
- **双模式自动阅读**：支持 **平滑垂直滚动** 与 **定时自动翻页** 双模式切换，配套悬浮控制条随时调节速度与暂停恢复。
- **Windows + Android 双端原生 TTS 听书**：统一 Dart `TtsEngine` 接口与智能分句控制器；Windows 端采用原生 COM SAPI 5 / OneCore，Android 端采用系统 TTS 前台服务与 `MediaSession` 锁屏/通知栏控播。
- **统一书源与 QuickJS 安全沙箱**：支持轻量化 JS 插件书源与 Legado JSON 书源（纯 Dart AES/DES/SHA/HMAC、`org.jsoup` DOM 桥接与 `:regex` 规则），提供多源聚合搜索、一键换源、4 步可视化调试工作台、书源批量体检与去重、统一正文净化管道（`ContentSanitizer`）及书内全文关键字搜索。
- **完整单机备份与数据安全**：基于 Drift (SQLite WAL) 9 表持久化；数据库 Schema 升级前自动创建回滚快照；支持一键导出/导入 `.pureread.zip` 整库备份包（含书架、进度、书签、书源、净化规则、主题与自定义字体）。

---

## 下载与安装

前往 [GitHub Releases](https://github.com/141HR/PureRead/releases/latest) 下载最新版本安装包，并用 `SHA256SUMS.txt` 校验文件完整性：

| 发布包 | 适用平台与说明 |
| :--- | :--- |
| `pureread-windows-x64.zip` | **Windows x64 便携版**：解压后直接运行 `pureread.exe` |
| `pureread-android-arm64-v8a.apk` | **Android 64 位 ARM（推荐）**：适用于绝大多数现代手机与平板 |
| `pureread-android-armeabi-v7a.apk` | **Android 32 位 ARM**：适用于老旧 ARMv7 设备 |
| `pureread-android-x86_64.apk` | **Android x86_64**：适用于 x86_64 模拟器或平板 |
| `SHA256SUMS.txt` | 各平台构建产物的 SHA-256 校验清单 |

---

## 版本演进

完整更新记录请参阅 [CHANGELOG.md](./CHANGELOG.md)。

| 版本 | 里程碑要点 |
| :---: | :--- |
| **`v0.5.0`** | EPUB 内联插图提取/探测/分页/LRU 缓存与大图查看器；平滑垂直滚动 + 定时翻页双模式自动阅读；Windows COM SAPI 5/OneCore 与 Android 原生 TTS + `MediaSession` 控播；Windows CJK 混合字重回退修复 |
| **`v0.4.0`** | Windows / Android 3A 应用图标；Android `split-per-abi` 分包与 GitHub Release 自动发布流水线；书内关键字搜索与片段跳转；书源批量体检/导入去重/失效清理；Legado 模板表达式与卷页边缘手势加固 |
| **`v0.3.0`** | 本地 EPUB 2/3 解析；仿真卷页与纸张纹理；书架自定义分组；Legado AES/DES/SHA/HMAC 与 `org.jsoup` / `:regex` 兼容加固；R8/ProGuard 压缩包与 30 MiB 生产性能验证 |
| **`v0.1`–`v0.2`** | 本地大 TXT 流式引擎、自研中文排版内核、Drift 9 表持久化、QuickJS 沙箱与 JS/Legado 双书源引擎、聚合搜索/换源/调试工作台、正文净化与 `.pureread.zip` 备份恢复 |

---

## 技术栈与开发构建

- **核心技术选型**：Flutter `3.47.7` / Dart `3.13.5` · `drift` (SQLite WAL) · `flutter_riverpod` · `go_router` · `dio` (+ `cookie_jar`) · `qjs` (`^0.2.3`) · `html` / `xpath_selector_html_parser` / `json_path` / `archive` / `charset`
- **质量保障**：覆盖单元测试、Widget 测试、端到端集成测试与 30 MiB TXT 生产性能基准测试的自动化测试套件。

```bash
# 1. 安装依赖、静态分析与全量测试
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test

# 2. Windows 桌面端运行与 Release 构建
flutter run -d windows
flutter build windows --release

# 3. Android Release 分架构 APK 构建（已启用 R8/ProGuard；可按需配置 android/key.properties 正式签名）
flutter build apk --release --split-per-abi
```

在 Windows 环境下，完成上述双端 Release 构建后，可运行 `tool/package_release.ps1` 自动校验 `pureread.exe`、Android DEX / ABI `.so` 与 R8 `mapping.txt`，并归档至本地 `dist/` 目录及生成 `SHA256SUMS.txt`。

---

## 文档导航

| 类别 | 文档 | 说明 |
| :---: | :--- | :--- |
| 版本记录 | [CHANGELOG.md](./CHANGELOG.md) | 按版本整理的功能新增、变更与修复记录 |
| 贡献指南 | [CONTRIBUTING.md](./CONTRIBUTING.md) | 开发环境配置、分支与提交规范、PR 自检要求 |
| 安全策略 | [SECURITY.md](./SECURITY.md) | 漏洞私密披露流程与沙箱/本地安全边界说明 |
| 行为准则 | [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) | 开源社区行为准则（Contributor Covenant v2.1） |
| Phase 0 | [docs/00-charter.md](./docs/00-charter.md) | 项目章程、范围边界、开发环境基线与已确认决策 |
| Phase 1 | [docs/01-prd.md](./docs/01-prd.md) | 产品需求规格说明书（MoSCoW 功能清单与量化 NFR） |
| Phase 2 | [docs/02-architecture.md](./docs/02-architecture.md) | 系统分层架构、核心接口契约与 Isolate 并发模型 |
| Phase 2 | [docs/03-database-schema.md](./docs/03-database-schema.md) | SQLite/Drift 9 表 Schema、索引调优与 `.pureread.zip` 规范 |
| PoC | [docs/poc/01-txt-pagination-report.md](./docs/poc/01-txt-pagination-report.md) | 30 MiB 大 TXT 流式分章与根 Isolate 增量排版验证报告 |
| PoC | [docs/poc/02-js-provider-report.md](./docs/poc/02-js-provider-report.md) | QuickJS (`qjs: ^0.2.3`) 双端沙箱编译与熔断验证报告 |
| 书源兼容 | [docs/m2-source-compat-report.md](./docs/m2-source-compat-report.md) | M2 真实书源库（2,693 条）静态解析与实网探测基线 |
| 书源兼容 | [docs/m3-compat-update.md](./docs/m3-compat-update.md) | M3 纯 Dart AES/DES 对称加密与 `:regex` 规则兼容性说明 |
| 书源兼容 | [docs/m3-reprobe-compat-report.md](./docs/m3-reprobe-compat-report.md) | M3.5 `org.jsoup`/SHA/HMAC/重定向补强与复测对比报告 |
| Release | [docs/v0.3-release-and-perf-report.md](./docs/v0.3-release-and-perf-report.md) | Windows/Android Release 审计与 30 MiB 生产性能压测报告 |
| ADR | [docs/adr/0001-tech-stack-flutter.md](./docs/adr/0001-tech-stack-flutter.md) | ADR-0001：选择 Flutter 作为 Windows + Android 跨端技术栈 |
| ADR | [docs/adr/0002-unified-book-provider.md](./docs/adr/0002-unified-book-provider.md) | ADR-0002：采用统一 `BookProvider` 抽象与多驱动书源架构 |
| ADR | [docs/adr/0003-storage-and-state.md](./docs/adr/0003-storage-and-state.md) | ADR-0003：核心工程依赖与组件选型（Drift / Riverpod / GoRouter / Dio / QuickJS） |

---

## 合规声明

PureRead 是一款纯本地跨端文档阅读与解析工具：

- **不内置、不提供、不分发任何小说文本或第三方书源规则**；
- **零第三方统计、零行为追踪、零后台遥测**，除用户主动配置的书源或明确触发的解析动作外不发起网络请求；
- 请在遵守所在地法律法规与版权规范的前提下使用自定义书源及本地文档解析功能。

---

## 参与贡献与开源协议

欢迎通过 [Issues](https://github.com/141HR/PureRead/issues) 反馈问题或建议，提交 Pull Request 前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md) 并遵守 [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)。

本项目基于 **GNU General Public License v3.0 (GPL-3.0)** 协议开源，详见 [LICENSE](./LICENSE)。
