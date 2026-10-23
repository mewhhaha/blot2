# Opt-in derivation

`scripts/derive.ts` turns checked `type ... is data` declarations into ordinary
Blot source. It emits `Type.eq`, a `std/equality.Eq` implementation, a
`std/text.Format` implementation, and a `std/codec.Codec` implementation. The
generated module is checked again before it replaces the output file. Only types
listed in the schema manifest are derived, so a handwritten implementation can
be used instead. The compiler has no unrestricted runtime reflection.

For example, save this source as `model.blot`:

```blot
type Ticket is data = #Ticket { number: U32, active: Bool } | #Empty
```

Save `schema.json` beside it:

```json
{
  "types": {
    "Ticket": {
      "version": 1,
      "variants": {
        "Ticket": { "tag": 8, "fields": { "number": 20, "active": 10 } },
        "Empty": { "tag": 4, "fields": {} }
      }
    }
  }
}
```

Run from the repository root after building the development compiler:

```sh
deno task build:compiler:dev
deno run -A scripts/derive.ts --source model.blot --schema schema.json \
  --output model_derived.blot --blotc zig-native/zig-out-dev/bin/blotc
```

Keep the output beside the source so relative imports resolve the same way. The
command checks the input project, reads its data-declaration CST, emits source,
checks the generated project, and atomically publishes the output. Build or
import `model_derived.blot` instead of `model.blot`. The supported payloads are
nullary, scalar, product, and named record constructors. Generic type parameters
and array fields are supported. Recursive fields require handwritten operations
and receive a field-naming diagnostic. A function field likewise receives a
diagnostic naming its field and missing structural equality or formatting
operation. Other missing contract implementations are reported by the Blot
checker when the generated function is instantiated.

The default derives all three operations. A type can select any nonempty subset
with `"operations": ["equality", "debug", "codec"]` in its manifest entry.
Equality-only derivation needs no version or field IDs, and codec-only
derivation does not require a debug formatter. For example,
`"Coordinate": { "operations": ["equality"] }` derives equality for an F32
record without inventing a persisted F32 codec.

`std/codec` defines the user-extensible `Codec a` contract with `encode` and
`decode`. Its default wire format is an `Array U32`, independent of the host
numeric ABI. A derived value starts with `[version, variant_tag, field_count]`;
each field then has `[field_id, payload_length, ...payload]`. Fields are emitted
in **ascending declared ID order**, regardless of source order. Array fields
contain a count and length-framed element payloads. Decoders reject an unknown
version or tag, missing or reordered fields, incorrect lengths, trailing words,
and malformed element payloads. The standard library supplies U32 and Bool
codecs. A custom field codec can enforce domain validation:

```blot
type Positive is data = #Positive U32
impl PositiveCodec : codec.Codec Positive = {
  const encode = fn (#Positive value) => #[value],
  const decode = fn words =>
    if words.length == 1 && words[0] > 0 then #Some (#Positive words[0])
    else #Nothing,
}
```

The manifest owns persisted identity. Never renumber a published variant or
field ID just because source order changes. When the format changes, choose a
new version and author a migration that validates the old shape before
constructing a current value. For example, the executed test changes Ticket from
version 1 to 2 while reversing source field order: its v2 decoder rejects v1
words, and an explicit `migrate_v1` checks the old IDs and Bool payload, then
re-encodes a Ticket under v2. No automatic migration or semantic validation is
inferred from a declaration.

Generated `Format` output is for inspection, with constructor and field names;
it is not a stable persistence representation. Array traversal is emitted at the
source type so imported user-defined element implementations remain available
during generic specialization. The one-layer array tests cover records, generic
types, custom codecs, and malformed payloads. More deeply nested generic
collections still need explicit operation implementations when their required
contracts cannot be resolved. Record encoding computes the complete size and
writes framing and payloads into one output buffer. Array payload construction
collects words in a List before one conversion.

The TypeScript `deriveCodec(shape, schema, options)` API also accepts
`options.scalars`, a map from a scalar type spelling to named `encode` and
`decode` functions. Each encoder returns one U32 word; each decoder returns a
`Maybe` scalar. If every field in a constructor has such a mapping, its codec
emits and reads the fixed frame directly. The contract owner supplies these
operations, and the generated module still undergoes native checking. Framing,
field IDs, version checks and malformed-input rejection remain the same.
