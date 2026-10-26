# Partial instrumented static scalar helpers

This scratch experiment instruments the actual restricted scalar parser and
independent validator rather than estimating their work afterward. Before each
exposed lexer-token request, scalar AST node creation, AST child read, and
explicit scalar type observation, it charges the existing compiler-owned
`work::Meter` in the relevant phase. Parse and validation return the updated
meter to the caller. Semantic ceiling exhaustion and invalid work/phase state
have distinct private statuses, and neither publishes a scalar tree as a
successful result.

The local cache accepts one exact source per batch, constructs its own cache
from a successful cold parse and independently checked tree, and retains the
measured per-phase logical visit counts. On a cache hit it charges the same
number of visits in the same phases before reporting completion. It does not
accept a caller-supplied receipt, hash or symbolic ID as authority. Tests check
cold/warm counts and status at every cutoff around the 1,048,576 limit for
multiple expressions, plus valid, invalid and forged-meter controls. This is
not yet integrated with the optional aggregate cache or publication entry.

This is deliberately **not a complete C09 receipt**. Internal UTF-8 and lexer
scans, literal and identifier byte handling, source equality, node comparisons
beyond the explicitly charged observations, aggregate construction, scalar
execution, type/layout/proof dependencies, publication and other compiler
phases are not fully instrumented. On a cache hit the current `work::Meter`
records phase totals but not a detailed per-event transcript. Meters passed to
the helpers are compiler-owned; `work::charge` does not authenticate every
possible forged counter combination. A complete implementation must account
for all required helper traversals and preserve policy-specific logical work,
not merely add this partial count to an unmetered result.
