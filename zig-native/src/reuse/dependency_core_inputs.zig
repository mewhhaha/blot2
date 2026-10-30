//! Exact immutable module owners read by dependency Core validation. This is
//! private snapshot authority; ordinary ContextImage admission is unchanged.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const retained = @import("retained_dependency.zig");
const A = std.mem.Allocator;
fn invocationActive(value: *const @import("frozen_dependency.zig").FrozenDependency) bool {
    for (value.modules) |module| for (module.core.bindings) |binding| if (binding.capability_parameters.inputInvokes()) return true;
    return false;
}
comptime {
    for (std.meta.tags(core.Tag)) |tag| switch (tag) {
        .invalid, .constant, .reference, .scalar, .logical, .call, .if_value, .block, .suite, .bind, .return_, .if_stmt, .product, .record, .construct, .project, .match, .pattern_bind, .update, .array, .array_op, .closure, .apply, .constructor_function, .associated, .primitive_function, .panic, .loop, .break_, .type_same, .result_associated, .suspend_, .force, .type_constructor, .resolver_op, .operation_value, .effect_provider, .state_provider, .handle, .effect_reflection, .computation, .request_loop, .request_decision, .record_merge, .contract_method, .effect_scope, .proof_guard, .package_pack, .package_unpack, .staging, .usage_borrow, .usage_read, .resource_scope, .usage_share, .resource_acquire, .resource_release, .task, .storage => {},
    };
}
fn unitField(comptime Record: type, comptime name: []const u8) bool {
    return std.mem.eql(u8, name, "unit") or std.mem.eql(u8, name, "qualification_unit") or (Record == core.SelectedProof and std.mem.eql(u8, name, "context"));
}
fn hasUnits(comptime Record: type) bool {
    @setEvalBranchQuota(50_000);
    if (Record == T.Node) return true;
    return switch (@typeInfo(Record)) {
        .@"struct" => |record| blk: {
            inline for (record.field_names) |name| {
                if (unitField(Record, name) or hasUnits(@FieldType(Record, name))) break :blk true;
            }
            break :blk false;
        },
        .pointer => |pointer| if (pointer.size == .slice) hasUnits(pointer.child) else @compileError("Core owner inputs require owned slices"),
        .optional => |optional| hasUnits(optional.child),
        .array => |array| hasUnits(array.child),
        .@"union" => |record| blk: {
            inline for (record.field_names) |name| if (hasUnits(@FieldType(Record, name))) break :blk true;
            break :blk false;
        },
        .int, .float, .bool, .@"enum", .void => false,
        else => @compileError("Unregistered Core owner input type " ++ @typeName(Record)),
    };
}
const Inputs = struct {
    bits: []u64,
    count: usize,
    remaining: *usize,
    complete: bool = true,
    fn add(self: *Inputs, unit: u32) void {
        if (unit == 0 or unit == std.math.maxInt(u32)) return;
        if (unit > self.count) {
            self.complete = false;
            return;
        }
        const index = unit - 1;
        self.bits[index / 64] |= @as(u64, 1) << @intCast(index % 64);
    }
    fn visit(self: *Inputs, value: anytype) void {
        const Record = @TypeOf(value);
        if (comptime !hasUnits(Record)) return;
        if (self.remaining.* == 0) {
            self.complete = false;
            return;
        }
        self.remaining.* -= 1;
        if (Record == T.Node) {
            switch (value.tag) {
                .nominal, .projection, .type_constructor, .instance_selection, .instance_version => self.add(value.a),
                .scoped => self.add(value.b),
                .absent, .unit, .boolean, .u32, .f32, .never, .variable, .function, .product, .record, .array, .list, .cursor, .demand, .resolver, .provider, .state_provider, .erased_proof, .forall, .existential, .bound, .rigid, .usage => {},
            }
            return;
        }
        switch (@typeInfo(Record)) {
            .@"struct" => |record| inline for (record.field_names) |name| {
                if (comptime unitField(Record, name)) self.add(@field(value, name)) else self.visit(@field(value, name));
            },
            .pointer, .array => for (value) |item| {
                if (self.remaining.* == 0) {
                    self.complete = false;
                    break;
                }
                self.visit(item);
            },
            .optional => if (value) |item| self.visit(item),
            .@"union" => |record| inline for (record.field_names) |name| {
                if (std.meta.activeTag(value) == @field(std.meta.Tag(Record), name)) self.visit(@field(value, name));
            },
            else => unreachable,
        }
    }
    fn module(self: *Inputs, owner: *const core.Module) void {
        // Every Module field is classified; new metadata requires review.
        inline for (@typeInfo(core.Module).@"struct".field_names) |name| switch (@field(std.meta.FieldEnum(core.Module), name)) {
            .unit => self.add(owner.unit),
            .types, .bindings, .references, .calls, .obligations, .nominals, .operation_names, .constructors, .projections, .associated, .contracts, .contract_members, .implementations, .implementation_members, .member_templates, .selected_proofs, .selected_members, .resolver_ops, .operation_values, .dependency_references, .erased_declaration_references => self.visit(@field(owner, name)),
            .has_rank_contracts, .has_usage_contracts, .has_numeric_proofs, .proof_contracts, .capability_contracts, .field_names, .runtime_names, .source_names, .declaration_dependencies, .dependency_members, .request_loops, .request_arms, .tag_calls, .nodes, .spans, .extra, .bodies, .parameters, .merges, .merge_ranges, .names, .projection_variants, .patterns, .pattern_rows, .match_arms, .matches, .updates, .update_steps, .closures, .selected_edges, .selected_uses, .dictionary_selections, .dictionary_uses, .primitives, .loops, .loop_carries, .handle_effects, .dispatch_signatures, .diagnostics, .body_lowerings => {
                if (comptime hasUnits(@FieldType(core.Module, name))) @compileError("Unregistered Core module owner field " ++ name);
            },
        };
    }
};
pub const Owners = struct {
    stable: []bool,
    pub fn deinit(self: *Owners, a: A) void {
        a.free(self.stable);
    }
    pub fn init(a: A, current: *const retained.Snapshot, previous: *const retained.Snapshot) A.Error!?Owners {
        const count = current.initialized;
        if (!previous.validated or count != previous.initialized or count == 0 or count > 1024) return null;
        // capability_invocations.active observes this global predicate only
        // for scoped modules. Propagate its change through actual owner edges.
        const activation_changed = invocationActive(&current.value) != invocationActive(&previous.value);
        const width = (count + 63) / 64;
        const edge_words = std.math.mul(usize, count, width) catch return null;
        const words = std.math.add(usize, edge_words, count) catch return null;
        const stable = try a.alloc(bool, count);
        errdefer a.free(stable);
        const storage = try a.alloc(u64, words);
        defer a.free(storage);
        const edges = storage[0..edge_words];
        const queue = storage[edge_words..];
        @memset(edges, 0);
        var remaining: usize = 1_000_000;
        for (stable, 0..) |*same, id| {
            same.* = current.shares(previous, id);
            if (same.* and activation_changed) for (current.value.modules[id].core.types.nodes) |node| {
                if (node.tag == .scoped) {
                    same.* = false;
                    break;
                }
            };
            if (!same.*) continue;
            var inputs: Inputs = .{ .bits = edges[id * width ..][0..width], .count = count, .remaining = &remaining };
            inputs.module(&current.value.modules[id].core);
            same.* = inputs.complete;
        }
        var queued: usize = 0;
        for (stable, 0..) |same, id| if (!same) {
            queue[queued] = id;
            queued += 1;
        };
        var next: usize = 0;
        while (next < queued) : (next += 1) {
            const target = queue[next];
            for (stable, 0..) |*same, id| {
                if (!same.* or edges[id * width + target / 64] & (@as(u64, 1) << @intCast(target % 64)) == 0) continue;
                same.* = false;
                queue[queued] = id;
                queued += 1;
            }
        }
        return .{ .stable = stable };
    }
};
