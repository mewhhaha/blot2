# Literal edit invalidation

Task 023 narrows what a literal edit invalidates. Before it, an edited module
that was not structurally equal to its previous revision kept the reuse gate
only when it had no effect-operation values. Any module that named an effect
operation, provider, state provider or runner therefore turned a literal edit
inside a function body or aggregate into a disabled gate for the whole program:
every retained function, closure, principal proof and selected query in every
module was rebuilt. Top-level scalar edits were unaffected because they keep the
module structural. The compiler milestone is recorded below.

## Admission rule

[`catalogEqual`](src/principal_reuse_gate.zig) now compares the ordered
operation-value catalog entry by entry, exactly like the other semantic
catalogs: identity, arguments, signature, witness node and witness result must
all be identical.

This is sufficient because every entry is created by, and referenced from, a
single `.operation_value` node, and its witness operand is lowered into that
declaration's own prefix. Definition equality
([declaration_projection.zig](src/declaration_projection.zig)) compares the
entry and scans its witness; the dependency walk
([declaration_dependencies.zig](src/declaration_dependencies.zig)) follows it. A
changed provider, state initial value or witness therefore dirties exactly its
declaration and that declaration's transitive consumers. Every other reader of
the catalog (backend, evaluator, importer, relink) indexes it through such a
node or only remaps identities.

Conservative fallbacks are unchanged:

- an added, removed or shifted entry (for example a witness body that grows and
  moves its node) changes the catalog and disables the gate for the program;
- an edited module still declines whole-module executable admission (`admits`);
  only per-declaration principal and code-body admission apply;
- associated-catalog and type edits still disable the gate.

## Certificate image sharing

An enabled gate freezes a dependency-validation certificate for the next
revision. Previously each edit re-serialized a full structural image of every
unit, prelude included. The gate now marks a unit `certified_images` when the
old certificate's image exactly matched the old pin and `proveSame` proved the
current module stream-equal to that pin. Those exact comparisons, not stamps,
are the proof. [The certificate](src/dependency_certificate.zig) then retains
the old image's lease instead of copying it, after rechecking the unit, producer
path and stamp; every other unit is re-imaged. The next revision still walks
every byte of every image against its pin, so tampering with retained memory is
detected as before. `source_validation.reused_images` counts shared images.

## Qualification on 10 October 2026

The baseline is the task-022 compiler sources (`62241e2`); the candidate is
pinned with its probe in [the pins](qualification/literal-edits-pins.json).

Completed checks:

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 629 guest/client tests; `deno task lint:zig` reports
  zero findings across 309 files.
- [Native laws](src/literal_edit_tests.zig) cover an effectful module with a
  witness: a top-level scalar edit (control), a body literal and a witness's
  captured constant reuse unaffected bodies; a growing witness body and an added
  operation value decline. Outputs equal fresh builds, including under an
  allocation-failure sweep.
- The [gate laws](src/principal_reuse_gate_tests.zig) now state that a changed
  state-provider initial value rejects the provider and its consumer while
  admitting independent declarations, and that published certificates share
  exactly proven unchanged images, re-image edited units, decline a wrongly
  marked unit by its stamp, never share a forged old image, and survive an
  allocation-failure sweep. The
  [principal cache law](src/principal_evidence_reuse_tests.zig) keeps global
  rejection for type and associated-catalog edits and keeps the independent
  proof across a provider edit.
- A mutant with the old catalog rule fails all four new or restated native laws
  above that depend on it.
- [A process-level law](tests/literal_edit_reuse.test.ts) compares a retained
  server with fresh servers through edit, revert, a failing edit and re-edit of
  ten literal edits in public examples, including ecs, requests,
  generic_effects, host_io and host_capabilities: bytes and native work steps
  equal fresh builds. A generated program edits a state initial value, a reader
  witness and an unrelated literal; executed results follow each revision.

### Measurements

The retained probe ran 21 alternating repetitions of nine rounds over thirteen
workloads ([CSV](qualification/literal-edits.csv)). Every phase emits identical
Wasm in both compilers, and retained memory plateaus. Steady medians per edit:

| Workload                                       | Reused named (fresh) | CPU µs      | Requested bytes |
| ---------------------------------------------- | -------------------- | ----------- | --------------- |
| Effectful entry, 40-function import, body edit | 0 (82) → 80 (2)      | 3445 → 3455 | −39 KB          |
| Effectful entry, small import, body edit       | 0 (6) → 4 (2)        | 1429 → 1627 | +175 KB         |
| Effect witness module, body edit               | 0 (3) → 1 (2)        | 1250 → 1398 | +113 KB         |
| ecs literal                                    | 0 (20) → 6 (14)      | 8197 → 8725 | +288 KB         |
| generic_effects literal                        | 0 (5) → 2 (3)        | 1648 → 1844 | +186 KB         |
| requests body literal                          | 0 (5) → 0 (5)        | 1888 → 2015 | +165 KB         |
| Pure-module literal edits (six workloads)      | unchanged            | 0.82–0.95 × | −196 to −327 KB |
| arrays import edit                             | unchanged            | 9090 → 9023 | +28 bytes       |

Steady CPU geomeans are 0.970 (edit) and 0.968 (revert); rejected-edit and no-op
controls are 0.991 and 0.987. One-minute load was 4.9–8.6 on an interactive
desktop, so single-sample phases (population, first edit) swing by up to ±30% in
both directions on identical code.

Effectful modules now keep unaffected code across literal edits, and every
gate-enabled edit is cheaper because unchanged certificate images are shared. At
public-example size, though, reuse in an effectful module does not yet pay for
itself in CPU. Enabling the gate adds the exact verification that pure edits
already pay: the old certificate is matched against each unit (about 70 µs), the
edited module is fully validated (55–140 µs) and re-imaged, and retained
fragments are replayed (about 4 µs each, plus lookup). For the 40-function
import, replaying 80 functions costs about as much as specializing them. First
edits after population are slower still, 1.1–1.8 × on effectful workloads,
because population publishes no certificate, so the first edit validates every
old module. Retained live bytes grow by the certificate and gate state (for
example ecs 1.83 → 2.13 MB).

## Remaining scope

- Invalidation is per declaration. A consumer of an edited constant rebuilds
  even when it reads only unchanged parts: every ecs system reads `simulation`,
  whose world data holds the edited literal beside an unchanged scope closure.
  Value-level cutoff of named-constant reads, and task 024's interface cutoff,
  are not implemented.
- Fragment replay and verification cost roughly what small functions cost to
  specialize; the CPU benefit needs larger bodies than the public examples.
- Population publishes no dependency certificate, so the first edit validates
  every module.
- Constants are still evaluated every revision, and aggregate data is
  re-serialized (task 022).
- The under-30-ms target is not demonstrated. gdev is private and unavailable,
  and the `floor_half_extent` edit, if it is a top-level scalar, already took
  the structural path. It stays open for task 084.
