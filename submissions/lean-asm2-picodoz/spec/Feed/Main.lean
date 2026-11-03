/-
Feed.Main — SpecCheck: the executable acceptance oracle of the requirement spec.

Runs the 42 analogues of the challenge's test/test.sh against the pure handlers
(`Model.handle`) over the golden-fixture model DB, plus the SHA-256/HMAC/base64url
published test vectors. Every analogue is a decidable boolean check on exact
response values; output format mirrors test.sh ("  ok/FAIL …", "passed=N failed=M"),
exit code 0 iff all 42 pass.

The Invariant lemmas (Feed.Invariant) are compiled in — this exe is the runtime
(executable-spec) half of the verification story.
-/

import Feed.Types
import Feed.Json
import Feed.Jwt
import Feed.Contract
import Feed.Model
import Feed.Invariant
import Feed.Fixtures

open Feed Json Sha256 Jwt Contract Model Fixtures

/-! ## helpers -/

-- one request through the pure handler
def run (req : Request) (db : ModelDb) : Response × ModelDb :=
  handle fixtureCfg req db fixtureNow

def runKeep (req : Request) (db : ModelDb) : Response := (run req db).1

def get (path : String) : Response := runKeep ⟨.GET, path, none, ""⟩ fixtureDb

def post (path : String) (auth : Option String) (body : String) : Response :=
  runKeep ⟨.POST, path, auth, body⟩ fixtureDb

def bearer : String := "Bearer " ++ token
def bearerExpired : String := "Bearer " ++ expiredToken
def bearerBadSub : String := "Bearer " ++ badSubToken
def bearerNoName : String := "Bearer " ++ noNameToken
def bearerNoneAlg : String := "Bearer " ++ noneAlgToken
def bearerBadSig : String := "Bearer " ++ badSigToken

def resp (status : Nat) (body : String) : Response := ⟨status, body⟩

-- jq '.post.body' analogue: parse a 200/201 post body and extract .post.body
def postBodyOf (r : Response) : Option String :=
  Json.parse r.body >>= (·.getField? "post") >>= (·.getField? "body") >>= (·.asStr?)

-- jq '.post.id' analogue
def postIdOf (r : Response) : Option Int :=
  Json.parse r.body >>= (·.getField? "post") >>= (·.getField? "id") >>= (·.asInt?)

-- jq '.post.like_count'
def postLikesOf (r : Response) : Option Int :=
  Json.parse r.body >>= (·.getField? "post") >>= (·.getField? "like_count") >>= (·.asInt?)

-- jq '.posts | length'
def feedLenOf (r : Response) : Option Nat :=
  Json.parse r.body >>= (·.getField? "posts") >>= (·.asArrLen?)

-- jq '.posts[0]' object equality analogue (compare the Json trees)
def feedTopEntry (r : Response) : Option Json :=
  Json.parse r.body >>= (·.getField? "posts") >>= (·.asHead?)

-- jq '.posts[0].id'
def feedTopIdOf (r : Response) : Option Int :=
  Json.parse r.body >>= (·.getField? "posts") >>= asHead? >>= (·.getField? "id") >>= asInt?

-- created_at format check: YYYY-MM-DDTHH:MM:SS.mmmZ (digits + fixed separators)
def digit (c : Char) : Bool := c.isDigit
def stampOk (s : String) : Bool :=
  let cs := s.toList
  cs.length == 24
    && digit cs[0]! && digit cs[1]! && digit cs[2]! && digit cs[3]!
    && cs[4]! == '-'
    && digit cs[5]! && digit cs[6]! && cs[7]! == '-'
    && digit cs[8]! && digit cs[9]! && cs[10]! == 'T'
    && digit cs[11]! && digit cs[12]! && cs[13]! == ':'
    && digit cs[14]! && digit cs[15]! && cs[16]! == ':'
    && digit cs[17]! && digit cs[18]! && cs[19]! == '.'
    && digit cs[20]! && digit cs[21]! && digit cs[22]! && cs[23]! == 'Z'

/-! ## the 42 analogues -/

def checks : List (String × Bool) :=
  let db := fixtureDb
  -- the sequential state for the create/like/read-back block
  let r29 := run ⟨.POST, "/posts", some bearer,
    "{\"body\":\"  test: <b>&amp;</b> \\\"quoted\\\" / café ✓  \"}"⟩ db          -- trimmed by spec
  let r30 := run ⟨.POST, "/posts", some bearer, "{\"body\":\"  " ++ String.join (List.replicate 500 "b") ++ " \"}"⟩ r29.2
  let newId := postIdOf r30.1
  let created := (Json.parse r30.1.body >>= (·.getField? "post") >>= (·.getField? "created_at") >>= (·.asStr?)).getD ""
  let r34 := run ⟨.POST, "/posts/" ++ toString (newId.getD 0) ++ "/like", some bearer, ""⟩ r30.2
  let r35 := run ⟨.POST, "/posts/" ++ toString (newId.getD 0) ++ "/like", some bearer, ""⟩ r34.2
  let r38 := run ⟨.GET, "/posts/" ++ toString (newId.getD 0), none, ""⟩ r35.2
  let r39a := run ⟨.POST, "/posts/1/like", some bearer, ""⟩ r38.2
  let r39b := run ⟨.GET, "/posts/1", none, ""⟩ r39a.2
  let r40 := run ⟨.GET, "/feed", none, ""⟩ r39b.2
  let b500 := String.join (List.replicate 500 "b")
  let newIdTxt := toString (newId.getD 0)
  [
    ("GET /feed == golden", get "/feed" == resp 200 goldenFeedTxt),
    ("GET /feed content-type (body parses as JSON)", (Json.parse (get "/feed").body).isSome),
    ("GET /posts/1 == golden", get "/posts/1" == resp 200 goldenPost1Txt),
    ("GET /posts/250000 == golden", get "/posts/250000" == resp 200 goldenPost250000Txt),
    ("GET /posts/500000 == golden", get "/posts/500000" == resp 200 goldenPost500000Txt),
    ("GET /posts/:id content-type (body parses as JSON)", (Json.parse (get "/posts/1").body).isSome),
    ("GET /health -> 200 {status,db,uptime_s}",
      get "/health" == resp 200 "{\"status\":\"ok\",\"db\":\"ok\",\"uptime_s\":600}"),
    ("GET /nope", get "/nope" == resp 404 "{\"error\":\"not found\"}"),
    ("GET /posts/0", get "/posts/0" == resp 400 "{\"error\":\"invalid post id\"}"),
    ("GET /posts/-1", get "/posts/-1" == resp 400 "{\"error\":\"invalid post id\"}"),
    ("GET /posts/abc", get "/posts/abc" == resp 400 "{\"error\":\"invalid post id\"}"),
    ("GET /posts/1.5", get "/posts/1.5" == resp 400 "{\"error\":\"invalid post id\"}"),
    ("GET /posts/999999999", get "/posts/999999999" == resp 404 "{\"error\":\"post not found\"}"),
    ("POST /posts, no token", post "/posts" none "{\"body\":\"x\"}"
      == resp 401 "{\"error\":\"missing bearer token\"}"),
    ("POST /posts, Basic auth", post "/posts" (some "Basic abc") "{\"body\":\"x\"}"
      == resp 401 "{\"error\":\"missing bearer token\"}"),
    ("POST /posts, garbage token", post "/posts" (some "Bearer abc") "{\"body\":\"x\"}"
      == resp 401 "{\"error\":\"invalid or expired token\"}"),
    ("POST /posts, bad signature", post "/posts" (some bearerBadSig) "{\"body\":\"x\"}"
      == resp 401 "{\"error\":\"invalid or expired token\"}"),
    ("POST /posts, alg=none", post "/posts" (some bearerNoneAlg) "{\"body\":\"x\"}"
      == resp 401 "{\"error\":\"invalid or expired token\"}"),
    ("POST /posts, expired token", post "/posts" (some bearerExpired) "{\"body\":\"x\"}"
      == resp 401 "{\"error\":\"invalid or expired token\"}"),
    ("POST /posts, sub not an integer", post "/posts" (some bearerBadSub) "{\"body\":\"x\"}"
      == resp 401 "{\"error\":\"invalid token payload\"}"),
    ("POST /posts, no username", post "/posts" (some bearerNoName) "{\"body\":\"x\"}"
      == resp 401 "{\"error\":\"invalid token payload\"}"),
    ("POST /posts/abc/like, no token (auth before id)",
      post "/posts/abc/like" none "" == resp 401 "{\"error\":\"missing bearer token\"}"),
    ("empty body", post "/posts" (some bearer) "{\"body\":\"\"}"
      == resp 400 "{\"error\":\"body is required\"}"),
    ("whitespace body", post "/posts" (some bearer) "{\"body\":\"   \"}"
      == resp 400 "{\"error\":\"body is required\"}"),
    ("numeric body", post "/posts" (some bearer) "{\"body\":123}"
      == resp 400 "{\"error\":\"body is required\"}"),
    ("missing body", post "/posts" (some bearer) "{}"
      == resp 400 "{\"error\":\"body is required\"}"),
    ("malformed JSON", post "/posts" (some bearer) "{bad json"
      == resp 400 "{\"error\":\"malformed JSON body\"}"),
    ("501-char body", post "/posts" (some bearer) ("{\"body\":\"" ++ String.join (List.replicate 501 "a") ++ "\"}")
      == resp 400 "{\"error\":\"body must be at most 500 characters\"}"),
    ("special characters round-trip (trimmed) -> 201",
      r29.1.status == 201
        && postBodyOf r29.1 == some "test: <b>&amp;</b> \"quoted\" / café ✓"),
    ("create 500-char post",
      r30.1 == resp 201 ("{\"post\":{\"id\":" ++ newIdTxt ++ ",\"body\":\"" ++ b500
        ++ "\",\"created_at\":\"" ++ created ++ "\",\"author\":\"golden_ember_1\",\"like_count\":0}}")),
    ("POST /posts content-type (body parses as JSON)", (Json.parse r30.1.body).isSome),
    ("created_at format", stampOk created),
    ("created_at is now (fixture stamp, drift 0)", created == "2026-01-01T00:00:00.123Z"),
    ("like (first)",
      r34.1 == resp 201 ("{\"liked\":true,\"already_liked\":false,\"post_id\":" ++ newIdTxt ++ "}")),
    ("like (repeat)",
      r35.1 == resp 200 ("{\"liked\":true,\"already_liked\":true,\"post_id\":" ++ newIdTxt ++ "}")),
    ("like missing post", post "/posts/999999999/like" (some bearer) ""
      == resp 404 "{\"error\":\"post not found\"}"),
    ("like bad id (with token)", post "/posts/abc/like" (some bearer) ""
      == resp 400 "{\"error\":\"invalid post id\"}"),
    ("read back, like_count 1",
      r38.1 == resp 200 ("{\"post\":{\"id\":" ++ newIdTxt ++ ",\"body\":\"" ++ b500
        ++ "\",\"created_at\":\"" ++ created ++ "\",\"author\":\"golden_ember_1\",\"like_count\":1}}")),
    ("seeded post like_count counted at once (11 -> 12)", postLikesOf r39b.1 == some 12),
    ("feed has 20 posts", feedLenOf r40.1 == some 20),
    ("new post is at the top of the feed", feedTopIdOf r40.1 == newId),
    ("feed entry matches the post",
      feedTopEntry r40.1 == Json.parse ("{\"id\":" ++ newIdTxt ++ ",\"body\":\"" ++ b500
        ++ "\",\"created_at\":\"" ++ created ++ "\",\"author\":\"golden_ember_1\",\"like_count\":1}"))
  ]

def cryptoChecks : List (String × Bool) :=
  [
    ("SHA-256(\"\") vector", Sha256.hexDigest "" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("SHA-256(\"abc\") vector", Sha256.hexDigest "abc" == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    ("HMAC-SHA256 vector",
      Sha256.hmacHex "key" "The quick brown fox jumps over the lazy dog"
        == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"),
    ("b64url header vector",
      Sha256.b64urlEncode (utf8Encode "{\"alg\":\"HS256\",\"typ\":\"JWT\"}")
        == "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")
  ]

def main : IO UInt32 := do
  IO.println "SpecCheck: executable requirement spec (analogues of test/test.sh)"
  let mut pass := 0
  let mut fail := 0
  let mut firstFail : Option String := none
  for (name, ok) in cryptoChecks ++ checks do
    if ok then
      IO.println s!"  ok   {name}"
      pass := pass + 1
    else
      IO.println s!"  FAIL {name}"
      if firstFail.isNone then firstFail := some name
      fail := fail + 1
  IO.println s!"crypto vectors: {cryptoChecks.length} (checked first)"
  IO.println s!"suite analogues: {checks.length}"
  IO.println s!"passed={pass} failed={fail}"
  if fail > 0 then
    IO.println s!"first failure: {firstFail.getD "?"}"
    return 1
  return 0
