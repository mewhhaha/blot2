# Squid vNext Compiler Architecture & Pruning Roadmap

21 November 2026 — grounded in the actual `compiler-goose/src/` tree
(**70,962 LOC across 221 `.goose` files**) and targeting
[docs/language/spec.md](../language/spec.md).

## 1. Where the 71k Lines Actually Go Today

| Directory | Files | Current LOC | Primary Bloat / Complexity Driver | Target LOC |
| --- | ---: | ---: | --- | ---: |
| `check/` | 76 | 26,673 | Retired subsystems (~10.3k LOC) + HM/row solver + escaping-closure & `lent` checks | ~7,500–9,000 |
| `reuse/` | 59 | 18,159 | `dependency_payload.goose` (7,957 LOC) serializing all dead subsystems + principal type graphs | ~4,000–5,000 |
| `direct/` | 17 | 10,123 | Already lean! Remove `List`/`@cursor`/requests/`lent`/escaping envs; add `fork`, `*T`, `#[n; T]` | ~7,500–9,000 |
| `support/` | 22 | 7,847 | Auto-generated JSON/structural adapters (4,402 LOC) mirroring dead AST/Core/reuse structs | ~3,500–4,500 |
| `parse/` | 8 | 2,815 | Custom operator fixities (`source_operators.goose`, 511 LOC) + retired syntax forms | ~1,800–2,000 |
| `eval/` | 17 | 2,411 | Almost entirely associated-contract equation & evidence import machinery | ~300–500 |
| `backend/` | 9 | 1,368 | Native assets, SIMD intrinsics, loop targets (mostly keep) | ~1,100 |
| `driver/` | 4 | 583 | Includes `cli_migrate_stores.goose` (203 LOC) | ~350 |
| top-level + `runtime/` | 9 | 983 | `work_counters.goose` (54k bytes!), policy, entry | ~500 |
| **Total** | **221** | **70,962** | | **~26,000–31,000** |

**Key takeaway:** Over **55–60% of the compiler** is dead or superseded weight
from pre-vNext features (packages, proofs, usage contracts, scoped capability
lifetimes, typed staging, row variables, associated equations, escaping closure
graphs, and the massive serialization layer required to cache all of them).
Cutting this first is the highest-leverage path to **50k–1M LOC/s** and
**<100ms retained edits**.

---

## 2. Phase 1 — The Big Prune (~35–40k LOC Deleted)

Delete retired subsystems in coherent, test-gated batches and regenerate
`support/*_adapters.goose` after each batch:

### Batch 1A: Zero-Use Academic Subsystems in `check/` (~8.3k LOC)
Remove completely (zero app usage in Ink/Gdev):
- **Packages (`forall`/`exists`/`pack`/`unpack`, ~2,641 LOC):**
  `package_core.goose`, `package_contracts.goose`, `package_portable.goose`,
  `package_row_facts.goose`, `package_owner_frames.goose`,
  `package_evidence.goose`, `rank_equal.goose`, `rank_walk.goose`,
  `rank_portable.goose`, `quantifier_goals.goose`.
- **Scoped capability lifetimes (`@effect.scope`, `{state.get}`, ~2,553 LOC):**
  `capability_lifetimes.goose`, `capability_flow.goose`,
  `capability_contracts.goose`, `capability_contract_core.goose`,
  `capability_contract_source.goose`, `capability_invocations.goose`,
  `lifetime_report_pool.goose`.
- **Numeric proofs (`@proof.*`, ~1,165 LOC):**
  `numeric_proof_core.goose`, `numeric_proof_terms.goose`,
  `numeric_proof_contracts.goose`, `numeric_proof_headers.goose`,
  `numeric_proof_bodies.goose`, `numeric_proof_names.goose`.
- **Usage contracts (`@usage.*`, ~800 LOC):**
  `usage_check.goose`, `usage_core.goose`.
- **Typed staging (`@code.*`, ~683 LOC):**
  `staging_core.goose`, `typed_staging.goose`, `staging_type_match.goose`,
  `staging_capture_rights.goose`, `typed_staging_names.goose`.
- **Language tasks (~432 LOC):**
  `task_types.goose`, `task_core.goose`, `task_regions.goose`.

### Batch 1B: Legacy Dispatch, Equations & `eval/` (~4.1k LOC)
Replace old string-named dispatch, contracts/`impl`, and equation proofs with
nominal trait records (`const Type.Trait`) and namespace lookup:
- Delete in `check/`: `dictionary_contracts.goose`, `associated_admission.goose`,
  `scheme_equations.goose`, `scheme_projection.goose`, `generative_core.goose`,
  `generative_relocation.goose`, `generative_schemes.goose`,
  `cleanup_contracts.goose`, `frozen_core_bounds.goose`,
  `frozen_core_scopes.goose`, `frozen_core_graph.goose`,
  `frozen_core_validation.goose`.
- Delete almost all of `eval/` (~2,100 LOC): `type_evidence.goose`,
  `implementation_evidence.goose`, `body_recipe.goose`,
  `closed_evidence_import.goose`, `implementation_admission.goose`,
  `implementation_rows.goose`, `semantic_evidence_import.goose`,
  `given_equations.goose`, `implementation_patterns.goose`,
  `selected_implementation_admission.goose`, `evidence_projection.goose`.

### Batch 1C: Parser, Legacy Storage & Transitional Syntax (~2.5k LOC)
- `parse/source_operators.goose` (511 LOC): replace with fixed operator table.
- Remove from `parse/` & `check/`: `do (monad ...)`, `@requests`/`yield`/
  `complete`, `List` / `@cursor` / `std/list` / `std/iter`, `@record.merge`,
  `=` store statement, `lent`, `=> return do:` with `break value`, and
  `driver/cli_migrate_stores.goose` (203 LOC).
- Retire the legacy counted-storage backend (completing task 120) so `direct/`
  is the sole backend.

### Batch 1D: Collapse `reuse/` Serialization & Regenerate Adapters (~12–15k LOC)
- Strip all removed Core/scheme/evidence tables out of
  `reuse/dependency_payload.goose` (currently 7,957 LOC -> target <2,000 LOC),
  `dependency_format_codecs.goose`, `dependency_format_owners.goose`, and
  `principal_type_graph.goose`.
- Regenerate `support/structural_adapters.goose` and `support/json_adapters.goose`
  (automatic multi-thousand-line drop).

---

## 3. Phase 2 — vNext Frontend, Type Checker & Linearity (`parse/` + `check/`)

With the dead weight gone, build the small, fast vNext semantic pipeline:

1. **Parse-only module interfaces (`parse/` + `reuse/`):**
   - Because every top-level `func`, `const`, `let`, and `type` writes its full
     signature, a module's public interface is extracted immediately after
     parsing—**zero cross-module HM inference**, unlocking maximum parallelism
     across modules.
   - Add syntax for `#[T]`, `#[+T]`, `#[~T]`, `#[n; T]`, `*T`, `*(A -> B)`,
     `fork x:`, `with Effect = { ... }:`, `return use`, `#for` / `#if` over
     `#fields` / `#variants`, and `val.(field)`.
2. **Closed effect sets (delete row unification in `check/effects.goose`):**
   - Represent effects as a compact sorted set / bitset of concrete `EffectId`s.
   - Remove row variables (`| e`), row-tail unification, and open-row cloning.
   - Downward 2A callbacks propagate their concrete effects directly when
     templated; `with Effect = { ... }:` subtracts `Effect` and adds any outer
     effects performed by the handler body.
3. **2A/2B callable checking:**
   - Classify every callable expression as:
     - **Capture-free** -> assignable to `A -> B` (4B fn ptr) or templated.
     - **Capturing / partial app (2A)** -> downward-only (templated at call
       site); error if stored in data or returned without `freeze`.
     - **Frozen closure `*(A -> B)` (2B)** -> created by `freeze (...)`; verify
       every captured binding is inline or `*T` (reject borrowed/linear captures).
4. **Local linearity, `#[n; T]` lengths & `fork` (`check/uniqueness.goose`):**
   - Shrink `uniqueness.goose` (currently 2,962 LOC) by removing `lent`, `=`,
     and escaping-closure capture graphs.
   - Add **disjoint path linearity** on record fields (`world.pos` vs
     `world.vel`), **typestate shadowing** (`seal`, `freeze`), and **scoped
     `with` handler exclusive ownership** of shadowed outer locals.
   - Add **`#[n; T]` length-variable unification** (equal-length proof across
     fields and parameters; lockstep `n -> n + 1` check on record construction)
     and index-validity tracking (`#[T]` / `#[+T]` preserve checked indices;
     `#[~T]` invalidates indices after shrink).
   - Add **`fork x:` checking** (verify `x` is linear on entry, does not escape
     the `fork` return value, and no `Foreign` effect runs inside `fork`).
5. **Typed `#for` / `#if` unrolling:**
   - Lower `#for field in #fields t:` and `#variants t` during monomorphization
     for each concrete `T`, resolving `val.(field)` and `@[...]` tag queries
     directly into typed Core nodes—zero AST macros or `#quote` runtime.

---

## 4. Phase 3 — Direct Wasm Backend (`direct/`)

`direct/` is already lean (~10k LOC) and maps cleanly onto vNext:

1. **2A Templated Callables (`direct/function_calls.goose`):**
   - Specialize/inline downward partial applications and capturing lambdas into
     direct Wasm loops—zero closure heap allocations, zero `call_indirect`.
2. **2B Frozen Closures & `*T` Runtime (`direct/runtime.goose`, `direct/function_storage.goose`):**
   - `A -> B` emits a single `i32` Wasm table index.
   - `*(A -> B)` emits a 2-word `(fn_idx: i32, env_ptr: i32)` fat pointer using
     the same `*T` immutable allocator as `*#[T]`.
   - Linear `#[T]` / `#[+T]` / `#[~T]` pay **0% refcounting**; only `*T`
     participates in shared lifetime tracking (refcount-on-`*T`-only or region).
3. **Speculative `fork x:` Undo Journal (`direct/function_control.goose`):**
   - Maintain a compact scratch undo stack of `(addr: i32, old_word: i32)` pairs
     plus saved array lengths for `#[+T]` / `#[~T]`.
   - Inside `fork`, array stores emit a 2-instruction log push before writing in
     place. On `fork` exit, a tight reverse loop restores overwritten words and
     rewinds array lengths / scratch marks in `O(edits)`.
4. **Bounds-Check Elimination & FBIP Reuse (`direct/function_data.goose`):**
   - Emit zero bounds checks for `a[i]` / `b[i]` when `i` is bounded by `n` and
     both arrays share `#[n; T]` (or for checked indices on `#[T]` / `#[+T]`).
   - On `:=` of a linear sum-type value whose RHS constructs a same-size
     variant, overwrite payload words in place without reallocating.
5. **Scoped `with` Handlers (`direct/function_effects.goose`):**
   - Lower inline `with Effect = { ... }:` to stack-framed handler slots
     pointing directly at the enclosing function's shadowed locals—zero heap
     allocation.

---

## 5. Phase 4 — Hitting 50k–1M LOC/s and <100ms Retained Edits

Why the pruned architecture hits the compile-speed goals naturally:

1. **Parse-only module boundaries:** Editing a function body in module `M`
   re-parses and re-checks **only `M`** (no downstream re-check unless `M`'s
   written public signature changed).
2. **Tiny interface packets:** Shrinking `reuse/dependency_payload.goose` from
   7,957 LOC by ~75% eliminates the 67+ MB worker reply serialization bottleneck
   recorded in [CONTINUE.md](../../CONTINUE.md).
3. **Per-body Wasm replay:** Build on the existing retained-backend one-body
   replay (already measured at **12.7 ms** for a Gdev simulation edit!) once
   module interfaces and closed call/effect keys are small and stable.
4. **No global constraint/row/lifetime solver:** Checking becomes a single
   predictable linear pass per function body, scaling linearly with LOC.

---

## 6. Recommended Execution Order

Keep tests and `Gdev` / `Ink` green at clear checkpoints rather than breaking
the world all at once:

1. **Checkpoint 1 (Zero-risk prune):** Execute **Batch 1A** (delete the 6
   zero-use academic subsystems in `check/`), regenerate `support/` adapters,
   verify `deno task test:compiler` + `Gdev` frame pass. Expect immediate
   compile-time & binary-size drop.
2. **Checkpoint 2 (Backend & legacy cleanup):** Retire counted backend (task
   120), delete `List`/`@cursor`/`@requests`/`monad`/custom fixities, and finish
   migrating remaining Gdev `=` sites so `=` and `lent` can be deleted.
3. **Checkpoint 3 (Traits, closed effects & 2A/2B callables):** Switch to
   nominal trait records (deleting `eval/` & Batch 1B), drop `! {| e}` row
   variables, enforce 2A downward templating + `A -> B` / `*(A -> B)`, and
   enable scoped `with` shadowing handlers.
4. **Checkpoint 4 (vNext symbols & superpowers):** Land `#[T]` / `#[+T]` /
   `#[~T]` / `#[n; T]`, `*T` (`freeze` / `seal`), `fork x:` undo journal, and
   typed `#for` / `#if` over `#fields` / `#variants` (then delete the 202
   hand-written codecs in `Ink` & `Gdev`!).
5. **Checkpoint 5 (Throughput gate):** Collapse `reuse/dependency_payload.goose`
   to the slim vNext IR, wire per-body Wasm replay into the production session,
   and benchmark cold builds + retained edits against the **<1s / <100ms / 1–2 MB**
   targets.
