# Known issues, deferred bugs, API rate limit hits

Append-only log. Each entry dated. Resolved entries get a `[RESOLVED <date>]` prefix.

Format:
## YYYY-MM-DD: short title
- Symptom: ...
- Cause (if known): ...
- Workaround: ...
- Permanent fix: deferred to Day N / ticket #N / not planned

## 2026-05-28: ingest_subscriber_SUITE zmq_throughput_latency flaky under suite load
- Symptom: p50 spikes to ~1.1 s (threshold is 2 ms) when test runs as part of the
  full `make test` suite. Passes every time when run in isolation.
- Cause: WSL2 scheduler starvation — ZMQ socket buffer fills while Python process
  is preempted by concurrent Erlang compilation and test suites.
- Workaround: Run `rebar3 ct --suite apps/core_bus/test/ingest_subscriber_SUITE`
  separately. Full `make test` occasionally red on this test only.
- Permanent fix: deferred — consider mocking latency or splitting ZMQ test into a
  separate non-blocking test target.

## Example: 2026-XX-XX: Polymarket WebSocket disconnects every ~6 hours
- Symptom: ws connection drops, reconnect succeeds, no message loss observed.
- Cause: server-side connection recycling.
- Workaround: exponential backoff already handles. No action.
- Permanent fix: not needed.