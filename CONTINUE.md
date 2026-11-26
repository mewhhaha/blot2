# Working on Blot and Gdev

## Current frontier: In-Language Kernel/Process Coordination (`eb4d3d89`) & `io` Entry Syntax (26 November 2026)

Typed in-language `#kernel` / `#process` coordination (`eb4d3d89`) and the greenfield
`io` entry syntax (`io main (...) => ...`, `io const`, `io let` replacing `#entry`)
are complete and verified in `blot2` at `blotc-goose` SHA-256
`e472c8c23e89b5169ca268c68b55ef9f5ff1161a6cf3fa1857f885851545f4a0`
(`9,951,256` B; `generated/compiler/blotc.gz` SHA-256
`f4f366c0bf335613d610220a763e1a9cbd429bd5fe9bae844a16095235d3a0f8`,
`4,204,540` B):

- **Typed In-Language `#kernel` & `#process` Coordination (`eb4d3d89`, 26 November 2026):**
  - Upgraded opaque `Process [cfg, cmd, reply]` in [std/prelude.blot](std/prelude.blot) to `(U32, (U32, U32))` carrying `(process_id, binding_hash)` (FNV-1a-64 domain tag `0x13` over config/cmd/reply schema hashes) and added 6 `std`-only `@flat.*` intrinsics (`@flat.process_id`, `@flat.process_binding_hash`, `@flat.encode_wire`, `@flat.decode_wire`, `@flat.encode_batch`, `@flat.decode_batch`) with zero ABI 8 changes.
  - Added [std/runtime.blot](std/runtime.blot) (`Runtime` effect over `BRT1` packets), [std/process.blot](std/process.blot) (`spawn`, `call`, `send`, `poll`, `advance`, `close`), coordination APIs in [std/kernel.blot](std/kernel.blot) (`run`, `prepare`, `run_prepared`, `clear`, `submit`, `submit_prepared`, `poll`, `await_job`), and Deno coordinator [host/runtime.ts](host/runtime.ts) (`BlotRuntime`, `createRuntime`, `computeProcessBindingHash`) exported via [mod.ts](mod.ts) and [deno.json](deno.json).
  - Verified in [tests/host/runtime_coordination.test.ts](tests/host/runtime_coordination.test.ts) (5 end-to-end executed-Wasm tests covering stateless/prepared kernels, multi-core `KernelPool`, stateful `#process` actors, concurrent `submit`/`send`/`advance`/`poll`, trap containment, and pure-Blot mocked `Runtime.call`).

- **Contextual `io` Entry Syntax Replacing `#entry` (this commit, 26 November 2026):**
  - Replaced `#entry func <name>`, `#entry const`, and `#entry let` across all four grammar/tooling layers with contextual top-level `io <name> (...) => ...`, `io const`, and `io let` (supporting `private io` and `@[attr] io`, keeping `io` an ordinary identifier everywhere else, and rejecting legacy `#entry` and `io func`):
    1. Native compiler: [parser.goose](compiler-goose/src/parse/parser.goose), [source_operators.goose](compiler-goose/src/parse/source_operators.goose), [check.goose](compiler-goose/src/check/check.goose), [diagnostic_code.goose](compiler-goose/src/check/diagnostic_code.goose), [direct.goose](compiler-goose/src/direct/direct.goose), [function_entry.goose](compiler-goose/src/direct/function_entry.goose).
    2. Baba parser & formatter: [host/parser_source.ts](host/parser_source.ts) (`iO` marker), [host/syntax.ts](host/syntax.ts), [host/parser/grammar.baba](host/parser/grammar.baba), [host/parser/baba.json](host/parser/baba.json), regenerated `generated/parser/wasm/*`.
    3. Tree-sitter editor grammar: [editor/tree-sitter-blot2/grammar.js](editor/tree-sitter-blot2/grammar.js), [queries/highlights.scm](editor/tree-sitter-blot2/queries/highlights.scm), corpus & highlight suites (zero warnings, 11/11 corpus, 19/19 highlight).
    4. Host tooling, docs, skills, tests, benchmarks & fixtures: [host/doc.ts](host/doc.ts), [host/doc_html.ts](host/doc_html.ts), [host/generators.ts](host/generators.ts), [host/test_runner.ts](host/test_runner.ts), [host/diagnostics.ts](host/diagnostics.ts), [scripts/integration/migration_audit.ts](scripts/integration/migration_audit.ts), and all `blot2` `.blot`/`.ts`/`.md` files (`test_fixtures.py` verified **zero Wasm byte diffs across all 109 fixtures** before re-recording offsets/metadata).
  - **Sibling checkouts & installed CLI note:** `~/.local/bin/blotc` and `~/.local/bin/blot` were intentionally NOT overwritten yet so sibling checkouts `../pen`, `../ink`, and `../gdev` (which still use `#entry` and contain concurrent uncommitted edits) remain unbroken until explicitly migrated in lockstep.

- **Compiler-Backed Documentation Generator (`blotc doc-project` + `blot doc`, `df207b98`, 26 November 2026):**
  - Added `blotc doc-project ENTRY [--include-private]` in [cli.goose](compiler-goose/src/driver/cli.goose) and [cli_project.goose](compiler-goose/src/driver/cli_project.goose) to emit checked `doc_module` JSON lines directly from `CheckedProject` (skipping lowering/emit so libraries without `#entry` succeed cleanly), including inferred types, `own` parameter masks, `where` clauses, effect rows, `is data` constructors/fields/defaults/spans, `is opaque` hiding private representations, `is trait`, `is effect`, associated members, and trait `impl`s.
  - Added [host/doc.ts](host/doc.ts), [host/doc_html.ts](host/doc_html.ts), and [docs/host/doc.md](docs/host/doc.md), wired `blot doc` into [host/cli.ts](host/cli.ts), [host/installed_cli.ts](host/installed_cli.ts), [mod.ts](mod.ts), and [deno.json](deno.json): supports `std`, `blot.json` and `pen.json` alias/library discovery (verified on `std/` and `../ink/lib/codec.blot`), `//!` / `//` / `///` Markdown comments, Rustdoc-style intra-doc links (`[`Symbol`]`, `[label](`mod/Symbol`)`, `--check-links`), local runnable doctests (`--test`, `// => expected`, `test` / `test expect_trap`, `check`/`no_run`/`ignore`), static Markdown (`--out`: `INDEX.md`, `API.md`, `modules/*.md`), `--search`, `--json`, and static HTML (`--html --out`) with precompiled base64 ABI 8 `.wasm` examples and a zero-dependency pure-JS browser runner (`runner.js` decoding ABI 8 returns, `blot:traps` v1 panics, and BTST v1 reports).
  - Added runnable doc comments and intra-doc links to [std/vector.blot](std/vector.blot) and [std/text.blot](std/text.blot) (with two `source_bytes`-only fixture updates in [expected.json](compiler-goose/tests/fixtures/expected.json)) and 7 unit/integration tests in [tests/host/doc.test.ts](tests/host/doc.test.ts) (including live execution of generated `runner.js` against precompiled base64 Wasm).

- **Wave 1 — Compiler Type, Trait, Opaque, Ownership, Uniqueness & FBIP Soundness (`c5109160` + this commit):**
  - Enforced trait associated output `type_eq`, full-parameter & nested `traitIsReadOnly`, `is opaque` reflection (`#fields`, `#variants`, `.(field)`, builders), indirect `fork`+`with` `Foreign` rejection, `@simd.store` uniqueness/cache invalidation, duplicate `with` rejection, single `ambiguous_member` on dot-calls, `test` return validation, `#[N; T]` `#entry` rejection, and comptime closure checks.
  - Closed uniqueness & FBIP soundness gaps: loan-ended undo trails, generic `#for` builders/updates, non-unique storage `own`/`fork`, generic `freeze`, recursive deep copy for nested arrays/ADTs, `with` record/cell/fork soundness with rebinding-slot tracking, FBIP/`linearAppend` aliasing across loops/merges/no-op updates/statement `case`/loop carries, `runtime.create` overflow guard, `static_pool_flag` write checks, and multi-parameter bracket nominal (`Map [k, v]`, `Result [a, e]`) `matchNominalArgs` ownership matching in [uniqueness.goose](compiler-goose/src/check/uniqueness.goose).
  - Permanent executed-Wasm regressions in [audit_soundness_regressions.test.ts](tests/guest/audit_soundness_regressions.test.ts) (16 tests, incl. negative `Result [U32, #[U32]]` `result_not_owned`).

- **Wave 2 — Incremental SIMD Relocations, Staging Determinism & Control Flow (`c5109160`):**
  - Added `unpatchableOperand` across all 5 SIMD vectorizers + `emitVec3F32Expr`, tightened `defer_f32_nan` NaN canonicalization, fixed `#run`/`#if` associated `eq`/`ne` and IEEE-754 F32 equality (`-0.0 == 0.0`, `NaN != NaN`), fixed `let ... else:` / `#for` RHS carries, generic `field.default`, `spark #[p.(f) + i]`, and `--relaxed-simd` help accuracy.

- **Wave 3 — Formatter, Tree-sitter, Stdlib, Examples & Docs (`c5109160` + this commit):**
  - Extended Baba grammar & [host/format.ts](host/format.ts) for expression `fork`/`#for`/`#if`, reflected updates `val.(f) :=`, fixed arrays, trailing-comma tuples, and strict 80-char idempotency across all 33 shipped `.blot` files; extended Tree-sitter grammar & corpus ([reflected_members.txt](editor/tree-sitter-blot2/test/corpus/reflected_members.txt)).
  - Hardened `std/text` (`from_f32`, `from_f32_fixed`), `std/test` (`near_array`), `std/vector` (`normalized`), [wgsl_gen.blot](examples/generators/wgsl_gen.blot), [csv_gen.blot](examples/generators/csv_gen.blot), [ecs.blot](examples/ecs.blot), [CHEATSHEET.md](CHEATSHEET.md), [docs/language/guide.md](docs/language/guide.md), and [README.md](README.md).

- **Wave 4 — Solid-2 Agent Diagnostics, Skills & `blot:traps` v1 Provenance in Deno & Pen (this commit + `../pen` `f2047ec`):**
  - Honest `blot check` (runs lowering/uniqueness by default; generator-backed libraries without `#entry` succeed cleanly on `Code.no_entry` only; LSP filters spurious `no_entry` on library files).
  - Unified v1 enriched diagnostic JSON schema (`schemaVersion: 1`) across CLI text, `--json`, LSP, and test runners; repaired all broken quick-fixes with a 12-case compile-replay CI test; expanded `DIAGNOSTIC_CATALOG` / `blot explain` to 35 canonical entries synced 1-to-1 with [skills/blot-diagnostics/SKILL.md](skills/blot-diagnostics/SKILL.md) covering 100% of all 232 compiler diagnostic codes + `asset_import` + `Io`; added [skills/agent-loops/SKILL.md](skills/agent-loops/SKILL.md) and exported it in [deno.json](deno.json).
  - Emitted optional `"blot:traps"` v1 custom section + Page-0 offset `772` trap-site ID (exporting `"blot:memory"` on trapping scalar-only modules) and decoded typed panic/bounds/unreachable provenance + source locations in both Deno ([host/guest.ts](host/guest.ts), [host/test_runner.ts](host/test_runner.ts), [host/generators.ts](host/generators.ts) with Stage-0 `provenance` & `virtual_source`) and Pen (`../pen` `f2047ec`: `pen-runtime`, `blot-host` Wasmtime/native/`wtime-aot`, and `pen test-blot`).

- **Preceding 25 November 2026 milestones (full details in `git show 08f35702:CONTINUE.md` and `git show b6462804:CONTINUE.md`):**
  - Extended `#for` comptime reflection (`val.(field) :=`, `#for field in #fields T:`, `field.index`, `field.default`), Stage-0 Blot virtual module generators (`a24fc85c`), generic comptime decoders in Ink (`../ink` `f7486d3`), `goosew` fast dev/check & per-declaration reuse (`9df8c3ab`), `#entry`/`#kernel`/`#process` (`c482fccb`), and first-class `test "..."` + `std/test` + unified `pen test-blot` (`7b1468cb`, `91a06cbe`).

### Checkpoints on `origin/main`
| Repo | Current `origin/main` | Frontier Commits |
|---|---|---|
| `blot2` | this commit (after `eb4d3d89`) | Contextual `io` entry syntax across compiler/Baba/Tree-sitter/tooling (this commit); typed in-language `#kernel`/`#process` coordination (`eb4d3d89`); `blotc doc-project` + `blot doc` (`df207b98`); Stage-0 Pen pointer (`0f4a5cd4`); Wave 4 Solid-2 agent diagnostics & `blot:traps` v1 (`7157f22a`) |
| `../pen` | `92e2ef7` | Stage-0 Blot virtual module generators (`pen:plugin@0.3.0`, `compiler.settings.generators`, `guest.run-u32-packet`, `virtual_source` / provenance in `plugin_build`) (`92e2ef7`); `blot:traps` v1 runtime trap provenance (`f2047ec`); unified `pen test-blot` (`eb8f575`) |
| `../ink` | `46111bd` | Current checkout (`46111bd`, preserves local uncommitted edits); generic comptime decoders (`f7486d3`) |
| `../gdev` | `4e891d2` | Current checkout (`4e891d2`); >8192 rad trig NaN fix & physical brick counts (`642ad53`) |

### Hard Invariants Preserved
- **Guest ABI 8:** `blot:abi` v8 and `blot:invocation` v1 unchanged (zero extra
  runtime exports; Page-0 offset `640` carries `arena_oom_flag`, offset `772`
  carries optional trap-site ID; optional `blot:finish_invocation` /
  `blot:kernels` / `blot:processes` / `blot:traps` v1; optional `blot:tests` v1
  custom section in `--test` builds only).
- **Session Protocol 2:** `Operation 0..=6` unchanged; `service::KERNEL = 15`
  uses unambiguous `request == 0` host→guest provenance (`CAP`, `CTL`,
  `BATCH_ERR`, `BATCH_OK`), strips live-only unrecorded `CAP` before `Recorded`,
  filters `request == 0` events in `ink/lib/pen/host.blot` before `app.advance`,
  and normalizes render packets via `pen_protocol::canonical_render_packet`.
- **Save Schema 26:** Ephemeral `KernelTransport` and Gdev `prewarm_entries`
  are excluded from Save 26 and cleared on restore; `world_storage.blot`
  preserves `input` (key 3), `god_hand` (key 114), optional `impact` (key 157
  v1), canonical scene section order, and immediate `restore_scene` with
  `app.hold_frame` on `restore_stash`.
- **Canonical `0x7fc00000` quiet NaN** determinism across `function_spark`,
  `scalarOp`, `std/simd`, and `#run`.
- **Unified dynamic arrays, single update `:=`, value restriction, and read-only references:**
  `#[T]` (`Array T`) is the sole dynamic array type (`#[N; T]` for fixed-length);
  local `let` generalizes only on syntactic `func` values; `&T`, `&[T]`, `^T`,
  and `*T` are strictly read-only; `:=`, `@storage.push`, `@storage.pop`,
  `@storage.truncate`, and `@simd.store` enforce unique ownership
  (`ownedInPlacePath`), guaranteeing all module `const` pools are deeply
  immutable (`mode = 2`).

### Verified Identities & Qualification Evidence
- **Compiler, CLI & host identities:**
  - `compiler-goose/build/blotc-goose` SHA-256:
    `e472c8c23e89b5169ca268c68b55ef9f5ff1161a6cf3fa1857f885851545f4a0`
    (`9,951,256` bytes; `~/.local/bin/blotc` kept at prior `df207b98` until sibling repos migrate from `#entry` to `io`)
  - `generated/compiler/blotc.gz` SHA-256:
    `f4f366c0bf335613d610220a763e1a9cbd429bd5fe9bae844a16095235d3a0f8`
    (`4,204,540` bytes; decompressed byte-identical to `blotc-goose`)
  - `std/prelude.blot` SHA-256:
    `dcd26873026cd23ac7d53b9b17df8e23b95d84bb95d56c525d277e72a87784b7`
  - `../pen/target/release/pen` & `~/.local/lib/pen-runtime/pen` SHA-256:
    `deec51f8d7c689701dcc6c21d70888f59e59b86b9016cfa3353edf2de0bfe0f6`
    (`pen:plugin@0.3.0`; `plugins/blot.wasm` SHA-256
    `3f291f7a3e6c203b959ceaf19d1b808e77e35dbb3c79522a52380a88b103c901`)
- **Qualification gates:**
  - `blot2` (this commit): `deno fmt --check` (97 files), `deno check`,
    `test:editor` (**6/6**), `harness` (`2.44 s`), `release-build` (`101.68 s`,
    `run-8bf13ff522c80c98`), `reference-direct` (**2/2**), `reference-uniqueness`
    (**206/206**), `reference-fixtures` (**109/109**, zero Wasm diffs across all
    109 fixtures), `pack` OK, `preflight-regressions` OK, `test:guest` exit 0
    (`23.78 s`, incl. `runtime_coordination.test.ts`, `doc.test.ts`, `format.test.ts`,
    `syntax.test.ts`, `diagnostics_agent.test.ts`), `test:std` (**7 modules, 18
    tests, 146 assertions, 0 failed**, `137.9 ms`), `check:editor` (**11/11**
    corpus + **19/19** highlight suites, zero grammar warnings), and
    `deno task blot doc std --test --check-links` (**3/3** passed).
  - `../pen` (`92e2ef7`): `plugins/blot` (**24/24** unit), `pen-plugins`
    (**9/9** unit + **10/10** real-WASI integration incl. Stage-0 WGSL/CSV/record/bytes
    generators, two-level caching spawn counts, `$Err`/`@panic`/bounds `blot:traps` v1
    spans, `virtual_source`, and `watch_changes`), `pen plugin_build` (**4/4**),
    `pen blot_test` Stage-0 WGSL/CSV execution test, and installed `/tmp`
    `pen test-blot` Stage-0 smoke run (**1/1**, `0.1 s`); preceding `f2047ec`
    qualified `pen-runtime` (**218/218**), `blot-host` (**33 unit + 11 integration**),
    and `pen blot_test` (**17/17**).
  - `../ink` (`46111bd` + local edits): `pen test-blot --project ../ink` exit 0
    — **493 passed, 0 failed** in 108 Blot modules (`1.7 s`, `436` checks, `53`
    must-trap, `4` must-not-compile) + **257 passed, 0 failed** native
    f64-reference Rust tests (`9.43 s`).
  - `../gdev` (`4e891d2`) live NVIDIA Vulkan hardware frame:
    - Compiled via `scripts/integration/build_gdev.ts --frontend-workers 8 --profile`
      (`build/gdev-first-frame/main-337aad2680dbae15/main.wasm`, `6,530,935` B,
      SHA-256 `a51952caafaba76540c566b834e1af736a2d66734a494a4dfd59760ae4ce4d63`,
      `320` modules / `4,555` functions, **`885.1 ms`** build,
      `parallel_retries=0`, `parallel_batches=1`).
    - Executed on **`NVIDIA GeForce RTX 4080 SUPER (Vulkan)`** via
      `LD_LIBRARY_PATH="$HOME/.local/lib/pen-runtime"
      VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json python3
      scripts/integration/run_pen.py --launch --hardware` →
      `build/storage-integration/gdev-one-frame/attempt-i_35rf4f/frame.png`
      (inspected `640×480` PNG, SHA-256
      `19a03f0a92e7ad3cd6c1480ab2e538cd57a4553963ffa03122d4b59a68b663e8`,
      bit-identical to prior baseline; `frames.trace`: `0 7062536994385978
      f1af2247052533db`, `guest 9.577 ms`, `render 0.614 ms`, `total 12.497 ms`,
      all 6 runner checks `true`, `compiled_wasm_unchanged: true`).

## Remaining work

All planned frontier tracks (Waves 1–4 + Stage-0 Blot generators in Pen) are
complete, installed, and verified across `blot2` and `../pen`. Optional future
directions:

1. **Incremental uniqueness validation & backend replay for Track 5:** Scoping
   uniqueness validation to the spliced binding's dependency cone and
   broadening backend body-image replay on behavior-changing edits would push
   single-body structural edits on `robots.blot` below `20 ms`.
2. **Migrate remaining flat lane decoders in Ink & Gdev:** Adopt the new
   generic `codec.decode_lanes` / `codec.decode_record` across simple flat
   records where no extra domain range clamps are needed.

## Pinned history & evidence

Superseded checkpoint narratives are preserved in pinned Git history and in
their dedicated task and measurement records:

- Extended `#for` reflection & Stage-0 generators: `git show 08f35702:CONTINUE.md`
- `#entry`/`#kernel`/`#process`, `std/test`, `goosew` & Track 5 reuse: `git show b6462804:CONTINUE.md`
- Structural edit localization (`fresh=1`), FBIP reuse & `wtime-aot 0.1.3`: `git show c482fccb:CONTINUE.md`
- Retained-edit fast paths & timeline rewind determinism: `git show 7c06d4e6:CONTINUE.md`
- Tier 1–7, Tracks 1–4, Solid-2 diagnostics & Phases 1–6: `git show 98f277f2:CONTINUE.md`
- Concurrency vNext Phases 1–5: `git show 67fc95b8:CONTINUE.md`
- Checkpoint F compiler pruning / Batch 1B–1D: `git show d0ae1652:CONTINUE.md`
- [tasks/CONCURRENCY_VNEXT.md](tasks/CONCURRENCY_VNEXT.md) · [tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) · [docs/compiler/VNEXT_ROADMAP.md](docs/compiler/VNEXT_ROADMAP.md) · [tasks/FAST_COMPILE.md](tasks/FAST_COMPILE.md) · [tasks/MEMORY_MODEL.md](tasks/MEMORY_MODEL.md)
- [benchmarks/evidence/measurements/2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json](benchmarks/evidence/measurements/2026-11-25-rust-and-bevy-ecs-wtime-0.1.3.json) · [benchmarks/evidence/qualification/2026-11-17-owned-runtime.json](benchmarks/evidence/qualification/2026-11-17-owned-runtime.json) · [benchmarks/language/NATIVE_ROUTES.md](benchmarks/language/NATIVE_ROUTES.md) · [benchmarks/language/BROWSER_ROUTES.md](benchmarks/language/BROWSER_ROUTES.md)

Use `deno task test:compiler` for compiler changes and the tracked
[Main build](scripts/integration/build_gdev.ts) and
[frame runner](scripts/integration/run_pen.py) for integration.
