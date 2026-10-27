# Private joined driver fixture

`joined-fixture ENTRY [--trace]` is an experimental local driver for the
bounded public-shaped U32 scalar/finite-loop subset described by
`joined_public_SCOPE.md`. The driver reads at most 16 MiB, parses and
independently replays the exact original source and checked body, and writes a
hex-encoded fixture Wasm module only after success. Unsupported or invalid
input fails without stdout. Existing public `check` and `build` remain gated.

The target association gate independently decodes the fixed fixture Wasm
against the original checked source and Core; it does not re-run the emitter.
It is a bounded checker, not a general M13 certificate. See
`joined_target_SCOPE.md` for the supported instructions and limitations.
It does not use retained session reuse or grant package, artifact, public ABI,
resource, C09, capability or M13 authority. Its fixture Wasm exports are not a
public host protocol. Source ownership depends on the caller retaining the
exact immutable original source during checking and emission.
