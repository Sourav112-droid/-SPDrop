#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// Add C++/WinRT headers for ShareTarget activation
#include <winrt/Windows.ApplicationModel.Activation.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.ShareTarget.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.h>

using namespace winrt;
using namespace Windows::ApplicationModel::Activation;
using namespace Windows::ApplicationModel::DataTransfer::ShareTarget;
using namespace Windows::Storage;

// Check if --tray argument is present in command line
static bool HasTrayFlag(const std::vector<std::string> &args) {
  return std::find(args.begin(), args.end(), "--tray") != args.end();
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  winrt::init_apartment();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  // Check for ShareTarget activation
  try {
    auto args = Windows::ApplicationModel::AppInstance::GetActivatedEventArgs();
    if (args != nullptr && args.Kind() == ActivationKind::ShareTarget) {
      auto shareArgs = args.as<ShareTargetActivatedEventArgs>();
      auto shareOperation = shareArgs.ShareOperation();
      auto data = shareOperation.Data();

      // Create a staging directory so files survive after ReportCompleted().
      // Windows may delete sandbox paths once the share operation completes.
      wchar_t tempPath[MAX_PATH];
      GetTempPathW(MAX_PATH, tempPath);
      std::wstring stagingDir = std::wstring(tempPath) + L"SpDrop_Share\\";
      CreateDirectoryW(stagingDir.c_str(), NULL);

      if (data.Contains(winrt::Windows::ApplicationModel::DataTransfer::
                            StandardDataFormats::StorageItems())) {
        auto items = data.GetStorageItemsAsync().get();
        auto stagingFolder =
            winrt::Windows::Storage::StorageFolder::GetFolderFromPathAsync(
                winrt::hstring(stagingDir))
                .get();

        for (auto const &item : items) {
          try {
            // Copy each shared file into our staging directory
            auto storageFile = item.as<StorageFile>();
            auto copied =
                storageFile
                    .CopyAsync(stagingFolder, storageFile.Name(),
                               winrt::Windows::Storage::NameCollisionOption::
                                   GenerateUniqueName)
                    .get();

            std::wstring path = copied.Path().c_str();
            int size_needed = WideCharToMultiByte(CP_UTF8, 0, path.c_str(), -1,
                                                  NULL, 0, NULL, NULL);
            if (size_needed > 0) {
              std::string utf8_path(size_needed - 1, '\0');
              WideCharToMultiByte(CP_UTF8, 0, path.c_str(), -1, &utf8_path[0],
                                  size_needed, NULL, NULL);
              command_line_arguments.push_back("--share-file=" + utf8_path);
            }
          } catch (...) {
            // If copy fails for one file, try the rest
          }
        }
      }
      // Support text/URI clipboard content in Share (fallback)
      else if (data.Contains(winrt::Windows::ApplicationModel::DataTransfer::
                                 StandardDataFormats::Text())) {
        auto text = data.GetTextAsync().get();
        std::wstring text_str = text.c_str();
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, text_str.c_str(), -1,
                                              NULL, 0, NULL, NULL);
        if (size_needed > 0) {
          std::string utf8_text(size_needed - 1, '\0');
          WideCharToMultiByte(CP_UTF8, 0, text_str.c_str(), -1, &utf8_text[0],
                              size_needed, NULL, NULL);
          command_line_arguments.push_back("--text-share=" + utf8_text);
        }
      }

      // Mark this as a share-target activation so Dart handles it differently
      command_line_arguments.push_back("--share-target");
      // Force app to stay hidden during ShareTarget process delivery
      command_line_arguments.push_back("--tray");

      // Complete the share operation so Windows closes its dialog
      shareOperation.ReportCompleted();
    }
  } catch (...) {
    // Ignore WinRT exceptions if run as a standard Win32 app without identity
  }

  // Detect --tray mode before passing args to Dart
  bool start_in_tray = HasTrayFlag(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Tell the window to suppress auto-show when starting in tray mode
  window.SetStartHidden(start_in_tray);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SpDrop", origin, size)) {
    return EXIT_FAILURE;
  }

  // Don't set quit_on_close = true.
  // The window_manager Flutter plugin needs to intercept WM_CLOSE via
  // setPreventClose(true) to minimize to system tray instead of quitting.
  // Setting quit_on_close = true here caused a race condition where the
  // C++ side would PostQuitMessage(0) before window_manager could intercept.
  // Instead, the Dart side handles quit via windowManager.destroy() when
  // the user explicitly clicks "Quit" from the tray menu.
  window.SetQuitOnClose(false);

  // If --tray flag is present, start hidden (window was created but
  // not yet shown). The system tray icon will be initialized by Flutter.
  // If NOT in tray mode, show window normally.
  if (!start_in_tray) {
    window.Show();
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
