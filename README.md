# challenge-from-scratch-2 — Lean spec → x86-64 asm ($12 Server Challenge)

Study iteration 2 (from scratch): FIRST write an executable Lean 4 requirement specification for
the $12 Server Challenge feed API, THEN emit an x86-64 assembly application layer from Lean that
satisfies it, and validate against the challenge's 42-check suite.

- Challenge (read-only oracle): `../repo/twelve-dollar-server-challenge/` — `SPEC.md`,
  `schema.sql`, `test/test.sh` (42 checks), `test/run.sh` (CI contract), `seed/`, `bench/`.
- Deliverable: `submissions/lean-asm2-picodoz/` — local-only; done = `tools/test_local.sh` 42/42
  and `PORT=3457 bash ../repo/twelve-dollar-server-challenge/test/run.sh <abs submission dir>`
  exits 0.

## Pipeline

```
spec/ (Lean 4.35, core only)  --lake exe derive-->  gen/app_gen.s (GAS Intel, -no-pie)
                                                        |
                                                        v
                        cc -c  +  runtime/*.c (io_uring loop, HTTP framing, SQLite glue)  ->  bin/server
```

All application logic (routing, id parsing, JWT verify: base64url+SHA-256+HMAC, JSON in/out,
validation, SQL binding) is EMITTED asm. C is transport + syscalls + SQLite C-API only.

## Honesty line

Lean proves spec-level properties (42 suite analogues against golden fixtures, auth-before-id
ordering, trim laws, id classification, JWT alg/exp discipline). The emitted asm is VALIDATED by
a differential corpus harness (spec vs asm) plus the 42 checks — machine-checked asm↔spec
equivalence is NOT claimed.

## Repo map

See `AGENTS.md` (rules, layout, commands), `JOURNAL.md` (append-only log),
`state/next-step.txt` (literal next command), `PLAN.md`/`TASK-PROMPT.md` (approved plan).
