# Foreground HTTPS network slice — alpha 0.1

This is a real Dart HTTPS transfer implementation. It does not simulate peers,
files, throughput or receiver acknowledgements.

## Implemented

- A software EC P-256 TLS identity stored through the injected `SecretStore`.
  The production application must supply OS-protected storage. The core does not
  provide a plaintext disk store. `MemorySecretStore` is for explicit temporary
  probes and tests only.
- SPKI pin = base64(SHA-256(DER SubjectPublicKeyInfo)), not a certificate hash.
  The client uses an empty-root TLS context, a strictly pinned certificate
  callback and an unconditional `SecureSocket.peerCertificate` check before
  returning the socket to `HttpClient`. HTTP credentials cannot be written until
  this last check succeeds. Only the selected HTTPS origin is allowed; redirects
  and proxy routing are disabled.
- Full-entropy QR/text invitations, atomic invitation reservation, manual host
  approval, pending state in protected storage and idempotent commit.
- Two independent 256-bit directional bearer credentials. The issuer stores a
  digest for incoming authentication; outgoing tokens remain in the protected
  store. Tokens, private keys and invitations are not logged by the core.
- Consent-gated push offers, per-peer authorization, tus 1.0 core HEAD/PATCH,
  decimal offsets, a single writer, bounded metadata and streaming file bodies.
- Receiver durable-offset resume after a real HTTPS interruption and process
  storage reopen; final success comes from the verified Sink commit.
- Separate sender/receiver pause ownership, cancellation and peer revocation,
  including stopping a live body stream before it finishes.

## Alpha boundaries

The network core currently implements **push only**, with an active receiver
HTTPS listener. It advertises `canPullClient: false` and both native-background
capabilities as false. Both applications must remain open. A paused or killed
receiver is handled by interruption and later resume, not an unsupported promise
of always-on iOS listening.

Pull, persistent events/long polling, native URLSession, remote/WebRTC/TURN,
automatic expiry/retention of all journals and a versioned OpenAPI description
remain follow-up work. Discovery is supplied by the Flutter application, not
this core. IPv6 and real iOS/Android/Windows device matrices require physical
validation; loopback tests prove protocol/storage behavior only.

The application must keep the prepared source immutable. The receiver verifies
SHA-256, but neither SHA-256 nor a paired device name is a substitute for first
pairing authentication. A compromised trusted peer can send an untrusted file;
the application must not execute or open received files automatically.

Malformed/oversized chunked HTTP bodies can be rejected by closing the
connection; receiving a JSON error is not guaranteed after stream cancellation.
Known-length oversized metadata is rejected before it is read. This prevents a
large advertised body from allocating its stated size in application memory.

The PIN/credential model is a scoped alpha implementation, not a security audit.
An independent review and physical-device tests are release gates.

## Runnable large-file integration probe

Run from `packages/transfer_core` after `dart pub get`:

```bash
dart run bin/loopback_probe.dart --mib 16 --output /absolute/fresh/probe-directory
```

For a 1 GiB check, use `--mib 1024`. Accepted sizes are 8–10240 MiB; the default
is 16 MiB. The minimum leaves room to interrupt after a genuine 4 MiB durable
checkpoint. On a managed executor, prefix SDK commands with `CI=true` and
`FLUTTER_SUPPRESS_ANALYTICS=true` if its SDK bootstrap requires that environment.

The probe:

1. Generates an actual deterministic disk file using a bounded 1 MiB buffer.
2. Creates two temporary identities and manually approves an actual HTTPS pair.
3. Confirms that data access is denied before receiver consent.
4. Starts a real streaming upload, interrupts the TLS connection after a durable
   prefix, and closes/reopens the receiver's SQLite/file storage and HTTPS host.
5. Rechecks the durable offset and transfers only the remaining source suffix.
6. Requires receiver `committed` and independently rereads the saved file to
   verify its size and SHA-256.
7. Prints JSON with source/sink paths, hashes, measured elapsed time and the
   resumed offset. It writes the same JSON to `result.json`.

Source, sink and receiver state are retained for independent verification. An
existing `source.bin`, `receiver` directory or `result.json` is never overwritten.
Without `--output`, a fresh system temporary directory is used and its paths are
included in the result. Private keys and credentials never enter those files.

Independent Python verification after a run:

```python
import hashlib, json, pathlib

report = json.loads(pathlib.Path('/absolute/probe-directory/result.json').read_text())
for field in ('source_path', 'sink_path'):
    path = pathlib.Path(report[field])
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    assert path.stat().st_size == report['size_bytes']
    assert digest == report['sha256']
print('Independent size and SHA-256 verification passed')
```
