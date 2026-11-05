// Predicate owner records are sorted exact graph handles.
namespace blot_check_quantifier_goals;
import check.types;
import support.error;

import std;
fn get(records: const blot_check_types::QuantifierGoals[:], obligations: const blot_check_types::Obligation[:],
       owner: blot_check_types::Id) -> const blot_check_types::Obligation[:] {
    var low: i64 = 0; var high = records.len;
    while low < high {
        let middle = low + (high - low) / 2;
        let record = records[middle];
        if record.owner < owner { low = middle + 1; }
        else if record.owner > owner { high = middle; }
        else { return obligations[record.goals.start..record.goals.start + record.goals.len]; }
    }
    return obligations[..0];
}
fn sameHead(a: blot_check_types::Obligation, b: blot_check_types::Obligation) -> bool {
    return a.kind == b.kind && a.name == b.name && a.operator == b.operator &&
        a.identity.unit == b.identity.unit && a.identity.decl == b.identity.decl;
}
fn sort(records: blot_check_types::QuantifierGoals[:]) {
    // Stable insertion sort keeps canonical equal-owner diagnostics deterministic.
    for i in 1..records.len {
        let record = records[i]; var j = i;
        while j > 0 && records[j - 1].owner > record.owner { records[j] = records[j - 1]; j -= 1; }
        records[j] = record;
    }
}
fn validate(nodes: const blot_check_types::Node[:], records: const blot_check_types::QuantifierGoals[:],
            obligations: const blot_check_types::Obligation[:]) -> blot_error::Error {
    var remaining: i64 = 65536;
    return validateWithBudget(nodes, records, obligations, remaining);
}
fn validateWithBudget(nodes: const blot_check_types::Node[:], records: const blot_check_types::QuantifierGoals[:],
                      obligations: const blot_check_types::Obligation[:], remaining: i64&) -> blot_error::Error {
    var previous: u32 = 0; var claimed: i64 = 0;
    for record in records {
        if remaining == 0 { return blot_error::Error.invalid_artifact; }
        remaining -= 1;
        if record.owner == 0 || record.owner <= previous || record.owner >= nodes.len { return blot_error::Error.invalid_artifact; }
        previous = record.owner;
        let node = nodes[record.owner];
        if node.tag != blot_check_types::Tag.forall && node.tag != blot_check_types::Tag.existential { return blot_error::Error.invalid_artifact; }
        if record.goals.len == 0 || record.goals.len > 4096 || record.goals.start > obligations.len ||
           record.goals.len > obligations.len - record.goals.start { return blot_error::Error.invalid_artifact; }
        if record.goals.start != claimed { return blot_error::Error.invalid_artifact; }
        if claimed > 0x7fffffffffffffff - (record.goals.len as i64) { return blot_error::Error.invalid_artifact; }
        claimed += record.goals.len;
        for goal in obligations[record.goals.start..record.goals.start + record.goals.len] {
            if remaining == 0 { return blot_error::Error.invalid_artifact; }
            remaining -= 1;
            if goal.ty >= nodes.len || goal.other >= nodes.len || goal.result >= nodes.len || goal.signature >= nodes.len {
                return blot_error::Error.invalid_artifact;
            }
        }
    }
    if claimed != obligations.len { return blot_error::Error.invalid_artifact; }
    return blot_error::Error.none;
}
