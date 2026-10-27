# Partial metered scalar source scanning

This scratch slice replaces the scalar helper's source lexer with a separately
metered equivalent. Every explicit source-byte access in UTF-8 validation and
tokenization calls `work::source_read` before reading. The scalar parser and
independent verifier also meter their source-token comparisons, numeric literal
scans, retained-source comparison and identifier validation, including the
reserved-name comparisons performed by this implementation. The existing
semantic visit charges remain in place. The source byte counter measures
physical inspections and is separate from the 1,048,576 semantic-visit limit;
its U64 overflow is an internal instrumentation error, not semantic exhaustion.

A restricted repeated-identical-source test cache still replays the exact
logical semantic phase counts recorded on its cold parse and verification.
It does not replay physical byte-read telemetry for work a cache hit did not
perform. The cache is created inside the call and its receipt is not accepted
from a caller. Its scalar helper, cache and input meter are private
compiler-owned experiments, not a public API or an authenticated work receipt.

Implicit source copying/retention and allocations are not metered by these
helpers. The copied lexer and scalar paths are still incomplete as full C09
instrumentation. The aggregate parser and validator, scalar execution, type,
layout and proof dependencies, publication, other compiler passes and the
complete declaration-level phase scheduler are not all charged here. The
original optimized aggregate cache is not connected to this path. Even in this
slice `work::Meter` assumes compiler-owned counter integrity and does not
validate every forged counter combination. No full C09 qualification or
performance claim is made.
