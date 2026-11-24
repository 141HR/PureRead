# ADR-0003：核心工程依赖与技术组件选型

- **状态**：已采纳（经 Phase 0 PoC-2 实测锁定）
- **日期**：2026-11-24
- **关联文档**：[系统架构设计](./../02-architecture.md) | [数据库 Schema](./../03-database-schema.md) | [ADR-0001](./0001-tech-stack-flutter.md) | [ADR-0002](./0002-unified-book-provider.md) | [PoC-2 验证报告](../poc/02-js-provider-report.md)

---

## 1. 背景

在确定采用 Flutter（Windows + Android 一套代码）与 `GPL-3.0` 开源协议后，需要在正式搭建工程脚手架（Phase 3）前冻结存储、状态管理、路由、网络抓取、多格式文档解析与嵌入式 JS 沙箱的基础技术选型，避免后期因底层库不兼容或跨端差异导致返工。

---

## 2. 核心组件选型决策

| 领域 | 选定组件 | 备选对比 | 选型理由 |
| :--- | :--- | :--- | :--- |
| **本地数据库** | `drift` + `sqlite3_flutter_libs` | Hive / Isar / sqflite | 1. 书架筛选、万章目录索引、按作用域筛选净化规则天然适合关系型 SQL 与复合索引；<br>2. Drift 提供强类型 Dart 查询、编译期校验、事务与显式版本 Migration 支持；<br>3. `sqlite3_flutter_libs` 在 Windows 与 Android 双端开箱一致，且支持后台 Isolate 执行与内存数据库单测。 |
| **状态管理与 DI** | `flutter_riverpod` | Bloc / Provider / GetX | 1. 编译期安全的依赖注入，方便将 `BookProvider`、Repository 与用例测试解耦；<br>2. 通过细粒度 `select` 控制局部刷新，避免翻页/拖拽调节滑块时触发整页重建；<br>3. 不依赖 `BuildContext`，可直接在纯业务控制层驱动。 |
| **路由导航** | `go_router` | Navigator 2.0 原生 / AutoRoute | 官方维护，支持声明式路由与 `ShellRoute`，便于同一套路由表分别承载 Windows 侧边导航栏壳层与 Android 底部 Tab 壳层。 |
| **网络与编码** | `dio` + 自研限流拦截器 + `cookie_jar` + `charset`（GBK/GB18030 支持） | `http` 包 | 老牌网文站大量使用 GBK/GB18030 编码、自定义 Referer/Header 与 Cookie 会话；`dio` 拦截器体系利于统一实现**按域名限流、重试、取消令牌与调试抓包日志采集**。 |
| **HTML / XML / JSON / ZIP 解析** | `html` + `xpath_selector_html_parser` + `json_path` + `xml` + `archive` | 自写正则硬抠 | 分别覆盖 CSS 选择器、XPath、JSONPath（Legado 规则核心）、EPUB OPF/NCX 容器 XML 解析，以及 EPUB 与 `.pureread.zip` 备份包的解压缩。 |
| **嵌入式 JS 沙箱** | 领域层抽象 `JsRuntime`，底层正式锁定 **`qjs: ^0.2.3`**（`MIT` 协议，QuickJS-NG + Dart Native Assets） | `flutter_qjs` / `flutter_js` / `flutter_qjs_next` / `quickjs_runtime` | 1. 经 Phase 0 PoC-2 于 Flutter `3.47.7` / Dart `3.13.5`（VS Community 2026 + Android SDK `36.1.0` / AGP `9.1.0`）双端实测，`flutter test`、Windows Debug 与 Android APK（内置 `arm64-v8a`/`armeabi-v7a`/`x86_64` 三架构 `libqjs_dart.so`）全部通过，零警告零冲突；<br>2. 基于 Dart Native Assets（`hooks` + `code_assets`），无需 Android SDK 额外安装 `cmake`，无历史 KGP/Groovy 插件包袱；<br>3. 支持原生 C 层 `JS_SetInterruptHandler`（`setDeadline` / `clearDeadline`）、跨 Isolate `JSInterruptHandle` 取消、`JSRuntimeConfig.hardened()` 与堆/栈上限；<br>4. 实测淘汰 `flutter_qjs 0.3.7`（`ffi ^1.0.0` 依赖冲突且 Android Gradle 9 报错）与 `flutter_js 0.8.7`（Android Kotlin/JVM target 编译失败且跨端实现割裂）。 |

---

## 3. GPL-3.0 开源协议兼容性说明

PureRead 采用 **GPL-3.0** 协议发布：
- 上述选用的 Flutter 生态主流依赖大多采用 **MIT / BSD / Apache-2.0** 等宽松协议，与 `GPL-3.0` 完全兼容，可直接链接与分发。
- 引入任何新三方包（尤其是 C/C++ FFI 原生库或字体资源）前，必须在 `pubspec` 评审环节核对许可证类型，禁止引入禁止开源再分发的闭源二进制或冲突许可证资产（特别是内置字体应选用 SIL OFL 或可自由再分发的开源字体）。

---

## 4. 风险与隔离约束

1. **禁止业务层直接硬编码三方库 API**：`Drift`、`Dio`、`qjs` 均收敛在 `infrastructure/` 或具体 `source_engine/` 驱动内部；`domain/` 与 `application/` 层只依赖抽象接口。
2. **QuickJS 沙箱生产基线（PoC-2 已实证）**：
   - 适配器默认启用 `JSRuntimeConfig.hardened()`（禁用 `eval` 与 `Proxy`、64 MiB 堆上限、512 KiB 栈上限），每次脚本执行统一施加 `setDeadline(Duration(seconds: 5))`（结合 `Timer` 与 `JSInterruptHandle.requestInterrupt()` 覆盖 `async/await` 后死循环场景），异常统一映射为 `JsExecutionFailure`。
   - `JSRuntime` 绑定于创建它的单个 Dart `Isolate` 线程，**不可跨 Isolate 传递实例**；后台解析任务应在独立 `Isolate` 内创建/持有运行时，并通过可跨 Isolate 发送的 `JSInterruptHandle` 对接 `CancellationToken` 实现即时取消。
3. **本机与 CI 构建注意事项**：
   - Android 工程（`android/app/build.gradle.kts`）保留本地已安装 NDK 版本自动探测与回退逻辑，避免本机未装齐 Flutter 默认 NDK 版本时无法构建 APK。
   - `qjs` 的 Native Assets 构建脚本默认优先校验拉取预编译动态库，拉取失败时自动回退至 `native_toolchain_c` 本地编译 QuickJS-NG C 源码；CI 环境需保留外网下载能力或缓存 `.dart_tool/hooks_runner/`。
