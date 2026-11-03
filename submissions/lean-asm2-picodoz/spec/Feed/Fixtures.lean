/-
Feed.Fixtures — the 42-check suite analogues' data: embedded golden fixtures
(byte-exact copies of the challenge's test/golden/*.json) and the model DB / time /
config they run against.

The fixture DB is BUILT FROM the golden feed by our own JSON parser, so the golden
feed check is simultaneously: parser round-trip + serializer byte-fidelity + handler
ordering over real data.
-/

import Feed.Types
import Feed.Json
import Feed.Jwt
import Feed.Model

open Feed Json Sha256 Jwt Model

namespace Fixtures

/-- Byte-exact golden fixtures (from the challenge's test/golden/, embedded at compile time). -/
def goldenFeedTxt : String := include_str "../../tests/golden/feed.json"
def goldenPost1Txt : String := include_str "../../tests/golden/post-1.json"
def goldenPost250000Txt : String := include_str "../../tests/golden/post-250000.json"
def goldenPost500000Txt : String := include_str "../../tests/golden/post-500000.json"

/-- Json.obj → Post (exact key set of the wire format). -/
def postOfJson? (j : Json) : Option Post :=
  match j.getField? "id", j.getField? "body", j.getField? "created_at", j.getField? "author",
        j.getField? "like_count" with
  | some (.num id), some (.str body), some (.str createdAt), some (.str author), some (.num likeCount) =>
    some { id := id, body := body, createdAt := createdAt, author := author, likeCount := likeCount }
  | _, _, _, _, _ => none

def postsOfFeedJson? (j : Json) : Option (List Post) :=
  match j.getField? "posts" with
  | some (.arr items) =>
    let rec go (items : List Json) (acc : List Post) : Option (List Post) :=
      match items with
      | [] => some acc.reverse
      | i :: rest => match postOfJson? i with
        | some p => go rest (p :: acc)
        | none => none
    go items []
  | _ => none

/-- The 20 newest posts, parsed out of the golden feed bytes. -/
def goldenFeedPosts : List Post :=
  match Json.parse goldenFeedTxt >>= postsOfFeedJson? with
  | some ps => ps
  | none => []            -- SpecCheck asserts this never happens

def goldenPost1 : Post :=
  match Json.parse goldenPost1Txt >>= (·.getField? "post") >>= postOfJson? with
  | some p => p
  | none => { id := 0, body := "", createdAt := "", author := "", likeCount := 0 }

def goldenPost250000 : Post :=
  match Json.parse goldenPost250000Txt >>= (·.getField? "post") >>= postOfJson? with
  | some p => p
  | none => { id := 0, body := "", createdAt := "", author := "", likeCount := 0 }

/-- The fixture DB: the 20 golden feed posts (newest first) + posts 1 and 250000. -/
def fixtureDb : ModelDb where
  posts := goldenFeedPosts ++ [goldenPost1, goldenPost250000]
  nextPostId := 500001
  liked := []
  healthy := true
  healthError := ""

/-- Challenge secret (test.sh default). -/
def fixtureCfg : Config where
  jwtSecret := "twelve-dollar-challenge"

/-- Fixed "now": what the analogues sign tokens against and compare exp with. -/
def fixtureNow : Now where
  nowSec := 1767225600            -- 2026-01-01T00:00:00Z
  startSec := 1767225000          -- server started 600 s earlier
  insertStamp := "2026-01-01T00:00:00.123Z"

/-- A valid token for user 1 (golden_ember_1), mirroring test.sh's sign(). -/
def token : String :=
  Jwt.sign fixtureCfg.jwtSecret "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
    "{\"sub\":\"1\",\"username\":\"golden_ember_1\",\"iat\":1767225000,\"exp\":1767229200}"

/-- Expired token (exp an hour before now). -/
def expiredToken : String :=
  Jwt.sign fixtureCfg.jwtSecret "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
    "{\"sub\":\"1\",\"username\":\"golden_ember_1\",\"iat\":1767221000,\"exp\":1767222000}"

/-- Valid signature, sub not an integer. -/
def badSubToken : String :=
  Jwt.sign fixtureCfg.jwtSecret "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
    "{\"sub\":\"abc\",\"username\":\"golden_ember_1\",\"iat\":1767225000,\"exp\":1767229200}"

/-- Valid signature, no username claim. -/
def noNameToken : String :=
  Jwt.sign fixtureCfg.jwtSecret "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
    "{\"sub\":\"1\",\"iat\":1767225000,\"exp\":1767229200}"

/-- alg=none attack: header says none, payload from `token`, empty signature. -/
def noneAlgToken : String :=
  Sha256.b64urlEncode (utf8Encode "{\"alg\":\"none\",\"typ\":\"JWT\"}")
    ++ "." ++ (token.splitOn ".").getD 1 ""
    ++ "."

/-- Tampered signature: valid header/payload, garbage signature. -/
def badSigToken : String :=
  let parts := token.splitOn "."
  (parts.getD 0 "") ++ "." ++ (parts.getD 1 "")
    ++ ".c2lnbmF0dXJlLWlzLW5vdC12YWxpZC1hdC1hbGwtYXQtYWxsLTEyMzQ"

end Fixtures
