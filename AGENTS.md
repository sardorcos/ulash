# Working on File Transfer

Read `docs/IMPLEMENTATION_STATUS_RU.md` and the relevant part of
`docs/SPECIFICATION_v1_0_RU.md` before extending the implementation.

- Keep UI and native adapters separate from `packages/transfer_core`.
- Never fabricate discovered peers, transfer progress or a delivery receipt.
- Never weaken SPKI pinning, enable plaintext fallback, follow auth redirects,
  or reset an identity on a locked/corrupt secure store.
- Discovery is an untrusted address hint. Names and addresses do not establish trust.
- No file data before explicit Sink consent. No autoaccept in this alpha.
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
- Explicit cleanup may remove only the previewed, still-unreferenced outgoing copies after the user confirms the documented last-copy consequence. Never sweep completed received files.
- The delivered 0.2 debug Android ID is .alpha02 because its signer differs from 0.1. Preserve installed user data; never suggest uninstalling a prior app to mask a signing-key mismatch.
