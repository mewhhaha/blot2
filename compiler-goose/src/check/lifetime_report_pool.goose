// A report owns each typed run until its generation lease is consumed.
namespace blot_check_lifetime_report_pool;
import support.error;
import .capability_lifetimes;
type Error = blot_error::Error;
type Report = blot_check_capability_lifetimes::Report;
struct Range { start: i64 = 0, len: i64 = 0 }
struct Lease { live: bool = false, generation: u64 = 0, ranges: Range[13] = [Range {..}; 13] }
reusable var leases: Lease[>..] = [];
var next_generation: u64 = 1;
reusable[] var pool_nodes: blot_check_capability_lifetimes::Node[>..] = [];
reusable[] var pool_edges: blot_check_capability_lifetimes::Edge[>..] = [];
reusable[] var pool_mappings: blot_eval_type_evidence::Mapping[>..] = [];
reusable[] var pool_boundaries: blot_check_capability_lifetimes::Boundary[>..] = [];
reusable[] var pool_invocations: blot_check_capability_lifetimes::Invocation[>..] = [];
reusable[] var pool_evidence_nodes: blot_eval_type_evidence::Node[>..] = [];
reusable[] var pool_evidence_extra: u32[>..] = [];
reusable[] var pool_evidence_goals: blot_eval_type_evidence::QuantifierGoals[>..] = [];
reusable[] var pool_evidence_obligations: blot_eval_type_evidence::Goal[>..] = [];
reusable[] var pool_effect_operations: blot_check_effect_evidence::Operation[>..] = [];
reusable[] var pool_effect_arguments: u32[>..] = [];
reusable[] var pool_effect_rows: blot_check_effect_evidence::Row[>..] = [];
reusable[] var pool_effect_labels: u32[>..] = [];
fn own(source: Report) -> Report, Error {
    if next_generation == 0xffffffffffffffff || leases.len == 0xffffffff { return default<Report>(), Error.analysis_limit; }
    let generation = next_generation; next_generation += 1; var lease = Lease { true, generation , ..}; var result = source;
    if source.nodes.len != 0 {
        let run = pool_nodes.alloc_slice(source.nodes.len); for value, index in source.nodes { run[index] = value; }
        let first: const blot_check_capability_lifetimes::Node& = run[0]; lease.ranges[0] = Range { pool_nodes.index_of(first), run.len , ..}; result.nodes = run;
    }
    if source.edges.len != 0 {
        let run = pool_edges.alloc_slice(source.edges.len); for value, index in source.edges { run[index] = value; }
        let first: const blot_check_capability_lifetimes::Edge& = run[0]; lease.ranges[1] = Range { pool_edges.index_of(first), run.len , ..}; result.edges = run;
    }
    if source.mappings.len != 0 {
        let run = pool_mappings.alloc_slice(source.mappings.len); for value, index in source.mappings { run[index] = value; }
        let first: const blot_eval_type_evidence::Mapping& = run[0]; lease.ranges[2] = Range { pool_mappings.index_of(first), run.len , ..}; result.mappings = run;
    }
    if source.boundaries.len != 0 {
        let run = pool_boundaries.alloc_slice(source.boundaries.len); for value, index in source.boundaries { run[index] = value; }
        let first: const blot_check_capability_lifetimes::Boundary& = run[0]; lease.ranges[3] = Range { pool_boundaries.index_of(first), run.len , ..}; result.boundaries = run;
    }
    if source.invocations.len != 0 {
        let run = pool_invocations.alloc_slice(source.invocations.len); for value, index in source.invocations { run[index] = value; }
        let first: const blot_check_capability_lifetimes::Invocation& = run[0]; lease.ranges[4] = Range { pool_invocations.index_of(first), run.len , ..}; result.invocations = run;
    }
    if source.evidence.nodes.len != 0 {
        let run = pool_evidence_nodes.alloc_slice(source.evidence.nodes.len); for value, index in source.evidence.nodes { run[index] = value; }
        let first: const blot_eval_type_evidence::Node& = run[0]; lease.ranges[5] = Range { pool_evidence_nodes.index_of(first), run.len , ..}; result.evidence.nodes = run;
    }
    if source.evidence.extra.len != 0 {
        let run = pool_evidence_extra.alloc_slice(source.evidence.extra.len); for value, index in source.evidence.extra { run[index] = value; }
        let first: const u32& = run[0]; lease.ranges[6] = Range { pool_evidence_extra.index_of(first), run.len , ..}; result.evidence.extra = run;
    }
    if source.evidence.quantifier_goals.len != 0 {
        let run = pool_evidence_goals.alloc_slice(source.evidence.quantifier_goals.len); for value, index in source.evidence.quantifier_goals { run[index] = value; }
        let first: const blot_eval_type_evidence::QuantifierGoals& = run[0]; lease.ranges[7] = Range { pool_evidence_goals.index_of(first), run.len , ..}; result.evidence.quantifier_goals = run;
    }
    if source.evidence.quantifier_obligations.len != 0 {
        let run = pool_evidence_obligations.alloc_slice(source.evidence.quantifier_obligations.len); for value, index in source.evidence.quantifier_obligations { run[index] = value; }
        let first: const blot_eval_type_evidence::Goal& = run[0]; lease.ranges[8] = Range { pool_evidence_obligations.index_of(first), run.len , ..}; result.evidence.quantifier_obligations = run;
    }
    if source.evidence.effects.operations.len != 0 {
        let run = pool_effect_operations.alloc_slice(source.evidence.effects.operations.len); for value, index in source.evidence.effects.operations { run[index] = value; }
        let first: const blot_check_effect_evidence::Operation& = run[0]; lease.ranges[9] = Range { pool_effect_operations.index_of(first), run.len , ..}; result.evidence.effects.operations = run;
    }
    if source.evidence.effects.arguments.len != 0 {
        let run = pool_effect_arguments.alloc_slice(source.evidence.effects.arguments.len); for value, index in source.evidence.effects.arguments { run[index] = value; }
        let first: const u32& = run[0]; lease.ranges[10] = Range { pool_effect_arguments.index_of(first), run.len , ..}; result.evidence.effects.arguments = run;
    }
    if source.evidence.effects.rows.len != 0 {
        let run = pool_effect_rows.alloc_slice(source.evidence.effects.rows.len); for value, index in source.evidence.effects.rows { run[index] = value; }
        let first: const blot_check_effect_evidence::Row& = run[0]; lease.ranges[11] = Range { pool_effect_rows.index_of(first), run.len , ..}; result.evidence.effects.rows = run;
    }
    if source.evidence.effects.labels.len != 0 {
        let run = pool_effect_labels.alloc_slice(source.evidence.effects.labels.len); for value, index in source.evidence.effects.labels { run[index] = value; }
        let first: const u32& = run[0]; lease.ranges[12] = Range { pool_effect_labels.index_of(first), run.len , ..}; result.evidence.effects.labels = run;
    }
    let index = leases.alloc_index(lease); result.lease_index = (index + 1) as u32; result.generation = generation; return result, Error.none;
}
fn deinit(report: Report&) -> Error {
    if report.lease_index == 0 { return Error.none; } if report.lease_index > leases.len { return Error.invalid_artifact; }
    let index = report.lease_index - 1; let lease = leases[index]; if !lease.live || lease.generation != report.generation { return Error.invalid_artifact; } leases[index].live = false;
    if lease.ranges[0].len != 0 { let range = lease.ranges[0]; pool_nodes.free_slice(pool_nodes[range.start..range.start + range.len]); }
    report.nodes = [];
    if lease.ranges[1].len != 0 { let range = lease.ranges[1]; pool_edges.free_slice(pool_edges[range.start..range.start + range.len]); }
    report.edges = [];
    if lease.ranges[2].len != 0 { let range = lease.ranges[2]; pool_mappings.free_slice(pool_mappings[range.start..range.start + range.len]); }
    report.mappings = [];
    if lease.ranges[3].len != 0 { let range = lease.ranges[3]; pool_boundaries.free_slice(pool_boundaries[range.start..range.start + range.len]); }
    report.boundaries = [];
    if lease.ranges[4].len != 0 { let range = lease.ranges[4]; pool_invocations.free_slice(pool_invocations[range.start..range.start + range.len]); }
    report.invocations = [];
    if lease.ranges[5].len != 0 { let range = lease.ranges[5]; pool_evidence_nodes.free_slice(pool_evidence_nodes[range.start..range.start + range.len]); }
    report.evidence.nodes = [];
    if lease.ranges[6].len != 0 { let range = lease.ranges[6]; pool_evidence_extra.free_slice(pool_evidence_extra[range.start..range.start + range.len]); }
    report.evidence.extra = [];
    if lease.ranges[7].len != 0 { let range = lease.ranges[7]; pool_evidence_goals.free_slice(pool_evidence_goals[range.start..range.start + range.len]); }
    report.evidence.quantifier_goals = [];
    if lease.ranges[8].len != 0 { let range = lease.ranges[8]; pool_evidence_obligations.free_slice(pool_evidence_obligations[range.start..range.start + range.len]); }
    report.evidence.quantifier_obligations = [];
    if lease.ranges[9].len != 0 { let range = lease.ranges[9]; pool_effect_operations.free_slice(pool_effect_operations[range.start..range.start + range.len]); }
    report.evidence.effects.operations = [];
    if lease.ranges[10].len != 0 { let range = lease.ranges[10]; pool_effect_arguments.free_slice(pool_effect_arguments[range.start..range.start + range.len]); }
    report.evidence.effects.arguments = [];
    if lease.ranges[11].len != 0 { let range = lease.ranges[11]; pool_effect_rows.free_slice(pool_effect_rows[range.start..range.start + range.len]); }
    report.evidence.effects.rows = [];
    if lease.ranges[12].len != 0 { let range = lease.ranges[12]; pool_effect_labels.free_slice(pool_effect_labels[range.start..range.start + range.len]); }
    report.evidence.effects.labels = [];
    leases.free(index); report.lease_index = 0; report.generation = 0; report.evidence.owner_id = 0; report.evidence.effects.owner_id = 0; report.complete = false; return Error.none;
}
