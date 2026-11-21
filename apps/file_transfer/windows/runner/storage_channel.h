#ifndef RUNNER_STORAGE_CHANNEL_H_
#define RUNNER_STORAGE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <atomic>
#include <memory>
#include <string>
#include <thread>

// App-owned, foreground storage methods. Native bytes never cross the channel.
class StorageChannel {
 public:
  StorageChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~StorageChannel();
  StorageChannel(const StorageChannel&) = delete;
  StorageChannel& operator=(const StorageChannel&) = delete;

  bool HandleWindowMessage(UINT message);
  void Shutdown();

 private:
  struct CopyState {
    std::atomic<bool> cancel{false};
    bool succeeded = false;
    DWORD error = ERROR_SUCCESS;
    std::wstring destination;
  };

  void HandleCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StartExport(const flutter::EncodableMap& arguments,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void FinishExport();
  static void CopyReceivedFile(const std::wstring& source,
                               const std::shared_ptr<CopyState>& state);

  static constexpr UINT kExportComplete = WM_APP + 0x416;
  HWND window_;
  bool closing_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
  std::shared_ptr<CopyState> copy_state_;
  std::thread worker_;
};

#endif  // RUNNER_STORAGE_CHANNEL_H_
