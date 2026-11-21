import 'package:transfer_core/transfer_core.dart';

/// Validate a remote receipt before using it for UI success or source cleanup.
/// Authenticated transport alone does not make a contradictory response valid.
void validateTransferReceipt(
  TransferManifest expected,
  TransferSnapshot actual, {
  String? transferId,
  String? sourcePeerId,
}) {
  Never invalid() => throw const NetworkException(
    'PROTOCOL_CONFLICT',
    'Inconsistent transfer receipt',
  );
  if (actual.manifest.requestId != expected.requestId ||
      actual.manifest.totalBytes != expected.totalBytes ||
      actual.manifest.files.length != expected.files.length ||
      actual.files.length != expected.files.length ||
      (transferId != null && actual.transferId != transferId) ||
      (sourcePeerId != null && actual.peerId != sourcePeerId)) {
    invalid();
  }
  final files = {for (final file in expected.files) file.fileId: file};
  final manifestsSeen = <String>{};
  final receiptsSeen = <String>{};
  void checkManifest(FileManifest manifest) {
    final original = files[manifest.fileId];
    if (original == null ||
        original.displayName != manifest.displayName ||
        original.sizeBytes != manifest.sizeBytes ||
        original.sha256 != manifest.sha256) {
      invalid();
    }
  }

  for (final manifest in actual.manifest.files) {
    checkManifest(manifest);
    if (!manifestsSeen.add(manifest.fileId)) invalid();
  }
  for (final receipt in actual.files) {
    checkManifest(receipt.manifest);
    if (!receiptsSeen.add(receipt.fileId) ||
        receipt.offset < 0 ||
        receipt.offset > receipt.manifest.sizeBytes ||
        (receipt.state == FileState.committed &&
            receipt.offset != receipt.manifest.sizeBytes)) {
      invalid();
    }
  }
  if (actual.state == TransferState.completed &&
      actual.files.any((file) => file.state != FileState.committed)) {
    invalid();
  }
}
