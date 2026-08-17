#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include "utils.h"

using namespace winrt::Windows::UI::Notifications;
using namespace winrt::Windows::Data::Xml::Dom;

std::wstring EscapeXml(std::wstring text) {
    size_t pos = 0;
    while ((pos = text.find(L"&", pos)) != std::wstring::npos) { text.replace(pos, 1, L"&amp;"); pos += 5; }
    pos = 0;
    while ((pos = text.find(L"<", pos)) != std::wstring::npos) { text.replace(pos, 1, L"&lt;"); pos += 4; }
    pos = 0;
    while ((pos = text.find(L">", pos)) != std::wstring::npos) { text.replace(pos, 1, L"&gt;"); pos += 4; }
    pos = 0;
    while ((pos = text.find(L"\"", pos)) != std::wstring::npos) { text.replace(pos, 1, L"&quot;"); pos += 6; }
    pos = 0;
    while ((pos = text.find(L"'", pos)) != std::wstring::npos) { text.replace(pos, 1, L"&apos;"); pos += 6; }
    return text;
}

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
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

  // Toast Notification MethodChannel
  toast_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.example.p2psyncapp/toast",
      &flutter::StandardMethodCodec::GetInstance());

  toast_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "showProgressToast") {
          auto args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto title_it = args->find(flutter::EncodableValue("title"));
            auto status_it = args->find(flutter::EncodableValue("status"));
            auto progress_it = args->find(flutter::EncodableValue("progress"));
            auto tag_it = args->find(flutter::EncodableValue("tag"));
            
            if (title_it != args->end() && status_it != args->end() && progress_it != args->end() && tag_it != args->end()) {
              std::wstring title = EscapeXml(Utf16FromUtf8(std::get<std::string>(title_it->second)));
              std::wstring status = EscapeXml(Utf16FromUtf8(std::get<std::string>(status_it->second)));
              double progress = std::get<double>(progress_it->second);
              std::wstring tag = EscapeXml(Utf16FromUtf8(std::get<std::string>(tag_it->second)));
              
              std::wstring progressString = std::to_wstring((int)(progress * 100)) + L"%";
              
              // We use <audio silent='true'/> so it doesn't chime on every progress update.
              std::wstring xmlString = 
                L"<toast><visual><binding template='ToastGeneric'>"
                L"<text>" + title + L"</text>"
                L"<progress title='Transferring' value='" + std::to_wstring(progress) + 
                L"' valueStringOverride='" + progressString + 
                L"' status='" + status + L"'/>"
                L"</binding></visual><audio silent='true'/></toast>";

              try {
                XmlDocument xml;
                xml.LoadXml(xmlString);
                ToastNotification toast(xml);
                toast.Tag(tag);
                toast.Group(L"SpDrop");
                
                ToastNotificationManager::CreateToastNotifier(L"SpDrop").Show(toast);
                result->Success(flutter::EncodableValue(true));
              } catch (...) {
                result->Error("TOAST_ERROR", "Failed to show toast");
              }
            } else {
              result->Error("INVALID_ARGUMENTS", "Missing parameters");
            }
          } else {
            result->Error("INVALID_ARGUMENTS", "Arguments must be a map");
          }
        } else if (call.method_name() == "hideToast") {
          auto args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto tag_it = args->find(flutter::EncodableValue("tag"));
            if (tag_it != args->end()) {
              std::wstring tag = Utf16FromUtf8(std::get<std::string>(tag_it->second));
              try {
                ToastNotificationManager::History().Remove(tag, L"SpDrop", L"SpDrop");
                result->Success(flutter::EncodableValue(true));
              } catch (...) {
                result->Error("TOAST_ERROR", "Failed to hide toast");
              }
            } else {
              result->Error("INVALID_ARGUMENTS", "Missing tag");
            }
          }
        } else {
          result->NotImplemented();
        }
      });

  // Only auto-show window on first frame if NOT in tray mode.
  // In --tray mode, the window stays hidden until the user clicks the tray
  // icon.
  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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
