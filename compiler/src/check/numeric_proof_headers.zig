//! Header syntax becomes an owned positional contract. Datatype checking
//! supplies resolved operand kinds; source type names grant no value authority.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const terms = @import("numeric_proof_terms.zig");
const contracts = @import("numeric_proof_contracts.zig");
const A = std.mem.Allocator;
pub const Error = contracts.Error || error{InvalidProofKind};
pub const Owned = struct {
    arity: u32,
    value_slots: []const u32 = &.{},
    proof_slots: []const u32 = &.{},
    values: []const terms.Kind = &.{},
    operands: []const terms.Term = &.{},
    requirements: []const contracts.Requirement = &.{},
    result: ?terms.Proposition = null,
    pub fn signature(self: Owned) contracts.Signature {
        return .{ .arity = self.arity, .value_slots = self.value_slots, .proof_slots = self.proof_slots, .contract = .{ .values = self.values, .operands = self.operands, .requirements = self.requirements, .result = self.result } };
    }
    pub fn clone(self: Owned, allocator: A) A.Error!Owned {
        var owned: Owned = .{ .arity = self.arity, .result = self.result };
        errdefer owned.deinit(allocator);
        owned.value_slots = try allocator.dupe(u32, self.value_slots);
        owned.proof_slots = try allocator.dupe(u32, self.proof_slots);
        owned.values = try allocator.dupe(terms.Kind, self.values);
        owned.operands = try allocator.dupe(terms.Term, self.operands);
        owned.requirements = try allocator.dupe(contracts.Requirement, self.requirements);
        return owned;
    }
    pub fn deinit(self: *Owned, allocator: A) void {
        allocator.free(self.value_slots);
        allocator.free(self.proof_slots);
        allocator.free(self.values);
        allocator.free(self.operands);
        allocator.free(self.requirements);
        self.* = undefined;
    }
};
pub const Named = struct { binding: u32, header: Owned };
pub fn find(values: []const Named, binding: u32) ?*const Owned {
    for (values) |*value| if (value.binding == binding) return &value.header;
    return null;
}
pub fn equal(left: Owned, right: Owned) bool {
    return @import("../structural.zig").equal(left, right);
}
const Binding = struct { name: symbols.Symbol, formal: ?u32 };
const Builder = struct {
    allocator: A,
    tree: *const ast.Tree,
    pool: *const symbols.Pool,
    store: terms.Store,
    bindings: std.ArrayList(Binding) = .empty,
    kinds: std.ArrayList(terms.Kind) = .empty,
    value_slots: std.ArrayList(u32) = .empty,
    proof_slots: std.ArrayList(u32) = .empty,
    requirements: std.ArrayList(contracts.Requirement) = .empty,
    fn deinit(self: *Builder) void {
        self.store.deinit(self.allocator);
        self.bindings.deinit(self.allocator);
        self.kinds.deinit(self.allocator);
        self.value_slots.deinit(self.allocator);
        self.proof_slots.deinit(self.allocator);
        self.requirements.deinit(self.allocator);
    }
    fn visit(self: *Builder) Error!void {
        if (self.store.visits >= self.store.limits.visits) return error.ProofAnalysisLimit;
        self.store.visits += 1;
    }
    fn contains(self: *Builder, id: ast.Id, depth: usize) Error!bool {
        if (id == 0) return false;
        if (depth >= 128) return error.ProofAnalysisLimit;
        try self.visit();
        const node = self.tree.node(id);
        switch (node.tag) {
            .type_forall, .type_exists => return self.contains(self.tree.extra.items[node.c], depth + 1),
            .type_usage => return self.contains(node.c, depth + 1),
            .type_name => return terms.typeName(self.pool.get(node.a)) != null,
            .type_apply, .type_effect => return try self.contains(node.a, depth + 1) or try self.contains(node.b, depth + 1),
            .type_function => return try self.contains(node.a, depth + 1) or try self.contains(node.b, depth + 1) or try self.contains(node.c, depth + 1),
            .group, .type_demand => return self.contains(node.a, depth + 1),
            .type_binder, .type_field => return self.contains(node.b, depth + 1),
            .type_array, .type_product, .type_record, .effect_row => {
                for (self.tree.children(id)) |child| if (try self.contains(child, depth + 1)) return true;
            },
            else => {},
        }
        return false;
    }
    fn operand(self: *Builder, id: ast.Id, depth: usize) Error!terms.Id {
        if (depth >= 128) return error.ProofAnalysisLimit;
        try self.visit();
        const node = self.tree.node(id);
        switch (node.tag) {
            .integer => return self.store.intern(self.allocator, .{ .tag = .literal, .a = node.a }),
            .group => return self.operand(node.a, depth + 1),
            .type_name => {
                var i = self.bindings.items.len;
                while (i != 0) {
                    i -= 1;
                    try self.visit();
                    const binding = self.bindings.items[i];
                    if (binding.name != node.a) continue;
                    const formal = binding.formal orelse return error.InvalidProofOperand;
                    return self.store.intern(self.allocator, .{ .tag = .formal, .kind = self.kinds.items[formal], .a = formal });
                }
                return error.ProofScopeEscape;
            },
            .type_apply => {
                const head = self.tree.node(node.a);
                if (head.tag != .type_name) return error.InvalidProofOperand;
                const name = self.pool.get(head.a);
                var kind: terms.Kind = .array;
                if (std.mem.eql(u8, name, "@list.length")) {
                    kind = .list;
                } else if (!std.mem.eql(u8, name, "@array.length")) return error.InvalidProofOperand;
                // Only a preceding collection binder may appear under length.
                if (self.tree.node(node.b).tag != .type_name) return error.InvalidProofOperand;
                const collection = try self.operand(node.b, depth + 1);
                if ((try self.store.view().get(collection)).kind != kind) return error.InvalidProofOperand;
                return self.store.intern(self.allocator, .{ .tag = .length, .a = collection });
            },
            else => return error.InvalidProofOperand,
        }
    }
    fn proposition(self: *Builder, id: ast.Id) Error!?terms.Proposition {
        try self.visit();
        const outer = self.tree.node(id);
        if (outer.tag != .type_apply) return null;
        const inner = self.tree.node(outer.a);
        if (inner.tag != .type_apply) return null;
        const head = self.tree.node(inner.a);
        if (head.tag != .type_name) return null;
        const relation = terms.typeName(self.pool.get(head.a)) orelse return null;
        const result: terms.Proposition = .{ .relation = relation, .left = try self.operand(inner.b, 0), .right = try self.operand(outer.b, 0) };
        try self.store.view().proposition(result);
        return result;
    }
};

/// Resolved kinds correspond to every arrow, including nonnumeric and proof
/// inputs as null. No allocation occurs when the annotation has no proof syntax.
/// This describes only a complete outer function contract, not a checked body.
pub fn contains(allocator: A, tree: *const ast.Tree, pool: *const symbols.Pool, annotation: ast.Id, limits: terms.Limits) Error!bool {
    var builder: Builder = .{ .allocator = allocator, .tree = tree, .pool = pool, .store = .{ .limits = limits } };
    return builder.contains(annotation, 0);
}
pub fn proofRelation(tree: *const ast.Tree, pool: *const symbols.Pool, id: ast.Id) ?terms.Relation {
    const outer = tree.node(id);
    if (outer.tag != .type_apply) return null;
    const inner = tree.node(outer.a);
    if (inner.tag != .type_apply) return null;
    const head = tree.node(inner.a);
    if (head.tag != .type_name) return null;
    return terms.typeName(pool.get(head.a));
}
pub fn lower(allocator: A, tree: *const ast.Tree, pool: *const symbols.Pool, annotation: ast.Id, input_kinds: []const ?terms.Kind, limits: terms.Limits) Error!?Owned {
    var builder: Builder = .{ .allocator = allocator, .tree = tree, .pool = pool, .store = .{ .limits = limits } };
    defer builder.deinit();
    if (!try builder.contains(annotation, 0)) return null;
    var at = annotation;
    while (tree.node(at).tag == .type_forall) {
        try builder.visit();
        at = tree.extra.items[tree.node(at).c];
    }
    var arity: u32 = 0;
    while (tree.node(at).tag == .type_function) {
        if (arity >= input_kinds.len or arity >= limits.terms) return error.ProofScopeEscape;
        try builder.visit();
        const arrow = tree.node(at);
        if (try builder.contains(arrow.c, 0)) return error.InvalidProofKind;
        var input = arrow.a;
        var name: symbols.Symbol = 0;
        if (tree.node(input).tag == .type_binder) {
            name = tree.node(input).a;
            input = tree.node(input).b;
        }
        var formal: ?u32 = null;
        if (try builder.proposition(input)) |proof| {
            if (input_kinds[arity] != null) return error.InvalidProofKind;
            if (builder.requirements.items.len >= 256) return error.ProofAnalysisLimit;
            try builder.requirements.append(allocator, .{ .before = @intCast(builder.kinds.items.len), .proposition = proof });
            try builder.proof_slots.append(allocator, arity);
        } else {
            if (try builder.contains(input, 0)) return error.InvalidProofKind;
            if (input_kinds[arity]) |kind| {
                formal = @intCast(builder.kinds.items.len);
                try builder.kinds.append(allocator, kind);
                try builder.value_slots.append(allocator, arity);
            }
        }
        // A nonnumeric or proof binder shadows the previous name as well.
        if (name != 0) try builder.bindings.append(allocator, .{ .name = name, .formal = formal });
        arity += 1;
        at = arrow.b;
    }
    if (arity != input_kinds.len) return error.ProofScopeEscape;
    const result = try builder.proposition(at);
    if (result == null and try builder.contains(at, 0)) return error.InvalidProofKind;
    const signature: contracts.Signature = .{
        .arity = arity,
        .value_slots = builder.value_slots.items,
        .proof_slots = builder.proof_slots.items,
        .contract = .{ .values = builder.kinds.items, .operands = builder.store.terms.items, .requirements = builder.requirements.items, .result = result },
    };
    var remaining = limits;
    remaining.visits -= builder.store.visits;
    try signature.validate(allocator, remaining);
    const borrowed: Owned = .{ .arity = arity, .result = result, .value_slots = signature.value_slots, .proof_slots = signature.proof_slots, .values = signature.contract.values, .operands = signature.contract.operands, .requirements = signature.contract.requirements };
    return try borrowed.clone(allocator);
}

fn fixture(allocator: A, source: []const u8, kinds: []const ?terms.Kind, limits: terms.Limits) !?Owned {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var lexed = try @import("../parse/lexer.zig").lex(allocator, source);
    defer lexed.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    return lower(allocator, &tree, &pool, tree.valueDecl(tree.roots.items[0]).annotation, kinds, limits);
}

fn positionalContracts(allocator: A) !void {
    // Buffer/Count stand for already resolved aliases. The recipe builder must
    // use their supplied kinds rather than recognizing the source spelling.
    var owned = (try fixture(allocator,
        \\const checked: (values: Buffer a) -> Bool -> (index: Count) -> (@proof.Index values index) -> (index: U32) -> (@proof.U32Le 0 index) -> @proof.U32Le 0 index = ()
    , &.{ .array, null, .u32, null, .u32, null }, .{})).?;
    defer owned.deinit(allocator);
    const signature = owned.signature();
    try std.testing.expectEqual(@as(u32, 6), signature.arity);
    try std.testing.expectEqualSlices(u32, &.{ 0, 2, 4 }, signature.value_slots);
    try std.testing.expectEqualSlices(u32, &.{ 3, 5 }, signature.proof_slots);
    try std.testing.expectEqual(@as(u32, 2), signature.contract.requirements[0].before);
    try std.testing.expectEqual(@as(u32, 3), signature.contract.requirements[1].before);
    try signature.validate(allocator, .{});
    const format = @import("../reuse/dependency_format.zig");
    const digest: format.Digest = @splat(70);
    const key: format.Key = .{ .compiler = digest, .settings = digest, .source = digest, .dependencies = digest };
    const encoded = try format.encode(allocator, key, signature);
    defer allocator.free(encoded);
    var decoded = try format.decode(contracts.Signature, allocator, encoded, key);
    defer format.deinit(allocator, &decoded);
    try decoded.validate(allocator, .{});
    var target: terms.Store = .{};
    defer target.deinit(allocator);
    const left = try target.intern(allocator, .{ .tag = .version, .kind = .array, .a = 7, .b = 1 });
    const right = try target.intern(allocator, .{ .tag = .version, .kind = .array, .a = 7, .b = 2 });
    const first = try target.intern(allocator, .{ .tag = .version, .a = 8, .b = 1 });
    const rebound = try target.intern(allocator, .{ .tag = .version, .a = 8, .b = 2 });
    const proofs = try decoded.instantiate(allocator, &target, &.{ left, 0, first, 0, rebound, 0 });
    defer allocator.free(proofs);
    try std.testing.expectEqualDeep(terms.Proposition{ .relation = .index, .left = left, .right = first }, proofs[0]);
    try std.testing.expectEqual(rebound, proofs[1].right);
    try std.testing.expectEqualDeep(proofs[1], proofs[2]);
    try std.testing.expectEqualDeep(proofs[0], try decoded.instantiateRequirement(allocator, &target, 3, &.{ left, 0, first }));
    try std.testing.expectEqualDeep(proofs[1], try decoded.instantiateRequirement(allocator, &target, 5, &.{ left, 0, first, 0, rebound }));
    const aliases = try decoded.instantiate(allocator, &target, &.{ left, 0, first, 0, rebound, 0 });
    defer allocator.free(aliases);
    try std.testing.expectEqualSlices(terms.Proposition, proofs, aliases);
    const changed = try decoded.instantiate(allocator, &target, &.{ right, 0, first, 0, rebound, 0 });
    defer allocator.free(changed);
    try std.testing.expectEqual(right, changed[0].left);
    try std.testing.expect(changed[0].left != proofs[0].left);
}
test "numeric proof headers own positional contracts and exact call substitution through OOM" {
    try positionalContracts(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, positionalContracts, .{});
}

test "numeric proof headers reject hidden kinds forward names shadowed values and mismatched lengths" {
    const Case = struct { source: []const u8, kinds: []const ?terms.Kind, expected: Error };
    for ([_]Case{
        .{ .source = "const bad: (@proof.U32Lt x 1) -> (x: U32) -> U32 = ()", .kinds = &.{ null, .u32 }, .expected = error.ProofScopeEscape },
        .{ .source = "const bad: (x: U32) -> (x: Bool) -> (@proof.U32Eq x 0) -> U32 = ()", .kinds = &.{ .u32, null, null }, .expected = error.InvalidProofOperand },
        .{ .source = "const bad: (x: U32) -> (x: @proof.U32Eq x 0) -> (@proof.U32Eq x 0) -> U32 = ()", .kinds = &.{ .u32, null, null }, .expected = error.InvalidProofOperand },
        .{ .source = "const bad: (xs: List U32) -> (@proof.U32Le 0 (@array.length xs)) -> U32 = ()", .kinds = &.{ .list, null }, .expected = error.InvalidProofOperand },
        .{ .source = "const bad: (xs: Array U32) -> (@proof.U32Le 0 (@list.length xs)) -> U32 = ()", .kinds = &.{ .array, null }, .expected = error.InvalidProofOperand },
        .{ .source = "const bad: (@proof.U32Lt 0 0) -> U32 = ()", .kinds = &.{null}, .expected = error.ContradictoryProof },
        .{ .source = "const bad: U32 -> (@proof.U32Le local 0) = ()", .kinds = &.{.u32}, .expected = error.ProofScopeEscape },
        .{ .source = "const bad: List (@proof.U32Eq 0 0) -> U32 = ()", .kinds = &.{.list}, .expected = error.InvalidProofKind },
        .{ .source = "const bad: (Bool, @proof.U32Eq 0 0) -> U32 = ()", .kinds = &.{null}, .expected = error.InvalidProofKind },
        .{ .source = "const bad: ~(@proof.U32Eq 0 0) -> U32 = ()", .kinds = &.{null}, .expected = error.InvalidProofKind },
        .{ .source = "const bad: (@proof.U32Eq 0 0) -> U32 = ()", .kinds = &.{.u32}, .expected = error.InvalidProofKind },
    }) |case| try std.testing.expectError(case.expected, fixture(std.testing.allocator, case.source, case.kinds, .{}));
    try std.testing.expectError(error.ProofAnalysisLimit, fixture(std.testing.allocator, "const bounded: (@proof.U32Eq 0 0) -> U32 = ()", &.{null}, .{ .visits = 4 }));
}

test "numeric proof positional imports reject forged slots and missing ordinary arguments" {
    var owned = (try fixture(std.testing.allocator, "const f: (x: U32) -> Bool -> (@proof.U32Eq x x) -> U32 = ()", &.{ .u32, null, null }, .{})).?;
    defer owned.deinit(std.testing.allocator);
    var forged = owned.signature();
    forged.value_slots = &.{2};
    try std.testing.expectError(error.InvalidProofOperand, forged.validate(std.testing.allocator, .{}));
    forged = owned.signature();
    forged.value_slots = &.{1};
    // Moving a slot can be well formed; matching the datatype/callee signature
    // belongs to checked artifact admission, not this recipe validator.
    try forged.validate(std.testing.allocator, .{});
    forged.proof_slots = &.{3};
    try std.testing.expectError(error.ProofScopeEscape, forged.validate(std.testing.allocator, .{}));
    var target: terms.Store = .{};
    defer target.deinit(std.testing.allocator);
    const actual = try target.intern(std.testing.allocator, .{ .tag = .literal, .a = 4 });
    try std.testing.expectError(error.ProofScopeEscape, owned.signature().instantiate(std.testing.allocator, &target, &.{ actual, 0 }));
    try std.testing.expectError(error.InvalidProofOperand, owned.signature().instantiate(std.testing.allocator, &target, &.{ 0, 0, 0 }));
    try std.testing.expectError(error.InvalidProofOperand, owned.signature().instantiate(std.testing.allocator, &target, &.{ actual, actual, 0 }));
    try std.testing.expectError(error.ProofScopeEscape, owned.signature().instantiateRequirement(std.testing.allocator, &target, 2, &.{actual}));
    try std.testing.expectError(error.InvalidProofOperand, owned.signature().instantiateRequirement(std.testing.allocator, &target, 2, &.{ 0, 0 }));
    try std.testing.expectError(error.InvalidProofOperand, owned.signature().instantiateRequirement(std.testing.allocator, &target, 2, &.{ actual, actual }));
    try std.testing.expectError(error.InvalidProofOperand, owned.signature().instantiateRequirement(std.testing.allocator, &target, 1, &.{actual}));
}

test "numeric proof header scanning allocates nothing for ordinary annotations" {
    const source = "const ordinary: (value: Array U32) -> Bool -> List U32 = ()";
    var pool: symbols.Pool = .{};
    defer pool.deinit(std.testing.allocator);
    var lexed = try @import("../parse/lexer.zig").lex(std.testing.allocator, source);
    defer lexed.deinit(std.testing.allocator);
    var tree = try @import("../parse/parser.zig").parse(std.testing.allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(std.testing.allocator);
    var never_allocate = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectEqual(@as(?Owned, null), try lower(never_allocate.allocator(), &tree, &pool, tree.valueDecl(tree.roots.items[0]).annotation, &.{}, .{}));
    try std.testing.expectEqual(@as(usize, 0), never_allocate.allocated_bytes);
}
