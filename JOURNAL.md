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
