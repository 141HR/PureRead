# 参与贡献 PureRead（净读）

感谢你关注并愿意参与 **PureRead（净读）** 的开发与完善！在提交 Issue 或 Pull Request 之前，请先花几分钟阅读本指南。

---

## 1. 合规与开源底线（重要）

PureRead 采用 **MIT** 协议开源，是一款纯粹的本地阅读与解析工具。任何贡献必须严格遵守以下红线：

1. **严禁提交任何受版权保护的小说文本、盗版站点列表或内置书源合集**（测试夹具请使用自造虚构样本或开源/公版测试文本）。
2. **严禁提交任何密钥与签名敏感文件**（如 `android/key.properties`、`*.jks`、`*.keystore`、个人 API Token 等）。
3. **严禁引入第三方遥测、埋点统计或未经用户触发的后台联网行为**。
4. 引入新依赖时，请确认其开源协议与 **MIT** 兼容（优先 MIT / BSD / Apache-2.0，避免引入强传染性 Copyleft 依赖）。

---

## 2. 本地开发环境要求

| 组件 | 推荐版本 / 说明 |
| :--- | :--- |
| **Flutter SDK** | `3.47.7`（`stable` 通道） |
| **Dart SDK** | `^3.13.5`（随 Flutter 3.47.7 自带） |
| **Windows 桌面编译** | Visual Studio 2022 / 2026（勾选“使用 C++ 的桌面开发”与 Windows SDK） |
| **Android 编译** | JDK 21 + Android SDK 36（含构建 `qjs` 所需的 NDK） |
| **编辑器建议** | VS Code / Android Studio，仓库已内置 `.editorconfig` |

初始化工程并确认环境就绪：

```bash
flutter doctor
flutter pub get
```

---

## 3. 代码架构约定

项目采用清晰的五层单向依赖架构（详见 [docs/02-architecture.md](./docs/02-architecture.md)）：

```text
lib/
├── domain/          # 纯 Dart 领域实体、值对象、Repository 与 Service 抽象接口（不依赖 Flutter/IO）
├── engine/          # 核心排版引擎（reader_engine）与多驱动书源解析引擎（source_engine）
├── infrastructure/  # Drift SQLite、Dio 网络、QuickJS 沙箱、文件缓存、平台通道与双端 TTS 实现
├── application/     # Riverpod 状态控制器、业务编排、预加载调度与备份导出用例
└── presentation/    # 自适应双端 UI 壳层、书架、阅读器、搜索、书源工作台与设置页
```

修改 `lib/infrastructure/database/` 中的 Drift 表结构后，请记得重新生成代码：

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 4. 分支与提交规范

### 分支命名
- 功能开发：`feat/<short-topic>`
- 缺陷修复：`fix/<short-topic>`
- 重构优化：`refactor/<short-topic>`
- 文档或工程配置：`docs/<short-topic>` / `chore/<short-topic>`

### Commit Message 规范（Conventional Commits）
请使用 `<type>(<scope>): <subject>` 格式，例如：
- `feat(reader): add custom tap zone presets`
- `fix(legado): handle relative redirect url in toc parser`
- `docs(readme): update installation guide`
- `test(epub): cover malformed opf manifest fallback`

常用 `type`：`feat`、`fix`、`refactor`、`perf`、`docs`、`test`、`ci`、`chore`。

---

## 5. 提交 PR 前的必检清单

请确保在本地通过以下全部检查后再提交 Pull Request：

```bash
# 1. 代码格式化检查
dart format --output=none --set-exit-if-changed lib test tool

# 2. 严格静态分析（零 warning / zero info）
flutter analyze --fatal-infos --fatal-warnings

# 3. 运行全量自动化测试
flutter test
```

- 新增核心逻辑或修复 Bug 时，请补充对应的单元测试、Widget 测试或集成测试（放置于 `test/` 对应模块目录）。
- 涉及双端原生通道（`windows/runner/` 或 `android/app/src/main/kotlin/`）的改动，请在 PR 描述中注明实际编译与验证过的平台。
- 若改动影响用户可见行为或配置格式，请同步更新 [CHANGELOG.md](./CHANGELOG.md) 的 `[Unreleased]` 小节或相关文档。
