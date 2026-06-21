#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include <algorithm>
#include <fstream>
#include <iostream>

#include "audio_manager.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutex[] =
    L"Global\\BluetoothAudioManager-63FD2C0E-4DC9-4F75-9D11-DB40835623A8";
constexpr wchar_t kActivateMessage[] =
    L"com.xhosa.bluetooth_audio_manager.activate";

void ActivateExistingInstance() {
  const UINT message = RegisterWindowMessageW(kActivateMessage);
  if (message == 0) return;
  // The first instance may still be creating its window. Repeating briefly
  // avoids losing the activation request during that startup window.
  for (int attempt = 0; attempt < 20; ++attempt) {
    PostMessageW(HWND_BROADCAST, message, 0, 0);
    Sleep(50);
  }
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

int RunDiagnostics(const std::string& output_path) {
  std::ofstream file;
  if (!output_path.empty()) file.open(output_path, std::ios::trunc);
  std::ostream& output = file.is_open() ? file : std::cout;
  try {
    AudioManager manager;
    const auto devices = manager.ListDevices();
    output << manager.Diagnostics();
    output << "compatibleDevices=" << devices.size() << "\n";
    for (const auto& device : devices) {
      const auto status = manager.GetStatus(device.id);
      output << "name=" << WideToUtf8(device.name) << "\n"
             << "id=" << WideToUtf8(device.id) << "\n"
             << "connected=" << (status.connected ? "true" : "false")
             << "\nmode=" << status.mode
             << "\nmicrophoneEnabled="
             << (status.microphone_enabled ? "true" : "false")
             << "\nhfpActive=" << (status.hfp_active ? "true" : "false")
             << "\na2dpIsDefault="
             << (status.a2dp_is_default ? "true" : "false")
             << "\nhfpRenderIsDefault="
             << (status.hfp_render_is_default ? "true" : "false")
             << "\nhfpCaptureIsDefault="
             << (status.hfp_capture_is_default ? "true" : "false") << "\n";
    }
    return EXIT_SUCCESS;
  } catch (const std::exception& error) {
    std::cerr << "diagnosticsError=" << error.what() << "\n";
    return EXIT_FAILURE;
  }
}

int RunModeSwitch(const std::string& mode, const std::string& output_path) {
  std::ofstream file;
  if (!output_path.empty()) file.open(output_path, std::ios::trunc);
  std::ostream& output = file.is_open() ? file : std::cout;
  try {
    AudioManager manager;
    const auto devices = manager.ListDevices();
    const auto selected = std::find_if(
        devices.begin(), devices.end(),
        [](const auto& device) { return device.connected; });
    if (selected == devices.end()) {
      throw std::runtime_error("No connected compatible headset.");
    }
    const auto status = manager.SetMode(selected->id, mode);
    output << "name=" << WideToUtf8(selected->name) << "\n"
           << "requestedMode=" << mode << "\n"
           << "actualMode=" << status.mode << "\n";
    return status.mode == mode ? EXIT_SUCCESS : EXIT_FAILURE;
  } catch (const std::exception& error) {
    output << "switchError=" << error.what() << "\n";
    return EXIT_FAILURE;
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const auto diagnostics = std::find(command_line_arguments.begin(),
                                     command_line_arguments.end(),
                                     "--diagnostics");
  const auto diagnostics_file = std::find(command_line_arguments.begin(),
                                          command_line_arguments.end(),
                                          "--diagnostics-file");
  const auto switch_mode = std::find(command_line_arguments.begin(),
                                     command_line_arguments.end(),
                                     "--switch-mode");
  if (switch_mode != command_line_arguments.end() &&
      std::next(switch_mode) != command_line_arguments.end()) {
    std::string path;
    if (diagnostics_file != command_line_arguments.end() &&
        std::next(diagnostics_file) != command_line_arguments.end()) {
      path = *std::next(diagnostics_file);
    }
    const int result = RunModeSwitch(*std::next(switch_mode), path);
    ::CoUninitialize();
    return result;
  }
  if (diagnostics != command_line_arguments.end() ||
      diagnostics_file != command_line_arguments.end()) {
    std::string path;
    if (diagnostics_file != command_line_arguments.end() &&
        std::next(diagnostics_file) != command_line_arguments.end()) {
      path = *std::next(diagnostics_file);
    }
    const int result = RunDiagnostics(path);
    ::CoUninitialize();
    return result;
  }

  // Give the taskbar a stable identity that is independent from stale pinned
  // shortcuts and their cached icons.
  SetCurrentProcessExplicitAppUserModelID(
      L"Xhosa.BluetoothAudioManager.Desktop.v2");

  HANDLE single_instance =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutex);
  const DWORD mutex_error = GetLastError();
  if ((single_instance && mutex_error == ERROR_ALREADY_EXISTS) ||
      (!single_instance && mutex_error == ERROR_ACCESS_DENIED)) {
    if (single_instance) CloseHandle(single_instance);
    ActivateExistingInstance();
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }
  if (!single_instance) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"bluetooth_audio_manager", origin, size)) {
    CloseHandle(single_instance);
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
