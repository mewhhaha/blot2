# Private source-bound public-shaped compiler candidate

This joins a single bounded public-shaped U32 declaration to the existing
source-checked tagged scalar, finite-loop, and mixed compiler. It requires
`pub let NAME: U32 -> U32 ! {} resources {depth: D, frame: S} = ...`, a
one-physical-line header, closed U32 resource values, and 1 <= D <= 128. It
fails closed on other syntax, extra declarations, nonempty effects, and bodies
outside the existing compiler's admitted subsets. Actual unsupported body forms
and conservative proofs are documented in `compiler_schema.md`.

The candidate owns the original source, header record and complete underlying
compiler Core. Verification lexes the original source again, compares every
header field and exact caller-retained bytes, constructs a projection starting
at `let`, replacing the effect and resource clause with spaces, then checks the
entire projected body via `compiler_validate`. Projection offsets are relative
to that `let`, not original module offsets. The Wasm emitter rechecks the same
binding and passes the projected body to `compiler_wasm`; no source text is
emitted or parsed by host JavaScript. The independent caller must retain the
original immutable source; mutating the expected source together with the whole
candidate intentionally describes a different program, not authenticated origin.

The header verifier is the authoritative source recognizer for the producer,
while the existing tagged compiler has independent producer and consumer checks
on the projected body. This is a source-bound prototype, not a complete public
K1 frontend or checked interface: it does not prove declared frame/depth bounds,
effects beyond the fixed syntax, full source-to-Core origin spans, package or
module identity, portable artifacts, host ABI, C09 work limits, or publication.
The underlying Wasm export uses its fixture calling convention and is not a
public host protocol. Public check/build stay fail-closed until those independent
obligations are qualified. No claim of speed, full language support, or M12/M13
admission is made.
