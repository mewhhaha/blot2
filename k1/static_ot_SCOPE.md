# Private ordered static target metering

This bounded source-to-static-Wasm experiment extends the private ordered
static path. Its copied parser helpers charge the shared work meter before
explicit source-retention copies and selected source-derived buffer/AST
allocations. The target emitter charges before its explicit section, function,
instruction, edge and temporary-buffer operations. The independent target
checker decodes the fixed supported Wasm shape, enforces section/body bounds,
and charges before its covered node, edge and byte inspections. Both retain
one compiler-owned `ScheduledWork`, and failure returns no target bytes.

Target-byte visits are physical telemetry, not a new semantic budget: writes
and explicit reads of target/intermediate bytes are counted where performed.
Source-byte telemetry is likewise distinct from semantic visits. Tests cover
all semantic and telemetry-counter cutoffs on a small input, source-copy
failure, target flips/truncations/trailing bytes, exact baseline bytes for 120
programs, a two-page static data segment, and actual Wasm execution at O0/O2.
The checker requires a previously source-verified image; its standalone API
does not authenticate an image against source.

This is still **not a complete C09 receipt, general Wasm validator, M13
certificate, public ABI or K1 compiler admission**. Hidden vector capacity
growth, implicit language/runtime allocations and copies, some metadata
checks, F32 operations, output data comparison, generic type/layout/proof and
resource work, package dependencies and complete manifest validation are not
fully instrumented. The scheduler verifies phase order for this fixture but
cannot itself establish that every required visit was charged. Source and
work state are compiler-owned trusted inputs. The subset excludes general
static expressions, public Domain authority and most K1 language features.
