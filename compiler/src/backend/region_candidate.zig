//! Detached physical region, authorized only by freshly intersected owned graphs.
const std = @import("std");
const w = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const cohort = @import("cohort_candidate.zig");
const intersection = @import("activation_intersection.zig");
const runtime = @import("../runtime/region_runtime.zig");
const A = std.mem.Allocator;
const absent = std.math.maxInt(u32);
pub const Extension = struct {
    view: cohort.Extension,
    members: []runtime.Member,
    scopes: []runtime.Scope,
    boundary: u32,
    pub fn deinit(self: *Extension) void {
        const a = self.view.module.allocator;
        self.view.deinit();
        a.free(self.members);
        a.free(self.scopes);
    }
};
pub fn prepare(a: A, source: *const w.Module, model: intersection.Model) A.Error!?Extension {
    if (!cohort.possible(source) or source.regions != null) return null;
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
pub fn checked(a: A, source: *const w.Module, model: intersection.Model, boundary: u32) A.Error!?Extension {
    var proof = (try intersection.analyze(a, source, model, boundary)) orelse return null;
    defer proof.deinit(a);
    return extend(a, source, &proof) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
}
pub fn extensionForTest(a: A, source: *const w.Module, proof: *const intersection.Intersection) !Extension {
    if (!@import("builtin").is_test) @compileError("test-only region preparation");
    return extend(a, source, proof);
}
fn extend(a: A, source: *const w.Module, proof: *const intersection.Intersection) !Extension {
    const graph = &proof.runtime.graph;
    const owner = graph.sites[proof.runtime.owner];
    const original = &source.functions.items[owner.function];
    var constructor: ?@import("provider_origins.zig").Fact = null;
    for (original.instructions.items, 0..) |_, at| {
        const fact = @import("provider_origins.zig").constructor(source, original, at) orelse continue;
        if (fact.allocation == owner.at) constructor = fact;
    }
    const fact = constructor orelse return error.Unavailable;
    if (fact.kind != @import("../runtime/runtime_layout.zig").StateFrame.tag or fact.value_role != .reference or owner.bytes != @sizeOf(@import("../runtime/runtime_layout.zig").StateFrame)) return error.Unavailable;
    var scopes: std.ArrayList(runtime.Scope) = .empty;
    defer scopes.deinit(a);
    const owner_bit = @as(u64, 1) << proof.runtime.owner;
    for (source.functions.items, 0..) |body, id| {
        var used = false;
        for (graph.contexts, 0..) |context, context_id| {
            if (context.function != id or context_id == 0) continue;
            if (context.provider != owner_bit or context.outside_provider or body.provider_parameter >= body.parameters.len) return error.Unavailable;
            used = true;
        }
        if (used) try scopes.append(a, .{ .function = @intCast(id), .parameter = body.provider_parameter });
    }
    var members: std.ArrayList(runtime.Member) = .empty;
    defer members.deinit(a);
    var size = owner.bytes;
    var offsets: [64]u32 = @splat(absent);
    for (graph.sites, 0..) |site, id| {
        if (proof.runtime.members & (@as(u64, 1) << @intCast(id)) == 0) continue;
        for (graph.sites[0..id], 0..) |previous, previous_id| {
            if (proof.runtime.members & (@as(u64, 1) << @intCast(previous_id)) == 0) continue;
            if (site.function == previous.function and site.at == previous.at) return error.Unavailable;
        }
        offsets[id] = size;
        try members.append(a, .{ .offset = size, .bytes = site.bytes, .demand = site.kind == .memo });
        size = std.math.add(u32, size, site.bytes) catch return error.Unavailable;
    }
    var mask: u32 = 0;
    const annotations = ir.allocationAnnotations(original.instructions.items, owner.at);
    for (0..owner.bytes / 4) |word| {
        const role = ir.Ownership.wordRole(annotations, word);
        if (role != .reference and role != .scalar) return error.Unavailable;
        if (word != @offsetOf(@import("../runtime/runtime_layout.zig").StateFrame, "value") / 4 and role == .reference) mask |= @as(u32, 1) << @intCast(word);
    }
    const plan: runtime.Plan = .{ .frame_bytes = owner.bytes, .bytes = size, .mask = mask, .members = members.items };
    if (!plan.valid()) return error.Unavailable;
    var result: Extension = .{ .view = try cohort.detached(a, source), .members = &.{}, .scopes = &.{}, .boundary = owner.function };
    errdefer result.deinit();
    result.members = try members.toOwnedSlice(a);
    result.scopes = try scopes.toOwnedSlice(a);
    const owned_plan: runtime.Plan = .{ .frame_bytes = plan.frame_bytes, .bytes = plan.bytes, .mask = plan.mask, .members = result.members };
    const helpers = try runtime.install(&result.view.module, owned_plan);
    result.view.module.regions = .{ .runtime = helpers, .plan = owned_plan, .scopes = result.scopes };
    for (0..result.view.original_functions) |function| {
        var touched = function == owner.function;
        for (graph.sites, 0..) |site, id| if (proof.runtime.members & (@as(u64, 1) << @intCast(id)) != 0 and site.function == function) {
            touched = true;
        };
        const force = @import("../eval/demand_origins.zig").force(source, @intCast(function));
        if (force != null) for (result.scopes) |scope| if (scope.function == function) {
            touched = true;
        };
        if (!touched) continue;
        const body = try result.view.own(@intCast(function));
        var replacement: std.ArrayList(ir.Instruction) = .empty;
        errdefer replacement.deinit(a);
        for (body.instructions.items, 0..) |instruction, at| {
            var offset: ?u32 = null;
            for (graph.sites, 0..) |site, id| if (offsets[id] != absent and site.function == function and site.at == at) {
                offset = offsets[id];
            };
            if (offset) |position| {
                if (instruction.op != .call or !source.arena.?.isAllocation(instruction.operand)) return error.Unavailable;
                try replacement.appendSlice(a, &.{ .{ .op = .drop }, .{ .op = .local_get, .operand = body.provider_parameter }, .{ .op = .i32_const, .operand = position }, .{ .op = .call, .operand = helpers.member_at } });
            } else if (function == owner.function and at == owner.at) {
                var changed = instruction;
                changed.operand = helpers.frame_allocate;
                try replacement.append(a, changed);
            } else if (force != null and instruction.op == .call and instruction.operand == source.arena.?.store_word) {
                var changed = instruction;
                changed.operand = helpers.raw_store;
                try replacement.append(a, changed);
            } else try replacement.append(a, instruction);
        }
        body.instructions.deinit(a);
        body.instructions = replacement;
    }
    const pop = try result.view.own(source.arena.?.root_pop);
    const patched = try runtime.forcePop(a, &result.view.module, helpers);
    pop.locals.deinit(a);
    pop.instructions.deinit(a);
    pop.locals = patched.locals;
    pop.instructions = patched.instructions;
    return result;
}
