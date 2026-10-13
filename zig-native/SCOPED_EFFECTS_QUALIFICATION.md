# Direct scoped effect qualification

This is an implementation slice of [the reviewed design](SCOPED_EFFECTS.md).
Tasks058 and059 remain open. No milestone commit or full compiler gate is
claimed here.

## Supported boundary

Direct `@effect.scope (fn (capability: Family Arguments) => body)` creates fresh
authority on every guest entry. Member operations, local aliases, capturing
local thunks and ordinary providers preserve the exact owner. Nested same-typed
State capabilities return `[11,102,10,100]`; callback forwarding returns119 and
reinstalling one capability shadows its own installation. Scoped request clauses
carry an exact operation selector and a separate counted authority edge; two
same-family owners route to distinct clauses, while aliases of one owner reject
duplicate clauses. Unhandled owners forward to their outer provider.

Checked/frozen operation keys retain declaration, family arguments and a lexical
scope binder. Runtime descriptors remain static; the activation owner is a
separate counted edge retained by operation closures and installations. State
cells remain separate. Frozen validation checks binder ownership, member
references and exact request selector/label correspondence. Runtime invocation
checks active permission before provider lookup.

Each owner registers a dedicated activation journal record before exposure.
Normal cleanup revokes before its private storage retires; trap/JSPI rejection
revokes invocation owners before closing frames. Retained aliases preserve
identity without preserving permission. Native handles never recycle, and
exhaustion fails. The journal is separate from demand-force records.

Fresh scope execution declines ordinary constant evaluation. Emission declines
fragment reuse for the owning job. Capability layouts cannot become closed
semantic value evidence. Scoped semantic receipts decline import; checkpoints
may retain validated symbolic binders and executable code, which creates fresh
owners when run. No live authority enters an evaluator snapshot or archive.

## Conservative limits

Only direct callbacks with explicit family annotations are admitted. Symbolic
family payload arguments substitute through generic scope factories, including
separately compiled factories. A structural result may retain the same unsolved
payload variables: those shapes originate outside the fresh owner. The result
footprint compares the exiting binder exactly. A longer-lived outer capability
may cross an inner boundary through structural data; that inner capability still
rejects. Dotted member selection preserves the complete checked projection path,
including operation aliases. Array reads borrow their input; writes retain
conservative sink checks. Fresh capabilities and known opaque results still
reject. A directly returned source closure has a bounded footprint walk over
resolved bindings and exact operation aliases: no captures, primitive captures
and longer-lived authority may return; an exiting-owner capture still rejects
even when its operation is handled and its row is pure. Unknown callable/opaque
captures and unsupported source forms retain a conservative error. Generic
capability parameters/capture contracts, branch-selected identities, written
capability rows remain unsupported. State read/write pairs from different owners
reject rather than losing an owner edge.

Anonymous callback adapters whose whole body invokes their parameter may borrow
operations/capturing closures when the callback returns structural data. This
proof stays within the requesting expression; a named/imported helper still
requires an owned capture/store contract. Sync/JSPI callbacks retain permission
until completion and revoke on rejection.

Primitive and structural data may return. Apart from inherited symbolic payload
variables and proven direct source closures, callable, demand, provider, nominal
and unresolved results or transferred arguments reject conservatively, including
pure handled closures and longer-lived builtin State writes. Associated dispatch
arguments use the same guard. This also rejects some authority-free values and
legal storage/callback flows. Precise footprints, opaque/generic/compiled store
contracts, origin traces and the complete059 acceptance matrix remain open.
Structural escape checking is bounded at128 depth and65536 visits per query.

## Validation

Zig0.17.0, Safe/noLLVM, CPU4 for development:

- Focused `zig build test` filters: `scoped effect`, `effect authority` and
  `scoped provider keys`; passing allocation-failure laws cover checking,
  lowering, emission, exact evidence imports and authority/frame publication.
- Frozen evidence rejects missing or substituted scope binders and absent or
  substituted request selectors. Request checking/lowering/emission have
  allocation-failure coverage. Generic payload checking/lowering/emission and
  static-operation storage rejection also have allocation-failure laws.
- Executed controls:23 groups across direct scopes, scoped requests, the
  authority journal, symbolic rows, generic scope factories and storage
  diagnostics pass, including both codegen tiers, sync/JSPI, suspension,
  rejection, trap recovery, aliases, forwarding, source/compiled effect
  declarations, retained edits, failed edits and checkpoint byte parity. Scoped
  request groups also cover cancellation, a demand retry that recreates scope
  authority, provider forwarding and host suspension/rejection inside a clause.
  Generic factories cover U32/F32 scalars and arrays through source/compiled
  declarations, retained specialization edits and checkpoint parity. Static
  generic operation calls enforce the same transfer guard as ordinary calls; a
  capturing pure closure passed through such an operation to longer-lived State
  rejects in both source and compiled consumers. Two direct callback adapter
  groups cover borrowed operations/closures, sync/JSPI, rejection/recovery and
  checkpoints. Two structural lifetime groups prove record/array forwarding of
  longer-lived authority after inner revocation and rejected-edit rollback.
  Projection lowering/emission, checker and allocation-failure laws cover the
  same boundary. Two returned-closure groups cover primitive captures and
  operation aliases across inner revocation. A same-header edit adding a handled
  authority capture rejects without changing the prior checkpoint. Native
  checker/lowering/emission allocation-failure laws cover the returned-closure
  proof.
- The lifecycle fixture proves retained identity is inactive before teardown on
  success and failure, with zero journal roots and leases.
- Zig analyzer:368 files, zero findings.

The full LLVM/compiler gate belongs to the combined qualification. This slice
was developed against staged source tree
`c2b1b545ffa6877affc9e34b9825e1e2ab158680`; unrelated joint-batch repairs and
costs are separate.

## Measurement

CPU6, Safe/noLLVM compiler, seven alternating fresh compiler pairs and31 warmed
guest pairs,2048 calls per guest sample. Both programs return the same four
numeric values. The static control uses two distinct declared families; the
scoped program uses two fresh owners of one family.

| Measurement                                        | Control median | Candidate median | Median paired ratio |
| -------------------------------------------------- | -------------: | ---------------: | ------------------: |
| Static compiler, source baseline versus this slice |       19.311ms |         19.413ms |              1.0105 |
| Candidate compiler, static versus scoped program   |       19.461ms |         21.229ms |              1.0917 |
| Candidate guest, static versus scoped program      |   1.158µs/call |     1.682µs/call |              1.5084 |

Compiler samples include process loading and fresh checking/emission. Retained
and restart behavior is verified separately; these are not retained-edit
timings. Guest overhead includes both fresh owners, callbacks, exact routing,
journals and cleanup. It is about0.52µs per call on this small workload. A
direct-member shortcut removes transient operation closures created solely to
recover the provider owner; an earlier run measured1.744µs for the scoped guest.

Raw inputs, binaries, Wasm hashes, samples and distributions are recorded in
`build/bench/scoped-058/results.json` (SHA-256
`0550e1bbd7f4f174fce1736adddaac0e01dc1ff8f7a9ac9967e1571d4600275a`). The
measured candidate compiler SHA-256 is
`8d6171e91d1b113e6b6f2a490cb89f2c579b896064a974feab7c7e25bd917e20`. These
numbers qualify the earlier direct source slice, not a merged release compiler.
The later scoped-request, symbolic-factory and transfer-guard extensions have
separate source/binary pins; no additional CPU claim is made.
