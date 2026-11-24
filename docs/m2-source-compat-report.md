# Milestone 2 Source Compatibility & Real-Corpus Report

> **Date**: 2026-11-24  
> **Scope**: `SourceHttpClient`, `QjsSandboxRuntime`, `ChapterCacheStore`, `LegadoSelectorEngine` + `PureMd5`, `JsPluginProvider`, `LegadoCompatProvider` + `LegadoSourceParser`, `BookProviderFactory` + `SourceImportExportService`  
> **Probe Script**: [probe_real_sources.dart](file:///D:/READ/tool/probe_real_sources.dart)

---

## 1. Executive Summary

1. **Zero-crash real-corpus batch parsing**: `LegadoSourceParser.parseBatch` parsed all **2,693** real community Legado JSON sources (`4.07 MiB` + `12.86 MiB`, total `16.93 MiB`) across both user corpora with **0 parse errors** and **0 uncaught exceptions**.
2. **Isolate parsing throughput**:
   - `d:\QQ\Downloads\超级精品书源1031个10月10日.json` (`1,031` sources, `4.07 MiB`): **484 ms** sync / **425 ms** background `Isolate.run`.
   - `d:\QQ\Downloads\精品书源合集.json` (`1,662` sources, `12.86 MiB`): **1,316 ms** sync / **1,303 ms** background `Isolate.run`.
3. **Static headless compatibility**: **2,240 / 2,693 (83.2%)** total sources — and **2,240 / 2,565 (87.3%)** of text novel sources (`bookSourceType == 0`) — pass static headless compatibility checks (valid HTTP/HTTPS `baseUrl` after stripping `#fragment`, no `webView: true` / `startBrowserAwait`, and no Rhino `Packages.*` / `java.lang.*`).
4. **Bounded live smoke probe (20 diverse text sources, 6s HTTP timeout, 500ms rate limit, 18s per-source budget)**:
   - **4 / 20** completed the full 4-step chain `search -> getBookDetail -> getToc -> getChapterContent` (`Success`), including POST+GBK+`#🎃` fragment URL + `@put:`/`@get:` (`🎃笔迷读吧🎃`, 1,226 chapters, 1,177 chars prose in 2,847 ms) and embedded `<js>` `java.ajax` (`🖤㊣♛塔读文学一程1201`, 3,806 chars in 2,221 ms).
   - **3 / 20** succeeded in `search` (and `detail` / partial `toc`) before hitting upstream site rule drift (`话本小说`), `:regex` list syntax (`🎃黑岩小说🎃`), or multi-page TOC budget (`搜小说🎃`, 400 chapters fetched).
   - **13 / 20** cleanly mapped upstream outages, timeouts, selector drift, or `'webView': true` (`🎃当阅读网🎃`, rejected in 2 ms) into typed `AppFailure` instances (`NetworkFailure`, `SourceParseFailure`, `UnsupportedLegadoRuleFailure`, `TimeoutException`), with **0 process crashes**.

---

## 2. Real-Corpus Parsing & Compatibility Breakdown (2,693 Sources)

### 2.1 Classification Summary

| Metric | `超级精品书源1031个10月10日.json` | `精品书源合集.json` | Combined Total |
| :--- | :---: | :---: | :---: |
| File size | `4,264,852 B` (`4.07 MiB`) | `13,481,877 B` (`12.86 MiB`) | `17,746,729 B` (`16.93 MiB`) |
| Total entries | `1,031` | `1,662` | `2,693` |
| Parse errors / crashes | `0` | `0` | `0` |
| Sync batch parse (`parseBatchSync`) | `484 ms` | `1,316 ms` | `1,800 ms` |
| Background Isolate (`parseBatch`) | `425 ms` | `1,303 ms` | `1,728 ms` |
| Text sources (`bookSourceType == 0`) | `1,031` | `1,534` | `2,565` |
| Non-text sources (`bookSourceType != 0`) | `0` | `128` (`41` audio, `52` image, `35` file) | `128` |
| Malformed / non-HTTP `bookSourceUrl` | `0` | `28` | `28` |
| `#fragment`-tagged `bookSourceUrl` | `1,031` | `772` | `1,803` |
| Unsupported WebView (`webView: true` / `startBrowserAwait` / `java.webView`) | `30` | `33` | `63` |
| Unsupported Rhino (`Packages.*` / `java.lang.*` / `org.jsoup.*`) | `91` | `143` | `234` |
| **Statically supported (headless text)** | **`910` (`88.3%`)** | **`1,330` (`80.0%` / `86.7%` text)** | **`2,240` (`83.2%`)** |

### 2.2 Observed DSL & Transport Feature Distribution

| Feature | `1031` File (`n=1,031`) | `1662` File (`n=1,662`) | Combined (`n=2,693`) | Implementation Status |
| :--- | :---: | :---: | :---: | :--- |
| `searchUrl` present | `1,031` (`100.0%`) | `1,615` (`97.2%`) | `2,646` (`98.3%`) | Supported (GET/POST, JSON/lenient JS options, `<a,b>` page syntax, `<js>`/`@js:`) |
| `{{...}}` mustache templates | `1,017` (`98.6%`) | `1,592` (`95.8%`) | `2,609` (`96.9%`) | Supported (`{{key}}`, `{{page}}`, `{{source.*}}`, `{{cookie.*}}`, JS expressions) |
| `##pattern##rep` / `###` regex | `876` (`85.0%`) | `1,297` (`78.0%`) | `2,173` (`80.7%`) | Supported (all/first-only `###`, `$1` capture groups, malformed-regex safe) |
| Legado default chains (`class.`/`id.`/`tag.`/`text.`/`children`/`!`) | `850` (`82.4%`) | `1,180` (`71.0%`) | `2,030` (`75.4%`) | Supported (`!0:-1`, negative indices, `ownText`/`textNodes`/`html`/`attr`) |
| `#fragment`-tagged `bookSourceUrl` | `1,031` (`100.0%`) | `772` (`46.5%`) | `1,803` (`67.0%`) | Supported (raw preserved for `source.getKey()`, stripped for HTTP URI resolution) |
| Embedded `<js>` / `@js:` scripts | `498` (`48.3%`) | `987` (`59.4%`) | `1,485` (`55.1%`) | Supported in hardened QuickJS (`java.*`, `cookie.*`, `source.*`, async `java.ajax`) |
| Combinators (`&&` / `||` / `%%`) | `526` (`51.0%`) | `931` (`56.0%`) | `1,457` (`54.1%`) | Supported across element lists and field extractors |
| `POST` requests | `462` (`44.8%`) | `609` (`36.6%`) | `1,071` (`39.8%`) | Supported (form & JSON bodies, charset-aware GBK percent-encoding) |
| Custom `header` | `340` (`33.0%`) | `584` (`35.1%`) | `924` (`34.3%`) | Supported (JSON, lenient JS object, `Key: Val` lines, bare UA, `<js>`/`@js:`) |
| `nextContentUrl` pagination | `418` (`40.5%`) | `430` (`25.9%`) | `848` (`31.5%`) | Supported (bounded `maxContentPages = 25`, visited-URL loop guard) |
| `jsonPath` (`$.` / `@Json:`) | `114` (`11.1%`) | `539` (`32.4%`) | `653` (`24.2%`) | Supported (list unpacking + `{$.field}` inline template substitution) |
| `nextTocUrl` pagination | `295` (`28.6%`) | `350` (`21.1%`) | `645` (`24.0%`) | Supported (bounded `maxTocPages = 20`, linked & JS-array pagination) |
| `ruleContent.replaceRegex` | `312` (`30.3%`) | `317` (`19.1%`) | `629` (`23.4%`) | Supported (with `{{chapter.title}}` / `{{book.name}}` substitution) |
| `GBK` / `GB2312` / `GB18030` charset | `175` (`17.0%`) | `223` (`13.4%`) | `398` (`14.8%`) | Supported (`explicit -> Content-Type -> <meta> -> UTF-8 -> GB18030/GBK`, GBK form encoding) |
| `loginUrl` present | `81` (`7.9%`) | `298` (`17.9%`) | `379` (`14.1%`) | Stored in metadata; interactive login UI deferred |
| `XPath` (`@XPath:` / `//`) | `58` (`5.6%`) | `184` (`11.1%`) | `242` (`9.0%`) | Supported for both element lists and text/attribute extraction |
| `@css:` explicit CSS mode | `27` (`2.6%`) | `82` (`4.9%`) | `109` (`4.0%`) | Supported (including `:contains(...)` and `:eq(n)` extensions) |

---

## 3. Bounded Live Smoke Probe Results (20 Diverse Text Sources)

Configuration: `connectTimeout = 6s`, `receiveTimeout = 6s`, `defaultRateLimitMs = 500ms`, `jsTimeout = 4s`, per-source total cap `18s`, queries tried: `"凡人修仙传"` (fallback `"诡秘之主"`).

| # | Source Name | Bucket | Stage Reached | Outcome | HTTP | Latency | Search / TOC / Chars | Observed Detail / Failure Category |
| :-: | :--- | :--- | :---: | :--- | :---: | :---: | :---: | :--- |
| 1 | `开心文学网` | GET-CSS | `content` | **Success** | `200` | `3,140 ms` | `3` / `2,497` / `47` | Extracted book & ch1 (`新书《玄界之门》正式发布了哦！`) |
| 2 | `搜小说🎃` | POST-GBK | `toc` | `TimeoutException` | `200` | `18,004 ms` | `3` / `400` / `0` | Search & detail succeeded; fetched 400 chapters across paginated TOC before hitting 18s probe cap |
| 3 | `千凡小说` | POST-UTF8 | `search` | `SourceParseFailure` | — | `1,138 ms` | `0` / `0` / `0` | `ruleSearch.bookList` matched 0 elements (`class.jieshao`) |
| 4 | `猫眼看书🎃#3` | JSONPath | `search` | `SourceParseFailure` | — | `793 ms` | `0` / `0` / `0` | `ruleSearch.bookList` matched 0 elements (`$.data[*]`) |
| 5 | `手机小说` | XPath | `init` | `NetworkFailure` | `404` | `741 ms` | `0` / `0` / `0` | `HTTP 404 from https://m.shoujix.com/s.php` |
| 6 | `🖤㊣♛塔读文学一程1201` | JS-Embedded | `content` | **Success** | `200` | `2,221 ms` | `30` / `5` / `3,806` | `Book="都市凡人修仙传"`, `java.ajax` fetched chapter endpoint (`3,806` chars) |
| 7 | `英文小说（英文）` | Pagination | `search` | `SourceParseFailure` | — | `779 ms` | `0` / `0` / `0` | `ruleSearch.bookList` matched 0 elements (`class.list_1`) |
| 8 | `🎃76小说🎃` | FragmentURL | `init` | `NetworkTimeout` | — | `6,010 ms` | `0` / `0` / `0` | `receiveTimeout` at `6s` (`wap.qiliuwx.com`) |
| 9 | `笔趣阁` | Combinator | `search` | `SourceParseFailure` | — | `2,002 ms` | `0` / `0` / `0` | `ruleSearch.bookList` matched 0 elements (`class.grid@tag.tr`) |
| 10 | `博爱书屋` | GET-CSS | `init` | `NetworkFailure` | — | `216 ms` | `0` / `0` / `0` | Connection closed before full header (`www.bequgew.info`) |
| 11 | `🎃御书屋🎃#4` | POST-GBK | `init` | `NetworkTimeout` | — | `6,003 ms` | `0` / `0` / `0` | `connectTimeout` at `6s` (`m.wmp8.com`) |
| 12 | `🎃悠悠文学🎃` | POST-UTF8 | `init` | `NetworkTimeout` | — | `6,005 ms` | `0` / `0` / `0` | `receiveTimeout` at `6s` (`m.uuwx.la`) |
| 13 | `🎃黑岩小说🎃` | JSONPath | `toc` | `SourceParseFailure` | `200` | `1,484 ms` | `20` / `0` / `0` | Search succeeded (`20` items); `toc` uses unsupported `:regex` all-in-one regex list syntax |
| 14 | `🎃多多书院🎃#2` | XPath | `init` | `NetworkFailure` | `500` | `1,639 ms` | `0` / `0` / `0` | `HTTP 500` from `www.txtduo.net` |
| 15 | `🎃天域小说️🎃` | JS-Embedded | `init` | `NetworkTimeout` | — | `6,003 ms` | `0` / `0` / `0` | `receiveTimeout` at `6s` (`www.tycqzw.net`) |
| 16 | `话本小说` | Pagination | `toc` | `SourceParseFailure` | `200` | `1,060 ms` | `30` / `0` / `0` | Search succeeded (`30` items); `ruleToc.chapterList` matched 0 elements (`class.chapters@tag.div@tag.p`) |
| 17 | `🎃当阅读网🎃` | FragmentURL | `init` | `UnsupportedLegadoRuleFailure` | — | `2 ms` | `0` / `0` / `0` | `searchUrl` inline option `'webView': true` fast-rejected before network I/O |
| 18 | `刺猬猫备用™💯` | Combinator | `content` | **Success** | `200` | `1,721 ms` | `10` / `20` / `17` | Full pipeline executed (`Ch1="第一章 “我只是个普通的奥特战士”"`) |
| 19 | `zhsxs` | GET-CSS | `init` | `NetworkFailure` | `404` | `1,590 ms` | `0` / `0` / `0` | `HTTP 404` from `www.zhswx.com` |
| 20 | `🎃笔迷读吧🎃` | POST-GBK | `content` | **Success** | `200` | `2,847 ms` | `35` / `1,226` / `1,177` | `Book="凡人修仙之仙界篇 （凡人修仙传仙界篇）"`, `Ch1="第一百六十六章 速之法则"`, `1,177` chars prose |

### Live Probe Failure Category Breakdown

- **Full-Chain Success (`search -> detail -> toc -> content`)**: `4 / 20` (`20.0%`)
- **Upstream Transport / HTTP Outages (`NetworkFailure` + `NetworkTimeout`)**: `8 / 20` (`40.0%` — 4 timeouts, 2 HTTP 404, 1 HTTP 500, 1 connection reset; expected on aged community source lists)
- **Selector Drift / Upstream HTML Change / `:regex` Gap (`SourceParseFailure`)**: `6 / 20` (`30.0%` — 4 at `search`, 2 at `toc` after `search` succeeded)
- **Paginated TOC Budget Exceeded (`TimeoutException`)**: `1 / 20` (`5.0%` — `搜小说🎃` succeeded at `search` + `detail` + 400 chapters of `toc`)
- **Explicit Unsupported Feature (`UnsupportedLegadoRuleFailure`)**: `1 / 20` (`5.0%` — `searchUrl` option `'webView': true` fast-rejected in `2 ms`)

---

## 4. Key Engineering Findings & Future M3 Backlog

1. **Mustache `{{key}}` vs `<a,b>` page conditional separation**: Splitting page-conditional `<a,b>` expansion from full `{{...}}` mustache interpolation prevented `{{key}}` from being erased prior to charset-aware URL/form encoding.
2. **Literal `@get:{key}` rule resolution**: Real sources such as `🎃笔迷读吧🎃` populate `@put:{...}` in `ruleBookInfo.init` and read fields back with bare `@get:{n}`. Resolving bare `@get:{...}` as literal variable values (rather than CSS tag selectors) immediately unlocked full `detail -> toc -> content` execution.
3. **JS void helper return values**: `cookie.removeCookie(...)` and `source.setVariable(...)` must evaluate to `undefined` (`""`) rather than `null` (`"null"`), preventing malformed URLs such as `/null%0As.php`.
4. **M3 compatibility candidates identified by the probe**:
   - `:regex` all-in-one regex match-group list rules (e.g. `黑岩小说`: `:(?s)(\d+)" class=...` + `$1`/`$2` substitution).
   - Pure-JS AES/DES helpers (`java.createSymmetricCrypto`, `java.aesBase64DecodeToString`) for API-based sources (`19–27` sources).
   - Optional headless WebView fallback adapter for the `63` `webView: true` / `startBrowserAwait` sources.
