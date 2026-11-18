# Packed lists of Gdev intents

Gdev's pile-handle benchmark produced 144 Idle and 144 Collect intents across
the six workers' incoming and outgoing plans. The sequence comes from executing
the Blot fixture for pile counts 2, 8 and 64. The main game does not use this
candidate planner. A separate balanced control exercises Deliver and Rest too.

| Wasm layout | Bytes per intent | Tags only | All fields | Concatenate |
| --- | ---: | ---: | ---: | ---: |
| Fixed 32-bit tag and maximum payload | 20 | 23.7 µs | 214.6 µs | 29.4 µs |
| Inline byte tag and variable payload | 9 | 202.4 µs | 250.6 µs | 14.3 µs |
| Separate byte tags and packed payloads | 9 | 20.0 µs | 200.4 µs | 13.6 µs |

Times cover 65,536 elements. An inline tag makes even a tag-only scan depend
on the previous element's payload width. The separate tag buffer lets Wasm
read those tags sequentially. For the balanced control the separate layout
uses 7 bytes per intent and scans all fields in 183.1 µs. Fixed-width storage
takes 214.5 µs. The byte counts cover list contents, excluding allocator and
owner headers.

Run `deno run -A benchmarks/intent/run.ts` from the Blot root with the Gdev and
Ink siblings present. The driver builds the actual Gdev fixture with a source
overlay to collect the input. Clang compiles three kernels to Wasm to isolate
layout cost. Each timing is the median of nine rotated rounds in V8. Each round
warms the kernel and checks 100 results. Concatenation copies two spans in
reverse order and checks the resulting sequence with an order-sensitive hash.

These measurements support a split representation for sequential lists of
varying-width cases. Blot still emits its existing fixed-stride list layout.
The experiment does not measure building persistent lists by repeated append,
shared tails or growth of a tag and payload pair. [Raw measurements](../evidence/measurements/2026-11-18-intent-layout.json)
