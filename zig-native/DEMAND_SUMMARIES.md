# Owned demand-use summaries

The compiler publishes schema 1 summaries from immutable checked Core. A query
owns its checked `Body` header, parameter and local creation facts, aliases,
force-site scopes, closure capture identities and frozen latent type/effect-row
ordinals. Its transitive body read set is an immutable refcounted lease shared
by the analyzed component records. All Core ordinals belong to the enclosing
artifact's pinned module graph. No solver IDs or analysis scratch pointers
survive.

Facts describe at most zero, one or multiple dynamic force attempts, plus
independent unknown and escape flags. Escape takes precedence over unknown and
counts. Exclusive branches join with maximum use; sequential paths add counts up
to two. A creation outside a loop can be forced repeatedly; one inside that loop
is fresh per iteration. Binding versions preserve direct aliases. Returned or
aggregated demands and retained closure captures escape. Unknown callbacks,
unsupported shapes, provider cancellation and request boundaries remain
conservative. Provider and request scopes remain recorded on force sites.

A discovery pass builds the checked call graph. Tarjan schedules dependency
components before callers. Recursive components converge monotonically within a
per-component iteration budget; exhausted work becomes unknown. Child summaries
are cached with the root, so forwarding does not analyze suffixes again at every
call site. Node, body, depth, iteration, record, payload, capacity and lookup
budgets bound work and storage.

The backend consumes dynamic counts only when the existing `demand_inline.Plan`
independently admits lowering. This removes redundant memo state when two
exclusive arms each force once. Unknown/exhausted summaries and cache capacity
declines retain the existing Plan proof. Escaping uses cannot become direct
forces. Broad local memo and loop lowering remains task 037.

Before carrying queries into a retained revision, the executable body gate
validates every consumed body against its exact reachable projection and
transitive semantic dependencies, including captures and latent effects. Each
shared read set is validated once within the lookup budget. Namespace or unit
movement conservatively declines reuse. Consumed summary bodies are also added
to the emitted job's inline-body reads. New records belong to the unpublished
backend capture; failure releases the candidate and preserves the last good
revision. Runtime memo cells remain separate per dynamic demand creation.

Development checks on Zig 0.17.0, isolated worktree based on `544d715`:

- `zig build test -Doptimize=safe -Dllvm=false -Dtest-filter=demand --summary all`:
  82 passed, with the then-existing recursive-demand checker restriction. Task
  098 restores that source law. The integrated fixed-point and exhaustion laws
  use real checked self-recursive and mutually recursive bodies.
- The five demand guest test files, including
  `demand_summary_execution.test.ts`: 27 passed. These exercise effects, skipped
  traps, sync/JSPI cancellation, terminal traps, captures, imports, stable-type
  branch moves, retained/fresh equality and failed revision recovery.
- `deno task lint:zig` with the workspace's built zig-analyzer: zero findings.
  Two test-only directives document analyzer false positives for a filled
  metadata output and an operation-local query table pointer token.
- Every-allocation-failure laws cover owned summary construction/publication and
  a retained compiler edit. Three no-op generations preserve reusable summaries.

The deterministic forwarding-growth law measures analysis and cache publication
separately from source checking and emission:

| Bodies | Node visits | Call-edge visits | Component passes | Cached records |
| -----: | ----------: | ---------------: | ---------------: | -------------: |
|      8 |          30 |               14 |                8 |              8 |
|     16 |          62 |               30 |               16 |             16 |
|     32 |         126 |               62 |               32 |             32 |
|     64 |         254 |              126 |               64 |             64 |
|    128 |         510 |              254 |              128 |            128 |

These are work laws, not a claim of whole-compiler speedup. All records for one
analyzed graph conservatively share its complete read set, so an unrelated
producer within that graph can decline more reuse than strictly necessary.
Fallback counts can also overestimate forces through forwarded memoized values;
they remain safe. The summary cache is currently in-process artifact metadata;
portable checkpoint serialization does not include these records and safely
reanalyzes after restart. The full compiler gate remains required at
integration.

A focused baseline comparison used an archived, separately built `544d715`
compiler and the candidate, both Zig 0.17.0 debug/noLLVM with optimized guest
code. Complete scalar Wasm sizes were 76 -> 76 bytes for one straight force, 136
-> 96 bytes for one force in either exclusive branch, and 116 -> 116 bytes for
two sequential forces. Both compilers returned identical results for 0, 1, 21
and maximum U32. The branch reduction removes unnecessary local memo state;
these probes had no demand heap storage in either version.

Three candidate-only samples per generated forwarding size measured full project
build requests separately. Times below are medians in milliseconds:

| Bodies |  Cold | First edit | Later edit | No-op | Recovery |
| -----: | ----: | ---------: | ---------: | ----: | -------: |
|      8 |  27.6 |       29.3 |       29.1 |  1.20 |     1.03 |
|     16 |  50.1 |       50.1 |       46.7 |  1.30 |     0.91 |
|     32 |  83.1 |       93.7 |       90.9 |  1.12 |     1.10 |
|     64 | 188.4 |      183.0 |      180.4 |  1.19 |     1.05 |
|    128 | 429.0 |      405.8 |      397.8 |  1.41 |     1.29 |

The workload moves the same typed leaf force between branches and recovers the
last successful source after a rejected edit. No-op/recovery requests use the
project's frontend fast path and run zero backend summary work; direct native
laws above establish backend query reuse. Cold chain128 used one graph build,
127 summary hits, 770 node visits and 254 call-edge visits. This benchmark has a
Boolean condition in addition to the pure forwarding law's nodes. Whole-compiler
timings include source checking and emission and have no timing baseline here;
only the focused Wasm probes above compare baseline and candidate. Raw samples
and generated workloads are in the isolated worktree's ignored
`build/bench/demand-summary/{measure.ts,measurements.json,size.ts,sizes.json}`.
