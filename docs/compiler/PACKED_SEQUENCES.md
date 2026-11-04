# Packed owned sequences

Design direction for `[]` and `List T`; packed variable-width elements are not
yet the production representation. Current flat Lists use fixed-stride owned
array storage. Preserve sequential building, concatenation and traversal.
`Array T` remains the collection for indexing and mutable fixed-stride rows.

## Values and construction

`List T` is immutable. A literal or comprehension builds into a private append
buffer and freezes its result. Aliases share frozen bytes. No public indexing,
element mutation, `Ref` or `Link` into a packed sequence is introduced.

Keep owner identity and lifetime evidence, a byte extent and an element count. A
cursor carries a byte position and a remaining count. Independent cursor copies
advance independently; zero-byte Unit elements advance the count. Frozen nested
views borrow their containing owner. Explicit copying is required to retain them
past that owner. No reference counting or per-element owners.

Evaluate each element once in written order. Check its complete active extent
before writing, then publish the new extent and count after the element is
complete. A failed append preserves the committed prefix. Comprehensions must
not execute twice to determine allocation size.

Use the existing planned byte regions and original temporary/persistent budgets.
Report reserved capacity separately from live encoded bytes; compact encoding
does not imply that worst-case reservation shrinks by the same amount.

## Element layout pilot

Share one encode/decode plan per concrete element type. Scalars preserve their
bits; packed loads may be unaligned. An enum has a dense tag followed by only
its selected payload: one tag byte up to 256 alternatives, two up to 65,536. Do
not reserve or clear inactive alternatives.

```blot
type Event is data =
  $Empty
  | $Point (U32, F32)
  | $Samples { channel: U32, samples: List U32 }
```

| Element    |              Encoded extent |
| ---------- | --------------------------: |
| `$Empty`   |                      1 byte |
| `$Point`   |                     9 bytes |
| `$Samples` | 13 + 4 × sample count bytes |

The Samples image is tag, channel, nested count, nested byte length, then scalar
bytes. Copy the nested frozen image into its parent; decode it as an immutable
slice of the parent's owner. Validate tags, integer overflow, complete extents
and `nested_bytes == nested_count * 4` before consuming a malformed image.

Start with scalar/inline payloads and one terminal nested scalar sequence per
alternative. Recursive shapes, arbitrary owner descriptors, callbacks,
capabilities and mutable interior references require separate designs. This
layout is private implementation detail, not a serialization or ABI promise.

## Concatenation

The contiguous pilot copies both inputs: O(total encoded bytes). Repeated
left-fold concatenation can therefore be quadratic. Literals/comprehensions and
bulk builder extension must supply a linear construction path.

An eventual chunked concatenation can avoid payload copies, but its result must
retain both input lifetimes, and its nodes, traversal depth and balancing need
bounded storage. Lack of indexing alone does not establish O(1) owned concat.

## Acceptance

Execute mixed alternatives, dynamic tails, exact F32 bits, empty/Unit sequences,
independent cursors, concatenation, capacity failure and borrowed-tail escape
rejection. Compare flat versus packed live/reserved bytes, bytes copied,
construction/decode time, emitted Wasm and compilation work. Include scalar
sequences as a regression control and keep Main measurements separate.

Goose's
[active enum image](https://github.com/mewhhaha/goose-to-wasm/blob/0d1715ceef998e65737335ee3ac88433a90672ef/docs/VARIABLE_ENUMS.md)
provides a compact-tag/active-payload reference. Its documented variable-element
and containing-owner limits mean it is not a complete sequence implementation to
copy unchanged.

## Native representation witness

`benchmarks/tools/packed_sequences.zig` is a standalone prototype, not the
production List emitter. Its five executed tests cover active alternatives,
exact F32 bits, independent cursors, copied dynamic tails, committed-prefix
capacity failure, frozen concatenation and malformed images.

```sh
zig test -fno-llvm -Osafe benchmarks/tools/packed_sequences.zig
zig build-exe -fno-llvm -Ofast benchmarks/tools/packed_sequences.zig -femit-bin=build/packed-sequences
build/packed-sequences
```

The 100,000-element 80% Empty/20% Point witness actually encodes 260,000 bytes
and decodes all entries with checksum 999,950,000. Its worst-case backing buffer
reserves 900,000 bytes. The current tag-word/max-payload layout models 1,200,000
bytes for this element schema, excluding sequence metadata. The 78.3% reduction
describes encoded element bytes; it is not a measured Blot runtime, Wasm-size or
compile-time improvement.
