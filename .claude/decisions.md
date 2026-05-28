# Architectural Decision Log

Format: ADR-lite. New decisions append. Existing decisions get amended with
"Superseded by ADR-NNN" if reversed.

## ADR-001: Erlang/OTP as the spine
Date: Phase 0
Context: Need fault-isolated, hot-swappable strategy runtime with bounded
latency under load and trivial multi-server distribution.
Decision: Erlang/OTP 27 as the orchestration layer. gen_servers per strategy.
Supervisor trees for fault isolation. Native distribution for Phase 3.
Consequences: Learning curve. Pays back in fault tolerance and hot reload.

## ADR-002: Rust over C++ for NIFs
Date: Phase 0
Context: Compute kernels need to be fast, called from Erlang.
Decision: Rust + Rustler. Memory-safe, official Polymarket SDK exists,
ergonomic NIF interface, async via tokio when needed.
Consequences: Slightly steeper for newcomers than C++, but the safety win
during real-money phases is decisive.

## ADR-003: Python only at edges
Date: Phase 0
Context: Polymarket SDK, NBA APIs, ML training are Python ecosystem.
Decision: Python in isolated subprocesses, ZMQ-published only. Never in
the Erlang process tree, never on hot path.
Consequences: One extra hop (ZMQ). Worth it for crash isolation.

## ADR-004: Protobuf wire format
Date: Phase 0
Context: Schema evolution, cross-language, performance.
Decision: All internal events are Protobuf-encoded.
Consequences: Code-gen step in CI. Versioned schemas. Worth it.

## ADR-005: K3s for production orchestration
Date: Phase 0
Context: 100+ containers on 5 servers, need to schedule, restart, expose.
Decision: K3s (lightweight Kubernetes). Compose for dev only.
Consequences: K8s API surface to learn, but it is industry standard and
Helm charts are reusable.

## ADR-006: No real orders until Phase 3 Day 50
Date: Phase 0
Context: Real money risk. No Polymarket testnet exists.
Decision: Paper executor for all of Phase 1 and Phase 2. Real orders gated
behind explicit operator action on Day 50.
Consequences: Slower to first dollar earned, much lower risk of catastrophic bug.

## ADR-007: strategy_supervisor uses transient restart with simple_one_for_one
Date: Phase 1, Day 5
Context: Strategies can fail (bad data, logic bugs). We want bounded restarts,
not infinite loops. A strategy that exits normally (e.g., self-terminates on
{stop, normal}) should not be restarted. A strategy that crashes should get
a few retries before the supervisor gives up.
Decision: strategy_supervisor is simple_one_for_one; child restart = transient
(crash -> restart; normal/shutdown -> done). intensity=10, period=60 gives 10
crash-restarts per minute before the supervisor itself shuts down.
Consequences: A strategy that crashes 10 times/minute will bring down
strategy_supervisor (and all strategies). Per-strategy sub-supervisors would
give finer isolation but are deferred to Phase 2. In practice, buggy strategies
should be removed via remove_strategy/1 rather than left to crash-loop.