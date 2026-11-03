# AGENTS.md — challenge-from-scratch-2

Study iteration: implement the $12 Server Challenge **from scratch** as a Lean-4-specified,
x86-64-assembly-emitted server. Spec first, then build to satisfy the spec. This repo is its own
git repo (the workspace root is not).

## Hard prohibitions (cheating — ruins the study)

1. NEVER read anything under `../enter-challenge-1/` at any depth.
2. NEVER read or list anything under `../repo/twelve-dollar-server-challenge/submissions/`.
3. NEVER look up this challenge or its solutions on GitHub/internet. Allowed references: the
   challenge repo's own `SPEC.md`, `README.md`, `schema.sql`, `LEADERBOARD.md`, `test/`, `seed/`,
   `bench/`, `benchmarks/`, `.github/`, plus generic tooling docs (Lean 4, SQLite C API,
   io_uring, GAS). Installing tooling (k6) is fine; solution code is not.
4. NEVER modify anything inside `../repo/twelve-dollar-server-challenge/` (running its scripts —
   `test/test.sh`, `seed/make-seed.sh` — is allowed and expected).

## Locked decisions (do not re-litigate)

- Submission folder: `submissions/lean-asm2-picodoz/`, LOCAL-ONLY (no GitHub PR; done = locally
  validated: 42/42 via `tools/test_local.sh` and `bash test/run.sh` exit 0).
- MAX ASM FROM START: Lean emits ALL application logic (routing, `:id` parse, JWT verify
  incl. base64url + SHA-256 + HMAC, body JSON parse, JSON serialization, validation, SQL binding,
  response assembly, uptime). C runtime ONLY: io_uring loop (raw syscalls, no liburing), HTTP
  framing, SQLite C-API wrappers, buffers, ABI glue.
- Single-threaded io_uring, HTTP/1.1 keep-alive, idle timeout ≥75 s, must cope with ~15k conns.
- Lean local-only under our own hard 2 GiB cap (`tools/lean_cap.sh`,
  `systemd-run --user --scope -p MemoryMax=2G -p MemorySwapMax=0`). NEVER bare `lake`/`lean`.
  Modal is NOT installed: if the same module OOMs twice under the cap — STOP and report.
  Keep modules small (~2.1 GiB free RAM on this box).

## Layout

- `submissions/lean-asm2-picodoz/` — the deliverable tree (dev happens here):
  `spec/` (Lake project, Lean core only), `runtime/` (C), `gen/app_gen.s` (checked-in emitted
  asm, promotion-gated), `tests/` (golden + corpus), `install.sh`/`build.sh`/`start.sh`/`README.md`.
- `tools/` — `lean_cap.sh`, `journal.sh`, `make_seed.sh`, `test_local.sh`, `promote.sh`.
- `state/` — `next-step.txt` (literal next command), `progress.json`, `.lock` (flock),
  `promote_min.txt` (min passing checks for the promotion gate).
- `JOURNAL.md` — append-only log (only via `tools/journal.sh`).
- `work/` — disposable, gitignored.
- `PLAN.md` / `TASK-PROMPT.md` — the approved plan and the originating prompt.

## Commands (from this dir)

```bash
cat state/next-step.txt                      # literal next command — kept current
tools/lean_cap.sh lake build                 # ONLY way to run lean/lake (inside spec/)
tools/test_local.sh                          # full 42-check run: fresh DB copy, PORT=3457
tools/promote.sh                             # promotion gate for gen/app_gen.s
tools/journal.sh note "..."                  # journal + state discipline
```

## Process rules

- Every step boundary: `tools/journal.sh` entry + `state/next-step.txt` update; commit per
  milestone. `JOURNAL.md` is append-only.
- Every milestone leaves the server bootable; `gen/app_gen.s` only changes through
  `tools/promote.sh` (assemble + link + boot + ≥ `state/promote_min.txt` checks green).
- Emitted-asm conventions: GAS Intel syntax, `-no-pie`, rip-relative, `.note.GNU-stack`,
  16-byte stack alignment before calls into C.
- ABI: C calls only `app_init`/`app_request`; asm calls only `x_*` wrappers; struct layouts
  owned by the Lean emitter (`.set` equates) and pinned by `_Static_assert`s in `runtime/abi.h`.
- If reality contradicts the plan (files moved, port busy, toolchain changed) — stop and report.

## Local environment facts (verified 2026-11-03)

- Lean 4.35.0 via `~/.elan`; gcc 14.2; sqlite3 3.46.1; node v24 at
  `~/.nvm/versions/node/v24.21.0/bin`; k6 absent (optional M8).
- Port 3000 OCCUPIED → use PORT=3457 for every local run.
- Seed DB `repo/.../seed/feed.db` (~238 MB, WAL; users=50000 posts=500000 likes=2016005,
  quick_check ok) + `seed/tokens.json` exist. 4 cores, 7.6 GiB RAM (~2.5 GiB available).
