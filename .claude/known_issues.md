# Known issues, deferred bugs, API rate limit hits

Append-only log. Each entry dated. Resolved entries get a `[RESOLVED <date>]` prefix.

Format:
## YYYY-MM-DD: short title
- Symptom: ...
- Cause (if known): ...
- Workaround: ...
- Permanent fix: deferred to Day N / ticket #N / not planned

## Example: 2026-XX-XX: Polymarket WebSocket disconnects every ~6 hours
- Symptom: ws connection drops, reconnect succeeds, no message loss observed.
- Cause: server-side connection recycling.
- Workaround: exponential backoff already handles. No action.
- Permanent fix: not needed.