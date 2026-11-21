# ADR 0002: finite retries, consent expiry and explicit payload cleanup

Date: 2026-11-21. Status: implemented in alpha 0.3.0.

## Problem

A foreground network interruption previously required an immediate manual
resume. Unanswered incoming offers occupied the queue indefinitely. Failed
incoming payloads could remain charged to the shared storage budget with no
usable cleanup action. Automatic cleanup of rejected outgoing jobs could also
remove the only prepared copy after the original had been deleted.

## Decisions

1. One explicit send or resume owns at most five retries. Base delays are
   1/2/4/8/16 seconds plus 0–25% positive jitter. Each attempt re-reads the
   trusted peer and creates a new pinned client. A closed allowlist admits
   transport/interrupted-commit errors; consent, trust, storage, integrity and
   source failures do not qualify. Delays are cancellable monotonic timers.
2. Automatic attempts preserve the logical request and transfer IDs. They use
   Sink status and HEAD offsets. They never clear either participant's manual
   pause. An explicit Source resume can clear only the Source flag once.
   Pause/cancel/revoke/background/shutdown cancel the whole running retry
   sequence. Recovery does not automatically schedule a new run.
3. Unaccepted offers expire after 120 seconds. The original UTC deadline is
   stored transactionally; an in-process Stopwatch is authoritative. Expiry is
   checked on reads and immediately before consent commit as well as by timer.
   The expired row remains an idempotency record. Reusing a request ID cannot
   resurrect it. After process restart, UTC supplies a bounded remaining time;
   observed rollback before creation fails closed. This cannot detect every
   external wall-clock change across shutdown.
4. A new user-confirmed attempt may reuse immutable outgoing copies only for
   a terminal job with no committed files, intact matching manifests and an
   active trusted peer. It receives a new request ID and new Sink consent.
   The old terminal result remains unchanged. Automatic source cleanup is
   allowed only after a complete validated committed receipt. All other
   prepared copies require explicit cleanup with the last-copy warning.
5. Incoming cleanup confirms exact transfer IDs from a preview. The controller
   rechecks eligibility; core serializes cancellation with its writer and final
   commit. Only journal-owned plain temporary files may be removed. Completed
   files, terminal receipts and unresolved durable commit intents survive.
   The budget is reconciled even when deletion fails; removed prefixes no
   longer advertise a durable offset.

## Compatibility and scope

The incoming SQLite migration is additive and transactional; a regression
reopens the old schema with offered, accepted, paused and committed transfers.
`expired` is a new wire enum member. Alpha 0.2 fails closed on that response;
both peers should use 0.3 to exercise expiry UX. Full mixed-version testing and
capability negotiation remain open. No automatic 7-day payload sweep, 30-day
history pruning, orphan scan, background service or agreed reset is added.

## Evidence

- `packages/transfer_core/test/inbox_lifecycle_test.dart`
- `packages/transfer_core/test/network_test.dart`
- `apps/file_transfer/test/network_retry_policy_test.dart`
- `apps/file_transfer/test/retry_controller_integration_test.dart`
- `apps/file_transfer/test/incoming_cleanup_controller_test.dart`
- `apps/file_transfer/test/network_resume_integration_test.dart`
- `apps/file_transfer/test/ui_test.dart`
- Final reports under `docs/verification/*_v03.*`.

The transport tests use actual TCP/TLS, files and SQLite on one Linux host.
They do not establish native device acceptance or wireless performance.
