/-
Feed.EmitAsm — emits the ENTIRE application layer as x86-64 assembly (GAS Intel
syntax), mirroring the executable spec in Feed.Model / Feed.Contract.

The emitted file owns the struct layouts (`.set` equates at the top); runtime/abi.h
pins those exact numbers with `_Static_assert`s.

Emission scope (grows per milestone; every milestone leaves the server bootable):
  M2: routing, /health (SELECT 1 + uptime), 404 not found, :id classification
      (400 invalid post id), x_fail stubs for unimplemented handlers
  M3: GET /posts/:id + /feed serialization
  M4: bearer/JWT verification (b64url + SHA-256 + HMAC)
  M5: body JSON parse + POST /posts + POST like

Conventions: SysV AMD64; rbx/r12 kept as req/out pointers; 16-byte stack
alignment before every call into C; rip-relative pools; `-no-pie` link;
`.note.GNU-stack` section emitted.
-/

import Feed.Types
import Feed.Json
import Feed.Jwt
import Feed.Contract
import Feed.Model

namespace EmitAsm

/-! ## Asm builder -/

/-- Building state: text lines, pooled byte strings (emitted as .byte lists). -/
structure Asm where
  text : List String := []
  data : List String := []
  pool : List (String × String) := []   -- label → content
  mutLabel : Nat := 0
deriving Inhabited

def Asm.raw (a : Asm) (s : String) : Asm := { a with text := a.text ++ [s] }

/-- Emit an instruction/directive line. -/
def Asm.insn (a : Asm) (s : String) : Asm := a.raw ("    " ++ s)

/-- Emit a label (flush left, with colon). -/
def Asm.label (a : Asm) (s : String) : Asm := a.raw (s ++ ":")

/-- Call with 16-byte alignment already guaranteed by our frame. -/
def Asm.call (a : Asm) (f : String) : Asm := a.raw ("    call " ++ f)

/-- Pool a string; returns the label (content emitted as raw bytes). -/
def Asm.poolStr (a : Asm) (s : String) : Asm × String :=
  -- reuse an identical pool entry if present
  match a.pool.find? (fun kv => kv.2 == s) with
  | some kv => (a, kv.1)
  | none =>
    let l := s!".Lstr{a.mutLabel}"
    ({ a with pool := a.pool ++ [(l, s)], mutLabel := a.mutLabel + 1 }, l)

/-- ASCII bytes of a Lean string literal (application-layer literals are ASCII). -/
def asciiBytes (s : String) : List Nat := s.toList.map (fun c => c.toNat)

def byteListAsm (bs : List Nat) : String :=
  ", ".intercalate (bs.map (fun b => toString b))

/-! ## Equates (layout ownership) -/

def equates : List String :=
  [ ".set APPREQ_METHOD, 0"
  , ".set APPREQ_PATH_LEN, 4"
  , ".set APPREQ_PATH, 8"
  , ".set APPREQ_AUTH_LEN, 16"
  , ".set APPREQ_AUTH, 24"
  , ".set APPREQ_BODY_LEN, 32"
  , ".set APPREQ_BODY, 40"
  , ".set OUTBUF_BASE, 0"
  , ".set OUTBUF_LEN, 8"
  , ".set OUTBUF_CAP, 16"
  ]

/-! ## Shared helper routines (emitted once) -/

-- streq(rdi=ptr, rsi=len, rdx=lit, rcx=litlen) -> al = 1/0
def emitStreq (a : Asm) : Asm :=
  let a := a.label ".Lstreq"
  let a := a.insn "cmp rsi, rcx"
  let a := a.insn "jne .Lstreq_no"
  let a := a.label ".Lstreq_loop"
  let a := a.insn "test rcx, rcx"
  let a := a.insn "jz .Lstreq_yes"
  let a := a.insn "movzx r8d, BYTE PTR [rdi]"
  let a := a.insn "movzx r9d, BYTE PTR [rdx]"
  let a := a.insn "cmp r8b, r9b"
  let a := a.insn "jne .Lstreq_no"
  let a := a.insn "inc rdi"
  let a := a.insn "inc rdx"
  let a := a.insn "dec rcx"
  let a := a.insn "jmp .Lstreq_loop"
  let a := a.label ".Lstreq_yes"
  let a := a.insn "mov al, 1"
  let a := a.insn "ret"
  let a := a.label ".Lstreq_no"
  let a := a.insn "xor eax, eax"
  let a := a.insn "ret"
  a

-- parseid(rdi=ptr, rsi=len) -> rax = value, edx = 1 valid | 0 invalid
-- mirrors Feed.parseId exactly: digits-only, value >= 1, i64 overflow -> invalid
def emitParseId (a : Asm) : Asm :=
  let a := a.label ".Lparseid"
  let a := a.insn "test rsi, rsi"
  let a := a.insn "jz .Lparseid_bad"
  let a := a.insn "xor eax, eax"
  let a := a.insn "xor rcx, rcx"
  let a := a.label ".Lparseid_loop"
  let a := a.insn "cmp rcx, rsi"
  let a := a.insn "jae .Lparseid_done"
  let a := a.insn "movzx r8d, BYTE PTR [rdi+rcx]"
  let a := a.insn "sub r8d, 48"
  let a := a.insn "cmp r8d, 9"
  let a := a.insn "ja .Lparseid_bad"
  let a := a.insn "imul rax, rax, 10"
  let a := a.insn "jo .Lparseid_bad"
  let a := a.insn "add rax, r8"
  let a := a.insn "jo .Lparseid_bad"
  let a := a.insn "inc rcx"
  let a := a.insn "jmp .Lparseid_loop"
  let a := a.label ".Lparseid_done"
  let a := a.insn "test rax, rax"
  let a := a.insn "jz .Lparseid_bad"
  let a := a.insn "mov edx, 1"
  let a := a.insn "ret"
  let a := a.label ".Lparseid_bad"
  let a := a.insn "xor eax, eax"
  let a := a.insn "xor edx, edx"
  let a := a.insn "ret"
  a

-- strlen(rdi=cstr) -> rax
def emitStrlen (a : Asm) : Asm :=
  let a := a.label ".Lstrlen"
  let a := a.insn "xor eax, eax"
  let a := a.label ".Lstrlen_loop"
  let a := a.insn "cmp BYTE PTR [rdi+rax], 0"
  let a := a.insn "je .Lstrlen_done"
  let a := a.insn "inc rax"
  let a := a.insn "jmp .Lstrlen_loop"
  let a := a.label ".Lstrlen_done"
  let a := a.insn "ret"
  a

/-! ## Response helpers -/

/-- Append pooled literal `s` to out-buffer register `oreg` (e.g. "r12"). -/
def outStr (a : Asm) (oreg : String) (s : String) : Asm :=
  let (a, l) := a.poolStr s
  let n := String.length s
  a.insn (s!"mov rdi, {oreg}")
   |>.insn (s!"lea rsi, [rip+{l}]")
   |>.insn (s!"mov edx, {n}")
   |>.call "x_out_str"

/-- Append an error body `{"error":"<msg>"}` and set status. -/
def outErrorBody (a : Asm) (oreg : String) (msg : String) : Asm :=
  outStr a oreg ("{\"error\":\"" ++ msg ++ "\"}")

/-! ## Handlers -/

/-- GET /health — mirrors Model.healthNow + Contract.health (SELECT 1 gate). -/
def emitHealth (a : Asm) : Asm :=
  let a := a.label ".Lhealth"
  -- SELECT 1
  let (a, lSql) := a.poolStr "SELECT 1"
  let a := a.insn (s!"lea rdi, [rip+{lSql}]")
  let a := a.insn "mov esi, 8"
  let a := a.call "x_db_prepare"
  let a := a.insn "test rax, rax"
  let a := a.insn "jz .Lhealth_bad"
  let a := a.insn "mov r13, rax"
  let a := a.insn "mov rdi, r13"
  let a := a.call "x_db_step"
  let a := a.insn "cmp eax, 1"
  let a := a.insn "jne .Lhealth_bad_reset"
  let a := a.insn "mov rdi, r13"
  let a := a.call "x_db_reset"
  let a := outStr a "r12" "{\"status\":\"ok\",\"db\":\"ok\",\"uptime_s\":"
  let a := a.insn "mov rdi, r12"
  let a := a.call "x_uptime"
  let a := a.insn "mov rdi, r12"
  let a := a.insn "mov rsi, rax"
  let a := a.call "x_out_int"
  let a := a.insn "mov rdi, r12"
  let a := a.insn "mov esi, 125"          -- '}'
  let a := a.call "x_out_byte"
  let a := a.insn "mov eax, 200"
  let a := a.insn "jmp .Ldone"
  let a := a.label ".Lhealth_bad_reset"
  let a := a.insn "mov rdi, r13"
  let a := a.call "x_db_reset"
  let a := a.label ".Lhealth_bad"
  let a := outStr a "r12" "{\"status\":\"degraded\",\"db\":\"unreachable\",\"error\":"
  let a := a.insn "call x_db_errmsg"
  let a := a.insn "mov r14, rax"
  let a := a.insn "mov rdi, r14"
  let a := a.insn "call .Lstrlen"
  let a := a.insn "mov rdx, rax"
  let a := a.insn "mov rsi, r14"
  let a := a.insn "mov rdi, r12"
  let a := a.call "x_out_json_escaped_str"
  let a := a.insn "mov rdi, r12"
  let a := a.insn "mov esi, 34"           -- '"'
  let a := a.call "x_out_byte"
  let a := a.insn "mov rdi, r12"
  let a := a.insn "mov esi, 125"          -- '}'
  let a := a.call "x_out_byte"
  let a := a.insn "mov eax, 503"
  let a := a.insn "jmp .Ldone"
  a

/-- GET /posts/:id with a VALID id — full row fetch lands in M3; M2 stub. -/
def emitGetPostValid (a : Asm) : Asm :=
  let a := a.label ".Lgetpost"
  let a := a.insn "mov rdi, r12"
  let a := a.call "x_fail"                -- eax = 500
  let a := a.insn "jmp .Ldone"
  a

/-- GET /feed — M3; M2 stub. -/
def emitFeed (a : Asm) : Asm :=
  let a := a.label ".Lfeed"
  let a := a.insn "mov rdi, r12"
  let a := a.call "x_fail"
  let a := a.insn "jmp .Ldone"
  a

/-- POST routes — auth lands in M4; M2 stub. -/
def emitPost (a : Asm) : Asm :=
  let a := a.label ".Lpost"
  let a := a.insn "mov rdi, r12"
  let a := a.call "x_fail"
  let a := a.insn "jmp .Ldone"
  a

/-! ## app_request: routing (mirrors Model.handle) -/

def emitAppRequest (a : Asm) : Asm :=
  let a := a.raw ".globl app_request"
  let a := a.label "app_request"
  let a := a.insn "push rbx"
  let a := a.insn "push rbp"
  let a := a.insn "push r12"
  let a := a.insn "push r13"
  let a := a.insn "push r14"
  let a := a.insn "push r15"
  let a := a.insn "sub rsp, 8"
  let a := a.insn "mov rbx, rdi"
  let a := a.insn "mov r12, rsi"
  -- method dispatch (AppReq.method: 0=GET 1=POST other=404)
  let a := a.insn "mov eax, [rbx+APPREQ_METHOD]"
  let a := a.insn "cmp eax, 0"
  let a := a.insn "je .Lroute_get"
  let a := a.insn "cmp eax, 1"
  let a := a.insn "je .Lroute_post"
  let a := a.insn "jmp .Lnotfound"
  -- GET
  let a := a.label ".Lroute_get"
  let a := a.insn "mov rdi, [rbx+APPREQ_PATH]"
  let a := a.insn "mov esi, [rbx+APPREQ_PATH_LEN]"
  let (a, lHealth) := a.poolStr "/health"
  let a := a.insn (s!"lea rdx, [rip+{lHealth}]")
  let a := a.insn "mov ecx, 7"
  let a := a.insn "call .Lstreq"
  let a := a.insn "test al, al"
  let a := a.insn "jnz .Lhealth"
  let (a, lFeed) := a.poolStr "/feed"
  let a := a.insn "mov rdi, [rbx+APPREQ_PATH]"
  let a := a.insn "mov esi, [rbx+APPREQ_PATH_LEN]"
  let a := a.insn (s!"lea rdx, [rip+{lFeed}]")
  let a := a.insn "mov ecx, 5"
  let a := a.insn "call .Lstreq"
  let a := a.insn "test al, al"
  let a := a.insn "jnz .Lfeed"
  -- /posts/:id (GET) — prefix "/posts/" then id segment must be the LAST segment
  let a := a.insn "mov rdi, [rbx+APPREQ_PATH]"
  let a := a.insn "mov esi, [rbx+APPREQ_PATH_LEN]"
  let (a, lPosts) := a.poolStr "/posts/"
  let a := a.insn (s!"lea rdx, [rip+{lPosts}]")
  let a := a.insn "mov ecx, 7"
  let a := a.insn "call .Lstreqpfx"
  let a := a.insn "test al, al"
  let a := a.insn "jz .Lnotfound"
  let a := a.insn "mov rdi, [rbx+APPREQ_PATH]"
  let a := a.insn "add rdi, 7"
  let a := a.insn "mov esi, [rbx+APPREQ_PATH_LEN]"
  let a := a.insn "sub esi, 7"
  let a := a.insn "call .Lhas_slash"
  let a := a.insn "test al, al"
  let a := a.insn "jnz .Lnotfound"            -- "/posts/1/like" as GET -> 404
  let a := a.insn "mov rdi, [rbx+APPREQ_PATH]"
  let a := a.insn "add rdi, 7"
  let a := a.insn "mov esi, [rbx+APPREQ_PATH_LEN]"
  let a := a.insn "sub esi, 7"
  let a := a.insn "call .Lparseid"
  let a := a.insn "test edx, edx"
  let a := a.insn "jz .Linvalidid"
  let a := a.insn "jmp .Lgetpost"             -- M3: row fetch; M2 stub 500
  -- POST (M2: everything stub)
  let a := a.label ".Lroute_post"
  let a := a.insn "jmp .Lpost"
  -- error responses
  let a := a.label ".Lnotfound"
  let a := outErrorBody a "r12" "not found"
  let a := a.insn "mov eax, 404"
  let a := a.insn "jmp .Ldone"
  let a := a.label ".Linvalidid"
  let a := outErrorBody a "r12" "invalid post id"
  let a := a.insn "mov eax, 400"
  let a := a.insn "jmp .Ldone"
  -- epilogue
  let a := a.label ".Ldone"
  let a := a.insn "add rsp, 8"
  let a := a.insn "pop r15"
  let a := a.insn "pop r14"
  let a := a.insn "pop r13"
  let a := a.insn "pop r12"
  let a := a.insn "pop rbp"
  let a := a.insn "pop rbx"
  let a := a.insn "ret"
  a

-- streqpfx(rdi=ptr, rsi=len, rdx=lit, rcx=litlen) -> al = 1 if len>=litlen and prefix matches
def emitStreqpfx (a : Asm) : Asm :=
  let a := a.label ".Lstreqpfx"
  let a := a.insn "cmp rsi, rcx"
  let a := a.insn "jb .Lstreqpfx_no"
  let a := a.label ".Lstreqpfx_loop"
  let a := a.insn "test rcx, rcx"
  let a := a.insn "jz .Lstreqpfx_yes"
  let a := a.insn "movzx r8d, BYTE PTR [rdi]"
  let a := a.insn "movzx r9d, BYTE PTR [rdx]"
  let a := a.insn "cmp r8b, r9b"
  let a := a.insn "jne .Lstreqpfx_no"
  let a := a.insn "inc rdi"
  let a := a.insn "inc rdx"
  let a := a.insn "dec rcx"
  let a := a.insn "jmp .Lstreqpfx_loop"
  let a := a.label ".Lstreqpfx_yes"
  let a := a.insn "mov al, 1"
  let a := a.insn "ret"
  let a := a.label ".Lstreqpfx_no"
  let a := a.insn "xor eax, eax"
  let a := a.insn "ret"
  a

-- has_slash(rdi=ptr, rsi=len) -> al
def emitHasSlash (a : Asm) : Asm :=
  let a := a.label ".Lhas_slash"
  let a := a.insn "xor eax, eax"
  let a := a.insn "xor rcx, rcx"
  let a := a.label ".Lhas_slash_loop"
  let a := a.insn "cmp rcx, rsi"
  let a := a.insn "jae .Lhas_slash_done"
  let a := a.insn "cmp BYTE PTR [rdi+rcx], 47"
  let a := a.insn "je .Lhas_slash_yes"
  let a := a.insn "inc rcx"
  let a := a.insn "jmp .Lhas_slash_loop"
  let a := a.label ".Lhas_slash_yes"
  let a := a.insn "mov al, 1"
  let a := a.insn "ret"
  let a := a.label ".Lhas_slash_done"
  let a := a.insn "xor eax, eax"
  let a := a.insn "ret"
  a

/-- app_init: nothing to do in M2 (JWT secret is fetched lazily in M4). -/
def emitAppInit (a : Asm) : Asm :=
  let a := a.raw ".globl app_init"
  let a := a.label "app_init"
  let a := a.insn "xor eax, eax"
  let a := a.insn "ret"
  a

/-! ## Whole program -/

def program : String :=
  let a0 : Asm := {}
  -- helpers + handlers + entry
  let a := emitStreq a0
  let a := emitStreqpfx a
  let a := emitHasSlash a
  let a := emitParseId a
  let a := emitStrlen a
  let a := emitAppInit a
  let a := emitAppRequest a
  let a := emitHealth a
  let a := emitFeed a
  let a := emitGetPostValid a
  let a := emitPost a
  -- pooled strings used by handlers, each emitted as raw bytes
  let poolLines : List String :=
    a.pool.map (fun kv => s!"{kv.1}:" ++ "\n" ++ s!"    .byte {byteListAsm (asciiBytes kv.2)}")
  let dataLines := ".section .rodata" :: poolLines
  let text := String.join (a.text.map (fun l => l ++ "\n"))
  let header := String.join
    [ "# gen/app_gen.s — EMITTED by spec/EmitAsm.lean (lake exe derive). Do not hand-edit.\n"
    , "# Layout equates: owned here, pinned by runtime/abi.h _Static_asserts.\n"
    , ".intel_syntax noprefix\n"
    , String.join (equates.map (fun e => e ++ "\n"))
    , ".text\n" ]
  let footer := "\n.section .note.GNU-stack,\"\",@progbits\n"
  header ++ text ++ String.join (dataLines.map (fun l => l ++ "\n")) ++ footer

end EmitAsm
