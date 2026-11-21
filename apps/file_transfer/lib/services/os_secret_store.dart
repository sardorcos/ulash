import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:transfer_core/transfer_core.dart';

/// Failure to unlock/read secure storage propagates. It must never reset an
/// identity, silently replace a peer's key, or downgrade to plain-text files.
class OsSecretStore implements SecretStore {
  const OsSecretStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'file_transfer_v1',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
