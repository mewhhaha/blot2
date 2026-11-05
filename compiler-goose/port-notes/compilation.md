# Compilation repair frontier

The user explicitly requested fixing and recompiling the port. Verification is
active; there is no remaining approval or source-writing barrier. Keep the Zig
compiler, normal toolchain, saved oracle and siblings unchanged.

Checkpoint `19615dbbf029b1eada6ac7f8139045f2227ef03a` is pushed to main. It repairs
parsing and many ownership APIs; it is not a successful full compiler build.
Upstream Goose parses roughly 35,700 declarations across 435 files in about
1.1 seconds. Whole-program type checking has not completed successfully.

Use `python3 compiler-goose/tools/check_source.py --phase check --log NAME`.
The runner caps and kills the process group and saves full diagnostics under
`build/goose-port/verification/`. Check mode uses streaming text diagnostics;
JSON diagnostics buffer until completion and hid errors in capped runs.
Check mode stops the process group after the first error, keeping failed
iterations near two seconds. One coordinator runs whole-program checks at a
time; checker currently owns this loop while errors remain in its files.

The actual build entry remains `compiler-goose/build.py`, with explicit Goose
binary, standard-library directory and 30-second stage caps. Do not claim a
working compiler until C emission, linking and execution have succeeded.

The latest official check advanced past the optimizer to semantic worker slice
defaults (check31, 2.669 seconds). Optimizer growing instruction views now pass
through analysis helpers rather than being stored in analysis records; module
copy-coalescing inputs use numeric tape ranges. Whole-program parsing passes
after this batch (35,775 declarations, 435 files, 1.102 seconds).
Scoped tests pass for lexer, interning, graph
SCCs, arena ownership, byte/hash/JSON helpers, maps and buffers, wire/IR emission,
native JSON and WGSL fixtures. A fresh exact C-host startup probe passes with
the unchanged native shim and official runtime. The newer coalescing executable
probe hit its 30-second emission cap with no diagnostics; execution is pending.
Saved probe sources/commands/logs are under
ignored `build/goose-port/`; these do not qualify the whole compiler.

Canonical ownership repairs include explicit typed empty slices, finite lazy
JSON/packet adapters, enum aliases qualified to original definitions, safe
pool free/reallocation receipts, numeric process-local owner slots, pooled
planning/query buffers and ordered bootstrap globals. Copied packets omit the
new process-local Chunk/Loops/Auxiliary slot fields.

Astra's private toolchain experiment is isolated under
`build/goose-port/fast-goose/`. The first candidate hash is
`b493cdeac83a1833d645503cf5eeb7d5d5f1c32ffa64ee9634719480fa7502b3`.
Readiness hash traversal plus successful-graph descendant caching passes 12
actual-header laws, 37 differential frontend fixtures and eight runtime laws.
Neither this candidate nor a second private global-narrowing experiment
demonstrated a whole-Blot timing win within matched 30-second caps. Neither
experiment is accepted into the toolchain. Keep the installed compiler and
upstream checkout intact.

Runtime recoverable physical OOM and retention parity remain separate known
production requirements; null/unavailable metrics do not close them.
