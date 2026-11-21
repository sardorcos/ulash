import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_core/transfer_core.dart';

import 'package:file_transfer/services/outgoing_journal.dart';
import 'package:file_transfer/services/receipt_validation.dart';

FileManifest manifestFile(String id) => FileManifest(
  fileId: id,
  displayName: '$id.txt',
  sizeBytes: 3,
  sha256: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
);

TransferSnapshot receipt(
  TransferManifest manifest,
  List<FileSnapshot> files, {
  String transferId = 'remote',
  TransferState state = TransferState.completed,
}) => TransferSnapshot(
  transferId: transferId,
  peerId: 'source',
  manifest: manifest,
  state: state,
  files: files,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

FileSnapshot fileReceipt(
  FileManifest file, {
  int offset = 3,
  FileState state = FileState.committed,
}) => FileSnapshot(
  manifest: file,
  offset: offset,
  state: state,
  storageIncarnationId: 'storage1',
);

void main() {
  test(
    'a final receipt requires each expected file exactly once and committed',
    () {
      final first = manifestFile('first');
      final second = manifestFile('second');
      final manifest = TransferManifest(
        requestId: 'offer',
        files: [first, second],
      );
      validateTransferReceipt(
        manifest,
        receipt(manifest, [fileReceipt(first), fileReceipt(second)]),
        transferId: 'remote',
        sourcePeerId: 'source',
      );
      expect(
        () => validateTransferReceipt(
          manifest,
          receipt(manifest, [fileReceipt(first), fileReceipt(first)]),
        ),
        throwsA(isA<NetworkException>()),
      );
      expect(
        () => validateTransferReceipt(
          manifest,
          receipt(manifest, [fileReceipt(first)]),
        ),
        throwsA(isA<NetworkException>()),
      );
      expect(
        () => validateTransferReceipt(
          manifest,
          receipt(manifest, [
            fileReceipt(first),
            fileReceipt(second, state: FileState.verifying),
          ]),
        ),
        throwsA(isA<NetworkException>()),
      );
    },
  );

  test(
    'receipt for wrong session, source or durable byte count is rejected',
    () {
      final file = manifestFile('first');
      final manifest = TransferManifest(requestId: 'offer', files: [file]);
      expect(
        () => validateTransferReceipt(
          manifest,
          receipt(manifest, [fileReceipt(file)]),
          transferId: 'different',
        ),
        throwsA(isA<NetworkException>()),
      );
      expect(
        () => validateTransferReceipt(
          manifest,
          receipt(manifest, [fileReceipt(file)]),
          sourcePeerId: 'other',
        ),
        throwsA(isA<NetworkException>()),
      );
      expect(
        () => validateTransferReceipt(
          manifest,
          receipt(manifest, [fileReceipt(file, offset: 2)]),
        ),
        throwsA(isA<NetworkException>()),
      );
    },
  );

  test(
    'restart preserves a cancellation intent and never resumes it as upload',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'transfer-journal-test-',
      );
      try {
        final manifest = TransferManifest(
          requestId: 'offer',
          files: [manifestFile('first')],
        );
        final writer = OutgoingJournal(root);
        writer.save(
          OutgoingJob(
            id: 'job',
            peerId: 'peer',
            peerName: 'Receiver',
            manifest: manifest,
            createdAt: DateTime.now(),
            remoteId: 'remote',
            localState: 'cancelling',
          ),
        );
        writer.close();
        final reopened = OutgoingJournal(root);
        final job = reopened.recover().single;
        expect(job.localState, 'cancelling');
        expect(job.remoteId, 'remote');
        expect(job.manifest.requestId, 'offer');
        reopened.close();
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'restart pauses an unfinished upload and keeps a committed receipt',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'transfer-journal-test-',
      );
      try {
        final file = manifestFile('first');
        final manifest = TransferManifest(requestId: 'offer', files: [file]);
        final writer = OutgoingJournal(root);
        writer.save(
          OutgoingJob(
            id: 'active',
            peerId: 'peer',
            peerName: 'Receiver',
            manifest: manifest,
            createdAt: DateTime.now(),
            localState: 'sending',
          ),
        );
        writer.save(
          OutgoingJob(
            id: 'done',
            peerId: 'peer',
            peerName: 'Receiver',
            manifest: manifest,
            createdAt: DateTime.now(),
            localState: 'completed',
            snapshot: receipt(manifest, [fileReceipt(file)]),
          ),
        );
        writer.close();
        final reopened = OutgoingJournal(root);
        final jobs = reopened.recover();
        expect(
          jobs.firstWhere((job) => job.id == 'active').localState,
          'paused',
        );
        final done = jobs.firstWhere((job) => job.id == 'done');
        expect(done.localState, 'completed');
        expect(done.snapshot!.files.single.state, FileState.committed);
        reopened.close();
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
