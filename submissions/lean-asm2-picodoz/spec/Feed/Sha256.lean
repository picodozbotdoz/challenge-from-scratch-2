/-
Feed.Sha256 — byte codecs, SHA-256, HMAC-SHA256, base64url.

Pure Lean (core only). The emitted asm re-implements exactly these algorithms; SpecCheck
validates them against the standard published test vectors, and the M6 differential harness
cross-checks spec vs asm on corpora.

Shift discipline: all UInt32 shifts use amounts in [0, 31] (rotation amounts in this
algorithm are 2..25; `rotr32` avoids the ambiguous amount-32 case explicitly).
Loops that advance an index recurse on a structural `fuel` argument.
-/

namespace Sha256

/-! ## Byte helpers -/

def mapBytes (f : UInt8 → UInt8) (b : ByteArray) : ByteArray :=
  let rec go (fuel : Nat) (i : Nat) (acc : ByteArray) : ByteArray :=
    match fuel with
    | 0 => acc
    | fuel + 1 =>
      if i ≥ b.size then acc
      else go fuel (i + 1) (acc.push (f b[i]!))
  go b.size 0 ByteArray.empty

/-! ## UTF-8 codec -/

/-- Encode a String as UTF-8 bytes (code point → 1..4 octets). -/
def utf8Encode (s : String) : ByteArray :=
  let rec go (cs : List Char) (acc : ByteArray) : ByteArray :=
    match cs with
    | [] => acc
    | c :: rest =>
      let n := c.toNat
      let acc :=
        if n < 0x80 then acc.push (UInt8.ofNat n)
        else if n < 0x800 then
          let a1 := acc.push (UInt8.ofNat (0xC0 + n / 64))
          a1.push (UInt8.ofNat (0x80 + n % 64))
        else if n < 0x10000 then
          let a1 := acc.push (UInt8.ofNat (0xE0 + n / 4096))
          let a2 := a1.push (UInt8.ofNat (0x80 + n / 64 % 64))
          a2.push (UInt8.ofNat (0x80 + n % 64))
        else
          let a1 := acc.push (UInt8.ofNat (0xF0 + n / 262144))
          let a2 := a1.push (UInt8.ofNat (0x80 + n / 4096 % 64))
          let a3 := a2.push (UInt8.ofNat (0x80 + n / 64 % 64))
          a3.push (UInt8.ofNat (0x80 + n % 64))
      go rest acc
  go s.toList ByteArray.empty

/-- Strict UTF-8 decode (rejects overlongs, surrogates, truncated sequences). -/
def utf8Decode (b : ByteArray) : Option String :=
  let n := b.size
  let rec go (fuel : Nat) (i : Nat) (acc : List Char) : Option (List Char) :=
    match fuel with
    | 0 => none
    | fuel + 1 =>
      if i ≥ n then some acc.reverse
      else
        let b0 := b[i]!.toNat
        if b0 < 0x80 then go fuel (i + 1) (Char.ofNat b0 :: acc)
        else if b0 < 0xC0 then none                          -- stray continuation
        else if b0 < 0xE0 then                               -- 2-byte
          if i + 1 ≥ n then none
          else
            let b1 := b[i + 1]!.toNat
            let cp := (b0 % 32) * 64 + (b1 % 64)
            if b1 < 0x80 || b1 ≥ 0xC0 || cp < 0x80 then none
            else go fuel (i + 2) (Char.ofNat cp :: acc)
        else if b0 < 0xF0 then                               -- 3-byte
          if i + 2 ≥ n then none
          else
            let b1 := b[i + 1]!.toNat
            let b2 := b[i + 2]!.toNat
            let cp := (b0 % 16) * 4096 + (b1 % 64) * 64 + (b2 % 64)
            if b1 < 0x80 || b1 ≥ 0xC0 || b2 < 0x80 || b2 ≥ 0xC0 || cp < 0x800
                || (cp ≥ 0xD800 && cp ≤ 0xDFFF) then none
            else go fuel (i + 3) (Char.ofNat cp :: acc)
        else if b0 < 0xF8 then                               -- 4-byte
          if i + 3 ≥ n then none
          else
            let b1 := b[i + 1]!.toNat
            let b2 := b[i + 2]!.toNat
            let b3 := b[i + 3]!.toNat
            let cp := (b0 % 8) * 262144 + (b1 % 64) * 4096 + (b2 % 64) * 64 + (b3 % 64)
            if b1 < 0x80 || b1 ≥ 0xC0 || b2 < 0x80 || b2 ≥ 0xC0 || b3 < 0x80 || b3 ≥ 0xC0
                || cp < 0x10000 || cp > 0x10FFFF then none
            else go fuel (i + 4) (Char.ofNat cp :: acc)
        else none                                            -- 0xF8..: never valid
  match go (n + 1) 0 [] with
  | some cs => some (String.ofList cs)
  | none => none

/-! ## SHA-256 -/

private def K : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

private def H0 : Array UInt32 := #[
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

/-- Rotate right; `n` in [0, 32]; amount 0 short-circuits (avoids the `<<< 32` case). -/
def rotr32 (x : UInt32) (n : Nat) : UInt32 :=
  if n = 0 then x
  else (x >>> UInt32.ofNat n) ||| (x <<< UInt32.ofNat (32 - n))

private def be32 (b : ByteArray) (i : Nat) : UInt32 :=
  (UInt32.ofNat b[i]!.toNat <<< 24) |||
  (UInt32.ofNat b[i + 1]!.toNat <<< 16) |||
  (UInt32.ofNat b[i + 2]!.toNat <<< 8) |||
  UInt32.ofNat b[i + 3]!.toNat

/-- SHA-256 padding: 0x80, zeros, 8-byte big-endian bit length. -/
def pad (msg : ByteArray) : ByteArray :=
  let bitLen : Nat := msg.size * 8
  let paddedLen : Nat := ((msg.size + 9 + 63) / 64) * 64
  let rec zeros (k : Nat) (acc : ByteArray) : ByteArray :=
    match k with
    | 0 => acc
    | k + 1 => zeros k (acc.push 0)
  let acc := zeros (paddedLen - msg.size - 9) (msg.push 0x80)
  let acc := acc.push (UInt8.ofNat (bitLen / 72057594037927936 % 256))   -- bits 56..63
  let acc := acc.push (UInt8.ofNat (bitLen / 281474976710656 % 256))     -- bits 48..55
  let acc := acc.push (UInt8.ofNat (bitLen / 1099511627776 % 256))       -- bits 40..47
  let acc := acc.push (UInt8.ofNat (bitLen / 4294967296 % 256))          -- bits 32..39
  let acc := acc.push (UInt8.ofNat (bitLen / 16777216 % 256))            -- bits 24..31
  let acc := acc.push (UInt8.ofNat (bitLen / 65536 % 256))
  let acc := acc.push (UInt8.ofNat (bitLen / 256 % 256))
  acc.push (UInt8.ofNat (bitLen % 256))

/-- Compress the 64-byte block at byte offset `off` of `padded` into the 8-word state. -/
def compressBlock (padded : ByteArray) (off : Nat) (h : Array UInt32) : Array UInt32 :=
  let w : Array UInt32 := Id.run do
    let mut w : Array UInt32 := Array.mkEmpty 64
    for i in [0:16] do
      w := w.push (be32 padded (off + i * 4))
    for i in [16:64] do
      let w15 := w[i - 15]!
      let w2 := w[i - 2]!
      let s0 := (rotr32 w15 7) ^^^ (rotr32 w15 18) ^^^ (w15 >>> 3)
      let s1 := (rotr32 w2 17) ^^^ (rotr32 w2 19) ^^^ (w2 >>> 10)
      w := w.push (w[i - 16]! + s0 + w[i - 7]! + s1)
    return w
  let rec step (fuel : Nat) (t : Nat) (a b c d e f g h' : UInt32) : Array UInt32 :=
    match fuel with
    | 0 => #[a + h[0]!, b + h[1]!, c + h[2]!, d + h[3]!, e + h[4]!, f + h[5]!, g + h[6]!, h' + h[7]!]
    | fuel + 1 =>
      let S1 := (rotr32 e 6) ^^^ (rotr32 e 11) ^^^ (rotr32 e 25)
      let ch := (e &&& f) ^^^ ((e ^^^ 0xFFFFFFFF) &&& g)
      let temp1 := h' + S1 + ch + K[t]! + w[t]!
      let S0 := (rotr32 a 2) ^^^ (rotr32 a 13) ^^^ (rotr32 a 22)
      let maj := (a &&& b) ^^^ (a &&& c) ^^^ (b &&& c)
      let temp2 := S0 + maj
      step fuel (t + 1) (temp1 + temp2) a b c (d + temp1) e f g
  step 64 0 h[0]! h[1]! h[2]! h[3]! h[4]! h[5]! h[6]! h[7]!

/-- SHA-256 over bytes. -/
def hash (msg : ByteArray) : ByteArray :=
  let padded := pad msg
  let rec go (fuel : Nat) (off : Nat) (acc : Array UInt32) : Array UInt32 :=
    match fuel with
    | 0 => acc
    | fuel + 1 =>
      if off ≥ padded.size then acc
      else go fuel (off + 64) (compressBlock padded off acc)
  let hs := go ((padded.size / 64) + 1) 0 H0
  Id.run do
    let mut o := ByteArray.empty
    for x in hs do
      o := o.push ((x >>> 24).toUInt8)
      o := o.push ((x >>> 16).toUInt8)
      o := o.push ((x >>> 8).toUInt8)
      o := o.push (x.toUInt8)
    return o

def toHex (b : ByteArray) : String :=
  let hexDigit (n : Nat) : Char :=
    if n < 10 then Char.ofNat ('0'.toNat + n) else Char.ofNat ('a'.toNat + (n - 10))
  String.join (b.toList.map (fun u =>
    let n := u.toNat
    String.ofList [hexDigit (n / 16), hexDigit (n % 16)]))

/-- SHA-256 over a UTF-8 string, as a lowercase hex digest. -/
def hexDigest (s : String) : String := toHex (hash (utf8Encode s))

/-! ## HMAC-SHA256 (block size 64) -/

private def xorByte (x y : UInt8) : UInt8 := UInt8.ofNat (x.toNat ^^^ y.toNat)

private def repeatByte (u : UInt8) (n : Nat) : ByteArray :=
  let rec go (k : Nat) (acc : ByteArray) : ByteArray :=
    match k with
    | 0 => acc
    | k + 1 => go k (acc.push u)
  go n ByteArray.empty

def hmac (key : ByteArray) (msg : ByteArray) : ByteArray :=
  let key := if key.size > 64 then hash key else key
  let keyPadded := key ++ repeatByte 0 (64 - key.size)
  let ipad := mapBytes (xorByte 0x36) keyPadded
  let opad := mapBytes (xorByte 0x5c) keyPadded
  hash (opad ++ hash (ipad ++ msg))

def hmacHex (key msg : String) : String := toHex (hmac (utf8Encode key) (utf8Encode msg))

/-! ## base64url (RFC 4648 §5, unpadded encoding; decode tolerates '=' padding) -/

def b64urlAlphabet : String :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

private def b64Char (n : Nat) : Char := b64urlAlphabet.toList.getD n 'A'

/-- Encode bytes as unpadded base64url. -/
def b64urlEncode (b : ByteArray) : String :=
  let n := b.size
  let enc3 (i : Nat) : String :=
    let v := (b[i]!.toNat <<< 16) ||| (b[i + 1]!.toNat <<< 8) ||| b[i + 2]!.toNat
    String.ofList [b64Char (v >>> 18), b64Char ((v >>> 12) % 64), b64Char ((v >>> 6) % 64), b64Char (v % 64)]
  let enc2 (i : Nat) : String :=
    let v := (b[i]!.toNat <<< 8) ||| b[i + 1]!.toNat
    String.ofList [b64Char (v >>> 10), b64Char ((v >>> 4) % 64), b64Char ((v % 16) * 4)]
  let enc1 (i : Nat) : String :=
    let v := b[i]!.toNat
    String.ofList [b64Char (v >>> 2), b64Char ((v % 4) * 16)]
  let rec go (fuel : Nat) (i : Nat) (acc : String) : String :=
    match fuel with
    | 0 => acc
    | fuel + 1 =>
      if n - i ≥ 3 then go fuel (i + 3) (acc ++ enc3 i)
      else if n - i = 2 then acc ++ enc2 i
      else if n - i = 1 then acc ++ enc1 i
      else acc
  go (n / 3 + 1) 0 ""

private def b64Val (c : Char) : Option Nat :=
  match c with
  | 'A' => some 0 | 'B' => some 1 | 'C' => some 2 | 'D' => some 3 | 'E' => some 4 | 'F' => some 5
  | 'G' => some 6 | 'H' => some 7 | 'I' => some 8 | 'J' => some 9 | 'K' => some 10 | 'L' => some 11
  | 'M' => some 12 | 'N' => some 13 | 'O' => some 14 | 'P' => some 15 | 'Q' => some 16 | 'R' => some 17
  | 'S' => some 18 | 'T' => some 19 | 'U' => some 20 | 'V' => some 21 | 'W' => some 22 | 'X' => some 23
  | 'Y' => some 24 | 'Z' => some 25 | 'a' => some 26 | 'b' => some 27 | 'c' => some 28 | 'd' => some 29
  | 'e' => some 30 | 'f' => some 31 | 'g' => some 32 | 'h' => some 33 | 'i' => some 34 | 'j' => some 35
  | 'k' => some 36 | 'l' => some 37 | 'm' => some 38 | 'n' => some 39 | 'o' => some 40 | 'p' => some 41
  | 'q' => some 42 | 'r' => some 43 | 's' => some 44 | 't' => some 45 | 'u' => some 46 | 'v' => some 47
  | 'w' => some 48 | 'x' => some 49 | 'y' => some 50 | 'z' => some 51 | '0' => some 52 | '1' => some 53
  | '2' => some 54 | '3' => some 55 | '4' => some 56 | '5' => some 57 | '6' => some 58 | '7' => some 59
  | '8' => some 60 | '9' => some 61 | '-' => some 62 | '_' => some 63
  | _ => none

/-- Decode base64url; accepts optional '=' padding, rejects everything else malformed. -/
def b64urlDecode (s : String) : Option ByteArray :=
  let cs := s.toList.takeWhile (fun c => c ≠ '=')
  let rec go (cs : List Char) (acc : ByteArray) : Option ByteArray :=
    match cs with
    | a :: b :: c :: d :: rest => do
      let va ← b64Val a
      let vb ← b64Val b
      let vc ← b64Val c
      let vd ← b64Val d
      let v := va * 262144 + vb * 4096 + vc * 64 + vd
      let acc := acc.push (UInt8.ofNat (v / 65536))
      let acc := acc.push (UInt8.ofNat (v / 256 % 256))
      go rest (acc.push (UInt8.ofNat (v % 256)))
    | a :: b :: c :: [] => do
      let va ← b64Val a
      let vb ← b64Val b
      let vc ← b64Val c
      let v := va * 1024 + vb * 16 + vc / 4
      some ((acc.push (UInt8.ofNat (v / 256))).push (UInt8.ofNat (v % 256)))
    | a :: b :: [] => do
      let va ← b64Val a
      let vb ← b64Val b
      some (acc.push (UInt8.ofNat (va * 4 + vb / 16)))
    | [] => some acc
    | _ => none                                            -- a single trailing char is invalid
  if cs.length % 4 = 1 then none else go cs ByteArray.empty

end Sha256
