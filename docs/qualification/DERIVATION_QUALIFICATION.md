# Opt-in derivation qualification

Issue #19 is implemented as a checked source-generation tool. A manifest opts
individual data types into equality, debug formatting, codecs, or any subset.
The command checks the original project, reads its data-declaration CST,
generates ordinary Blot source, checks the generated project, and atomically
publishes the output. Equality uses the explicit `std/equality.Eq` contract;
debug output uses `std/text.Format`; codecs use `std/codec.Codec`. This keeps
the new structural contracts out of the implicit prelude. Ordinary Bool equality
is available in the prelude.

The executed-Wasm tests cover a named record, multi-variant data, scalar and
product payloads, a generic wrapper, an array of user-defined records, Bool
equality, debug output, U32 and Bool codecs, and a custom Positive codec that
rejects zero. They check exact encoded words, round trips, invalid version and
field IDs, malformed lengths, invalid Bool payloads, trailing words, and an
authored v1-to-v2 migration. A source-field reorder retains the manifest's
ascending field IDs. The generator test checks that unsupported function fields
name the field and missing operations; CLI tests check equality-only and
codec-only generation work independently. Recursive fields receive a
field-naming diagnostic; more deeply nested generic collections may need
explicit implementations. No automatic semantic validation or migration is
claimed.

The full compiler gate passed 2,506 native laws across four shards and 1,629
guest tests, including the five new derivation tests. The LLVM release build,
Zig lint (zero findings), TypeScript checks, formatting, and package dry run
passed. The 300-link generic-chain regression test also passed: the new Eq
contract lives in `std/equality` to avoid increasing the implicit prelude's
type-graph footprint. Initial population accounts for the two added Bool
methods; retained-edit budgets remain unchanged.
