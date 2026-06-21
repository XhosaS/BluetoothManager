#include "audio_session_monitor.h"

#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

using Microsoft::WRL::ClassicCom;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::RuntimeClass;
using Microsoft::WRL::RuntimeClassFlags;

namespace {

using Notify = std::function<void(bool)>;

class SessionEvents
    : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IAudioSessionEvents> {
 public:
  explicit SessionEvents(Notify notify) : notify_(std::move(notify)) {}

  HRESULT STDMETHODCALLTYPE OnDisplayNameChanged(LPCWSTR, LPCGUID) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnIconPathChanged(LPCWSTR, LPCGUID) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnSimpleVolumeChanged(float, BOOL, LPCGUID) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnChannelVolumeChanged(DWORD, float[], DWORD,
                                                    LPCGUID) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnGroupingParamChanged(LPCGUID, LPCGUID) override {
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnStateChanged(AudioSessionState) override {
    notify_(false);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnSessionDisconnected(
      AudioSessionDisconnectReason) override {
    notify_(true);
    return S_OK;
  }

 private:
  Notify notify_;
};

class SessionNotification
    : public RuntimeClass<RuntimeClassFlags<ClassicCom>,
                          IAudioSessionNotification> {
 public:
  explicit SessionNotification(Notify notify) : notify_(std::move(notify)) {}
  HRESULT STDMETHODCALLTYPE OnSessionCreated(IAudioSessionControl*) override {
    notify_(true);
    return S_OK;
  }

 private:
  Notify notify_;
};

class EndpointNotification
    : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IMMNotificationClient> {
 public:
  explicit EndpointNotification(Notify notify) : notify_(std::move(notify)) {}
  HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR, DWORD) override {
    notify_(true);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR) override {
    notify_(true);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR) override {
    notify_(true);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(EDataFlow, ERole,
                                                    LPCWSTR) override {
    notify_(true);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(LPCWSTR,
                                                   const PROPERTYKEY) override {
    notify_(true);
    return S_OK;
  }

 private:
  Notify notify_;
};

}  // namespace

class AudioSessionMonitor::Impl {
 public:
  Impl(HWND window, UINT message) : window_(window), message_(message) {
    worker_ = std::thread([this] { Run(); });
  }

  ~Impl() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
      rebuild_ = true;
    }
    wake_.notify_one();
    if (worker_.joinable()) worker_.join();
  }

  void Watch(const std::wstring& endpoint_id) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (endpoint_id_ == endpoint_id) return;
      endpoint_id_ = endpoint_id;
      rebuild_ = true;
    }
    wake_.notify_one();
  }

 private:
  void NotifyFlutter(bool rebuild) {
    if (rebuild) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        rebuild_ = true;
      }
      wake_.notify_one();
    }
    PostMessageW(window_, message_, 0, 0);
  }

  void ClearSessions() {
    for (auto& session : sessions_) {
      session->UnregisterAudioSessionNotification(session_events_.Get());
    }
    sessions_.clear();
    if (session_manager_ && session_notification_) {
      session_manager_->UnregisterSessionNotification(
          session_notification_.Get());
    }
    session_manager_.Reset();
  }

  void BuildSessions(const std::wstring& endpoint_id) {
    ClearSessions();
    if (endpoint_id.empty() || !device_enumerator_) return;

    ComPtr<IMMDevice> device;
    if (FAILED(device_enumerator_->GetDevice(endpoint_id.c_str(), &device))) {
      return;
    }
    DWORD state = 0;
    if (FAILED(device->GetState(&state)) ||
        (state & DEVICE_STATE_ACTIVE) == 0) {
      return;
    }
    if (FAILED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL,
                                nullptr, reinterpret_cast<void**>(
                                             session_manager_.GetAddressOf())))) {
      session_manager_.Reset();
      return;
    }

    // Register first, then enumerate, so sessions created during the initial
    // snapshot still trigger a rebuild notification.
    session_manager_->RegisterSessionNotification(session_notification_.Get());
    ComPtr<IAudioSessionEnumerator> enumerator;
    if (FAILED(session_manager_->GetSessionEnumerator(&enumerator))) return;
    int count = 0;
    if (FAILED(enumerator->GetCount(&count))) return;
    for (int index = 0; index < count; ++index) {
      ComPtr<IAudioSessionControl> session;
      if (SUCCEEDED(enumerator->GetSession(index, &session)) && session) {
        if (SUCCEEDED(session->RegisterAudioSessionNotification(
                session_events_.Get()))) {
          sessions_.push_back(std::move(session));
        }
      }
    }
  }

  void Run() {
    if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) return;
    const Notify notify = [this](bool rebuild) { NotifyFlutter(rebuild); };
    session_events_ = Microsoft::WRL::Make<SessionEvents>(notify);
    session_notification_ = Microsoft::WRL::Make<SessionNotification>(notify);
    endpoint_notification_ = Microsoft::WRL::Make<EndpointNotification>(notify);
    if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                   CLSCTX_ALL,
                                   IID_PPV_ARGS(&device_enumerator_)))) {
      device_enumerator_->RegisterEndpointNotificationCallback(
          endpoint_notification_.Get());
    }

    while (true) {
      std::wstring endpoint;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        wake_.wait(lock, [this] { return rebuild_ || stopping_; });
        if (stopping_) break;
        rebuild_ = false;
        endpoint = endpoint_id_;
      }
      BuildSessions(endpoint);
    }

    ClearSessions();
    if (device_enumerator_ && endpoint_notification_) {
      device_enumerator_->UnregisterEndpointNotificationCallback(
          endpoint_notification_.Get());
    }
    endpoint_notification_.Reset();
    session_notification_.Reset();
    session_events_.Reset();
    device_enumerator_.Reset();
    CoUninitialize();
  }

  HWND window_;
  UINT message_;
  std::thread worker_;
  std::mutex mutex_;
  std::condition_variable wake_;
  bool stopping_ = false;
  bool rebuild_ = true;
  std::wstring endpoint_id_;
  ComPtr<IMMDeviceEnumerator> device_enumerator_;
  ComPtr<IAudioSessionManager2> session_manager_;
  ComPtr<SessionEvents> session_events_;
  ComPtr<SessionNotification> session_notification_;
  ComPtr<EndpointNotification> endpoint_notification_;
  std::vector<ComPtr<IAudioSessionControl>> sessions_;
};

AudioSessionMonitor::AudioSessionMonitor(HWND window, UINT message)
    : impl_(std::make_unique<Impl>(window, message)) {}

AudioSessionMonitor::~AudioSessionMonitor() = default;

void AudioSessionMonitor::Watch(const std::wstring& capture_endpoint_id) {
  impl_->Watch(capture_endpoint_id);
}
