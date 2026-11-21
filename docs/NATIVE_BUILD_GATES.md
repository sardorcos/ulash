# Native build gates

The repository includes optional GitHub Actions jobs for Android, iOS and
Windows. The iOS and Windows jobs are **configured source, not executed build
evidence**. They do not publish to stores, install on a device, or sign a
production release. This repository has no configured external Git remote.

## Local builds

Use Flutter **3.50.1**, the checked-in dependency lockfiles, and a native host
with the platform's normal development tools. Run `flutter pub get
--enforce-lockfile` from `apps/file_transfer` before compiling.

| Target | Build host | Command from `apps/file_transfer` | Expected output |
|---|---|---|---|
| Android ARM64 debug | Linux, macOS or Windows with Android SDK and a full JDK 21 | `flutter build apk --debug --target-platform android-arm64 --split-per-abi --no-pub` | `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` |
| iOS device code without signing | macOS with Xcode and its iOS SDK | `flutter build ios --release --no-codesign --no-pub` | `build/ios/iphoneos/Runner.app`, not an installable signed IPA |
| Windows x64 | Windows x64 host with Visual Studio's Desktop development with C++ workload | `flutter build windows --release --no-pub` | Complete `build/windows/x64/runner/Release` directory |

The Windows executable depends on the adjacent DLLs and `data` directory.
Flutter 3.50.1 selects the Windows target architecture from its host; the
checked-in command does not pass an unsupported target-platform option.
Distribute the complete bundle only after testing it; copying the EXE alone
is insufficient. The unsigned iOS product is a compile gate. Installing on an
iPhone requires the user's Apple development team, provisioning, signing and
device authorization. No such credentials are included.

## Optional Actions workflow

After the user connects this source to their own GitHub repository, the
`Verify source` workflow can be run manually with `build_android`, `build_ios`
and/or `build_windows`. All options default to false. Normal push/PR runs only
analyze and test the common code on Linux. Workflow permissions are read-only;
checkout does not retain credentials.

The native jobs currently compile and retain their logs in the Actions run.
They do not upload binary artifacts, publish a release, request a signing key,
or establish device acceptance. `macos-latest` and `windows-latest` choose a
hosted toolchain; any platform error must be resolved and recorded before a
successful native build is claimed.

`scripts/install_flutter_ci.py` selects a pinned archive for Linux x64,
macOS x64/ARM64, or Windows x64, verifies its SHA-256 and adds `flutter/bin` to
the CI path. It requires Python 3.12 or newer. Unsupported architectures fail
explicitly. Archive hashes were read from the official release manifests:

- https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
- https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json
- https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json

The installer does not change SDK sources, downgrade TLS or choose a mirror.
`--print-plan` reports the chosen URL and digest without a download.

## Evidence required after compiling

Record the source revision, SDK/Xcode/Visual Studio version, build command,
exit code, artifact SHA-256 and size. Then perform the physical matrix in
`DEVICE_TEST_MATRIX.md`, including permissions, identity persistence, local
network discovery, interrupted transfer/resume and file hashes. Export to an
external document provider needs a separate real-platform check, including
cancellation, provider errors and insufficient space.
