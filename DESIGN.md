# Blot Design Direction

Blot is a pure, value-semantic, data-oriented language that compiles directly to
WebAssembly through a single handwritten compiler in Goose
([compiler-goose/](compiler-goose/README.md)). Deno hosts the CLI, project
client, formatter, and Wasm runtime adapter.

The authoritative target language is [docs/language/spec.md](docs/language/spec.md).
[docs/language/guide.md](docs/language/guide.md) documents what the current
compiler executes during migration, [CONTINUE.md](CONTINUE.md) records the
latest qualified runtime checkpoints, and
[docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) tracks the
compiler pruning and vNext implementation plan.

## Core Philosophy

1. **Pure shadowing (`let` / `:=` + `self`) + static linearity.** Every value is
   logically immutable. `let` always binds new names; `:=` evolves existing
   bindings, disjoint record paths, and loop/branch carries while reusing linear
   memory in place—including zero-copy `freeze` transitions and same-shape
   sum-type reuse (FBIP).
2. **Intrinsics are symbols; user types are names.**
   - Arrays use two unified symbols: `#[T]` (dynamic contiguous `Array T`, with
     `push`/`pop`/`truncate`/`reserve`/`extend` gated by unique `own` ownership)
     and `#[n; T]` (fixed/linked lengths across fields and parameters for
     zero-cost bounds-check elimination). Borrowed read-only `#[T]` accepts
     `#[T]`, `#[n; T]`, and `*#[T]`. (`%[T]` is reserved for future packed
     sequential arrays, and `~[T]` for a future list-like sequence structure.)
   - Frozen/shared values use `*T` (`O(1)` `freeze`, freely aliasable; explicit
     `copy` to obtain a linear editable clone; zero refcount overhead on linear
     code).
3. **No borrow-checker lifetimes, no hidden `O(n)` copies.**
   Read borrows are lexical. Ownership transfers explicitly with `own`. When
   timelines diverge, code explicitly picks `copy` (eager `O(n)`), `freeze`
   (`O(1)` immutable `*T`), or `fork x:` (`O(edits)` inner lexical shadowing via
   scratch undo log).
4. **Curried `a -> b -> c` with 2A/2B callables.**
   Saturated calls emit direct Wasm calls. Downward partial applications and
   capturing lambdas are templated at zero cost and cannot escape. Storable
   `A -> B` values are 4-byte capture-free function pointers; storable capturing
   closures use `*(A -> B)` via `freeze` and capture only inline or `*T` values.
5. **Simple, visible effects and zero-macro metaprogramming.**
   - `use x <- call` / `use call` / `return use call` keep pure regions visually
     distinct and reorderable. Templated downward callbacks eliminate open
     effect-row variables (`! {| e}`). Composable `handler` bindings (installed
     via `.handle ... .run`, `@handle`, and `layer`) may capture locals, forward
     `Foreign`, and linearly shadow outer locals—replacing built-in `State`.
   - Traits are compile-time nominal records (`type X is trait`, `const T.Trait`,
     no `impl`, no runtime dictionaries).
   - `#run expr` evaluates pure compile-time values and declared build inputs;
     body-only typed `#for` / `#if` over `#fields t` and `#variants t` replaces
     untyped `#quote` and hand-written codecs while keeping module interfaces
     100% parseable.

## Performance & Compiler Targets

Compilation and edit-to-running-game latency are primary product requirements:

- **Sub-second fresh builds**, **<100ms retained edits**, and **1–2 MB** Gdev
  Wasm, scaling toward **50k–1M LOC/s**.
- **Delete complexity before optimizing.** Pruning retired academic features
  (packages, numeric proofs, usage contracts, capability lifetimes, typed
  staging, row polymorphism, escaping closure environments, `List`, `=`, `lent`,
  and the legacy counted backend) shrinks `compiler-goose/` from ~71k LOC toward
  ~22–28k LOC and makes module interfaces parse-only.
- **One meaning per program.** Every optimization must preserve wrapping integer
  arithmetic, IEEE 754 float bits, trap order, effect order, and real
  application budgets.

Historical proposals remain pinned in Git history (`541ff890`). Active compiler
pruning and rollout phases live in
[docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) and
[PLAN.md](PLAN.md).
