#include "audio_manager.h"

#include <windows.h>

#include <initguid.h>
#include <cfgmgr32.h>
#include <devpkey.h>
#include <mmdeviceapi.h>
#include <audiopolicy.h>
#include <propsys.h>
#include <propvarutil.h>
#include <functiondiscoverykeys_devpkey.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <map>
#include <stdexcept>
#include <sstream>
#include <thread>

using Microsoft::WRL::ComPtr;

namespace {

struct DeviceShareMode {
  DWORD mode;
  DWORD unknown;
};

MIDL_INTERFACE("f8679f50-850a-41cf-9c72-430f290290c8")
IPolicyConfig : public IUnknown {
 public:
  virtual HRESULT STDMETHODCALLTYPE GetMixFormat(PCWSTR, WAVEFORMATEX**) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetDeviceFormat(PCWSTR, INT,
                                                     WAVEFORMATEX**) = 0;
  virtual HRESULT STDMETHODCALLTYPE ResetDeviceFormat(PCWSTR) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetDeviceFormat(PCWSTR, WAVEFORMATEX*,
                                                     WAVEFORMATEX*) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetProcessingPeriod(PCWSTR, INT, PINT64,
                                                        PINT64) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetProcessingPeriod(PCWSTR, PINT64) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetShareMode(PCWSTR, DeviceShareMode*) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetShareMode(PCWSTR, DeviceShareMode*) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetPropertyValue(PCWSTR,
                                                     const PROPERTYKEY&,
                                                     PROPVARIANT*) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetPropertyValue(PCWSTR,
                                                     const PROPERTYKEY&,
                                                     PROPVARIANT*) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetDefaultEndpoint(PCWSTR, ERole) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetEndpointVisibility(PCWSTR, INT) = 0;
};

const CLSID CLSID_PolicyConfigClient = {
    0x870af99c,
    0x171d,
    0x4f9e,
    {0xaf, 0x0d, 0xe6, 0x3d, 0xf4, 0x0c, 0x2b, 0xc9}};

std::runtime_error HResultError(const char* operation, HRESULT result) {
  return std::runtime_error(std::string(operation) + " failed (HRESULT " +
                            std::to_string(static_cast<unsigned long>(result)) +
                            ")");
}

std::wstring GetStringProperty(IPropertyStore* store,
                               const PROPERTYKEY& key) {
  PROPVARIANT value;
  PropVariantInit(&value);
  std::wstring result;
  if (SUCCEEDED(store->GetValue(key, &value)) && value.vt == VT_LPWSTR &&
      value.pwszVal) {
    result = value.pwszVal;
  }
  PropVariantClear(&value);
  return result;
}

std::wstring GetGuidProperty(IPropertyStore* store, const PROPERTYKEY& key) {
  PROPVARIANT value;
  PropVariantInit(&value);
  std::wstring result;
  if (SUCCEEDED(store->GetValue(key, &value)) && value.vt == VT_CLSID &&
      value.puuid) {
    wchar_t buffer[64] = {};
    if (StringFromGUID2(*value.puuid, buffer, ARRAYSIZE(buffer)) > 0) {
      result = buffer;
    }
  }
  PropVariantClear(&value);
  return result;
}

UINT32 GetUIntProperty(IPropertyStore* store, const PROPERTYKEY& key) {
  PROPVARIANT value;
  PropVariantInit(&value);
  UINT32 result = UINT32_MAX;
  if (SUCCEEDED(store->GetValue(key, &value))) {
    if (value.vt == VT_UI4) result = value.ulVal;
    if (value.vt == VT_I4) result = static_cast<UINT32>(value.lVal);
  }
  PropVariantClear(&value);
  return result;
}

struct EndpointInfo {
  EDataFlow flow = eAll;
  EndpointFormFactor form_factor = UnknownFormFactor;
  DWORD state = DEVICE_STATE_NOTPRESENT;
  std::wstring endpoint_id;
  std::wstring instance_id;
  std::wstring container_id;
  std::wstring name;
};

std::wstring PnpContainerId(const std::wstring& instance_id) {
  DEVINST device = 0;
  if (CM_Locate_DevNodeW(&device,
                        const_cast<DEVINSTID_W>(instance_id.c_str()),
                        CM_LOCATE_DEVNODE_PHANTOM) != CR_SUCCESS) {
    return {};
  }
  GUID container{};
  ULONG size = sizeof(container);
  DEVPROPTYPE type = 0;
  if (CM_Get_DevNode_PropertyW(device, &DEVPKEY_Device_ContainerId, &type,
                              reinterpret_cast<PBYTE>(&container), &size,
                              0) != CR_SUCCESS ||
      type != DEVPROP_TYPE_GUID) {
    return {};
  }
  wchar_t buffer[64] = {};
  return StringFromGUID2(container, buffer, ARRAYSIZE(buffer)) > 0
             ? std::wstring(buffer)
             : std::wstring{};
}

std::wstring PnpStringProperty(DEVINST device, const DEVPROPKEY& key) {
  DEVPROPTYPE type = 0;
  ULONG size = 0;
  if (CM_Get_DevNode_PropertyW(device, &key, &type, nullptr, &size, 0) !=
          CR_BUFFER_SMALL ||
      type != DEVPROP_TYPE_STRING || size < sizeof(wchar_t)) {
    return {};
  }
  std::vector<BYTE> buffer(size);
  if (CM_Get_DevNode_PropertyW(device, &key, &type, buffer.data(), &size, 0) !=
      CR_SUCCESS) {
    return {};
  }
  return reinterpret_cast<const wchar_t*>(buffer.data());
}

void AddMissingPnpEndpoints(std::vector<EndpointInfo>& endpoints) {
  constexpr wchar_t audio_endpoint_class[] =
      L"{C166523C-FE0C-4A94-A586-F1A80CFBBF3E}";
  ULONG list_size = 0;
  if (CM_Get_Device_ID_List_SizeW(
          &list_size, audio_endpoint_class,
          CM_GETIDLIST_FILTER_CLASS) != CR_SUCCESS ||
      list_size <= 1) {
    return;
  }
  std::vector<wchar_t> ids(list_size);
  if (CM_Get_Device_ID_ListW(audio_endpoint_class, ids.data(), list_size,
                            CM_GETIDLIST_FILTER_CLASS) != CR_SUCCESS) {
    return;
  }

  for (const wchar_t* current = ids.data(); *current;
       current += wcslen(current) + 1) {
    const std::wstring instance_id = current;
    constexpr wchar_t prefix[] = L"SWD\\MMDEVAPI\\";
    if (instance_id.rfind(prefix, 0) != 0) continue;
    const std::wstring endpoint_id = instance_id.substr(std::size(prefix) - 1);
    const auto existing =
        std::find_if(endpoints.begin(), endpoints.end(), [&](const auto& item) {
          return _wcsicmp(item.endpoint_id.c_str(), endpoint_id.c_str()) == 0;
        });
    if (existing != endpoints.end()) continue;

    DEVINST device = 0;
    if (CM_Locate_DevNodeW(&device,
                          const_cast<DEVINSTID_W>(instance_id.c_str()),
                          CM_LOCATE_DEVNODE_PHANTOM) != CR_SUCCESS) {
      continue;
    }
    EndpointInfo info;
    info.endpoint_id = endpoint_id;
    info.instance_id = instance_id;
    info.container_id = PnpContainerId(instance_id);
    info.name = PnpStringProperty(device, DEVPKEY_Device_FriendlyName);
    if (endpoint_id.rfind(L"{0.0.0.", 0) == 0) info.flow = eRender;
    if (endpoint_id.rfind(L"{0.0.1.", 0) == 0) info.flow = eCapture;
    ULONG status = 0;
    ULONG problem = 0;
    if (CM_Get_DevNode_Status(&status, &problem, device, 0) == CR_SUCCESS &&
        (status & DN_STARTED) != 0 && problem == 0) {
      info.state = DEVICE_STATE_ACTIVE;
    }
    if (!info.container_id.empty()) endpoints.push_back(std::move(info));
  }
}

std::vector<EndpointInfo> EnumerateEndpoints() {
  ComPtr<IMMDeviceEnumerator> enumerator;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (FAILED(hr)) throw HResultError("Create MMDeviceEnumerator", hr);

  ComPtr<IMMDeviceCollection> collection;
  hr = enumerator->EnumAudioEndpoints(eAll, DEVICE_STATEMASK_ALL, &collection);
  if (FAILED(hr)) throw HResultError("Enumerate audio endpoints", hr);

  UINT count = 0;
  collection->GetCount(&count);
  std::vector<EndpointInfo> endpoints;
  for (UINT index = 0; index < count; ++index) {
    ComPtr<IMMDevice> device;
    if (FAILED(collection->Item(index, &device))) continue;

    EndpointInfo info;
    LPWSTR endpoint_id = nullptr;
    if (SUCCEEDED(device->GetId(&endpoint_id)) && endpoint_id) {
      info.endpoint_id = endpoint_id;
      CoTaskMemFree(endpoint_id);
    }
    device->GetState(&info.state);

    ComPtr<IMMEndpoint> endpoint;
    if (SUCCEEDED(device.As(&endpoint))) endpoint->GetDataFlow(&info.flow);

    ComPtr<IPropertyStore> store;
    if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &store))) {
      info.name = GetStringProperty(store.Get(), PKEY_Device_FriendlyName);
      info.instance_id =
          GetStringProperty(store.Get(), PKEY_Device_InstanceId);
      info.container_id =
          GetGuidProperty(store.Get(), PKEY_Device_ContainerId);
      const UINT32 form =
          GetUIntProperty(store.Get(), PKEY_AudioEndpoint_FormFactor);
      if (form != UINT32_MAX) {
        info.form_factor = static_cast<EndpointFormFactor>(form);
      }
    }
    if (info.instance_id.empty() && !info.endpoint_id.empty()) {
      info.instance_id = L"SWD\\MMDEVAPI\\" + info.endpoint_id;
    }
    if (info.container_id.empty() && !info.instance_id.empty()) {
      info.container_id = PnpContainerId(info.instance_id);
    }
    if (!info.endpoint_id.empty()) {
      endpoints.push_back(std::move(info));
    }
  }
  AddMissingPnpEndpoints(endpoints);
  return endpoints;
}

bool IsActive(DWORD state) { return (state & DEVICE_STATE_ACTIVE) != 0; }

bool HasActiveAudioSession(const std::wstring& endpoint_id) {
  ComPtr<IMMDeviceEnumerator> enumerator;
  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
  if (FAILED(hr)) throw HResultError("Create MMDeviceEnumerator", hr);

  ComPtr<IMMDevice> device;
  hr = enumerator->GetDevice(endpoint_id.c_str(), &device);
  if (FAILED(hr)) throw HResultError("Open HFP capture endpoint", hr);

  ComPtr<IAudioSessionManager2> session_manager;
  hr = device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr,
                        reinterpret_cast<void**>(session_manager.GetAddressOf()));
  if (FAILED(hr)) throw HResultError("Activate HFP session manager", hr);

  ComPtr<IAudioSessionEnumerator> sessions;
  hr = session_manager->GetSessionEnumerator(&sessions);
  if (FAILED(hr)) throw HResultError("Enumerate HFP audio sessions", hr);

  int count = 0;
  hr = sessions->GetCount(&count);
  if (FAILED(hr)) throw HResultError("Count HFP audio sessions", hr);
  for (int index = 0; index < count; ++index) {
    ComPtr<IAudioSessionControl> session;
    hr = sessions->GetSession(index, &session);
    if (FAILED(hr)) throw HResultError("Read HFP audio session", hr);
    AudioSessionState state = AudioSessionStateInactive;
    hr = session->GetState(&state);
    if (FAILED(hr)) throw HResultError("Read HFP audio session state", hr);
    if (state == AudioSessionStateActive) return true;
  }
  return false;
}

std::wstring DefaultEndpointId(EDataFlow flow) {
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return {};
  }
  ComPtr<IMMDevice> device;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(flow, eConsole, &device))) {
    return {};
  }
  LPWSTR id = nullptr;
  std::wstring result;
  if (SUCCEEDED(device->GetId(&id)) && id) {
    result = id;
    CoTaskMemFree(id);
  }
  return result;
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

}  // namespace

std::vector<BluetoothAudioDeviceNative> AudioManager::ListDevices() {
  const auto endpoints = EnumerateEndpoints();
  std::map<std::wstring, BluetoothAudioDeviceNative> grouped;
  for (const auto& endpoint : endpoints) {
    if (endpoint.container_id == L"{00000000-0000-0000-FFFF-FFFFFFFFFFFF}") {
      continue;
    }
    auto& device = grouped[endpoint.container_id];
    device.id = endpoint.container_id;
    if (device.name.empty() || endpoint.form_factor == Headphones) {
      device.name = endpoint.name;
    }
    device.connected = device.connected || IsActive(endpoint.state);

    if (endpoint.flow == eRender && endpoint.form_factor == Headphones) {
      device.a2dp_endpoint_id = endpoint.endpoint_id;
    } else if (endpoint.flow == eRender &&
               endpoint.form_factor == Headset) {
      device.hfp_render_endpoint_id = endpoint.endpoint_id;
    } else if (endpoint.flow == eRender &&
               endpoint.form_factor == UnknownFormFactor &&
               device.hfp_render_endpoint_id.empty()) {
      device.hfp_render_endpoint_id = endpoint.endpoint_id;
    } else if (endpoint.flow == eCapture &&
               (endpoint.form_factor == Headset ||
                endpoint.form_factor == Microphone)) {
      device.hfp_capture_endpoint_id = endpoint.endpoint_id;
      device.hfp_capture_instance_id = endpoint.instance_id;
    }
  }

  std::vector<BluetoothAudioDeviceNative> devices;
  for (auto& [id, device] : grouped) {
    if (!device.a2dp_endpoint_id.empty() &&
        !device.hfp_render_endpoint_id.empty() &&
        !device.hfp_capture_endpoint_id.empty() &&
        !device.hfp_capture_instance_id.empty()) {
      devices.push_back(std::move(device));
    }
  }
  std::sort(devices.begin(), devices.end(), [](const auto& left,
                                                const auto& right) {
    if (left.connected != right.connected) return left.connected > right.connected;
    return left.name < right.name;
  });
  return devices;
}

std::string AudioManager::Diagnostics() {
  std::ostringstream output;
  const auto endpoints = EnumerateEndpoints();
  output << "rawEndpoints=" << endpoints.size() << "\n";
  for (const auto& endpoint : endpoints) {
    output << "endpoint.name=" << WideToUtf8(endpoint.name) << "\n"
           << "endpoint.container=" << WideToUtf8(endpoint.container_id)
           << "\nendpoint.id=" << WideToUtf8(endpoint.endpoint_id)
           << "\nendpoint.instance=" << WideToUtf8(endpoint.instance_id)
           << "\nendpoint.flow=" << static_cast<int>(endpoint.flow)
           << "\nendpoint.form=" << static_cast<int>(endpoint.form_factor)
           << "\nendpoint.state=" << endpoint.state << "\n---\n";
  }
  return output.str();
}

BluetoothAudioDeviceNative AudioManager::FindDevice(
    const std::wstring& device_id) {
  const auto devices = ListDevices();
  const auto found =
      std::find_if(devices.begin(), devices.end(), [&](const auto& device) {
        return device.id == device_id;
      });
  if (found == devices.end()) {
    throw std::runtime_error("找不到所选蓝牙耳机，请重新连接后刷新。");
  }
  return *found;
}

BluetoothAudioStatusNative AudioManager::GetStatus(
    const std::wstring& device_id) {
  const auto device = FindDevice(device_id);
  const auto endpoints = EnumerateEndpoints();
  DWORD capture_state = DEVICE_STATE_NOTPRESENT;
  for (const auto& endpoint : endpoints) {
    if (endpoint.endpoint_id == device.hfp_capture_endpoint_id) {
      capture_state = endpoint.state;
      break;
    }
  }

  BluetoothAudioStatusNative status;
  status.connected = device.connected;
  status.microphone_enabled = IsActive(capture_state);
  if (status.connected && status.microphone_enabled) {
    status.hfp_active =
        HasActiveAudioSession(device.hfp_capture_endpoint_id);
  }
  const std::wstring default_render = DefaultEndpointId(eRender);
  const std::wstring default_capture = DefaultEndpointId(eCapture);
  status.a2dp_is_default = default_render == device.a2dp_endpoint_id;
  status.hfp_render_is_default =
      default_render == device.hfp_render_endpoint_id;
  status.hfp_capture_is_default =
      default_capture == device.hfp_capture_endpoint_id;

  if (!status.connected) {
    status.mode = "offline";
  } else if (!status.microphone_enabled && status.a2dp_is_default) {
    status.mode = "a2dp";
  } else if (status.microphone_enabled && status.hfp_capture_is_default &&
             (status.hfp_render_is_default || status.a2dp_is_default)) {
    status.mode = "hfp";
  } else {
    status.mode = "mixed";
  }
  return status;
}

void AudioManager::SetDefaultEndpoint(const std::wstring& endpoint_id) {
  ComPtr<IPolicyConfig> policy;
  const HRESULT create_result =
      CoCreateInstance(CLSID_PolicyConfigClient, nullptr, CLSCTX_ALL,
                       __uuidof(IPolicyConfig), &policy);
  if (FAILED(create_result)) {
    throw HResultError("Create audio policy client", create_result);
  }
  for (const ERole role : {eConsole, eMultimedia, eCommunications}) {
    const HRESULT result = policy->SetDefaultEndpoint(endpoint_id.c_str(), role);
    if (FAILED(result)) throw HResultError("Set default endpoint", result);
  }
}

void AudioManager::SetEndpointVisibility(const std::wstring& endpoint_id,
                                         bool visible) {
  ComPtr<IPolicyConfig> policy;
  const HRESULT create_result =
      CoCreateInstance(CLSID_PolicyConfigClient, nullptr, CLSCTX_ALL,
                       __uuidof(IPolicyConfig), &policy);
  if (FAILED(create_result)) {
    throw HResultError("Create audio policy client", create_result);
  }
  const HRESULT result =
      policy->SetEndpointVisibility(endpoint_id.c_str(), visible ? TRUE : FALSE);
  if (FAILED(result)) {
    throw HResultError("Set audio endpoint visibility", result);
  }
}

BluetoothAudioStatusNative AudioManager::SetMode(
    const std::wstring& device_id,
    const std::string& mode) {
  auto device = FindDevice(device_id);
  if (!device.connected) {
    throw std::runtime_error("目标耳机当前未连接，期望模式将在重连后应用。");
  }

  if (mode == "a2dp") {
    try {
      SetDefaultEndpoint(device.a2dp_endpoint_id);
    } catch (const std::exception& error) {
      throw std::runtime_error(std::string("a2dp_default: ") + error.what());
    }
    try {
      SetEndpointVisibility(device.hfp_capture_endpoint_id, false);
    } catch (const std::exception& error) {
      throw std::runtime_error(std::string("capture_hide: ") + error.what());
    }
    try {
      SetEndpointVisibility(device.hfp_render_endpoint_id, false);
    } catch (const std::exception& error) {
      throw std::runtime_error(std::string("hfp_render_hide: ") + error.what());
    }
  } else if (mode == "hfp") {
    try {
      SetEndpointVisibility(device.hfp_render_endpoint_id, true);
    } catch (const std::exception& error) {
      throw std::runtime_error(std::string("hfp_render_show: ") + error.what());
    }
    try {
      SetEndpointVisibility(device.hfp_capture_endpoint_id, true);
    } catch (const std::exception& error) {
      throw std::runtime_error(std::string("capture_show: ") + error.what());
    }
    for (int attempt = 0; attempt < 20; ++attempt) {
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
      try {
        device = FindDevice(device_id);
        const auto state = GetStatus(device_id);
        if (state.microphone_enabled) break;
      } catch (...) {
      }
    }
    device = FindDevice(device_id);
    try {
      SetDefaultEndpoint(device.hfp_capture_endpoint_id);
    } catch (const std::exception& error) {
      throw std::runtime_error(std::string("hfp_capture_default: ") +
                               error.what());
    }
    try {
      // Windows 11 exposes Bluetooth output as a unified logical endpoint on
      // current HFP drivers. The transport changes to HFP when capture starts.
      SetDefaultEndpoint(device.a2dp_endpoint_id);
    } catch (const std::exception& error) {
      throw std::runtime_error(std::string("hfp_unified_render_default: ") +
                               error.what());
    }
  } else {
    throw std::runtime_error("不支持的音频模式。");
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(400));
  return GetStatus(device_id);
}
