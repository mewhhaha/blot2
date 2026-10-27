# Private U32-to-Bool lexical scalar prototype

This scratch-only frontend admits `let NAME: U32 -> Bool = fn PARAM => do:`
with the existing unified scalar subset's U32 lexical locals, comparisons,
short-circuit Bool expressions, explicit if/return, checked and wrapping U32
operations. Returns must be Bool; locals remain U32. Exact source, scope and
completion are replayed independently. A returned Bool expression is checked
using the existing branch/short-circuit proof machinery, not numeric-value
checking; each evaluated checked addition still needs independently replayed
source/edge/alias evidence. Both sides of a pruned branch retain source and
type validation. Unsupported syntax fails closed.

The six `predflow_` source files are isolated clones of the unified frontend,
shape, proof producer, independent evidence consumer, check and emitter. They
use the same immutable source/Core schema but are not a general common typed
IR or public signature path. Their output is private fixture Wasm with a raw
U32 argument and canonical Bool result. The ordinary emitter independently decodes the fixed target against the
source-bound checked Core before returning bytes; this is not general Wasm or
M13 certification. No full finite-fact engine, C09, effect/resource verification, M13, host
ABI, artifact authorization, compiler-speed or public admission claim follows.
