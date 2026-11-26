import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:transfer_core/src/network/core_client.dart';
import 'package:transfer_core/src/network/network_error.dart';
import 'package:transfer_core/src/security/crypto.dart';
import 'package:transfer_core/src/security/device_identity.dart';
import 'package:transfer_core/src/security/pairing_invite.dart';
import 'package:transfer_core/src/security/pairing_service.dart';
import 'package:transfer_core/src/security/secret_store.dart';
import 'package:transfer_core/src/security/trusted_peer_store.dart';

Matcher pairingCode(String code) =>
    isA<PairingException>().having((error) => error.code, 'code', code);

void main() {
  late DeviceIdentity host;
  late DeviceIdentity joiner;
  late DeviceIdentity attacker;
  setUpAll(() async {
    host = await DeviceIdentity.generate(displayName: 'Host');
    joiner = await DeviceIdentity.generate(displayName: 'Joiner');
    attacker = await DeviceIdentity.generate(displayName: 'Mallory');
  });

  late PairingService service;
  final endpoint = Uri.parse('https://127.0.0.1:9');

  setUp(() async {
    service = PairingService(
      identity: host,
      peers: TrustedPeerStore(MemorySecretStore()),
    );
    await service.load();
  });

  Map<String, dynamic> body(
    PairingInvite invite,
    DeviceIdentity who, {
    String? commitment,
    String requestId = 'request-1',
  }) => {
    'requestId': requestId,
    'inviteId': invite.inviteId,
    'peerId': who.peerId,
    'serverPin': who.serverPin,
    'displayName': who.displayName,
    'reverseToken': randomToken(),
    'commitment': ?commitment,
  };

  group('commit/reveal', () {
    test(
      'the code exists only after the reveal; approval waits for it',
      () async {
        final invite = service.createInvite(endpoint);
        final nonce = randomToken();
        final response = await service.request(
          body(invite, joiner, commitment: pairingCommitment(nonce)),
          invite.inviteSecret,
        );
        final hostNonce = response['hostNonce'] as String;
        expect(isCanonicalToken(hostNonce), isTrue);
        expect(response['revealed'], isFalse);
        // Not shown (nothing to compare yet) and not approvable.
        expect(service.pending, isEmpty);
        await expectLater(
          service.approve('request-1'),
          throwsA(pairingCode('SAS_PENDING')),
        );
        final revealed = await service.reveal('request-1', {
          'nonce': nonce,
        }, invite.inviteSecret);
        expect(revealed['revealed'], isTrue);
        final pending = service.pending.single;
        expect(pending.legacy, isFalse);
        expect(
          pending.sas,
          pairingSasV2(
            hostNonce: hostNonce,
            joinerNonce: nonce,
            hostPin: host.serverPin,
            joinerPin: joiner.serverPin,
          ),
        );
        // Idempotent for the same nonce.
        await service.reveal('request-1', {
          'nonce': nonce,
        }, invite.inviteSecret);
        await service.approve('request-1');
      },
    );

    test(
      'an attacker cannot steer the code after seeing the host nonce',
      () async {
        // Mallory knows the (published) invitation and Joiner's key. Whatever
        // nonce she commits to, the host nonce is drawn afterwards, and she
        // cannot swap in a different nonce that would give a chosen code.
        final invite = service.createInvite(endpoint, requireCommitment: true);
        final committed = randomToken();
        final response = await service.request(
          body(invite, attacker, commitment: pairingCommitment(committed)),
          invite.inviteSecret,
        );
        final hostNonce = response['hostNonce'] as String;
        // Suppose she found a nonce producing the code Joiner's screen shows.
        final ground = randomToken();
        final wanted = pairingSasV2(
          hostNonce: hostNonce,
          joinerNonce: ground,
          hostPin: host.serverPin,
          joinerPin: attacker.serverPin,
        );
        expect(wanted, matches(RegExp(r'^[0-9]{6}$')));
        await expectLater(
          service.reveal('request-1', {'nonce': ground}, invite.inviteSecret),
          throwsA(pairingCode('COMMITMENT_MISMATCH')),
        );
        // One attempt per invitation: the request is now rejected for good,
        // even with the honest nonce, and the invitation stays reserved.
        await expectLater(
          service.reveal('request-1', {
            'nonce': committed,
          }, invite.inviteSecret),
          throwsA(pairingCode('PAIRING_REJECTED')),
        );
        await expectLater(
          service.request(
            body(
              invite,
              attacker,
              commitment: pairingCommitment(randomToken()),
              requestId: 'request-2',
            ),
            invite.inviteSecret,
          ),
          throwsA(pairingCode('CONFLICT')),
        );
        expect(service.pending, isEmpty);
      },
    );

    test('host nonces are fresh and the commitment is immutable', () async {
      final first = service.createInvite(endpoint);
      final second = service.createInvite(endpoint);
      final commitment = pairingCommitment(randomToken());
      final a = await service.request(
        body(first, joiner, commitment: commitment),
        first.inviteSecret,
      );
      final b = await service.request(
        body(second, joiner, commitment: commitment, requestId: 'request-2'),
        second.inviteSecret,
      );
      expect(a['hostNonce'], isNot(b['hostNonce']));
      // Replaying request-1 with another commitment is a conflict.
      await expectLater(
        service.request(
          body(first, joiner, commitment: pairingCommitment(randomToken())),
          first.inviteSecret,
        ),
        throwsA(pairingCode('CONFLICT')),
      );
    });

    test('legacy joiners work for QR invitations only', () async {
      final qr = service.createInvite(endpoint);
      final response = await service.request(body(qr, joiner), qr.inviteSecret);
      expect(response.containsKey('hostNonce'), isFalse);
      expect(response.containsKey('revealed'), isFalse);
      final pending = service.pending.single;
      expect(pending.legacy, isTrue);
      expect(pending.sas, isNull);
      expect(pending.legacyCode, shortFingerprint(joiner.peerId));
      await service.approve(pending.requestId);

      final nearby = service.createInvite(endpoint, requireCommitment: true);
      await expectLater(
        service.request(
          body(nearby, joiner, requestId: 'request-2'),
          nearby.inviteSecret,
        ),
        throwsA(pairingCode('UPGRADE_REQUIRED')),
      );
    });

    test('commitment syntax is validated', () async {
      final invite = service.createInvite(endpoint);
      await expectLater(
        service.request(
          body(invite, joiner, commitment: 'not-hex'),
          invite.inviteSecret,
        ),
        throwsA(pairingCode('INVALID_REQUEST')),
      );
      expect(() => pairingCommitment('short'), throwsFormatException);
    });
  });

  group('client against a 1.0/1.1 host', () {
    late HttpServer old;
    var sawCommitment = false;
    setUp(() async {
      sawCommitment = false;
      old = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        host.serverContext(),
      );
      old.listen((request) async {
        final text = await utf8.decodeStream(request);
        final json = jsonDecode(text) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        if (json.containsKey('commitment')) {
          sawCommitment = true;
          request.response
            ..statusCode = 400
            ..write(
              jsonEncode({
                'error': {
                  'code': 'INVALID_REQUEST',
                  'message': 'Unexpected pairing fields',
                },
              }),
            );
        } else {
          request.response
            ..statusCode = 202
            ..write(
              jsonEncode({
                'requestId': json['requestId'],
                'pairingId': 'pairing-1',
                'state': 'waiting',
                'hostPeerId': host.peerId,
                'hostPin': host.serverPin,
                'displayName': 'Old host',
                'expiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 2))
                    .toIso8601String(),
              }),
            );
        }
        await request.response.close();
      });
    });
    tearDown(() => old.close(force: true));

    PairingInvite inviteFor({bool discovered = false}) => PairingInvite(
      inviteId: 'invite-1',
      inviteSecret: randomToken(),
      hostPin: host.serverPin,
      displayName: 'Old host',
      endpoint: Uri(scheme: 'https', host: '127.0.0.1', port: old.port),
      discovered: discovered,
    );

    test('a scanned invitation falls back to the key code', () async {
      final invite = inviteFor();
      final client = CoreClient(
        endpoint: invite.endpoint,
        serverPin: host.serverPin,
      );
      final peers = TrustedPeerStore(MemorySecretStore());
      try {
        final progress = await client.requestPairing(
          invite,
          identity: joiner,
          peers: peers,
        );
        expect(sawCommitment, isTrue);
        expect(progress.legacy, isTrue);
        expect(progress.sas, isNull);
        expect(progress.legacyCode, shortFingerprint(joiner.peerId));
        final code = await client.pendingPairingCode(peers);
        expect(code?.legacy, isTrue);
        expect(code?.code, shortFingerprint(joiner.peerId));
      } finally {
        client.close();
      }
    });

    test('a discovered invitation never downgrades', () async {
      final invite = inviteFor(discovered: true);
      final client = CoreClient(
        endpoint: invite.endpoint,
        serverPin: host.serverPin,
      );
      try {
        await expectLater(
          client.requestPairing(
            invite,
            identity: joiner,
            peers: TrustedPeerStore(MemorySecretStore()),
          ),
          throwsA(
            isA<NetworkException>().having(
              (error) => error.code,
              'code',
              'INVALID_REQUEST',
            ),
          ),
        );
      } finally {
        client.close();
      }
    });
  });
}
