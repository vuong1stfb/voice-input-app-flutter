#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <optional>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();
  void HandleKeyboardEvent(WPARAM wparam, const KBDLLHOOKSTRUCT* keyboard_info);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  struct KeyState {
    std::optional<UINT> original_virtual_key;
    std::optional<UINT> translation_virtual_key;
    bool original_down = false;
    bool translation_down = false;
  };

  void SetUpPlatformChannel();
  void InvokeHotkeyEvent(const std::string& kind, const std::string& action);
  bool ConfigureHotkeys(const flutter::EncodableMap& arguments,
                        std::string* error_message);
  std::optional<UINT> VirtualKeyForHotkey(
      const std::string& hotkey_name) const;
  bool PasteClipboardShortcut();
  bool TypeText(const std::string& text);
  bool InstallKeyboardHook();
  void RemoveKeyboardHook();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      platform_channel_;
  KeyState key_state_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
