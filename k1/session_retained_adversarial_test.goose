// Private retained scalar hit gate: exhaust every target byte and truncation,
// plus forged plan and optional-budget controls. This does not authenticate an
// externally supplied receipt or establish complete K1 work accounting.
import catalog;
import session_retained;
fn repaired(s: session_retained::Session&, source: u8[:], obs: session_retained::Observations&, baseline: u8[:]) {
    let before = s.fresh_runs;
    let result = session_retained::compile(s,source,obs,catalog::semantic_policy(),"",0);
    assert(result.status==0 && !result.reused && result.bytes[..]==baseline && s.fresh_runs==before+1);
}
fn main() {
    let source="let identity: U32 -> U32 = fn x => return x\n";
    var obs=session_retained::Observations {};
    var seed=session_retained::Session {};
    let first=session_retained::compile(seed,source,obs,catalog::semantic_policy(),"",0);
    assert(first.status==0 && first.retained);
    let baseline=copy(first.bytes);
    for i in baseline.len {
        var s=seed; s.entries[s.active].target[i] ^= 1;
        repaired(s,source,obs,baseline);
    }
    for n in baseline.len {
        var s=seed; s.entries[s.active].target_len=n as u32;
        repaired(s,source,obs,baseline);
    }
    for field in 18 {
        var s=seed;
        if field==0 {s.entries[s.active].plan.schema = -1;}
        else if field==1 {s.entries[s.active].plan.edition = 0;}
        else if field==2 {s.entries[s.active].plan.semantic_policy = 0;}
        else if field==3 {s.entries[s.active].plan.optimization_policy = 0;}
        else if field==4 {s.entries[s.active].plan.abi = 0;}
        else if field==5 {s.entries[s.active].plan.parameter_representation = 0;}
        else if field==6 {s.entries[s.active].plan.result_representation = 0;}
        else if field==7 {s.entries[s.active].plan.environment_parameter = 0;}
        else if field==8 {s.entries[s.active].plan.source_parameters = 0;}
        else if field==9 {s.entries[s.active].plan.result_slot = 1;}
        else if field==10 {s.entries[s.active].plan.opcode = 1;}
        else if field==11 {s.entries[s.active].plan.helper_count = 1;}
        else if field==12 {s.entries[s.active].plan.memory_grow = 1;}
        else if field==13 {s.entries[s.active].plan.memory_initial_pages = 1;}
        else if field==14 {s.entries[s.active].plan.depth = 0;}
        else if field==15 {s.entries[s.active].plan.core.result_id = 99;}
        else if field==16 {s.entries[s.active].plan.core.name_start = -1;}
        else {s.entries[s.active].plan.core.values[0].literal = 1;}
        repaired(s,source,obs,baseline);
    }
    // A valid but exhausted optional verifier receipt falls back to a fresh
    // successful compile instead of producing a semantic rejection.
    var exhausted=seed;
    let used=exhausted.entries[exhausted.active].receipt.meter.semantic;
    exhausted.entries[exhausted.active].receipt.meter.phase_semantic[0] += 1048576-used;
    exhausted.entries[exhausted.active].receipt.meter.semantic=1048576;
    assert(session_retained::receipt_valid(exhausted.entries[exhausted.active].receipt));
    repaired(exhausted,source,obs,baseline);
    print("retained target/plan mutation and truncation fallback passed");
}
