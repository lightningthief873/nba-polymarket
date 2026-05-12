# nba-polymarket

Automated NBA win-probability + Polymarket trading system.
Erlang/OTP spine, Rust compute kernels, Python edge adapters.

## Status
See `.claude/current_task.md` for current state.

## Quick start (dev)
```bash
make setup    # install local deps (assumes asdf, docker, wsl2)
make build    # compile everything
make test     # run all tests
make run      # start dev stack via docker-compose + rebar3 shell
```

## Architecture
See `docs/architecture.md`.

## Phase plans
- `docs/phase1.md` Spine
- `docs/phase2.md` Strategies + ML
- `docs/phase3.md` Production
- `docs/phase4.md` Dashboard

## Memory and decisions
- `CLAUDE.md` Top-level project memory
- `.claude/decisions.md` Architectural decision log
- `.claude/progress.md` Day-by-day progress
- `.claude/known_issues.md` Active and resolved issues