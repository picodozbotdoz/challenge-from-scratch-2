/-
Feed.Invariant — machine-checked properties of the executable spec.

Proved here (Lean kernel-checked):
1. `parseId_pos` / `parseId_class` — the `:id` classification: every `some n` has n ≥ 1,
   and parseId is total into {some n ≥ 1, none}.
2. `trim_idem` — trimming is idempotent.
3. `authCheck_missing` + `like_auth_before_id` + `create_auth_before_body` — on BOTH
   authenticated routes, a missing/foreign-scheme Authorization yields exactly the
   `missing bearer token` response REGARDLESS of the id segment or request body
   (auth is checked before id / body — the SPEC.md ordering rule).
4. JWT discipline:
   - `verify_none_of_structural_none` — structural failure classifies as `invalid`;
   - `badPayload_requires` — a payload error implies structural AND temporal checks
     passed (so alg/signature/exp failures are never misreported as payload errors);
   - `ok_requires_payload` — success implies payload checks passed;
   - `expired_invalid` — exp ≤ now (with a structural pass) ⇒ `invalid`.
   Concrete attack vectors (alg=none, tampered signature) are checked in SpecCheck
   against the staged pipeline.

Note: routing dispatch itself (path → handler) is exercised exhaustively by the 42
analogues in SpecCheck; the ORDERING properties above are what this module proves.
-/

import Feed.Types
import Feed.Json
import Feed.Jwt
import Feed.Contract
import Feed.Model

open Feed Json Sha256 Jwt Contract Model

namespace Invariant

/-! ## `:id` classification -/

theorem parseId_pos (s : String) (n : Int) (h : parseId s = some n) : n ≥ 1 := by
  simp only [parseId] at h
  split at h
  · exact absurd h (by simp)
  · split at h
    · exact absurd h (by simp)
    · split at h
      · simp only [Option.some.injEq] at h
        omega
      · exact absurd h (by simp)

theorem parseId_class (s : String) : (∃ n, n ≥ 1 ∧ parseId s = some n) ∨ parseId s = none := by
  by_cases hex : ∃ n, parseId s = some n
  · cases hex with
    | intro n hn => exact Or.inl ⟨n, parseId_pos s n hn, hn⟩
  · right
    cases hp : parseId s with
    | none => rfl
    | some n =>
      exact absurd ⟨n, hp⟩ hex

/-! ## Trim laws -/

private theorem dw_cons_of_false {α : Type} (p : α → Bool) (x : α) (l : List α)
    (h : p x = false) : List.dropWhile p (x :: l) = x :: l := by
  simp only [List.dropWhile, h]

/-- A nonempty `dropWhile` result starts with a non-satisfying element. -/
private theorem dw_head_ne {α : Type} (p : α → Bool) (l : List α)
    (h : List.dropWhile p l ≠ []) :
    ∃ x r, List.dropWhile p l = x :: r ∧ p x = false := by
  induction l with
  | nil => exact absurd rfl h
  | cons x xs ih =>
    by_cases hpx : p x = true
    · simp only [List.dropWhile, hpx] at h ⊢
      exact ih h
    · have hp' : (p x) = false := by simp [hpx]
      refine ⟨x, xs, ?_, hp'⟩
      simp only [List.dropWhile, hp']

private theorem DT_idem (l : List Char) :
    Feed.dropTrailing (Feed.dropTrailing l) = Feed.dropTrailing l := by
  induction l with
  | nil => rfl
  | cons c cs ih =>
    by_cases hc : Feed.isWs c = true
    · by_cases hnil : Feed.dropTrailing cs = []
      · simp [Feed.dropTrailing, hc, hnil]
      · simp [Feed.dropTrailing, hc, hnil, ih]
    · have hc' : Feed.isWs c = false := by simp [hc]
      simp [Feed.dropTrailing, hc', ih]

private theorem DT_cons_head (c : Char) (cs : List Char) (h : Feed.isWs c = false) :
    Feed.dropTrailing (c :: cs) = c :: Feed.dropTrailing cs := by
  simp [Feed.dropTrailing, h]

private theorem trimList_idem (cs : List Char) :
    Feed.trimList (Feed.trimList cs) = Feed.trimList cs := by
  unfold Feed.trimList
  by_cases hdw : List.dropWhile Feed.isWs cs = []
  · simp only [hdw, Feed.dropTrailing]
    rfl
  · obtain ⟨x, r, heq, hpx⟩ := dw_head_ne Feed.isWs cs hdw
    rw [heq, DT_cons_head x r hpx]
    simp only [dw_cons_of_false Feed.isWs x (Feed.dropTrailing r) hpx]
    rw [DT_cons_head x (Feed.dropTrailing r) hpx, DT_idem r]

theorem trim_idem (s : String) : trim (trim s) = trim s := by
  simp only [trim, String.toList_ofList, trimList_idem]

/-! ## Auth ordering (auth BEFORE id / body) -/

theorem authCheck_missing {cfg : Config} {req : Request} {t : Int}
    (h : bearerMissing req = true) : authCheck cfg req t = JwtResult.missingBearer := by
  have hf : bearerMissing req = true := h
  unfold bearerMissing at hf
  cases hr : req.authorization with
  | none => simp only [authCheck, hr]
  | some v =>
    rw [hr] at hf
    simp only [Bool.not_eq_true'] at hf
    simp [authCheck, hr, hf]

/-- POST /posts/:id/like without a usable bearer → `missing bearer token`, for ANY id. -/
theorem like_auth_before_id (cfg : Config) (req : Request) (db : ModelDb) (now : Now)
    (idSeg : String) (h : bearerMissing req = true) :
    (likePost cfg req db now idSeg).1 = missingBearerToken := by
  simp only [likePost, authCheck_missing h, ofJwtResult]

/-- POST /posts without a usable bearer → `missing bearer token`, for ANY body. -/
theorem create_auth_before_body (cfg : Config) (req : Request) (db : ModelDb) (now : Now)
    (h : bearerMissing req = true) :
    (createPost cfg req db now).1 = missingBearerToken := by
  simp only [createPost, authCheck_missing h, ofJwtResult]

/-! ## JWT alg / exp / signature discipline -/

theorem verify_none_of_structural_none (cfg : Config) (token : String) (t : Int)
    (h : verifyStructural cfg token = none) : verify cfg token t = JwtResult.invalid := by
  simp only [verify, h]

/-- A payload error implies structural (alg+signature) and temporal checks passed. -/
theorem badPayload_requires (cfg : Config) (token : String) (t : Int)
    (h : verify cfg token t = JwtResult.badPayload) :
    ∃ p : Json, verifyStructural cfg token = some p ∧ verifyTemporal t p = true := by
  simp only [verify] at h
  split at h
  · exact absurd h (by simp)
  · next p hs =>
    by_cases htemp : verifyTemporal t p = true
    · rw [if_pos htemp] at h
      cases hpay : verifyPayload p with
      | none => exact ⟨p, hs, htemp⟩
      | some up =>
        rw [hpay] at h
        exact absurd h (by simp)
    · rw [if_neg htemp] at h
      exact absurd h (by simp)

/-- Success implies payload checks passed (structural + temporal by construction). -/
theorem ok_requires_payload (cfg : Config) (token : String) (t : Int) (uid : Int) (name : String)
    (h : verify cfg token t = JwtResult.ok uid name) :
    ∃ p : Json, verifyStructural cfg token = some p ∧ verifyTemporal t p = true
      ∧ verifyPayload p = some (uid, name) := by
  simp only [verify] at h
  split at h
  · exact absurd h (by simp)
  · next p hs =>
    by_cases htemp : verifyTemporal t p = true
    · rw [if_pos htemp] at h
      cases hpay : verifyPayload p with
      | none =>
        rw [hpay] at h
        exact absurd h (by simp)
      | some up =>
        obtain ⟨u1, u2⟩ := up
        rw [hpay] at h
        simp only [JwtResult.ok.injEq, Prod.mk.injEq] at h
        refine ⟨p, hs, htemp, ?_⟩
        rw [hpay]
        simp only [Option.some.injEq, Prod.mk.injEq]
        exact ⟨h.1, h.2⟩
    · rw [if_neg htemp] at h
      exact absurd h (by simp)

/-- exp ≤ now on a structurally valid token ⇒ the whole verification is `invalid`. -/
theorem expired_invalid (cfg : Config) (token : String) (t : Int) (p : Json) (e : Int)
    (hs : verifyStructural cfg token = some p) (he : expOf p = some e) (hle : e ≤ t) :
    verify cfg token t = JwtResult.invalid := by
  have hnot : ¬(e > t) := by omega
  have htemp : verifyTemporal t p = false := by
    rw [verifyTemporal, he]
    show decide (e > t) = false
    rw [decide_eq_false_iff_not]
    exact hnot
  simp [verify, hs, htemp]

end Invariant
