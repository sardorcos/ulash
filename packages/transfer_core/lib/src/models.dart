import 'dart:convert';

/// Wire and storage limits for the foreground alpha. These are product limits,
/// not limits of HTTPS or the platforms.
abstract final class TransferLimits {
  static const int maxFileBytes = 10 * 1024 * 1024 * 1024;
  static const int maxTransferBytes = 50 * 1024 * 1024 * 1024;
  static const int maxFiles = 1000;
  static const int maxManifestBytes = 2 * 1024 * 1024;
  static const int maxSignedInt64 = 9223372036854775807;
}

/// Bidirectional overrides, isolates, marks and zero-width characters can make
/// `invoice\u202Efdp.exe` look like `invoiceexe.pdf`. They are never needed
/// in a stored or displayed file name.
final RegExp invisibleNameCharacters = RegExp(
  '[\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\u061C\uFEFF'
  '\u3164\u115F\u1160\u00AD\u2028\u2029\u180E\uFFA0\u034F]',
);

/// Removes invisible/bidirectional formatting characters from a display name.
String stripInvisibleNameCharacters(String input) =>
    input.replaceAll(invisibleNameCharacters, '');

/// Display-safe text for names shown to the user (file and device names):
/// invisible/bidirectional characters removed and every run of whitespace
/// (including the long space padding used to push an extension out of view)
/// collapsed to a single space.
String sanitizeDisplayText(String input) => stripInvisibleNameCharacters(
  // Line/paragraph separators separate words: keep them as a space.
  input.replaceAll(RegExp('[\u2028\u2029]'), ' '),
).replaceAll(RegExp(r'\s+'), ' ').trim();

const _executableExtensions = {
  'exe', 'com', 'bat', 'cmd', 'ps1', 'psm1', 'vbs', 'vbe', 'js', 'jse', //
  'wsf', 'wsh', 'hta', 'msi', 'msix', 'appx', 'scr', 'pif', 'lnk', 'url', //
  'reg', 'cpl', 'jar', 'dll', 'sys', 'app', 'command', 'sh', 'workflow', //
  'apk', 'ipa',
};

/// True when opening a file with this name may run code (Windows/macOS
/// executables, scripts, installers, shortcuts). The UI warns or refuses
/// instead of launching such files directly.
bool isPotentiallyExecutable(String fileName) {
  final name = sanitizeDisplayText(fileName).toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return false;
  final extension = name.substring(dot + 1).replaceAll(RegExp(r'[. ]+$'), '');
  return _executableExtensions.contains(extension);
}

/// Validates an optional folder path inside a transfer (protocol minor 1):
/// forward-slash separated, 1–8 segments, each a plain name (no `.`, `..`,
/// empty, control or path characters), at most 240 characters.
String? validateRelativeDirectory(Object? value) {
  if (value == null) return null;
  if (value is! String ||
      value.isEmpty ||
      value.length > 240 ||
      value.startsWith('/') ||
      value.endsWith('/')) {
    throw const StorageException('INVALID_MANIFEST', 'Invalid folder path.');
  }
  final segments = value.split('/');
  if (segments.length > 8 ||
      segments.any(
        (segment) =>
            segment.isEmpty ||
            segment == '.' ||
            segment == '..' ||
            segment.trim().isEmpty ||
            segment.runes.length > 120 ||
            RegExp(r'[\\:\x00-\x1f\x7f]').hasMatch(segment) ||
            invisibleNameCharacters.hasMatch(segment),
      )) {
    throw const StorageException('INVALID_MANIFEST', 'Invalid folder path.');
  }
  return value;
}

class StorageException implements Exception {
  const StorageException(this.code, this.message, {this.offset});

  final String code;
  final String message;
  final int? offset;

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (offset != null) 'durableOffset': offset.toString(),
  };

  @override
  String toString() => 'StorageException($code): $message';
}

int parseWireUint64(Object? value, String field) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(value)) {
    throw StorageException(
      'INVALID_MANIFEST',
      '$field must be a canonical unsigned decimal string.',
    );
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0 || parsed > TransferLimits.maxSignedInt64) {
    throw StorageException('INVALID_MANIFEST', '$field exceeds signed int64.');
  }
  return parsed;
}

String _string(Map<String, dynamic> value, String name) {
  final result = value[name];
  if (result is! String) {
    throw StorageException('INVALID_MANIFEST', '$name must be a string.');
  }
  return result;
}

void validateOpaqueId(String value, String field) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value)) {
    throw StorageException('INVALID_MANIFEST', 'Invalid $field.');
  }
}

class FileManifest {
  FileManifest({
    required this.fileId,
    required this.displayName,
    required this.sizeBytes,
    required this.sha256,
    this.mimeType,
    String? relativeDirectory,
  }) : relativeDirectory = validateRelativeDirectory(relativeDirectory) {
    validateOpaqueId(fileId, 'fileId');
    if (displayName.isEmpty ||
        displayName.runes.length > 512 ||
        displayName == '.' ||
        displayName == '..' ||
        RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(displayName)) {
      throw const StorageException('INVALID_MANIFEST', 'Invalid file name.');
    }
    if (sizeBytes < 0 || sizeBytes > TransferLimits.maxFileBytes) {
      throw const StorageException('FILE_TOO_LARGE', 'Unsupported file size.');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const StorageException('INVALID_MANIFEST', 'Invalid SHA-256.');
    }
    if (mimeType != null &&
        (mimeType!.length > 255 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(mimeType!))) {
      throw const StorageException('INVALID_MANIFEST', 'Invalid MIME type.');
    }
  }

  final String fileId;
  final String displayName;

  /// The name to show in UI and use for local files: the wire name without
  /// invisible bidirectional/zero-width characters (never empty).
  String get visibleName {
    final cleaned = sanitizeDisplayText(displayName);
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  final int sizeBytes;
  final String sha256;
  final String? mimeType;

  /// Folder of this file inside the transfer (`Photos/2026`), or null for a
  /// top-level file. Requires protocol minor 1 on the receiver.
  final String? relativeDirectory;

  factory FileManifest.fromJson(Map<String, dynamic> json) => FileManifest(
    fileId: _string(json, 'fileId'),
    displayName: _string(json, 'displayName'),
    sizeBytes: parseWireUint64(json['sizeBytes'], 'sizeBytes'),
    sha256: _string(json, 'sha256'),
    mimeType: json['mimeType'] == null ? null : _string(json, 'mimeType'),
    relativeDirectory: json['relativeDirectory'] == null
        ? null
        : _string(json, 'relativeDirectory'),
  );

  Map<String, dynamic> toJson() => {
    'fileId': fileId,
    'displayName': displayName,
    'sizeBytes': sizeBytes.toString(),
    'mimeType': mimeType,
    'sha256': sha256,
    // Omitted for top-level files so protocol-minor-0 manifests are unchanged.
    if (relativeDirectory != null) 'relativeDirectory': relativeDirectory,
  };
}

class TransferManifest {
  TransferManifest({required this.requestId, required List<FileManifest> files})
    : files = List.unmodifiable(files) {
    validateOpaqueId(requestId, 'requestId');
    if (files.isEmpty || files.length > TransferLimits.maxFiles) {
      throw const StorageException('INVALID_MANIFEST', 'Invalid file count.');
    }
    if (files.map((f) => f.fileId).toSet().length != files.length) {
      throw const StorageException('INVALID_MANIFEST', 'Duplicate fileId.');
    }
    if (totalBytes > TransferLimits.maxTransferBytes) {
      throw const StorageException(
        'TRANSFER_TOO_LARGE',
        'Package is too large.',
      );
    }
    if (utf8.encode(jsonEncode(toJson())).length >
        TransferLimits.maxManifestBytes) {
      throw const StorageException(
        'INVALID_MANIFEST',
        'Manifest is too large.',
      );
    }
  }

  final String requestId;
  final List<FileManifest> files;
  int get totalBytes => files.fold(0, (total, file) => total + file.sizeBytes);

  /// True when any file carries a folder path (needs protocol minor 1).
  bool get usesFolders => files.any((file) => file.relativeDirectory != null);

  factory TransferManifest.fromJson(Map<String, dynamic> json) {
    if (json['protocolMajor'] != null && json['protocolMajor'] != 1) {
      throw const StorageException(
        'UNSUPPORTED_PROTOCOL',
        'Only protocol major 1 is supported.',
      );
    }
    if (json['mode'] != null && json['mode'] != 'push') {
      throw const StorageException('UNSUPPORTED_MODE', 'Alpha supports push.');
    }
    final raw = json['files'];
    if (raw is! List || raw.length > TransferLimits.maxFiles) {
      throw const StorageException('INVALID_MANIFEST', 'files must be a list.');
    }
    final result = TransferManifest(
      requestId: _string(json, 'requestId'),
      files: raw.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const StorageException(
            'INVALID_MANIFEST',
            'Invalid file item.',
          );
        }
        return FileManifest.fromJson(item);
      }).toList(),
    );
    if (json.containsKey('totalBytes') &&
        parseWireUint64(json['totalBytes'], 'totalBytes') !=
            result.totalBytes) {
      throw const StorageException('INVALID_MANIFEST', 'totalBytes disagrees.');
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'protocolMajor': 1,
    // Minor 1 only when a folder feature is used: older receivers see the
    // exact same manifest bytes as before for flat transfers.
    'protocolMinor': usesFolders ? 1 : 0,
    'mode': 'push',
    'files': files.map((file) => file.toJson()).toList(),
    'totalBytes': totalBytes.toString(),
  };
}

enum FileState {
  offered,
  accepted,
  transferring,
  paused,
  verifying,
  committing,
  committed,
  rejected,
  cancelled,
  failed,
  expired;

  String get wireName => name;
  static FileState fromWire(String value) => values.firstWhere(
    (state) => state.wireName == value,
    orElse: () => throw const StorageException('INVALID_STATE', 'File state.'),
  );
}

enum TransferState {
  offered,
  accepted,
  transferring,
  paused,
  completed,
  partiallyCompleted,
  rejected,
  cancelled,
  failed,
  expired;

  String get wireName =>
      this == partiallyCompleted ? 'partially_completed' : name;
  static TransferState fromWire(String value) => values.firstWhere(
    (state) => state.wireName == value,
    orElse: () =>
        throw const StorageException('INVALID_STATE', 'Transfer state.'),
  );
}

class FileSnapshot {
  const FileSnapshot({
    required this.manifest,
    required this.offset,
    required this.state,
    required this.storageIncarnationId,
    this.finalPath,
    this.errorCode,
  });

  final FileManifest manifest;
  final int offset;
  final FileState state;
  final String storageIncarnationId;
  final String? finalPath;
  final String? errorCode;
  String get fileId => manifest.fileId;
  int get durableOffset => offset;

  Map<String, dynamic> toJson({bool includeLocalPaths = false}) => {
    'manifest': manifest.toJson(),
    'offset': offset.toString(),
    'state': state.wireName,
    'storageIncarnationId': storageIncarnationId,
    'errorCode': errorCode,
    if (includeLocalPaths && finalPath != null) 'finalPath': finalPath,
  };

  factory FileSnapshot.fromJson(Map<String, dynamic> json) => FileSnapshot(
    manifest: FileManifest.fromJson(
      Map<String, dynamic>.from(json['manifest'] as Map),
    ),
    offset: parseWireUint64(json['offset'], 'offset'),
    state: FileState.fromWire(_string(json, 'state')),
    storageIncarnationId: _string(json, 'storageIncarnationId'),
    finalPath: json['finalPath'] as String?,
    errorCode: json['errorCode'] as String?,
  );
}

class TransferSnapshot {
  TransferSnapshot({
    required this.transferId,
    required this.peerId,
    required this.manifest,
    required this.state,
    required List<FileSnapshot> files,
    required this.createdAt,
    required this.updatedAt,
    this.pausedBySource = false,
    this.pausedBySink = false,
    this.offerExpiresAt,
  }) : files = List.unmodifiable(files);

  final String transferId;
  final String peerId;
  final TransferManifest manifest;
  final TransferState state;
  final List<FileSnapshot> files;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pausedBySource;
  final bool pausedBySink;

  /// Sink-authoritative display deadline. Local wall time is not used to
  /// authorize consent; the store enforces a monotonic lifetime while open.
  final DateTime? offerExpiresAt;
  String get id => transferId;
  int get durableBytes => files.fold(0, (value, file) => value + file.offset);

  Map<String, dynamic> toJson({bool includeLocalPaths = false}) => {
    'transferId': transferId,
    'peerId': peerId,
    'manifest': manifest.toJson(),
    'state': state.wireName,
    'files': files
        .map((file) => file.toJson(includeLocalPaths: includeLocalPaths))
        .toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'pausedBySource': pausedBySource,
    'pausedBySink': pausedBySink,
    if (offerExpiresAt != null)
      'offerExpiresAt': offerExpiresAt!.toUtc().toIso8601String(),
  };

  factory TransferSnapshot.fromJson(Map<String, dynamic> json) =>
      TransferSnapshot(
        transferId: _string(json, 'transferId'),
        peerId: _string(json, 'peerId'),
        manifest: TransferManifest.fromJson(
          Map<String, dynamic>.from(json['manifest'] as Map),
        ),
        state: TransferState.fromWire(_string(json, 'state')),
        files: (json['files'] as List)
            .map(
              (file) =>
                  FileSnapshot.fromJson(Map<String, dynamic>.from(file as Map)),
            )
            .toList(),
        createdAt: DateTime.parse(_string(json, 'createdAt')).toUtc(),
        updatedAt: DateTime.parse(_string(json, 'updatedAt')).toUtc(),
        pausedBySource: json['pausedBySource'] == true,
        pausedBySink: json['pausedBySink'] == true,
        offerExpiresAt: json['offerExpiresAt'] == null
            ? null
            : DateTime.parse(_string(json, 'offerExpiresAt')).toUtc(),
      );
}

class PreparedFile {
  const PreparedFile({
    required this.manifest,
    required this.path,
    required this.createdAt,
  });
  final FileManifest manifest;
  final String path;
  final DateTime createdAt;
}

class PreparedTransfer {
  const PreparedTransfer({
    required this.manifest,
    required this.peerId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.remoteTransferId,
  });
  final TransferManifest manifest;
  final String peerId;
  final String state;
  final String? remoteTransferId;
  final DateTime createdAt;
  final DateTime updatedAt;
  String get requestId => manifest.requestId;
}
