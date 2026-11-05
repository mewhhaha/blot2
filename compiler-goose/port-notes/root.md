# Support, runtime and retained-state source pass

Writing only. No port build, compiler check, test, lint, formatter or execution
has run. Zig source, installed binaries and the default toolchain remain intact.
`source-correspondence.json` records author-reported writing status; it proves
neither API integration nor parity.

Root-owned production algorithms now have first writing passes:

- Runtime guest storage, roots, cycles, region/cohort ownership, RC, lists,
  data stacks, cleanup, requests, resources, tasks and ABI emitters.
- Reuse receipts, principal/constant queries, artifact capture/import/replay,
  immutable catalog admission, validation images and packed row-use proofs.
- Frozen Core bounds, graph and scope validation; exact structural streams,
  Wyhash, Blake3, SHA256, typed payload journals and complete Core packets.
- Dependency bundles, loaders/consumers and CLI admission; retained revision
  prepare/commit/discard, source completion, restart cache and project server.
- Provider specialization, runtime identity, memory-profile Wasm observers,
  backend checkpoints, copied process workers and phase/worker profiling.

Representation contracts:

- Retained contexts and recursive scratch use typed canonical pools, numeric
  generation-checked handles and explicit release. Recursive calls retain no
  locally growing array owners. First writing passes do not qualify this law.
- Core headers borrow immutable table storage pinned by payload journals.
  Exact header-storage identity guards reuse; structural digests exclude local
  owner tokens and derived package payloads.
- Compilations stage input pins before entering the backend. Completed Results
  own byte buffers; capture transfer precedes detach/release of a workspace.
- A process-local nonzero allocation-owner identity replaces Zig allocator
  pointer/vtable identity. Unknown zero declines reuse.
- Worker requests copy complete immutable inputs into independent Goose OS
  processes. The private framed protocol is version 2 with an inference budget,
  schema/value bounds and content digest. No Zig compilation callback or silent
  serial replacement is used. Public project protocol remains version 1;
  guest ABI 8/session 2 and original guest memory budgets remain unchanged.
- Source-shaped JSON keeps custom projections, finite enum adapters and fixed
  array handling. `tools/write_json_adapters.py` authors these overloads without
  invoking a compiler or claiming verification.

Remaining qualification:

- All algorithm owners have reported first passes. Verification stays deferred
  pending clarification of whether runtime recovery must precede acceptance.
  The five earlier backend leaves also have explicit reconciled writing reports.
- Select the Goose toolchain, then bound source acceptance/build iterations.
  Verify imports, constructors, references, schema codecs and ownership rules.
- Qualify CLI/session behavior and differential source/output/diagnostics against
  the pinned Zig oracle before changing the default toolchain.
- Allocation instrumentation and native allocator-fault parity are unavailable;
  see `runtime-adaptation.md`. Pool retention and recovered OOM need evidence.
- Measure compile time, Wasm size, runtime and retained edits on fingerprinted
  identical workloads. The source port has no measured performance result.
