//! One owner for runtime optimization scratch and transformed bodies. A pass
//! consumes a typed IR view; replacement drops the previous body immediately.
//! The retained source/artifact body is immutable and survives every failure.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const lifetimes = @import("wasm_lifetimes.zig");
const A = std.mem.Allocator;

pub const Session = struct {
    allocator: A,
    module: *const wasm.Module,
    summaries: lifetimes.Summaries,
    roots: bool = false,
    tier: @import("compilation_tier.zig").Tier = .optimized,

    pub fn init(a: A, module: *const wasm.Module) A.Error!Session {
        var summaries = try lifetimes.Summaries.init(a, module);
        errdefer summaries.deinit();
        try summaries.prepare();
        var result: Session = .{ .allocator = a, .module = module, .summaries = summaries };
        result.roots = module.arena != null and !module.mutable_static and module.host_references == null and module.imports.items.len == 0;
        var needs_roots = module.public_arena or module.static_fields.items.len != 0;
        if (result.roots) for (module.functions.items) |*function| {
            if (result.runtimeHelper(function)) continue;
            if (function.parameters.len >= 8192 or function.locals.items.len >= 8192 - function.parameters.len or (function.result_role != .scalar and function.result_role != .reference)) {
                result.roots = false;
                break;
            }
            for (function.instructions.items) |inst| {
                if (inst.op == .call) {
                    if (module.arena.?.isAllocation(inst.operand) or inst.operand == module.arena.?.allocate_typed) needs_roots = true;
                    if (module.lists) |lists| inline for (@typeInfo(@TypeOf(lists)).@"struct".field_names) |field| {
                        if (inst.operand == @field(lists, field)) needs_roots = true;
                    };
                }
                if (inst.op == .global_set and module.globals.items[inst.operand].scalar.role() == .reference and module.start == null) result.roots = false;
                if (inst.op != .ownership) continue;
                const scope: ir.Ownership = @bitCast(inst.operand);
                if (scope.kind == .scope and scope.chunk == 15) result.roots = false;
            }
            if (!result.roots) break;
        };
        result.roots = result.roots and needs_roots;
        return result;
    }
    pub fn deinit(self: *Session) void {
        self.summaries.deinit();
    }
    pub fn runtimeHelper(self: *const Session, function: *const ir.Function) bool {
        const id = (@intFromPtr(function) - @intFromPtr(self.module.functions.items.ptr)) / @sizeOf(ir.Function);
        if (self.module.arena) |arena| inline for (wasm.Arena.function_fields) |field| {
            if (id == @field(arena, field)) return true;
        };
        if (self.module.lists) |lists| inline for (@typeInfo(@TypeOf(lists)).@"struct".field_names) |field| {
            if (id == @field(lists, field)) return true;
        };
        return false;
    }
    pub fn optimize(self: *Session, source: *const ir.Function) A.Error!?ir.Body {
        var owned: ?ir.Body = null;
        errdefer if (owned) |*body| body.deinit(self.allocator);
        var view = source.*;
        inline for (.{ "inline", "scalar", "vector", "lifetime", "reduce", "rc" }) |pass| {
            const next: ?ir.Body = if (self.tier == .development and !std.mem.eql(u8, pass, "lifetime") and !std.mem.eql(u8, pass, "rc"))
                null
            else if (comptime std.mem.eql(u8, pass, "inline"))
                try @import("wasm_inline.zig").run(self.allocator, self.module, &view)
            else if (comptime std.mem.eql(u8, pass, "scalar"))
                try @import("wasm_sroa.zig").run(self.allocator, self.module, &view)
            else if (comptime std.mem.eql(u8, pass, "vector"))
                try @import("wasm_vectorize.zig").run(self.allocator, self.module, &view)
            else if (comptime std.mem.eql(u8, pass, "rc"))
                if (self.runtimeHelper(source)) null else try lifetimes.runRc(self.allocator, self.module, &view, &self.summaries)
            else if (comptime std.mem.eql(u8, pass, "reduce"))
                try @import("wasm_row_reduce.zig").run(self.allocator, &view)
            else
                try lifetimes.runWithSummaries(self.allocator, self.module, &view, &self.summaries);
            if (next) |replacement| {
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
            if (!arena_helper) {
                const entry = source.entry;
                if (try @import("root_lowering.zig").run(self.allocator, self.module, &view, !self.runtimeHelper(source), entry, self.module.start != null and id == self.module.start.?)) |replacement| {
                    if (owned) |*body| body.deinit(self.allocator);
                    owned = replacement;
                }
            }
        }
        return owned;
    }
};
