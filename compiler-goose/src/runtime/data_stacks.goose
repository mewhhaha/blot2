// Nonmoving regions pack fixed extents and extend growers only at the top.
// Epoch-checked owner metadata makes rewind independent of payload tracing.
namespace blot_runtime_data_stacks;
import backend.wasm;
import backend.runtime_ir;
import backend.runtime_code;
import support.emitter;
import support.error;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Local = blot_backend_runtime_code::Local;
type Code = blot_emitter::Emitter<Module>;
enum Mode { fixed, grow, resize }
fn modeCode(mode: Mode) -> u32 { match mode { Mode.fixed => 0, Mode.grow => 1, Mode.resize => 2 } }
let header_bytes: u32 = 16; let descriptor_words: u32 = 3; let max_stacks: u32 = 0xffffffff; let data_base: u32 = 65536;
let slot_bytes: u32 = 16; let slot_base: u32 = 0; let slot_top: u32 = 4; let slot_end: u32 = 8;
let owner_bytes: u32 = 28; let owner_live: u32 = 0; let owner_region: u32 = 4; let owner_low: u32 = 8; let owner_high: u32 = 12;
let owner_base: u32 = 16; let owner_end: u32 = 20; let owner_mark: u32 = 24;
let array_token: u32 = 0; let array_mode: u32 = 4; let array_length: u32 = 8; let array_stride: u32 = 12;
struct Plan { region_capacities: const u32[:], owner_capacity: u32 }
struct Layout { owner_base: u32, data_base: u32, total_bytes: u32 }
fn layout(plan: Plan) -> Layout, Error {
    if plan.region_capacities.len == 0 || plan.owner_capacity == 0 { return default<Layout>(), Error.invalid_plan; }
    let metadata = (plan.region_capacities.len as u64) * (slot_bytes as u64) + (plan.owner_capacity as u64) * (owner_bytes as u64);
    let base = (metadata + 65535) & ~(65535 as u64); var total = base;
    for capacity in plan.region_capacities { if capacity < header_bytes || capacity & 3 != 0 { return default<Layout>(), Error.invalid_plan; } total += capacity; }
    if total > 0xffffffff { return default<Layout>(), Error.invalid_plan; }
    return Layout { (plan.region_capacities.len * slot_bytes) as u32, base as u32, total as u32 }, Error.none;
}
fn regionBase(plan: Plan, index: u32) -> u32, Error {
    if index >= plan.region_capacities.len { return 0, Error.invalid_plan; }
    let memory, error = layout(plan); if error != Error.none { return 0, error; }
    var base = memory.data_base; for capacity in plan.region_capacities[..index] { base += capacity; } return base, Error.none;
}
struct Functions {
    reset: u32,
    reset_temporary: u32,
    open: u32,
    epoch_low: u32,
    epoch_high: u32,
    close: u32,
    mark: u32,
    rewind: u32,
    create: u32,
    length: u32,
    read: u32,
    write: u32,
    append: u32,
    append_space: u32,
    truncate: u32,
    freeze: u32,
    address: u32,
}
struct Runtime {
    functions: Functions, count: u32, owner_count: u32, owner_extent: u32, owner_table: u32, serial: u32, serial_high: u32,
    lookup: u32, entry: u32, region: u32, checked: u32, initialize: u32, initialized: u32, literal_base: u32, inline_returns: u32[3],
}
fn function(module: Module&, count: i64, result: blot_backend_runtime_ir::ValueType) -> u32, Error {
    assert(count >= 0 && count <= 6); let parameters = [blot_backend_runtime_ir::VT_i32; 6];
    return module.addTypedFunction(parameters[..count], result, blot_backend_runtime_ir::ROLE_scalar);
}
fn trimOwners(c: Code&, r: Runtime) {
    let entry = c.temp(); c.loopStart(); c.globalGet(r.owner_extent); c.loopTest();
    c.globalGet(r.owner_table); c.globalGet(r.owner_extent); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(owner_bytes); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(entry);
    c.value(entry); c.load(owner_live); c.op(blot_backend_runtime_ir::OP_br_if, 1);
    c.globalGet(r.owner_extent); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(r.owner_extent); c.again();
}
fn finishPlan(module: Module&, r: Runtime, plan: Plan) -> Error {
    let memory, error = layout(plan); if error != Error.none { return error; }
    module.globals[r.count].bits = plan.region_capacities.len as u32;
    module.globals[r.owner_count].bits = plan.owner_capacity; module.globals[r.owner_table].bits = memory.owner_base;
    if module.data.len > 0xffffffff - memory.total_bytes { return Error.invalid_plan; }
    let total = memory.total_bytes + module.data.len as u32;
    module.globals[r.literal_base].bits = memory.total_bytes; module.fixed_memory_bytes = total;
    var c = blot_emitter::init(module, r.initialize); c.globalGet(r.initialized); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(0); c.value(0); c.value(memory.data_base); c.zero(); var base = memory.data_base;
    for capacity, index in plan.region_capacities {
        let slot = (index * slot_bytes) as u32; c.value(slot); c.value(base); c.store(slot_base); c.value(slot); c.value(base); c.store(slot_top);
        base += capacity; c.value(slot); c.value(base); c.store(slot_end);
    }
    c.value(1 as u32); c.globalSet(r.initialized); c.end(); return c.failure;
}
fn emit(module: Module&) -> Runtime, Error {
    if module.arena.present || module.fixed_memory_bytes != 0 || module.data.len != 0 || module.artifacts != null { return default<Runtime>(), Error.invalid_storage_configuration; }
    module.memory_model = blot_backend_wasm::MemoryModel.data_stacks; module.fixed_memory_bytes = data_base;
    var r = default<Runtime>();
    { let id, error = function(module, 0, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.functions.reset = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.functions.reset_temporary = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.open = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.epoch_low = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.epoch_high = id; }
    { let id, error = function(module, 3, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.functions.close = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.mark = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.functions.rewind = id; }
    { let id, error = function(module, 6, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.create = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.length = id; }
    { let id, error = function(module, 5, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.read = id; }
    { let id, error = function(module, 6, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.functions.write = id; }
    { let id, error = function(module, 5, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.functions.append = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.append_space = id; }
    { let id, error = function(module, 5, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.functions.truncate = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.functions.freeze = id; }
    { let id, error = function(module, 5, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.functions.address = id; }
    { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, false); if error != Error.none { return default<Runtime>(), error; } r.count = id; }
    { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, false); if error != Error.none { return default<Runtime>(), error; } r.owner_count = id; }
    { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, true); if error != Error.none { return default<Runtime>(), error; } r.owner_extent = id; }
    { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, false); if error != Error.none { return default<Runtime>(), error; } r.owner_table = id; }
    { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, true); if error != Error.none { return default<Runtime>(), error; } r.serial = id; }
    { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, true); if error != Error.none { return default<Runtime>(), error; } r.serial_high = id; }
    { let id, error = function(module, 3, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.lookup = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.entry = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.region = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != Error.none { return default<Runtime>(), error; } r.checked = id; }
    { let id, error = function(module, 0, blot_backend_runtime_ir::VT_none); if error != Error.none { return default<Runtime>(), error; } r.initialize = id; }
    { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, true); if error != Error.none { return default<Runtime>(), error; } r.initialized = id; }
    { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, false); if error != Error.none { return default<Runtime>(), error; } r.literal_base = id; }
    for index in 0..3 { let id, error = module.addGlobal(blot_backend_runtime_ir::SC_u32, 0, true); if error != Error.none { return default<Runtime>(), error; } r.inline_returns[index] = id; }
    let error = emitBodies(module, r); if error != Error.none { return default<Runtime>(), error; }
    return r, Error.none;
}
struct Epoch { function: u32, offset: u32 }
fn emitBodies(module: Module&, r: Runtime) -> Error {
    {
        var c = blot_emitter::init(module, r.region);
        c.call(r.initialize);
        c.value(Local { 0 }); c.globalGet(r.count); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.trap();
        c.value(Local { 0 }); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_mul);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.entry);
        let owner = Local { 0 };
        c.call(r.initialize);
        c.value(owner); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(owner); c.globalGet(r.owner_count); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
        c.globalGet(r.owner_table); c.value(owner); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(owner_bytes); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.lookup);
        let entry_ = c.temp();
        c.value(Local { 0 }); c.call(r.entry); c.set(entry_);
        c.value(entry_); c.load(owner_live); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
        c.value(entry_); c.load(owner_low); c.value(Local { 1 }); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
        c.value(entry_); c.load(owner_high); c.value(Local { 2 }); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
        c.value(entry_);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    for item in [Epoch { r.functions.epoch_low, owner_low }, Epoch { r.functions.epoch_high, owner_high }] {
        var c = blot_emitter::init(module, item.function);
        let entry_ = c.temp();
        c.value(Local { 0 }); c.call(r.entry); c.set(entry_);
        c.value(entry_); c.load(owner_live); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
        c.value(entry_); c.load(item.offset);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.open);
        let region_ = Local { 0 };
        let index = c.temp();
        let entry_ = c.temp();
        c.value(region_); c.call(r.region);
        c.op(blot_backend_runtime_ir::OP_drop, 0);
        c.value(0); c.set(index);
        c.loopStart(); c.value(index); c.globalGet(r.owner_count); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
        c.globalGet(r.owner_table); c.value(index); c.value(owner_bytes); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(entry_);
        c.value(entry_); c.load(owner_live); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
        // Increment the full 64-bit epoch before publication; exhaustion traps.
        c.globalGet(r.serial); c.value(0xffffffff); c.op(blot_backend_runtime_ir::OP_i32_eq); c.globalGet(r.serial_high); c.value(0xffffffff); c.op(blot_backend_runtime_ir::OP_i32_eq); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
        c.globalGet(r.serial); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add);
        c.op(blot_backend_runtime_ir::OP_global_set, r.serial);
        c.globalGet(r.serial); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
        c.globalGet(r.serial_high); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add);
        c.op(blot_backend_runtime_ir::OP_global_set, r.serial_high);
        c.end();
        c.value(entry_); c.value(0); c.value(owner_bytes); c.zero();
        c.value(entry_); c.value(region_); c.store(owner_region);
        c.value(entry_); c.value(region_); c.call(r.region); c.load(slot_top); c.store(owner_mark);
        c.value(entry_); c.globalGet(r.serial); c.store(owner_low);
        c.value(entry_); c.globalGet(r.serial_high); c.store(owner_high);
        c.value(entry_); c.value(1); c.store(owner_live);
        c.value(index); c.globalGet(r.owner_extent); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when();
        c.value(index); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add);
        c.op(blot_backend_runtime_ir::OP_global_set, r.owner_extent);
        c.end();
        c.value(index); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.ret();
        c.end();
        c.next(index);
        c.again();
        c.op(blot_backend_runtime_ir::OP_unreachable_, 0);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.close);
        let owner = Local { 0 };
        let entry_ = c.temp();
        let region_ = c.temp();
        c.value(owner); c.when();
        c.value(owner); c.value(Local { 1 }); c.value(Local { 2 }); c.call(r.lookup); c.set(entry_);
        c.value(entry_); c.load(owner_region); c.call(r.region); c.set(region_);
        c.value(entry_); c.load(owner_base); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_ne); c.value(entry_); c.load(owner_end); c.value(region_); c.load(slot_top); c.op(blot_backend_runtime_ir::OP_i32_eq); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
        c.value(region_); c.value(entry_); c.load(owner_base); c.store(slot_top);
        c.end();
        c.value(entry_); c.value(0); c.store(owner_live);
        trimOwners(c, r);
        c.end();
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.mark);
        c.value(Local { 0 }); c.call(r.region); c.load(slot_top);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.rewind);
        let id = Local { 0 };
        let mark = Local { 1 };
        let region_ = c.temp();
        let index = c.temp();
        let entry_ = c.temp();
        c.value(id); c.call(r.region); c.set(region_);
        c.value(mark); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(mark); c.value(region_); c.load(slot_base); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
        c.value(mark); c.value(region_); c.load(slot_top); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(0); c.set(index);
        // Validate all owners before changing any state. A mark cannot cut an
        // initialized extent in half or resurrect an owner after failure.
        c.loopStart(); c.value(index); c.globalGet(r.owner_extent); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
        c.globalGet(r.owner_table); c.value(index); c.value(owner_bytes); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(entry_);
        c.value(entry_); c.load(owner_live); c.value(entry_); c.load(owner_region); c.value(id); c.op(blot_backend_runtime_ir::OP_i32_eq); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
        c.value(entry_); c.load(owner_base); c.value(mark); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.value(entry_); c.load(owner_end); c.value(mark); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
        c.end();
        c.next(index);
        c.again();
        c.value(0); c.set(index);
        c.loopStart(); c.value(index); c.globalGet(r.owner_extent); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
        c.globalGet(r.owner_table); c.value(index); c.value(owner_bytes); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(entry_);
        c.value(entry_); c.load(owner_live); c.value(entry_); c.load(owner_region); c.value(id); c.op(blot_backend_runtime_ir::OP_i32_eq); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
        c.value(entry_); c.load(owner_base); c.value(mark); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.value(entry_); c.load(owner_base); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(entry_); c.load(owner_mark); c.value(mark); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_or); c.when();
        c.value(entry_); c.value(0); c.store(owner_live);
        c.end();
        c.end();
        c.next(index);
        c.again();
        c.value(region_); c.value(mark); c.store(slot_top);
        trimOwners(c, r);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.reset_temporary);
        let first = Local { 0 };
        let index = c.temp();
        let entry_ = c.temp();
        let region_ = c.temp();
        c.call(r.initialize);
        c.value(first); c.globalGet(r.count); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(0); c.set(index);
        c.loopStart(); c.value(index); c.globalGet(r.owner_extent); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
        c.globalGet(r.owner_table); c.value(index); c.value(owner_bytes); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(entry_);
        c.value(entry_); c.load(owner_region); c.value(first); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when();
        c.value(entry_); c.value(0); c.store(owner_live);
        c.end();
        c.next(index);
        c.again();
        trimOwners(c, r);
        c.value(first); c.set(index);
        c.loopStart(); c.value(index); c.globalGet(r.count); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
        c.value(index); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(region_);
        c.value(region_); c.value(region_); c.load(slot_base); c.store(slot_top);
        c.next(index);
        c.again();
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.reset);
        c.value(0); c.call(r.functions.reset_temporary);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.create);
        let token = Local { 0 };
        let count = Local { 3 };
        let mode = Local { 4 };
        let stride = Local { 5 };
        let entry = c.temp();
        let slot = c.temp();
        let address = c.temp();
        let available = c.temp();
        let bytes = c.temp();
        c.value(token); c.value(Local { 1 }); c.value(Local { 2 }); c.call(r.lookup); c.set(entry);
        c.value(entry); c.load(owner_base); c.trap();
        c.value(entry); c.load(owner_region); c.call(r.region); c.set(slot);
        c.value(slot); c.load(slot_top); c.set(address);
        c.value(slot); c.load(slot_end); c.value(address); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(available);
        c.value(available); c.value(header_bytes); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.trap();
        c.value(stride); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(stride); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
        c.value(mode); c.value(modeCode(Mode.resize)); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(count); c.value(available); c.value(header_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(stride); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(header_bytes); c.value(count); c.value(stride); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(bytes);
        c.value(address); c.value(0); c.value(bytes); c.zero();
        c.value(address); c.value(token); c.store(array_token);
        c.value(address); c.value(mode); c.store(array_mode);
        c.value(address); c.value(count); c.store(array_length);
        c.value(address); c.value(stride); c.store(array_stride);
        c.value(entry); c.value(address); c.store(owner_base);
        c.value(entry); c.value(address); c.value(bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.store(owner_end);
        c.value(slot); c.value(address); c.value(bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.store(slot_top);
        c.value(address);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.checked);
        let owner = Local { 0 };
        let address = Local { 3 };
        let entry = c.temp();
        let region = c.temp();
        let stride = c.temp();
        c.value(owner); c.value(Local { 1 }); c.value(Local { 2 }); c.call(r.lookup); c.set(entry);
        c.value(address); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(address); c.value(entry); c.load(owner_base); c.op(blot_backend_runtime_ir::OP_i32_ne); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
        c.value(address); c.load(array_token); c.value(owner); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
        c.value(address); c.load(array_stride); c.set(stride);
        c.value(stride); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(stride); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
        c.value(address); c.load(array_length); c.value(entry); c.load(owner_end); c.value(address); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(header_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(stride); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(entry); c.load(owner_region); c.call(r.region); c.set(region);
        c.value(region);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.length);
        c.value(Local { 0 }); c.value(Local { 1 }); c.value(Local { 2 }); c.value(Local { 3 }); c.call(r.checked);
        c.op(blot_backend_runtime_ir::OP_drop, 0);
        c.value(Local { 3 }); c.load(array_length);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.address);
        let address = Local { 3 };
        let index = Local { 4 };
        c.value(Local { 0 }); c.value(Local { 1 }); c.value(Local { 2 }); c.value(address); c.call(r.checked);
        c.op(blot_backend_runtime_ir::OP_drop, 0);
        c.value(index); c.value(address); c.load(array_length); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.trap();
        c.value(address); c.value(header_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(index); c.value(address); c.load(array_stride); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.read);
        c.value(Local { 0 }); c.value(Local { 1 }); c.value(Local { 2 }); c.value(Local { 3 }); c.value(Local { 4 }); c.call(r.functions.address); c.load(0);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.write);
        c.value(Local { 0 }); c.value(Local { 1 }); c.value(Local { 2 }); c.value(Local { 3 }); c.value(Local { 4 }); c.call(r.functions.address); c.value(Local { 5 }); c.store(0);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.append_space);
        let token = Local { 0 };
        let address = Local { 3 };
        let slot = c.temp();
        let top = c.temp();
        let stride = c.temp();
        c.value(token); c.value(Local { 1 }); c.value(Local { 2 }); c.value(address); c.call(r.checked); c.set(slot);
        c.value(slot); c.load(slot_top); c.set(top);
        c.value(address); c.load(array_stride); c.set(stride);
        c.value(address); c.load(array_mode); c.value(modeCode(Mode.fixed)); c.op(blot_backend_runtime_ir::OP_i32_eq); c.trap();
        c.value(top); c.value(address); c.value(header_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(address); c.load(array_length); c.value(stride); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
        c.value(stride); c.value(slot); c.load(slot_end); c.value(top); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(top); c.value(0); c.value(stride); c.zero();
        c.value(address); c.value(address); c.load(array_length); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.store(array_length);
        c.value(token); c.value(Local { 1 }); c.value(Local { 2 }); c.call(r.lookup); c.value(top); c.value(stride); c.op(blot_backend_runtime_ir::OP_i32_add); c.store(owner_end);
        c.value(slot); c.value(top); c.value(stride); c.op(blot_backend_runtime_ir::OP_i32_add); c.store(slot_top);
        c.value(top);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.append);
        c.value(Local { 0 }); c.value(Local { 1 }); c.value(Local { 2 }); c.value(Local { 3 }); c.call(r.functions.append_space); c.value(Local { 4 }); c.store(0);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.truncate);
        let token = Local { 0 };
        let address = Local { 3 };
        let count = Local { 4 };
        let slot = c.temp();
        c.value(token); c.value(Local { 1 }); c.value(Local { 2 }); c.value(address); c.call(r.checked); c.set(slot);
        c.value(address); c.load(array_mode); c.value(modeCode(Mode.resize)); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
        c.value(count); c.value(address); c.load(array_length); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(slot); c.load(slot_top); c.value(address); c.value(header_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(address); c.load(array_length); c.value(address); c.load(array_stride); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
        c.value(slot); c.value(address); c.value(header_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.value(address); c.load(array_stride); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.store(slot_top);
        c.value(token); c.value(Local { 1 }); c.value(Local { 2 }); c.call(r.lookup); c.value(slot); c.load(slot_top); c.store(owner_end);
        c.value(address); c.value(count); c.store(array_length);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    {
        var c = blot_emitter::init(module, r.functions.freeze);
        c.value(Local { 0 }); c.value(Local { 1 }); c.value(Local { 2 }); c.value(Local { 3 }); c.call(r.checked);
        c.op(blot_backend_runtime_ir::OP_drop, 0);
        c.value(Local { 3 }); c.value(modeCode(Mode.fixed)); c.store(array_mode);
        { let propagated_error = c.failure; if propagated_error != Error.none { return propagated_error; } }
    }
    return Error.none;
}
