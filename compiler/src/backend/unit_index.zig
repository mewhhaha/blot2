//! Per-unit indexes the backend builds once per compile attempt, on first
//! use, from a unit's immutable Core tables.
const std = @import("std");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const Allocator = std.mem.Allocator;

/// The type variables and row variables some scheme, type declaration,
/// operation, closure, contract or implementation of one unit quantifies or
/// closes. A variable outside both sets is ambiguous: checking left it
/// unconstrained.
pub const Quantified = struct {
    types: std.AutoHashMapUnmanaged(types.Id, void) = .empty,
    rows: std.AutoHashMapUnmanaged(u32, void) = .empty,

    pub fn init(allocator: Allocator, source: *const core.Module) Allocator.Error!Quantified {
        var result: Quantified = .{};
        errdefer result.deinit(allocator);
        const t = &source.types;
        for (source.bindings) |binding| {
            try result.add(allocator, false, t, &.{ binding.scheme.variables, binding.scheme.generative, binding.public_variables });
            try result.add(allocator, true, t, &.{ binding.scheme.row_variables, binding.scheme.closed_rows, binding.public_rows });
        }
        for (source.bodies) |body| {
            try result.add(allocator, false, t, &.{ body.scheme.variables, body.scheme.generative });
            try result.add(allocator, true, t, &.{ body.scheme.row_variables, body.scheme.closed_rows, body.closed_rows });
        }
        for (source.constructors) |constructor| {
            try result.add(allocator, false, t, &.{ constructor.scheme.variables, constructor.scheme.generative });
            try result.add(allocator, true, t, &.{constructor.scheme.row_variables});
        }
        for (source.nominals) |nominal| try result.add(allocator, false, t, &.{ nominal.parameters, nominal.variables });
        for (source.operation_names) |operation| try result.add(allocator, false, t, &.{ operation.variables, operation.parameters });
        for (source.closures) |metadata| try result.add(allocator, true, t, &.{metadata.closed_rows});
        for (source.contracts) |contract| {
            try result.add(allocator, false, t, &.{ contract.parameters, contract.variables });
            try result.add(allocator, true, t, &.{ contract.row_variables, contract.row_parameters });
        }
        for (source.implementations) |implementation| {
            try result.add(allocator, false, t, &.{ implementation.variables, implementation.head });
            try result.add(allocator, true, t, &.{ implementation.row_variables, implementation.row_parameters });
        }
        return result;
    }
    pub fn deinit(self: *Quantified, allocator: Allocator) void {
        self.types.deinit(allocator);
        self.rows.deinit(allocator);
    }
    /// Whether type variable or, for `row`, row variable `variable` is
    /// quantified or closed by some declaration of the unit.
    pub fn has(self: *const Quantified, variable: u32, row: bool) bool {
        return if (row) self.rows.contains(variable) else self.types.contains(variable);
    }
    fn add(self: *Quantified, allocator: Allocator, row: bool, t: *const core.Types, lists: []const types.List) Allocator.Error!void {
        for (lists) |list| for (t.list(list)) |variable| {
            if (row) try self.rows.put(allocator, variable, {}) else try self.types.put(allocator, variable, {});
        };
    }
};

/// Values grouped by a dense key, each group in the order a visitor emits
/// them. The visitor runs twice, once to count each group and once to fill
/// it, so no intermediate list is built.
pub fn Table(comptime T: type) type {
    return struct {
        const Self = @This();
        offsets: []u32 = &.{},
        items: []T = &.{},

        pub const Builder = struct {
            offsets: []u32,
            items: []T = &.{},
            filling: bool = false,
            pub fn add(self: *Builder, key: u32, value: T) void {
                if (!self.filling) {
                    self.offsets[key + 1] += 1;
                    return;
                }
                self.items[self.offsets[key]] = value;
                self.offsets[key] += 1;
            }
        };

        /// Every key `visit` passes to `Builder.add` is below `keys`, and
        /// both passes emit the same pairs in the same order.
        pub fn build(allocator: Allocator, keys: usize, context: anytype, comptime visit: fn (@TypeOf(context), *Builder) void) Allocator.Error!Self {
            const offsets = try allocator.alloc(u32, keys + 1);
            errdefer allocator.free(offsets);
            @memset(offsets, 0);
            var builder: Builder = .{ .offsets = offsets };
            visit(context, &builder);
            for (1..offsets.len) |index| offsets[index] += offsets[index - 1];
            const items = try allocator.alloc(T, offsets[keys]);
            builder.items = items;
            builder.filling = true;
            visit(context, &builder);
            // Each offset now ends its group; shift them back to starts.
            var index = keys;
            while (index > 0) : (index -= 1) offsets[index] = offsets[index - 1];
            offsets[0] = 0;
            return .{ .offsets = offsets, .items = items };
        }
        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.offsets);
            allocator.free(self.items);
            self.* = .{};
        }
        pub fn get(self: *const Self, key: u32) []const T {
            if (key + 1 >= self.offsets.len) return &.{};
            return self.items[self.offsets[key]..self.offsets[key + 1]];
        }
    };
}

/// The binding reference `id` of `source` names when it is one of the unit
/// itself, numbered as `unit` or as the module numbers itself.
fn ownReference(source: *const core.Module, unit: u32, id: core.Id) ?core.BindingId {
    const reference = source.reference(id);
    if (reference.unit != 0 and reference.unit != unit and reference.unit != source.unit) return null;
    if (reference.binding >= source.bindings.len) return null;
    return reference.binding;
}

const Scope = struct { source: *const core.Module, unit: u32 };

fn visitReferences(scope: Scope, builder: *Table(core.Id).Builder) void {
    for (scope.source.nodes, 0..) |node, index| {
        if (node.tag != .reference) continue;
        const binding = ownReference(scope.source, scope.unit, @intCast(index)) orelse continue;
        builder.add(binding, @intCast(index));
    }
}

/// Reference nodes naming each binding of the unit, in node order. Both
/// spellings of the unit's own references are included, so a caller that
/// accepts only one rechecks it.
pub fn references(allocator: Allocator, source: *const core.Module, unit: u32) Allocator.Error!Table(core.Id) {
    return Table(core.Id).build(allocator, source.bindings.len, Scope{ .source = source, .unit = unit }, visitReferences);
}

fn visitDefinitions(scope: Scope, builder: *Table(core.Id).Builder) void {
    for (scope.source.nodes, 0..) |node, index| {
        if (node.tag == .bind and node.a < scope.source.bindings.len) builder.add(node.a, @intCast(index));
    }
}
fn visitInputs(scope: Scope, builder: *Table(core.Id).Builder) void {
    const source = scope.source;
    for (source.nodes, 0..) |node, index| {
        if (node.tag != .bind) continue;
        var input = node.b;
        if (input != 0 and source.node(input).tag == .array_op and source.arrayOperation(input) == .cursor_advance) input = source.children(input)[0];
        if (input == 0 or source.node(input).tag != .reference) continue;
        if (ownReference(source, scope.unit, input)) |binding| builder.add(binding, @intCast(index));
    }
}
fn visitExits(scope: Scope, builder: *Table(core.Id).Builder) void {
    for (scope.source.nodes, 0..) |node, index| {
        if (node.tag == .break_ and node.a < scope.source.nodes.len) builder.add(node.a, @intCast(index));
    }
}
fn visitValues(scope: Scope, builder: *Table(Uses.Exit).Builder) void {
    const source = scope.source;
    for (source.nodes, 0..) |node, index| {
        if (node.tag != .break_) continue;
        for (source.breakValues(@intCast(index)), 0..) |value, position| builder.add(value, .{ .exit = @intCast(index), .position = @intCast(position) });
    }
}
fn visitCarries(scope: Scope, builder: *Table(u32).Builder) void {
    const bindings = scope.source.bindings.len;
    for (scope.source.loop_carries, 0..) |carry, index| {
        const named = [_]core.BindingId{ carry.incoming, carry.iteration, carry.backedge, carry.outgoing };
        for (named, 0..) |held, position| {
            if (held >= bindings) continue;
            // One entry per carry, even when it names a binding twice.
            if (std.mem.findScalar(core.BindingId, named[0..position], held) != null) continue;
            builder.add(held, @intCast(index));
        }
    }
}

/// Def-use facts of one unit's Core graph: references by binding with
/// capture, merge and carry flags; on request, the block or suite listing
/// each statement; and on request, the flow facts the cursor proofs read
/// (definitions and cursor inputs by binding, carries by binding, loop exits
/// and break values). Each answer equals the whole-unit scan it replaces, in
/// the same node order.
pub const Uses = struct {
    pub const Flags = packed struct(u8) {
        /// Some closure or suspension captures the binding.
        captured: bool = false,
        /// A merge takes the binding from one of its branches.
        merge_branch: bool = false,
        /// A merge produces the binding.
        merge_result: bool = false,
        /// A loop carry names the binding.
        carried: bool = false,
        _: u4 = 0,
    };
    pub const Parent = struct {
        /// The first block or suite listing the node, or 0.
        node: core.Id = 0,
        position: u32 = 0,
        /// How many times block and suite children list the node, saturated.
        count: u2 = 0,
    };
    const PackedParent = packed struct(u64) { node: u32 = 0, position: u30 = 0, count: u2 = 0 };
    /// A break listing a value at one position.
    pub const Exit = struct { exit: core.Id, position: u32 };
    /// The loop owning a carry and the carry's position there.
    pub const Carry = struct { loop: core.Id = 0, position: u32 = 0 };
    /// The optional groups a caller reads.
    pub const Need = struct { parents: bool = false, flow: bool = false };

    references: Table(core.Id) = .{},
    flags: []Flags = &.{},
    parents: []PackedParent = &.{},
    has_parents: bool = false,
    /// Bind nodes defining each binding.
    definitions: Table(core.Id) = .{},
    /// Bind nodes whose input, through one cursor advance, is a reference to
    /// each binding.
    inputs: Table(core.Id) = .{},
    /// Loop carries naming each binding, by index into `loop_carries`.
    carries: Table(u32) = .{},
    /// Breaks targeting each node.
    exits: Table(core.Id) = .{},
    /// Breaks listing each node as a value.
    values: Table(Exit) = .{},
    carry_loops: []Carry = &.{},
    has_flow: bool = false,

    /// Every group.
    pub fn init(allocator: Allocator, source: *const core.Module, unit: u32) Allocator.Error!Uses {
        var result = try initBase(allocator, source, unit);
        errdefer result.deinit(allocator);
        try result.ensure(allocator, source, unit, .{ .parents = true, .flow = true });
        return result;
    }
    /// References and flags only.
    pub fn initBase(allocator: Allocator, source: *const core.Module, unit: u32) Allocator.Error!Uses {
        var result: Uses = .{};
        errdefer result.deinit(allocator);
        result.references = try references(allocator, source, unit);
        result.flags = try allocator.alloc(Flags, source.bindings.len);
        @memset(result.flags, .{});
        for (source.closures) |metadata| for (source.extra[metadata.captures.start..][0..metadata.captures.len]) |held| {
            if (held < result.flags.len) result.flags[held].captured = true;
        };
        for (source.merges) |merge| {
            for ([_]core.BindingId{ merge.then_binding, merge.else_binding }) |held| {
                if (held < result.flags.len) result.flags[held].merge_branch = true;
            }
            if (merge.result < result.flags.len) result.flags[merge.result].merge_result = true;
        }
        for (source.loop_carries) |carry| for ([_]core.BindingId{ carry.incoming, carry.iteration, carry.backedge, carry.outgoing }) |held| {
            if (held < result.flags.len) result.flags[held].carried = true;
        };
        return result;
    }
    /// Builds the groups `need` asks for that are still missing. A group is
    /// added only once it is complete.
    pub fn ensure(self: *Uses, allocator: Allocator, source: *const core.Module, unit: u32, need: Need) Allocator.Error!void {
        const scope: Scope = .{ .source = source, .unit = unit };
        if (need.parents and !self.has_parents) {
            const parents = try allocator.alloc(PackedParent, source.nodes.len);
            @memset(parents, .{});
            for (source.nodes, 0..) |node, index| {
                if (node.tag != .block and node.tag != .suite) continue;
                for (source.children(@intCast(index)), 0..) |child, position| {
                    const parent = &parents[child];
                    if (parent.count == 0) parent.* = .{ .node = @intCast(index), .position = @intCast(position) };
                    parent.count +|= 1;
                }
            }
            allocator.free(self.parents);
            self.parents = parents;
            self.has_parents = true;
        }
        if (need.flow and !self.has_flow) {
            var definitions = try Table(core.Id).build(allocator, source.bindings.len, scope, visitDefinitions);
            errdefer definitions.deinit(allocator);
            var inputs = try Table(core.Id).build(allocator, source.bindings.len, scope, visitInputs);
            errdefer inputs.deinit(allocator);
            var carries = try Table(u32).build(allocator, source.bindings.len, scope, visitCarries);
            errdefer carries.deinit(allocator);
            var exits = try Table(core.Id).build(allocator, source.nodes.len, scope, visitExits);
            errdefer exits.deinit(allocator);
            var values = try Table(Exit).build(allocator, source.nodes.len, scope, visitValues);
            errdefer values.deinit(allocator);
            const carry_loops = try allocator.alloc(Carry, source.loop_carries.len);
            @memset(carry_loops, .{});
            for (source.nodes, 0..) |node, index| {
                if (node.tag != .loop) continue;
                const range = source.loopInfo(@intCast(index)).carries;
                for (0..range.len) |position| carry_loops[range.start + position] = .{ .loop = @intCast(index), .position = @intCast(position) };
            }
            // The groups were empty; release them before taking the new ones.
            self.definitions.deinit(allocator);
            self.inputs.deinit(allocator);
            self.carries.deinit(allocator);
            self.exits.deinit(allocator);
            self.values.deinit(allocator);
            allocator.free(self.carry_loops);
            self.definitions = definitions;
            self.inputs = inputs;
            self.carries = carries;
            self.exits = exits;
            self.values = values;
            self.carry_loops = carry_loops;
            self.has_flow = true;
        }
    }
    pub fn deinit(self: *Uses, allocator: Allocator) void {
        self.references.deinit(allocator);
        allocator.free(self.flags);
        allocator.free(self.parents);
        self.definitions.deinit(allocator);
        self.inputs.deinit(allocator);
        self.carries.deinit(allocator);
        self.exits.deinit(allocator);
        self.values.deinit(allocator);
        allocator.free(self.carry_loops);
        self.* = .{};
    }
    pub fn flagsOf(self: *const Uses, binding: core.BindingId) Flags {
        return if (binding < self.flags.len) self.flags[binding] else .{};
    }
    pub fn parentOf(self: *const Uses, id: core.Id) Parent {
        std.debug.assert(self.has_parents);
        if (id >= self.parents.len) return .{};
        const parent = self.parents[id];
        return .{ .node = parent.node, .position = parent.position, .count = parent.count };
    }
};
