// Standalone, compiler-owned required-work model. This is not yet connected to
// the fixture compiler and is not a durable receipt or cache admission proof.
// Event numbering and token charging are proposals; see WORK_SCHEMA.md. This
// model does not yet count type-graph size, nesting, binders, static work,
// source nesting, or enforce phase order. `proof_edges` is monotone here:
// scope-aware discharge and a separate peak count are not implemented, so it
// can over-reject and must not be used to claim K1 required-policy compliance.
namespace work;

// Phases 1..7: syntax, source verification, Core, proof, semantic validation,
// plan validation, and emission validation. This model does not enforce phase
// order; its caller must use the fixed required schedule for every build mode.
struct Meter {
    semantic: u32 = 0,
    proof_visits: u32 = 0,
    proof_terms: u32 = 0,
    proof_edges: u32 = 0,
    core_operations: u32 = 0,
    core_blocks: u32 = 0,
    phase_semantic: u32[7] = [0; 7],
    source_byte_reads: u64 = 0
}

// status 0 success; 1 semantic limit; 2 proof limit; 3 Core limit;
// 4 source limit; 5 invalid event/phase; 6 instrumentation counter overflow.
// quantity 1 semantic visits, 2 proof visits, 3 proof terms, 4 proof edges,
// 5 Core operations, 6 Core blocks, 7 source bytes, 8 source-byte telemetry.
// For a limit result `measured` is the pre-event count and `limit` the ceiling.
struct Receipt { status: u32 = 0, quantity: u32 = 0, measured: u64 = 0, limit: u64 = 0 }

// Events 1..13 visit syntax/token, AST node/edge, Core node/edge, type,
// effect, usage, exhaustivity, layout, constraint, plan node/edge respectively.
// Event 20 is a proof visit, 21 additionally interns a new term, and 22
// additionally adds a live fact/evidence edge. Event 30 creates a Core
// operation and 31 creates a Core block. Every event also charges one semantic
// visit. Callers charge each repeated traversal and each new node/edge.
fn charge(m: Meter&, phase: u32, event: u32) -> Receipt {
    if phase < 1 || phase > 7 ||
       !((event >= 1 && event <= 13) || (event >= 20 && event <= 22) || event == 30 || event == 31) {
        return Receipt { status: 5 };
    }
    // Total semantic exhaustion wins over a simultaneous specific limit.
    if m.semantic >= 1048576 {
        return Receipt { status: 1, quantity: 1, measured: m.semantic, limit: 1048576 };
    }
    if event == 21 && m.proof_terms >= 4096 {
        return Receipt { status: 2, quantity: 3, measured: m.proof_terms, limit: 4096 };
    }
    if event == 22 && m.proof_edges >= 16384 {
        return Receipt { status: 2, quantity: 4, measured: m.proof_edges, limit: 16384 };
    }
    if event >= 20 && event <= 22 && m.proof_visits >= 65536 {
        return Receipt { status: 2, quantity: 2, measured: m.proof_visits, limit: 65536 };
    }
    if event == 30 && m.core_operations >= 65536 {
        return Receipt { status: 3, quantity: 5, measured: m.core_operations, limit: 65536 };
    }
    if event == 31 && m.core_blocks >= 4096 {
        return Receipt { status: 3, quantity: 6, measured: m.core_blocks, limit: 4096 };
    }
    // Defensive bound on this compiler-owned aggregate. No arithmetic wraps
    // if a corrupted in-memory meter is accidentally passed to this function.
    if m.phase_semantic[phase - 1] > m.semantic {
        return Receipt { status: 5 };
    }
    m.semantic += 1;
    m.phase_semantic[phase - 1] += 1;
    if event >= 20 && event <= 22 { m.proof_visits += 1; }
    if event == 21 { m.proof_terms += 1; }
    if event == 22 { m.proof_edges += 1; }
    if event == 30 { m.core_operations += 1; }
    if event == 31 { m.core_blocks += 1; }
    return Receipt {};
}

// Input byte ceiling. The bounded reader may inspect one extra byte to detect
// overflow in a stream; it must never grow the source buffer beyond this cap.
fn source_size(bytes: u64) -> Receipt {
    if bytes > 16777216 {
        return Receipt { status: 4, quantity: 7, measured: bytes, limit: 16777216 };
    }
    return Receipt {};
}

// Counts actual source-byte inspections separately from semantic visits; no
// new admission ceiling is implied. Source buffer limits and bounded-pass
// algorithms remain the caller's responsibility. Counter overflow is an
// internal instrumentation failure, never a source-limit diagnostic.
fn source_read(m: Meter&, bytes: u64) -> Receipt {
    let maximum: u64 = ~(0 as u64);
    if bytes > maximum - m.source_byte_reads {
        return Receipt { status: 6, quantity: 8, measured: m.source_byte_reads, limit: maximum };
    }
    m.source_byte_reads += bytes;
    return Receipt {};
}
