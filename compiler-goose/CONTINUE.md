# Finish the Goose compiler experiment

The writing-first phase is over. Current work is to fix production lifetime
failures in coherent families, produce the complete native compiler, then
qualify CLI/project-server behavior and recoverable request OOM against Zig.
Run bounded batch checks at family boundaries rather than per-edit fixtures.
Never count source presence or a selected-root check as whole-port completion.

Keep `compiler/` and its installed binaries as the oracle. `oracle.json` pins
Zig commit `156f84b4810f630dff7e5efb7014b2194e3160f7`; the executable copy and
identity are in ignored `build/goose-port/oracle/`. New-language comparisons
must use the corresponding newer Zig candidate and pinned source inputs.
Preserve sibling checkouts and installed Goose toolchains.

Use the tracked private checker recipe. The newer selfhost Goose snapshot is
not a qualified replacement for this port's packages, reusable pools and native
host APIs. Selected-root diagnostics are partial. Normal whole builds emit C
and a host header, then compile and link the real Goose CLI with native OS
adapters. Stages remain capped at 120s and whole attempts at 300s.

The current lifetime repair replaces recursive predicate scratch borrows with
scalar pool ranges. Reusable storage remains owned until the calling frame
finishes; each recursive step reads a predicate by value. Importer callback
contexts pass their fixed borrowed fields by value. No lifetime acceptance rule
is weakened. The proof/resolver, scalar metadata, sort and diagnostic transfer
families are repaired. The source/global-reference validator batch adds 21 AST
cursors and removes 14 span aliases. Combined selected checking hit120.301s
with no error and is incomplete; split engine checking is pending.
Six isolated production engine families execute. Current results and the next frontier belong in root CONTINUE.md
and pinned qualification receipts.

Native request rollback and runtime observation components are tested; their
whole compiler integration remains unqualified. A
committed worker forks a candidate before reading each request; only a complete
staged reply can adopt it. Explicit allocation failures discard the candidate
and retain the committed heap. Generic panics and signals are not OOM. Coverage
must distinguish observed pool operations, reserved capacity and RSS; unavailable
live/scratch counts must stay explicitly unavailable.

Retained contexts now use canonical typed metadata and fixed pooled buffers.
Lexical contexts may borrow caller-owned tables. Arrays cannot
become multiple owning fields in one Goose record. Backend Function/Signature
records use ranges into Module tables. Owner identities are fresh process-local
u64 values, not pointer casts; zero declines optional cache authority. Marks,
rollback, source checking and private proof ownership remain distinct.

`support/error.goose` owns explicit trailing Error results and original wire
error names. `support/option.goose` contains only fixed optional values. Native
adapters supply scalar bit representations, OS byte I/O, clocks and atomics;
they do not compile or interpret Blot or Zig.

The local Goose specification is in
`../goose-to-wasm/build/source/docs/goose_spec.md`; the live sibling is under
independent development. Its current bootstrap has gaps around native threads,
encoded references, recoverable allocation and source-package imports. Preserve
the requested source contracts and record gaps; choose and qualify the Goose
toolchain after writing. Do not work around gaps by weakening Blot checks,
forwarding compilation to Zig, or inserting placeholder successes.
