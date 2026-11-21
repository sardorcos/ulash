/// Native-only, foreground LAN transport. No browser or cloud fallback.
library;

export 'src/models.dart';
export 'src/storage/durable_inbox.dart';
export 'src/storage/durable_outbox.dart';
export 'src/security/secret_store.dart';
export 'src/security/device_identity.dart';
export 'src/security/trusted_peer_store.dart';
export 'src/security/pairing_invite.dart';
export 'src/security/pairing_service.dart'
    show PendingPairing, PairingException;
export 'src/network/core_client.dart';
export 'src/network/core_host.dart';
export 'src/network/network_error.dart';
