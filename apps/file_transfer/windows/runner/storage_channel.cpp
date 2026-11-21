#include "storage_channel.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

#include "utils.h"

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

std::wstring Utf16(const std::string& input) {
  if (input.empty() || input.size() > 32768 || input.find('\0') != std::string::npos) return {};
  const int count = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      input.data(), static_cast<int>(input.size()), nullptr, 0);
  if (!count) return {};
  std::wstring result(static_cast<size_t>(count), L'\0');
  if (!::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
      static_cast<int>(input.size()), result.data(), count)) return {};
  return result;
}

std::string StringArgument(const EncodableMap& arguments, const char* key) {
  const auto entry = arguments.find(EncodableValue(key));
  if (entry == arguments.end()) return {};
  const auto value = std::get_if<std::string>(&entry->second);
  return value ? *value : std::string();
}

std::wstring AbsolutePath(const std::wstring& input) {
  if (input.empty()) return {};
  const DWORD needed = ::GetFullPathNameW(input.c_str(), 0, nullptr, nullptr);
  if (!needed || needed > 32768) return {};
  std::wstring result(needed, L'\0');
  const DWORD copied = ::GetFullPathNameW(input.c_str(), needed, result.data(), nullptr);
  if (!copied || copied >= needed) return {};
  result.resize(copied);
  return result;
}

bool Within(const std::wstring& file, const std::wstring& directory) {
  if (file.size() < directory.size() ||
      ::CompareStringOrdinal(file.data(), static_cast<int>(directory.size()),
          directory.data(), static_cast<int>(directory.size()), TRUE) != CSTR_EQUAL) return false;
  return file.size() == directory.size() || file[directory.size()] == L'\\';
}

std::wstring ManagedRoot() {
  PWSTR known = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_DEFAULT, nullptr, &known))) return {};
  std::wstring result(known);
  ::CoTaskMemFree(known);
  // These are the CompanyName/ProductName values in Runner.rc, which
  // path_provider_windows uses for getApplicationSupportDirectory.
  result += L"\\Ulash\\Ulash\\file-transfer-v1";
  return AbsolutePath(result);
}

bool ReceivedSource(const std::wstring& source) {
  const std::wstring managed = ManagedRoot();
  if (managed.empty()) return false;
  const std::wstring root = managed + L"\\inbox\\received";
  if (!Within(source, root) || source.size() == root.size()) return false;
  // Reject NTFS ADS and reparse points in the managed subtree. The input is
  // an app-owned committed path, never a destination from a remote manifest.
  if (source.find(L':', 2) != std::wstring::npos) return false;
  std::wstring current = source;
  bool first = true;
  while (Within(current, managed)) {
    const DWORD attributes = ::GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
        (first && (attributes & FILE_ATTRIBUTE_DIRECTORY))) return false;
    first = false;
    if (current == managed) break;
    const size_t slash = current.find_last_of(L'\\');
    if (slash == std::wstring::npos) return false;
    current.resize(slash);
  }
  return true;
}

class FileHandle {
 public:
  explicit FileHandle(HANDLE value = INVALID_HANDLE_VALUE) : value_(value) {}
  ~FileHandle() { if (valid()) ::CloseHandle(value_); }
  FileHandle(const FileHandle&) = delete;
  FileHandle& operator=(const FileHandle&) = delete;
  bool valid() const { return value_ != INVALID_HANDLE_VALUE && value_ != nullptr; }
  HANDLE get() const { return value_; }
 private:
  HANDLE value_;
};

// An unfinished copy is removed using its open handle, not a racy path delete.
class TemporaryExport {
 public:
  explicit TemporaryExport(HANDLE value) : file(value) {}
  ~TemporaryExport() {
    if (!published && file.valid()) {
      FILE_DISPOSITION_INFO disposition{};
      disposition.DeleteFile = TRUE;
      ::SetFileInformationByHandle(file.get(), FileDispositionInfo,
          &disposition, sizeof(disposition));
    }
  }
  FileHandle file;
  bool published = false;
};

bool SafeSuggestedName(const std::wstring& name) {
  if (name.empty() || name.size() > 255 || name == L"." || name == L"..") return false;
  for (const wchar_t value : name) {
    if (value < 32 || value == L'/' || value == L'\\' || value == L':') return false;
  }
  return true;
}
}  // namespace

StorageChannel::StorageChannel(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "file_transfer/storage", &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleCall(call, std::move(result));
  });
}

StorageChannel::~StorageChannel() { Shutdown(); }

void StorageChannel::HandleCall(const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (closing_) {
    result->Error("EXPORT_INTERRUPTED", "The application is closing.");
    return;
  }
  const auto* arguments = std::get_if<EncodableMap>(call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGUMENT", "Storage arguments are required.");
    return;
  }
  if (call.method_name() == "freeBytes") {
    const auto path = AbsolutePath(Utf16(StringArgument(*arguments, "path")));
    const auto root = ManagedRoot();
    ULARGE_INTEGER available{};
    if (root.empty() || !Within(path, root) ||
        !::GetDiskFreeSpaceExW(path.c_str(), &available, nullptr, nullptr) ||
        available.QuadPart > static_cast<ULONGLONG>(std::numeric_limits<int64_t>::max())) {
      result->Success(EncodableValue());
    } else {
      result->Success(EncodableValue(static_cast<int64_t>(available.QuadPart)));
    }
  } else if (call.method_name() == "exportFile") {
    StartExport(*arguments, std::move(result));
  } else {
    result->NotImplemented();
  }
}

void StorageChannel::StartExport(const EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (pending_) {
    result->Error("EXPORT_BUSY", "Another save dialog or copy is active.");
    return;
  }
  const auto source = AbsolutePath(Utf16(StringArgument(arguments, "sourcePath")));
  const auto name = Utf16(StringArgument(arguments, "displayName"));
  if (!SafeSuggestedName(name)) {
    result->Error("INVALID_ARGUMENT", "A safe filename is required.");
    return;
  }
  if (!ReceivedSource(source)) {
    result->Error("EXPORT_SOURCE_UNAVAILABLE", "The received file is unavailable.");
    return;
  }
  ComPtr<IFileSaveDialog> dialog;
  HRESULT hr = ::CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&dialog));
  if (FAILED(hr)) {
    result->Error("EXPORT_UNSUPPORTED", "The system save dialog is unavailable.");
    return;
  }
  FILEOPENDIALOGOPTIONS options{};
  hr = dialog->GetOptions(&options);
  if (SUCCEEDED(hr)) {
    options = static_cast<FILEOPENDIALOGOPTIONS>(
        (options | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR) & ~FOS_OVERWRITEPROMPT);
    hr = dialog->SetOptions(options);
  }
  if (SUCCEEDED(hr)) hr = dialog->SetFileName(name.c_str());
  if (SUCCEEDED(hr)) hr = dialog->SetTitle(L"Сохранить копию полученного файла");
  if (SUCCEEDED(hr)) hr = dialog->SetOkButtonLabel(L"Сохранить новый файл");
  if (FAILED(hr)) {
    result->Error("EXPORT_FAILED", "The save dialog could not be prepared.");
    return;
  }
  // The modal dialog pumps the UI message loop. Reserve the operation before
  // showing it so a second Dart request cannot start a concurrent export.
  pending_ = std::move(result);
  hr = dialog->Show(window_);
  if (closing_ || !pending_) return;
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    pending_->Success(EncodableValue());
    pending_.reset();
    return;
  }
  ComPtr<IShellItem> item;
  PWSTR selected = nullptr;
  if (SUCCEEDED(hr)) hr = dialog->GetResult(&item);
  if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &selected);
  if (FAILED(hr) || !selected) {
    if (selected) ::CoTaskMemFree(selected);
    pending_->Error("EXPORT_FAILED", "The system returned no destination.");
    pending_.reset();
    return;
  }
  const auto destination = AbsolutePath(selected);
  ::CoTaskMemFree(selected);
  if (destination.empty()) {
    pending_->Error("EXPORT_FAILED", "The destination path is invalid.");
    pending_.reset();
    return;
  }
  if (::GetFileAttributesW(destination.c_str()) != INVALID_FILE_ATTRIBUTES) {
    pending_->Error("EXPORT_DESTINATION_EXISTS", "Choose a new name; existing files are kept.");
    pending_.reset();
    return;
  }
  copy_state_ = std::make_shared<CopyState>();
  copy_state_->destination = destination;
  const auto state = copy_state_;
  const HWND target = window_;
  try {
    worker_ = std::thread([source, state, target]() {
      try {
        CopyReceivedFile(source, state);
      } catch (const std::bad_alloc&) {
        state->error = ERROR_NOT_ENOUGH_MEMORY;
      } catch (...) {
        state->error = ERROR_GEN_FAILURE;
      }
      ::PostMessageW(target, kExportComplete, 0, 0);
    });
  } catch (...) {
    pending_->Error("EXPORT_FAILED", "The copy could not be started.");
    pending_.reset();
    copy_state_.reset();
  }
}

void StorageChannel::CopyReceivedFile(const std::wstring& source,
    const std::shared_ptr<CopyState>& state) {
  if (!ReceivedSource(source)) {
    state->error = ERROR_FILE_NOT_FOUND;
    return;
  }
  FileHandle input(::CreateFileW(source.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
      OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  if (!input.valid()) { state->error = ::GetLastError(); return; }
  BY_HANDLE_FILE_INFORMATION information{};
  if (!::GetFileInformationByHandle(input.get(), &information) ||
      (information.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
    state->error = ERROR_ACCESS_DENIED;
    return;
  }
  LARGE_INTEGER expected{};
  if (!::GetFileSizeEx(input.get(), &expected) || expected.QuadPart < 0) {
    state->error = ERROR_READ_FAULT;
    return;
  }
  const auto slash = state->destination.find_last_of(L'\\');
  if (slash == std::wstring::npos) { state->error = ERROR_INVALID_NAME; return; }
  GUID id{};
  if (FAILED(::CoCreateGuid(&id))) { state->error = ERROR_GEN_FAILURE; return; }
  std::array<wchar_t, 40> identifier{};
  if (!::StringFromGUID2(id, identifier.data(), static_cast<int>(identifier.size()))) {
    state->error = ERROR_GEN_FAILURE;
    return;
  }
  const auto temporary = state->destination.substr(0, slash + 1) +
      L".file-transfer-" + identifier.data() + L".part";
  TemporaryExport output(::CreateFileW(temporary.c_str(), GENERIC_WRITE | DELETE,
      FILE_SHARE_READ, nullptr, CREATE_NEW,
      FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN | FILE_FLAG_OPEN_REPARSE_POINT,
      nullptr));
  if (!output.file.valid()) { state->error = ::GetLastError(); return; }
  std::array<uint8_t, 64 * 1024> buffer{};
  int64_t copied = 0;
  while (true) {
    if (state->cancel.load()) { state->error = ERROR_CANCELLED; return; }
    DWORD count = 0;
    if (!::ReadFile(input.get(), buffer.data(), static_cast<DWORD>(buffer.size()), &count, nullptr)) {
      state->error = ::GetLastError();
      return;
    }
    if (!count) break;
    DWORD offset = 0;
    while (offset < count) {
      if (state->cancel.load()) { state->error = ERROR_CANCELLED; return; }
      DWORD written = 0;
      if (!::WriteFile(output.file.get(), buffer.data() + offset, count - offset, &written, nullptr) || !written) {
        state->error = ::GetLastError();
        if (state->error == ERROR_SUCCESS) state->error = ERROR_WRITE_FAULT;
        return;
      }
      offset += written;
    }
    copied += count;
  }
  if (copied != expected.QuadPart) { state->error = ERROR_READ_FAULT; return; }
  if (state->cancel.load()) { state->error = ERROR_CANCELLED; return; }
  if (!::FlushFileBuffers(output.file.get())) { state->error = ::GetLastError(); return; }
  // The destination name is published only after the complete copy is flushed.
  // ReplaceIfExists=false also protects against a name created during copying.
  const auto bytes = state->destination.size() * sizeof(wchar_t);
  std::vector<uint8_t> rename_buffer(sizeof(FILE_RENAME_INFO) + bytes);
  auto* rename = reinterpret_cast<FILE_RENAME_INFO*>(rename_buffer.data());
  rename->ReplaceIfExists = FALSE;
  rename->RootDirectory = nullptr;
  rename->FileNameLength = static_cast<DWORD>(bytes);
  std::memcpy(rename->FileName, state->destination.data(), bytes);
  if (!::SetFileInformationByHandle(output.file.get(), FileRenameInfo, rename,
      static_cast<DWORD>(rename_buffer.size()))) {
    state->error = ::GetLastError();
    return;
  }
  output.published = true;
  state->succeeded = true;
}

bool StorageChannel::HandleWindowMessage(UINT message) {
  if (message != kExportComplete) return false;
  FinishExport();
  return true;
}

void StorageChannel::FinishExport() {
  if (worker_.joinable()) worker_.join();
  if (!pending_ || !copy_state_) return;
  const auto state = copy_state_;
  if (state->succeeded) {
    const auto destination = Utf8FromUtf16(state->destination.c_str());
    pending_->Success(EncodableValue(EncodableMap{
      {EncodableValue("status"), EncodableValue("exported")},
      {EncodableValue("destinationLabel"), EncodableValue(destination)},
      {EncodableValue("platformReference"), EncodableValue(destination)},
    }));
  } else if (state->error == ERROR_FILE_EXISTS || state->error == ERROR_ALREADY_EXISTS) {
    pending_->Error("EXPORT_DESTINATION_EXISTS", "Choose a new name; existing files are kept.");
  } else if (state->error == ERROR_CANCELLED || state->error == ERROR_OPERATION_ABORTED) {
    pending_->Error("EXPORT_INTERRUPTED", "The save operation was interrupted.");
  } else {
    pending_->Error("EXPORT_FAILED", "The copy was not saved. The received file remains in the app.");
  }
  pending_.reset();
  copy_state_.reset();
}

void StorageChannel::Shutdown() {
  if (closing_) return;
  closing_ = true;
  channel_->SetMethodCallHandler(nullptr);
  if (copy_state_) copy_state_->cancel.store(true);
  if (worker_.joinable()) {
    // Interrupt a synchronous file I/O if necessary before releasing Flutter.
    ::CancelSynchronousIo(worker_.native_handle());
    worker_.join();
  }
  if (pending_) {
    pending_->Error("EXPORT_INTERRUPTED", "The application closed before confirming the copy.");
    pending_.reset();
  }
  copy_state_.reset();
}
