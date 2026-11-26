# Foreground storage alpha

These stores implement real local disk I/O and SQLite journals. They do not
claim that the full v1 product specification or a physical-device release gate
has been completed.

## Entry points

- `DurableInbox.open(Directory, {checkpointBytes (8 MiB), checkpointInterval,
  budget, offerLifetime, wallClock, monotonicClock, receivedDirectory,
  maxPendingOffersPerPeer (5)})`
- With `receivedDirectory`, results are committed to
  `<dir>/<yyyy-MM-dd HH.mm> (<id6>)/<folder?>/<safe name>` (collisions get
  ` (2)`; never overwritten) and journaled as `r:<relative path>`, so the
  directory may move with its container. Results from the private
  `received/` layout are migrated on open (crash-safe via `moved_from`).
- `list({peerId})`, `listRecent({limit, before})`, `count({peerId})` and
  `changedTransfers` (ids) for history screens.
- `DurableOutbox.stageFile(..., adoptTemporary: true)` renames a temporary the
  caller owns into the store (copy fallback); never for user originals.
- `createOffer(TransferManifest, {required peerId})`
- `accept`, `reject`, `cancel`, `pause`, `resume` return `TransferSnapshot`.
- `pause` and `resume` accept `bySource: true`; the default is the local sink.
  Each participant can clear only its own pause flag.
- `status(id)` and `list({peerId})` synchronously enforce pending-offer expiry
  before reading the journal.
- `expireOffers()` returns the snapshots expired by that invocation; an internal
  foreground timer also emits expiry without a network/UI poll.
- `previewIncompleteCleanup()` returns immutable `IncomingCleanupItem` entries
  with actual temporary bytes, future reservation bytes and file counts.
- `discardIncomplete(transferId)` returns an `IncomingCleanupResult` with the
  snapshot and actual removed file/byte counts. Call it only for IDs explicitly
  previewed and confirmed by the user; it stops the selected batch first.
- `changes` is a broadcast stream of committed snapshots; it is not the
  authoritative persistence mechanism.
- `writeFile(transferId, fileId, {offset, incarnation, bytes})` consumes a stream.
  A clean partial upload checkpoints the prefix and returns its offset. An
  exact complete body triggers hash verification and sink commit automatically.
- `finishFile(transferId, fileId, {incarnation})` verifies a complete durable file
  or an accepted empty file. It is idempotent after commit.
- `DurableOutbox.open(Directory, {budget})` provides `stageFile`, `stageStream`, `get`,
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

## Temporary storage and free-space guard (0.2)

Pass one shared `StorageBudget` to both stores on the same filesystem. Its
native `availableBytes` callback reports bytes actually available to this app;
`null` explicitly means that capacity could not be reported. No artificial
available-space value is substituted. A configured temporary quota still
applies when the platform cannot report free space.

Defaults are a **128 MiB free-space safety margin** and a **20 GiB temporary
payload quota**. They are product policy values, not measured performance
figures. `setTemporaryQuotaBytes` changes the quota atomically; lowering it below
existing payloads plus outstanding reservations returns
`TEMP_QUOTA_BELOW_USAGE`, without deleting files or invalidating accepted work.

An incoming batch reserves its full manifest size before persisting consent.
A known-size outgoing copy reserves its size before creating a partial file;
an unknown-length provider stream expands its claim before each bounded write.
Both directions use one serialized accounting queue. Already-written payloads
count toward the temporary quota but are **not subtracted twice** from OS free
space. The free-space check includes only future reserved bytes and the margin.
Checks run at admission, receive-stream start/resume, after at most 4 MiB of
shared writes or 2 seconds, and whenever an unknown-size stream expands.

`inspect()` returns nullable `availableBytes`, actual temporary payload bytes,
future reserved bytes, safety margin and quota. The budget counts prepared
outgoing files and incomplete incoming payloads. It excludes committed receive
results from the temporary quota; those results still occupy disk space and
are reflected by the native capacity query. Journals and filesystem allocation
overhead are outside the payload quota and remain part of OS-used space.

Reservations are rebuilt from journals and actual payload lengths on store
open, including orphaned payloads. Failed preparation removes only its own
temporary copy. Cancellation releases a receive reservation only after pending
writes have stopped and its partial file has been removed. Hash failures retain
their existing partial data but release future-byte reservations. No automatic
retention or history deletion is introduced by this guard.

These are application admission reservations, **not OS preallocation**. Other
processes can consume disk space between checks, and providers can report
capacity imprecisely. Actual write/flush failures remain handled by the durable
journal. `DISK_FULL` pauses a receive at its last acknowledged checkpoint and
does not remove originals or committed results. The per-root filesystem lease
remains required; all stores for one volume must receive the same budget.

## Offer lifetime and explicit incoming cleanup (0.3)

Pending offers expire after **120 seconds** by default. A process-local
monotonic clock controls the interval; changing wall time while the store is
open does not extend it. The journal stores `offer_expires_at` for display and
restart fallback. On restart, remaining time is bounded by the original UTC
deadline and configured lifetime; an observed wall time before the offer's
creation expires it immediately. This fallback cannot establish elapsed time
across shutdown against every external wall-clock change. Tests inject both
clocks, while production uses a `Stopwatch` and UTC `DateTime`.

The 0.2 journal migration derives deadlines from original `created_at`, not
the recovery-updated timestamp. Expiry persists `expired` on transfer and files,
keeps `(peer_id, request_id)` idempotency, releases queue slots, and accepts no
data. Repeating an expired request returns the same expired transfer. A new
attempt requires a new request ID. A final deadline check after asynchronous
capacity/path preparation prevents late consent; already accepted work does
not expire under this offer policy.

Explicit incoming cleanup serializes its cancellation decision with other
controls and waits for its writer to stop before deleting. It can also remove
payloads retained by failed terminal attempts. Only journal-owned plain files
under the managed `.staging` directory are eligible. Committed results and
receipt/idempotency rows remain. If final commit wins before confirmation,
cleanup reports zero removed bytes. A batch with an unresolved durable
`committing` intent is protected until normal recovery verifies the candidate.
Failed deletions remain retryable; accounting is reconciled conservatively.

Cleanup does not sweep unknown orphan files and does not implement the
specification's seven-day inactivity retention, 30-day history/receipt retention
or history limit. These remain explicit later tasks. The new `expired` wire
state is understood by 0.3; an older 0.2 participant fails closed when parsing it
and may show a generic state error instead of the expiry message.

## Explicit alpha limitations

- Foreground push storage only; no pull receipts, agreed receive resets,
  background URLSession journal adapter or automatic seven-day payload retention.
- Free-space protection depends on the injected native capacity adapter. These
  core tests use deterministic capacity simulators and real local payload files;
  they do not replace physical-device capacity tests.
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

`test/storage_budget_test.dart` adds insufficient-disk consent rejection,
all-or-nothing batch quota admission, concurrent inbox/outbox reservations,
no double-counting during writes, retained completed files, late space loss
with checkpoint recovery, unknown-size provider limits, restart reconstruction,
quota lowering, empty files at the reserve margin, cancelled preparation,
orphan accounting and safe deletion refusal through a symlinked parent.

`test/inbox_lifecycle_test.dart` covers 120-second pending expiry, monotonic
versus wall-clock changes, restart/deadline migration, retained idempotency,
queue-slot release, slow admission crossing expiry, timer delivery, partial and
failed-file cleanup, active writer cancellation, late confirmation after commit,
symlink refusal and protected unresolved commit intent.

Recovery tests deliberately construct the filesystem/journal states that exist
between write/flush/commit/rename operations. They are not an exhaustive power
failure campaign.
