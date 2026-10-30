//! Bounded nonmoving byte regions with independent, epoch-checked owners.
//! Fixed extents pack together; growers extend only at a region's top. Frame
//! rewind invalidates metadata without tracing any payload or reference graph.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const Code = @import("../backend/runtime_code.zig").Code;
const Local = @import("../backend/runtime_code.zig").Local;
pub const Mode = enum(u32) { fixed, grow, resize };
pub const header_bytes: u32 = 16;
pub const descriptor_words: u32 = 3;
pub const max_stacks: u32 = std.math.maxInt(u32);
pub const data_base: u32 = 65536;
const slot_bytes: u32 = 16;
const slot_base: u32 = 0;
const slot_top: u32 = 4;
const slot_end: u32 = 8;
const owner_bytes: u32 = 28;
const owner_live: u32 = 0;
const owner_region: u32 = 4;
const owner_low: u32 = 8;
const owner_high: u32 = 12;
const owner_base: u32 = 16;
const owner_end: u32 = 20;
const owner_mark: u32 = 24;
const array_token: u32 = 0;
const array_mode: u32 = 4;
const array_length: u32 = 8;
const array_stride: u32 = 12;

pub const Plan = struct { region_capacities: []const u32, owner_capacity: u32 };
pub const Layout = struct { owner_base: u32, data_base: u32, total_bytes: u32 };
pub fn layout(plan: Plan) error{InvalidPlan}!Layout {
    if (plan.region_capacities.len == 0 or plan.owner_capacity == 0) return error.InvalidPlan;
    const metadata = @as(u64, plan.region_capacities.len) * slot_bytes + @as(u64, plan.owner_capacity) * owner_bytes;
    const base = (metadata + 65535) & ~@as(u64, 65535);
    var total = base;
    for (plan.region_capacities) |capacity| {
        if (capacity < header_bytes or capacity & 3 != 0) return error.InvalidPlan;
        total += capacity;
    }
    // Keep end addresses representable; no address arithmetic may wrap.
    if (total > std.math.maxInt(u32)) return error.InvalidPlan;
    return .{ .owner_base = @intCast(plan.region_capacities.len * slot_bytes), .data_base = @intCast(base), .total_bytes = @intCast(total) };
}
pub fn regionBase(plan: Plan, index: u32) error{InvalidPlan}!u32 {
    if (index >= plan.region_capacities.len) return error.InvalidPlan;
    var base = (try layout(plan)).data_base;
    for (plan.region_capacities[0..index]) |capacity| base += capacity;
    return base;
}

pub const Functions = struct {
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
};
pub const Runtime = struct {
    functions: Functions,
    count: u32,
    owner_count: u32,
    owner_extent: u32,
    owner_table: u32,
    serial: u32,
    serial_high: u32,
    lookup: u32,
    entry: u32,
    region: u32,
    checked: u32,
    initialize: u32,
    initialized: u32,
};
fn function(module: *wasm.Module, comptime count: usize, result: wasm.ValueType) !u32 {
    return module.addTypedFunction(&@as([count]wasm.ValueType, @splat(.i32)), result, .scalar);
}
fn code(module: *wasm.Module, id: u32) Code {
    return .{ .module = module, .function = id };
}
/// Dead trailing entries cannot participate in a lookup. Keep holes below the
/// last live owner so out-of-order closes and persistent owners retain identity.
fn trimOwners(c: Code, r: Runtime) !void {
    const entry_ = try c.temp();
    try c.loop(.{ .global, r.owner_extent });
    try c.set(entry_, .{ .i32_add, .{ .global, r.owner_table }, .{ .i32_mul, .{ .i32_sub, .{ .global, r.owner_extent }, 1 }, owner_bytes } });
    try c.value(.{ .load, entry_, owner_live });
    try c.op(.br_if, 1);
    try c.value(.{ .i32_sub, .{ .global, r.owner_extent }, 1 });
    try c.op(.global_set, r.owner_extent);
    try c.again();
}
pub fn finishPlan(module: *wasm.Module, r: Runtime, plan: Plan) !void {
    const memory = try layout(plan);
    module.globals.items[r.count].bits = @intCast(plan.region_capacities.len);
    module.globals.items[r.owner_count].bits = plan.owner_capacity;
    module.globals.items[r.owner_table].bits = memory.owner_base;
    module.fixed_memory_bytes = memory.total_bytes;
    const c = code(module, r.initialize);
    try c.when(.{ .i32_eqz, .{ .global, r.initialized } });
    try c.zero(0, memory.data_base);
    var base = memory.data_base;
    for (plan.region_capacities, 0..) |capacity, index| {
        const slot: u32 = @intCast(index * slot_bytes);
        try c.store(slot, slot_base, base);
        try c.store(slot, slot_top, base);
        base += capacity;
        try c.store(slot, slot_end, base);
    }
    try c.value(1);
    try c.op(.global_set, r.initialized);
    try c.end();
}
pub fn emit(module: *wasm.Module) !Runtime {
    if (module.arena != null or module.fixed_memory_bytes != 0 or
        module.data.items.len != 0 or module.artifacts != null) return error.InvalidStorageConfiguration;
    module.memory_model = .data_stacks;
    module.fixed_memory_bytes = data_base;
    const r: Runtime = .{
        .functions = .{
            .reset = try function(module, 0, .none),
            .reset_temporary = try function(module, 1, .none),
            .open = try function(module, 1, .i32),
            .epoch_low = try function(module, 1, .i32),
            .epoch_high = try function(module, 1, .i32),
            .close = try function(module, 3, .none),
            .mark = try function(module, 1, .i32),
            .rewind = try function(module, 2, .none),
            .create = try function(module, 6, .i32),
            .length = try function(module, 4, .i32),
            .read = try function(module, 5, .i32),
            .write = try function(module, 6, .none),
            .append = try function(module, 5, .none),
            .append_space = try function(module, 4, .i32),
            .truncate = try function(module, 5, .none),
            .freeze = try function(module, 4, .none),
            .address = try function(module, 5, .i32),
        },
        .count = try module.addGlobal(.u32, 0, false),
        .owner_count = try module.addGlobal(.u32, 0, false),
        .owner_extent = try module.addGlobal(.u32, 0, true),
        .owner_table = try module.addGlobal(.u32, 0, false),
        .serial = try module.addGlobal(.u32, 0, true),
        .serial_high = try module.addGlobal(.u32, 0, true),
        .lookup = try function(module, 3, .i32),
        .entry = try function(module, 1, .i32),
        .region = try function(module, 1, .i32),
        .checked = try function(module, 4, .i32),
        .initialize = try function(module, 0, .none),
        .initialized = try module.addGlobal(.u32, 0, true),
    };
    {
        const c = code(module, r.region);
        try c.value(.{ .call, r.initialize });
        try c.trap(.{ .i32_ge_u, Local{ .id = 0 }, .{ .global, r.count } });
        try c.value(.{ .i32_mul, Local{ .id = 0 }, slot_bytes });
    }
    {
        const c = code(module, r.entry);
        const owner: Local = .{ .id = 0 };
        try c.value(.{ .call, r.initialize });
        try c.trap(.{ .i32_or, .{ .i32_eqz, owner }, .{ .i32_gt_u, owner, .{ .global, r.owner_count } } });
        try c.value(.{ .i32_add, .{ .global, r.owner_table }, .{ .i32_mul, .{ .i32_sub, owner, 1 }, owner_bytes } });
    }
    {
        const c = code(module, r.lookup);
        const entry_ = try c.temp();
        try c.set(entry_, .{ .call, r.entry, Local{ .id = 0 } });
        try c.trap(.{ .i32_eqz, .{ .load, entry_, owner_live } });
        try c.trap(.{ .i32_ne, .{ .load, entry_, owner_low }, Local{ .id = 1 } });
        try c.trap(.{ .i32_ne, .{ .load, entry_, owner_high }, Local{ .id = 2 } });
        try c.value(entry_);
    }
    inline for (.{ .{ r.functions.epoch_low, owner_low }, .{ r.functions.epoch_high, owner_high } }) |item| {
        const c = code(module, item[0]);
        const entry_ = try c.temp();
        try c.set(entry_, .{ .call, r.entry, Local{ .id = 0 } });
        try c.trap(.{ .i32_eqz, .{ .load, entry_, owner_live } });
        try c.value(.{ .load, entry_, item[1] });
    }
    {
        const c = code(module, r.functions.open);
        const region_: Local = .{ .id = 0 };
        const index = try c.temp();
        const entry_ = try c.temp();
        try c.value(.{ .call, r.region, region_ });
        try c.op(.drop, 0);
        try c.set(index, 0);
        try c.loop(.{ .i32_lt_u, index, .{ .global, r.owner_count } });
        try c.set(entry_, .{ .i32_add, .{ .global, r.owner_table }, .{ .i32_mul, index, owner_bytes } });
        try c.when(.{ .i32_eqz, .{ .load, entry_, owner_live } });
        // Increment the full 64-bit epoch before publication; exhaustion traps.
        try c.trap(.{ .i32_and, .{ .i32_eq, .{ .global, r.serial }, 0xffffffff }, .{ .i32_eq, .{ .global, r.serial_high }, 0xffffffff } });
        try c.value(.{ .i32_add, .{ .global, r.serial }, 1 });
        try c.op(.global_set, r.serial);
        try c.when(.{ .i32_eqz, .{ .global, r.serial } });
        try c.value(.{ .i32_add, .{ .global, r.serial_high }, 1 });
        try c.op(.global_set, r.serial_high);
        try c.end();
        try c.zero(entry_, owner_bytes);
        try c.store(entry_, owner_region, region_);
        try c.store(entry_, owner_mark, .{ .load, .{ .call, r.region, region_ }, slot_top });
        try c.store(entry_, owner_low, .{ .global, r.serial });
        try c.store(entry_, owner_high, .{ .global, r.serial_high });
        try c.store(entry_, owner_live, 1);
        try c.when(.{ .i32_ge_u, index, .{ .global, r.owner_extent } });
        try c.value(.{ .i32_add, index, 1 });
        try c.op(.global_set, r.owner_extent);
        try c.end();
        try c.ret(.{ .i32_add, index, 1 });
        try c.end();
        try c.next(index);
        try c.again();
        try c.op(.unreachable_, 0);
    }
    {
        const c = code(module, r.functions.close);
        const owner: Local = .{ .id = 0 };
        const entry_ = try c.temp();
        const region_ = try c.temp();
        try c.when(owner);
        try c.set(entry_, .{ .call, r.lookup, owner, Local{ .id = 1 }, Local{ .id = 2 } });
        try c.set(region_, .{ .call, r.region, .{ .load, entry_, owner_region } });
        try c.when(.{ .i32_and, .{ .i32_ne, .{ .load, entry_, owner_base }, 0 }, .{ .i32_eq, .{ .load, entry_, owner_end }, .{ .load, region_, slot_top } } });
        try c.store(region_, slot_top, .{ .load, entry_, owner_base });
        try c.end();
        try c.store(entry_, owner_live, 0);
        try trimOwners(c, r);
        try c.end();
    }
    {
        const c = code(module, r.functions.mark);
        try c.value(.{ .load, .{ .call, r.region, Local{ .id = 0 } }, slot_top });
    }
    {
        const c = code(module, r.functions.rewind);
        const id: Local = .{ .id = 0 };
        const mark: Local = .{ .id = 1 };
        const region_ = try c.temp();
        const index = try c.temp();
        const entry_ = try c.temp();
        try c.set(region_, .{ .call, r.region, id });
        try c.trap(.{ .i32_or, .{ .i32_and, mark, 3 }, .{ .i32_lt_u, mark, .{ .load, region_, slot_base } } });
        try c.trap(.{ .i32_gt_u, mark, .{ .load, region_, slot_top } });
        try c.set(index, 0);
        // Validate all owners before changing any state. A mark cannot cut an
        // initialized extent in half or resurrect an owner after failure.
        try c.loop(.{ .i32_lt_u, index, .{ .global, r.owner_extent } });
        try c.set(entry_, .{ .i32_add, .{ .global, r.owner_table }, .{ .i32_mul, index, owner_bytes } });
        try c.when(.{ .i32_and, .{ .load, entry_, owner_live }, .{ .i32_eq, .{ .load, entry_, owner_region }, id } });
        try c.trap(.{ .i32_and, .{ .i32_lt_u, .{ .load, entry_, owner_base }, mark }, .{ .i32_gt_u, .{ .load, entry_, owner_end }, mark } });
        try c.end();
        try c.next(index);
        try c.again();
        try c.set(index, 0);
        try c.loop(.{ .i32_lt_u, index, .{ .global, r.owner_extent } });
        try c.set(entry_, .{ .i32_add, .{ .global, r.owner_table }, .{ .i32_mul, index, owner_bytes } });
        try c.when(.{ .i32_and, .{ .load, entry_, owner_live }, .{ .i32_eq, .{ .load, entry_, owner_region }, id } });
        try c.when(.{ .i32_or, .{ .i32_ge_u, .{ .load, entry_, owner_base }, mark }, .{ .i32_and, .{ .i32_eqz, .{ .load, entry_, owner_base } }, .{ .i32_ge_u, .{ .load, entry_, owner_mark }, mark } } });
        try c.store(entry_, owner_live, 0);
        try c.end();
        try c.end();
        try c.next(index);
        try c.again();
        try c.store(region_, slot_top, mark);
        try trimOwners(c, r);
    }
    {
        const c = code(module, r.functions.reset_temporary);
        const first: Local = .{ .id = 0 };
        const index = try c.temp();
        const entry_ = try c.temp();
        const region_ = try c.temp();
        try c.value(.{ .call, r.initialize });
        try c.trap(.{ .i32_gt_u, first, .{ .global, r.count } });
        try c.set(index, 0);
        try c.loop(.{ .i32_lt_u, index, .{ .global, r.owner_extent } });
        try c.set(entry_, .{ .i32_add, .{ .global, r.owner_table }, .{ .i32_mul, index, owner_bytes } });
        try c.when(.{ .i32_ge_u, .{ .load, entry_, owner_region }, first });
        try c.store(entry_, owner_live, 0);
        try c.end();
        try c.next(index);
        try c.again();
        try trimOwners(c, r);
        try c.set(index, first);
        try c.loop(.{ .i32_lt_u, index, .{ .global, r.count } });
        try c.set(region_, .{ .i32_mul, index, slot_bytes });
        try c.store(region_, slot_top, .{ .load, region_, slot_base });
        try c.next(index);
        try c.again();
    }
    {
        const c = code(module, r.functions.reset);
        try c.value(.{ .call, r.functions.reset_temporary, 0 });
    }
    {
        const c = code(module, r.functions.create);
        const token: Local = .{ .id = 0 };
        const count: Local = .{ .id = 3 };
        const mode: Local = .{ .id = 4 };
        const stride: Local = .{ .id = 5 };
        const entry = try c.temp();
        const slot = try c.temp();
        const address = try c.temp();
        const available = try c.temp();
        const bytes = try c.temp();
        try c.set(entry, .{ .call, r.lookup, token, Local{ .id = 1 }, Local{ .id = 2 } });
        try c.trap(.{ .load, entry, owner_base });
        try c.set(slot, .{ .call, r.region, .{ .load, entry, owner_region } });
        try c.set(address, .{ .load, slot, slot_top });
        try c.set(available, .{ .i32_sub, .{ .load, slot, slot_end }, address });
        try c.trap(.{ .i32_lt_u, available, header_bytes });
        try c.trap(.{ .i32_or, .{ .i32_eqz, stride }, .{ .i32_and, stride, 3 } });
        try c.trap(.{ .i32_gt_u, mode, @backingInt(Mode.resize) });
        try c.trap(.{ .i32_gt_u, count, .{ .i32_div_u, .{ .i32_sub, available, header_bytes }, stride } });
        try c.set(bytes, .{ .i32_add, header_bytes, .{ .i32_mul, count, stride } });
        try c.zero(address, bytes);
        try c.store(address, array_token, token);
        try c.store(address, array_mode, mode);
        try c.store(address, array_length, count);
        try c.store(address, array_stride, stride);
        try c.store(entry, owner_base, address);
        try c.store(entry, owner_end, .{ .i32_add, address, bytes });
        try c.store(slot, slot_top, .{ .i32_add, address, bytes });
        try c.value(address);
    }
    {
        const c = code(module, r.checked);
        const owner: Local = .{ .id = 0 };
        const address: Local = .{ .id = 3 };
        const entry = try c.temp();
        const region = try c.temp();
        const stride = try c.temp();
        try c.set(entry, .{ .call, r.lookup, owner, Local{ .id = 1 }, Local{ .id = 2 } });
        try c.trap(.{ .i32_or, .{ .i32_eqz, address }, .{ .i32_ne, address, .{ .load, entry, owner_base } } });
        try c.trap(.{ .i32_ne, .{ .load, address, array_token }, owner });
        try c.set(stride, .{ .load, address, array_stride });
        try c.trap(.{ .i32_or, .{ .i32_eqz, stride }, .{ .i32_and, stride, 3 } });
        try c.trap(.{ .i32_gt_u, .{ .load, address, array_length }, .{ .i32_div_u, .{ .i32_sub, .{ .i32_sub, .{ .load, entry, owner_end }, address }, header_bytes }, stride } });
        try c.set(region, .{ .call, r.region, .{ .load, entry, owner_region } });
        try c.value(region);
    }
    {
        const c = code(module, r.functions.length);
        try c.value(.{ .call, r.checked, Local{ .id = 0 }, Local{ .id = 1 }, Local{ .id = 2 }, Local{ .id = 3 } });
        try c.op(.drop, 0);
        try c.value(.{ .load, Local{ .id = 3 }, array_length });
    }
    {
        const c = code(module, r.functions.address);
        const address: Local = .{ .id = 3 };
        const index: Local = .{ .id = 4 };
        try c.value(.{ .call, r.checked, Local{ .id = 0 }, Local{ .id = 1 }, Local{ .id = 2 }, address });
        try c.op(.drop, 0);
        try c.trap(.{ .i32_ge_u, index, .{ .load, address, array_length } });
        try c.value(.{ .i32_add, .{ .i32_add, address, header_bytes }, .{ .i32_mul, index, .{ .load, address, array_stride } } });
    }
    {
        const c = code(module, r.functions.read);
        try c.value(.{ .load, .{ .call, r.functions.address, Local{ .id = 0 }, Local{ .id = 1 }, Local{ .id = 2 }, Local{ .id = 3 }, Local{ .id = 4 } }, 0 });
    }
    {
        const c = code(module, r.functions.write);
        try c.store(.{ .call, r.functions.address, Local{ .id = 0 }, Local{ .id = 1 }, Local{ .id = 2 }, Local{ .id = 3 }, Local{ .id = 4 } }, 0, Local{ .id = 5 });
    }
    {
        const c = code(module, r.functions.append_space);
        const token: Local = .{ .id = 0 };
        const address: Local = .{ .id = 3 };
        const slot = try c.temp();
        const top = try c.temp();
        const stride = try c.temp();
        try c.set(slot, .{ .call, r.checked, token, Local{ .id = 1 }, Local{ .id = 2 }, address });
        try c.set(top, .{ .load, slot, slot_top });
        try c.set(stride, .{ .load, address, array_stride });
        try c.trap(.{ .i32_eq, .{ .load, address, array_mode }, @backingInt(Mode.fixed) });
        try c.trap(.{ .i32_ne, top, .{ .i32_add, .{ .i32_add, address, header_bytes }, .{ .i32_mul, .{ .load, address, array_length }, stride } } });
        try c.trap(.{ .i32_gt_u, stride, .{ .i32_sub, .{ .load, slot, slot_end }, top } });
        try c.zero(top, stride);
        try c.store(address, array_length, .{ .i32_add, .{ .load, address, array_length }, 1 });
        try c.store(.{ .call, r.lookup, token, Local{ .id = 1 }, Local{ .id = 2 } }, owner_end, .{ .i32_add, top, stride });
        try c.store(slot, slot_top, .{ .i32_add, top, stride });
        try c.value(top);
    }
    {
        const c = code(module, r.functions.append);
        try c.store(.{ .call, r.functions.append_space, Local{ .id = 0 }, Local{ .id = 1 }, Local{ .id = 2 }, Local{ .id = 3 } }, 0, Local{ .id = 4 });
    }
    {
        const c = code(module, r.functions.truncate);
        const token: Local = .{ .id = 0 };
        const address: Local = .{ .id = 3 };
        const count: Local = .{ .id = 4 };
        const slot = try c.temp();
        try c.set(slot, .{ .call, r.checked, token, Local{ .id = 1 }, Local{ .id = 2 }, address });
        try c.trap(.{ .i32_ne, .{ .load, address, array_mode }, @backingInt(Mode.resize) });
        try c.trap(.{ .i32_gt_u, count, .{ .load, address, array_length } });
        try c.trap(.{ .i32_ne, .{ .load, slot, slot_top }, .{ .i32_add, .{ .i32_add, address, header_bytes }, .{ .i32_mul, .{ .load, address, array_length }, .{ .load, address, array_stride } } } });
        try c.store(slot, slot_top, .{ .i32_add, .{ .i32_add, address, header_bytes }, .{ .i32_mul, count, .{ .load, address, array_stride } } });
        try c.store(.{ .call, r.lookup, token, Local{ .id = 1 }, Local{ .id = 2 } }, owner_end, .{ .load, slot, slot_top });
        try c.store(address, array_length, count);
    }
    {
        const c = code(module, r.functions.freeze);
        try c.value(.{ .call, r.checked, Local{ .id = 0 }, Local{ .id = 1 }, Local{ .id = 2 }, Local{ .id = 3 } });
        try c.op(.drop, 0);
        try c.store(Local{ .id = 3 }, array_mode, @backingInt(Mode.fixed));
    }
    return r;
}
