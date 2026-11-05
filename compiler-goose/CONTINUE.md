# Write the complete Goose port before verification

The user requests a 1:1 experimental port in idiomatic Goose, keeping Zig as
the oracle. **Do not compile, execute, test, lint or format-check the port until
all production code is written.** Source inspection and writing are the current
phase. Never count file presence as algorithm completion or claim parity.

`oracle.json` pins Zig commit `156f84b4810f630dff7e5efb7014b2194e3160f7`,
all native sources and the installed compiler. An executable copy and its
identity are in ignored `build/goose-port/oracle/`. Leave `compiler/`, its
installed binaries and the sibling checkouts intact.

The source is about 183k production lines. The root module will be
`src/main.goose`. Each source module retains its Zig filename and uses a flat
namespace `blot_<area>_<filename>`. Use Goose's `namespace::name`, dotted
package-root imports (`import check.types;`) and file-relative peer imports
(`import .effects;`). Imports create no namespace or alias.

Current writing ownership:

- `goose_syntax_port`: parse/eval first passes; now archive codecs and optimized bodies.
- `goose_language_mapping`: check first passes complete; now artifact fragment and constant replay.
- `goose_backend_port`: all 125 backend modules.
- Root: all reuse/runtime modules, support primitives, driver and packaging.

Progress and exact constructor/API decisions belong in the agents' port notes.
The writing phase is unfinished; no verification has run.

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

Source-only writing checkpoint: see source-correspondence.json and port-notes/
for explicit completed writing passes, WIP and required unwritten modules. The
whole port remains unwritten and verification_started remains false. All normal
Zig compiler files and binaries remain the oracle and default.
