#ifndef RUNNER_TTS_CHANNEL_HANDLER_H_
#define RUNNER_TTS_CHANNEL_HANDLER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <windows.h>
#include <objbase.h>
#include <sapi.h>

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace detail {

// Minimal RAII wrapper for COM interface pointers without ATL dependency.
template <typename T>
class ComPtr {
 public:
  ComPtr() noexcept = default;

  ComPtr(const ComPtr& other) noexcept : ptr_(other.ptr_) {
    if (ptr_) {
      ptr_->AddRef();
    }
  }

  ComPtr(ComPtr&& other) noexcept : ptr_(other.ptr_) {
    other.ptr_ = nullptr;
  }

  ~ComPtr() { Reset(); }

  ComPtr& operator=(const ComPtr& other) noexcept {
    if (this != &other) {
      ComPtr(other).Swap(*this);
    }
    return *this;
  }

  ComPtr& operator=(ComPtr&& other) noexcept {
    if (this != &other) {
      ComPtr(std::move(other)).Swap(*this);
    }
    return *this;
  }

  void Swap(ComPtr& other) noexcept {
    T* tmp = ptr_;
    ptr_ = other.ptr_;
    other.ptr_ = tmp;
  }

  void Reset() noexcept {
    T* tmp = ptr_;
    ptr_ = nullptr;
    if (tmp) {
      tmp->Release();
    }
  }

  T* Get() const noexcept { return ptr_; }
  T* operator->() const noexcept { return ptr_; }
  explicit operator bool() const noexcept { return ptr_ != nullptr; }

  T** Put() noexcept {
    Reset();
    return &ptr_;
  }

 private:
  T* ptr_ = nullptr;
};

}  // namespace detail

// Bridges Flutter MethodChannel/EventChannel calls for PureRead TTS to
// Windows SAPI 5 and OneCore system voices using pure Win32 COM.
class TtsChannelHandler {
 public:
  static constexpr UINT kWmTtsEvent = WM_APP + 0x51;

  TtsChannelHandler(flutter::BinaryMessenger* messenger, HWND hwnd);
  ~TtsChannelHandler();

  TtsChannelHandler(const TtsChannelHandler&) = delete;
  TtsChannelHandler& operator=(const TtsChannelHandler&) = delete;

  // Drains queued SAPI events posted via kWmTtsEvent on the Win32 UI thread.
  void ProcessSapiEvents();

  // Stops active speech, detaches channel handlers, and releases COM objects.
  void Shutdown();

 private:
  struct VoiceEntry {
    std::string id;
    std::string name;
    std::string locale;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::EncodableMap InitializeVoice();
  std::vector<VoiceEntry> CollectVoices();
  void EnumerateCategory(const wchar_t* category_id,
                         std::vector<VoiceEntry>& voices,
                         std::unordered_map<std::wstring, bool>& seen_ids);
  bool SetVoiceById(const std::string& voice_id);
  void SetSpeechRate(double rate);
  void SetPitch(double pitch);
  bool SpeakText(const std::string& text, const std::string& utterance_id);
  void StopSpeech();
  void ReleaseVoiceResources();

  void ApplyRateToVoice();
  std::wstring BuildSpeakPayload(const std::wstring& wide_text,
                                 DWORD* out_flags) const;
  void EmitSpeechEvent(const char* type, const std::string& utterance_id);

  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  detail::ComPtr<ISpVoice> voice_;
  std::unordered_map<std::wstring, detail::ComPtr<ISpObjectToken>>
      voice_tokens_;

  bool owns_com_init_ = false;
  bool is_stopped_ = true;
  double speech_rate_ = 1.0;
  double pitch_ = 1.0;
  std::string active_utterance_id_;
  ULONG active_stream_num_ = 0;
};

#endif  // RUNNER_TTS_CHANNEL_HANDLER_H_
