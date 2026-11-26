# Changelog

All notable changes to **PureRead（净读）** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-11-26

### Added
- **在线书源「发现 / 排行榜」全链路**：
  - 领域层新增 `ExploreCategory`、`ExplorableBookProvider` 与 `ProviderCapabilities.supportsExplore` 能力声明。
  - 书源引擎新增 `LegadoExploreRule` / `LegadoExploreParser`（支持 JSON 严格与宽松格式、`\n` / `&&` 分隔并保护 `{...}` 参数与引号、分组标题与裸 URL）及 `LegadoCompatProvider` / `JsPluginProvider` 发现与榜单分页能力（含 `ruleExplore -> ruleSearch` 回退、单分类 `<js>` URL 逐页求值与 `page > 1` 平滑翻页结束）。
  - 应用层新增 `ExploreState`、`ExploreController` 与独立 `exploreBookDetailControllerProvider`（支持书源筛选排序、按源缓存分类、旧请求取消与分页 URL 去重）。
  - 界面层从搜索页抽离可复用的 `OnlineBookDetailPane` 与 `OnlineBookCover`（支持网络封面加载与离线渐变兜底），在主导航接入「发现」（`/explore`）入口，提供桌面三栏/双栏与移动端下钻响应式布局及 `#1/#2/#3` 榜单角标。
- **开源社区规范与自动化配置**：完善 `CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、`SECURITY.md`、`.github/ISSUE_TEMPLATE/` 表单模板、`PULL_REQUEST_TEMPLATE.md`、`release.yml`、`dependabot.yml`、`.editorconfig` 与 `.gitattributes`。

### Changed
- 将项目开源协议由 GPL-3.0 变更为 **MIT License**（含 `LICENSE`、`pubspec.yaml`、Windows `Runner.rc`、应用内关于页及项目章程/PRD/ADR 文档）。
- 升级 `cupertino_icons` 至 `2.0.0` 及 GitHub Actions（`actions/checkout@v7`、`actions/setup-java@v6`、`actions/upload-artifact@v7`、`actions/download-artifact@v8`、`softprops/action-gh-release@v3`），并为 CI 工作流补充最小权限与并发取消策略。

## [0.5.0] - 2026-11-26

### Added
- **EPUB 内联插图支持**：实现 EPUB 资源路径解析与提取（`EpubContainerParser` / `EpubXhtmlExtractor`）、图片尺寸探测（`EpubImageProbe`）、图文混排分页（`InlineImageMarker` / `IncrementalTextPaginator`）、LRU 内存图片缓存（`EpubImageCache`）与全屏/缩放图片查看器（`EpubImageViewerDialog`）。
- **双模式自动阅读（Auto-Read）**：新增 **平滑垂直滚动** 与 **定时自动翻页** 两种自动阅读模式、状态控制器（`AutoReadController`）、阅读器覆盖层（`ReaderAutoReadOverlay`）及悬浮速度控制条（`ReaderAutoReadBar`）。
- **Windows + Android 双端原生 TTS 听书**：
  - Dart 层统一 `TtsEngine` 抽象、中英文智能分句器（`TtsSentenceSplitter`）、播放状态机（`TtsController`）以及底部控制条/设置面板（`ReaderTtsBar` / `ReaderTtsSettingsSheet`）。
  - Windows 端基于原生 COM SAPI 5 / OneCore 实现 `tts_channel_handler`。
  - Android 端实现系统 TTS 引擎桥接（`TtsChannelHandler`）、前台播放服务与 `MediaSession` 锁屏/通知栏控制（`TtsPlaybackService`）。

### Changed
- 将自动阅读的帘幕覆盖模式重构为平滑垂直滚动，与定时自动翻页共同构成双模式自动阅读体验。

### Fixed
- 修复 Windows 平台 CJK 字体族回退配置，避免混合字重渲染导致的字体粗细不一致问题。

## [0.4.0] - 2026-11-25

### Added
- **3A 风格应用图标**：为 Windows (`app_icon.ico`) 与 Android 自适应图标（`mipmap-*` / `ic_launcher`）全面应用 PureRead 视觉图标。
- **自动化多 ABI 发布流水线**：新增 Android `--split-per-abi`（`arm64-v8a`、`armeabi-v7a`、`x86_64`）分包支持与 GitHub Actions 自动发版工作流（`.github/workflows/release.yml`）。
- **书内全文关键字搜索**：支持在阅读器中搜索当前书籍关键字、展示上下文片段并精准跳转至对应 `charOffset`。
- **书源健康度管理**：新增书源批量体检（`SourceHealthChecker`）、导入自动去重以及失效书源一键清理。

### Fixed
- 加固 Legado 兼容层的 JS Mustache 模板与 ID 处理逻辑，提升复杂规则解析稳定性。
- 优化 Android 仿真卷页边缘触控手势判定，减少误触与卡顿。
- 修复 `SettingsPage` 跨平台文件路径 basename 展示兼容性。

## [0.3.0] - 2026-11-25

### Added
- **本地 EPUB 2/3 解析（M3）**：支持 `LocalEpubProvider` 读取 EPUB 容器、OPF 元数据与封面提取、NCX/NAV 目录树及 XHTML 文本段落。
- **高刷交互式仿真翻页与书架分组（M3）**：实现 `SimulationPageCurl` 交互式卷页几何计算、纸张纹理及宽屏双栏中缝；支持书架自定义分组与批量管理。
- **书源兼容与加密能力补强（M3 / M3.5）**：新增纯 Dart AES/DES 对称加密与 SHA/HMAC 摘要、`org.jsoup` DOM 桥接、`ajaxAll`、重定向详情搜索以及 `:regex` 全能列表规则（在 2,693 条真实书源样本中静态无头支持率达 90.5%、小说类达 95.0%）。
- **Release 打包审计与 30 MiB 性能压测**：完成 Android R8/ProGuard 混淆配置、Windows/Android 产物核验脚本（`tool/package_release.ps1`）及 30 MiB UTF-8/GB18030 TXT 端到端性能基线验证（导入 `421–465 ms`）。
- **M1 & M2 基础阅读平台能力**：
  - 本地超大 TXT 流式扫描分章（UTF-8 / GB18030 / UTF-16）与自研中文排版分页引擎（`charOffset` 精准锚点、标点避头尾、中英混排微距、双栏适配）。
  - Drift (SQLite WAL) 9 表持久化架构及数据库升级前自动快照备份。
  - QuickJS 沙箱运行时（`qjs`）与统一 `BookProvider`（`JsPluginProvider` / `LegadoCompatProvider`）、多源聚合搜索、一键换源、4 步可视化调试台、正文净化（`ContentSanitizer`）、静默预加载与 `.pureread.zip` 本地整库备份恢复。

[unreleased]: https://github.com/141HR/PureRead/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/141HR/PureRead/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/141HR/PureRead/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/141HR/PureRead/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/141HR/PureRead/releases/tag/v0.3.0
