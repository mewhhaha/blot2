//! Detached late Source view for a freshly rederived closed activation.
const std = @import("std");
const wasm = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const graph = @import("activation_graph.zig");
const runtime = @import("../runtime/cohort_runtime.zig");
const A = std.mem.Allocator;
pub fn possible(source: *const wasm.Module) bool {
    if (source.arena == null or source.semantic_sites.items.len == 0 or source.cohorts != null) return false;
    for (source.table_origins.items) |origin| if (origin.kind == .demand) return true;
    return false;
}
/// Search exact private State installation boundaries, in stable function
/// order. Size, source spelling and benchmark identity never select a region.
pub fn prepare(a: A, source: *const wasm.Module, model: @import("activation_intersection.zig").Model) A.Error!?Extension {
    if (!possible(source)) return null;
    for (source.functions.items, 0..) |*body, id| {
        if (body.entry or body.result_role != .scalar) continue;
        var named = false;
        for (model.functions) |entry| if (entry.function == id and entry.request == .named) {
            named = true;
        };
        if (!named) continue;
        var installation = false;
        for (body.instructions.items, 0..) |_, at| if (@import("provider_origins.zig").constructor(source, body, at) != null) {
            installation = true;
            break;
        };
        if (!installation) continue;
        if (try checked(a, source, model, @intCast(id))) |view| return view;
    }
    return null;
}
pub const Extension = struct {
    module: wasm.Module,
    original_functions: usize,
    original_signatures: usize,
    owned: []bool,
    pub fn deinit(self: *Extension) void {
        const a = self.module.allocator;
        for (self.module.functions.items, 0..) |*body, id| {
            if (id >= self.original_functions or self.owned[id]) body.deinit(a);
        }
        for (self.module.signatures.items[@min(self.original_signatures, self.module.signatures.items.len)..]) |signature| a.free(signature.parameters);
        self.module.signatures.deinit(a);
        self.module.functions.deinit(a);
        a.free(self.owned);
    }
    pub fn own(self: *Extension, id: u32) A.Error!*ir.Function {
        const body = &self.module.functions.items[id];
        if (!self.owned[id]) {
            var locals = try body.locals.clone(self.module.allocator);
            errdefer locals.deinit(self.module.allocator);
            const instructions = try body.instructions.clone(self.module.allocator);
            body.locals = locals;
            body.instructions = instructions;
            self.owned[id] = true;
        }
        return body;
    }
};
fn rewriteSource(view: *Extension, proof: *const graph.Cohort, helpers: runtime.Runtime) !void {
    const a = view.module.allocator;
    const owner = proof.graph.sites[proof.owner];
    var owner_end: ?usize = null;
    var owner_local: ?u32 = null;
    const original_owner = &view.module.functions.items[owner.function];
    for (original_owner.instructions.items, 0..) |_, at| {
        const fact = @import("provider_origins.zig").constructor(&view.module, original_owner, at) orelse continue;
        if (fact.allocation != owner.at) continue;
        owner_end = fact.end;
        owner_local = fact.local;
    }
    if (owner_end == null) return error.UnsupportedCohort;
    for (0..view.original_functions) |function| {
        var touched = owner.function == function;
        for (proof.graph.sites, 0..) |site, id| if (proof.members & (@as(u64, 1) << @intCast(id)) != 0 and site.function == function) {
            touched = true;
        };
        if (!touched) continue;
        const body = try view.own(@intCast(function));
        var replacement: std.ArrayList(ir.Instruction) = .empty;
        errdefer replacement.deinit(a);
        for (body.instructions.items, 0..) |inst, at| {
            var member = false;
            for (proof.graph.sites, 0..) |site, id| if (proof.members & (@as(u64, 1) << @intCast(id)) != 0 and site.function == function and site.at == at) {
                member = true;
            };
            if (member) {
                const annotations = ir.allocationAnnotations(body.instructions.items, at);
                var mask: u32 = 0;
                var matched = false;
                for (proof.graph.sites, 0..) |site, id| if (proof.members & (@as(u64, 1) << @intCast(id)) != 0 and site.function == function and site.at == at) {
                    if (site.bytes / 4 > 31) return error.UnsupportedCohort;
                    for (0..site.bytes / 4) |word| switch (ir.Ownership.wordRole(annotations, word)) {
                        .scalar => {},
                        .reference => mask |= @as(u32, 1) << @intCast(word),
                        else => return error.UnsupportedCohort,
                    };
                    matched = true;
                    break;
                };
                if (!matched or inst.op != .call or !view.module.arena.?.isAllocation(inst.operand) or body.provider_parameter >= body.parameters.len) return error.UnsupportedCohort;
                try replacement.appendSlice(a, &.{ .{ .op = .i32_const, .operand = mask }, .{ .op = .local_get, .operand = body.provider_parameter }, .{ .op = .call, .operand = helpers.allocate } });
            } else try replacement.append(a, inst);
            if (owner.function == function and at == owner_end.?) {
                try replacement.appendSlice(a, &.{ .{ .op = .local_get, .operand = owner_local.? }, .{ .op = .call, .operand = helpers.begin } });
            }
        }
        body.instructions.deinit(a);
        body.instructions = replacement;
    }
}
fn storeFastpath(view: *Extension) !void {
    const body = try view.own(view.module.arena.?.store_word);
    var at: ?usize = null;
    for (body.instructions.items, 0..) |inst, id| if (inst.op == .wide_layouts) {
        at = id;
        break;
    };
    // The ordinary generated helper validates counted storage, alignment and
    // full field bounds before selecting narrow/wide reference slots.
    const position = at orelse return error.UnsupportedCohort;
    const header = @sizeOf(@import("../runtime/runtime_layout.zig").ArenaHeader);
    const flags = @import("../runtime/runtime_layout.zig").offset(@import("../runtime/runtime_layout.zig").ArenaHeader, "flags");
    try body.instructions.insertSlice(view.module.allocator, position, &.{
        .{ .op = .local_get }, .{ .op = .i32_const, .operand = header }, .{ .op = .i32_sub },                 .{ .op = .i32_load, .operand = flags }, .{ .op = .i32_const, .operand = runtime.member }, .{ .op = .i32_and },
        .{ .op = .local_get }, .{ .op = .i32_const, .operand = header }, .{ .op = .i32_sub },                 .{ .op = .i32_load, .operand = flags }, .{ .op = .i32_const, .operand = runtime.owner },  .{ .op = .i32_and },
        .{ .op = .i32_eqz },   .{ .op = .i32_eqz },                      .{ .op = .local_get, .operand = 1 }, .{ .op = .local_get },                  .{ .op = .i32_const, .operand = 4 },              .{ .op = .i32_add },
        .{ .op = .i32_eq },    .{ .op = .i32_and },                      .{ .op = .i32_or },                  .{ .op = .if_ },                        .{ .op = .local_get, .operand = 1 },              .{ .op = .local_get, .operand = 2 },
        .{ .op = .i32_store }, .{ .op = .return_ },                      .{ .op = .end },
    });
}
// The freshly checked graph has no live outgoing member edge or resource
// obligation. Preserve complete-set validation and dead marking, then recycle
// each physical block without running a typed outgoing-edge destructor.
fn closedRetirement(view: *Extension, proof: *const graph.Cohort, helper: u32) !void {
    var allowed = proof.members | (@as(u64, 1) << proof.owner);
    for (proof.graph.sites, 0..) |site, id| if (site.kind == .static_data) {
        allowed |= @as(u64, 1) << @intCast(id);
    };
    for (proof.graph.sites, 0..) |site, id| if (proof.members & (@as(u64, 1) << @intCast(id)) != 0) {
        if (site.borrowed_head or site.children & ~allowed != 0) return error.UnsupportedCohort;
    };
    const arena = view.module.arena.?;
    const body = &view.module.functions.items[helper];
    var replacement: std.ArrayList(ir.Instruction) = .empty;
    errdefer replacement.deinit(view.module.allocator);
    var found: usize = 0;
    for (body.instructions.items) |inst| {
        if (inst.op != .call or inst.operand != arena.retire) {
            try replacement.append(view.module.allocator, inst);
            continue;
        }
        try replacement.appendSlice(view.module.allocator, &.{
            .{ .op = .global_get, .operand = arena.rc_destroyed }, .{ .op = .i32_const, .operand = 1 },     .{ .op = .i32_add },
            .{ .op = .global_set, .operand = arena.rc_destroyed }, .{ .op = .call, .operand = arena.free },
        });
        found += 1;
    }
    if (found != 1) return error.UnsupportedCohort;
    body.instructions.deinit(view.module.allocator);
    body.instructions = replacement;
}
pub fn checked(a: A, source: *const wasm.Module, model: @import("activation_intersection.zig").Model, boundary: u32) A.Error!?Extension {
    var proof = (try @import("activation_intersection.zig").analyze(a, source, model, boundary)) orelse return null;
    defer proof.deinit(a);
    return extend(a, source, &proof.runtime) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
}
/// Allocation-failure laws isolate extension ownership from the independently
/// qualified readers. Runtime-only reports cannot enter production this way.
pub fn extensionForTest(a: A, source: *const wasm.Module, boundary: u32) !?Extension {
    if (!@import("builtin").is_test) @compileError("test-only cohort mechanics");
    var proof = (try graph.cohort(a, source, boundary)) orelse return null;
    defer proof.deinit(a);
    return try extend(a, source, &proof);
}
fn extend(a: A, source: *const wasm.Module, proof: *const graph.Cohort) !Extension {
    var view = try detached(a, source);
    errdefer view.deinit();
    const helpers = try runtime.install(&view.module);
    try rewriteSource(&view, proof, helpers);
    const arena = source.arena.?;
    const retire = try view.own(arena.retire);
    try retire.instructions.insertSlice(a, 0, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = helpers.retire_members } });
    for ([_]struct { id: u32, mask: u32 }{
        .{ .id = arena.cycle_enqueue, .mask = @import("../runtime/cycles_runtime.zig").enqueue_guard },
        .{ .id = arena.cycle_visit, .mask = @import("../runtime/cycles_runtime.zig").visit_guard },
    }) |guard| {
        const body = try view.own(guard.id);
        var matched: usize = 0;
        for (body.instructions.items) |*inst| if (inst.op == .i32_const and inst.operand == guard.mask) {
            inst.operand |= runtime.member | runtime.owner;
            matched += 1;
        };
        if (matched != 1) return error.UnsupportedCohort;
    }
    try storeFastpath(&view);
    try closedRetirement(&view, proof, helpers.retire_members);
    return view;
}

/// Own the containers before any helper can grow a function or type table.
pub fn detached(a: A, source: *const wasm.Module) A.Error!Extension {
    var view: Extension = .{ .module = source.*, .original_functions = source.functions.items.len, .original_signatures = source.signatures.items.len, .owned = try a.alloc(bool, source.functions.items.len) };
    @memset(view.owned, false);
    view.module.allocator = a;
    view.module.artifacts = null;
    view.module.functions = .empty;
    view.module.signatures = .empty;
    errdefer view.deinit();
    try view.module.functions.appendSlice(a, source.functions.items);
    try view.module.signatures.appendSlice(a, source.signatures.items);
    return view;
}
