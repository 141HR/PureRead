# PureRead（净读）数据库 Schema 与迁移备份规范（Phase 2）

> **文档状态**：Draft（待评审）  
> **存储引擎**：SQLite 3（通过 Drift 管理强类型表与 Migration）  
> **关联文档**：[系统架构设计](./02-architecture.md) | [ADR-0003](./adr/0003-storage-and-state.md)

---

## 1. 设计原则与 ER 关系总览

1. **轻量化关系库**：数据库仅存结构化元数据（书架、章节目录索引、精确锚点进度、书源、净化规则、主题与配置）；**本地 TXT 正文按字节偏移按需读，在线正文原始文本存入文件缓存区**，避免数据库膨胀。
2. **统一章节模型**：`chapters` 表通过条件字段统一服务本地 TXT（`byte_start` / `byte_end`）、本地 EPUB（`epub_href`）与在线书源（`url` / `is_cached` / `cache_key`）。
3. **预留演进字段**：虽 `v1.0` 暂不做双端同步，所有核心表均规范维护 `updated_at`（UTC 毫秒时间戳），`reading_progress` 预留 `char_offset` 与 `device_id`，为未来扩展提供零重构基础。

```text
book_groups (1) ──────< (N) books (1) ──────< (N) chapters
                              │
                              ├────── (1) reading_progress
                              │
                              └──────< (N) bookmarks

book_sources (1) ─────< (N) books (逻辑关联 source_id，允许本地书为 NULL)

replace_rules   (独立规则表，通过 scope_type + scope_target_id 逻辑关联全局/书源/单书)
reader_themes   (独立主题与排版预设表)
app_settings    (独立键值对配置表)
```

---

## 2. 核心数据表详细设计（9 张表）

> 约定：所有时间字段均使用 `INTEGER` 存储 **UTC 毫秒时间戳（Unix Epoch ms）**；所有布尔值在 SQLite 中由 Drift 映射为 `INTEGER (0/1)`；主键优先使用业务无关的确定性 UUID / ULID 字符串或自增整型。

### 2.1 `book_groups`（书架分组表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `PRIMARY KEY` | 分组 ID（内置默认分组如 `default`） |
| `name` | `TEXT` | `NOT NULL` | 分组名称（如“追更中”“本地完本”） |
| `sort_order` | `INTEGER` | `NOT NULL DEFAULT 0` | 排序权重 |
| `created_at` | `INTEGER` | `NOT NULL` | 创建时间 |
| `updated_at` | `INTEGER` | `NOT NULL` | 最后修改时间 |

### 2.2 `books`（书籍主表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `PRIMARY KEY` | 书籍唯一 ID（本地书可基于文件路径/Hash，在线书可基于 `source_id + origin_book_url` 摘要） |
| `source_id` | `TEXT` | `NULLABLE` | 关联的 `book_sources.id`（本地 TXT / EPUB 时为 `NULL`） |
| `provider_type` | `TEXT` | `NOT NULL` | 驱动类型枚举：`local_txt` / `local_epub` / `js_plugin` / `legado` |
| `origin_book_url` | `TEXT` | `NULLABLE` | 在线书籍详情页 URL |
| `toc_url` | `TEXT` | `NULLABLE` | 在线书籍独立目录页 URL |
| `title` | `TEXT` | `NOT NULL` | 书名 |
| `author` | `TEXT` | `NOT NULL DEFAULT ''` | 作者 |
| `cover_path` | `TEXT` | `NULLABLE` | 本地封面图相对路径或远程封面 URL |
| `intro` | `TEXT` | `NOT NULL DEFAULT ''` | 简介 |
| `local_file_path` | `TEXT` | `NULLABLE` | 本地 TXT / EPUB 文件绝对路径 |
| `file_encoding` | `TEXT` | `NULLABLE` | 本地 TXT 探测编码（如 `utf-8`、`gb18030`、`utf-16le`） |
| `file_size_bytes` | `INTEGER` | `NULLABLE` | 本地文件字节大小（用于检测文件是否被外部修改） |
| `file_hash` | `TEXT` | `NULLABLE` | 本地文件快速指纹（头尾采样+大小摘要，避免大文件全量算 MD5 卡顿） |
| `group_id` | `TEXT` | `NULLABLE REFERENCES book_groups(id) ON DELETE SET NULL` | 所属书架分组 |
| `is_pinned` | `INTEGER` | `NOT NULL DEFAULT 0` | 是否书架置顶（0/1） |
| `total_chapters` | `INTEGER` | `NOT NULL DEFAULT 0` | 当前总章节数 |
| `unread_count` | `INTEGER` | `NOT NULL DEFAULT 0` | 追更未读新增章数 |
| `last_chapter_title` | `TEXT` | `NOT NULL DEFAULT ''` | 最新章名快照（用于书架展示） |
| `last_read_at` | `INTEGER` | `NULLABLE` | 最近一次阅读时间戳（用于默认“最近阅读”排序） |
| `latest_chapter_at` | `INTEGER` | `NULLABLE` | 最近检测到新章节的时间戳 |
| `created_at` | `INTEGER` | `NOT NULL` | 入架时间 |
| `updated_at` | `INTEGER` | `NOT NULL` | 元数据更新时间 |

### 2.3 `chapters`（统一章节索引表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | `INTEGER` | `PRIMARY KEY AUTOINCREMENT` | 章节行 ID |
| `book_id` | `TEXT` | `NOT NULL REFERENCES books(id) ON DELETE CASCADE` | 所属书籍 ID |
| `chapter_index` | `INTEGER` | `NOT NULL` | 章节序号（从 `0` 开始连续递增） |
| `title` | `TEXT` | `NOT NULL` | 章节标题 |
| `url` | `TEXT` | `NULLABLE` | 在线章节 URL（本地书为 `NULL`） |
| `byte_start` | `INTEGER` | `NULLABLE` | 本地 TXT 起始字节偏移（闭区间） |
| `byte_end` | `INTEGER` | `NULLABLE` | 本地 TXT 结束字节偏移（开区间） |
| `epub_href` | `TEXT` | `NULLABLE` | `v0.3` EPUB 内部 XHTML 资源路径（含可选锚点 `#id`） |
| `is_cached` | `INTEGER` | `NOT NULL DEFAULT 0` | 在线章节正文是否已缓存到本地文件 |
| `cache_key` | `TEXT` | `NULLABLE` | 缓存文件相对键（如 `{bookId}/{chapterIndex}.txt`） |
| `word_count` | `INTEGER` | `NOT NULL DEFAULT 0` | 章节字数（本地建索引或首次拉取后回填） |
| `updated_at` | `INTEGER` | `NOT NULL` | 记录更新时间 |

- **唯一约束**：`UNIQUE(book_id, chapter_index)`

### 2.4 `reading_progress`（阅读进度表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `book_id` | `TEXT` | `PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE` | 关联书籍 ID |
| `chapter_index` | `INTEGER` | `NOT NULL DEFAULT 0` | 当前所在章节索引 |
| `char_offset` | `INTEGER` | `NOT NULL DEFAULT 0` | **当前页首字在章节净化后正文中的字符偏移（核心精确锚点）** |
| `chapter_title_snapshot` | `TEXT` | `NOT NULL DEFAULT ''` | 章节名快照（换源匹配章节时作相似度参照） |
| `progress_percent` | `REAL` | `NOT NULL DEFAULT 0.0` | 全书进度百分比（`0.0 ~ 1.0`） |
| `reading_duration_sec` | `INTEGER` | `NOT NULL DEFAULT 0` | 累计阅读时长（秒） |
| `updated_at` | `INTEGER` | `NOT NULL` | 进度落盘时间 |
| `device_id` | `TEXT` | `NOT NULL DEFAULT ''` | 本机设备标识（`v1.0+` 扩展预留） |

### 2.5 `bookmarks`（书签与批注表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `PRIMARY KEY` | 书签 ID |
| `book_id` | `TEXT` | `NOT NULL REFERENCES books(id) ON DELETE CASCADE` | 所属书籍 ID |
| `chapter_index` | `INTEGER` | `NOT NULL` | 章节索引 |
| `char_offset` | `INTEGER` | `NOT NULL` | 精确字符偏移 |
| `excerpt` | `TEXT` | `NOT NULL` | 摘录片段预览（通常前 80 字） |
| `note` | `TEXT` | `NOT NULL DEFAULT ''` | 可选用户批注 |
| `created_at` | `INTEGER` | `NOT NULL` | 创建时间 |

### 2.6 `book_sources`（统一书源表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `PRIMARY KEY` | 书源 ID（通常基于规范化 `base_url` 或用户导出 ID） |
| `name` | `TEXT` | `NOT NULL` | 书源名称 |
| `group_name` | `TEXT` | `NOT NULL DEFAULT '默认'` | 书源分组标签 |
| `engine_type` | `TEXT` | `NOT NULL` | 引擎枚举：`js_plugin` / `legado` |
| `base_url` | `TEXT` | `NOT NULL` | 书源站点根地址 |
| `raw_definition` | `TEXT` | `NOT NULL` | 原始规则文本（JS 插件源代码或 Legado JSON 字符串） |
| `enabled` | `INTEGER` | `NOT NULL DEFAULT 1` | 是否启用 |
| `weight` | `INTEGER` | `NOT NULL DEFAULT 0` | 聚合搜索与换源优先级权重 |
| `rate_limit_ms` | `INTEGER` | `NOT NULL DEFAULT 500` | 同域名请求最小间隔（毫秒） |
| `last_check_status` | `TEXT` | `NOT NULL DEFAULT 'unknown'` | 最近状态：`unknown` / `ok` / `error` / `unsupported` |
| `last_error_summary` | `TEXT` | `NULLABLE` | 最近错误摘要（供书源列表与调试参考） |
| `created_at` | `INTEGER` | `NOT NULL` | 导入时间 |
| `updated_at` | `INTEGER` | `NOT NULL` | 更新时间 |

### 2.7 `replace_rules`（正文净化规则表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `PRIMARY KEY` | 规则 ID |
| `name` | `TEXT` | `NOT NULL` | 规则名称（如“去除章节末尾求月票广告”） |
| `group_name` | `TEXT` | `NOT NULL DEFAULT '通用'` | 规则分组 |
| `pattern` | `TEXT` | `NOT NULL` | 匹配表达式（文本或正则） |
| `replacement` | `TEXT` | `NOT NULL DEFAULT ''` | 替换结果字符串 |
| `is_regex` | `INTEGER` | `NOT NULL DEFAULT 1` | 是否为正则表达式 |
| `scope_type` | `TEXT` | `NOT NULL DEFAULT 'global'` | 作用域：`global`（全局）/ `source`（指定书源）/ `book`（指定书籍） |
| `scope_target_id` | `TEXT` | `NULLABLE` | 当 `scope_type` 为 `source` 或 `book` 时的目标 ID |
| `enabled` | `INTEGER` | `NOT NULL DEFAULT 1` | 是否启用 |
| `sort_order` | `INTEGER` | `NOT NULL DEFAULT 0` | 执行顺序 |
| `updated_at` | `INTEGER` | `NOT NULL` | 更新时间 |

### 2.8 `reader_themes`（阅读主题与排版预设表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `PRIMARY KEY` | 主题 ID |
| `name` | `TEXT` | `NOT NULL` | 主题名称（如“羊皮纸护眼”“OLED 纯黑”） |
| `is_builtin` | `INTEGER` | `NOT NULL DEFAULT 0` | 是否内置预设 |
| `is_dark` | `INTEGER` | `NOT NULL DEFAULT 0` | 是否深色模式 |
| `bg_color` | `INTEGER` | `NOT NULL` | 背景 ARGB 颜色值 |
| `text_color` | `INTEGER` | `NOT NULL` | 正文 ARGB 颜色值 |
| `secondary_text_color` | `INTEGER` | `NOT NULL` | 页眉页脚辅助文字颜色 |
| `bg_texture_path` | `TEXT` | `NULLABLE` | 可选背景纸纹图片资源路径 |
| `font_family` | `TEXT` | `NOT NULL DEFAULT 'system'` | 字体族名称 |
| `font_path` | `TEXT` | `NULLABLE` | 自定义 `.ttf/.otf` 字体本地相对路径 |
| `font_size` | `REAL` | `NOT NULL DEFAULT 18.0` | 字号（dp/pt） |
| `font_weight` | `INTEGER` | `NOT NULL DEFAULT 400` | 字重（`300 ~ 700`） |
| `line_height` | `REAL` | `NOT NULL DEFAULT 1.65` | 行高倍数 |
| `paragraph_spacing` | `REAL` | `NOT NULL DEFAULT 12.0` | 段间距 |
| `letter_spacing` | `REAL` | `NOT NULL DEFAULT 0.2` | 字间距 |
| `paragraph_indent_chars` | `INTEGER` | `NOT NULL DEFAULT 2` | 段首缩进全角字符数 |
| `margin_horizontal` | `REAL` | `NOT NULL DEFAULT 20.0` | 水平页边距 |
| `margin_vertical` | `REAL` | `NOT NULL DEFAULT 24.0` | 上下页边距 |
| `column_mode` | `TEXT` | `NOT NULL DEFAULT 'auto'` | 栏数策略：`auto`（窄屏单栏/宽屏双栏）/ `single` / `double` |
| `max_content_width` | `REAL` | `NOT NULL DEFAULT 760.0` | 宽屏单栏模式下最大居中版心宽度 |
| `page_turn_mode` | `TEXT` | `NOT NULL DEFAULT 'cover'` | 翻页动效：`none` / `slide` / `cover` / `scroll` / `simulation` |
| `enable_punctuation_hanging` | `INTEGER` | `NOT NULL DEFAULT 1` | 是否开启标点避头尾禁则 |
| `enable_cjk_spacing` | `INTEGER` | `NOT NULL DEFAULT 1` | 是否开启中英数字混排微距 |
| `updated_at` | `INTEGER` | `NOT NULL` | 更新时间 |

### 2.9 `app_settings`（应用全局配置表）

| 字段名 | SQLite 类型 | 约束 | 说明 |
| :--- | :--- | :--- | :--- |
| `key` | `TEXT` | `PRIMARY KEY` | 配置键（如 `active_theme_id`、`volume_key_turn`、`boss_key_shortcut`、`schema_backup_keep`） |
| `value` | `TEXT` | `NOT NULL` | JSON 或字符串序列化值 |
| `updated_at` | `INTEGER` | `NOT NULL` | 更新时间 |

---

## 3. 索引清单与 SQLite 运行时调优

### 3.1 必备索引
| 索引名 | 表名与列 | 服务场景 |
| :--- | :--- | :--- |
| `idx_books_shelf_sort` | `books(group_id, is_pinned DESC, last_read_at DESC)` | 书架分组过滤与默认置顶/最近阅读排序 |
| `idx_books_source_url` | `books(source_id, origin_book_url)` | 搜索结果入架查重与一键换源检查 |
| `idx_chapters_book_index` | `chapters(book_id, chapter_index)`（`UNIQUE`） | 开书秒级定位章节与相邻章节翻页查询 |
| `idx_bookmarks_book_pos` | `bookmarks(book_id, chapter_index, char_offset)` | 书签列表按阅读顺序展示 |
| `idx_sources_enabled_weight` | `book_sources(enabled, weight DESC)` | 并发聚合搜索快速捞取启用书源 |
| `idx_replace_rules_active` | `replace_rules(enabled, scope_type, scope_target_id, sort_order)` | `ContentSanitizer` 快速组装当前章节净化链 |

### 3.2 SQLite PRAGMA 启动配置
在 Drift `beforeOpen` 钩子中统一执行：
```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;
```
开启 **WAL（Write-Ahead Logging）** 后，阅读页高频保存 `reading_progress` 与后台预加载回填 `chapters.is_cached` 可并发读写不互相阻塞。

---

## 4. 安全迁移与本地整库备份包（`.pureread.zip`）规范

### 4.1 数据库升级自动备份机制
1. **升级前快照**：每次应用启动打开数据库时，Drift 在 `beforeOpen` 检查 `details.hadUpgrade`（即 `oldVersion < newVersion`）。在执行任何 `ALTER TABLE` 迁移 SQL **之前**，自动将现有 `pureread.db`（及 `-wal`/`-shm` 合并后快照）拷贝至 `db/backups/pureread_v{oldVersion}_{timestamp}.db`。
2. **滚动保留**：`db/backups/` 最多保留最近 **3 份** 历史版本备份，自动清理更早文件。
3. **失败保护**：所有 Schema Migration 包裹在事务中执行；若发生不可预期失败，向上层抛出 `DatabaseFailure` 并保留升级前原库快照路径以供一键回滚恢复。

### 4.2 `.pureread.zip` 本地整库备份包结构
为支持换机迁移或重装恢复，应用提供完整且可读性强的标准压缩包格式：

```text
pureread_backup_20261124_1910.pureread.zip
├── manifest.json            # formatVersion, appVersion, schemaVersion, exportedAt, counts
├── data/
│   ├── book_groups.json
│   ├── books.json
│   ├── reading_progress.json
│   ├── bookmarks.json
│   ├── book_sources.json
│   ├── replace_rules.json
│   ├── reader_themes.json
│   └── app_settings.json
└── fonts/                   # (可选) 用户自定义导入的 .ttf / .otf 字体文件
```

- **明确不包含内容（并在导出界面显著提示）**：
  - 在线章节正文文本缓存（体积大且可通过书源重新拉取）；
  - 本地超大 TXT / EPUB 原始文件本身（避免动辄几百 MB 的压缩包；导入恢复后若检测到原本地路径失效，在书架条目提示用户重新关联本地源文件，保留原阅读进度 `charOffset` 与书签不丢失）。
- **导入校验流程**：先解析 `manifest.json` 校验 `formatVersion` 与完整性；导入采用**预览合并或覆盖恢复**确认弹窗，执行前同样先自动生成当前库备份再事务导入。
