/-
Feed.SpecDump — `lake exe specdump <corpus`: run the differential corpus against
the LEAN SPEC functions and print results in the exact format tests/asm_corpus.c
prints for the emitted asm. tools/diff_corpus.sh diffs the two.
-/

import Feed.Types
import Feed.Json
import Feed.Sha256
import Feed.Jwt

open Feed Json Sha256

def unhex (s : String) : Option (List UInt8) :=
  let cs := s.toList
  let rec go (cs : List Char) (acc : List UInt8) : Option (List UInt8) :=
    match cs with
    | [] => some acc.reverse
    | a :: b :: rest =>
      let d (c : Char) : Option Nat :=
        let n := c.toNat
        if n ≥ '0'.toNat && n ≤ '9'.toNat then some (n - '0'.toNat)
        else if n ≥ 'a'.toNat && n ≤ 'f'.toNat then some (n - 'a'.toNat + 10)
        else if n ≥ 'A'.toNat && n ≤ 'F'.toNat then some (n - 'A'.toNat + 10)
        else none
      match d a, d b with
      | some hi, some lo => go rest (UInt8.ofNat (hi * 16 + lo) :: acc)
      | _, _ => none
    | _ => none
  go cs []

def toByteArray (bs : List UInt8) : ByteArray :=
  bs.foldl (fun acc u => acc.push u) ByteArray.empty

def hexOfList (bs : List UInt8) : String :=
  String.join (bs.map (fun u =>
    let n := u.toNat
    let hx (m : Nat) : Char := if m < 10 then Char.ofNat ('0'.toNat + m) else Char.ofNat ('a'.toNat + (m - 10))
    String.ofList [hx (n / 16), hx (n % 16)]))

/-- bytes -> String via lenient UTF-8 (for Json.parse input; corpus JSON is ASCII
except raw-UTF-8 cases, which we map through our own decoder to stay honest). -/
def bytesToString (bs : List UInt8) : String :=
  match utf8Decode (toByteArray bs) with
  | some s => s
  | none => String.ofList [Char.ofNat 0xFFFD]   -- invalid utf8 corpus cases are J-invalid anyway

def processLine (idx : Nat) (l : String) : String :=
  let parts := l.splitOn " "
  match parts with
  | "J" :: hex :: _ =>
    match unhex hex with
    | none => s!"J{idx} hexerr"
    | some bs =>
      -- RFC 8259: a JSON text is UTF-8; invalid encodings are invalid documents
      match utf8Decode (toByteArray bs) with
      | none => s!"J{idx} bad"
      | some txt => if (Json.parse txt).isSome then s!"J{idx} ok" else s!"J{idx} bad"
  | "U" :: hex :: _ =>
    match unhex hex with
    | none => s!"U{idx} hexerr"
    | some bs =>
      -- spec: parse the quoted string, take the unescaped value bytes
      let txt := bytesToString bs
      match Json.parse ( "\"" ++ txt ++ "\"") with
      | some (.str s) => s!"U{idx} {hexOfList (utf8Encode s).toList}"
      | _ => s!"U{idx} ERR"
  | "B" :: hex :: _ =>
    match unhex hex with
    | none => s!"B{idx} hexerr"
    | some bs =>
      let barr := toByteArray bs
      let enc := b64urlEncode barr
      match b64urlDecode enc with
      | some dec => s!"B{idx} {enc} {hexOfList dec.toList}"
      | none => s!"B{idx} MISMATCH"
  | "S" :: hex :: _ =>
    match unhex hex with
    | none => s!"S{idx} hexerr"
    | some bs => s!"S{idx} {toHex (hash (toByteArray bs))}"
  | "H" :: keyhex :: msghex :: _ =>
    match unhex keyhex, unhex msghex with
    | some k, some m => s!"H{idx} {toHex (hmac (toByteArray k) (toByteArray m))}"
    | _, _ => s!"H{idx} hexerr"
  | "I" :: rest =>
    let txt := (l.drop 2).toString
    match parseId txt with
    | some n =>
      -- the asm maps i64 overflow to invalid (documented edge decision); mirror it
      if n > 9223372036854775807 then s!"I{idx} none0" else s!"I{idx} {n}"
    | none => s!"I{idx} none0"
  | "E" :: rest =>
    let txt := (l.drop 2).toString
    -- parseexp: -?digits
    let cs := txt.toList
    let (neg, digits) := match cs with | '-' :: r => (true, r) | r => (false, r)
    if digits.isEmpty || digits.any (fun c => !c.isDigit) then
      s!"E{idx} bad0"
    else
      let n := digits.foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0
      -- asm saturates at i64 max; corpus max is 10^20-ish; mirror the saturation
      let v := if n > 9223372036854775807 then (9223372036854775807 : Int) else n
      let v := if neg then -v else v
      s!"E{idx} {v}"
  | _ => s!"?{idx} unknown"

def main (args : List String) : IO UInt32 := do
  let stdin ← IO.getStdin
  let mut idx := 0
  let mut out := ""
  while true do
    let line ← stdin.getLine
    if line.isEmpty then break
    let l := String.ofList ((line.toList.reverse.dropWhile (fun c => c == '\n' || c == '\r')).reverse)
    idx := idx + 1
    out := out ++ processLine idx l ++ "\n"
  IO.print out
  return 0
