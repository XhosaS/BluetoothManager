#ifndef RUNNER_AUDIO_MANAGER_H_
#define RUNNER_AUDIO_MANAGER_H_

#include <string>
#include <vector>

struct BluetoothAudioDeviceNative {
  std::wstring id;
  std::wstring name;
  bool connected = false;
  std::wstring a2dp_endpoint_id;
  std::wstring hfp_render_endpoint_id;
  std::wstring hfp_capture_endpoint_id;
  std::wstring hfp_capture_instance_id;
};

struct BluetoothAudioStatusNative {
  std::string mode = "offline";
  bool connected = false;
  bool microphone_enabled = false;
  bool hfp_active = false;
  bool a2dp_is_default = false;
  bool hfp_render_is_default = false;
  bool hfp_capture_is_default = false;
};

class AudioManager {
 public:
  std::vector<BluetoothAudioDeviceNative> ListDevices();
  BluetoothAudioDeviceNative GetDevice(const std::wstring& device_id);
  std::string Diagnostics();
  BluetoothAudioStatusNative GetStatus(const std::wstring& device_id);
  BluetoothAudioStatusNative SetMode(const std::wstring& device_id,
                                     const std::string& mode);

 private:
  BluetoothAudioDeviceNative FindDevice(const std::wstring& device_id);
  void SetDefaultEndpoint(const std::wstring& endpoint_id);
  void SetEndpointVisibility(const std::wstring& endpoint_id, bool visible);
};

#endif  // RUNNER_AUDIO_MANAGER_H_
