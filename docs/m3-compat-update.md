# Milestone 3 Legado Compatibility Update

> **Baseline**: [m2-source-compat-report.md](file:///D:/READ/docs/m2-source-compat-report.md)  
> **Scope**: Pure-Dart AES/DES symmetric cryptography (`JsCryptoHelpers`), QuickJS `host.*` & Legado `java.*` crypto bridges (`QjsSandboxRuntime`, `LegadoRuleEvaluator`), and `:regex` / `@regex:` all-in-one list rules (`LegadoSelectorEngine`, `LegadoRuleEvaluator`).  
> **Dependencies**: Zero new packages added to `pubspec.yaml` (pure Dart `dart:convert` + `dart:typed_data` implementations).

---

## 1. Summary of M3 Enhancements

In [m2-source-compat-report.md](file:///D:/READ/docs/m2-source-compat-report.md), two high-impact gaps were identified from the 2,693-source real Legado corpus:

1. **Symmetric crypto APIs (`AES` / `DES`)** for API-backed sources (such as `java.aesBase64DecodeToString` and `java.createSymmetricCrypto`).
2. **`:regex` / `@regex:` all-in-one regex list rules** with inline flags (`(?s)`, `(?i)`, `(?m)`, `(?is)`) and `$0`/`$1`/`$2` capture-group propagation into item field rules.

Milestone 3 closes both gaps without external cryptographic packages and while maintaining full backward compatibility with M2 CSS, XPath, JSONPath, and QuickJS behaviors.

---

## 2. Pure-Dart Symmetric Crypto (`JsCryptoHelpers`)

Implemented in [js_crypto_helpers.dart](file:///D:/READ/lib/infrastructure/js/js_crypto_helpers.dart):

| Capability | Details |
| :--- | :--- |
| **AES (FIPS-197)** | AES-128 (16-byte key), AES-192 (24-byte key), AES-256 (32-byte key), 16-byte block size |
| **DES (FIPS-46)** | Single DES (8-byte key), 8-byte block size |
| **Modes** | `ECB` and `CBC` (omitted/empty IV falls back to zero-filled block IV; non-empty IVs are truncated or zero-padded cleanly to block size) |
| **Padding** | `PKCS5Padding` / `PKCS7Padding`, `ZeroPadding`, and `NoPadding` |
| **Public APIs** | `encryptSymmetric`, `decryptSymmetric`, `validateSymmetricConfig`, `aesEncryptBase64`, `aesDecryptBase64`, `aesEncryptHex`, `aesDecryptHex`, `hexEncode`, `hexDecodeBytes`, `coerceBytes`, `decodeCiphertextInput` |
| **Error Handling** | Explicit `ArgumentError` / `FormatException` messages on invalid algorithm, mode, padding, key length, unaligned `NoPadding`, or corrupted PKCS padding |

---

## 3. QuickJS Host & Legado `java.*` Bridges

Implemented in [qjs_sandbox_runtime.dart](file:///D:/READ/lib/infrastructure/js/qjs_sandbox_runtime.dart) and [legado_rule_evaluator.dart](file:///D:/READ/lib/engine/source_engine/legado_compat/legado_rule_evaluator.dart):

### 3.1 QuickJS Sandbox Host (`host.*`)

- `host.aesEncodeBase64(data, key, transformation?, iv?)`
- `host.aesDecodeBase64(data, key, transformation?, iv?)`
- `host.aesEncodeHex(data, key, transformation?, iv?)`
- `host.aesDecodeHex(data, key, transformation?, iv?)`
- `host.symmetricCrypto(op, transformation, key, iv?, data?)` (handles AES & DES encrypt/decrypt across `String`, `Array<int>`, and `Uint8Array`)
- `host.strToBytes(str)`, `host.base64DecodeBytes(str)`, `host.hexDecodeBytes(str)`
- Host crypto errors are mapped into catchable JS `Error` (`JSException`) / `JsExecutionFailure` so malformed inputs never crash the host Dart isolate.

### 3.2 Legado `java.*` Helper Methods

- `java.aesBase64DecodeToString(str, key, transformation, iv)`
- `java.aesDecodeToString(data, key, transformation, iv)` (supports Base64, Hex, and `Array<int>` / `Uint8Array` byte inputs)
- `java.aesBase64Encode(str, key, transformation, iv)` / `java.aesEncodeToString(str, key, transformation, iv)` / `java.aesEncodeToBase64String(str, key, transformation, iv)`
- `java.desEncodeToBase64String(str, key, transformation, iv)` / `java.desBase64DecodeToString(str, key, transformation, iv)`
- `java.strToBytes(s)`, `java.base64DecodeToByteArray(s)`, `java.hexDecodeToByteArray(s)`
- `java.createSymmetricCrypto(transformation, key, iv)` supporting both `AES/...` and `DES/...` with `String`, `Array<int>` (unsigned `0..255` and signed Java `-128..127`), and `Uint8Array` keys/IVs, returning an object with:
  - `.decryptStr(data)`
  - `.decrypt(data)` (returns decrypted `Array<int>` byte array)
  - `.decryptBase64Str(data)`
  - `.decryptHexStr(data)`
  - `.encryptBase64(str)`
  - `.encryptHex(str)`
  - (plus `.encrypt(str)`, `.decryptBase64(data)`, `.decryptHex(data)`)

---

## 4. Legado `:regex` / `@regex:` All-in-One List Rules

Implemented in [legado_selector_engine.dart](file:///D:/READ/lib/engine/source_engine/parsing/legado_selector_engine.dart) and [legado_rule_evaluator.dart](file:///D:/READ/lib/engine/source_engine/legado_compat/legado_rule_evaluator.dart):

- **List rule detection**: Supports `bookList` and `chapterList` rules starting with `:` (excluding CSS pseudo-elements `::`) or `@regex:` (case-insensitive), including `-:` / `-@regex:` reverse prefixes and `:region&&itemRegex` narrowing chains.
- **Inline flag translation**: `LegadoSelectorEngine.compileLegadoRegex` strips Java/PCRE inline flag prefixes/directives (`(?s)`, `(?i)`, `(?m)`, `(?is)`, `(?ms)`, `(?i-m)`, scoped `(?i:...)`, etc.) outside character classes/escapes and maps them to Dart `RegExp(dotAll: ..., caseSensitive: ..., multiLine: ...)`. Also applied inside `##pattern##replacement` rules.
- **Capture-group propagation**: Each regex match carries `$0` (full match) and `$1`..`$N` capture groups into item field evaluation (`name`, `author`, `bookUrl`, `coverUrl`, `chapterName`, `chapterUrl`, etc.).
- **Chained rule compatibility**: Supports `$1`/`$2` substitution combined with `##regex##replace`, `||`/`&&`/`%%` combinators, `@js:` / `<js>...</js>` stages (exposing `result` as `$0` plus `$0`..`$N` JS bindings), and `{{...}}` mustache templates (`{{$1}}`, `{{java.md5Encode($1)}}`), while keeping CSS, XPath, and JSONPath rules untouched.

---

## 5. Test Coverage & Static Analysis

Covered by [legado_m3_compat_test.dart](file:///D:/READ/test/engine/source_engine/legado_m3_compat_test.dart) and checked with `dart analyze --fatal-infos --fatal-warnings`:

- Official NIST FIPS-197 AES-128/192/256 ECB, NIST SP 800-38A AES-128 CBC, and NIST FIPS-46 DES ECB vectors.
- PKCS5Padding, PKCS7Padding, ZeroPadding, and NoPadding round-trips, IV normalization, and explicit parameter validation errors.
- QuickJS execution of `host.*` and `java.*` symmetric crypto APIs (`AES/...` and `DES/...`, `String` and `Array<int>` / `Uint8Array`).
- End-to-end `:regex`, `-@regex:`, `(?is)`/`(?m)`, `&&` narrowing, `$1`/`$2` capture substitution, `##replace##`, `{{...}}`, and `@js:` / `<js>` evaluation through `LegadoRuleEvaluator` and `LegadoCompatProvider`.
