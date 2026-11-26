#ifndef RUNNER_DESKTOP_CHANNEL_H_
#define RUNNER_DESKTOP_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Desktop shell integration: open/reveal received files safely (never through
// cmd.exe), mark them as downloaded from the Internet and report app folders.
class DesktopChannel {
 public:
  explicit DesktopChannel(flutter::BinaryMessenger* messenger);
  DesktopChannel(const DesktopChannel&) = delete;
  DesktopChannel& operator=(const DesktopChannel&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESKTOP_CHANNEL_H_
