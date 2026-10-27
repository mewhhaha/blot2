# Private joined driver fixture

`joined-fixture ENTRY [--trace]` is an experimental local driver for the
bounded public-shaped U32 scalar/finite-loop subset described by
`joined_public_SCOPE.md`. The driver reads at most 16 MiB, parses and
independently replays the exact original source and checked body, and writes a
hex-encoded fixture Wasm module only after success. Unsupported or invalid
input fails without stdout. Existing public `check` and `build` remain gated.

The target association gate checks the exact bytes against deterministic
re-emission from the same checked original source and Core. It detects
mismatched or modified target bytes but reuses the same emitter: this is not an
independent semantic target validation or a certificate. The current driver
emits twice to perform that comparison; it is not a compilation-speed claim.
It does not use retained session reuse or grant package, artifact, public ABI,
resource, C09, capability or M13 authority. Its fixture Wasm exports are not a
public host protocol. Source ownership depends on the caller retaining the
exact immutable original source during checking and emission.
