# Continue the Goose compiler experiment

Repair ownership in coherent families, build the **actual native Goose compiler**,
then qualify CLI/server behavior, retained revisions and recoverable request OOM
against Zig. **No whole C/header/executable exists yet.** Do not forward to Zig or
substitute component tests for integrated qualification.

## Current evidence

All **30 production helper laws pass together in 221.34s** on the private
copied-argument checker. They emit C, link and execute real production code. Exact
input closures, compiler and native objects are pinned in
[the complete receipt](benchmarks/evidence/qualification/2026-11-10-goose-complete30.json.gz).
These are helper laws, not whole-compiler qualification.

Current source uses existing named pools and owner journals:

- Inputs, overlays, Pattern stores, retained seeds and SessionTables use checked
  scalar keys. Shared sessions retain original catalog table authority and
  explicitly reborrow header, published or worker module runs.
- Value spellings are ranges into the existing metadata byte arena. Value and
  Root are fully scalar; two redundant retention name copies are removed.
- Thirteen maps with local APIs have nominal descriptors. Fifteen maps using the
  generic interface retain its shared descriptor. Their layouts are unchanged.
- Effect evidence transfers all six buffers and both bucket maps through exact
  registered runs. Its nonempty move/source cleanup/Frame/readback law passes.
- Ordinary and copied-packet Checked publication, Prepared/seed admission,
  diagnostic ownership, nested type cursors and query-table growth have executed
  laws. Source retains 49 alias guards; no project graphs are cloned.

Whole 115 reaches GoalContext defaults and semantic Outcome publication in
135.30s without artifacts; both families now have executed controls. Worker and
archive headers reborrow their existing owner journals. Persisted retains only
its scalar Frozen owner, removing three duplicate metadata allocations; alias
prefixes now copy into the same owner as their canonical roots.

Use `check_engines.py --engines scoped` for strict backend discovery: about 19s
per check. It constructs deliberately invalid empty Core and is **check-only**.
It does not qualify runtime behavior or omitted frontend/server bodies. Current
frontier: recursive child Generator emission changes the recursive reference root
(scoped131, 19.68s). Astra is testing parent/child context save/restore at the same
address, without weakening the checker.

Specialization key lookup now compares evidence contents. An actual native
witness reproduced lookup failure after copying identical evidence; the new law
checks admission deduplication, candidate chains, rollback and wrapped hash
collisions. Map deletion has one owner-aware API; all 78 production call sites
supply their existing named pool. No extra pool or compatibility overload.

Whole builds stop 3s after the first diagnostic. Repair checks cap at 120s; final
emission may use 180s within a 300s build budget. Do not extend caps to hide slow
or unfinished checks. Off-tree bulk-error experiments remain unpromoted.

Current and historical exact-candidate evidence is in
[the completion frontier](benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json).
An interrupted inventory is incomplete, even if its completed laws pass.

## Private checker

The optional copied-argument-contents layer preserves incoming by-value record
contents without making storage identity exact. Independent review, 21 focused
lifetime controls, 3 executed positives, 24 existing semantic/runtime controls and
24 empty-holder parity cases pass. Deep/reference reads and recursion remain
conservative. The installed Goose compiler and qualified678 binary are unchanged.

Recipe: `compiler-goose/tools/build_goose_checker.py --copied-argument-contents`
requires the complete `--global-reach-trace` recipe. The measured binary is
`build/goose-port/argcopy-experiment-20261110/goose`, SHA256
`c2b24b697acfff54f5e89fb7eeb024fc2e528ff46e7582faf7714662d3067632`.
The tracked patch reproduces its exact 108-file source without another compiler
build. See [the tooling receipt](benchmarks/evidence/qualification/2026-11-10-goose-copied-argument-contents.json.gz).
Newer independent Goose releases are not automatically qualified for this port.

## Remaining qualification and contracts

Keep ABI 8, session 2, explicit owners/copies and invocation-local borrows. Language
tasks remain retired; copied-packet host workers remain. Current syntax is
`func`, explicit `return`, curried `->`, `$Constructor`, Boolean primitives and
`#[...]` arrays. Preserve compiler/, the Zig oracle and sibling source/assets.

`qualify_compiler.ts` has eight matching-language Zig oracle baseline passes and
an exact unsupported ABI 8 recursion witness. It has **not run against Goose**.
Native request supervisor/transport/cache components pass normal and sanitizer
controls with a fake compiler entry; actual compiler OOM/retry/retention remain
pending. Live payload/capacity/scratch counts are unavailable, never invented zero.

The required Zig full gate is incomplete: all 2,974 laws compile without LLVM,
but the LLVM release phase hit 120s and cancelled execution after 94 native laws
and 65 full allocation sweeps. Smoke/harness and zero-finding Zig lint pass.
Zig source is unchanged; do not repeat that expensive release build per Goose edit.

The named-function source migration across std/Ink/Gdev is checkpointed. Its
[exact source/API qualification](benchmarks/evidence/qualification/2026-11-08-named-source-migration.json)
does not qualify a fresh Main/frame. Full release, original-export and Gdev Main
qualification remain pending. Historical Main measured 9,203,613B and 5.523s on
its pinned older release, with no reliable compile gain; subsecond compilation
and 1–2MB output remain unmet.

Preserve the remaining language RFC and performance requirements in
[tasks/STORAGE_REWRITE.md](tasks/STORAGE_REWRITE.md) and
[docs/language/NEXT_MIGRATION.md](docs/language/NEXT_MIGRATION.md).
Earlier detailed checkpoints remain in
[the preceding handoff](https://github.com/mewhhaha/blot2/blob/17eb9d04ad20a9c6caf245b4b1142ee9bafa0b1a/CONTINUE.md).
Environment publication and upstream issue/comment changes require explicit
requests. Use Astra for concrete snags; never Terra.
