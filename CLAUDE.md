# NBA Prediction + Polymarket Trading System

## What this project is
Long-running automated trading system that places bets on Polymarket NBA markets
using live game state and historical models. Owner is a solo builder. Goal is
profitable strategies plus a learning experience in distributed systems.

## End goal
A production system on 5 Hetzner servers running 100+ Docker containers via K3s,
trading real USDC on Polymarket with a top-K strategy selector, full observability,
and a simple dashboard for monitoring and kill-switch control. Total path: 66 days
across 4 phases.

## Locked architectural decisions (do not deviate without explicit approval)
1. Erlang/OTP 27 is the spine. All orchestration, supervision, strategy lifecycle.
2. Rust (stable) for compute kernels via Rustler NIFs. Dirty NIFs for >1ms work.
3. Python 3.12 at edges only (Polymarket SDK, NBA APIs, ML training). Subprocess isolated.
4. TypeScript + Next.js for Phase 4 UI only.
5. Protobuf for all internal events. JSON only at outer API edges.
6. ZeroMQ with chumak (Erlang) and pyzmq (Python) for cross-language IPC.
7. QuestDB time series, Redis hot state, Parquet archives, Postgres metadata (Phase 3+).
8. WSL2 Ubuntu 24.04 dev. Hetzner Cloud production. K3s orchestration.
9. Strategies are gen_servers implementing strategy_behaviour. Hot-swappable.
10. Rate limiting at order_router, not in strategies.
11. Kill switch in two layers: Erlang flag + Polygon allowance revocation.
12. Simulator is first-class: replay and synthetic modes, indistinguishable to strategies.
13. NO real orders before Phase 3 Day 50. Paper trading until then.
14. GitHub with branch protection. Conventional commits. PR workflow even solo.

## Current phase
See `.claude/current_task.md` for the day-level state.

## Where memory lives
- `CLAUDE.md` (this file): goal, locked decisions, top-level state.
- `.claude/decisions.md`: ADR-style log of every architectural choice with rationale.
- `.claude/progress.md`: day-by-day checkmark tracker.
- `.claude/current_task.md`: what we are doing right now, blockers, last commit.
- `.claude/known_issues.md`: API rate limit hits, flaky tests, deferred bugs.
- `docs/`: phase plans, architecture, runbooks.

## Commands Claude Code should run for context
- `cat .claude/current_task.md` first, every session.
- `git log -10 --oneline` for recent work.
- `git status` for dirty state.
- `cat .claude/known_issues.md` if anything is unexpected.

## Testing and Git rules (enforced)
- Every feature on a branch: `phaseN/dayM-feature-slug`.
- Conventional commits: feat|fix|test|docs|chore|refactor|perf.
- CI must pass before merge.
- Daily commit minimum, end-of-day push, no exceptions.
- Tag at end of each week and each phase.
- Coverage targets: 80% for core_bus and execution, 60% for strategies.
- Property tests preferred for state machines.

## Hardware constraints
Dev: Dell Inspiron 14 5410, i7-1195G7, 16GB RAM, 8 logical cores, WSL2 Ubuntu 24.04.
Prod: 5 Hetzner CCX23 or similar, ~16GB RAM, 4 vCPU each (provisioned in Phase 3).