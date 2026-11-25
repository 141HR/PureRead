#include "tts_channel_handler.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cwchar>
#include <optional>
#include <string>
#include <utility>
#include <variant>

#include "utils.h"

namespace {

constexpr char kTtsMethodChannelName[] = "com.pureread.app/tts";
constexpr char kTtsEventChannelName[] = "com.pureread.app/tts/events";
constexpr char kEngineId[] = "windows_sapi";
// "Windows 系统语音 (SAPI/OneCore)" in UTF-8 without non-ASCII source bytes.
constexpr char kEngineLabel[] =
    "Windows \xE7\xB3\xBB\xE7\xBB\x9F\xE8\xAF\xAD\xE9\x9F\xB3 (SAPI/OneCore)";
constexpr wchar_t kOneCoreVoicesCategory[] =
    L"HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech_OneCore\\Voices";

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int input_length = static_cast<int>(utf8.size());
  const int target_length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), input_length, nullptr, 0);
  if (target_length <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(target_length), L'\0');
  const int converted = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), input_length, result.data(), target_length);
  if (converted <= 0) {
    return std::wstring();
  }
  return result;
}

std::wstring ToLowerAscii(const std::wstring& input) {
  std::wstring out = input;
  for (wchar_t& ch : out) {
    if (ch >= L'A' && ch <= L'Z') {
      ch = static_cast<wchar_t>(ch - L'A' + L'a');
    }
  }
  return out;
}

bool IsZhLocale(const std::string& locale) {
  if (locale.size() < 2) {
    return false;
  }
  return (locale[0] == 'z' || locale[0] == 'Z') &&
         (locale[1] == 'h' || locale[1] == 'H') &&
         (locale.size() == 2 || locale[2] == '-' || locale[2] == '_');
}

std::optional<std::string> GetStringArg(
    const flutter::EncodableValue* arguments, const char* key) {
  const auto* args = std::get_if<flutter::EncodableMap>(arguments);
  if (!args) {
    return std::nullopt;
  }
  const auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) {
    return std::nullopt;
  }
  if (const auto* val = std::get_if<std::string>(&it->second)) {
    return *val;
  }
  return std::nullopt;
}

std::optional<double> GetDoubleArg(const flutter::EncodableValue* arguments,
                                   const char* key) {
  const auto* args = std::get_if<flutter::EncodableMap>(arguments);
  if (!args) {
    return std::nullopt;
  }
  const auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) {
    return std::nullopt;
  }
  if (const auto* val = std::get_if<double>(&it->second)) {
    return *val;
  }
  if (const auto* val = std::get_if<int32_t>(&it->second)) {
    return static_cast<double>(*val);
  }
  if (const auto* val = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*val);
  }
  return std::nullopt;
}

std::string FormatHResultError(const char* prefix, HRESULT hr) {
  char buf[128] = {};
  std::snprintf(buf, sizeof(buf), "%s (HRESULT=0x%08lX)", prefix,
                static_cast<unsigned long>(hr));
  return std::string(buf);
}

void ClearSpEvent(SPEVENT& ev) {
  if (ev.lParam != 0) {
    if (ev.elParamType == SPET_LPARAM_IS_POINTER ||
        ev.elParamType == SPET_LPARAM_IS_STRING) {
      ::CoTaskMemFree(reinterpret_cast<void*>(ev.lParam));
    } else if (ev.elParamType == SPET_LPARAM_IS_TOKEN ||
               ev.elParamType == SPET_LPARAM_IS_OBJECT) {
      reinterpret_cast<IUnknown*>(ev.lParam)->Release();
    }
    ev.lParam = 0;
  }
  ev.elParamType = SPET_LPARAM_IS_UNDEFINED;
}

std::wstring EscapeXmlText(const std::wstring& input) {
  std::wstring out;
  out.reserve(input.size() + 16);
  for (wchar_t ch : input) {
    switch (ch) {
      case L'&':
        out.append(L"&amp;");
        break;
      case L'<':
        out.append(L"&lt;");
        break;
      case L'>':
        out.append(L"&gt;");
        break;
      case L'"':
        out.append(L"&quot;");
        break;
      case L'\'':
        out.append(L"&apos;");
        break;
      default:
        // Strip XML 1.0 disallowed control chars while preserving whitespace.
        if (ch < 0x20 && ch != L'\t' && ch != L'\n' && ch != L'\r') {
          out.push_back(L' ');
        } else {
          out.push_back(ch);
        }
        break;
    }
  }
  return out;
}

}  // namespace

TtsChannelHandler::TtsChannelHandler(flutter::BinaryMessenger* messenger,
                                     HWND hwnd)
    : hwnd_(hwnd) {
  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kTtsMethodChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });

  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, kTtsEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                     events)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            event_sink_ = std::move(events);
            return nullptr;
          },
          [this](const flutter::EncodableValue* arguments)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            event_sink_.reset();
            return nullptr;
          }));
}

TtsChannelHandler::~TtsChannelHandler() {
  Shutdown();
  if (owns_com_init_) {
    ::CoUninitialize();
    owns_com_init_ = false;
  }
}

void TtsChannelHandler::Shutdown() {
  ReleaseVoiceResources();
  if (method_channel_) {
    method_channel_->SetMethodCallHandler(nullptr);
    method_channel_.reset();
  }
  if (event_channel_) {
    event_channel_->SetStreamHandler(nullptr);
    event_channel_.reset();
  }
  event_sink_.reset();
}

void TtsChannelHandler::ReleaseVoiceResources() {
  is_stopped_ = true;
  active_utterance_id_.clear();
  active_stream_num_ = 0;

  if (voice_) {
    voice_->Speak(nullptr, SPF_ASYNC | SPF_PURGEBEFORESPEAK, nullptr);
    voice_->SetInterest(0, 0);
    voice_->SetNotifySink(nullptr);
    voice_.Reset();
  }
  voice_tokens_.clear();
}

void TtsChannelHandler::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "initialize") {
    result->Success(flutter::EncodableValue(InitializeVoice()));
    return;
  }

  if (method == "getEngines") {
    flutter::EncodableMap engine_map;
    engine_map[flutter::EncodableValue("id")] =
        flutter::EncodableValue(std::string(kEngineId));
    engine_map[flutter::EncodableValue("label")] =
        flutter::EncodableValue(std::string(kEngineLabel));
    engine_map[flutter::EncodableValue("isDefault")] =
        flutter::EncodableValue(true);

    flutter::EncodableList engines;
    engines.push_back(flutter::EncodableValue(std::move(engine_map)));
    result->Success(flutter::EncodableValue(std::move(engines)));
    return;
  }

  if (method == "setEngine") {
    const auto engine_id = GetStringArg(call.arguments(), "engineId");
    const bool ok = engine_id.has_value() && *engine_id == kEngineId;
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "getVoices") {
    const std::vector<VoiceEntry> voices = CollectVoices();
    flutter::EncodableList list;
    list.reserve(voices.size());
    for (const auto& entry : voices) {
      flutter::EncodableMap item;
      item[flutter::EncodableValue("id")] = flutter::EncodableValue(entry.id);
      item[flutter::EncodableValue("name")] =
          flutter::EncodableValue(entry.name);
      item[flutter::EncodableValue("locale")] =
          flutter::EncodableValue(entry.locale);
      list.push_back(flutter::EncodableValue(std::move(item)));
    }
    result->Success(flutter::EncodableValue(std::move(list)));
    return;
  }

  if (method == "setVoice") {
    const auto voice_id = GetStringArg(call.arguments(), "voiceId");
    const bool ok =
        voice_id.has_value() && !voice_id->empty() && SetVoiceById(*voice_id);
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "setSpeechRate") {
    const auto rate = GetDoubleArg(call.arguments(), "rate");
    SetSpeechRate(rate.value_or(1.0));
    result->Success();
    return;
  }

  if (method == "setPitch") {
    const auto pitch = GetDoubleArg(call.arguments(), "pitch");
    SetPitch(pitch.value_or(1.0));
    result->Success();
    return;
  }

  if (method == "speak") {
    const auto text = GetStringArg(call.arguments(), "text");
    const auto utterance_id = GetStringArg(call.arguments(), "utteranceId");
    const bool ok = text.has_value() && !text->empty() &&
                    utterance_id.has_value() && !utterance_id->empty() &&
                    SpeakText(*text, *utterance_id);
    result->Success(flutter::EncodableValue(ok));
    return;
  }

  if (method == "stop" || method == "pauseNotification") {
    StopSpeech();
    result->Success();
    return;
  }

  if (method == "updateMetadata") {
    result->Success();
    return;
  }

  if (method == "shutdown") {
    ReleaseVoiceResources();
    result->Success();
    return;
  }

  result->NotImplemented();
}

flutter::EncodableMap TtsChannelHandler::InitializeVoice() {
  flutter::EncodableMap response;

  if (voice_) {
    response[flutter::EncodableValue("available")] =
        flutter::EncodableValue(true);
    response[flutter::EncodableValue("engine")] =
        flutter::EncodableValue(std::string(kEngineId));
    response[flutter::EncodableValue("error")] = flutter::EncodableValue();
    return response;
  }

  detail::ComPtr<ISpVoice> voice;
  HRESULT hr = ::CoCreateInstance(__uuidof(SpVoice), nullptr, CLSCTX_ALL,
                                  IID_PPV_ARGS(voice.Put()));
  if (hr == CO_E_NOTINITIALIZED) {
    const HRESULT com_hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (com_hr == S_OK || com_hr == S_FALSE) {
      owns_com_init_ = true;
    }
    hr = ::CoCreateInstance(__uuidof(SpVoice), nullptr, CLSCTX_ALL,
                            IID_PPV_ARGS(voice.Put()));
  }

  if (FAILED(hr) || !voice) {
    response[flutter::EncodableValue("available")] =
        flutter::EncodableValue(false);
    response[flutter::EncodableValue("engine")] = flutter::EncodableValue();
    response[flutter::EncodableValue("error")] =
        flutter::EncodableValue(FormatHResultError("Failed to create ISpVoice", hr));
    return response;
  }

  const ULONGLONG interest =
      SPFEI(SPEI_START_INPUT_STREAM) | SPFEI(SPEI_END_INPUT_STREAM);
  hr = voice->SetInterest(interest, interest);
  if (FAILED(hr)) {
    response[flutter::EncodableValue("available")] =
        flutter::EncodableValue(false);
    response[flutter::EncodableValue("engine")] = flutter::EncodableValue();
    response[flutter::EncodableValue("error")] = flutter::EncodableValue(
        FormatHResultError("ISpVoice::SetInterest failed", hr));
    return response;
  }

  if (hwnd_ != nullptr) {
    hr = voice->SetNotifyWindowMessage(hwnd_, kWmTtsEvent, 0, 0);
    if (FAILED(hr)) {
      response[flutter::EncodableValue("available")] =
          flutter::EncodableValue(false);
      response[flutter::EncodableValue("engine")] = flutter::EncodableValue();
      response[flutter::EncodableValue("error")] = flutter::EncodableValue(
          FormatHResultError("ISpVoice::SetNotifyWindowMessage failed", hr));
      return response;
    }
  }

  voice_ = std::move(voice);
  ApplyRateToVoice();

  response[flutter::EncodableValue("available")] =
      flutter::EncodableValue(true);
  response[flutter::EncodableValue("engine")] =
      flutter::EncodableValue(std::string(kEngineId));
  response[flutter::EncodableValue("error")] = flutter::EncodableValue();
  return response;
}

std::vector<TtsChannelHandler::VoiceEntry> TtsChannelHandler::CollectVoices() {
  voice_tokens_.clear();

  std::vector<VoiceEntry> voices;
  std::unordered_map<std::wstring, bool> seen_ids;

  EnumerateCategory(SPCAT_VOICES, voices, seen_ids);
  EnumerateCategory(kOneCoreVoicesCategory, voices, seen_ids);

  std::sort(voices.begin(), voices.end(),
            [](const VoiceEntry& a, const VoiceEntry& b) {
              const bool a_zh = IsZhLocale(a.locale);
              const bool b_zh = IsZhLocale(b.locale);
              if (a_zh != b_zh) {
                return a_zh;
              }
              if (a.locale != b.locale) {
                return a.locale < b.locale;
              }
              if (a.name != b.name) {
                return a.name < b.name;
              }
              return a.id < b.id;
            });

  return voices;
}

void TtsChannelHandler::EnumerateCategory(
    const wchar_t* category_id,
    std::vector<VoiceEntry>& voices,
    std::unordered_map<std::wstring, bool>& seen_ids) {
  detail::ComPtr<ISpObjectTokenCategory> category;
  HRESULT hr = ::CoCreateInstance(__uuidof(SpObjectTokenCategory), nullptr,
                                  CLSCTX_ALL, IID_PPV_ARGS(category.Put()));
  if (FAILED(hr) || !category) {
    return;
  }

  hr = category->SetId(category_id, FALSE);
  if (FAILED(hr)) {
    return;
  }

  detail::ComPtr<IEnumSpObjectTokens> enum_tokens;
  hr = category->EnumTokens(nullptr, nullptr, enum_tokens.Put());
  if (FAILED(hr) || !enum_tokens) {
    return;
  }

  detail::ComPtr<ISpObjectToken> token;
  ULONG fetched = 0;
  while (enum_tokens->Next(1, token.Put(), &fetched) == S_OK && fetched == 1) {
    fetched = 0;
    if (!token) {
      continue;
    }

    LPWSTR raw_id = nullptr;
    if (FAILED(token->GetId(&raw_id)) || raw_id == nullptr) {
      continue;
    }
    std::wstring token_id(raw_id);
    ::CoTaskMemFree(raw_id);

    if (token_id.empty()) {
      continue;
    }

    const std::wstring dedup_key = ToLowerAscii(token_id);
    if (!seen_ids.emplace(dedup_key, true).second) {
      continue;
    }

    voice_tokens_[token_id] = token;

    std::wstring voice_name;
    LPWSTR raw_desc = nullptr;
    if (SUCCEEDED(token->GetStringValue(nullptr, &raw_desc)) &&
        raw_desc != nullptr) {
      voice_name.assign(raw_desc);
      ::CoTaskMemFree(raw_desc);
    }
    if (voice_name.empty()) {
      voice_name = token_id;
    }

    std::string locale;
    detail::ComPtr<ISpDataKey> attr_key;
    if (SUCCEEDED(token->OpenKey(L"Attributes", attr_key.Put())) && attr_key) {
      LPWSTR raw_lang = nullptr;
      if (SUCCEEDED(attr_key->GetStringValue(L"Language", &raw_lang)) &&
          raw_lang != nullptr) {
        wchar_t* end_ptr = nullptr;
        const unsigned long lcid_val = std::wcstoul(raw_lang, &end_ptr, 16);
        const bool parsed = (end_ptr != raw_lang && lcid_val != 0);
        ::CoTaskMemFree(raw_lang);

        if (parsed) {
          wchar_t locale_name[LOCALE_NAME_MAX_LENGTH] = {};
          const int written = ::LCIDToLocaleName(
              static_cast<LCID>(lcid_val), locale_name,
              LOCALE_NAME_MAX_LENGTH, 0);
          if (written > 0) {
            locale = Utf8FromUtf16(locale_name);
          }
        }
      }
    }

    voices.push_back(VoiceEntry{
        Utf8FromUtf16(token_id.c_str()),
        Utf8FromUtf16(voice_name.c_str()),
        std::move(locale),
    });
  }
}

bool TtsChannelHandler::SetVoiceById(const std::string& voice_id) {
  if (!voice_) {
    return false;
  }

  const std::wstring wide_id = Utf16FromUtf8(voice_id);
  if (wide_id.empty()) {
    return false;
  }

  detail::ComPtr<ISpObjectToken> token;
  HRESULT hr = ::CoCreateInstance(__uuidof(SpObjectToken), nullptr, CLSCTX_ALL,
                                  IID_PPV_ARGS(token.Put()));
  if (SUCCEEDED(hr) && token) {
    hr = token->SetId(nullptr, wide_id.c_str(), FALSE);
    if (SUCCEEDED(hr) && SUCCEEDED(voice_->SetVoice(token.Get()))) {
      return true;
    }
  }

  if (voice_tokens_.empty()) {
    CollectVoices();
  }

  const auto exact = voice_tokens_.find(wide_id);
  if (exact != voice_tokens_.end() && exact->second) {
    if (SUCCEEDED(voice_->SetVoice(exact->second.Get()))) {
      return true;
    }
  }

  const std::wstring target_lower = ToLowerAscii(wide_id);
  for (const auto& pair : voice_tokens_) {
    if (ToLowerAscii(pair.first) == target_lower && pair.second) {
      if (SUCCEEDED(voice_->SetVoice(pair.second.Get()))) {
        return true;
      }
    }
  }

  return false;
}

void TtsChannelHandler::SetSpeechRate(double rate) {
  if (!std::isfinite(rate)) {
    rate = 1.0;
  }
  speech_rate_ = std::clamp(rate, 0.5, 2.5);
  ApplyRateToVoice();
}

void TtsChannelHandler::ApplyRateToVoice() {
  if (!voice_) {
    return;
  }
  double mapped = 0.0;
  if (speech_rate_ <= 1.0) {
    mapped = (speech_rate_ - 1.0) / 0.5 * 10.0;
  } else {
    mapped = (speech_rate_ - 1.0) / 1.5 * 10.0;
  }
  const long rate_adjust =
      std::clamp(static_cast<long>(std::lround(mapped)), -10L, 10L);
  voice_->SetRate(rate_adjust);
}

void TtsChannelHandler::SetPitch(double pitch) {
  if (!std::isfinite(pitch)) {
    pitch = 1.0;
  }
  pitch_ = std::clamp(pitch, 0.5, 2.0);
}

std::wstring TtsChannelHandler::BuildSpeakPayload(
    const std::wstring& wide_text, DWORD* out_flags) const {
  if (std::fabs(pitch_ - 1.0) <= 0.02) {
    *out_flags = SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML;
    return wide_text;
  }

  double mapped = 0.0;
  if (pitch_ <= 1.0) {
    mapped = (pitch_ - 1.0) / 0.5 * 10.0;
  } else {
    mapped = (pitch_ - 1.0) / 1.0 * 10.0;
  }
  const long pitch_adjust =
      std::clamp(static_cast<long>(std::lround(mapped)), -10L, 10L);

  *out_flags = SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_XML;
  return L"<pitch absmiddle=\"" + std::to_wstring(pitch_adjust) + L"\">" +
         EscapeXmlText(wide_text) + L"</pitch>";
}

bool TtsChannelHandler::SpeakText(const std::string& text,
                                  const std::string& utterance_id) {
  if (!voice_) {
    return false;
  }

  const std::wstring wide_text = Utf16FromUtf8(text);
  if (wide_text.empty()) {
    return false;
  }

  DWORD flags = 0;
  const std::wstring payload = BuildSpeakPayload(wide_text, &flags);

  // Clear active state before Speak so any stale events pumped during purge
  // cannot match the previous utterance.
  active_utterance_id_.clear();
  active_stream_num_ = 0;

  ULONG stream_num = 0;
  const HRESULT hr = voice_->Speak(payload.c_str(), flags, &stream_num);
  if (FAILED(hr)) {
    is_stopped_ = true;
    return false;
  }

  is_stopped_ = false;
  active_utterance_id_ = utterance_id;
  active_stream_num_ = stream_num;
  return true;
}

void TtsChannelHandler::StopSpeech() {
  is_stopped_ = true;
  active_utterance_id_.clear();
  active_stream_num_ = 0;
  if (voice_) {
    voice_->Speak(nullptr, SPF_ASYNC | SPF_PURGEBEFORESPEAK, nullptr);
  }
}

void TtsChannelHandler::ProcessSapiEvents() {
  if (!voice_) {
    return;
  }

  SPEVENT ev{};
  ULONG fetched = 0;
  while (voice_ && SUCCEEDED(voice_->GetEvents(1, &ev, &fetched)) &&
         fetched == 1) {
    const SPEVENTENUM event_id = ev.eEventId;
    const ULONG stream_num = ev.ulStreamNum;
    ClearSpEvent(ev);
    fetched = 0;

    if (is_stopped_ || active_utterance_id_.empty() ||
        stream_num != active_stream_num_) {
      continue;
    }

    if (event_id == SPEI_START_INPUT_STREAM) {
      EmitSpeechEvent("start", active_utterance_id_);
    } else if (event_id == SPEI_END_INPUT_STREAM) {
      std::string completed_id = std::move(active_utterance_id_);
      active_utterance_id_.clear();
      active_stream_num_ = 0;
      EmitSpeechEvent("complete", completed_id);
    }
  }
}

void TtsChannelHandler::EmitSpeechEvent(const char* type,
                                        const std::string& utterance_id) {
  if (!event_sink_) {
    return;
  }
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("type")] =
      flutter::EncodableValue(std::string(type));
  payload[flutter::EncodableValue("utteranceId")] =
      flutter::EncodableValue(utterance_id);
  event_sink_->Success(flutter::EncodableValue(std::move(payload)));
}
