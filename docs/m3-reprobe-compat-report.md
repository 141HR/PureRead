# Milestone 3.5 Source Compatibility Hardening & Re-Probe Report

> **Date**: 2026-11-25  
> **Scope**: Stage 1 Foundations ([`js_crypto_helpers.dart`](file:///d:/READ/lib/infrastructure/js/js_crypto_helpers.dart), [`qjs_sandbox_runtime.dart`](file:///d:/READ/lib/infrastructure/js/qjs_sandbox_runtime.dart), [`legado_jsoup_bridge.dart`](file:///d:/READ/lib/engine/source_engine/parsing/legado_jsoup_bridge.dart)) & Stage 2 Integration ([`legado_source.dart`](file:///d:/READ/lib/engine/source_engine/legado_compat/legado_source.dart), [`legado_rule_evaluator.dart`](file:///d:/READ/lib/engine/source_engine/legado_compat/legado_rule_evaluator.dart), [`legado_compat_provider.dart`](file:///d:/READ/lib/engine/source_engine/legado_compat/legado_compat_provider.dart), [`source_http_client.dart`](file:///d:/READ/lib/infrastructure/network/source_http_client.dart))  
> **Probe Script**: [`probe_m3_compat.dart`](file:///d:/READ/tool/probe_m3_compat.dart)  
> **Baseline Comparison**: [`m2-source-compat-report.md`](file:///d:/READ/docs/m2-source-compat-report.md) (M2 baseline), M3 baseline probe, and M3.5 hardened re-probe  

---

## 1. Executive Summary

1. **Static headless compatibility jumped from `83.2%` to `90.5%` (`+196` sources)**:
   - Unlocking `org.jsoup.*` / `Packages.org.jsoup.*` / `importClass(org.jsoup.*)` via the QuickJS DOM bridge reduced `unsupportedRhino` rejections across the **2,693** real community Legado sources (`1,031` + `1,662`) from **`234` (`8.7%`)** down to **`38` (`1.4%`, `-83.8%`)**.
   - Statically supported headless text sources rose from **`2,240 / 2,693` (`83.2%`)** to **`2,436 / 2,693` (`90.5%`, or `95.0%` of all `2,565` text novel sources)** with **`0` parse errors**.
2. **Cohort A (`m2-baseline`, 20 pinned sources) full-chain success rose `20.0% -> 25.0% -> 30.0%`**:
   - M2 baseline (`probe_real_sources.dart`): `4 / 20` (`20.0%`) `Success`
   - M3 baseline (`probe_m3_compat.dart`): `5 / 20` (`25.0%`) `Success`
   - **M3.5 hardened**: **`6 / 20` (`30.0%`) `Success`**, `3` `redirectedOnSearch`, **`0` `JsExecutionFailure`** (`笔趣阁` unlocked via search redirect-to-detail fallback with `2,464` chapters).
3. **Cohort B (`m3-targeted`, high-complexity crypto / Jsoup / JS-API / regex sources) doubled full-chain success & cut `init` JS blocks**:
   - M3 baseline: `2 / 26` (`7.7%`) `Success`, `18 / 26` (`69.2%`) stopped at `init`, `2` `UnsupportedLegadoRuleFailure`, `7` `JsExecutionFailure`.
   - **M3.5 hardened**: **`4 / 28` (`14.3%`) `Success`**, **`0` `UnsupportedLegadoRuleFailure`**, `init` stops cut to **`11 / 28` (`39.3%`)**, with **`17 / 28` (`60.7%`)** advancing into `search` (`8`), `toc` (`4`), or `content` (`5`).

---

## 2. M2 Baseline vs. M3 Baseline vs. M3.5 Hardened — Static Corpus (2,693 Sources)

| Metric | M2 Baseline | M3 Baseline | M3.5 Hardened | Delta (vs M3 Baseline) |
| :--- | :---: | :---: | :---: | :---: |
| Total parsed sources | `2,693` | `2,693` | `2,693` | `0` |
| Parse errors / crashes | `0` | `0` | `0` | `0` |
| Non-text sources (`bookSourceType != 0`) | `128` | `128` | `128` | `0` (`52` image, `41` audio, `35` file) |
| Malformed / non-HTTP `bookSourceUrl` | `28` | `28` | `28` | `0` |
| Unsupported WebView (`webView` / `startBrowserAwait`) | `63` | `63` | `63` | `0` |
| **Unsupported Rhino (`Packages.*` / `java.lang.*` / ...)** | `234` (`8.7%`) | `234` (`8.7%`) | **`38` (`1.4%`)** | **`-196` (`-83.8%`)** |
| **Statically supported (headless text)** | `2,240` (`83.2%`) | `2,240` (`83.2%`) | **`2,436` (`90.5%`)** | **`+196` (`+7.3 pp`)** |
| Share of text sources (`n = 2,565`) supported | `87.3%` | `87.3%` | **`95.0%`** | **`+7.7 pp`** |
| `#fragment`-tagged `bookSourceUrl` | `1,803` | `1,803` | `1,803` | `0` |

### 2.1 Extended Corpus Feature Inventory (2,693 Sources)

| Extended Feature | `1031` File (`n=1,031`) | `1662` File (`n=1,662`) | Combined (`n=2,693`) | M3.5 Status |
| :--- | :---: | :---: | :---: | :--- |
| `checkKeyWord` (`ruleSearch.checkKeyWord`) | `234` | `314` | `548` | Parsed into `LegadoSearchRule` |
| `loginUrl` present | `81` | `298` | `379` | Stored; `source.getLoginInfo*` / `getLoginHeader*` safe stubs added |
| `orgJsoup` (`org.jsoup.*` / `Jsoup.*`) | `86` | `120` | `206` | Supported via [`LegadoJsoupBridge`](file:///d:/READ/lib/engine/source_engine/parsing/legado_jsoup_bridge.dart) (`orgJsoupOnly = 193`) |
| `cryptoAny` (`aes` = `75`, `des` = `45`) | `36` | `84` | `120` | Supported via [`JsCryptoHelpers`](file:///d:/READ/lib/infrastructure/js/js_crypto_helpers.dart) (`createSymmetricCrypto = 35`) |
| `webView` feature detected | `30` | `37` | `67` | Explicitly rejected (`unsupportedWebView = 63` at classifier level) |
| `javaPost` | `12` | `34` | `46` | Supported (`await` rewrite, form/JSON body, `Location` header fallback) |
| `jsLib` | `19` | `24` | `43` | Prepended into QuickJS execution context |
| `bookVariable` (`book.variable` / `*Variable`) | `12` | `22` | `34` | Supported on `book` backed by [`LegadoEvalSession`](file:///d:/READ/lib/engine/source_engine/legado_compat/legado_rule_evaluator.dart) |
| `regexListRule` (`:` list regex) | `12` | `20` | `32` | `colonRegex` feature tag added; partial legacy regex syntax remains |
| `digestShaHmac` (`javaDigestHex = 4`) | `3` | `19` | `22` | Supported (`digestHex/Base64`, `sha1/256/512Encode`, `HMacHex/Base64`, `createDigest`, `createHMac`) |
| `javaTimeFormatUTC` | `4` | `15` | `19` | Supported (2-arg & 3-arg, `Date`/num/string, hours & ms offsets) |
| `javaAjaxAll` | `5` | `9` | `14` | Supported via bounded concurrent `java.__asyncAjaxAll` (concurrency 4) |
| `preUpdateJs` (`ruleToc.preUpdateJs`) | `1` | `12` | `13` | Parsed into `LegadoTocRule` and executed in `getToc` |
| `cacheGetPut` | `1` | `2` | `3` | Supported via provider-shared `cache` TTL store |
| Non-Jsoup Rhino (`rhinoPackages = 64`, `rhinoImportClass = 9`, `rhinoJavaLang = 9`) | `6` rejected | `32` rejected | `38` rejected | Intentionally rejected by `hasUnsupportedRhinoApi` |

---

## 3. Live Re-Probe Summary: Cohort A (`m2-baseline`) & Cohort B (`m3-targeted`)

Probe configuration (identical across M3 baseline and M3.5 after-probe): `connectTimeout = 6s`, `receiveTimeout = 6s`, `defaultRateLimitMs = 500ms`, `jsTimeout = 4s`, `perSourceCap = 18s`, `concurrency = 4`, `preferRuleSearchCheckKeyWord = true`, default queries `["凡人修仙传", "诡秘之主"]`.

### 3.1 Aggregate Cohort Comparison

| Cohort | Metric | M2 Baseline | M3 Baseline | M3.5 Hardened | Delta (M3.5 vs M3 Baseline) |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **Cohort A** (`m2-baseline`, `n=20`) | **Full-Chain `Success`** | `4 / 20` (`20.0%`) | `5 / 20` (`25.0%`) | **`6 / 20` (`30.0%`)** | **`+1` (`+5.0 pp`)** |
| | `redirectedOnSearch` | — | `3` | `3` | `0` |
| | `SourceParseFailure` | `6` | `5` | `4` | `-1` |
| | `JsExecutionFailure` | `0` | `0` | `0` | `0` |
| | `NetworkFailure` + `NetworkTimeout` | `8` | `8` | `8` | `0` |
| | `TimeoutException` (18s cap) | `1` | `1` | `1` | `0` |
| | `UnsupportedLegadoRuleFailure` | `1` | `1` | `1` | `0` |
| **Cohort B** (`m3-targeted`, `n=26 -> 28`)* | **Full-Chain `Success`** | — | `2 / 26` (`7.7%`) | **`4 / 28` (`14.3%`)** | **`+2` (`+6.6 pp`)** |
| | `redirectedOnSearch` | — | `2` | `5` | `+3` |
| | Reached `content` | — | `2` (`7.7%`) | **`5` (`17.9%`)** | **`+3`** |
| | Reached `toc` | — | `1` (`3.8%`) | **`4` (`14.3%`)** | **`+3`** |
| | Reached `search` | — | `4` (`15.4%`) | **`8` (`28.6%`)** | **`+4`** |
| | Stopped at `init` | — | `18` (`69.2%`) | **`11` (`39.3%`)** | **`-7` (`-29.9 pp`)** |
| | `UnsupportedLegadoRuleFailure` | — | `2` | **`0`** | **`-2` (`-100%`)** |
| | `JsExecutionFailure` | — | `7` | `6` | `-1` |

*\*Note on Cohort B size (`26 -> 28`): `m3-regex` increased from `5` sources in M3 baseline to `7` sources in M3.5 because unlocking `org.jsoup` made `🎃言情小说吧🎃`, `🎃言情小说吧🎃#2`, and `🎃海棠书屋🎃#5` statically supported.*

### 3.2 Cohort B Category Breakdown (`M3 Baseline -> M3.5 Hardened`)

| Bucket | M3 Baseline | M3.5 Hardened | Key Progressions |
| :--- | :--- | :--- | :--- |
| `m3-regex` (`5 -> 7`) | `1/5` Success (`init=3, search=1, content=1`) | `1/7` Success (`init=3, search=2, content=2`) | `🎃海棠书屋🎃#5` extracted `7` search items + `1,412` TOC chapters (redirected) before empty content; `🎃言情小说吧🎃` unlocked `org.jsoup` & extracted `8` search items |
| `m3-crypto` (`7 -> 7`) | `0/7` Success (`init=5, search=1, detail=1`; `JsExec=3`) | **`1/7` Success** (`init=3, search=1, toc=2, content=1`; `JsExec=2`) | `🎃完本小说网🎃` reached **Success** (`items=4, ch=2000`, `createSymmetricCrypto` + `org.jsoup`); `🎃小红书🎃` progressed `detail -> toc` (`10` ch); `顶点小说` cleared `randomUUID` `init` block (`HTTP 200` at `search`); `鸠摩搜书（下载）` cleared regex-literal syntax error & executed `POST` `java.ajax` |
| `m3-jsoup` (`7 -> 7`) | `1/7` Success (`Unsupported=2`, `init=4`) | **`2/7` Success** (`Unsupported=0`, `init=2, search=3, content=2`) | `耽美7` unlocked & reached **Success** (`items=1, ch=635, chars=60,958`); `💰晋江分类` cleared `Unsupported` block (`HTTP 200` at `search`) |
| `m3-js-api` (`7 -> 7`) | `0/7` Success (`init=6, toc=1`; `JsExec=4`) | `0/7` Success (`init=3, search=2, toc=2`; `JsExec=1`) | `🎃阅友网络🎃` progressed `init -> toc` (`20` items, `356` chapters via HMAC+DES+UUID); `🎃读读看🎃` cleared `java.ajaxAll` `init` block (`HTTP 200` at `search`); `🎃天天书吧🎃` fixed `.netsearch.html` -> `https://www.ttshu8.net/search.html` (upstream HTTP 500) |

---

## 4. Notable Source-Level Improvements Verified Live

| Source | Cohort / Bucket | M3 Baseline | M3.5 Hardened | Mechanism Validated |
| :--- | :--- | :--- | :--- | :--- |
| `笔趣阁` (`biquge001.com`) | Cohort A (`Combinator`) | `search / SourceParseFailure` (`items=0`) | **`content / Success`** (`items=1, ch=2464, chars=58, redir=true`) | Search redirect-to-detail fallback (`_tryExtractRedirectDetailSearchItem`) |
| `🖤㊣♛塔读文学一程1201` | Cohort A (`JS-Embedded`) | `content / Success` (`items=30, ch=5, chars=3849`) | **`content / Success`** (`items=30, ch=5, chars=3875`) | `source.getHeaderMap()` arrow-object parens + `java.ajax` callback unwrap |
| `耽美7` (`m.xyuzhaiwu7.com`) | Cohort B (`m3-jsoup`) | `init / NetworkTimeout` (previously `orgJsoup` rejected) | **`content / Success`** (`items=1, ch=635, chars=60958`) | `org.jsoup` unlock + DOM bridge execution |
| `🎃完本小说网🎃` (`finalbooks.work`) | Cohort B (`m3-crypto`) | Excluded / `orgJsoup` | **`content / Success`** (`items=4, ch=2000, redir=true`) | `org.jsoup` `ruleToc` JS sort + `jsLib` `createSymmetricCrypto` + redirect fallback |
| `🎃阅友网络🎃` (`yueyouxs.com`) | Cohort B (`m3-js-api`) | `init / JsExecutionFailure` (`HMacHex` / `randomUUID`) | `toc / NetworkFailure` (**`items=20, ch=356`**) | `java.HMacHex`, `desEncodeToBase64String`, `randomUUID`, `{{$.id}}` inside `@js:`, `resolveUrlSpec`, shared provider `javaVars` |
| `🎃小红书🎃` (`xxxhongshu.com`) | Cohort B (`m3-crypto`) | `detail / JsExecutionFailure` (`src is not defined`) | `toc / JsExecutionFailure` (`items=1, ch=10, redir=true`) | `src` binding + `org.jsoup` `Elements` sort/select in `ruleToc` |
| `🎃海棠书屋🎃#5` (`haitang123.com`) | Cohort B (`m3-regex`) | Excluded / `orgJsoup` | `content / SourceParseFailure` (`items=7, ch=1412, redir=true`) | `{{...}}` mustache evaluation inside `@js:` + `title` binding + `book.putVariable` |
| `顶点小说` (`api.basusan.com`) | Cohort B (`m3-crypto`) | `init / JsExecutionFailure` (`randomUUID` / `preUpdateJs`) | `search / SourceParseFailure` (`HTTP 200`, `$.data[*]`) | `java.randomUUID`, `preUpdateJs` parsing, search `HTTP 200` |
| `🎃读读看🎃` (`m.duduaa.com`) | Cohort B (`m3-js-api`) | `init / JsExecutionFailure` (`java.ajaxAll`) | `search / SourceParseFailure` (`HTTP 200`, `.list@li`) | `java.ajaxAll` bounded async rewrite (`java.__asyncAjaxAll`) |
| `🎃天天书吧🎃` (`ttshu8.net`) | Cohort B (`m3-js-api`) | `init / JsExecutionFailure` (`https://www.ttshu8.netsearch.html`) | `init / NetworkFailure` (`HTTP 500` from `https://www.ttshu8.net/search.html`) | Root trailing `/` normalization on `raw().request().url()` + `Location` header fallback |
| `💰晋江分类` (`m.jjwxc.net`) | Cohort B (`m3-jsoup`) | `init / UnsupportedLegadoRuleFailure` (`orgJsoup`) | `search / SourceParseFailure` (`HTTP 200`, `@css:tbody tr:lt(5)`) | `org.jsoup` classifier & evaluator guard unlock |

---

## 5. Remaining Non-Headless Items & Live Failure Breakdown

### 5.1 Intentional Headless Exclusions (`257 / 2,693`, `9.5%`)

- **Non-text sources (`128`)**: `52` image/manga (`bookSourceType == 2`), `41` audio (`1`), `35` file/download (`3`).
- **Interactive WebView (`63`)**: `webView: true`, `startBrowserAwait`, or `java.webView(...)` requiring an interactive browser view.
- **Non-Jsoup Rhino Java APIs (`38`)**: scripts referencing `Packages.(?!org.jsoup)`, `java.lang.*`, `java.net.*`, `java.io.*`, `java.util.*`, or non-Jsoup `importClass(...)` (down from `234`).
- **Malformed `bookSourceUrl` (`28`)**: empty, non-HTTP(S), or placeholder URLs in the community corpus.
- **Interactive login (`379` `loginUrl` metadata)**: non-login browse/search works with safe stubs (`getLoginInfo*` / `getLoginHeader*`), while login-gated endpoints cannot sign in automatically without user credentials.

### 5.2 Remaining Live-Probe Failures Across Cohort A & Cohort B (`48` Sources)

1. **Upstream Network Outages, HTTP Errors, & Timeouts (`19 / 48` + `1` 18s TOC cap)**:
   - Cohort A (`8` network + `1` cap): `手机小说` (404), `博爱书屋` (connection closed), `🎃御书屋🎃#4` (404), `🎃多多书院🎃#2` (500), `zhsxs` (404), `🎃76小说🎃` / `🎃悠悠文学🎃` / `🎃天域小说️🎃` (6s timeouts), `搜小说🎃` (400 chapters fetched before 18s budget).
   - Cohort B (`9` network): `🎃书书小说🎃` (404), `🎃阅读书库🎃` (connection closed), `🎃九五小说🎃#2` (timeout), `笔阅读器` (connection failure), `🎃漫蛙可直连🎃` (connection failure), `爱看书吧[海阔搜索]` (connection failure), `🎃若雨中文🎃#2` (timeout), `🎃小米书城🎃` (404), `🎃天天书吧🎃` (`HTTP 500` on `/search.html`).
2. **Upstream HTML/API Drift (`12 / 48` `SourceParseFailure` + `1` `EmptyToc`)**:
   - Sites returning HTTP `200` whose live markup/API schema drifted from the legacy selector (`千凡小说`, `猫眼看书🎃#3`, `英文小说（英文）`, `话本小说`, `顶点小说`, `🎃新龙小说🎃`, `💰晋江分类`, `万相书城` `wxsck.com`, `🎃中华典藏🎃`, `🎃读读看🎃`, `🎃龙渊书屋🎃`, `🎃海棠书屋🎃#5`, plus `移动阅读 cm` `EmptyToc`).
3. **Remaining Edge-Case JS / DSL Compatibility Items (`6 / 48` `JsExecutionFailure` + `1` TOC-to-Content ID quirk in Cohort B, `0` in Cohort A)**:
   - `万相书城` (`wxscn.com`): `{{...}}` mustache block inside a `//` JS comment line triggered evaluation (`unexpected token '\'`); also uses `java.ajax(..., {'webView': true})`.
   - `🎃言情小说吧🎃` & `🎃言情小说吧🎃#2`: JS snippets in `ruleSearch`/`ruleBookInfo` throw `not a function` (uses additional non-standard helper/DOM chain methods).
   - `🎃小红书🎃`: reached `content` (`10` chapters extracted), where upstream page lacked the expected encrypted `d("...")` payload (`match(...)[1]` null).
   - `鸠摩搜书（下载）`: `POST /init_hubs.php` succeeded without syntax error; upstream JSON response did not contain `id`.
   - `🎃阅友网络🎃`: extracted `20` search items and `356` TOC chapters; `ruleToc.chapterUrl` yields bare numeric IDs (`274535`), so `getChapterContent` requests `http://dl.reader.yueyouxs.com/userCenter/274535` (HTTP `404`) before running `ruleContent`'s `@js:` downloader.

---

## 6. Verification Summary

- `dart analyze --fatal-infos --fatal-warnings` on all 5 owned source & test files (`legado_source.dart`, `legado_rule_evaluator.dart`, `legado_compat_provider.dart`, `source_http_client.dart`, `legado_m3_5_compat_test.dart`): **0 issues**.
- Targeted test run (`flutter test --no-pub --reporter compact` across `legado_m3_5_compat_test.dart`, `legado_real_corpus_test.dart`, `legado_compat_provider_test.dart`, `legado_m3_compat_test.dart`, `source_http_client_test.dart`): **29 / 29 passed**.
- Live re-probe (`dart run tool/probe_m3_compat.dart`): **0 uncaught crashes** across 2,693 static analyses and 48 live HTTP source probes.
