#include <windows.h>

#include <cfgmgr32.h>
#include <sddl.h>
#include <wtsapi32.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <set>
#include <string>

namespace {

constexpr wchar_t kServiceName[] = L"BluetoothAudioManagerService";
constexpr wchar_t kPipeName[] =
    LR"(\\.\pipe\BluetoothAudioManager.Service.v1)";

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status{};
HANDLE g_stop_event = nullptr;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::filesystem::path StateFilePath() {
  wchar_t program_data[MAX_PATH] = {};
  const DWORD length = GetEnvironmentVariableW(
      L"ProgramData", program_data, static_cast<DWORD>(std::size(program_data)));
  std::filesystem::path directory =
      length > 0 ? program_data : L"C:\\ProgramData";
  directory /= L"BluetoothAudioManager";
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  return directory / L"disabled-endpoints.txt";
}

std::set<std::wstring> ReadDisabledEndpoints() {
  std::set<std::wstring> endpoints;
  std::wifstream input(StateFilePath());
  std::wstring line;
  while (std::getline(input, line)) {
    if (!line.empty()) endpoints.insert(line);
  }
  return endpoints;
}

void WriteDisabledEndpoints(const std::set<std::wstring>& endpoints) {
  std::wofstream output(StateFilePath(), std::ios::trunc);
  for (const auto& endpoint : endpoints) output << endpoint << L'\n';
}

bool IsAllowedInstanceId(const std::wstring& instance_id) {
  std::wstring upper = instance_id;
  std::transform(upper.begin(), upper.end(), upper.begin(), towupper);
  constexpr wchar_t prefix[] = L"SWD\\MMDEVAPI\\{0.0.1.";
  return upper.rfind(prefix, 0) == 0 && upper.size() < 300;
}

CONFIGRET ChangeDeviceState(const std::wstring& instance_id, bool enable) {
  DEVINST device = 0;
  CONFIGRET result = CM_Locate_DevNodeW(
      &device, const_cast<DEVINSTID_W>(instance_id.c_str()),
      CM_LOCATE_DEVNODE_PHANTOM);
  if (result != CR_SUCCESS) return result;
  return enable ? CM_Enable_DevNode(device, 0)
                : CM_Disable_DevNode(device, CM_DISABLE_PERSIST);
}

void TrackChange(const std::wstring& instance_id, bool enabled) {
  auto endpoints = ReadDisabledEndpoints();
  if (enabled) {
    endpoints.erase(instance_id);
  } else {
    endpoints.insert(instance_id);
  }
  WriteDisabledEndpoints(endpoints);
}

void RestoreTrackedEndpoints() {
  const auto endpoints = ReadDisabledEndpoints();
  std::set<std::wstring> remaining;
  for (const auto& endpoint : endpoints) {
    if (ChangeDeviceState(endpoint, true) != CR_SUCCESS) {
      remaining.insert(endpoint);
    }
  }
  WriteDisabledEndpoints(remaining);
}

bool IsActiveInteractiveClient(HANDLE pipe) {
  ULONG process_id = 0;
  if (!GetNamedPipeClientProcessId(pipe, &process_id)) return false;
  DWORD session_id = 0;
  return ProcessIdToSessionId(process_id, &session_id) &&
         session_id == WTSGetActiveConsoleSessionId();
}

void SendResponse(HANDLE pipe, const std::string& response) {
  DWORD written = 0;
  WriteFile(pipe, response.data(), static_cast<DWORD>(response.size()),
            &written, nullptr);
  FlushFileBuffers(pipe);
}

void HandleClient(HANDLE pipe) {
  if (!IsActiveInteractiveClient(pipe)) {
    SendResponse(pipe, "ERROR\tunauthorized_client\n");
    return;
  }
  char buffer[1024] = {};
  DWORD bytes_read = 0;
  if (!ReadFile(pipe, buffer, sizeof(buffer) - 1, &bytes_read, nullptr) ||
      bytes_read == 0) {
    SendResponse(pipe, "ERROR\tread_failed\n");
    return;
  }
  std::string command(buffer, bytes_read);
  const size_t tab = command.find('\t');
  const size_t newline = command.find('\n');
  if (tab == std::string::npos || newline == std::string::npos ||
      newline <= tab + 1) {
    SendResponse(pipe, "ERROR\tinvalid_command\n");
    return;
  }
  const std::string action = command.substr(0, tab);
  const std::wstring instance_id =
      Utf8ToWide(command.substr(tab + 1, newline - tab - 1));
  if ((action != "ENABLE" && action != "DISABLE") ||
      !IsAllowedInstanceId(instance_id)) {
    SendResponse(pipe, "ERROR\toperation_not_allowed\n");
    return;
  }

  const bool enable = action == "ENABLE";
  const CONFIGRET result = ChangeDeviceState(instance_id, enable);
  if (result != CR_SUCCESS) {
    SendResponse(pipe, "ERROR\tconfig_manager_" + std::to_string(result) +
                           "\n");
    return;
  }
  TrackChange(instance_id, enable);
  SendResponse(pipe, "OK\n");
}

void ReportStatus(DWORD state, DWORD win32_exit_code = NO_ERROR,
                  DWORD wait_hint = 0) {
  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_status.dwCurrentState = state;
  g_status.dwWin32ExitCode = win32_exit_code;
  g_status.dwWaitHint = wait_hint;
  g_status.dwControlsAccepted =
      state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN
                               : 0;
  SetServiceStatus(g_status_handle, &g_status);
}

DWORD WINAPI ServiceControlHandler(DWORD control, DWORD, LPVOID, LPVOID) {
  if (control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_SHUTDOWN) {
    ReportStatus(SERVICE_STOP_PENDING, NO_ERROR, 2000);
    SetEvent(g_stop_event);
    HANDLE wake = CreateFileW(kPipeName, GENERIC_WRITE, 0, nullptr,
                              OPEN_EXISTING, 0, nullptr);
    if (wake != INVALID_HANDLE_VALUE) CloseHandle(wake);
  }
  return NO_ERROR;
}

void RunPipeServer() {
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  ConvertStringSecurityDescriptorToSecurityDescriptorW(
      L"D:P(A;;GA;;;SY)(A;;GRGW;;;AU)", SDDL_REVISION_1, &descriptor,
      nullptr);
  SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), descriptor,
                                 FALSE};

  while (WaitForSingleObject(g_stop_event, 0) != WAIT_OBJECT_0) {
    HANDLE pipe = CreateNamedPipeW(
        kPipeName, PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE | PIPE_READMODE_BYTE |
                                            PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
        PIPE_UNLIMITED_INSTANCES, 1024, 1024, 0, &attributes);
    if (pipe == INVALID_HANDLE_VALUE) break;
    const BOOL connected = ConnectNamedPipe(pipe, nullptr)
                               ? TRUE
                               : GetLastError() == ERROR_PIPE_CONNECTED;
    if (connected &&
        WaitForSingleObject(g_stop_event, 0) != WAIT_OBJECT_0) {
      HandleClient(pipe);
    }
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
  if (descriptor) LocalFree(descriptor);
}

void WINAPI ServiceMain(DWORD, LPWSTR*) {
  g_status_handle = RegisterServiceCtrlHandlerExW(
      kServiceName, ServiceControlHandler, nullptr);
  if (!g_status_handle) return;
  ReportStatus(SERVICE_START_PENDING, NO_ERROR, 2000);
  g_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!g_stop_event) {
    ReportStatus(SERVICE_STOPPED, GetLastError());
    return;
  }
  ReportStatus(SERVICE_RUNNING);
  RunPipeServer();
  CloseHandle(g_stop_event);
  g_stop_event = nullptr;
  ReportStatus(SERVICE_STOPPED);
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc == 2 && std::wstring(argv[1]) == L"--restore") {
    RestoreTrackedEndpoints();
    return 0;
  }
  SERVICE_TABLE_ENTRYW dispatch_table[] = {
      {const_cast<LPWSTR>(kServiceName), ServiceMain}, {nullptr, nullptr}};
  return StartServiceCtrlDispatcherW(dispatch_table) ? 0
                                                      : GetLastError();
}
