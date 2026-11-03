/-
Feed.Model — the executable requirement: pure handlers
`Request → ModelDb → Now → Response × ModelDb`.

Routing (query stripped first; trailing-slash NOT identified; unknown path or wrong
method on a known path → 404):
  GET  /health
  GET  /feed
  GET  /posts/:id
  POST /posts              (auth before body)
  POST /posts/:id/like     (auth BEFORE id — SPEC.md pins this ordering)
-/

import Feed.Types
import Feed.Json
import Feed.Jwt
import Feed.Contract

open Feed Json Sha256 Jwt Contract

namespace Model

/-- Strip a query string: keep everything before the first '?'. -/
def stripQuery (p : String) : String :=
  match p.splitOn "?" with
  | first :: _ => first
  | [] => p

/-
Split a path into segments: "/posts/42/like" → ["posts","42","like"].
One leading '/' is stripped; every '/' after that separates segments, and EMPTY
segments are preserved — so "/posts/1/" → ["posts","1",""] (no route → 404) and
"/posts//like" → ["posts","","like"] (404). Trailing-slash variants are NOT
identified with the bare path.
-/
def segments (p : String) : List String :=
  let cs := (stripQuery p).toList
  let rec go (cs : List Char) (acc : List Char) : List String :=
    match cs with
    | [] => [String.ofList acc.reverse]
    | '/' :: rest => String.ofList acc.reverse :: go rest []
    | c :: rest => go rest (c :: acc)
  match cs with
  | '/' :: rest => go rest []
  | _ => []

/-! ## Handlers -/

def healthNow (db : ModelDb) (now : Now) : Response :=
  if db.healthy then Contract.health (Now.uptime now) none
  else Contract.health 0 (some db.healthError)

def getPostById (id : String) (db : ModelDb) : Response :=
  match parseId id with
  | none => invalidPostId
  | some n =>
    match db.posts.find? (fun p => p.id == n) with
    | some p => Contract.getPost p
    | none => postNotFound

/--
POST /posts — auth, then body JSON parse, then body validation, then insert.
The model insert assigns `nextPostId` / `now.insertStamp` like the SQL defaults.
-/
def createPost (cfg : Config) (req : Request) (db : ModelDb) (now : Now) : Response × ModelDb :=
  match authCheck cfg req now.nowSec with
  | .ok uid name =>
    match Json.parse req.body with
    | none => (malformedJsonBody, db)
    | some j =>
      match j.getField? "body" with
      | some (.str s) =>
        let t := trim s
        if t.isEmpty then (bodyRequired, db)
        else if t.length > 500 then (bodyTooLong, db)
        else
          let p : Post := { id := db.nextPostId, body := t, createdAt := now.insertStamp,
                            author := name, likeCount := 0 }
          let db' : ModelDb := { db with posts := p :: db.posts, nextPostId := db.nextPostId + 1 }
          (Contract.created p, db')
      | _ => (bodyRequired, db)
  | r => (Contract.ofJwtResult r, db)

/--
POST /posts/:id/like — AUTH FIRST, then id parse, then existence, then the insert.
First like → 201 `already_liked:false`; repeat → 200 `already_liked:true`.
-/
def likePost (cfg : Config) (req : Request) (db : ModelDb) (now : Now) (id : String) :
    Response × ModelDb :=
  match authCheck cfg req now.nowSec with
  | .ok uid _ =>
    match parseId id with
    | none => (invalidPostId, db)
    | some n =>
      match db.posts.find? (fun p => p.id == n) with
      | none => (postNotFound, db)
      | some _ =>
        if db.liked.any (fun kv => kv.1 == uid && kv.2 == n) then
          (Contract.likeResult n true, db)
        else
          -- record the pair and bump the post's like count
          let bump (q : Post) : Post := if q.id == n then { q with likeCount := q.likeCount + 1 } else q
          let db' : ModelDb := { db with
            posts := db.posts.map bump,
            liked := (uid, n) :: db.liked }
          (Contract.likeResult n false, db')
  | r => (Contract.ofJwtResult r, db)

/-- The single entry point the runtime calls per request. -/
def handle (cfg : Config) (req : Request) (db : ModelDb) (now : Now) : Response × ModelDb :=
  match req.method, segments req.path with
  | .GET, ["health"] => (healthNow db now, db)
  | .GET, ["feed"] => (getFeed db.posts, db)
  | .GET, ["posts", id] => (getPostById id db, db)
  | .POST, ["posts"] => createPost cfg req db now
  | .POST, ["posts", id, "like"] => likePost cfg req db now id
  | _, _ => (notFound, db)

end Model
