#include "flutter_window.h"

#include <commdlg.h>
#include <flutter/standard_method_codec.h>

#include <cwchar>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

constexpr char kPlatformChannelName[] = "com.pureread.app/platform";

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int input_length = static_cast<int>(utf8.size());
  const int target_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), input_length, nullptr, 0);
  if (target_length <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(target_length), L'\0');
  const int converted = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), input_length, result.data(),
      target_length);
  if (converted <= 0) {
    return std::wstring();
  }
  return result;
}

std::wstring BuildOpenFileFilter(const std::vector<std::wstring>& extensions) {
  std::wstring filter;
  if (!extensions.empty()) {
    std::wstring patterns;
    for (size_t i = 0; i < extensions.size(); ++i) {
      if (i > 0) {
        patterns.push_back(L';');
      }
      patterns.append(L"*.");
      patterns.append(extensions[i]);
    }
    std::wstring label = L"Supported Files (";
    label.append(patterns);
    label.push_back(L')');

    filter.append(label);
    filter.push_back(L'\0');
    filter.append(patterns);
    filter.push_back(L'\0');
  }

  filter.append(L"All Files (*.*)");
  filter.push_back(L'\0');
  filter.append(L"*.*");
  filter.push_back(L'\0');
  filter.push_back(L'\0');
  return filter;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupPlatformChannel();
  tts_channel_handler_ = std::make_unique<TtsChannelHandler>(
      flutter_controller_->engine()->messenger(), GetHandle());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (tts_channel_handler_) {
    tts_channel_handler_->Shutdown();
    tts_channel_handler_.reset();
  }
  if (platform_channel_) {
    platform_channel_->SetMethodCallHandler(nullptr);
    platform_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetupPlatformChannel() {
  platform_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kPlatformChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  platform_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandlePlatformCall(call, std::move(result));
      });
}

void FlutterWindow::HandlePlatformCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "pickFiles") {
    HandlePickFiles(call.arguments(), std::move(result));
    return;
  }

  if (method == "setImmersiveMode") {
    bool enabled = false;
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      const auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        if (const auto* val = std::get_if<bool>(&it->second)) {
          enabled = *val;
        }
      }
    }
    SetImmersiveMode(enabled);
    result->Success();
    return;
  }

  if (method == "bossKeyHide") {
    BossKeyHide();
    result->Success();
    return;
  }

  if (method == "setKeepScreenOn") {
    bool enabled = false;
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      const auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        if (const auto* val = std::get_if<bool>(&it->second)) {
          enabled = *val;
        }
      }
    }
    ::SetThreadExecutionState(
        enabled ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED) : ES_CONTINUOUS);
    result->Success();
    return;
  }

  if (method == "setVolumeKeyPaging") {
    // Hardware volume-key paging is Android-only; succeed as no-op on Windows.
    result->Success();
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::HandlePickFiles(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  bool allow_multiple = false;
  std::vector<std::wstring> extensions;

  if (const auto* args = std::get_if<flutter::EncodableMap>(arguments)) {
    const auto mult_it = args->find(flutter::EncodableValue("allowMultiple"));
    if (mult_it != args->end()) {
      if (const auto* mult_val = std::get_if<bool>(&mult_it->second)) {
        allow_multiple = *mult_val;
      }
    }
    const auto ext_it = args->find(flutter::EncodableValue("extensions"));
    if (ext_it != args->end()) {
      if (const auto* ext_list =
              std::get_if<flutter::EncodableList>(&ext_it->second)) {
        for (const auto& item : *ext_list) {
          if (const auto* ext_str = std::get_if<std::string>(&item)) {
            std::wstring wide_ext = Utf16FromUtf8(*ext_str);
            if (!wide_ext.empty()) {
              extensions.push_back(std::move(wide_ext));
            }
          }
        }
      }
    }
  }

  const std::wstring filter = BuildOpenFileFilter(extensions);
  std::vector<wchar_t> file_buffer(65536, L'\0');

  OPENFILENAMEW ofn{};
  ofn.lStructSize = sizeof(ofn);
  ofn.hwndOwner = GetHandle();
  ofn.lpstrFilter = filter.c_str();
  ofn.nFilterIndex = 1;
  ofn.lpstrFile = file_buffer.data();
  ofn.nMaxFile = static_cast<DWORD>(file_buffer.size());
  ofn.Flags =
      OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
  if (allow_multiple) {
    ofn.Flags |= OFN_ALLOWMULTISELECT;
  }

  if (::GetOpenFileNameW(&ofn)) {
    flutter::EncodableList selected_paths;
    const wchar_t* cursor = file_buffer.data();
    const size_t first_len = wcslen(cursor);
    if (first_len > 0) {
      const wchar_t* next = cursor + first_len + 1;
      if (*next == L'\0') {
        selected_paths.push_back(
            flutter::EncodableValue(Utf8FromUtf16(cursor)));
      } else {
        std::wstring directory(cursor);
        if (!directory.empty() && directory.back() != L'\\') {
          directory.push_back(L'\\');
        }
        while (*next != L'\0') {
          const std::wstring full_path = directory + next;
          selected_paths.push_back(
              flutter::EncodableValue(Utf8FromUtf16(full_path.c_str())));
          next += wcslen(next) + 1;
        }
      }
    }
    result->Success(flutter::EncodableValue(std::move(selected_paths)));
    return;
  }

  const DWORD dialog_error = ::CommDlgExtendedError();
  if (dialog_error == 0) {
    // User cancelled dialog.
    result->Success(flutter::EncodableValue(flutter::EncodableList{}));
    return;
  }

  result->Error("PICK_FILES_FAILED",
                "Win32 GetOpenFileNameW failed with extended error code.");
}

void FlutterWindow::SetImmersiveMode(bool enabled) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  if (enabled && !is_fullscreen_) {
    saved_style_ = ::GetWindowLongPtrW(hwnd, GWL_STYLE);
    saved_window_placement_.length = sizeof(saved_window_placement_);
    ::GetWindowPlacement(hwnd, &saved_window_placement_);

    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    HMONITOR monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
    if (::GetMonitorInfoW(monitor, &monitor_info)) {
      ::SetWindowLongPtrW(
          hwnd, GWL_STYLE,
          saved_style_ & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW));
      ::SetWindowPos(
          hwnd, HWND_TOP, monitor_info.rcMonitor.left,
          monitor_info.rcMonitor.top,
          monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
          monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
          SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
      is_fullscreen_ = true;
    }
  } else if (!enabled && is_fullscreen_) {
    ::SetWindowLongPtrW(hwnd, GWL_STYLE, saved_style_);
    ::SetWindowPlacement(hwnd, &saved_window_placement_);
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                       SWP_FRAMECHANGED);
    is_fullscreen_ = false;
  }
}

void FlutterWindow::BossKeyHide() {
  HWND hwnd = GetHandle();
  if (hwnd) {
    ::ShowWindow(hwnd, SW_MINIMIZE);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case TtsChannelHandler::kWmTtsEvent:
      if (tts_channel_handler_) {
        tts_channel_handler_->ProcessSapiEvents();
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
