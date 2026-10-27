# Partial metered static aggregate-to-image experiment

This scratch path performs the private tuple-array subset's actual aggregate
parse, independent source replay, scalar evaluation and source/image
verification with one compiler-owned `work::Meter`. It uses the metered lexer,
identifier and scalar helpers, charges explicit aggregate and scalar node,
edge, type and image-layout observations before their accesses, and records
physical source-byte reads separately. Static primitive steps and produced
bytes remain under the existing per-declaration budget. Failures do not return
an image or partial data.

The verifier can use two local exact-source/type scalar-check slots. Each hit
replays the successful cold scalar parser/validator's phase-1 and phase-2
semantic visit totals against the same ceiling before proceeding. Source-byte
telemetry counts physical reads rather than simulated cache misses. The slots
are created inside a single verification, with no caller-supplied receipts.
Cold and cached paths are tested at every cutoff around the 1,048,576 semantic
limit and against the existing private evaluator and source/image verifier.

This does **not** implement or certify complete C09. The current meter records
phase totals, not the original per-event transcript, and the prototype uses a
compatibility meter that permits phase re-entry; it is not the ordered owner
or a durable policy receipt. Some metadata checks, source-copy and allocation
internals, runtime F32 helpers, output-copy operations, generic type/layout,
proof and resource traversals, Wasm target verification, manifest/publication
and other declaration/module work remain unmetered. It does not connect the
optional public-facing cache, authenticate `Domain`, or provide public K1
admission. Meters are trusted compiler-owned state; `work::charge` does not
validate every forged-counter combination. Fixing all required traversals and
phase/dependency accounting is necessary before calling this a C09 receipt.
