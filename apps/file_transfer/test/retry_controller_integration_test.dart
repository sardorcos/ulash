import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_transfer/services/app_runtime.dart';
import 'package:file_transfer/services/network_retry_policy.dart';
import 'package:file_transfer/services/outgoing_journal.dart';
import 'package:file_transfer/services/transfer_app_controller.dart';
import 'package:file_transfer/ui/app_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:transfer_core/transfer_core.dart' as core;

class _RealHttpOverrides extends HttpOverrides {}

Future<void> _network(Future<void> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

Future<void> _wait(bool Function() ready, String reason) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed > const Duration(seconds: 15)) fail(reason);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Harness {
  _Harness(this.root, this.senderSecrets, this.receiverSecrets);
  final Directory root;
  final core.MemorySecretStore senderSecrets;
  final core.MemorySecretStore receiverSecrets;
  late final core.DeviceIdentity identity;
  late final core.TrustedPeerStore receiverPeers;
  late final core.DurableInbox inbox;
  late final core.CoreHost host;
  late final TransferAppController sender;
  bool hostClosed = false;
  bool closed = false;

  static Future<_Harness> create({
    Future<void> Function(Duration)? retryDelay,
  }) async {
    final root = await Directory.systemTemp.createTemp('retry-controller-');
    final result = _Harness(
      root,
      core.MemorySecretStore(),
      core.MemorySecretStore(),
    );
    result.identity = await core.DeviceIdentity.loadOrCreate(
      result.receiverSecrets,
      displayName: 'Retry receiver',
    );
    result.receiverPeers = core.TrustedPeerStore(result.receiverSecrets);
    result.inbox = await core.DurableInbox.open(
      Directory(p.join(root.path, 'sink')),
    );
    result.host = core.CoreHost(
      identity: result.identity,
      peers: result.receiverPeers,
      inbox: result.inbox,
    );
    await result.host.start();
    result.sender = TransferAppController(
      runtime: AppRuntime(
        secrets: result.senderSecrets,
        storageDirectory: () async => Directory(p.join(root.path, 'source')),
        ensurePermission: () async => true,
        addresses: () async => ['127.0.0.1'],
        listenAddress: InternetAddress.loopbackIPv4,
        mobileLifecycle: true,
        retryPolicy: NetworkRetryPolicy(randomUnit: () => 0),
        retryDelay: retryDelay,
      ),
    );
    await result.sender.initialize();
    expect(result.sender.errorMessage, isNull);
    final pairing = result.sender.pairFromText(
      result.host.createInvite().encode(),
    );
    await _wait(
      () => result.host.pendingPairings.isNotEmpty,
      'Pairing did not reach real host',
    );
    await result.host.approvePairing(
      result.host.pendingPairings.single.requestId,
    );
    await pairing;
    await _wait(
      () => result.sender.peers.any((peer) => peer.isTrusted && peer.isOnline),
      'Paired receiver did not become reachable',
    );
    return result;
  }

  Directory get sourceData =>
      Directory(p.join(root.path, 'source', 'file-transfer-v1'));

  Future<List<int>> send({bool deleteOriginal = false}) async {
    final payload = List<int>.generate(
      128 * 1024 + 17,
      (i) => (i * 7 + 11) & 255,
    );
    final source = File(p.join(root.path, 'original.dat'));
    await source.writeAsBytes(payload, flush: true);
    await sender.addSourcePaths([source.path]);
    expect(sender.errorMessage, isNull);
    if (deleteOriginal) await source.delete();
    await sender.sendTo(identity.peerId);
    expect(sender.errorMessage, isNull);
    return payload;
  }

  Future<void> stopHost() async {
    if (hostClosed) return;
    hostClosed = true;
    await host.close();
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    await sender.shutdown();
    sender.dispose();
    await stopHost();
    await inbox.close();
    await receiverPeers.close();
    senderSecrets.clear();
    receiverSecrets.clear();
    await root.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'five automatic retries exhaust once; explicit resume gets a new budget',
    () => _network(() async {
      final delays = <Duration>[];
      final h = await _Harness.create(
        retryDelay: (duration) async => delays.add(duration),
      );
      try {
        await h.stopHost();
        await h.send(deleteOriginal: true);
        await _wait(
          () => h.sender.transfers.single.canResume && delays.length == 5,
          'Retry budget did not stop after five waits',
        );
        final originalId = h.sender.transfers.single.id;
        expect(h.sender.transfers.single.phase, TransferPhase.paused);
        expect(delays.map((d) => d.inSeconds), [1, 2, 4, 8, 16]);
        expect(
          h.sender.transfers.single.detail,
          contains('5 повторных попыток'),
        );
        await h.sender.resumeTransfer(originalId);
        await _wait(
          () => h.sender.transfers.single.canResume && delays.length == 10,
          'Explicit resume did not finish its new finite retry budget',
        );
        expect(h.sender.transfers.single.id, originalId);
        expect(h.sender.transfers, hasLength(1));
        await h.sender.shutdown();
        final outbox = await core.DurableOutbox.open(
          Directory(p.join(h.sourceData.path, 'outbox')),
        );
        expect(
          outbox.list(),
          hasLength(1),
          reason: 'No receipt means the sole staged copy must survive',
        );
        await outbox.close();
        final journal = OutgoingJournal(
          Directory(p.join(h.sourceData.path, 'journal')),
        );
        final recovered = journal.recover().single;
        expect(recovered.localState, 'paused');
        expect('out:${recovered.manifest.requestId}', originalId);
        journal.close();
      } finally {
        await h.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 40)),
  );

  for (final action in [
    'pause',
    'cancel',
    'background',
    'revoke',
    'shutdown',
  ]) {
    test(
      '$action interrupts pending backoff and never restarts on a late timer',
      () => _network(() async {
        final gate = Completer<void>();
        var waits = 0;
        final h = await _Harness.create(
          retryDelay: (_) {
            waits++;
            return gate.future;
          },
        );
        try {
          await h.stopHost();
          await h.send();
          await _wait(() => waits == 1, 'Did not enter backoff');
          final id = h.sender.transfers.single.id;
          expect(h.sender.transfers.single.phase, TransferPhase.retrying);
          expect(h.sender.transfers.single.canPause, isTrue);
          switch (action) {
            case 'pause':
              await h.sender.pauseTransfer(id);
            case 'cancel':
              await h.sender.cancelTransfer(id);
            case 'background':
              h.sender.didChangeAppLifecycleState(AppLifecycleState.paused);
            case 'revoke':
              await h.sender.revokePeer(h.identity.peerId);
            case 'shutdown':
              await h.sender.shutdown().timeout(const Duration(seconds: 3));
          }
          if (action != 'shutdown') {
            await _wait(
              () => h.sender.transfers.single.canResume,
              'Run did not stop promptly',
            );
            expect(h.sender.transfers.single.phase, TransferPhase.paused);
          }
          gate.complete();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (action == 'background') {
            h.sender.didChangeAppLifecycleState(AppLifecycleState.resumed);
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(waits, 1);
          expect(h.inbox.list(), isEmpty);
          await h.sender.shutdown();
          final journal = OutgoingJournal(
            Directory(p.join(h.sourceData.path, 'journal')),
          );
          final restored = journal.recover().single;
          expect(
            restored.localState,
            action == 'cancel' ? 'cancelling' : 'paused',
          );
          journal.close();
        } finally {
          if (!gate.isCompleted) gate.complete();
          await h.close();
        }
      }),
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  test(
    'sink pause is preserved and explicit resume only clears source pause',
    () => _network(() async {
      var waits = 0;
      final h = await _Harness.create(retryDelay: (_) async => waits++);
      try {
        await h.send();
        await _wait(() => h.inbox.list().isNotEmpty, 'Offer missing');
        final id = h.inbox.list().single.id;
        await h.inbox.accept(id);
        await h.inbox.pause(id);
        await _wait(
          () => h.sender.transfers.single.canResume,
          'Source did not respect sink pause',
        );
        expect(h.inbox.status(id).durableBytes, 0);
        expect(waits, 0);
        await h.sender.pauseTransfer(h.sender.transfers.single.id);
        expect(h.inbox.status(id).pausedBySource, isTrue);
        expect(h.inbox.status(id).pausedBySink, isTrue);
        await h.sender.resumeTransfer(h.sender.transfers.single.id);
        await _wait(
          () => h.sender.transfers.single.canResume,
          'Explicit resume did not settle',
        );
        expect(h.inbox.status(id).pausedBySource, isFalse);
        expect(h.inbox.status(id).pausedBySink, isTrue);
        expect(h.inbox.status(id).durableBytes, 0);
        expect(waits, 0);
      } finally {
        await h.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'rejection retains the only copy; explicit resend uses a new consent and request ID',
    () => _network(() async {
      var waits = 0;
      final h = await _Harness.create(retryDelay: (_) async => waits++);
      try {
        final bytes = await h.send(deleteOriginal: true);
        await _wait(() => h.inbox.list().isNotEmpty, 'Offer missing');
        final first = h.inbox.list().single;
        await h.inbox.reject(first.id);
        await _wait(
          () => h.sender.transfers.single.canRetry,
          'Rejected staging did not remain reusable',
        );
        expect(
          waits,
          0,
          reason: 'A denied consent never retries automatically',
        );
        final oldId = h.sender.transfers.single.id;
        expect(h.sender.transfers.single.phase, TransferPhase.cancelled);
        await h.sender.retryTransfer(oldId);
        await _wait(
          () => h.inbox.list().length == 2,
          'Explicit resend did not create a new offer',
        );
        final next = h.inbox.list().firstWhere((item) => item.id != first.id);
        expect(next.manifest.requestId, isNot(first.manifest.requestId));
        expect(next.files.single.fileId, first.files.single.fileId);
        expect(next.state, core.TransferState.offered);
        expect(next.durableBytes, 0);
        expect(h.inbox.status(first.id).state, core.TransferState.rejected);
        await h.inbox.accept(next.id);
        await _wait(
          () => h.sender.transfers.any(
            (item) => item.phase == TransferPhase.completed,
          ),
          'Resend did not receive a verified receipt',
        );
        final saved = File(h.inbox.status(next.id).files.single.finalPath!);
        expect(
          await sha256.bind(saved.openRead()).first,
          sha256.convert(bytes),
        );
        expect(
          h.sender.transfers.where((item) => item.id == oldId).single.phase,
          TransferPhase.cancelled,
        );
        await h.sender.refreshStorage();
        expect(h.sender.storageOverview!.temporaryBytes, 0);
        expect(waits, 0);
      } finally {
        await h.close();
      }
    }),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
