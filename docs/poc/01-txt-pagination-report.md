# PoC-1 技术验证报告：30MB 大 TXT 流式索引与根 Isolate 增量排版引擎

> **验证日期**：2026-11-24  
> **验证环境**：Windows 11 / Flutter `3.47.7` (`stable`) / Dart `3.13.5` / `charset: ^2.0.1`  
> **PoC 工程路径**：[`poc/poc_txt_pagination/`](../../poc/poc_txt_pagination/)  
> **关联文档**：[项目章程](../00-charter.md) | [PRD v1.0](../01-prd.md) | [系统架构设计 §4.1–§4.2](../02-architecture.md)

---

## 1. 执行结论（Executive Summary）

本次 Phase 0 PoC-1 在独立 Flutter 工程 `poc/poc_txt_pagination/` 中完成了 **30 MiB 大 TXT（UTF-8 与 GB18030/GBK 双变体、1,500 章）后台 Isolate 流式探测与建索引**、**`RandomAccessFile` 单章分片随机读取**、以及 **主线程（Root Isolate）`TextPainter` 增量中文排版分页器** 的全链路实现与自动化压测。

| NFR / 验证指标 | 目标阈值 | PoC 实测结果 | 结论 |
| :--- | :--- | :--- | :---: |
| **30 MiB UTF-8 探测 + 流式分章扫描** | `< 2.0s` (`2,000 ms`) | **`273.38 ms`**（探测 `5.40 ms` + 扫描 `261.54 ms`，含 `Isolate.run` 开销） | **通过（~7.3x 余量）** |
| **30 MiB GB18030 探测 + 流式分章扫描** | `< 2.0s` (`2,000 ms`) | **`236.64 ms`**（探测 `3.70 ms` + 扫描 `232.11 ms`，含 `Isolate.run` 开销） | **通过（~8.4x 余量）** |
| **单章 `RandomAccessFile` 字节切片读取** | `< 200 ms` | UTF-8 **`1.38–4.88 ms`** / GB18030 **`3.29–6.47 ms`**（裸读 `0.04–0.27 ms`） | **通过（> 30x 余量）** |
| **首屏增量排版（锚点 + 2~3 页）** | `< 8 ms` | 首次冷启动 **`6.94 ms`** / 千字高多态冷启动 **`1.99 ms`** / 热缓存 **`0.13–0.73 ms`** | **通过** |
| **整章排版（~5,000 CJK 字符）** | `< 50 ms` | 冷缓存 **`2.33–8.94 ms`** / 字体放大+双栏重排 **`2.73 ms`** / 热缓存 **`0.50–1.35 ms`** | **通过（> 5x 余量）** |
| **分页字数守恒 & `charOffset` 往返精度** | 100% 守恒、0 字误差 | 全部场景 `PageSlice` 拼接与原章 100% 一致；缩放往返 0 字符漂移 | **通过** |
| **中文排版避头尾禁则 & 中英混排微距** | 0 违例 | 覆盖 `，。！？、》」《「（）` 及连续标点、C/A 混排边界，100% 通过 | **通过** |
| **静态检查与自动化测试** | 0 Issue / 全绿 | `flutter analyze` `0` issues；`flutter test` **`12/12`** 全部通过 | **通过** |

---

## 2. 30MB 大 TXT 流式编码探测与 Isolate 分章索引

### 2.1 核心设计与工程发现

代码实现位于 [`lib/txt/`](../../poc/poc_txt_pagination/lib/txt/)：
- **流式编码探测（[`txt_encoding.dart`](../../poc/poc_txt_pagination/lib/txt/txt_encoding.dart)）**：
  - 优先识别 BOM：`UTF-8-BOM`（`EF BB BF`）、`UTF-16LE`（`FF FE`）、`UTF-16BE`（`FE FF`）。
  - 无 BOM 时以 `64 KiB` 分块流式读入（最多采样 `256 KiB` 或集齐足够非 ASCII 字节后提前收敛），内置**跨分块有状态机**并行校验严格 UTF-8（RFC 3629，含过长编码与代理区拦截）与 GB18030/GBK 字节序列，避免多字节字符恰巧被 chunk 边界劈开导致的误判。
- **流式正则章节扫描器（[`txt_chapter_scanner.dart`](../../poc/poc_txt_pagination/lib/txt/txt_chapter_scanner.dart)）**：
  - 在 `Isolate.run` 中以 `128 KiB` 固定缓冲流式扫描 `RandomAccessFile` 换行字节（UTF-8/GB18030 为 `0x0A`，UTF-16 按奇偶对齐检查 `0x0A 0x00` / `0x00 0x0A`），仅对长度 `<= 384` 字节的候选标题行解码并匹配章节正则，记录精确 `(chapterIndex, title, byteStart, byteEnd)`。
  - 首章前若有有效序言自动归入 `序言`；无章节标识的纯文本自动按固定字节边界安全回退切分（对齐至换行与多字节字符边界），保证 100% 字节无损还原。

### 2.2 实测数据（`txt_isolate_benchmark_test.dart`）

合成语料由 [`synthetic_novel_generator.dart`](../../poc/poc_txt_pagination/lib/txt/synthetic_novel_generator.dart) 按 `256 KiB` 缓冲流式生成（`1,500` 章、含中英数字混排、全套标点 `，。！？、》」《「（）` 及正文内含 `第X天/第X次` 干扰句），测试结束后在 `tearDownAll` 中自动清理 `.tmp/`：

| 语料变体 | 文件体积 | 生成耗时 | 识别编码 | 命中章节数 | 编码探测耗时 | 流式扫描耗时 | Isolate 端到端耗时 | RSS 增量 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **UTF-8 无 BOM** | `30.00 MiB` | `139.8 ms` | `UTF-8` | `1,501`（含序言，0 误报） | `5.40 ms` | `261.54 ms` | **`273.38 ms`** | `11.54 MiB` |
| **GB18030 / GBK** | `30.00 MiB` | `112.9 ms` | `GB18030` | `1,501`（含序言，0 误报） | `3.70 ms` | `232.11 ms` | **`236.64 ms`** | `0.00–7.15 MiB`* |

> \*注：GB18030 扫描首次冷分配 64K `Uint16List` 查表与章节列表时实测 `rssDelta` 为 `6.05–7.15 MiB`，复用内存页后为 `0.00 MiB`，均远低于全文件读入内存（`30+ MiB`）的开销。

**`RandomAccessFile` 单章切片随机读取延迟（含 `Isolate.run` 派发与解码）**：

| 语料 | 章节样本 | 字节切片大小 | `RAF` 定位读取耗时 | 解码耗时 | Isolate 总耗时 |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **UTF-8** | `ch#1 序章 青云初雪` | `20,813 B` | `0.268 ms` | `2.622 ms` | **`4.875 ms`** |
| **UTF-8** | `ch#750 第749章 山海旧约（749）` | `20,811 B` | `0.050 ms` | `0.764 ms` | **`1.497 ms`** |
| **UTF-8** | `ch#1500 尾声 山海旧约（2026终章）` | `22,214 B` | `0.071 ms` | `0.846 ms` | **`1.383 ms`** |
| **GB18030** | `ch#1 序章 青云初雪` | `20,955 B` | `0.050 ms` | `5.805 ms` | **`6.448 ms`** |
| **GB18030** | `ch#750 第749章 山海旧约（749）` | `20,944 B` | `0.051 ms` | `5.893 ms` | **`6.471 ms`** |
| **GB18030** | `ch#1500 尾声 山海旧约（2026终章）` | `21,929 B` | `0.042 ms` | `2.745 ms` | **`3.288 ms`** |

> 另已验证 `UTF-8-BOM`、`UTF-16LE BOM`、`UTF-16BE BOM`、`64 B` 极端分块跨行切分、前 `4 KB+` 纯 ASCII 延迟出现 GBK 中文、以及无章回纯文本兜底切分的 100% 文本还原。

### 2.3 重要发现：`package:charset 2.0.1` 源码审计避坑

阅读 `charset-2.0.1` 源码发现 4 个生产环境必须规避的隐患：
1. **GB18030 映射实际为 GBK**：`Charset.getByName('gb18030')` 直接返回 `gbk`（仅含 23,940 个双字节 GBK 映射，不包含 4 字节 GB18030 序列）。PoC 在 `TxtCodecHelper` 中补充了 4 字节 GB18030 辅助平面（`U+10000..U+10FFFF`）算法解码。
2. **`GbkDecoder` 分块与 `Map` 查找开销**：原生 `gbk` 解码器每个字符走 `Map<int, int>` 哈希查表，且 `_GbkStreamDecoder` 跨 chunk 时存在 `codeUnits[0]` 索引缺陷。PoC 在 Isolate 内一次性批量解码生成 `Uint16List(65536)` 扁平查表，将 30 MiB GB18030 扫描压低至 `~232 ms`。
3. **`Charset.detect()` 行为不可靠**：`Charset.detect` 默认只探测 `ascii` 与 `gbk` 且将 UTF-16BE BOM 误判返回 `utf8`；生产环境必须使用自研 BOM + 状态机流式探测器。
4. **`Utf16Decoder` 对无 BOM 切片默认按 BE 解码**：从文件中间用 `RandomAccessFile` 读出的 UTF-16LE 章节切片不含 BOM，直接调用 `utf16.decode()` 会按 UTF-16BE 解码成乱码！必须依据文件探测结果显式调用 `decodeUtf16Le(..., stripBom: false)` 或 `decodeUtf16Be(..., stripBom: false)`。

---

## 3. 根 Isolate `TextPainter` 增量排版引擎验证

### 3.1 架构与排版实现

代码实现位于 [`lib/pagination/`](../../poc/poc_txt_pagination/lib/pagination/)：
- **严格遵守 `dart:ui` 根 Isolate 约束**：测试已实证在 `Isolate.run` 内调用 `TextPainter.layout()` 会立即抛出异常。分页器 [`IncrementalTextPaginator`](../../poc/poc_txt_pagination/lib/pagination/incremental_paginator.dart) 完全运行在 Root Isolate。
- **零字符串篡改与 100% 字符守恒**：绝不在 `sanitizedText` 中插入全角缩进空格或发丝空格；段落首行缩进通过 `LayoutLine.dx` 实现，中英混排微距（`0.2 * fontSize`，仅作用于 CJK 表意文字与 ASCII 字母数字边界，不对 `《》「」。` 等自带留白的全角标点加宽）通过 `TextSpan` 局部 `letterSpacing` 承载，段尾 `\r\n` 归属该段末行。由此保证任意 `PageSlice` 与 `LayoutLine` 区间严格闭开连续 `[start, end)`，拼接即 100% 还原原始文本。
- **避头尾禁则（[`chinese_typesetting.dart`](../../poc/poc_txt_pagination/lib/pagination/chinese_typesetting.dart)）**：覆盖全/半角避头标点（`，。！？、》」）】；：…—～·’”` 等）与避尾标点（`《「（【‘“` 等），断行越界时回溯前移并保护 UTF-16 代理对与完整 ASCII 单词；针对全标点极端输入设安全下限防止死循环。
- **混合首屏 + 时间片增量策略**：
  - 当 `priorityCharOffset <= 1200` 时直接从章首排版至锚点后 `2~3` 页，零边界漂移；当 `priorityCharOffset > 1200` 时，先从锚点前约 `650` 字符的段首起排局部窗口立即产出首屏（`anchor + 2~3 页`），随后以 `<= 4 ms` 时间片增量补全整章规范页序列。
  - **关键加速优化（`TextPainter` 实测均一字宽探针）**：对当前字号与字体使用 `TextPainter` 一次性探测 10 个结构迥异的代表汉字（`一国鑫田口日月木水火`）；若宽差 `<= 0.02px`（覆盖微软雅黑、苹方、思源黑体/宋体、霞鹜文楷与 Ahem），`U+4E00..U+9FFF` 直接 O(1) 复用实测宽度，标点与 ASCII 仍经由批量 `warmUpSlice` 与整词 `tokenWidth` 调用 `TextPainter` 精确测量（保留拉丁连字/字距微调）。
- **单栏与桌面双栏等价复用**：使用 `PaginationConfig.fromViewport` 计算逻辑页宽 `(contentWidth - columnGap) / 2`，输出统一线性页序列 `[P0, P1, ...]`，双栏第 `k` 屏直接配对绘制 `(P_{2k}, P_{2k+1})`（末页奇数时右栏自然留白），由 [`ReaderPagePainter`](../../poc/poc_txt_pagination/lib/pagination/page_painter.dart) 渲染。

### 3.2 实测性能与精度数据（`pagination_benchmark_test.dart`）

| 测试场景 | 章节长度 | 锚点偏移 | 总页数 | 首屏耗时 (`< 8ms`) | 整章计算耗时 (`< 50ms`) | 时间片数 / 最大单片 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **冷缓存首次打开**（含 Skia/TextPainter 首帧初始化） | `5,020` chars | `0` | `14` | **`6.94 ms`**（3 页） | **`8.94 ms`** | `2` / `6.94 ms` |
| **高词表复杂度冷缓存**（~1,200 个不重复汉字） | `5,003` chars | `0` | `14` | **`1.99 ms`**（3 页） | **`2.33 ms`** | `2` / `1.99 ms` |
| **热缓存章首打开**（1-col `400x760`, 18pt） | `5,002` chars | `0` | `14` | **`0.17 ms`**（3 页） | **`0.67 ms`** | `2` / `0.50 ms` |
| **热缓存章中锚点恢复**（局部锚点窗口） | `5,002` chars | `1,800` | `14` | **`0.73 ms`**（4 页） | **`1.35 ms`** | `2` / `0.73 ms` |
| **热缓存章尾锚点恢复**（局部锚点窗口） | `5,002` chars | `4,200` | `14` | **`0.38 ms`**（4 页） | **`0.80 ms`** | `2` / `0.42 ms` |
| **字号+双栏重排**（18pt 单栏 → 22pt 双栏 `1100x760`） | `5,002` chars | `1,800` | `14` | **`1.86 ms`** | **`2.73 ms`** | `2` / `1.86 ms` |
| **万五字大章深处跳转压测** | `15,006` chars | `11,200` | `41` | **`0.13 ms`**（4 页） | **`1.18 ms`** | `2` / `1.05 ms` |

**排版与交互正确性实测**：
- **避头尾禁则**：在 `width = 220..380`、`fontSize = 16..22`（含连续组合 `》」），。！？、` 与 `《「（`）交叉矩阵测试下违例数为 `0`；全标点病态输入不死循环且 100% 守恒。
- **`charOffset` 往返定位**：手机单栏 (`390x760`, 18pt) → 桌面双栏 (`1100x760`, 22pt) → 超窄单栏 (`320x620`, 15pt) → 还原手机单栏，每步目标页（及双栏 `(P_{2k}, P_{2k+1})`）均严格包含原 `charOffset`，返回原配置后精确命中原 `pageIndex` 与 `startCharOffset`（**0 字符偏移误差**）。
- **Widget 交互测试**：[`widget_test.dart`](../../poc/poc_txt_pagination/test/widget_test.dart) 验证了 `ReaderPocScreen` 在 `CustomPaint` 下的单/双栏切换、字号调整与翻页全通过。

---

## 4. 生产落地建议（Phase 4 接入 `lib/engine/`）

1. **采用“Worker Isolate 常驻池 + 扁平 GBK 查表 + 自研状态机解码”落地 `local_txt/`**：
   - 将 `TxtEncodingDetector`、`TxtChapterScanner` 与 `TxtCodecHelper` 迁入 `lib/engine/source_engine/local_txt/`，切勿直接调用 `package:charset` 的 `Charset.detect` 与无参 `utf16.decode`。
   - 保持单个后台 Worker Isolate 常驻，避免每次翻章重复创建 Isolate 与重建 64K GBK 查表；30 MiB 建索引可稳定控制在 `~200–275 ms`、单章读取 `< 5 ms`。
2. **注意真机字体与 `flutter test` (`Ahem`) 差异，保留 4ms 时间片与局部窗口**：
   - 本次无头单元测试使用 Flutter 测试字体 `Ahem`；在 Windows/Android 真机加载微软雅黑/思源字体/用户自定义 `.ttf/.otf` 时，Skia 首次冷字形光栅化耗时高于 `Ahem`（尤其首次冷开书第 1 帧）。
   - 建议在 `lib/engine/reader_engine/` 中保留 PoC 的三项关键机制：**（1）10 汉字均一字宽 `TextPainter` 实测探针**；**（2）深偏移（`charOffset > 1200`）先排局部窗口立即出首屏**；**（3）单帧 `<= 4 ms` 时间片配合 `SchedulerBinding.scheduleFrameCallback` 补全整章并写入三章缓存环**，同时在窗口/字号连续拖拽时对重排增加 `~32–50 ms` 防抖并仅实时重算当前可视页。
3. **双栏与连续缩放的 `charOffset` 状态管理建议**：
   - 拖拽桌面窗口宽度或连续调节字号期间，应**保持会话级基准 `anchorOffset` 不被中间态页首覆盖**（例如在 `A -> B -> C -> A` 往返缩放时不因中间落到 `P_{2k+1}` 或上移几行而永久改变锚点），仅在用户主动翻页或滚动后更新 `ReadingAnchor.charOffset`。
4. **生产级字体补充细节**：
   - 针对部分艺术/手写类非等宽中文字体（`maxW - minW > 0.02`），PoC 已内置自动回退至按段落批量 `getOffsetForCaret` 测量机制，可无缝兼容；上线前建议在 Windows（微软雅黑 / 霞鹜文楷）与 Android 真机上对 `ReaderPagePainter` 补充一次真实字体 DevTools Frame Profiling。
