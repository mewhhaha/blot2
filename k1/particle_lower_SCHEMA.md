# Private particle-expression lowering scope

This experiment accepts one fixed F32 particle declaration and finite carry
loop shape. Its two row fields may contain bounded expressions over
`source[i].x`, `.y`, `.vx`, `.vy` and `dt`, with `+`, `*` and parentheses.
The independently written recognizer reconstructs the exact source-linked
postorder operations and the fixed precondition, invariant and transition
records. It does not authenticate the caller-supplied symbolic context or
implement general K1 source, type, proof, effect, resource, ownership or loan
admission.

The emitted private worker consumes a separately prepared zero-length builder.
It performs no placement or helper calls, uses scalar F32 loads and separate
`f32.mul`/`f32.add` instructions, evaluates both row arguments before any
output store, and publishes the initialized length after both fields are stored. The setup and preflight wrapper use a
flattened test ABI, and their fixed bodies are compared with a previously
reviewed trusted fixture. The final byte checker independently reconstructs the
worker from checked expression nodes. Raw owner/bitmap integrity, distinct
backing, input initialization, exclusive output and ended loans are trusted
fixture preconditions; this is not a public K1 ABI or M13 certificate.

The Node execution witness compares ordinary arithmetic results against an
independent operation-by-operation F32-rounding reference, including signed
zero, infinity and arithmetic NaN cases. For arithmetic NaNs it checks only
that the result is a NaN; **it does not validate the complete permitted NaN
payload and sign propagation set**. A separate pure field-copy control checks
bit preservation for selected noncanonical NaN and signed-zero inputs, but
those samples do not close the arithmetic NaN gap. No complete F32 or I08
qualification is claimed. See `particle_lower_test.mjs`,
`particle_lower_verify_test.goose` and `particle_lower_target.goose`.
