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
