# Runtime text qualification

Issue #20 adds ordinary string literals with the `Text` representation `Array U32`.
Elements are Unicode scalar values; length, indexing and slicing count scalars.
The compiler decodes UTF-8 source literals into Core array constants. `std/text`
provides exact scalar-sequence equality, concatenation, a List-backed builder,
join, decimal U32 and bounded fixed F32 formatting, and an extensible `Format`
contract. `Text` is an alias, so callers should validate arrays crossing a trust
boundary with `text.from_scalars` or the JavaScript host adapters. No implicit
normalization or IO is introduced, and the numeric ABI is unchanged.

The executed guest test covers empty text, CJK and emoji literals, combining
marks versus precomposed scalars, text in arrays, 8,193-character builder output,
U32 boundary values, fixed F32 formatting and invalid values, a user-defined
`Format` instance, a dynamic assertion message sent through an explicit Foreign
callback, a Unicode host round trip, and malformed external scalar rejection.
The native Core law covers UTF-8 lowering and empty literals under the full
allocation-failure sweep. Public `encodeText` and `decodeText` adapters reject
unpaired UTF-16 surrogates and invalid Unicode scalars.

The full compiler gate passed 2,506 native laws across four shards and 1,624
guest tests. The LLVM release build, package extraction, Zig formatting, Deno
formatting, `git diff --check`, and Zig lint (zero findings) passed. The guide
documents representation, indexing units, validation, host transport, and the
cost of repeated concatenation. The builder test confirms an 8,193-scalar
result within 2 MiB of guest memory; it is a bounded functional check, not a
general performance claim.
