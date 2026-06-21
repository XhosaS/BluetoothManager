add_executable(bluetooth_audio_service
  "service_main.cpp"
)

target_compile_features(bluetooth_audio_service PRIVATE cxx_std_17)
target_compile_definitions(bluetooth_audio_service PRIVATE
  UNICODE
  _UNICODE
  NOMINMAX
)
target_compile_options(bluetooth_audio_service PRIVATE /W4 /WX- /utf-8)
target_link_libraries(bluetooth_audio_service PRIVATE
  "advapi32.lib"
  "cfgmgr32.lib"
  "wtsapi32.lib"
)
