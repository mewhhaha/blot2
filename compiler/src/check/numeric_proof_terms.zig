//! Owned value terms for erased numeric contracts. A type, spelling, length or
//! runtime address is never an identity for the value described by a proof.
//! This owner describes propositions; admission of a checked guard is separate.
const std = @import("std");
const A = std.mem.Allocator;
pub const Id = u32;
pub const Kind = enum(u8) { u32, array, list };
pub const Tag = enum(u8) { literal, formal, capture, version, length, complement };
pub const Relation = enum(u8) { eq, lt, le, add_fits, sub_fits, index };
pub const Term = struct { tag: Tag, kind: Kind = .u32, a: u32, b: u32 = 0 };
pub const Proposition = struct { relation: Relation, left: Id, right: Id };
pub const Limits = struct { terms: usize = 4096, visits: usize = 65_536 };
pub const Error = A.Error || error{ InvalidProofOperand, ProofScopeEscape, ProofAnalysisLimit };
pub const Boundary = struct { formals: []const Kind, captures: []const Kind = &.{}, local_versions: bool = false };

pub fn constructor(name: []const u8) ?Relation {
    inline for (.{ "eq", "lt", "le", "add_fits", "sub_fits", "index" }, 0..) |suffix, index|
        if (std.mem.eql(u8, name, "@proof." ++ suffix)) return @fromBackingInt(@intCast(index));
    return null;
}
pub fn typeName(name: []const u8) ?Relation {
    inline for (.{ "U32Eq", "U32Lt", "U32Le", "U32AddFits", "U32SubFits", "Index" }, 0..) |suffix, index|
        if (std.mem.eql(u8, name, "@proof." ++ suffix)) return @fromBackingInt(@intCast(index));
    return null;
}
/// Index's first word is an already evaluated collection length. This helper
/// never grants authority to another collection with the same length.
pub fn holds(relation: Relation, left: u32, right: u32) bool {
    return switch (relation) {
        .eq => left == right,
        .lt => left < right,
        .le => left <= right,
        .add_fits => @as(u64, left) + right <= std.math.maxInt(u32),
        .sub_fits => right <= left,
        .index => right < left,
    };
}

pub const View = struct {
    terms: []const Term,
    pub fn get(self: View, id: Id) Error!Term {
        if (id == 0 or id > self.terms.len) return error.InvalidProofOperand;
        return self.terms[id - 1];
    }
    pub fn proposition(self: View, value: Proposition) Error!void {
        const left = try self.get(value.left);
        const right = try self.get(value.right);
        if (right.kind != .u32) return error.InvalidProofOperand;
        if (value.relation == .index) {
            if (left.kind == .u32) return error.InvalidProofOperand;
        } else if (left.kind != .u32) return error.InvalidProofOperand;
    }
    pub fn validate(self: View, boundary: Boundary, limits: Limits) Error!void {
        if (self.terms.len > limits.terms or self.terms.len > limits.visits) return error.ProofAnalysisLimit;
        for (self.terms, 0..) |term, index| {
            switch (term.tag) {
                .literal => if (term.kind != .u32 or term.b != 0) return error.InvalidProofOperand,
                .formal => {
                    if (term.b != 0 or term.a >= boundary.formals.len) return error.ProofScopeEscape;
                    if (term.kind != boundary.formals[term.a]) return error.InvalidProofOperand;
                },
                .capture => {
                    if (term.b != 0 or term.a >= boundary.captures.len) return error.ProofScopeEscape;
                    if (term.kind != boundary.captures[term.a]) return error.InvalidProofOperand;
                },
                .version => if (!boundary.local_versions or term.a == 0 or term.b == 0) return error.ProofScopeEscape,
                .length => {
                    if (term.kind != .u32 or term.b != 0 or term.a == 0 or term.a > index) return error.InvalidProofOperand;
                    if ((try self.get(term.a)).kind == .u32) return error.InvalidProofOperand;
                },
                .complement => {
                    if (term.kind != .u32 or term.b != 0 or term.a == 0 or term.a > index) return error.InvalidProofOperand;
                    const child = try self.get(term.a);
                    if (child.kind != .u32 or child.tag == .literal or child.tag == .complement) return error.InvalidProofOperand;
                },
            }
        }
    }
};
pub const Owned = struct {
    terms: []const Term,
    pub fn view(self: Owned) View {
        return .{ .terms = self.terms };
    }
    pub fn deinit(self: *Owned, allocator: A) void {
        allocator.free(self.terms);
        self.* = undefined;
    }
};
/// Entries are identities in the destination owner, never source ordinals.
/// Version substitutions are indexed by the source term ordinal; zero misses.
pub const Substitution = struct { formals: []const Id = &.{}, captures: []const Id = &.{}, versions: []const Id = &.{} };
pub const Store = struct {
    terms: std.ArrayList(Term) = .empty,
    index: std.AutoHashMapUnmanaged(Term, Id) = .empty,
    limits: Limits = .{},
    visits: usize = 0,
    /// Optional attribution only; the global admission counter remains visits.
    account: ?*usize = null,
    pub fn deinit(self: *Store, allocator: A) void {
        self.terms.deinit(allocator);
        self.index.deinit(allocator);
    }
    pub fn view(self: *const Store) View {
        return .{ .terms = self.terms.items };
    }
    pub fn charge(self: *Store, amount: usize) Error!void {
        if (amount > self.limits.visits -| self.visits) return error.ProofAnalysisLimit;
        self.visits += amount;
        if (self.account) |account| account.* += amount;
    }
    pub fn intern(self: *Store, allocator: A, term: Term) Error!Id {
        try self.charge(1);
        switch (term.tag) {
            .literal => if (term.kind != .u32 or term.b != 0) return error.InvalidProofOperand,
            .formal, .capture => if (term.b != 0) return error.InvalidProofOperand,
            .version => if (term.a == 0 or term.b == 0) return error.InvalidProofOperand,
            .length => {
                if (term.kind != .u32 or term.b != 0 or (try self.view().get(term.a)).kind == .u32) return error.InvalidProofOperand;
            },
            .complement => {
                if (term.kind != .u32 or term.b != 0) return error.InvalidProofOperand;
                const child = try self.view().get(term.a);
                if (child.kind != .u32) return error.InvalidProofOperand;
                if (child.tag == .literal) return self.intern(allocator, .{ .tag = .literal, .a = std.math.maxInt(u32) - child.a });
                if (child.tag == .complement) return child.a;
            },
        }
        if (self.index.get(term)) |id| return id;
        if (self.terms.items.len >= @min(self.limits.terms, std.math.maxInt(Id))) return error.ProofAnalysisLimit;
        const entry = try self.index.getOrPut(allocator, term);
        std.debug.assert(!entry.found_existing);
        errdefer std.debug.assert(self.index.remove(term));
        try self.terms.append(allocator, term);
        entry.value_ptr.* = @intCast(self.terms.items.len);
        return entry.value_ptr.*;
    }
    pub fn copyOwned(self: *const Store, allocator: A) A.Error!Owned {
        return .{ .terms = try allocator.dupe(Term, self.terms.items) };
    }
    /// Import from a separate immutable owner once per reachable source term.
    /// Repeated DAG children share identities; failure publishes no terms.
    pub fn import(self: *Store, allocator: A, source: View, proof: Proposition, boundary: Boundary, substitution: Substitution) Error!Proposition {
        var result: [1]Proposition = undefined;
        try self.importInto(allocator, source, &.{proof}, &result, boundary, substitution);
        return result[0];
    }
    pub fn importMany(self: *Store, allocator: A, source: View, proofs: []const Proposition, boundary: Boundary, substitution: Substitution) Error![]Proposition {
        const result = try allocator.alloc(Proposition, proofs.len);
        errdefer allocator.free(result);
        try self.importInto(allocator, source, proofs, result, boundary, substitution);
        return result;
    }
    fn importInto(self: *Store, allocator: A, source: View, proofs: []const Proposition, results: []Proposition, boundary: Boundary, substitution: Substitution) Error!void {
        if (source.terms.len != 0 and self.terms.items.len != 0) {
            const begin = @intFromPtr(source.terms.ptr);
            const own_begin = @intFromPtr(self.terms.items.ptr);
            if (begin < own_begin + self.terms.items.len * @sizeOf(Term) and own_begin < begin + source.terms.len * @sizeOf(Term)) return error.InvalidProofOperand;
        }
        try source.validate(boundary, self.limits);
        try self.charge(source.terms.len);
        try self.charge(proofs.len);
        for (proofs) |proof| try source.proposition(proof);
        const initial = self.terms.items.len;
        errdefer while (self.terms.items.len > initial) {
            const removed = self.terms.pop().?;
            std.debug.assert(self.index.remove(removed));
        };
        const map = try allocator.alloc(Id, source.terms.len);
        defer allocator.free(map);
        @memset(map, 0);
        const Context = struct {
            target: *Store,
            source: View,
            map: []Id,
            substitution: Substitution,
            allocator: A,
            fn term(self_: *@This(), id: Id) Error!Id {
                const input = try self_.source.get(id);
                try self_.target.charge(1);
                if (self_.map[id - 1] != 0) return self_.map[id - 1];
                var output: Id = 0;
                switch (input.tag) {
                    .literal => output = try self_.target.intern(self_.allocator, input),
                    .length, .complement => output = try self_.target.intern(self_.allocator, .{ .tag = input.tag, .a = try self_.term(input.a) }),
                    .formal, .capture, .version => {
                        var values = self_.substitution.formals;
                        var position = input.a;
                        if (input.tag == .capture) values = self_.substitution.captures;
                        if (input.tag == .version) {
                            values = self_.substitution.versions;
                            position = id - 1;
                        }
                        if (position >= values.len) return error.ProofScopeEscape;
                        output = values[position];
                        if ((try self_.target.view().get(output)).kind != input.kind) return error.InvalidProofOperand;
                    },
                }
                self_.map[id - 1] = output;
                return output;
            }
        };
        var context: Context = .{ .target = self, .source = source, .map = map, .substitution = substitution, .allocator = allocator };
        for (proofs, results) |proof, *result|
            result.* = .{ .relation = proof.relation, .left = try context.term(proof.left), .right = try context.term(proof.right) };
    }
};

fn ownedTerms(allocator: A) !void {
    var source: Store = .{};
    defer source.deinit(allocator);
    const values = try source.intern(allocator, .{ .tag = .formal, .kind = .array, .a = 0 });
    const index = try source.intern(allocator, .{ .tag = .formal, .a = 1 });
    const length = try source.intern(allocator, .{ .tag = .length, .a = values });
    const complement = try source.intern(allocator, .{ .tag = .complement, .a = index });
    var owned = try source.copyOwned(allocator);
    defer owned.deinit(allocator);
    source.deinit(allocator);
    source = .{};
    const boundary: Boundary = .{ .formals = &.{ .array, .u32 } };
    try owned.view().validate(boundary, .{});
    var target: Store = .{};
    defer target.deinit(allocator);
    const left = try target.intern(allocator, .{ .tag = .version, .kind = .array, .a = 7, .b = 1 });
    const right = try target.intern(allocator, .{ .tag = .version, .kind = .array, .a = 7, .b = 2 });
    const position = try target.intern(allocator, .{ .tag = .literal, .a = 0 });
    const proof: Proposition = .{ .relation = .index, .left = values, .right = index };
    const one = try target.import(allocator, owned.view(), proof, boundary, .{ .formals = &.{ left, position } });
    const alias = try target.import(allocator, owned.view(), proof, boundary, .{ .formals = &.{ left, position } });
    const changed = try target.import(allocator, owned.view(), proof, boundary, .{ .formals = &.{ right, position } });
    try std.testing.expectEqual(one, alias);
    try std.testing.expect(one.left != changed.left);
    const batch = try target.importMany(allocator, owned.view(), &.{ proof, proof }, boundary, .{ .formals = &.{ left, position } });
    defer allocator.free(batch);
    try std.testing.expectEqualSlices(Proposition, &.{ one, one }, batch);
    const comparison = try target.import(allocator, owned.view(), .{ .relation = .lt, .left = index, .right = length }, boundary, .{ .formals = &.{ left, position } });
    try std.testing.expectEqual(left, (try target.view().get(comparison.right)).a);
    const arithmetic = try target.import(allocator, owned.view(), .{ .relation = .le, .left = index, .right = complement }, boundary, .{ .formals = &.{ left, position } });
    try std.testing.expectEqual(std.math.maxInt(u32), (try target.view().get(arithmetic.right)).a);
    const initial = target.terms.items.len;
    const missing = target.import(allocator, owned.view(), proof, boundary, .{ .formals = &.{left} });
    if (missing) |_| return error.ExpectedScopeFailure else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.ProofScopeEscape, err);
    }
    try std.testing.expectEqual(initial, target.terms.items.len);
    const swapped = target.import(allocator, owned.view(), proof, boundary, .{ .formals = &.{ position, left } });
    if (swapped) |_| return error.ExpectedKindFailure else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidProofOperand, err);
    }
    try std.testing.expectEqual(initial, target.terms.items.len);
}
test "numeric proof terms own exact substituted versions and unwind every allocation failure" {
    try ownedTerms(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedTerms, .{});
}
test "numeric proof terms reject forged scopes forward edges kinds and exhausted work" {
    const boundary: Boundary = .{ .formals = &.{.array} };
    try std.testing.expectError(error.InvalidProofOperand, (View{ .terms = &.{.{ .tag = .length, .a = 1 }} }).validate(boundary, .{}));
    try std.testing.expectError(error.InvalidProofOperand, (View{ .terms = &.{ .{ .tag = .formal, .a = 0 }, .{ .tag = .complement, .a = 1 }, .{ .tag = .complement, .a = 2 } } }).validate(.{ .formals = &.{.u32} }, .{}));
    try std.testing.expectError(error.ProofScopeEscape, (View{ .terms = &.{.{ .tag = .formal, .a = 1 }} }).validate(boundary, .{}));
    try std.testing.expectError(error.InvalidProofOperand, (View{ .terms = &.{.{ .tag = .formal, .a = 0 }} }).validate(boundary, .{}));
    try std.testing.expectError(error.ProofScopeEscape, (View{ .terms = &.{.{ .tag = .capture, .a = 0 }} }).validate(boundary, .{}));
    try std.testing.expectError(error.ProofScopeEscape, (View{ .terms = &.{.{ .tag = .version, .a = 1, .b = 1 }} }).validate(boundary, .{}));
    var store: Store = .{ .limits = .{ .terms = 1, .visits = 3 } };
    defer store.deinit(std.testing.allocator);
    const zero = try store.intern(std.testing.allocator, .{ .tag = .literal, .a = 0 });
    try std.testing.expectEqual(zero, try store.intern(std.testing.allocator, .{ .tag = .literal, .a = 0 }));
    try std.testing.expectError(error.ProofAnalysisLimit, store.intern(std.testing.allocator, .{ .tag = .literal, .a = 1 }));
    try std.testing.expectError(error.ProofAnalysisLimit, store.intern(std.testing.allocator, .{ .tag = .literal, .a = 0 }));
    try std.testing.expectEqual(@as(usize, 1), store.terms.items.len);
    try std.testing.expectError(error.InvalidProofOperand, store.import(std.testing.allocator, store.view(), .{ .relation = .eq, .left = zero, .right = zero }, .{ .formals = &.{} }, .{}));
}
test "numeric proof constructors preserve unsigned boundaries and wrapping distinctions" {
    const maximum = std.math.maxInt(u32);
    try std.testing.expect(holds(.eq, maximum, maximum));
    try std.testing.expect(!holds(.lt, maximum, 0));
    try std.testing.expect(holds(.le, maximum, maximum));
    try std.testing.expect(holds(.add_fits, maximum, 0));
    try std.testing.expect(!holds(.add_fits, maximum, 1));
    try std.testing.expect(!holds(.sub_fits, 0, 1));
    try std.testing.expect(!holds(.index, 0, 0));
    try std.testing.expect(holds(.index, 1, 0));
    try std.testing.expect(!holds(.index, 1, 1));
    try std.testing.expectEqual(@as(?Relation, .index), constructor("@proof.index"));
    try std.testing.expectEqual(@as(?Relation, null), constructor("User.index"));
}

test "numeric proof imports validate a shared public graph once per invocation" {
    const allocator = std.testing.allocator;
    var source: Store = .{};
    defer source.deinit(allocator);
    const value = try source.intern(allocator, .{ .tag = .formal, .a = 0 });
    for (0..2048) |number| _ = try source.intern(allocator, .{ .tag = .literal, .a = @intCast(number) });
    var target: Store = .{};
    defer target.deinit(allocator);
    const actual = try target.intern(allocator, .{ .tag = .version, .a = 7, .b = 2 });
    const proofs: [256]Proposition = @splat(.{ .relation = .eq, .left = value, .right = value });
    const before = target.visits;
    const imported = try target.importMany(allocator, source.view(), &proofs, .{ .formals = &.{.u32} }, .{ .formals = &.{actual} });
    defer allocator.free(imported);
    for (imported) |proof| try std.testing.expectEqual(Proposition{ .relation = .eq, .left = actual, .right = actual }, proof);
    try std.testing.expectEqual(source.terms.items.len + proofs.len * 3, target.visits - before);
    try std.testing.expectEqual(@as(usize, 1), target.terms.items.len);
}
