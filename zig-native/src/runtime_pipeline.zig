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
        result.roots = module.arena != null and !module.mutable_static;
        for (module.imports.items, 0..) |_, index| if (module.hostCallbackImport(index) == null) {
            result.roots = false;
            break;
        };
        var needs_roots = module.host_references != null or module.public_arena or module.static_fields.items.len != 0;
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
        return self.module.runtimeHelper(id);
    }
    fn borrowedHost(self: *const Session, function: *const ir.Function) bool {
        const references = self.module.host_references orelse return false;
        if (function.entry or function.result_role != .scalar or function.instructions.items.len == 0) return false;
        const marker: ir.Ownership = .{ .kind = .scope, .chunk = 14 };
        if (!std.meta.eql(function.instructions.items[0], ir.Instruction{ .op = .ownership, .operand = @bitCast(marker) })) return false;
        var imports: usize = 0;
        for (function.instructions.items) |inst| switch (inst.op) {
            .ownership => if (inst.operand != @as(u32, @bitCast(marker))) return false,
            .call_import => {
                const callback = self.module.hostCallbackImport(inst.operand) orelse return false;
                if (callback.result.role() != .scalar or function.result != callback.result.machine()) return false;
                if (!std.mem.eql(ir.ValueType, function.parameters, &.{ .i32, callback.parameter.machine(), .i32 })) return false;
                if (function.parameter_roles != ir.packParameterRoles(&.{ .reference, callback.parameter.role(), .reference })) return false;
                imports += 1;
            },
            .global_get => if (inst.operand != references.active) return false,
            .local_get => if (inst.operand >= function.parameters.len) return false,
            .i32_load => if (inst.operand != @import("runtime_layout.zig").offset(@import("runtime_layout.zig").HostClosure, "handle")) return false,
            .host_ref_get, .i32_ne, .if_, .end, .unreachable_ => {},
            else => return false,
        };
        return imports == 1;
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
            if (self.module.host_references) |references| {
                if (id == references.retain or id == references.release) arena_helper = true;
            }
            if (!arena_helper) {
                const entry = source.entry;
                if (try @import("root_lowering.zig").run(self.allocator, self.module, &view, !self.runtimeHelper(source) and !self.borrowedHost(&view), entry, self.module.start != null and id == self.module.start.?)) |replacement| {
                    if (owned) |*body| body.deinit(self.allocator);
                    owned = replacement;
                }
            }
        }
        return owned;
    }
};
