# Working on File Transfer

Read `docs/IMPLEMENTATION_STATUS_RU.md` and the relevant part of
`docs/SPECIFICATION_v1_0_RU.md` before extending the implementation.

- Keep UI and native adapters separate from `packages/transfer_core`.
- Never fabricate discovered peers, transfer progress or a delivery receipt.
- Never weaken SPKI pinning, enable plaintext fallback, follow auth redirects,
  or reset an identity on a locked/corrupt secure store automatically. A reset
  happens only after the user confirms it (startup recovery or Settings); it
  removes keys and pairings only and keeps the user's settings.
- Discovery is an untrusted address hint. Names and addresses do not establish trust.
- No file data before explicit Sink consent. No autoaccept.
- A Sender may mark success or clean its only prepared copy only after a complete,
  validated committed receipt from the Sink.
- Preserve outgoing request IDs and cancellation intent across restart.
- Acknowledge only flushed bytes committed to the SQLite journal.
- Do not overwrite originals, existing results, or files outside managed storage.
- Use streaming with bounded buffers; never load a large file as a single byte array.
- A failed native capability must remain unavailable. No background guarantees
  before physical-platform verification.
- Use `python3 scripts/verify.py --flutter /path/to/flutter/bin/flutter`.
- Keep source/test reports separate from native hardware acceptance. Only report
  builds and tests that actually ran. Read the latest test report before claims.
- Do not commit keys, tokens, QR invitations, keystores, runtime-data or build caches.
- The repository has no production signing credentials. Device installation,
  signed release publication and customer distribution are separate actions.

- Use one StorageBudget for inbox and outbox on the same volume. Unknown native free space stays null; never convert it into an invented capacity.
- Keep committed network receipt and native export state separate. Recover an unfinished export as unknown and never automatically repeat it.
- Explicit outgoing cleanup may remove only the previewed, still-unreferenced copies after the user confirms the documented last-copy consequence. Incoming cleanup may stop only the confirmed batch IDs and remove journal-owned unfinished payloads; preserve completed files, receipts and unresolved commit intents.
- Rejection, cancellation and expiry do not automatically delete an outgoing prepared copy. Automatic source cleanup requires a complete validated committed receipt. A user-requested new attempt has a new requestId and requires new Sink consent.
- Network retries are finite and cancellable. Never clear a manual Source or Sink pause automatically or retry trust/integrity failures.
- Product decision for 1.0: a send stopped by backgrounding (after the bounded grace period) or by exhausted network retries continues automatically once the app is in the foreground and the peer answers a fresh pinned probe (at most 3 automatic continuations per job and session). A cold start never resumes work by itself; a manual pause is never resumed automatically.
- Automatic history pruning removes journal records only, never prepared copies or received files. A freshly created outbox journal never deletes existing snapshots.
- Release identifiers: iOS bundle ID and Android applicationId `uz.ulash.app` (debug `uz.ulash.app.debug`). The alpha lines (`uz.sardor.file_transfer*`) are separate installations; there is no migration from them.
- User-visible text lives in `apps/file_transfer/lib/l10n/*.arb` (ru template, uz Latin, en), generated from `scripts/l10n/catalog.py` via `scripts/l10n/gen.py` and `flutter gen-l10n`. Never hard-code UI strings.
- Diagnostics are local only and must not contain file names, paths, addresses, tokens or invitations.
