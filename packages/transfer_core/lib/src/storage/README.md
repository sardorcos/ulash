# Foreground storage alpha

These stores implement real local disk I/O and SQLite journals. They do not
claim that the full v1 product specification or a physical-device release gate
has been completed.

## Entry points

- `DurableInbox.open(Directory, {checkpointBytes, checkpointInterval})`
- `createOffer(TransferManifest, {required peerId})`
- `accept`, `reject`, `cancel`, `pause`, `resume` return `TransferSnapshot`.
- `pause` and `resume` accept `bySource: true`; the default is the local sink.
  Each participant can clear only its own pause flag.
- `status(id)` and `list({peerId})` are synchronous journal reads.
- `changes` is a broadcast stream of committed snapshots; it is not the
  authoritative persistence mechanism.
- `writeFile(transferId, fileId, {offset, incarnation, bytes})` consumes a stream.
  A clean partial upload checkpoints the prefix and returns its offset. An
  exact complete body triggers hash verification and sink commit automatically.
- `finishFile(transferId, fileId, {incarnation})` verifies a complete durable file
  or an accepted empty file. It is idempotent after commit.
- `DurableOutbox.open(Directory)` provides `stageFile`, `stageStream`, `get`,
  `list`, `read(fileId, {offset})`, `remove`, `close`.
- `stageStream` accepts a native provider stream with optional
  `expectedSizeBytes`, `mimeType`, `onProgress`, and `isCancelled` callbacks.
- Optional `createTransfer`/`transfer`/`transfers`/`updateTransfer` persist
  outgoing request metadata. The Flutter app may use its own outgoing journal
  instead; it must persist the request before its first network offer.

All opaque IDs and wire byte counts are validated. JSON sizes/offsets are
canonical decimal strings within signed int64. `toJson()` on snapshots excludes
local paths; `includeLocalPaths: true` is for local diagnostics/UI only.

## Durability and recovery

Journals require effective WAL + `synchronous=FULL`. A checkpoint is published
only after file flush and SQLite transaction commit. On restart an unacknowledged
tail is truncated; a missing durable prefix fails with `RECOVERY_INCONSISTENT`.
The receive incarnation is preserved, never silently reset to reuse old offsets.

Full files are hashed from actual stored bytes before commit intent is written.
The intent records the final destination before same-volume rename. Recovery
verifies an existing final result or temporary candidate, then completes the
journal. Existing mismatching data is never overwritten during recovery.

The committed destination is inside the application-controlled root:
`received/<transferId>/<storageIncarnationId>/<safe filename>`. This intentionally does not
export to an arbitrary Downloads folder, Photos library, external volume or
document provider. Those require separate platform adapters and export states.

An active writer is exclusive within an inbox. Opening a storage root also
acquires an in-process lease and nonblocking OS advisory file lock. Cancellation
and final commit have an explicit sink ordering; an already committed result is
retained when the rest of its package is cancelled.

## Explicit alpha limitations

- Foreground push storage only; no pull receipts, agreed receive resets,
  background URLSession journal adapter, automatic expiry or disk quota manager.
- Disk-full errors are handled at write time. A native free-space preflight and
  reserved-space accounting are not implemented yet.
- `stageFile` compares source metadata and a second source hash to detect normal
  concurrent edits. This is not an OS-level coordinated snapshot of an actively
  edited provider document. `stageStream` snapshots exactly the supplied bytes;
  the native adapter owns the provider version guarantee.
- Published outbox copies are immutable by application policy, not protected
  against a malicious local process running with the same account privileges.
- Managed parent directories and symlinks are checked. Pure Dart path APIs do
  not supply a complete handle-relative no-follow/no-replace transaction against
  a hostile concurrent local filesystem actor. Use app-private storage, not an
  untrusted shared directory. Native filesystem hardening is a release task.
- Lifecycle recovery is designed for process interruption/ordinary restart.
  Hardware failure, filesystem corruption and absolute power-loss guarantees
  are outside what these tests demonstrate.
- A failed/inconsistent receive currently needs a new offer/request for a clean
  retry. Full idempotent `reset-receive` with a new incarnation is not exposed.
- Source preparation cancellation is checked between received chunks. A native
  provider that never produces another chunk also needs a cancellable native
  read operation; the boolean callback alone cannot interrupt that provider.
- Existing completed files are not continuously rehashed in the background.
- Tests exercise persistence on the available host filesystem. They do not
  prove platform filesystem semantics, 5/10 GiB physical-device throughput,
  iOS suspension, Android service behaviour or Windows installation support.

## Tests

`test/storage_test.dart` checks actual files and SQLite, including idempotency,
consent, interruption/resume, missing-prefix refusal, commit-intent recovery,
hash failures, empty files, pause ownership, retention of committed files,
source mutation detection, provider streams and malicious staging symlinks.

Recovery tests deliberately construct the filesystem/journal states that exist
between write/flush/commit/rename operations. They are not an exhaustive power
failure campaign.
