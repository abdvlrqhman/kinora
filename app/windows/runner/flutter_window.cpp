#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "kinora/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* on = std::get_if<bool>(call.arguments());
        if (call.method_name() != "setFullScreen" || on == nullptr) {
          result->NotImplemented();
          return;
        }
        SetFullScreen(*on);
        result->Success();
      });

  // Kinora shows the window itself (window_manager's waitUntilReadyToShow),
  // once its own title bar replaced the system one.

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

// The usual Win32 full screen: no frame or caption (so the taskbar steps
// aside), the whole monitor, then back to where the window was. The resize
// reaches the Flutter view through WM_SIZE like any other.
void FlutterWindow::SetFullScreen(bool on) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || on == full_screen_) return;
  full_screen_ = on;
  if (on) {
    style_before_full_screen_ = ::GetWindowLongPtr(hwnd, GWL_STYLE);
    placement_before_full_screen_.length = sizeof(WINDOWPLACEMENT);
    ::GetWindowPlacement(hwnd, &placement_before_full_screen_);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    ::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor);
    // (Not "maximized" either: its frame insets would leave a border.)
    ::SetWindowLongPtr(hwnd, GWL_STYLE,
                       style_before_full_screen_ & ~(WS_OVERLAPPEDWINDOW | WS_MAXIMIZE));
    const RECT& r = monitor.rcMonitor;
    ::SetWindowPos(hwnd, HWND_TOP, r.left, r.top, r.right - r.left, r.bottom - r.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    ::SetWindowLongPtr(hwnd, GWL_STYLE, style_before_full_screen_);
    ::SetWindowPlacement(hwnd, &placement_before_full_screen_);
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                       SWP_FRAMECHANGED);
  }
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
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
