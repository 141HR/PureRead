#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that hosts a Flutter view and PureRead's native Win32 platform channel.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetupPlatformChannel();
  void HandlePlatformCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandlePickFiles(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetImmersiveMode(bool enabled);
  void BossKeyHide();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Zero-plugin platform bridge channel.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      platform_channel_;

  // Fullscreen restore state.
  bool is_fullscreen_ = false;
  LONG_PTR saved_style_ = 0;
  WINDOWPLACEMENT saved_window_placement_{sizeof(WINDOWPLACEMENT)};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
