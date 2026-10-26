# Private fixed-particle frame witness

The source recognizer checks a fixed particle signature containing
`resources {depth: 2, frame: 256}`. The separately byte-checked original
module contains a fixed project wrapper and a no-call particle worker. The
scratch frame wrapper calls that project and is not the canonical M12 adapter.
It enters a 768-byte slice of a real 4KiB Wasm linear-memory arena before the
host reserves the fixture owner or copies inputs. The entry also requires an
empty fixture-owner pool. The host ends descriptors, performs checked owner
close, and only then can the Wasm leave operation restore the old frontier.
Invalid entry, active descriptors, live owners, and malformed state reject
without modifying memory. A trap does not restore the frontier; the whole
single-use instance is discarded.

The constant 768 is not a qualified M11 whole-invocation bound. The source
header's declared 256-byte frame is checked as text, but the remaining
512 bytes are a private fixed allowance: no independently checked canonical
or thin adapter, complete temporary layout, indirect result slot, call-depth
composition, or host engine-stack envelope establishes that allowance. The
source callable still accepts a tuple/Builder and returns an existential View;
it is not the canonical M12 record/Dest/Result interface. The fixed helper
byte validator and arena geometry do not certify arbitrary source, ABI, stack,
loan, frame or resource behavior. Raw owner/bitmap memory, host orchestration
and preflighted helper bodies are trusted fixture invariants.
