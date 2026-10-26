import os;
import catalog;
import session_retained;
import wasm_scalar_validation;

fn set(observations: session_retained::Observations&, index: i64, kind: u32,
       key: u8[:], found: bool, value: u8[:]) {
    assert(index >= 0 && index < 16 && key.len > 0 && key.len <= 64 && value.len <= 128);
    observations.values[index] = session_retained::Observation { kind: kind, key_len: key.len as u32,
        found: found, value_len: value.len as u32 };
    for b, i in key { observations.values[index].key[i] = b; }
    for b, i in value { observations.values[index].value[i] = b; }
}
fn main() {
    let source = "let identity: U32 -> U32 = fn x => return x\n";
    let policy = catalog::semantic_policy();
    var observations = session_retained::Observations { count: 3 };
    set(observations, 0, 1, "callee", true, "contract1");
    set(observations, 1, 6, "optional_provider", false, "");
    set(observations, 2, 8, "semantic_policy", true, policy);
    var session = session_retained::Session {};
    var cold = session_retained::compile(session, source, observations, policy, "", 0);
    assert(cold.status == 0 && !cold.reused && cold.retained && cold.bytes.len > 0);
    assert(session.generation == 1 && session.fresh_runs == 1 && session.hits == 0);
    let baseline = copy(cold.bytes);
    let semantic = cold.semantic; assert(semantic > 0 && cold.proof_visits == 0);
    assert(cold.validation_semantic > 0 && cold.validation_target_visits > 0);
    var warm = session_retained::compile(session, source, observations, policy, "forged zero-work receipt", 0);
    assert(warm.status == 0 && warm.reused && warm.retained && warm.bytes[..] == baseline[..]);
    assert(warm.semantic == semantic && warm.validation_semantic == cold.validation_semantic &&
        warm.validation_target_visits == cold.validation_target_visits &&
        session.generation == 1 && session.fresh_runs == 1 && session.hits == 1);
    assert(write_file("session_retained.wasm", warm.bytes));
    // Returned bytes are a new owner, not a mutable lease to the sealed entry.
    warm.bytes[0] ^= 1;
    let second = session_retained::compile(session, source, observations, policy, "", 0);
    assert(second.reused && second.bytes[..] == baseline[..] && session.fresh_runs == 1 && session.hits == 2);
    // A formerly absent provider becoming present invalidates the observation,
    // including when its current value is empty.
    observations.values[1].found = true;
    let added = session_retained::compile(session, source, observations, policy, "", 0);
    assert(added.status == 0 && !added.reused && added.retained && session.generation == 2 && session.fresh_runs == 2);
    assert(added.bytes[..] == baseline[..]);
    // A semantic interface change invalidates callers; unchanged exact facts hit.
    observations.values[0].value[8] = '2';
    let contract = session_retained::compile(session, source, observations, policy, "", 0);
    assert(contract.status == 0 && !contract.reused && contract.retained && session.generation == 3 && session.fresh_runs == 3);
    let stable = session_retained::compile(session, source, observations, policy, "", 0);
    assert(stable.reused && stable.semantic == semantic && stable.bytes[..] == baseline[..]);
    let old_active = session.active; let old_generation = session.generation;
    for point in 1..4 {
        let interrupted = session_retained::compile(session, source, observations, policy, "", point as u32);
        assert(interrupted.status == 6 && interrupted.bytes.len == 0);
        assert(session.active == old_active && session.generation == old_generation);
        let still = session_retained::compile(session, source, observations, policy, "", 0);
        assert(still.status == 0 && still.reused && still.bytes[..] == baseline[..]);
    }
    let invalid = session_retained::compile(session, "invalid source", observations, policy, "forged zero-work receipt", 0);
    assert(invalid.status == 1 && invalid.bytes.len == 0 && session.generation == old_generation);
    var no_trusted_history = session_retained::Session {};
    let forged = session_retained::compile(no_trusted_history, "invalid source", observations, policy, "forged zero-work receipt", 0);
    assert(forged.status == 1 && !forged.reused && forged.bytes.len == 0 && !no_trusted_history.has_revision);
    let wrong_policy = session_retained::compile(session, source, observations, "incorrect-policy", "", 0);
    assert(wrong_policy.status == 5 && wrong_policy.bytes.len == 0 && session.generation == old_generation);
    var long_source: u8[>..] = []; long_source.append(source); long_source.append("//");
    for i in 4100 { long_source.push('a'); } long_source.push('\n');
    let no_space = session_retained::compile(session, long_source, observations, policy, "", 0);
    assert(no_space.status == 0 && !no_space.reused && !no_space.retained && no_space.bytes.len > 0);
    assert(session.generation == old_generation && session.active == old_active);
    // Malformed observations decline optional retention rather than changing
    // the source result or treating an incomplete list as a match.
    var malformed = session_retained::Observations { count: 17 };
    let declined = session_retained::compile(session, source, malformed, policy, "", 0);
    assert(declined.status == 0 && !declined.reused && !declined.retained && declined.bytes[..] == baseline[..]);
    assert(session.generation == old_generation && session.active == old_active);
    let final = session_retained::compile(session, source, observations, policy, "", 0);
    assert(final.reused && final.bytes[..] == baseline[..]);
    let edited = "let identity: U32 -> U32 = fn x => return 7\n";
    let changed = session_retained::compile(session, edited, observations, policy, "", 0);
    assert(changed.status == 0 && !changed.reused && changed.retained && changed.bytes[..] != baseline[..]);
    assert(session.generation == old_generation + 1);
    let reverted = session_retained::compile(session, source, observations, policy, "", 0);
    assert(reverted.status == 0 && !reverted.reused && reverted.retained && reverted.bytes[..] == baseline[..]);
    assert(session.generation == old_generation + 2);
    assert(session_retained::compile(session, source, observations, policy, "", 0).reused);
    // Mutate the executable local.get argument in a separate session. The
    // independent source/plan/target gate must decline the corrupt record and
    // rebuild; neither its old receipt nor a matching source authorizes it.
    var compromised = session_retained::Session {};
    let prime = session_retained::compile(compromised, source, observations, policy, "", 0);
    assert(prime.status == 0 && prime.retained && prime.bytes[..] == baseline[..]);
    var reader = wasm_scalar_validation::Reader { at: 8, end: baseline.len };
    let _ = wasm_scalar_validation::section(baseline, reader, 1);
    let _ = wasm_scalar_validation::section(baseline, reader, 3);
    let _ = wasm_scalar_validation::section(baseline, reader, 5);
    let _ = wasm_scalar_validation::section(baseline, reader, 7);
    var code = wasm_scalar_validation::section(baseline, reader, 10);
    assert(wasm_scalar_validation::u32_leb(baseline, code) == 1);
    let size = wasm_scalar_validation::u32_leb(baseline, code); assert(size >= 4);
    assert(wasm_scalar_validation::byte(baseline, code) == 0);
    assert(wasm_scalar_validation::byte(baseline, code) == 0x20);
    let immediate = code.at;
    assert(wasm_scalar_validation::byte(baseline, code) == 1);
    compromised.entries[compromised.active].target[immediate] = 0;
    let repaired = session_retained::compile(compromised, source, observations, policy, "", 0);
    assert(repaired.status == 0 && !repaired.reused && repaired.retained && repaired.bytes[..] == baseline[..]);
    assert(compromised.fresh_runs == 2 && compromised.generation == 2);
    let last = compromised.entries[compromised.active].target_len - 1;
    compromised.entries[compromised.active].target[last] ^= 1;
    let repaired_metadata = session_retained::compile(compromised, source, observations, policy, "", 0);
    assert(repaired_metadata.status == 0 && !repaired_metadata.reused && repaired_metadata.bytes[..] == baseline[..]);
    compromised.entries[compromised.active].target_len -= 1;
    let repaired_truncated = session_retained::compile(compromised, source, observations, policy, "", 0);
    assert(repaired_truncated.status == 0 && !repaired_truncated.reused && repaired_truncated.bytes[..] == baseline[..]);
    compromised.entries[compromised.active].target_len += 1;
    let repaired_extra = session_retained::compile(compromised, source, observations, policy, "", 0);
    assert(repaired_extra.status == 0 && !repaired_extra.reused && repaired_extra.bytes[..] == baseline[..]);
    compromised.entries[compromised.active].plan.opcode = 1;
    let repaired_plan = session_retained::compile(compromised, source, observations, policy, "", 0);
    assert(repaired_plan.status == 0 && !repaired_plan.reused && repaired_plan.bytes[..] == baseline[..]);
    // Optional verification exhaustion declines retention and fresh checking
    // remains available. This is a partial fixture meter, not full K1 C09.
    let active = compromised.active;
    let used = compromised.entries[active].receipt.meter.semantic;
    compromised.entries[active].receipt.meter.phase_semantic[0] += 1048576 - used;
    compromised.entries[active].receipt.meter.semantic = 1048576;
    assert(session_retained::receipt_valid(compromised.entries[active].receipt));
    let budget_fallback = session_retained::compile(compromised, source, observations, policy, "", 0);
    assert(budget_fallback.status == 0 && !budget_fallback.reused && budget_fallback.bytes[..] == baseline[..]);
    for fixture in [
        "let v: U32 -> U32 = fn x => return 42\n",
        "let f: U32 -> U32 = fn x => return x & 7\n",
        "let f: U32 -> Bool = fn x => return x < 7\n",
        "let f: U32 -> U32 = fn x => do:\n  return x\n",
        "let f: U32 -> U32 = fn x => return do:\n  break x\n"
    ] {
        var different = session_retained::Session {};
        let a = session_retained::compile(different, fixture, observations, policy, "", 0);
        let b = session_retained::compile(different, fixture, observations, policy, "", 0);
        assert(a.status == 0 && a.retained && !a.reused && b.status == 0 && b.reused);
        assert(a.bytes[..] == b.bytes[..] && a.semantic == b.semantic && a.validation_semantic == b.validation_semantic &&
            a.validation_target_visits == b.validation_target_visits);
    }
    print("private session retention and dependency laws passed");
}
