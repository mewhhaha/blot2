namespace blot_backend_backend_timing;
import std;
import support.native;
import support.option;
import work_counters;

let phase_names = ["other", "lookup", "query_prepare", "query_scan", "query_source", "query_import", "query_match", "query_validate", "query_publish", "replay", "specialization", "constants", "principals", "interfaces", "startup", "layouts", "evaluation", "inference", "semantic_coordination", "semantic_dispatch", "semantic_publication"];
enum Phase { other, lookup, query_prepare, query_scan, query_source, query_import, query_match, query_validate, query_publish, replay, specialization, constants, principals, interfaces, startup, layouts, evaluation, inference, semantic_coordination, semantic_dispatch, semantic_publication }
let phases = [Phase.other, Phase.lookup, Phase.query_prepare, Phase.query_scan, Phase.query_source, Phase.query_import, Phase.query_match, Phase.query_validate, Phase.query_publish, Phase.replay, Phase.specialization, Phase.constants, Phase.principals, Phase.interfaces, Phase.startup, Phase.layouts, Phase.evaluation, Phase.inference, Phase.semantic_coordination, Phase.semantic_dispatch, Phase.semantic_publication];
fn phaseIndex(phase: Phase) -> i64 { for value, index in phases { if value == phase { return index; } } abort("invalid backend timing phase"); }
struct Region {
    file_utf8: u8[160] = [0; 160], file_truncated: bool = false, offset: u32 = 0, unit: u32 = 0, binding: u32 = 0, body: u32 = 0,
    scopes: i64 = 0, nodes: i64 = 0, us: u64 = 0, principal: bool = false, rejected: u16 = 0,
    input_calls: i64 = 0, recorded_inputs: bool = false, output_types: i64 = 0, output_rows: i64 = 0,
}
struct ThreadCpu { values: u64[21] = [0; 21] }
struct RefinementCost { admission: u8 = 0, publication: u16 = 0, rejected_candidates: u16 = 0, record_rejections: u8 = 0, requests: u64 = 0, nodes: u64 = 0 }
struct RefinementRequest { cost: RefinementCost, unit: u32 = 0, source: u32 = 0, closure: bool = false, expected: u32 = 0, seeds: i64 = 0, rows: i64 = 0 }
struct RefinementCensus { groups: RefinementCost[32] = [RefinementCost {..}; 32], overflow: RefinementCost, heaviest: RefinementRequest[8] = [RefinementRequest {..}; 8] }
fn saturatingAdd(left: u64, right: u64) -> u64 { if right > 18446744073709551615 - left { return 18446744073709551615; } return left + right; }
fn add(census: RefinementCensus&, request: RefinementRequest) {
    let cost = request.cost; var slot = -1;
    for group, index in census.groups { if group.requests == 0 || (group.admission == cost.admission && group.publication == cost.publication && group.rejected_candidates == cost.rejected_candidates && group.record_rejections == cost.record_rejections) { slot = index; break; } }
    if slot >= 0 {
        if census.groups[slot].requests == 0 { census.groups[slot] = cost; }
        else { census.groups[slot].requests = saturatingAdd(census.groups[slot].requests, cost.requests); census.groups[slot].nodes = saturatingAdd(census.groups[slot].nodes, cost.nodes); }
    } else { census.overflow.requests = saturatingAdd(census.overflow.requests, cost.requests); census.overflow.nodes = saturatingAdd(census.overflow.nodes, cost.nodes); }
    var smallest = 0; for prior, index in census.heaviest { if prior.cost.nodes < census.heaviest[smallest].cost.nodes { smallest = index; } }
    if cost.nodes > census.heaviest[smallest].cost.nodes { census.heaviest[smallest] = request; }
}
struct RegionCaller { function: const u8[:] = "", line: u32 = 0 }
struct RegionCost {
    caller: RegionCaller, stage: blot_support::Option<blot_work_counters::InferenceStage> = blot_support::Option<blot_work_counters::InferenceStage> { present: true, value: blot_work_counters::InferenceStage.general , ..}, regions: u64 = 0, inclusive_us: u64 = 0, scopes: u64 = 0, nodes: u64 = 0,
    solver_bytes: u64 = 0, scratch_bytes: u64 = 0, solver_allocations: u64 = 0, scratch_allocations: u64 = 0,
}
struct RegionCensus { entries: RegionCost[32] = [RegionCost {..}; 32], overflow: RegionCost = RegionCost { caller: RegionCaller { function: "overflow" , ..}, stage: blot_support::Option<blot_work_counters::InferenceStage> { present: false , ..} , ..} }
fn sameBytes(left: const u8[:], right: const u8[:]) -> bool { if left.len != right.len { return false; } for byte, index in left { if byte != right[index] { return false; } } return true; }
fn addCost(target: RegionCost&, cost: RegionCost) {
    target.regions = saturatingAdd(target.regions, cost.regions); target.inclusive_us = saturatingAdd(target.inclusive_us, cost.inclusive_us); target.scopes = saturatingAdd(target.scopes, cost.scopes); target.nodes = saturatingAdd(target.nodes, cost.nodes);
    target.solver_bytes = saturatingAdd(target.solver_bytes, cost.solver_bytes); target.scratch_bytes = saturatingAdd(target.scratch_bytes, cost.scratch_bytes);
    target.solver_allocations = saturatingAdd(target.solver_allocations, cost.solver_allocations); target.scratch_allocations = saturatingAdd(target.scratch_allocations, cost.scratch_allocations);
}
fn add(census: RegionCensus&, cost: RegionCost) {
    var slot = -1;
    for entry, index in census.entries { if entry.regions == 0 || (entry.stage == cost.stage && entry.caller.line == cost.caller.line && sameBytes(entry.caller.function, cost.caller.function)) { slot = index; break; } }
    if slot < 0 { addCost(census.overflow, cost); return; }
    if census.entries[slot].regions == 0 { census.entries[slot].caller = cost.caller; census.entries[slot].stage = cost.stage; }
    addCost(census.entries[slot], cost);
}
struct WorkStats {
    regions: Region[8] = [Region {..}; 8], region_callers: RegionCensus, refinements: RefinementCensus, thread_cpu_us: blot_support::Option<ThreadCpu>,
    lookup_us: u64 = 0,
    query_prepare_us: u64 = 0,
    query_scan_us: u64 = 0,
    query_source_us: u64 = 0,
    query_import_us: u64 = 0,
    query_match_us: u64 = 0,
    query_validate_us: u64 = 0,
    query_publish_us: u64 = 0,
    replay_us: u64 = 0,
    specialization_us: u64 = 0,
    constants_us: u64 = 0,
    principals_us: u64 = 0,
    interfaces_us: u64 = 0,
    startup_us: u64 = 0,
    layouts_us: u64 = 0,
    evaluation_us: u64 = 0,
    inference_us: u64 = 0,
    semantic_coordination_us: u64 = 0,
    semantic_dispatch_us: u64 = 0,
    semantic_publication_us: u64 = 0,
    semantic_job_sum_us: u64 = 0,
}
struct Stats { prepare_us: u64 = 0, generate_us: u64 = 0, initialize_us: u64 = 0, assemble_us: u64 = 0, capture_us: u64 = 0, profiled: bool = false, work: WorkStats }
struct Clock { enabled: bool = false, previous: u64 = 0, cpu: bool = false }
fn now(clock: Clock) -> u64 { if clock.cpu { return blot_native::thread_cpu_ns(); } return blot_native::clock_ns(); }
fn init(enabled: bool) -> Clock { initKind(enabled, false) }
fn initKind(enabled: bool, cpu: bool) -> Clock { var clock = Clock { enabled: enabled, cpu: cpu , ..}; if enabled { clock.previous = now(clock); } return clock; }
fn lapNanos(clock: Clock&) -> u64 {
    if !clock.enabled { return 0; } let current = now(clock); var elapsed: u64 = 0; if current >= clock.previous { elapsed = current - clock.previous; } clock.previous = current; return elapsed;
}
fn lap(clock: Clock&) -> u64 { lapNanos(clock) / 1000 }
struct Work {
    clock: Clock, cpu_clock: Clock = Clock { cpu: true , ..}, cpu_nanos: u64[21] = [0; 21], active: Phase = Phase.other,
    regions: Region[8] = [Region {..}; 8], region_callers: RegionCensus, refinements: RefinementCensus, nanos: u64[21] = [0; 21], semantic_job_nanos: u64 = 0,
}
struct Scope { owner: Work&, previous: Phase, started: u64 = 0 }
fn elapsedUs(scope: Scope) -> u64 { if !scope.owner.clock.enabled { return 0; } let current = blot_native::clock_ns(); if current < scope.started { return 0; } return (current - scope.started) / 1000; }
fn account(work: Work&) { let index = phaseIndex(work.active); work.nanos[index] += lapNanos(work.clock); work.cpu_nanos[index] += lapNanos(work.cpu_clock); }
fn deinit(scope: Scope) { account(scope.owner); scope.owner.active = scope.previous; }
fn change(scope: Scope, phase: Phase) { account(scope.owner); scope.owner.active = phase; }
fn enter(work: Work&, phase: Phase) -> Scope { account(work); let scope = Scope { owner: work, previous: work.active, started: work.clock.previous , ..}; work.active = phase; return scope; }
fn copyUtf8Prefix(buffer: u8[:], name: const u8[:]) -> bool {
    var length = name.len; if length > buffer.len { length = buffer.len; }
    while length != 0 && length < name.len && (name[length] & 192) == 128 { length--; }
    for index in 0..length { buffer[index] = name[index]; } return length != name.len;
}
fn region(work: Work&, input: Region, name: const u8[:]) {
    var smallest = 0; for record, index in work.regions { if record.us < work.regions[smallest].us { smallest = index; } }
    if input.us <= work.regions[smallest].us { return; } work.regions[smallest] = input; work.regions[smallest].file_truncated = copyUtf8Prefix(work.regions[smallest].file_utf8, name);
}
fn snapshot(work: Work&) -> WorkStats {
    var result = WorkStats { regions: work.regions, region_callers: work.region_callers, refinements: work.refinements, semantic_job_sum_us: work.semantic_job_nanos / 1000 , ..};
    if work.cpu_clock.enabled { var cpu = ThreadCpu {..}; for nanos, index in work.cpu_nanos { cpu.values[index] = nanos / 1000; } result.thread_cpu_us = blot_support::some(cpu); }
    result.lookup_us = work.nanos[1] / 1000;
    result.query_prepare_us = work.nanos[2] / 1000;
    result.query_scan_us = work.nanos[3] / 1000;
    result.query_source_us = work.nanos[4] / 1000;
    result.query_import_us = work.nanos[5] / 1000;
    result.query_match_us = work.nanos[6] / 1000;
    result.query_validate_us = work.nanos[7] / 1000;
    result.query_publish_us = work.nanos[8] / 1000;
    result.replay_us = work.nanos[9] / 1000;
    result.specialization_us = work.nanos[10] / 1000;
    result.constants_us = work.nanos[11] / 1000;
    result.principals_us = work.nanos[12] / 1000;
    result.interfaces_us = work.nanos[13] / 1000;
    result.startup_us = work.nanos[14] / 1000;
    result.layouts_us = work.nanos[15] / 1000;
    result.evaluation_us = work.nanos[16] / 1000;
    result.inference_us = work.nanos[17] / 1000;
    result.semantic_coordination_us = work.nanos[18] / 1000;
    result.semantic_dispatch_us = work.nanos[19] / 1000;
    result.semantic_publication_us = work.nanos[20] / 1000;
    return result;
}
fn jsonString(out: u8[>..]&, value: const u8[:]) {
    let hex = "0123456789abcdef"; out.push('"');
    for byte in value {
        if byte == '"' || byte == '\\' { out.push('\\'); out.push(byte); }
        else if byte < 32 { out.append("\\u00"); out.push(hex[byte >> 4]); out.push(hex[byte & 15]); }
        else { out.push(byte); }
    }
    out.push('"');
}
fn jsonField<T>(out: u8[>..]&, field: const u8[:], value: T, comma: bool = true) {
    if comma { out.push(','); } jsonString(out, field); out.push(':'); format(out, value);
}
fn jsonStringify(region: Region, out: u8[>..]&) {
    var length = 0; while length < region.file_utf8.len && region.file_utf8[length] != 0 { length++; }
    out.append("{\"file\":"); jsonString(out, region.file_utf8[..length]);
    jsonField(out, "file_truncated", region.file_truncated); jsonField(out, "offset", region.offset); jsonField(out, "unit", region.unit); jsonField(out, "binding", region.binding); jsonField(out, "body", region.body);
    jsonField(out, "scopes", region.scopes); jsonField(out, "nodes", region.nodes); jsonField(out, "us", region.us); jsonField(out, "principal", region.principal); jsonField(out, "rejected", region.rejected);
    jsonField(out, "input_calls", region.input_calls); jsonField(out, "recorded_inputs", region.recorded_inputs); jsonField(out, "output_types", region.output_types); jsonField(out, "output_rows", region.output_rows); out.push('}');
}
fn jsonStringify(cpu: ThreadCpu, out: u8[>..]&) { out.push('{'); for name, index in phase_names { jsonField(out, name, cpu.values[index], index != 0); } out.push('}'); }
fn jsonStringify(cost: RefinementCost, out: u8[>..]&) {
    out.push('{'); jsonField(out, "admission", cost.admission, false); jsonField(out, "publication", cost.publication); jsonField(out, "rejected_candidates", cost.rejected_candidates);
    jsonField(out, "record_rejections", cost.record_rejections); jsonField(out, "requests", cost.requests); jsonField(out, "nodes", cost.nodes); out.push('}');
}
fn jsonStringify(request: RefinementRequest, out: u8[>..]&) {
    out.append("{\"cost\":"); jsonStringify(request.cost, out); jsonField(out, "unit", request.unit); jsonField(out, "source", request.source); jsonField(out, "closure", request.closure); jsonField(out, "expected", request.expected); jsonField(out, "seeds", request.seeds); jsonField(out, "rows", request.rows); out.push('}');
}
fn jsonStringify(census: RefinementCensus, out: u8[>..]&) {
    out.append("{\"groups\":["); var comma = false;
    for group in census.groups { if group.requests == 0 { continue; } if comma { out.push(','); } jsonStringify(group, out); comma = true; }
    out.append("],\"overflow\":"); jsonStringify(census.overflow, out); out.append(",\"heaviest\":["); comma = false;
    for request in census.heaviest { if request.cost.requests == 0 { continue; } if comma { out.push(','); } jsonStringify(request, out); comma = true; } out.append("]}");
}
fn stageName(stage: blot_work_counters::InferenceStage) -> const u8[:] {
    if stage == blot_work_counters::InferenceStage.general { return "general"; } if stage == blot_work_counters::InferenceStage.specialization { return "specialization"; } if stage == blot_work_counters::InferenceStage.preparation { return "preparation"; } return "lowering";
}
fn jsonStringify(cost: RegionCost, out: u8[>..]&) {
    out.append("{\"caller\":{\"function\":"); jsonString(out, cost.caller.function); jsonField(out, "line", cost.caller.line); out.append("},\"stage\":");
    if cost.stage.present { jsonString(out, stageName(cost.stage.value)); } else { out.append("null"); }
    jsonField(out, "regions", cost.regions); jsonField(out, "inclusive_us", cost.inclusive_us); jsonField(out, "scopes", cost.scopes); jsonField(out, "nodes", cost.nodes);
    jsonField(out, "solver_bytes", cost.solver_bytes); jsonField(out, "scratch_bytes", cost.scratch_bytes); jsonField(out, "solver_allocations", cost.solver_allocations); jsonField(out, "scratch_allocations", cost.scratch_allocations); out.push('}');
}
fn jsonStringify(census: RegionCensus, out: u8[>..]&) {
    out.push('['); var comma = false;
    for entry in census.entries { if entry.regions == 0 { continue; } if comma { out.push(','); } jsonStringify(entry, out); comma = true; }
    if census.overflow.regions != 0 { if comma { out.push(','); } jsonStringify(census.overflow, out); } out.push(']');
}
fn jsonStringify(work: WorkStats, out: u8[>..]&) {
    out.append("{\"regions\":["); var comma = false; for region in work.regions { if region.us == 0 { continue; } if comma { out.push(','); } jsonStringify(region, out); comma = true; }
    out.append("],\"region_callers\":"); jsonStringify(work.region_callers, out); out.append(",\"refinements\":"); jsonStringify(work.refinements, out); out.append(",\"thread_cpu_us\":");
    if work.thread_cpu_us.present { jsonStringify(work.thread_cpu_us.value, out); } else { out.append("null"); }
    jsonField(out, "lookup_us", work.lookup_us);
    jsonField(out, "query_prepare_us", work.query_prepare_us);
    jsonField(out, "query_scan_us", work.query_scan_us);
    jsonField(out, "query_source_us", work.query_source_us);
    jsonField(out, "query_import_us", work.query_import_us);
    jsonField(out, "query_match_us", work.query_match_us);
    jsonField(out, "query_validate_us", work.query_validate_us);
    jsonField(out, "query_publish_us", work.query_publish_us);
    jsonField(out, "replay_us", work.replay_us);
    jsonField(out, "specialization_us", work.specialization_us);
    jsonField(out, "constants_us", work.constants_us);
    jsonField(out, "principals_us", work.principals_us);
    jsonField(out, "interfaces_us", work.interfaces_us);
    jsonField(out, "startup_us", work.startup_us);
    jsonField(out, "layouts_us", work.layouts_us);
    jsonField(out, "evaluation_us", work.evaluation_us);
    jsonField(out, "inference_us", work.inference_us);
    jsonField(out, "semantic_coordination_us", work.semantic_coordination_us);
    jsonField(out, "semantic_dispatch_us", work.semantic_dispatch_us);
    jsonField(out, "semantic_publication_us", work.semantic_publication_us);
    jsonField(out, "semantic_job_sum_us", work.semantic_job_sum_us);
    out.push('}');
}
fn jsonStringify(stats: Stats, out: u8[>..]&) {
    out.push('{'); jsonField(out, "prepare_us", stats.prepare_us, false); jsonField(out, "generate_us", stats.generate_us); jsonField(out, "initialize_us", stats.initialize_us); jsonField(out, "assemble_us", stats.assemble_us); jsonField(out, "capture_us", stats.capture_us);
    if stats.profiled { out.append(",\"work\":"); jsonStringify(stats.work, out); } out.push('}');
}
