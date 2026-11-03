/-
Feed.Json — minimal JSON value, strict parser, compact serializer.

Serializer contract (what the challenge pins byte-exactly):
- compact: no spaces anywhere
- object key order is the order of the assoc list (never sorted)
- strings escape `"` `\` and the C0 controls (`\b \f \n \r \t \u00xx`); everything else,
  including `<>&/` and non-ASCII, is emitted raw (SPEC: escaping those is optional)
- integers in plain decimal (no exponent, no `.0`)
- booleans as `true` / `false`

Parser contract:
- strict JSON grammar (no trailing commas, missing commas rejected, trailing garbage rejected)
- `\uXXXX` escapes incl. surrogate pairs; a lone surrogate is malformed
- numbers WITHOUT `.`/`e`/`E` parse to `.num : Int`; numbers with them parse to
  `.fnum` — the VALUE of a float is not preserved (no endpoint decision depends on it;
  only "it is not an integer / not a string" matters)
-/

inductive Json where
  | null
  | bool (b : Bool)
  | num (i : Int)
  | fnum
  | str (s : String)
  | arr (items : List Json)
  | obj (fields : List (String × Json))
deriving BEq, Repr

namespace Json

/-! ## Serialization -/

def hexDigitChar (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n) else Char.ofNat ('a'.toNat + (n - 10))

def escapeChar (c : Char) : String :=
  match c with
  | '"'  => "\\\""
  | '\\' => "\\\\"
  | '\n' => "\\n"
  | '\r' => "\\r"
  | '\t' => "\\t"
  | '\x08' => "\\b"   -- BS 0x08
  | '\x0c' => "\\f"   -- FF 0x0c
  | c =>
    let n := c.toNat
    if n < 0x20 then "\\u00" ++ String.ofList [hexDigitChar (n / 16), hexDigitChar (n % 16)]
    else String.ofList [c]

/-- Escape a string for use inside JSON double quotes. -/
def escape (s : String) : String := String.join (s.toList.map escapeChar)

partial def serialize : Json → String
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .num i => toString i
  | .fnum => "0.0"
  | .str s => "\"" ++ escape s ++ "\""
  | .arr items => "[" ++ String.join ((items.map serialize).intersperse ",") ++ "]"
  | .obj fields =>
    let field (kv : String × Json) : String := "\"" ++ escape kv.1 ++ "\":" ++ serialize kv.2
    "{" ++ String.join ((fields.map field).intersperse ",") ++ "}"

/-! ## Parsing -/

/-- Parser input: remaining characters. -/
abbrev P := List Char

private def digitVal (c : Char) : Option Nat :=
  let n := c.toNat
  if n ≥ '0'.toNat && n ≤ '9'.toNat then some (n - '0'.toNat) else none

private def isDigitC (c : Char) : Bool := (digitVal c).isSome

private def hexVal (c : Char) : Option Nat :=
  let n := c.toNat
  if n ≥ '0'.toNat && n ≤ '9'.toNat then some (n - '0'.toNat)
  else if n ≥ 'a'.toNat && n ≤ 'f'.toNat then some (n - 'a'.toNat + 10)
  else if n ≥ 'A'.toNat && n ≤ 'F'.toNat then some (n - 'A'.toNat + 10)
  else none

private def ws (p : P) : P := p.dropWhile (fun c => c = ' ' || c = '\t' || c = '\n' || c = '\r')

private def parseHex4 : List Char → Option (Nat × List Char)
  | a :: b :: c :: d :: rest => do
    let h1 ← hexVal a; let h2 ← hexVal b; let h3 ← hexVal c; let h4 ← hexVal d
    some (h1 * 4096 + h2 * 256 + h3 * 16 + h4, rest)
  | _ => none

private def isHighSurrogate (n : Nat) : Bool := n ≥ 0xD800 && n ≤ 0xDBFF
private def isLowSurrogate (n : Nat) : Bool := n ≥ 0xDC00 && n ≤ 0xDFFF

/-- Code point → Char; rejects lone surrogates and out-of-range values. -/
private def charOf (n : Nat) : Option Char :=
  if n ≤ 0x10FFFF && !(isHighSurrogate n || isLowSurrogate n) then some (Char.ofNat n) else none

private partial def parseStrAux (acc : List Char) : P → Option (String × P)
  | [] => none
  | '"' :: rest => some (String.ofList acc.reverse, rest)
  | '\\' :: e :: rest =>
    let cont (c : Char) := parseStrAux (c :: acc) rest
    match e with
    | '"' => cont '"'
    | '\\' => cont '\\'
    | '/' => cont '/'
    | 'b' => cont '\x08'
    | 'f' => cont '\x0c'
    | 'n' => cont '\n'
    | 'r' => cont '\r'
    | 't' => cont '\t'
    | 'u' =>
      match parseHex4 rest with
      | some (h, rest') =>
        if isHighSurrogate h then
          match rest' with
          | '\\' :: 'u' :: rest'' =>
            match parseHex4 rest'' with
            | some (l, rest3) =>
              if isLowSurrogate l then
                match charOf (0x10000 + (h - 0xD800) * 0x400 + (l - 0xDC00)) with
                | some c => parseStrAux (c :: acc) rest3
                | none => none
              else none
            | none => none
          | _ => none
        else
          match charOf h with
          | some c => parseStrAux (c :: acc) rest'
          | none => none
      | none => none
    | _ => none
  | c :: rest =>
    let n := c.toNat
    if n < 0x20 then none else parseStrAux (c :: acc) rest

mutual

/-- Parse a number (sign handled by caller). Integer values exact; floats marked only. -/
private partial def parseNum (neg : Bool) (p : P) : Option (Json × P) :=
  let digits := p.takeWhile isDigitC
  if digits.isEmpty then none
  else
    let intVal := digits.foldl (fun acc c => acc * 10 + (digitVal c).get!) 0
    let r1 := p.drop digits.length
    match r1 with
    | '.' :: _ | 'e' :: _ | 'E' :: _ =>
      -- consume [. digits] and/or [e[+-]digits]; at least one digit required after each marker
      let frac : P → Option P
        | '.' :: r =>
          let ds := r.takeWhile isDigitC
          if ds.isEmpty then none else some (r.drop ds.length)
        | r => some r
      match frac r1 with
      | none => none
      | some r2 =>
        let expo : P → Option P
          | e :: r =>
            if e = 'e' || e = 'E' then
              match r with
              | s :: r' =>
                let r'' := if s = '+' || s = '-' then r' else r
                let ds := r''.takeWhile isDigitC
                if ds.isEmpty then none else some (r''.drop ds.length)
              | [] => none
            else some r
          | r => some r
        match expo r2 with
        | none => none
        | some r3 => some (.fnum, r3)
    | _ => some (.num (if neg then -intVal else intVal), r1)

private partial def parseValue : P → Option (Json × P) := fun p =>
  match ws p with
  | '{' :: rest => do
    let (fields, r) ← parseFields (ws rest)
    some (.obj fields, r)
  | '[' :: rest => do
    let (items, r) ← parseItems (ws rest)
    some (.arr items, r)
  | '"' :: rest => do
    let (s, r) ← parseStrAux [] rest
    some (.str s, r)
  | 't' :: 'r' :: 'u' :: 'e' :: rest => some (.bool true, rest)
  | 'f' :: 'a' :: 'l' :: 's' :: 'e' :: rest => some (.bool false, rest)
  | 'n' :: 'u' :: 'l' :: 'l' :: rest => some (.null, rest)
  | '-' :: rest => parseNum true rest
  | p => parseNum false p

/-- After `{` + ws: `"key": value` (`,` `"key": value`)* `}` — strict. -/
private partial def parseFields (p : P) : Option (List (String × Json) × P) :=
  match p with
  | '}' :: rest => some ([], rest)
  | '"' :: rest => do
    let (k, r1) ← parseStrAux [] rest
    match ws r1 with
    | ':' :: r2 => do
      let (v, r3) ← parseValue r2
      parseFieldsTail [(k, v)] (ws r3)
    | _ => none
  | _ => none

private partial def parseFieldsTail (acc : List (String × Json)) : P → Option (List (String × Json) × P)
  | '}' :: rest => some (acc.reverse, rest)
  | ',' :: rest => match ws rest with
    | '"' :: r => do
      let (k, r1) ← parseStrAux [] r
      match ws r1 with
      | ':' :: r2 => do
        let (v, r3) ← parseValue r2
        parseFieldsTail ((k, v) :: acc) (ws r3)
      | _ => none
    | _ => none
  | _ => none

/-- After `[` + ws: `value` (`,` `value`)* `]` — strict. -/
private partial def parseItems (p : P) : Option (List Json × P) :=
  match p with
  | ']' :: rest => some ([], rest)
  | _ => do
    let (v, r) ← parseValue p
    parseItemsTail [v] (ws r)

private partial def parseItemsTail (acc : List Json) : P → Option (List Json × P)
  | ']' :: rest => some (acc.reverse, rest)
  | ',' :: rest => do
    let (v, r) ← parseValue (ws rest)
    parseItemsTail (v :: acc) (ws r)
  | _ => none

end

/-- Parse a complete JSON document (entire input must be one value + optional whitespace). -/
def parse (s : String) : Option Json :=
  match parseValue s.toList with
  | some (v, rest) => if (ws rest).isEmpty then some v else none
  | none => none

/-- Look a field up in an object (first occurrence wins). -/
def getField? : Json → String → Option Json
  | .obj fields, k => (fields.find? (fun kv => kv.1 == k)).map (·.2)
  | _, _ => none

/-! ## Typed accessors (jq-analogue helpers for SpecCheck) -/

def asStr? : Json → Option String
  | .str s => some s
  | _ => none

def asInt? : Json → Option Int
  | .num i => some i
  | _ => none

def asArrLen? : Json → Option Nat
  | .arr items => some items.length
  | _ => none

def asHead? : Json → Option Json
  | .arr (h :: _) => some h
  | _ => none

end Json
