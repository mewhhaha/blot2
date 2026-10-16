//! Complete public operand recipes, independent of data type substitution.
//! Validation establishes well-formed, consistent requirements, never a runtime
//! witness. A compiled producer still needs checked introductions and uses.
const std = @import("std");
const terms = @import("numeric_proof_terms.zig");
const A = std.mem.Allocator;
pub const Error = terms.Error || error{ContradictoryProof};
pub const Stats = struct { terms: usize = 0, edges: usize = 0, visits: usize = 0 };
pub const Requirement = struct { before: u32, proposition: terms.Proposition };
/// Formal recipes are dense; these slots map them to actual curried arrows.
/// Bool, function, and erased proof inputs still count toward arity. A type
/// variable or a proof requirement cannot fill an omitted ordinary argument.
pub const Signature = struct {
    arity: u32,
    value_slots: []const u32,
    proof_slots: []const u32,
    contract: Contract,

    pub fn validate(self: Signature, allocator: A, limits: terms.Limits) Error!void {
        _ = try self.validateMeasured(allocator, limits);
    }
    fn validateMeasured(self: Signature, allocator: A, limits: terms.Limits) Error!Stats {
        if (self.arity > limits.terms) return error.ProofAnalysisLimit;
        if (self.value_slots.len != self.contract.values.len or self.proof_slots.len != self.contract.requirements.len) return error.InvalidProofOperand;
        for ([_][]const u32{ self.value_slots, self.proof_slots }) |slots| {
            for (slots, 0..) |slot, i| {
                if (slot >= self.arity or (i != 0 and slot <= slots[i - 1])) return error.ProofScopeEscape;
            }
        }
        var values: usize = 0;
        for (self.proof_slots, self.contract.requirements) |slot, requirement| {
            while (values < self.value_slots.len and self.value_slots[values] < slot) values += 1;
            if (values < self.value_slots.len and self.value_slots[values] == slot) return error.InvalidProofOperand;
            if (requirement.before != values) return error.ProofScopeEscape;
        }
        const visits = self.value_slots.len + self.proof_slots.len;
        if (visits > limits.visits) return error.ProofAnalysisLimit;
        var remaining = limits;
        remaining.visits -= visits;
        var result = try self.contract.validateMeasured(allocator, remaining);
        result.visits += visits;
        return result;
    }
    pub fn validateInto(self: Signature, allocator: A, destination: *terms.Store) Error!void {
        var remaining = destination.limits;
        remaining.visits -|= destination.visits;
        const measured = try self.validateMeasured(allocator, remaining);
        try destination.charge(measured.visits);
    }

    /// The caller owns the returned propositions: requirements in order,
    /// followed by the optional result. These are recipes, not witnesses.
    /// Every ordinary proof-capable argument supplies its checked identity;
    /// other slots are zero. One import shares the complete operand graph.
    pub fn instantiate(self: Signature, allocator: A, destination: *terms.Store, arguments: []const terms.Id) Error![]terms.Proposition {
        try self.validateInto(allocator, destination);
        if (arguments.len != self.arity) return error.ProofScopeEscape;
        var next_value: usize = 0;
        for (arguments, 0..) |argument, slot| {
            if (next_value < self.value_slots.len and self.value_slots[next_value] == slot) {
                next_value += 1;
            } else if (argument != 0) return error.InvalidProofOperand;
        }
        const formals = try allocator.alloc(terms.Id, self.value_slots.len);
        defer allocator.free(formals);
        for (self.value_slots, self.contract.values, formals) |slot, kind, *formal| {
            const actual = arguments[slot];
            if ((try destination.view().get(actual)).kind != kind) return error.InvalidProofOperand;
            formal.* = actual;
        }
        const count = std.math.add(usize, self.contract.requirements.len, @intFromBool(self.contract.result != null)) catch return error.ProofAnalysisLimit;
        const propositions = try allocator.alloc(terms.Proposition, count);
        defer allocator.free(propositions);
        for (self.contract.requirements, propositions[0..self.contract.requirements.len]) |requirement, *proof| proof.* = requirement.proposition;
        if (self.contract.result) |result| propositions[count - 1] = result;
        return destination.importMany(allocator, .{ .terms = self.contract.operands }, propositions, .{ .formals = self.contract.values }, .{ .formals = formals });
    }

    /// A curried proof parameter can depend only on already supplied values.
    /// All preceding ordinary arguments remain explicit, even if this recipe
    /// does not mention them. Later values cannot be inferred from the proof.
    pub fn instantiateRequirement(self: Signature, allocator: A, destination: *terms.Store, slot: u32, preceding: []const terms.Id) Error!terms.Proposition {
        try self.validateInto(allocator, destination);
        if (slot != preceding.len or slot >= self.arity) return error.ProofScopeEscape;
        var requested: ?terms.Proposition = null;
        for (self.proof_slots, self.contract.requirements) |position, value| if (position == slot) {
            requested = value.proposition;
            break;
        };
        const proof = requested orelse return error.InvalidProofOperand;
        const formals = try allocator.alloc(terms.Id, self.value_slots.len);
        defer allocator.free(formals);
        @memset(formals, 0);
        var next: usize = 0;
        for (preceding, 0..) |actual, position| {
            if (next < self.value_slots.len and self.value_slots[next] == position) {
                if ((try destination.view().get(actual)).kind != self.contract.values[next]) return error.InvalidProofOperand;
                formals[next] = actual;
                next += 1;
            } else if (actual != 0) return error.InvalidProofOperand;
        }
        return destination.import(allocator, .{ .terms = self.contract.operands }, proof, .{ .formals = self.contract.values }, .{ .formals = formals });
    }
};
pub const Contract = struct {
    values: []const terms.Kind,
    operands: []const terms.Term,
    requirements: []const Requirement,
    result: ?terms.Proposition = null,

    pub fn validate(self: Contract, allocator: A, limits: terms.Limits) Error!void {
        _ = try self.validateMeasured(allocator, limits);
    }
    pub fn validateMeasured(self: Contract, allocator: A, limits: terms.Limits) Error!Stats {
        if (self.values.len > limits.terms or self.requirements.len > 256) return error.ProofAnalysisLimit;
        const source: terms.View = .{ .terms = self.operands };
        try source.validate(.{ .formals = self.values }, limits);
        if (self.requirements.len == 0 and self.result == null) return .{ .terms = self.operands.len, .visits = self.operands.len };
        var owned: terms.Store = .{ .limits = limits, .visits = self.operands.len };
        defer owned.deinit(allocator);
        const mapping = try allocator.alloc(terms.Id, self.operands.len);
        defer allocator.free(mapping);
        for (self.operands, mapping) |input, *target| {
            var term = input;
            if (term.tag == .length or term.tag == .complement) term.a = mapping[term.a - 1];
            target.* = try owned.intern(allocator, term);
        }
        const initial_visits = owned.visits;
        var graph: Order = .{ .remaining = limits.visits -| initial_visits };
        defer graph.deinit(allocator);
        var prior: u32 = 0;
        for (self.requirements) |requirement| {
            if (requirement.before < prior or requirement.before > self.values.len) return error.ProofScopeEscape;
            prior = requirement.before;
            try inScope(source, requirement.proposition, requirement.before);
            try graph.proposition(allocator, &owned, remap(mapping, requirement.proposition));
        }
        if (self.result) |result| {
            try inScope(source, result, self.values.len);
            try graph.proposition(allocator, &owned, remap(mapping, result));
        }
        try graph.complements(allocator, &owned);
        try graph.bounds(allocator, &owned);
        // Normalizing index lengths and complements also consumes the budget.
        try graph.spend(owned.visits - initial_visits);
        try graph.checkConsistency(allocator, owned.terms.items.len);
        return .{ .terms = owned.terms.items.len, .edges = graph.edges.items.len, .visits = limits.visits - graph.remaining };
    }
};

fn inScope(source: terms.View, proof: terms.Proposition, before: usize) Error!void {
    try source.proposition(proof);
    for ([_]terms.Id{ proof.left, proof.right }) |root| {
        var cursor = root;
        // Valid recipes have at most complement(length(formal)).
        for (0..3) |_| {
            const term = try source.get(cursor);
            switch (term.tag) {
                .literal => break,
                .formal => {
                    if (term.a >= before) return error.ProofScopeEscape;
                    break;
                },
                .length, .complement => cursor = term.a,
                .capture, .version => return error.ProofScopeEscape,
            }
        }
    }
}
fn remap(mapping: []const terms.Id, proof: terms.Proposition) terms.Proposition {
    return .{ .relation = proof.relation, .left = mapping[proof.left - 1], .right = mapping[proof.right - 1] };
}

const Pair = struct { left: terms.Id, right: terms.Id };
const Edge = struct { pair: Pair, strict: bool };
const Constraint = struct { forward: Edge, reverse: bool = false };
pub const Unequal = struct { left: terms.Id, right: terms.Id };

/// Finite unsigned reasoning over already admitted facts. Contradictions and
/// exhausted work never supply a proof. Collection lengths retain their exact
/// value owner; wrapping sums and differences are not ordered expressions.
pub fn entails(allocator: A, store: *terms.Store, facts: []const terms.Proposition, goal: terms.Proposition) Error!bool {
    return entailsWithUnequal(allocator, store, facts, &.{}, goal);
}
pub fn entailsWithUnequal(allocator: A, store: *terms.Store, facts: []const terms.Proposition, unequal: []const Unequal, goal: terms.Proposition) Error!bool {
    const initial_visits = store.visits;
    const budget = store.limits.visits -| initial_visits;
    var graph: Order = .{ .remaining = budget };
    defer graph.deinit(allocator);
    var normalized_visits: usize = 0;
    defer store.visits = @min(store.limits.visits, store.visits +| (budget - graph.remaining - normalized_visits));
    for (facts) |fact| try graph.proposition(allocator, store, fact);
    const requested = try graph.constraint(allocator, store, goal);
    try graph.complements(allocator, store);
    try graph.bounds(allocator, store);
    const visits = store.visits - initial_visits;
    try graph.spend(visits);
    normalized_visits = visits;
    try graph.checkConsistency(allocator, store.terms.items.len);
    for (unequal) |pair| {
        try store.view().proposition(.{ .relation = .eq, .left = pair.left, .right = pair.right });
        if (try graph.reaches(allocator, store.terms.items.len, .{ .pair = .{ .left = pair.left, .right = pair.right }, .strict = false })) {
            try graph.edge(allocator, pair.left, pair.right, true);
        } else if (try graph.reaches(allocator, store.terms.items.len, .{ .pair = .{ .left = pair.right, .right = pair.left }, .strict = false })) {
            try graph.edge(allocator, pair.right, pair.left, true);
        }
    }
    if (unequal.len != 0) try graph.checkConsistency(allocator, store.terms.items.len);
    if (!try graph.reaches(allocator, store.terms.items.len, requested.forward)) return false;
    if (requested.reverse) return graph.reaches(allocator, store.terms.items.len, .{ .pair = .{ .left = requested.forward.pair.right, .right = requested.forward.pair.left }, .strict = false });
    return true;
}

const Order = struct {
    edges: std.ArrayList(Edge) = .empty,
    remaining: usize,
    needs_complements: bool = false,
    fn deinit(self: *Order, allocator: A) void {
        self.edges.deinit(allocator);
    }
    fn spend(self: *Order, count: usize) Error!void {
        if (count > self.remaining) return error.ProofAnalysisLimit;
        self.remaining -= count;
    }
    fn charge(self: *Order) Error!void {
        try self.spend(1);
    }
    fn edge(self: *Order, allocator: A, left: terms.Id, right: terms.Id, strict: bool) Error!void {
        try self.charge();
        if (left == right) {
            if (strict) return error.ContradictoryProof;
            return;
        }
        try self.edges.append(allocator, .{ .pair = .{ .left = left, .right = right }, .strict = strict });
    }
    fn constraint(self: *Order, allocator: A, store: *terms.Store, value: terms.Proposition) Error!Constraint {
        try store.view().proposition(value);
        self.needs_complements = self.needs_complements or store.terms.items[value.left - 1].tag == .complement or store.terms.items[value.right - 1].tag == .complement;
        switch (value.relation) {
            .eq, .lt, .le => return .{ .forward = .{ .pair = .{ .left = value.left, .right = value.right }, .strict = value.relation == .lt }, .reverse = value.relation == .eq },
            .sub_fits => return .{ .forward = .{ .pair = .{ .left = value.right, .right = value.left }, .strict = false } },
            .add_fits => {
                const complement = try store.intern(allocator, .{ .tag = .complement, .a = value.right });
                self.needs_complements = self.needs_complements or store.terms.items[complement - 1].tag == .complement;
                return .{ .forward = .{ .pair = .{ .left = value.left, .right = complement }, .strict = false } };
            },
            .index => return .{ .forward = .{ .pair = .{ .left = value.right, .right = try store.intern(allocator, .{ .tag = .length, .a = value.left }) }, .strict = true } },
        }
    }
    fn proposition(self: *Order, allocator: A, store: *terms.Store, value: terms.Proposition) Error!void {
        const item = try self.constraint(allocator, store, value);
        try self.edge(allocator, item.forward.pair.left, item.forward.pair.right, item.forward.strict);
        if (item.reverse) try self.edge(allocator, item.forward.pair.right, item.forward.pair.left, false);
    }
    fn bounds(self: *Order, allocator: A, store: *terms.Store) Error!void {
        const zero = try store.intern(allocator, .{ .tag = .literal, .a = 0 });
        const maximum = try store.intern(allocator, .{ .tag = .literal, .a = std.math.maxInt(u32) });
        for (store.terms.items, 1..) |term, id_| {
            if (term.kind != .u32) continue;
            const id: terms.Id = @intCast(id_);
            try self.edge(allocator, zero, id, false);
            try self.edge(allocator, id, maximum, false);
            if (term.tag != .literal) continue;
            for (store.terms.items[0 .. id_ - 1], 1..) |other, other_id_| {
                try self.charge();
                if (other.tag != .literal) continue;
                const other_id: terms.Id = @intCast(other_id_);
                if (other.a < term.a) {
                    try self.edge(allocator, other_id, id, true);
                } else if (term.a < other.a) {
                    try self.edge(allocator, id, other_id, true);
                }
            }
        }
    }
    fn reaches(self: *Order, allocator: A, count: usize, requested: Edge) Error!bool {
        const none = std.math.maxInt(usize);
        const Step = struct { node: terms.Id, strict: bool };
        try self.spend(count + self.edges.items.len);
        const first = try allocator.alloc(usize, count + 1);
        defer allocator.free(first);
        @memset(first, none);
        const next = try allocator.alloc(usize, self.edges.items.len);
        defer allocator.free(next);
        for (self.edges.items, 0..) |item, index| {
            next[index] = first[item.pair.left];
            first[item.pair.left] = index;
        }
        const seen = try allocator.alloc([2]bool, count + 1);
        defer allocator.free(seen);
        @memset(seen, .{ false, false });
        const queue_length = std.math.mul(usize, 2, count + 1) catch return error.ProofAnalysisLimit;
        const queue = try allocator.alloc(Step, queue_length);
        defer allocator.free(queue);
        queue[0] = .{ .node = requested.pair.left, .strict = false };
        seen[requested.pair.left][0] = true;
        var end: usize = 1;
        var begin: usize = 0;
        while (begin < end) : (begin += 1) {
            const current = queue[begin];
            try self.charge();
            if (current.node == requested.pair.right and (current.strict or !requested.strict)) return true;
            var edge_id = first[current.node];
            while (edge_id != none) : (edge_id = next[edge_id]) {
                try self.charge();
                const item = self.edges.items[edge_id];
                const strict = current.strict or item.strict;
                const state = @intFromBool(strict);
                if (seen[item.pair.right][state]) continue;
                seen[item.pair.right][state] = true;
                queue[end] = .{ .node = item.pair.right, .strict = strict };
                end += 1;
            }
        }
        return false;
    }
    // Complements are exact unsigned values, so x <= y also constrains
    // (MAX - y) <= (MAX - x). In particular, substituting x = 1 must not
    // leave (MAX - x) unrelated to the literal MAX - 1. Allocate this dual
    // graph only for contracts which actually contain a nonliteral complement.
    fn complements(self: *Order, allocator: A, store: *terms.Store) Error!void {
        if (!self.needs_complements) return;
        const count = store.terms.items.len;
        const slots = std.math.add(usize, count, 1) catch return error.ProofAnalysisLimit;
        const opposite = try allocator.alloc(terms.Id, slots);
        defer allocator.free(opposite);
        @memset(opposite, 0);
        for (1..count + 1) |id| {
            if (store.terms.items[id - 1].kind == .u32) opposite[id] = try store.intern(allocator, .{ .tag = .complement, .a = @intCast(id) });
        }
        const edges = self.edges.items.len;
        for (0..edges) |index| {
            const prior = self.edges.items[index];
            try self.edge(allocator, opposite[prior.pair.right], opposite[prior.pair.left], prior.strict);
        }
    }
    // A strict edge inside a strongly connected component is exactly a
    // contradictory order cycle. Do not materialize all transitive pairs just
    // to decide consistency; that can exhaust a small valid public contract.
    fn checkConsistency(self: *Order, allocator: A, count: usize) Error!void {
        const none = std.math.maxInt(usize);
        const State = struct { index: u32 = 0, low: u32 = 0, component: u32 = 0, first: usize = none };
        const Frame = struct { node: terms.Id, next: usize };
        try self.spend(count + self.edges.items.len);
        const states = try allocator.alloc(State, count + 1);
        defer allocator.free(states);
        @memset(states, .{});
        const next = try allocator.alloc(usize, self.edges.items.len);
        defer allocator.free(next);
        for (self.edges.items, 0..) |item, edge_id| {
            next[edge_id] = states[item.pair.left].first;
            states[item.pair.left].first = edge_id;
        }
        var frames: std.ArrayList(Frame) = .empty;
        defer frames.deinit(allocator);
        try frames.ensureTotalCapacity(allocator, count);
        var stack: std.ArrayList(terms.Id) = .empty;
        defer stack.deinit(allocator);
        try stack.ensureTotalCapacity(allocator, count);
        var discovered: u32 = 0;
        var component: u32 = 0;
        for (1..count + 1) |root_| {
            try self.charge();
            const root: terms.Id = @intCast(root_);
            if (states[root].index != 0) continue;
            discovered += 1;
            states[root].index = discovered;
            states[root].low = discovered;
            stack.appendAssumeCapacity(root);
            frames.appendAssumeCapacity(.{ .node = root, .next = states[root].first });
            while (frames.items.len != 0) {
                const frame = &frames.items[frames.items.len - 1];
                if (frame.next != none) {
                    try self.charge();
                    const edge_id = frame.next;
                    frame.next = next[edge_id];
                    const child = self.edges.items[edge_id].pair.right;
                    if (states[child].index == 0) {
                        discovered += 1;
                        states[child].index = discovered;
                        states[child].low = discovered;
                        stack.appendAssumeCapacity(child);
                        frames.appendAssumeCapacity(.{ .node = child, .next = states[child].first });
                    } else if (states[child].component == 0) {
                        states[frame.node].low = @min(states[frame.node].low, states[child].index);
                    }
                    continue;
                }
                const finished = frames.pop().?.node;
                if (states[finished].low == states[finished].index) {
                    component += 1;
                    while (stack.pop()) |member| {
                        try self.charge();
                        states[member].component = component;
                        if (member == finished) break;
                    }
                }
                if (frames.items.len != 0) {
                    const parent = frames.items[frames.items.len - 1].node;
                    states[parent].low = @min(states[parent].low, states[finished].low);
                }
            }
        }
        for (self.edges.items) |item| {
            try self.charge();
            if (item.strict and states[item.pair.left].component == states[item.pair.right].component) return error.ContradictoryProof;
        }
    }
};

test "numeric proof consistency agrees with transitive closure on mixed strict order graphs" {
    var random = std.Random.DefaultPrng.init(0x70_13);
    const count = 8;
    for (0..256) |_| {
        var graph: Order = .{ .remaining = 65_536 };
        defer graph.deinit(std.testing.allocator);
        // Zero is absent, one is <=, and two is <. The tiny dense oracle is
        // deliberately independent of the production component traversal.
        var reachable: [count][count]u8 = @splat(@splat(0));
        for (0..random.random().uintLessThan(usize, 33)) |_| {
            const left = random.random().uintLessThan(u32, count);
            const right = random.random().uintLessThan(u32, count);
            if (left == right) continue;
            const strict = random.random().boolean();
            try graph.edge(std.testing.allocator, left + 1, right + 1, strict);
            var relation: u8 = 1;
            if (strict) relation = 2;
            reachable[left][right] = @max(reachable[left][right], relation);
        }
        for (0..count) |middle| for (0..count) |left| for (0..count) |right| {
            if (reachable[left][middle] == 0 or reachable[middle][right] == 0) continue;
            reachable[left][right] = @max(reachable[left][right], @max(reachable[left][middle], reachable[middle][right]));
        };
        var contradictory = false;
        for (0..count) |id| contradictory = contradictory or reachable[id][id] == 2;
        if (contradictory) {
            try std.testing.expectError(error.ContradictoryProof, graph.checkConsistency(std.testing.allocator, count));
        } else {
            try graph.checkConsistency(std.testing.allocator, count);
            for (0..count) |left| for (0..count) |right| {
                const pair: Pair = .{ .left = @intCast(left + 1), .right = @intCast(right + 1) };
                try std.testing.expectEqual(left == right or reachable[left][right] != 0, try graph.reaches(std.testing.allocator, count, .{ .pair = pair, .strict = false }));
                try std.testing.expectEqual(reachable[left][right] == 2, try graph.reaches(std.testing.allocator, count, .{ .pair = pair, .strict = true }));
            };
        }
    }
}
