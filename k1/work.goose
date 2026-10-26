// Compiler-owned required-work model. The fixture uses the compatibility
// meter, not the opt-in scheduler below. This is not a durable receipt or
// cache admission proof; see WORK_SCHEMA.md for missing required accounting.
namespace work;

// Phases 1..7: syntax, source verification, Core, proof, semantic validation,
// plan validation, and emission validation. Compatibility meters are ungated.
struct Meter {
    semantic: u32 = 0,
    proof_visits: u32 = 0,
    proof_terms: u32 = 0,
    proof_edges: u32 = 0,
    proof_peak_edges: u32 = 0,
    core_operations: u32 = 0,
    core_blocks: u32 = 0,
    phase_semantic: u32[7] = [0; 7],
    source_byte_reads: u64 = 0,
    target_visits: u64 = 0,
    // 0 compatibility, 1..7 active phase, 8 between phases, 9 failed.
    gate: u32 = 0
}

// status 0 success; 1 semantic limit; 2 proof limit; 3 Core limit;
// 4 source limit; 5 invalid event/phase; 6 instrumentation counter overflow.
// quantity 1 semantic visits, 2 proof visits, 3 proof terms, 4 proof edges,
// 5 Core operations, 6 Core blocks, 7 source bytes, 8 source-byte telemetry,
// 9 target-node telemetry.
// For a limit result `measured` is the pre-event count and `limit` the ceiling.
struct Receipt { status: u32 = 0, quantity: u32 = 0, measured: u64 = 0, limit: u64 = 0 }

fn failed_meter(m: Meter&, receipt: Receipt) -> Receipt {
    if m.gate != 0 { m.gate = 9; }
    return receipt;
}

// Events 1..13 visit syntax/token, AST node/edge, Core node/edge, type,
// effect, usage, exhaustivity, layout, constraint, plan node/edge respectively.
// Event 20 is a proof visit, 21 additionally interns a new term, and 22
// additionally adds a live fact/evidence edge. Event 30 creates a Core
// operation and 31 creates a Core block. Every event also charges one semantic
// visit. Callers charge each repeated traversal and each new node/edge.
fn charge(m: Meter&, phase: u32, event: u32) -> Receipt {
    if m.gate != 0 && m.gate != phase { return failed_meter(m, Receipt { status: 5 }); }
    if phase < 1 || phase > 7 ||
       !((event >= 1 && event <= 13) || (event >= 20 && event <= 22) || event == 30 || event == 31) {
        return failed_meter(m, Receipt { status: 5 });
    }
    // Total semantic exhaustion wins over a simultaneous specific limit.
    if m.semantic >= 1048576 {
        return failed_meter(m, Receipt { status: 1, quantity: 1, measured: m.semantic, limit: 1048576 });
    }
    if event == 21 && m.proof_terms >= 4096 {
        return failed_meter(m, Receipt { status: 2, quantity: 3, measured: m.proof_terms, limit: 4096 });
    }
    if event == 22 && m.proof_edges >= 16384 {
        return failed_meter(m, Receipt { status: 2, quantity: 4, measured: m.proof_edges, limit: 16384 });
    }
    if event >= 20 && event <= 22 && m.proof_visits >= 65536 {
        return failed_meter(m, Receipt { status: 2, quantity: 2, measured: m.proof_visits, limit: 65536 });
    }
    if event == 30 && m.core_operations >= 65536 {
        return failed_meter(m, Receipt { status: 3, quantity: 5, measured: m.core_operations, limit: 65536 });
    }
    if event == 31 && m.core_blocks >= 4096 {
        return failed_meter(m, Receipt { status: 3, quantity: 6, measured: m.core_blocks, limit: 4096 });
    }
    // Defensive bound on this compiler-owned aggregate. No arithmetic wraps
    // if a corrupted in-memory meter is accidentally passed to this function.
    if m.phase_semantic[phase - 1] > m.semantic {
        return failed_meter(m, Receipt { status: 5 });
    }
    m.semantic += 1;
    m.phase_semantic[phase - 1] += 1;
    if event >= 20 && event <= 22 { m.proof_visits += 1; }
    if event == 21 { m.proof_terms += 1; }
    if event == 22 {
        m.proof_edges += 1;
        if m.proof_edges > m.proof_peak_edges { m.proof_peak_edges = m.proof_edges; }
    }
    if event == 30 { m.core_operations += 1; }
    if event == 31 { m.core_blocks += 1; }
    return Receipt {};
}

// Opt-in ordered owner for one declaration. Compatibility callers may still
// use Meter and charge directly; those callers do not get phase enforcement.
// A phase is pending (0), active (1), complete (2), or explicitly skipped (3).
// Only proof is optional in this seven-phase scalar schedule. An empty phase
// may be ended and any event may be charged in an active phase: this schedule
// cannot establish that a phase actually did its required work. Once started,
// direct charges through the owned meter still enforce the active phase.
struct ScheduledWork {
    meter: Meter = Meter {},
    phases: u8[7] = [0; 7],
    completed: u32 = 0,
    active: u32 = 0,
    failed: bool = false
}

fn schedule_valid(w: ScheduledWork&) -> bool {
    if w.completed > 7 || w.active > 7 { return false; }
    if w.active != 0 {
        if w.meter.gate != w.active { return false; }
    } else if w.completed == 0 {
        if w.meter.gate != 0 { return false; }
    } else if w.meter.gate != 8 { return false; }
    if w.active != 0 && (w.completed == 7 || w.active != w.completed + 1) { return false; }
    for i in 0..7 {
        let state = w.phases[i];
        if i < w.completed {
            if state != 2 && !(i == 3 && state == 3) { return false; }
        } else if w.active != 0 && i + 1 == w.active {
            if state != 1 { return false; }
        } else if state != 0 { return false; }
    }
    return true;
}

// Invalid sequencing permanently fails this owner. Failed owners must be
// discarded, including after a limit failure; counters are never reset.
fn schedule_begin(w: ScheduledWork&, phase: u32) -> bool {
    if w.failed { return false; }
    if !schedule_valid(w) || phase < 1 || phase > 7 || w.active != 0 || phase != w.completed + 1 {
        w.failed = true;
        w.meter.gate = 9;
        return false;
    }
    w.active = phase;
    w.meter.gate = phase;
    w.phases[phase - 1] = 1;
    return true;
}

fn schedule_end(w: ScheduledWork&, phase: u32) -> bool {
    if w.failed { return false; }
    if !schedule_valid(w) || phase == 0 || w.active != phase {
        w.failed = true;
        w.meter.gate = 9;
        return false;
    }
    w.phases[phase - 1] = 2;
    w.completed = phase;
    w.active = 0;
    w.meter.gate = 8;
    return true;
}

fn schedule_skip_proof(w: ScheduledWork&) -> bool {
    if w.failed { return false; }
    if !schedule_valid(w) || w.active != 0 || w.completed != 3 {
        w.failed = true;
        w.meter.gate = 9;
        return false;
    }
    w.phases[3] = 3;
    w.completed = 4;
    return true;
}

fn scheduled_charge(w: ScheduledWork&, phase: u32, event: u32) -> Receipt {
    if w.failed { return Receipt { status: 5 }; }
    if !schedule_valid(w) || phase == 0 || phase != w.active {
        w.failed = true;
        w.meter.gate = 9;
        return Receipt { status: 5 };
    }
    let receipt = charge(w.meter, phase, event);
    if receipt.status != 0 { w.failed = true; }
    return receipt;
}

fn schedule_complete(w: ScheduledWork&) -> bool {
    return !w.failed && schedule_valid(w) && w.completed == 7 && w.active == 0;
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
    if m.gate >= 8 { return failed_meter(m, Receipt { status: 5 }); }
    let maximum: u64 = ~(0 as u64);
    if bytes > maximum - m.source_byte_reads {
        return failed_meter(m, Receipt { status: 6, quantity: 8, measured: m.source_byte_reads, limit: maximum });
    }
    m.source_byte_reads += bytes;
    return Receipt {};
}

// Target-format section/instruction traversal is tracked separately from the
// source semantic policy. This telemetry is not a new admission ceiling or
// a certificate; callers must independently bound byte ranges and loops.
fn target_visit(m: Meter&) -> Receipt {
    if m.gate != 0 && m.gate != 7 { return failed_meter(m, Receipt { status: 5 }); }
    let maximum: u64 = ~(0 as u64);
    if m.target_visits == maximum {
        return failed_meter(m, Receipt { status: 6, quantity: 9, measured: m.target_visits, limit: maximum });
    }
    m.target_visits += 1;
    return Receipt {};
}
