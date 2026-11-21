/// Host applications must implement this with their platform's protected store.
/// No filesystem/plaintext implementation is provided by the production core.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Volatile storage for tests or an explicitly temporary CLI session ONLY.
/// Closing this store destroys the session's identity and pairing credentials.
final class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);

  void clear() => _values.clear();

  @override
  String toString() => 'MemorySecretStore(temporary, redacted)';
}
