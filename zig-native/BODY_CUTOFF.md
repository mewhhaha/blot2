# Body interface cutoff

Task 024 lets semantic work stop at an unchanged interface when a body changes.
Before it, two things defeated this for edits inside a module:

- Refinement receipts, the retained semantic results that drive specialization,
  were admitted only when their root's module was structurally unchanged. Any
  body edit therefore re-inferred every region in the edited module, including
  closures in declarations that had not changed. Inference is the largest part
  of code generation, for example about 3 of 4.4 ms on an ecs edit.
- `for` loops were desugared into hygienic names that embedded the loop's source
  offset and syntax-node count. An edit that changed a module's length renamed
  every later loop variable, changed the project namespace, and so disabled the
  reuse gate for the whole program.

The compiler milestone is recorded below.

## Receipt roots in edited modules

[The refinement lookup](src/refinement_receipt.zig) now admits a root by its own
declaration instead of its whole module:

- a body root when its declaration's exact projection and identity are admitted
  (`admitsLocalSource`);
- a closure root when its unit is structural, or when the
  [gate](src/principal_reuse_gate.zig) recorded, during the exact projection of
  a declaration in an edited module, that this declaration reaches that closure
  catalog entry, and that declaration's source and identity are admitted
  (`admitsClosure`). The projection compares the closure entry at the same index
  in both modules, so the old root names the same lexical closure.

Everything else is unchanged. A receipt still replays only if every collected
source body is exact, every consumed call judgment has an unchanged identity
(type, scheme, runtime and function-ness) and is already established in the new
session, and its expected shape, seeds, scalar reads (structural units only),
plain facts (structural units only) and imported results agree. This is the
interface cutoff: a consumer whose region read only a callee's interface replays
after that callee's body changes, while a region that collected the callee's
source re-infers. A projection also compares the binding record of every
same-unit declaration it references, so a changed interface revokes its
referencing owners.

Executable reuse is not widened. Retained fragments still require the transitive
dirty set, so every executable caller of a changed body, its selected evidence,
captures and staged inputs is regenerated; only the semantic inference those
callers need may come from receipts.

## Hygienic loop names

[The parser](src/parser.zig) numbers `$collection.N` names within each top-level
declaration. Names stay unique where they are visible, and an edit elsewhere no
longer renames them.

## Qualification on 11 October 2026

The baseline is the task-023 compiler sources (`fbe28c8`); the candidate is
pinned with its probe in [the pins](qualification/body-cutoff-pins.json).

Completed checks:

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 632 guest/client tests; `deno task lint:zig` reports
  zero findings across 310 files.
- [Native laws](src/body_cutoff_tests.zig): a same-size body edit replays the
  three receipts rooted in unchanged declarations and their closures, with
  fresh-identical output under an allocation-failure sweep; a callee body edit
  with an unchanged interface keeps consumer receipts, declines the region that
  collected the callee's source, and regenerates its executable callers. A
  mutant with the old structural root rule replays none of them.
- [A gate law](src/principal_reuse_gate_tests.zig) checks closure roots in an
  edited module: an unrelated edit keeps both closures, a closure body edit
  revokes only that closure, a callee body edit keeps the caller's closure, and
  a changed callee annotation (a changed binding record) revokes the referencing
  owner's closure but not an unrelated one.
- [A process-level law](tests/body_cutoff_reuse.test.ts) compares a retained
  server with fresh servers through a callee value change, a same-value body
  rewrite, swapped demand control flow, a changed effect trace, a failing edit
  and recovery; executed results follow every revision, and receipts replay. It
  also edits, reverts, breaks and re-edits five public-example body edits,
  including size-changing ones, with bytes and native work steps equal to fresh.
- `cli_profile.test.ts` compared counters from builds in two random temporary
  directories whose names vary in length; since task 021 the metadata counters
  include the canonical path, so it failed in roughly one run in five. Both
  builds now use equal-length sibling directories (0 failures in 30 runs).

### Measurements

The retained probe ran 21 alternating repetitions of nine rounds over seventeen
workloads ([CSV](qualification/body-cutoff.csv)); every phase emits identical
Wasm in both compilers, and retained memory plateaus. One-minute load was 40–49
on 16 threads (other sessions' builds and browsers), which roughly doubles
absolute times; the alternating pairs keep the ratios comparable. Steady medians
per edit:

| Workload                         | Refinement hits | CPU ratio     | Requested bytes |
| -------------------------------- | --------------- | ------------- | --------------- |
| ecs literal (non-scalar)         | 10 → 58 of 82   | 0.850         | −94 KB          |
| ecs body operand swap            | 10 → 58 of 82   | 0.844         | −94 KB          |
| monads literal                   | 6 → 23 of 32    | 0.851         | −24 KB          |
| generic_effects literal          | 0 → 5 of 7      | 0.956         | −3 KB           |
| requests body literal            | 6 → 9 of 18     | 0.994         | +13 KB          |
| lists size-changing literal      | 0 → 6 of 9      | 1.129         | +145 KB         |
| ecs / syntax size-changing edits | 0 → 0           | 1.008 / 0.997 | ~0              |
| other workloads                  | unchanged       | 0.97–1.02     | ~0              |

Steady CPU geomeans are 0.972 (edit) and 0.969 (revert); rejected-edit and no-op
controls are 0.995 and 0.999, and first edits 0.985.

Inference is the largest cost of the code a body edit regenerates, so admitting
receipts per declaration removes most of it when an edited module's other
declarations are unchanged. The size-changing lists edit now keeps its gate,
because loop names no longer move, and reuses one function and six receipts. On
that small program the per-edit verification costs more than they save, as with
effectful edits in task 023. The ecs and syntax size-changing edits still add
type nodes, which changes the type catalog and disables the gate.

The under-100-ms body-edit target is not demonstrated: gdev is not available in
this checkout. A separate session measured the current gdev checkout with the
`fbe28c8` compiler: a top-level scalar literal edit costs about 1.1 s of CPU,
about 60% of it re-evaluating entry constants. It also bisected a 2.3× slowdown
against `632b461` to `099e700` ("Share owned inferred principal graphs without
unfolding open diamonds"); disabling `reuse_principal_graphs` restores the old
cost there. Neither is addressed by this task.

## Remaining scope

- Core node and type IDs are module-global. A body edit that adds nodes
  renumbers every later declaration in its module; one that adds type nodes
  changes the type catalog, which disables the gate for the program.
  Size-changing edits therefore still lose most reuse.
- The project symbol table is ordered by first use. A new identifier spelling
  anywhere still changes the namespace and disables the gate.
- The frontend still rechecks every body of an edited module.
- Executable fragments of transitive callers rebuild even when the callee's
  summaries are unchanged; finer executable dependencies are not recorded.
