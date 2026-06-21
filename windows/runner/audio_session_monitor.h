#ifndef RUNNER_AUDIO_SESSION_MONITOR_H_
#define RUNNER_AUDIO_SESSION_MONITOR_H_

#include <windows.h>

#include <memory>
#include <string>

class AudioSessionMonitor {
 public:
  AudioSessionMonitor(HWND window, UINT notification_message);
  ~AudioSessionMonitor();

  AudioSessionMonitor(const AudioSessionMonitor&) = delete;
  AudioSessionMonitor& operator=(const AudioSessionMonitor&) = delete;

  void Watch(const std::wstring& capture_endpoint_id);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_AUDIO_SESSION_MONITOR_H_
