#include "flutter_window.h"

#include <optional>
#include <stdexcept>

#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>
#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kAudioStatusChangedMessage = WM_APP + 0x42;

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

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

flutter::EncodableMap EncodeDevice(const BluetoothAudioDeviceNative& device) {
  return {
      {flutter::EncodableValue("id"),
       flutter::EncodableValue(WideToUtf8(device.id))},
      {flutter::EncodableValue("name"),
       flutter::EncodableValue(WideToUtf8(device.name))},
      {flutter::EncodableValue("connected"),
       flutter::EncodableValue(device.connected)},
      {flutter::EncodableValue("a2dpEndpointId"),
       flutter::EncodableValue(WideToUtf8(device.a2dp_endpoint_id))},
      {flutter::EncodableValue("hfpRenderEndpointId"),
       flutter::EncodableValue(WideToUtf8(device.hfp_render_endpoint_id))},
      {flutter::EncodableValue("hfpCaptureEndpointId"),
       flutter::EncodableValue(WideToUtf8(device.hfp_capture_endpoint_id))},
      {flutter::EncodableValue("hfpCaptureInstanceId"),
       flutter::EncodableValue(WideToUtf8(device.hfp_capture_instance_id))},
  };
}

flutter::EncodableMap EncodeStatus(const BluetoothAudioStatusNative& status) {
  return {
      {flutter::EncodableValue("mode"), flutter::EncodableValue(status.mode)},
      {flutter::EncodableValue("connected"),
       flutter::EncodableValue(status.connected)},
      {flutter::EncodableValue("microphoneEnabled"),
       flutter::EncodableValue(status.microphone_enabled)},
      {flutter::EncodableValue("hfpActive"),
       flutter::EncodableValue(status.hfp_active)},
      {flutter::EncodableValue("a2dpIsDefault"),
       flutter::EncodableValue(status.a2dp_is_default)},
      {flutter::EncodableValue("hfpRenderIsDefault"),
       flutter::EncodableValue(status.hfp_render_is_default)},
      {flutter::EncodableValue("hfpCaptureIsDefault"),
       flutter::EncodableValue(status.hfp_capture_is_default)},
  };
}

std::string MapString(const flutter::EncodableValue* arguments,
                      const char* key) {
  if (!arguments) return {};
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (!map) return {};
  const auto found = map->find(flutter::EncodableValue(key));
  if (found == map->end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string{};
}

bool MapBool(const flutter::EncodableValue* arguments, const char* key) {
  if (!arguments) return false;
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (!map) return false;
  const auto found = map->find(flutter::EncodableValue(key));
  if (found == map->end()) return false;
  const auto* value = std::get_if<bool>(&found->second);
  return value && *value;
}

void SetLaunchAtStartup(bool enabled) {
  constexpr wchar_t key_path[] =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  constexpr wchar_t value_name[] = L"BluetoothAudioManager";
  HKEY key = nullptr;
  const LSTATUS open_result = RegCreateKeyExW(
      HKEY_CURRENT_USER, key_path, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key,
      nullptr);
  if (open_result != ERROR_SUCCESS) {
    throw std::runtime_error("无法打开 Windows 开机启动注册表项。");
  }
  LSTATUS result = ERROR_SUCCESS;
  if (enabled) {
    wchar_t executable[MAX_PATH] = {};
    if (!GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable))) {
      RegCloseKey(key);
      throw std::runtime_error("无法确定应用程序路径。");
    }
    const std::wstring command = L"\"" + std::wstring(executable) +
                                 L"\" --background";
    result = RegSetValueExW(
        key, value_name, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    result = RegDeleteValueW(key, value_name);
    if (result == ERROR_FILE_NOT_FOUND) result = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  if (result != ERROR_SUCCESS) {
    throw std::runtime_error("写入 Windows 开机启动设置失败。");
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  const HINSTANCE instance = GetModuleHandleW(nullptr);
  const auto large_icon = reinterpret_cast<HICON>(LoadImageW(
      instance, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON), LR_SHARED));
  const auto small_icon = reinterpret_cast<HICON>(LoadImageW(
      instance, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_SHARED));
  if (large_icon) {
    SendMessageW(GetHandle(), WM_SETICON, ICON_BIG,
                 reinterpret_cast<LPARAM>(large_icon));
  }
  if (small_icon) {
    SendMessageW(GetHandle(), WM_SETICON, ICON_SMALL,
                 reinterpret_cast<LPARAM>(small_icon));
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
  audio_manager_ = std::make_unique<AudioManager>();
  audio_session_monitor_ = std::make_unique<AudioSessionMonitor>(
      GetHandle(), kAudioStatusChangedMessage);
  audio_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.xhosa.bluetooth_audio_manager/audio",
      &flutter::StandardMethodCodec::GetInstance());
  audio_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        try {
          if (call.method_name() == "setLaunchAtStartup") {
            SetLaunchAtStartup(MapBool(call.arguments(), "enabled"));
            result->Success();
            return;
          }
          if (call.method_name() == "listDevices") {
            flutter::EncodableList list;
            for (const auto& device : audio_manager_->ListDevices()) {
              list.emplace_back(EncodeDevice(device));
            }
            result->Success(flutter::EncodableValue(list));
            return;
          }
          if (call.method_name() == "clearWatch") {
            watched_device_id_.clear();
            audio_session_monitor_->Watch(L"");
            result->Success();
            return;
          }

          const std::string id = MapString(call.arguments(), "deviceId");
          if (id.empty()) {
            result->Error("invalid_argument", "缺少蓝牙设备标识。");
            return;
          }
          if (call.method_name() == "getStatus") {
            result->Success(flutter::EncodableValue(
                EncodeStatus(audio_manager_->GetStatus(Utf8ToWide(id)))));
            return;
          }
          if (call.method_name() == "watchDevice") {
            watched_device_id_ = Utf8ToWide(id);
            const auto device = audio_manager_->GetDevice(watched_device_id_);
            audio_session_monitor_->Watch(device.hfp_capture_endpoint_id);
            result->Success();
            return;
          }
          if (call.method_name() == "setMode") {
            const std::string mode = MapString(call.arguments(), "mode");
            result->Success(flutter::EncodableValue(EncodeStatus(
                audio_manager_->SetMode(Utf8ToWide(id), mode))));
            return;
          }
          result->NotImplemented();
        } catch (const std::exception& error) {
          result->Error("windows_audio_error", error.what());
        }
      });
  status_event_channel_ = std::make_unique<
      flutter::EventChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.xhosa.bluetooth_audio_manager/audio_events",
      &flutter::StandardMethodCodec::GetInstance());
  status_event_channel_->SetStreamHandler(
      std::make_unique<
          flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<
                     flutter::EventSink<flutter::EncodableValue>>&& sink) {
            status_sink_ = std::move(sink);
            PostMessageW(GetHandle(), kAudioStatusChangedMessage, 0, 0);
            return nullptr;
          },
          [this](const flutter::EncodableValue*) {
            status_sink_.reset();
            return nullptr;
          }));
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
  audio_session_monitor_.reset();
  status_sink_.reset();
  if (status_event_channel_) status_event_channel_->SetStreamHandler(nullptr);
  status_event_channel_.reset();
  audio_channel_.reset();
  audio_manager_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  static const UINT activate_message = RegisterWindowMessageW(
      L"com.xhosa.bluetooth_audio_manager.activate");
  if (activate_message != 0 && message == activate_message) {
    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style & ~WS_EX_TOOLWINDOW);
    ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(hwnd);
    return 0;
  }

  if (message == kAudioStatusChangedMessage) {
    if (status_sink_ && audio_manager_ && !watched_device_id_.empty()) {
      try {
        const auto device = audio_manager_->GetDevice(watched_device_id_);
        audio_session_monitor_->Watch(device.hfp_capture_endpoint_id);
        const auto value = flutter::EncodableValue(
            EncodeStatus(audio_manager_->GetStatus(watched_device_id_)));
        status_sink_->Success(value);
      } catch (const std::exception& error) {
        status_sink_->Error("windows_audio_error", error.what());
      }
    }
    return 0;
  }

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
