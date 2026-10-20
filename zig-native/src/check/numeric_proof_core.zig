//! Recompute proof authority from executable Core. Public recipes describe
//! obligations; only executed guards, exact aliases and explicit formal proof
//! parameters supply witnesses. No source receipt grants portable authority.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const terms = @import("numeric_proof_terms.zig");
const headers = @import("numeric_proof_headers.zig");
const contracts = @import("numeric_proof_contracts.zig");
const A = std.mem.Allocator;
pub const Error = error{ InvalidArtifact, OutOfMemory };
const WorkError = Error || headers.Error;
const Value = struct { operand: terms.Id = 0, proof: ?terms.Proposition = null, condition: u32 = 0, exits: bool = false };
const Entry = struct { binding: u32, value: Value };
const Return = struct { target: core.Id, value: Value };
const Fact = union(enum) { order: terms.Proposition, unequal: contracts.Unequal };
const Condition = struct { op: core.Op = .none, negated: bool = false, left: u32 = 0, right: u32 = 0, positive: ?Fact = null, negative: ?Fact = null };
const SummaryInputs = union(enum) {
    parameters: struct { bindings: []const core.Parameter, values: []const Value },
    captures: []const Entry,
    locals: struct { entries: []const Entry, parent: *const SummaryInputs },

    fn lookup(self: SummaryInputs, binding: u32) ?Value {
        switch (self) {
            .parameters => |input| for (input.bindings, input.values) |parameter, value| {
                if (parameter.binding == binding) return value;
            },
            .captures => |entries| {
                var index = entries.len;
                while (index != 0) {
                    index -= 1;
                    if (entries[index].binding == binding) return entries[index].value;
                }
            },
            .locals => |input| {
                var index = input.entries.len;
                while (index != 0) {
                    index -= 1;
                    if (input.entries[index].binding == binding) return input.entries[index].value;
                }
                return input.parent.lookup(binding);
            },
        }
        return null;
    }
};

/// An owned, recomputed admission flag for each executable check. Every visit
/// to a shared Core node must prove the check; one unproved visit revokes it.
/// This plan contains no public authority and is never decoded from an archive.
pub const Plan = struct {
    checks: std.AutoHashMapUnmanaged(core.Id, bool) = .empty,
    visits: usize = 0,
    pub fn deinit(self: *Plan, allocator: A) void {
        self.checks.deinit(allocator);
    }
    pub fn admits(self: *const Plan, id: core.Id) bool {
        return self.checks.get(id) orelse false;
    }
    fn record(self: *Plan, allocator: A, id: core.Id, admitted: bool) A.Error!void {
        const entry = try self.checks.getOrPut(allocator, id);
        if (!entry.found_existing) entry.value_ptr.* = true;
        entry.value_ptr.* = entry.value_ptr.* and admitted;
    }
};

fn require(condition: bool) Error!void {
    if (!condition) return error.InvalidArtifact;
}
fn kind(tag: T.Tag) ?terms.Kind {
    return switch (tag) {
        .u32 => .u32,
        .array => .array,
        .list => .list,
        else => null,
    };
}
fn opaqueReferenceConstructor(module: *const core.Module, catalog: u32) bool {
    if (catalog >= module.constructors.len) return false;
    const constructor = module.constructor(catalog);
    if (constructor.nominal >= module.nominals.len) return false;
    const nominal = module.nominal(constructor.nominal);
    const constructors = module.nominalConstructors(constructor.nominal);
    return nominal.is_opaque and !nominal.affine and !nominal.has_usage and nominal.storage.kind == .reference and constructors.len == 1 and constructors[0] == catalog;
}
fn opaqueReferenceBinding(module: *const core.Module, id: core.PatternId) ?u32 {
    const pattern = module.pattern(id);
    if (pattern.tag != .constructor or pattern.b == 0 or !opaqueReferenceConstructor(module, pattern.a)) return null;
    const payload = module.pattern(pattern.b);
    return if (payload.tag == .bind and payload.a != 0) payload.a else null;
}
fn opaqueReferenceResult(module: *const core.Module, binding: u32, arguments: usize) bool {
    if (binding == 0 or binding >= module.bindings.len) return false;
    var ty = module.bindings[binding].ty;
    for (0..128) |_| {
        const node = module.types.node(ty);
        if (node.tag != .forall) break;
        ty = node.a;
    } else return false;
    for (0..arguments) |_| {
        const node = module.types.node(ty);
        if (node.tag != .function) return false;
        ty = node.b;
    }
    const result = module.types.node(ty);
    if (result.tag != .nominal) return false;
    for (module.nominals, 0..) |nominal, index| {
        if (nominal.identity.unit == result.a and nominal.identity.decl == result.b) {
            const constructors = module.nominalConstructors(@intCast(index));
            return constructors.len == 1 and opaqueReferenceConstructor(module, constructors[0]);
        }
    }
    return false;
}
pub fn contract(module: *const core.Module, binding: u32) ?*const headers.Owned {
    for (module.proof_contracts) |*value| if (value.binding == binding) return &value.header;
    return null;
}
/// The datatype leaf is never enough: every numeric/collection and proof
/// position must agree with the complete positional recipe.
pub fn signatureTypes(source: anytype, root: T.Id, header: headers.Owned) Error!void {
    var ty = root;
    var wrappers: usize = 0;
    while (source.node(resolved(source, ty)).tag == .forall) {
        try require(wrappers < 128);
        wrappers += 1;
        ty = source.node(resolved(source, ty)).a;
    }
    var value_slot: usize = 0;
    var proof_slot: usize = 0;
    for (0..header.arity) |slot| {
        const arrow = source.node(resolved(source, ty));
        try require(arrow.tag == .function);
        const input = source.node(resolved(source, arrow.a)).tag;
        if (kind(input)) |expected| {
            try require(value_slot < header.value_slots.len and value_slot < header.values.len);
            try require(header.value_slots[value_slot] == slot and header.values[value_slot] == expected);
            value_slot += 1;
        } else if (input == .erased_proof) {
            try require(proof_slot < header.proof_slots.len and header.proof_slots[proof_slot] == slot);
            proof_slot += 1;
        }
        ty = arrow.b;
    }
    try require(value_slot == header.value_slots.len and proof_slot == header.proof_slots.len);
    try require((source.node(resolved(source, ty)).tag == .erased_proof) == (header.result != null));
}
fn resolved(source: anytype, id: T.Id) T.Id {
    const Source = switch (@typeInfo(@TypeOf(source))) {
        .pointer => |pointer| pointer.child,
        else => @TypeOf(source),
    };
    if (comptime @hasDecl(Source, "head")) return source.head(id, 0);
    return id;
}
/// Call after datatype bounds validation. Proof leaves have a separate kind
/// and cannot fill an ordinary container or datatype parameter.
pub fn dataTypes(source: anytype, nodes: []const T.Node) Error!void {
    for (nodes) |node| switch (node.tag) {
        .array, .list, .cursor, .demand, .resolver, .provider => try require(source.node(node.a).tag != .erased_proof),
        .state_provider => for ([_]T.Id{ node.a, node.b, node.c }) |child| try require(source.node(child).tag != .erased_proof),
        .product => for (source.list(.{ .start = node.a, .len = node.b })) |child| try require(source.node(child).tag != .erased_proof),
        .record => for (0..node.b) |field| try require(source.node(source.recordField(node, field).ty).tag != .erased_proof),
        .nominal, .projection => for (source.nominalArguments(node)) |child| try require(source.node(child).tag != .erased_proof),
        else => {},
    };
}

/// Borrowed only from one already resolved, unpublished executable body.
/// These targets are never decoded or selected again by the numeric reader.
pub const Selected = struct { node: core.Id, target: core.BindingRef };

const Loop = struct { source: core.Id, previous: ?*Loop, breaks: bool = false };

const Checker = struct {
    selected: []const Selected = &.{},
    allocator: A,
    module: *const core.Module,
    units: []const *const core.Module,
    values: terms.Store = .{},
    environment: std.ArrayList(Entry) = .empty,
    returns: std.ArrayList(Return) = .empty,
    plan: ?*Plan = null,
    facts: std.ArrayList(Fact) = .empty,
    conditions: std.ArrayList(Condition) = .empty,
    degraded: bool = false,
    event: u32 = 0,
    loop: ?*Loop = null,
    fn deinit(self: *Checker) void {
        self.values.deinit(self.allocator);
        self.environment.deinit(self.allocator);
        self.returns.deinit(self.allocator);
        self.facts.deinit(self.allocator);
        self.conditions.deinit(self.allocator);
    }
    fn owner(self: *const Checker, unit: u32) Error!*const core.Module {
        if (unit == 0 or unit == self.module.unit) return self.module;
        for (self.units) |module| if (module.unit == unit) return module;
        return error.InvalidArtifact;
    }
    fn target(self: *const Checker, raw: core.BindingRef) Error!struct { module: *const core.Module, binding: u32 } {
        var module = try self.owner(raw.unit);
        var binding = raw.binding;
        for (0..128) |_| {
            try require(binding != 0 and binding < module.bindings.len);
            const value = module.bindings[binding];
            if (value.kind != .external) return .{ .module = module, .binding = binding };
            var next = module;
            if (value.target.unit != 0 and value.target.unit != module.unit) {
                next = try self.owner(value.target.unit);
            }
            module = next;
            binding = value.target.binding;
        }
        return error.InvalidArtifact;
    }
    fn lookup(self: *const Checker, binding: u32) ?Value {
        var index = self.environment.items.len;
        while (index != 0) {
            index -= 1;
            const entry = self.environment.items[index];
            if (entry.binding == binding) return entry.value;
        }
        return null;
    }
    fn bind(self: *Checker, binding: u32, value: Value) WorkError!void {
        try self.values.charge(1);
        if (self.environment.items.len >= self.values.limits.terms) return error.ProofAnalysisLimit;
        try self.environment.append(self.allocator, .{ .binding = binding, .value = value });
    }
    fn version(self: *Checker, ty: T.Id, binding: u32) WorkError!Value {
        const operand_kind = kind(self.module.types.node(ty).tag) orelse return .{};
        if (binding != 0) return .{ .operand = try self.values.intern(self.allocator, .{ .tag = .version, .kind = operand_kind, .a = binding, .b = 1 }) };
        self.event = std.math.add(u32, self.event, 1) catch return error.ProofAnalysisLimit;
        return .{ .operand = try self.values.intern(self.allocator, .{ .tag = .version, .kind = operand_kind, .a = self.event, .b = 2 }) };
    }
    fn ordinary(value: Value) Error!void {
        try require(value.proof == null);
    }
    fn proof(self: *Checker, actual: ?terms.Proposition, expected: terms.Proposition) WorkError!void {
        const supplied = actual orelse return error.InvalidArtifact;
        if (std.meta.eql(supplied, expected)) return;
        try require(try contracts.entails(self.allocator, &self.values, &.{supplied}, expected));
    }
    fn fact(self: *Checker, value: Fact) WorkError!void {
        if (self.plan == null or self.degraded) return;
        for (self.facts.items) |prior| if (std.meta.eql(prior, value)) return;
        if (self.facts.items.len >= 256) return;
        try self.values.charge(1);
        try self.facts.append(self.allocator, value);
    }
    fn query(self: *Checker, goal: terms.Proposition) WorkError!bool {
        if (self.plan == null or self.degraded) return false;
        var ordered: [256]terms.Proposition = undefined;
        var unequal: [256]contracts.Unequal = undefined;
        var order_count: usize = 0;
        var unequal_count: usize = 0;
        for (self.facts.items) |item| switch (item) {
            .order => |value| {
                ordered[order_count] = value;
                order_count += 1;
            },
            .unequal => |value| {
                unequal[unequal_count] = value;
                unequal_count += 1;
            },
        };
        return contracts.entailsWithUnequal(self.allocator, &self.values, ordered[0..order_count], unequal[0..unequal_count], goal) catch |err| {
            if (err == error.OutOfMemory) return err;
            if (err == error.ProofAnalysisLimit) self.degraded = true;
            return false;
        };
    }
    fn condition(self: *Checker, value: Condition) WorkError!u32 {
        if (self.plan == null) return 0;
        try self.values.charge(1);
        if (self.conditions.items.len >= self.values.limits.terms) return error.ProofAnalysisLimit;
        try self.conditions.append(self.allocator, value);
        return @intCast(self.conditions.items.len);
    }
    fn length(self: *Checker, value: Value) WorkError!terms.Id {
        if (value.operand == 0) return error.InvalidProofOperand;
        return self.values.intern(self.allocator, .{ .tag = .length, .a = value.operand });
    }
    fn preserveLength(self: *Checker, id: core.Id, input: Value) WorkError!Value {
        const result = try self.version(self.module.typeOf(id), 0);
        if (result.operand != 0 and input.operand != 0) try self.fact(.{ .order = .{ .relation = .eq, .left = try self.length(result), .right = try self.length(input) } });
        return result;
    }
    /// Identities hold for every U32 bit pattern, without a no-wrap fact.
    fn arithmeticIdentity(self: *Checker, op: core.Op, left: terms.Id, right: terms.Id) WorkError!terms.Id {
        if (left == 0 or right == 0) return 0;
        const lhs = try self.values.view().get(left);
        const rhs = try self.values.view().get(right);
        if (lhs.kind != .u32 or rhs.kind != .u32) return 0;
        switch (op) {
            .add, .sub, .bit_or, .bit_xor => {
                if (rhs.tag == .literal and rhs.a == 0) return left;
                if (op != .sub and lhs.tag == .literal and lhs.a == 0) return right;
                if ((op == .sub or op == .bit_xor) and left == right) return self.values.intern(self.allocator, .{ .tag = .literal, .a = 0 });
                if (op == .bit_or and left == right) return left;
            },
            .mul, .div => {
                if (rhs.tag == .literal and rhs.a == 1) return left;
                if (op == .mul and lhs.tag == .literal and lhs.a == 1) return right;
            },
            .bit_and => {
                if (rhs.tag == .literal and rhs.a == std.math.maxInt(u32)) return left;
                if (lhs.tag == .literal and lhs.a == std.math.maxInt(u32)) return right;
                if (left == right) return left;
            },
            .shift_left, .shift_right => {
                // U32 shifts mask the count to five bits, matching Wasm.
                if (rhs.tag == .literal and rhs.a & 31 == 0) return left;
            },
            else => {},
        }
        return 0;
    }
    fn arithmetic(self: *Checker, id: core.Id, op: core.Op, left: Value, right: Value) WorkError!Value {
        const lhs = try self.values.view().get(left.operand);
        const rhs = try self.values.view().get(right.operand);
        if (lhs.tag == .literal and rhs.tag == .literal) {
            const value = @import("../backend/scalar_ops.zig").evaluate(op, .{ .scalar = .u32, .bits = lhs.a }, .{ .scalar = .u32, .bits = rhs.a }) catch return self.version(self.module.typeOf(id), 0);
            if (value.scalar == .u32) return .{ .operand = try self.values.intern(self.allocator, .{ .tag = .literal, .a = value.bits }) };
        }
        const identity = try self.arithmeticIdentity(op, left.operand, right.operand);
        if (identity != 0) return .{ .operand = identity };
        const result = try self.version(self.module.typeOf(id), 0);
        if (op != .add and op != .sub) return result;
        const zero = try self.values.intern(self.allocator, .{ .tag = .literal, .a = 0 });
        var fits: terms.Relation = .add_fits;
        if (op == .sub) fits = .sub_fits;
        if (!try self.query(.{ .relation = fits, .left = left.operand, .right = right.operand })) return result;
        if (op == .add) {
            try self.fact(.{ .order = .{ .relation = .le, .left = left.operand, .right = result.operand } });
            try self.fact(.{ .order = .{ .relation = .le, .left = right.operand, .right = result.operand } });
            if (try self.query(.{ .relation = .lt, .left = zero, .right = right.operand })) try self.fact(.{ .order = .{ .relation = .lt, .left = left.operand, .right = result.operand } });
            if (try self.query(.{ .relation = .lt, .left = zero, .right = left.operand })) try self.fact(.{ .order = .{ .relation = .lt, .left = right.operand, .right = result.operand } });
        } else {
            try self.fact(.{ .order = .{ .relation = .le, .left = result.operand, .right = left.operand } });
            if (try self.query(.{ .relation = .lt, .left = zero, .right = right.operand })) try self.fact(.{ .order = .{ .relation = .lt, .left = result.operand, .right = left.operand } });
        }
        return result;
    }
    fn assume(self: *Checker, id: u32, positive: bool, depth: usize) WorkError!void {
        if (id == 0 or self.plan == null or self.degraded) return;
        if (depth >= 128) return error.ProofAnalysisLimit;
        try self.values.charge(1);
        const value = self.conditions.items[id - 1];
        if (value.negated) return self.assume(value.left, !positive, depth + 1);
        if (value.op == .none) {
            var selected = value.negative;
            if (positive) selected = value.positive;
            if (selected) |item| try self.fact(item);
            return;
        }
        if ((value.op == .and_ and positive) or (value.op == .or_ and !positive)) {
            try self.assume(value.left, positive, depth + 1);
            try self.assume(value.right, positive, depth + 1);
            return;
        }
        // The other short-circuit outcome has two predecessors. Keep only
        // exact facts common to both, rather than guessing which operand ran.
        const start = self.facts.items.len;
        try self.assume(value.left, positive, depth + 1);
        const first = try self.allocator.dupe(Fact, self.facts.items[start..]);
        defer self.allocator.free(first);
        self.facts.shrinkRetainingCapacity(start);
        try self.assume(value.left, !positive, depth + 1);
        try self.assume(value.right, positive, depth + 1);
        const second = try self.allocator.dupe(Fact, self.facts.items[start..]);
        defer self.allocator.free(second);
        self.facts.shrinkRetainingCapacity(start);
        for (first) |item| for (second) |other| if (std.meta.eql(item, other)) {
            try self.fact(item);
            break;
        };
    }
    fn join(left: Value, right: Value, proof_result: bool) Error!Value {
        if (left.exits) return right;
        if (right.exits) return left;
        if (proof_result) {
            try require(left.proof != null and right.proof != null);
            try require(std.meta.eql(left.proof.?, right.proof.?));
            return left;
        }
        try ordinary(left);
        try ordinary(right);
        if (std.meta.eql(left, right)) return left;
        if (left.operand == right.operand) return .{ .operand = left.operand };
        return .{};
    }
    fn operands(self: *Checker, children: []const core.Id, depth: usize) WorkError!void {
        for (children) |child| try ordinary(try self.walk(child, depth + 1));
    }
    fn comparison(self: *Checker, op: core.Op, left: terms.Id, right: terms.Id) WorkError!u32 {
        if (left == 0 or right == 0) return 0;
        if ((try self.values.view().get(left)).kind != .u32 or (try self.values.view().get(right)).kind != .u32) return 0;
        const forward: terms.Proposition = .{ .relation = .lt, .left = left, .right = right };
        const backward: terms.Proposition = .{ .relation = .le, .left = right, .right = left };
        const equal: Fact = .{ .order = .{ .relation = .eq, .left = left, .right = right } };
        const unequal: Fact = .{ .unequal = .{ .left = left, .right = right } };
        const result: Condition = switch (op) {
            .less => .{ .positive = .{ .order = forward }, .negative = .{ .order = backward } },
            .less_equal => .{ .positive = .{ .order = .{ .relation = .le, .left = left, .right = right } }, .negative = .{ .order = .{ .relation = .lt, .left = right, .right = left } } },
            .greater => .{ .positive = .{ .order = .{ .relation = .lt, .left = right, .right = left } }, .negative = .{ .order = .{ .relation = .le, .left = left, .right = right } } },
            .greater_equal => .{ .positive = .{ .order = backward }, .negative = .{ .order = forward } },
            .equal => .{ .positive = equal, .negative = unequal },
            .not_equal => .{ .positive = unequal, .negative = equal },
            else => return 0,
        };
        return self.condition(result);
    }
    fn summaryOperand(self: *Checker, module: *const core.Module, inputs: SummaryInputs, id: core.Id, depth: usize) WorkError!terms.Id {
        if (id == 0 or depth >= 32) return 0;
        try self.values.charge(1);
        const node = module.node(id);
        if (node.tag == .reference) {
            const reference = module.reference(id);
            if (reference.unit != 0 and reference.unit != module.unit) return 0;
            if (inputs.lookup(reference.binding)) |value| return value.operand;
        }
        if (node.tag == .constant and module.types.node(node.ty).tag == .u32) return self.values.intern(self.allocator, .{ .tag = .literal, .a = node.a });
        if (node.tag == .scalar and node.c == 0 and module.types.node(node.ty).tag == .u32 and node.b != 0) {
            if (module.types.node(module.typeOf(node.a)).tag != .u32 or module.types.node(module.typeOf(node.b)).tag != .u32) return 0;
            const left = try self.summaryOperand(module, inputs, node.a, depth + 1);
            const right = try self.summaryOperand(module, inputs, node.b, depth + 1);
            return self.arithmeticIdentity(node.op, left, right);
        }
        if (node.tag == .construct and node.b != 0 and opaqueReferenceConstructor(module, node.a)) return self.summaryOperand(module, inputs, node.b, depth + 1);
        if (node.tag == .call) return (try self.summaryInvocation(module, inputs, id, depth)).operand;
        if (node.tag == .block) return (try self.summaryBlock(module, inputs, id, &.{}, depth)).operand;
        if (node.tag == .suite and module.children(id).len == 1) return self.summaryOperand(module, inputs, module.children(id)[0], depth + 1);
        if (node.tag == .array_op and module.arrayOperation(id) == .length) {
            const children = module.children(id);
            if (children.len != 1) return 0;
            const operand = try self.summaryOperand(module, inputs, children[0], depth + 1);
            if (operand == 0) return 0;
            const collection = (try self.values.view().get(operand)).kind;
            if (collection != .array and collection != .list) return 0;
            return self.values.intern(self.allocator, .{ .tag = .length, .a = operand });
        }
        return 0;
    }
    /// Read the selected immutable body, without trusting the helper's name or
    /// a stored summary. Exact operand identities, collection lengths, primitive
    /// comparisons and their Boolean composition qualify. Demand conditions
    /// come from exact captured values; reading them does not execute guards.
    fn summaryCall(self: *Checker, target_: core.BindingRef, actual: []const Value, depth: usize) WorkError!Value {
        if (depth >= 32) return .{};
        const selected = try self.target(target_);
        const binding = selected.module.bindings[selected.binding];
        if (binding.body_id == 0 or binding.body_id >= selected.module.bodies.len) return .{};
        const body_ = &selected.module.bodies[binding.body_id];
        const parameters = selected.module.bodyParameters(body_);
        if (body_.binding != selected.binding or !body_.is_function or parameters.len > actual.len) return .{};
        for (parameters, 0..) |parameter, index| {
            try self.values.charge(index + 1);
            if (parameter.binding == 0) return .{};
            for (parameters[0..index]) |prior| if (prior.binding == parameter.binding) return .{};
        }
        return self.summaryApplied(selected.module, .{ .parameters = .{ .bindings = parameters, .values = actual[0..parameters.len] } }, body_.root, actual[parameters.len..], depth + 1);
    }
    fn summaryApplied(self: *Checker, module: *const core.Module, inputs: SummaryInputs, id: core.Id, arguments: []const Value, depth: usize) WorkError!Value {
        if (id == 0 or depth >= 32) return .{};
        if (arguments.len == 0) return self.summaryValue(module, inputs, id, depth);
        try self.values.charge(1);
        const node = module.node(id);
        if (node.tag == .block) return self.summaryBlock(module, inputs, id, arguments, depth);
        if (node.tag != .closure) return .{};
        const metadata = module.closure(id);
        if (metadata.parameter.binding == 0 or inputs.lookup(metadata.parameter.binding) != null) return .{};
        for (module.extra[metadata.captures.start..][0..metadata.captures.len]) |capture| {
            try self.values.charge(1);
            if (inputs.lookup(capture) == null) return .{};
        }
        const entry: Entry = .{ .binding = metadata.parameter.binding, .value = arguments[0] };
        const nested: SummaryInputs = .{ .locals = .{ .entries = &.{entry}, .parent = &inputs } };
        return self.summaryApplied(module, nested, metadata.body, arguments[1..], depth + 1);
    }
    fn summaryValue(self: *Checker, module: *const core.Module, inputs: SummaryInputs, id: core.Id, depth: usize) WorkError!Value {
        if (id == 0 or depth >= 32) return .{};
        const node = module.node(id);
        if (node.tag == .call) return self.summaryInvocation(module, inputs, id, depth);
        if (node.tag == .block) return self.summaryBlock(module, inputs, id, &.{}, depth);
        if (node.tag == .if_value and module.types.node(node.ty).tag != .boolean) {
            try self.values.charge(1);
            const left = try self.summaryValue(module, inputs, node.b, depth + 1);
            const right = try self.summaryValue(module, inputs, node.c, depth + 1);
            return join(left, right, false);
        }
        return .{
            .operand = try self.summaryOperand(module, inputs, id, depth),
            .condition = try self.summaryCondition(module, inputs, id, depth),
        };
    }
    fn summaryInvocation(self: *Checker, module: *const core.Module, inputs: SummaryInputs, id: core.Id, depth: usize) WorkError!Value {
        const invocation = module.call(id);
        try self.values.charge(invocation.arguments.len + 1);
        const actual = try self.allocator.alloc(Value, invocation.arguments.len);
        defer self.allocator.free(actual);
        for (invocation.arguments, actual) |argument, *value| value.* = try self.summaryValue(module, inputs, argument, depth + 1);
        var target_ = invocation.target;
        if (target_.unit == 0) target_.unit = module.unit;
        return self.summaryCall(target_, actual, depth + 1);
    }
    fn summaryBlock(self: *Checker, module: *const core.Module, inputs: SummaryInputs, id: core.Id, arguments: []const Value, depth: usize) WorkError!Value {
        if (depth >= 32) return .{};
        var locals: std.ArrayList(Entry) = .empty;
        defer locals.deinit(self.allocator);
        for (module.children(id)) |child| {
            try self.values.charge(1);
            const node = module.node(child);
            const scope: SummaryInputs = .{ .locals = .{ .entries = locals.items, .parent = &inputs } };
            switch (node.tag) {
                .bind => {
                    const value = try self.summaryValue(module, scope, node.b, depth + 1);
                    // Unknown computations and control flow do not confer
                    // authority. Exact aliases retain their caller's versions.
                    if (value.operand == 0 and value.condition == 0) return .{};
                    if (scope.lookup(node.a) != null) return .{};
                    if (locals.items.len >= self.values.limits.terms) return error.ProofAnalysisLimit;
                    try locals.append(self.allocator, .{ .binding = node.a, .value = value });
                },
                .pattern_bind => {
                    if (node.c != 0) return .{};
                    const binding = opaqueReferenceBinding(module, node.a) orelse return .{};
                    const value = try self.summaryValue(module, scope, node.b, depth + 1);
                    if (value.operand == 0 or value.proof != null or value.condition != 0 or scope.lookup(binding) != null) return .{};
                    if (locals.items.len >= self.values.limits.terms) return error.ProofAnalysisLimit;
                    try locals.append(self.allocator, .{ .binding = binding, .value = value });
                },
                .return_ => {
                    if (node.b != id) return .{};
                    return self.summaryApplied(module, scope, node.a, arguments, depth + 1);
                },
                else => return .{},
            }
        }
        return .{};
    }
    fn summaryCondition(self: *Checker, module: *const core.Module, inputs: SummaryInputs, id: core.Id, depth: usize) WorkError!u32 {
        if (id == 0 or depth >= 32) return 0;
        try self.values.charge(1);
        const node = module.node(id);
        if (node.tag == .reference) {
            const reference = module.reference(id);
            if (reference.unit != 0 and reference.unit != module.unit) return 0;
            if (inputs.lookup(reference.binding)) |value| return value.condition;
        }
        if (node.tag == .force) return self.summaryCondition(module, inputs, node.a, depth + 1);
        if (node.tag == .call) return (try self.summaryInvocation(module, inputs, id, depth)).condition;
        if (node.tag == .scalar and node.c == 0 and module.types.node(node.ty).tag == .boolean) {
            const left = try self.summaryOperand(module, inputs, node.a, depth + 1);
            const right = try self.summaryOperand(module, inputs, node.b, depth + 1);
            return self.comparison(node.op, left, right);
        }
        if (node.tag == .logical and (node.op == .and_ or node.op == .or_)) {
            const left = try self.summaryCondition(module, inputs, node.a, depth + 1);
            const right = try self.summaryCondition(module, inputs, node.b, depth + 1);
            if (left == 0 and right == 0) return 0;
            return self.condition(.{ .op = node.op, .left = left, .right = right });
        }
        if (node.tag == .if_value and module.types.node(node.ty).tag == .boolean) {
            var condition_ = try self.summaryCondition(module, inputs, node.a, depth + 1);
            const then_node = module.node(node.b);
            const else_node = module.node(node.c);
            if (then_node.tag == .constant and else_node.tag == .constant and module.types.node(then_node.ty).tag == .boolean and module.types.node(else_node.ty).tag == .boolean) {
                if (then_node.a == else_node.a) return 0;
                if (then_node.a != 0) return condition_;
                return self.condition(.{ .negated = true, .left = condition_ });
            }
            for ([_]core.Id{ node.c, node.b }, 0..) |branch, index| {
                const fixed = module.node(branch);
                if (fixed.tag != .constant or module.types.node(fixed.ty).tag != .boolean) continue;
                var other = node.b;
                if (index == 1) {
                    other = node.c;
                    condition_ = try self.condition(.{ .negated = true, .left = condition_ });
                }
                const right = try self.summaryCondition(module, inputs, other, depth + 1);
                var op: core.Op = .and_;
                if (fixed.a != 0) {
                    op = .or_;
                    condition_ = try self.condition(.{ .negated = true, .left = condition_ });
                }
                return self.condition(.{ .op = op, .left = condition_, .right = right });
            }
        }
        if (node.tag == .block) return (try self.summaryBlock(module, inputs, id, &.{}, depth)).condition;
        if (node.tag == .suite and module.children(id).len == 1) return self.summaryCondition(module, inputs, module.children(id)[0], depth + 1);
        if (node.tag == .return_) return self.summaryCondition(module, inputs, node.a, depth + 1);
        return 0;
    }
    fn call(self: *Checker, id: core.Id, raw: core.BindingRef, callee_type: T.Id, arguments: []const core.Id, depth: usize) WorkError!Value {
        const selected = try self.target(raw);
        const header = contract(selected.module, selected.binding);
        const actual = try self.allocator.alloc(Value, arguments.len);
        defer self.allocator.free(actual);
        for (arguments, actual) |argument, *value| value.* = try self.walk(argument, depth + 1);
        if (header) |signature| {
            try signatureTypes(&self.module.types, callee_type, signature.*);
            try require(arguments.len <= signature.arity);
            const substituted = try self.allocator.alloc(terms.Id, arguments.len);
            defer self.allocator.free(substituted);
            @memset(substituted, 0);
            for (actual, 0..) |value, slot| {
                if (std.mem.findScalar(u32, signature.proof_slots, @intCast(slot)) != null) {
                    try require(value.proof != null);
                    const expected = try signature.signature().instantiateRequirement(self.allocator, &self.values, @intCast(slot), substituted[0..slot]);
                    try self.proof(value.proof, expected);
                } else {
                    try ordinary(value);
                    if (std.mem.findScalar(u32, signature.value_slots, @intCast(slot)) != null) {
                        try require(value.operand != 0);
                        substituted[slot] = value.operand;
                    }
                }
            }
            if (self.module.types.node(self.module.typeOf(id)).tag == .erased_proof) {
                try require(signature.result != null and arguments.len == signature.arity);
                const propositions = try signature.signature().instantiate(self.allocator, &self.values, substituted);
                defer self.allocator.free(propositions);
                try self.fact(.{ .order = propositions[propositions.len - 1] });
                return .{ .proof = propositions[propositions.len - 1] };
            }
        } else {
            for (actual) |value| try ordinary(value);
            try require(self.module.types.node(self.module.typeOf(id)).tag != .erased_proof);
        }
        if (self.plan != null) {
            const tag = self.module.types.node(self.module.typeOf(id)).tag;
            if (tag == .boolean or kind(tag) != null or opaqueReferenceResult(selected.module, selected.binding, arguments.len)) {
                const value = try self.summaryCall(raw, actual, 0);
                if (value.operand != 0 or value.condition != 0) return value;
            }
        }
        return self.version(self.module.typeOf(id), 0);
    }
    fn branches(self: *Checker, id: core.Id, condition_: u32, left_id: core.Id, right_id: core.Id, depth: usize) WorkError!Value {
        const start = self.environment.items.len;
        const facts = self.facts.items.len;
        try self.assume(condition_, true, 0);
        const left = try self.walk(left_id, depth + 1);
        const left_facts = try self.allocator.dupe(Fact, self.facts.items[facts..]);
        defer self.allocator.free(left_facts);
        self.facts.shrinkRetainingCapacity(facts);
        const left_bindings = try self.allocator.dupe(Entry, self.environment.items[start..]);
        defer self.allocator.free(left_bindings);
        self.environment.shrinkRetainingCapacity(start);
        try self.assume(condition_, false, 0);
        const right = try self.walk(right_id, depth + 1);
        const right_facts = try self.allocator.dupe(Fact, self.facts.items[facts..]);
        defer self.allocator.free(right_facts);
        self.facts.shrinkRetainingCapacity(facts);
        const right_bindings = try self.allocator.dupe(Entry, self.environment.items[start..]);
        defer self.allocator.free(right_bindings);
        self.environment.shrinkRetainingCapacity(start);
        if (left.exits) {
            if (!right.exits) for (right_facts) |item| try self.fact(item);
        } else if (right.exits) {
            for (left_facts) |item| try self.fact(item);
        } else {
            for (left_facts) |item| for (right_facts) |other| if (std.meta.eql(item, other)) {
                try self.fact(item);
                break;
            };
        }
        for (self.module.branchMerges(id)) |merge| {
            var then_value = self.lookup(merge.then_binding);
            var else_value = self.lookup(merge.else_binding);
            for (left_bindings) |entry| if (entry.binding == merge.then_binding) {
                then_value = entry.value;
            };
            for (right_bindings) |entry| if (entry.binding == merge.else_binding) {
                else_value = entry.value;
            };
            const proof_binding = self.module.types.node(self.module.bindings[merge.result].ty).tag == .erased_proof;
            var value = try join(then_value orelse .{}, else_value orelse .{}, proof_binding);
            if (value.operand == 0 and value.proof == null) value = try self.version(self.module.bindings[merge.result].ty, merge.result);
            try self.bind(merge.result, value);
        }
        const proof_result = self.module.types.node(self.module.typeOf(id)).tag == .erased_proof;
        var value = try join(left, right, proof_result);
        if (value.operand == 0 and value.proof == null) value = try self.version(self.module.typeOf(id), 0);
        return value;
    }
    fn closure(self: *Checker, id: core.Id, depth: usize) WorkError!Value {
        const metadata = self.module.closures[self.module.node(id).a];
        for (self.module.extra[metadata.captures.start..][0..metadata.captures.len]) |binding| {
            try require(self.module.types.node(self.module.bindings[binding].ty).tag != .erased_proof);
            if (self.lookup(binding)) |value| try ordinary(value);
        }
        const previous = self.environment;
        const previous_returns = self.returns;
        const previous_facts = self.facts;
        const previous_loop = self.loop;
        self.loop = null;
        self.environment = .empty;
        self.returns = .empty;
        self.facts = .empty;
        defer {
            self.environment.deinit(self.allocator);
            self.environment = previous;
            self.returns.deinit(self.allocator);
            self.returns = previous_returns;
            self.facts.deinit(self.allocator);
            self.facts = previous_facts;
            self.loop = previous_loop;
        }
        for (self.module.extra[metadata.captures.start..][0..metadata.captures.len]) |binding| {
            var value: ?Value = null;
            for (previous.items) |entry| if (entry.binding == binding) {
                value = entry.value;
            };
            try self.bind(binding, value orelse try self.version(self.module.bindings[binding].ty, binding));
        }
        try require(self.module.types.node(metadata.parameter.ty).tag != .erased_proof);
        try self.bind(metadata.parameter.binding, try self.version(metadata.parameter.ty, metadata.parameter.binding));
        try ordinary(try self.walk(metadata.body, depth + 1));
        try require(self.returns.items.len == 0);
        return .{};
    }
    fn pattern(self: *Checker, id: core.PatternId, depth: usize) WorkError!void {
        if (id == 0) return;
        if (depth >= 128) return error.ProofAnalysisLimit;
        try self.values.charge(1);
        const value = self.module.pattern(id);
        switch (value.tag) {
            .bind => try self.bind(value.a, try self.version(self.module.bindings[value.a].ty, value.a)),
            .product => for (self.module.patternChildren(id)) |child| try self.pattern(child, depth + 1),
            .constructor, .record_payload => if (value.b != 0) try self.pattern(value.b, depth + 1),
            .value => try ordinary(try self.walk(value.a, depth + 1)),
            else => {},
        }
    }
    fn walk(self: *Checker, id: core.Id, depth: usize) WorkError!Value {
        if (id == 0) return .{};
        if (depth >= 128) return error.ProofAnalysisLimit;
        try self.values.charge(1);
        const module = self.module;
        const n = module.node(id);
        switch (n.tag) {
            .task => {
                for (module.children(id)) |child| try ordinary(try self.walk(child, depth + 1));
                return .{};
            },
            .staging => return .{},
            .constant => if (module.types.node(n.ty).tag == .u32) return .{ .operand = try self.values.intern(self.allocator, .{ .tag = .literal, .a = n.a }) },
            .reference => {
                const reference = module.reference(id);
                if (reference.unit == 0 or reference.unit == module.unit) {
                    if (self.lookup(reference.binding)) |value| return value;
                    try require(module.types.node(n.ty).tag != .erased_proof);
                    const binding = module.bindings[reference.binding];
                    try require(binding.kind == .global or binding.kind == .external);
                    return self.version(n.ty, reference.binding);
                }
            },
            .proof_guard => {
                const left = try self.walk(n.a, depth + 1);
                const right = try self.walk(n.b, depth + 1);
                try ordinary(left);
                try ordinary(right);
                try require(left.operand != 0 and right.operand != 0);
                const relation = std.enums.fromInt(terms.Relation, n.c) orelse return error.InvalidArtifact;
                const proposition: terms.Proposition = .{ .relation = relation, .left = left.operand, .right = right.operand };
                try self.values.view().proposition(proposition);
                if (self.plan) |plan| try plan.record(self.allocator, id, try self.query(proposition));
                try self.fact(.{ .order = proposition });
                return .{ .proof = proposition };
            },
            .bind => {
                const value = try self.walk(n.b, depth + 1);
                try require((module.types.node(module.bindings[n.a].ty).tag == .erased_proof) == (value.proof != null));
                try self.bind(n.a, value);
                return .{};
            },
            .call => {
                const invocation = module.call(id);
                return self.call(id, invocation.target, invocation.callee_type, invocation.arguments, depth);
            },
            .apply => {
                var arguments: std.ArrayList(core.Id) = .empty;
                defer arguments.deinit(self.allocator);
                var leaf = id;
                while (module.node(leaf).tag == .apply) {
                    try self.values.charge(1);
                    try arguments.append(self.allocator, module.node(leaf).b);
                    leaf = module.node(leaf).a;
                }
                std.mem.reverse(core.Id, arguments.items);
                if (module.node(leaf).tag == .reference) return self.call(id, module.reference(leaf), module.typeOf(leaf), arguments.items, depth);
                if (module.node(leaf).tag == .associated) {
                    const method = module.node(leaf);
                    try self.values.charge(arguments.items.len + 2);
                    const actual = try self.allocator.alloc(Value, arguments.items.len + 2);
                    defer self.allocator.free(actual);
                    actual[0] = try self.walk(method.a, depth + 1);
                    actual[1] = try self.walk(method.b, depth + 1);
                    for (arguments.items, actual[2..]) |argument, *value| value.* = try self.walk(argument, depth + 1);
                    for (actual) |value| try ordinary(value);
                    for (self.selected) |selected| {
                        try self.values.charge(1);
                        if (selected.node == leaf) return self.summaryCall(selected.target, actual, 0);
                    }
                    return .{};
                }
                try ordinary(try self.walk(n.a, depth + 1));
                try ordinary(try self.walk(n.b, depth + 1));
            },
            .block, .suite => {
                const bindings = self.environment.items.len;
                const returns = self.returns.items.len;
                defer if (n.tag == .block) self.environment.shrinkRetainingCapacity(bindings);
                var exits = false;
                for (module.children(id)) |child| {
                    const value = try self.walk(child, depth + 1);
                    if (value.exits) {
                        exits = true;
                        break;
                    }
                }
                if (n.tag == .block) {
                    var result: ?Value = null;
                    const proof_result = module.types.node(n.ty).tag == .erased_proof;
                    for (self.returns.items[returns..]) |returned| if (returned.target == id) {
                        if (result) |prior| result = try join(prior, returned.value, proof_result) else result = returned.value;
                    } else return error.InvalidArtifact;
                    self.returns.shrinkRetainingCapacity(returns);
                    if (proof_result) try require(result != null and result.?.proof != null);
                    return result orelse try self.version(n.ty, 0);
                }
                return .{ .exits = exits or module.types.node(n.ty).tag == .never };
            },
            .return_ => {
                const value = try self.walk(n.a, depth + 1);
                if (self.returns.items.len >= self.values.limits.terms) return error.ProofAnalysisLimit;
                try self.returns.append(self.allocator, .{ .target = n.b, .value = value });
                return .{ .exits = true };
            },
            .if_value, .if_stmt => {
                const condition_value = try self.walk(n.a, depth + 1);
                try ordinary(condition_value);
                return self.branches(id, condition_value.condition, n.b, n.c, depth);
            },
            .closure => return self.closure(id, depth),
            .suspend_ => {
                _ = try self.closure(id, depth);
                const shape = module.types.node(n.ty);
                if (self.plan != null and shape.tag == .demand and module.types.node(shape.a).tag == .boolean) return .{ .condition = try self.summaryCondition(module, .{ .captures = self.environment.items }, module.suspension(id).body, 0) };
                return .{};
            },
            .loop => {
                const metadata = module.loopInfo(id);
                const first = try self.walk(metadata.first, depth + 1);
                const end = try self.walk(metadata.end, depth + 1);
                try ordinary(first);
                try ordinary(end);
                const bindings = self.environment.items.len;
                const facts = self.facts.items.len;
                for (module.loopCarries(id)) |carry| {
                    try require(module.types.node(module.bindings[carry.iteration].ty).tag != .erased_proof);
                    try self.bind(carry.iteration, try self.version(module.bindings[carry.iteration].ty, carry.iteration));
                }
                try self.pattern(metadata.pattern, depth + 1);
                if (metadata.kind == .range and metadata.pattern != 0 and module.pattern(metadata.pattern).tag == .bind) {
                    const index = self.lookup(module.pattern(metadata.pattern).a) orelse return error.InvalidArtifact;
                    if (first.operand != 0 and end.operand != 0 and index.operand != 0) {
                        try self.fact(.{ .order = .{ .relation = .le, .left = first.operand, .right = index.operand } });
                        try self.fact(.{ .order = .{ .relation = .lt, .left = index.operand, .right = end.operand } });
                    }
                }
                var loop: Loop = .{ .source = id, .previous = self.loop };
                self.loop = &loop;
                defer self.loop = loop.previous;
                _ = try self.walk(metadata.body, depth + 1);
                self.facts.shrinkRetainingCapacity(facts);
                self.environment.shrinkRetainingCapacity(bindings);
                for (module.loopCarries(id)) |carry| try self.bind(carry.outgoing, try self.version(module.bindings[carry.outgoing].ty, carry.outgoing));
                return .{ .exits = metadata.kind == .forever and !metadata.can_exit and !loop.breaks };
            },
            .match => {
                try self.operands(module.matchInputs(id), depth);
                const start = self.environment.items.len;
                const facts = self.facts.items.len;
                var result: ?Value = null;
                const proof_result = module.types.node(n.ty).tag == .erased_proof;
                for (module.matchArms(id)) |arm| {
                    for (module.armRows(arm)) |row| for (module.rowPatterns(row)) |pattern_| try self.pattern(pattern_, depth + 1);
                    const condition_value = try self.walk(arm.guard, depth + 1);
                    try ordinary(condition_value);
                    try self.assume(condition_value.condition, true, 0);
                    const value = try self.walk(arm.body, depth + 1);
                    if (result) |prior| result = try join(prior, value, proof_result) else result = value;
                    self.environment.shrinkRetainingCapacity(start);
                    self.facts.shrinkRetainingCapacity(facts);
                }
                if (proof_result) try require(result != null and result.?.proof != null);
                return result orelse try self.version(n.ty, 0);
            },
            .pattern_bind => {
                const subject = try self.walk(n.b, depth + 1);
                try ordinary(subject);
                if (n.c != 0) {
                    const facts = self.facts.items.len;
                    const bindings = self.environment.items.len;
                    const fallback = try self.walk(n.c, depth + 1);
                    self.facts.shrinkRetainingCapacity(facts);
                    self.environment.shrinkRetainingCapacity(bindings);
                    try require(fallback.exits);
                }
                if (n.c == 0) if (opaqueReferenceBinding(module, n.a)) |binding| {
                    try self.bind(binding, subject);
                    return .{};
                };
                try self.pattern(n.a, depth + 1);
            },
            .array_op => {
                const arguments = module.children(id);
                if (module.arrayOperation(id) == .length and arguments.len == 1) {
                    const collection = try self.walk(arguments[0], depth + 1);
                    try ordinary(collection);
                    try require(collection.operand != 0);
                    return .{ .operand = try self.length(collection) };
                }
                if (self.plan != null and (module.arrayOperation(id) == .get or module.arrayOperation(id) == .set)) {
                    const collection = try self.walk(arguments[0], depth + 1);
                    const index = try self.walk(arguments[1], depth + 1);
                    try ordinary(collection);
                    try ordinary(index);
                    if (arguments.len > 2) try self.operands(arguments[2..], depth);
                    var admitted = false;
                    if (collection.operand != 0 and index.operand != 0) admitted = try self.query(.{ .relation = .index, .left = collection.operand, .right = index.operand });
                    try self.plan.?.record(self.allocator, id, admitted);
                    if (module.arrayOperation(id) == .set) return self.preserveLength(id, collection);
                    return self.version(n.ty, 0);
                }
                if (self.plan != null and (module.arrayOperation(id) == .identity or module.arrayOperation(id) == .convert)) {
                    const collection = try self.walk(arguments[0], depth + 1);
                    try ordinary(collection);
                    if (module.arrayOperation(id) == .identity and kind(module.types.node(n.ty).tag) == kind(module.types.node(module.typeOf(arguments[0])).tag)) return collection;
                    return self.preserveLength(id, collection);
                }
                if (self.plan != null and (module.arrayOperation(id) == .fill or module.arrayOperation(id) == .generate)) {
                    const count = try self.walk(arguments[0], depth + 1);
                    try ordinary(count);
                    try self.operands(arguments[1..], depth);
                    const result = try self.version(n.ty, 0);
                    if (result.operand != 0 and count.operand != 0) try self.fact(.{ .order = .{ .relation = .eq, .left = try self.length(result), .right = count.operand } });
                    return result;
                }
                try self.operands(arguments, depth);
            },
            .array => {
                const children = module.children(id);
                try self.operands(children, depth);
                const result = try self.version(n.ty, 0);
                if (self.plan != null and result.operand != 0) {
                    const count = try self.values.intern(self.allocator, .{ .tag = .literal, .a = @intCast(children.len) });
                    try self.fact(.{ .order = .{ .relation = .eq, .left = try self.length(result), .right = count } });
                }
                return result;
            },
            .break_ => {
                try self.operands(module.children(id), depth);
                var loop_target = self.loop;
                while (loop_target) |loop| : (loop_target = loop.previous) {
                    if (loop.source != n.a) continue;
                    loop.breaks = true;
                    return .{ .exits = true };
                }
                return error.InvalidArtifact;
            },
            .product, .record, .contract_method => try self.operands(module.children(id), depth),
            .scalar => {
                const left = try self.walk(n.a, depth + 1);
                const right = try self.walk(n.b, depth + 1);
                try ordinary(left);
                try ordinary(right);
                if (n.c == 0 and left.operand != 0 and right.operand != 0 and module.types.node(module.typeOf(n.a)).tag == .u32 and module.types.node(module.typeOf(n.b)).tag == .u32) {
                    const comparison_ = try self.comparison(n.op, left.operand, right.operand);
                    if (comparison_ != 0) return .{ .condition = comparison_ };
                    if (self.plan != null and module.types.node(n.ty).tag == .u32) return self.arithmetic(id, n.op, left, right);
                }
            },
            .logical => {
                const left = try self.walk(n.a, depth + 1);
                try ordinary(left);
                const facts = self.facts.items.len;
                try self.assume(left.condition, n.op == .and_, 0);
                const right = try self.walk(n.b, depth + 1);
                try ordinary(right);
                self.facts.shrinkRetainingCapacity(facts);
                return .{ .condition = try self.condition(.{ .op = n.op, .left = left.condition, .right = right.condition }) };
            },
            .associated => {
                const left = try self.walk(n.a, depth + 1);
                const right = try self.walk(n.b, depth + 1);
                try ordinary(left);
                try ordinary(right);
                for (self.selected) |selected| {
                    try self.values.charge(1);
                    if (selected.node == id) return self.summaryCall(selected.target, &.{ left, right }, 0);
                }
            },
            .record_merge, .type_same, .effect_provider, .handle => {
                try ordinary(try self.walk(n.a, depth + 1));
                try ordinary(try self.walk(n.b, depth + 1));
            },
            .construct => if (n.b != 0) {
                const payload = try self.walk(n.b, depth + 1);
                try ordinary(payload);
                if (opaqueReferenceConstructor(module, n.a)) return payload;
            },
            .resource_release, .usage_share, .usage_read, .package_pack => try ordinary(try self.walk(n.a, depth + 1)),
            .resource_scope => {
                try ordinary(try self.walk(n.a, depth + 1));
                try ordinary(try self.walk(n.b, depth + 1));
                try ordinary(try self.walk(n.c, depth + 1));
            },
            .resource_acquire, .usage_borrow => {
                try ordinary(try self.walk(n.a, depth + 1));
                try ordinary(try self.walk(n.b, depth + 1));
            },
            .package_unpack => {
                try ordinary(try self.walk(n.a, depth + 1));
                const frontier = self.environment.items.len;
                defer self.environment.shrinkRetainingCapacity(frontier);
                try self.bind(n.b, .{});
                return self.walk(module.packageOpening(id).body, depth + 1);
            },
            .project, .result_associated, .force, .computation, .effect_scope => try ordinary(try self.walk(n.a, depth + 1)),
            .state_provider => {
                try ordinary(try self.walk(n.a, depth + 1));
                try ordinary(try self.walk(n.b, depth + 1));
                try ordinary(try self.walk(n.c, depth + 1));
            },
            .update => {
                const metadata = module.updateInfo(id);
                const root = try self.walk(metadata.root, depth + 1);
                try ordinary(root);
                if (metadata.self_binding != 0) try self.bind(metadata.self_binding, root);
                for (module.updateSelectors(id)) |step| try ordinary(try self.walk(step.index, depth + 1));
                try ordinary(try self.walk(metadata.value, depth + 1));
                if (self.plan != null and kind(module.types.node(n.ty).tag) != null) return self.preserveLength(id, root);
            },
            .resolver_op => {
                try ordinary(try self.walk(module.resolverInfo(id).resolver, depth + 1));
                try self.operands(module.resolverArguments(id), depth);
            },
            .operation_value => {
                const metadata = module.operationValue(id);
                try ordinary(try self.walk(metadata.capability, depth + 1));
                try ordinary(try self.walk(metadata.witness, depth + 1));
            },
            .request_loop => {
                const metadata = module.requestLoopInfo(id);
                try ordinary(try self.walk(metadata.computation, depth + 1));
                for (module.requestArms(id)) |arm| {
                    try ordinary(try self.walk(arm.selector, depth + 1));
                    try ordinary(try self.walk(arm.callback, depth + 1));
                }
                const start = self.environment.items.len;
                defer self.environment.shrinkRetainingCapacity(start);
                for (module.requestCompletionBindings(id)) |binding| {
                    try require(module.types.node(module.bindings[binding].ty).tag != .erased_proof);
                    try self.bind(binding, try self.version(module.bindings[binding].ty, binding));
                }
                try self.pattern(metadata.completion_pattern, depth + 1);
                try ordinary(try self.walk(metadata.completion_body, depth + 1));
            },
            .request_decision => {
                try ordinary(try self.walk(n.b, depth + 1));
                try ordinary(try self.walk(n.c, depth + 1));
            },
            .invalid => return error.InvalidArtifact,
            .panic => return .{ .exits = true },
            .constructor_function, .primitive_function, .type_constructor, .effect_reflection => {},
        }
        try require(module.types.node(n.ty).tag != .erased_proof);
        return self.version(n.ty, 0);
    }
    fn body(self: *Checker, body_: *const core.Body) WorkError!void {
        const signature = contract(self.module, body_.binding);
        const parameters = self.module.bodyParameters(body_);
        if (signature) |header| {
            try require(body_.is_function and parameters.len == header.arity);
            try signatureTypes(&self.module.types, self.module.bindings[body_.binding].ty, header.*);
            try header.signature().validate(self.allocator, self.values.limits);
        }
        const arguments = try self.allocator.alloc(terms.Id, parameters.len);
        defer self.allocator.free(arguments);
        @memset(arguments, 0);
        for (parameters, 0..) |parameter, slot| {
            var value = try self.version(parameter.ty, parameter.binding);
            if (self.module.types.node(parameter.ty).tag == .erased_proof) {
                const header = signature orelse return error.InvalidArtifact;
                value.proof = try header.signature().instantiateRequirement(self.allocator, &self.values, @intCast(slot), arguments[0..slot]);
                try self.fact(.{ .order = value.proof.? });
            }
            arguments[slot] = value.operand;
            try self.bind(parameter.binding, value);
        }
        const result = try self.walk(body_.root, 0);
        try require(self.returns.items.len == 0);
        if (result.exits) return;
        if (signature) |header| if (header.result != null) {
            const expected = try header.signature().instantiate(self.allocator, &self.values, arguments);
            defer self.allocator.free(expected);
            try self.proof(result.proof, expected[expected.len - 1]);
            return;
        };
        try ordinary(result);
    }
};

/// Optional reasoning recomputes from executable bodies. Failure to establish
/// an ordinary body's bounded graph retains every check in this module.
pub fn analyze(allocator: A, module: *const core.Module, units: []const *const core.Module, limits: terms.Limits) A.Error!Plan {
    var plan: Plan = .{};
    errdefer plan.deinit(allocator);
    var candidate = module.has_numeric_proofs;
    if (!candidate) for (module.nodes, 0..) |node, id| {
        if (node.tag == .array_op and (module.arrayOperation(@intCast(id)) == .get or module.arrayOperation(@intCast(id)) == .set)) {
            candidate = true;
            break;
        }
    };
    if (!candidate) return plan;
    var remaining: usize = 1_000_000;
    for (module.bodies[1..]) |*body_| {
        var checker: Checker = .{ .allocator = allocator, .module = module, .units = units, .plan = &plan };
        defer checker.deinit();
        checker.values.limits = limits;
        checker.values.limits.visits = @min(remaining, limits.visits);
        checker.body(body_) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            plan.checks.clearRetainingCapacity();
            plan.visits += checker.values.visits;
            return plan;
        };
        plan.visits += checker.values.visits;
        remaining -= @min(remaining, checker.values.visits);
    }
    return plan;
}

/// Prepared selected methods are scoped to this exact source body. Untracked
/// numeric operands and selected calls nested in helper bodies decline. The
/// containing executable owner keeps this plan beside its physical mappings.
pub fn analyzePrepared(allocator: A, module: *const core.Module, units: []const *const core.Module, body_: *const core.Body, selected: []const Selected, limits: terms.Limits) A.Error!Plan {
    var plan: Plan = .{};
    errdefer plan.deinit(allocator);
    if (selected.len > limits.terms or body_.binding == 0 or body_.binding >= module.bindings.len) return plan;
    const owned = module.body(body_.binding) orelse return plan;
    if (owned != body_ or owned.binding != body_.binding) return plan;
    var checker: Checker = .{ .allocator = allocator, .module = module, .units = units, .plan = &plan, .selected = selected };
    defer checker.deinit();
    checker.values.limits = limits;
    checker.body(body_) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        plan.checks.clearRetainingCapacity();
    };
    plan.visits = checker.values.visits;
    return plan;
}

pub fn validate(allocator: A, module: *const core.Module, units: []const *const core.Module, remaining: *usize) Error!void {
    if (!module.has_numeric_proofs) return;
    try dataTypes(&module.types, module.types.nodes);
    var metadata: Checker = .{ .allocator = allocator, .module = module, .units = units };
    defer metadata.deinit();
    metadata.values.limits.visits = @min(remaining.*, metadata.values.limits.visits);
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(allocator);
    for (module.proof_contracts) |value| {
        const slot = try seen.getOrPut(allocator, value.binding);
        try require(!slot.found_existing);
        try signatureTypes(&module.types, module.bindings[value.binding].ty, value.header);
        value.header.signature().validateInto(allocator, &metadata.values) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.InvalidArtifact;
        };
        if (module.bindings[value.binding].kind == .external) {
            const selected = try metadata.target(.{ .binding = value.binding });
            const producer = contract(selected.module, selected.binding) orelse return error.InvalidArtifact;
            try require(headers.equal(value.header, producer.*));
        } else try require(module.body(value.binding) != null);
    }
    remaining.* -= @min(remaining.*, metadata.values.visits);
    for (module.bodies[1..]) |*body| {
        var checker: Checker = .{ .allocator = allocator, .module = module, .units = units };
        defer checker.deinit();
        checker.values.limits.visits = @min(remaining.*, checker.values.limits.visits);
        checker.body(body) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.InvalidArtifact;
        };
        remaining.* -= @min(remaining.*, checker.values.visits);
    }
}
