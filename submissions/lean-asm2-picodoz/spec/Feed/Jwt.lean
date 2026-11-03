/-
Feed.Jwt — HS256 JWT verification, staged so the alg/exp/signature discipline is provable.

Result classification (mirrors SPEC.md's error table):
- `missingBearer` — no Authorization header / no `Bearer ` prefix (401 "missing bearer token")
- `invalid`       — malformed JWT, alg ≠ HS256, bad signature, exp missing/non-int/expired
                    (401 "invalid or expired token")
- `badPayload`    — valid signature+alg+exp, but `sub` not a digits≥1 string or `username`
                    not a string (401 "invalid token payload")
- `ok uid name`   — authenticated

Stage discipline (proved in Feed.Invariant):
  badPayload ⇒ structural (alg=HS256 + signature) AND temporal (exp ok) checks passed.
  i.e. payload errors are never reported for structurally/temporally invalid tokens,
  and structural failures are never reported as payload errors.

Decisions (documented, consistent with the suite): `exp` required and integer with
exp > now; `iat` ignored; header fields other than `alg` ignored; signature compared as
unpadded base64url strings.
-/

import Feed.Types
import Feed.Json
import Feed.Sha256

open Feed Json Sha256

namespace Jwt

/-- Split on '.' (there is no `String.splitOn` dependency here; hand-rolled, exact). -/
def splitDot (s : String) : List String :=
  let rec go (cs : List Char) (acc : List Char) : List String :=
    match cs with
    | [] => [String.ofList acc.reverse]
    | '.' :: rest => String.ofList acc.reverse :: go rest []
    | c :: rest => go rest (c :: acc)
  go s.toList []

/-
Stage 1 — structural: 3 dot-separated parts, b64url-decodable header+payload (+sig bytes),
header JSON object with alg == "HS256", HMAC-SHA256(secret, header64 ++ "." ++ payload64)
base64url == the signature part.
-/
def verifyStructural (cfg : Config) (token : String) : Option Json :=
  match splitDot token with
  | [h64, p64, s64] =>
    do
      let hBytes ← b64urlDecode h64
      let pBytes ← b64urlDecode p64
      let _sBytes ← b64urlDecode s64
      let hTxt ← utf8Decode hBytes
      let pTxt ← utf8Decode pBytes
      let hJson ← Json.parse hTxt
      let pJson ← Json.parse pTxt
      -- alg discipline
      match hJson.getField? "alg" with
      | some (.str "HS256") =>
        -- signature over the ASCII bytes of "h64.p64"
        let signed := utf8Encode (h64 ++ "." ++ p64)
        let mac := b64urlEncode (hmac (utf8Encode cfg.jwtSecret) signed)
        if mac == s64 then some pJson else none
      | _ => none
  | _ => none

/-- Stage 2 — temporal: `exp` present, a JSON integer, strictly greater than now. -/
def expOf (payload : Json) : Option Int :=
  match payload.getField? "exp" with
  | some (.num e) => some e
  | _ => none

def verifyTemporal (now : Int) (payload : Json) : Bool :=
  match expOf payload with
  | some e => e > now
  | none => false

/-- `sub` as a user id: digits-only string with value ≥ 1. -/
def subOf (payload : Json) : Option Int :=
  match payload.getField? "sub" with
  | some (.str s) => Feed.parseId s
  | _ => none

/-- Stage 3 — payload: `sub` a digits≥1 string, `username` a string. -/
def verifyPayload (payload : Json) : Option (Int × String) :=
  match subOf payload with
  | some uid =>
    match payload.getField? "username" with
    | some (.str name) => some (uid, name)
    | _ => none
  | none => none

/-- The JWT verification pipeline. -/
inductive JwtResult where
  | missingBearer
  | invalid
  | badPayload
  | ok (uid : Int) (name : String)
deriving DecidableEq, Repr

def verify (cfg : Config) (token : String) (now : Int) : JwtResult :=
  match verifyStructural cfg token with
  | none => .invalid
  | some payload =>
    if verifyTemporal now payload then
      match verifyPayload payload with
      | none => .badPayload
      | some (uid, name) => .ok uid name
    else .invalid

/-- Map an Authorization header value to the JWT verdict. -/
def authCheck (cfg : Config) (req : Request) (now : Int) : JwtResult :=
  match req.authorization with
  | none => .missingBearer
  | some v =>
    if v.startsWith "Bearer " then
      verify cfg (String.ofList (v.toList.drop 7)) now
    else .missingBearer

/-! ## Signing (used by fixtures / SpecCheck analogues; mirrors the challenge's openssl pipeline) -/

def sign (secret : String) (headerJson payloadJson : String) : String :=
  let h64 := b64urlEncode (utf8Encode headerJson)
  let p64 := b64urlEncode (utf8Encode payloadJson)
  let mac := b64urlEncode (hmac (utf8Encode secret) (utf8Encode (h64 ++ "." ++ p64)))
  h64 ++ "." ++ p64 ++ "." ++ mac

end Jwt
