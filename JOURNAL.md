2026-11-03T11:02:28Z BEGIN M0: bootstrap repo (git init, tools, state, sanity)
2026-11-03T11:02:28Z NOTE  env re-verified: Lean 4.35.0, gcc 14.2.0, sqlite3 3.46.1, node v24.21.0, port 3457 free (3000 occupied), ~2.5 GiB RAM available
2026-11-03T11:02:28Z NOTE  seed verified: quick_check ok, users=50000 posts=500000 likes=2016005, journal_mode=wal, tokens.json 20000 tokens (first golden_ember_1)
2026-11-03T11:02:28Z OK    M0: lean_cap.sh (2G systemd-run cap) sanity Lake build green: 'bootstrap: spec project builds under the 2G cap'
2026-11-03T11:02:28Z MILE M0 done
2026-11-03T11:48:19Z BEGIN M1: executable Lean spec
2026-11-03T11:48:19Z NOTE  M1: modules Types/Json/Sha256/Jwt/Contract/Model/Invariant/Fixtures/Main; Lean core only
2026-11-03T11:48:19Z NOTE  M1: crypto verified vs published vectors (SHA-256 empty/abc, HMAC-SHA256 fox, b64url JWT header)
2026-11-03T11:48:19Z NOTE  M1: kernel-checked lemmas: parseId_pos/class, trim_idem, auth-before-id (like+create), JWT discipline (badPayload_requires, expired_invalid, ok_requires_payload, verify_none_of_structural_none)
2026-11-03T11:48:19Z OK    M1: lake exe speccheck -> passed=46 failed=0 (42 suite analogues + 4 crypto vectors)
2026-11-03T11:48:19Z MILE M1 done
2026-11-03T12:03:56Z BEGIN M2: emitter v1 + bootable server
2026-11-03T12:03:56Z NOTE  M2: io_uring raw syscalls proven by echo harness first (bug found: params struct layout — switched to system linux/io_uring.h; ring_entries offsets vs counts)
2026-11-03T12:03:56Z NOTE  M2: runtime: uring.h/c, abi.h/c (static-assert pins), db.c (WAL+NORMAL, stmt cache), http.c (framing, keep-alive, pipelining), main.c (16384-conn loop); third_party/sqlite3 self-contained dev files
2026-11-03T12:03:56Z NOTE  M2: EmitAsm.lean emits app_init/app_request: routing, /health (SELECT 1 gate + uptime), 404, :id classification w/ i64 overflow->400; streq/prefix/parseid/strlen helpers; pools as .byte
2026-11-03T12:03:56Z NOTE  M2: derive exe works: lake exe derive -> app_gen.s (273 lines) assembles+links -no-pie; GAS Intel gotchas: BYTE PTR, no movzx rsi,esi
2026-11-03T12:03:56Z OK    M2: server boots on 3457; suite: passed=10 failed=32 (gate 10); /health,/nope,id-classification all green; promoted gen/app_gen.s via tools/promote.sh
2026-11-03T12:03:56Z MILE M2 done
2026-11-03T12:06:20Z BEGIN M3: GET data path in asm
2026-11-03T12:06:20Z NOTE  M3: emit .Lemit_post serializer (exact key order, JSON-escaped text via column_bytes, int formatting) + /posts/:id row fetch + /feed 20-post loop; SQL per SPEC
2026-11-03T12:06:20Z NOTE  M3: bug fixed — .Lemit_post called C with misaligned stack (entered via call => rsp%16==8); added sub/add 8 frame
2026-11-03T12:06:20Z OK    M3: suite passed=15 (goldens 1-6, health, 404s, id classification, post-not-found, feed length); gen/app_gen.s promoted
2026-11-03T12:06:20Z MILE M3 done
2026-11-03T12:42:03Z BEGIN M4: auth in asm
2026-11-03T12:42:03Z NOTE  M4: emitted SHA-256/HMAC-SHA256/base64url codec/strict-UTF8/JSON-field-scan/JWT pipeline (bearer parse, split, alg=HS256, signature, exp>now, sub digits>=1, username string) + POST routing (auth BEFORE id)
2026-11-03T12:42:03Z NOTE  M4: crypto helpers exported global (sha256_asm etc + _c wrappers) -> tests/asm_selftest.c validates against published vectors (RFC 4231 incl long-key); all green
2026-11-03T12:42:03Z NOTE  M4: bugs fixed en route: sigma0/1 shift-of-rotated (need 3rd copy), b64enc tail shifts, p64 pointer vs index, auth_len sign-extension (movsx), payload [rsp+0x200] mov->lea, .Lac_err3 fallthrough, ah-register encoding
2026-11-03T12:42:03Z OK    M4: suite passed=25 (checks 14-22 auth all green); asm selftest PASS; promoted
2026-11-03T12:42:03Z MILE M4 done
2026-11-03T13:04:42Z BEGIN M5: body JSON + POST endpoints
2026-11-03T13:04:42Z NOTE  M5: emitted json_valid_asm (strict recursive descent, surrogate pairing, no-leading-zero numbers, depth cap 64), json_unescape_asm (\uXXXX + surrogate pairs -> UTF-8), trim_asm, cplen_asm (code points = non-continuation bytes)
2026-11-03T13:04:42Z NOTE  M5: create handler: validate -> extract body -> unescape -> trim -> 500cp cap -> INSERT..RETURNING -> exact 201 body; like handler: exists -> INSERT..ON CONFLICT DO NOTHING -> changes() -> 201/200
2026-11-03T13:04:42Z NOTE  M5: bugs fixed: jv_number frame bug (tail-jmp+ret mismatch -> call + flag-based failure), missing closing brace in create literal, inverted like status, main.c flush-first on pipelined/partial reads (need_more)
2026-11-03T13:04:42Z OK    M5: tools/test_local.sh -> passed=42 failed=0 (FULL SUITE); promoted gen/app_gen.s (gate=42)
2026-11-03T13:04:42Z MILE M5 done
2026-11-03T13:39:54Z BEGIN M6: differential harness + hardening
2026-11-03T13:39:54Z NOTE  M6: tools/gen_corpus.py (1042 cases: JSON validity+mutations, unescape incl surrogates, b64, sha256, hmac incl >64B keys, parseid/parseexp) + tests/asm_corpus.c + spec exe specdump + tools/diff_corpus.sh
2026-11-03T13:39:54Z NOTE  M6: corpus-driven fixes: spec Json.parseNum rewritten flat (nested-let bug rejected floats in containers), spec rejects leading-zero numbers (RFC), asm json_valid gates on strict UTF-8, asm parseexp whole-string strict, unescape lone-low-surrogate range
2026-11-03T13:39:54Z NOTE  M6: hardening: RLIMIT_NOFILE raise, SIGALRM idle sweep (default 8x10s=80s >= 65s rule), conn generation guard vs stale cqes, shutdown-before-close (io_uring read pins fd), interruptible uring_wait
2026-11-03T13:39:54Z OK    M6: diff_corpus IDENTICAL (1042 cases); test_local 42/42 with sweep enabled; promoted
2026-11-03T13:39:54Z MILE M6 done
2026-11-03T13:41:13Z BEGIN M7: packaging
2026-11-03T13:41:13Z NOTE  M7: install.sh (build-essential + libsqlite3-dev only; NO Lean at deploy), build.sh, start.sh (foreground, env-only), README (stack, proved-vs-tested honesty line, direct mode, edge decisions), .gitignore; core dump artifact removed
2026-11-03T13:41:13Z OK    M7: PORT=3457 bash ../repo/twelve-dollar-server-challenge/test/run.sh <abs submission dir> -> exit 0, 42/42
2026-11-03T13:41:13Z MILE M7 done
2026-11-03T13:50:20Z BEGIN M8: indicative k6 bench
2026-11-03T13:50:20Z NOTE  M8: official k6 v1.1.0 installed to work/k6 (gitignored); dev box != benchmark box (4 cores vs 1 vCPU) — informational
2026-11-03T13:50:20Z OK    M8: 100 VUs: p95=0.6ms p99=2.5ms 0% err; 1000 VUs: p95=0.58ms p99=2.2ms 0% err (8303 checks all green), server RSS 15MB
2026-11-03T13:50:20Z MILE M8 done
2026-11-03T14:10:29Z NOTE  push blocked by GitHub secret scanning: core.575023 (1.8MB core dump committed in M4, present through M6) captured process env incl. real AZURE_DEVOPS_EXT_PAT + TOKEN. History scrubbed via filter-branch index-filter (only that path removed; M0-M3 hashes unchanged), refs/original+reflog+gc purged (blob 5ac86ce verified absent). .gitignore now covers core/core.*. Secret never left the box (push was blocked); rotate the Azure PAT if in doubt.
2026-11-03T16:57:52Z NOTE  M9 profiling: built ptrace rip-sampler (work/prof/sampler.c ~460Hz, no perf due paranoid=3) + strace (apt-get download + dpkg -x) + resolve.py (server nm / libc dynsym / libsqlite3 dbgsym 3.46.1). CPU: 54us/req hot, 13.4k req/s cap, 97% idle at official load — CPU not score-limiting. Syscalls: 3.2/req (uring_enter 1.5, fcntl shm-lock 1.25, pwrite 0.28, pread ~0). Hot CPU: sqlite3 ~44% (walFindFrame 3.6%, btree movetos 2%, pcache1Fetch), JSON escape x_out_json_escaped_str 2.6%, out-buf grow 1.7%. TAIL: 4x clean 4000VU official-shape runs (work/prof/out-tail4000*): p99 2.6ms-5.9s bimodal; freeze run showed server zero-CPU zero-syscall 4.4s then 3.7MB burst, 2773 reqs bunched. ROOT CAUSE: fdatasync(syscall 75) runs INLINE on event loop inside sqlite3_step (wal_autocheckpoint 1000pg every ~2.4s under load; strace median 7.45ms max 106ms) -> jbd2_log_wait_commit caught by 5Hz wchan probe; rare jbd2 stalls = multi-second all-conn freezes. Sweep tick NOT implicated (spikes uniform mod 10s). Robustness note: ring=1024 entries, arm_read on SQ-full closes conn silently (scaling ceiling vs 16384 conns). Fixes ranked: (1) keep event loop off fdatasync — worker thread for DB ops w/ eventfd in ring, or bounded incremental checkpointing; (2) fp refactors? no — (2) pre-size feed out-buffer + escape fast-path in emitter (Lean, corpus-gated); (3) fcntl shm-lock reduction via per-request txn batching. Profiling kit reusable: work/prof/{sampler.c,resolve.py,hot.js,run_prof.sh,run_tail.sh}
2026-11-03T17:54:12Z BEGIN M10: fix#1 checkpoint worker — fdatasync off event loop (db.c, -lpthread)
2026-11-03T17:54:12Z OK    M10: 42/42; tail 4000VU max 455ms/7.5s -> 61.8/57.7ms; 8000VU p95=0.54ms p99=1.23ms max=69ms; WAL bounded 4.18MB
