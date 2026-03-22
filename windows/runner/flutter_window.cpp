#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <codecvt>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kPlatformChannelName[] = "input_app/platform";
HHOOK g_keyboard_hook = nullptr;
FlutterWindow* g_active_window = nullptr;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                        0);
  std::wstring wide(size_needed, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide.data(), size_needed);
  if (!wide.empty()) {
    wide.pop_back();
  }
  return wide;
}

void SendVirtualKey(WORD key_code, DWORD flags = 0) {
  INPUT input{};
  input.type = INPUT_KEYBOARD;
  input.ki.wVk = key_code;
  input.ki.dwFlags = flags;
  SendInput(1, &input, sizeof(INPUT));
}

void SendUnicodeText(const std::wstring& text) {
  std::vector<INPUT> inputs;
  inputs.reserve(text.size() * 2);
  for (wchar_t ch : text) {
    INPUT down{};
    down.type = INPUT_KEYBOARD;
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    down.ki.wScan = ch;
    inputs.push_back(down);

    INPUT up = down;
    up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    inputs.push_back(up);
  }
  if (!inputs.empty()) {
    SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
  }
}

void AppendNativeLog(const std::string& message) {
  std::ofstream stream("C:\\dev\\input_app_flutter\\windows_runner.log",
                       std::ios::app);
  if (!stream.is_open()) {
    return;
  }
  stream << message << std::endl;
}

LRESULT CALLBACK LowLevelKeyboardProc(int code,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  if (code == HC_ACTION && g_active_window != nullptr) {
    const auto* keyboard_info =
        reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    g_active_window->HandleKeyboardEvent(wparam, keyboard_info);
  }
  return CallNextHookEx(g_keyboard_hook, code, wparam, lparam);
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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  SetUpPlatformChannel();
  InstallKeyboardHook();
  AppendNativeLog("runner:on_create");

  flutter_controller_->engine()->SetNextFrameCallback([&]() {});

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  AppendNativeLog("runner:on_destroy");
  RemoveKeyboardHook();
  platform_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetUpPlatformChannel() {
  platform_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kPlatformChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  platform_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();

        if (method == "configureHotkeys") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("bad_args", "Expected a map of hotkey values.");
            return;
          }

          std::string error_message;
          if (!ConfigureHotkeys(*arguments, &error_message)) {
            AppendNativeLog("runner:configure_hotkeys:error:" + error_message);
            result->Error("hotkey_registration_failed", error_message);
            return;
          }
          AppendNativeLog("runner:configure_hotkeys:ok");
          result->Success(flutter::EncodableValue(true));
          return;
        }

        if (method == "pasteClipboardShortcut") {
          result->Success(flutter::EncodableValue(PasteClipboardShortcut()));
          return;
        }

        if (method == "typeText") {
          const auto* text =
              std::get_if<std::string>(call.arguments());
          if (text == nullptr) {
            result->Error("bad_args", "Expected text.");
            return;
          }
          result->Success(flutter::EncodableValue(TypeText(*text)));
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::InvokeHotkeyEvent(const std::string& kind,
                                      const std::string& action) {
  if (!platform_channel_) {
    return;
  }
  AppendNativeLog("runner:event:" + kind + ":" + action);

  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("kind")] = flutter::EncodableValue(kind);
  payload[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  platform_channel_->InvokeMethod("onHotkeyEvent",
                                  std::make_unique<flutter::EncodableValue>(
                                      payload));
}

bool FlutterWindow::ConfigureHotkeys(const flutter::EncodableMap& arguments,
                                     std::string* error_message) {
  auto get_string = [&arguments](const char* key) -> std::optional<std::string> {
    auto it = arguments.find(flutter::EncodableValue(key));
    if (it == arguments.end()) {
      return std::nullopt;
    }
    if (const auto* value = std::get_if<std::string>(&it->second)) {
      return *value;
    }
    return std::nullopt;
  };

  const auto original = get_string("original");
  const auto translation = get_string("translation");
  if (!original.has_value() || !translation.has_value()) {
    *error_message = "Missing original or translation hotkey.";
    return false;
  }
  if (*original == *translation) {
    *error_message = "Original and translation hotkeys must differ.";
    return false;
  }

  const auto original_virtual_key = VirtualKeyForHotkey(*original);
  const auto translation_virtual_key = VirtualKeyForHotkey(*translation);
  if (!original_virtual_key.has_value() ||
      !translation_virtual_key.has_value()) {
    *error_message = "Unsupported hotkey value.";
    return false;
  }

  key_state_.original_virtual_key = original_virtual_key;
  key_state_.translation_virtual_key = translation_virtual_key;
  key_state_.original_down = false;
  key_state_.translation_down = false;
  return true;
}

std::optional<UINT> FlutterWindow::VirtualKeyForHotkey(
    const std::string& hotkey_name) const {
  static const std::unordered_map<std::string, UINT> kHotkeys = {
      {"F1", VK_F1},       {"F2", VK_F2},       {"F3", VK_F3},
      {"F4", VK_F4},       {"F5", VK_F5},       {"F6", VK_F6},
      {"F7", VK_F7},       {"F8", VK_F8},       {"F9", VK_F9},
      {"F10", VK_F10},     {"F11", VK_F11},     {"F12", VK_F12},
      {"Space", VK_SPACE}, {"Enter", VK_RETURN}, {"Tab", VK_TAB},
  };

  const auto found = kHotkeys.find(hotkey_name);
  if (found == kHotkeys.end()) {
    return std::nullopt;
  }
  return found->second;
}

bool FlutterWindow::PasteClipboardShortcut() {
  SendVirtualKey(VK_CONTROL);
  SendVirtualKey('V');
  SendVirtualKey('V', KEYEVENTF_KEYUP);
  SendVirtualKey(VK_CONTROL, KEYEVENTF_KEYUP);
  return true;
}

bool FlutterWindow::TypeText(const std::string& text) {
  SendUnicodeText(Utf8ToWide(text));
  return true;
}

bool FlutterWindow::InstallKeyboardHook() {
  g_active_window = this;
  if (g_keyboard_hook != nullptr) {
    AppendNativeLog("runner:keyboard_hook:already_installed");
    return true;
  }

  g_keyboard_hook =
      SetWindowsHookEx(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                       GetModuleHandle(nullptr), 0);
  AppendNativeLog(g_keyboard_hook != nullptr ? "runner:keyboard_hook:installed"
                                             : "runner:keyboard_hook:failed");
  return g_keyboard_hook != nullptr;
}

void FlutterWindow::RemoveKeyboardHook() {
  if (g_keyboard_hook != nullptr) {
    AppendNativeLog("runner:keyboard_hook:removed");
    UnhookWindowsHookEx(g_keyboard_hook);
    g_keyboard_hook = nullptr;
  }
  g_active_window = nullptr;
}

void FlutterWindow::HandleKeyboardEvent(
    WPARAM wparam,
    const KBDLLHOOKSTRUCT* keyboard_info) {
  if (keyboard_info == nullptr) {
    return;
  }

  const UINT virtual_key = keyboard_info->vkCode;
  const bool is_key_down = wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
  const bool is_key_up = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;

  if (key_state_.original_virtual_key.has_value() &&
      virtual_key == key_state_.original_virtual_key.value()) {
    if (is_key_down && !key_state_.original_down) {
      key_state_.original_down = true;
      AppendNativeLog("runner:key:original:down");
      InvokeHotkeyEvent("original", "down");
    } else if (is_key_up && key_state_.original_down) {
      key_state_.original_down = false;
      AppendNativeLog("runner:key:original:up");
      InvokeHotkeyEvent("original", "up");
    }
    return;
  }

  if (key_state_.translation_virtual_key.has_value() &&
      virtual_key == key_state_.translation_virtual_key.value()) {
    if (is_key_down && !key_state_.translation_down) {
      key_state_.translation_down = true;
      AppendNativeLog("runner:key:translation:down");
      InvokeHotkeyEvent("translation", "down");
    } else if (is_key_up && key_state_.translation_down) {
      key_state_.translation_down = false;
      AppendNativeLog("runner:key:translation:up");
      InvokeHotkeyEvent("translation", "up");
    }
  }
}
