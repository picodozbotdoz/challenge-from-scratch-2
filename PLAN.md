# Action: persist the plan for a fresh session

Write exactly one file — `challenge-from-scratch-2/PLAN.md` — containing:

1. **Fresh-session kickoff header**: how to launch (ZCode session with working dir `/home/doz/zcode-workdir/twelve-d-workdir/`, so the root `AGENTS.md` still loads) and the opening prompt to use, e.g. *"Read challenge-from-scratch-2/PLAN.md and execute it milestone by milestone. Do not re-plan."*
2. **Hard prohibitions** (only exist in this chat otherwise): never read `enter-challenge-1/` or the challenge repo's `submissions/`; no solution lookups on GitHub/internet; official challenge files (`SPEC.md`, `schema.sql`, `test/`, `seed/`, `bench/`) are the only allowed references; tooling installs (k6) allowed, solution code not.
3. **User decisions locked in this session**: submission folder `lean-asm2-picodoz`, local-only (no GitHub PR execution); **max asm from start** (C only for syscalls/HTTP byte I/O/SQLite C-API); **io_uring** transport via raw syscalls; Lean local-only under an own 2 GiB `systemd-run` cap (Modal no longer installed — two OOMs of the same module ⇒ stop and report). Note this supersedes AGENTS.md rule 1's `enter-challenge-1/tools/lean_cap.sh` pointer for this iteration.
4. **The full implementation plan** as approved-in-content this session: deliverable definition, repo layout, architecture/ABI/promotion-gate rules, the spec-first M1 contract (incl. documented edge decisions), milestones M0–M8 with per-milestone verification, risks, and the end-to-end verification commands (`tools/test_local.sh` 42/42, `PORT=3457 bash test/run.sh <abs dir>`, `lake exe speccheck`).
5. **Process rules**: journal + `state/next-step.txt` updates at every step boundary, git commit per milestone, every milestone leaves the server bootable, promotion gate for `gen/app_gen.s`.

No other files are touched; no implementation is started here.