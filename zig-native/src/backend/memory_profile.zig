//! Late, opt-in counters over the instructions that are actually encoded.
//! Diagnostic storage is outside the managed heap and never calls its allocator.
const std = @import("std");
const w = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const heap = @import("../runtime/runtime_layout.zig");
const origins = @import("source_origins.zig");
const Error = std.mem.Allocator.Error || error{ModuleTooLarge};
pub const Metric = enum {
    allocations,
    requested_bytes,
    rounded_bytes,
    frees,
    freed_requested_bytes,
    freed_rounded_bytes,
    live_bytes,
    peak_live_bytes,
    retains,
    releases,
    retired_objects,
    copy_bytes,
    fill_bytes,
    read_bytes,
    write_bytes,
    cycle_passes,
    cycle_vertices,
    cycle_edges,
    cycle_bytes,
    cycle_candidates,
    copy_operations,
    reused_blocks,
    fresh_blocks,
};
pub const metric_count = @typeInfo(Metric).@"enum".field_names.len;
pub const row_bytes = metric_count * 8;
const shadow_slots = 1 << 18;
pub const Category = enum { source, allocation, retirement, roots, cycles, runtime_other };
pub const category_count = @typeInfo(Category).@"enum".field_names.len;
const Source = struct { unit: u32, filename: []const u8, source_blake3: ?[32]u8 };
const Sites = struct {
    items: []const origins.Site,
    pub fn jsonStringify(self: Sites, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginArray();
        for (self.items) |site| {
            try stream.beginObject();
            inline for (.{ "unit", "node", "start", "end", "operation", "source_type", "inline_depth", "inline_truncated" }) |field| {
                try stream.objectField(field);
                try stream.write(@field(site, field));
            }
            try stream.objectField("inline_context");
            try stream.beginArray();
            for (site.inline_context[0..site.inline_depth]) |frame| try stream.write(.{ .unit = frame.unit, .node = frame.node, .start = frame.start, .end = frame.end });
            try stream.endArray();
            try stream.endObject();
        }
        try stream.endArray();
    }
};
pub const Profile = struct {
    module: *const w.Module,
    arena: w.Arena,
    base: u32,
    counters: u32,
    shadow: u32,
    end: u32,
    context_global: u32,
    sites: []const origins.Site,
    compiler_identity: ?[32]u8,
    identity: [32]u8 = @splat(0),
    pub fn init(module: *const w.Module, sites: []const origins.Site, compiler_identity: ?[32]u8) Error!Profile {
        const arena = module.arena.?;
        const base = std.mem.alignForward(u64, @max(module.data.items.len, module.globals.items[arena.heap].bits), 16);
        const shadow = std.mem.alignForward(u64, base + 16 + (sites.len + 2 + category_count) * row_bytes, 16);
        const end = std.mem.alignForward(u64, shadow + shadow_slots * 8, 65536);
        if (end > std.math.maxInt(u32)) return error.ModuleTooLarge;
        return .{ .module = module, .arena = arena, .base = @intCast(base), .counters = @intCast(base + 16), .shadow = @intCast(shadow), .end = @intCast(end), .context_global = @intCast(module.globals.items.len), .sites = sites, .compiler_identity = compiler_identity };
    }
    pub fn metadata(self: Profile, a: std.mem.Allocator) Error![]u8 {
        // Paths and digests belong to source units, not each emitted call site.
        // Intern them once so large diagnostic modules fit the bounded protocol.
        var sources: std.array_hash_map.Auto(u32, Source) = .empty;
        defer sources.deinit(a);
        for (self.sites) |site| try sources.put(a, site.unit, .{ .unit = site.unit, .filename = site.filename, .source_blake3 = site.source_blake3 });
        for (self.sites) |site| for (site.inline_context[0..site.inline_depth]) |frame| {
            const entry = try sources.getOrPut(a, frame.unit);
            if (!entry.found_existing) entry.value_ptr.* = .{ .unit = frame.unit, .filename = frame.filename, .source_blake3 = null };
        };
        return std.json.Stringify.valueAlloc(a, .{
            .version = @as(u32, 2),
            .identity = self.identity,
            .base = self.base,
            .counters = self.counters,
            .row_bytes = row_bytes,
            .total_row = self.sites.len + 1,
            .categories = @typeInfo(Category).@"enum".field_names,
            .category_row = self.sites.len + 2,
            .metrics = @typeInfo(Metric).@"enum".field_names,
            .sources = sources.values(),
            .sites = Sites{ .items = self.sites },
            .compiler_identity = self.compiler_identity,
            .shadow_slots = shadow_slots,
            .reserved_bytes = self.end - self.base,
            .offset_encoding = "utf8_bytes",
            .aggregation = "source site plus up to four source-emission inline callers; later machine-inlined instances of the same origin are aggregated",
            .cycle_candidate_reason = "owning fields without a lifetime-stable no_cycle proof; candidate counts identify admitted objects, not all attempted enqueues",
            .unknown_row = @as(u32, 0),
            .status_bits = .{ .shadow_full = 1, .missing_allocation = 2, .counter_overflow = 4 },
        }, .{});
    }
    /// The live instance exports this fingerprint. Readers must match it before
    /// interpreting counter addresses; an equal table geometry is insufficient.
    pub fn bind(self: *Profile, bodies: anytype) Error!void {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        const description = try self.metadata(self.module.allocator);
        defer self.module.allocator.free(description);
        hash.update(description);
        hash.update(self.module.data.items);
        for (self.module.functions.items, 0..) |function, index| {
            const instructions = if (bodies[index].body) |body| body.instructions.items else function.instructions.items;
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, instructions.len, .little);
            hash.update(&bytes);
            for (instructions) |inst| {
                std.mem.writeInt(u64, &bytes, @bitCast(inst), .little);
                hash.update(&bytes);
            }
        }
        hash.final(&self.identity);
    }
    pub fn category(self: Profile, function: u32) Category {
        inline for (w.Arena.function_fields) |name| if (function == @field(self.arena, name)) {
            if (std.mem.startsWith(u8, name, "cycle_")) return .cycles;
            if (std.mem.startsWith(u8, name, "root_")) return .roots;
            if (std.mem.startsWith(u8, name, "allocate")) return .allocation;
            return .retirement;
        };
        return if (self.module.runtimeHelper(function)) .runtime_other else .source;
    }
    pub fn globalValue(self: Profile, id: usize, value: u32) u32 {
        return if (id == self.arena.heap or id == self.arena.base or id == self.arena.static_end) self.end else value;
    }
};

fn op(b: *w.Bytes, byte: u8, operand: u32) Error!void {
    try b.byte(byte);
    try b.uleb(operand);
}
fn integer(b: *w.Bytes, value: u32) Error!void {
    try b.byte(0x41);
    try b.sleb(@bitCast(value));
}
fn memory(b: *w.Bytes, byte: u8, offset: u32) Error!void {
    try b.byte(byte);
    try b.uleb(if (byte == 0x29 or byte == 0x37) 3 else 2);
    try b.uleb(offset);
}
const Value = union(enum) { constant: u32, local: u32 };
fn emitValue(b: *w.Bytes, input: Value) Error!void {
    switch (input) {
        .constant => |n| try integer(b, n),
        .local => |n| try op(b, 0x20, n),
    }
}

pub const Function = struct {
    profile: Profile,
    function: u32,
    context: u32,
    amount: u32,
    pointer: u32,
    slot: u32,
    probes: u32,
    birth: u32,
    address: u32,
    heap_before: u32,
    pub const local_count = 8;
    pub fn init(profile: Profile, function: u32, locals: usize) Function {
        const base: u32 = @intCast(locals);
        return .{ .profile = profile, .function = function, .context = base, .amount = base + 1, .pointer = base + 2, .slot = base + 3, .probes = base + 4, .birth = base + 5, .address = base + 6, .heap_before = base + 7 };
    }
    fn status(self: Function, b: *w.Bytes, bits: u32) Error!void {
        try integer(b, self.profile.base);
        try integer(b, self.profile.base);
        try memory(b, 0x28, 0);
        try integer(b, bits);
        try b.byte(0x72);
        try memory(b, 0x36, 0);
    }
    fn counter(self: Function, b: *w.Bytes, origin: Value, metric: Metric) Error!void {
        try emitValue(b, origin);
        try integer(b, row_bytes);
        try b.byte(0x6c);
        try integer(b, self.profile.counters + @as(u32, @backingInt(metric)) * 8);
        try b.byte(0x6a);
        try op(b, 0x21, self.address);
    }
    fn change(self: Function, b: *w.Bytes, origin: Value, metric: Metric, quantity: Value, subtract: bool) Error!void {
        try self.counter(b, origin, metric);
        // Counter overflow is diagnostic failure, never silent wraparound.
        try op(b, 0x20, self.address);
        try memory(b, 0x29, 0);
        if (!subtract) {
            try emitValue(b, quantity);
            try b.byte(0xad);
            try b.byte(0x7c);
            try op(b, 0x20, self.address);
            try memory(b, 0x29, 0);
        } else {
            try emitValue(b, quantity);
            try b.byte(0xad);
        }
        try b.byte(0x54); // i64.lt_u
        try b.raw(&.{ 0x04, 0x40 });
        try self.status(b, 4);
        try b.byte(0x0b);
        try op(b, 0x20, self.address);
        try op(b, 0x20, self.address);
        try memory(b, 0x29, 0);
        try emitValue(b, quantity);
        try b.byte(0xad); // i64.extend_i32_u
        try b.byte(if (subtract) 0x7d else 0x7c);
        try memory(b, 0x37, 0);
        if (metric == .live_bytes and !subtract) {
            try op(b, 0x20, self.address);
            try memory(b, 0x29, 0);
            try op(b, 0x20, self.address);
            try memory(b, 0x29, 8);
            try b.byte(0x56); // i64.gt_u
            try b.raw(&.{ 0x04, 0x40 });
            try op(b, 0x20, self.address);
            try op(b, 0x20, self.address);
            try memory(b, 0x29, 0);
            try memory(b, 0x37, 8);
            try b.byte(0x0b);
        }
    }
    fn count(self: Function, b: *w.Bytes, origin: Value, metric: Metric, quantity: Value, subtract: bool) Error!void {
        try self.change(b, origin, metric, quantity, subtract);
        try self.change(b, .{ .constant = @intCast(self.profile.sites.len + 1) }, metric, quantity, subtract);
        // Live ownership belongs to the allocation category even when freed
        // by a retirement helper; this keeps the category balances meaningful.
        const category: Category = if (metric == .live_bytes) .allocation else self.profile.category(self.function);
        try self.change(b, .{ .constant = @intCast(self.profile.sites.len + 2 + @as(usize, @backingInt(category))) }, metric, quantity, subtract);
    }
    /// Search a fixed diagnostic table. Address reuse replaces the old birth
    /// origin. Saturation marks the report incomplete instead of looping forever.
    fn lookup(self: Function, b: *w.Bytes) Error!void {
        try op(b, 0x20, self.pointer);
        try integer(b, 4);
        try b.byte(0x76);
        try integer(b, shadow_slots - 1);
        try b.byte(0x71);
        try op(b, 0x21, self.slot);
        try integer(b, 0);
        try op(b, 0x21, self.probes);
        try b.raw(&.{ 0x02, 0x40, 0x03, 0x40 });
        try op(b, 0x20, self.slot);
        try integer(b, 8);
        try b.byte(0x6c);
        try integer(b, self.profile.shadow);
        try b.byte(0x6a);
        try op(b, 0x21, self.address);
        try op(b, 0x20, self.address);
        try memory(b, 0x28, 0);
        try b.byte(0x45);
        try op(b, 0x20, self.address);
        try memory(b, 0x28, 0);
        try op(b, 0x20, self.pointer);
        try b.byte(0x46);
        try b.byte(0x72);
        try op(b, 0x0d, 1);
        try op(b, 0x20, self.probes);
        try integer(b, 1);
        try b.byte(0x6a);
        try op(b, 0x22, self.probes);
        try integer(b, shadow_slots);
        try b.byte(0x46);
        try b.raw(&.{ 0x04, 0x40 });
        try self.status(b, 1);
        try integer(b, 0);
        try op(b, 0x21, self.address);
        try op(b, 0x0c, 2);
        try b.byte(0x0b);
        try op(b, 0x20, self.slot);
        try integer(b, 1);
        try b.byte(0x6a);
        try integer(b, shadow_slots - 1);
        try b.byte(0x71);
        try op(b, 0x21, self.slot);
        try op(b, 0x0c, 0);
        try b.raw(&.{ 0x0b, 0x0b });
    }
    fn birthOrigin(self: Function, b: *w.Bytes, pointer_local: u32) Error!void {
        try op(b, 0x20, pointer_local);
        try op(b, 0x21, self.pointer);
        try self.lookup(b);
        try integer(b, 0);
        try op(b, 0x21, self.birth);
        try op(b, 0x20, self.address);
        try b.raw(&.{ 0x04, 0x40 });
        try op(b, 0x20, self.address);
        try memory(b, 0x28, 0);
        try op(b, 0x20, self.pointer);
        try b.byte(0x46);
        try b.raw(&.{ 0x04, 0x40 });
        try op(b, 0x20, self.address);
        try memory(b, 0x28, 4);
        try op(b, 0x21, self.birth);
        try b.byte(0x05);
        try self.status(b, 2);
        try b.raw(&.{ 0x0b, 0x0b });
    }
    fn object(self: Function, b: *w.Bytes, allocating: bool) Error!void {
        try self.lookup(b);
        try integer(b, 0);
        try op(b, 0x21, self.birth);
        try op(b, 0x20, self.address);
        try b.raw(&.{ 0x04, 0x40 });
        if (allocating) {
            try op(b, 0x20, self.address);
            try op(b, 0x20, self.pointer);
            try memory(b, 0x36, 0);
            try op(b, 0x20, self.address);
            try op(b, 0x20, self.context);
            try memory(b, 0x36, 4);
        } else {
            try op(b, 0x20, self.address);
            try memory(b, 0x28, 0);
            try op(b, 0x20, self.pointer);
            try b.byte(0x47);
            try b.raw(&.{ 0x04, 0x40 });
            try self.status(b, 2);
            try b.byte(0x05);
            try op(b, 0x20, self.address);
            try memory(b, 0x28, 4);
            try op(b, 0x21, self.birth);
            try b.byte(0x0b);
        }
        try b.byte(0x0b);
        const origin: Value = .{ .local = if (allocating) self.context else self.birth };
        try self.count(b, origin, if (allocating) .allocations else .frees, .{ .constant = 1 }, false);
        inline for (.{ "requested", "block_size" }) |field| {
            try op(b, 0x20, self.pointer);
            try integer(b, @sizeOf(heap.ArenaHeader));
            try b.byte(0x6b);
            try memory(b, 0x28, heap.offset(heap.ArenaHeader, field));
            try op(b, 0x21, self.amount);
            const requested = comptime std.mem.eql(u8, field, "requested");
            const metric: Metric = if (allocating) (if (requested) .requested_bytes else .rounded_bytes) else (if (requested) .freed_requested_bytes else .freed_rounded_bytes);
            try self.count(b, origin, metric, .{ .local = self.amount }, false);
            if (requested) try self.count(b, origin, .live_bytes, .{ .local = self.amount }, !allocating);
        }
    }
    pub fn enter(self: Function, b: *w.Bytes, entry: bool) Error!void {
        if (entry) try integer(b, 0) else try op(b, 0x23, self.profile.context_global);
        try op(b, 0x21, self.context);
        if (self.function == self.profile.arena.allocate) {
            try op(b, 0x23, self.profile.arena.heap);
            try op(b, 0x21, self.heap_before);
        }
        if (self.function == self.profile.arena.copy_words) try self.count(b, .{ .local = self.context }, .copy_operations, .{ .constant = 1 }, false);
        if (self.function == self.profile.arena.free) {
            try op(b, 0x20, 0);
            try op(b, 0x21, self.pointer);
            try self.object(b, false);
        }
    }
    pub fn finish(self: Function, b: *w.Bytes) Error!void {
        if (self.function != self.profile.arena.allocate) return;
        try op(b, 0x22, self.pointer); // preserve the original return value
        try op(b, 0x20, 0);
        try b.raw(&.{ 0x04, 0x40 });
        try self.object(b, true);
        try op(b, 0x20, self.pointer);
        try op(b, 0x20, self.heap_before);
        try b.byte(0x49); // i32.lt_u: retired block below the previous frontier
        try b.raw(&.{ 0x04, 0x40 });
        try self.count(b, .{ .local = self.context }, .reused_blocks, .{ .constant = 1 }, false);
        try b.byte(0x05);
        try self.count(b, .{ .local = self.context }, .fresh_blocks, .{ .constant = 1 }, false);
        try b.raw(&.{ 0x0b, 0x0b });
    }
    fn globalMetric(self: Function, id: u32) ?Metric {
        const a = self.profile.arena;
        inline for (.{ "rc_retains", "rc_releases", "rc_destroyed", "cycle_passes", "cycle_vertices", "cycle_edges", "cycle_bytes" }, .{ Metric.retains, Metric.releases, Metric.retired_objects, Metric.cycle_passes, Metric.cycle_vertices, Metric.cycle_edges, Metric.cycle_bytes }) |field, metric| {
            if (id == @field(a, field)) return metric;
        }
        return null;
    }
    pub fn before(self: Function, b: *w.Bytes, inst: ir.Instruction) Error!void {
        if (inst.op == .return_) try self.finish(b);
        if (inst.op == .call or inst.op == .call_import or inst.op == .call_indirect) {
            if (inst.origin != 0) try integer(b, inst.origin) else try op(b, 0x20, self.context);
            try op(b, 0x24, self.profile.context_global);
        }
        if (inst.op == .memory_copy or inst.op == .memory_fill) try op(b, 0x22, self.amount);
        if (inst.op == .global_set and self.function == self.profile.arena.cycle_enqueue and inst.operand == self.profile.arena.cycle_head) {
            try self.birthOrigin(b, 0);
            try self.count(b, .{ .local = self.birth }, .cycle_candidates, .{ .constant = 1 }, false);
        }
        if (inst.op == .global_set) if (self.globalMetric(inst.operand)) |metric| {
            try op(b, 0x22, self.amount);
            try op(b, 0x20, self.amount);
            try op(b, 0x23, inst.operand);
            try b.byte(0x6b);
            try op(b, 0x21, self.amount);
            var source: Value = .{ .local = self.context };
            if (metric == .cycle_vertices and self.function == self.profile.arena.cycle_visit) {
                try self.birthOrigin(b, 0);
                source = .{ .local = self.birth };
            } else if ((metric == .cycle_edges or metric == .cycle_bytes) and self.function == self.profile.arena.cycle_collect) {
                try self.birthOrigin(b, @import("../runtime/cycles_runtime.zig").collector_object_local);
                source = .{ .local = self.birth };
            }
            try self.count(b, source, metric, .{ .local = self.amount }, false);
        };
    }
    pub fn after(self: Function, b: *w.Bytes, inst: ir.Instruction) Error!void {
        const origin: Value = if (inst.origin != 0) .{ .constant = inst.origin } else .{ .local = self.context };
        if (inst.op == .call or inst.op == .call_import or inst.op == .call_indirect) {
            try op(b, 0x20, self.context);
            try op(b, 0x24, self.profile.context_global);
        }
        if (inst.op == .memory_copy) try self.count(b, origin, .copy_operations, .{ .constant = 1 }, false);
        if (inst.op == .memory_copy or inst.op == .memory_fill) try self.count(b, origin, if (inst.op == .memory_copy) .copy_bytes else .fill_bytes, .{ .local = self.amount }, false);
        const facts = ir.fixed(inst.op);
        if (facts.bytes != 0) {
            const reading = facts.effect == .read;
            try self.count(b, origin, if (reading) .read_bytes else .write_bytes, .{ .constant = facts.bytes }, false);
            if (!reading and self.function == self.profile.arena.copy_words) try self.count(b, origin, .copy_bytes, .{ .constant = facts.bytes }, false);
        }
    }
};
