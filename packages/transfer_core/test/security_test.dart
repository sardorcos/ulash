import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:transfer_core/src/security/crypto.dart';
import 'package:transfer_core/src/security/device_identity.dart';
import 'package:transfer_core/src/security/pairing_invite.dart';
import 'package:transfer_core/src/security/pairing_service.dart';
import 'package:transfer_core/src/security/secret_store.dart';
import 'package:transfer_core/src/security/trusted_peer_store.dart';

void main() {
  late DeviceIdentity host;
  late DeviceIdentity client;
  setUpAll(() async {
    host = await DeviceIdentity.generate(displayName: 'Receiver');
    client = await DeviceIdentity.generate(displayName: 'Sender');
  });

  test('identity persists, SPKI differs from certificate hash and secrets are redacted', () async {
    final store = MemorySecretStore();
    final first = await DeviceIdentity.loadOrCreate(
      store,
      displayName: 'Test device',
    );
    final reloaded = await DeviceIdentity.loadOrCreate(
      store,
      displayName: 'Ignored new name',
    );
    expect(reloaded.deviceId, first.deviceId);
    expect(reloaded.serverPin, first.serverPin);
    expect(reloaded.peerId, first.peerId);
    final der = CryptoUtils.getBytesFromPEMString(first.certificatePem);
    expect(base64Encode(sha256.convert(der).bytes), isNot(first.serverPin));
    expect(first.toString(), isNot(contains('PRIVATE KEY')));
    expect(first.publicInfo.keys, isNot(contains('privateKeyPem')));
    await store.write('transfer.identity.v1', '{"version":999}');
    await expectLater(
      DeviceIdentity.loadOrCreate(store, displayName: 'Must not regenerate'),
      throwsFormatException,
    );
  });

  test('random credentials are canonical 256-bit values with independent directions', () {
    final values = List.generate(100, (_) => randomToken());
    expect(values.toSet().length, 100);
    expect(values.every(isCanonicalToken), isTrue);
    expect(isCanonicalToken('123456'), isFalse);
    expect(constantTimeEqual('abc', 'abc'), isTrue);
    expect(constantTimeEqual('abc', 'abd'), isFalse);
    expect(constantTimeEqual('abc', 'abcd'), isFalse);
  });

  test(
    'QR invitation roundtrips and does not expose its secret in toString',
    () {
      final invite = PairingInvite(
        inviteId: 'invitation-1',
        inviteSecret: randomToken(),
        hostPin: host.serverPin,
        displayName: 'My Windows',
        endpoint: Uri.parse('https://192.168.1.12:41414'),
      );
      final parsed = PairingInvite.parse(invite.encode());
      expect(parsed.inviteSecret, invite.inviteSecret);
      expect(parsed.hostPin, host.serverPin);
      expect(parsed.endpoint, invite.endpoint);
      expect(invite.toString(), isNot(contains(invite.inviteSecret)));
      expect(
        () => PairingInvite.parse('https://attacker.invalid/?data=abc'),
        throwsFormatException,
      );
      expect(
        () => PairingInvite(
          inviteId: 'bad',
          inviteSecret: '123456',
          hostPin: host.serverPin,
          displayName: 'Bad',
          endpoint: Uri.parse('https://localhost:1234'),
        ),
        throwsFormatException,
      );
    },
  );

  test('pairing reserves invitation, requires approval, issues directional credentials and revokes', () async {
    final secrets = MemorySecretStore();
    final peers = TrustedPeerStore(secrets);
    final service = PairingService(identity: host, peers: peers);
    await service.load();
    final invite = service.createInvite(Uri.parse('https://127.0.0.1:44444'));
    final reverse = randomToken();
    final body = {
      'requestId': 'first-request',
      'inviteId': invite.inviteId,
      'peerId': client.peerId,
      'serverPin': client.serverPin,
      'displayName': client.displayName,
      'reverseToken': reverse,
    };
    final waiting = await service.request(body, invite.inviteSecret);
    expect(waiting['state'], 'waiting');
    expect(waiting.containsKey('credential'), isFalse);
    expect(peers.list(), isEmpty);
    expect(
      (await service.request(body, invite.inviteSecret))['pairingId'],
      waiting['pairingId'],
    );
    await expectLater(
      service.request({
        ...body,
        'requestId': 'second-request',
      }, invite.inviteSecret),
      throwsA(
        isA<PairingException>().having((e) => e.code, 'code', 'CONFLICT'),
      ),
    );
    await expectLater(
      service.commit(waiting['pairingId'] as String, reverse),
      throwsA(isA<PairingException>()),
    );
    await service.approve('first-request');
    final approved = service.poll('first-request', invite.inviteSecret);
    final forward = approved['credential'] as String;
    expect(forward, isNot(reverse));
    expect(peers.authenticate(forward), isNull);
    final committed = await service.commit(
      waiting['pairingId'] as String,
      forward,
    );
    expect(committed['state'], 'active');
    expect(committed.containsKey('credential'), isFalse);
    expect(peers.authenticate(forward)?.peerId, client.peerId);
    expect(peers.byId(client.peerId)?.outgoingToken, reverse);
    final reloaded = TrustedPeerStore(secrets);
    await reloaded.load();
    expect(reloaded.authenticate(forward)?.peerId, client.peerId);
    await service.revoke(client.peerId);
    expect(peers.authenticate(forward), isNull);
    await expectLater(
      service.commit(waiting['pairingId'] as String, forward),
      throwsA(isA<PairingException>()),
    );
    await peers.close();
    await reloaded.close();
  });

  test('pending manual approval survives host journal reload', () async {
    final secrets = MemorySecretStore();
    final peers = TrustedPeerStore(secrets);
    final original = PairingService(identity: host, peers: peers);
    await original.load();
    final invite = original.createInvite(Uri.parse('https://127.0.0.1:44444'));
    final body = {
      'requestId': 'restart-request',
      'inviteId': invite.inviteId,
      'peerId': client.peerId,
      'serverPin': client.serverPin,
      'displayName': client.displayName,
      'reverseToken': randomToken(),
    };
    await original.request(body, invite.inviteSecret);
    await original.approve('restart-request');
    final restored = PairingService(identity: host, peers: peers);
    await restored.load();
    expect(
      restored.poll('restart-request', invite.inviteSecret)['state'],
      'approved',
    );
    await peers.close();
  });
}
