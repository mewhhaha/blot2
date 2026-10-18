//! One owner for runtime optimization scratch and transformed bodies. A pass
//! consumes a typed IR view; replacement drops the previous body immediately.
//! The retained source/artifact body is immutable and survives every failure.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const lifetimes = @import("wasm_lifetimes.zig");
const A = std.mem.Allocator;

// An unobserved generic identity retains its word representation. Returning
// that exact formal cannot acquire or retire an owner, so it needs no result
// journal or scalar/reference guess. Private adapters may permute formals while
// forwarding through the same bounded proof. Any additional action declines.
fn borrowedParameter(module: *const wasm.Module, source: *const ir.Function, depth: usize) ?u32 {
    if (depth >= 32 or source.entry or source.result != .i32 or source.result_role != .value or source.locals.items.len != 0) return null;
    const instructions = source.instructions.items;
    var end = instructions.len;
    if (end != 0 and instructions[end - 1].op == .return_) end -= 1;
    if (end == 0) return null;
    const last = instructions[end - 1];
    var parameter: u32 = undefined;
    switch (last.op) {
        .local_get => {
            if (end != 1) return null;
            parameter = last.operand;
        },
        .call => {
            if (last.operand >= module.functions.items.len) return null;
            const callee = &module.functions.items[last.operand];
            if (end - 1 != callee.parameters.len) return null;
            for (instructions[0 .. end - 1], callee.parameters) |argument, machine| {
                if (argument.op != .local_get or argument.operand >= source.parameters.len) return null;
                if (source.parameters[argument.operand] != machine) return null;
            }
            const returned = borrowedParameter(module, callee, depth + 1) orelse return null;
            parameter = instructions[returned].operand;
        },
        else => return null,
    }
    if (parameter >= source.parameters.len or source.parameters[parameter] != .i32 or source.parameterRole(parameter) != .value) return null;
    return parameter;
}

pub const Session = struct {
    allocator: A,
    module: *const wasm.Module,
    summaries: lifetimes.Summaries,
    inline_facts: @import("wasm_inline.zig").Facts = .{},
    providers: @import("provider_modes.zig").Catalog = .{},
    roots: bool = false,
    needs_roots: bool = false,
    tier: @import("../compilation_tier.zig").Tier = .optimized,

    pub fn init(a: A, module: *const wasm.Module) A.Error!Session {
        var summaries = try lifetimes.Summaries.init(a, module);
        errdefer summaries.deinit();
        var inline_facts = try @import("wasm_inline.zig").Facts.init(a, module);
        errdefer inline_facts.deinit(a);
        var result: Session = .{ .allocator = a, .module = module, .summaries = summaries, .inline_facts = inline_facts };
        result.roots = module.arena != null and !module.mutable_static;
        for (module.imports.items, 0..) |_, index| if (module.hostCallbackImport(index) == null and !module.ownedCleanupBindImport(index) and !module.resourceImport(index) and !module.taskImport(index)) {
            result.roots = false;
            break;
        };
        // Raw helper exports can acquire leases outside a journal. They belong
        // to the explicit partial fixture contract, never complete admission.
        for (module.exports.items) |item| if (!item.global and !item.task_runtime and module.runtimeHelper(item.index)) {
            result.roots = false;
            break;
        };
        var needs_roots = module.host_references != null or module.public_arena or module.static_fields.items.len != 0 or module.start != null;
        if (result.roots) for (module.functions.items) |*function| {
            if (result.runtimeHelper(function)) continue;
            if (function.parameters.len >= 8192 or function.locals.items.len >= 8192 - function.parameters.len or (function.result_role != .scalar and function.result_role != .reference and borrowedParameter(module, function, 0) == null)) {
                result.roots = false;
                break;
            }
            for (function.instructions.items) |inst| {
                if (inst.op == .call) {
                    if (module.arena.?.isAllocation(inst.operand) or inst.operand == module.arena.?.allocate_typed or inst.operand == module.arena.?.allocate_shaped or (module.regions != null and inst.operand == module.regions.?.runtime.frame_allocate)) needs_roots = true;
                    if (module.lists) |lists| inline for (@typeInfo(@TypeOf(lists)).@"struct".field_names) |field| {
                        if (lists.functionId(field)) |function_id| if (inst.operand == function_id) {
                            needs_roots = true;
                        };
                    };
                }
                if (inst.op == .global_set and module.globals.items[inst.operand].scalar.role() == .reference and module.start == null) result.roots = false;
                if (inst.op != .ownership) continue;
                const scope: ir.Ownership = @bitCast(inst.operand);
                if (scope.kind == .scope and scope.chunk == 15) result.roots = false;
            }
            if (!result.roots) break;
        };
        if (module.regions) |regions| if (!regions.valid(module)) {
            result.roots = false;
        };
        result.needs_roots = needs_roots;
        if (result.roots) result.providers = try .init(a, module);
        errdefer result.providers.deinit(a);
        result.summaries.providers = result.providers.entries.items;
        try result.summaries.prepare();
        return result;
    }
    pub fn deinit(self: *Session) void {
        self.inline_facts.deinit(self.allocator);
        self.providers.deinit(self.allocator);
        self.summaries.deinit();
    }
    pub fn runtimeHelper(self: *const Session, function: *const ir.Function) bool {
        const id = (@intFromPtr(function) - @intFromPtr(self.module.functions.items.ptr)) / @sizeOf(ir.Function);
        return self.module.runtimeHelper(id);
    }
    fn borrowedHost(self: *const Session, function: *const ir.Function) bool {
        return function.result_role == .scalar and @import("host_entry.zig").hostStub(self.module, function);
    }
    // Source callees retire their private owners. Only a reference result or an
    // allocating helper can acquire a caller slot; scalar calls cannot do so.
    // Indirect calls need their checked result fact, not their machine type.
    fn borrowsOnly(self: *const Session, function: *const ir.Function) bool {
        if (borrowedParameter(self.module, function, 0) != null) return true;
        if (function.result_role != .scalar) return false;
        for (function.instructions.items, 0..) |inst, at| switch (inst.op) {
            .ownership => {
                const annotation: ir.Ownership = @bitCast(inst.operand);
                if (annotation.kind == .scope) switch (annotation.chunk) {
                    0, 1, 14 => {},
                    else => return false,
                };
            },
            .call => {
                if (self.module.runtimeHelper(inst.operand)) return false;
                if (self.module.functions.items[inst.operand].result_role != .scalar) return false;
            },
            .call_indirect => if (ir.indirectResult(function.instructions.items, at) != .scalar) return false,
            .call_import => return false,
            .global_set => if (self.module.globals.items[inst.operand].scalar.role() == .reference) return false,
            else => {},
        };
        return true;
    }
    pub fn optimize(self: *Session, source: *const ir.Function) A.Error!?ir.Body {
        var owned: ?ir.Body = null;
        errdefer if (owned) |*body| body.deinit(self.allocator);
        var view = source.*;
        var provider_borrow = false;
        if (self.roots) if (try @import("provider_modes.zig").specialize(self.allocator, &self.providers, source)) |replacement| {
            owned = replacement;
            view.locals = replacement.locals;
            view.instructions = replacement.instructions;
            provider_borrow = true;
        };
        // The lifetime and rc passes share one scan while the body between
        // them stays the same.
        var scan: lifetimes.SharedScan = .{};
        defer scan.deinit();
        inline for (.{ "inline", "scalar", "vector", "row_products", "lifetime", "reduce", "rc" }) |pass| {
            const next: ?ir.Body = if (self.tier == .development and !std.mem.eql(u8, pass, "lifetime") and !std.mem.eql(u8, pass, "rc"))
                null
            else if (comptime std.mem.eql(u8, pass, "inline"))
                try @import("wasm_inline.zig").runWithFacts(self.allocator, self.module, &view, &self.inline_facts)
            else if (comptime std.mem.eql(u8, pass, "scalar"))
                try @import("wasm_sroa.zig").runWithRoots(self.allocator, self.module, &view, self.roots)
            else if (comptime std.mem.eql(u8, pass, "vector"))
                try @import("wasm_vectorize.zig").run(self.allocator, self.module, &view)
            else if (comptime std.mem.eql(u8, pass, "row_products"))
                try @import("wasm_row_products.zig").run(self.allocator, &view)
            else if (comptime std.mem.eql(u8, pass, "rc"))
                if (self.runtimeHelper(source)) null else try lifetimes.runRc(self.allocator, self.module, &view, &self.summaries, &scan)
            else if (comptime std.mem.eql(u8, pass, "reduce"))
                try @import("wasm_row_reduce.zig").run(self.allocator, &view)
            else
                try lifetimes.runWithSummaries(self.allocator, self.module, &view, &self.summaries, &scan);
            if (next) |replacement| {
                scan.invalidate();
                if (owned) |*body| body.deinit(self.allocator);
                owned = replacement;
                view.locals = replacement.locals;
                view.instructions = replacement.instructions;
            }
        }
        if (self.roots and !self.runtimeHelper(source)) {
            if (try @import("root_borrows.zig").run(self.allocator, self.module, &view)) |replacement| {
                if (owned) |*body| body.deinit(self.allocator);
                owned = replacement;
                view.locals = replacement.locals;
                view.instructions = replacement.instructions;
            }
        }
        if (self.roots) {
            const id: u32 = @intCast((@intFromPtr(source) - @intFromPtr(self.module.functions.items.ptr)) / @sizeOf(ir.Function));
            var arena_helper = false;
            inline for (wasm.Arena.function_fields) |field| {
                if (id == @field(self.module.arena.?, field)) arena_helper = true;
            }
            if (self.module.host_references) |references| {
                if (id == references.retain or id == references.release) arena_helper = true;
            }
            // Late cohort helpers own the explicit transfer from a fresh
            // allocation lease to the enclosing rooted owner. Journaling their
            // allocator again would give two owners the same strong count.
            if (self.module.cohorts) |cohorts| {
                if (id == cohorts.allocate) arena_helper = true;
            }
            if (self.module.regions) |regions| if (regions.runtime.contains(id)) {
                arena_helper = true;
            };
            if (!arena_helper) {
                const entry = source.entry;
                const start = self.module.start != null and id == self.module.start.?;
                var borrows = self.borrowedHost(&view) or self.borrowsOnly(&view);
                if (provider_borrow) borrows = self.borrowedHost(source) or self.borrowsOnly(source);
                const framed = self.needs_roots and !self.runtimeHelper(source) and (entry or start or !borrows);
                var owner: ?u32 = null;
                if (@import("../runtime/region_runtime.zig").scope(self.module, id)) |scope| owner = scope.parameter;
                if (try @import("root_lowering.zig").runScoped(self.allocator, self.module, &view, framed, entry, start, provider_borrow, owner)) |replacement| {
                    if (owned) |*body| body.deinit(self.allocator);
                    owned = replacement;
                    view.locals = replacement.locals;
                    view.instructions = replacement.instructions;
                }
            }
        }
        const id = (@intFromPtr(source) - @intFromPtr(self.module.functions.items.ptr)) / @sizeOf(ir.Function);
        if (!self.runtimeHelper(source) and !self.module.resourceAdapterFunction(id)) if (try @import("../runtime/resource_safepoints.zig").run(self.allocator, self.module, &view)) |replacement| {
            if (owned) |*body| body.deinit(self.allocator);
            owned = replacement;
        };
        if (!self.runtimeHelper(source) and !self.module.resourceAdapterFunction(id) and !self.module.taskAdapterFunction(id)) {
            if (owned) |body| {
                view.locals = body.locals;
                view.instructions = body.instructions;
            }
            if (try @import("../runtime/task_safepoints.zig").run(self.allocator, self.module, &view)) |replacement| {
                if (owned) |*body| body.deinit(self.allocator);
                owned = replacement;
            }
        }
        return owned;
    }
};
