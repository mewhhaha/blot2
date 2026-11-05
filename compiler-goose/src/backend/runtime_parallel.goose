// Joined immutable optimization jobs use copied images and independent Goose
// worker processes. Only the coordinator publishes outputs in function order.
namespace blot_backend_runtime_parallel;
import .runtime_ir;
import .runtime_pipeline;
import .runtime_job;
import .optimized_bodies;
import .wasm;
import .wasm_lifetimes;
import compilation_tier;
import phase_profile;
import support.process_pool;
import support.error;
import support.option;
import support.native;
type Error = blot_error::Error;
type Body = blot_backend_runtime_ir::DetachedBody;
type WorkerTiming = blot_backend_optimized_bodies::WorkerTiming;
struct Slot { needed: bool,rc: bool = false,output: blot_support::Option<Body>,failed: bool = false,unproven: bool = false }
struct Job { id: i64,instructions: i64 }
struct Batch { slots: Slot[:] = default<Slot[:]>(),workers: i64 = 1,jobs: i64,rc: bool = false,timings: blot_support::Option<WorkerTiming[16]> }
reusable[] var slot_runs: Slot[>..] = [];
reusable[] var request_runs: u8[>..] = [];
fn heavier(left: Job,right: Job) -> bool { if left.instructions == right.instructions { return left.id < right.id; } return left.instructions > right.instructions; }
fn sort(jobs: Job[:]) { var scratch: Job[>..<] = []; for job in jobs { scratch.push(job); } var width: i64 = 1; while width < jobs.len { var first: i64 = 0; while first < jobs.len { let middle = min(jobs.len,first + width); let end = min(jobs.len,middle + width); var left = first; var right = middle; for destination in first..end { var take_left = left < middle; if take_left && right < end { take_left = heavier(jobs[left],jobs[right]); } if take_left { scratch[destination] = jobs[left]; left++; } else { scratch[destination] = jobs[right]; right++; } } first = end; } for job,index in scratch { jobs[index] = job; } width *= 2; } }
struct Packet {
    version: u32 = 1,id: u32,needed: bool,rc: bool,roots: bool,needs_roots: bool,tier: blot_compilation_tier::Tier,profile: bool,started_ns: u64,trace: blot_phase_profile::WorkerContext,
    has_cached_body: bool,module_image: u8[],cached_locals: u8[],cached_code: blot_backend_runtime_ir::Instruction[],
}
struct Response {
    version: u32 = 1,id: u32,failure: Error,unproven: bool,has_output: bool,timing: WorkerTiming,trace: blot_phase_profile::WorkerSnapshot,
    locals: u8[],instructions: blot_backend_runtime_ir::Instruction[],
}
fn cachedLocals(body: blot_support::Option<Body>) -> u8[] { if body.present { return copy(body.value.locals); } return []; }
fn cachedCode(body: blot_support::Option<Body>) -> blot_backend_runtime_ir::Instruction[] { if body.present { return copy(body.value.instructions); } return []; }
fn elapsed(started: u64) -> u64 { let now = blot_native::clock_ns(); if now <= started { return 0; } return (now - started) / 1000; }
struct Execution {
    id: u32,needed: bool,rc: bool,roots: bool,needs_roots: bool,tier: blot_compilation_tier::Tier,cached: blot_support::Option<Body>,output: blot_support::Option<Body>,unproven: bool = false,
}
fn executeModule(context: Execution&,module: blot_backend_wasm::Module&) -> Error {
    if context.id >= module.functions.len { return blot_error::Error.invalid_artifact; } var session,error = blot_backend_runtime_pipeline::init(module); if error != blot_error::Error.none { return error; } session.roots = context.roots; session.needs_roots = context.needs_roots; session.tier = context.tier;
    recursive fn execute() -> Error {
        var body = context.cached; if context.needed { let optimized,error = session.optimize(context.id); if error != blot_error::Error.none { return error; } body = optimized; context.output = optimized; }
        if context.rc { let function = module.functions[context.id]; var view = function; if body.present { view = blot_backend_runtime_pipeline::viewBody(function,body.value); } var proof,error = blot_backend_wasm_lifetimes::rcPlan(module,view,session.summaries,null); if error != blot_error::Error.none { return error; } context.unproven = !proof.admitted || proof.allocations.items.len != 0; proof.deinit(); } return blot_error::Error.none;
    } let result = execute(); session.deinit(); return result;
}
// The process dispatcher invokes actual Goose pipeline algorithms here. Nested
// parallel work is disabled by the dispatcher's process-local worker marker.
fn executePacket(bytes: const u8[:],output: u8[>..<]&) -> Error {
    let packets,valid = from_bytes<Packet[]>(bytes); if !valid || packets.len != 1 { return blot_error::Error.invalid_artifact; }
    for packet in packets {
        if packet.version != 1 || (packet.needed && packet.has_cached_body) { return blot_error::Error.invalid_artifact; } let installation = blot_phase_profile::beginWorker(packet.trace); var context = Execution { id: packet.id,needed: packet.needed,rc: packet.rc,roots: packet.roots,needs_roots: packet.needs_roots,tier: packet.tier,..}; if packet.has_cached_body { context.cached = blot_support::some(Body { locals: packet.cached_locals[..],instructions: packet.cached_code[..],..}); } var timing = WorkerTiming { started_us: elapsed(packet.started_ns),..}; var cpu: u64 = 0; if packet.profile && blot_native::thread_cpu_available() { cpu = blot_native::thread_cpu_ns(); }
        let error = blot_backend_runtime_job::decodeWithModule(packet.module_image[..],context,executeModule); timing.finished_us = elapsed(packet.started_ns); if packet.profile { timing.jobs = 1; if packet.id < 4294967295 { let images,image_valid = from_bytes<blot_backend_runtime_job::Image[]>(packet.module_image[..]); if image_valid { for image in images { for function,id in image.functions { if id == packet.id { timing.instructions = function.instructions.len; } } } } } if cpu != 0 { let end = blot_native::thread_cpu_ns(); timing.cpu_us = blot_support::some((end - min(end,cpu)) / 1000); } } let telemetry = installation.finish(); let response = Response { id: packet.id,failure: error,unproven: context.unproven,has_output: context.output.present,timing: timing,trace: telemetry,locals: cachedLocals(context.output),instructions: cachedCode(context.output),..}; to_bytes([response],output); if context.output.present { context.output.value.deinit(); } return blot_error::Error.none;
    } return blot_error::Error.invalid_artifact;
}
fn mergeTiming(destination: WorkerTiming&,source: WorkerTiming) { if destination.jobs == 0 { destination.started_us = source.started_us; } else { destination.started_us = min(destination.started_us,source.started_us); } destination.finished_us = max(destination.finished_us,source.finished_us); destination.jobs += source.jobs; destination.instructions += source.instructions; if source.cpu_us.present { if !destination.cpu_us.present { destination.cpu_us = blot_support::some<u64>(0); } destination.cpu_us.value += source.cpu_us.value; } }
fn run(optional_io: bool,session: blot_backend_runtime_pipeline::Session&,matcher: blot_support::Option<blot_backend_optimized_bodies::Matcher>,requested: u8,rc: bool,profile: bool) -> blot_support::Option<Batch>,Error {
    if requested <= 1 || !optional_io { return blot_support::none<Batch>(),blot_error::Error.none; } assert(session.module && session.summaries.prepared); let module .= session.module; var jobs: i64 = 0; var instructions: i64 = 0;
    for function,id in module.functions { if matcher.present && matcher.value.matches(id) { continue; } jobs++; let count = blot_backend_wasm::instructions(module,function).len; instructions = min(9223372036854775807 - instructions,count) + instructions; } if jobs < 4 || instructions < 4096 { return blot_support::none<Batch>(),blot_error::Error.none; }
    var batch = Batch { slots: slot_runs.alloc_slice(module.functions.len),jobs: jobs,rc: rc,..}; var queue: Job[>..<] = []; var requests: blot_process_pool::Request[>..<] = []; var packets: (u8[:])[>..<] = []; var keep = false;
    recursive fn schedule() -> Error {
        for function,id in module.functions { var reused = false; var cached_rc = false; if matcher.present { reused = matcher.value.matches(id); cached_rc = matcher.value.rcUnproven(id).present; } batch.slots[id] = Slot { needed: !reused,rc: rc && !session.runtimeHelper(id as u32) && !cached_rc,..}; }
        for slot,id in batch.slots { if !slot.needed && !slot.rc { continue; } var body = blot_support::none<Body>(); if !slot.needed { assert(matcher.present); body = matcher.value.output(id); } var count = blot_backend_wasm::instructions(module,module.functions[id]).len; if body.present { count = body.value.instructions.len; } queue.push(Job { id: id,instructions: count,..}); } sort(queue[..]); var width = min(requested as i64,min(jobs,16)); batch.workers = width; if profile { batch.timings = blot_support::some([WorkerTiming {..};16]); }
        var module_image: u8[>..<] = []; let encoded = blot_backend_runtime_job::encode(module,module_image); if encoded != blot_error::Error.none { return encoded; } let started = blot_native::clock_ns();
        for job in queue { let slot = batch.slots[job.id]; var body = blot_support::none<Body>(); if !slot.needed { body = matcher.value.output(job.id); } let packet = Packet { id: job.id as u32,needed: slot.needed,rc: slot.rc,roots: session.roots,needs_roots: session.needs_roots,tier: session.tier,profile: profile,started_ns: started,trace: blot_phase_profile::captureWorker(),has_cached_body: body.present,module_image: copy(module_image[..]),cached_locals: cachedLocals(body),cached_code: cachedCode(body),..}; var encoded: u8[>..<] = []; to_bytes([packet],encoded); let owned = request_runs.alloc_slice(encoded.len); for byte,index in encoded { owned[index] = byte; } packets.push(owned); requests.push(blot_process_pool::Request { bytes: owned,..}); }
        var replies,reply_error = blot_process_pool::run(blot_process_pool::Kind.runtime,requests[..],width as u8); if reply_error != blot_error::Error.none { replies.deinit(); return reply_error; }
        recursive fn collect() -> Error {
            if replies.items.len != queue.len { return blot_error::Error.invalid_artifact; } for reply,index in replies.items { let job = queue[index]; if reply.failure != blot_error::Error.none { batch.slots[job.id].failed = true; continue; } let responses,valid = from_bytes<Response[]>(reply.bytes); if !valid || responses.len != 1 { return blot_error::Error.invalid_artifact; } for response in responses { if response.version != 1 || response.id != job.id { return blot_error::Error.invalid_artifact; } blot_phase_profile::mergeWorker(response.trace); if profile { var timing = response.timing; timing.instructions = job.instructions; mergeTiming(batch.timings.value[index % width],timing); } if response.failure != blot_error::Error.none { batch.slots[job.id].failed = true; continue; } batch.slots[job.id].unproven = response.unproven; if response.has_output { if !batch.slots[job.id].needed { return blot_error::Error.invalid_artifact; } let body,error = blot_backend_runtime_ir::cloneBody(response.locals[..],response.instructions[..]); if error != blot_error::Error.none { batch.slots[job.id].failed = true; continue; } batch.slots[job.id].output = blot_support::some(body); } } }
            for slot in batch.slots { if slot.failed { return blot_error::Error.out_of_memory; } } return blot_error::Error.none;
        } let wait_region = blot_phase_profile::region("runtime-ir.worker-join",0,0,0); let collected = collect(); wait_region.exit(); replies.deinit(); if collected != blot_error::Error.none { return collected; } keep = true; return blot_error::Error.none;
    }
    let error = schedule(); for packet in packets { if packet.len != 0 { request_runs.free_slice(packet); } } if !keep { batch.deinit(); return blot_support::none<Batch>(),error; } return blot_support::some(batch),blot_error::Error.none;
}
fn take(self_: Batch&,id: i64) -> blot_support::Option<Body>,Error { assert(id >= 0 && id < self_.slots.len && self_.slots[id].needed); let body = self_.slots[id].output; self_.slots[id].output = blot_support::none<Body>(); return body,blot_error::Error.none; }
fn unproven(self_: const Batch&,id: i64) -> blot_support::Option<bool> { if !self_.slots[id].rc { return blot_support::none<bool>(); } return blot_support::some(self_.slots[id].unproven); }
fn deinit(self_: Batch&) { for &slot in self_.slots { if slot.output.present { slot.output.value.deinit(); } } if self_.slots.len != 0 { slot_runs.free_slice(self_.slots); } self_.slots = []; }
