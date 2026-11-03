/-
Feed.Types — core domain types of the executable requirement specification.

The spec models the server as pure functions:
  handler : Request → ModelDb → Now → Response × ModelDb

Everything the application layer sees is data here; IO, sockets, SQL and HTTP framing live
in the runtime and are out of scope of the *requirement* (they are pinned by the contract
tests instead).

Documented edge decisions (SPEC.md leaves these open; the test suite never contradicts them):
- `:id` is a nonempty string of ASCII digits with numeric value ≥ 1 ("007" accepted);
  anything else (including values past 2^63) is `400 invalid post id`.
- `Bearer ` prefix is matched case-sensitively; the rest is the raw token.
- `exp` is REQUIRED, must be a JSON integer, and must satisfy exp > now (exp = now expired).
- `sub` must be digits-only with value ≥ 1; `username` must be present and a string.
- body length is counted in Unicode code points after trimming.
- unknown path OR wrong method on a known path → 404 `not found`.
- a query string is stripped before routing and otherwise ignored.
- trailing-slash variants are NOT identified with the bare path.
-/

namespace Feed

/-- HTTP methods the API distinguishes. -/
inductive Method where
  | GET | POST
deriving DecidableEq, Repr

/-- One HTTP request, as seen by the application layer. -/
structure Request where
  method : Method
  -- request target path WITH query string stripped ("/posts/42/like")
  path : String
  -- value of the Authorization header, if present
  authorization : Option String
  -- raw request body (decoded UTF-8; bodies are JSON text)
  body : String
deriving DecidableEq, Repr

/-- One HTTP response: status plus the exact body bytes. -/
structure Response where
  status : Nat
  body : String
deriving DecidableEq, Repr

def Response.isError (r : Response) : Bool := r.status ≥ 400

/-- A feed post exactly as serialized on the wire. -/
structure Post where
  id : Int
  body : String
  createdAt : String
  author : String
  likeCount : Int
deriving DecidableEq, Repr

/-- Time context handed to a handler. -/
structure Now where
  -- current unix time (seconds)
  nowSec : Int
  -- server start time (seconds) — uptime = nowSec - startSec
  startSec : Int
  -- created_at stamp assigned to rows inserted "now" (DB default format)
  insertStamp : String
deriving DecidableEq, Repr

def Now.uptime (n : Now) : Int := n.nowSec - n.startSec

/-- Static configuration (environment). -/
structure Config where
  jwtSecret : String
deriving DecidableEq, Repr

/-
ModelDb — an executable model of the database view the handlers need.
`posts` is kept newest-first (the order /feed emits); inserts prepend.
`liked` records (user, post) pairs that already have a like row.
-/
structure ModelDb where
  posts : List Post
  nextPostId : Int
  liked : List (Int × Int)
  -- would `SELECT 1` succeed?
  healthy : Bool
  -- error string for the degraded /health body
  healthError : String
deriving DecidableEq, Repr

/-! ## Input shaping helpers -/

/-- Whitespace as JSON/trimming understands it. -/
def isWs (c : Char) : Bool :=
  c = ' ' || c = '\t' || c = '\n' || c = '\r'

/-- Drop trailing whitespace (code-point-wise), recursively. -/
def dropTrailing : List Char → List Char
  | [] => []
  | c :: cs =>
    let t := dropTrailing cs
    if isWs c && t.isEmpty then [] else c :: t

/-- Character-list trim: drop leading, then trailing whitespace. -/
def trimList (cs : List Char) : List Char := dropTrailing (cs.dropWhile isWs)

/-- Drop leading and trailing whitespace characters (code-point-wise). -/
def trim (s : String) : String := String.ofList (trimList s.toList)

/-- `true` iff the request carries no usable bearer token (no header or wrong scheme). -/
def bearerMissing (req : Request) : Bool :=
  match req.authorization with
  | none => true
  | some v => !(v.startsWith "Bearer ")

/--
`parseId` — the `:id` classification: `some n` with `n ≥ 1` iff `s` is a nonempty digit
string of value ≥ 1. Digits are ASCII only; the numeric value is arbitrary precision here
(the emitted asm uses i64 with an overflow check that maps to the same `none`).
-/
def parseId (s : String) : Option Int :=
  let cs := s.toList
  if cs.isEmpty then none
  else if cs.any (fun c => !(c.isDigit)) then none
  else
    let n := cs.foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0
    if n ≥ 1 then some n else none

end Feed
