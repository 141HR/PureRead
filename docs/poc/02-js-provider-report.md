# PoC-2 工程验证报告：QuickJS 运行时选型与统一 `BookProvider` 原型

> **验证日期**：2026-11-24  
> **目标基线**：Flutter `3.47.7`（stable）/ Dart `3.13.5` / Windows 11 25H2（Visual Studio Community 2026 `18.11.1`）/ Android SDK `36.1.0`（AGP `9.1.0`、Gradle `9.3.1`、JDK `21`、本地已安装 NDK `30.0.16248370`）  
> **PoC 工程路径**：[poc_js_provider](file:///D:/READ/poc/poc_js_provider/pubspec.yaml)  
> **开源协议合规**：PureRead 采用 `GPL-3.0`；本报告锁定方案均采用 `MIT` / `BSD` 宽松协议，可无冲突链接与分发。

---

## 1. 结论摘要

1. **最终锁定嵌入式 JS 引擎绑定包**：**`qjs: ^0.2.3`**（实测锁定版本 `0.2.3`，`MIT` 协议，底层为 QuickJS-NG）。
   - **选型核心依据**：`qjs` 基于 Dart 官方 **Native Assets**（`hooks: 2.2.0` + `code_assets: 2.2.0` + `native_toolchain_c: 0.19.6` + `ffi: 2.2.0`），零 Flutter Plugin Groovy/KGP 兼容包袱，无需 Android SDK 额外安装 `cmake` 或降级 NDK。
   - **双端与测试全通**：同一套代码在 `flutter analyze`（0 issues）、`flutter test`（13/13 全部通过，Dart VM 直接自动加载 `qjs_dart.dll`，无需手动拷贝 DLL 或配置环境变量）、`flutter build windows --debug`（28.5s，`qjs_dart.dll` 随包输出）与 `flutter build apk --debug`（50.1s，`arm64-v8a`/`armeabi-v7a`/`x86_64` 三架构自动打包 `libqjs_dart.so`）全部实测通过。
   - **沙箱与中断隔离完备**：支持原生 C 层 `JS_SetInterruptHandler` 墙钟超时中断（`setDeadline` / `clearDeadline`）、跨 Isolate `JSInterruptHandle.requestInterrupt()` 协同取消、`JSRuntimeConfig.hardened()`（禁用 `eval` 与 `Proxy`、64 MiB 堆上限、512 KiB 栈上限），实测同步死循环、异步 `await` 后死循环、内存超限与脚本异常均在毫秒级安全捕获并映射为结构化 `JsExecutionFailure`，宿主零崩溃、零卡死。
2. **统一 `BookProvider` 原型全链路跑通**：
   - 在本地回环 `dart:io` `HttpServer`（`127.0.0.1:<ephemeral>`，零外网依赖）下，完整跑通 **`JsPluginProvider`**（4 方法 `search`/`getBookDetail`/`getToc`/`getChapterContent` + UTF-8 JSON/HTML + `host.httpGet`/`cssSelect`/`jsonPath`）与 **`LegadoCompatProvider`**（`POST` 请求、自定义 Header、`GBK` 转码解码、CSS `@text`/`@href`/`@html`、`##regex##replacement`、QuickJS `<js>` 片段及 `webView: true` / Rhino `Packages.*` 优雅降级为 `UnsupportedLegadoRuleFailure`）。

---

## 2. QuickJS 候选包双端实测评估矩阵

在 `Flutter 3.47.7` / `Dart 3.13.5` 环境下，对 pub.dev 候选包执行了依赖解析、源码架构审计与真实 Windows + Android Debug 构建实测：

| 候选包与版本 | 协议 | 绑定架构 | `flutter test`（Windows VM） | `flutter build windows --debug` | `flutter build apk --debug`（AGP 9.1.0 / SDK 36.1.0） | 实测结论与阻塞问题 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`flutter_qjs` (`0.3.7`)** | `MIT` | Flutter FFI Plugin（CMake） | 需手动设置 `test/build/Debug/ffiquickjs.dll` | **通过**（62.5s，大量 `C4244`/`C4267` 与 CMake `<3.10` 弃用警告） | **失败**（15.7s，`exit 1`） | **淘汰**：1. SDK 约束 `<3.0.0` 且强依赖 `ffi ^1.0.0`，锁定 `ffi 1.2.1` 并与 `ffi ^2.x` 生态冲突（污染 `flutter_js`/`sqlite3_flutter_libs` 等依赖解析）；2. `android/build.gradle` 缺失 `namespace`、使用 Gradle 9 已移除的 `jcenter()`，报 `Could not find method jcenter()` 及 `NullPointerException`。 |
| **`flutter_js` (`0.8.7`)** | `MIT` | Win 预编译 DLL + Android JitPack/MethodChannel | 需手工确保 `quickjs_c_bridge.dll` 在搜索路径 | **通过**（17.3s，拷贝闭源预编译 `quickjs_c_bridge.dll`） | **失败**（279.4s，`exit 1`） | **淘汰**：1. 触发 Flutter 3.47 警告 `plugins that apply Kotlin Gradle Plugin (KGP)`，且在 `:flutter_js:compileDebugKotlin` 报错 `Inconsistent JVM-target compatibility detected for tasks 'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (1.8)`；2. Windows 依赖预编译二进制 DLL、Android 走 MethodChannel + JitPack `fastdev-jsruntimes-quickjs:0.3.6`，跨端实现割裂且不支持后台 Isolate 直接运行；3. `getJavascriptRuntime()` 未暴露超时中断。 |
| **`flutter_qjs_next` (`1.5.2`)** | `MIT` | Flutter FFI Plugin（CMake） | 需预先构建 Windows 产物的 `flutter_qjs_next_plugin.dll` 或设置 `FLUTTER_QJS_NEXT_LIBRARY` | **通过**（19.8s，QuickJS `2026-06-04`，含 `msvc-compat.h` 编码页 C4819/C4146 警告） | **受限于本机工具链**（未预装 Android SDK `cmake`，且插件未声明本地 NDK fallback，触发 AGP 尝试下载 ~1GB NDK `28.2.13676358`） | **备选（第 2 位）**：原生支持 `timeout`（`GetTickCount64` / `clock_gettime`）、`memoryLimit`（64 MiB）与 `JsEnginePool`，代码质量高；但作为传统 CMake Flutter Plugin，要求本机/CI 均额外安装 Android SDK CMake，且 `flutter test` 不能开箱即用。 |
| **`quickjs_runtime` (`0.4.9`)** | `MIT` | Pure Dart + Native Assets | 未运行 | 未运行 | 未运行 | **静态审计淘汰**：其官方文档明确声明 `No timeouts: a dispatched function that never returns blocks its caller forever, like any infinite script loop`，缺少运行期字节码超时中断机制，不满足书源异常隔离 NFR。 |
| **`quickjs_engine` (`0.1.7`)** | `MIT` | Flutter FFI Plugin（QuickJS-NG 0.14.0） | 需预先编译并配置 `LIBQUICKJSC_TEST_PATH` | 未运行 | 未运行 | **静态审计淘汰**：`flutter_js` 的 QuickJS-NG 移植版（Java 插件类已兼容 AGP 9），但仅提供 Dart `Future.timeout`，未暴露 `JS_SetInterruptHandler` 死循环强杀接口，且同样依赖 Android SDK CMake。 |
| **`qjs` (`0.2.3`)** | `MIT` | Pure Dart + Dart Native Assets（`hooks` + `code_assets`） | **开箱即用通过**（自动构建/缓存原生库，无需手工拷贝 DLL） | **通过**（28.5s，零警告） | **通过**（50.1s，`arm64-v8a` / `armeabi-v7a` / `x86_64` 自动内置 `libqjs_dart.so`） | **最终锁定**：1. `MIT` 协议（含内置 QuickJS-NG 源码 MIT 许可），与 `GPL-3.0` 100% 兼容；2. 支持 `setDeadline` + `JSInterruptHandle` + `JSRuntimeConfig.hardened()` + 内存/栈限制；3. 同时兼容 `flutter test`、后台 Dart `Isolate` 及 Windows/Android 构建，无 CMake/KGP 历史包袱。 |

> **关键工程发现（Android NDK 版本解析）**：本机 `D:\dev\android-sdk\ndk` 仅预装了 `30.0.16248370`，而 Flutter 3.47.7 默认 `flutter.ndkVersion` 为 `28.2.13676358`（直接构建默认模板会因 sdkmanager 无法拉取 `28.2.13676358` 而阻塞）。在 [build.gradle.kts](file:///D:/READ/poc/poc_js_provider/android/app/build.gradle.kts#L11-L30) 中采用“检测本地已安装 NDK（校验 `source.properties`），存在 `flutter.ndkVersion` 时优先使用、否则回退至本地最新版本”的策略后，`qjs 0.2.3` 的 Android APK 构建一次通过。

---

## 3. PoC 工程架构与依赖清单

PoC 项目位于 [d:\READ\poc\poc_js_provider\](file:///D:/READ/poc/poc_js_provider/pubspec.yaml)，严格对齐 Phase 2 分层架构与已冻结的 `lib/domain/` 契约：

- **精确锁定依赖版本**（来自 [pubspec.lock](file:///D:/READ/poc/poc_js_provider/pubspec.lock)）：
  - JS 运行时：`qjs: 0.2.3`（传递依赖 `hooks: 2.2.0`、`code_assets: 2.2.0`、`native_toolchain_c: 0.19.6`、`ffi: 2.2.0`）
  - 网络与编码：`dio: 5.11.1`、`cookie_jar: 4.0.9`、`dio_cookie_manager: 3.5.0`、`charset: 2.0.1`
  - HTML / XPath / JSONPath 解析：`html: 0.15.7`、`xpath_selector_html_parser: 3.0.1`、`json_path: 0.9.0`
- **核心模块实现**：
  - 领域契约层（纯 Dart，零 Flutter/Dio/QuickJS 依赖）：[domain.dart](file:///D:/READ/poc/poc_js_provider/lib/domain/domain.dart)、[app_failure.dart](file:///D:/READ/poc/poc_js_provider/lib/domain/failures/app_failure.dart)、[book_provider.dart](file:///D:/READ/poc/poc_js_provider/lib/domain/services/book_provider.dart)、[js_runtime.dart](file:///D:/READ/poc/poc_js_provider/lib/domain/services/js_runtime.dart)
  - QuickJS 沙箱适配器：[QjsSandboxRuntime](file:///D:/READ/poc/poc_js_provider/lib/infrastructure/js/qjs_sandbox_runtime.dart)
  - HTTP 与编码嗅探客户端（按 `explicitCharset -> Content-Type -> <meta charset> -> UTF-8 -> GBK` 解码）：[SourceHttpClient](file:///D:/READ/poc/poc_js_provider/lib/infrastructure/network/source_http_client.dart)
  - 共享选择器工具（CSS `@text`/`@html`/`@href`/`@attr` + 索引 + XPath + JSONPath）：[HtmlSelectorHelper](file:///D:/READ/poc/poc_js_provider/lib/engine/source_engine/parsing/html_selector_helper.dart)
  - JS 插件驱动：[JsPluginProvider](file:///D:/READ/poc/poc_js_provider/lib/engine/source_engine/js_plugin/js_plugin_provider.dart)
  - Legado 兼容驱动：[LegadoBookSource](file:///D:/READ/poc/poc_js_provider/lib/engine/source_engine/legado_compat/legado_source.dart)、[LegadoRuleEvaluator](file:///D:/READ/poc/poc_js_provider/lib/engine/source_engine/legado_compat/legado_rule_evaluator.dart)、[LegadoCompatProvider](file:///D:/READ/poc/poc_js_provider/lib/engine/source_engine/legado_compat/legado_compat_provider.dart)
  - 本地离线测试桩：[MockBookServer](file:///D:/READ/poc/poc_js_provider/test/fixtures/mock_book_server.dart)

---

## 4. 自动化测试、构建产物与延迟基准结果

### 4.1 构建与静态检查验证（最终修改后实测）

| 验证命令 | 结果 | 耗时 | 产物与关键细节 |
| :--- | :---: | :---: | :--- |
| `flutter analyze` | 通过（0 issues） | 3.7s | 无任何警告或错误 |
| `flutter test --reporter expanded --concurrency=1` | 通过（13/13） | ~2.5s | 覆盖 `js_plugin_provider_test.dart` (6)、`legado_compat_provider_test.dart` (4)、`qjs_smoke_test.dart` (2)、`widget_test.dart` (1) |
| `flutter build windows --debug` | 通过（exit 0） | 28.5s | [poc_js_provider.exe](file:///D:/READ/poc/poc_js_provider/build/windows/x64/runner/Debug/poc_js_provider.exe)（1,267,200 bytes）+ `qjs_dart.dll`（1,114,112 bytes） |
| `flutter build apk --debug` | 通过（exit 0） | 50.1s | [app-debug.apk](file:///D:/READ/poc/poc_js_provider/build/app/outputs/flutter-apk/app-debug.apk)（153,973,697 bytes）；APK `lib/` 内含：<br>• `lib/arm64-v8a/libqjs_dart.so`（1,174,408 bytes）<br>• `lib/armeabi-v7a/libqjs_dart.so`（812,772 bytes）<br>• `lib/x86_64/libqjs_dart.so`（1,273,440 bytes） |

### 4.2 双驱动全链路执行延迟（本地回环 `HttpServer` 实测）

以下数据来自最终一次 `flutter test --reporter expanded --concurrency=1` 真实打印输出（包含首轮 `Dio` 客户端与 QuickJS VM 冷启动 + 规则解析耗时）：

| 驱动 | `search` | `getBookDetail` | `getToc` | `getChapterContent` | 稳态热请求均值（10 次正文抓取+CSS解析） |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **`JsPluginProvider`**（UTF-8 JSON/HTML + `async/await` + `host.*` 桥接） | **106 ms** | **37 ms** | **9 ms** | **6 ms** | **4.90 ms**（样本 `[6, 4, 5, 5, 5, 5, 5, 4, 5, 5]` ms） |
| **`LegadoCompatProvider`**（POST + `X-Client-Token` + GBK 解码 + CSS + `##regex##` + `<js>`） | **96 ms** | **13 ms** | **6 ms** | **33 ms** | — |

---

## 5. 超时隔离、内存限额与错误边界发现

在 [js_plugin_provider_test.dart](file:///D:/READ/poc/poc_js_provider/test/js_plugin_provider_test.dart) 与 [legado_compat_provider_test.dart](file:///D:/READ/poc/poc_js_provider/test/legado_compat_provider_test.dart) 中针对恶意/异常脚本进行了 5 类压测验证：

1. **同步死循环中断（`while (true) {}`）**：
   - 设置 `timeout: 80ms`，`QjsSandboxRuntime` 通过 `rt.setDeadline(timeout)` 触发 QuickJS C 层 `interrupt_handler`，在 **85 ms** 内抛出可捕获 `JsExecutionFailure(isTimeout: true)`。
   - 清除 deadline 后同一 `JSRuntime` 实例立即恢复可用（后续执行 `'6 * 7'` 返回 `'42'`）。
2. **`async/await` 异步回调后死循环中断**：
   - 在 `await host.httpGet(...)` 返回 HTTP 200 后进入 `while (true) {}`（模拟网络阶段正常、解析阶段恶意死循环的插件），`scriptTimeout: 120ms` 下实测在 **121 ms** 内通过 `onUncaughtError` + `Timer` + `JSInterruptHandle` 双保险终止并返回 `JsExecutionFailure(isTimeout: true)`，未挂死事件循环。
3. **后台 Isolate + `CancellationToken` 协同取消**：
   - 将 `JSRuntime` 置于独立 Dart `Isolate.run` 中执行 `while (true) {}`，通过 `SendPort` 回传纯数值句柄 `JSInterruptHandle` 并绑定到 `CancellationToken`；主 Isolate 调用 `cancelToken.cancel()` 后，跨线程原子标志位 `qjs_runtime_request_interrupt` 立即打断后台 QuickJS 字节码循环并返回 `InternalError: interrupted`。
4. **内存限额保护（`memoryLimitBytes: 2 MiB`）**：
   - 连续分配大字符串数组时触发 QuickJS `out of memory` 保护，转换为 `JsExecutionFailure` 抛出，宿主进程未出现原生 OOM 闪退；调用 `resetRuntime()` 即可重建干净虚拟机。
5. **Legado 不支持特性与运行时错误隔离**：
   - 顶层 `"webView": true`、URL 选项 `,{"webView":true}` 均在发请求前快速短路返回 `UnsupportedLegadoRuleFailure(feature: 'webView')`。
   - 规则内含 Rhino 专属 `Packages.*` 或 `java.webView` 时返回 `UnsupportedLegadoRuleFailure(feature: 'rhino_java_api')`。
   - Legado `<js>while(true){}</js>` 恶意脚本同样在 80ms 级别被中断为 `JsExecutionFailure(isTimeout: true)`；HTTP 404 响应映射为 `NetworkFailure(statusCode: 404)`。

> **架构级重要约束（生产集成必读）**：
> - `qjs` 的 `JSRuntime` 与 `JSValue`/`JSObject` 绑定于创建它的单个 Dart `Isolate` 线程，**不可跨 Isolate 传递 `JSRuntime` 实例**；需要 UI 零卡顿时，应由后台 Isolate 持有 `JSRuntime`（或每个解析任务在 `Isolate` 内创建短生命周期 `JSRuntime`，冷启动仅数毫秒），并通过可跨 Isolate 发送的 `JSInterruptHandle` 实现即时取消。
> - `qjs` 的 `hook/build.dart` 默认优先校验并下载对应 GitHub Release SHA-256 预编译动态库，下载失败时自动回退至 `native_toolchain_c` 本地编译 QuickJS-NG C 源码。**生产环境 CI（GitHub Actions）需保留外网访问或缓存 `.dart_tool/hooks_runner/`，且 Windows/Android 工具链均已验证可无缝回退编译**。

---

## 6. 对 ADR-0003 的最终锁定建议

建议正式更新 [ADR-0003](file:///D:/READ/docs/adr/0003-storage-and-state.md)，将“嵌入式 JS 沙箱”条目的待评审状态锁定为以下技术方案：

1. **正式锁定依赖**：采用 **`qjs: ^0.2.3`**（`MIT` 协议，QuickJS-NG + Dart Native Assets），与主工程已选用的 `dio`、`cookie_jar`、`dio_cookie_manager`、`html`、`xpath_selector_html_parser`、`json_path`、`charset` 完全兼容，且符合 `GPL-3.0` 分发要求。
2. **明确拒绝旧版插件**：不采用 `flutter_qjs`（`ffi ^1.0.0` 依赖冲突且 Android Gradle 9 构建失败）与 `flutter_js`（KGP/JVM target 在 AGP 9.1.0 编译失败、双端引擎不一致且无 Isolate 支持）。
3. **沙箱配置基线**：生产 `QjsSandboxRuntime` 默认启用 `JSRuntimeConfig.hardened()`（`enableEval: false`、`es6Proxy: false`、`memoryLimit: 64 MiB`、`maxStackSize: 512 KiB`），单次脚本执行统一施加 `setDeadline(Duration(seconds: 5))` 并绑定 `CancellationToken -> JSInterruptHandle.requestInterrupt()`，确保单个恶意或失控书源的崩溃率为 **0**。
4. **Android NDK 工程配置**：在主工程 [android/app/build.gradle.kts](file:///D:/READ/android/app/build.gradle.kts) 保留本地已安装 NDK 版本自动回退逻辑，避免开发者本机缺失 Flutter 默认 NDK 版本时无法构建 APK。
