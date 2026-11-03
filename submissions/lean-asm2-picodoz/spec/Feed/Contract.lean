/-
Feed.Contract — the exact wire contract: every response body this API can emit,
byte for byte. This module is the single source of truth both the handlers and the
asm emitter mirror; SpecCheck checks the handler outputs against these constructors.

Error table (SPEC.md):
  404 not found / 400 invalid post id / 404 post not found /
  401 missing bearer token / 401 invalid or expired token / 401 invalid token payload /
  400 malformed JSON body / 400 body is required / 400 body must be at most 500 characters /
  500 internal server error
-/

import Feed.Types
import Feed.Json
import Feed.Jwt

open Feed Json

namespace Contract

/-- Every error body is exactly `{"error":"<message>"}`. -/
def errorBody (msg : String) : String := "{\"error\":\"" ++ msg ++ "\"}"

def error (status : Nat) (msg : String) : Response := ⟨status, errorBody msg⟩

def notFound : Response := error 404 "not found"
def invalidPostId : Response := error 400 "invalid post id"
def postNotFound : Response := error 404 "post not found"
def missingBearerToken : Response := error 401 "missing bearer token"
def invalidOrExpiredToken : Response := error 401 "invalid or expired token"
def invalidTokenPayload : Response := error 401 "invalid token payload"
def malformedJsonBody : Response := error 400 "malformed JSON body"
def bodyRequired : Response := error 400 "body is required"
def bodyTooLong : Response := error 400 "body must be at most 500 characters"
def internalError : Response := error 500 "internal server error"

/-- `authCheck` result → response (for authenticated routes). -/
def ofJwtResult : Jwt.JwtResult → Response
  | .missingBearer => missingBearerToken
  | .invalid => invalidOrExpiredToken
  | .badPayload => invalidTokenPayload
  | .ok _ _ => internalError   -- never used: ok is matched by callers

/-! ## Success bodies (exact key order) -/

/-- Post object: `{"id":…,"body":…,"created_at":…,"author":…,"like_count":…}`. -/
def postJson (p : Post) : String :=
  Json.serialize (.obj [
    ("id", .num p.id),
    ("body", .str p.body),
    ("created_at", .str p.createdAt),
    ("author", .str p.author),
    ("like_count", .num p.likeCount)
  ])

def postBody (p : Post) : String := "{\"post\":" ++ postJson p ++ "}"

def getPost (p : Post) : Response := ⟨200, postBody p⟩

/-- `{"posts":[<post>×20]}` — order as given (newest first). -/
def feedBody (ps : List Post) : String :=
  "{\"posts\":[" ++ String.join ((ps.take 20).map postJson |>.intersperse ",") ++ "]}"

def getFeed (ps : List Post) : Response := ⟨200, feedBody ps⟩

/-- `{"liked":true,"already_liked":<bool>,"post_id":<int>}`. -/
def likeBody (postId : Int) (already : Bool) : String :=
  "{\"liked\":true,\"already_liked\":" ++ (if already then "true" else "false")
    ++ ",\"post_id\":" ++ toString postId ++ "}"

def likeResult (postId : Int) (already : Bool) : Response :=
  ⟨if already then 200 else 201, likeBody postId already⟩

/-- `{"status":"ok","db":"ok","uptime_s":<int>}`. -/
def healthOk (uptime : Int) : String :=
  "{\"status\":\"ok\",\"db\":\"ok\",\"uptime_s\":" ++ toString uptime ++ "}"

/-- `{"status":"degraded","db":"unreachable","error":<escaped string>}`. -/
def healthDegraded (err : String) : String :=
  "{\"status\":\"degraded\",\"db\":\"unreachable\",\"error\":" ++ Json.serialize (.str err) ++ "}"

def health (uptime : Int) (dbErr : Option String) : Response :=
  match dbErr with
  | none => ⟨200, healthOk uptime⟩
  | some e => ⟨503, healthDegraded e⟩

/-- `{"post":<freshly created post>}` with 201. -/
def created (p : Post) : Response := ⟨201, postBody p⟩

end Contract
