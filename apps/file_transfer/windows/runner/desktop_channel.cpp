#include "desktop_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
// windows.h must come first for the shell headers.
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <cwctype>
#include <string>

#include "utils.h"

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;

std::wstring Wide(const std::string& input) {
  if (input.empty() || input.size() > 32768 || input.find('\0') != std::string::npos) return {};
  const int count = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
                                          static_cast<int>(input.size()), nullptr, 0);
  if (!count) return {};
  std::wstring result(static_cast<size_t>(count), L'\0');
  if (!::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
                             static_cast<int>(input.size()), result.data(), count)) return {};
  return result;
}

std::wstring PathArgument(const EncodableValue* arguments) {
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (!map) return {};
  const auto entry = map->find(EncodableValue("path"));
  if (entry == map->end()) return {};
  const auto* value = std::get_if<std::string>(&entry->second);
  if (!value) return {};
  std::wstring path = Wide(*value);
  if (path.empty()) return {};
  const DWORD needed = ::GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
  if (!needed || needed > 32768) return {};
  std::wstring full(needed, L'\0');
  const DWORD copied = ::GetFullPathNameW(path.c_str(), needed, full.data(), nullptr);
  if (!copied || copied >= needed) return {};
  full.resize(copied);
  // No alternate data streams or device paths: only a plain "X:\..." or UNC file.
  if (full.find(L':', 2) != std::wstring::npos) return {};
  return full;
}

bool BoolArgument(const EncodableValue* arguments, const char* key) {
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (!map) return false;
  const auto entry = map->find(EncodableValue(key));
  if (entry == map->end()) return false;
  const auto* value = std::get_if<bool>(&entry->second);
  return value && *value;
}

bool IsRegularFile(const std::wstring& path) {
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         !(attributes & FILE_ATTRIBUTE_DIRECTORY) &&
         !(attributes & FILE_ATTRIBUTE_REPARSE_POINT);
}

// Types Windows would execute, install, mount or interpret instead of
// opening as a plain document. Keep this a SUPERSET of transfer_core's
// `isPotentiallyExecutable` list (packages/transfer_core/lib/src/models.dart):
// the Dart UI warns using that list, this native gate refuses to launch.
bool IsExecutableType(const std::wstring& path) {
  static const wchar_t* kTypes[] = {
      // Programs, libraries and scripts.
      L".exe", L".com", L".bat", L".cmd", L".ps1", L".psm1", L".ps1xml", L".vbs", L".vbe",
      L".js", L".jse", L".wsf", L".wsh", L".wsc", L".hta", L".scr", L".pif", L".cpl",
      L".dll", L".sys", L".xll", L".jar", L".msc", L".gadget", L".inf", L".reg",
      L".sh", L".command", L".app", L".workflow",
      // Installers and packages.
      L".msi", L".msp", L".mst", L".msix", L".msixbundle", L".appx", L".appxbundle",
      L".appinstaller", L".appref-ms", L".application", L".apk", L".ipa",
      // Disk images Explorer mounts (and then autoplays/opens).
      L".iso", L".img", L".vhd", L".vhdx",
      // Shortcuts, shell/search links and active documents.
      L".lnk", L".url", L".website", L".scf", L".search-ms", L".searchconnector-ms",
      L".settingcontent-ms", L".library-ms", L".diagcab", L".chm", L".mht", L".mhtml"};
  // Win32 strips trailing dots and spaces when it opens a file, so
  // "invoice.exe. " runs as an .exe: strip them before looking at the type.
  std::wstring name = path;
  while (!name.empty() && (name.back() == L'.' || name.back() == L' ')) name.pop_back();
  const size_t dot = name.find_last_of(L'.');
  const size_t slash = name.find_last_of(L"\\/");
  if (dot == std::wstring::npos || (slash != std::wstring::npos && dot < slash)) return false;
  std::wstring ext = name.substr(dot);
  std::transform(ext.begin(), ext.end(), ext.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  for (const auto* type : kTypes) {
    if (ext == type) return true;
  }
  return false;
}

// True when running as an MSIX package (package identity). Looked up
// dynamically so the runner has no hard dependency on appmodel exports.
bool HasPackageIdentity() {
  using GetCurrentPackageFullNameFn = LONG(WINAPI*)(UINT32*, PWSTR);
  static const auto fn = reinterpret_cast<GetCurrentPackageFullNameFn>(
      ::GetProcAddress(::GetModuleHandleW(L"kernel32.dll"), "GetCurrentPackageFullName"));
  if (!fn) return false;
  UINT32 length = 0;
  // ERROR_INSUFFICIENT_BUFFER: packaged; APPMODEL_ERROR_NO_PACKAGE (15700): not.
  return fn(&length, nullptr) == ERROR_INSUFFICIENT_BUFFER;
}

// Under MSIX, files the app writes below %LOCALAPPDATA%/%APPDATA% are
// redirected to the package's private LocalCache. Explorer and the handler
// apps run outside the package and would not find them at the logical path,
// so hand the shell the real (final) path. Unpackaged: the path unchanged.
std::wstring ShellPath(const std::wstring& path) {
  if (!HasPackageIdentity()) return path;
  HANDLE file = ::CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                              OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
  if (file == INVALID_HANDLE_VALUE) return path;
  std::wstring final_path(MAX_PATH, L'\0');
  DWORD length = ::GetFinalPathNameByHandleW(file, final_path.data(),
                                             static_cast<DWORD>(final_path.size()),
                                             FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  if (length >= final_path.size()) {
    final_path.resize(length + 1);
    length = ::GetFinalPathNameByHandleW(file, final_path.data(),
                                         static_cast<DWORD>(final_path.size()),
                                         FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  }
  ::CloseHandle(file);
  if (length == 0 || length >= final_path.size()) return path;
  final_path.resize(length);
  if (final_path.rfind(L"\\\\?\\UNC\\", 0) == 0) return L"\\\\" + final_path.substr(8);
  if (final_path.rfind(L"\\\\?\\", 0) == 0) return final_path.substr(4);
  return final_path;
}

std::string KnownFolder(REFKNOWNFOLDERID id, const wchar_t* child) {
  PWSTR known = nullptr;
  if (FAILED(::SHGetKnownFolderPath(id, KF_FLAG_CREATE, nullptr, &known))) return {};
  std::wstring path(known);
  ::CoTaskMemFree(known);
  if (child) {
    path += L"\\";
    path += child;
    ::CreateDirectoryW(path.c_str(), nullptr);  // Already existing is fine.
  }
  return Utf8FromUtf16(path.c_str());
}

std::string OpenFile(const std::wstring& path, bool allow_executable) {
  if (path.empty() || !IsRegularFile(path)) return "missing";
  if (IsExecutableType(path) && !allow_executable) return "blocked";
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOASYNC;
  info.lpVerb = L"open";
  const std::wstring shell_path = ShellPath(path);
  info.lpFile = shell_path.c_str();  // The exact file: no command line is parsed.
  info.nShow = SW_SHOWNORMAL;
  return ::ShellExecuteExW(&info) ? "opened" : "failed";
}

bool RevealInFolder(const std::wstring& path) {
  if (path.empty() || ::GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) return false;
  PIDLIST_ABSOLUTE item = nullptr;
  const std::wstring shell_path = ShellPath(path);
  if (FAILED(::SHParseDisplayName(shell_path.c_str(), nullptr, &item, 0, nullptr)) || !item) {
    return false;
  }
  const HRESULT result = ::SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
  ::CoTaskMemFree(item);
  return SUCCEEDED(result);
}

// Mark-of-the-Web: SmartScreen and Office treat the file as downloaded.
bool MarkFromInternet(const std::wstring& path) {
  if (path.empty() || !IsRegularFile(path)) return false;
  const std::wstring stream = path + L":Zone.Identifier";
  HANDLE file = ::CreateFileW(stream.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;  // e.g. FAT/exFAT volumes.
  static const char kContent[] = "[ZoneTransfer]\r\nZoneId=3\r\n";
  DWORD written = 0;
  const BOOL ok = ::WriteFile(file, kContent, static_cast<DWORD>(sizeof(kContent) - 1),
                              &written, nullptr);
  ::CloseHandle(file);
  return ok && written == sizeof(kContent) - 1;
}
}  // namespace

DesktopChannel::DesktopChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "file_transfer/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([](const auto& call, auto result) {
    const std::string& method = call.method_name();
    const EncodableValue* arguments = call.arguments();
    if (method == "openFile") {
      result->Success(EncodableValue(
          OpenFile(PathArgument(arguments), BoolArgument(arguments, "allowExecutable"))));
    } else if (method == "revealInFolder") {
      result->Success(EncodableValue(RevealInFolder(PathArgument(arguments))));
    } else if (method == "markFromInternet") {
      result->Success(EncodableValue(MarkFromInternet(PathArgument(arguments))));
    } else if (method == "localDataDirectory") {
      // MSIX: AppData writes are virtualised into the package's LocalCache,
      // which never roams and is removed on uninstall, and a packaged install
      // has no 1.0 Roaming data to move. Return null so Dart keeps its
      // application-support directory and skips the Roaming → LocalAppData
      // migration (legacy root == current root).
      if (HasPackageIdentity()) {
        result->Success(EncodableValue());
        return;
      }
      const std::string path = KnownFolder(FOLDERID_LocalAppData, L"Ulash");
      result->Success(path.empty() ? EncodableValue() : EncodableValue(path));
    } else if (method == "downloadsDirectory") {
      const std::string path = KnownFolder(FOLDERID_Downloads, nullptr);
      result->Success(path.empty() ? EncodableValue() : EncodableValue(path));
    } else {
      result->NotImplemented();
    }
  });
}
