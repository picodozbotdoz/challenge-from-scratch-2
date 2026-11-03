# Task: $12 Server Challenge — iteration "challenge-from-scratch-2" (Lean spec → x86-64 asm)

Study iteration: Lean spec-first programming, from scratch. Working dir:
/home/doz/zcode-workdir/twelve-d-workdir/challenge-from-scratch-2/ (exists, currently empty with 2 files — make it
its own git repo). The challenge lives (read-only) at
/home/doz/zcode-workdir/twelve-d-workdir/repo/twelve-dollar-server-challenge/.
Refer to plan challenge-from-scratch-2/PLAN.md
and refer to this exact prompt in challenge-from-scratch-2/TASK-PROMPT.md

Goal: FIRST write an executable Lean requirement specification for the challenge, THEN build an
assembly program that satisfies it, and carry the work through to completion: a submission folder
that passes the challenge's 42-check suite and `test/run.sh` locally.

## ABSOLUTE PROHIBITIONS (cheating — violating these ruins the study)
- NEVER read anything under `enter-challenge-1/` at any depth.
- NEVER read or list anything under `repo/twelve-dollar-server-challenge/submissions/`.
- NEVER look up this challenge or its solutions on GitHub or the internet.
- Allowed references: the challenge repo's own `SPEC.md`, `README.md`, `schema.sql`,
  `LEADERBOARD.md`, `test/`, `seed/`, `bench/`, `benchmarks/`, `.github/`, plus normal tooling docs
  (Lean 4, SQLite C API, io_uring, GAS). Installing tooling (e.g. k6) is fine; solution code is not.

## Decisions already made (do NOT re-litigate)
1. Submission folder: `challenge-from-scratch-2/submissions/lean-asm2-picodoz/`. LOCAL-ONLY — no
   GitHub PR will be filed; "done" = locally validated.
2. MAX ASM FROM START: Lean emits ALL application logic as x86-64 — routing, `:id` parsing,
   bearer/JWT verification (base64url + SHA-256 + HMAC-SHA256), request-body JSON parsing, JSON
   response serialization (key order, escaping, int formatting), trim/≤500 validation, SQL
   selection + binding, response assembly, uptime. C runtime ONLY: io_uring event loop (raw
   syscalls, NO liburing dependency), HTTP framing, SQLite C-API wrappers, buffers, ABI glue.
3. Transport: single-threaded io_uring, HTTP/1.1 keep-alive, idle timeout ≥75s (rule: ≥65s), must
   cope with ~15k open connections.
4. Lean policy: local-only, via `challenge-from-scratch-2/tools/lean_cap.sh` — our OWN hard 2 GiB
   cap wrapper (`systemd-run --user --scope -MemoryMax=2G -MemorySwapMax=0`, verified working).
   NEVER run bare `lake`/`lean`. Modal is NOT installed anymore: if the same module OOMs twice
   under the cap, STOP and report — do not improvise. Keep Lean modules small (box has only
   ~2.1 GiB free RAM).

## Environment facts (surveyed 2026-11-03; re-verify briefly, then trust)
- Lean v4.35.0 (+ v4.36.0-rc1) via ~/.elan; gcc 14.2; sqlite3 3.46.1; curl/jq/openssl present;
  node v24 at ~/.nvm/versions/node/v24.21.0/bin (needed by `seed/make-seed.sh`); k6 absent
  (optional, M8). 4 cores, 7.6 GiB RAM, ~240 GiB disk free.
- Port 3000 is OCCUPIED on this box → use PORT=3457 for every local run.
- `repo/.../seed/feed.db` (~238 MB, WAL) and `seed/tokens.json` already exist — verify, don't
  rebuild unless broken (rebuild = `bash seed/make-seed.sh` inside the challenge repo, ~1 min).

## The challenge (read these files yourself — they are the acceptance oracle)
- `SPEC.md`: 5 endpoints (GET /health, GET /feed, GET /posts/:id, POST /posts, POST /posts/:id/like);
  compact JSON, exact key order; every error body is exactly `{"error":"<message>"}` per its table;
  HS256 JWT with `JWT_SECRET` env; on authed routes check auth BEFORE id
  (`POST /posts/abc/like` no-token→401, valid-token→400).
- `schema.sql`: fixed schema (users/posts/likes + 3 indexes) — may not add or change anything.
- `test/test.sh`: 42 byte-exact checks; run against a server on a FRESH copy of seed/feed.db
  (it writes, so a second run on the same DB fails):
  `bash test/test.sh http://127.0.0.1:3457`
- `test/run.sh` (CI contract): submission dir needs `build.sh` + `start.sh`; it copies the seed DB
  to a temp path, exports `SQLITE_PATH/JWT_SECRET/HOST/PORT`, waits ≤60s for /health, runs test.sh.
  Validate with: `PORT=3457 bash test/run.sh <abs path to submissions/lean-asm2-picodoz>`
- Runtime rules: config ONLY via env vars; WAL + `synchronous=NORMAL` or stronger; writes committed
  before responding; NO caching across requests (prepared-statement reuse is explicitly OK);
  no hardcoded responses. Bench thresholds (bench/load.js): p95<500ms, p99<1s, <1% errors.

## Architecture rules
- Pipeline: `spec/` (Lake project, Lean core only, no mathlib) → `tools/lean_cap.sh lake exe derive`
  → `gen/app_gen.s` (GAS Intel syntax, `-no-pie`, rip-relative, `.note.GNU-stack`, 16-byte stack
  alignment before calls into C) → `cc -c` + link `runtime/*.c` → `bin/server`.
- ABI: C calls ONLY `app_init` / `app_request`; emitted asm calls ONLY `x_*` wrappers
  (`x_db_prepare/bind_int/bind_text/step/column_int/column_text/changes/reset`,
  `x_out_byte/mem/int/str/json_escaped_str`, `x_env_secret`, `x_now`, `x_uptime`, `x_fail`→500).
  Struct layouts owned by the Lean emitter (`.set` equates at top of the emitted `.s`) and pinned
  by `_Static_assert`s in `runtime/abi.h` — never hand-duplicate offsets.
- Promotion gate: `gen/app_gen.s` is checked in; never overwrite it unless the gate
  (`tools/promote.sh`: assemble + link + current test subset green) passes. Every milestone must
  leave the server bootable.
- Spec-first (M1 is the requirement deliverable): handlers as pure functions
  `Request → DbView → Now → Response`; a `SpecCheck` exe that decide-checks all 42 suite analogues
  against embedded golden fixtures (`test/golden/*.json`); lemmas for auth-before-id ordering, trim
  laws, id-parse classification, JWT alg/exp discipline. Document edge decisions explicitly:
  `:id` = digit string with value ≥1 (overflow → 400), `Bearer ` prefix case-sensitive, `exp`
  required, `sub` digits-only ≥1, body length counted in code points, unknown path or wrong method
  → 404 `not found`.
- Honesty line (goes in the submission README): Lean PROVES spec-level properties; the emitted asm
  is VALIDATED by a differential corpus harness (spec vs asm on JSON/JWT/SHA/id-parse inputs) plus
  the 42 checks. Do not claim machine-checked asm↔spec equivalence.

## Milestones (each ends with: journal entry + state update + git commit)
- M0 Bootstrap: git init; `AGENTS.md`+`README.md` for this repo; `tools/{journal.sh
  (begin/ok/fail/note/milestone), lean_cap.sh, make_seed.sh, test_local.sh, promote.sh}`;
  `state/{next-step.txt, progress.json, .lock}` (flock-guarded commands); sanity: trivial Lake
  project builds under the cap; verify seed DB integrity.
- M1 Executable Lean spec: `Types/Model/Json/Jwt/Sha256/Contract/Invariant/Fixtures/SpecCheck`;
  `lake exe speccheck` all green under the cap.
- M2 Emitter v1 + bootable server: EmitAsm IR (labels/pools); emit /health + not-found +
  invalid-post-id paths; C runtime: prove io_uring loop with an echo harness FIRST, then HTTP
  framing, SQLite open + `SELECT 1`, ABI static asserts; boot on port 3457 → test.sh checks 7–12 green.
- M3 GET data path: `x_db_*` wrappers; emit GET /posts/:id + /feed (post serializer, escaping,
  ints, like_count); checks 1–6 and 13 green (golden byte-match).
- M4 Auth in asm: base64url + SHA-256 + HMAC + JWT structural/alg/exp/claim validation + bearer
  parsing; checks 14–22 green.
- M5 Body JSON parse (asm) + POST /posts + POST like: validation chain, `INSERT … RETURNING`,
  like + `changes()` for 201-vs-200; FULL 42/42 via `tools/test_local.sh` (fresh DB copy, port
  3457, exit 0).
- M6 Differential conformance harness + hardening: spec-vs-asm corpus on JSON/JWT/SHA/id-parse;
  keep-alive idle 75s, fd headroom, RSS budget for a 2 GB box (provided buffer ring, pooled
  out-buffers), SQLite pragmas (cache_size cap, mmap OK).
- M7 Packaging: `submissions/lean-asm2-picodoz/{install.sh (gcc only), build.sh (assemble+link; NO
  Lean at deploy), start.sh (foreground, env-only config), README.md (stack, proved-vs-tested,
  direct-mode), spec/, runtime/, gen/}`; verify: `PORT=3457 bash test/run.sh <abs dir>` → exit 0.
- M8 (optional): install k6 into `work/` (official tool only) and run `bench/load.js` at modest VUS
  for an indicative local score (dev box ≠ benchmark box; informational).

## Process rules
- `challenge-from-scratch-2/` is its own git repo; commit per milestone; `JOURNAL.md` append-only;
  `state/next-step.txt` always holds the literal next command.
- NEVER modify anything in `repo/twelve-dollar-server-challenge/` (running its scripts like
  `test/test.sh` or `seed/make-seed.sh` is allowed and expected).
- `work/` in challenge-from-scratch-2 is disposable and gitignored.

Start now: briefly re-verify the environment facts above, then execute M0 and proceed milestone by
milestone without re-asking about the decisions above. If reality contradicts this prompt (files
moved, port busy, toolchain changed), stop and report before improvising.