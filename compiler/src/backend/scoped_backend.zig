//! Source storage admission and data-stack emission. Owner identities survive
//! aliases and control-flow joins; borrowed values never own or retain storage.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const types = @import("../check/storage_types.zig");
const ops = @import("../check/storage_ops.zig");
const wasm = @import("wasm.zig");
const storage = @import("../runtime/data_stacks.zig");
const packets = @import("../runtime/storage_packets.zig");
const Code = @import("runtime_code.zig").Code;
const Local = @import("runtime_code.zig").Local;
const backend = @import("core_backend.zig");
const call_plan = @import("storage_calls.zig");
const field_plan = @import("storage_field_plan.zig");
const scope_outline = @import("wasm_scope_outline.zig");
const deferred_join = @import("storage_deferred_join.zig");
const type_arguments_index = @import("storage_type_arguments.zig");
const selected_types = @import("storage_type_key.zig");
const private_append = @import("private_append_region.zig");
const storage_plan = @import("storage_plan.zig");
const transport_plan = @import("storage_transport.zig");
const type_evidence = @import("../eval/type_evidence.zig");
const scalar_ops = @import("scalar_ops.zig");
const source_proof = @import("../check/package_core.zig");
const global_footprint = @import("storage_global_footprint.zig");
const addressed_input = @import("addressed_input_demand.zig");
const recursive_admission = @import("storage_recursive_admission.zig");
const evaluation = @import("../eval/core_eval.zig");
const Error = std.mem.Allocator.Error || error{Declined};
/// Compiler work policy, independent of guest storage capacities and proofs.
/// Each export and reusable child retains its own finite expansion allowance.
pub const WorkLimits = struct { expressions: u32 = 500_000 };

/// Transitional selection follows reached expressions, not imported type tables.
/// It grants no admission authority; the selected backend still validates Core.
pub fn required(allocator: std.mem.Allocator, units: []const core.Module, entry: u32) std.mem.Allocator.Error!bool {
    const Node = struct { unit: u32, id: core.Id };
    var pending: std.ArrayList(Node) = .empty;
    defer pending.deinit(allocator);
    var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer seen.deinit(allocator);
    if (entry == 0 or entry > units.len) return true;
    for (units[entry - 1].bodies) |body| if (body.exported) {
        try pending.append(allocator, .{ .unit = entry, .id = body.root });
    };
    while (pending.pop()) |current| {
        if (current.id == 0) continue;
        if (current.unit == 0 or current.unit > units.len or seen.count() >= 100_000) return true;
        const m = &units[current.unit - 1];
        if (current.id >= m.nodes.len) return true;
        if ((try seen.getOrPut(allocator, (@as(u64, current.unit) << 32) | current.id)).found_existing) continue;
        const n = m.node(current.id);
        if (n.tag == .storage) return true;
        if (n.tag == .update) for (m.updateSelectors(current.id)) |selector| {
            if (selector.kind == .index) return true;
        };
        const ty = m.types.node(n.ty);
        if (ty.tag == .nominal and types.identity(ty.a, ty.b) != null) return true;
        if (n.tag == .reference or n.tag == .call) {
            var target = if (n.tag == .call) m.call(current.id).target else m.reference(current.id);
            if (target.unit == 0) target.unit = m.unit;
            if (target.unit == 0 or target.unit > units.len) return true;
            const producer = &units[target.unit - 1];
            if (target.binding >= producer.bindings.len) return true;
            if (producer.body(target.binding)) |body| try pending.append(allocator, .{ .unit = target.unit, .id = body.root });
        }
        if (n.tag == .closure) {
            try pending.append(allocator, .{ .unit = m.unit, .id = m.closures[n.a].body });
        }
        const Visitor = struct {
            pending: *std.ArrayList(Node),
            unit: u32,
            pub fn append(self: *@This(), a: std.mem.Allocator, id: core.Id) error{ OutOfMemory, PlanLimit }!void {
                if (self.pending.items.len >= 100_000) return error.PlanLimit;
                if (id != 0) try self.pending.append(a, .{ .unit = self.unit, .id = id });
            }
            pub fn appendSlice(self: *@This(), a: std.mem.Allocator, ids: []const core.Id) error{ OutOfMemory, PlanLimit }!void {
                for (ids) |id| try self.append(a, id);
            }
        };
        var visitor: Visitor = .{ .pending = &pending, .unit = m.unit };
        @import("../eval/body_recipe.zig").appendChildren(&visitor, allocator, m, current.id, false) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.PlanLimit => return true,
        };
    }
    return false;
}
// This proof only removes an unused scalar payload load. It establishes no
// owner/read authority, and unsupported RHS forms retain their ordinary load.
fn independentScalarReplacement(m: *const core.Module, id: core.Id, self_binding: core.BindingId, depth: usize, remaining: *usize) bool {
    if (id == 0) return true;
    if (depth > 32 or remaining.* == 0 or id >= m.nodes.len) return false;
    remaining.* -= 1;
    const node = m.node(id);
    switch (node.tag) {
        .constant => return true,
        .reference => {
            const reference = m.reference(id);
            if (reference.unit != 0 and reference.unit != m.unit) return false;
            if (reference.binding == self_binding or reference.binding == 0 or reference.binding >= m.bindings.len) return false;
            const kind = m.binding(reference.binding).kind;
            return kind == .local or kind == .parameter;
        },
        .scalar, .logical => {
            if (node.tag == .scalar and node.c != 0) return false;
            return independentScalarReplacement(m, node.a, self_binding, depth + 1, remaining) and
                independentScalarReplacement(m, node.b, self_binding, depth + 1, remaining);
        },
        .array_op => {
            const operation = m.arrayOperation(id);
            if (operation != .get and operation != .length) return false;
            for (m.children(id)) |child| {
                if (!independentScalarReplacement(m, child, self_binding, depth + 1, remaining)) return false;
            }
            return true;
        },
        else => return false,
    }
}
test "scalar replacement proof declines self captures dispatch and bounded exhaustion" {
    var nodes = [_]core.Node{
        .{ .tag = .invalid },
        .{ .tag = .constant, .ty = T.u32_type, .a = 42 },
        .{ .tag = .reference, .a = 0 },
        .{ .tag = .reference, .a = 1 },
        .{ .tag = .reference, .a = 2 },
        .{ .tag = .reference, .a = 3 },
        .{ .tag = .scalar, .a = 4, .b = 1 },
        .{ .tag = .array_op, .a = 0, .b = 2, .c = @backingInt(core.ArrayOp.get) },
        .{ .tag = .array_op, .a = 0, .b = 1, .c = @backingInt(core.ArrayOp.length) },
        .{ .tag = .closure },
        .{ .tag = .scalar, .a = 4, .b = 1, .c = 1 },
        .{ .tag = .logical, .a = 7, .b = 8 },
        .{ .tag = .array_op, .a = 0, .b = 2, .c = @backingInt(core.ArrayOp.set) },
        .{ .tag = .scalar, .a = 1, .b = 2 },
        .{ .tag = .array_op, .a = 2, .b = 2, .c = @backingInt(core.ArrayOp.get) },
        .{ .tag = .reference, .a = 4 },
        .{ .tag = .reference, .a = 5 },
    };
    var references = [_]core.BindingRef{
        .{ .binding = 1 },            .{ .unit = 1, .binding = 1 }, .{ .binding = 2 },
        .{ .unit = 1, .binding = 3 }, .{ .unit = 2, .binding = 1 }, .{ .binding = 4 },
    };
    var bindings: [5]core.Binding = undefined;
    for (&bindings) |*binding| {
        binding.* = std.mem.zeroes(core.Binding);
        binding.kind = .local;
    }
    bindings[2].kind = .parameter;
    bindings[4].kind = .global;
    var extra = [_]core.Id{ 4, 5, 4, 2 };
    var m: core.Module = .{
        .unit = 1,
        .types = .{ .nodes = &.{}, .extra = &.{} },
        .nodes = &nodes,
        .spans = &.{},
        .extra = &extra,
        .bindings = &bindings,
        .bodies = &.{},
        .parameters = &.{},
        .references = &references,
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
    for ([_]core.Id{ 1, 4, 5, 6, 7, 8, 11 }) |id| {
        var remaining: usize = 64;
        try std.testing.expect(independentScalarReplacement(&m, id, 1, 0, &remaining));
    }
    for ([_]core.Id{ 2, 3, 9, 10, 12, 13, 14, 15, 16 }) |id| {
        var remaining: usize = 64;
        try std.testing.expect(!independentScalarReplacement(&m, id, 1, 0, &remaining));
    }
    // No capture/body tables are consulted for unsupported forms: every such
    // node declines even if its ordinary children look independent.
    for ([_]core.Tag{ .closure, .call, .apply, .project, .proof_guard, .match, .pattern_bind, .update, .loop }) |tag| {
        nodes[9] = .{ .tag = tag, .a = 1, .b = 1 };
        var remaining: usize = 64;
        try std.testing.expect(!independentScalarReplacement(&m, 9, 1, 0, &remaining));
    }
    var chain: [35]core.Node = undefined;
    chain[0] = .{ .tag = .invalid };
    chain[1] = .{ .tag = .constant };
    for (chain[2..], 2..) |*node, id| node.* = .{ .tag = .scalar, .a = @intCast(id - 1) };
    m.nodes = &chain;
    var remaining: usize = 64;
    try std.testing.expect(independentScalarReplacement(&m, 33, 1, 0, &remaining));
    remaining = 64;
    try std.testing.expect(!independentScalarReplacement(&m, 34, 1, 0, &remaining));
    for (chain[2..8], 2..) |*node, id| node.* = .{ .tag = .scalar, .a = @intCast(id - 1), .b = @intCast(id - 1) };
    remaining = 64;
    try std.testing.expect(independentScalarReplacement(&m, 6, 1, 0, &remaining));
    try std.testing.expectEqual(@as(usize, 1), remaining);
    remaining = 64;
    try std.testing.expect(!independentScalarReplacement(&m, 7, 1, 0, &remaining));
    try std.testing.expectEqual(@as(usize, 0), remaining);
}
const Value = struct {
    tag: enum { scalar, array, ref, view, link, aggregate, callable } = .scalar,
    word: Local,
    root: ?usize = null,
    other_roots: []const usize = &.{},
    // Published child metadata is immutable. Constructors fill private vectors;
    // recursive writers detach a vector before obtaining mutable children.
    fields: []const Value = &.{},
    variant_tags: []const u32 = &.{},
    variant_index: ?usize = null,
    // Immutable evidence about initialized payloads. Empty means unknown;
    // fresh pool layouts start with an all-false set and stores widen it.
    variant_possible: []const bool = &.{},
    terminated: bool = false,
    sequence: bool = false,
    pool_borrow: bool = false,
    token: Local = .{ .id = 0 },
    epoch_low: Local = .{ .id = 0 },
    epoch_high: Local = .{ .id = 0 },
    index: Local = .{ .id = 0 },
    length: Local = .{ .id = 0 },
    depth: usize = 0,
    mode: storage.Mode = .fixed,
    floating: bool = false,
    literal: ?u32 = null,
    constant_bits: ?u32 = null,
    name: []const u8 = "",
    callable: ?*const Callable = null,
    host: ?wasm.Callback = null,
    nominal: ?T.NominalIdentity = null,
    type_evidence: ?*const TypeEvidence = null,
    // Set only after a complete anonymous-formal footprint. Semantic type
    // evidence remains complete; this bit describes the physical parameter.
    projected_parameter_fields: bool = false,
};
const ZeroSource = struct {
    function: ?u32 = null,
    word: Local = .{ .id = 0 },
    fn get(self: *ZeroSource, code: Code) std.mem.Allocator.Error!Local {
        if (self.function != code.function) {
            self.word = try code.temp();
            self.function = code.function;
        }
        return self.word;
    }
};
fn checkZeroSource(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    _ = try module.addTypedFunction(&.{}, .i32, .scalar);
    var source: ZeroSource = .{};
    const first: Code = .{ .module = &module, .function = 0 };
    const second: Code = .{ .module = &module, .function = 1 };
    const word = try source.get(first);
    try std.testing.expectEqual(@as(u32, 1), word.id);
    try std.testing.expectEqual(word, try source.get(first));
    try std.testing.expectEqual(@as(usize, 1), module.functions.items[0].locals.items.len);
    try std.testing.expectEqual(@as(usize, 0), module.functions.items[0].instructions.items.len);
    try first.value(word);
    const other = try source.get(second);
    try second.value(other);
    try std.testing.expectEqual(@as(u32, 0), other.id);
    try std.testing.expectEqual(@as(usize, 1), module.functions.items[1].locals.items.len);
    for (module.functions.items) |function| for (function.instructions.items) |inst| {
        try std.testing.expect(inst.op != .local_set and inst.op != .local_tee);
    };
}
test "default zero sources share unwritten locals per function through OOM" {
    try checkZeroSource(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, checkZeroSource, .{});
}
test "default zero source checkpoints never retain a rolled back local" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    module.memory_model = .data_stacks;
    module.fixed_memory_bytes = 65_536;
    const code: Code = .{ .module = &module, .function = 0 };
    var source: ZeroSource = .{};
    const saved = source;
    const mark = module.tailCheckpoint().?;
    _ = try module.addTypedFunction(&.{}, .i32, .scalar);
    const discarded = try source.get(code);
    module.rollbackTail(mark);
    source = saved;
    _ = try module.addTypedFunction(&.{}, .i32, .scalar);
    const replacement = try code.temp();
    try code.set(replacement, 123);
    const zero = try source.get(code);
    try std.testing.expectEqual(discarded, replacement);
    try std.testing.expect(zero.id != replacement.id);
    try code.value(zero);
    try std.testing.expectEqual(@as(usize, 2), module.functions.items[0].locals.items.len);
}
const Callable = struct {
    unit: u32,
    node: core.Id = 0,
    target: core.BindingId = 0,
    captures: []const core.BindingId = &.{},
    types: []const TypeArgument = &.{},
    goals: []const core.Obligation = &.{},

    const Kind = enum { named, closure, primitive };
    fn kind(self: Callable, owner: *const core.Module) Kind {
        if (self.node == 0) return .named;
        if (owner.node(self.node).tag == .primitive_function) return .primitive;
        return .closure;
    }
    fn signature(self: Callable, owner: *const core.Module) T.Id {
        return switch (self.kind(owner)) {
            .named => owner.binding(self.target).ty,
            .closure => owner.closure(self.node).function_type,
            .primitive => owner.typeOf(self.node),
        };
    }
};
fn orderFields(fields: []Value) void {
    std.mem.sort(Value, fields, {}, struct {
        fn less(_: void, left: Value, right: Value) bool {
            return std.mem.order(u8, left.name, right.name) == .lt;
        }
    }.less);
}
const FixedSpan = struct { length: Local, ready: ?Local = null, checked_scope: ?usize = null };
const Root = struct { word: Local, token: Local, epoch_low: Local, epoch_high: Local, stack: u32, depth: usize, element: Value, element_initialized: bool = true, known_empty: bool = false, capacity_request: ?usize = null, live: bool = true, frozen: bool = false, persistent: bool = false, dedicated: bool = true, fixed_span: ?FixedSpan = null, fixed_created: bool = false, global_ready: ?Local = null, imported_global: bool = false };
fn createdDescriptorMatches(owner: Root, value: Value) bool {
    return owner.fixed_created and owner.live and !owner.imported_global and
        owner.element.tag == .scalar and owner.element.fields.len == 0 and owner.element.root == null and owner.element.host == null and
        value.tag == .array and value.mode == .fixed and value.other_roots.len == 0 and value.host == null and
        value.word.id == owner.word.id and value.token.id == owner.token.id and
        value.epoch_low.id == owner.epoch_low.id and value.epoch_high.id == owner.epoch_high.id;
}
test "created fixed span provenance requires exact live singleton descriptor" {
    const owner: Root = .{ .word = .{ .id = 1 }, .token = .{ .id = 2 }, .epoch_low = .{ .id = 3 }, .epoch_high = .{ .id = 4 }, .stack = 0, .depth = 0, .element = .{ .word = .{ .id = 0 } }, .fixed_created = true };
    const value: Value = .{ .tag = .array, .word = owner.word, .token = owner.token, .epoch_low = owner.epoch_low, .epoch_high = owner.epoch_high, .root = 0, .mode = .fixed };
    try std.testing.expect(createdDescriptorMatches(owner, value));
    inline for (.{ "word", "token", "epoch_low", "epoch_high" }) |field| {
        var forged = value;
        @field(forged, field).id += 10;
        try std.testing.expect(!createdDescriptorMatches(owner, forged));
    }
    var mixed = value;
    mixed.other_roots = &.{1};
    try std.testing.expect(!createdDescriptorMatches(owner, mixed));
    mixed = value;
    mixed.mode = .grow;
    try std.testing.expect(!createdDescriptorMatches(owner, mixed));
    inline for (.{ "fixed_created", "live" }) |field| {
        var unproven = owner;
        @field(unproven, field) = false;
        try std.testing.expect(!createdDescriptorMatches(unproven, value));
    }
    var imported = owner;
    imported.imported_global = true;
    try std.testing.expect(!createdDescriptorMatches(imported, value));
}
const Global = struct { target: core.BindingRef, word: u32, token: u32, epoch_low: u32, epoch_high: u32, capacity_request: usize, literal_bytes: ?u32 = null, initializing: bool = false };
const TypeRef = struct { unit: u32, ty: T.Id, environment: ?[]const TypeArgument = null };
const TypeArgument = struct { unit: u32, parameter: T.Id, argument: T.Id, argument_unit: u32, environment: ?[]const TypeArgument = null };
const TypeEvidence = struct { root: TypeRef, arguments: []const TypeArgument };
fn boxTypeEvidenceIn(arena: std.mem.Allocator, source: TypeEvidence) Error!*const TypeEvidence {
    const value = try arena.create(TypeEvidence);
    value.* = source;
    return value;
}
const Binding = struct { unit: u32, id: core.BindingId, value: Value, remaining: u32 };
const ValueJoin = struct { value: ?Value = null, physical: deferred_join.Join, selective: bool = false };
const Control = struct { unit: u32, id: core.Id, nesting: u32, roots_before: usize, result: ValueJoin };
const LoopSharing = struct { whole: bool = false, fields: []const bool = &.{} };
const FrameMark = struct { word: Local, first: usize, end: usize };
const Loop = struct { unit: u32, id: core.Id, nesting: u32, roots_before: usize, carries: []Value, shared: []const LoopSharing, headers: []const Value, iterator: ?Local, mark: FrameMark, depth: usize, read_frame: usize };
const RootRead = struct { owner: usize, shape: *const Value };
const ReadFrame = struct {
    owner_limit: usize,
    first: std.ArrayList(RootRead) = .empty,
    persistent: std.ArrayList(RootRead) = .empty,
    fn position(self: *const ReadFrame, owner: usize) usize {
        var low: usize = 0;
        var high = self.first.items.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.first.items[middle].owner < owner) low = middle + 1 else high = middle;
        }
        return low;
    }
};
const WriterKind = enum { read, write };
const WriterEvent = struct { owner: usize, kind: WriterKind, shape: Value, initializes_rows: bool = true };
const WriterTrace = struct { inputs: usize, stable: bool = false, events: std.ArrayList(WriterEvent) = .empty, remaining: usize = 100_000 };
// Physical descriptor calls own their summaries for the complete compilation.
// Incoming owners are formal descriptor roles, never retained caller roots.
const FunctionAbi = enum { scalar, registers, result_slot, buffered };
const AccessContract = union(enum) { ordered: []const WriterEvent, invariant: []const recursive_admission.Access };
const ReturnedOwner = struct { element: Value, element_initialized: bool, known_empty: bool, frozen: bool };
const CheckedFunctionPlan = struct {
    entry: call_plan.Entry,
    input_words: usize,
    used_input_words: []const bool,
    result_aliases: []const u32,
    unit_result: bool,
    abi: FunctionAbi,
    return_registers: usize,
    result_pointer_first: bool = false,
    addressed_arguments: []const bool = &.{},
    result: Value,
    returned_owners: []const ReturnedOwner = &.{},
    access: AccessContract,
    regions: []const usize,
};
const RecursiveHeader = struct { target: core.BindingRef, plan: *const CheckedFunctionPlan, parameter_owners: []const u32 };
const InputBundle = struct { parameter: u32, first: u32, words: usize, needed: []bool };
const BundleSnapshot = struct { function: u32, root: usize, address: Local, words: []const Local, used: []const bool };
const DescriptorCalls = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    calls: call_plan.Cache,
    plans: std.AutoHashMapUnmanaged(u32, *const CheckedFunctionPlan) = .empty,
    declined: std.HashMapUnmanaged(call_plan.Key, void, call_plan.KeyContext, 80) = .empty,
    addressed_declined: std.HashMapUnmanaged(call_plan.Key, void, call_plan.KeyContext, 80) = .empty,
    transports: std.AutoHashMapUnmanaged(u32, ?*transport_plan.Index) = .empty,
    record_metadata: RecordMetadataCache,
    global_footprint: ?global_footprint.Index = null,
    primitive_evidence: []const TypeEvidence = &.{},
    recursion: recursive_admission.Cache = .{},
    fn initPrimitiveEvidence(self: *DescriptorCalls, units: []const core.Module) std.mem.Allocator.Error!void {
        const count = std.math.mul(usize, units.len, 5) catch return error.OutOfMemory;
        const cached = try self.arena.allocator().alloc(TypeEvidence, count);
        for (units, 0..) |unit, index| {
            for (0..5) |primitive| {
                cached[index * 5 + primitive] = .{
                    .root = .{ .unit = unit.unit, .ty = T.unit + @as(T.Id, @intCast(primitive)) },
                    .arguments = &.{},
                };
            }
        }
        self.primitive_evidence = cached;
    }
    fn decline(self: *DescriptorCalls, key: call_plan.Key) Error!void {
        if (self.declined.contains(key)) return;
        try self.declined.ensureUnusedCapacity(self.allocator, 1);
        var owned = key;
        owned.evidence = try self.arena.allocator().dupe(u32, key.evidence);
        self.declined.putAssumeCapacityNoClobber(owned, {});
    }
    fn declineAddressed(self: *DescriptorCalls, key: call_plan.Key) Error!void {
        if (self.addressed_declined.count() >= 4096 or self.addressed_declined.contains(key)) return;
        try self.addressed_declined.ensureUnusedCapacity(self.allocator, 1);
        var owned = key;
        owned.evidence = try self.arena.allocator().dupe(u32, key.evidence);
        self.addressed_declined.putAssumeCapacityNoClobber(owned, {});
    }
    fn deinit(self: *DescriptorCalls) void {
        self.recursion.deinit(self.allocator);
        if (self.global_footprint) |*index| index.deinit();
        self.calls.deinit();
        // Summary slices and shapes belong to the compilation arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.plans.deinit(self.allocator);
        // Keys borrow flat immutable words in the compilation arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.declined.deinit(self.allocator);
        // Optional negative decisions own arena keys and survive body rollback.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.addressed_declined.deinit(self.allocator);
        // Source indexes and nested buffers belong to the compilation arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.transports.deinit(self.allocator);
        self.record_metadata.deinit();
        self.arena.deinit();
    }
};
fn hasRoot(value: Value, root_id: usize) bool {
    return storage_plan.hasRoot(value, root_id);
}
fn borrows(value: Value, owner: Value) bool {
    return storage_plan.borrows(value, owner);
}
const DispatchKey = struct { unit: u32, identity: T.NominalIdentity, member: u32, operator: T.Operator, field: bool = false };
const Dispatches = std.AutoHashMapUnmanaged(DispatchKey, ?core.BindingRef);
const MethodSelector = struct {
    allocator: std.mem.Allocator,
    units: []const core.Module,
    entry: u32,
    session: ?evaluation.Session = null,
    // Getter selection borrows one immutable context for this compilation.
    bounds: @import("../check/scheme_equations.zig").Workspace,
    fn deinit(self: *MethodSelector) void {
        if (self.session) |*session| session.deinit();
        self.bounds.deinit();
    }
    fn get(self: *MethodSelector) std.mem.Allocator.Error!*evaluation.Session {
        if (self.session == null) {
            self.session = try evaluation.Session.init(self.allocator, self.units);
            self.session.?.diagnostic_context.entry = self.entry;
        }
        return &self.session.?;
    }
};
const RecordMetadataCache = struct {
    const Key = struct { unit: u32, ty: T.Id };
    const Field = struct { ty: T.Id, symbol: u32, spelling: ?[]const u8 };
    const Metadata = struct { fields: []Field, name_words: usize };

    allocator: std.mem.Allocator,
    entries: std.AutoHashMapUnmanaged(Key, Metadata) = .empty,

    fn deinit(self: *RecordMetadataCache) void {
        var values = self.entries.valueIterator();
        while (values.next()) |metadata| self.allocator.free(metadata.fields);
        self.entries.deinit(self.allocator);
    }

    fn less(_: void, left: Field, right: Field) bool {
        if (left.spelling) |name| {
            if (right.spelling) |other| return std.mem.order(u8, name, other) == .lt;
            return true;
        }
        if (right.spelling != null) return false;
        return left.symbol < right.symbol;
    }

    fn get(self: *RecordMetadataCache, owner: *const core.Module, ty: T.Id, node: T.Node, encoded_words: usize, word_work: usize) (std.mem.Allocator.Error || error{Limit})!Metadata {
        const key: Key = .{ .unit = owner.unit, .ty = ty };
        if (self.entries.get(key)) |metadata| {
            if (metadata.name_words > encoded_words or metadata.name_words > word_work) return error.Limit;
            return metadata;
        }

        var name_words: usize = 1;
        for (0..node.b) |index| {
            const field = owner.types.recordField(node, index);
            const spelling = owner.fieldSpelling(field.name);
            var words: usize = 4;
            if (spelling) |name| words = std.math.add(usize, name.len, 2) catch return error.Limit;
            name_words = std.math.add(usize, name_words, words) catch return error.Limit;
            if (name_words > encoded_words or name_words > word_work) return error.Limit;
        }

        const fields = try self.allocator.alloc(Field, node.b);
        errdefer self.allocator.free(fields);
        for (fields, 0..) |*cached, index| {
            const field = owner.types.recordField(node, index);
            const spelling = owner.fieldSpelling(field.name);
            cached.* = .{ .ty = field.ty, .symbol = field.name, .spelling = spelling };
        }
        std.mem.sort(Field, fields, {}, less);
        const metadata: Metadata = .{ .fields = fields, .name_words = name_words };
        try self.entries.put(self.allocator, key, metadata);
        return metadata;
    }
};
const Generator = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    uses: []const u32 = &.{},
    active_goals: []const core.Obligation = &.{},
    entry_unit: u32,
    specialization_origin: ?evaluation.SourceLocation = null,
    context_sensitive: bool = false,
    methods: *MethodSelector,
    calls: call_plan.Cache,
    shared_calls: *call_plan.Cache,
    descriptor_calls: *DescriptorCalls,
    field_recipes: *field_plan.Cache,
    numeric_call_peak: usize = 0,
    scalar_admission: *call_plan.ScalarAdmission,
    active_calls: *call_plan.ActiveCalls,
    specialize: bool = true,
    protected: std.ArrayList(Value) = .empty,
    append_regions: std.ArrayList(struct { unit: u32, plan: private_append.Plan }) = .empty,
    units: []const core.Module,
    module: *wasm.Module,
    runtime: storage.Runtime,
    transport: ?packets.Runtime = null,
    transport_region: ?u32 = null,
    fixed_region: u32 = 0,
    destination: ?Value = null,
    external_destination: ?usize = null,
    c: Code = undefined,
    zero_source: ZeroSource = .{},
    recursive_header: ?RecursiveHeader = null,
    recursive_scope: bool = false,
    input_bundles: []const InputBundle = &.{},
    bundle_snapshots: std.ArrayList(BundleSnapshot) = .empty,
    bundle_scan: usize = 0,
    bundle_function: ?u32 = null,
    bundle_retained_bytes: usize = 0,
    bundle_retained_count: usize = 0,
    bundle_sources: std.AutoHashMapUnmanaged(u32, void) = .empty,
    span_scopes: @import("storage_span_dominance.zig").Scopes = .{},
    stacks: std.ArrayList(bool) = .empty,
    globals: std.ArrayList(Global) = .empty,
    globals_ready: bool = false,
    global_roots: []const usize = &.{},
    type_arguments: type_arguments_index.Stack(TypeArgument) = .empty,
    max_stacks: u32 = 0,
    used_regions: std.AutoHashMapUnmanaged(usize, void) = .empty,
    roots: std.ArrayList(Root) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    controls: std.ArrayList(Control) = .empty,
    mutable_join_words: std.AutoHashMapUnmanaged(u32, void) = .empty,
    indexed_mutable_roots: usize = 0,
    loops: std.ArrayList(Loop) = .empty,
    read_frames: std.ArrayList(ReadFrame) = .empty,
    diagnostic: ?backend.Diagnostic = null,
    depth: usize = 0,
    nesting: u32 = 0,
    steps: usize = 0,
    work_limits: WorkLimits = .{},
    emission_work: *@import("../work_counters.zig").Counters,
    outlining: *scope_outline.Context,
    layout_steps: usize = 0,
    // Templates contain only closed inline data and zero local words. Each use
    // receives independent fields; root/variant evidence is never cached here.
    plain_layouts: std.AutoHashMapUnmanaged(u64, Value) = .empty,
    // Borrowed only while compiling one selected writer specialization.
    writer_trace: ?*WriterTrace = null,
    planning_writer: bool = false,
    emitting_function_plan: bool = false,
    planning_owner_graph: bool = false,
    validation_budget: *usize,
    proof_cache: *source_proof.SourceProofCache,
    dispatches: *Dispatches,
    capacity_requests: *storage_plan.CapacityRequests,
    // During tentative emission, only requests created by that transaction
    // may change. Incoming roots have no reservation authority.
    capacity_prefix: ?usize = null,
    unit_views: []const *const core.Module,
    invalid_literals: std.AutoHashMapUnmanaged(u32, void) = .empty,
    fn deinit(self: *Generator) void {
        self.span_scopes.deinit(self.allocator);
        self.calls.deinit();
        // Value fields borrow this generator's arena or immutable Core; the
        // protected list owns only its backing buffer, not those shared slices.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.protected.deinit(self.allocator);
        self.append_regions.deinit(self.allocator);
        self.roots.deinit(self.allocator);
        self.stacks.deinit(self.allocator);
        self.used_regions.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.type_arguments.deinit(self.allocator);
        self.invalid_literals.deinit(self.allocator);
        self.mutable_join_words.deinit(self.allocator);
        // Snapshot word/mask vectors belong to the generator arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.bundle_snapshots.deinit(self.allocator);
        self.bundle_sources.deinit(self.allocator);
        // Templates and nested fields are owned by the generator arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.plain_layouts.deinit(self.allocator);
        // Result trees and captured type environments belong to this arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        // Event shapes belong to the generator arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        // Scratch footprints belong to the generator arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.bindings.deinit(self.allocator);
        self.controls.deinit(self.allocator);
        self.loops.deinit(self.allocator);
        // Snapshot fields belong to the generator arena, not the list buffer.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.read_frames.deinit(self.allocator);
        self.arena.deinit();
    }
    fn boxCallable(self: *Generator, source: Callable) Error!*const Callable {
        const value = try self.arena.allocator().create(Callable);
        value.* = source;
        return value;
    }
    fn fail(self: *Generator, m: *const core.Module, id: core.Id, code: backend.Code, detail: []const u8) Error {
        if (self.diagnostic == null) self.diagnostic = .{ .unit = m.unit, .span = m.span(id), .code = code, .detail = detail };
        return error.Declined;
    }
    fn unsupported(self: *Generator, m: *const core.Module, id: core.Id) Error {
        return self.fail(m, id, .storage_unsupported, "This form is not yet supported by the bounded scoped-storage backend");
    }
    fn unit(self: *Generator, id: u32) Error!*const core.Module {
        if (id == 0 or id > self.units.len) return error.Declined;
        return &self.units[id - 1];
    }
    fn boxTypeEvidence(self: *Generator, source: TypeEvidence) Error!*const TypeEvidence {
        if (source.root.environment == null and source.arguments.len == 0 and source.root.ty >= T.unit and source.root.ty <= T.never and source.root.unit != 0 and source.root.unit <= self.descriptor_calls.primitive_evidence.len / 5) {
            const unit_index = @as(usize, source.root.unit - 1);
            const index = unit_index * 5 + @as(usize, source.root.ty - T.unit);
            if (index < self.descriptor_calls.primitive_evidence.len) {
                const cached = &self.descriptor_calls.primitive_evidence[index];
                if (cached.root.unit == source.root.unit) return cached;
            }
        }
        return boxTypeEvidenceIn(self.arena.allocator(), source);
    }
    fn constant(self: *Generator, word: u32) Error!Value {
        const local = try self.c.temp();
        try self.c.set(local, word);
        return .{ .word = local };
    }
    fn unitValue(self: *Generator) Error!Value {
        const word = try self.zero_source.get(self.c);
        self.emission_work.scoped_zero_values_shared +|= 1;
        return .{ .word = word };
    }
    fn terminated(self: *Generator) Error!Value {
        var value = try self.unitValue();
        value.terminated = true;
        return value;
    }
    fn hasWord(value: Value) bool {
        return value.tag != .aggregate or value.variant_tags.len != 0;
    }
    fn scalar(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!Local {
        if (value.tag != .scalar) return self.unsupported(m, id);
        return value.word;
    }
    fn bind(self: *Generator, m: *const core.Module, id: core.BindingId, original: Value) Error!void {
        var value: Value = undefined;
        // Core bindings are single-assignment. Without any local address in
        // the inventory, a scalar lane cannot be mutated through an alias.
        // Control carriers and capture/backedge snapshots remain independent.
        if (!self.scalar_admission.hasScalarReferences()) {
            value = self.immutableBindingValue(original, m.binding(id).kind == .parameter);
        } else value = try self.snapshot(original);
        try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = id, .value = value, .remaining = if (id < self.uses.len) self.uses[id] else 0 });
    }
    fn transportIndex(self: *Generator, m: *const core.Module) Error!?*transport_plan.Index {
        if (self.scalar_admission.hasScalarReferences() or m.updates.len == 0) return null;
        if (self.descriptor_calls.transports.get(m.unit)) |index| return index;
        const index = try transport_plan.Index.create(&self.descriptor_calls.arena, m);
        try self.descriptor_calls.transports.put(self.allocator, m.unit, index);
        return index;
    }
    fn mergeTransport(self: *Generator, m: *const core.Module, merges: []const core.Merge, merged: []?Value) Error![]const bool {
        const shared = try self.arena.allocator().alloc(bool, merges.len);
        @memset(shared, false);
        if (merges.len == 0) return shared;
        const index = try self.transportIndex(m) orelse return shared;
        for (merges, shared, merged) |merge, *reuse, *value| {
            const left = try index.canonical(merge.then_binding) orelse continue;
            const right = try index.canonical(merge.else_binding) orelse continue;
            if (left != right) continue;
            // Resolve the representative before either arm. Its physical
            // lanes dominate both paths; this lookup consumes no source use.
            var cursor = self.bindings.items.len;
            while (cursor != 0) {
                cursor -= 1;
                const binding = self.bindings.items[cursor];
                if (binding.unit != m.unit or binding.id != left) continue;
                if (binding.value.tag == .aggregate) {
                    value.* = binding.value;
                    reuse.* = true;
                }
                break;
            }
        }
        return shared;
    }
    fn transportSnapshot(self: *Generator, value: Value, shared: bool) Error!Value {
        if (!shared) return self.snapshot(value);
        self.emission_work.scoped_transport_words_avoided +|= snapshotWords(value);
        return value;
    }
    fn loopTemporary(self: *Generator, value: Value, sharing: LoopSharing) Error!Value {
        if (sharing.whole) return value;
        if (sharing.fields.len == 0) return self.temporary(value);
        var result = value;
        const fields = initializeFields(&result, try self.arena.allocator().alloc(Value, value.fields.len));
        for (fields, value.fields, sharing.fields) |*field, input, shared| {
            field.* = input;
            if (!shared) field.* = try self.temporary(input);
        }
        return result;
    }
    fn loopSnapshot(self: *Generator, value: Value, sharing: LoopSharing) Error!Value {
        if (sharing.fields.len == 0) return self.transportSnapshot(value, sharing.whole);
        var result = value;
        const fields = initializeFields(&result, try self.arena.allocator().alloc(Value, value.fields.len));
        for (fields, value.fields, sharing.fields) |*field, input, shared| field.* = try self.transportSnapshot(input, shared);
        return result;
    }
    fn assignLoop(self: *Generator, m: *const core.Module, id: core.Id, target: *Value, value: Value, sharing: LoopSharing) Error!void {
        return self.assignTransportParts(m, id, target, value, !sharing.whole, sharing.fields);
    }
    fn snapshotWords(value: Value) usize {
        if (value.tag == .scalar) return 1;
        if (value.tag == .view) return 6;
        if (value.tag == .link or (value.tag == .ref and (value.root != null or value.pool_borrow))) return 5;
        if (value.tag != .aggregate) return 0;
        var words: usize = 0;
        if (value.variant_tags.len != 0) words += 1;
        for (value.fields) |field| words += snapshotWords(field);
        return words;
    }
    fn immutableBindingValue(self: *Generator, original: Value, parameter: bool) Value {
        var value = original;
        if (value.tag == .scalar) {
            value.literal = self.knownLiteral(original);
            value.constant_bits = self.knownConstant(original);
            value.depth = self.depth;
            if (parameter) {
                self.emission_work.scoped_parameter_words_shared +|= 1;
            } else self.emission_work.scoped_local_words_shared +|= 1;
        }
        return value;
    }
    fn knownLiteral(self: *Generator, value: Value) ?u32 {
        if (self.invalid_literals.contains(value.word.id)) return null;
        return value.literal;
    }
    fn knownConstant(self: *Generator, value: Value) ?u32 {
        if (self.invalid_literals.contains(value.word.id)) return null;
        return value.constant_bits;
    }
    fn snapshot(self: *Generator, original: Value) Error!Value {
        var value = original;
        value.literal = self.knownLiteral(original);
        value.constant_bits = self.knownConstant(original);
        if (value.tag == .scalar) {
            value.word = try self.c.temp();
            try self.c.set(value.word, original.word);
            value.depth = self.depth;
        }
        if (value.tag == .view or value.tag == .link or (value.tag == .ref and (value.root != null or value.pool_borrow))) {
            value.word = try self.c.temp();
            value.token = try self.c.temp();
            value.epoch_low = try self.c.temp();
            value.epoch_high = try self.c.temp();
            value.index = try self.c.temp();
            try self.c.set(value.word, original.word);
            try self.c.set(value.token, original.token);
            try self.c.set(value.epoch_low, original.epoch_low);
            try self.c.set(value.epoch_high, original.epoch_high);
            try self.c.set(value.index, original.index);
            if (value.tag == .view) {
                value.length = try self.c.temp();
                try self.c.set(value.length, original.length);
            }
        }
        if (value.tag == .aggregate) {
            if (value.variant_tags.len != 0) {
                value.word = try self.c.temp();
                try self.c.set(value.word, original.word);
            }
            const fields = initializeFields(&value, try self.arena.allocator().alloc(Value, original.fields.len));
            for (fields, original.fields) |*field, input| field.* = try self.snapshot(input);
        }
        return value;
    }
    fn bindingValue(self: *Generator, m: *const core.Module, id: core.BindingId) Error!Value {
        var i = self.bindings.items.len;
        while (i != 0) {
            i -= 1;
            const binding = &self.bindings.items[i];
            if (binding.unit == m.unit and binding.id == id) {
                binding.remaining -|= 1;
                return binding.value;
            }
        }
        return error.Declined;
    }
    fn returnedRoot(self: *Generator, index: usize) bool {
        for (self.controls.items) |control| if (control.result.value) |value| if (hasRoot(value, index)) return true;
        return false;
    }
    fn closeRuntime(self: *Generator, first: usize, keep: Value) Error!void {
        var cursor = self.roots.items.len;
        while (cursor > first) {
            cursor -= 1;
            const index = cursor;
            const owner = self.roots.items[index];
            if (!owner.live or owner.persistent or hasRoot(keep, index)) continue;
            try self.c.value(.{ .call, self.runtime.functions.close, owner.token, owner.epoch_low, owner.epoch_high });
            try self.c.set(owner.token, 0);
        }
    }
    fn frameMark(self: *Generator) Error!FrameMark {
        const mark = try self.c.temp();
        const first = self.module.functions.items[self.c.function].instructions.items.len;
        try self.c.set(mark, .{ .call, self.runtime.functions.mark, self.fixed_region });
        return .{ .word = mark, .first = first, .end = self.module.functions.items[self.c.function].instructions.items.len };
    }
    fn rewindUnescaped(self: *Generator, first: usize, mark: FrameMark, keep: Value) Error!void {
        // Pure helper/block evaluation creates no owner to invalidate and
        // cannot advance this fixed region. Its completed scope needs neither
        // a mark nor a scan of unrelated owners. Keep instruction coordinates.
        if (first == self.roots.items.len) {
            @memset(self.module.functions.items[self.c.function].instructions.items[mark.first..mark.end], .{ .op = .nop });
            return;
        }
        // A caller opened this owner before entering the callee, but its
        // payload is constructed after the callee's mark. Root creation order
        // alone cannot prove that rewinding preserves the returned payload.
        if (self.external_destination) |root_id| if (hasRoot(keep, root_id)) return;
        for (first..self.roots.items.len) |index| if (hasRoot(keep, index)) return;
        try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, mark.word });
    }
    fn root(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!*Root {
        return &self.roots.items[value.root orelse return self.unsupported(m, id)];
    }
    fn borrowed(self: *Generator, owner: Value) bool {
        for (self.bindings.items) |binding| if (binding.remaining != 0 and borrows(binding.value, owner)) return true;
        for (self.protected.items) |value| if (borrows(value, owner)) return true;
        for (self.roots.items) |root_| if (root_.live and borrows(root_.element, owner)) return true;
        return false;
    }
    fn shape(self: *Generator, m: *const core.Module, id: core.Id, ty: T.Id, depth: usize) Error!Value {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        if (depth > 128) return self.fail(m, id, .storage_unsupported, "Storage layout exceeded its nesting bound");
        if (self.type_arguments.latestNonidentity(m.unit, ty)) |argument_index| {
            const argument = self.type_arguments.items[argument_index];
            const before = self.type_arguments.items.len;
            defer self.type_arguments.shrinkRetainingCapacity(before);
            if (argument.environment) |environment| try self.restoreTypes(environment);
            return self.shape(try self.unit(argument.argument_unit), 0, argument.argument, depth + 1);
        }
        const key = (@as(u64, m.unit) << 32) | ty;
        if (self.plain_layouts.get(key)) |template| return template;
        self.layout_steps += 1;
        if (self.layout_steps > 100_000) return self.fail(m, id, .storage_unsupported, "Storage layout exceeded its checked node budget");
        // Prove closure without ambient substitutions before building a
        // declaration-wide template. Generic constructors install only their
        // own mappings; nested field witnesses must not capture caller state.
        var remaining = 100_000 - self.layout_steps;
        const closed = call_plan.inlineType(m, ty, &remaining, 0);
        self.layout_steps = 100_000 - remaining;
        var value = if (closed) isolated: {
            const caller = self.type_arguments;
            self.type_arguments = .empty;
            defer {
                self.type_arguments.deinit(self.allocator);
                self.type_arguments = caller;
            }
            break :isolated try self.shapeUncached(m, id, ty, depth);
        } else try self.shapeUncached(m, id, ty, depth);
        // Loaded user nominal fields retain their checked semantic type even
        // when a generic projection has not resolved its own result variable.
        // Constructor-local mappings have unwound here. Closed cache entries
        // must not retain unrelated caller substitutions.
        if (value.type_evidence == null and value.nominal != null and m.types.node(ty).tag == .nominal) value.type_evidence = try self.boxTypeEvidence(.{
            .root = .{ .unit = m.unit, .ty = ty },
            .arguments = if (closed) &.{} else try self.captureTypes(),
        });
        if (closed and plainShape(value)) try self.plain_layouts.put(self.allocator, key, value);
        return value;
    }
    // Closed-storage facts are independently validated against their producer
    // before emission. An opaque layout may use them only after every actual
    // argument has resolved in its own caller environment; a phantom parameter
    // does not license an unknown, callable or borrowed argument.
    fn closedLayoutArgument(self: *Generator, input: TypeRef, remaining: *usize, depth: usize) Error!bool {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        if (remaining.* == 0 or depth > 128) return false;
        remaining.* -= 1;
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32 => return true,
            .array, .list => return self.closedLayoutArgument(.{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, remaining, depth + 1),
            .product, .record => {
                for (0..node.b) |index| {
                    const child = if (node.tag == .record) owner.types.recordField(node, index).ty else owner.types.list(.{ .start = node.a, .len = node.b })[index];
                    if (!try self.closedLayoutArgument(.{ .unit = actual.unit, .ty = child, .environment = actual.environment }, remaining, depth + 1)) return false;
                }
                return true;
            },
            .nominal => {
                for (owner.nominals) |nominal| {
                    if (remaining.* == 0) return false;
                    remaining.* -= 1;
                    if (nominal.identity.unit != node.a or nominal.identity.decl != node.b) continue;
                    if (!nominal.closed_storage or nominal.has_usage) return false;
                    const arguments = owner.types.nominalArguments(node);
                    if (arguments.len != nominal.parameters.len) return false;
                    for (arguments) |argument| if (!try self.closedLayoutArgument(.{ .unit = actual.unit, .ty = argument, .environment = actual.environment }, remaining, depth + 1)) return false;
                    return true;
                }
                return false;
            },
            else => return false,
        }
    }
    fn shapeUncached(self: *Generator, m: *const core.Module, id: core.Id, ty: T.Id, depth: usize) Error!Value {
        const n = m.types.node(ty);
        if (n.tag == .unit or n.tag == .u32 or n.tag == .boolean or n.tag == .f32) return .{ .word = .{ .id = 0 }, .floating = n.tag == .f32, .type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = ty }, .arguments = &.{} }) };
        if (@import("storage_collections.zig").element(m, ty) != null) return .{
            .tag = .array,
            .word = .{ .id = 0 },
            .sequence = n.tag == .list,
            .mode = if (types.info(&m.types, ty)) |info| switch (info.kind) {
                .grow => .grow,
                .resize => .resize,
                else => .fixed,
            } else .fixed,
            .type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = ty }, .arguments = try self.captureTypes() }),
        };
        if (n.tag == .cursor) return .{
            .tag = .view,
            .word = .{ .id = 0 },
            .pool_borrow = true,
            .type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = ty }, .arguments = try self.captureTypes() }),
        };
        if (n.tag == .record or n.tag == .product) {
            const fields = try self.arena.allocator().alloc(Value, n.b);
            for (fields, 0..) |*field, index| {
                field.* = try self.shape(m, id, if (n.tag == .record) m.types.recordField(n, index).ty else m.types.list(.{ .start = n.a, .len = n.b })[index], depth + 1);
                if (n.tag == .record) field.name = m.fieldSpelling(m.types.recordField(n, index).name) orelse return self.unsupported(m, id);
            }
            if (n.tag == .record) orderFields(fields);
            return .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields };
        }
        if (types.info(&m.types, ty)) |info| switch (info.kind) {
            .ref, .view, .link => return .{ .tag = switch (info.kind) {
                .ref => .ref,
                .view => .view,
                else => .link,
            }, .word = .{ .id = 0 }, .pool_borrow = true },
            else => {},
        };
        if (n.tag == .nominal) for (m.nominals, 0..) |nominal, ordinal| {
            if (nominal.identity.unit != n.a or nominal.identity.decl != n.b) continue;
            var source = m;
            var source_ordinal: u32 = @intCast(ordinal);
            var caller_environment: ?[]const TypeArgument = null;
            if (m.nominalConstructors(source_ordinal).len == 0) {
                if (!nominal.is_opaque or !nominal.closed_storage or nominal.has_usage or nominal.identity.unit == m.unit) return self.unsupported(m, id);
                caller_environment = try self.captureTypes();
                var remaining = 100_000 - self.layout_steps;
                for (m.types.nominalArguments(n)) |argument| {
                    if (!try self.closedLayoutArgument(.{ .unit = m.unit, .ty = argument, .environment = caller_environment }, &remaining, depth + 1)) {
                        self.layout_steps = 100_000 - remaining;
                        return self.unsupported(m, id);
                    }
                }
                source = try self.unit(nominal.identity.unit);
                if (source.unit != nominal.identity.unit) return self.unsupported(m, id);
                var found: ?u32 = null;
                for (source.nominals, 0..) |definition, index| {
                    if (remaining == 0) return self.fail(m, id, .storage_unsupported, "Storage layout exceeded its checked node budget");
                    remaining -= 1;
                    if (!std.meta.eql(definition.identity, nominal.identity)) continue;
                    if (found != null or !definition.is_opaque or !definition.closed_storage or definition.has_usage or source.nominalConstructors(@intCast(index)).len != 1) return self.unsupported(m, id);
                    found = @intCast(index);
                }
                self.layout_steps = 100_000 - remaining;
                source_ordinal = found orelse return self.unsupported(m, id);
            }
            const definition = source.nominal(source_ordinal);
            const constructors = source.nominalConstructors(source_ordinal);
            if (constructors.len == 0) {
                return self.unsupported(m, id);
            }
            const parameters = source.types.list(definition.parameters);
            const arguments = m.types.nominalArguments(n);
            if (parameters.len != arguments.len or parameters.len != nominal.parameters.len) return self.unsupported(m, id);
            const before = self.type_arguments.items.len;
            defer self.type_arguments.shrinkRetainingCapacity(before);
            for (parameters, arguments) |parameter, argument| try self.mapTypesUnder(.{ .unit = source.unit, .ty = parameter }, .{ .unit = m.unit, .ty = argument }, caller_environment, 0);
            const fields = try self.arena.allocator().alloc(Value, constructors.len);
            const tags: []u32 = if (constructors.len > 1) try self.arena.allocator().alloc(u32, constructors.len) else &.{};
            for (constructors, fields, 0..) |constructor_id, *field, index| {
                const constructor = source.constructor(constructor_id);
                const signature = source.types.node(constructor.scheme.root);
                const result_type = if (signature.tag == .function) signature.b else constructor.scheme.root;
                try self.mapTypesUnder(.{ .unit = source.unit, .ty = result_type }, .{ .unit = m.unit, .ty = ty }, caller_environment, 0);
                field.* = if (constructor.payload == 0) .{ .word = .{ .id = 0 } } else try self.shape(source, if (source == m) id else 0, constructor.payload, depth + 1);
                if (constructors.len > 1) tags[index] = constructor.tag;
            }
            return .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields, .nominal = nominal.identity, .variant_tags = tags };
        };
        return self.fail(m, id, .storage_unsupported, "Array elements require a fixed inline layout; resizable and unresolved elements cannot be stored here");
    }
    fn width(value: Value) Error!u32 {
        return @import("storage_layout.zig").bytes(value) catch error.Declined;
    }
    fn unionRoots(self: *Generator, target: *Value, value: Value) Error!void {
        return storage_plan.unionRootMetadata(self.allocator, self.arena.allocator(), self.roots.items.len, target, value);
    }
    fn storedShape(self: *Generator, m: *const core.Module, id: core.Id, target: *Value, value: Value, owner_depth: usize) Error!void {
        if (target.tag != value.tag or target.fields.len != value.fields.len or target.floating != value.floating) return self.unsupported(m, id);
        if (!std.meta.eql(target.nominal, value.nominal)) return self.unsupported(m, id);
        if (value.tag == .ref or value.tag == .view or value.tag == .link) {
            if (value.root == null) return self.fail(m, id, .storage_escape, "A local scalar reference cannot be stored in a data-stack aggregate");
            for (self.roots.items, 0..) |owner, index| if (hasRoot(value, index) and owner.depth > owner_depth) return self.fail(m, id, .storage_escape, "The stored borrow would outlive its owner");
        }
        try self.unionRoots(target, value);
        for (try self.writableFields(target), value.fields, 0..) |*field, input, index| {
            if (!possibleVariant(value, index)) continue;
            try self.storedShape(m, id, field, input, owner_depth);
        }
        try self.unionVariants(target, value);
    }
    fn possibleVariant(value: Value, index: usize) bool {
        if (value.variant_tags.len == 0) return true;
        if (value.variant_index) |selected| return selected == index;
        return value.variant_possible.len == 0 or value.variant_possible[index];
    }
    fn unionVariants(self: *Generator, target: *Value, value: Value) Error!void {
        if (target.variant_tags.len == 0) return;
        const possible = try self.arena.allocator().alloc(bool, target.variant_tags.len);
        for (possible, 0..) |*present, index| present.* = possibleVariant(target.*, index) or possibleVariant(value, index);
        target.variant_possible = possible;
        if (target.variant_index != value.variant_index) target.variant_index = null;
    }
    fn emptyShape(self: *Generator, input: Value) Error!Value {
        var value = input;
        if (value.variant_tags.len != 0 and !plainShape(value)) {
            const possible = try self.arena.allocator().alloc(bool, value.variant_tags.len);
            @memset(possible, false);
            value.variant_possible = possible;
            value.variant_index = null;
        }
        const fields = initializeFields(&value, try self.arena.allocator().alloc(Value, input.fields.len));
        for (fields, input.fields) |*field, original| field.* = try self.emptyShape(original);
        return value;
    }
    fn storeValue(self: *Generator, address: Local, offset: u32, value: Value) Error!void {
        switch (value.tag) {
            .scalar => try self.c.store(address, offset, value.word),
            .ref, .link, .view => {
                try self.c.store(address, offset, value.word);
                try self.c.store(address, offset + 4, value.token);
                try self.c.store(address, offset + 8, value.epoch_low);
                try self.c.store(address, offset + 12, value.epoch_high);
                try self.c.store(address, offset + 16, value.index);
                if (value.tag == .view) try self.c.store(address, offset + 20, value.length);
            },
            .aggregate => {
                if (value.variant_tags.len != 0) {
                    try self.c.store(address, offset, value.word);
                    for (value.fields, value.variant_tags) |field, tag| {
                        try self.c.when(.{ .i32_eq, value.word, tag });
                        self.nesting += 1;
                        try self.storeValue(address, offset + 4, field);
                        self.nesting -= 1;
                        try self.c.end();
                    }
                    return;
                }
                var at = offset;
                for (value.fields) |field| {
                    try self.storeValue(address, at, field);
                    at += try width(field);
                }
            },
            .array, .callable => unreachable,
        }
    }
    fn loadValue(self: *Generator, address: Local, offset: u32, shape_: Value) Error!Value {
        var value = shape_;
        value.word = .{ .id = 0 };
        if (hasWord(value)) value.word = try self.c.temp();
        switch (value.tag) {
            .scalar => try self.c.set(value.word, .{ .load, address, offset }),
            .ref, .link, .view => {
                try self.c.set(value.word, .{ .load, address, offset });
                value.token = try self.c.temp();
                value.epoch_low = try self.c.temp();
                value.epoch_high = try self.c.temp();
                value.index = try self.c.temp();
                try self.c.set(value.token, .{ .load, address, offset + 4 });
                try self.c.set(value.epoch_low, .{ .load, address, offset + 8 });
                try self.c.set(value.epoch_high, .{ .load, address, offset + 12 });
                try self.c.set(value.index, .{ .load, address, offset + 16 });
                if (value.tag == .view) {
                    value.length = try self.c.temp();
                    try self.c.set(value.length, .{ .load, address, offset + 20 });
                }
            },
            .aggregate => {
                const fields = initializeFields(&value, try self.arena.allocator().alloc(Value, shape_.fields.len));
                if (value.variant_tags.len != 0) {
                    try self.c.set(value.word, .{ .load, address, offset });
                    const valid = try self.c.temp();
                    try self.c.set(valid, 0);
                    for (fields, shape_.fields, value.variant_tags) |*field, input, tag| {
                        try self.c.when(.{ .i32_eq, value.word, tag });
                        self.nesting += 1;
                        field.* = try self.loadValue(address, offset + 4, input);
                        try self.c.set(valid, 1);
                        self.nesting -= 1;
                        try self.c.end();
                    }
                    try self.c.trap(.{ .i32_eqz, valid });
                    value.variant_index = null;
                    return value;
                }
                var at = offset;
                for (fields, shape_.fields) |*field, input| {
                    field.* = try self.loadValue(address, at, input);
                    at += try width(input);
                }
            },
            .array, .callable => unreachable,
        }
        return value;
    }
    const ElementPlace = struct { address: Local, element: Value };
    fn fixedScalarSpan(self: *Generator, value: Value) Error!?FixedSpan {
        // Private helpers cannot cross the host boundary or close input owners.
        // Match immutable physical descriptors, never only a possible root set.
        if (self.writer_trace == null or value.tag != .array or value.mode != .fixed or value.other_roots.len != 0 or value.host != null) return null;
        const root_id = value.root orelse return null;
        const owner = &self.roots.items[root_id];
        if (owner.imported_global and owner.global_ready == null) return null;
        if (!owner.live or owner.element.tag != .scalar or owner.element.fields.len != 0 or owner.element.root != null or owner.element.host != null) return null;
        if (value.word.id != owner.word.id or value.token.id != owner.token.id or value.epoch_low.id != owner.epoch_low.id or value.epoch_high.id != owner.epoch_high.id) return null;
        if (owner.fixed_span == null) {
            // Locals recreated in a loop need a fresh create receipt, not a
            // function-wide lazy cache (including growers frozen later).
            if (root_id >= self.writer_trace.?.inputs) return null;
            owner.fixed_span = .{ .length = try self.c.temp(), .ready = try self.c.temp() };
            self.emission_work.scoped_fixed_spans +|= 1;
        }
        var span = owner.fixed_span.?;
        if (span.ready) |ready| {
            try self.span_scopes.scan(self.allocator, self.c.function, self.module.functions.items[self.c.function].instructions.items);
            if (self.span_scopes.contains(span.checked_scope)) return span;
            // Readiness starts at typed zero on each function call. Validate at
            // the first actual use, preserving zero-iteration and branch order.
            try self.c.when(.{ .i32_eqz, ready });
            if (owner.fixed_created) {
                try self.c.set(span.length, .{ .load, value.word, 8 });
                self.emission_work.scoped_created_span_validations_avoided +|= 1;
            } else try self.c.set(span.length, .{ .call, self.runtime.functions.length, value.token, value.epoch_low, value.epoch_high, value.word });
            try self.c.set(ready, 1);
            try self.c.end();
            span.checked_scope = self.span_scopes.current();
            owner.fixed_span = span;
        }
        return span;
    }
    fn elementAddress(self: *Generator, value: Value, index: Local) Error!Local {
        const address = try self.c.temp();
        if (try self.fixedScalarSpan(value)) |span| {
            try self.c.trap(.{ .i32_ge_u, index, span.length });
            try self.c.set(address, .{ .i32_add, .{ .i32_add, value.word, storage.header_bytes }, .{ .i32_mul, index, 4 } });
            self.emission_work.scoped_fixed_span_accesses +|= 1;
        } else try self.c.set(address, .{ .call, self.runtime.functions.address, value.token, value.epoch_low, value.epoch_high, value.word, index });
        return address;
    }
    fn readElementPlace(self: *Generator, m: *const core.Module, id: core.Id, array_: Value, index: Local) Error!?ElementPlace {
        try self.writerEvent(m, id, array_, .read);
        try self.registerShapeRead(array_);
        const address = try self.elementAddress(array_, index);
        if (self.emptyUninitialized(array_)) {
            // The checked address traps: every possible owner was constructed
            // with zero rows and has had no write. Do not manufacture payload
            // borrow roots for this unreachable value. The read frame still
            // rejects a later backedge that adds reachable payload evidence.
            try self.c.op(.unreachable_, 0);
            return null;
        }
        var element = (try self.root(m, id, array_)).element;
        // A joined pool can hold borrows into either origin. Preserve the
        // complete origin set independently of the runtime-selected address.
        for (array_.other_roots) |other| {
            // An empty alternative has no payload whose borrow roots must be
            // merged. Its address is still checked against its runtime length.
            if (!self.roots.items[other].element_initialized) continue;

            try self.storedShape(m, id, &element, self.roots.items[other].element, std.math.maxInt(usize));
        }
        return .{ .address = address, .element = element };
    }
    fn readElement(self: *Generator, m: *const core.Module, id: core.Id, array_: Value, index: Local) Error!Value {
        const place = try self.readElementPlace(m, id, array_, index) orelse return self.terminated();
        return self.loadValue(place.address, 0, place.element);
    }
    fn emptyUninitialized(self: *const Generator, value: Value) bool {
        const first = value.root orelse return false;
        const owner = self.roots.items[first];
        if (!owner.known_empty or owner.element_initialized) return false;
        for (value.other_roots) |other| {
            const alternative = self.roots.items[other];
            if (!alternative.known_empty or alternative.element_initialized) return false;
        }
        return true;
    }
    fn zeroShape(self: *Generator, shape_: Value) Error!Value {
        var value = shape_;
        value.word = .{ .id = 0 };
        if (hasWord(value)) value.word = (try self.constant(0)).word;
        if (value.variant_tags.len != 0) {
            const possible = try self.arena.allocator().alloc(bool, value.variant_tags.len);
            @memset(possible, false);
            value.variant_possible = possible;
            value.variant_index = null;
        }
        if (value.pool_borrow or value.tag == .array) {
            value.token = (try self.constant(0)).word;
            value.epoch_low = (try self.constant(0)).word;
            value.epoch_high = (try self.constant(0)).word;
            value.index = (try self.constant(0)).word;
            if (value.tag == .view) value.length = (try self.constant(0)).word;
        }
        const fields = initializeFields(&value, try self.arena.allocator().alloc(Value, shape_.fields.len));
        for (fields, shape_.fields) |*field, input| field.* = try self.zeroShape(input);
        return value;
    }
    fn initializeFields(value: *Value, fields: []Value) []Value {
        value.fields = fields;
        return fields;
    }
    // Shallow path copy; descendants remain shared until their own mutation.
    fn writableFields(self: *Generator, value: *Value) Error![]Value {
        return initializeFields(value, try self.arena.allocator().dupe(Value, value.fields));
    }
    fn beginReadFrame(self: *Generator) Error!usize {
        const index = self.read_frames.items.len;
        try self.read_frames.append(self.allocator, .{ .owner_limit = self.roots.items.len });
        return index;
    }
    fn readShapeSnapshot(self: *Generator, value: Value) Error!*const Value {
        const snapshot_ = try self.arena.allocator().create(Value);
        snapshot_.* = value;
        return snapshot_;
    }
    fn registerShapeRead(self: *Generator, value: Value) Error!void {
        // Every enclosing runtime loop needs the read, including reads in a
        // nested generator. Evidence must not share mutable field slices.
        for (self.read_frames.items) |*frame| {
            if (value.root) |owner| try self.registerFrameRead(frame, owner);
            for (value.other_roots) |owner| try self.registerFrameRead(frame, owner);
        }
    }
    fn registerFrameRead(self: *Generator, frame: *ReadFrame, owner: usize) Error!void {
        if (owner >= frame.owner_limit) return self.registerPersistentRead(frame, owner);
        const position = frame.position(owner);
        if (position < frame.first.items.len and frame.first.items[position].owner == owner) return;
        const shape_ = try self.readShapeSnapshot(self.roots.items[owner].element);
        // Arena lifetime matches immutable snapshots. Keep ordinary owner order
        // for deterministic first-error selection, independent of read order.
        try frame.first.insert(self.arena.allocator(), position, .{ .owner = owner, .shape = shape_ });
    }
    fn registerPersistentRead(self: *Generator, frame: *ReadFrame, owner: usize) Error!void {
        // Global owners may be opened lazily inside a loop. Their storage is
        // persistent even though their compiler root index is new here.
        if (!self.roots.items[owner].persistent) return;
        for (frame.persistent.items) |read| if (read.owner == owner) return;
        const shape_ = try self.readShapeSnapshot(self.roots.items[owner].element);
        try frame.persistent.append(self.arena.allocator(), .{ .owner = owner, .shape = shape_ });
    }
    fn includesReadShape(before: Value, after: Value) bool {
        if (before.tag != after.tag or before.fields.len != after.fields.len or before.variant_tags.len != after.variant_tags.len) return false;
        if (after.root) |owner| if (!hasRoot(before, owner)) return false;
        for (after.other_roots) |owner| if (!hasRoot(before, owner)) return false;
        for (before.fields, after.fields, 0..) |old, next, index| {
            if (!possibleVariant(after, index)) continue;
            if (!possibleVariant(before, index) or !includesReadShape(old, next)) return false;
        }
        return true;
    }
    fn checkReadFrame(self: *Generator, m: *const core.Module, id: core.Id, index: usize) Error!void {
        for (self.read_frames.items[index].first.items) |read| {
            if (!includesReadShape(read.shape.*, self.roots.items[read.owner].element)) return self.fail(m, id, .storage_escape, "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read");
        }
        for (self.read_frames.items[index].persistent.items) |read| {
            if (!includesReadShape(read.shape.*, self.roots.items[read.owner].element)) return self.fail(m, id, .storage_escape, "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read");
        }
    }
    fn writeElement(self: *Generator, m: *const core.Module, id: core.Id, array_: Value, index: ?Local, value: Value) Error!void {
        for (self.roots.items, 0..) |*owner, root_id| if (array_.root == root_id or std.mem.findScalar(usize, array_.other_roots, root_id) != null) {
            try self.storedShape(m, id, &owner.element, value, owner.depth);
            owner.element_initialized = true;
            owner.known_empty = false;
        };
        try self.writerEvent(m, id, array_, .write);
        var address: Local = undefined;
        if (index) |at| address = try self.elementAddress(array_, at) else {
            address = try self.c.temp();
            try self.c.set(address, .{ .call, self.runtime.functions.append_space, array_.token, array_.epoch_low, array_.epoch_high, array_.word });
        }
        try self.storeValue(address, 0, value);
    }
    fn inputOwner(self: *const Generator, value: Value) bool {
        const trace = self.writer_trace orelse return false;
        return storage_plan.nextRoot(value, 0, @min(trace.inputs, self.roots.items.len)) != null;
    }
    fn writableCapacity(self: *const Generator, request: usize) Error!void {
        if (self.capacity_prefix) |prefix| if (request < prefix) return error.Declined;
    }
    fn writerEvent(self: *Generator, m: *const core.Module, id: core.Id, value: Value, kind: WriterKind) Error!void {
        return self.writerAccess(m, id, value, kind, true);
    }
    fn writerAccess(self: *Generator, m: *const core.Module, id: core.Id, value: Value, kind: WriterKind, initializes_rows: bool) Error!void {
        const trace = self.writer_trace orelse return;
        for (self.roots.items, 0..) |owner, index| {
            if (index >= trace.inputs or !hasRoot(value, index)) continue;
            // Plain rows without variants cannot change their borrow or shape
            // facts. Repeated reads/writes are idempotent for this summary.
            if (trace.stable) {
                var seen = false;
                for (trace.events.items) |*event| if (event.owner == index and event.kind == kind) {
                    event.initializes_rows = event.initializes_rows or initializes_rows;
                    seen = true;
                    break;
                };
                if (seen) continue;
            }
            if (trace.remaining == 0) return self.fail(m, id, .storage_unsupported, "Writer access summary exceeded its checked event budget");
            trace.remaining -= 1;
            try trace.events.append(self.allocator, .{ .owner = index, .kind = kind, .shape = owner.element, .initializes_rows = initializes_rows });
        }
    }
    fn privateAppendNode(self: *const Generator, unit_: u32, id: core.Id, comptime field: []const u8) bool {
        var index = self.append_regions.items.len;
        while (index != 0) {
            index -= 1;
            const region = self.append_regions.items[index];
            if (region.unit == unit_ and @field(region.plan, field) == id) return true;
        }
        return false;
    }
    fn freezeValue(self: *Generator, m: *const core.Module, id: core.Id, first: Value) Error!Value {
        if (self.inputOwner(first)) return error.Declined;
        if (self.frozen(first)) return self.fail(m, id, .storage_borrow_conflict, "This array's growth capability was already consumed");
        for (self.roots.items, 0..) |*owner, index| if (hasRoot(first, index)) {
            owner.frozen = true;
        };
        try self.c.value(.{ .call, self.runtime.functions.freeze, first.token, first.epoch_low, first.epoch_high, first.word });
        var result = first;
        result.mode = .fixed;
        result.type_evidence = null;
        return result;
    }
    fn frozen(self: *Generator, owner: Value) bool {
        for (self.roots.items, 0..) |item, index| if (item.frozen and hasRoot(owner, index)) return true;
        return false;
    }
    fn temporary(self: *Generator, value: Value) Error!Value {
        var result = value;
        result.literal = null;
        result.constant_bits = null;
        if (value.host != null) {
            result.word = .{ .id = try self.module.addLocal(self.c.function, .externref) };
        } else if (!hasWord(value)) {
            result.word = .{ .id = 0 };
        } else if (value.tag != .ref or value.root != null or value.pool_borrow) result.word = try self.c.temp();
        if (value.root != null or value.pool_borrow or value.tag == .array) {
            result.token = try self.c.temp();
            result.epoch_low = try self.c.temp();
            result.epoch_high = try self.c.temp();
        }
        if (value.tag == .ref or value.tag == .view or value.tag == .link) result.index = try self.c.temp();
        if (value.tag == .view) result.length = try self.c.temp();
        const fields = initializeFields(&result, try self.arena.allocator().alloc(Value, value.fields.len));
        for (fields, value.fields) |*field, original| field.* = try self.temporary(original);
        return result;
    }
    fn loopHeader(self: *Generator, value: *Value) Error!void {
        // The body runs with values from every backedge, not just the entry
        // edge. An inactive inline payload needs no extra authority. Borrowed
        // payloads retain exactly the incoming evidence; every backedge must
        // remain within that set, independently of owner identity stability.
        if (value.variant_tags.len != 0) {
            const possible = try self.arena.allocator().alloc(bool, value.fields.len);
            for (possible, value.fields, 0..) |*present, field, index| present.* = possibleVariant(value.*, index) or plainShape(field);
            value.variant_index = null;
            value.variant_possible = possible;
        }
        for (try self.writableFields(value)) |*field| try self.loopHeader(field);
    }
    fn assign(self: *Generator, m: *const core.Module, id: core.Id, target: *Value, value: Value) Error!void {
        return self.assignTransport(m, id, target, value, true);
    }
    fn assignTransport(self: *Generator, m: *const core.Module, id: core.Id, target: *Value, value: Value, copies: bool) Error!void {
        return self.assignTransportParts(m, id, target, value, copies, &.{});
    }
    fn assignTransportParts(self: *Generator, m: *const core.Module, id: core.Id, target: *Value, value: Value, copies: bool, shared_fields: []const bool) Error!void {
        target.literal = null;
        target.constant_bits = null;
        if (target.tag != value.tag or target.fields.len != value.fields.len or target.mode != value.mode or target.floating != value.floating) return self.unsupported(m, id);
        if (!std.meta.eql(target.nominal, value.nominal)) return self.unsupported(m, id);
        if (!std.meta.eql(target.host, value.host)) return self.unsupported(m, id);
        if (target.tag == .callable and target.host == null and (target.callable.?.unit != value.callable.?.unit or target.callable.?.node != value.callable.?.node or target.callable.?.target != value.callable.?.target)) return self.fail(m, id, .storage_unsupported, "A callback must have a statically known function body");
        if (target.tag == .ref and target.root == null and !target.pool_borrow) {
            if (value.root != null or target.word.id != value.word.id) return self.unsupported(m, id);
        } else if (hasWord(target.*)) {
            if (copies) try self.c.set(target.word, value.word) else self.emission_work.scoped_transport_words_avoided +|= 1;
        }
        if (target.root != null or target.pool_borrow or target.tag == .array) {
            if (copies) {
                try self.c.set(target.token, value.token);
                try self.c.set(target.epoch_low, value.epoch_low);
                try self.c.set(target.epoch_high, value.epoch_high);
            } else self.emission_work.scoped_transport_words_avoided +|= 3;
        }
        if (value.tag == .ref or value.tag == .view or value.tag == .link) {
            if (copies) try self.c.set(target.index, value.index) else self.emission_work.scoped_transport_words_avoided +|= 1;
        }
        if (value.tag == .view) {
            if (copies) try self.c.set(target.length, value.length) else self.emission_work.scoped_transport_words_avoided +|= 1;
        }
        try self.unionRoots(target, value);
        for (try self.writableFields(target), value.fields, 0..) |*field, original, index| {
            if (!possibleVariant(value, index)) continue;
            try self.assignTransport(m, id, field, original, copies and (shared_fields.len == 0 or !shared_fields[index]));
        }
        try self.unionVariants(target, value);
    }
    fn newJoin(self: *Generator) ValueJoin {
        return .{ .physical = deferred_join.Join.init(self.c) };
    }
    fn shareableNode(value: Value) bool {
        if (value.variant_tags.len != 0 or value.host != null) return false;
        if ((value.tag == .ref or value.tag == .view or value.tag == .link) and value.root == null and !value.pool_borrow) return false;
        return true;
    }
    fn joinNodeWords(self: *Generator, value: Value, words: *std.ArrayList(Local)) Error!void {
        const arena = self.arena.allocator();
        if (hasWord(value)) try words.append(arena, value.word);
        if (value.root != null or value.pool_borrow or value.tag == .array) {
            try words.appendSlice(arena, &.{ value.token, value.epoch_low, value.epoch_high });
        }
        if (value.tag == .ref or value.tag == .view or value.tag == .link) try words.append(arena, value.index);
        if (value.tag == .view) try words.append(arena, value.length);
    }
    // Mutable inventories include every payload, even where sharing declines.
    fn joinWords(self: *Generator, value: Value, words: *std.ArrayList(Local)) Error!void {
        try self.joinNodeWords(value, words);
        for (value.fields) |field| try self.joinWords(field, words);
    }
    fn selectiveJoinWords(self: *Generator, value: Value, words: *std.ArrayList(Local)) Error!void {
        if (!shareableNode(value)) return;
        try self.joinNodeWords(value, words);
        for (value.fields) |field| try self.selectiveJoinWords(field, words);
    }
    fn joinTemplate(self: *Generator, incoming: Value) Error!Value {
        if (!shareableNode(incoming)) return self.temporary(incoming);
        var result = incoming;
        const fields = initializeFields(&result, try self.arena.allocator().alloc(Value, incoming.fields.len));
        for (fields, incoming.fields) |*field, original| field.* = try self.joinTemplate(original);
        return result;
    }
    fn assignFixedJoinParts(self: *Generator, m: *const core.Module, id: core.Id, target: *Value, incoming: Value) Error!void {
        if (!shareableNode(target.*)) return self.assign(m, id, target, incoming);
        for (try self.writableFields(target), incoming.fields) |*field, original| try self.assignFixedJoinParts(m, id, field, original);
    }
    fn joinFailure(err: scope_outline.Error) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.Declined;
    }
    fn addJoin(self: *Generator, m: *const core.Module, id: core.Id, join: *ValueJoin, incoming: Value) Error!void {
        if (join.value == null) {
            join.selective = !self.scalar_admission.hasScalarReferences() and
                incoming.tag != .scalar and shareableNode(incoming);
            join.value = incoming;
            if (join.selective) join.value = try self.joinTemplate(incoming) else join.value = try self.temporary(incoming);
        }
        if (!join.selective) return self.assign(m, id, &join.value.?, incoming);
        {
            // Keep the complete validation and owner/variant union. Its dry
            // transport is not a saving: a later edge can backfill every word.
            const avoided = self.emission_work.scoped_transport_words_avoided;
            defer self.emission_work.scoped_transport_words_avoided = avoided;
            try self.assignTransport(m, id, &join.value.?, incoming, false);
        }
        try self.assignFixedJoinParts(m, id, &join.value.?, incoming);
        var words: std.ArrayList(Local) = .empty;
        try self.selectiveJoinWords(incoming, &words);
        join.physical.add(self.arena.allocator(), self.c, self.outlining, words.items) catch |err| return joinFailure(err);
    }
    fn markMutableWords(self: *Generator, value: Value, mutable: *std.AutoHashMapUnmanaged(u32, void)) Error!void {
        var words: std.ArrayList(Local) = .empty;
        try self.joinWords(value, &words);
        for (words.items) |word| try mutable.put(self.allocator, word.id, {});
    }
    fn joinedWords(self: *Generator, value: *Value, physical: deferred_join.Join, cursor: *usize) Error!void {
        if (!shareableNode(value.*)) return;
        value.literal = null;
        value.constant_bits = null;
        if (hasWord(value.*)) {
            value.word = physical.word(cursor.*);
            cursor.* += 1;
        }
        if (value.root != null or value.pool_borrow or value.tag == .array) {
            value.token = physical.word(cursor.*);
            value.epoch_low = physical.word(cursor.* + 1);
            value.epoch_high = physical.word(cursor.* + 2);
            cursor.* += 3;
        }
        if (value.tag == .ref or value.tag == .view or value.tag == .link) {
            value.index = physical.word(cursor.*);
            cursor.* += 1;
        }
        if (value.tag == .view) {
            value.length = physical.word(cursor.*);
            cursor.* += 1;
        }
        // The validated metadata may still share immutable child slices with
        // incoming bindings and owner evidence. Detach before replacing words.
        for (try self.writableFields(value)) |*field| try self.joinedWords(field, physical, cursor);
    }
    fn finishJoin(self: *Generator, join: *ValueJoin, fallthrough: bool) Error!?Value {
        if (!join.selective) return join.value;
        // Root tokens remain mutable after release. Index each appended root
        // once; loop carriers are marked when created.
        for (self.roots.items[self.indexed_mutable_roots..]) |owner| try self.mutable_join_words.put(self.allocator, owner.token.id, {});
        self.indexed_mutable_roots = self.roots.items.len;
        const shared = join.physical.finish(self.arena.allocator(), self.c, self.outlining, &self.mutable_join_words, fallthrough) catch |err| return joinFailure(err);
        var result = join.value.?;
        var cursor: usize = 0;
        try self.joinedWords(&result, join.physical, &cursor);
        std.debug.assert(cursor == join.physical.lanes.len);
        self.emission_work.scoped_join_words_shared +|= shared;
        join.value = result;
        return result;
    }
    fn promote(self: *Generator, value: *Value, boundary: usize) Error!void {
        if (value.tag == .array) {
            var cursor: usize = 0;
            while (storage_plan.nextRoot(value.*, cursor, self.roots.items.len)) |index| {
                const owner = &self.roots.items[index];
                if (owner.depth >= boundary) owner.depth = boundary - 1;
                cursor = index + 1;
            }
            value.depth = @min(value.depth, boundary - 1);
        }
        for (try self.writableFields(value)) |*field| try self.promote(field, boundary);
    }
    fn escape(self: *Generator, m: *const core.Module, id: core.Id, value: *Value, boundary: usize) Error!void {
        try self.promote(value, boundary);
        try self.checkEscape(m, id, value.*, boundary);
    }
    fn checkEscape(self: *Generator, m: *const core.Module, id: core.Id, value: Value, boundary: usize) Error!void {
        if (value.tag == .ref or value.tag == .view or value.tag == .link) {
            if (value.root == null) {
                if (value.depth >= boundary) return self.fail(m, id, .storage_escape, "A borrowed result would outlive its local value");
            } else {
                var cursor: usize = 0;
                while (storage_plan.nextRoot(value, cursor, self.roots.items.len)) |index| {
                    if (self.roots.items[index].depth >= boundary) return self.fail(m, id, .storage_escape, "A borrowed result would outlive its data-stack owner");
                    cursor = index + 1;
                }
            }
        } else if (value.tag == .array) {
            var cursor: usize = 0;
            while (storage_plan.nextRoot(value, cursor, self.roots.items.len)) |index| {
                try self.checkEscape(m, id, self.roots.items[index].element, boundary);
                cursor = index + 1;
            }
        }
        for (value.fields) |field| try self.checkEscape(m, id, field, boundary);
    }
    fn scalarLiteralArray(m: *const core.Module, element: T.Id, values: []const core.Id) bool {
        if (values.len == 0 or values.len > std.math.maxInt(u32) / 4) return false;
        if (element != T.unit and element != T.boolean and element != T.u32_type and element != T.f32_type) return false;
        for (values) |child| {
            const node = m.node(child);
            if (node.tag != .constant or node.ty != element) return false;
        }
        return true;
    }
    fn initializeLiteralArray(self: *Generator, m: *const core.Module, id: core.Id, result: Value, values: []const core.Id, depth: usize) Error!void {
        const offset = std.math.cast(u32, self.module.data.items.len) orelse return self.unsupported(m, id);
        for (values) |child| {
            try self.chargeExpression(m, child, depth + 1);
            _ = self.module.scopedDataWord(self.runtime.literal_base, m.node(child).a) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, id),
            };
        }
        // This path owns a fresh scalar owner, so no input write or shape can
        // be hidden. Keep the ordinary metadata/observer checks once.
        const owner = &self.roots.items[result.root.?];
        try self.storedShape(m, id, &owner.element, .{ .word = .{ .id = 0 }, .floating = m.node(values[0]).ty == T.f32_type }, owner.depth);
        owner.element_initialized = true;
        owner.known_empty = false;
        try self.writerEvent(m, id, result, .write);
        const bytes: u32 = @intCast(values.len * 4);
        try self.c.copy(.{ .call, self.runtime.functions.address, result.token, result.epoch_low, result.epoch_high, result.word, 0 }, .{ .i32_add, .{ .global, self.runtime.literal_base }, offset }, bytes);
        self.emission_work.scoped_literal_data_bytes +|= bytes;
        self.emission_work.scoped_literal_writes_avoided +|= values.len;
    }
    fn array(self: *Generator, m: *const core.Module, id: core.Id, capacity: Local, mode: storage.Mode) Error!Value {
        const element = @import("storage_collections.zig").element(m, m.typeOf(id)) orelse return self.unsupported(m, id);
        const element_shape = try self.shape(m, id, element, 0);
        var result = try self.arrayWithShape(m, id, capacity, mode, element_shape);
        result.sequence = @import("storage_collections.zig").immutable(m, m.typeOf(id));
        return result;
    }
    fn arrayWithShape(self: *Generator, m: *const core.Module, id: core.Id, capacity: Local, mode: storage.Mode, element_shape: Value) Error!Value {
        var value: Value = undefined;
        if (self.destination) |destination| {
            value = destination;
            self.destination = null;
        } else value = try self.reserveOwner(m, id, mode, element_shape);
        try self.c.set(value.word, .{ .call, self.runtime.functions.create, value.token, value.epoch_low, value.epoch_high, capacity, @backingInt(mode), try width(element_shape) });
        const owner = &self.roots.items[value.root.?];
        owner.fixed_created = mode == .fixed and element_shape.tag == .scalar and element_shape.fields.len == 0 and element_shape.root == null and element_shape.host == null;
        owner.fixed_span = null;
        if (owner.fixed_created) {
            const length_ = try self.c.temp();
            try self.c.set(length_, capacity);
            self.roots.items[value.root.?].fixed_span = .{ .length = length_ };
            self.emission_work.scoped_fixed_spans +|= 1;
        }
        return value;
    }
    fn reserveOwner(self: *Generator, m: *const core.Module, id: core.Id, mode: storage.Mode, element_shape: Value) Error!Value {
        var slot: usize = self.fixed_region;
        if (mode != .fixed) {
            slot = 0;
            while (slot < self.stacks.items.len and self.stacks.items[slot]) : (slot += 1) {}
            if (slot >= storage.max_stacks) return self.fail(m, id, .storage_unsupported, "Too many simultaneously live data regions");
            if (slot == self.stacks.items.len) try self.stacks.append(self.allocator, false);
            self.stacks.items[slot] = true;
            self.max_stacks = @max(self.max_stacks, @as(u32, @intCast(slot + 1)));
            try self.used_regions.put(self.allocator, slot, {});
        }
        const token = try self.c.temp();
        const word = try self.c.temp();
        const epoch_low = try self.c.temp();
        const epoch_high = try self.c.temp();
        try self.c.set(token, .{ .call, self.runtime.functions.open, @as(u32, @intCast(slot)) });
        try self.c.set(epoch_low, .{ .call, self.runtime.functions.epoch_low, token });
        try self.c.set(epoch_high, .{ .call, self.runtime.functions.epoch_high, token });
        const index = self.roots.items.len;
        const request = if (mode != .fixed) try self.capacity_requests.add(@intCast(slot)) else null;
        try self.roots.append(self.allocator, .{ .word = word, .token = token, .epoch_low = epoch_low, .epoch_high = epoch_high, .stack = @intCast(slot), .depth = self.depth, .element = try self.emptyShape(element_shape), .element_initialized = plainShape(element_shape), .capacity_request = request, .dedicated = mode != .fixed });
        return .{ .tag = .array, .word = word, .token = token, .epoch_low = epoch_low, .epoch_high = epoch_high, .root = index, .depth = self.depth, .mode = mode };
    }
    fn fromWire(self: *Generator, m: *const core.Module, id: core.Id, pointer: Local, kind: wasm.Scalar) Error!Value {
        const transport = self.transport orelse return self.unsupported(m, id);
        const count = try self.c.temp();
        try self.c.set(count, .{ .call, transport.length, pointer });
        const value = try self.arrayWithShape(m, id, count, .fixed, .{ .word = .{ .id = 0 }, .floating = kind == .array_f32 });
        try self.c.copy(.{ .i32_add, value.word, storage.header_bytes }, .{ .i32_add, pointer, 4 }, .{ .i32_mul, count, 4 });
        return value;
    }
    fn toWire(self: *Generator, m: *const core.Module, id: core.Id, value: Value, kind: wasm.Scalar) Error!Local {
        const transport = self.transport orelse return self.unsupported(m, id);
        if (value.tag != .array) return self.unsupported(m, id);
        const shape_ = (try self.root(m, id, value)).element;
        if (shape_.tag != .scalar or shape_.floating != (kind == .array_f32)) return self.unsupported(m, id);
        const count = try self.length(m, id, value);
        const pointer = try self.c.temp();
        try self.c.trap(.{ .i32_gt_u, count, (std.math.maxInt(u32) - 4) / 4 });
        try self.c.set(pointer, .{ .call, transport.allocate, .{ .i32_add, 4, .{ .i32_mul, count, 4 } } });
        try self.c.store(pointer, 0, count);
        try self.c.copy(.{ .i32_add, pointer, 4 }, .{ .i32_add, value.word, storage.header_bytes }, .{ .i32_mul, count, 4 });
        return pointer;
    }
    fn resetPackets(self: *Generator) Error!void {
        if (self.transport) |transport| {
            try self.c.value(.{ .call, transport.reset, 0 });
            try self.c.op(.drop, 0);
        }
    }
    fn hostCall(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value) Error!Value {
        if (self.writer_trace != null) return error.Declined;
        const signature = function.host.?;
        const import = self.module.importHostCallback(signature) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, id);
        };
        try self.resetPackets();
        const input = if (arrayAbi(signature.parameter)) try self.toWire(m, id, argument, signature.parameter) else try self.scalar(m, id, argument);
        try self.c.value(function.word);
        try self.c.value(input);
        if (signature.parameter == .f32) try self.c.op(.f32_reinterpret_i32, 0);
        try self.c.op(.call_import, import);
        const output = try self.c.temp();
        if (signature.result == .f32) try self.c.op(.i32_reinterpret_f32, 0);
        try self.c.op(.local_set, output.id);
        const result = if (arrayAbi(signature.result)) try self.fromWire(m, id, output, signature.result) else Value{ .word = output, .floating = signature.result == .f32 };
        try self.resetPackets();
        return result;
    }
    fn plainShape(value: Value) bool {
        return plainShapePointer(&value);
    }
    fn plainShapePointer(value: *const Value) bool {
        if (value.tag != .scalar and value.tag != .aggregate) return false;
        for (value.fields) |*field| if (!plainShapePointer(field)) return false;
        return true;
    }
    fn globalArray(self: *Generator, m: *const core.Module, id: core.Id, target: core.BindingRef) Error!Value {
        const slot = for (self.globals.items, 0..) |global, index| {
            if (std.meta.eql(global.target, target)) break index;
        } else return self.unsupported(m, id);
        const global = &self.globals.items[slot];
        if (global.initializing) return self.fail(m, id, .storage_unsupported, "Application storage initializers cannot be recursive");
        const owner = try self.unit(target.unit);
        const binding = owner.binding(target.binding);
        const initializer = (owner.body(target.binding) orelse return self.unsupported(m, id)).root;

        const info = types.info(&owner.types, binding.ty);
        const mode: storage.Mode = if (info) |kind| (if (kind.kind == .grow) .grow else .resize) else .fixed;
        const sequence = @import("storage_collections.zig").immutable(owner, binding.ty);
        // Dependency-ordered initialization dominates the entry body. Reached
        // references reuse its locals instead of emitting the initializer and
        // payload copy again. Each export clears roots before this traversal.
        for (self.roots.items, 0..) |root_, index| if (root_.persistent and root_.stack == slot) {
            var existing = root_;
            if (existing.imported_global and existing.global_ready == null) {
                existing.word = try self.c.temp();
                existing.token = try self.c.temp();
                existing.epoch_low = try self.c.temp();
                existing.epoch_high = try self.c.temp();
                existing.global_ready = try self.c.temp();
                self.roots.items[index] = existing;
            }
            if (existing.global_ready) |ready| {
                // Entry locals start at zero. Every reached reference carries
                // its guard, including references after conditional first use.
                try self.c.when(.{ .i32_eqz, ready });
                try self.c.set(existing.word, .{ .global, global.word });
                try self.c.set(existing.token, .{ .global, global.token });
                try self.c.set(existing.epoch_low, .{ .global, global.epoch_low });
                try self.c.set(existing.epoch_high, .{ .global, global.epoch_high });
                try self.c.set(ready, 1);
                try self.c.end();
                self.emission_work.scoped_global_plan_loads +|= 1;
            }
            return .{
                .tag = .array,
                .word = existing.word,
                .token = existing.token,
                .epoch_low = existing.epoch_low,
                .epoch_high = existing.epoch_high,
                .root = index,
                .depth = 0,
                .mode = mode,
                .sequence = sequence,
            };
        };
        if (self.globals_ready) return self.unsupported(m, id);
        const element = @import("storage_collections.zig").element(owner, binding.ty) orelse return self.unsupported(m, id);
        const shape_ = try self.shape(owner, initializer, element, 0);
        if (!plainShape(shape_)) return self.fail(owner, initializer, .storage_unsupported, "Application array elements currently require scalar or inline record data without borrows");
        if (mode == .fixed and owner.node(initializer).tag == .array) {
            // Fixed literal pools can never extend. Reserve only their known
            // extent, while retaining configured limits for computed lengths.
            global.literal_bytes = storage_plan.CapacityRequests.bytes(@intCast(owner.children(initializer).len), try width(shape_)) catch return self.unsupported(owner, initializer);
        }
        const index = self.roots.items.len;
        try self.roots.append(self.allocator, .{ .word = try self.c.temp(), .token = try self.c.temp(), .epoch_low = try self.c.temp(), .epoch_high = try self.c.temp(), .stack = @intCast(slot), .depth = 0, .element = shape_, .capacity_request = global.capacity_request, .persistent = true });
        const word = self.roots.items[index].word;
        const token = self.roots.items[index].token;
        const epoch_low = self.roots.items[index].epoch_low;
        const epoch_high = self.roots.items[index].epoch_high;
        try self.c.set(epoch_low, .{ .global, global.epoch_low });
        try self.c.set(epoch_high, .{ .global, global.epoch_high });
        try self.c.set(word, .{ .global, global.word });
        try self.c.set(token, .{ .global, global.token });
        const result: Value = .{ .tag = .array, .word = word, .token = token, .epoch_low = epoch_low, .epoch_high = epoch_high, .root = index, .depth = 0, .mode = mode, .sequence = sequence };
        try self.c.when(.{ .i32_eqz, word });
        self.nesting += 1;
        global.initializing = true;
        defer global.initializing = false;
        // Clear the retry handle before closing the previous unpublished
        // attempt. An open/create failure cannot leave a stale close token.
        try self.c.value(0);
        try self.c.op(.global_set, global.token);
        try self.c.value(0);
        try self.c.op(.global_set, global.epoch_low);
        try self.c.value(0);
        try self.c.op(.global_set, global.epoch_high);
        try self.c.value(.{ .call, self.runtime.functions.close, token, epoch_low, epoch_high });
        const temporary_start = self.roots.items.len;
        const initialization_mark = try self.frameMark();
        // Literal data needs a fresh temporary, not a helper's supplied
        // destination. Ordinary invocation keeps all source and escape checks.
        var source: Value = undefined;
        if (self.destination == null and owner.node(initializer).tag == .array and scalarLiteralArray(owner, element, owner.children(initializer))) {
            source = try self.invokeBody(target, &.{}, 0, false);
        } else source = try self.invoke(target, &.{}, 0);
        if (source.tag != .array) return self.unsupported(owner, initializer);
        for (self.roots.items, 0..) |root_, root_index| if (hasRoot(source, root_index) and root_.persistent) {
            return self.fail(owner, initializer, .storage_unsupported, "A named pool initializer must build fresh storage; use an explicit copy for an existing pool");
        };
        const count = try self.length(owner, initializer, source);
        try self.c.set(token, .{ .call, self.runtime.functions.open, @as(u32, @intCast(slot)) });
        try self.c.set(epoch_low, .{ .call, self.runtime.functions.epoch_low, token });
        try self.c.set(epoch_high, .{ .call, self.runtime.functions.epoch_high, token });
        // This unpublished owner is retained only as a retry handle. Publish
        // global.word after every payload write and temporary cleanup succeeds.
        try self.c.value(token);
        try self.c.op(.global_set, global.token);
        try self.c.value(epoch_low);
        try self.c.op(.global_set, global.epoch_low);
        try self.c.value(epoch_high);
        try self.c.op(.global_set, global.epoch_high);
        try self.c.set(word, .{ .call, self.runtime.functions.create, token, epoch_low, epoch_high, count, @backingInt(mode), try width(shape_) });
        // Persistent rows were independently admitted as plain inline data.
        // Both owners are live and create checked count * stride against its
        // region. Copy the initialized payload without per-field locals or an
        // ownership walk; no descriptor-bearing row reaches this path.
        const source_shape = (try self.root(owner, initializer, source)).element;
        if (!plainShape(source_shape) or try width(source_shape) != try width(shape_)) return self.unsupported(owner, initializer);
        try self.c.copy(.{ .i32_add, word, storage.header_bytes }, .{ .i32_add, source.word, storage.header_bytes }, .{ .i32_mul, count, try width(shape_) });
        try self.release(temporary_start, null);
        try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, initialization_mark.word });
        try self.c.value(word);
        try self.c.op(.global_set, global.word);
        self.nesting -= 1;
        try self.c.end();
        return result;
    }
    fn release(self: *Generator, first: usize, keep: ?Value) Error!void {
        var cursor = self.roots.items.len;
        while (cursor > first) {
            cursor -= 1;
            const index = cursor;
            if (keep) |value| if (hasRoot(value, index)) continue;
            if (self.returnedRoot(index)) continue;
            const owner = &self.roots.items[index];
            if (!owner.live or owner.persistent) continue;
            try self.c.value(.{ .call, self.runtime.functions.close, owner.token, owner.epoch_low, owner.epoch_high });
            try self.c.set(owner.token, 0);
            if (owner.dedicated) self.stacks.items[owner.stack] = false;
            owner.live = false;
        }
    }

    fn length(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!Local {
        if (value.tag == .view) return value.length;
        if (value.tag != .array) return self.unsupported(m, id);
        if (try self.fixedScalarSpan(value)) |span| return span.length;
        const result = try self.c.temp();
        try self.c.set(result, .{ .call, self.runtime.functions.length, value.token, value.epoch_low, value.epoch_high, value.word });
        return result;
    }
    fn elementIndex(self: *Generator, m: *const core.Module, id: core.Id, value: Value, index: Local) Error!Local {
        if (value.tag == .array) return index;
        if (value.tag != .view) return self.unsupported(m, id);
        try self.c.trap(.{ .i32_ge_u, index, value.length });
        const absolute = try self.c.temp();
        try self.c.set(absolute, .{ .i32_add, value.index, index });
        return absolute;
    }
    fn operation(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const n = m.node(id);
        const op: ops.Op = @fromBackingInt(@intCast(n.c));
        const args = m.children(id);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        const first = try self.expression(m, args[0], depth + 1);
        if (first.terminated) return first;
        try self.protected.append(self.allocator, first);
        const second = if (args.len >= 2) try self.expression(m, args[1], depth + 1) else try self.constant(0);
        if (second.terminated) return second;
        const third = if (args.len == 3) try self.expression(m, args[2], depth + 1) else try self.constant(0);
        if (third.terminated) return third;
        if (op == .reserve or op == .pop or op == .truncate) {
            if (self.inputOwner(first)) return error.Declined;
        }
        switch (op) {
            .reserve => {
                const count = self.knownLiteral(second) orelse return self.fail(m, id, .storage_unsupported, "A storage reservation requires a compile-time U32 literal");
                if (first.tag != .array or first.mode == .fixed or first.root == null) return self.unsupported(m, id);
                for (self.roots.items, 0..) |owner, index| {
                    if (!hasRoot(first, index)) continue;
                    const request = owner.capacity_request orelse return self.unsupported(m, id);
                    try self.writableCapacity(request);
                    self.capacity_requests.reserve(request, count, try width(owner.element)) catch return self.fail(m, id, .storage_unsupported, "Array capacity exceeds the Wasm32 storage plan");
                }
            },
            .ref => {
                var place = args[0];
                while (m.node(place).tag == .project) place = m.node(place).a;
                if (m.node(place).tag != .reference) return self.fail(m, id, .storage_escape, "A reference needs a local place with an enclosing lifetime");
                const target = m.reference(place);
                if ((target.unit != 0 and target.unit != m.unit) or (m.binding(target.binding).kind != .local and m.binding(target.binding).kind != .parameter)) return self.unsupported(m, id);
                if (first.tag != .scalar) return self.unsupported(m, id);
                try self.invalid_literals.put(self.allocator, first.word.id, {});
                var result = first;
                result.literal = null;
                result.constant_bits = null;
                result.tag = .ref;
                result.type_evidence = null;
                return result;
            },
            .at, .link => {
                const index = try self.elementIndex(m, id, first, try self.scalar(m, id, second));
                const address = try self.c.temp();
                try self.c.set(address, .{ .call, self.runtime.functions.address, first.token, first.epoch_low, first.epoch_high, first.word, index });
                return .{ .tag = if (op == .link) .link else .ref, .word = first.word, .token = first.token, .epoch_low = first.epoch_low, .epoch_high = first.epoch_high, .root = first.root, .other_roots = first.other_roots, .index = index, .depth = first.depth };
            },
            .view => {
                const start = try self.scalar(m, id, second);
                const end = try self.scalar(m, id, third);
                const length_ = try self.length(m, id, first);
                try self.c.trap(.{ .i32_or, .{ .i32_gt_u, start, end }, .{ .i32_gt_u, end, length_ } });
                const index = try self.c.temp();
                try self.c.set(index, start);
                if (first.tag == .view) try self.c.set(index, .{ .i32_add, first.index, start });
                const count = try self.c.temp();
                try self.c.set(count, .{ .i32_sub, end, start });
                return .{ .tag = .view, .word = first.word, .token = first.token, .epoch_low = first.epoch_low, .epoch_high = first.epoch_high, .root = first.root, .other_roots = first.other_roots, .index = index, .length = count, .depth = first.depth };
            },
            .load, .write => {
                if (first.tag != .ref and first.tag != .link) return self.unsupported(m, id);
                if (op == .load) {
                    if (first.root != null) return self.readElement(m, id, first, first.index);
                    var value = try self.constant(0);
                    try self.c.set(value.word, first.word);
                    value.floating = first.floating;
                    return value;
                }
                if (first.root == null) try self.c.set(first.word, try self.scalar(m, id, second)) else try self.writeElement(m, id, first, first.index, second);
            },
            .length => return .{ .word = try self.length(m, id, first) },
            .read => {
                const index = try self.elementIndex(m, id, first, try self.scalar(m, id, second));
                return self.readElement(m, id, first, index);
            },
            .push => {
                if (self.frozen(first)) return self.fail(m, id, .storage_borrow_conflict, "This array's growth capability was consumed by freeze");
                try self.writeElement(m, id, first, null, second);
            },
            .pop, .truncate => {
                if (self.borrowed(first) or self.frozen(first)) return self.fail(m, id, .storage_borrow_conflict, "Shrinking would invalidate a live borrow or a consumed growth capability");
                const count = if (op == .pop) try self.length(m, id, first) else try self.scalar(m, id, second);
                var popped: ?Value = null;
                if (op == .pop) {
                    try self.c.trap(.{ .i32_eqz, count });
                    try self.c.set(count, .{ .i32_sub, count, 1 });
                    popped = try self.readElement(m, id, first, count);
                }
                try self.c.value(.{ .call, self.runtime.functions.truncate, first.token, first.epoch_low, first.epoch_high, first.word, count });
                if (popped) |value| return value;
            },
            .freeze => return self.freezeValue(m, id, first),
            .copy => {
                const count = try self.length(m, id, first);
                const copied = try self.array(m, id, count, first.mode);
                const index = (try self.constant(0)).word;
                try self.c.loop(.{ .i32_lt_u, index, count });
                const value = try self.readElement(m, id, first, index);
                if (!value.terminated) try self.writeElement(m, id, copied, index, value);
                try self.c.next(index);
                try self.c.again();
                return copied;
            },
        }
        return self.unitValue();
    }
    fn copyRange(self: *Generator, m: *const core.Module, id: core.Id, target: Value, offset: Local, source: Value, start: Local, count: Local) Error!void {
        const index = try self.c.temp();
        try self.c.set(index, 0);
        try self.c.op(.block, 0);
        try self.c.op(.loop, 0);
        try self.c.value(.{ .i32_ge_u, index, count });
        try self.c.op(.br_if, 1);
        const from = try self.c.temp();
        const to = try self.c.temp();
        try self.c.set(from, .{ .i32_add, start, index });
        try self.c.set(to, .{ .i32_add, offset, index });
        const value = try self.readElement(m, id, source, from);
        if (!value.terminated) try self.writeElement(m, id, target, to, value);
        try self.c.next(index);
        try self.c.op(.br, 0);
        try self.c.end();
        try self.c.end();
    }
    fn collection(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const region_count = self.append_regions.items.len;
        defer self.append_regions.shrinkRetainingCapacity(region_count);
        if (self.destination == null) if (private_append.analyzeConversion(m, id)) |plan| {
            try self.append_regions.append(self.allocator, .{ .unit = m.unit, .plan = plan });
        };
        const inputs = m.children(id);
        if (inputs.len > 3 or inputs.len == 0) return self.unsupported(m, id);
        var args: [3]Value = undefined;
        const before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(before);
        for (inputs, 0..) |input, index| {
            args[index] = try self.expression(m, input, depth + 1);
            if (args[index].terminated) return args[index];
            try self.protected.append(self.allocator, args[index]);
        }
        const op = m.arrayOperation(id);
        if (op == .append and self.privateAppendNode(m.unit, id, "append")) {
            try self.writeElement(m, id, args[0], null, args[1]);
            return args[0];
        }
        if (op == .convert and self.privateAppendNode(m.unit, id, "conversion")) {
            var result = try self.freezeValue(m, id, args[0]);
            result.sequence = false;
            return result;
        }
        const zero = (try self.constant(0)).word;
        switch (op) {
            .length => return .{ .word = try self.length(m, id, args[0]) },
            .get => return self.readElement(m, id, args[0], try self.elementIndex(m, id, args[0], try self.scalar(m, id, args[1]))),
            .simd_load, .simd_store => {
                var access: WriterKind = .read;
                if (op == .simd_store) access = .write;
                try self.writerEvent(m, id, args[0], access);
                if (access == .read) try self.registerShapeRead(args[0]);
                const element = (try self.root(m, id, args[0])).element;
                if (element.tag != .scalar or args[0].sequence) return self.unsupported(m, id);
                const start = try self.scalar(m, id, args[1]);
                const count = try self.length(m, id, args[0]);
                // Check the entire span before storing any lane, without an
                // overflowing start + 4 calculation.
                try self.c.trap(.{ .i32_or, .{ .i32_lt_u, count, 4 }, .{ .i32_gt_u, start, .{ .i32_sub, count, 4 } } });
                const at = try self.elementIndex(m, id, args[0], start);
                const address = try self.c.temp();
                try self.c.set(address, .{ .call, self.runtime.functions.address, args[0].token, args[0].epoch_low, args[0].epoch_high, args[0].word, at });
                if (op == .simd_store) {
                    const vector = try self.vectorLocal(m, id, args[2]);
                    if (args[2].fields[0].floating != element.floating) return self.unsupported(m, id);
                    try self.c.value(address);
                    try self.c.value(vector);
                    try self.c.op(.v128_store, 0);
                    return args[0];
                }
                const vector: Local = .{ .id = try self.module.addLocal(self.c.function, .v128) };
                try self.c.value(address);
                try self.c.op(.v128_load, 0);
                try self.c.op(.local_set, vector.id);
                const result = try self.temporary(try self.shape(m, id, m.typeOf(id), 0));
                for (result.fields, 0..) |field, lane| {
                    try self.c.value(vector);
                    try self.c.op(.i32x4_extract_lane, @intCast(lane));
                    try self.c.op(.local_set, field.word.id);
                }
                return result;
            },
            .set => {
                if (args[0].sequence) return self.unsupported(m, id);
                try self.writeElement(m, id, args[0], try self.scalar(m, id, args[1]), args[2]);
                return args[0];
            },
            .identity => return args[0],
            .convert => {
                const count = try self.length(m, id, args[0]);
                const result = try self.array(m, id, count, .fixed);
                try self.copyRange(m, id, result, zero, args[0], zero, count);
                return result;
            },
            .cursor => {
                var result = args[0];
                result.tag = .view;
                result.type_evidence = null;
                result.index = (try self.constant(0)).word;
                result.length = try self.length(m, id, args[0]);
                return result;
            },
            .cursor_has => {
                if (args[0].tag != .view) return self.unsupported(m, id);
                const result = try self.c.temp();
                try self.c.set(result, .{ .i32_lt_u, args[0].index, args[0].length });
                return .{ .word = result };
            },
            .cursor_value => {
                if (args[0].tag != .view) return self.unsupported(m, id);
                try self.c.trap(.{ .i32_ge_u, args[0].index, args[0].length });
                return self.readElement(m, id, args[0], args[0].index);
            },
            .cursor_advance => {
                if (args[0].tag != .view) return self.unsupported(m, id);
                var result = args[0];
                try self.c.trap(.{ .i32_ge_u, result.index, result.length });
                result.index = try self.c.temp();
                try self.c.set(result.index, .{ .i32_add, args[0].index, 1 });
                return result;
            },
            .fill, .generate => {
                const count = try self.scalar(m, id, args[0]);
                const result = try self.array(m, id, count, .fixed);
                const read_frame = try self.beginReadFrame();
                defer self.read_frames.shrinkRetainingCapacity(read_frame);
                const index = try self.c.temp();
                try self.c.set(index, 0);
                try self.c.op(.block, 0);
                try self.c.op(.loop, 0);
                self.nesting += 2;
                try self.c.value(.{ .i32_ge_u, index, count });
                try self.c.op(.br_if, 1);
                const value = if (op == .fill) args[1] else try self.apply(m, id, args[1], .{ .word = index }, depth + 1);
                if (!value.terminated) try self.writeElement(m, id, result, index, value);
                try self.checkReadFrame(m, id, read_frame);
                try self.c.next(index);
                try self.c.op(.br, 0);
                try self.c.end();
                try self.c.end();
                self.nesting -= 2;
                return result;
            },
            .concat, .append, .prepend, .slice => {
                const source_length = try self.length(m, id, args[0]);
                const count = try self.c.temp();
                var start = zero;
                if (op == .slice) {
                    start = try self.scalar(m, id, args[1]);
                    try self.c.set(count, try self.scalar(m, id, args[2]));
                    try self.c.trap(.{ .i32_gt_u, start, source_length });
                    try self.c.trap(.{ .i32_gt_u, count, .{ .i32_sub, source_length, start } });
                } else {
                    const added = if (op == .concat) try self.length(m, id, args[1]) else (try self.constant(1)).word;
                    try self.c.set(count, .{ .i32_add, source_length, added });
                    try self.c.trap(.{ .i32_lt_u, count, source_length });
                }
                const result = try self.array(m, id, count, .fixed);
                if (op == .slice) {
                    try self.copyRange(m, id, result, zero, args[0], start, count);
                } else if (op == .prepend) {
                    try self.writeElement(m, id, result, zero, args[1]);
                    try self.copyRange(m, id, result, (try self.constant(1)).word, args[0], zero, source_length);
                } else {
                    try self.copyRange(m, id, result, zero, args[0], zero, source_length);
                    if (op == .concat) try self.copyRange(m, id, result, source_length, args[1], zero, try self.length(m, id, args[1])) else try self.writeElement(m, id, result, source_length, args[1]);
                }
                return result;
            },
            else => return self.unsupported(m, id),
        }
    }
    fn restoreTypes(self: *Generator, arguments: []const TypeArgument) Error!void {
        for (arguments) |argument| {
            var present = false;
            if (self.type_arguments.latestAny(argument.unit, argument.parameter)) |position| present = std.meta.eql(self.type_arguments.items[position], argument);
            if (!present) try self.type_arguments.append(self.allocator, argument);
        }
    }
    fn inheritTypes(self: *Generator, child: *Generator) Error!void {
        const retained = try child.type_arguments.inheritActive(self.allocator, &self.type_arguments);
        self.emission_work.scoped_type_environment_inherited_raw_bindings +|= self.type_arguments.items.len;
        self.emission_work.scoped_type_environment_inherited_bindings +|= retained;
    }
    fn captureTypes(self: *Generator) Error![]const TypeArgument {
        const before = self.type_arguments.stats;
        const captured = try self.type_arguments.capture(self.arena.allocator());
        self.emission_work.scoped_type_environment_captures +|= self.type_arguments.stats.captures - before.captures;
        self.emission_work.scoped_type_environment_capture_hits +|= self.type_arguments.stats.capture_hits - before.capture_hits;
        if (self.type_arguments.stats.captures != before.captures) self.emission_work.scoped_type_environment_copied_bindings +|= captured.len;
        return captured;
    }
    fn resolveType(self: *Generator, input: TypeRef, depth: usize) Error!TypeRef {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        if (depth > 128) return error.Declined;
        if (input.environment) |environment| return self.resolveActual(.{ .unit = input.unit, .ty = input.ty }, environment, depth + 1);
        // Bounds fix these IDs; fresh substitutions bind only variable/bound
        // nodes. Captures and inheritance preserve that same key invariant.
        if (input.ty >= T.unit and input.ty <= T.never) return input;
        const position = self.type_arguments.latestNonidentity(input.unit, input.ty) orelse return input;
        const argument = self.type_arguments.items[position];
        return self.resolveType(.{ .unit = argument.argument_unit, .ty = argument.argument, .environment = argument.environment }, depth + 1);
    }
    fn mapTypes(self: *Generator, formal: TypeRef, input: TypeRef, depth: usize) Error!void {
        return self.mapTypesUnder(formal, input, null, depth);
    }
    // Actual value/callback witnesses have their own immutable substitution
    // environment. Installing it globally can overwrite an active callee's
    // inference variables when the same generic helper is instantiated twice.
    fn resolveActual(self: *Generator, input: TypeRef, environment: []const TypeArgument, depth: usize) Error!TypeRef {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        if (depth > 128) return error.Declined;
        if (input.ty >= T.unit and input.ty <= T.never) {
            self.emission_work.scoped_primitive_environment_entries_avoided +|= environment.len;
        } else {
            var at = environment.len;
            while (at != 0) {
                at -= 1;
                const item = environment[at];
                if (item.unit != input.unit or item.parameter != input.ty) continue;
                const next: TypeRef = .{ .unit = item.argument_unit, .ty = item.argument, .environment = item.environment };
                if (std.meta.eql(input, next)) continue;
                if (next.environment != null) return self.resolveType(next, depth + 1);
                return self.resolveActual(next, environment, depth + 1);
            }
        }
        const resolved = try self.resolveType(input, depth);
        return .{ .unit = resolved.unit, .ty = resolved.ty, .environment = resolved.environment orelse environment };
    }
    fn mapTypesUnder(self: *Generator, formal: TypeRef, input: TypeRef, environment: ?[]const TypeArgument, depth: usize) Error!void {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        if (depth > 128) return error.Declined;
        const actual = if (environment) |captured| try self.resolveActual(input, captured, 0) else try self.resolveType(input, 0);
        const actual_environment = actual.environment orelse environment;
        if (std.meta.eql(try self.resolveType(formal, 0), actual)) return;
        const left = try self.unit(formal.unit);
        const right = try self.unit(actual.unit);
        const source = left.types.node(formal.ty);
        const destination = right.types.node(actual.ty);
        if (source.tag == .variable or source.tag == .bound) {
            if (destination.tag == .variable or destination.tag == .bound) {
                const known = try self.resolveType(formal, 0);
                const known_owner = try self.unit(known.unit);
                const known_shape = known_owner.types.node(known.ty);
                // A getter's result may still be a source inference variable
                // even after its receiver supplied the concrete element type.
                // Propagate that fact to the result instead of erasing it.
                if (known_shape.tag != .variable and known_shape.tag != .bound) {
                    try self.type_arguments.append(self.allocator, .{ .unit = actual.unit, .parameter = actual.ty, .argument = known.ty, .argument_unit = known.unit, .environment = known.environment });
                    return;
                }
            }
            // Preserve equalities shared by several parameters/results. If a
            // maps to still-open x, specializing a also specializes every other
            // checked occurrence of x (not just this one alias of it).
            const representative = try self.resolveType(formal, 0);
            const representative_node = (try self.unit(representative.unit)).types.node(representative.ty);
            const parameter = if (representative_node.tag == .variable or representative_node.tag == .bound) representative else formal;
            if (!std.meta.eql(parameter, actual)) try self.type_arguments.append(self.allocator, .{ .unit = parameter.unit, .parameter = parameter.ty, .argument = actual.ty, .argument_unit = actual.unit, .environment = actual_environment });
            return;
        }
        if (source.tag == .forall or source.tag == .usage) return self.mapTypesUnder(.{ .unit = formal.unit, .ty = source.a }, if (destination.tag == source.tag) .{ .unit = actual.unit, .ty = destination.a } else actual, actual_environment, depth + 1);
        // A generic callback such as identity can acquire its concrete input
        // from the checked higher-order parameter (for example U32 -> a).
        // Propagate that semantic constraint to its shared result variable.
        if (destination.tag == .variable or destination.tag == .bound) {
            const known = try self.resolveType(formal, 0);
            try self.type_arguments.append(self.allocator, .{ .unit = actual.unit, .parameter = actual.ty, .argument = known.ty, .argument_unit = known.unit, .environment = known.environment });
            return;
        }
        if (source.tag != destination.tag) return;
        switch (source.tag) {
            .function => {
                try self.mapTypesUnder(.{ .unit = formal.unit, .ty = source.a }, .{ .unit = actual.unit, .ty = destination.a }, actual_environment, depth + 1);
                try self.mapTypesUnder(.{ .unit = formal.unit, .ty = source.b }, .{ .unit = actual.unit, .ty = destination.b }, actual_environment, depth + 1);
            },
            .array, .list, .cursor => try self.mapTypesUnder(.{ .unit = formal.unit, .ty = source.a }, .{ .unit = actual.unit, .ty = destination.a }, actual_environment, depth + 1),
            .product, .nominal => {
                const from = if (source.tag == .product) left.types.list(.{ .start = source.a, .len = source.b }) else left.types.nominalArguments(source);
                const to = if (destination.tag == .product) right.types.list(.{ .start = destination.a, .len = destination.b }) else right.types.nominalArguments(destination);
                if (source.tag == .nominal and (source.a != destination.a or source.b != destination.b)) return error.Declined;
                if (from.len != to.len) return error.Declined;
                for (from, to) |a, b| try self.mapTypesUnder(.{ .unit = formal.unit, .ty = a }, .{ .unit = actual.unit, .ty = b }, actual_environment, depth + 1);
            },
            .record => for (0..source.b) |index| {
                const field = left.types.recordField(source, index);
                const name = left.fieldSpelling(field.name) orelse return error.Declined;
                for (0..destination.b) |other| {
                    const target = right.types.recordField(destination, other);
                    if (std.mem.eql(u8, name, right.fieldSpelling(target.name) orelse return error.Declined)) {
                        try self.mapTypesUnder(.{ .unit = formal.unit, .ty = field.ty }, .{ .unit = actual.unit, .ty = target.ty }, actual_environment, depth + 1);
                        break;
                    }
                }
            },
            else => {},
        }
    }
    fn recordFieldRecipe(self: *Generator, query: *const core.Module, name: u32, owner: *const core.Module, ty: T.Id) Error!?field_plan.Recipe {
        const hits_before = self.field_recipes.hits;
        const probes_before = self.field_recipes.probes;
        defer {
            self.emission_work.scoped_field_recipe_hits +|= self.field_recipes.hits - hits_before;
            self.emission_work.scoped_field_name_probes +|= self.field_recipes.probes - probes_before;
        }
        return self.field_recipes.get(query, name, owner, ty);
    }
    /// Resolve dependent field results before planning a callee's local owners.
    /// The checked receiver and its actual catalog declaration establish the
    /// result; the spelling of a member never implies a collection element type.
    fn refineFields(self: *Generator, m: *const core.Module, goals: []const core.Obligation) Error!void {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        self.emission_work.scoped_field_refinements +|= 1;
        const before_stats = self.type_arguments.stats;
        defer {
            self.emission_work.scoped_refinement_lookups +|= self.type_arguments.stats.lookups - before_stats.lookups;
            self.emission_work.scoped_refinement_indexed_bindings +|= self.type_arguments.stats.synchronized - before_stats.synchronized;
        }
        var passes: usize = 0;
        while (passes <= goals.len) : (passes += 1) {
            const before = self.type_arguments.items.len;
            for (goals) |goal| {
                self.emission_work.scoped_field_goal_visits +|= 1;
                if ((goal.kind != .field and goal.kind != .collection) or goal.result == 0) continue;
                const receiver = try self.resolveType(.{ .unit = m.unit, .ty = goal.ty }, 0);
                const source = try self.unit(receiver.unit);
                const node = source.types.node(receiver.ty);
                if (goal.kind == .collection) {
                    const element = types.readableElement(&source.types, receiver.ty) orelse
                        (if (node.tag == .list) node.a else continue);
                    try self.mapTypes(.{ .unit = m.unit, .ty = goal.result }, .{ .unit = source.unit, .ty = element, .environment = receiver.environment }, 0);
                    continue;
                }
                if (node.tag == .record) {
                    const recipe = try self.recordFieldRecipe(m, goal.name, source, receiver.ty);
                    if (recipe) |field| try self.mapTypes(.{ .unit = m.unit, .ty = goal.result }, .{ .unit = source.unit, .ty = field.ty, .environment = receiver.environment }, 0);
                    continue;
                }
                const identity = T.receiverIdentity(node) orelse continue;
                const target = (try self.fieldTarget(m, identity, goal.name)) orelse continue;
                const owner = try self.unit(target.unit);
                const signature = owner.types.node(owner.binding(target.binding).ty);
                if (signature.tag != .function) continue;
                try self.mapTypes(.{ .unit = owner.unit, .ty = signature.a }, receiver, 0);
                try self.mapTypes(.{ .unit = m.unit, .ty = goal.result }, .{ .unit = owner.unit, .ty = signature.b }, 0);
            }
            if (self.type_arguments.items.len == before) return;
        }
    }
    /// Specialize only from checked semantic witnesses carried by values.
    /// Inline product fields retain their own witnesses; a machine word or a
    /// storage descriptor alone never chooses a type or associated operation.
    fn mapValueTypes(self: *Generator, formal: TypeRef, value: Value, depth: usize) Error!void {
        if (depth > 128) return error.Declined;
        if (value.type_evidence) |evidence| {
            try self.mapTypesUnder(formal, evidence.root, evidence.arguments, depth + 1);
            return;
        }
        if (value.tag != .aggregate) return;
        const actual = try self.resolveType(formal, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        if (node.tag == .product and node.b == value.fields.len) {
            for (owner.types.list(.{ .start = node.a, .len = node.b }), value.fields) |ty, field| try self.mapValueTypes(.{ .unit = actual.unit, .ty = ty }, field, depth + 1);
        } else if (node.tag == .record) {
            for (0..node.b) |index| {
                const field = owner.types.recordField(node, index);
                const name = owner.fieldSpelling(field.name) orelse return error.Declined;
                for (value.fields) |item| if (std.mem.eql(u8, item.name, name)) {
                    try self.mapValueTypes(.{ .unit = actual.unit, .ty = field.ty }, item, depth + 1);
                    break;
                };
            }
        }
    }
    fn instantiate(self: *Generator, target: core.BindingRef, signature: TypeRef, arguments: []const Value, depth: usize) Error!Value {
        const before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(before);
        const owner = try self.unit(target.unit);
        try self.mapTypes(.{ .unit = owner.unit, .ty = owner.binding(target.binding).ty }, signature, 0);
        return self.invoke(target, arguments, depth);
    }
    fn callableType(self: *Generator, value: Value) Error!?TypeRef {
        const callable = value.callable orelse return null;
        const owner = try self.unit(callable.unit);
        var signature = callable.signature(owner);
        if (callable.kind(owner) != .closure) for (value.fields) |_| {
            const arrow = owner.types.node(signature);
            if (arrow.tag != .function) return null;
            signature = arrow.b;
        };
        return .{ .unit = owner.unit, .ty = signature, .environment = callable.types };
    }
    fn primitiveCallable(self: *Generator, m: *const core.Module, id: core.Id) Error!?Value {
        const primitive_ = m.primitive(id);
        if (primitive_.kind != .scalar or primitive_.arity == 0 or primitive_.arity > 2) return null;
        var signature = m.typeOf(id);
        var machine: wasm.Scalar = .u32;
        for (0..primitive_.arity) |index| {
            const arrow = m.types.node(signature);
            if (arrow.tag != .function) return null;
            const input = m.types.node(arrow.a);
            switch (input.tag) {
                .u32, .boolean => {},
                .f32 => if (index == 0) {
                    machine = .f32;
                },
                else => return null,
            }
            signature = arrow.b;
        }
        switch (m.types.node(signature).tag) {
            .u32, .f32, .boolean => {},
            else => return null,
        }
        if (scalar_ops.opcode(primitive_.op, machine) == null) return null;
        return .{ .tag = .callable, .word = .{ .id = 0 }, .callable = try self.boxCallable(.{ .unit = m.unit, .node = id }), .type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = m.typeOf(id) }, .arguments = &.{} }) };
    }
    fn primitivePartial(self: *Generator, function: Value, argument: Value, emitting: bool) Error!Value {
        const callable = function.callable.?;
        const owner = try self.unit(callable.unit);
        const signature = (try self.callableType(function)) orelse return error.Declined;
        const arrow = owner.types.node(signature.ty);
        if (arrow.tag != .function) return error.Declined;
        try self.mapValueTypes(.{ .unit = owner.unit, .ty = arrow.a }, argument, 0);
        const fields = try self.arena.allocator().alloc(Value, function.fields.len + 1);
        @memcpy(fields[0..function.fields.len], function.fields);
        fields[function.fields.len] = argument;
        if (emitting) fields[function.fields.len] = try self.snapshot(argument);
        return .{ .tag = .callable, .word = function.word, .fields = fields, .callable = callable, .type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = owner.unit, .ty = arrow.b }, .arguments = &.{} }) };
    }
    fn applyPrimitive(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value) Error!Value {
        const callable = function.callable.?;
        const owner = try self.unit(callable.unit);
        const primitive_ = owner.primitive(callable.node);
        if (function.fields.len + 1 < primitive_.arity) return self.primitivePartial(function, argument, true);
        if (function.fields.len + 1 != primitive_.arity) return self.unsupported(m, id);
        var left = argument;
        var right = try self.unitValue();
        if (primitive_.arity == 2) {
            left = function.fields[0];
            right = argument;
        }
        self.emission_work.scoped_primitive_applications +|= 1;
        var result = try self.scalarPrimitive(m, id, primitive_.op, primitive_.arity == 2, left, right);
        const signature = (try self.callableType(function)) orelse return self.unsupported(m, id);
        const arrow = owner.types.node(signature.ty);
        if (arrow.tag != .function) return self.unsupported(m, id);
        result.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = owner.unit, .ty = arrow.b }, .arguments = &.{} });
        return result;
    }
    // Additional inline-data specializations follow exact checked numeric
    // selections. No storage, host calls, captures, global values or unknown
    // callbacks enter this summary. Generic declarations are instantiated from
    // their actual checked inputs before examining their scalar bodies.
    fn selectedInlineType(self: *Generator, input: TypeRef, remaining: *usize) Error!bool {
        return self.selectedDataType(input, false, remaining, 0);
    }
    fn selectedDataType(self: *Generator, input: TypeRef, readers: bool, remaining: *usize, depth: usize) Error!bool {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        if (remaining.* == 0 or depth > 128) return false;
        remaining.* -= 1;
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32, .never => return true,
            .array, .list => return readers and try self.selectedDataType(.{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, self.planning_owner_graph, remaining, depth + 1),
            .cursor => return readers and try self.selectedDataType(.{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, true, remaining, depth + 1),
            .product, .record => {
                for (0..node.b) |index| {
                    const child = if (node.tag == .record) owner.types.recordField(node, index).ty else owner.types.list(.{ .start = node.a, .len = node.b })[index];
                    if (!try self.selectedDataType(.{ .unit = actual.unit, .ty = child, .environment = actual.environment }, readers, remaining, depth + 1)) return false;
                }
                return true;
            },
            .nominal => {
                if (types.info(&owner.types, actual.ty)) |info| return readers and try self.selectedDataType(.{ .unit = actual.unit, .ty = info.element, .environment = actual.environment }, self.planning_owner_graph, remaining, depth + 1);
                for (owner.nominals, 0..) |nominal, ordinal| {
                    if (nominal.identity.unit != node.a or nominal.identity.decl != node.b) continue;
                    const parameters = owner.types.list(nominal.parameters);
                    const arguments = owner.types.nominalArguments(node);
                    const constructors = owner.nominalConstructors(@intCast(ordinal));
                    if (parameters.len != arguments.len or constructors.len == 0) return false;
                    if (parameters.len > remaining.*) return false;
                    remaining.* -= parameters.len;
                    const before = self.type_arguments.items.len;
                    defer self.type_arguments.shrinkRetainingCapacity(before);
                    for (parameters, arguments) |parameter, argument| try self.mapTypesUnder(.{ .unit = actual.unit, .ty = parameter }, .{ .unit = actual.unit, .ty = argument }, actual.environment, 0);
                    for (constructors) |constructor_id| {
                        if (parameters.len >= remaining.*) return false;
                        remaining.* -= parameters.len + 1;
                        const variant_before = self.type_arguments.items.len;
                        defer self.type_arguments.shrinkRetainingCapacity(variant_before);
                        const constructor = owner.constructor(constructor_id);
                        const signature = owner.types.node(constructor.scheme.root);
                        const result = if (signature.tag == .function) signature.b else constructor.scheme.root;
                        try self.mapTypesUnder(.{ .unit = actual.unit, .ty = result }, actual, actual.environment, 0);
                        // Constructor formals use the newly installed scope;
                        // its bindings retain the selected argument contexts.
                        if (constructor.payload != 0 and !try self.selectedDataType(.{ .unit = actual.unit, .ty = constructor.payload }, readers, remaining, depth + 1)) return false;
                    }
                    return true;
                }
                return false;
            },
            else => return false,
        }
    }
    // Symbolic values used only by the read-only admission walk. Runtime
    // capture words are supplied by readerParameter, never computed here.
    const GetterSelection = struct { target: core.BindingRef, receiver: TypeRef };
    fn selectedGetter(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!?GetterSelection {
        const projection = m.projection(m.node(id).b);
        var receiver = try self.resolveType(.{ .unit = m.unit, .ty = projection.source_type }, 0);
        var source = try self.unit(receiver.unit);
        if (T.receiverIdentity(source.types.node(receiver.ty)) == null) if (value.type_evidence) |evidence| {
            try self.restoreTypes(evidence.arguments);
            receiver = try self.resolveType(evidence.root, 0);
            source = try self.unit(receiver.unit);
        };
        const identity = T.receiverIdentity(source.types.node(receiver.ty)) orelse value.nominal orelse return null;
        const target = (try self.fieldTarget(m, identity, projection.field)) orelse return null;
        return .{ .target = target, .receiver = receiver };
    }
    fn planPartial(self: *Generator, m: *const core.Module, id: core.Id, remaining: *usize, depth: usize) Error!?Value {
        const n = m.node(id);
        const function = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return null;
        const callable = function.callable orelse return null;
        if (function.host != null) return null;
        const owner = try self.unit(callable.unit);
        if (callable.kind(owner) == .primitive) {
            if (function.fields.len + 1 >= owner.primitive(callable.node).arity) return null;
            const argument = (try self.planValue(m, n.b, remaining, depth + 1)) orelse return null;
            return try self.primitivePartial(function, argument, false);
        }
        if (callable.kind(owner) != .named) return null;
        const body = owner.body(callable.target) orelse return null;
        const parameters = owner.bodyParameters(body);
        if (function.fields.len + 1 >= parameters.len) return null;
        const argument = (try self.planValue(m, n.b, remaining, depth + 1)) orelse return null;
        const before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(before);
        const use_input = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.b) }, 0);
        const use_output = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
        try self.restoreTypes(callable.types);
        var signature = owner.binding(callable.target).ty;
        for (function.fields) |_| {
            const arrow = owner.types.node(signature);
            if (arrow.tag != .function) return null;
            signature = arrow.b;
        }
        const arrow = owner.types.node(signature);
        if (arrow.tag != .function) return null;
        try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.a }, use_input, 0);
        try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.b }, use_output, 0);
        const formal: TypeRef = .{ .unit = owner.unit, .ty = parameters[function.fields.len].ty };
        if (try self.callableType(argument)) |argument_signature| try self.mapTypesUnder(formal, argument_signature, argument.callable.?.types, 0) else try self.mapValueTypes(formal, argument, 0);
        const fields = try self.arena.allocator().alloc(Value, function.fields.len + 1);
        @memcpy(fields[0..function.fields.len], function.fields);
        fields[function.fields.len] = argument;
        return .{ .tag = .callable, .word = .{ .id = 0 }, .fields = fields, .callable = try self.boxCallable(.{ .unit = owner.unit, .target = callable.target, .types = try self.captureTypes() }) };
    }
    fn planGraphRead(self: *Generator, m: *const core.Module, id: core.Id, receiver: Value) Error!?Value {
        const first = receiver.root orelse return null;
        if (first >= self.roots.items.len or self.emptyUninitialized(receiver)) return null;
        var value = self.roots.items[first].element;
        for (receiver.other_roots) |other| {
            if (other >= self.roots.items.len) return null;
            if (self.roots.items[other].element_initialized) try self.storedShape(m, id, &value, self.roots.items[other].element, std.math.maxInt(usize));
        }
        value.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = m.typeOf(id) }, .arguments = try self.captureTypes() });
        return value;
    }
    fn planValue(self: *Generator, m: *const core.Module, id: core.Id, remaining: *usize, depth: usize) Error!?Value {
        if (id == 0 or remaining.* == 0 or depth > 128) return null;
        remaining.* -= 1;
        const n = m.node(id);
        switch (n.tag) {
            .reference => {
                var ref = m.reference(id);
                if (ref.unit == 0) ref.unit = m.unit;
                var at = self.bindings.items.len;
                while (at != 0) {
                    at -= 1;
                    const item = self.bindings.items[at];
                    if (item.unit == ref.unit and item.id == ref.binding) return item.value;
                }
                const owner = try self.unit(ref.unit);
                if (owner.binding(ref.binding).kind == .external) {
                    ref = owner.binding(ref.binding).target;
                    if (ref.unit == 0) ref.unit = owner.unit;
                }
                const source = try self.unit(ref.unit);
                if (source.body(ref.binding)) |body| {
                    if (body.is_function) return .{ .tag = .callable, .word = .{ .id = 0 }, .callable = try self.boxCallable(.{ .unit = ref.unit, .target = ref.binding, .types = try self.captureTypes() }) };
                    if (source.node(body.root).tag == .primitive_function or source.node(body.root).tag == .reference) return self.planValue(source, body.root, remaining, depth + 1);
                } else if (source.binding(ref.binding).kind != .local and source.binding(ref.binding).kind != .parameter) return null;
            },
            .primitive_function => return self.primitiveCallable(m, id),
            .closure => {
                const captures = m.closureCaptures(id);
                const fields = try self.arena.allocator().alloc(Value, captures.len);
                for (captures, fields) |capture, *field| {
                    var at = self.bindings.items.len;
                    var found = false;
                    while (at != 0) {
                        at -= 1;
                        const item = self.bindings.items[at];
                        if (item.unit == m.unit and item.id == capture) {
                            field.* = item.value;
                            found = true;
                            break;
                        }
                    }
                    if (!found) return null;
                }
                return .{ .tag = .callable, .word = .{ .id = 0 }, .fields = fields, .callable = try self.boxCallable(.{ .unit = m.unit, .node = id, .captures = captures, .types = try self.captureTypes(), .goals = self.active_goals }) };
            },
            .project => {
                const receiver = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return null;
                const projection = m.projection(n.b);
                const name = m.fieldSpelling(projection.field) orelse return null;
                if (dataField(receiver, name)) |field| return field;
                const before = self.type_arguments.items.len;
                defer self.type_arguments.shrinkRetainingCapacity(before);
                const selection = (try self.selectedGetter(m, id, receiver)) orelse return null;
                const owner = try self.unit(selection.target.unit);
                const body = owner.body(selection.target.binding) orelse return null;
                const signature = owner.types.node(owner.binding(selection.target.binding).ty);
                if (signature.tag != .function) return null;
                try self.mapTypes(.{ .unit = owner.unit, .ty = signature.a }, selection.receiver, 0);
                try self.mapTypes(.{ .unit = owner.unit, .ty = signature.b }, .{ .unit = m.unit, .ty = projection.result_type }, 0);
                if (owner.bodyParameters(body).len == 0) {
                    if (try self.planValue(owner, body.root, remaining, depth + 1)) |function| {
                        if (function.callable) |callable| {
                            const source = try self.unit(callable.unit);
                            if (callable.kind(source) == .primitive and source.primitive(callable.node).arity == 2) return try self.primitivePartial(function, receiver, false);
                        }
                    }
                }
                // A curried getter captures its receiver now; admission of its
                // body waits for the saturated callback, just like invoke.
                if (owner.bodyParameters(body).len > 1) return .{ .tag = .callable, .word = .{ .id = 0 }, .fields = try self.arena.allocator().dupe(Value, &.{receiver}), .callable = try self.boxCallable(.{ .unit = owner.unit, .target = selection.target.binding, .types = try self.captureTypes() }) };
            },
            .product, .record => {
                const children = m.children(id);
                const fields = try self.arena.allocator().alloc(Value, children.len);
                for (children, 0..) |child, index| {
                    const destination = if (n.tag == .record) m.recordDestinations(id)[index] else index;
                    fields[destination] = (try self.planValue(m, child, remaining, depth + 1)) orelse return null;
                    if (n.tag == .record) fields[destination].name = m.fieldSpelling(m.types.recordField(m.types.node(n.ty), destination).name) orelse return null;
                }
                if (n.tag == .record) orderFields(fields);
                return .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields };
            },
            .record_merge => {
                const left = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return null;
                const right = (try self.planValue(m, n.b, remaining, depth + 1)) orelse return null;
                return self.mergeRecordValues(left, right);
            },
            .call => {
                const call = m.call(id);
                var target = call.target;
                if (target.unit == 0) target.unit = m.unit;
                const owner = try self.unit(target.unit);
                const body = owner.body(target.binding) orelse return null;
                if (owner.bodyParameters(body).len == 0 and call.arguments.len != 0) {
                    var value = (try self.planValue(owner, body.root, remaining, depth + 1)) orelse return null;
                    const callable = value.callable orelse return null;
                    const source = try self.unit(callable.unit);
                    if (callable.kind(source) != .primitive) return null;
                    const arity = source.primitive(callable.node).arity;
                    for (call.arguments) |argument_id| {
                        if (value.fields.len + 1 >= arity) break;
                        const argument = (try self.planValue(m, argument_id, remaining, depth + 1)) orelse return null;
                        value = try self.primitivePartial(value, argument, false);
                    }
                    if (call.arguments.len < arity) return value;
                }
                if (call.arguments.len < owner.bodyParameters(body).len) {
                    const fields = try self.arena.allocator().alloc(Value, call.arguments.len);
                    for (fields, call.arguments) |*field, argument| field.* = (try self.planValue(m, argument, remaining, depth + 1)) orelse return null;
                    return .{ .tag = .callable, .word = .{ .id = 0 }, .fields = fields, .callable = try self.boxCallable(.{ .unit = owner.unit, .target = target.binding, .types = try self.captureTypes() }) };
                }
                if (call.arguments.len == owner.bodyParameters(body).len and owner.node(body.root).tag == .associated) {
                    const types_before = self.type_arguments.items.len;
                    defer self.type_arguments.shrinkRetainingCapacity(types_before);
                    const bindings_before = self.bindings.items.len;
                    defer self.bindings.shrinkRetainingCapacity(bindings_before);
                    for (owner.bodyParameters(body), call.arguments) |parameter, argument| {
                        const value = (try self.planValue(m, argument, remaining, depth + 1)) orelse return null;
                        try self.mapValueTypes(.{ .unit = owner.unit, .ty = parameter.ty }, value, 0);
                        try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = parameter.binding, .value = value, .remaining = 0 });
                    }
                    const previous_goals = self.active_goals;
                    self.active_goals = owner.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len];
                    defer self.active_goals = previous_goals;
                    if (try self.planValue(owner, body.root, remaining, depth + 1)) |value| if (value.tag == .callable) return value;
                }
            },
            .storage => {
                const op: @import("../check/storage_ops.zig").Op = @fromBackingInt(@intCast(n.c));
                const args = m.children(id);
                if (self.planning_owner_graph and (op == .read or op == .load)) {
                    const receiver = (try self.planValue(m, args[0], remaining, depth + 1)) orelse return null;
                    return self.planGraphRead(m, id, receiver);
                }
                if (op == .view or op == .at or op == .link) {
                    var receiver = (try self.planValue(m, args[0], remaining, depth + 1)) orelse return null;
                    receiver.tag = if (op == .view) .view else if (op == .at) .ref else .link;
                    // Roots describe physical provenance; the checked result
                    // describes the selected capability, not its source owner.
                    receiver.type_evidence = try self.boxTypeEvidence(.{
                        .root = .{ .unit = m.unit, .ty = n.ty },
                        .arguments = try self.captureTypes(),
                    });
                    return receiver;
                }
            },
            .array_op => if (self.planning_owner_graph) {
                const op = m.arrayOperation(id);
                if (op == .get or op == .cursor_value or op == .cursor or op == .cursor_advance) {
                    var receiver = (try self.planValue(m, m.children(id)[0], remaining, depth + 1)) orelse return null;
                    if (op == .get or op == .cursor_value) return self.planGraphRead(m, id, receiver);
                    receiver.tag = .view;
                    receiver.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = n.ty }, .arguments = try self.captureTypes() });
                    return receiver;
                }
            },
            .apply => if (try self.planPartial(m, id, remaining, depth)) |partial| return partial,
            .associated => {
                const first = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return null;
                const second = (try self.planValue(m, n.b, remaining, depth + 1)) orelse return null;
                const left = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.a) }, 0);
                const right = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.b) }, 0);
                const a = (try self.unit(left.unit)).types.node(left.ty);
                const b = (try self.unit(right.unit)).types.node(right.ty);
                if (a.tag != b.tag or (a.tag != .u32 and a.tag != .f32 and a.tag != .boolean)) return null;
                const target = (try self.dispatchTarget(m, T.receiverIdentity(a).?, n.c, .none)) orelse return null;
                const owner = try self.unit(target.unit);
                const body = owner.body(target.binding) orelse return null;
                const parameters = owner.bodyParameters(body);
                if (parameters.len <= 2) return null;
                try self.mapValueTypes(.{ .unit = owner.unit, .ty = parameters[0].ty }, first, 0);
                try self.mapValueTypes(.{ .unit = owner.unit, .ty = parameters[1].ty }, second, 0);
                const fields = try self.arena.allocator().dupe(Value, &.{ first, second });
                return .{ .tag = .callable, .word = .{ .id = 0 }, .fields = fields, .callable = try self.boxCallable(.{ .unit = owner.unit, .target = target.binding, .types = try self.captureTypes() }) };
            },
            else => {},
        }
        if (self.planning_writer and (n.tag == .array or n.tag == .call or n.tag == .apply or
            (n.tag == .array_op and (m.arrayOperation(id) == .fill or m.arrayOperation(id) == .generate))))
        {
            const actual = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
            const owner = try self.unit(actual.unit);
            const node = owner.types.node(actual.ty);
            const info = types.info(&owner.types, actual.ty);
            if (node.tag == .array or (info != null and (info.?.kind == .grow or info.?.kind == .resize))) {
                const element = @import("storage_collections.zig").element(owner, actual.ty) orelse return null;
                if (!try self.selectedInlineType(.{ .unit = actual.unit, .ty = element, .environment = actual.environment }, remaining)) return null;
                const before = self.type_arguments.items.len;
                defer self.type_arguments.shrinkRetainingCapacity(before);
                if (actual.environment) |environment| try self.restoreTypes(environment);
                const row = try self.shape(owner, 0, element, 0);
                if (!plainShape(row)) return null;
                // Admission-only descriptor. Real child emission establishes
                // allocation, aliases and ordered input-root access facts.
                const root_id = self.roots.items.len;
                try self.roots.append(self.allocator, .{ .word = .{ .id = 0 }, .token = .{ .id = 0 }, .epoch_low = .{ .id = 0 }, .epoch_high = .{ .id = 0 }, .stack = self.fixed_region, .depth = self.depth, .element = row, .element_initialized = true, .dedicated = false });
                return .{ .tag = .array, .word = .{ .id = 0 }, .root = root_id, .depth = self.depth, .mode = if (info) |kind| (if (kind.kind == .grow) .grow else .resize) else .fixed, .type_evidence = try self.boxTypeEvidence(.{ .root = actual, .arguments = try self.captureTypes() }) };
            }
        }
        if (!try self.selectedInlineType(.{ .unit = m.unit, .ty = n.ty }, remaining)) return null;
        var value = try self.shape(m, id, n.ty, 0);
        value.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = n.ty }, .arguments = try self.captureTypes() });
        return value;
    }
    fn plannedCallback(self: *Generator, function: Value, argument: Value, remaining: *usize, active: *[128]core.BindingRef, used: usize, depth: usize) Error!bool {
        const callable = function.callable orelse return false;
        if (function.host != null or used == active.len) return false;
        const owner = try self.unit(callable.unit);
        if (callable.kind(owner) == .primitive) {
            if (function.fields.len + 1 != owner.primitive(callable.node).arity) return false;
            const signature = (try self.callableType(function)) orelse return false;
            const arrow = owner.types.node(signature.ty);
            if (arrow.tag != .function) return false;
            try self.mapValueTypes(.{ .unit = owner.unit, .ty = arrow.a }, argument, 0);
            return true;
        }
        if (callable.node == 0) {
            const values = try self.arena.allocator().alloc(Value, function.fields.len + 1);
            @memcpy(values[0..function.fields.len], function.fields);
            values[function.fields.len] = argument;
            const inputs = try self.arena.allocator().alloc(TypeRef, values.len);
            const body = owner.body(callable.target) orelse return false;
            if (owner.bodyParameters(body).len != values.len) return false;
            for (inputs, values, owner.bodyParameters(body)) |*input, value, parameter| {
                if (value.type_evidence) |evidence| input.* = .{ .unit = evidence.root.unit, .ty = evidence.root.ty, .environment = evidence.arguments } else input.* = .{ .unit = owner.unit, .ty = parameter.ty, .environment = callable.types };
            }
            return self.numericCallBody(.{ .unit = owner.unit, .binding = callable.target }, inputs, values, .{ .unit = owner.unit, .ty = owner.typeOf(body.root), .environment = callable.types }, remaining, active, used, true);
        }
        const identity: core.BindingRef = .{ .unit = owner.unit, .binding = callable.node | 0x80000000 };
        for (active[0..used]) |prior| if (std.meta.eql(prior, identity)) return false;
        active[used] = identity;
        const types_before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(types_before);
        const bindings_before = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(bindings_before);
        try self.restoreTypes(callable.types);
        const closure = owner.closure(callable.node);
        const previous_goals = self.active_goals;
        self.active_goals = callable.goals;
        defer self.active_goals = previous_goals;
        try self.mapValueTypes(.{ .unit = owner.unit, .ty = closure.parameter.ty }, argument, 0);
        for (callable.captures, function.fields) |binding, capture| {
            try self.mapValueTypes(.{ .unit = owner.unit, .ty = owner.binding(binding).ty }, capture, 0);
            try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = binding, .value = capture, .remaining = 0 });
        }
        try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = closure.parameter.binding, .value = argument, .remaining = 0 });
        try self.refineFields(owner, callable.goals);
        return self.numericExpression(owner, closure.body, remaining, active, used + 1, true, depth + 1);
    }
    // A completed concrete plan never captures runtime words, owner roots or
    // substitutions. Nominal/hidden witnesses and callable rows stay scoped.
    fn concreteInlineType(self: *Generator, input: TypeRef, remaining: *usize, depth: usize) Error!bool {
        if (remaining.* == 0 or depth > 128) return false;
        remaining.* -= 1;
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32 => return true,
            .product, .record => {
                for (0..node.b) |index| {
                    const child = if (node.tag == .record) owner.types.recordField(node, index).ty else owner.types.list(.{ .start = node.a, .len = node.b })[index];
                    if (!try self.concreteInlineType(.{ .unit = actual.unit, .ty = child, .environment = actual.environment }, remaining, depth + 1)) return false;
                }
                return true;
            },
            else => return false,
        }
    }
    fn concreteInlineEvidence(self: *Generator, m: *const core.Module, body: *const core.Body) Error!?[]const u32 {
        const previous = self.diagnostic;
        return self.concreteInlineEvidenceInner(m, body) catch |err| {
            if (err == error.OutOfMemory) return err;
            self.diagnostic = previous;
            return null;
        };
    }
    fn plainInlineValue(value: Value) bool {
        if ((value.tag != .scalar and value.tag != .aggregate) or value.root != null or value.other_roots.len != 0 or value.host != null or value.callable != null or value.pool_borrow) return false;
        for (value.fields) |field| if (!plainInlineValue(field)) return false;
        return true;
    }
    fn inlineCallEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, arguments: []const Value, result: ?Value) Error!?[]const u32 {
        if (try self.concreteInlineEvidence(m, body)) |evidence| return evidence;
        const previous = self.diagnostic;
        return self.nominalInlineEvidence(m, body, arguments, result) catch |err| {
            if (err == error.OutOfMemory) return err;
            self.diagnostic = previous;
            return null;
        };
    }
    fn nominalInlineEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, arguments: []const Value, result_schema: ?Value) Error!?[]const u32 {
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        try evidence.append(self.allocator, std.math.maxInt(u32) - 6);
        if (!try self.sharedDescriptorEvidence(m, body, arguments, &evidence, null)) return null;
        const result = result_schema orelse try self.shape(m, body.root, m.typeOf(body.root), 0);
        if (!plainInlineValue(result)) return null;
        var remaining: usize = 4096;
        var work: usize = 4096;
        var keys = selected_types.Builder.init(self.allocator, &work, .{});
        defer keys.deinit();
        // Semantic type arguments alone do not determine a constructor-local
        // payload ABI. Bind both physical inputs and the rebuilt result schema.
        for (arguments) |argument| {
            if (!plainInlineValue(argument)) return null;
            try self.inlineLayoutEvidence(m, body.root, argument, &evidence, &keys);
        }
        try self.descriptorValueEvidence(m, body.root, result, &evidence, &keys, &remaining, 0);
        try self.readerLayoutEvidence(m, body.root, result, &evidence, &keys);
        try self.finishSelectedTypes(m, body.root, &evidence, &keys);
        return try evidence.toOwnedSlice(self.allocator);
    }
    // This recognizes the source identity of a field-associated ambient. It
    // does NOT close that ambient: a completed body walk must still admit all
    // other operations, and source/call effect checks remain unchanged.
    fn structuralFieldAmbients(self: *Generator, m: *const core.Module, body: *const core.Body, variables: T.List, remaining: *usize) Error!bool {
        for (m.types.list(variables)) |variable| {
            var found = false;
            for (m.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len]) |goal| {
                if (remaining.* == 0) return false;
                remaining.* -= 1;
                if (goal.kind != .field or goal.signature == 0) continue;
                const signature = m.types.node(goal.signature);
                if (signature.tag != .function) continue;
                const row = m.types.row(signature.c);
                if (row.labels.len != 0 or row.tail != .variable or row.tail.variable != variable) continue;
                const receiver = try self.resolveType(.{ .unit = m.unit, .ty = goal.ty }, 0);
                const owner = try self.unit(receiver.unit);
                if (owner.types.node(receiver.ty).tag != .record) continue;
                if (try self.recordFieldRecipe(m, goal.name, owner, receiver.ty) == null) continue;
                found = true;
                break;
            }
            if (!found) return false;
        }
        return true;
    }
    fn concreteInlineEvidenceInner(self: *Generator, m: *const core.Module, body: *const core.Body) Error!?[]const u32 {
        const binding = m.binding(body.binding);
        if (body.scheme.generative.len != 0 or binding.scheme.generative.len != 0) return null;
        var remaining: usize = 4096;
        const row_frontiers = [_]T.List{ body.scheme.row_variables, binding.scheme.row_variables, binding.public_rows };
        for (row_frontiers) |rows| if (!try self.structuralFieldAmbients(m, body, rows, &remaining)) return null;
        for (m.bodyParameters(body)) |parameter| if (!try self.concreteInlineType(.{ .unit = m.unit, .ty = parameter.ty }, &remaining, 0)) return null;
        if (!try self.concreteInlineType(.{ .unit = m.unit, .ty = m.typeOf(body.root) }, &remaining, 0)) return null;
        const frontiers = [_]T.List{ body.scheme.variables, binding.scheme.variables, binding.public_variables };
        for (frontiers) |variables| for (m.types.list(variables)) |variable| {
            if (!try self.concreteInlineType(.{ .unit = m.unit, .ty = variable }, &remaining, 0)) return null;
        };
        var evidence: std.ArrayList(u32) = .empty;
        errdefer evidence.deinit(self.allocator);
        try evidence.append(self.allocator, std.math.maxInt(u32) - 3);
        // Exact source row identities remain symbolic; these are not zero-row
        // certificates and cannot establish purity or authorize an invocation.
        for (row_frontiers) |rows| {
            try evidence.append(self.allocator, rows.len);
            try evidence.appendSlice(self.allocator, m.types.list(rows));
        }
        var type_work: usize = 4096;
        var keys = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer keys.deinit();
        for (m.bodyParameters(body)) |parameter| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, &evidence, &keys, 0);
        try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = m.typeOf(body.root) }, &evidence, &keys, 0);
        for (frontiers) |variables| {
            try evidence.append(self.allocator, variables.len);
            for (m.types.list(variables)) |variable| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = variable }, &evidence, &keys, 0);
        }
        try self.finishSelectedTypes(m, body.root, &evidence, &keys);
        return try evidence.toOwnedSlice(self.allocator);
    }
    fn descriptorAdmissionEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, values: []const Value) Error!?[]const u32 {
        // Owner-graph writers have a complete separate alias/topology key.
        // The older plain-row admission receipt cannot represent that graph.
        if (self.planning_owner_graph) return null;
        const result = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(body.root) }, 0);
        var aggregate_result = false;
        switch ((try self.unit(result.unit)).types.node(result.ty).tag) {
            .unit, .boolean, .u32, .f32 => {},
            else => aggregate_result = true,
        }
        if (aggregate_result and self.planning_writer) return null;
        var remaining: usize = 4096;
        var has_descriptor = false;
        for (values) |value| if (!self.readerArgument(value, &has_descriptor, &remaining)) return null;
        if (!has_descriptor) return null;
        var result_schema: ?Value = null;
        if (aggregate_result) {
            const diagnostic_before = self.diagnostic;
            const schema = self.shape(m, body.root, m.typeOf(body.root), 0) catch |err| {
                if (err == error.OutOfMemory) return err;
                self.diagnostic = diagnostic_before;
                return null;
            };
            if (!plainInlineValue(schema) or !stableDescriptorShape(schema)) {
                self.traceDescriptorBarrier(m, body.root, schema, "descriptor.admission.result", true);
                return null;
            }
            result_schema = schema;
        }
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        // Admission mode changes which operations are permitted.
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 5, @intFromBool(self.planning_writer) });
        if (self.planning_writer) {
            var descriptors: std.ArrayList(Value) = .empty;
            defer descriptors.deinit(self.allocator);
            for (values) |value| try self.readerDescriptors(value, &descriptors);
            var owners: std.ArrayList(usize) = .empty;
            defer owners.deinit(self.allocator);
            for (descriptors.items) |value| {
                const first = value.root orelse return null;
                if (std.mem.findScalar(usize, owners.items, first) == null) try owners.append(self.allocator, first);
                for (value.other_roots) |other| if (std.mem.findScalar(usize, owners.items, other) == null) try owners.append(self.allocator, other);
            }
            for (owners.items) |owner_id| if (!stableDescriptorShape(self.roots.items[owner_id].element)) {
                self.traceDescriptorBarrier(m, body.root, self.roots.items[owner_id].element, "descriptor.admission.writer-row", true);
                return null;
            };
            if (!try self.optionalWriterEvidence(m, body, values, descriptors.items, owners.items, &evidence)) return null;
        } else if (!try self.optionalReaderEvidence(m, body, values, &evidence)) return null;
        if (!try self.sharedDescriptorEvidence(m, body, values, &evidence, result_schema)) return null;
        return try evidence.toOwnedSlice(self.allocator);
    }
    fn plainAdmissionEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, values: ?[]const Value) Error!?[]const u32 {
        if (values) |known| return self.inlineCallEvidence(m, body, known, null);
        return self.concreteInlineEvidence(m, body);
    }
    fn admitNumericBody(self: *Generator, m: *const core.Module, target: core.BindingRef, values: ?[]const Value, remaining: *usize, active: *[128]core.BindingRef, used: usize, readers: bool) Error!bool {
        const peak_before = self.numeric_call_peak;
        self.numeric_call_peak = used;
        defer self.numeric_call_peak = @max(peak_before, self.numeric_call_peak);
        const body = m.body(target.binding) orelse return false;
        if (readers) if (values) |known| if (try self.descriptorAdmissionEvidence(m, body, known)) |evidence| {
            defer self.allocator.free(evidence);
            const key: call_plan.Key = .{ .unit = m.unit, .binding = target.binding, .context = self.invocationContext(), .evidence = evidence };
            if (self.descriptor_calls.calls.admitted(key)) |height| {
                if (remaining.* == 0 or height > 128 - used) return false;
                remaining.* -= 1;
                self.numeric_call_peak = @max(self.numeric_call_peak, used + height);
                self.emission_work.scoped_descriptor_admission_hits +|= 1;
                return true;
            }
        };
        if (!readers and !self.planning_writer) if (try self.plainAdmissionEvidence(m, body, values)) |evidence| {
            defer self.allocator.free(evidence);
            const key: call_plan.Key = .{ .unit = m.unit, .binding = target.binding, .context = self.invocationContext(), .evidence = evidence };
            if (self.shared_calls.admitted(key)) |height| {
                if (remaining.* == 0 or height > 128 - used) return false;
                remaining.* -= 1;
                self.numeric_call_peak = @max(self.numeric_call_peak, used + height);
                self.emission_work.scoped_concrete_admission_hits +|= 1;
                return true;
            }
        };
        const admitted = try self.numericExpression(m, body.root, remaining, active, used + 1, readers, 0);
        if (admitted and readers) if (values) |known| if (try self.descriptorAdmissionEvidence(m, body, known)) |evidence| {
            defer self.allocator.free(evidence);
            const key: call_plan.Key = .{ .unit = m.unit, .binding = target.binding, .context = self.invocationContext(), .evidence = evidence };
            const before = self.descriptor_calls.calls.plans.items.len;
            try self.descriptor_calls.calls.admit(key, self.numeric_call_peak - used);
            if (self.descriptor_calls.calls.plans.items.len > before) self.emission_work.scoped_descriptor_admissions +|= 1;
        };
        if (admitted and !readers and !self.planning_writer) if (try self.plainAdmissionEvidence(m, body, values)) |evidence| {
            defer self.allocator.free(evidence);
            const key: call_plan.Key = .{ .unit = m.unit, .binding = target.binding, .context = self.invocationContext(), .evidence = evidence };
            const before = self.shared_calls.plans.items.len;
            try self.shared_calls.admit(key, self.numeric_call_peak - used);
            if (self.shared_calls.plans.items.len > before) self.emission_work.scoped_concrete_admissions +|= 1;
        };
        return admitted;
    }
    fn numericCallBody(self: *Generator, target: core.BindingRef, inputs: []const TypeRef, values: ?[]const Value, output: TypeRef, remaining: *usize, active: *[128]core.BindingRef, used: usize, readers: bool) Error!bool {
        if (used == active.len) return false;
        // Different selected callbacks can nest through the same generic
        // declaration. Planning is bounded by call depth and shared work;
        // emission independently rejects exact selected-call recursion.
        const owner = try self.unit(target.unit);
        const body = owner.body(target.binding) orelse return false;
        // A planned closure captures obligations in its defining module's
        // type namespace, just as ordinary invoke/apply emission does.
        const previous_goals = self.active_goals;
        self.active_goals = owner.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len];
        defer self.active_goals = previous_goals;
        const parameters = owner.bodyParameters(body);
        if (parameters.len != inputs.len) {
            if (parameters.len == 0 and inputs.len != 0 and owner.node(body.root).tag == .primitive_function) {
                const function = (try self.primitiveCallable(owner, body.root)) orelse return false;
                const callable = function.callable.?;
                if (inputs.len != owner.primitive(callable.node).arity) return false;
                var signature = callable.signature(owner);
                for (inputs) |input| {
                    const arrow = owner.types.node(signature);
                    if (arrow.tag != .function) return false;
                    try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.a }, input, 0);
                    signature = arrow.b;
                }
                try self.mapTypes(.{ .unit = owner.unit, .ty = signature }, output, 0);
                return true;
            }
            // A source alias such as `floor = F32.floor` has no own
            // parameters. Follow only its exact reference body; evaluating a
            // factory or choosing a callback remains a separate admission.
            if (parameters.len == 0 and inputs.len != 0 and owner.node(body.root).tag == .reference and remaining.* != 0) {
                remaining.* -= 1;
                active[used] = target;
                var next = owner.reference(body.root);
                if (next.unit == 0) next.unit = owner.unit;
                return self.numericCallBody(next, inputs, values, output, remaining, active, used + 1, readers);
            }
            // A checked primitive associated partial (lerp) can consume one
            // final argument. No arbitrary factory body is evaluated here.
            const known = values orelse return false;
            const node = owner.node(body.root);
            if (inputs.len != parameters.len + 1 or node.tag != .associated) return false;
            const types_before = self.type_arguments.items.len;
            defer self.type_arguments.shrinkRetainingCapacity(types_before);
            const bindings_before = self.bindings.items.len;
            defer self.bindings.shrinkRetainingCapacity(bindings_before);
            active[used] = target;
            for (parameters, known[0..parameters.len]) |parameter, value| {
                try self.mapValueTypes(.{ .unit = owner.unit, .ty = parameter.ty }, value, 0);
                try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = parameter.binding, .value = value, .remaining = 0 });
            }
            if (!try self.numericExpression(owner, node.a, remaining, active, used + 1, readers, 0) or !try self.numericExpression(owner, node.b, remaining, active, used + 1, readers, 0)) return false;
            const function = (try self.planValue(owner, body.root, remaining, 0)) orelse return false;
            return self.plannedCallback(function, known[parameters.len], remaining, active, used + 1, 0);
        }
        const before = self.type_arguments.items.len;
        errdefer self.type_arguments.shrinkRetainingCapacity(before);
        const bindings_before = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(bindings_before);
        active[used] = target;
        if (values) |known| for (parameters, known) |parameter, value| {
            try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = parameter.binding, .value = value, .remaining = 0 });
        };
        if (values) |known| {
            for (parameters, known) |parameter, value| {
                const formal: TypeRef = .{ .unit = owner.unit, .ty = parameter.ty };
                if (try self.callableType(value)) |signature| try self.mapTypesUnder(formal, signature, value.callable.?.types, 0) else try self.mapValueTypes(formal, value, 0);
            }
        } else for (parameters, inputs) |parameter, input| try self.mapTypes(.{ .unit = owner.unit, .ty = parameter.ty }, input, 0);
        try self.mapTypes(.{ .unit = owner.unit, .ty = owner.typeOf(body.root) }, output, 0);
        try self.refineFields(owner, owner.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len]);
        const admitted = try self.admitNumericBody(owner, target, values, remaining, active, used, readers);
        var result = try self.resolveType(.{ .unit = owner.unit, .ty = owner.typeOf(body.root) }, 0);
        if (result.environment == null) switch ((try self.unit(result.unit)).types.node(result.ty).tag) {
            .unit, .boolean, .u32, .f32, .never => {},
            // Composite results can still mention formals from this temporary
            // selected call, including nested instantiations of one nominal.
            else => result.environment = try self.captureTypes(),
        };
        self.type_arguments.shrinkRetainingCapacity(before);
        if (admitted) try self.mapTypes(output, result, 0);
        return admitted;
    }
    fn numericExpression(self: *Generator, m: *const core.Module, id: core.Id, remaining: *usize, active: *[128]core.BindingRef, used: usize, readers: bool, depth: usize) Error!bool {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        self.numeric_call_peak = @max(self.numeric_call_peak, used);
        self.emission_work.scoped_call_admission_nodes +|= 1;
        if (id == 0) return true;
        if (remaining.* == 0 or depth > 128) return false;
        remaining.* -= 1;
        const n = m.node(id);
        switch (n.tag) {
            .panic => return true,
            .constant => {},
            .array => {
                if (!self.planning_writer) return false;
                for (m.children(id)) |child| if (!try self.numericExpression(m, child, remaining, active, used, readers, depth + 1)) return false;
            },
            .reference => {
                var ref = m.reference(id);
                if (ref.unit == 0) ref.unit = m.unit;
                const owner = try self.unit(ref.unit);
                const binding = owner.binding(ref.binding);
                if (binding.kind == .external) {
                    ref = binding.target;
                    if (ref.unit == 0) ref.unit = owner.unit;
                }
                const source = try self.unit(ref.unit);
                const kind = source.binding(ref.binding).kind;
                if (kind != .local and kind != .parameter) {
                    // Children receive pool descriptors explicitly; they do
                    // not own the caller's persistent-global catalog.
                    if (kind == .global and @import("storage_collections.zig").element(source, source.binding(ref.binding).ty) != null) return false;
                    const body = source.body(ref.binding) orelse return false;
                    if (body.is_function) {
                        if (!readers) return false;
                        const value = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                        var descriptor = false;
                        return self.readerArgument(value, &descriptor, remaining);
                    }
                    if (!try self.numericCallBody(ref, &.{}, null, .{ .unit = m.unit, .ty = n.ty }, remaining, active, used, readers)) return false;
                }
            },
            .scalar, .logical => {
                // Reusable word parameters discard literal selector evidence.
                // Keep lane-sensitive wrappers on the checked inline path,
                // just as leafBody does before this numeric fallback.
                if (n.tag == .scalar and @import("simd_intrinsics.zig").literalLanes(n.op)) return false;
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
            },
            .bind => {
                if (!try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
                if (readers) if (try self.planValue(m, n.b, remaining, depth + 1)) |value| try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = n.a, .value = value, .remaining = 0 });
            },
            .construct, .return_ => if (!try self.numericExpression(m, if (n.tag == .return_) n.a else n.b, remaining, active, used, readers, depth + 1)) return false,
            .closure, .primitive_function => {
                if (!readers) return false;
                const value = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                var descriptor = false;
                return self.readerArgument(value, &descriptor, remaining);
            },
            .apply => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1)) return false;
                const function = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return false;
                const argument = (try self.planValue(m, n.b, remaining, depth + 1)) orelse return false;
                if (!try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
                if (readers) if (try self.planValue(m, id, remaining, depth + 1)) |partial| if (partial.tag == .callable) {
                    var descriptor = false;
                    return self.readerArgument(partial, &descriptor, remaining);
                };
                if (!try self.plannedCallback(function, argument, remaining, active, used, depth + 1)) return false;
            },
            .pattern_bind => {
                if (!try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
                const binding_pattern = m.pattern(n.a);
                if (readers and binding_pattern.tag == .bind) {
                    if (try self.planValue(m, n.b, remaining, depth + 1)) |value| try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = binding_pattern.a, .value = value, .remaining = 0 });
                }
                if (!try self.numericExpression(m, n.c, remaining, active, used, readers, depth + 1)) return false;
            },
            .project => {
                var projected_receiver = false;
                const projection = m.projection(n.b);
                if (readers and m.node(n.a).tag == .reference) {
                    if (try self.planValue(m, n.a, remaining, depth + 1)) |value| {
                        if (value.projected_parameter_fields and value.nominal != null) {
                            const actual = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.a) }, 0);
                            const owner = try self.unit(actual.unit);
                            if (@import("storage_parameter_fields.zig").nominalRecord(owner, actual.ty, remaining)) |nominal| {
                                if (std.meta.eql(value.nominal.?, nominal.identity) and nominal.projection(m, n.b, remaining)) {
                                    const name = m.fieldSpelling(projection.field) orelse return false;
                                    const field = dataField(value, name) orelse return false;
                                    try self.mapValueTypes(.{ .unit = m.unit, .ty = n.ty }, field, 0);
                                    projected_receiver = true;
                                }
                            }
                        }
                    }
                }
                if (!projected_receiver and (projection.variants.len == 0 or @import("storage_parameter_fields.zig").namedRecordProjection(m, n.b))) {
                    const receiver = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.a) }, 0);
                    const owner = try self.unit(receiver.unit);
                    const record = owner.types.node(receiver.ty);
                    if (record.tag != .record) {
                        if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1)) return false;
                        const value = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return false;
                        // Direct named data fields already carry checked field
                        // evidence, just as expression/planValue projections do.
                        const spelling = m.fieldSpelling(projection.field) orelse return false;
                        if (dataField(value, spelling)) |field| {
                            try self.mapValueTypes(.{ .unit = m.unit, .ty = n.ty }, field, 0);
                            return true;
                        }
                        const before = self.type_arguments.items.len;
                        defer self.type_arguments.shrinkRetainingCapacity(before);
                        const selection = (try self.selectedGetter(m, id, value)) orelse return false;
                        const declaration = (try self.unit(selection.target.unit)).body(selection.target.binding) orelse return false;
                        const source = try self.unit(selection.target.unit);
                        if (source.bodyParameters(declaration).len > 1 or (source.node(declaration.root).tag == .primitive_function and source.primitive(declaration.root).arity == 2)) {
                            const function = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                            if (function.tag != .callable) return false;
                            if (!readers) {
                                for (function.fields) |capture| if (!plainShape(capture)) return false;
                                return true;
                            }
                            var descriptor = false;
                            return self.readerArgument(function, &descriptor, remaining);
                        }
                        return self.numericCallBody(selection.target, &.{selection.receiver}, &.{value}, .{ .unit = m.unit, .ty = n.ty }, remaining, active, used, readers);
                    }
                    var found = false;
                    const name = m.fieldSpelling(projection.field) orelse return false;
                    for (0..record.b) |index| {
                        const field = owner.types.recordField(record, index);
                        if (std.mem.eql(u8, name, owner.fieldSpelling(field.name) orelse return false)) found = true;
                    }
                    if (!found) return false;
                    // A checked direct projection reads only this field. The
                    // complete footprint proved that omitted fields cannot be
                    // observed; admitting their semantic types here would
                    // reintroduce unrelated callback/owner ABI requirements.
                    if (readers and m.node(n.a).tag == .reference) {
                        if (try self.planValue(m, n.a, remaining, depth + 1)) |value| {
                            if (value.projected_parameter_fields) {
                                // Reusable ABI admission already proved the
                                // actual owner schema before this body walk.
                                projected_receiver = true;
                            }
                        }
                    }
                }
                if (!projected_receiver and !try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1)) return false;
            },
            .match => {
                for (m.matchInputs(id)) |input| if (!try self.numericExpression(m, input, remaining, active, used, readers, depth + 1)) return false;
                for (m.matchArms(id)) |arm| {
                    if (!try self.numericExpression(m, arm.guard, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, arm.body, remaining, active, used, readers, depth + 1)) return false;
                }
            },
            .if_value, .if_stmt => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.c, remaining, active, used, readers, depth + 1)) return false;
            },
            .record_merge => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
            },
            .block, .suite, .product, .record => for (m.children(id)) |child| {
                if (!try self.numericExpression(m, child, remaining, active, used, readers, depth + 1)) return false;
            },
            .storage => {
                if (!readers) return false;
                const op: @import("../check/storage_ops.zig").Op = @fromBackingInt(@intCast(n.c));
                switch (op) {
                    .at, .link, .view, .load, .length, .read => {},
                    .push, .write => {
                        if (!self.planning_writer) return false;
                        const args = m.children(id);
                        const receiver = (try self.planValue(m, args[0], remaining, depth + 1)) orelse return false;
                        if (receiver.root == null) return false;
                        if (op == .push and (receiver.tag != .array or receiver.mode == .fixed)) return false;
                        if (op == .write and receiver.tag != .ref and receiver.tag != .link) return false;
                    },
                    else => return false,
                }
                for (m.children(id)) |child| if (!try self.numericExpression(m, child, remaining, active, used, readers, depth + 1)) return false;
            },
            .update => {
                if (!self.planning_writer) return false;
                const info = m.updateInfo(id);
                const selectors = m.updateSelectors(id);
                const path = m.updatePath(id);
                var receiver = (try self.planValue(m, info.root, remaining, depth + 1)) orelse return false;
                var row = false;
                for (0..@max(selectors.len, path.len)) |index| {
                    if (selectors.len != 0 and selectors[index].kind == .index) {
                        if (row or receiver.root == null or (receiver.tag != .array and receiver.tag != .view)) return false;
                        if (!try self.numericExpression(m, selectors[index].index, remaining, active, used, readers, depth + 1)) return false;
                        receiver = self.roots.items[receiver.root.?].element;
                        row = true;
                    } else {
                        const projection_id = if (selectors.len != 0) selectors[index].projection else path[index];
                        const projection = m.projection(projection_id);
                        const name = m.fieldSpelling(projection.field) orelse return false;
                        receiver = dataField(receiver, name) orelse return false;
                    }
                }
                if (!row and !try self.selectedInlineType(.{ .unit = m.unit, .ty = m.typeOf(info.root) }, remaining)) return false;
                const before = self.bindings.items.len;
                defer self.bindings.shrinkRetainingCapacity(before);
                try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = info.self_binding, .value = receiver, .remaining = 0 });
                if (!try self.numericExpression(m, info.value, remaining, active, used, readers, depth + 1)) return false;
            },
            .array_op => {
                if (!readers) return false;
                const op = m.arrayOperation(id);
                const arguments = m.children(id);
                switch (op) {
                    .length, .get, .identity, .cursor, .cursor_has, .cursor_value, .cursor_advance => {},
                    .fill, .generate => {
                        if (!self.planning_writer or arguments.len != 2) return false;
                        const actual = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
                        const owner = try self.unit(actual.unit);
                        const element = @import("storage_collections.zig").element(owner, actual.ty) orelse return false;
                        if (!try self.selectedInlineType(.{ .unit = actual.unit, .ty = element, .environment = actual.environment }, remaining)) return false;
                    },
                    else => return false,
                }
                for (arguments) |argument| if (!try self.numericExpression(m, argument, remaining, active, used, readers, depth + 1)) return false;
                if (op == .generate) {
                    const function = (try self.planValue(m, arguments[1], remaining, depth + 1)) orelse return false;
                    // Runtime indices carry their checked type, never a literal.
                    const index: Value = .{ .word = .{ .id = 0 }, .type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = T.u32_type }, .arguments = &.{} }) };
                    if (!try self.plannedCallback(function, index, remaining, active, used, depth + 1)) return false;
                }
            },
            .loop => {
                const loop = m.loopInfo(id);
                if (loop.kind != .range and !readers) return false;
                if (!try self.numericExpression(m, loop.first, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, loop.end, remaining, active, used, readers, depth + 1)) return false;
                const before = self.bindings.items.len;
                defer self.bindings.shrinkRetainingCapacity(before);
                if (self.planning_owner_graph and loop.kind == .array and loop.pattern != 0) {
                    const pattern_ = m.pattern(loop.pattern);
                    if (pattern_.tag != .bind) return false;
                    const receiver = (try self.planValue(m, loop.first, remaining, depth + 1)) orelse return false;
                    var item = (try self.planGraphRead(m, id, receiver)) orelse return false;
                    item.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = pattern_.ty }, .arguments = try self.captureTypes() });
                    try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = pattern_.a, .value = item, .remaining = 0 });
                }
                if (!try self.numericExpression(m, loop.body, remaining, active, used, readers, depth + 1)) return false;
            },
            .call => {
                const call = m.call(id);
                var target = call.target;
                if (target.unit == 0) target.unit = m.unit;
                for (call.arguments) |argument| if (!try self.numericExpression(m, argument, remaining, active, used, readers, depth + 1)) return false;
                const declaration = (try self.unit(target.unit)).body(target.binding) orelse return false;
                if (call.arguments.len < (try self.unit(target.unit)).bodyParameters(declaration).len) {
                    const value = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                    if (value.tag != .callable) return false;
                    if (readers) {
                        var descriptor = false;
                        return self.readerArgument(value, &descriptor, remaining);
                    }
                    for (value.fields) |field| if (!plainShape(field)) return false;
                    return true;
                }
                const inputs = try self.arena.allocator().alloc(TypeRef, call.arguments.len);
                const values = try self.arena.allocator().alloc(Value, call.arguments.len);
                var all_known = true;
                for (inputs, values, call.arguments) |*input, *value, argument| {
                    input.* = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(argument) }, 0);
                    if (try self.planValue(m, argument, remaining, depth + 1)) |known| value.* = known else all_known = false;
                }
                if (!try self.numericCallBody(target, inputs, if (all_known) values else null, .{ .unit = m.unit, .ty = n.ty }, remaining, active, used, readers)) return false;
                if (try self.planValue(m, id, remaining, depth + 1)) |value| if (value.tag == .callable) {
                    if (readers) {
                        var descriptor = false;
                        return self.readerArgument(value, &descriptor, remaining);
                    }
                    for (value.fields) |field| if (!plainShape(field)) return false;
                    return true;
                };
            },
            .associated => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
                const first = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.a) }, 0);
                const second = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.b) }, 0);
                const a = (try self.unit(first.unit)).types.node(first.ty);
                const b = (try self.unit(second.unit)).types.node(second.ty);
                // Equal concrete primitive receivers select the same catalog
                // family; user nominal overloads remain on the existing path.
                if (a.tag != b.tag or (a.tag != .u32 and a.tag != .f32 and a.tag != .boolean)) return false;
                const identity = T.receiverIdentity(a) orelse return false;
                const target = (try self.dispatchTarget(m, identity, n.c, .none)) orelse return false;
                const actual_output = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
                if ((try self.unit(actual_output.unit)).types.node(actual_output.ty).tag == .function) {
                    const partial = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                    return partial.tag == .callable;
                }
                if (!try self.numericCallBody(target, &.{ first, second }, null, .{ .unit = m.unit, .ty = n.ty }, remaining, active, used, readers)) return false;
            },
            else => return false,
        }
        if (readers) {
            if (n.tag == .reference or n.tag == .project or n.tag == .call) if (try self.planValue(m, id, remaining, depth + 1)) |value| if (value.tag == .callable) {
                var descriptor = false;
                return self.readerArgument(value, &descriptor, remaining);
            };
            const actual = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
            return self.selectedDataType(actual, true, remaining, 0);
        }
        return self.selectedInlineType(.{ .unit = m.unit, .ty = n.ty }, remaining);
    }
    fn noteCalleeContext(self: *Generator, entry: call_plan.Entry) void {
        if (entry.context_sensitive) {
            self.context_sensitive = true;
            self.emission_work.scoped_context_sensitive_calls +|= 1;
        } else self.emission_work.scoped_context_free_calls +|= 1;
    }
    fn completeCall(self: *Generator, cache: *call_plan.Cache, index: usize, child_sensitive: bool, closed_frontier: bool) Error!void {
        var sensitive = true;
        if (closed_frontier) sensitive = child_sensitive;
        try cache.complete(index, sensitive);
        if (sensitive) {
            self.emission_work.scoped_context_sensitive_definitions +|= 1;
        } else self.emission_work.scoped_context_free_definitions +|= 1;
    }
    fn closedScalarBody(self: *Generator, m: *const core.Module, target: core.BindingId) Error!bool {
        const nodes_before = self.scalar_admission.nodes;
        const hits_before = self.scalar_admission.hits;
        defer {
            self.emission_work.scoped_scalar_admission_nodes +|= self.scalar_admission.nodes - nodes_before;
            self.emission_work.scoped_scalar_admission_hits +|= self.scalar_admission.hits - hits_before;
        }
        // An optional probe cannot consume the existing fallback's allowance.
        var remaining: usize = 100_000;
        return self.scalar_admission.admit(m, target, &remaining);
    }
    /// Scalar leaves use a normal Wasm call, not repeated source expansion.
    /// The initial ABI transports F32 as exact i32 bits, matching Value.word.
    fn inlineWords(value: Value) Error!usize {
        if (value.tag == .scalar) return 1;
        var count: usize = @intFromBool(value.variant_tags.len != 0);
        for (value.fields) |field| count = std.math.add(usize, count, try inlineWords(field)) catch return error.Declined;
        return count;
    }
    fn inlineReturnRegisters(shape_: Value) Error!usize {
        if (shape_.tag != .aggregate) return 0;
        const words = try inlineWords(shape_);
        if (words == 0 or words > 4) return 0;
        if (!plainInlineValue(shape_) or !stableDescriptorShape(shape_)) return 0;
        return words;
    }
    fn inlineReturnLeaves(value: Value, words: *[4]Local, next: *usize) Error!void {
        if (value.tag == .scalar) {
            if (next.* == words.len) return error.Declined;
            words[next.*] = value.word;
            next.* += 1;
            return;
        }
        if (value.tag != .aggregate or value.variant_tags.len != 0) return error.Declined;
        for (value.fields) |field| try inlineReturnLeaves(field, words, next);
    }
    fn publishInlineReturn(self: *Generator, output: Value, count: usize) Error!void {
        // A trapping body never returns, so its ABI-zero carrier has no shape.
        if (output.terminated) return self.c.value(0);
        var words: [4]Local = undefined;
        var next: usize = 0;
        try inlineReturnLeaves(output, &words, &next);
        if (next != count) return error.Declined;
        // invokeBody already finished nested calls, cleanup and outlining.
        // Publication contains only local/global operations, then word zero.
        for (1..count) |index| {
            try self.c.value(words[index]);
            try self.c.op(.global_set, self.runtime.inline_returns[index - 1]);
        }
        try self.c.value(words[0]);
    }
    fn inlineReturnValue(self: *Generator, template: Value, words: []const Local, next: *usize) Error!Value {
        var value = template;
        value.literal = null;
        value.constant_bits = null;
        if (value.tag == .scalar) {
            value.word = words[next.*];
            next.* += 1;
            return value;
        }
        value.word = .{ .id = 0 };
        const fields = initializeFields(&value, try self.arena.allocator().alloc(Value, template.fields.len));
        for (fields, template.fields) |*field, original| field.* = try self.inlineReturnValue(original, words, next);
        return value;
    }
    fn inlineParameter(self: *Generator, original: Value, next: *u32) Error!Value {
        var value = original;
        value.literal = null;
        value.constant_bits = null;
        if (value.tag == .scalar or value.variant_tags.len != 0) {
            value.word = .{ .id = next.* };
            next.* += 1;
        } else value.word = .{ .id = 0 };
        value.variant_index = null;
        value.variant_possible = &.{};
        const fields = initializeFields(&value, try self.arena.allocator().alloc(Value, original.fields.len));
        for (fields, original.fields) |*field, input| field.* = try self.inlineParameter(input, next);
        return value;
    }

    /// Inline fields travel as ordinary word parameters. Small plain results
    /// return through an instance-private word bank, drained immediately into
    /// locals; other aggregates use a caller-owned slot and immediate rewind.
    fn readerWords(value: Value) usize {
        return readerWordsPointer(&value);
    }
    fn readerWordsPointer(value: *const Value) usize {
        if (value.tag == .aggregate or value.tag == .callable) {
            var count: usize = @intFromBool(value.variant_tags.len != 0);
            for (value.fields) |*field| count += readerWordsPointer(field);
            return count;
        }
        return switch (value.tag) {
            .scalar => 1,
            .array => 4,
            .ref, .link => 5,
            .view => 6,
            else => unreachable,
        };
    }
    // Failed admission alone requests a diagnostic path. The optional walk
    // never changes evidence, work limits, cache keys or the admission result.
    fn traceDescriptorBarrier(self: *Generator, m: ?*const core.Module, id: core.Id, value: Value, stage: []const u8, stable: bool) void {
        const profile = @import("../phase_profile.zig");
        if (profile.currentTrace() == null) return;
        var location: evaluation.SourceLocation = self.specialization_origin orelse .{ .unit = self.entry_unit, .span = .{ .start = 0, .end = 0 } };
        if (m) |owner| location = .{ .unit = owner.unit, .span = owner.span(id) };
        profile.detail(stage, location.unit, location.span.start, location.span.end, @backingInt(value.tag));
        var current = value;
        for (0..128) |_| {
            if (current.type_evidence) |known| profile.detail("descriptor.type", known.root.unit, 0, 0, known.root.ty);
            if (current.tag == .callable) {
                profile.detail("descriptor.callback", location.unit, location.span.start, location.span.end, 0);
                return;
            }
            if (current.tag != .scalar and current.tag != .aggregate) {
                profile.detail("descriptor.nested-descriptor", location.unit, location.span.start, location.span.end, @backingInt(current.tag));
                return;
            }
            if (stable and current.variant_tags.len != 0) {
                profile.detail("descriptor.variant", location.unit, location.span.start, location.span.end, current.variant_tags.len);
                return;
            }
            var found = false;
            for (current.fields, 0..) |field, index| {
                var admitted = plainShape(field);
                if (stable) admitted = stableDescriptorShape(field);
                if (admitted) continue;
                profile.detail("descriptor.field-index", location.unit, location.span.start, location.span.end, index);
                current = field;
                found = true;
                break;
            }
            if (!found) return;
        }
    }
    fn readerArgument(self: *Generator, value: Value, descriptor: *bool, remaining: *usize) bool {
        if (remaining.* == 0) {
            self.traceDescriptorBarrier(null, 0, value, "descriptor.reader.work-limit", false);
            return false;
        }
        if (value.host != null) {
            self.traceDescriptorBarrier(null, 0, value, "descriptor.reader.host-callback", false);
            return false;
        }

        remaining.* -= 1;
        switch (value.tag) {
            .scalar => return true,
            .aggregate, .callable => {
                if (value.tag == .callable) {
                    if (value.callable == null) {
                        self.traceDescriptorBarrier(null, 0, value, "descriptor.reader.callback-missing", false);
                        return false;
                    }
                    descriptor.* = true;
                }
                for (value.fields) |field| if (!self.readerArgument(field, descriptor, remaining)) return false;
                return true;
            },
            .array, .ref, .link, .view => {
                const owner_root = value.root orelse {
                    self.traceDescriptorBarrier(null, 0, value, "descriptor.reader.owner-missing", false);
                    return false;
                };
                if (self.planning_owner_graph) {
                    if (owner_root >= self.roots.items.len) return false;
                    for (value.other_roots) |other| if (other >= self.roots.items.len) return false;
                    descriptor.* = true;
                    return true;
                }
                if (!plainShape(self.roots.items[owner_root].element)) {
                    self.traceDescriptorBarrier(null, 0, self.roots.items[owner_root].element, "descriptor.reader.plain-row", false);
                    return false;
                }
                for (value.other_roots) |other| if (!plainShape(self.roots.items[other].element)) {
                    self.traceDescriptorBarrier(null, 0, self.roots.items[other].element, "descriptor.reader.alternative-row", false);
                    return false;
                };
                descriptor.* = true;
                return true;
            },
        }
    }
    fn readerLayoutEvidence(self: *Generator, m: *const core.Module, id: core.Id, value: Value, evidence: *std.ArrayList(u32), keys: *selected_types.Builder) Error!void {
        return self.callLayoutEvidence(m, id, value, evidence, keys, true);
    }
    fn inlineLayoutEvidence(self: *Generator, m: *const core.Module, id: core.Id, value: Value, evidence: *std.ArrayList(u32), keys: *selected_types.Builder) Error!void {
        std.debug.assert(plainInlineValue(value));
        return self.callLayoutEvidence(m, id, value, evidence, keys, false);
    }
    fn callLayoutEvidence(self: *Generator, m: *const core.Module, id: core.Id, value: Value, evidence: *std.ArrayList(u32), keys: *selected_types.Builder, refinements: bool) Error!void {
        const remaining = keys.remaining;
        if (remaining.* == 0 or value.name.len >= remaining.*) return self.fail(m, id, .storage_unsupported, "The static callback capture schema exceeds its supported bound");
        remaining.* -= 1;
        var selected_variant: u32 = std.math.maxInt(u32);
        if (refinements) if (value.variant_index) |selected| {
            selected_variant = @intCast(selected);
        };
        try evidence.appendSlice(self.allocator, &.{ @backingInt(value.tag), @backingInt(value.mode), @intFromBool(value.sequence), @intFromBool(value.floating), @intCast(value.fields.len), @intCast(value.variant_tags.len), @intCast(value.name.len), selected_variant });
        for (value.name) |byte| {
            try evidence.append(self.allocator, byte);
            remaining.* -= 1;
        }
        if (value.nominal) |identity| try evidence.appendSlice(self.allocator, &.{ 1, identity.unit, identity.decl }) else try evidence.append(self.allocator, 0);
        if (value.type_evidence) |known| {
            try evidence.append(self.allocator, 1);
            try self.selectedType(m, id, .{ .unit = known.root.unit, .ty = known.root.ty, .environment = known.arguments }, evidence, keys, 0);
        } else try evidence.append(self.allocator, 0);
        if (value.callable) |callable| {
            try evidence.appendSlice(self.allocator, &.{ callable.unit, callable.target, callable.node });
            const owner = try self.unit(callable.unit);
            for (callable.captures) |binding| try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.binding(binding).ty, .environment = callable.types }, evidence, keys, 0);
        }
        try evidence.appendSlice(self.allocator, value.variant_tags);
        var possible_count: usize = 0;
        if (refinements) possible_count = value.variant_possible.len;
        try evidence.append(self.allocator, @intCast(possible_count));
        for (value.variant_possible[0..possible_count]) |possible| try evidence.append(self.allocator, @intFromBool(possible));
        for (value.fields) |field| try self.callLayoutEvidence(m, id, field, evidence, keys, refinements);
    }
    fn readerReads(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!void {
        if (value.tag == .aggregate or value.tag == .callable) {
            for (value.fields) |field| try self.readerReads(m, id, field);
        } else if (value.tag != .scalar) {
            try self.registerShapeRead(value);
            try self.writerEvent(m, id, value, .read);
        }
    }
    fn readerValues(self: *Generator, value: Value) Error!void {
        var ordinal: usize = 0;
        try self.readerValuesMasked(value, &.{}, &ordinal);
    }
    fn readerInputWord(self: *Generator, word: Local, used: []const bool, ordinal: *usize) Error!void {
        if (used.len == 0 or used[ordinal.*]) {
            try self.c.value(word);
        } else self.emission_work.scoped_direct_argument_words_avoided +|= 1;
        ordinal.* += 1;
    }
    fn readerValuesMasked(self: *Generator, value: Value, used: []const bool, ordinal: *usize) Error!void {
        if (value.tag == .aggregate or value.tag == .callable) {
            if (value.variant_tags.len != 0) try self.readerInputWord(value.word, used, ordinal);
            for (value.fields) |field| try self.readerValuesMasked(field, used, ordinal);
            return;
        }
        try self.readerInputWord(value.word, used, ordinal);
        if (value.tag == .scalar) return;
        try self.readerInputWord(value.token, used, ordinal);
        try self.readerInputWord(value.epoch_low, used, ordinal);
        try self.readerInputWord(value.epoch_high, used, ordinal);
        if (value.tag != .array) try self.readerInputWord(value.index, used, ordinal);
        if (value.tag == .view) try self.readerInputWord(value.length, used, ordinal);
    }
    fn readerWordLocals(self: *Generator, value: Value, output: *std.ArrayList(Local)) Error!void {
        if (value.tag == .aggregate or value.tag == .callable) {
            if (value.variant_tags.len != 0) try output.append(self.allocator, value.word);
            for (value.fields) |field| try self.readerWordLocals(field, output);
            return;
        }
        try output.append(self.allocator, value.word);
        if (value.tag == .scalar) return;
        try output.appendSlice(self.allocator, &.{ value.token, value.epoch_low, value.epoch_high });
        if (value.tag != .array) try output.append(self.allocator, value.index);
        if (value.tag == .view) try output.append(self.allocator, value.length);
    }
    fn resultAliasCandidates(self: *Generator, value: Value, output: *std.ArrayList(Local)) Error!void {
        if (!shareableNode(value)) {
            try output.appendNTimes(self.allocator, .{ .id = @import("storage_result_alias.zig").absent }, readerWords(value));
            return;
        }
        if (value.tag == .aggregate or value.tag == .callable) {
            for (value.fields) |field| try self.resultAliasCandidates(field, output);
        } else try self.readerWordLocals(value, output);
    }
    fn readerPlainShape(self: *Generator, source: Value) Error!Value {
        var value = source;
        value.literal = null;
        value.constant_bits = null;
        value.variant_index = null;
        value.variant_possible = &.{};
        const fields = initializeFields(&value, try self.arena.allocator().alloc(Value, source.fields.len));
        for (fields, source.fields) |*field, original| field.* = try self.readerPlainShape(original);
        return value;
    }
    // The graph owns metadata and owner ordinals. Rebind only runtime words,
    // in exactly readerValues order; writerInput performs the existing remap.
    fn inputParameterWord(next: *u32, aliases: []const u32, first: u32) Local {
        const ordinal = next.* - first;
        next.* += 1;
        if (aliases.len == 0) return .{ .id = first + ordinal };
        return .{ .id = first + aliases[ordinal] };
    }
    fn readerWordParameter(self: *Generator, original: Value, next: *u32, aliases: []const u32, first: u32) Error!Value {
        var value = original;
        if (value.tag == .aggregate or value.tag == .callable) {
            if (value.variant_tags.len != 0) {
                value.word = inputParameterWord(next, aliases, first);
            } else if (value.tag == .aggregate) value.word = .{ .id = 0 } else value.word = (try self.unitValue()).word;
            const fields = initializeFields(&value, try self.arena.allocator().alloc(Value, original.fields.len));
            for (fields, original.fields) |*field, source| field.* = try self.readerWordParameter(source, next, aliases, first);
            return value;
        }
        value.word = inputParameterWord(next, aliases, first);
        if (value.tag == .scalar) return value;
        value.token = inputParameterWord(next, aliases, first);
        value.epoch_low = inputParameterWord(next, aliases, first);
        value.epoch_high = inputParameterWord(next, aliases, first);
        if (value.tag != .array) {
            value.index = inputParameterWord(next, aliases, first);
        }
        if (value.tag == .view) {
            value.length = inputParameterWord(next, aliases, first);
        }
        return value;
    }
    // Runtime descriptors are rebound to independent child roots; owner identity
    // and epochs remain runtime parameters rather than specialization keys.
    fn readerParameter(self: *Generator, child: *Generator, input: *Value, argument: Value, next: *u32) Error!void {
        input.* = argument;
        input.literal = null;
        input.constant_bits = null;
        if (argument.tag == .aggregate or argument.tag == .callable) {
            const fields = initializeFields(input, try child.arena.allocator().alloc(Value, argument.fields.len));
            if (argument.variant_tags.len != 0) {
                input.word = .{ .id = next.* };
                next.* += 1;
            } else if (argument.tag == .aggregate) {
                input.word = .{ .id = 0 };
            } else input.word = (try child.constant(0)).word;
            for (fields, argument.fields) |*field, source| try self.readerParameter(child, field, source, next);
            return;
        }
        input.word = .{ .id = next.* };
        input.literal = null;
        input.constant_bits = null;
        next.* += 1;
        input.depth = 0;
        if (argument.tag == .scalar) return;
        input.token = .{ .id = next.* };
        input.epoch_low = .{ .id = next.* + 1 };
        input.epoch_high = .{ .id = next.* + 2 };
        next.* += 3;
        if (argument.tag != .array) {
            input.index = .{ .id = next.* };
            next.* += 1;
        }
        if (argument.tag == .view) {
            input.length = .{ .id = next.* };
            next.* += 1;
        }
        // Only reads and aliases of existing inputs are admitted. A joined input's
        // selected runtime descriptor keeps its actual owner and epoch;
        // this local root supplies the already-proved plain row layout.
        input.root = child.roots.items.len;
        input.other_roots = &.{};
        try child.roots.append(self.allocator, .{
            .word = input.word,
            .token = input.token,
            .epoch_low = input.epoch_low,
            .epoch_high = input.epoch_high,
            .stack = self.fixed_region,
            .depth = 0,
            .element = try child.readerPlainShape(self.roots.items[argument.root.?].element),
            .element_initialized = self.roots.items[argument.root.?].element_initialized,
            .dedicated = false,
        });
    }
    const EnvironmentKey = struct { address: usize, length: usize };
    const EnvironmentCopies = std.AutoHashMapUnmanaged(EnvironmentKey, []const TypeArgument);
    fn retainEnvironment(self: *Generator, source: []const TypeArgument, copies: *EnvironmentCopies, depth: usize) Error![]const TypeArgument {
        return self.retainEnvironmentIn(self.arena.allocator(), source, copies, depth);
    }
    fn retainEnvironmentIn(self: *Generator, arena: std.mem.Allocator, source: []const TypeArgument, copies: *EnvironmentCopies, depth: usize) Error![]const TypeArgument {
        if (depth > 128) return error.Declined;
        if (source.len == 0) return &.{};
        const key: EnvironmentKey = .{ .address = @intFromPtr(source.ptr), .length = source.len };
        if (copies.get(key)) |known| return known;
        const result = try arena.dupe(TypeArgument, source);
        try copies.put(self.allocator, key, result);
        for (result) |*item| if (item.environment) |environment| {
            item.environment = try self.retainEnvironmentIn(arena, environment, copies, depth + 1);
        };
        return result;
    }
    fn retainReaderResult(self: *Generator, source: Value, inputs: usize, copies: *EnvironmentCopies, reachable: bool, depth: usize) Error!Value {
        if (depth > 128 or source.host != null or source.tag == .callable) return error.Declined;
        if (source.tag != .scalar and source.tag != .aggregate) {
            if (source.root) |input| {
                if (input >= inputs) return error.Declined;
            } else if (reachable) return error.Declined;
            for (source.other_roots) |other| if (other >= inputs) return error.Declined;
        }
        // Root indices are parameter-descriptor ordinals here, not retained
        // caller identities. Every hit substitutes the current argument roots.
        var result = source;
        result.other_roots = try self.arena.allocator().dupe(usize, source.other_roots);
        result.variant_tags = try self.arena.allocator().dupe(u32, source.variant_tags);
        result.variant_possible = try self.arena.allocator().dupe(bool, source.variant_possible);
        const fields = initializeFields(&result, try self.arena.allocator().alloc(Value, source.fields.len));
        for (fields, source.fields, 0..) |*field, original, index| {
            const live = reachable and (source.variant_tags.len == 0 or possibleVariant(source, index));
            field.* = try self.retainReaderResult(original, inputs, copies, live, depth + 1);
        }
        if (source.type_evidence) |known| {
            var root_type = known.root;
            if (root_type.environment) |environment| root_type.environment = try self.retainEnvironment(environment, copies, 0);
            result.type_evidence = try boxTypeEvidenceIn(self.arena.allocator(), .{ .root = root_type, .arguments = try self.retainEnvironment(known.arguments, copies, 0) });
        }
        return result;
    }
    fn readerDescriptors(self: *Generator, value: Value, output: *std.ArrayList(Value)) Error!void {
        if (value.tag == .aggregate or value.tag == .callable) {
            for (value.fields) |field| try self.readerDescriptors(field, output);
        } else if (value.tag != .scalar) try output.append(self.allocator, value);
    }
    fn readerResult(self: *Generator, template: Value, descriptors: []const Value) Error!Value {
        var result = template;
        const fields = initializeFields(&result, try self.arena.allocator().alloc(Value, template.fields.len));
        for (fields, template.fields) |*field, original| field.* = try self.readerResult(original, descriptors);
        if (template.tag == .scalar or template.tag == .aggregate) return result;
        result.root = null;
        result.other_roots = &.{};
        result.depth = 0;
        if (template.root) |input| try self.unionRoots(&result, descriptors[input]);
        for (template.other_roots) |input| try self.unionRoots(&result, descriptors[input]);
        for (self.roots.items, 0..) |owner, index| {
            if (hasRoot(result, index)) result.depth = @max(result.depth, owner.depth);
        }
        return result;
    }
    // ABI slots are temporary U32 buffers, never language rows containing
    // owning descriptors. Every descriptor word is copied before slot rewind.
    fn storeReaderResult(self: *Generator, address: Local, offset: u32, value: Value) Error!void {
        return self.storeReaderResultMasked(address, offset, value, null);
    }
    fn storeReaderWord(self: *Generator, address: Local, offset: u32, value: Local, used: ?[]const bool) Error!void {
        if (used) |mask| {
            std.debug.assert(offset % 4 == 0 and offset / 4 < mask.len);
            if (!mask[offset / 4]) {
                self.emission_work.scoped_packed_argument_words_avoided +|= 1;
                return;
            }
        }
        try self.c.store(address, offset, value);
    }
    fn storeReaderResultMasked(self: *Generator, address: Local, offset: u32, value: Value, used: ?[]const bool) Error!void {
        var at = offset;
        if (value.tag == .aggregate or value.tag == .callable) {
            if (value.variant_tags.len != 0) {
                try self.storeReaderWord(address, at, value.word, used);
                at += 4;
            }
            for (value.fields) |field| {
                try self.storeReaderResultMasked(address, at, field, used);
                at += @intCast(readerWords(field) * 4);
            }
            return;
        }
        try self.storeReaderWord(address, at, value.word, used);
        if (value.tag == .scalar) return;
        try self.storeReaderWord(address, at + 4, value.token, used);
        try self.storeReaderWord(address, at + 8, value.epoch_low, used);
        try self.storeReaderWord(address, at + 12, value.epoch_high, used);
        if (value.tag != .array) try self.storeReaderWord(address, at + 16, value.index, used);
        if (value.tag == .view) try self.storeReaderWord(address, at + 20, value.length, used);
    }
    fn loadReaderResult(self: *Generator, address: Local, offset: u32, template: Value) Error!Value {
        var ordinal: usize = 0;
        return self.loadReaderResultAliased(address, offset, template, &.{}, &.{}, &ordinal);
    }
    fn loadReaderWordAliased(self: *Generator, address: Local, offset: u32, aliases: []const u32, arguments: []const Local, ordinal: *usize) Error!Local {
        const index = ordinal.*;
        ordinal.* += 1;
        if (aliases.len != 0) {
            std.debug.assert(index < aliases.len);
            const alias = aliases[index];
            if (alias != @import("storage_result_alias.zig").absent) {
                std.debug.assert(alias < arguments.len);
                self.emission_work.scoped_result_load_words_avoided +|= 1;
                return arguments[alias];
            }
        }
        const result = try self.c.temp();
        try self.c.set(result, .{ .load, address, offset });
        return result;
    }
    fn loadReaderResultAliased(self: *Generator, address: Local, offset: u32, template: Value, aliases: []const u32, arguments: []const Local, ordinal: *usize) Error!Value {
        var result = template;
        var at = offset;
        result.word = .{ .id = 0 };
        if (result.tag == .aggregate or result.tag == .callable) {
            if (result.variant_tags.len != 0) {
                result.word = try self.loadReaderWordAliased(address, at, aliases, arguments, ordinal);
                at += 4;
            } else if (result.tag == .callable) result.word = (try self.unitValue()).word;
            const fields = initializeFields(&result, try self.arena.allocator().alloc(Value, template.fields.len));
            for (fields, template.fields) |*field, original| {
                field.* = try self.loadReaderResultAliased(address, at, original, aliases, arguments, ordinal);
                at += @intCast(readerWords(original) * 4);
            }
            return result;
        }
        result.word = try self.loadReaderWordAliased(address, at, aliases, arguments, ordinal);
        if (result.tag == .scalar) return result;
        result.token = try self.loadReaderWordAliased(address, at + 4, aliases, arguments, ordinal);
        result.epoch_low = try self.loadReaderWordAliased(address, at + 8, aliases, arguments, ordinal);
        result.epoch_high = try self.loadReaderWordAliased(address, at + 12, aliases, arguments, ordinal);
        if (result.tag != .array) result.index = try self.loadReaderWordAliased(address, at + 16, aliases, arguments, ordinal);
        if (result.tag == .view) result.length = try self.loadReaderWordAliased(address, at + 20, aliases, arguments, ordinal);
        return result;
    }
    // Only key encoding can decline here. Source/body admission and child
    // emission remain outside this boundary; no cache entry exists yet.
    fn optionalReaderEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, arguments: []const Value, evidence: *std.ArrayList(u32)) Error!bool {
        const diagnostic_before = self.diagnostic;
        self.readerCallEvidence(m, body, arguments, evidence) catch |err| {
            if (err == error.OutOfMemory) return err;
            self.diagnostic = diagnostic_before;
            self.emission_work.scoped_outline_key_declines +|= 1;
            return false;
        };
        return true;
    }
    fn readerCallEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, arguments: []const Value, evidence: *std.ArrayList(u32)) Error!void {
        const result_type = m.typeOf(body.root);
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 1, result_type });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (arguments) |argument| try self.readerLayoutEvidence(m, body.root, argument, evidence, &type_key);
        for (m.bodyParameters(body)) |parameter| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, evidence, &type_key, 0);
        try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = result_type }, evidence, &type_key, 0);
        try self.finishSelectedTypes(m, body.root, evidence, &type_key);
    }
    // A shared descriptor definition must not key environment-dependent forms
    // through selectedTypeNode's deliberately opaque source-ID fallback.
    fn descriptorType(self: *Generator, input: TypeRef, remaining: *usize, depth: usize) Error!void {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        if (remaining.* == 0 or depth > 128) return error.Declined;
        remaining.* -= 1;
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32, .never => {},
            .array, .list, .cursor, .resolver => try self.descriptorType(.{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, remaining, depth + 1),
            .function => {
                try self.descriptorType(.{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, remaining, depth + 1);
                try self.descriptorType(.{ .unit = actual.unit, .ty = node.b, .environment = actual.environment }, remaining, depth + 1);
            },
            .usage => {
                try self.descriptorType(.{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, remaining, depth + 1);
                if (node.c != 0) try self.descriptorType(.{ .unit = actual.unit, .ty = node.c, .environment = actual.environment }, remaining, depth + 1);
            },
            .product, .record, .nominal => {
                const count = if (node.tag == .nominal) owner.types.nominalArguments(node).len else node.b;
                if (count > remaining.*) return error.Declined;
                for (0..count) |index| {
                    const child = switch (node.tag) {
                        .record => owner.types.recordField(node, index).ty,
                        .nominal => owner.types.nominalArguments(node)[index],
                        else => owner.types.list(.{ .start = node.a, .len = node.b })[index],
                    };
                    try self.descriptorType(.{ .unit = actual.unit, .ty = child, .environment = actual.environment }, remaining, depth + 1);
                }
            },
            else => return error.Declined,
        }
    }
    fn descriptorTypeEvidence(self: *Generator, m: *const core.Module, id: core.Id, input: TypeRef, evidence: *std.ArrayList(u32), keys: *selected_types.Builder, remaining: *usize) Error!void {
        try self.descriptorType(input, remaining, 0);
        try self.selectedType(m, id, input, evidence, keys, 0);
    }
    fn descriptorBodyEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, environment: ?[]const TypeArgument, evidence: *std.ArrayList(u32), keys: *selected_types.Builder, remaining: *usize) Error!void {
        const binding = m.binding(body.binding);
        if (body.scheme.generative.len != 0 or binding.scheme.generative.len != 0) return error.Declined;
        for ([_]T.List{ body.scheme.variables, binding.scheme.variables, binding.public_variables }) |variables| {
            try evidence.append(self.allocator, variables.len);
            for (m.types.list(variables)) |variable| try self.descriptorTypeEvidence(m, body.root, .{ .unit = m.unit, .ty = variable, .environment = environment }, evidence, keys, remaining);
        }
        // Row identities retain source authority; they never establish purity.
        for ([_]T.List{ body.scheme.row_variables, binding.scheme.row_variables, binding.public_rows }) |rows| {
            if (rows.len > remaining.*) return error.Declined;
            remaining.* -= rows.len;
            try evidence.append(self.allocator, rows.len);
            try evidence.appendSlice(self.allocator, m.types.list(rows));
        }
    }
    fn descriptorValueEvidence(self: *Generator, m: *const core.Module, id: core.Id, value: Value, evidence: *std.ArrayList(u32), keys: *selected_types.Builder, remaining: *usize, depth: usize) Error!void {
        if (remaining.* == 0 or depth > 128) return error.Declined;
        remaining.* -= 1;
        if (value.type_evidence) |known| try self.descriptorTypeEvidence(m, id, .{ .unit = known.root.unit, .ty = known.root.ty, .environment = known.root.environment orelse known.arguments }, evidence, keys, remaining);
        if (value.callable) |callable| {
            const owner = try self.unit(callable.unit);
            if (callable.target == 0) {
                if (callable.node == 0 or callable.goals.len != 0) {
                    self.traceDescriptorBarrier(m, id, value, "descriptor.shared.callback-evidence", false);
                    return error.Declined;
                }
                if (callable.kind(owner) == .closure and !concreteClosureQualifier(owner, owner.closure(callable.node))) {
                    self.traceDescriptorBarrier(m, id, value, "descriptor.shared.callback-qualifier", false);
                    return error.Declined;
                }
            }
            const signature = callable.signature(owner);
            try self.descriptorTypeEvidence(m, id, .{ .unit = owner.unit, .ty = signature, .environment = callable.types }, evidence, keys, remaining);
            if (callable.target != 0) try self.descriptorBodyEvidence(owner, owner.body(callable.target) orelse return error.Declined, callable.types, evidence, keys, remaining);
        }
        if (value.tag != .scalar and value.tag != .aggregate and value.tag != .callable) {
            const root_id = value.root orelse return error.Declined;
            const root_ = self.roots.items[root_id];
            try evidence.append(self.allocator, @intCast(value.other_roots.len));
            try evidence.appendSlice(self.allocator, &.{ @intFromBool(root_.element_initialized), @intFromBool(root_.frozen) });
            try self.descriptorValueEvidence(m, id, root_.element, evidence, keys, remaining, depth + 1);
            try self.readerLayoutEvidence(m, id, root_.element, evidence, keys);
            for (value.other_roots) |other| {
                const alternative = self.roots.items[other];
                try evidence.appendSlice(self.allocator, &.{ @intFromBool(alternative.element_initialized), @intFromBool(alternative.frozen) });
                try self.descriptorValueEvidence(m, id, alternative.element, evidence, keys, remaining, depth + 1);
                try self.readerLayoutEvidence(m, id, alternative.element, evidence, keys);
            }
        }
        for (value.fields) |field| try self.descriptorValueEvidence(m, id, field, evidence, keys, remaining, depth + 1);
    }
    fn concreteClosureQualifier(owner: *const core.Module, closure: core.ClosureInfo) bool {
        if (closure.qualifier == 0) return true;
        const binding = owner.binding(closure.qualifier);
        const scheme = binding.scheme;
        return scheme.variables.len == 0 and scheme.row_variables.len == 0 and scheme.obligations.len == 0 and scheme.generative.len == 0 and binding.public_variables.len == 0 and binding.public_rows.len == 0;
    }
    fn sharedDescriptorEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, arguments: []const Value, evidence: *std.ArrayList(u32), result_schema: ?Value) Error!bool {
        const before = evidence.items.len;
        const diagnostic_before = self.diagnostic;
        self.descriptorEvidence(m, body, arguments, evidence, result_schema) catch |err| {
            if (err == error.OutOfMemory) return err;
            evidence.shrinkRetainingCapacity(before);
            self.diagnostic = diagnostic_before;
            @import("../phase_profile.zig").detail("descriptor.shared.evidence", m.unit, m.span(body.root).start, m.span(body.root).end, body.binding);
            return false;
        };
        return true;
    }
    fn descriptorEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, arguments: []const Value, evidence: *std.ArrayList(u32), result_schema: ?Value) Error!void {
        if (result_schema) |result| if (!plainInlineValue(result) or !stableDescriptorShape(result)) {
            self.traceDescriptorBarrier(m, body.root, result, "descriptor.shared.result", true);
            return error.Declined;
        };
        var remaining: usize = 4096;
        var work: usize = 4096;
        var keys = selected_types.Builder.init(self.allocator, &work, .{});
        defer keys.deinit();
        try evidence.append(self.allocator, std.math.maxInt(u32) - 4);
        for (m.bodyParameters(body)) |parameter| try self.descriptorTypeEvidence(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, evidence, &keys, &remaining);
        try self.descriptorTypeEvidence(m, body.root, .{ .unit = m.unit, .ty = m.typeOf(body.root) }, evidence, &keys, &remaining);
        try self.descriptorBodyEvidence(m, body, null, evidence, &keys, &remaining);
        for (arguments) |argument| try self.descriptorValueEvidence(m, body.root, argument, evidence, &keys, &remaining, 0);
        if (result_schema) |result| {
            // A shared result owns no child environment. Bind its complete
            // physical schema before reconstructing it in another caller.
            try self.descriptorValueEvidence(m, body.root, result, evidence, &keys, &remaining, 0);
            try self.readerLayoutEvidence(m, body.root, result, evidence, &keys);
        }
        try self.finishSelectedTypes(m, body.root, evidence, &keys);
    }
    fn retainDescriptorShape(self: *Generator, source: Value) Error!Value {
        if (!plainShape(source)) return error.Declined;
        const arena = self.descriptor_calls.arena.allocator();
        var result = source;
        result.word = .{ .id = 0 };
        result.literal = null;
        result.constant_bits = null;
        result.type_evidence = null;
        result.name = try arena.dupe(u8, source.name);
        const fields = initializeFields(&result, try arena.alloc(Value, source.fields.len));
        result.variant_tags = try arena.dupe(u32, source.variant_tags);
        result.variant_possible = try arena.dupe(bool, source.variant_possible);
        for (fields, source.fields) |*field, original| field.* = try self.retainDescriptorShape(original);
        return result;
    }
    fn plainReaderResultABI(value: Value, expected: Value) bool {
        if (!plainInlineValue(value) or !stableDescriptorShape(value)) return false;
        if (value.tag != expected.tag or value.floating != expected.floating or !std.meta.eql(value.nominal, expected.nominal) or value.fields.len != expected.fields.len) return false;
        if (expected.name.len != 0 and !std.mem.eql(u8, value.name, expected.name)) return false;
        for (value.fields, expected.fields) |field, schema| if (!plainReaderResultABI(field, schema)) return false;
        return true;
    }
    fn stableDescriptorShape(value: Value) bool {
        return stableDescriptorShapePointer(&value);
    }
    fn stableDescriptorShapePointer(value: *const Value) bool {
        if ((value.tag != .scalar and value.tag != .aggregate) or value.variant_tags.len != 0) return false;
        for (value.fields) |*field| if (!stableDescriptorShapePointer(field)) return false;
        return true;
    }
    fn optionalWriterEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, arguments: []const Value, descriptors: []const Value, owners: []const usize, evidence: *std.ArrayList(u32)) Error!bool {
        const diagnostic_before = self.diagnostic;
        self.writerCallEvidence(m, body, arguments, descriptors, owners, evidence) catch |err| {
            if (err == error.OutOfMemory) return err;
            self.diagnostic = diagnostic_before;
            self.emission_work.scoped_outline_key_declines +|= 1;
            return false;
        };
        return true;
    }
    fn writerCallEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, arguments: []const Value, descriptors: []const Value, owners: []const usize, evidence: *std.ArrayList(u32)) Error!void {
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 2, @intCast(owners.len) });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (arguments) |argument| try self.readerLayoutEvidence(m, body.root, argument, evidence, &type_key);
        for (m.bodyParameters(body)) |parameter| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, evidence, &type_key, 0);
        for (descriptors) |value| {
            try evidence.appendSlice(self.allocator, &.{ @intCast(try writerOrdinal(owners, value.root.?)), @intCast(value.other_roots.len) });
            for (value.other_roots) |other| try evidence.append(self.allocator, @intCast(try writerOrdinal(owners, other)));
        }
        for (owners) |owner_id| {
            const owner = self.roots.items[owner_id];
            try evidence.appendSlice(self.allocator, &.{ @intFromBool(owner.frozen), @intFromBool(owner.element_initialized) });
            try self.readerLayoutEvidence(m, body.root, owner.element, evidence, &type_key);
        }
        try self.finishSelectedTypes(m, body.root, evidence, &type_key);
    }

    fn writerOrdinal(owners: []const usize, owner_id: usize) Error!usize {
        return std.mem.findScalar(usize, owners, owner_id) orelse error.Declined;
    }

    fn writerInput(self: *Generator, value: *Value, owners: []const usize, assigned: []bool) Error!void {
        value.literal = null;
        value.constant_bits = null;
        value.depth = 0;
        for (try self.writableFields(value)) |*field| try self.writerInput(field, owners, assigned);
        if (value.tag == .scalar or value.tag == .aggregate or value.tag == .callable) return;
        const original = value.root orelse return error.Declined;
        value.root = try writerOrdinal(owners, original);
        const others = try self.arena.allocator().alloc(usize, value.other_roots.len);
        for (others, value.other_roots) |*destination, source| destination.* = try writerOrdinal(owners, source);
        value.other_roots = others;
        for (self.roots.items, 0..) |*owner, index| if (hasRoot(value.*, index) and !assigned[index]) {
            // A mixed/inactive argument cannot stand in for this named pool.
            // Its own module-global descriptors load at the first actual use.
            if (owner.imported_global) continue;
            owner.word = value.word;
            owner.token = value.token;
            std.debug.assert(self.writer_trace != null and index < self.writer_trace.?.inputs);
            owner.epoch_low = value.epoch_low;
            owner.epoch_high = value.epoch_high;
            assigned[index] = true;
        };
    }
    fn clearWriterLiterals(self: *Generator, value: *Value) Error!void {
        value.literal = null;
        value.constant_bits = null;
        for (try self.writableFields(value)) |*field| try self.clearWriterLiterals(field);
    }
    const OwnerGraph = @import("storage_owner_graph.zig").Graph(Value);
    // Layout/type evidence and root edges are separate: the graph numbers each
    // owner once, so cyclic stored borrows never recurse through type evidence.
    fn graphValueEvidence(self: *Generator, m: *const core.Module, id: core.Id, value: Value, evidence: *std.ArrayList(u32), keys: *selected_types.Builder, remaining: *usize, depth: usize) Error!void {
        if (value.callable != null) self.emission_work.scoped_function_plan_callback_evidence_nodes +|= 1;
        if (depth > 128) return error.Declined;
        var metadata = value;
        metadata.fields = &.{};
        if (metadata.tag != .scalar and metadata.tag != .aggregate and metadata.tag != .callable) metadata.tag = .scalar;
        try self.descriptorValueEvidence(m, id, metadata, evidence, keys, remaining, depth);
        try evidence.appendSlice(self.allocator, &.{ @intFromBool(value.pool_borrow), @intFromBool(value.terminated) });
        for (value.fields) |field| try self.graphValueEvidence(m, id, field, evidence, keys, remaining, depth + 1);
    }
    fn graphWriterEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, actual_binding: core.BindingId, arguments: []const Value, graph: *const OwnerGraph, evidence: *std.ArrayList(u32)) Error!void {
        var remaining: usize = 100_000;
        var type_work: usize = 100_000;
        var keys = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer keys.deinit();
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 8, @intCast(graph.owners.items.len) });
        for (m.bodyParameters(body)) |parameter| try self.descriptorTypeEvidence(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, evidence, &keys, &remaining);
        try self.descriptorTypeEvidence(m, body.root, .{ .unit = m.unit, .ty = m.typeOf(body.root) }, evidence, &keys, &remaining);
        try self.descriptorBodyEvidence(m, body, null, evidence, &keys, &remaining);
        if (actual_binding != body.binding) {
            const checked = m.binding(actual_binding);
            if (checked.scheme.generative.len != 0) return error.Declined;
            for ([_]T.List{ checked.scheme.variables, checked.public_variables }) |variables| {
                try evidence.append(self.allocator, variables.len);
                for (m.types.list(variables)) |variable| try self.descriptorTypeEvidence(m, body.root, .{ .unit = m.unit, .ty = variable }, evidence, &keys, &remaining);
            }
            for ([_]T.List{ checked.scheme.row_variables, checked.public_rows }) |rows| {
                if (rows.len > remaining) return error.Declined;
                remaining -= rows.len;
                try evidence.append(self.allocator, rows.len);
                try evidence.appendSlice(self.allocator, m.types.list(rows));
            }
        }
        for (arguments) |argument| {
            try self.graphValueEvidence(m, body.root, argument, evidence, &keys, &remaining, 0);
            try self.readerLayoutEvidence(m, body.root, argument, evidence, &keys);
            try graph.edges(argument, evidence);
        }
        for (graph.owners.items) |owner_id| {
            const owner = self.roots.items[owner_id];
            try evidence.appendSlice(self.allocator, &.{ @intFromBool(owner.frozen), @intFromBool(owner.element_initialized), @intFromBool(owner.known_empty), @intFromBool(owner.live), @intFromBool(owner.persistent) });
            if (owner.persistent) try evidence.append(self.allocator, owner.stack);
            try self.graphValueEvidence(m, body.root, owner.element, evidence, &keys, &remaining, 0);
            try self.readerLayoutEvidence(m, body.root, owner.element, evidence, &keys);
            try graph.edges(owner.element, evidence);
        }
        try self.finishSelectedTypes(m, body.root, evidence, &keys);
    }
    fn optionalGraphWriterEvidence(self: *Generator, m: *const core.Module, body: *const core.Body, actual_binding: core.BindingId, arguments: []const Value, graph: *const OwnerGraph, evidence: *std.ArrayList(u32)) Error!bool {
        const before = self.diagnostic;
        self.graphWriterEvidence(m, body, actual_binding, arguments, graph, evidence) catch |err| {
            if (err == error.OutOfMemory) return err;
            self.diagnostic = before;
            return false;
        };
        return true;
    }
    fn graphInputShape(self: *Generator, value: *Value, graph: *const OwnerGraph) Error!void {
        value.literal = null;
        value.constant_bits = null;
        value.depth = 0;
        if (value.root) |owner| value.root = try graph.ordinal(owner);
        const others = try self.arena.allocator().alloc(usize, value.other_roots.len);
        for (value.other_roots, others) |owner, *ordinal| ordinal.* = try graph.ordinal(owner);
        value.other_roots = others;
        for (try self.writableFields(value)) |*field| try self.graphInputShape(field, graph);
    }
    fn graphResultLayout(value: Value) bool {
        if (value.host != null or value.tag == .callable) return false;
        for (value.fields) |field| if (!graphResultLayout(field)) return false;
        return true;
    }
    fn retainGraphShape(self: *Generator, source: Value, inputs: usize, copies: *EnvironmentCopies, depth: usize) Error!Value {
        if (depth > 128 or source.host != null or source.tag == .callable) return error.Declined;
        // Retained graphs contain only checked owner roles. Fresh result
        // owners are numbered before this copy; writer events stay input-only.
        if ((source.tag == .array and source.root == null) or (source.root != null and source.root.? >= inputs)) {
            self.emission_work.scoped_fresh_owner_summary_declines +|= 1;
            return error.Declined;
        }
        for (source.other_roots) |owner| if (owner >= inputs) {
            self.emission_work.scoped_fresh_owner_summary_declines +|= 1;
            return error.Declined;
        };
        const arena = self.descriptor_calls.arena.allocator();
        var result = source;
        result.word = .{ .id = 0 };
        result.literal = null;
        result.constant_bits = null;
        // Projected results need semantic witnesses as well as physical layout.
        // They are immutable, owned by this compilation, and selected by the
        // complete graph/type key; no child-generator arena may escape here.
        if (source.type_evidence) |known| {
            var root_type = known.root;
            if (root_type.environment) |environment| root_type.environment = try self.retainEnvironmentIn(arena, environment, copies, 0);
            result.type_evidence = try boxTypeEvidenceIn(arena, .{ .root = root_type, .arguments = try self.retainEnvironmentIn(arena, known.arguments, copies, 0) });
        }
        result.name = try arena.dupe(u8, source.name);
        result.other_roots = try arena.dupe(usize, source.other_roots);
        result.variant_tags = try arena.dupe(u32, source.variant_tags);
        result.variant_possible = try arena.dupe(bool, source.variant_possible);
        const fields = initializeFields(&result, try arena.alloc(Value, source.fields.len));
        for (fields, source.fields) |*field, original| field.* = try self.retainGraphShape(original, inputs, copies, depth + 1);
        return result;
    }
    fn graphCallerShape(self: *Generator, source: Value, owners: []const usize) Error!Value {
        var result = source;
        try self.graphCallerRoots(&result, owners);
        return result;
    }
    fn graphCallerRoots(self: *Generator, value: *Value, owners: []const usize) Error!void {
        value.depth = 0;
        if (value.root) |ordinal| {
            if (ordinal >= owners.len) return error.Declined;
            value.root = owners[ordinal];
            value.depth = self.roots.items[owners[ordinal]].depth;
        }
        const others = try self.arena.allocator().alloc(usize, value.other_roots.len);
        for (value.other_roots, others) |ordinal, *owner| {
            if (ordinal >= owners.len) return error.Declined;
            owner.* = owners[ordinal];
            value.depth = @max(value.depth, self.roots.items[owner.*].depth);
        }
        value.other_roots = others;
        for (try self.writableFields(value)) |*field| try self.graphCallerRoots(field, owners);
    }
    const PreparedArguments = struct { values: []const Value, fields_omitted: usize = 0, words_omitted: usize = 0, words_complete: bool = true };
    fn projectedArguments(self: *Generator, m: *const core.Module, body: *const core.Body, original: []const Value) Error!PreparedArguments {
        self.emission_work.scoped_argument_preparations +|= 1;
        var result: ?[]Value = null;
        var prepared: PreparedArguments = .{ .values = original };
        var word_work: usize = 4096;
        for (m.bodyParameters(body), original, 0..) |parameter, argument, index| {
            if (argument.tag != .aggregate or argument.variant_tags.len != 0 or argument.host != null or argument.root != null) continue;
            const fields = @import("storage_parameter_fields.zig");
            var nominal: ?fields.NominalRecord = null;
            var record = &argument;
            if (argument.nominal != null) {
                if (argument.fields.len != 1 or argument.other_roots.len != 0 or argument.callable != null or argument.pool_borrow or argument.sequence) continue;
                record = &argument.fields[0];
                if (record.tag != .aggregate or record.nominal != null or record.variant_tags.len != 0 or record.host != null or record.root != null or record.other_roots.len != 0 or record.callable != null or record.pool_borrow or record.sequence) continue;
            }
            // Callback presence selects work, never authority. Large plain
            // records use the same complete footprint and physical-root guards.
            var callback_work: usize = 4096;
            if (!containsCallback(record.*, &callback_work, 0) and record.fields.len < 8) continue;
            const actual = try self.resolveType(.{ .unit = m.unit, .ty = parameter.ty }, 0);
            const owner = try self.unit(actual.unit);
            if (argument.nominal) |identity| {
                var policy_work: usize = 100_000;
                nominal = fields.nominalRecord(owner, actual.ty, &policy_work) orelse continue;
                if (!std.meta.eql(nominal.?.identity, identity)) continue;
            } else if (owner.types.node(actual.ty).tag != .record) continue;
            var footprint = try fields.collect(self.allocator, m, body.root, parameter.binding, nominal);
            defer footprint.deinit(self.allocator);
            if (footprint.whole or footprint.names.items.len >= record.fields.len) continue;
            // Resolve every requested spelling before dropping any physical
            // fields. Ambiguous or absent layout evidence keeps the full ABI.
            var selected: std.ArrayList(Value) = .empty;
            defer selected.deinit(self.allocator);
            var omitted_words: usize = 0;
            var words_complete = true;
            for (record.fields) |*field| {
                var retained = false;
                for (footprint.names.items) |name| {
                    const spelling = m.fieldSpelling(name) orelse break;
                    if (std.mem.eql(u8, field.name, spelling)) {
                        try selected.append(self.allocator, field.*);
                        retained = true;
                        break;
                    }
                }
                // Diagnostic work only, bounded independently of admission.
                // Count omitted subtrees here; committed calls do no extra walk.
                if (!retained and words_complete) {
                    omitted_words +|= boundedReaderWords(field, &word_work, 0) orelse {
                        words_complete = false;
                        continue;
                    };
                }
            }
            if (selected.items.len != footprint.names.items.len) continue;
            if (result == null) result = try self.arena.allocator().dupe(Value, original);
            if (nominal != null) {
                const wrapper = try self.arena.allocator().dupe(Value, argument.fields);
                wrapper[0].fields = try self.arena.allocator().dupe(Value, selected.items);
                result.?[index].fields = wrapper;
            } else result.?[index].fields = try self.arena.allocator().dupe(Value, selected.items);
            result.?[index].projected_parameter_fields = true;
            prepared.fields_omitted +|= record.fields.len - selected.items.len;
            prepared.words_omitted +|= omitted_words;
            prepared.words_complete = prepared.words_complete and words_complete;
            self.emission_work.scoped_projected_parameter_fields +|= record.fields.len - selected.items.len;
            @import("../phase_profile.zig").detail("descriptor.parameter.projected", m.unit, m.span(body.root).start, m.span(body.root).end, record.fields.len - selected.items.len);
        }
        if (prepared.fields_omitted != 0) self.emission_work.scoped_argument_projection_preparations +|= 1;
        self.emission_work.scoped_projection_word_count_nodes +|= 4096 - word_work;
        prepared.values = result orelse original;
        return prepared;
    }
    // Statistics never expand the checked ABI or grant admission. If the full
    // original tree exceeds this separate budget, omit its word count.
    fn boundedReaderWords(value: *const Value, remaining: *usize, depth: usize) ?usize {
        if (remaining.* == 0 or depth > 128) return null;
        remaining.* -= 1;
        if (value.tag == .aggregate or value.tag == .callable) {
            var count: usize = @intFromBool(value.variant_tags.len != 0);
            for (value.fields) |*field| count = std.math.add(usize, count, boundedReaderWords(field, remaining, depth + 1) orelse return null) catch return null;
            return count;
        }
        return switch (value.tag) {
            .scalar => 1,
            .array => 4,
            .ref, .link => 5,
            .view => 6,
            else => unreachable,
        };
    }
    fn commitPreparedArguments(self: *Generator, prepared: PreparedArguments, comptime kind: enum { reader, owned }) void {
        if (prepared.fields_omitted == 0) return;
        if (kind == .reader) {
            self.emission_work.scoped_reader_projection_calls +|= 1;
            self.emission_work.scoped_reader_argument_fields_omitted +|= prepared.fields_omitted;
            if (prepared.words_complete) self.emission_work.scoped_reader_argument_words_omitted +|= prepared.words_omitted;
        } else {
            self.emission_work.scoped_owned_projection_calls +|= 1;
            self.emission_work.scoped_owned_argument_fields_omitted +|= prepared.fields_omitted;
            if (prepared.words_complete) self.emission_work.scoped_owned_argument_words_omitted +|= prepared.words_omitted;
        }
        if (!prepared.words_complete) self.emission_work.scoped_projection_word_counts_limited +|= 1;
    }
    fn containsCallback(value: Value, remaining: *usize, depth: usize) bool {
        if (remaining.* == 0 or depth > 128) return false;
        remaining.* -= 1;
        if (value.tag == .callable) return true;
        if (value.tag != .aggregate) return false;
        if (depth == 128) return false;
        if (value.fields.len > remaining.*) return false;
        remaining.* -= value.fields.len;
        // Keep the ordinary flat-record scan cheap; only aggregates recurse.
        for (value.fields) |field| if (field.tag == .callable) return true;
        for (value.fields) |field| if (field.tag == .aggregate and containsCallback(field, remaining, depth + 1)) return true;
        return false;
    }
    const published_fields = .{ "scoped_recursive_definitions", "scoped_recursive_calls", "scoped_recursive_backedges", "scoped_addressed_definitions", "scoped_addressed_calls", "scoped_addressed_input_loads", "scoped_addressed_forwarded_words", "scoped_addressed_cached_words", "scoped_addressed_snapshot_words", "scoped_addressed_retained_bytes_max", "scoped_addressed_retained_slots_max", "scoped_global_plan_definitions", "scoped_global_plan_loads", "scoped_packed_plans_promoted", "scoped_input_alias_words_avoided", "scoped_result_owner_transfer_definitions", "scoped_transferred_result_owners", "scoped_primitive_applications", "scoped_scalar_constants_folded", "scoped_bit_recurrences", "scoped_bit_rounds_removed", "scoped_fixed_spans", "scoped_fixed_span_accesses", "scoped_bulk_copies", "scoped_bulk_fills", "scoped_merge_loops", "scoped_lane_loops", "scoped_lane_simd_loops", "scoped_stride_reductions", "scoped_created_span_validations_avoided", "scoped_scalar_old_loads_avoided", "scoped_result_slots_avoided", "scoped_zero_values_shared", "scoped_join_words_shared", "scoped_result_store_words_avoided", "scoped_result_load_words_avoided", "scoped_packed_input_words_avoided", "scoped_packed_argument_words_avoided", "scoped_direct_input_words_avoided", "scoped_direct_argument_words_avoided", "scoped_immutable_survivor_bindings", "scoped_function_plan_read_events", "scoped_function_plan_write_events", "scoped_function_plan_empty_owner_contracts", "scoped_function_plan_definitions", "scoped_function_plan_emissions", "scoped_function_plan_register_calls", "scoped_inline_register_calls", "scoped_inline_result_owners_avoided", "scoped_inline_result_roots_avoided", "scoped_inline_result_bytes_avoided", "scoped_scalar_definitions", "scoped_inline_definitions", "scoped_closure_definitions", "scoped_reader_definitions", "scoped_writer_definitions", "scoped_owner_graph_definitions", "scoped_owner_graph_inputs", "scoped_completed_plan_definitions", "scoped_plain_plan_definitions", "scoped_context_free_definitions", "scoped_context_sensitive_definitions", "scoped_reader_projection_calls", "scoped_reader_argument_fields_omitted", "scoped_reader_argument_words_omitted", "scoped_owned_projection_calls", "scoped_owned_argument_fields_omitted", "scoped_owned_argument_words_omitted", "scoped_projection_word_counts_limited" };
    const FunctionMark = struct {
        module: wasm.Module.TailCheckpoint,
        local_calls: usize,
        shared_calls: usize,
        descriptor_calls: usize,
        capacities: usize,
        validation_budget: usize,
        max_stacks: u32,
        active_calls: usize,
        types: usize,
        diagnostic: ?backend.Diagnostic,
        context_sensitive: bool,
        zero_source: ZeroSource,
        publications: [published_fields.len]u64,
        fn begin(g: *Generator) ?FunctionMark {
            const module = g.module.tailCheckpoint() orelse return null;
            var publications: [published_fields.len]u64 = undefined;
            inline for (published_fields, 0..) |field, index| publications[index] = @field(g.emission_work.*, field);
            return .{ .module = module, .local_calls = g.calls.checkpoint(), .shared_calls = g.shared_calls.checkpoint(), .descriptor_calls = g.descriptor_calls.calls.checkpoint(), .capacities = g.capacity_requests.items.items.len, .validation_budget = g.validation_budget.*, .max_stacks = g.max_stacks, .active_calls = g.active_calls.frames.items.len, .types = g.type_arguments.items.len, .diagnostic = g.diagnostic, .context_sensitive = g.context_sensitive, .zero_source = g.zero_source, .publications = publications };
        }
        fn rollback(self: FunctionMark, g: *Generator) void {
            const last = g.module.functions.items.len;
            for (self.module.functions..last) |index| {
                const function: u32 = @intCast(index);
                _ = g.descriptor_calls.plans.remove(function);
            }
            g.calls.rollbackEntries(self.local_calls);
            g.shared_calls.rollbackEntries(self.shared_calls);
            g.descriptor_calls.calls.rollbackEntries(self.descriptor_calls);
            g.capacity_requests.items.shrinkRetainingCapacity(self.capacities);
            g.validation_budget.* = self.validation_budget;
            g.max_stacks = self.max_stacks;
            std.debug.assert(g.active_calls.frames.items.len == self.active_calls);
            g.type_arguments.shrinkRetainingCapacity(self.types);
            g.diagnostic = self.diagnostic;
            g.context_sensitive = self.context_sensitive;
            g.zero_source = self.zero_source;
            g.bundle_snapshots.clearRetainingCapacity();
            g.bundle_sources.clearRetainingCapacity();
            g.bundle_scan = 0;
            g.span_scopes.reset();
            inline for (published_fields, 0..) |field, index| {
                if (comptime std.mem.eql(u8, field, "scoped_reader_projection_calls") or std.mem.eql(u8, field, "scoped_owned_projection_calls")) {
                    g.emission_work.scoped_argument_projection_discards +|= @field(g.emission_work.*, field) -| self.publications[index];
                }
                @field(g.emission_work.*, field) = self.publications[index];
            }
            g.module.rollbackTail(self.module);
        }
    };
    fn tryFunctionPlan(self: *Generator, input: FunctionPlanInput) Error!?usize {
        if (self.descriptor_calls.declined.contains(input.key)) return null;
        const mark = FunctionMark.begin(self) orelse return null;
        const prefix_before = self.capacity_prefix;
        self.capacity_prefix = mark.capacities;
        defer self.capacity_prefix = prefix_before;
        var complete = false;
        defer if (!complete) mark.rollback(self);
        const expressions_before = self.emission_work.scoped_emission_expressions;
        const discarded_before = self.emission_work.scoped_completed_plan_discarded_expressions;
        self.emission_work.scoped_completed_plan_attempts +|= 1;
        const result = self.buildFunctionPlan(input) catch |err| {
            if (err == error.OutOfMemory) return err;
            self.emission_work.scoped_completed_plan_rollbacks +|= 1;
            const nested_discarded = self.emission_work.scoped_completed_plan_discarded_expressions - discarded_before;
            self.emission_work.scoped_completed_plan_discarded_expressions +|= self.emission_work.scoped_emission_expressions - expressions_before - nested_discarded;
            try self.descriptor_calls.decline(input.key);
            return null;
        };
        self.emission_work.scoped_completed_plan_definitions +|= 1;
        complete = true;
        return result;
    }
    fn ownedWordAbi(words: usize, result: Value) bool {
        // Bound the complete machine signature, including the result pointer.
        return words <= 512 - @as(usize, @intFromBool(result.tag != .scalar));
    }
    const FunctionPlanInput = struct {
        module: *const core.Module,
        target: core.BindingRef,
        arguments: []const Value,
        owners: []const usize,
        graph: ?*const OwnerGraph,
        words: usize,
        input_aliases: []const u32,
        alias_rejected: ?*bool = null,
        addressed: bool = true,
        addressed_rejected: ?*bool = null,
        borrowed_inputs: bool = false,
        recursive: ?*const recursive_admission.Contract = null,
        created_receipts: []const bool = &.{},
        capture_globals: bool,
        unit_result: bool,
        result_shape: Value,
        shared: bool,
        key: call_plan.Key,
    };
    fn buildFunctionPlan(self: *Generator, request: FunctionPlanInput) Error!usize {
        var candidate = request;
        candidate.addressed = candidate.addressed and request.words >= 64 and request.recursive == null and !self.recursive_scope;
        if (candidate.addressed) candidate.addressed = !self.descriptor_calls.addressed_declined.contains(request.key);
        while (true) {
            const mark = FunctionMark.begin(self) orelse return error.Declined;
            var alias_rejected = false;
            var addressed_rejected = false;
            candidate.alias_rejected = &alias_rejected;
            candidate.addressed_rejected = &addressed_rejected;
            const expressions_before = self.emission_work.scoped_emission_expressions;
            const discarded_before = self.emission_work.scoped_completed_plan_discarded_expressions;
            return self.constructFunctionPlan(candidate) catch |err| {
                if (err == error.OutOfMemory or (!alias_rejected and !addressed_rejected)) return err;
                mark.rollback(self);
                if (addressed_rejected) {
                    candidate.addressed = false;
                    try self.descriptor_calls.declineAddressed(request.key);
                    self.emission_work.scoped_addressed_retries +|= 1;
                } else {
                    candidate.input_aliases = &.{};
                    self.emission_work.scoped_input_alias_retries +|= 1;
                }
                self.emission_work.scoped_completed_plan_rollbacks +|= 1;
                const nested_discarded = self.emission_work.scoped_completed_plan_discarded_expressions - discarded_before;
                self.emission_work.scoped_completed_plan_discarded_expressions +|= self.emission_work.scoped_emission_expressions - expressions_before - nested_discarded;
                continue;
            };
        }
    }
    fn constructFunctionPlan(self: *Generator, request: FunctionPlanInput) Error!usize {
        const m = request.module;
        const target = request.target;
        const body = m.body(target.binding) orelse return error.Declined;
        const arguments = request.arguments;
        const owners = request.owners;
        const graph = request.graph;
        const graph_mode = graph != null;
        const words = request.words;
        const unit_result = request.unit_result;
        const shared = request.shared;
        var addressed: []bool = &.{};
        defer self.allocator.free(addressed);
        var physical_words: usize = 0;
        var has_bundle = false;
        if (request.addressed and !self.scalar_admission.hasScalarReferences()) {
            addressed = try self.allocator.alloc(bool, arguments.len);
            for (arguments, addressed) |argument, *by_address| {
                const count = readerWords(argument);
                by_address.* = count >= 64;
                has_bundle = has_bundle or by_address.*;
                if (by_address.*) physical_words += 1 else physical_words += count;
            }
            if (!has_bundle or physical_words >= 512) {
                self.allocator.free(addressed);
                addressed = &.{};
            }
        }
        const using_bundles = addressed.len != 0;
        var direct = using_bundles or ownedWordAbi(words, request.result_shape);
        const return_registers = if (direct) try inlineReturnRegisters(request.result_shape) else 0;
        const buffered_result = request.result_shape.tag != .scalar and return_registers == 0;
        const key = request.key;
        const cache = &self.descriptor_calls.calls;
        var signature: []const wasm.ValueType = &.{.i32};
        if (direct) {
            const count = std.math.add(usize, if (using_bundles) physical_words else words, @intFromBool(buffered_result)) catch return error.Declined;
            const parameters = try self.arena.allocator().alloc(wasm.ValueType, count);
            @memset(parameters, .i32);
            signature = parameters;
        }
        const function = self.module.addTypedFunction(signature, .i32, .scalar) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.unsupported(m, body.root),
        };
        const inserted = try cache.insert(key, function, request.result_shape.floating);
        var trace: WriterTrace = .{ .inputs = owners.len, .stable = request.recursive != null or (shared and !graph_mode) };
        defer trace.events.deinit(self.allocator);
        var child: Generator = .{
            .allocator = self.allocator,
            .arena = std.heap.ArenaAllocator.init(self.allocator),
            .calls = .{ .allocator = self.allocator },
            .shared_calls = self.shared_calls,
            .descriptor_calls = self.descriptor_calls,
            .field_recipes = self.field_recipes,
            .scalar_admission = self.scalar_admission,
            .active_calls = self.active_calls,
            .specialize = false,
            .work_limits = self.work_limits,
            .emission_work = self.emission_work,
            .outlining = self.outlining,
            .units = self.units,
            .unit_views = self.unit_views,
            .proof_cache = self.proof_cache,
            .dispatches = self.dispatches,
            .capacity_requests = self.capacity_requests,
            .capacity_prefix = self.capacity_prefix,
            .validation_budget = self.validation_budget,
            .entry_unit = self.entry_unit,
            .specialization_origin = self.specialization_origin,
            .methods = self.methods,
            .module = self.module,
            .runtime = self.runtime,
            .fixed_region = self.fixed_region,
            .max_stacks = self.max_stacks,
            .writer_trace = &trace,
            .recursive_scope = self.recursive_scope or request.recursive != null,
            .c = .{ .module = self.module, .function = function },
        };
        defer child.deinit();
        try self.inheritTypes(&child);
        try child.stacks.appendSlice(self.allocator, self.stacks.items);
        if (request.capture_globals) {
            try child.globals.appendSlice(self.allocator, self.globals.items);
            child.globals_ready = true;
        }
        for (owners, 0..) |owner_id, owner_ordinal| {
            const original = self.roots.items[owner_id];
            var row = original.element;
            try child.clearWriterLiterals(&row);
            if (graph) |value| try child.graphInputShape(&row, value);
            try child.roots.append(self.allocator, .{ .word = .{ .id = 0 }, .token = .{ .id = 0 }, .epoch_low = .{ .id = 0 }, .epoch_high = .{ .id = 0 }, .stack = self.fixed_region, .depth = 0, .element = row, .element_initialized = original.element_initialized, .known_empty = original.known_empty, .frozen = original.frozen, .live = original.live, .persistent = original.persistent, .dedicated = false, .fixed_created = request.created_receipts.len == owners.len and request.created_receipts[owner_ordinal] });
        }
        // Input owners precede every helper cleanup boundary. Only new local
        // owners can have their token cleared; loops mark separately.
        child.indexed_mutable_roots = owners.len;
        const assigned = try child.arena.allocator().alloc(bool, owners.len);
        @memset(assigned, false);
        const inputs = try child.arena.allocator().alloc(Value, arguments.len);
        var input_aliases = request.input_aliases;
        if (self.scalar_admission.hasScalarReferences()) input_aliases = &.{};
        var offset: u32 = 0;
        if (using_bundles) {
            try self.module.functions.items[function].locals.appendNTimes(self.allocator, .i32, words);
            offset = @intCast(signature.len);
            const bundles = try child.arena.allocator().alloc(InputBundle, std.mem.count(bool, addressed, &.{true}));
            var parameter: u32 = 0;
            var first = offset;
            var index: usize = 0;
            for (arguments, addressed) |argument, by_address| {
                const count = readerWords(argument);
                if (by_address) {
                    const needed = try child.arena.allocator().alloc(bool, count);
                    @memset(needed, false);
                    bundles[index] = .{ .parameter = parameter, .first = first, .words = count, .needed = needed };
                    index += 1;
                    parameter += 1;
                } else parameter += @intCast(count);
                first += @intCast(count);
            }
            child.input_bundles = bundles;
        } else if (!direct) {
            // Logical words keep packet order; dummy callable words and body
            // temporaries allocate after this complete reserved input range.
            try self.module.functions.items[function].locals.appendNTimes(self.allocator, .i32, words);
            offset = 1;
        }
        if (request.capture_globals) {
            for (owners, child.roots.items) |owner_id, *root_| {
                const original = self.roots.items[owner_id];
                if (!original.persistent) continue;
                root_.stack = original.stack;
                root_.imported_global = true;
            }
            const roots = try child.arena.allocator().alloc(usize, child.globals.items.len);
            @memset(roots, std.math.maxInt(usize));
            for (child.roots.items, 0..) |root_, index| if (root_.persistent) {
                roots[root_.stack] = index;
            };
            child.global_roots = roots;
        }
        const input_first = offset;
        for (inputs, arguments) |*input, argument| {
            input.* = try child.readerWordParameter(argument, &offset, input_aliases, input_first);
            try child.writerInput(input, owners, assigned);
        }
        std.debug.assert(offset == input_first + words);
        var invariant: []recursive_admission.Access = &.{};
        var provisional: CheckedFunctionPlan = undefined;
        if (request.recursive) |contract| {
            invariant = try self.descriptor_calls.arena.allocator().alloc(recursive_admission.Access, owners.len);
            @memset(invariant, .{});
            const parameter_owners = try child.arena.allocator().alloc(u32, arguments.len);
            @memset(parameter_owners, std.math.maxInt(u32));
            for (arguments, contract.parameter_access, parameter_owners) |argument, access, *role| if (argument.root) |owner| {
                const ordinal = try writerOrdinal(owners, owner);
                role.* = @intCast(ordinal);
                invariant[ordinal].read = invariant[ordinal].read or access.read;
                invariant[ordinal].write = invariant[ordinal].write or access.write;
            };
            for (child.roots.items, owners, invariant) |*owner, original_id, access| {
                const original = self.roots.items[original_id];
                if ((access.read or access.write) and (!original.live or (!original.element_initialized and !original.known_empty))) return error.Declined;
                if (access.write and original.frozen) return error.Declined;
                owner.known_empty = false;
                // A fixed empty owner has no uninitialized existing rows and
                // this contract cannot add rows. No caller fact is upgraded.
                owner.element_initialized = original.element_initialized or original.known_empty;
            }
            provisional = .{ .entry = cache.entries.items[inserted], .input_words = words, .used_input_words = &.{}, .result_aliases = &.{}, .unit_result = true, .abi = .scalar, .return_registers = 0, .result = .{ .word = .{ .id = 0 } }, .access = .{ .invariant = invariant }, .regions = &.{} };
            child.recursive_header = .{ .target = target, .plan = &provisional, .parameter_owners = parameter_owners };
        }
        const output = child.invokeBody(target, inputs, 0, false) catch |err| {
            if (child.diagnostic) |diagnostic| self.diagnostic = diagnostic;
            return err;
        };
        var copies: EnvironmentCopies = .empty;
        defer copies.deinit(self.allocator);
        var result_aliases: []u32 = &.{};
        defer self.allocator.free(result_aliases);
        var result_template = request.result_shape;
        var returned_owners: []const ReturnedOwner = &.{};
        const serialization_start = self.module.functions.items[function].instructions.items.len;
        if (unit_result) {
            try child.c.value(try child.scalar(m, body.root, output));
        } else {
            var source = request.result_shape;
            if (!output.terminated) source = output;
            var roles: ?OwnerGraph = null;
            defer if (roles) |*value| value.deinit();
            var result_owner_count = owners.len;
            if (!output.terminated and storage_plan.nextRoot(source, owners.len, child.roots.items.len) != null) {
                roles = OwnerGraph.result(self.allocator, child.roots.items, owners.len, source, child.fixed_region, plainInlineValue) catch |err| {
                    if (err != error.OutOfMemory) {
                        self.emission_work.scoped_fresh_owner_summary_declines +|= 1;
                        @import("../phase_profile.zig").detail("descriptor.result.fresh-owner", m.unit, m.span(body.root).start, m.span(body.root).end, target.binding);
                    }
                    return err;
                };
                const graph_ = &roles.?;
                result_owner_count = graph_.owners.items.len;
                try child.graphInputShape(&source, graph_);
                const summaries = try self.descriptor_calls.arena.allocator().alloc(ReturnedOwner, result_owner_count - owners.len);
                for (summaries, graph_.owners.items[owners.len..]) |*summary, index| {
                    const owner = child.roots.items[index];
                    summary.* = .{ .element = try self.retainGraphShape(owner.element, 0, &copies, 0), .element_initialized = owner.element_initialized, .known_empty = owner.known_empty, .frozen = owner.frozen };
                }
                returned_owners = summaries;
            }
            const template = try self.retainGraphShape(source, result_owner_count, &copies, 0);
            result_template = template;
            if (return_registers != 0) {
                try child.publishInlineReturn(output, return_registers);
            } else if (request.result_shape.tag == .scalar) {
                try child.c.value(try child.scalar(m, body.root, output));
            } else {
                var output_words: std.ArrayList(Local) = .empty;
                defer output_words.deinit(self.allocator);
                try child.readerWordLocals(output, &output_words);
                if (!output.terminated and !self.scalar_admission.hasScalarReferences()) {
                    var candidates: std.ArrayList(Local) = .empty;
                    defer candidates.deinit(self.allocator);
                    try child.resultAliasCandidates(output, &candidates);
                    std.debug.assert(candidates.items.len == output_words.items.len);
                    const first = input_first;
                    result_aliases = try @import("storage_result_alias.zig").analyze(self.allocator, &self.module.functions.items[function], first, words, candidates.items);
                }
                var address: Local = .{ .id = 0 };
                var base: usize = words * 4;
                if (direct) {
                    address.id = @intCast(words);
                    if (using_bundles) address.id = @intCast(physical_words);
                    base = 0;
                }
                for (output_words.items, 0..) |word, ordinal| {
                    if (result_aliases.len != 0 and result_aliases[ordinal] != @import("storage_result_alias.zig").absent) {
                        self.emission_work.scoped_result_store_words_avoided +|= 1;
                        continue;
                    }
                    try child.c.store(address, @intCast(base + ordinal * 4), word);
                }
                try child.c.value(0);
            }
        }
        // An ordinary helper has no registered outline root. Do not publish
        // a body the existing Wasm engine cannot encode; expanded fallback
        // retains the caller's outliner. Standard scoped instructions encode
        // within 64 bytes, including vector immediates. This conservative raw
        // body bound includes local groups/header; final encoding remains the
        // authority after optimization (this is not an arbitrary-IR proof).
        const machine = &self.module.functions.items[function];
        if (request.capture_globals) {
            for (child.roots.items[0..owners.len]) |root_| if (root_.imported_global and root_.global_ready != null) {
                self.emission_work.scoped_global_plan_definitions +|= 1;
                break;
            };
        }
        if (using_bundles and scope_outline.hasCoordinates(self.module, function)) {
            if (request.addressed_rejected) |rejected| rejected.* = true;
            return error.Declined;
        }
        if (input_aliases.len != 0) {
            if (scope_outline.hasCoordinates(self.module, function) or !try @import("storage_input_alias.zig").readOnly(self.allocator, machine, input_first, input_aliases)) {
                if (request.alias_rejected) |rejected| rejected.* = true;
                return error.Declined;
            }
            for (input_aliases, 0..) |alias, ordinal| if (alias != ordinal) {
                self.emission_work.scoped_input_alias_words_avoided +|= 1;
            };
        }
        if (request.recursive != null) {
            if (child.roots.items.len != owners.len or child.used_regions.count() != 0 or scope_outline.hasCoordinates(self.module, function)) return error.Declined;
            for (trace.events.items) |event| {
                if (event.owner >= invariant.len) return error.Declined;
                const allowed = invariant[event.owner];
                if ((event.kind == .read and !allowed.read) or (event.kind == .write and !allowed.write)) return error.Declined;
                if (event.shape.tag != .scalar or event.shape.floating or event.shape.fields.len != 0 or event.shape.root != null) return error.Declined;
            }
            self.emission_work.scoped_recursive_definitions +|= 1;
        }
        var result_pointer_first = false;
        if (!direct and !scope_outline.hasCoordinates(self.module, function) and try @import("direct_input_demand.zig").canPromotePacked(self.allocator, machine, words, serialization_start, buffered_result)) {
            const parameters = try self.arena.allocator().alloc(wasm.ValueType, words + 1);
            @memset(parameters, .i32);
            machine.parameters = parameters;
            // Parameters take over the reserved leading i32 local types. Every
            // input, body temporary and result recipe keeps its logical ID.
            std.mem.copyForwards(wasm.ValueType, machine.locals.items, machine.locals.items[words..]);
            machine.locals.items.len -= words;
            if (buffered_result) {
                for (machine.instructions.items[serialization_start..]) |*inst| {
                    if (inst.op == .i32_store) {
                        std.debug.assert(inst.operand >= words * 4);
                        inst.operand -= @intCast(words * 4);
                    }
                }
            }
            direct = true;
            result_pointer_first = true;
            self.emission_work.scoped_packed_plans_promoted +|= 1;
        }
        var input_demand: []bool = &.{};
        defer self.allocator.free(input_demand);
        if (using_bundles) {
            input_demand = try self.allocator.alloc(bool, words);
            @memset(input_demand, false);
            for (machine.instructions.items) |inst| {
                if (inst.op == .local_get and inst.operand >= input_first and inst.operand - input_first < words) input_demand[inst.operand - input_first] = true;
            }
            var forwarded: usize = 0;
            for (child.input_bundles) |bundle| for (bundle.needed, 0..) |needed, ordinal| {
                if (needed) {
                    input_demand[bundle.first - input_first + ordinal] = true;
                    forwarded += 1;
                }
            };
            const result_pointer = buffered_result and !fullyAliasedResult(result_aliases);
            const demanded = std.mem.count(bool, input_demand, &.{true}) + @intFromBool(result_pointer);
            if (!request.borrowed_inputs and demanded <= 512 and forwarded < 16) {
                if (request.addressed_rejected) |rejected| rejected.* = true;
                return error.Declined;
            }
            const bundles = try self.allocator.alloc(addressed_input.Bundle, child.input_bundles.len);
            defer self.allocator.free(bundles);
            for (bundles, child.input_bundles) |*bundle, input| bundle.* = .{ .parameter = input.parameter, .first = input.first, .words = input.words };
            const lowered = (try addressed_input.materialize(self.allocator, machine, bundles)) orelse {
                if (request.addressed_rejected) |rejected| rejected.* = true;
                return error.Declined;
            };
            defer self.allocator.free(lowered.used);
            self.emission_work.scoped_addressed_input_loads +|= lowered.loads;
            // Narrow inputs remain ordinary parameters, copied to their
            // reserved logical positions only when actually read.
            var prefix: std.ArrayList(wasm.Instruction) = .empty;
            defer prefix.deinit(self.allocator);
            var parameter: u32 = 0;
            var ordinal: usize = 0;
            for (arguments, addressed) |argument, by_address| {
                const count = readerWords(argument);
                if (by_address) parameter += 1 else for (0..count) |index| {
                    if (input_demand[ordinal + index]) try prefix.appendSlice(self.allocator, &.{
                        .{ .op = .local_get, .operand = parameter + @as(u32, @intCast(index)) },
                        .{ .op = .local_set, .operand = input_first + @as(u32, @intCast(ordinal + index)) },
                    });
                }
                if (!by_address) parameter += @intCast(count);
                ordinal += count;
            }
            try machine.instructions.insertSlice(self.allocator, 0, prefix.items);
            self.emission_work.scoped_addressed_definitions +|= 1;
        } else if (direct and request.recursive == null) {
            // Only this new helper may gain an entry prefix. No published
            // semantic or table position may refer into its original body.
            if (!scope_outline.hasCoordinates(self.module, function)) {
                const demand = try @import("direct_input_demand.zig").materialize(self.allocator, machine);
                input_demand = demand.used;
                self.emission_work.scoped_direct_input_words_avoided +|= demand.omitted;
                if (input_demand.len != 0 or result_pointer_first) {
                    machine.signature = self.module.internType(machine.parameters, machine.result) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.Declined,
                    };
                    machine.parameters = self.module.signatures.items[machine.signature].parameters;
                }
            }
        } else if (!direct) {
            const demand = try @import("packed_input_demand.zig").materialize(self.allocator, machine, words);
            input_demand = demand.used;
            self.emission_work.scoped_packed_input_words_avoided +|= demand.omitted;
        }
        if (result_pointer_first) std.debug.assert(machine.parameters.len <= 512);
        const raw_bytes = 6 +| (machine.locals.items.len *| 6) +| (machine.instructions.items.len *| 64);
        if (machine.parameters.len > 50_000 or machine.locals.items.len > 50_000 - machine.parameters.len or raw_bytes > 7_654_321) {
            self.emission_work.scoped_function_plan_machine_declines +|= 1;
            return error.Declined;
        }
        self.max_stacks = @max(self.max_stacks, child.max_stacks);
        var regions: std.ArrayList(usize) = .empty;
        defer regions.deinit(self.allocator);
        if (self.recursive_scope and (child.roots.items.len != owners.len or child.used_regions.count() != 0)) return error.Declined;
        // Closed scratch roots still describe regions used at runtime.
        for (child.roots.items[owners.len..]) |owner| if (owner.dedicated and std.mem.findScalar(usize, regions.items, owner.stack) == null) try regions.append(self.allocator, owner.stack);

        var descendant_regions = child.used_regions.keyIterator();
        while (descendant_regions.next()) |region| if (std.mem.findScalar(usize, regions.items, region.*) == null) try regions.append(self.allocator, region.*);
        var summary_arena = self.arena.allocator();
        if (shared) summary_arena = self.descriptor_calls.arena.allocator();
        const facts = try summary_arena.alloc(WriterEvent, trace.events.items.len);
        for (facts, trace.events.items) |*fact, original| {
            var shape_: Value = undefined;
            if (graph_mode) {
                shape_ = try self.retainGraphShape(original.shape, owners.len, &copies, 0);
            } else if (shared) shape_ = try self.retainDescriptorShape(original.shape) else shape_ = try self.retainReaderResult(original.shape, 0, &copies, true, 0);
            fact.* = .{ .owner = original.owner, .kind = original.kind, .shape = shape_, .initializes_rows = original.initializes_rows };
        }
        const retained_regions = try summary_arena.dupe(usize, regions.items);
        const plan = try summary_arena.create(CheckedFunctionPlan);
        const used_input_words = try summary_arena.dupe(bool, input_demand);
        const retained_aliases = try summary_arena.dupe(u32, result_aliases);
        const retained_addressed = try summary_arena.dupe(bool, addressed);
        try self.descriptor_calls.plans.ensureUnusedCapacity(self.allocator, 1);
        try self.completeCall(cache, inserted, child.context_sensitive, shared and graph_mode);
        plan.* = .{ .entry = cache.entries.items[inserted], .input_words = words, .used_input_words = used_input_words, .result_aliases = retained_aliases, .unit_result = unit_result, .abi = if (!direct) .buffered else if (return_registers != 0) .registers else if (buffered_result) .result_slot else .scalar, .return_registers = return_registers, .result_pointer_first = result_pointer_first, .addressed_arguments = retained_addressed, .result = result_template, .returned_owners = returned_owners, .access = .{ .ordered = facts }, .regions = retained_regions };
        if (request.recursive != null) plan.access = .{ .invariant = invariant };
        self.descriptor_calls.plans.putAssumeCapacityNoClobber(function, plan);
        for (facts) |event| {
            if (event.kind == .read) self.emission_work.scoped_function_plan_read_events +|= 1 else self.emission_work.scoped_function_plan_write_events +|= 1;
        }
        if (owners.len != 0 and facts.len == 0) self.emission_work.scoped_function_plan_empty_owner_contracts +|= 1;
        if (returned_owners.len != 0) self.emission_work.scoped_result_owner_transfer_definitions +|= 1;
        self.emission_work.scoped_function_plan_definitions +|= 1;
        self.emission_work.scoped_writer_definitions +|= 1;
        if (graph_mode and owners.len == 0) {
            self.emission_work.scoped_plain_plan_definitions +|= 1;
        } else if (graph_mode) {
            self.emission_work.scoped_owner_graph_definitions +|= 1;
            self.emission_work.scoped_owner_graph_inputs +|= owners.len;
            @import("../phase_profile.zig").detail("descriptor.owner-graph.complete", m.unit, m.span(body.root).start, m.span(body.root).end, owners.len);
        }
        return inserted;
    }

    const PreparedFunctionCall = struct {
        graph: OwnerGraph,
        evidence: std.ArrayList(u32),
        key: call_plan.Key,
        words: usize,
        arguments: []const Value,
        closed_scalar: bool,
        input_aliases: []const u32,
        borrowed_inputs: bool,
        capture_globals: bool,
        created_receipts: []const bool,
        fn deinit(self: *PreparedFunctionCall, allocator: std.mem.Allocator) void {
            self.graph.deinit();
            self.evidence.deinit(allocator);
            allocator.free(self.input_aliases);
        }
    };
    fn createdReceiptValues(self: *Generator, value: Value, graph: *const OwnerGraph, receipts: []bool, seen: []bool, remaining: *usize, depth: usize) Error!void {
        if (remaining.* == 0 or depth > 128) return error.Declined;
        remaining.* -= 1;
        if (value.root) |root_id| {
            const ordinal = try graph.ordinal(root_id);
            seen[ordinal] = true;
            if (!createdDescriptorMatches(self.roots.items[root_id], value)) receipts[ordinal] = false;
        }
        for (value.other_roots) |root_id| receipts[try graph.ordinal(root_id)] = false;
        for (value.fields) |field| try self.createdReceiptValues(field, graph, receipts, seen, remaining, depth + 1);
    }
    fn createdReceipts(self: *Generator, arguments: []const Value, graph: *const OwnerGraph, evidence: *std.ArrayList(u32)) Error![]const bool {
        const owners = graph.owners.items;
        if (owners.len == 0) return &.{};
        const receipts = try self.arena.allocator().alloc(bool, owners.len);
        const seen = try self.arena.allocator().alloc(bool, owners.len);
        @memset(seen, false);
        for (owners, receipts) |owner, *receipt| receipt.* = self.roots.items[owner].fixed_created and !self.scalar_admission.hasScalarReferences();
        var remaining: usize = 100_000;
        for (arguments) |argument| self.createdReceiptValues(argument, graph, receipts, seen, &remaining, 0) catch |err| {
            if (err == error.OutOfMemory) return err;
            @memset(receipts, false);
            break;
        };
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 19, @intCast(owners.len) });
        for (receipts, seen) |*receipt, present| {
            receipt.* = receipt.* and present;
            try evidence.append(self.allocator, @intFromBool(receipt.*));
        }
        return receipts;
    }
    fn prepareFunctionCall(self: *Generator, m: *const core.Module, target: core.BindingRef, arguments: []const Value) Error!?PreparedFunctionCall {
        if (self.destination != null) return null;
        const body = m.body(target.binding) orelse return null;
        var evidence: std.ArrayList(u32) = .empty;
        var keep = false;
        defer if (!keep) evidence.deinit(self.allocator);
        self.emission_work.scoped_function_plan_preparations +|= 1;
        var scalar_inputs = true;
        for (arguments) |argument| if (argument.tag != .scalar or argument.callable != null or argument.host != null or argument.root != null or argument.other_roots.len != 0 or argument.fields.len != 0 or argument.variant_tags.len != 0) {
            scalar_inputs = false;
            break;
        };
        const closed_scalar = scalar_inputs and try self.closedScalarBody(m, target.binding);
        const capture_globals = self.globals_ready and self.globals.items.len != 0 and !closed_scalar;
        var graph_arguments: std.ArrayList(Value) = .empty;
        defer graph_arguments.deinit(self.allocator);
        var owner_arguments = arguments;
        if (capture_globals) {
            var buffer: [256]u8 = undefined;
            var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
            const mask = try scratch.allocator().alloc(bool, self.globals.items.len);
            defer scratch.allocator().free(mask);
            @memset(mask, false);
            if (self.descriptor_calls.global_footprint == null) return error.Declined;
            const index = &self.descriptor_calls.global_footprint.?;
            for (try index.slots(m.unit, body.root, body.scheme)) |slot| mask[slot] = true;
            var remaining: usize = 100_000;
            for (arguments) |argument| try self.callableGlobalSlots(argument, mask, &remaining, 0);
            try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 14, @intCast(std.mem.count(bool, mask, &.{true})) });
            for (mask, 0..) |needed, slot| {
                if (!needed) continue;
                try evidence.append(self.allocator, @intCast(slot));
                const owner_id = self.global_roots[slot];
                if (owner_id == std.math.maxInt(usize)) return null;
                try graph_arguments.append(self.allocator, .{ .tag = .array, .word = .{ .id = 0 }, .root = owner_id });
            }
            if (graph_arguments.items.len != 0) {
                try graph_arguments.appendSlice(self.allocator, arguments);
                owner_arguments = graph_arguments.items;
            }
        }
        var graph = OwnerGraph.init(self.allocator, self.roots.items, owner_arguments) catch |err| {
            if (err == error.OutOfMemory) return err;
            return null;
        };
        defer if (!keep) graph.deinit();
        const created_receipts = try self.createdReceipts(arguments, &graph, &evidence);
        if (closed_scalar) {
            try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 12, m.typeOf(body.root), @intCast(arguments.len) });
            for (m.bodyParameters(body), arguments) |parameter, argument| try evidence.appendSlice(self.allocator, &.{ parameter.ty, @intFromBool(argument.floating) });
            self.emission_work.scoped_function_plan_closed_scalar_preparations +|= 1;
        } else if (!try self.optionalGraphWriterEvidence(m, body, target.binding, arguments, &graph, &evidence)) return null;
        var words: usize = 0;
        for (arguments) |argument| words = std.math.add(usize, words, readerWords(argument)) catch return null;
        var input_aliases: []const u32 = &.{};
        var borrowed_inputs = false;
        errdefer self.allocator.free(input_aliases);
        if (!closed_scalar) {
            var locals: std.ArrayList(Local) = .empty;
            defer locals.deinit(self.allocator);
            for (arguments) |argument| try self.readerWordLocals(argument, &locals);
            var ordinal: usize = 0;
            for (arguments) |argument| {
                const count = readerWords(argument);
                if (count >= 64 and self.inputBundleRange(locals.items[ordinal..][0..count]) != null) borrowed_inputs = true;
                ordinal += count;
            }
            input_aliases = try @import("storage_input_alias.zig").partition(self.allocator, locals.items);
            try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 13, @intCast(input_aliases.len) });
            try evidence.appendSlice(self.allocator, input_aliases);
        }
        // Physical ABI preference is structural provenance, never a pointer
        // value. A borrowed-bundle alternative cannot select a costly snapshot
        // ABI for unrelated direct callers with the same semantic signature.
        if (borrowed_inputs) try evidence.append(self.allocator, std.math.maxInt(u32) - 15);
        if (self.recursive_scope) try evidence.append(self.allocator, std.math.maxInt(u32) - 17);
        keep = true;
        return .{ .created_receipts = created_receipts, .borrowed_inputs = borrowed_inputs, .graph = graph, .evidence = evidence, .words = words, .arguments = arguments, .closed_scalar = closed_scalar, .input_aliases = input_aliases, .capture_globals = capture_globals, .key = .{ .unit = m.unit, .binding = target.binding, .context = if (closed_scalar) 0 else self.invocationContext(), .context_free = closed_scalar, .evidence = evidence.items } };
    }
    fn callableGlobalSlots(self: *Generator, value: Value, mask: []bool, remaining: *usize, depth: usize) Error!void {
        if (remaining.* == 0 or depth > 128) {
            @memset(mask, true);
            return;
        }
        remaining.* -= 1;
        if (value.callable) |callable| {
            if (callable.goals.len != 0) {
                @memset(mask, true);
                return;
            }
            if (self.descriptor_calls.global_footprint == null) return error.Declined;
            const index = &self.descriptor_calls.global_footprint.?;
            const owner = try self.unit(callable.unit);
            var root_ = callable.node;
            var scheme: T.Scheme = .{};
            if (callable.target != 0) {
                const body = owner.body(callable.target) orelse return error.Declined;
                root_ = body.root;
                scheme = body.scheme;
            }
            for (try index.slots(owner.unit, root_, scheme)) |slot| mask[slot] = true;
        }
        for (value.fields) |field| try self.callableGlobalSlots(field, mask, remaining, depth + 1);
    }
    fn getOrBuildFunctionPlan(self: *Generator, m: *const core.Module, target: core.BindingRef, call: *PreparedFunctionCall) Error!?*const CheckedFunctionPlan {
        const body = m.body(target.binding) orelse return null;
        var candidates = self.descriptor_calls.calls.candidates(call.key);
        while (candidates.next()) |index| {
            const entry = self.descriptor_calls.calls.entries.items[index];
            if (entry.building) return self.fail(m, body.root, .storage_unsupported, "Recursive function plans are not admitted");
            const plan = self.descriptor_calls.plans.get(entry.function) orelse return self.unsupported(m, body.root);
            var available = true;
            for (plan.regions) |region| if (region < self.stacks.items.len and self.stacks.items[region]) {
                available = false;
                break;
            };
            if (!available) continue;
            self.emission_work.scoped_function_plan_hits +|= 1;
            return plan;
        }
        if (self.descriptor_calls.declined.contains(call.key)) return null;
        self.emission_work.scoped_function_plan_constructions +|= 1;
        const result: TypeRef = if (call.closed_scalar) .{ .unit = m.unit, .ty = m.typeOf(body.root) } else try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(body.root) }, 0);
        const unit_result = (try self.unit(result.unit)).types.node(result.ty).tag == .unit;
        var result_shape: Value = .{ .word = .{ .id = 0 } };
        if (call.closed_scalar) {
            result_shape.floating = result.ty == T.f32_type;
        } else if (!unit_result) {
            const graph_before = self.planning_owner_graph;
            self.planning_owner_graph = true;
            defer self.planning_owner_graph = graph_before;
            var remaining: usize = 100_000;
            if (!try self.selectedDataType(result, true, &remaining, 0)) return null;
            const before = self.type_arguments.items.len;
            defer self.type_arguments.shrinkRetainingCapacity(before);
            if (result.environment) |environment| try self.restoreTypes(environment);
            result_shape = try self.shape(try self.unit(result.unit), if (result.unit == m.unit) body.root else 0, result.ty, 0);
            if (!graphResultLayout(result_shape)) return null;
        }
        const request: FunctionPlanInput = .{ .module = m, .target = target, .arguments = call.arguments, .owners = call.graph.owners.items, .graph = &call.graph, .words = call.words, .input_aliases = call.input_aliases, .created_receipts = call.created_receipts, .capture_globals = call.capture_globals, .borrowed_inputs = call.borrowed_inputs, .unit_result = unit_result, .result_shape = result_shape, .shared = true, .key = call.key };
        const index = (try self.tryFunctionPlan(request)) orelse return null;
        return self.descriptor_calls.plans.get(self.descriptor_calls.calls.entries.items[index].function) orelse return self.unsupported(m, body.root);
    }
    fn resultOwnerDescriptor(value: Value, ordinal: usize) ?Value {
        if (value.variant_tags.len != 0) return null;
        if (value.tag == .array and value.root == ordinal and value.other_roots.len == 0) return value;
        for (value.fields) |field| if (resultOwnerDescriptor(field, ordinal)) |found| return found;
        return null;
    }
    fn importReturnedOwners(self: *Generator, plan: *const CheckedFunctionPlan, result: Value, inputs: []const usize) Error!Value {
        if (plan.returned_owners.len == 0) return self.graphCallerShape(result, inputs);
        const roles = try self.arena.allocator().alloc(usize, inputs.len + plan.returned_owners.len);
        @memcpy(roles[0..inputs.len], inputs);
        for (plan.returned_owners, roles[inputs.len..], 0..) |summary, *role, index| {
            const descriptor = resultOwnerDescriptor(result, inputs.len + index) orelse return error.Declined;
            role.* = self.roots.items.len;
            try self.roots.append(self.allocator, .{ .word = descriptor.word, .token = descriptor.token, .epoch_low = descriptor.epoch_low, .epoch_high = descriptor.epoch_high, .stack = self.fixed_region, .depth = self.depth, .element = summary.element, .element_initialized = summary.element_initialized, .known_empty = summary.known_empty, .frozen = summary.frozen, .dedicated = false });
        }
        self.emission_work.scoped_transferred_result_owners +|= plan.returned_owners.len;
        return self.graphCallerShape(result, roles);
    }
    fn replayInvariant(self: *Generator, m: *const core.Module, id: core.Id, footprint: []const recursive_admission.Access, owners: []const usize) Error!void {
        if (footprint.len != owners.len) return error.Declined;
        for (footprint, owners) |access, owner_id| {
            if (!access.read and !access.write) continue;
            const owner = &self.roots.items[owner_id];
            if (!owner.live or (!owner.element_initialized and !owner.known_empty)) return self.fail(m, id, .storage_escape, "Recursive access requires initialized live input owners");
            if (owner.element.tag != .scalar or owner.element.floating or owner.element.fields.len != 0 or owner.element.root != null) return error.Declined;
            const value: Value = .{ .tag = .array, .word = owner.word, .root = owner_id };
            if (access.read) {
                try self.registerShapeRead(value);
                try self.writerEvent(m, id, value, .read);
            }
            if (access.write) {
                if (owner.frozen) return self.fail(m, id, .storage_escape, "Recursive writes cannot modify a frozen input owner");
                try self.clearWriterLiterals(&owner.element);
                // A possible write does not establish initialization or rows.
                try self.writerAccess(m, id, value, .write, false);
            }
        }
    }
    fn recursiveCall(self: *Generator, m: *const core.Module, target: core.BindingRef, arguments: []const Value) Error!?Value {
        const admission = &self.descriptor_calls.recursion;
        const discovery_bodies = admission.discovery_bodies;
        const discovery_nodes = admission.discovery_nodes;
        const scans = admission.scans;
        const nodes = admission.nodes;
        defer {
            self.emission_work.scoped_recursive_discovery_bodies +|= admission.discovery_bodies - discovery_bodies;
            self.emission_work.scoped_recursive_discovery_nodes +|= admission.discovery_nodes - discovery_nodes;
            self.emission_work.scoped_recursive_admission_scans +|= admission.scans - scans;
            self.emission_work.scoped_recursive_admission_nodes +|= admission.nodes - nodes;
        }
        const contract = (try admission.analyze(self.allocator, self.units, target)) orelse return null;
        if (!contract.self_recursive or contract.parameter_access.len != arguments.len) return null;
        const body = m.body(target.binding) orelse return null;
        // A provisional header belongs only to its checked direct self edge.
        if (self.recursive_header) |header| if (std.meta.eql(header.target, target)) {
            const frames = self.active_calls.frames.items;
            if (frames.len == 0 or frames[frames.len - 1].target.kind != .named or frames[frames.len - 1].target.unit != target.unit or frames[frames.len - 1].target.id != target.binding or self.c.function != header.plan.entry.function) return self.fail(m, body.root, .storage_unsupported, "Only a direct checked self edge can use a recursive header");
            for (arguments, header.parameter_owners) |argument, role| {
                if (role == std.math.maxInt(u32)) {
                    if (argument.tag != .scalar or argument.floating or argument.root != null or argument.fields.len != 0) return error.Declined;
                } else if (argument.tag != .array or argument.mode != .fixed or argument.root != role or argument.other_roots.len != 0) return self.fail(m, body.root, .storage_unsupported, "Recursive calls must preserve formal input owner correspondence");
            }
            const footprint = header.plan.access.invariant;
            const owners = try self.arena.allocator().alloc(usize, footprint.len);
            for (owners, 0..) |*owner, ordinal| owner.* = ordinal;
            self.emission_work.scoped_recursive_backedges +|= 1;
            return try self.emitPlannedCall(m, body, header.plan, arguments, owners);
        };
        var graph = OwnerGraph.init(self.allocator, self.roots.items, arguments) catch |err| {
            if (err == error.OutOfMemory) return err;
            return null;
        };
        defer graph.deinit();
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 18, @intCast(arguments.len), @intCast(graph.owners.items.len) });
        var words: usize = 0;
        for (arguments) |argument| {
            if (argument.callable != null or argument.host != null or argument.fields.len != 0 or argument.variant_tags.len != 0 or argument.other_roots.len != 0) return null;
            if (argument.tag == .scalar) {
                if (argument.floating or argument.root != null) return null;
                try evidence.append(self.allocator, std.math.maxInt(u32));
            } else if (argument.tag == .array and argument.mode == .fixed and argument.root != null) {
                const ordinal = try graph.ordinal(argument.root.?);
                try evidence.append(self.allocator, @intCast(ordinal));
            } else return null;
            words += readerWords(argument);
        }
        if (words > 512) return null;
        for (graph.owners.items) |owner_id| {
            const owner = self.roots.items[owner_id];
            if (!owner.live) return self.fail(m, body.root, .storage_escape, "Recursive calls require live input owners");
            if (owner.element.tag != .scalar or owner.element.floating or owner.element.fields.len != 0 or owner.element.root != null) return null;
            try evidence.append(self.allocator, @intFromBool(owner.frozen));
        }
        const created_receipts = try self.createdReceipts(arguments, &graph, &evidence);
        const key: call_plan.Key = .{ .unit = target.unit, .binding = target.binding, .context = self.invocationContext(), .evidence = evidence.items };
        if (self.descriptor_calls.calls.find(key)) |index| {
            const entry = self.descriptor_calls.calls.entries.items[index];
            if (entry.building) return self.fail(m, body.root, .storage_unsupported, "A recursive header cannot escape its construction transaction");
            const plan = self.descriptor_calls.plans.get(entry.function) orelse return error.Declined;
            return try self.emitPlannedCall(m, body, plan, arguments, graph.owners.items);
        }
        const request: FunctionPlanInput = .{ .module = m, .target = target, .arguments = arguments, .owners = graph.owners.items, .graph = &graph, .words = words, .input_aliases = &.{}, .addressed = false, .capture_globals = false, .unit_result = true, .result_shape = .{ .word = .{ .id = 0 } }, .shared = true, .recursive = contract, .created_receipts = created_receipts, .key = key };
        const index = (try self.tryFunctionPlan(request)) orelse {
            self.emission_work.scoped_recursive_declines +|= 1;
            return self.fail(m, body.root, .storage_unsupported, "The recursive body does not satisfy its fixed-owner contract");
        };
        const plan = self.descriptor_calls.plans.get(self.descriptor_calls.calls.entries.items[index].function) orelse return error.Declined;
        return try self.emitPlannedCall(m, body, plan, arguments, graph.owners.items);
    }
    fn emitPlannedCall(self: *Generator, m: *const core.Module, body: *const core.Body, plan: *const CheckedFunctionPlan, arguments: []const Value, owners: []const usize) Error!Value {
        self.emission_work.scoped_function_plan_emissions +|= 1;
        const emitting_before = self.emitting_function_plan;
        self.emitting_function_plan = true;
        defer self.emitting_function_plan = emitting_before;
        const entry = plan.entry;
        const words = plan.input_words;
        const unit_result = plan.unit_result;
        self.noteCalleeContext(entry);
        // Replay the actual compiler access order even on cache hits. Caller
        // loop scopes see the same row shapes as expanded selected bodies.
        if (plan.access == .invariant) {
            try self.replayInvariant(m, body.root, plan.access.invariant, owners);
            self.emission_work.scoped_recursive_calls +|= 1;
        } else {
            for (plan.access.ordered) |event| {
                const owner_id = owners[event.owner];
                var shape_ = event.shape;
                shape_ = try self.graphCallerShape(shape_, owners);
                if (event.kind == .write) {
                    const owner = &self.roots.items[owner_id];
                    try self.storedShape(m, body.root, &owner.element, shape_, owner.depth);
                    if (event.initializes_rows) {
                        owner.element_initialized = true;
                        owner.known_empty = false;
                    } else {
                        try self.clearWriterLiterals(&owner.element);
                    }
                } else {
                    const owner = self.roots.items[owner_id];
                    if (!includesReadShape(shape_, owner.element) or !includesReadShape(owner.element, shape_)) return self.fail(m, body.root, .storage_escape, "A writer call must preserve its checked read and mutation shape order");
                    try self.registerShapeRead(.{ .tag = .array, .word = owner.word, .root = owner_id });
                }
                const replay: Value = .{ .tag = .array, .word = self.roots.items[owner_id].word, .root = owner_id };
                try self.writerAccess(m, body.root, replay, event.kind, event.initializes_rows);
            }
        }
        for (plan.regions) |region| {
            try self.used_regions.put(self.allocator, region, {});
            self.max_stacks = @max(self.max_stacks, @as(u32, @intCast(region + 1)));
        }
        if (plan.abi != .buffered) return self.callOwnedWords(m, body.root, plan, arguments, owners);
        self.emission_work.scoped_owned_packed_calls +|= 1;
        const first_root = self.roots.items.len;
        const mark = try self.frameMark();
        const result_template = plan.result;
        var total_words = words;
        if (!unit_result and result_template.tag != .scalar) {
            total_words = std.math.add(usize, words, readerWords(result_template)) catch return self.unsupported(m, body.root);
        }
        const count = std.math.cast(u32, @max(1, total_words)) orelse return self.unsupported(m, body.root);
        const slot = try self.arrayWithShape(m, body.root, (try self.constant(count)).word, .fixed, .{ .word = .{ .id = 0 } });
        const address = try self.c.temp();
        try self.c.set(address, .{ .call, self.runtime.functions.address, slot.token, slot.epoch_low, slot.epoch_high, slot.word, 0 });
        std.debug.assert(plan.used_input_words.len == words);
        var offset: u32 = 0;
        for (arguments) |argument| {
            try self.storeReaderResultMasked(address, offset, argument, plan.used_input_words);
            offset += @intCast(readerWords(argument) * 4);
        }
        try self.c.value(address);
        try self.c.op(.call, entry.function);
        const word = try self.c.temp();
        try self.c.op(.local_set, word.id);
        var returned: Value = .{ .word = word, .floating = entry.floating };
        if (!unit_result and result_template.tag != .scalar) {
            returned = try self.loadPlannedResult(address, @intCast(words * 4), result_template, plan.result_aliases, arguments);
            returned = try self.importReturnedOwners(plan, returned, owners);
        }
        try self.release(first_root, returned);
        try self.rewindUnescaped(first_root, mark, returned);
        returned.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = T.unit }, .arguments = &.{} });
        if (!unit_result) returned.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = m.typeOf(body.root) }, .arguments = try self.captureTypes() });
        return returned;
    }
    fn loadPlannedResult(self: *Generator, address: Local, offset: u32, template: Value, aliases: []const u32, arguments: []const Value) Error!Value {
        if (aliases.len == 0) return self.loadReaderResult(address, offset, template);
        var inputs: std.ArrayList(Local) = .empty;
        defer inputs.deinit(self.allocator);
        for (arguments) |argument| try self.readerWordLocals(argument, &inputs);
        var ordinal: usize = 0;
        const result = try self.loadReaderResultAliased(address, offset, template, aliases, inputs.items, &ordinal);
        std.debug.assert(ordinal == aliases.len);
        return result;
    }
    fn fullyAliasedResult(aliases: []const u32) bool {
        if (aliases.len == 0) return false;
        for (aliases) |alias| if (alias == @import("storage_result_alias.zig").absent) return false;
        return true;
    }
    // Cache only straight-line snapshots whose exact source locals have not
    // changed. Region rewind and runtime close are lifetime barriers even when
    // the compile-time Root remains live along another control-flow path.
    fn scanBundleSnapshots(self: *Generator) void {
        const instructions = self.module.functions.items[self.c.function].instructions.items;
        if (self.bundle_function != self.c.function) {
            self.bundle_snapshots.clearRetainingCapacity();
            self.bundle_sources.clearRetainingCapacity();
            self.bundle_retained_bytes = 0;
            self.bundle_retained_count = 0;
            self.bundle_function = self.c.function;
            self.bundle_scan = instructions.len;
            return;
        }
        if (self.bundle_scan > instructions.len) {
            self.bundle_snapshots.clearRetainingCapacity();
            self.bundle_sources.clearRetainingCapacity();
            self.bundle_scan = instructions.len;
            return;
        }
        var barrier = false;
        for (instructions[self.bundle_scan..]) |inst| {
            switch (inst.op) {
                .block, .loop, .if_, .else_, .end, .br, .br_if, .return_, .unreachable_ => barrier = true,
                .local_set, .local_tee => if (self.bundle_sources.contains(inst.operand)) {
                    barrier = true;
                },
                .call => if (inst.operand == self.runtime.functions.rewind or inst.operand == self.runtime.functions.close) {
                    barrier = true;
                },
                else => {},
            }
        }
        if (barrier) {
            self.bundle_snapshots.clearRetainingCapacity();
            self.bundle_sources.clearRetainingCapacity();
        }
        self.bundle_scan = instructions.len;
    }
    const BundleRange = struct { bundle: usize, offset: usize };
    fn inputBundleRange(self: *const Generator, words: []const Local) ?BundleRange {
        if (words.len == 0) return null;
        for (self.input_bundles, 0..) |bundle, index| {
            if (words[0].id < bundle.first) continue;
            const offset = words[0].id - bundle.first;
            if (offset >= bundle.words or words.len > bundle.words - offset) continue;
            var exact = true;
            for (words, 0..) |word, ordinal| if (word.id != bundle.first + offset + ordinal) {
                exact = false;
                break;
            };
            if (exact) return .{ .bundle = index, .offset = offset };
        }
        return null;
    }
    fn forwardedBundle(self: *Generator, words: []const Local, used: []const bool) Error!?Local {
        const range = self.inputBundleRange(words) orelse return null;
        const bundle = self.input_bundles[range.bundle];
        for (used, 0..) |needed, index| if (needed) {
            bundle.needed[range.offset + index] = true;
            self.emission_work.scoped_addressed_forwarded_words +|= 1;
        };
        const pointer: Local = .{ .id = bundle.parameter };
        if (range.offset == 0) return pointer;
        const adjusted = try self.c.temp();
        try self.c.set(adjusted, .{ .i32_add, pointer, range.offset * 4 });
        return adjusted;
    }
    fn cachedBundle(self: *Generator, words: []const Local, used: []const bool) ?Local {
        self.scanBundleSnapshots();
        for (self.bundle_snapshots.items) |saved| {
            if (saved.function != self.c.function or !self.roots.items[saved.root].live or words.len != saved.words.len) continue;
            var complete = true;
            for (words, saved.words) |word, original| if (word.id != original.id) {
                complete = false;
                break;
            };
            for (used, saved.used) |needed, stored| if (needed and !stored) {
                complete = false;
                break;
            };
            if (complete) {
                for (used) |needed| if (needed) {
                    self.emission_work.scoped_addressed_cached_words +|= 1;
                };
                return saved.address;
            }
        }
        return null;
    }
    fn snapshotBundle(self: *Generator, m: *const core.Module, id: core.Id, words: []const Local, used: []const bool, retain: bool) Error!Local {
        const count = std.math.cast(u32, @max(1, words.len)) orelse return self.unsupported(m, id);
        const slot = try self.arrayWithShape(m, id, (try self.constant(count)).word, .fixed, .{ .word = .{ .id = 0 } });
        const address = try self.c.temp();
        try self.c.set(address, .{ .call, self.runtime.functions.address, slot.token, slot.epoch_low, slot.epoch_high, slot.word, 0 });
        for (words, used, 0..) |word, needed, ordinal| if (needed) {
            try self.c.store(address, @intCast(ordinal * 4), word);
            self.emission_work.scoped_addressed_snapshot_words +|= 1;
        };
        if (retain) {
            self.scanBundleSnapshots();
            const saved = try self.arena.allocator().dupe(Local, words);
            const mask = try self.arena.allocator().dupe(bool, used);
            try self.bundle_snapshots.append(self.allocator, .{ .function = self.c.function, .root = slot.root.?, .address = address, .words = saved, .used = mask });
            for (words) |word| try self.bundle_sources.put(self.allocator, word.id, {});
            try self.bundle_sources.put(self.allocator, address.id, {});
            try self.bundle_sources.put(self.allocator, slot.token.id, {});
            self.bundle_retained_bytes += words.len * 4 + storage.header_bytes;
            self.bundle_retained_count += 1;
            self.emission_work.scoped_addressed_retained_bytes_max = @max(self.emission_work.scoped_addressed_retained_bytes_max, self.bundle_retained_bytes);
            self.emission_work.scoped_addressed_retained_slots_max = @max(self.emission_work.scoped_addressed_retained_slots_max, self.bundle_retained_count);
        }
        return address;
    }
    fn callAddressedWords(self: *Generator, m: *const core.Module, id: core.Id, plan: *const CheckedFunctionPlan, arguments: []const Value, owners: []const usize) Error!Value {
        self.emission_work.scoped_addressed_calls +|= 1;
        var words: std.ArrayList(Local) = .empty;
        defer words.deinit(self.allocator);
        for (arguments) |argument| try self.readerWordLocals(argument, &words);
        std.debug.assert(words.items.len == plan.input_words and plan.used_input_words.len == words.items.len);
        const addresses = try self.arena.allocator().alloc(?Local, arguments.len);
        @memset(addresses, null);
        var ordinal: usize = 0;
        var ephemeral = false;
        for (arguments, plan.addressed_arguments, addresses) |argument, by_address, *address| {
            const count = readerWords(argument);
            const input = words.items[ordinal..][0..count];
            const used = plan.used_input_words[ordinal..][0..count];
            ordinal += count;
            if (!by_address) continue;
            address.* = try self.forwardedBundle(input, used);
            if (address.* == null) address.* = self.cachedBundle(input, used);
            if (address.* == null) {
                const bytes = count * 4 + storage.header_bytes;
                if (self.bundle_retained_count < 8 and bytes <= 32 * 1024 - self.bundle_retained_bytes) {
                    address.* = try self.snapshotBundle(m, id, input, used, true);
                } else ephemeral = true;
            }
        }
        // Reusable snapshots precede all call scratch storage. Capped snapshots
        // are one-call allocations and reclaim through the ordinary owner path.
        const first_root = self.roots.items.len;
        var mark: ?FrameMark = null;
        const template = plan.result;
        const result_slot = template.tag != .scalar and plan.return_registers == 0;
        const forwarded_result = result_slot and fullyAliasedResult(plan.result_aliases);
        if (ephemeral or (result_slot and !forwarded_result)) mark = try self.frameMark();
        ordinal = 0;
        for (arguments, plan.addressed_arguments, addresses) |argument, by_address, *address| {
            const count = readerWords(argument);
            if (by_address and address.* == null) address.* = try self.snapshotBundle(m, id, words.items[ordinal..][0..count], plan.used_input_words[ordinal..][0..count], false);
            ordinal += count;
        }
        var output: ?Local = null;
        if (result_slot and !forwarded_result) {
            const count = std.math.cast(u32, @max(1, readerWords(template))) orelse return self.unsupported(m, id);
            const slot = try self.arrayWithShape(m, id, (try self.constant(count)).word, .fixed, .{ .word = .{ .id = 0 } });
            const pointer = try self.c.temp();
            try self.c.set(pointer, .{ .call, self.runtime.functions.address, slot.token, slot.epoch_low, slot.epoch_high, slot.word, 0 });
            output = pointer;
        }
        ordinal = 0;
        for (arguments, plan.addressed_arguments, addresses) |argument, by_address, address| {
            if (by_address) try self.c.value(address.?) else try self.readerValues(argument);
            ordinal += readerWords(argument);
        }
        if (result_slot) try self.c.value(output orelse (try self.unitValue()).word);
        try self.c.op(.call, plan.entry.function);
        const word = try self.c.temp();
        try self.c.op(.local_set, word.id);
        var returned: Value = .{ .word = word, .floating = plan.entry.floating };
        if (plan.return_registers != 0) {
            var results: [4]Local = undefined;
            results[0] = word;
            for (1..plan.return_registers) |index| {
                results[index] = try self.c.temp();
                try self.c.set(results[index], .{ .global, self.runtime.inline_returns[index - 1] });
            }
            var next: usize = 0;
            returned = try self.inlineReturnValue(template, results[0..plan.return_registers], &next);
        } else if (forwarded_result) {
            returned = try self.loadPlannedResult(.{ .id = 0 }, 0, template, plan.result_aliases, arguments);
            self.emission_work.scoped_result_slots_avoided +|= 1;
        } else if (output) |pointer| returned = try self.loadPlannedResult(pointer, 0, template, plan.result_aliases, arguments);
        if (!plan.unit_result) returned = try self.importReturnedOwners(plan, returned, owners);
        if (mark) |saved| {
            try self.release(first_root, returned);
            try self.rewindUnescaped(first_root, saved, returned);
        }
        returned.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = T.unit }, .arguments = &.{} });
        if (!plan.unit_result) returned.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = m.typeOf(id) }, .arguments = try self.captureTypes() });
        return returned;
    }
    fn callOwnedWords(self: *Generator, m: *const core.Module, id: core.Id, plan: *const CheckedFunctionPlan, arguments: []const Value, owners: []const usize) Error!Value {
        if (plan.addressed_arguments.len != 0) return self.callAddressedWords(m, id, plan, arguments, owners);
        const entry = plan.entry;
        const template = plan.result;
        const words = plan.input_words;
        const unit_result = plan.unit_result;
        const return_registers = plan.return_registers;
        const result_aliases = plan.result_aliases;
        const used = plan.used_input_words;
        self.emission_work.scoped_owned_word_calls +|= 1;
        self.emission_work.scoped_owned_argument_words_avoided +|= words;
        const first_root = self.roots.items.len;
        var mark: ?FrameMark = null;
        var address: ?Local = null;
        const result_slot = template.tag != .scalar and return_registers == 0;
        const forwarded_result = result_slot and fullyAliasedResult(result_aliases);
        if (forwarded_result) self.emission_work.scoped_result_slots_avoided +|= 1;
        if (result_slot and !forwarded_result) {
            mark = try self.frameMark();
            const count = std.math.cast(u32, @max(1, readerWords(template))) orelse return self.unsupported(m, id);
            const slot = try self.arrayWithShape(m, id, (try self.constant(count)).word, .fixed, .{ .word = .{ .id = 0 } });
            const pointer = try self.c.temp();
            try self.c.set(pointer, .{ .call, self.runtime.functions.address, slot.token, slot.epoch_low, slot.epoch_high, slot.word, 0 });
            address = pointer;
        }
        var logical_words = words + @intFromBool(result_slot);
        if (plan.result_pointer_first) logical_words = words + 1;
        std.debug.assert(used.len == 0 or used.len == logical_words);
        var ordinal: usize = 0;
        if (plan.result_pointer_first) {
            if (forwarded_result or !result_slot) std.debug.assert(!used[0]);
            if (result_slot) try self.readerInputWord(address orelse (try self.unitValue()).word, used, &ordinal) else ordinal = 1;
        } else if (forwarded_result and used.len != 0) std.debug.assert(!used[words]);
        for (arguments) |argument| try self.readerValuesMasked(argument, used, &ordinal);
        std.debug.assert(ordinal == words + @intFromBool(plan.result_pointer_first));
        if (result_slot and !plan.result_pointer_first) {
            const pointer = address orelse (try self.unitValue()).word;
            try self.readerInputWord(pointer, used, &ordinal);
        }
        try self.c.op(.call, entry.function);
        const word = try self.c.temp();
        try self.c.op(.local_set, word.id);
        var returned: Value = .{ .word = word, .floating = entry.floating };
        if (return_registers != 0) {
            var results: [4]Local = undefined;
            results[0] = word;
            for (1..return_registers) |index| {
                results[index] = try self.c.temp();
                try self.c.set(results[index], .{ .global, self.runtime.inline_returns[index - 1] });
            }
            var next: usize = 0;
            returned = try self.inlineReturnValue(template, results[0..return_registers], &next);
            std.debug.assert(next == return_registers);
            self.emission_work.scoped_function_plan_register_calls +|= 1;
            self.emission_work.scoped_inline_register_calls +|= 1;
            self.emission_work.scoped_inline_result_owners_avoided +|= 1;
            self.emission_work.scoped_inline_result_roots_avoided +|= 1;
            self.emission_work.scoped_inline_result_bytes_avoided +|= storage.header_bytes + try width(template);
        } else if (forwarded_result) {
            // Every word comes from an actual argument; no address is read.
            returned = try self.loadPlannedResult(.{ .id = 0 }, 0, template, result_aliases, arguments);
        } else if (address) |pointer| returned = try self.loadPlannedResult(pointer, 0, template, result_aliases, arguments);
        if (!unit_result) returned = try self.importReturnedOwners(plan, returned, owners);
        if (mark) |saved| {
            try self.release(first_root, returned);
            try self.rewindUnescaped(first_root, saved, returned);
        }
        returned.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = T.unit }, .arguments = &.{} });
        if (!unit_result) returned.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = m.typeOf(id) }, .arguments = try self.captureTypes() });
        return returned;
    }
    fn selectedCallbacks(self: *Generator, m: *const core.Module, id: core.Id, value: Value, path: *std.ArrayList(u32), selection: *std.ArrayList(u32), remaining: *usize, depth: usize) Error!void {
        if (remaining.* == 0 or depth > 128) return self.fail(m, id, .storage_unsupported, "The static callback selection tree exceeds the supported bound");
        remaining.* -= 1;
        if (value.callable) |callable| {
            try selection.append(self.allocator, @intCast(path.items.len));
            try selection.appendSlice(self.allocator, path.items);
            try selection.appendSlice(self.allocator, &.{ callable.unit, callable.target, callable.node });
        }
        if (value.tag != .aggregate and value.callable == null) return;
        for (value.fields, 0..) |field, index| {
            const before = path.items.len;
            if (field.name.len != 0) {
                try path.appendSlice(self.allocator, &.{ 1, @intCast(field.name.len) });
                for (field.name) |byte| try path.append(self.allocator, byte);
            } else try path.appendSlice(self.allocator, &.{ 0, @intCast(index) });
            try self.selectedCallbacks(m, id, field, path, selection, remaining, depth + 1);
            path.shrinkRetainingCapacity(before);
        }
    }
    fn selectedArguments(self: *Generator, m: *const core.Module, id: core.Id, captures: []const Value, arguments: []const Value, selection: *std.ArrayList(u32)) Error!void {
        var path: std.ArrayList(u32) = .empty;
        defer path.deinit(self.allocator);
        var remaining: usize = 4096;
        for ([_][]const Value{ captures, arguments }, 0..) |values, group| for (values, 0..) |value, index| {
            path.clearRetainingCapacity();
            try path.appendSlice(self.allocator, &.{ @intCast(group), @intCast(index) });
            try self.selectedCallbacks(m, id, value, &path, selection, &remaining, 0);
        };
    }
    fn selectedType(self: *Generator, m: *const core.Module, id: core.Id, input: TypeRef, selection: *std.ArrayList(u32), keys: *selected_types.Builder, depth: usize) Error!void {
        const result = self.selectedTypeNode(m, id, input, keys, depth) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Declined => error.Declined,
            error.Cycle => self.fail(m, id, .storage_unsupported, "Cyclic selected call types cannot form a structural key"),
            error.Limit => self.fail(m, id, .storage_unsupported, "The selected call type exceeds the supported bound"),
        };
        keys.root(selection, result) catch |err| return self.selectedKeyError(m, id, err);
    }
    fn selectedKeyError(self: *Generator, m: *const core.Module, id: core.Id, err: selected_types.Error) Error {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Cycle => self.fail(m, id, .storage_unsupported, "Cyclic selected call types cannot form a structural key"),
            error.Limit => self.fail(m, id, .storage_unsupported, "The selected call key exceeds its encoded-word or construction-work bound"),
        };
    }
    fn finishSelectedTypes(self: *Generator, m: *const core.Module, id: core.Id, selection: *std.ArrayList(u32), keys: *selected_types.Builder) Error!void {
        keys.finish(selection) catch |err| return self.selectedKeyError(m, id, err);
    }
    fn selectedTypeChild(self: *Generator, m: *const core.Module, id: core.Id, input: TypeRef, descriptor: usize, keys: *selected_types.Builder, depth: usize, height: *usize) (Error || selected_types.Error)!void {
        const child = try self.selectedTypeNode(m, id, input, keys, depth + 1);
        try keys.descriptorWord(descriptor, child.id);
        height.* = @max(height.*, child.height + 1);
    }
    fn selectedTypeNode(self: *Generator, m: *const core.Module, id: core.Id, input: TypeRef, keys: *selected_types.Builder, depth: usize) (Error || selected_types.Error)!selected_types.Result {
        if (self.emitting_function_plan) self.emission_work.scoped_function_plan_post_type_queries +|= 1;
        if (keys.remaining.* == 0 or depth > 128) return error.Limit;
        const actual = try self.resolveType(input, 0);
        var reference: selected_types.Reference = .{
            .unit = actual.unit,
            .ty = actual.ty,
            .environment = if (actual.environment) |environment| @intFromPtr(environment.ptr) else 0,
            .environment_len = if (actual.environment) |environment| environment.len else 0,
            .captured = actual.environment != null,
        };
        // Only the private builder memo is canonicalized. Primitive descriptor
        // bytes have no unit/environment; semantic witnesses keep both.
        if (actual.ty >= T.unit and actual.ty <= T.never) reference = .{ .unit = 0, .ty = actual.ty };
        if (try keys.enter(reference, depth)) |completed| return completed;
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        const descriptor = keys.beginDescriptor();
        defer keys.endDescriptor(descriptor);
        var height: usize = 0;
        try keys.descriptorWord(descriptor, @backingInt(node.tag));
        switch (node.tag) {
            .array, .list, .cursor, .resolver, .provider => try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, descriptor, keys, depth, &height),
            .usage => {
                try keys.descriptorWord(descriptor, node.b);
                try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, descriptor, keys, depth, &height);
                try keys.descriptorWord(descriptor, @intFromBool(node.c != 0));
                if (node.c != 0) try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.c, .environment = actual.environment }, descriptor, keys, depth, &height);
            },
            .function => {
                try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, descriptor, keys, depth, &height);
                try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.b, .environment = actual.environment }, descriptor, keys, depth, &height);
                // Retain the existing exact checked row-carrier identity.
                try keys.descriptorWords(descriptor, &.{ if (node.c == 0) 0 else actual.unit, node.c });
            },
            .product, .nominal => {
                if (node.tag == .nominal) try keys.descriptorWords(descriptor, &.{ node.a, node.b });
                const children = if (node.tag == .product) owner.types.list(.{ .start = node.a, .len = node.b }) else owner.types.nominalArguments(node);
                try keys.descriptorWord(descriptor, @intCast(children.len));
                for (children) |child| try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = child, .environment = actual.environment }, descriptor, keys, depth, &height);
            },
            .record => {
                // Keys follow semantic field order, just as inline words do.
                // Bound both ordinal count and name bytes before sorting.
                if (node.b > keys.remaining.*) return error.Limit;
                const metadata = try self.descriptor_calls.record_metadata.get(owner, actual.ty, node, keys.options.encoded_words, keys.word_work);
                try keys.descriptorWord(descriptor, node.b);
                for (metadata.fields) |field| {
                    if (field.spelling) |name| {
                        try keys.descriptorWord(descriptor, @intCast(name.len));
                        for (name) |byte| try keys.descriptorWord(descriptor, byte);
                    } else try keys.descriptorWords(descriptor, &.{ std.math.maxInt(u32), actual.unit, field.symbol });
                    try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = field.ty, .environment = actual.environment }, descriptor, keys, depth, &height);
                }
            },
            .unit, .boolean, .u32, .f32, .never => {},
            // Abstract roles keep their source identity and correlation.
            else => try keys.descriptorWords(descriptor, &.{ actual.unit, actual.ty }),
        }
        return keys.completeDescriptor(reference, descriptor, height);
    }
    fn invocationContext(self: *const Generator) u32 {
        return if (self.specialization_origin) |origin| origin.unit else 0;
    }
    fn invocationOrigin(self: *const Generator, m: *const core.Module, id: core.Id) ?evaluation.SourceLocation {
        return evaluation.sourceInvocationOrigin(self.specialization_origin, self.entry_unit, m.unit, m.span(id), evaluation.callerDependentUse(m, id));
    }
    fn invokeAt(self: *Generator, m: *const core.Module, id: core.Id, target: core.BindingRef, arguments: []const Value, depth: usize) Error!Value {
        const previous = self.specialization_origin;
        self.specialization_origin = self.invocationOrigin(m, id);
        defer self.specialization_origin = previous;
        return self.invoke(target, arguments, depth);
    }
    fn invoke(self: *Generator, target: core.BindingRef, arguments: []const Value, depth: usize) Error!Value {
        return self.invokeBody(target, arguments, depth, true);
    }
    fn checkSourceBody(self: *Generator, m: *const core.Module, body: *const core.Body, binding_id: core.BindingId) Error!void {
        var origin: ?@import("../check/scheme_equations.zig").SourceFailure = null;
        source_proof.checkedInterfaceBodyCached(self.proof_cache, m, binding_id, self.validation_budget, &origin, null) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (self.proof_cache.exhaustedUnit()) |exhausted| {
                self.diagnostic = .{ .unit = exhausted, .span = if (origin) |failure| failure.span else .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Source module storage validation exceeded its checked work budget" };
                return error.Declined;
            }
            if (self.validation_budget.* == 0) return self.fail(m, body.root, .storage_unsupported, "Source storage validation exceeded its checked work budget");
            if (origin) |failure| {
                self.diagnostic = .{ .unit = failure.unit, .span = failure.span, .code = .storage_unsupported, .detail = "The scoped body lacks complete type evidence" };
                return error.Declined;
            }
            return self.fail(m, body.root, .storage_unsupported, "The scoped body lacks complete type evidence");
        };
    }
    // Definitions bypass their own registry entry. Reached calls still share
    // scalar definitions across generators; owner-bearing ABIs remain local.
    fn invokeBody(self: *Generator, target: core.BindingRef, arguments: []const Value, depth: usize, reuse: bool) Error!Value {
        const m = try self.unit(target.unit);
        const body = m.body(target.binding) orelse return error.Declined;
        const parameters = m.bodyParameters(body);
        const selected_target: call_plan.ActiveCalls.Target = .{ .unit = m.unit, .id = target.binding, .kind = .named, .context = self.invocationContext() };
        var selected: std.ArrayList(u32) = .empty;
        defer selected.deinit(self.allocator);
        try self.checkSourceBody(m, body, target.binding);
        if (parameters.len == 0 and m.node(body.root).tag == .primitive_function) {
            var function = try self.expression(m, body.root, depth + 1);
            for (arguments) |argument| function = try self.applyUse(m, body.root, function, argument, depth + 1, .{ .checked = false });
            return function;
        }
        if (arguments.len < parameters.len) {
            if (depth > 128) return self.unsupported(m, body.root);
            const fields = try self.arena.allocator().alloc(Value, arguments.len);
            for (fields, arguments) |*field, argument| field.* = try self.snapshot(argument);
            return .{ .tag = .callable, .word = (try self.unitValue()).word, .callable = try self.boxCallable(.{ .unit = m.unit, .target = target.binding, .types = try self.captureTypes() }), .fields = fields };
        }
        if (arguments.len > parameters.len) {
            if (depth > 128) return self.unsupported(m, body.root);
            var function = try self.invoke(target, arguments[0..parameters.len], depth + 1);
            for (arguments[parameters.len..]) |argument| function = try self.applyUse(m, body.root, function, argument, depth + 1, .{ .checked = false });
            return function;
        }
        for (parameters, arguments) |parameter, value| {
            const formal: TypeRef = .{ .unit = m.unit, .ty = parameter.ty };
            if (try self.callableType(value)) |signature| {
                try self.mapTypesUnder(formal, signature, value.callable.?.types, 0);
            } else try self.mapValueTypes(formal, value, 0);
        }
        const previous_goals = self.active_goals;
        self.active_goals = m.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len];
        defer self.active_goals = previous_goals;
        try self.refineFields(m, self.active_goals);
        if (reuse) if (try self.recursiveCall(m, target, arguments)) |result| return result;
        try self.selectedArguments(m, body.root, &.{}, arguments, &selected);
        const public = m.types.list(m.binding(target.binding).public_variables);
        try selected.appendSlice(self.allocator, &.{ std.math.maxInt(u32), @intCast(public.len) });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (public) |parameter| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter }, &selected, &type_key, 0);
        try self.finishSelectedTypes(m, body.root, &selected, &type_key);
        if (self.active_calls.contains(selected_target, selected.items)) return self.fail(m, body.root, .storage_unsupported, "Recursive selected calls are not supported by the owned-storage backend");
        if (self.active_calls.frames.items.len >= 128) return self.fail(m, body.root, .storage_unsupported, "Selected calls exceeded their active call bound");
        if (reuse) {
            const prepared = try self.projectedArguments(m, body, arguments);
            if (try self.prepareFunctionCall(m, target, prepared.values)) |candidate| {
                var call = candidate;
                defer call.deinit(self.allocator);
                if (try self.getOrBuildFunctionPlan(m, target, &call)) |plan| {
                    self.commitPreparedArguments(prepared, .owned);
                    return self.emitPlannedCall(m, body, plan, prepared.values, call.graph.owners.items);
                }
            }
            if (prepared.fields_omitted != 0) self.emission_work.scoped_argument_projection_discards +|= 1;
        }
        // A reusable definition's child enters while compiling its body. Do
        // not enter twice merely because planning moved to another Generator.
        if (!try self.active_calls.enter(selected_target, selected.items)) return self.fail(m, body.root, .storage_unsupported, "Recursive selected calls are not supported by the owned-storage backend");
        defer self.active_calls.leave();
        const first_root = self.roots.items.len;
        const outline_ticket = self.outlining.begin(self.c.function, .{ .expressions = self.steps, .layouts = self.layout_steps });
        const mark = try self.frameMark();
        const uses = @import("storage_liveness.zig").count(self.allocator, m, body.root) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, body.root);
        };
        defer self.allocator.free(uses);
        const previous_uses = self.uses;
        self.uses = uses;
        defer self.uses = previous_uses;
        const before = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(before);
        self.depth += 1;
        defer self.depth -= 1;
        for (parameters, arguments) |parameter, value| try self.bind(m, parameter.binding, value);
        var result = try self.expression(m, body.root, 0);
        try self.escape(m, body.root, &result, self.depth);
        try self.release(first_root, result);
        try self.rewindUnescaped(first_root, mark, result);
        if (outline_ticket) |ticket| {
            const credit = self.outlining.tryExtract(ticket, .{ .expressions = self.steps, .layouts = self.layout_steps }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.fail(m, body.root, .storage_unsupported, "Scoped helper extraction could not preserve its checked machine state"),
            };
            if (credit) |committed| {
                // Extraction moves barriers and local definitions into a new
                // machine body. A regrown suffix cannot prove cache dominance.
                self.bundle_snapshots.clearRetainingCapacity();
                self.bundle_sources.clearRetainingCapacity();
                self.bundle_scan = self.module.functions.items[self.c.function].instructions.items.len;
                self.span_scopes.reset();
                self.steps -= @intCast(committed.expressions);
                self.layout_steps -= committed.layouts;
            }
        }
        return result;
    }
    fn closureEvidence(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value, result: Value, evidence: *std.ArrayList(u32)) Error!bool {
        const before = evidence.items.len;
        const diagnostic_before = self.diagnostic;
        self.closureEvidenceInner(m, id, function, argument, result, evidence) catch |err| {
            if (err == error.OutOfMemory) return err;
            evidence.shrinkRetainingCapacity(before);
            self.diagnostic = diagnostic_before;
            return false;
        };
        return true;
    }
    fn closureEvidenceInner(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value, result: Value, evidence: *std.ArrayList(u32)) Error!void {
        const callable = function.callable.?;
        const owner = try self.unit(callable.unit);
        const closure = owner.closure(callable.node);
        if (callable.goals.len != 0 or closure.qualifier != 0 or !plainInlineValue(result) or !stableDescriptorShape(result)) return error.Declined;
        var remaining: usize = 4096;
        var work: usize = 4096;
        var keys = selected_types.Builder.init(self.allocator, &work, .{});
        defer keys.deinit();
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 7, callable.node, @intCast(function.fields.len) });
        try self.descriptorTypeEvidence(m, id, .{ .unit = owner.unit, .ty = closure.function_type }, evidence, &keys, &remaining);
        for (callable.captures, function.fields) |binding, capture| {
            try self.descriptorTypeEvidence(m, id, .{ .unit = owner.unit, .ty = owner.binding(binding).ty }, evidence, &keys, &remaining);
            try self.descriptorValueEvidence(m, id, capture, evidence, &keys, &remaining, 0);
            if (plainInlineValue(capture)) try self.inlineLayoutEvidence(m, id, capture, evidence, &keys) else try self.readerLayoutEvidence(m, id, capture, evidence, &keys);
        }
        try self.descriptorTypeEvidence(m, id, .{ .unit = owner.unit, .ty = closure.parameter.ty }, evidence, &keys, &remaining);
        try self.descriptorValueEvidence(m, id, argument, evidence, &keys, &remaining, 0);
        if (plainInlineValue(argument)) try self.inlineLayoutEvidence(m, id, argument, evidence, &keys) else try self.readerLayoutEvidence(m, id, argument, evidence, &keys);
        try self.descriptorTypeEvidence(m, id, .{ .unit = owner.unit, .ty = owner.typeOf(closure.body) }, evidence, &keys, &remaining);
        try self.descriptorValueEvidence(m, id, result, evidence, &keys, &remaining, 0);
        try self.readerLayoutEvidence(m, id, result, evidence, &keys);
        try self.finishSelectedTypes(m, id, evidence, &keys);
    }
    fn reusableClosure(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value, checked_use: bool) Error!?Value {
        const callable = function.callable.?;
        const owner = try self.unit(callable.unit);
        const closure = owner.closure(callable.node);
        var remaining: usize = 100_000;
        if (!try self.selectedDataType(.{ .unit = owner.unit, .ty = owner.typeOf(closure.body) }, true, &remaining, 0)) return null;
        var result_shape = try self.shape(owner, closure.body, owner.typeOf(closure.body), 0);
        if (!plainInlineValue(result_shape)) return null;
        const aggregate_result = result_shape.tag == .aggregate;
        if (aggregate_result and self.destination != null) return null;
        var descriptor = false;
        if (!self.readerArgument(argument, &descriptor, &remaining)) return null;
        var words = readerWords(argument);
        for (function.fields) |capture| {
            if (!self.readerArgument(capture, &descriptor, &remaining)) return null;
            words = std.math.add(usize, words, readerWords(capture)) catch return null;
        }
        const parameter_count = std.math.add(usize, words, @intFromBool(aggregate_result)) catch return null;
        if (parameter_count > std.math.maxInt(u32)) return null;
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        var shared = try self.closureEvidence(m, id, function, argument, result_shape, &evidence);
        if (!shared) {
            // Qualified and abstract callbacks keep their invocation-local path.
            if (!self.specialize or !checked_use or aggregate_result or argument.tag != .scalar) return null;
            const raw_result = owner.typeOf(closure.body);
            if (raw_result != T.unit and raw_result != T.boolean and raw_result != T.u32_type and raw_result != T.f32_type) return null;
            for (function.fields) |capture| switch (capture.tag) {
                .scalar, .array, .ref, .link, .view => {},
                else => return null,
            };
            try evidence.appendSlice(self.allocator, &.{ callable.node, owner.typeOf(closure.body), @intFromBool(argument.floating) });
            var work: usize = 4096;
            var keys = selected_types.Builder.init(self.allocator, &work, .{});
            defer keys.deinit();
            for (callable.captures, function.fields) |binding, capture| {
                try self.readerLayoutEvidence(m, id, capture, &evidence, &keys);
                try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.binding(binding).ty }, &evidence, &keys, 0);
            }
            try self.selectedType(m, id, .{ .unit = owner.unit, .ty = closure.parameter.ty }, &evidence, &keys, 0);
            try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.typeOf(closure.body) }, &evidence, &keys, 0);
            try self.finishSelectedTypes(m, id, &evidence, &keys);
        }
        var cache = &self.calls;
        if (shared) cache = self.shared_calls;
        var key: call_plan.Key = .{ .unit = owner.unit, .binding = 0, .context = self.invocationContext(), .evidence = evidence.items };
        var existing = cache.find(key);
        if (existing == null) {
            if (!shared) {
                if (descriptor) {
                    if (!call_plan.readerBody(owner, closure.body, &remaining, 0)) return null;
                } else if (!call_plan.scalarBody(owner, closure.body, &remaining, 0)) return null;
            } else if (!call_plan.readerBody(owner, closure.body, &remaining, 0)) {
                const planning_before = self.planning_writer;
                self.planning_writer = false;
                defer self.planning_writer = planning_before;
                var active: [128]core.BindingRef = undefined;
                if (!try self.plannedCallback(function, argument, &remaining, &active, 0, 0)) return null;
            }
            // Admission borrows a restored instance. Rebuild the exact shared
            // key and caller-owned shape after that temporary context is gone.
            if (shared) {
                evidence.clearRetainingCapacity();
                result_shape = try self.shape(owner, closure.body, owner.typeOf(closure.body), 0);
                shared = try self.closureEvidence(m, id, function, argument, result_shape, &evidence);
                if (!shared) return null;
                key.evidence = evidence.items;
                existing = cache.find(key);
            }
        }
        for (function.fields) |capture| try self.readerReads(m, id, capture);
        try self.readerReads(m, id, argument);
        if (existing != null) self.emission_work.scoped_closure_cache_hits +|= 1;
        const index = if (existing) |found| found else blk: {
            const signature = try self.allocator.alloc(wasm.ValueType, parameter_count);
            defer self.allocator.free(signature);
            @memset(signature, .i32);
            const target = self.module.addTypedFunction(signature, .i32, .scalar) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, id),
            };
            const inserted = try cache.insert(key, target, result_shape.floating);
            var child: Generator = .{
                .allocator = self.allocator,
                .arena = std.heap.ArenaAllocator.init(self.allocator),
                .calls = .{ .allocator = self.allocator },
                .shared_calls = self.shared_calls,
                .descriptor_calls = self.descriptor_calls,
                .field_recipes = self.field_recipes,
                .scalar_admission = self.scalar_admission,
                .active_calls = self.active_calls,
                .specialize = false,
                .work_limits = self.work_limits,
                .emission_work = self.emission_work,
                .outlining = self.outlining,
                .units = self.units,
                .unit_views = self.unit_views,
                .proof_cache = self.proof_cache,
                .dispatches = self.dispatches,
                .capacity_requests = self.capacity_requests,
                .capacity_prefix = self.capacity_prefix,
                .validation_budget = self.validation_budget,
                .entry_unit = self.entry_unit,
                .specialization_origin = self.specialization_origin,
                .methods = self.methods,
                .module = self.module,
                .runtime = self.runtime,
                .fixed_region = self.fixed_region,
                .c = .{ .module = self.module, .function = target },
            };
            defer child.deinit();
            try self.inheritTypes(&child);
            var input = function;
            const fields = initializeFields(&input, try child.arena.allocator().alloc(Value, function.fields.len));
            var next: u32 = 0;
            for (fields, function.fields) |*capture, original| {
                if (shared and plainInlineValue(original)) capture.* = try child.inlineParameter(original, &next) else try self.readerParameter(&child, capture, original, &next);
            }
            var input_argument: Value = undefined;
            if (shared and plainInlineValue(argument)) input_argument = try child.inlineParameter(argument, &next) else try self.readerParameter(&child, &input_argument, argument, &next);
            const output = child.applyUse(m, id, input, input_argument, 0, .{ .checked = false, .reuse = false }) catch |err| {
                if (child.diagnostic) |diagnostic| self.diagnostic = diagnostic;
                return err;
            };
            if (aggregate_result) {
                if (!output.terminated and !plainReaderResultABI(output, result_shape)) return self.fail(m, id, .storage_unsupported, "Shared callback output differs from its checked layout");
                try child.storeValue(.{ .id = next }, 0, output);
                try child.c.value(0);
            } else try child.c.value(try child.scalar(m, id, output));
            try self.completeCall(cache, inserted, child.context_sensitive, false);
            self.emission_work.scoped_closure_definitions +|= 1;
            break :blk inserted;
        };
        const entry = cache.entries.items[index];
        self.noteCalleeContext(entry);
        if (entry.building) return self.fail(m, id, .storage_unsupported, "Recursive callback specialization is not admitted");
        const first_root = self.roots.items.len;
        const mark: ?FrameMark = if (aggregate_result) try self.frameMark() else null;
        var address: ?Local = null;
        if (aggregate_result) {
            const slot = try self.arrayWithShape(m, id, (try self.constant(1)).word, .fixed, result_shape);
            address = try self.c.temp();
            try self.c.set(address.?, .{ .call, self.runtime.functions.address, slot.token, slot.epoch_low, slot.epoch_high, slot.word, 0 });
        }
        for (function.fields) |capture| try self.readerValues(capture);
        try self.readerValues(argument);
        if (address) |pointer| try self.c.value(pointer);
        try self.c.op(.call, entry.function);
        const word = try self.c.temp();
        try self.c.op(.local_set, word.id);
        var result = Value{ .word = word, .floating = entry.floating };
        if (address) |pointer| result = try self.loadValue(pointer, 0, result_shape);
        if (mark) |saved| {
            try self.release(first_root, null);
            try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, saved.word });
        }
        result.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = owner.unit, .ty = owner.typeOf(closure.body) }, .arguments = try self.captureTypes() });
        return result;
    }
    fn apply(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value, depth: usize) Error!Value {
        return self.applyUse(m, id, function, argument, depth, .{});
    }
    const ApplyOptions = struct { checked: bool = true, reuse: bool = true };
    fn applyUse(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value, depth: usize, options: ApplyOptions) Error!Value {
        if (function.host != null) return self.hostCall(m, id, function, argument);
        const callable = function.callable orelse return self.fail(m, id, .storage_unsupported, "A callback must have a statically known function body");
        const types_before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(types_before);
        // Resolve the caller's current instance before entering the captured
        // environment. Static inference IDs can be shared by distinct active
        // instantiations; a capture must not rewrite the checked use's result.
        const use_input: ?TypeRef = if (options.checked and m.node(id).tag == .apply) try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(m.node(id).b) }, 0) else null;
        const use_output: ?TypeRef = if (options.checked and m.node(id).tag == .apply) try self.resolveType(.{ .unit = m.unit, .ty = m.node(id).ty }, 0) else null;
        try self.restoreTypes(callable.types);
        // A partial application may have been captured before its remaining
        // generic inputs were known. The checked use owns the final instance;
        // refine after restoring the capture's earlier type environment.
        if (options.checked and m.node(id).tag == .apply) {
            const owner = try self.unit(callable.unit);
            var signature = callable.signature(owner);
            var skipped: usize = 0;
            while (skipped < if (callable.kind(owner) != .closure) function.fields.len else 0) : (skipped += 1) {
                const arrow = owner.types.node(signature);
                if (arrow.tag != .function) return self.unsupported(m, id);
                signature = arrow.b;
            }
            const arrow = owner.types.node(signature);
            if (arrow.tag == .function) {
                try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.a }, use_input.?, 0);
                try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.b }, use_output.?, 0);
            }
        }
        if (callable.kind(try self.unit(callable.unit)) == .primitive) return self.applyPrimitive(m, id, function, argument);
        if (callable.node == 0) {
            const args = try self.arena.allocator().alloc(Value, function.fields.len + 1);
            @memcpy(args[0..function.fields.len], function.fields);
            args[function.fields.len] = argument;
            return self.invokeAt(m, id, .{ .unit = callable.unit, .binding = callable.target }, args, depth + 1);
        }
        const owner = try self.unit(callable.unit);
        const closure = owner.closure(callable.node);
        if (try self.callableType(argument)) |signature| {
            try self.mapTypesUnder(.{ .unit = owner.unit, .ty = closure.parameter.ty }, signature, argument.callable.?.types, 0);
        } else try self.mapValueTypes(.{ .unit = owner.unit, .ty = closure.parameter.ty }, argument, 0);
        const previous_goals = self.active_goals;
        self.active_goals = callable.goals;
        defer self.active_goals = previous_goals;
        try self.refineFields(owner, callable.goals);
        if (closure.qualifier != 0) {
            const scheme = owner.binding(closure.qualifier).scheme;
            try self.refineFields(owner, owner.obligations[scheme.obligations.start..][0..scheme.obligations.len]);
        }
        for (callable.captures, function.fields) |binding, capture| {
            const formal: TypeRef = .{ .unit = owner.unit, .ty = owner.binding(binding).ty };
            if (try self.callableType(capture)) |signature| {
                try self.mapTypesUnder(formal, signature, capture.callable.?.types, 0);
            } else try self.mapValueTypes(formal, capture, 0);
        }
        const selected_target: call_plan.ActiveCalls.Target = .{ .unit = callable.unit, .id = callable.node, .kind = .closure, .context = self.invocationContext() };
        var selected: std.ArrayList(u32) = .empty;
        defer selected.deinit(self.allocator);
        try self.selectedArguments(m, id, function.fields, &.{argument}, &selected);
        try selected.appendSlice(self.allocator, &.{ std.math.maxInt(u32), @intCast(callable.captures.len + 2) });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (callable.captures) |binding| try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.binding(binding).ty }, &selected, &type_key, 0);
        try self.selectedType(m, id, .{ .unit = owner.unit, .ty = closure.parameter.ty }, &selected, &type_key, 0);
        try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.typeOf(closure.body) }, &selected, &type_key, 0);
        try self.finishSelectedTypes(m, id, &selected, &type_key);
        if (self.active_calls.contains(selected_target, selected.items)) return self.fail(m, id, .storage_unsupported, "Recursive selected calls are not supported by the owned-storage backend");
        if (self.active_calls.frames.items.len >= 128) return self.fail(m, id, .storage_unsupported, "Selected calls exceeded their active call bound");
        if (options.reuse) if (try self.reusableClosure(m, id, function, argument, options.checked)) |value| return value;
        if (!try self.active_calls.enter(selected_target, selected.items)) return self.fail(m, id, .storage_unsupported, "Recursive selected calls are not supported by the owned-storage backend");
        defer self.active_calls.leave();
        const uses = @import("storage_liveness.zig").count(self.allocator, owner, closure.body) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, id);
        };
        defer self.allocator.free(uses);
        const previous_uses = self.uses;
        self.uses = uses;
        defer self.uses = previous_uses;
        const bindings_before = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(bindings_before);
        const roots_before = self.roots.items.len;
        const mark = try self.frameMark();
        self.depth += 1;
        defer self.depth -= 1;
        for (callable.captures, function.fields) |binding, value| try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = binding, .value = value, .remaining = uses[binding] });
        try self.bind(owner, closure.parameter.binding, argument);
        var result = try self.expression(owner, closure.body, 0);
        try self.escape(owner, closure.body, &result, self.depth);
        try self.release(roots_before, result);
        try self.rewindUnescaped(roots_before, mark, result);
        return result;
    }
    fn pattern(self: *Generator, m: *const core.Module, id: core.PatternId, value: Value) Error!void {
        const p = m.pattern(id);
        switch (p.tag) {
            .bind => try self.bind(m, p.a, value),
            .wildcard => {},
            .product => {
                const children = m.patternChildren(id);
                if (value.tag != .aggregate or children.len != value.fields.len) return error.Declined;
                const ty = m.types.node(p.ty);
                for (children, 0..) |child, index| {
                    const field = if (ty.tag == .record) try self.namedField(m, 0, value, m.types.recordField(ty, index).name) else value.fields[index];
                    try self.pattern(m, child, field);
                }
            },
            .constructor => {
                const constructor = m.constructor(p.a);
                const nominal = m.nominal(constructor.nominal);
                if (value.nominal == null or !std.meta.eql(nominal.identity, value.nominal.?)) return error.Declined;
                const selected = if (value.variant_tags.len == 0) @as(usize, 0) else @import("storage_layout.zig").variantIndex(value.variant_tags, constructor.tag) orelse return error.Declined;
                if (value.variant_tags.len != 0) try self.c.trap(.{ .i32_ne, value.word, constructor.tag });
                if (p.b != 0) try self.pattern(m, p.b, value.fields[selected]);
            },
            .record_payload => {
                if (p.a == 1) {
                    if (value.fields.len != 1) return error.Declined;
                    try self.pattern(m, p.b, value.fields[0]);
                } else if (m.pattern(p.b).tag == .product) {
                    const children = m.patternChildren(p.b);
                    const ty = m.types.node(p.ty);
                    if (ty.tag != .record or children.len != value.fields.len) return error.Declined;
                    for (children, 0..) |child, index| try self.pattern(m, child, try self.namedField(m, 0, value, m.types.recordField(ty, index).name));
                } else return error.Declined;
            },
            else => return error.Declined,
        }
    }
    fn testPattern(self: *Generator, m: *const core.Module, id: core.PatternId, value: Value, depth: usize) Error!Local {
        if (depth > 128) return self.unsupported(m, 0);
        const p = m.pattern(id);
        switch (p.tag) {
            .bind => {
                try self.bind(m, p.a, value);
                return (try self.constant(1)).word;
            },
            .wildcard => return (try self.constant(1)).word,
            .constant, .value => {
                const expected = if (p.tag == .constant) try self.constant(p.a) else try self.expression(m, p.a, depth + 1);
                const actual = try self.scalar(m, 0, value);
                return @import("storage_patterns.zig").equal(self.c, actual, try self.scalar(m, 0, expected), value.floating);
            },
            .constructor => {
                const constructor = m.constructor(p.a);
                const nominal = m.nominal(constructor.nominal);
                if (value.nominal == null or !std.meta.eql(value.nominal.?, nominal.identity)) return self.unsupported(m, 0);
                const selected = if (value.variant_tags.len == 0) @as(usize, 0) else @import("storage_layout.zig").variantIndex(value.variant_tags, constructor.tag) orelse return self.unsupported(m, 0);
                const result = try self.c.temp();
                if (value.variant_tags.len == 0) try self.c.set(result, 1) else try self.c.set(result, .{ .i32_eq, value.word, constructor.tag });
                if (p.b != 0) {
                    try self.c.when(result);
                    self.nesting += 1;
                    try self.c.set(result, try self.testPattern(m, p.b, value.fields[selected], depth + 1));
                    self.nesting -= 1;
                    try self.c.end();
                }
                return result;
            },
            .product => {
                const children = m.patternChildren(id);
                if (value.tag != .aggregate or children.len != value.fields.len or value.variant_tags.len != 0) return self.unsupported(m, 0);
                const result = (try self.constant(1)).word;
                const ty = m.types.node(p.ty);
                for (children, 0..) |child, index| {
                    const field = if (ty.tag == .record) try self.namedField(m, 0, value, m.types.recordField(ty, index).name) else value.fields[index];
                    try self.c.when(result);
                    self.nesting += 1;
                    try self.c.set(result, try self.testPattern(m, child, field, depth + 1));
                    self.nesting -= 1;
                    try self.c.end();
                }
                return result;
            },
            .record_payload => {
                if (p.a == 1) {
                    if (value.fields.len != 1) return self.unsupported(m, 0);
                    return self.testPattern(m, p.b, value.fields[0], depth + 1);
                }
                return self.testPattern(m, p.b, value, depth + 1);
            },
            else => return self.unsupported(m, 0),
        }
    }
    fn evaluatedPattern(m: *const core.Module, id: core.PatternId, depth: usize) bool {
        if (depth > 128) return true;
        const p = m.pattern(id);
        return switch (p.tag) {
            .value => true,
            .constructor, .record_payload => p.b != 0 and evaluatedPattern(m, p.b, depth + 1),
            .product => blk: {
                for (m.patternChildren(id)) |child| if (evaluatedPattern(m, child, depth + 1)) break :blk true;
                break :blk false;
            },
            else => false,
        };
    }
    fn impossiblePattern(m: *const core.Module, id: core.PatternId, value: Value, depth: usize) bool {
        if (depth > 128) return false;
        const p = m.pattern(id);
        switch (p.tag) {
            .constructor => {
                const constructor = m.constructor(p.a);
                if (value.nominal == null or !std.meta.eql(value.nominal.?, m.nominal(constructor.nominal).identity)) return false;
                const selected = if (value.variant_tags.len == 0) @as(usize, 0) else @import("storage_layout.zig").variantIndex(value.variant_tags, constructor.tag) orelse return false;
                if (!possibleVariant(value, selected)) return true;
                return p.b != 0 and selected < value.fields.len and impossiblePattern(m, p.b, value.fields[selected], depth + 1);
            },
            .product => {
                const children = m.patternChildren(id);
                if (value.tag != .aggregate or children.len != value.fields.len or value.variant_tags.len != 0) return false;
                const ty = m.types.node(p.ty);
                for (children, 0..) |child, index| {
                    const field = if (ty.tag == .record) dataField(value, m.fieldSpelling(m.types.recordField(ty, index).name) orelse return false) orelse return false else value.fields[index];
                    if (impossiblePattern(m, child, field, depth + 1)) return true;
                }
            },
            .record_payload => {
                if (p.a == 1) return value.fields.len == 1 and impossiblePattern(m, p.b, value.fields[0], depth + 1);
                return impossiblePattern(m, p.b, value, depth + 1);
            },
            else => {},
        }
        return false;
    }
    fn continuationBindings(self: *Generator, m: *const core.Module, id: core.Id, output: *std.ArrayList(Binding), bindings: []const Binding) Error!void {
        for (bindings) |binding| {
            var existing: ?*Binding = null;
            for (output.items) |*item| if (item.unit == binding.unit and item.id == binding.id) {
                existing = item;
                break;
            };
            if (existing) |item| {
                try self.assign(m, id, &item.value, binding.value);
                item.remaining = @max(item.remaining, binding.remaining);
            } else {
                var item = binding;
                item.value = try self.temporary(binding.value);
                try self.assign(m, id, &item.value, binding.value);
                try output.append(self.allocator, item);
            }
        }
    }
    fn emitMatch(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const inputs = m.matchInputs(id);
        const values = try self.arena.allocator().alloc(Value, inputs.len);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        for (inputs, values) |input, *value| {
            const evaluated = try self.expression(m, input, depth + 1);
            if (evaluated.terminated) return evaluated;
            value.* = try self.snapshot(evaluated);
            try self.protected.append(self.allocator, value.*);
        }
        const done = (try self.constant(0)).word;
        var result = self.newJoin();
        const merges = m.branchMerges(id);
        const merged = try self.arena.allocator().alloc(?Value, merges.len);
        @memset(merged, null);
        const shared_merges = try self.mergeTransport(m, merges, merged);
        if (merges.len != 0 and m.matchArms(id).len != 2) return self.unsupported(m, id);
        var continuing: usize = 0;
        var survivor: []const Binding = &.{};
        for (m.matchArms(id), 0..) |arm, arm_index| {
            var arm_bindings: std.ArrayList(Binding) = .empty;
            defer arm_bindings.deinit(self.allocator);
            var arm_continues = false;
            const selected = (try self.constant(0)).word;
            rows: for (m.armRows(arm)) |row| {
                const bindings_before = self.bindings.items.len;
                const patterns = m.rowPatterns(row);
                if (patterns.len != values.len) return self.unsupported(m, id);
                // Source admission still checks every arm. Emission may omit
                // an uninhabited payload, but never skip value-pattern work.
                const evaluated = for (patterns) |pattern_id| {
                    if (evaluatedPattern(m, pattern_id, 0)) break true;
                } else false;
                if (!evaluated) for (patterns, values) |pattern_id, value| {
                    if (impossiblePattern(m, pattern_id, value, 0)) continue :rows;
                };
                try self.c.when(.{ .i32_eqz, .{ .i32_or, done, selected } });
                self.nesting += 1;
                const matches = (try self.constant(1)).word;
                for (patterns, values) |pattern_id, value| {
                    try self.c.when(matches);
                    self.nesting += 1;
                    try self.c.set(matches, try self.testPattern(m, pattern_id, value, depth + 1));
                    self.nesting -= 1;
                    try self.c.end();
                }
                try self.c.when(matches);
                self.nesting += 1;
                try self.c.set(selected, 1);
                const guard = if (arm.guard != 0) try self.expression(m, arm.guard, depth + 1) else try self.constant(1);
                try self.c.when(try self.scalar(m, id, guard));
                self.nesting += 1;
                try self.c.set(done, 1);
                const body = if (guard.terminated) guard else if (arm.body != 0) try self.expression(m, arm.body, depth + 1) else try self.unitValue();
                if (!body.terminated) {
                    arm_continues = true;
                    try self.addJoin(m, id, &result, body);
                    for (merges, merged, shared_merges) |merge, *value, shared_merge| {
                        const incoming = try self.bindingValue(m, if (arm_index == 0) merge.then_binding else merge.else_binding);
                        if (value.* == null) value.* = try self.temporary(incoming);
                        try self.assignTransport(m, id, &value.*.?, incoming, !shared_merge);
                    }
                    if (m.matchInfo(id).statement) {
                        const introduced = self.bindings.items[bindings_before..];
                        // A sole pattern row has one immutable physical
                        // origin. Only a sole continuing arm publishes it.
                        if (m.armRows(arm).len == 1 and !self.scalar_admission.hasScalarReferences()) {
                            try arm_bindings.appendSlice(self.allocator, introduced);
                            self.emission_work.scoped_immutable_survivor_bindings +|= introduced.len;
                        } else try self.continuationBindings(m, id, &arm_bindings, introduced);
                    }
                }
                self.nesting -= 3;
                try self.c.end();
                try self.c.end();
                try self.c.end();
                self.bindings.shrinkRetainingCapacity(bindings_before);
            }
            if (arm_continues) {
                continuing += 1;
                survivor = try self.arena.allocator().dupe(Binding, arm_bindings.items);
            }
        }
        try self.c.trap(.{ .i32_eqz, done });
        if (m.matchInfo(id).statement and continuing == 1) try self.bindings.appendSlice(self.allocator, survivor);
        const resolved = try self.finishJoin(&result, false);
        if (resolved != null) {
            for (merges, merged) |merge, value| if (value) |joined| try self.bind(m, merge.result, joined);
        }
        return resolved orelse try self.terminated();
    }
    fn namedField(self: *Generator, m: *const core.Module, id: core.Id, value: Value, name: u32) Error!Value {
        const spelling = m.fieldSpelling(name) orelse return self.unsupported(m, id);
        for (value.fields) |field| if (std.mem.eql(u8, field.name, spelling)) return field;
        return self.unsupported(m, id);
    }
    fn dataField(value: Value, name: []const u8) ?Value {
        if (value.tag != .aggregate) return null;
        for (value.fields) |field| if (std.mem.eql(u8, field.name, name)) return field;
        if (value.nominal != null and value.variant_tags.len == 0 and value.fields.len == 1) return dataField(value.fields[0], name);
        return null;
    }
    /// A record view selects existing field descriptors. Copying Value keeps
    /// callable captures and every owner/borrow root; no payload is copied.
    fn mergeRecordValues(self: *Generator, left: Value, right: Value) Error!?Value {
        if (left.tag != .aggregate or right.tag != .aggregate or left.nominal != null or right.nominal != null or
            left.variant_tags.len != 0 or right.variant_tags.len != 0 or left.sequence or right.sequence) return null;
        for (left.fields) |field| if (field.name.len == 0) return null;
        for (right.fields) |field| if (field.name.len == 0) return null;
        var count = left.fields.len;
        for (right.fields) |field| if (dataField(left, field.name) == null) {
            count += 1;
        };
        const fields = try self.arena.allocator().alloc(Value, count);
        for (left.fields, fields[0..left.fields.len]) |field, *selected| selected.* = dataField(right, field.name) orelse field;
        var next = left.fields.len;
        for (right.fields) |field| if (dataField(left, field.name) == null) {
            fields[next] = field;
            next += 1;
        };
        orderFields(fields);
        return .{ .tag = .aggregate, .word = left.word, .fields = fields };
    }
    /// Substitute only checked source types. Physical words and field counts
    /// cannot establish the receiver of an associated operation.
    fn dispatchEvidence(self: *Generator, evidence: *type_evidence.Store, input: TypeRef, depth: usize) Error!type_evidence.Id {
        if (depth > 128 or self.validation_budget.* == 0) {
            return error.Declined;
        }
        self.validation_budget.* -= 1;
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        var children: std.ArrayList(T.Id) = .empty;
        defer children.deinit(self.allocator);
        switch (node.tag) {
            .variable, .bound => {
                return error.Declined;
            },
            .array, .list, .cursor, .resolver => try children.append(self.allocator, node.a),
            .function => try children.appendSlice(self.allocator, &.{ node.a, node.b }),
            .product => try children.appendSlice(self.allocator, owner.types.list(.{ .start = node.a, .len = node.b })),
            .nominal => try children.appendSlice(self.allocator, owner.types.nominalArguments(node)),
            .record => for (0..node.b) |index| try children.append(self.allocator, owner.types.recordField(node, index).ty),
            .usage => {
                try children.append(self.allocator, node.a);
                if (node.c != 0) try children.append(self.allocator, node.c);
            },
            else => {},
        }
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        for (children.items) |child| try mappings.append(self.allocator, .{
            .variable = child,
            .evidence = try self.dispatchEvidence(evidence, .{ .unit = actual.unit, .ty = child, .environment = actual.environment }, depth + 1),
        });
        return evidence.projectWithBudget(&owner.types, actual.ty, mappings.items, &.{}, self.validation_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.Declined;
        };
    }
    // A selected associated declaration can return a function (for example
    // lerp after its two operands). Its exact result supplies the latent row
    // instantiation, while resolved child types and concrete effects must
    // still match. Never default an open row to empty or infer receiver types
    // from physical values here.
    fn dispatchResultEvidence(self: *Generator, evidence: *type_evidence.Store, input: TypeRef, selected: type_evidence.Id, depth: usize) Error!type_evidence.Id {
        if (depth > 128) return error.Declined;
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        if (node.tag != .function) return self.dispatchEvidence(evidence, actual, depth + 1);
        const candidate = evidence.nodes.items[selected];
        if (candidate.tag != .function) return error.Declined;
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        try mappings.append(self.allocator, .{ .variable = node.a, .evidence = try self.dispatchResultEvidence(evidence, .{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, candidate.a, depth + 1) });
        try mappings.append(self.allocator, .{ .variable = node.b, .evidence = try self.dispatchResultEvidence(evidence, .{ .unit = actual.unit, .ty = node.b, .environment = actual.environment }, candidate.b, depth + 1) });
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        const matches = evidence.matchWithRowsBudget(&owner.types, actual.ty, selected, &mappings, &rows, self.validation_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.Declined;
        };
        if (!matches) return error.Declined;
        return evidence.projectWithBudget(&owner.types, actual.ty, mappings.items, rows.items, self.validation_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.Declined;
        };
    }
    fn dispatchTarget(self: *Generator, m: *const core.Module, identity: T.NominalIdentity, member: u32, operator: T.Operator) Error!?core.BindingRef {
        const key: DispatchKey = .{ .unit = m.unit, .identity = identity, .member = member, .operator = operator };
        if (self.dispatches.get(key)) |cached| return cached;
        const nominal_owner = if (identity.unit == 0 or types.identity(identity.unit, identity.decl) != null) m else try self.unit(identity.unit);
        for ([_]*const core.Module{ m, nominal_owner }, 0..) |catalog, index| {
            if (index == 1 and catalog == m) continue;
            for (catalog.associated) |method| {
                if (self.validation_budget.* == 0) return error.Declined;
                self.validation_budget.* -= 1;
                if (!std.meta.eql(method.identity, identity) or (if (member != 0) method.member != member else method.operator != operator)) continue;
                var target = method.target;
                if (target.unit == 0) target.unit = catalog.unit;
                const owner = try self.unit(target.unit);
                if (owner != m and owner.binding(target.binding).private) continue;
                try self.dispatches.put(self.allocator, key, target);
                return target;
            }
        }
        try self.dispatches.put(self.allocator, key, null);
        return null;
    }
    fn fieldTarget(self: *Generator, m: *const core.Module, identity: T.NominalIdentity, member: u32) Error!?core.BindingRef {
        const key: DispatchKey = .{ .unit = m.unit, .identity = identity, .member = member, .operator = .none, .field = true };
        if (self.dispatches.get(key)) |cached| return cached;
        const target = @import("../check/resolver_core.zig").methodWorkspace(m, self.unit_views, identity, member, self.validation_budget, &self.methods.bounds) catch {
            if (self.methods.bounds.oom) return error.OutOfMemory;
            if (self.validation_budget.* == 0) return error.Declined;
            try self.dispatches.put(self.allocator, key, null);
            return null;
        };
        try self.dispatches.put(self.allocator, key, target);
        return target;
    }
    fn dispatchCandidate(self: *Generator, m: *const core.Module, id: core.Id, target: core.BindingRef, inputs: []const TypeRef, output: TypeRef, arguments: []const Value, depth: usize) Error!?Value {
        const owner = try self.unit(target.unit);
        const body = owner.body(target.binding) orelse return null;
        var evidence = type_evidence.Store.init(self.allocator) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.Declined;
        };
        defer evidence.deinit();
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        const before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(before);
        var result = body.scheme.root;
        for (inputs) |input| {
            const arrow = owner.types.node(result);
            if (arrow.tag != .function) return null;
            const actual = try self.dispatchEvidence(&evidence, input, 0);
            const matches = evidence.matchWithRowsBudget(&owner.types, arrow.a, actual, &mappings, &rows, self.validation_budget) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.unsupported(m, id);
            };
            if (!matches) return null;
            result = arrow.b;
        }
        // Operand compatibility fixes the declaration. An incompatible result
        // must not make selection fall through to the other operand's owner.
        var cursor = body.scheme.root;
        for (inputs) |input| {
            const arrow = owner.types.node(cursor);
            try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.a }, input, 0);
            cursor = arrow.b;
        }
        const selected_result = try self.resolveType(.{ .unit = owner.unit, .ty = result }, 0);
        const resolved_output = try self.resolveType(output, 0);
        const output_owner = try self.unit(resolved_output.unit);
        if (output_owner.types.node(resolved_output.ty).tag == .variable) try self.mapTypes(resolved_output, selected_result, 0);
        const expected = if (output_owner.types.node(resolved_output.ty).tag == .function) function_result: {
            const selected_evidence = try self.dispatchEvidence(&evidence, selected_result, 0);
            break :function_result try self.dispatchResultEvidence(&evidence, output, selected_evidence, 0);
        } else try self.dispatchEvidence(&evidence, output, 0);
        const matches = evidence.matchWithRowsBudget(&owner.types, result, expected, &mappings, &rows, self.validation_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, id);
        };
        if (!matches) return self.unsupported(m, id);
        try self.mapTypes(.{ .unit = owner.unit, .ty = result }, output, 0);
        return try self.invokeAt(m, id, target, arguments, depth + 1);
    }

    fn contractMethod(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        self.context_sensitive = true;
        self.emission_work.scoped_context_queries +|= 1;
        const node = m.node(id);
        const template = m.member_templates[node.a];
        const before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(before);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        const children = m.children(id);
        const arguments = try self.arena.allocator().alloc(Value, children.len);
        const inputs = try self.arena.allocator().alloc(TypeRef, children.len);
        for (children, arguments, inputs) |child, *argument, *input| {
            argument.* = try self.expression(m, child, depth + 1);
            if (argument.terminated) return argument.*;
            try self.protected.append(self.allocator, argument.*);
            input.* = try self.operandType(.{ .unit = m.unit, .ty = m.typeOf(child) }, argument.*);
        }
        const session = try self.methods.get();
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        for (m.types.list(template.arguments)) |argument_type| try mappings.append(self.allocator, .{
            .variable = argument_type,
            .evidence = try self.dispatchEvidence(&session.storage.evidence, .{ .unit = m.unit, .ty = argument_type }, 0),
        });
        // A chosen target and compatible data layouts cannot establish its
        // latent effects. Compare the complete checked declaration-proxy arrow
        // with the independently selected closed semantic signature.
        const expected = try self.dispatchEvidence(&session.storage.evidence, .{ .unit = m.unit, .ty = m.binding(template.binding).ty }, 0);
        const selected = selection: {
            session.associated_remaining = @min(session.associated_remaining, self.validation_budget.*);
            const remaining_before = session.associated_remaining;
            defer self.validation_budget.* -|= remaining_before -| session.associated_remaining;
            const previous_origin = session.specialization_origin;
            session.specialization_origin = self.specialization_origin;
            defer session.specialization_origin = previous_origin;
            break :selection session.implementationMethod(m.unit - 1, id, template, mappings.items, &.{}) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.unsupported(m, id);
            };
        };
        if (expected != selected.signature) return self.unsupported(m, id);
        return (try self.dispatchCandidate(m, id, selected.target, inputs, .{ .unit = m.unit, .ty = node.ty }, arguments, depth + 1)) orelse self.unsupported(m, id);
    }
    fn operandType(self: *Generator, input: TypeRef, value: Value) Error!TypeRef {
        const resolved = try self.resolveType(input, 0);
        const owner = try self.unit(resolved.unit);
        if (T.receiverIdentity(owner.types.node(resolved.ty)) != null) return resolved;
        if (value.type_evidence) |evidence| {
            try self.restoreTypes(evidence.arguments);
            return self.resolveType(evidence.root, 0);
        }
        return resolved;
    }
    fn vectorLocal(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!Local {
        if (value.tag != .aggregate or value.nominal != null or value.fields.len != 4) return self.unsupported(m, id);
        for (value.fields) |field| if (field.tag != .scalar or field.floating != value.fields[0].floating) return self.unsupported(m, id);
        const vector: Local = .{ .id = try self.module.addLocal(self.c.function, .v128) };
        try self.c.value(value.fields[0].word);
        try self.c.op(.i32x4_splat, 0);
        for (value.fields[1..], 1..) |field, lane| {
            try self.c.value(field.word);
            try self.c.op(.i32x4_replace_lane, @intCast(lane));
        }
        try self.c.op(.local_set, vector.id);
        return vector;
    }
    fn vectorPrimitive(self: *Generator, m: *const core.Module, id: core.Id, left: Value, right: Value) Error!Value {
        const n = m.node(id);
        const catalog = @import("simd_intrinsics.zig");
        const pair = catalog.pairs(n.op);
        if (pair and (right.tag != .aggregate or right.fields.len != 2)) return self.unsupported(m, id);
        const operand = if (pair) right.fields[0] else if (n.op == .swizzle) right else left;
        if (operand.tag != .aggregate or operand.fields.len != 4) return self.unsupported(m, id);
        const floating = operand.fields[0].floating;
        const intrinsic = catalog.operation(n.op, if (floating) .f32 else .u32) orelse return self.unsupported(m, id);
        if (catalog.literalLanes(n.op)) {
            var lanes: [4]u32 = undefined;
            if (n.op == .broadcast) {
                const lane = self.knownLiteral(right) orelse return self.fail(m, id, .simd_lane_literal, "SIMD lane selectors must be literal integers");
                @memset(&lanes, lane);
            } else {
                if (left.tag != .aggregate or left.fields.len != 4) return self.unsupported(m, id);
                for (&lanes, left.fields) |*lane, field| lane.* = self.knownLiteral(field) orelse return self.fail(m, id, .simd_lane_literal, "SIMD lane selectors must be literal integers");
            }
            var lane_bits: u32 = 0;
            for (lanes, 0..) |lane, index| {
                if (lane >= catalog.laneLimit(n.op)) return self.fail(m, id, .simd_lane_literal, "SIMD lane selector is outside its source vectors");
                lane_bits |= lane << @intCast(index * 3);
            }
            const first = try self.vectorLocal(m, id, operand);
            const second = if (n.op == .shuffle) try self.vectorLocal(m, id, right.fields[1]) else first;
            try self.c.value(first);
            try self.c.value(second);
            try self.c.op(.i8x16_shuffle, lane_bits);
        } else if (pair) {
            const a = try self.vectorLocal(m, id, left);
            const b = try self.vectorLocal(m, id, right.fields[0]);
            const c = try self.vectorLocal(m, id, right.fields[1]);
            if (n.op == .select) {
                try self.c.value(b);
                try self.c.value(c);
                try self.c.value(a);
                try self.c.op(.v128_bitselect, 0);
            } else {
                try self.c.value(a);
                try self.c.value(b);
                try self.c.value(c);
                try self.c.op(if (n.op == .relaxed_madd) .f32x4_relaxed_madd else .f32x4_relaxed_nmadd, 0);
            }
        } else {
            const a = try self.vectorLocal(m, id, left);
            const b: ?Local = if (n.b == 0) null else if (intrinsic.shape == .shift) try self.scalar(m, id, right) else try self.vectorLocal(m, id, right);
            if ((n.op == .min or n.op == .max) and floating) {
                try self.c.value(b.?);
                try self.c.value(a);
            } else {
                try self.c.value(a);
                if (b) |value| try self.c.value(value);
            }
            const opcode: ?wasm.Op = switch (n.op) {
                .bits, .from_bits => null,
                .bit_not => .v128_not,
                .bit_andnot => .v128_andnot,
                .shift_left => .i32x4_shl,
                .shift_right => .i32x4_shr_u,
                .shift_right_signed => .i32x4_shr_s,
                .any_true => .v128_any_true,
                .all_true => .i32x4_all_true,
                .min => if (floating) .f32x4_pmin else .i32x4_min_u,
                .max => if (floating) .f32x4_pmax else .i32x4_max_u,
                .convert_i32_f32 => .f32x4_convert_i32x4_s,
                .convert_f32_i32 => .i32x4_trunc_sat_f32x4_s,
                .equal => if (floating) .f32x4_eq else .i32x4_eq,
                .not_equal => if (floating) .f32x4_ne else .i32x4_ne,
                .less => if (floating) .f32x4_lt else .i32x4_lt_u,
                .less_equal => if (floating) .f32x4_le else .i32x4_le_u,
                .greater => if (floating) .f32x4_gt else .i32x4_gt_u,
                .greater_equal => if (floating) .f32x4_ge else .i32x4_ge_u,
                else => blk: {
                    const scalar_op = @import("scalar_ops.zig").opcode(n.op, if (floating) .f32 else .u32) orelse return self.unsupported(m, id);
                    break :blk @import("runtime_ir.zig").lift(scalar_op) orelse return self.unsupported(m, id);
                },
            };
            if (opcode) |op| try self.c.op(op, 0);
        }
        if (intrinsic.shape == .reduce) {
            const result = try self.c.temp();
            try self.c.op(.local_set, result.id);
            return .{ .word = result };
        }
        const vector: Local = .{ .id = try self.module.addLocal(self.c.function, .v128) };
        try self.c.op(.local_set, vector.id);
        const result = try self.temporary(try self.shape(m, id, n.ty, 0));
        for (result.fields, 0..) |*field, lane| {
            try self.c.value(vector);
            try self.c.op(.i32x4_extract_lane, @intCast(lane));
            try self.c.op(.local_set, field.word.id);
        }
        return result;
    }
    fn primitive(self: *Generator, m: *const core.Module, id: core.Id, left: Value, right: Value) Error!Value {
        if (left.tag == .aggregate) return self.vectorPrimitive(m, id, left, right);
        const node = m.node(id);
        return self.scalarPrimitive(m, id, node.op, node.b != 0, left, right);
    }
    fn scalarPrimitive(self: *Generator, m: *const core.Module, id: core.Id, operation_: core.Op, binary: bool, left_value: Value, right_value: Value) Error!Value {
        const left = try self.scalar(m, id, left_value);
        const right = try self.scalar(m, id, right_value);
        var machine: wasm.Scalar = .u32;
        if (left_value.floating) machine = .f32;
        const opcode = scalar_ops.opcode(operation_, machine) orelse return self.unsupported(m, id);
        const floating = scalar_ops.resultScalar(operation_, machine) == .f32;
        if (self.knownConstant(left_value)) |a| {
            var b: ?u32 = 0;
            if (binary) b = self.knownConstant(right_value);
            if (b) |bits| {
                const folded = scalar_ops.evaluateExact(operation_, .{ .scalar = machine, .bits = a }, .{ .scalar = machine, .bits = bits }) catch null;
                if (folded) |constant_| {
                    var result = try self.constant(constant_.bits);
                    result.floating = constant_.scalar == .f32;
                    result.constant_bits = constant_.bits;
                    self.emission_work.scoped_scalar_constants_folded +|= 1;
                    return result;
                }
            }
        }
        const word = try self.c.temp();
        try self.c.value(left);
        if (left_value.floating) try self.c.op(.f32_reinterpret_i32, 0);
        if (binary) {
            try self.c.value(right);
            if (right_value.floating) try self.c.op(.f32_reinterpret_i32, 0);
        }
        try self.c.op(opcode, 0);
        if (floating) try self.c.op(.i32_reinterpret_f32, 0);
        try self.c.op(.local_set, word.id);
        return .{ .word = word, .floating = floating };
    }
    fn associated(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const node = m.node(id);
        const types_before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(types_before);
        const before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(before);
        const left = try self.expression(m, node.a, depth + 1);
        if (left.terminated) return left;
        try self.protected.append(self.allocator, left);
        const output: TypeRef = .{ .unit = m.unit, .ty = node.ty };
        const input = try self.operandType(.{ .unit = m.unit, .ty = m.typeOf(node.a) }, left);
        if (node.tag == .result_associated) {
            const resolved = try self.resolveType(output, 0);
            const owner = try self.unit(resolved.unit);
            const identity = T.receiverIdentity(owner.types.node(resolved.ty)) orelse return self.unsupported(m, id);
            const target = (try self.dispatchTarget(m, identity, node.b, .none)) orelse return self.unsupported(m, id);
            return (try self.dispatchCandidate(m, id, target, &.{input}, output, &.{left}, depth + 1)) orelse self.unsupported(m, id);
        }
        const right = try self.expression(m, node.b, depth + 1);
        if (right.terminated) return right;
        try self.protected.append(self.allocator, right);
        const inputs = [_]TypeRef{ input, try self.operandType(.{ .unit = m.unit, .ty = m.typeOf(node.b) }, right) };
        const operator: T.Operator = if (@backingInt(node.op) <= @backingInt(core.Op.shift_right)) @fromBackingInt(@intCast(@backingInt(node.op))) else .none;
        for (inputs, 0..) |subject, side| {
            if (side == 1 and node.tag == .scalar) {
                const first = try self.resolveType(inputs[0], 0);
                const second = try self.resolveType(inputs[1], 0);
                const a = (try self.unit(first.unit)).types.node(first.ty);
                const b = (try self.unit(second.unit)).types.node(second.ty);
                if (a.tag == b.tag and (a.tag == .u32 or a.tag == .f32 or (a.tag == .boolean and (node.op == .equal or node.op == .not_equal)))) return self.primitive(m, id, left, right);
            }
            const resolved = try self.resolveType(subject, 0);
            const owner = try self.unit(resolved.unit);
            const identity = T.receiverIdentity(owner.types.node(resolved.ty)) orelse continue;
            const target = (try self.dispatchTarget(m, identity, if (node.tag == .associated) node.c else 0, operator)) orelse continue;
            if (try self.dispatchCandidate(m, id, target, &inputs, output, &.{ left, right }, depth + 1)) |value| return value;
        }
        return self.unsupported(m, id);
    }
    fn getter(self: *Generator, m: *const core.Module, id: core.Id, value: Value, depth: usize) Error!Value {
        const projection = m.projection(m.node(id).b);
        const before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(before);
        var receiver = try self.resolveType(.{ .unit = m.unit, .ty = projection.source_type }, 0);
        var source = try self.unit(receiver.unit);
        if (T.receiverIdentity(source.types.node(receiver.ty)) == null) if (value.type_evidence) |evidence| {
            try self.restoreTypes(evidence.arguments);
            receiver = try self.resolveType(evidence.root, 0);
            source = try self.unit(receiver.unit);
        };
        const identity = T.receiverIdentity(source.types.node(receiver.ty)) orelse value.nominal orelse return self.unsupported(m, id);
        const target = (try self.fieldTarget(m, identity, projection.field)) orelse return self.unsupported(m, id);
        const owner = try self.unit(target.unit);
        const signature = owner.types.node(owner.binding(target.binding).ty);
        if (signature.tag != .function) return self.unsupported(m, id);
        try self.mapTypes(.{ .unit = owner.unit, .ty = signature.a }, receiver, 0);
        try self.mapTypes(.{ .unit = owner.unit, .ty = signature.b }, .{ .unit = m.unit, .ty = projection.result_type }, 0);
        return self.invokeAt(m, id, target, &.{value}, depth + 1);
    }
    fn namedPlace(self: *Generator, m: *const core.Module, id: core.Id, value: *const Value, name: u32) Error!*const Value {
        const spelling = m.fieldSpelling(name) orelse return self.unsupported(m, id);
        for (value.fields) |*field| if (std.mem.eql(u8, field.name, spelling)) return field;
        return self.unsupported(m, id);
    }
    fn dataPlace(value: *const Value, name: []const u8) ?*const Value {
        if (value.tag != .aggregate) return null;
        for (value.fields) |*field| if (std.mem.eql(u8, field.name, name)) return field;
        if (value.nominal != null and value.variant_tags.len == 0 and value.fields.len == 1) return dataPlace(&value.fields[0], name);
        return null;
    }
    fn projected(self: *Generator, m: *const core.Module, id: core.Id, value: *const Value, projection_id: u32) Error!*const Value {
        if (value.tag != .aggregate) return self.unsupported(m, id);
        const projection = m.projection(projection_id);
        const variants = m.projectionVariants(projection_id);
        if (variants.len == 0) if (m.fieldSpelling(projection.field)) |name| {
            if (dataPlace(value, name)) |field| return field;
        };
        if (projection.nominal.decl != 0) {
            if (value.nominal == null or !std.meta.eql(value.nominal.?, projection.nominal) or value.fields.len != 1 or variants.len != 1) return self.unsupported(m, id);
            for (m.constructors) |constructor| {
                if (!std.meta.eql(m.nominal(constructor.nominal).identity, projection.nominal) or constructor.tag != variants[0].tag) continue;
                const record = m.types.node(constructor.payload);
                if (record.tag != .record or variants[0].field >= record.b) return self.unsupported(m, id);
                return self.namedPlace(m, id, &value.fields[0], m.types.recordField(record, variants[0].field).name);
            }
        } else if (m.types.node(projection.source_type).tag == .record) {
            return self.namedPlace(m, id, value, projection.field);
        } else if (variants.len == 1 and variants[0].field < value.fields.len) return &value.fields[variants[0].field];
        return self.unsupported(m, id);
    }
    fn writableNamedPlace(self: *Generator, m: *const core.Module, id: core.Id, value: *Value, name: u32) Error!*Value {
        const spelling = m.fieldSpelling(name) orelse return self.unsupported(m, id);
        for (try self.writableFields(value)) |*field| if (std.mem.eql(u8, field.name, spelling)) return field;
        return self.unsupported(m, id);
    }
    fn writableDataPlace(self: *Generator, value: *Value, name: []const u8) Error!?*Value {
        if (value.tag != .aggregate) return null;
        // writableFields publishes the arena-owned vector in value.
        // zig-analyzer: disable-next-line unreleased-allocation
        const fields = try self.writableFields(value);
        for (fields) |*field| if (std.mem.eql(u8, field.name, name)) return field;
        if (value.nominal != null and value.variant_tags.len == 0 and fields.len == 1) return self.writableDataPlace(&fields[0], name);
        return null;
    }
    fn writableProjected(self: *Generator, m: *const core.Module, id: core.Id, value: *Value, projection_id: u32) Error!*Value {
        if (value.tag != .aggregate) return self.unsupported(m, id);
        const projection = m.projection(projection_id);
        const variants = m.projectionVariants(projection_id);
        if (variants.len == 0) if (m.fieldSpelling(projection.field)) |name| {
            if (try self.writableDataPlace(value, name)) |field| return field;
        };
        if (projection.nominal.decl != 0) {
            if (value.nominal == null or !std.meta.eql(value.nominal.?, projection.nominal) or value.fields.len != 1 or variants.len != 1) return self.unsupported(m, id);
            for (m.constructors) |constructor| {
                if (!std.meta.eql(m.nominal(constructor.nominal).identity, projection.nominal) or constructor.tag != variants[0].tag) continue;
                const record = m.types.node(constructor.payload);
                if (record.tag != .record or variants[0].field >= record.b) return self.unsupported(m, id);
                return self.writableNamedPlace(m, id, &(try self.writableFields(value))[0], m.types.recordField(record, variants[0].field).name);
            }
        } else if (m.types.node(projection.source_type).tag == .record) {
            return self.writableNamedPlace(m, id, value, projection.field);
        } else if (variants.len == 1 and variants[0].field < value.fields.len) return &(try self.writableFields(value))[variants[0].field];
        return self.unsupported(m, id);
    }
    fn projectValue(self: *Generator, m: *const core.Module, id: core.Id, original: Value, depth: usize) Error!Value {
        var value = original;
        if (value.terminated) return value;
        const projection = m.node(id).b;
        if (m.projection(projection).variants.len == 0) {
            if (m.fieldSpelling(m.projection(projection).field)) |spelling| if (dataField(value, spelling)) |field| return field;
            return self.getter(m, id, value, depth + 1);
        }
        return (try self.projected(m, id, &value, projection)).*;
    }
    const LiteralProjection = struct { owner: *const core.Module, body: *const core.Body, binding: core.BindingId, constant: core.Id, fields: usize };
    fn intrinsicConstant(m: *const core.Module, id: core.Id) bool {
        const node = m.node(id);
        return node.tag == .constant and node.ty >= T.unit and node.ty <= T.f32_type;
    }
    fn literalProjectionPlan(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) ?LiteralProjection {
        // The skipped reference must fit the ordinary expression-depth bound.
        if (depth >= 128) return null;
        const project = m.node(id);
        const reference = m.node(project.a);
        if (reference.tag != .reference) return null;
        var target = m.reference(project.a);
        if (target.unit == 0) target.unit = m.unit;
        if (target.unit == 0 or target.unit > self.units.len) return null;
        const owner = &self.units[target.unit - 1];
        const binding = owner.binding(target.binding);
        const body = owner.body(target.binding) orelse return null;
        if (binding.kind != .global or body.runtime or body.is_function or owner.bodyParameters(body).len != 0) return null;
        // Ordinary references prefer an active binding/capture to the global
        // declaration, even when its source identity names a global binding.
        for (self.bindings.items) |active| if (active.unit == target.unit and active.id == target.binding) return null;
        for ([_]T.Scheme{ binding.scheme, body.scheme }) |scheme| {
            if (scheme.variables.len != 0 or scheme.row_variables.len != 0 or scheme.generative.len != 0 or scheme.obligations.len != 0) return null;
        }
        if (binding.public_variables.len != 0 or binding.public_rows.len != 0) return null;
        const construct = owner.node(body.root);
        if (construct.tag != .construct or construct.b == 0 or construct.c != 0) return null;
        const constructor = owner.constructor(construct.a);
        const nominal = owner.nominal(constructor.nominal);
        if (nominal.parameters.len != 0 or nominal.variables.len != 0 or nominal.is_opaque or nominal.has_usage or nominal.affine or owner.nominalConstructors(constructor.nominal).len != 1) return null;
        const projection = m.projection(project.b);
        const variants = m.projectionVariants(project.b);
        if (projection.nominal.decl == 0 or !std.meta.eql(projection.nominal, nominal.identity) or variants.len != 1 or variants[0].tag != constructor.tag) return null;
        const payload = owner.types.node(constructor.payload);
        if (payload.tag != .record) return null;
        // The projection's ordinal belongs to the caller's imported catalog,
        // whose field dictionary/order need not match the producer's.
        const name = for (m.constructors) |candidate| {
            if (!std.meta.eql(m.nominal(candidate.nominal).identity, projection.nominal) or candidate.tag != variants[0].tag) continue;
            const caller_payload = m.types.node(candidate.payload);
            if (caller_payload.tag != .record or variants[0].field >= caller_payload.b) return null;
            break m.fieldSpelling(m.types.recordField(caller_payload, variants[0].field).name) orelse return null;
        } else return null;
        const record = owner.node(construct.b);
        if (record.tag != .record) return null;
        const schema = owner.types.node(record.ty);
        const children = owner.children(construct.b);
        if (schema.tag != .record or schema.b != children.len or schema.b != payload.b or children.len > 4096 - 3) return null;
        self.emission_work.scoped_literal_projection_preflight_nodes +|= 3;
        var selected: ?core.Id = null;
        // Children execute in source order. Destinations identify the record
        // type's fields; neither their ordinal nor the constructor's ordinal
        // is the source child's position.
        for (children, owner.recordDestinations(construct.b)) |child, destination| {
            self.emission_work.scoped_literal_projection_preflight_nodes +|= 1;
            if (!intrinsicConstant(owner, child) or destination >= schema.b) return null;
            const field = owner.types.recordField(schema, destination);
            if (field.ty != owner.node(child).ty) return null;
            const spelling = owner.fieldSpelling(field.name) orelse return null;
            if (std.mem.eql(u8, name, spelling)) selected = child;
        }
        return .{ .owner = owner, .body = body, .binding = target.binding, .constant = selected orelse return null, .fields = children.len };
    }
    fn literalRecordProjection(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!?Value {
        const plan = self.literalProjectionPlan(m, id, depth) orelse return null;
        const project = m.node(id);
        const expected = self.resolveType(.{ .unit = m.unit, .ty = m.projection(project.b).result_type }, 0) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.Declined => return null,
        };
        if (expected.unit == 0 or expected.unit > self.units.len) return null;
        const expected_owner = &self.units[expected.unit - 1];
        const literal = plan.owner.node(plan.constant);
        if (expected_owner.types.node(expected.ty).tag != plan.owner.types.node(literal.ty).tag) return null;
        try self.chargeExpression(m, project.a, depth + 1);
        try self.checkSourceBody(plan.owner, plan.body, plan.binding);
        var value = try self.constant(literal.a);
        value.literal = if (literal.ty == T.u32_type) literal.a else null;
        value.constant_bits = literal.a;
        value.floating = literal.ty == T.f32_type;
        value.type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = plan.owner.unit, .ty = literal.ty }, .arguments = &.{} });
        self.emission_work.scoped_literal_record_projections +|= 1;
        self.emission_work.scoped_literal_projection_fields_skipped +|= plan.fields - 1;
        return value;
    }
    fn indexedProjection(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!?Value {
        const projection = m.node(id);
        const read = m.node(projection.a);
        if (read.tag != .array_op or m.arrayOperation(projection.a) != .get) return null;
        const inputs = m.children(projection.a);
        if (inputs.len != 2) return null;
        try self.chargeExpression(m, projection.a, depth + 1);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        const array_value = try self.expression(m, inputs[0], depth + 3);
        if (array_value.terminated) return array_value;
        try self.protected.append(self.allocator, array_value);
        const subscript = try self.expression(m, inputs[1], depth + 3);
        if (subscript.terminated) return subscript;
        try self.protected.append(self.allocator, subscript);
        const index = try self.elementIndex(m, projection.a, array_value, try self.scalar(m, projection.a, subscript));
        const place = try self.readElementPlace(m, projection.a, array_value, index) orelse return try self.terminated();
        if (plainInlineValue(place.element) and stableDescriptorShape(place.element)) {
            var schema = place.element;
            const diagnostic_before = self.diagnostic;
            const selected: ?*const Value = self.projected(m, id, &schema, projection.b) catch |err| blk: {
                if (err == error.OutOfMemory) return err;
                self.diagnostic = diagnostic_before;
                break :blk null;
            };
            if (selected) |field| {
                const offset = try fieldOffset(&schema, field) orelse return self.unsupported(m, id);
                return try self.loadValue(place.address, offset, field.*);
            }
        }
        const loaded = try self.loadValue(place.address, 0, place.element);
        self.protected.shrinkRetainingCapacity(protected_before);
        const value = try self.expressionEvidence(m, projection.a, loaded);
        return try self.projectValue(m, id, value, depth);
    }
    fn fieldOffset(value: *const Value, target: *const Value) Error!?u32 {
        if (value == target) return 0;
        var offset: u32 = 0;
        for (value.fields) |*field| {
            if (try fieldOffset(field, target)) |nested| return offset + nested;
            offset += try width(field.*);
        }
        return null;
    }
    fn updateValue(self: *Generator, m: *const core.Module, id: core.Id, original: Value, at: usize, depth: usize) Error!Value {
        if (depth > 128) return self.unsupported(m, id);
        const info = m.updateInfo(id);
        const selectors = m.updateSelectors(id);
        const path = m.updatePath(id);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        try self.protected.append(self.allocator, original);
        if (at == @max(selectors.len, path.len)) {
            const before = self.bindings.items.len;
            defer self.bindings.shrinkRetainingCapacity(before);
            try self.bind(m, info.self_binding, original);
            return self.expression(m, info.value, depth + 1);
        }
        var value = original;
        if (selectors.len != 0 and selectors[at].kind == .index) {
            const index_value = try self.expression(m, selectors[at].index, depth + 1);
            if (index_value.terminated) return index_value;
            const index = try self.scalar(m, id, index_value);
            const place = try self.readElementPlace(m, id, value, index) orelse return self.terminated();
            const selected_only = at + 1 < @max(selectors.len, path.len) and plainInlineValue(place.element) and stableDescriptorShape(place.element);
            var selected: Value = undefined;
            var replacement_budget: usize = 64;
            const scalar_replacement = at + 1 == @max(selectors.len, path.len) and
                !self.scalar_admission.hasScalarReferences() and place.element.tag == .scalar and
                place.element.fields.len == 0 and place.element.root == null and place.element.other_roots.len == 0 and
                place.element.host == null and place.element.callable == null and place.element.nominal == null and
                place.element.variant_tags.len == 0 and
                independentScalarReplacement(m, info.value, info.self_binding, 0, &replacement_budget);
            if (selected_only) {
                selected = place.element;
            } else if (scalar_replacement) {
                // Self is unreachable in this RHS. Keep only its checked type
                // shape; no old scalar bits or literal evidence are available.
                selected = .{ .word = .{ .id = 0 }, .floating = place.element.floating, .name = place.element.name, .type_evidence = place.element.type_evidence };
                self.emission_work.scoped_scalar_old_loads_avoided +|= 1;
            } else {
                selected = try self.loadValue(place.address, 0, place.element);
            }
            // Selecting a writable element pins its extent throughout RHS
            // evaluation, including nested calls. Growth keeps it in place.
            var selected_borrow = value;
            selected_borrow.tag = .ref;
            selected_borrow.index = index;
            try self.protected.append(self.allocator, selected_borrow);
            var leaf = &selected;
            var offset: u32 = 0;
            var next = at + 1;
            while (next < @max(selectors.len, path.len)) : (next += 1) {
                if (selectors.len != 0 and selectors[next].kind == .index) return self.unsupported(m, id);
                const projection = if (selectors.len != 0) selectors[next].projection else path[next];
                const field = try self.writableProjected(m, id, leaf, projection);
                offset += (try fieldOffset(leaf, field)) orelse return self.unsupported(m, id);
                leaf = field;
            }
            if (selected_only) leaf.* = try self.loadValue(place.address, offset, leaf.*);
            const replacement = try self.updateValue(m, id, leaf.*, next, depth + 1);
            if (replacement.terminated) return replacement;
            const name = leaf.name;
            leaf.* = replacement;
            leaf.name = name;
            for (self.roots.items, 0..) |*owner, root_id| if (hasRoot(value, root_id)) {
                try self.storedShape(m, id, &owner.element, selected, owner.depth);
                owner.known_empty = false;
            };
            try self.writerEvent(m, id, value, .write);
            // Write the selected place only. The RHS may have written other
            // fields through an alias; rebuilding the row would erase them.
            // The selected borrow pins this nonmoving extent across the RHS,
            // so its pre-RHS checked address remains valid after growth too.
            try self.storeValue(place.address, offset, replacement);
        } else {
            const projection = if (selectors.len != 0) selectors[at].projection else path[at];
            const field = try self.writableProjected(m, id, &value, projection);
            const name = field.name;
            const replacement = try self.updateValue(m, id, field.*, at + 1, depth + 1);
            if (replacement.terminated) return replacement;
            field.* = replacement;
            field.name = name;
        }
        return value;
    }
    fn indexedUpdate(self: *Generator, m: *const core.Module, id: core.Id, original: Value, depth: usize) Error!?Value {
        const selectors = m.updateSelectors(id);
        const first = for (selectors, 0..) |selector, index| {
            if (selector.kind == .index) break index;
        } else return null;
        if (self.scalar_admission.hasScalarReferences()) return null;
        if (depth + 1 + first > 128) return self.unsupported(m, id);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        try self.protected.append(self.allocator, original);
        var receiver = original;
        for (selectors[0..first]) |selector| receiver = (try self.projected(m, id, &receiver, selector.projection)).*;
        // The indexed branch writes the selected owner and preserves its
        // descriptor. Its enclosing access record therefore remains identical;
        // no scalar address can mutate an unchanged lane during the RHS.
        const updated = try self.updateValue(m, id, receiver, first, depth + 1 + first);
        if (updated.terminated) return updated;
        self.emission_work.scoped_indexed_update_roots_shared +|= 1;
        return original;
    }
    fn bulkDescriptor(self: *Generator, m: *const core.Module, reference: core.BindingRef, carries: []const core.LoopCarry, scalar_type: T.Id) ?@import("wasm_bulk_loop.zig").Descriptor {
        if (reference.unit != m.unit) return null;
        var binding = reference.binding;
        for (carries) |carry| if (carry.iteration == binding) {
            binding = carry.incoming;
            break;
        };
        var found: ?Value = null;
        for (self.bindings.items) |input| if (input.unit == m.unit and input.id == binding) {
            found = input.value;
        };
        const value = found orelse return null;
        if (value.tag != .array or value.mode != .fixed or value.other_roots.len != 0 or value.host != null) return null;
        const owner = self.roots.items[value.root orelse return null];
        if (!owner.live or owner.imported_global or owner.element.tag != .scalar or owner.element.fields.len != 0 or owner.element.root != null or owner.element.host != null) return null;
        if (owner.element.floating != (scalar_type == T.f32_type)) return null;
        if (value.word.id != owner.word.id or value.token.id != owner.token.id or value.epoch_low.id != owner.epoch_low.id or value.epoch_high.id != owner.epoch_high.id) return null;
        return .{ .word = value.word.id, .token = value.token.id, .epoch_low = value.epoch_low.id, .epoch_high = value.epoch_high.id };
    }
    fn mergeSpan(self: *Generator, m: *const core.Module, binding: core.BindingId, carries: []const core.LoopCarry) ?@import("wasm_merge_loop.zig").Span {
        const descriptor = self.bulkDescriptor(m, .{ .unit = m.unit, .binding = binding }, carries, T.u32_type) orelse return null;
        for (self.roots.items) |owner| {
            if (owner.word.id != descriptor.word or owner.token.id != descriptor.token or owner.epoch_low.id != descriptor.epoch_low or owner.epoch_high.id != descriptor.epoch_high) continue;
            const span = owner.fixed_span orelse return null;
            return .{ .word = descriptor.word, .token = descriptor.token, .epoch_low = descriptor.epoch_low, .epoch_high = descriptor.epoch_high, .length = span.length.id, .ready = if (span.ready) |ready| ready.id else null };
        }
        return null;
    }
    fn mergeScalar(self: *Generator, m: *const core.Module, binding: core.BindingId, carries: []const core.LoopCarry, values: []const Value) ?u32 {
        var found: ?Value = null;
        for (carries, values) |carry, value| if (carry.iteration == binding) {
            found = value;
            break;
        };
        if (found == null) for (self.bindings.items) |input| {
            if (input.unit == m.unit and input.id == binding) found = input.value;
        };
        const value = found orelse return null;
        if (value.tag != .scalar or value.floating or value.fields.len != 0 or value.root != null or value.host != null or value.other_roots.len != 0) return null;
        return value.word.id;
    }
    fn lanePrimitiveMember(context: *anyopaque, m: *const core.Module, member: u32) @import("wasm_lane_loop.zig").Error!?core.Op {
        const self: *Generator = @ptrCast(@alignCast(context));
        const identity = T.receiverIdentity(m.types.node(T.u32_type)) orelse return null;
        const target = (try self.dispatchTarget(m, identity, member, .none)) orelse return null;
        const owner = try self.unit(target.unit);
        const body = owner.body(target.binding) orelse return null;
        if (owner.bodyParameters(body).len != 0 or owner.node(body.root).tag != .primitive_function) return null;
        const primitive_ = owner.primitive(body.root);
        if (primitive_.kind != .scalar or primitive_.arity != 2) return null;
        return primitive_.op;
    }
    fn lanePrimitiveOperators(self: *Generator, m: *const core.Module, operators: std.EnumSet(core.Op)) Error!bool {
        var iterator = operators.iterator();
        while (iterator.next()) |op| {
            if (@backingInt(op) > @backingInt(core.Op.shift_right)) return false;
            const identity = T.receiverIdentity(m.types.node(T.u32_type)) orelse return false;
            const target = (try self.dispatchTarget(m, identity, 0, @fromBackingInt(@intCast(@backingInt(op))))) orelse continue;
            const owner = try self.unit(target.unit);
            const body = owner.body(target.binding) orelse return false;
            if (owner.node(body.root).tag != .primitive_function or owner.bodyParameters(body).len != 0) return false;
            const primitive_ = owner.primitive(body.root);
            if (primitive_.kind != .scalar or primitive_.arity != 2 or primitive_.op != op) return false;
        }
        return true;
    }
    fn publishLoop(self: *Generator, start: usize, detached: *@import("runtime_ir.zig").Body) Error!void {
        const machine = &self.module.functions.items[self.c.function];
        try machine.locals.ensureUnusedCapacity(self.allocator, detached.locals.items.len);
        try machine.instructions.ensureTotalCapacity(self.allocator, start + detached.instructions.items.len);
        machine.locals.appendSliceAssumeCapacity(detached.locals.items);
        machine.instructions.shrinkRetainingCapacity(start);
        machine.instructions.appendSliceAssumeCapacity(detached.instructions.items);
        self.span_scopes.reset();
        self.bundle_snapshots.clearRetainingCapacity();
        self.bundle_sources.clearRetainingCapacity();
        self.bundle_scan = machine.instructions.items.len;
    }
    fn emitLoop(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const info = m.loopInfo(id);
        const collection_value: ?Value = if (info.kind == .array) try self.expression(m, info.first, depth + 1) else null;
        if (collection_value) |value| if (value.terminated) return value;
        const first_value = if (info.kind == .range) try self.expression(m, info.first, depth + 1) else try self.constant(0);
        if (first_value.terminated) return first_value;
        const first = try self.scalar(m, id, first_value);
        const end_value: ?Value = if (info.kind == .range) try self.expression(m, info.end, depth + 1) else null;
        if (end_value) |value| if (value.terminated) return value;
        const end = if (end_value) |value| try self.scalar(m, id, value) else if (collection_value) |value| try self.length(m, id, value) else first;
        const iterator = try self.c.temp();
        try self.c.set(iterator, first);
        const roots_before = self.roots.items.len;
        const bindings_before = self.bindings.items.len;
        const pinned_before = self.protected.items.len;
        const read_frame = try self.beginReadFrame();
        defer self.read_frames.shrinkRetainingCapacity(read_frame);
        defer self.protected.shrinkRetainingCapacity(pinned_before);
        if (collection_value) |value| {
            var traversal = value;
            traversal.tag = .view;
            try self.protected.append(self.allocator, traversal);
        }
        const uses = @import("storage_liveness.zig").count(self.allocator, m, info.body) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, id);
        };
        defer self.allocator.free(uses);
        for (self.bindings.items) |binding| if (binding.unit == m.unit and binding.id < uses.len and uses[binding.id] != 0) {
            try self.protected.append(self.allocator, binding.value);
        };
        const carries = m.loopCarries(id);
        const values = try self.arena.allocator().alloc(Value, carries.len);
        const headers = try self.arena.allocator().alloc(Value, carries.len);
        const shared = try self.arena.allocator().alloc(LoopSharing, carries.len);
        @memset(shared, .{});
        const transport = try self.transportIndex(m);
        for (values, carries, headers, shared, 0..) |*value, carry, *header, *reuse, ordinal| {
            const incoming = try self.bindingValue(m, carry.incoming);
            if (!@import("storage_control.zig").fixedCarry(incoming)) return self.unsupported(m, id);
            const fixed_array = incoming.tag == .array and incoming.mode == .fixed and incoming.root != null and incoming.other_roots.len == 0;
            if (transport) |index| if (incoming.tag == .aggregate or fixed_array) {
                reuse.whole = try index.invariant(id, ordinal);
                if (incoming.tag == .aggregate and !reuse.whole and !self.scalar_admission.hasScalarReferences() and incoming.variant_tags.len == 0 and incoming.nominal == null and incoming.host == null and incoming.root == null) {
                    var named = incoming.fields.len != 0;
                    for (incoming.fields) |field| {
                        if (field.name.len == 0) named = false;
                    }
                    if (named) {
                        const fields = try self.arena.allocator().alloc(bool, incoming.fields.len);
                        for (fields, incoming.fields) |*field, input| field.* = try index.invariantField(id, ordinal, input.name);
                        reuse.fields = fields;
                    }
                }
            };
            value.* = try self.loopTemporary(incoming, reuse.*);
            try self.assignLoop(m, id, value, incoming, reuse.*);
            try self.loopHeader(value);
            header.* = value.*;
        }
        // Retain this inventory beyond loop pop: a surrounding return join
        // can finish after the loop whose physical carriers it observed.
        for (values) |value| try self.markMutableWords(value, &self.mutable_join_words);
        try self.mutable_join_words.put(self.allocator, iterator.id, {});
        const loop_code_start = self.module.functions.items[self.c.function].instructions.items.len;
        const helpers_before = self.outlining.helpers.items.len;
        try self.c.op(.block, 0);
        try self.c.op(.loop, 0);
        self.nesting += 2;
        const frame_mark = try self.frameMark();
        try self.loops.append(self.allocator, .{ .unit = m.unit, .id = id, .nesting = self.nesting, .roots_before = roots_before, .carries = values, .shared = shared, .headers = headers, .iterator = if (info.kind != .forever) iterator else null, .mark = frame_mark, .depth = self.depth + 1, .read_frame = read_frame });
        defer _ = self.loops.pop();
        if (info.kind != .forever) {
            try self.c.value(.{ .i32_ge_u, iterator, end });
            try self.c.op(.br_if, 1);
        }
        self.depth += 1;
        for (carries, values) |carry, value| try self.bind(m, carry.iteration, value);
        var unreachable_item: ?Value = null;
        if (info.pattern != 0) {
            const item = if (collection_value) |value| try self.readElement(m, id, value, try self.elementIndex(m, id, value, iterator)) else Value{ .word = iterator };
            if (item.terminated) unreachable_item = item else try self.pattern(m, info.pattern, item);
        }
        const iteration_start = self.module.functions.items[self.c.function].instructions.items.len;
        const body = unreachable_item orelse try self.expression(m, info.body, depth + 1);
        if (!body.terminated) {
            try self.checkReadFrame(m, id, read_frame);
            const next_values = try self.arena.allocator().alloc(Value, carries.len);
            for (carries, next_values, shared) |carry, *next, reuse| {
                next.* = try self.loopSnapshot(try self.bindingValue(m, carry.backedge), reuse);
                try self.checkEscape(m, id, next.*, self.depth);
            }
            for (values, next_values, headers, shared) |*value, next, header, reuse| {
                if (!@import("storage_control.zig").stableCarry(value.*, next)) return self.fail(m, id, .storage_escape, "A loop must retain the same named owners and borrowed roots across iterations");
                if (!includesReadShape(header, next)) return self.fail(m, id, .storage_escape, "A loop cannot activate a variant without complete incoming payload evidence");
                try self.assignLoop(m, id, value, next, reuse);
            }
        }
        const iteration_end = self.module.functions.items[self.c.function].instructions.items.len;
        // A conditional return reserves its result's static slot for the
        // caller, but the path reaching this backedge did not return it.
        // Rewind that iteration too; the next iteration reopens the same slot.
        try self.closeRuntime(roots_before, try self.unitValue());
        try self.release(roots_before, null);
        try self.rewindUnescaped(roots_before, frame_mark, try self.unitValue());
        self.depth -= 1;
        self.bindings.shrinkRetainingCapacity(bindings_before);
        if (info.kind != .forever) try self.c.next(iterator);
        try self.c.op(.br, 0);
        try self.c.end();
        try self.c.end();
        self.nesting -= 2;
        if (info.kind == .forever and !body.terminated and roots_before == self.roots.items.len and !self.scalar_admission.hasScalarReferences() and self.outlining.helpers.items.len == helpers_before and self.outlining.canRewriteSuffix(self.c.function, loop_code_start)) reduce_block: {
            const reduce = @import("wasm_stride_reduce.zig");
            const source = reduce.source(m, id) orelse break :reduce_block;
            const array_span = self.mergeSpan(m, source.array, carries) orelse break :reduce_block;
            const cursor = self.mergeScalar(m, source.cursor, carries, values) orelse break :reduce_block;
            const limit = self.mergeScalar(m, source.limit, carries, values) orelse break :reduce_block;
            const last = self.mergeScalar(m, source.last, carries, values) orelse break :reduce_block;
            const count = self.mergeScalar(m, source.count, carries, values) orelse break :reduce_block;
            const coordinates = [_]u32{ cursor, limit, last, count };
            for (coordinates, 0..) |coordinate, index| for (coordinates[index + 1 ..]) |other| {
                if (coordinate == other) break :reduce_block;
            };
            const machine = &self.module.functions.items[self.c.function];
            if (machine.instructions.items.len - loop_code_start > 4096) break :reduce_block;
            var detached = try reduce.emit(self.allocator, machine.instructions.items[loop_code_start..], .{
                .array = array_span,
                .cursor = cursor,
                .limit = limit,
                .last = last,
                .count = count,
                .stride = source.stride,
                .bits = source.bits,
                .length_function = self.runtime.functions.length,
                .next_local = @intCast(machine.parameters.len + machine.locals.items.len),
            });
            defer detached.deinit(self.allocator);
            try self.publishLoop(loop_code_start, &detached);
            self.emission_work.scoped_stride_reductions +|= 1;
        }
        if (info.kind == .forever and !body.terminated and roots_before == self.roots.items.len and !self.scalar_admission.hasScalarReferences() and self.outlining.helpers.items.len == helpers_before and self.outlining.canRewriteSuffix(self.c.function, loop_code_start)) merge_block: {
            const merge = @import("wasm_merge_loop.zig");
            const source = merge.source(m, id) orelse break :merge_block;
            const first_array = self.mergeSpan(m, source.first_array, carries) orelse break :merge_block;
            const second_array = self.mergeSpan(m, source.second_array, carries) orelse break :merge_block;
            const target = self.mergeSpan(m, source.target, carries) orelse break :merge_block;
            const first_cursor = self.mergeScalar(m, source.first, carries, values) orelse break :merge_block;
            const second_cursor = self.mergeScalar(m, source.second, carries, values) orelse break :merge_block;
            const output_cursor = self.mergeScalar(m, source.output, carries, values) orelse break :merge_block;
            if (first_cursor == second_cursor or first_cursor == output_cursor or second_cursor == output_cursor) break :merge_block;
            const first_limit = self.mergeScalar(m, source.first_limit, carries, values) orelse break :merge_block;
            const second_limit = self.mergeScalar(m, source.second_limit, carries, values) orelse break :merge_block;
            const machine = &self.module.functions.items[self.c.function];
            if (machine.instructions.items.len - loop_code_start > 4096) break :merge_block;
            var detached = try merge.emit(self.allocator, .{
                .first_array = first_array,
                .second_array = second_array,
                .target = target,
                .first = first_cursor,
                .second = second_cursor,
                .output = output_cursor,
                .first_limit = first_limit,
                .second_limit = second_limit,
                .length_function = self.runtime.functions.length,
                .next_local = @intCast(machine.parameters.len + machine.locals.items.len),
            });
            defer detached.deinit(self.allocator);
            try machine.locals.ensureUnusedCapacity(self.allocator, detached.locals.items.len);
            try machine.instructions.ensureTotalCapacity(self.allocator, loop_code_start + detached.instructions.items.len);
            machine.locals.appendSliceAssumeCapacity(detached.locals.items);
            machine.instructions.shrinkRetainingCapacity(loop_code_start);
            machine.instructions.appendSliceAssumeCapacity(detached.instructions.items);
            self.span_scopes.reset();
            self.bundle_snapshots.clearRetainingCapacity();
            self.bundle_sources.clearRetainingCapacity();
            self.bundle_scan = machine.instructions.items.len;
            self.emission_work.scoped_merge_loops +|= 1;
        }
        if (info.kind == .range and !info.can_exit and !body.terminated and roots_before == self.roots.items.len and !self.scalar_admission.hasScalarReferences() and self.outlining.helpers.items.len == helpers_before and self.outlining.canRewriteSuffix(self.c.function, loop_code_start)) lane_block: {
            const lane = @import("wasm_lane_loop.zig");
            const source = (lane.source(self.units, m, id, .{ .context = self, .resolve = lanePrimitiveMember }) catch |err| {
                if (err == error.OutOfMemory) return err;
                break :lane_block;
            }) orelse break :lane_block;
            const primitive_operators = self.lanePrimitiveOperators(m, source.associated_ops) catch |err| {
                if (err == error.OutOfMemory) return err;
                break :lane_block;
            };
            if (!primitive_operators) break :lane_block;
            const state = self.bulkDescriptor(m, source.state, carries, T.u32_type) orelse break :lane_block;
            const input = self.bulkDescriptor(m, source.input, carries, T.u32_type) orelse break :lane_block;
            const machine = &self.module.functions.items[self.c.function];
            const plan: lane.Plan = .{
                .state = state,
                .input = input,
                .iterator = iterator.id,
                .end = end.id,
                .length_function = self.runtime.functions.length,
                .next_local = @intCast(machine.parameters.len + machine.locals.items.len),
            };
            var replacement = try lane.emitSimd(self.allocator, machine.instructions.items[loop_code_start..], iteration_start - loop_code_start, iteration_end - loop_code_start, source, plan);
            const simd = replacement != null;
            if (replacement == null) replacement = try lane.emit(self.allocator, machine.instructions.items[loop_code_start..], iteration_start - loop_code_start, iteration_end - loop_code_start, source, plan);
            if (replacement) |output| {
                var detached = output;
                defer detached.deinit(self.allocator);
                try self.publishLoop(loop_code_start, &detached);
                self.emission_work.scoped_lane_loops +|= 1;
                if (simd) self.emission_work.scoped_lane_simd_loops +|= 1;
            }
        }
        if (info.kind == .range and !info.can_exit and !body.terminated and !self.scalar_admission.hasScalarReferences() and self.outlining.helpers.items.len == helpers_before and self.outlining.canRewriteSuffix(self.c.function, loop_code_start)) bulk_block: {
            const bulk = @import("wasm_bulk_loop.zig");
            const source = bulk.source(m, id) orelse break :bulk_block;
            const target = self.bulkDescriptor(m, source.target, carries, source.scalar) orelse break :bulk_block;
            var replacement: @FieldType(bulk.Plan, "replacement") = undefined;
            switch (source.replacement) {
                .copy => |input| replacement = .{ .copy = self.bulkDescriptor(m, input, carries, source.scalar) orelse break :bulk_block },
                .fill => |bits| replacement = .{ .fill = bits },
            }
            const machine = &self.module.functions.items[self.c.function];
            if (try bulk.emit(self.allocator, machine.instructions.items[loop_code_start..], iteration_start - loop_code_start, iteration_end - loop_code_start, .{
                .target = target,
                .replacement = replacement,
                .iterator = iterator.id,
                .end = end.id,
                .length_function = self.runtime.functions.length,
                .next_local = @intCast(machine.parameters.len + machine.locals.items.len),
            })) |output| {
                var detached = output;
                defer detached.deinit(self.allocator);
                try machine.locals.ensureUnusedCapacity(self.allocator, detached.locals.items.len);
                try machine.instructions.ensureTotalCapacity(self.allocator, loop_code_start + detached.instructions.items.len);
                machine.locals.appendSliceAssumeCapacity(detached.locals.items);
                machine.instructions.shrinkRetainingCapacity(loop_code_start);
                machine.instructions.appendSliceAssumeCapacity(detached.instructions.items);
                self.span_scopes.reset();
                self.bundle_snapshots.clearRetainingCapacity();
                self.bundle_sources.clearRetainingCapacity();
                self.bundle_scan = machine.instructions.items.len;
                switch (source.replacement) {
                    .copy => self.emission_work.scoped_bulk_copies +|= 1,
                    .fill => self.emission_work.scoped_bulk_fills +|= 1,
                }
            }
        }
        if (info.kind == .range and !info.can_exit and !body.terminated and values.len == 1 and !self.scalar_admission.hasScalarReferences() and self.outlining.helpers.items.len == helpers_before and self.outlining.canRewriteSuffix(self.c.function, loop_code_start)) {
            const start_node = m.node(info.first);
            const end_node = m.node(info.end);
            const value = values[0];
            const exact_u32 = m.types.node(m.binding(carries[0].iteration).ty).tag == .u32 and value.tag == .scalar and !value.floating and value.fields.len == 0 and value.root == null and value.other_roots.len == 0 and value.host == null;
            if (exact_u32 and start_node.tag == .constant and end_node.tag == .constant and start_node.ty == T.u32_type and end_node.ty == T.u32_type and end_node.a > start_node.a and end_node.a - start_node.a <= 8) {
                const recurrence = @import("wasm_bit_recurrence.zig");
                const machine = &self.module.functions.items[self.c.function];
                const shell = recurrence.canonicalLoop(machine.instructions.items[loop_code_start..], iteration_start - loop_code_start, iteration_end - loop_code_start, iterator.id, end.id);
                if (shell) if (recurrence.analyzeLoop(self.module, machine.instructions.items[iteration_start..iteration_end], value.word.id, iterator.id, end.id, end_node.a - start_node.a)) |transform| {
                    if (try recurrence.emit(self.allocator, transform, value.word.id)) |replacement| {
                        var output = replacement;
                        defer output.deinit(self.allocator);
                        try machine.instructions.ensureTotalCapacity(self.allocator, loop_code_start + output.instructions.items.len);
                        machine.instructions.shrinkRetainingCapacity(loop_code_start);
                        machine.instructions.appendSliceAssumeCapacity(output.instructions.items);
                        self.bundle_snapshots.clearRetainingCapacity();
                        self.bundle_sources.clearRetainingCapacity();
                        self.bundle_scan = machine.instructions.items.len;
                        self.span_scopes.reset();
                        self.emission_work.scoped_bit_recurrences +|= 1;
                        self.emission_work.scoped_bit_rounds_removed +|= end_node.a - start_node.a;
                    }
                };
            }
        }
        for (carries, values) |carry, value| try self.bind(m, carry.outgoing, value);
        return self.unitValue();
    }
    fn chargeExpression(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!void {
        if (self.steps >= self.work_limits.expressions) return self.fail(m, id, .storage_unsupported, "Storage source expansion exceeded its expression budget");
        self.steps += 1;
        self.emission_work.scoped_emission_expressions +|= 1;
        self.emission_work.max_scoped_emission_body_steps = @max(self.emission_work.max_scoped_emission_body_steps, self.steps);
        if (depth > 128) return self.fail(m, id, .storage_unsupported, "Storage source expansion exceeded its nesting bound");
    }
    fn expression(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        return self.expressionEvidence(m, id, try self.expressionInner(m, id, depth));
    }
    fn expressionEvidence(self: *Generator, m: *const core.Module, id: core.Id, original: Value) Error!Value {
        var value = original;
        if (!value.terminated and value.type_evidence == null) {
            const actual = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(id) }, 0);
            // Keep the checked receiver across generic calls, including the
            // cursor descriptor produced by Array.iter. Its physical view
            // layout does not identify the Cursor associated-method family.
            const owner = try self.unit(actual.unit);
            if (T.receiverIdentity(owner.types.node(actual.ty)) != null) value.type_evidence = try self.boxTypeEvidence(.{
                .root = actual,
                .arguments = if (actual.ty <= T.f32_type) &.{} else try self.captureTypes(),
            });
        }
        return value;
    }
    fn expressionInner(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        errdefer if (self.diagnostic == null) {
            self.diagnostic = .{ .unit = m.unit, .span = m.span(id), .code = .storage_unsupported, .detail = "This expression has no admitted storage layout or binding" };
        };
        try self.chargeExpression(m, id, depth);
        const n = m.node(id);
        switch (n.tag) {
            .task => return self.fail(m, id, .storage_unsupported, "Language tasks are not part of the data-stack model; use isolated host worker jobs and copied packets"),
            .constant => {
                if (n.ty != T.u32_type and n.ty != T.boolean and n.ty != T.unit and n.ty != T.f32_type) return self.unsupported(m, id);
                var value = try self.constant(n.a);
                value.literal = if (n.ty == T.u32_type) n.a else null;
                value.constant_bits = n.a;
                value.floating = n.ty == T.f32_type;
                return value;
            },
            .reference => {
                var ref = m.reference(id);
                if (ref.unit == 0) ref.unit = m.unit;
                var i = self.bindings.items.len;
                while (i != 0) {
                    i -= 1;
                    const binding = &self.bindings.items[i];
                    if (binding.unit == ref.unit and binding.id == ref.binding) {
                        binding.remaining -|= 1;
                        return binding.value;
                    }
                }
                const owner = try self.unit(ref.unit);
                const binding = owner.binding(ref.binding);
                if (owner.body(ref.binding)) |body| if (body.is_function) return self.instantiate(ref, .{ .unit = m.unit, .ty = n.ty }, &.{}, depth + 1);
                if (binding.kind == .global and @import("storage_collections.zig").element(owner, binding.ty) != null) return self.globalArray(m, id, ref);
                if (binding.kind != .global or owner.body(ref.binding) == null or owner.body(ref.binding).?.runtime or types.info(&owner.types, binding.ty) != null) return self.unsupported(m, id);
                return self.instantiate(ref, .{ .unit = m.unit, .ty = n.ty }, &.{}, depth + 1);
            },
            .bind => {
                const value = try self.expression(m, n.b, depth + 1);
                if (value.terminated) return value;
                try self.bind(m, n.a, value);
                return self.unitValue();
            },
            .pattern_bind => {
                const value = try self.expression(m, n.b, depth + 1);
                if (value.terminated) return value;
                if (n.c == 0) try self.pattern(m, n.a, value) else {
                    // Refutable bindings use the same initialized-payload
                    // evidence as matches. An impossible pattern has only its
                    // checked exiting fallback; do not bind zeroed inactive
                    // descriptors as if they were reachable loop carries.
                    if (!evaluatedPattern(m, n.a, 0) and impossiblePattern(m, n.a, value, 0)) {
                        const fallback = try self.expression(m, n.c, depth + 1);
                        if (!fallback.terminated) return self.unsupported(m, id);
                        return fallback;
                    }
                    const matches = try self.testPattern(m, n.a, value, depth + 1);
                    try self.c.when(.{ .i32_eqz, matches });
                    self.nesting += 1;
                    const fallback = try self.expression(m, n.c, depth + 1);
                    if (!fallback.terminated) return self.unsupported(m, id);
                    self.nesting -= 1;
                    try self.c.end();
                }
                return self.unitValue();
            },
            .construct => {
                const constructor = m.constructor(n.a);
                const nominal = m.nominal(constructor.nominal);

                var payload = if (n.b == 0) try self.constant(0) else try self.expression(m, n.b, depth + 1);
                if (payload.terminated) return payload;
                if (n.b != 0) try self.mapValueTypes(.{ .unit = m.unit, .ty = m.typeOf(n.b) }, payload, 0);
                if (n.c != 0) {
                    const record = m.types.node(constructor.payload);
                    if (record.tag != .record or record.b == 0) return self.unsupported(m, id);
                    const fields = try self.arena.allocator().alloc(Value, record.b);
                    if (record.b == 1) fields[0] = payload else {
                        if (payload.tag != .aggregate or payload.fields.len != fields.len) return self.unsupported(m, id);
                        @memcpy(fields, payload.fields);
                    }
                    for (fields, 0..) |*field, index| field.name = m.fieldSpelling(m.types.recordField(record, index).name) orelse return self.unsupported(m, id);
                    orderFields(fields);
                    payload = .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields };
                }
                if (m.nominalConstructors(constructor.nominal).len == 1) {
                    const fields = try self.arena.allocator().alloc(Value, 1);
                    fields[0] = payload;
                    return .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields, .nominal = nominal.identity, .type_evidence = try self.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = n.ty }, .arguments = try self.captureTypes() }) };
                }
                var result = try self.zeroShape(try self.shape(m, id, n.ty, 0));
                const selected = @import("storage_layout.zig").variantIndex(result.variant_tags, constructor.tag) orelse return self.unsupported(m, id);
                result.word = (try self.constant(constructor.tag)).word;
                (try self.writableFields(&result))[selected] = payload;
                result.variant_index = selected;
                return result;
            },
            .primitive_function => {
                var value = (try self.primitiveCallable(m, id)) orelse return self.unsupported(m, id);
                value.word = (try self.unitValue()).word;
                return value;
            },
            .closure => {
                const captures = m.closureCaptures(id);
                const values = try self.arena.allocator().alloc(Value, captures.len);
                for (captures, values) |capture, *value| value.* = try self.snapshot(try self.bindingValue(m, capture));
                return .{ .tag = .callable, .word = (try self.unitValue()).word, .callable = try self.boxCallable(.{ .unit = m.unit, .node = id, .captures = captures, .goals = self.active_goals, .types = try self.captureTypes() }), .fields = values, .depth = self.depth };
            },

            .panic => {
                try self.c.op(.unreachable_, 0);
                return self.terminated();
            },
            .apply => {
                const function = try self.expression(m, n.a, depth + 1);
                if (function.terminated) return function;
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                try self.protected.append(self.allocator, function);
                const argument = try self.expression(m, n.b, depth + 1);
                if (argument.terminated) return argument;
                try self.protected.append(self.allocator, argument);
                return self.apply(m, id, function, argument, depth + 1);
            },
            .product, .record => {
                const children = m.children(id);
                const fields = try self.arena.allocator().alloc(Value, children.len);
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                for (children, 0..) |child, index| {
                    const value = try self.expression(m, child, depth + 1);
                    if (value.terminated) return value;
                    const destination = if (n.tag == .record) m.recordDestinations(id)[index] else index;
                    fields[destination] = value;
                    if (n.tag == .record) fields[destination].name = m.fieldSpelling(m.types.recordField(m.types.node(n.ty), destination).name) orelse return self.unsupported(m, id);
                    try self.protected.append(self.allocator, value);
                }
                if (n.tag == .record) orderFields(fields);
                return .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields };
            },
            .record_merge => {
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                const left = try self.expression(m, n.a, depth + 1);
                if (left.terminated) return left;
                try self.protected.append(self.allocator, left);
                const right = try self.expression(m, n.b, depth + 1);
                if (right.terminated) return right;
                try self.protected.append(self.allocator, right);
                const merged = (try self.mergeRecordValues(left, right)) orelse return self.unsupported(m, id);
                const output = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
                const owner = try self.unit(output.unit);
                const record = owner.types.node(output.ty);
                if (record.tag == .record) {
                    if (record.b != merged.fields.len) return self.unsupported(m, id);
                    for (0..record.b) |index| {
                        const name = owner.fieldSpelling(owner.types.recordField(record, index).name) orelse return self.unsupported(m, id);
                        if (dataField(merged, name) == null) return self.unsupported(m, id);
                    }
                }
                return merged;
            },
            .project => {
                if (try self.literalRecordProjection(m, id, depth)) |value| return value;
                if (try self.indexedProjection(m, id, depth)) |value| return value;
                const value = try self.expression(m, n.a, depth + 1);
                return self.projectValue(m, id, value, depth);
            },
            .update => {
                const info = m.updateInfo(id);
                const evaluated = try self.expression(m, info.root, depth + 1);
                if (evaluated.terminated) return evaluated;
                if (try self.indexedUpdate(m, id, evaluated, depth)) |updated| return updated;
                var root_value: Value = undefined;
                var field_only = true;
                for (m.updateSelectors(id)) |selector| {
                    if (selector.kind == .index) field_only = false;
                }
                if (field_only and plainInlineValue(evaluated) and !self.scalar_admission.hasScalarReferences()) {
                    // Functional updates replace fields; they never overwrite
                    // the original scalar lanes. Keep independent metadata.
                    root_value = evaluated;
                    self.emission_work.scoped_record_updates_shared +|= 1;
                } else root_value = try self.snapshot(evaluated);
                return self.updateValue(m, id, root_value, 0, depth + 1);
            },
            .loop => return self.emitLoop(m, id, depth),
            .match => return self.emitMatch(m, id, depth),
            .break_ => {
                var index = self.loops.items.len;
                while (index != 0) {
                    index -= 1;
                    const target = self.loops.items[index];
                    if (target.unit != m.unit or target.id != n.a) continue;
                    const args = m.breakValues(id);
                    if (args.len != target.carries.len) return self.unsupported(m, id);
                    const snapshots = try self.arena.allocator().alloc(Value, args.len);
                    for (args, snapshots, target.shared) |arg, *value, reuse| {
                        value.* = try self.loopSnapshot(try self.expression(m, arg, depth + 1), reuse);
                        try self.checkEscape(m, id, value.*, target.depth);
                    }
                    for (target.carries, snapshots, target.headers, target.shared) |*carry, value, header, reuse| {
                        if (!@import("storage_control.zig").stableCarry(carry.*, value)) return self.fail(m, id, .storage_escape, "A loop exit must retain the same named owners and borrowed roots");
                        if (n.op == .continue_ and !includesReadShape(header, value)) return self.fail(m, id, .storage_escape, "A loop cannot activate a variant without complete incoming payload evidence");
                        try self.assignLoop(m, id, carry, value, reuse);
                    }
                    if (n.op == .continue_) try self.checkReadFrame(m, id, target.read_frame);
                    try self.closeRuntime(target.roots_before, try self.unitValue());
                    // Other paths may still allocate after this exit. Only
                    // the completed loop may discard its shared header mark.
                    if (target.roots_before != self.roots.items.len) try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, target.mark.word });
                    if (n.op == .continue_) if (target.iterator) |iterator| try self.c.next(iterator);
                    try self.c.op(.br, self.nesting - target.nesting + @as(u32, if (n.op == .continue_) 0 else 1));
                    return self.terminated();
                }
                return self.unsupported(m, id);
            },
            .array => {
                const element = @import("storage_collections.zig").element(m, n.ty) orelse return self.unsupported(m, id);
                const info = types.info(&m.types, n.ty);
                const mode: storage.Mode = if (self.privateAppendNode(m.unit, id, "initial")) .grow else if (info) |kind| (if (kind.kind == .grow) .grow else .resize) else .fixed;
                const values = m.children(id);
                const literal = self.destination == null and scalarLiteralArray(m, element, values);
                const capacity = try self.constant(@intCast(values.len));
                const result = try self.array(m, id, capacity.word, mode);
                if (values.len == 0 and result.other_roots.len == 0) if (result.root) |owner| {
                    self.roots.items[owner].known_empty = true;
                };
                if (result.root) |owner_id| if (self.roots.items[owner_id].capacity_request) |request| {
                    try self.writableCapacity(request);
                    self.capacity_requests.initial(request, @intCast(values.len), try width(self.roots.items[owner_id].element)) catch return self.fail(m, id, .storage_unsupported, "Array capacity exceeds the Wasm32 storage plan");
                };
                if (literal) {
                    try self.initializeLiteralArray(m, id, result, values, depth);
                    return result;
                }
                for (values, 0..) |child, index| {
                    const value = try self.expression(m, child, depth + 1);
                    if (value.terminated) return value;
                    try self.writeElement(m, id, result, (try self.constant(@intCast(index))).word, value);
                }
                return result;
            },
            .staging => {
                var session = try evaluation.Session.init(self.allocator, self.units);
                defer session.deinit();
                const values: std.AutoHashMapUnmanaged(core.BindingId, evaluation.ValueId) = .empty;
                const evaluated = session.closedNode(m.unit, id, &values, &.{}, &.{}) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.fail(m, id, .stage_unavailable, "");
                };
                const value = session.valueScalar(evaluated) orelse return self.unsupported(m, id);
                if (value.scalar != .u32 and value.scalar != .unit and value.scalar != .bool and value.scalar != .f32) return self.unsupported(m, id);
                var result = try self.constant(value.bits);
                result.literal = if (value.scalar == .u32) value.bits else null;
                result.constant_bits = value.bits;
                result.floating = value.scalar == .f32;
                return result;
            },
            .storage => return self.operation(m, id, depth),
            .array_op => return self.collection(m, id, depth + 1),
            .associated, .result_associated => return self.associated(m, id, depth),
            .scalar => {
                if (n.c != 0 and n.b != 0) return self.associated(m, id, depth);
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                const left = try self.expression(m, n.a, depth + 1);
                if (left.terminated) return left;
                try self.protected.append(self.allocator, left);
                const right = if (n.b != 0) try self.expression(m, n.b, depth + 1) else left;
                if (right.terminated) return right;
                return self.primitive(m, id, left, right);
            },
            .logical => {
                const left_value = try self.expression(m, n.a, depth + 1);
                if (left_value.terminated) return left_value;
                const left = try self.scalar(m, n.a, left_value);
                const result = try self.c.temp();
                try self.c.set(result, left);
                if (n.op == .and_) try self.c.when(left) else try self.c.when(.{ .i32_eqz, left });
                self.nesting += 1;
                const right = try self.expression(m, n.b, depth + 1);
                if (!right.terminated) try self.c.set(result, try self.scalar(m, n.b, right));
                self.nesting -= 1;
                try self.c.end();
                return .{ .word = result };
            },
            .block => {
                const region_count = self.append_regions.items.len;
                defer self.append_regions.shrinkRetainingCapacity(region_count);
                // This proof changes storage allocation only. The ordinary
                // evaluator retains the original immutable List semantics.
                if (self.destination == null) if (private_append.analyze(m, id)) |plan| {
                    try self.append_regions.append(self.allocator, .{ .unit = m.unit, .plan = plan });
                };
                const roots_before = self.roots.items.len;
                const mark = try self.frameMark();
                const bindings_before = self.bindings.items.len;
                defer self.bindings.shrinkRetainingCapacity(bindings_before);
                self.depth += 1;
                defer self.depth -= 1;
                try self.c.op(.block, 0);
                self.nesting += 1;
                const control_index = self.controls.items.len;
                try self.controls.append(self.allocator, .{ .unit = m.unit, .id = id, .nesting = self.nesting, .roots_before = roots_before, .result = self.newJoin() });
                defer _ = self.controls.pop();
                var exits = false;
                for (m.children(id)) |child| {
                    const value = try self.expression(m, child, depth + 1);
                    if (value.terminated) {
                        exits = true;
                        break;
                    }
                }
                self.nesting -= 1;
                try self.c.end();
                var result = (try self.finishJoin(&self.controls.items[control_index].result, !exits)) orelse if (exits) try self.terminated() else try self.unitValue();
                try self.escape(m, id, &result, self.depth);
                try self.release(roots_before, result);
                try self.rewindUnescaped(roots_before, mark, result);
                return result;
            },
            .suite => {
                for (m.children(id)) |child| {
                    const value = try self.expression(m, child, depth + 1);
                    if (value.terminated) return value;
                }
                return self.unitValue();
            },
            .return_ => {
                const value = try self.expression(m, n.a, depth + 1);
                if (value.terminated) return value;
                if (m.typeOf(n.a) == T.never) {
                    try self.c.op(.unreachable_, 0);
                    return self.terminated();
                }
                var i = self.controls.items.len;
                while (i != 0) {
                    i -= 1;
                    if (self.controls.items[i].unit == m.unit and self.controls.items[i].id == n.b) {
                        var target = self.controls.items[i];
                        try self.addJoin(m, id, &target.result, value);
                        self.controls.items[i] = target;
                        try self.closeRuntime(target.roots_before, value);
                        try self.c.op(.br, self.nesting - target.nesting);
                        return self.terminated();
                    }
                }
                return self.unsupported(m, id);
            },
            .if_value, .if_stmt => {
                const condition_value = try self.expression(m, n.a, depth + 1);
                if (condition_value.terminated) return condition_value;
                const condition = try self.scalar(m, n.a, condition_value);
                const bindings_before = self.bindings.items.len;
                const merges = m.branchMerges(id);
                const merged = try self.arena.allocator().alloc(?Value, merges.len);
                @memset(merged, null);
                const shared_merges = try self.mergeTransport(m, merges, merged);
                var result = self.newJoin();
                try self.c.when(condition);
                self.nesting += 1;
                const left = try self.expression(m, n.b, depth + 1);
                var left_bindings: []const Binding = &.{};
                if (!left.terminated) {
                    try self.addJoin(m, id, &result, left);
                    for (merges, merged, shared_merges) |merge, *value, shared_merge| {
                        const incoming = try self.bindingValue(m, merge.then_binding);
                        if (value.* == null) value.* = try self.temporary(incoming);
                        try self.assignTransport(m, id, &value.*.?, incoming, !shared_merge);
                    }
                    if (n.tag == .if_stmt) left_bindings = try self.arena.allocator().dupe(Binding, self.bindings.items[bindings_before..]);
                }
                self.bindings.shrinkRetainingCapacity(bindings_before);
                try self.c.op(.else_, 0);
                const right = if (n.c != 0) try self.expression(m, n.c, depth + 1) else try self.unitValue();
                var right_bindings: []const Binding = &.{};
                if (!right.terminated) {
                    try self.addJoin(m, id, &result, right);
                    for (merges, merged, shared_merges) |merge, *value, shared_merge| {
                        const incoming = try self.bindingValue(m, merge.else_binding);
                        if (value.* == null) value.* = try self.temporary(incoming);
                        try self.assignTransport(m, id, &value.*.?, incoming, !shared_merge);
                    }
                    if (n.tag == .if_stmt) right_bindings = try self.arena.allocator().dupe(Binding, self.bindings.items[bindings_before..]);
                }
                self.bindings.shrinkRetainingCapacity(bindings_before);
                self.nesting -= 1;
                try self.c.end();
                if (n.tag == .if_stmt and left.terminated != right.terminated) try self.bindings.appendSlice(self.allocator, if (left.terminated) right_bindings else left_bindings);
                const joined = try self.finishJoin(&result, false);
                if (joined != null) {
                    for (merges, merged) |merge, value| if (value) |normal| try self.bind(m, merge.result, normal);
                }
                return joined orelse try self.terminated();
            },
            .contract_method => return self.contractMethod(m, id, depth),
            .call => {
                const call = m.call(id);
                var values: std.ArrayList(Value) = .empty;
                defer values.deinit(self.allocator);
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                for (call.arguments) |arg| {
                    const value = try self.expression(m, arg, depth + 1);
                    if (value.terminated) return value;
                    try values.append(self.allocator, value);
                    try self.protected.append(self.allocator, value);
                }
                var target = call.target;
                if (target.unit == 0) target.unit = m.unit;
                const previous_origin = self.specialization_origin;
                self.specialization_origin = self.invocationOrigin(m, id);
                defer self.specialization_origin = previous_origin;
                return self.instantiate(target, .{ .unit = m.unit, .ty = call.callee_type }, values.items, depth + 1);
            },
            else => return self.unsupported(m, id),
        }
    }
    fn emit(self: *Generator, entry: u32) Error!void {
        const m = try self.unit(entry);
        const globals = @import("storage_globals.zig").collect(self.allocator, self.units, entry) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.fail(m, 0, .storage_unsupported, switch (err) {
                error.InitializationCycle => "Application pool initialization dependencies are cyclic",
                error.Limit => "Application pool dependency discovery exceeded its checked node budget",
                else => "Application pool dependency could not be resolved",
            });
        };
        defer self.allocator.free(globals);
        self.descriptor_calls.global_footprint = try global_footprint.Index.init(self.allocator, self.units, globals);
        if (globals.len > storage.max_stacks) return error.Declined;
        for (globals, 0..) |target, index| try self.globals.append(self.allocator, .{ .target = target, .word = try self.newGlobal(), .token = try self.newGlobal(), .epoch_low = try self.newGlobal(), .epoch_high = try self.newGlobal(), .capacity_request = try self.capacity_requests.add(@intCast(index)) });
        var reserved = globals.len;
        for (m.bodies) |*body| {
            if (!body.exported) continue;
            const parameters = m.bodyParameters(body);
            if (parameters.len != 1) continue;
            const callback = callbackAbi(m, parameters[0].ty);
            const needs_packets = if (callback) |host| arrayAbi(host.parameter) or arrayAbi(host.result) else if (valueAbi(m, parameters[0].ty)) |kind| arrayAbi(kind) else false;
            const result_packets = if (valueAbi(m, m.typeOf(body.root))) |kind| arrayAbi(kind) else false;
            if ((needs_packets or result_packets) and self.transport == null) {
                if (reserved >= storage.max_stacks) return self.unsupported(m, body.root);
                self.transport_region = @intCast(reserved);
                self.transport = packets.emit(self.module) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.unsupported(m, body.root);
                };
                reserved += 1;
            }
        }
        self.fixed_region = @intCast(reserved);
        reserved += 1;
        self.max_stacks = @intCast(reserved);
        var exports: usize = 0;
        for (m.bodies) |*body| {
            if (!body.exported) continue;
            const parameters = m.bodyParameters(body);
            if (!body.is_function or parameters.len != 1) return self.unsupported(m, body.root);
            const callback = callbackAbi(m, parameters[0].ty);
            const parameter = if (callback != null) wasm.Scalar.unit else valueAbi(m, parameters[0].ty) orelse return self.unsupported(m, body.root);
            const result = valueAbi(m, m.typeOf(body.root)) orelse return self.unsupported(m, body.root);
            const function = self.module.addTypedFunction(&.{if (callback != null) .externref else if (parameter == .f32) .f32 else .i32}, if (result == .f32) .f32 else .i32, .scalar) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            self.c = .{ .module = self.module, .function = function };
            self.outlining.registerRoot(function) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            // These values belong to one Wasm local namespace and one body
            // planning budget. Completed source proofs, call definitions and
            // physical capacity requests remain compilation-wide.
            self.steps = 0;
            self.layout_steps = 0;
            self.type_arguments.clearRetainingCapacity();
            self.invalid_literals.clearRetainingCapacity();
            self.mutable_join_words.clearRetainingCapacity();
            self.indexed_mutable_roots = 0;
            self.active_goals = &.{};
            self.specialization_origin = .{ .unit = m.unit, .span = body.span };
            self.roots.clearRetainingCapacity();
            self.globals_ready = false;
            self.global_roots = &.{};
            self.bindings.clearRetainingCapacity();
            self.stacks.clearRetainingCapacity();
            try self.stacks.appendNTimes(self.allocator, true, reserved);
            self.depth = 0;
            try self.c.value(.{ .call, self.runtime.functions.reset_temporary, @as(u32, @intCast(self.globals.items.len)) });
            const global_roots = try self.arena.allocator().alloc(usize, self.globals.items.len);
            for (self.globals.items, global_roots) |global, *root_| root_.* = (try self.globalArray(m, body.root, global.target)).root.?;
            self.global_roots = global_roots;
            self.globals_ready = true;
            const argument: Value = if (callback) |host| .{ .tag = .callable, .word = .{ .id = 0 }, .host = host } else if (arrayAbi(parameter)) try self.fromWire(m, body.root, .{ .id = 0 }, parameter) else blk: {
                const input = try self.c.temp();
                try self.c.op(.local_get, 0);
                if (parameter == .f32) try self.c.op(.i32_reinterpret_f32, 0);
                try self.c.op(.local_set, input.id);
                break :blk .{ .word = input, .floating = parameter == .f32 };
            };
            // The exported function already owns its registered outline root.
            const value = try self.invokeBody(.{ .unit = m.unit, .binding = body.binding }, &.{argument}, 0, false);
            if (arrayAbi(result)) try self.resetPackets();
            const word = if (value.terminated) value.word else if (arrayAbi(result)) try self.toWire(m, body.root, value, result) else try self.scalar(m, body.root, value);
            try self.release(0, null);
            try self.c.value(word);
            if (result == .f32) try self.c.op(.f32_reinterpret_i32, 0);
            const exported = if (callback) |host| self.module.exportCallbackFunction(function, m.name(body.export_name), host, result) else self.module.exportFunction(function, m.name(body.export_name), parameter, result);
            exported catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            exports += 1;
        }
        if (exports == 0) return error.Declined;
    }
    fn newGlobal(self: *Generator) Error!u32 {
        return self.module.addGlobal(.u32, 0, true) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.Declined,
        };
    }
};
fn valueAbi(m: *const core.Module, ty: T.Id) ?wasm.Scalar {
    const node = m.types.node(ty);
    if (node.tag == .array) return switch (node.a) {
        T.u32_type => .array_u32,
        T.f32_type => .array_f32,
        else => null,
    };
    return switch (ty) {
        T.unit => .unit,
        T.boolean => .bool,
        T.u32_type => .u32,
        T.f32_type => .f32,
        else => null,
    };
}
fn arrayAbi(kind: wasm.Scalar) bool {
    return kind == .array_u32 or kind == .array_f32;
}
fn callbackAbi(m: *const core.Module, ty: T.Id) ?wasm.Callback {
    const node = m.types.node(ty);
    if (node.tag != .function) return null;
    const row = m.types.row(node.c);
    const labels = m.types.rowLabels(node.c);
    if (row.tail != .closed or labels.len != 1 or labels[0] != T.foreign_operation) return null;
    return .{ .parameter = valueAbi(m, node.a) orelse return null, .result = valueAbi(m, node.b) orelse return null };
}
pub fn compile(allocator: std.mem.Allocator, units: []const core.Module, entry: u32) std.mem.Allocator.Error!backend.Result {
    return compileWithOptions(allocator, units, entry, .{});
}
pub const CompileOptions = struct {
    completed_core_validation: ?@import("../reuse/completed_core_validation.zig").Borrow = null,
    source_completion: @import("../reuse/source_completion.zig").Borrow = .{},
    identity: ?@import("runtime_identity.zig").View = null,
    storage: storage_plan.Config = .{},
    work_limits: WorkLimits = .{},
    tier: @import("../compilation_tier.zig").Tier = .optimized,
    workers: u8 = 1,
    share_machine_code: bool = false,
    io: ?std.Io = null,
    profile: bool = false,
};
pub fn compileWithOptions(allocator: std.mem.Allocator, units: []const core.Module, entry: u32, options: CompileOptions) std.mem.Allocator.Error!backend.Result {
    const trace_space = @import("../phase_profile.zig").enterSpace(.core);
    defer trace_space.restore();
    if (@import("../phase_profile.zig").currentTrace() != null) if (options.identity) |identity| {
        for (units) |*unit_| if (identity.owner(unit_.unit)) |path| {
            // Retained Core has canonical paths but no source byte inventory.
            @import("../phase_profile.zig").traceModule(unit_.unit, path, 0);
        };
    };
    const config = options.storage;
    const limits = options.work_limits;
    if (limits.expressions == 0) return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Scoped emission requires a positive expression allowance" } };
    const views = try allocator.alloc(*const core.Module, units.len);
    defer allocator.free(views);
    for (units, 0..) |*unit_, index| views[index] = unit_;
    const validation = @import("../check/frozen_core_validation.zig");
    var reused_core_validations: usize = 0;
    {
        const trace = @import("../phase_profile.zig").region("owned.validate-core", entry, 0, 0);
        defer trace.exit();
        for (units) |*unit_| validation.validateBounds(unit_, .{ .units = views }) catch {
            return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid scoped-storage Core bounds" } };
        };
        const proved_prefix = if (options.completed_core_validation) |receipt| if (options.identity) |identity| receipt.prefix(units, entry, identity) else 0 else 0;
        reused_core_validations = proved_prefix;
        @import("../phase_profile.zig").detail("owned.validate.reused", entry, 0, 0, proved_prefix);
        for (units, 0..) |*unit_, index| {
            if (index < proved_prefix) continue;
            validation.validate(allocator, unit_, .{ .units = views }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidArtifact => {
                    return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid scoped-storage Core evidence" } };
                },
            };
        }
    }
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    const runtime = runtime_block: {
        const trace = @import("../phase_profile.zig").region("owned.runtime-generation", entry, 0, 0);
        defer trace.exit();
        break :runtime_block storage.emit(&module) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
    };
    var emission_work: @import("../work_counters.zig").Counters = .{ .max_scoped_emission_limit = limits.expressions, .scoped_core_validation_reused = reused_core_validations, .scoped_core_validation_fresh = units.len - reused_core_validations };
    var proof_cache = source_proof.SourceProofCache.initWithInventoryBudget(allocator, views) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArtifact => return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid source proof context" } },
    };
    defer proof_cache.deinit();
    proof_cache.work = &emission_work;
    if (options.identity) |names| proof_cache.admitCompletedSource(options.source_completion, units, entry, names) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArtifact => return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid completed source context" } },
    };
    @import("../phase_profile.zig").detail("owned.source.completed", entry, 0, 0, emission_work.scoped_source_completed_bodies);
    var dispatches: Dispatches = .empty;
    defer dispatches.deinit(allocator);
    var capacity_requests: storage_plan.CapacityRequests = .{ .allocator = allocator };
    defer capacity_requests.deinit();
    var validation_budget: usize = 1_000_000;
    var active_calls: call_plan.ActiveCalls = .{ .allocator = allocator };
    defer active_calls.deinit();
    var scalar_admission: call_plan.ScalarAdmission = .{ .allocator = allocator, .units = units };
    defer scalar_admission.deinit();
    var field_recipes: field_plan.Cache = .{ .allocator = allocator };
    defer field_recipes.deinit();
    var descriptor_calls: DescriptorCalls = .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .record_metadata = .{ .allocator = allocator } };
    defer descriptor_calls.deinit();
    try descriptor_calls.initPrimitiveEvidence(units);
    var shared_calls: call_plan.Cache = .{ .allocator = allocator };
    defer shared_calls.deinit();
    var outlining = scope_outline.Context.init(allocator, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer outlining.deinit();
    var methods: MethodSelector = .{ .allocator = allocator, .units = units, .entry = entry, .bounds = .{ .allocator = allocator } };
    defer methods.deinit();
    var g: Generator = .{ .entry_unit = entry, .methods = &methods, .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .shared_calls = &shared_calls, .descriptor_calls = &descriptor_calls, .field_recipes = &field_recipes, .scalar_admission = &scalar_admission, .active_calls = &active_calls, .units = units, .unit_views = views, .proof_cache = &proof_cache, .dispatches = &dispatches, .capacity_requests = &capacity_requests, .validation_budget = &validation_budget, .module = &module, .runtime = runtime, .work_limits = limits, .emission_work = &emission_work, .outlining = &outlining };
    defer g.deinit();
    {
        const trace = @import("../phase_profile.zig").region("owned.emit", entry, 0, 0);
        defer trace.exit();
        g.emit(entry) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Declined => return .{ .counters = emission_work, .diagnostic = g.diagnostic orelse .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported } },
        };
    }
    {
        const trace = @import("../phase_profile.zig").region("owned.memory-plan", entry, 0, 0);
        defer trace.exit();
        const capacities = try allocator.alloc(u32, g.max_stacks);
        defer allocator.free(capacities);
        if (config.persistent_lanes.len != 0 and config.persistent_lanes.len != g.globals.items.len) return .{ .counters = emission_work, .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Persistent storage budgets must match the named pool inventory" } };
        @memset(capacities, config.grower_bytes);
        capacities[g.fixed_region] = config.temporary_bytes;
        for (g.globals.items, 0..) |global, index| {
            const configured = if (config.persistent_lanes.len == 0) config.persistent_bytes else config.persistent_lanes[index];
            // Inferred extents only reduce reservation; they never enlarge an
            // application's explicit per-pool budget.
            capacities[index] = @min(configured, global.literal_bytes orelse configured);
        }
        if (g.transport_region) |region| capacities[region] = config.transport_bytes;
        try capacity_requests.apply(capacities);
        const memory_plan: storage.Plan = .{ .region_capacities = capacities, .owner_capacity = config.owner_capacity };
        storage.finishPlan(&module, runtime, memory_plan) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{ .counters = emission_work, .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Owned storage memory plan exceeds Wasm32 capacity" } },
        };
        if (g.transport) |transport| packets.configure(&module, transport, storage.regionBase(memory_plan, g.transport_region.?) catch unreachable, capacities[g.transport_region.?]) catch {
            return .{ .counters = emission_work, .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid copied transport memory plan" } };
        };
    }
    const outlined = outline_block: {
        const trace = @import("../phase_profile.zig").region("owned.outline", entry, 0, 0);
        defer trace.exit();
        break :outline_block outlining.finalize() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{ .counters = emission_work, .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Scoped helpers exceeded their checked machine-state or engine limits" } },
        };
    };
    emission_work.scoped_outlined_regions = outlined.regions;
    emission_work.scoped_outlined_globals = outlined.globals;
    emission_work.scoped_copy_pairs_removed = outlined.copies_removed;
    emission_work.scoped_bank_operand_bytes_saved = outlined.bank_operand_bytes_saved;
    emission_work.scoped_copy_reads_forwarded = outlined.reads_forwarded;
    var runtime_optimization: @import("optimized_bodies.zig").Stats = .{ .tier = options.tier };
    const bytes = assembly_block: {
        const trace = @import("../phase_profile.zig").region("owned.assemble", entry, 0, 0);
        defer trace.exit();
        break :assembly_block module.assembleWithOptions(.{
            .tier = options.tier,
            .workers = options.workers,
            .share_machine_code = options.share_machine_code,
            .io = options.io,
            .profile = options.profile,
            .stats = &runtime_optimization,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{ .runtime_optimization = runtime_optimization, .counters = emission_work, .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Scoped storage emission failed Wasm validation" } },
        };
    };
    return .{ .runtime_optimization = runtime_optimization, .bytes = bytes, .emitted_functions = module.functions.items.len - runtime_optimization.shared, .whole_module_only = true, .counters = emission_work };
}

fn immutableMetadataSnapshots(allocator: std.mem.Allocator) !void {
    // These helpers use metadata only; emission and type selection stay idle.
    var g: Generator = undefined;
    g.emitting_function_plan = false;
    g.allocator = allocator;
    g.arena = std.heap.ArenaAllocator.init(allocator);
    defer g.arena.deinit();
    g.roots = .empty;
    defer g.roots.deinit(allocator);
    var trace: WriterTrace = .{ .inputs = 1 };
    defer trace.events.deinit(allocator);
    g.writer_trace = &trace;
    const m: core.Module = .{
        .types = .{ .nodes = &.{}, .extra = &.{} },
        .nodes = &.{},
        .spans = &.{},
        .extra = &.{},
        .bindings = &.{},
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
    const borrow: Value = .{ .tag = .view, .word = .{ .id = 0 }, .root = 1 };
    const tagged: Value = .{
        .tag = .aggregate,
        .word = .{ .id = 0 },
        .fields = &.{ borrow, borrow },
        .variant_tags = &.{ 3, 7 },
        .variant_index = 0,
        .variant_possible = &.{ true, false },
    };
    const original: Value = .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = &.{tagged} };
    for (0..3) |_| try g.roots.append(allocator, .{
        .word = .{ .id = 0 },
        .token = .{ .id = 0 },
        .epoch_low = .{ .id = 0 },
        .epoch_high = .{ .id = 0 },
        .stack = 0,
        .depth = 0,
        .element = original,
    });
    const read = try g.readShapeSnapshot(original);
    try g.writerEvent(&m, 0, .{ .tag = .array, .word = .{ .id = 0 }, .root = 0 }, .read);
    var header = original;
    try g.loopHeader(&header);
    const saved_header = header;
    const next_borrow: Value = .{ .tag = .view, .word = .{ .id = 0 }, .root = 2 };
    var next_tagged = tagged;
    next_tagged.fields = &.{ next_borrow, next_borrow };
    next_tagged.variant_index = 1;
    const next: Value = .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = &.{next_tagged} };
    try g.storedShape(&m, 0, &g.roots.items[0].element, next, 0);
    const live = g.roots.items[0].element;
    try std.testing.expect(live.fields[0].variant_possible[1]);
    try std.testing.expect(hasRoot(live.fields[0].fields[1], 2));
    for ([_]Value{ original, read.*, trace.events.items[0].shape, saved_header }) |old| {
        try std.testing.expect(old.fields[0].variant_possible[0]);
        try std.testing.expect(!old.fields[0].variant_possible[1]);
        try std.testing.expect(hasRoot(old.fields[0].fields[1], 1));
        try std.testing.expect(!hasRoot(old.fields[0].fields[1], 2));
        try std.testing.expect(!Generator.includesReadShape(old, live));
    }
}

test "immutable metadata preserves read writer and loop snapshots through allocation failures" {
    try immutableMetadataSnapshots(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, immutableMetadataSnapshots, .{});
}

fn sparseReadFrames(allocator: std.mem.Allocator) !void {
    // Metadata-only helpers; runtime emission and type selection stay idle.
    var g: Generator = undefined;
    g.emitting_function_plan = false;
    g.allocator = allocator;
    g.arena = std.heap.ArenaAllocator.init(allocator);
    defer g.arena.deinit();
    g.roots = .empty;
    defer g.roots.deinit(allocator);
    g.read_frames = .empty;
    defer g.read_frames.deinit(allocator);
    g.diagnostic = null;
    var spans = [_]core.Span{.{ .start = 0, .end = 0 }};
    const m: core.Module = .{
        .unit = 1,
        .types = .{ .nodes = &.{}, .extra = &.{} },
        .nodes = &.{},
        .spans = &spans,
        .extra = &.{},
        .bindings = &.{},
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
    const initial: Value = .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = &.{.{ .tag = .view, .word = .{ .id = 0 }, .root = 0 }} };
    const widened: Value = .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = &.{.{ .tag = .view, .word = .{ .id = 0 }, .root = 0, .other_roots = &.{1} }} };
    const root_: Root = .{ .word = .{ .id = 0 }, .token = .{ .id = 0 }, .epoch_low = .{ .id = 0 }, .epoch_high = .{ .id = 0 }, .stack = 0, .depth = 0, .element = initial };
    try g.roots.appendNTimes(allocator, root_, 6);
    const outer = try g.beginReadFrame();
    try std.testing.expectEqual(@as(usize, 6), g.read_frames.items[outer].owner_limit);
    try std.testing.expectEqual(@as(usize, 0), g.read_frames.items[outer].first.capacity);
    // Read encounter order differs from the required ascending owner order.
    try g.registerShapeRead(.{ .word = .{ .id = 0 }, .root = 4, .other_roots = &.{ 1, 4 } });
    try std.testing.expectEqual(@as(usize, 2), g.read_frames.items[outer].first.items.len);
    try std.testing.expectEqual(@as(usize, 1), g.read_frames.items[outer].first.items[0].owner);
    try std.testing.expectEqual(@as(usize, 4), g.read_frames.items[outer].first.items[1].owner);
    const first = g.read_frames.items[outer].first.items[1].shape;
    g.roots.items[4].element = widened;
    const inner = try g.beginReadFrame();
    try g.registerShapeRead(.{ .word = .{ .id = 0 }, .root = 4 });
    // The outer first read is immutable; the inner first read sees the latest
    // shape. Re-reading cannot replace either frame's original snapshot.
    try std.testing.expectEqual(first, g.read_frames.items[outer].first.items[1].shape);
    try std.testing.expect(!Generator.includesReadShape(first.*, widened));
    try g.checkReadFrame(&m, 0, inner);
    try std.testing.expectError(error.Declined, g.checkReadFrame(&m, 0, outer));
    try std.testing.expectEqual(backend.Code.storage_escape, g.diagnostic.?.code);
    g.diagnostic = null;
    g.roots.items[4].element = initial;
    try g.checkReadFrame(&m, 0, inner);
    try g.checkReadFrame(&m, 0, outer);
    // Lazily opened globals remain separate and retain encounter order; local
    // owners created after the frame are excluded from both ordinary lists.
    var persistent = root_;
    persistent.persistent = true;
    try g.roots.appendNTimes(allocator, persistent, 2);
    try g.roots.append(allocator, root_);
    try g.registerShapeRead(.{ .word = .{ .id = 0 }, .root = 7, .other_roots = &.{ 8, 6, 7 } });
    for (g.read_frames.items) |frame| {
        try std.testing.expectEqual(@as(usize, 2), frame.persistent.items.len);
        try std.testing.expectEqual(@as(usize, 7), frame.persistent.items[0].owner);
        try std.testing.expectEqual(@as(usize, 6), frame.persistent.items[1].owner);
        try std.testing.expectEqual(frame.first.items.len, frame.position(8));
    }
    const saved = g.read_frames.items[outer].persistent.items[0].shape;
    g.roots.items[7].element = widened;
    try g.registerShapeRead(.{ .word = .{ .id = 0 }, .root = 7 });
    try std.testing.expectEqual(saved, g.read_frames.items[outer].persistent.items[0].shape);
    try std.testing.expectError(error.Declined, g.checkReadFrame(&m, 0, outer));
    g.diagnostic = null;
    // Closing a nested frame, then opening a sibling, observes the new prefix
    // and newest shape without overwriting the enclosing frame's first read.
    g.read_frames.shrinkRetainingCapacity(inner);
    const sibling = try g.beginReadFrame();
    try g.registerShapeRead(.{ .word = .{ .id = 0 }, .root = 7 });
    try std.testing.expectEqual(@as(usize, 9), g.read_frames.items[sibling].owner_limit);
    try std.testing.expectEqual(@as(usize, 7), g.read_frames.items[sibling].first.items[0].owner);
    try std.testing.expectEqual(@as(usize, 0), g.read_frames.items[sibling].persistent.items.len);
    try g.checkReadFrame(&m, 0, sibling);
    try std.testing.expectEqual(saved, g.read_frames.items[outer].persistent.items[0].shape);
    try std.testing.expectEqual(@as(usize, 2 * @sizeOf(usize)), @sizeOf(RootRead));
}
fn recordMetadataScenario(allocator: std.mem.Allocator) !void {
    var record_node = [_]T.Node{.{ .tag = .record, .a = 0, .b = 5 }};
    var record_words = [_]u32{ 12, 6, 9, 3, 2, 4, 5, 2, 7, 1 };
    var name_bytes = [_]u8{ 'z', 'a', 'b' };
    var field_names = [_]core.FieldName{
        .{ .symbol = 5, .spelling = .{ .start = 0, .len = 1 } },
        .{ .symbol = 7, .spelling = .{ .start = 1, .len = 1 } },
        .{ .symbol = 9, .spelling = .{ .start = 2, .len = 1 } },
    };
    const owner: core.Module = .{
        .unit = 42,
        .types = .{ .nodes = &record_node, .extra = &record_words },
        .nodes = &.{},
        .spans = &.{},
        .extra = &.{},
        .bindings = &.{},
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &name_bytes,
        .field_names = &field_names,
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
    var cache: RecordMetadataCache = .{ .allocator = allocator };
    defer cache.deinit();

    try std.testing.expectError(error.Limit, cache.get(&owner, 0, record_node[0], 17, 17));
    const first = try cache.get(&owner, 0, record_node[0], 18, 18);
    const again = try cache.get(&owner, 0, record_node[0], 18, 18);
    try std.testing.expectEqual(@as(usize, 18), first.name_words);
    try std.testing.expectEqual(first.fields.ptr, again.fields.ptr);
    try std.testing.expectEqualSlices(u32, &.{ 1, 3, 2, 4, 6 }, &.{
        first.fields[0].ty,
        first.fields[1].ty,
        first.fields[2].ty,
        first.fields[3].ty,
        first.fields[4].ty,
    });
    try std.testing.expectEqualSlices(u32, &.{ 7, 9, 5, 2, 12 }, &.{
        first.fields[0].symbol,
        first.fields[1].symbol,
        first.fields[2].symbol,
        first.fields[3].symbol,
        first.fields[4].symbol,
    });
    try std.testing.expectEqualStrings("a", first.fields[0].spelling.?);
    try std.testing.expectEqualStrings("b", first.fields[1].spelling.?);
    try std.testing.expectEqualStrings("z", first.fields[2].spelling.?);
    try std.testing.expect(first.fields[3].spelling == null);
    try std.testing.expect(first.fields[4].spelling == null);
    try std.testing.expectError(error.Limit, cache.get(&owner, 0, record_node[0], 17, 17));

    var old_order = [_]u32{ 0, 1, 2, 3, 4 };
    const OldOrdering = struct {
        owner: *const core.Module,
        node: T.Node,
        fn less(context: @This(), left: u32, right: u32) bool {
            const a = context.owner.types.recordField(context.node, left).name;
            const b = context.owner.types.recordField(context.node, right).name;
            const a_name = context.owner.fieldSpelling(a);
            const b_name = context.owner.fieldSpelling(b);
            if (a_name) |name| {
                if (b_name) |other| return std.mem.order(u8, name, other) == .lt;
                return true;
            }
            if (b_name != null) return false;
            return a < b;
        }
    };
    std.mem.sort(u32, &old_order, OldOrdering{ .owner = &owner, .node = record_node[0] }, OldOrdering.less);
    var old_words: std.ArrayList(u32) = .empty;
    defer old_words.deinit(allocator);
    var cached_words: std.ArrayList(u32) = .empty;
    defer cached_words.deinit(allocator);
    for (old_order) |ordinal| {
        const field = owner.types.recordField(record_node[0], ordinal);
        if (owner.fieldSpelling(field.name)) |name| {
            try old_words.append(allocator, @intCast(name.len));
            for (name) |byte| try old_words.append(allocator, byte);
        } else try old_words.appendSlice(allocator, &.{ std.math.maxInt(u32), owner.unit, field.name });
        try old_words.append(allocator, field.ty);
    }
    for (first.fields) |field| {
        if (field.spelling) |name| {
            try cached_words.append(allocator, @intCast(name.len));
            for (name) |byte| try cached_words.append(allocator, byte);
        } else try cached_words.appendSlice(allocator, &.{ std.math.maxInt(u32), owner.unit, field.symbol });
        try cached_words.append(allocator, field.ty);
    }
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(old_words.items), std.mem.sliceAsBytes(cached_words.items));
}

test "record metadata snapshots raw fields and missing spellings through full OOM" {
    try recordMetadataScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, recordMetadataScenario, .{});
}

test "sparse loop read frames preserve sorted first snapshots nested backedges and lazy persistent owners through OOM" {
    try sparseReadFrames(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sparseReadFrames, .{});
}

fn scalarAdmissionRefinement(allocator: std.mem.Allocator, units: []const core.Module) !void {
    const m = &units[0];
    const body = for (m.bodies) |*candidate| {
        if (std.mem.eql(u8, m.name(candidate.declaration_name), "difference")) break candidate;
    } else return error.TestUnexpectedResult;
    const target: core.BindingRef = .{ .unit = m.unit, .binding = body.binding };
    const views = [_]*const core.Module{m};
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    const runtime = try storage.emit(&module);
    const function = try module.addTypedFunction(&.{}, .i32, .scalar);
    var emission_work: @import("../work_counters.zig").Counters = .{};
    var proof_cache = try source_proof.SourceProofCache.initWithInventoryBudget(allocator, &views);
    defer proof_cache.deinit();
    var dispatches: Dispatches = .empty;
    defer dispatches.deinit(allocator);
    var capacity_requests: storage_plan.CapacityRequests = .{ .allocator = allocator };
    defer capacity_requests.deinit();
    var validation_budget: usize = 1_000_000;
    var active_calls: call_plan.ActiveCalls = .{ .allocator = allocator };
    defer active_calls.deinit();
    var scalar_admission: call_plan.ScalarAdmission = .{ .allocator = allocator, .units = units };
    defer scalar_admission.deinit();
    var field_recipes: field_plan.Cache = .{ .allocator = allocator };
    defer field_recipes.deinit();
    var descriptor_calls: DescriptorCalls = .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .record_metadata = .{ .allocator = allocator } };
    defer descriptor_calls.deinit();
    var shared_calls: call_plan.Cache = .{ .allocator = allocator };
    defer shared_calls.deinit();
    var outlining = scope_outline.Context.init(allocator, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer outlining.deinit();
    var methods: MethodSelector = .{ .allocator = allocator, .units = units, .entry = m.unit, .bounds = .{ .allocator = allocator } };
    defer methods.deinit();
    var g: Generator = .{ .entry_unit = m.unit, .methods = &methods, .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .shared_calls = &shared_calls, .descriptor_calls = &descriptor_calls, .field_recipes = &field_recipes, .scalar_admission = &scalar_admission, .active_calls = &active_calls, .units = units, .unit_views = &views, .proof_cache = &proof_cache, .dispatches = &dispatches, .capacity_requests = &capacity_requests, .validation_budget = &validation_budget, .module = &module, .runtime = runtime, .emission_work = &emission_work, .outlining = &outlining, .c = .{ .module = &module, .function = function } };
    defer g.deinit();
    for ([_]T.Id{ T.u32_type, T.f32_type, T.u32_type, T.f32_type }) |actual| {
        const before = g.type_arguments.items.len;
        defer g.type_arguments.shrinkRetainingCapacity(before);
        var arguments: [2]Value = undefined;
        for (m.bodyParameters(body), &arguments, 0..) |parameter, *argument, ordinal| {
            try g.mapTypes(.{ .unit = m.unit, .ty = parameter.ty }, .{ .unit = m.unit, .ty = actual }, 0);
            argument.* = try g.constant(@intCast(ordinal + 1));
            argument.floating = actual == T.f32_type;
            argument.type_evidence = try g.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = actual }, .arguments = &.{} });
        }
        // A checked generic method's input types are known, but its return
        // variable is deliberately left for ordinary numeric admission.
        const unresolved = try g.resolveType(.{ .unit = m.unit, .ty = m.typeOf(body.root) }, 0);
        try std.testing.expect(m.types.node(unresolved.ty).tag == .variable);
        const saved = g.type_arguments.items.len;
        var unready = try g.prepareFunctionCall(m, target, &arguments);
        defer if (unready) |*call| call.deinit(allocator);
        try std.testing.expect(unready == null);
        try std.testing.expectEqual(saved, g.type_arguments.items.len);
        try std.testing.expect(g.diagnostic == null);
        const result = try g.invokeBody(target, &arguments, 0, true);
        try std.testing.expectEqual(actual == T.f32_type, result.floating);
        // The ordinary expanded result is correct even while the optional
        // planner declines an unresolved return. A checked result use closes
        // that instance before it can enter the shared plan dictionary.
        try g.mapTypes(.{ .unit = m.unit, .ty = m.typeOf(body.root) }, .{ .unit = m.unit, .ty = actual }, 0);
        const resolved = try g.resolveType(.{ .unit = m.unit, .ty = m.typeOf(body.root) }, 0);
        try std.testing.expectEqual(actual, resolved.ty);
        // Once ordinary proof/refinement has completed, both result families
        // use the same immutable plan and retain distinct scalar bit ABIs.
        const second = try g.invokeBody(target, &arguments, 0, true);
        try std.testing.expectEqual(actual == T.f32_type, second.floating);
        const definitions = emission_work.scoped_function_plan_definitions;
        const hits = emission_work.scoped_function_plan_hits;
        const repeated = try g.invokeBody(target, &arguments, 0, true);
        try std.testing.expectEqual(actual == T.f32_type, repeated.floating);
        try std.testing.expectEqual(definitions, emission_work.scoped_function_plan_definitions);
        try std.testing.expectEqual(hits + 1, emission_work.scoped_function_plan_hits);
        try std.testing.expectEqual(@as(u64, 0), emission_work.scoped_function_plan_post_type_queries);
    }
}
test "scalar completed hits preserve unresolved numeric admission and distinct return instantiations through OOM" {
    const allocator = std.testing.allocator;
    const source =
        \\const U32.minus = func (left: U32) -> (right: U32): U32 => return @u32.sub left right
        \\const F32.minus = func (left: F32) -> (right: F32): F32 => return @f32.sub left right
        \\const difference = func left -> right => return @type.call "minus" left right
        \\entry const answer = func (): U32 => return 0
    ;
    var lexed = try @import("../parse/lexer.zig").lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try @import("../check/check.zig").checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var lowered = try core.lower(allocator, &tree, &names, &checked);
    defer lowered.deinit(allocator);
    lowered.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), lowered.diagnostics.len);
    try scalarAdmissionRefinement(allocator, &.{lowered});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, scalarAdmissionRefinement, .{@as([]const core.Module, &.{lowered})});
}

fn primitiveEnvironments(allocator: std.mem.Allocator) !void {
    // Metadata-only resolution. No emission or source-query state is active.
    var g: Generator = undefined;
    g.emitting_function_plan = false;
    g.allocator = allocator;
    g.type_arguments = .empty;
    defer g.type_arguments.deinit(allocator);
    var work: @import("../work_counters.zig").Counters = .{};
    g.emission_work = &work;
    const environment = try allocator.alloc(TypeArgument, 4096);
    defer allocator.free(environment);
    for (environment, 0..) |*item, ordinal| item.* = .{
        .unit = 1,
        .parameter = @intCast(ordinal + 8),
        .argument_unit = 1,
        .argument = T.u32_type,
    };
    const outer = [_]TypeArgument{.{ .unit = 1, .parameter = 7, .argument_unit = 1, .argument = T.f32_type }};
    for (T.unit..T.never + 1) |primitive| {
        const plain: TypeRef = .{ .unit = 1, .ty = @intCast(primitive) };
        const captured: TypeRef = .{ .unit = 1, .ty = @intCast(primitive), .environment = environment };
        try std.testing.expect(std.meta.eql(plain, try g.resolveType(plain, 128)));
        try std.testing.expect(std.meta.eql(captured, try g.resolveType(captured, 127)));
        try std.testing.expect(std.meta.eql(captured, try g.resolveActual(plain, environment, 128)));
        // A separate use environment cannot replace the witness's own frame.
        try std.testing.expect(std.meta.eql(captured, try g.resolveActual(captured, &outer, 127)));
        try std.testing.expectError(error.Declined, g.resolveType(captured, 128));
        try std.testing.expectError(error.Declined, g.resolveActual(captured, &outer, 128));
        try std.testing.expectError(error.Declined, g.resolveType(plain, 129));
        try std.testing.expectError(error.Declined, g.resolveActual(plain, environment, 129));
    }
    try g.type_arguments.append(allocator, .{ .unit = 1, .parameter = 6, .argument_unit = 1, .argument = 7 });
    try g.type_arguments.append(allocator, .{ .unit = 1, .parameter = 7, .argument_unit = 1, .argument = T.f32_type, .environment = environment });
    const result = try g.resolveType(.{ .unit = 1, .ty = 6 }, 0);
    try std.testing.expectEqual(T.f32_type, result.ty);
    try std.testing.expectEqual(environment.ptr, result.environment.?.ptr);
    const selected = try g.resolveActual(.{ .unit = 1, .ty = 7 }, &outer, 0);
    try std.testing.expectEqual(T.f32_type, selected.ty);
    try std.testing.expectEqual(outer[0..].ptr, selected.environment.?.ptr);
    // ID zero deliberately retains the ordinary lookup path.
    try g.type_arguments.append(allocator, .{ .unit = 1, .parameter = 0, .argument_unit = 1, .argument = T.u32_type });
    try std.testing.expectEqual(T.u32_type, (try g.resolveType(.{ .unit = 1, .ty = 0 }, 0)).ty);
    try std.testing.expect(work.scoped_primitive_environment_entries_avoided > 4096);
}
test "primitive resolution preserves captured witnesses variable chains and depth boundaries through OOM" {
    try primitiveEnvironments(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, primitiveEnvironments, .{});
}

fn metadataTestModule(unit_id: u32) core.Module {
    return .{
        .unit = unit_id,
        .types = .{ .nodes = &.{}, .extra = &.{} },
        .nodes = &.{},
        .spans = &.{},
        .extra = &.{},
        .bindings = &.{},
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
}

fn typeEvidenceBoxLifetimes(allocator: std.mem.Allocator) !void {
    const blank = metadataTestModule(1);
    var units = [_]core.Module{ blank, blank };
    units[1].unit = 2;
    var summaries: DescriptorCalls = .{ .allocator = allocator, .arena = .init(allocator), .calls = .{ .allocator = allocator }, .record_metadata = .{ .allocator = allocator } };
    defer summaries.deinit();
    try summaries.initPrimitiveEvidence(&units);
    var retained: Value = undefined;
    {
        var g: Generator = undefined;
        g.emitting_function_plan = false;
        g.allocator = allocator;
        g.arena = .init(allocator);
        defer g.arena.deinit();
        g.descriptor_calls = &summaries;
        const primitive = try g.boxTypeEvidence(.{ .root = .{ .unit = 1, .ty = T.u32_type }, .arguments = &.{} });
        try std.testing.expectEqual(primitive, try g.boxTypeEvidence(.{ .root = primitive.root, .arguments = &.{} }));
        const other = try g.boxTypeEvidence(.{ .root = .{ .unit = 2, .ty = T.u32_type }, .arguments = &.{} });
        try std.testing.expect(primitive != other);
        try std.testing.expectEqual(@as(u32, 2), other.root.unit);
        // A present empty environment remains present, and cannot use a plain
        // primitive witness from the table.
        const captured = try g.boxTypeEvidence(.{ .root = .{ .unit = 1, .ty = T.u32_type, .environment = &.{} }, .arguments = &.{} });
        try std.testing.expect(captured != primitive);
        try std.testing.expect(captured.root.environment != null);
        for ([_]u32{ 0, 3, std.math.maxInt(u32) }) |unit_id| {
            const outside = try g.boxTypeEvidence(.{ .root = .{ .unit = unit_id, .ty = T.u32_type }, .arguments = &.{} });
            try std.testing.expectEqual(unit_id, outside.root.unit);
        }
        const arguments = try g.arena.allocator().alloc(TypeArgument, 1);
        arguments[0] = .{ .unit = 1, .parameter = 6, .argument_unit = 1, .argument = T.f32_type };
        const witness = try g.boxTypeEvidence(.{ .root = .{ .unit = 1, .ty = 6, .environment = arguments }, .arguments = arguments });
        try std.testing.expectEqual(arguments.ptr, witness.arguments.ptr);
        var copies: Generator.EnvironmentCopies = .empty;
        defer copies.deinit(allocator);
        retained = try g.retainGraphShape(.{ .word = .{ .id = 0 }, .type_evidence = witness }, 0, &copies, 0);
        try std.testing.expect(retained.type_evidence.? != witness);
        try std.testing.expect(retained.type_evidence.?.arguments.ptr != arguments.ptr);
        // Both aliases of the same captured environment retain one owned copy.
        try std.testing.expectEqual(retained.type_evidence.?.arguments.ptr, retained.type_evidence.?.root.environment.?.ptr);
    }
    // The source Generator and its witness/environment arena are gone.
    try std.testing.expectEqual(@as(u32, 6), retained.type_evidence.?.root.ty);
    try std.testing.expectEqual(T.f32_type, retained.type_evidence.?.arguments[0].argument);
}
test "boxed type witnesses preserve primitive units environments and retained arena ownership through OOM" {
    try typeEvidenceBoxLifetimes(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, typeEvidenceBoxLifetimes, .{});
}

fn primitiveKeyMemo(allocator: std.mem.Allocator) !void {
    var nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never } };
    var units = [_]core.Module{ metadataTestModule(1), metadataTestModule(2) };
    for (&units) |*unit_| unit_.types = .{ .nodes = &nodes, .extra = &.{} };
    var g: Generator = undefined;
    g.emitting_function_plan = false;
    g.allocator = allocator;
    g.units = &units;
    g.type_arguments = .empty;
    defer g.type_arguments.deinit(allocator);
    var work: @import("../work_counters.zig").Counters = .{};
    g.emission_work = &work;
    const first = [_]TypeArgument{.{ .unit = 1, .parameter = 6, .argument_unit = 1, .argument = T.u32_type }};
    const second = [_]TypeArgument{.{ .unit = 2, .parameter = 7, .argument_unit = 2, .argument = T.f32_type }};
    var old_work: usize = 4096;
    var new_work: usize = old_work;
    var old = selected_types.Builder.init(allocator, &old_work, .{ .hash_mask = 0 });
    defer old.deinit();
    var new = selected_types.Builder.init(allocator, &new_work, .{ .hash_mask = 0 });
    defer new.deinit();
    var expected: std.ArrayList(u32) = .empty;
    defer expected.deinit(allocator);
    var actual: std.ArrayList(u32) = .empty;
    defer actual.deinit(allocator);
    for ([_]?[]const TypeArgument{ null, &first, &second, &.{}, &first }) |environment| {
        for (T.unit..T.never + 1) |primitive| {
            const input: TypeRef = .{ .unit = 1 + @as(u32, @intCast(primitive % 2)), .ty = @intCast(primitive), .environment = environment };
            const resolved = try g.resolveType(input, 0);
            const reference: selected_types.Reference = .{ .unit = resolved.unit, .ty = resolved.ty, .environment = if (resolved.environment) |frame| @intFromPtr(frame.ptr) else 0, .environment_len = if (resolved.environment) |frame| frame.len else 0, .captured = resolved.environment != null };
            const prior = (try old.enter(reference, 0)) orelse done: {
                var descriptor: std.ArrayList(u32) = .empty;
                defer descriptor.deinit(allocator);
                try old.addWord(&descriptor, @backingInt(nodes[primitive].tag));
                break :done try old.complete(reference, descriptor.items, 0);
            };
            try old.root(&expected, prior);
            try new.root(&actual, try g.selectedTypeNode(&units[0], 0, input, &new, 0));
        }
    }
    try old.finish(&expected);
    try new.finish(&actual);
    try std.testing.expectEqualSlices(u32, expected.items, actual.items);
    try std.testing.expectEqual(@as(usize, 5), new.nodes.items.len);
    try std.testing.expect(new_work > old_work);
    var tiny_work: usize = 1;
    var tiny = selected_types.Builder.init(allocator, &tiny_work, .{});
    defer tiny.deinit();
    _ = try g.selectedTypeNode(&units[0], 0, .{ .unit = 1, .ty = T.u32_type }, &tiny, 128);
    try std.testing.expectError(error.Limit, g.selectedTypeNode(&units[0], 0, .{ .unit = 2, .ty = T.u32_type }, &tiny, 128));
    var depth_work: usize = 100;
    var depth = selected_types.Builder.init(allocator, &depth_work, .{});
    defer depth.deinit();
    _ = try g.selectedTypeNode(&units[0], 0, .{ .unit = 1, .ty = T.u32_type }, &depth, 128);
    try std.testing.expectError(error.Limit, g.selectedTypeNode(&units[0], 0, .{ .unit = 2, .ty = T.u32_type }, &depth, 129));
}
test "primitive key memo shares only encoded atoms across units captured frames and depth through OOM" {
    try primitiveKeyMemo(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, primitiveKeyMemo, .{});
}

test "callback discovery bounds shared trees depth and owner boundaries" {
    const callback: Callable = .{ .unit = 1, .target = 2 };
    const leaf: Value = .{ .tag = .callable, .word = .{ .id = 0 }, .callable = &callback };
    const payload = [_]Value{leaf};
    const nominal: Value = .{ .tag = .aggregate, .word = .{ .id = 0 }, .nominal = .{ .unit = 1, .decl = 1 }, .fields = &payload };
    const outer = [_]Value{nominal};
    var work: usize = 4;
    try std.testing.expect(Generator.containsCallback(.{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = &outer }, &work, 0));
    try std.testing.expectEqual(@as(usize, 0), work);
    work = 3;
    try std.testing.expect(!Generator.containsCallback(.{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = &outer }, &work, 0));
    work = 2;
    try std.testing.expect(!Generator.containsCallback(.{ .tag = .array, .word = .{ .id = 0 }, .fields = &payload }, &work, 0));
    work = 1;
    try std.testing.expect(Generator.containsCallback(leaf, &work, 128));
    work = 1;
    try std.testing.expect(!Generator.containsCallback(leaf, &work, 129));
    work = 100;
    try std.testing.expect(!Generator.containsCallback(nominal, &work, 128));
    var levels: [20][2]Value = undefined;
    levels[19] = @splat(.{ .word = .{ .id = 0 } });
    var index: usize = 19;
    while (index != 0) {
        index -= 1;
        levels[index] = @splat(.{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = &levels[index + 1] });
    }
    work = 4096;
    try std.testing.expect(!Generator.containsCallback(levels[0][0], &work, 0));
    try std.testing.expectEqual(@as(usize, 0), work);
}

fn preparedReaderHistory(allocator: std.mem.Allocator) !void {
    // Metadata replay is independent of formal admission. In particular, no
    // future admission can silently replace the original read set with its ABI.
    var g: Generator = undefined;
    g.emitting_function_plan = false;
    g.allocator = allocator;
    g.arena = .init(allocator);
    defer g.arena.deinit();
    g.roots = .empty;
    defer g.roots.deinit(allocator);
    g.read_frames = .empty;
    defer g.read_frames.deinit(allocator);
    g.writer_trace = null;
    g.diagnostic = null;
    var m = metadataTestModule(1);
    var spans = [_]core.Span{.{ .start = 0, .end = 0 }};
    m.spans = &spans;
    const scalar: Value = .{ .word = .{ .id = 0 } };
    const initial: Value = .{ .tag = .view, .word = .{ .id = 0 }, .root = 2 };
    const widened: Value = .{ .tag = .view, .word = .{ .id = 0 }, .root = 2, .other_roots = &.{3} };
    const owner: Root = .{ .word = .{ .id = 0 }, .token = .{ .id = 0 }, .epoch_low = .{ .id = 0 }, .epoch_high = .{ .id = 0 }, .stack = 0, .depth = 0, .element = scalar };
    try g.roots.appendNTimes(allocator, owner, 4);
    g.roots.items[0].element = initial;
    const fields = [_]Value{
        .{ .tag = .array, .word = .{ .id = 0 }, .root = 0, .name = "a_omitted" },
        scalar,
        scalar,
        scalar,
        scalar,
        scalar,
        scalar,
        .{ .tag = .array, .word = .{ .id = 0 }, .root = 1, .name = "z_kept" },
    };
    const original: Value = .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = &fields };
    const physical: Value = .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields[7..] };
    const frame = try g.beginReadFrame();
    try g.readerReads(&m, 0, physical);
    try std.testing.expectEqual(@as(usize, 1), g.read_frames.items[frame].first.items.len);
    try g.readerReads(&m, 0, original);
    try std.testing.expectEqual(@as(usize, 2), g.read_frames.items[frame].first.items.len);
    try std.testing.expectEqual(@as(usize, 0), g.read_frames.items[frame].first.items[0].owner);
    g.roots.items[0].element = widened;
    try std.testing.expectError(error.Declined, g.checkReadFrame(&m, 0, frame));
    try std.testing.expectEqual(backend.Code.storage_escape, g.diagnostic.?.code);
}
test "prepared reader original read replay retains omitted owner loop history through OOM" {
    try preparedReaderHistory(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, preparedReaderHistory, .{});
}

fn functionPlanAccessContract(allocator: std.mem.Allocator, units: []const core.Module) !void {
    const m = &units[0];
    const body = for (m.bodies) |*candidate| {
        if (std.mem.eql(u8, m.name(candidate.declaration_name), "ignore")) break candidate;
    } else return error.TestUnexpectedResult;
    const target: core.BindingRef = .{ .unit = m.unit, .binding = body.binding };
    const views = [_]*const core.Module{m};
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    const runtime = try storage.emit(&module);
    const function = try module.addTypedFunction(&.{}, .i32, .scalar);
    var emission_work: @import("../work_counters.zig").Counters = .{};
    var proof_cache = try source_proof.SourceProofCache.initWithInventoryBudget(allocator, &views);
    defer proof_cache.deinit();
    var dispatches: Dispatches = .empty;
    defer dispatches.deinit(allocator);
    var capacity_requests: storage_plan.CapacityRequests = .{ .allocator = allocator };
    defer capacity_requests.deinit();
    var validation_budget: usize = 1_000_000;
    var active_calls: call_plan.ActiveCalls = .{ .allocator = allocator };
    defer active_calls.deinit();
    var scalar_admission: call_plan.ScalarAdmission = .{ .allocator = allocator, .units = units };
    defer scalar_admission.deinit();
    var field_recipes: field_plan.Cache = .{ .allocator = allocator };
    defer field_recipes.deinit();
    var descriptor_calls: DescriptorCalls = .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .record_metadata = .{ .allocator = allocator } };
    defer descriptor_calls.deinit();
    var shared_calls: call_plan.Cache = .{ .allocator = allocator };
    defer shared_calls.deinit();
    var outlining = scope_outline.Context.init(allocator, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer outlining.deinit();
    var methods: MethodSelector = .{ .allocator = allocator, .units = units, .entry = m.unit, .bounds = .{ .allocator = allocator } };
    defer methods.deinit();
    var g: Generator = .{ .entry_unit = m.unit, .methods = &methods, .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .shared_calls = &shared_calls, .descriptor_calls = &descriptor_calls, .field_recipes = &field_recipes, .scalar_admission = &scalar_admission, .active_calls = &active_calls, .units = units, .unit_views = &views, .proof_cache = &proof_cache, .dispatches = &dispatches, .capacity_requests = &capacity_requests, .validation_budget = &validation_budget, .module = &module, .runtime = runtime, .emission_work = &emission_work, .outlining = &outlining, .c = .{ .module = &module, .function = function } };
    defer g.deinit();
    const parameters = m.bodyParameters(body);
    const element: Value = .{ .word = .{ .id = 0 }, .type_evidence = try g.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = T.u32_type }, .arguments = &.{} }) };
    const rows: Value = .{ .tag = .array, .word = try g.c.temp(), .token = try g.c.temp(), .epoch_low = try g.c.temp(), .epoch_high = try g.c.temp(), .root = 0, .type_evidence = try g.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = parameters[0].ty }, .arguments = &.{} }) };
    try g.roots.append(allocator, .{ .word = rows.word, .token = rows.token, .epoch_low = rows.epoch_low, .epoch_high = rows.epoch_high, .stack = 0, .depth = 0, .element = element });
    const arguments = [_]Value{ rows, try g.constant(5) };
    var call = (try g.prepareFunctionCall(m, target, &arguments)) orelse return error.TestUnexpectedResult;
    defer call.deinit(allocator);
    const plan = (try g.getOrBuildFunctionPlan(m, target, &call)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), call.graph.owners.items.len);
    try std.testing.expectEqual(@as(usize, 0), plan.access.ordered.len);
    try std.testing.expectEqual(@as(usize, 5), plan.input_words);
    try std.testing.expectEqual(FunctionAbi.scalar, plan.abi);
    const warm = (try g.getOrBuildFunctionPlan(m, target, &call)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(plan, warm);
    _ = try g.emitPlannedCall(m, body, plan, &arguments, call.graph.owners.items);
    try std.testing.expectEqual(@as(u64, 1), emission_work.scoped_function_plan_empty_owner_contracts);
    try std.testing.expectEqual(@as(u64, 0), emission_work.scoped_function_plan_read_events);
    try std.testing.expectEqual(@as(u64, 0), emission_work.scoped_function_plan_write_events);
    for (m.bodies) |*reader| {
        if (!std.mem.eql(u8, m.name(reader.declaration_name), "observe") and !std.mem.eql(u8, m.name(reader.declaration_name), "branch")) continue;
        const selected: core.BindingRef = .{ .unit = m.unit, .binding = reader.binding };
        var query = (try g.prepareFunctionCall(m, selected, &arguments)) orelse return error.TestUnexpectedResult;
        defer query.deinit(allocator);
        const read_plan = (try g.getOrBuildFunctionPlan(m, selected, &query)) orelse return error.TestUnexpectedResult;
        try std.testing.expect(read_plan.access.ordered.len > 0);
        for (read_plan.access.ordered) |event| {
            try std.testing.expectEqual(WriterKind.read, event.kind);
            try std.testing.expectEqual(@as(usize, 0), event.owner);
        }
    }
    try std.testing.expectEqual(@as(u64, 0), emission_work.scoped_function_plan_post_type_queries);
}

test "function plans retain empty unused-owner contracts actual reads and branch reads through OOM" {
    const allocator = std.testing.allocator;
    const source =
        \\const ignore = func (rows: Array U32) -> (value: U32): U32 => return @u32.add value 17
        \\const observe = func (rows: Array U32) -> (value: U32): U32 => return @u32.add (@storage.read rows 0) value
        \\const branch = func (rows: Array U32) -> (value: U32): U32 => return if @u32.eq value 0 then @storage.read rows 0 else value
        \\entry const answer = func (): U32 => return 0
    ;
    var lexed = try @import("../parse/lexer.zig").lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try @import("../check/check.zig").checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var lowered = try core.lower(allocator, &tree, &names, &checked);
    defer lowered.deinit(allocator);
    lowered.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), lowered.diagnostics.len);
    try functionPlanAccessContract(allocator, &.{lowered});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, functionPlanAccessContract, .{@as([]const core.Module, &.{lowered})});
}

fn recursivePublishedHeaders(g: *const Generator) !void {
    try std.testing.expect(g.recursive_header == null);
    try std.testing.expectEqual(@as(usize, 0), g.active_calls.frames.items.len);
    for (g.descriptor_calls.calls.entries.items) |entry| try std.testing.expect(!entry.building);
    var plans = g.descriptor_calls.plans.iterator();
    while (plans.next()) |entry| {
        const plan = entry.value_ptr.*;
        try std.testing.expect(!plan.entry.building);
        try std.testing.expect(plan.entry.function < g.module.functions.items.len);
    }
}

fn recursiveHeaderAccessContract(allocator: std.mem.Allocator, units: []const core.Module) !void {
    const m = &units[0];
    const recursive = for (m.bodies) |*candidate| {
        if (std.mem.eql(u8, m.name(candidate.declaration_name), "recur")) break candidate;
    } else return error.TestUnexpectedResult;
    const target: core.BindingRef = .{ .unit = m.unit, .binding = recursive.binding };
    const views = [_]*const core.Module{m};
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    const runtime = try storage.emit(&module);
    const function = try module.addTypedFunction(&.{}, .i32, .scalar);
    var emission_work: @import("../work_counters.zig").Counters = .{};
    var proof_cache = try source_proof.SourceProofCache.initWithInventoryBudget(allocator, &views);
    defer proof_cache.deinit();
    var dispatches: Dispatches = .empty;
    defer dispatches.deinit(allocator);
    var capacity_requests: storage_plan.CapacityRequests = .{ .allocator = allocator };
    defer capacity_requests.deinit();
    var validation_budget: usize = 1_000_000;
    var active_calls: call_plan.ActiveCalls = .{ .allocator = allocator };
    defer active_calls.deinit();
    var scalar_admission: call_plan.ScalarAdmission = .{ .allocator = allocator, .units = units };
    defer scalar_admission.deinit();
    var field_recipes: field_plan.Cache = .{ .allocator = allocator };
    defer field_recipes.deinit();
    var descriptor_calls: DescriptorCalls = .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .record_metadata = .{ .allocator = allocator } };
    defer descriptor_calls.deinit();
    var shared_calls: call_plan.Cache = .{ .allocator = allocator };
    defer shared_calls.deinit();
    var outlining = scope_outline.Context.init(allocator, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer outlining.deinit();
    var methods: MethodSelector = .{ .allocator = allocator, .units = units, .entry = m.unit, .bounds = .{ .allocator = allocator } };
    defer methods.deinit();
    var g: Generator = .{ .entry_unit = m.unit, .methods = &methods, .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .shared_calls = &shared_calls, .descriptor_calls = &descriptor_calls, .field_recipes = &field_recipes, .scalar_admission = &scalar_admission, .active_calls = &active_calls, .units = units, .unit_views = &views, .proof_cache = &proof_cache, .dispatches = &dispatches, .capacity_requests = &capacity_requests, .validation_budget = &validation_budget, .module = &module, .runtime = runtime, .emission_work = &emission_work, .outlining = &outlining, .c = .{ .module = &module, .function = function } };
    defer g.deinit();
    const parameters = m.bodyParameters(recursive);
    const element: Value = .{ .word = .{ .id = 0 }, .literal = 17, .constant_bits = 17, .type_evidence = try g.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = T.u32_type }, .arguments = &.{} }) };
    const rows: Value = .{ .tag = .array, .word = try g.c.temp(), .token = try g.c.temp(), .epoch_low = try g.c.temp(), .epoch_high = try g.c.temp(), .root = 0, .type_evidence = try g.boxTypeEvidence(.{ .root = .{ .unit = m.unit, .ty = parameters[0].ty }, .arguments = &.{} }) };
    try g.roots.append(allocator, .{ .word = rows.word, .token = rows.token, .epoch_low = rows.epoch_low, .epoch_high = rows.epoch_high, .stack = 0, .depth = 0, .element = element });
    const arguments = [_]Value{ rows, try g.constant(5) };
    const first = g.recursiveCall(m, target, &arguments) catch |err| {
        try recursivePublishedHeaders(&g);
        return err;
    };
    try std.testing.expect(first != null);
    try recursivePublishedHeaders(&g);
    try std.testing.expectEqual(@as(u64, 1), emission_work.scoped_recursive_definitions);
    try std.testing.expectEqual(@as(u64, 1), emission_work.scoped_recursive_backedges);
    try std.testing.expectEqual(@as(?u32, null), g.roots.items[0].element.literal);
    try std.testing.expectEqual(@as(?u32, null), g.roots.items[0].element.constant_bits);
    var recursive_plan: ?*const CheckedFunctionPlan = null;
    var plans = descriptor_calls.plans.iterator();
    while (plans.next()) |entry| if (entry.value_ptr.*.access == .invariant) {
        try std.testing.expect(recursive_plan == null);
        recursive_plan = entry.value_ptr.*;
    };
    const plan = recursive_plan orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 5), plan.input_words);
    try std.testing.expectEqual(@as(usize, 5), module.functions.items[plan.entry.function].parameters.len);
    try std.testing.expectEqual(FunctionAbi.scalar, plan.abi);
    try std.testing.expect(plan.unit_result);
    try std.testing.expectEqual(@as(usize, 0), plan.regions.len);
    try std.testing.expectEqual(@as(usize, 1), plan.access.invariant.len);
    try std.testing.expect(plan.access.invariant[0].read and plan.access.invariant[0].write);
    const completed = descriptor_calls.plans.count();
    const changed_arguments = [_]Value{ rows, try g.constant(7) };
    try std.testing.expect((try g.recursiveCall(m, target, &changed_arguments)) != null);
    try std.testing.expectEqual(completed, descriptor_calls.plans.count());
    try std.testing.expectEqual(@as(u64, 1), emission_work.scoped_recursive_definitions);

    // Build both ordinary layers so their completed ordered contracts must
    // retain the recursive write's lack of initialization authority.
    var outer: ?*const CheckedFunctionPlan = null;
    var outer_body: ?*const core.Body = null;
    for ([_][]const u8{ "wrap1", "wrap2" }) |name| {
        const body = for (m.bodies) |*candidate| {
            if (std.mem.eql(u8, m.name(candidate.declaration_name), name)) break candidate;
        } else return error.TestUnexpectedResult;
        const selected: core.BindingRef = .{ .unit = m.unit, .binding = body.binding };
        var call = (try g.prepareFunctionCall(m, selected, &arguments)) orelse return error.TestUnexpectedResult;
        defer call.deinit(allocator);
        const wrapper = (g.getOrBuildFunctionPlan(m, selected, &call) catch |err| {
            try recursivePublishedHeaders(&g);
            return err;
        }) orelse return error.TestUnexpectedResult;
        try std.testing.expect(wrapper.access == .ordered);
        var reads: usize = 0;
        var writes: usize = 0;
        for (wrapper.access.ordered) |event| {
            try std.testing.expectEqual(@as(usize, 0), event.owner);
            if (event.kind == .read) reads += 1 else {
                writes += 1;
                try std.testing.expect(!event.initializes_rows);
            }
        }
        try std.testing.expect(reads > 0 and writes > 0);
        try std.testing.expectEqual(wrapper, (try g.getOrBuildFunctionPlan(m, selected, &call)).?);
        outer = wrapper;
        outer_body = body;
    }
    try recursivePublishedHeaders(&g);
    const owners = [_]usize{0};
    g.roots.items[0].element_initialized = false;
    g.roots.items[0].known_empty = true;
    g.roots.items[0].element.literal = 23;
    g.roots.items[0].element.constant_bits = 23;
    const frame = try g.beginReadFrame();
    _ = try g.emitPlannedCall(m, outer_body.?, outer.?, &arguments, &owners);
    try std.testing.expect(!g.roots.items[0].element_initialized);
    try std.testing.expect(g.roots.items[0].known_empty);
    try std.testing.expectEqual(@as(?u32, null), g.roots.items[0].element.literal);
    try std.testing.expectEqual(@as(?u32, null), g.roots.items[0].element.constant_bits);
    try std.testing.expectEqual(@as(usize, 1), g.read_frames.items[frame].first.items.len);
    try std.testing.expectEqual(@as(usize, 0), g.read_frames.items[frame].first.items[0].owner);
    try g.checkReadFrame(m, recursive.root, frame);
    _ = try g.emitPlannedCall(m, recursive, plan, &arguments, &owners);
    try std.testing.expect(!g.roots.items[0].element_initialized);
    try std.testing.expect(g.roots.items[0].known_empty);

    // Failure calls must propagate injected OOM rather than count it as the
    // expected semantic rejection. Neither path may emit a machine call.
    for ([_]bool{ false, true }) |frozen| {
        g.roots.items[0].known_empty = false;
        g.roots.items[0].element_initialized = frozen;
        g.roots.items[0].frozen = frozen;
        g.diagnostic = null;
        const before = module.functions.items[function].instructions.items.len;
        if (g.emitPlannedCall(m, recursive, plan, &arguments, &owners)) |_| return error.TestUnexpectedResult else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(error.Declined, err);
        }
        try std.testing.expectEqual(backend.Code.storage_escape, g.diagnostic.?.code);
        try std.testing.expectEqual(before, module.functions.items[function].instructions.items.len);
    }
    g.roots.items[0].frozen = false;
    g.roots.items[0].element_initialized = true;
    g.diagnostic = null;
    const definitions_before_retry = emission_work.scoped_recursive_definitions;
    const plans_before_retry = descriptor_calls.plans.count();
    try std.testing.expect((try g.recursiveCall(m, target, &changed_arguments)) != null);
    try std.testing.expectEqual(definitions_before_retry, emission_work.scoped_recursive_definitions);
    try std.testing.expectEqual(plans_before_retry, descriptor_calls.plans.count());
    try recursivePublishedHeaders(&g);
}

test "recursive headers preserve finite access replay and transactional publication through full OOM" {
    const allocator = std.testing.allocator;
    const source =
        \\const recur = func (rows: Array U32) -> (n: U32): Unit => return do:
        \\  if @u32.lt 0 n:
        \\    rows[0] := @u32.add rows[0] 1
        \\    recur rows (@u32.sub n 1)
        \\  return ()
        \\const wrap1 = func (rows: Array U32) -> (n: U32): Unit => return recur rows n
        \\const wrap2 = func (rows: Array U32) -> (n: U32): Unit => return wrap1 rows n
        \\entry const answer = func (): U32 => return 0
    ;
    var lexed = try @import("../parse/lexer.zig").lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try @import("../check/check.zig").checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var lowered = try core.lower(allocator, &tree, &names, &checked);
    defer lowered.deinit(allocator);
    lowered.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), lowered.diagnostics.len);
    try recursiveHeaderAccessContract(allocator, &.{lowered});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, recursiveHeaderAccessContract, .{@as([]const core.Module, &.{lowered})});
}
