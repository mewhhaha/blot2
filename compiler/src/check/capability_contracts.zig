//! Owned value relationships. Public recipes contain formal slots and shape
//! paths; live authority belongs only to the receiving checker. Effects never
//! substitute for a captured value relationship.
const std = @import("std");
const A = std.mem.Allocator;
pub const Id = u32;
pub const Tag = enum(u8) { empty, unknown, parameter, authority, captures, product, record, wrapped, join, project, elements, argument, callable };
pub const Projection = enum(u8) { index, field, payload };
/// Lists contain child IDs, except records whose words alternate field symbol
/// and child ID. Project stores its base, selector and Projection ordinal.
pub const Term = struct { tag: Tag, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
pub const Error = A.Error || error{ InvalidCapabilityContract, CapabilityAnalysisLimit };
pub const Limits = struct { nodes: usize = 4096, words: usize = 65_536, visits: usize = 65_536, depth: usize = 128 };
pub const View = struct {
    nodes: []const Term,
    words: []const u32,
    pub fn children(self: View, node: Term) []const u32 {
        return self.words[node.a..][0..node.b];
    }
    pub fn parameterMask(self: View, root: Id) Error!u16 {
        if (root >= self.nodes.len or self.nodes.len > 4096) return error.InvalidCapabilityContract;
        var masks: [4096]u16 = @splat(0);
        var remaining: usize = 65_536;
        for (self.nodes, 0..) |node, index| {
            if (remaining == 0) return error.CapabilityAnalysisLimit;
            remaining -= 1;
            switch (node.tag) {
                .parameter => {
                    if (node.a >= 16) return error.InvalidCapabilityContract;
                    masks[index] = @as(u16, 1) << @intCast(node.a);
                },
                .argument => {},
                .callable => {
                    if (node.b >= index or node.c >= index) return error.InvalidCapabilityContract;
                    masks[index] = masks[node.b];
                },
                .wrapped, .project, .elements => {
                    if (node.a >= index) return error.InvalidCapabilityContract;
                    masks[index] = masks[node.a];
                },
                .captures, .product, .join, .record => {
                    if (node.a > self.words.len or node.b > self.words.len - node.a) return error.InvalidCapabilityContract;
                    for (self.children(node), 0..) |child, position| {
                        if (node.tag == .record and position % 2 == 0) continue;
                        if (remaining == 0) return error.CapabilityAnalysisLimit;
                        remaining -= 1;
                        if (child >= index) return error.InvalidCapabilityContract;
                        masks[index] |= masks[child];
                    }
                },
                .unknown, .authority => return error.InvalidCapabilityContract,
                .empty => {},
            }
        }
        return masks[root];
    }
    /// Only captures of nested callables belong to the current sealed body.
    /// Their own formal arguments have a different owner and are not inputs of
    /// this invocation.
    pub fn argumentMask(self: View, root: Id, remaining: *usize) Error!u16 {
        return self.argumentMaskDepth(root, remaining, 0);
    }
    fn argumentMaskDepth(self: View, root: Id, remaining: *usize, depth: usize) Error!u16 {
        if (root >= self.nodes.len or depth >= 128 or remaining.* == 0) return error.CapabilityAnalysisLimit;
        remaining.* -= 1;
        const node = self.nodes[root];
        switch (node.tag) {
            .argument => {
                if (node.a >= 16) return error.InvalidCapabilityContract;
                return @as(u16, 1) << @intCast(node.a);
            },
            .parameter, .authority, .unknown => return error.InvalidCapabilityContract,
            .empty => return 0,
            .callable => return self.argumentMaskDepth(node.b, remaining, depth + 1),
            .wrapped, .project, .elements => return self.argumentMaskDepth(node.a, remaining, depth + 1),
            .captures, .product, .join, .record => {
                if (node.a > self.words.len or node.b > self.words.len - node.a) return error.InvalidCapabilityContract;
                var mask: u16 = 0;
                for (self.children(node), 0..) |child, index| {
                    if (node.tag == .record and index % 2 == 0) continue;
                    mask |= try self.argumentMaskDepth(child, remaining, depth + 1);
                }
                return mask;
            },
        }
    }
    pub fn containsParameter(self: View, root: Id, remaining: *usize) Error!bool {
        return self.parameterDepth(root, remaining, 0);
    }
    fn parameterDepth(self: View, root: Id, remaining: *usize, depth: usize) Error!bool {
        if (root >= self.nodes.len or depth >= 128 or remaining.* == 0) return error.CapabilityAnalysisLimit;
        remaining.* -= 1;
        const node = self.nodes[root];
        switch (node.tag) {
            .parameter, .argument => return true,
            .callable => return self.parameterDepth(node.b, remaining, depth + 1),
            .wrapped, .project, .elements => return self.parameterDepth(node.a, remaining, depth + 1),
            .captures, .product, .join, .record => {
                if (node.a > self.words.len or node.b > self.words.len - node.a) return error.InvalidCapabilityContract;
                for (self.children(node), 0..) |child, index| {
                    if (node.tag == .record and index % 2 == 0) continue;
                    if (try self.parameterDepth(child, remaining, depth + 1)) return true;
                }
                return false;
            },
            else => return false,
        }
    }
    pub fn validate(self: View, root: Id, arity: u32, portable: bool) Error!void {
        if (self.nodes.len == 0 or self.nodes.len > 4096 or self.words.len > 65_536 or root >= self.nodes.len or arity > 16) return error.InvalidCapabilityContract;
        if (!std.meta.eql(self.nodes[0], Term{ .tag = .empty })) return error.InvalidCapabilityContract;
        var visits: usize = 0;
        // Only the prefixes indexed by this view's nodes and words are read.
        var depths: [4096]u8 = undefined;
        @memset(depths[0..self.nodes.len], 0);
        var roles: [65_536]u8 = undefined;
        @memset(roles[0..self.words.len], 0);
        for (self.nodes, 0..) |node, index| {
            visits += 1;
            if (visits > 65_536) return error.CapabilityAnalysisLimit;
            if (@backingInt(node.tag) > @backingInt(Tag.callable)) return error.InvalidCapabilityContract;
            switch (node.tag) {
                .empty, .unknown => if (node.a != 0 or node.b != 0 or node.c != 0) return error.InvalidCapabilityContract,
                .parameter, .argument => if (node.a >= 16 or node.b != 0 or node.c != 0) return error.InvalidCapabilityContract,
                .callable => if (node.a == 0 or node.a > 16 or node.b >= index or node.c >= index) return error.InvalidCapabilityContract,
                .authority => if (portable or node.b == 0 or node.c != 0) return error.InvalidCapabilityContract,
                .wrapped, .elements => if (node.a >= index or node.b != 0 or node.c != 0) return error.InvalidCapabilityContract,
                .project => {
                    if (node.a >= index or node.c > @backingInt(Projection.payload)) return error.InvalidCapabilityContract;
                    if (node.c == @backingInt(Projection.payload) and node.b != 0) return error.InvalidCapabilityContract;
                },
                .captures, .product, .join, .record => {
                    if (node.a > self.words.len or node.b > self.words.len - node.a or node.c != 0) return error.InvalidCapabilityContract;
                    const children_ = self.children(node);
                    if (node.tag == .record) {
                        if (children_.len % 2 != 0) return error.InvalidCapabilityContract;
                        for (0..children_.len / 2) |field| {
                            if (children_[field * 2] == 0 or children_[field * 2 + 1] >= index) return error.InvalidCapabilityContract;
                            for (0..field) |prior| {
                                visits += 1;
                                if (visits > 65_536) return error.CapabilityAnalysisLimit;
                                if (children_[prior * 2] == children_[field * 2]) return error.InvalidCapabilityContract;
                            }
                        }
                    } else for (children_) |child| if (child >= index) return error.InvalidCapabilityContract;
                },
            }
            var height: u16 = 0;
            if (node.tag == .callable) height = @max(@as(u16, depths[node.b]), @as(u16, depths[node.c])) + 1;
            if (node.tag == .wrapped or node.tag == .project or node.tag == .elements) height = @as(u16, depths[node.a]) + 1;
            if (node.tag == .captures or node.tag == .product or node.tag == .record or node.tag == .join) {
                for (self.children(node), 0..) |child, offset| {
                    var role: u8 = 2;
                    if (node.tag == .record and offset % 2 == 0) role = 1;
                    const slot = node.a + offset;
                    if (roles[slot] != 0 and roles[slot] != role) return error.InvalidCapabilityContract;
                    roles[slot] = role;
                    if (role == 2) height = @max(height, @as(u16, depths[child]) + 1);
                }
            }
            if (height >= 128) return error.CapabilityAnalysisLimit;
            depths[index] = @intCast(height);
        }
        var reached: [17][4096]bool = undefined;
        for (&reached) |*row| @memset(row[0..self.nodes.len], false);
        var remaining: usize = 65_536 - visits;
        try self.boundScopes(root, arity, 0, &reached, &remaining, 0);
    }
    fn boundScopes(self: View, root: Id, arity: u32, callable_arity: u32, reached: *[17][4096]bool, remaining: *usize, depth: usize) Error!void {
        if (depth >= 128 or remaining.* == 0) return error.CapabilityAnalysisLimit;
        remaining.* -= 1;
        if (reached[callable_arity][root]) return;
        reached[callable_arity][root] = true;
        const node = self.nodes[root];
        switch (node.tag) {
            .parameter => if (callable_arity != 0 or node.a >= arity) return error.InvalidCapabilityContract,
            .argument => if (callable_arity == 0 or node.a >= callable_arity) return error.InvalidCapabilityContract,
            .authority => if (callable_arity != 0) return error.InvalidCapabilityContract,
            .callable => {
                try self.boundScopes(node.b, arity, callable_arity, reached, remaining, depth + 1);
                try self.boundScopes(node.c, arity, node.a, reached, remaining, depth + 1);
            },
            .wrapped, .project, .elements => try self.boundScopes(node.a, arity, callable_arity, reached, remaining, depth + 1),
            .captures, .product, .record, .join => for (self.children(node), 0..) |child, index| {
                if (node.tag == .record and index % 2 == 0) continue;
                try self.boundScopes(child, arity, callable_arity, reached, remaining, depth + 1);
            },
            .empty, .unknown => {},
        }
    }
};
/// A lease into its immutable collection, never an independent allocation.
pub const Recipe = struct {
    arity: u32,
    root: Id,
    nodes: []const Term,
    words: []const u32,
    pub fn view(self: Recipe) View {
        return .{ .nodes = self.nodes, .words = self.words };
    }
};
pub const Owned = struct {
    arity: u32,
    root: Id,
    nodes: []const Term = &.{},
    words: []const u32 = &.{},
    pub fn view(self: Owned) View {
        return .{ .nodes = self.nodes, .words = self.words };
    }
    pub fn clone(self: Owned, allocator: A) A.Error!Owned {
        const nodes = try allocator.dupe(Term, self.nodes);
        errdefer allocator.free(nodes);
        return .{ .arity = self.arity, .root = self.root, .nodes = nodes, .words = try allocator.dupe(u32, self.words) };
    }
    pub fn deinit(self: *Owned, allocator: A) void {
        allocator.free(self.nodes);
        allocator.free(self.words);
        self.* = undefined;
    }
};
pub const Store = struct {
    nodes: std.ArrayList(Term) = .empty,
    words: std.ArrayList(u32) = .empty,
    limits: Limits = .{},
    visits: usize = 0,
    pub const Mark = struct { nodes: usize, words: usize, visits: usize };
    pub fn mark(self: *const Store) Mark {
        return .{ .nodes = self.nodes.items.len, .words = self.words.items.len, .visits = self.visits };
    }
    pub fn rollback(self: *Store, checkpoint: Mark) void {
        self.nodes.shrinkRetainingCapacity(checkpoint.nodes);
        self.words.shrinkRetainingCapacity(checkpoint.words);
        self.visits = checkpoint.visits;
    }
    pub fn deinit(self: *Store, allocator: A) void {
        self.nodes.deinit(allocator);
        self.words.deinit(allocator);
        self.* = .{};
    }
    pub fn view(self: *const Store) View {
        return .{ .nodes = self.nodes.items, .words = self.words.items };
    }
    fn visit(self: *Store, depth: usize) Error!void {
        if (depth >= self.limits.depth or self.visits >= self.limits.visits) return error.CapabilityAnalysisLimit;
        self.visits += 1;
    }
    pub fn append(self: *Store, allocator: A, term: Term) Error!Id {
        const before = self.mark();
        errdefer self.rollback(before);
        if (self.nodes.items.len == 0) try self.nodes.append(allocator, .{ .tag = .empty });
        for (self.nodes.items, 0..) |known, index| if (std.meta.eql(known, term)) return @intCast(index);
        if (self.nodes.items.len >= self.limits.nodes) return error.CapabilityAnalysisLimit;
        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(allocator, term);
        return id;
    }
    pub fn aggregate(self: *Store, allocator: A, tag: Tag, children_: []const u32) Error!Id {
        const before = self.mark();
        errdefer self.rollback(before);
        if (tag != .product and tag != .record and tag != .captures and tag != .join) return error.InvalidCapabilityContract;
        if (children_.len > self.limits.words -| self.words.items.len) return error.CapabilityAnalysisLimit;
        for (self.nodes.items, 0..) |node, index| {
            if (node.tag != tag or node.b != children_.len) continue;
            if (std.mem.eql(u32, self.view().children(node), children_)) return @intCast(index);
        }
        const start: u32 = @intCast(self.words.items.len);
        try self.words.appendSlice(allocator, children_);
        return self.append(allocator, .{ .tag = tag, .a = start, .b = @intCast(children_.len) });
    }
    pub fn project(self: *Store, allocator: A, base: Id, selector: u32, kind: Projection) Error!Id {
        const before = self.mark();
        errdefer self.rollback(before);
        return self.projectDepth(allocator, base, selector, kind, 0);
    }
    fn projectDepth(self: *Store, allocator: A, base: Id, selector: u32, kind: Projection, depth: usize) Error!Id {
        try self.visit(depth);
        if (base >= self.nodes.items.len) return error.InvalidCapabilityContract;
        const term = self.nodes.items[base];
        if (term.tag == .empty or term.tag == .unknown) return base;
        if (term.tag == .join) {
            var projected: [4096]Id = undefined;
            if (term.b > projected.len) return error.CapabilityAnalysisLimit;
            for (0..term.b) |index| {
                const child = self.words.items[term.a + index];
                projected[index] = try self.projectDepth(allocator, child, selector, kind, depth + 1);
            }
            return self.aggregate(allocator, .join, projected[0..term.b]);
        }
        if (kind == .payload and term.tag == .wrapped) return term.a;
        if (kind == .index and term.tag == .product) {
            if (selector >= term.b) return error.InvalidCapabilityContract;
            return self.words.items[term.a + selector];
        }
        if (kind == .field and term.tag == .record) {
            for (0..term.b / 2) |field| if (self.words.items[term.a + field * 2] == selector) return self.words.items[term.a + field * 2 + 1];
            return error.InvalidCapabilityContract;
        }
        return self.append(allocator, .{ .tag = .project, .a = base, .b = selector, .c = @backingInt(kind) });
    }
    /// An unknown index denotes any element, not the array's own shape. This
    /// distinction prevents a later projection from selecting a sibling array.
    pub fn elements(self: *Store, allocator: A, base: Id) Error!Id {
        const before = self.mark();
        errdefer self.rollback(before);
        return self.elementsDepth(allocator, base, 0);
    }
    fn elementsDepth(self: *Store, allocator: A, base: Id, depth: usize) Error!Id {
        try self.visit(depth);
        if (base >= self.nodes.items.len) return error.InvalidCapabilityContract;
        const term = self.nodes.items[base];
        if (term.tag == .empty or term.tag == .unknown) return base;
        if (term.tag == .product or term.tag == .join) {
            var children_: [4096]Id = undefined;
            if (term.b > children_.len) return error.CapabilityAnalysisLimit;
            for (0..term.b) |index| {
                const child = self.words.items[term.a + index];
                children_[index] = child;
                if (term.tag == .join) children_[index] = try self.elementsDepth(allocator, child, depth + 1);
            }
            return self.aggregate(allocator, .join, children_[0..term.b]);
        }
        return self.append(allocator, .{ .tag = .elements, .a = base });
    }
    pub fn own(self: *const Store, allocator: A, arity: u32, root: Id) Error!Owned {
        try self.view().validate(root, arity, true);
        return (Owned{ .arity = arity, .root = root, .nodes = self.nodes.items, .words = self.words.items }).clone(allocator);
    }
    /// Substitutions are explicit. A failed import leaves the receiver intact,
    /// including its budget; no ordinal from the producer is reused as a value.
    pub fn instantiate(self: *Store, allocator: A, header: anytype, arguments: []const Id) Error!Id {
        const before = self.mark();
        errdefer self.rollback(before);
        try header.view().validate(header.root, header.arity, true);
        if (arguments.len != header.arity) return error.InvalidCapabilityContract;
        if (self.nodes.items.len == 0) _ = try self.append(allocator, .{ .tag = .empty });
        for (arguments) |argument| if (argument >= self.nodes.items.len) return error.InvalidCapabilityContract;
        var needed: [4096]bool = @splat(false);
        needed[header.root] = true;
        var reverse = header.nodes.len;
        while (reverse != 0) {
            reverse -= 1;
            if (!needed[reverse]) continue;
            const term = header.nodes[reverse];
            if (term.tag == .callable) {
                needed[term.b] = true;
                needed[term.c] = true;
            }
            if (term.tag == .wrapped or term.tag == .project or term.tag == .elements) needed[term.a] = true else if (term.tag == .captures or term.tag == .product or term.tag == .record or term.tag == .join) {
                for (header.view().children(term), 0..) |child, index| {
                    if (term.tag == .record and index % 2 == 0) continue;
                    needed[child] = true;
                }
            }
        }
        var map: [4096]Id = undefined;
        map[0] = 0;
        if (self.nodes.items.len == 0) try self.nodes.append(allocator, .{ .tag = .empty });
        for (header.nodes[1..], 1..) |term, index| {
            if (!needed[index]) continue;
            try self.visit(0);
            map[index] = try self.copy(allocator, header.view(), term, &map, arguments);
        }
        return map[header.root];
    }
    /// instantiate, copying the reachable graph children first in depth-first
    /// order. The result then depends only on the recipe's terms, not on how
    /// its producer numbered shared nodes: a live checked module and its frozen
    /// interface number them differently, so published collections built this
    /// way are equal whichever one an importer was checked against.
    pub fn instantiateCanonical(self: *Store, allocator: A, header: anytype, arguments: []const Id) Error!Id {
        const before = self.mark();
        errdefer self.rollback(before);
        const source = header.view();
        try source.validate(header.root, header.arity, true);
        if (arguments.len != header.arity) return error.InvalidCapabilityContract;
        if (self.nodes.items.len == 0) _ = try self.append(allocator, .{ .tag = .empty });
        for (arguments) |argument| if (argument >= self.nodes.items.len) return error.InvalidCapabilityContract;
        const unmapped = std.math.maxInt(Id);
        var map: [4096]Id = undefined;
        @memset(map[0..source.nodes.len], unmapped);
        map[0] = 0;
        // validate bounds every path below 128 nodes, so the stack never
        // exceeds the root plus 128 descendants. Children precede parents.
        const Frame = struct { node: Id, next: u32 = 0 };
        var stack: [130]Frame = undefined;
        var depth: usize = 1;
        stack[0] = .{ .node = header.root };
        while (depth != 0) {
            const top = &stack[depth - 1];
            if (map[top.node] != unmapped) {
                depth -= 1;
                continue;
            }
            const term = source.nodes[top.node];
            const pending: ?Id = switch (term.tag) {
                .callable => edge: {
                    while (top.next < 2) {
                        const child = if (top.next == 0) term.b else term.c;
                        top.next += 1;
                        if (map[child] == unmapped) break :edge child;
                    }
                    break :edge null;
                },
                .wrapped, .project, .elements => edge: {
                    if (top.next != 0) break :edge null;
                    top.next = 1;
                    break :edge if (map[term.a] == unmapped) term.a else null;
                },
                .captures, .product, .record, .join => edge: {
                    const children_ = source.children(term);
                    while (top.next < children_.len) {
                        const position = top.next;
                        top.next += 1;
                        if (term.tag == .record and position % 2 == 0) continue;
                        if (map[children_[position]] == unmapped) break :edge children_[position];
                    }
                    break :edge null;
                },
                else => null,
            };
            if (pending) |child| {
                if (depth == stack.len) return error.CapabilityAnalysisLimit;
                stack[depth] = .{ .node = child };
                depth += 1;
                continue;
            }
            try self.visit(0);
            map[top.node] = try self.copy(allocator, source, term, &map, arguments);
            depth -= 1;
        }
        return map[header.root];
    }
    fn copy(self: *Store, allocator: A, source: View, term: Term, map: *const [4096]Id, arguments: []const Id) Error!Id {
        return switch (term.tag) {
            .empty => 0,
            .unknown => try self.append(allocator, term),
            .parameter => arguments[term.a],
            .argument => try self.append(allocator, term),
            .callable => try self.append(allocator, .{ .tag = .callable, .a = term.a, .b = map[term.b], .c = map[term.c] }),
            .authority => return error.InvalidCapabilityContract,
            .wrapped => try self.append(allocator, .{ .tag = .wrapped, .a = map[term.a] }),
            .elements => try self.elements(allocator, map[term.a]),
            .project => try self.project(allocator, map[term.a], term.b, @fromBackingInt(@intCast(term.c))),
            .captures, .product, .record, .join => blk: {
                const children_ = source.children(term);
                var mapped: [4096]u32 = undefined;
                if (children_.len > mapped.len) return error.CapabilityAnalysisLimit;
                for (children_, 0..) |child, child_index| {
                    if (term.tag == .record and child_index % 2 == 0) {
                        mapped[child_index] = child;
                        continue;
                    }
                    mapped[child_index] = map[child];
                }
                break :blk try self.aggregate(allocator, term.tag, mapped[0..children_.len]);
            },
        };
    }
    pub fn callable(self: *Store, allocator: A, header: Recipe, captures: Id) Error!Id {
        const before = self.mark();
        errdefer self.rollback(before);
        if (self.nodes.items.len == 0) _ = try self.append(allocator, .{ .tag = .empty });
        if (header.arity == 0 or header.arity > 16 or captures >= self.nodes.items.len) return error.InvalidCapabilityContract;
        var arguments: [16]Id = undefined;
        for (0..header.arity) |index| arguments[index] = try self.append(allocator, .{ .tag = .argument, .a = @intCast(index) });
        const result = try self.instantiate(allocator, header, arguments[0..header.arity]);
        return self.append(allocator, .{ .tag = .callable, .a = header.arity, .b = captures, .c = result });
    }
    pub fn callableArity(self: *const Store, root: Id, arity: usize, remaining: *usize, depth: usize) Error!bool {
        if (root >= self.nodes.items.len or depth >= 128 or remaining.* == 0) return error.CapabilityAnalysisLimit;
        remaining.* -= 1;
        const node = self.nodes.items[root];
        if (node.tag == .callable) return node.a == arity and node.a != 0 and node.a <= 16 and node.b < root and node.c < root;
        if (node.tag != .join or node.b == 0) return false;
        if (node.a > self.words.items.len or node.b > self.words.items.len - node.a) return error.InvalidCapabilityContract;
        for (self.view().children(node)) |child| {
            if (child >= root) return error.InvalidCapabilityContract;
            if (!try self.callableArity(child, arity, remaining, depth + 1)) return false;
        }
        return true;
    }
    pub fn invoke(self: *Store, allocator: A, root: Id, arguments: []const Id) Error!Id {
        const before = self.mark();
        errdefer self.rollback(before);
        return self.invokeDepth(allocator, root, arguments, 0);
    }
    fn invokeDepth(self: *Store, allocator: A, root: Id, arguments: []const Id, depth: usize) Error!Id {
        try self.visit(depth);
        if (root >= self.nodes.items.len or arguments.len == 0 or arguments.len > 16) return error.InvalidCapabilityContract;
        const callable_ = self.nodes.items[root];
        if (callable_.tag == .join) {
            if (callable_.b == 0 or callable_.b > 4096 or callable_.a > self.words.items.len or callable_.b > self.words.items.len - callable_.a) return error.InvalidCapabilityContract;
            var results: [4096]Id = undefined;
            for (0..callable_.b) |index| {
                const child = self.words.items[callable_.a + index];
                if (child >= root) return error.InvalidCapabilityContract;
                results[index] = try self.invokeDepth(allocator, child, arguments, depth + 1);
            }
            return self.aggregate(allocator, .join, results[0..callable_.b]);
        }
        if (callable_.tag != .callable or callable_.a != arguments.len or callable_.b >= root or callable_.c >= root) return error.InvalidCapabilityContract;
        for (arguments) |argument| if (argument >= self.nodes.items.len) return error.InvalidCapabilityContract;
        const count = self.nodes.items.len;
        if (count > 4096) return error.CapabilityAnalysisLimit;
        var needed: [4096]bool = @splat(false);
        needed[callable_.c] = true;
        var reverse = count;
        while (reverse != 0) {
            reverse -= 1;
            try self.visit(depth);
            if (!needed[reverse]) continue;
            const node = self.nodes.items[reverse];
            switch (node.tag) {
                .callable => {
                    if (node.a == 0 or node.a > 16 or node.b >= reverse or node.c >= reverse) return error.InvalidCapabilityContract;
                    needed[node.b] = true;
                },
                .wrapped, .project, .elements => {
                    if (node.a >= reverse) return error.InvalidCapabilityContract;
                    needed[node.a] = true;
                },
                .captures, .product, .record, .join => {
                    if (node.a > self.words.items.len or node.b > self.words.items.len - node.a) return error.InvalidCapabilityContract;
                    if (node.tag == .record and node.b % 2 != 0) return error.InvalidCapabilityContract;
                    for (self.view().children(node), 0..) |child, index| {
                        try self.visit(depth);
                        if (node.tag == .record and index % 2 == 0) continue;
                        if (child >= reverse) return error.InvalidCapabilityContract;
                        needed[child] = true;
                    }
                },
                else => {},
            }
        }
        var map: [4096]Id = undefined;
        map[0] = 0;
        for (1..count) |index| {
            try self.visit(depth);
            if (!needed[index]) continue;
            const node = self.nodes.items[index];
            map[index] = switch (node.tag) {
                .empty, .unknown => @intCast(index),
                .argument => blk: {
                    if (node.a >= arguments.len) return error.InvalidCapabilityContract;
                    break :blk arguments[node.a];
                },
                .parameter, .authority => return error.InvalidCapabilityContract,
                .callable => try self.append(allocator, .{ .tag = .callable, .a = node.a, .b = map[node.b], .c = node.c }),
                .wrapped => try self.append(allocator, .{ .tag = .wrapped, .a = map[node.a] }),
                .elements => try self.elements(allocator, map[node.a]),
                .project => try self.project(allocator, map[node.a], node.b, @fromBackingInt(@intCast(node.c))),
                .captures, .product, .record, .join => blk: {
                    if (node.b > 4096) return error.CapabilityAnalysisLimit;
                    var children_: [4096]Id = undefined;
                    for (self.view().children(node), 0..) |child, position| {
                        if (node.tag == .record and position % 2 == 0) children_[position] = child else children_[position] = map[child];
                    }
                    break :blk try self.aggregate(allocator, node.tag, children_[0..node.b]);
                },
            };
        }
        if (callable_.b == 0) return map[callable_.c];
        return self.aggregate(allocator, .join, &.{ map[callable_.c], callable_.b });
    }
};

/// One module owns a shared positional graph. Sparse binding roots avoid
/// copying an identical pair/closure recipe for every ordinary helper.
pub const Binding = struct { binding: u32, root: Id };
pub const Collection = struct {
    nodes: []Term = &.{},
    words: []u32 = &.{},
    bindings: []Binding = &.{},
    pub fn header(self: Collection, binding: u32, arity: u32) ?Recipe {
        for (self.bindings) |entry| if (entry.binding == binding) return .{ .arity = arity, .root = entry.root, .nodes = self.nodes, .words = self.words };
        return null;
    }
    pub fn select(self: Collection, allocator: A, bindings_: anytype, keep: ?[]const bool) Error!Collection {
        var store: Store = .{};
        defer store.deinit(allocator);
        var roots: std.ArrayList(Binding) = .empty;
        defer roots.deinit(allocator);
        for (self.bindings) |entry| {
            if (entry.binding >= bindings_.len) return error.InvalidCapabilityContract;
            const binding = bindings_[entry.binding];
            if (binding.kind != .global or !binding.capability_parameters.present()) continue;
            if (keep) |selected| if (!selected[entry.binding]) continue;
            const recipe = self.header(entry.binding, binding.capability_parameters.arity()).?;
            var arguments: [16]u32 = undefined;
            for (0..recipe.arity) |index| arguments[index] = try store.append(allocator, .{ .tag = .parameter, .a = @intCast(index) });
            const root = try store.instantiateCanonical(allocator, recipe, arguments[0..recipe.arity]);
            try roots.append(allocator, .{ .binding = entry.binding, .root = root });
        }
        if (roots.items.len == 0) return .{};
        var result: Collection = .{};
        errdefer result.deinit(allocator);
        result.nodes = try store.nodes.toOwnedSlice(allocator);
        result.words = try store.words.toOwnedSlice(allocator);
        result.bindings = try roots.toOwnedSlice(allocator);
        return result;
    }
    pub fn validate(self: Collection, binding_count: usize, symbol_count: usize) Error!void {
        if (self.bindings.len == 0) {
            if (self.nodes.len != 0 or self.words.len != 0) return error.InvalidCapabilityContract;
            return;
        }
        try (View{ .nodes = self.nodes, .words = self.words }).validate(0, 16, true);
        var previous: ?u32 = null;
        for (self.bindings) |entry| {
            if (entry.binding == 0 or entry.binding >= binding_count) return error.InvalidCapabilityContract;
            if (previous) |old| if (entry.binding <= old) return error.InvalidCapabilityContract;
            previous = entry.binding;
            if (entry.root >= self.nodes.len) return error.InvalidCapabilityContract;
        }
        for (self.nodes) |node| {
            if (node.tag == .record) for (0..node.b / 2) |field| {
                if (self.words[node.a + field * 2] >= symbol_count) return error.InvalidCapabilityContract;
            };
            if (node.tag == .project and node.c == @backingInt(Projection.field) and (node.b == 0 or node.b >= symbol_count)) return error.InvalidCapabilityContract;
        }
    }
    pub fn clone(self: Collection, allocator: A) A.Error!Collection {
        var result: Collection = .{};
        errdefer result.deinit(allocator);
        result.nodes = try allocator.dupe(Term, self.nodes);
        result.words = try allocator.dupe(u32, self.words);
        result.bindings = try allocator.dupe(Binding, self.bindings);
        return result;
    }
    pub fn deinit(self: *Collection, allocator: A) void {
        allocator.free(self.nodes);
        allocator.free(self.words);
        allocator.free(self.bindings);
        self.* = .{};
    }
};

fn projectionLaw(allocator: A) !void {
    var producer: Store = .{};
    defer producer.deinit(allocator);
    const input = try producer.append(allocator, .{ .tag = .parameter });
    _ = try producer.append(allocator, .{ .tag = .parameter, .a = 15 });
    const selected = try producer.project(allocator, input, 1, .index);
    var header = try producer.own(allocator, 1, selected);
    defer header.deinit(allocator);
    var receiver: Store = .{};
    defer receiver.deinit(allocator);
    const younger = try receiver.append(allocator, .{ .tag = .authority, .a = 7, .b = 3 });
    const older = try receiver.append(allocator, .{ .tag = .authority, .a = 7, .b = 1 });
    const captured = try receiver.aggregate(allocator, .captures, &.{older});
    const pair = try receiver.aggregate(allocator, .product, &.{ younger, captured });
    const before = receiver.mark();
    const value = try receiver.instantiate(allocator, header, &.{pair});
    try std.testing.expectEqual(captured, value);
    try std.testing.expectEqual(before.nodes, receiver.mark().nodes);
    try std.testing.expectEqual(before.words, receiver.mark().words);
    try std.testing.expect(receiver.mark().visits > before.visits);
    try std.testing.expectError(error.InvalidCapabilityContract, receiver.own(allocator, 1, pair));
    const failed = receiver.mark();
    try std.testing.expectError(error.InvalidCapabilityContract, receiver.instantiate(allocator, header, &.{}));
    try std.testing.expectEqual(failed, receiver.mark());
}
test "owned capability recipe substitution preserves precise paths and rejects live authority publication" {
    try projectionLaw(std.testing.allocator);
}
test "owned capability recipe imports retain atomic ownership under allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, projectionLaw, .{});
}
test "owned capability recipe validators reject later edges duplicate fields and unbound formals" {
    const nodes = [_]Term{ .{ .tag = .empty }, .{ .tag = .parameter }, .{ .tag = .product, .a = 0, .b = 1 } };
    try std.testing.expectError(error.InvalidCapabilityContract, (View{ .nodes = &nodes, .words = &.{2} }).validate(2, 1, true));
    const fields = [_]Term{ .{ .tag = .empty }, .{ .tag = .record, .a = 0, .b = 4 } };
    try std.testing.expectError(error.InvalidCapabilityContract, (View{ .nodes = &fields, .words = &.{ 7, 0, 7, 0 } }).validate(1, 0, true));
    try std.testing.expectError(error.InvalidCapabilityContract, (View{ .nodes = &nodes, .words = &.{1} }).validate(2, 0, true));
}

/// Numeric node IDs are local to their owners. Compare the owned relationships
/// themselves before a public claim can authorize a transfer.
pub fn equivalent(left: View, left_root: Id, right: View, right_root: Id) Error!bool {
    var remaining: usize = 65_536;
    return equivalentDepth(left, left_root, right, right_root, &remaining, 0);
}
fn equivalentDepth(left: View, left_root: Id, right: View, right_root: Id, remaining: *usize, depth: usize) Error!bool {
    if (depth >= 128 or remaining.* == 0) return error.CapabilityAnalysisLimit;
    remaining.* -= 1;
    if (left_root >= left.nodes.len or right_root >= right.nodes.len) return error.InvalidCapabilityContract;
    const a = left.nodes[left_root];
    const b = right.nodes[right_root];
    if (a.tag != b.tag) return false;
    switch (a.tag) {
        .empty, .unknown => return true,
        .parameter, .argument, .authority => return a.a == b.a and a.b == b.b and a.c == b.c,
        .callable => return a.a == b.a and try equivalentDepth(left, a.b, right, b.b, remaining, depth + 1) and try equivalentDepth(left, a.c, right, b.c, remaining, depth + 1),
        .wrapped, .elements => return equivalentDepth(left, a.a, right, b.a, remaining, depth + 1),
        .project => return a.b == b.b and a.c == b.c and try equivalentDepth(left, a.a, right, b.a, remaining, depth + 1),
        .captures, .product, .join, .record => {
            if (a.b != b.b) return false;
            const before = left.children(a);
            const after = right.children(b);
            for (before, after, 0..) |first, second, index| {
                if (a.tag == .record and index % 2 == 0) {
                    if (first != second) return false;
                    continue;
                }
                if (!try equivalentDepth(left, first, right, second, remaining, depth + 1)) return false;
            }
            return true;
        },
    }
}

/// Recipes hash their relationships and owned field spellings, independently
/// of module node IDs, dictionary ordinals or unrelated graph entries.
pub fn digest(recipe: Recipe, pool: *const @import("../parse/symbols.zig").Pool) ?[32]u8 {
    recipe.view().validate(recipe.root, recipe.arity, true) catch return null;
    var hash: std.crypto.hash.Blake3 = .init(.{});
    word(&hash, 0x43565001); // capability value paths v1
    word(&hash, recipe.arity);
    var remaining: usize = 65_536;
    if (!digestTerm(recipe.view(), recipe.root, pool, &hash, &remaining, 0)) return null;
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
fn word(hash: *std.crypto.hash.Blake3, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hash.update(&bytes);
}
fn fieldDigest(hash: *std.crypto.hash.Blake3, pool: *const @import("../parse/symbols.zig").Pool, symbol: u32) bool {
    if (symbol == 0 or symbol > pool.entries.items.len) return false;
    const text = pool.get(symbol);
    word(hash, @intCast(text.len));
    hash.update(text);
    return true;
}
fn digestTerm(view: View, root: Id, pool: *const @import("../parse/symbols.zig").Pool, hash: *std.crypto.hash.Blake3, remaining: *usize, depth: usize) bool {
    if (depth >= 128 or remaining.* == 0) return false;
    remaining.* -= 1;
    const term = view.nodes[root];
    word(hash, @backingInt(term.tag));
    switch (term.tag) {
        .empty, .unknown => {},
        .authority => return false,
        .parameter, .argument => word(hash, term.a),
        .callable => {
            word(hash, term.a);
            return digestTerm(view, term.b, pool, hash, remaining, depth + 1) and digestTerm(view, term.c, pool, hash, remaining, depth + 1);
        },
        .wrapped, .elements => return digestTerm(view, term.a, pool, hash, remaining, depth + 1),
        .project => {
            word(hash, term.c);
            if (term.c == @backingInt(Projection.field)) {
                if (!fieldDigest(hash, pool, term.b)) return false;
            } else word(hash, term.b);
            return digestTerm(view, term.a, pool, hash, remaining, depth + 1);
        },
        .captures, .product, .record, .join => {
            word(hash, term.b);
            for (view.children(term), 0..) |child, index| {
                if (term.tag == .record and index % 2 == 0) {
                    if (!fieldDigest(hash, pool, child)) return false;
                } else if (!digestTerm(view, child, pool, hash, remaining, depth + 1)) return false;
            }
        },
    }
    return true;
}

test "owned capability recipe digests track field paths across dictionaries" {
    const a = std.testing.allocator;
    var left_pool: @import("../parse/symbols.zig").Pool = .{};
    defer left_pool.deinit(a);
    const left = try left_pool.intern(a, "retained");
    const discarded = try left_pool.intern(a, "discarded");
    var right_pool: @import("../parse/symbols.zig").Pool = .{};
    defer right_pool.deinit(a);
    _ = try right_pool.intern(a, "unrelated");
    const right = try right_pool.intern(a, "retained");
    var nodes = [_]Term{ .{ .tag = .empty }, .{ .tag = .parameter }, .{ .tag = .project, .a = 1, .b = left, .c = @backingInt(Projection.field) } };
    const recipe: Recipe = .{ .arity = 1, .root = 2, .nodes = &nodes, .words = &.{} };
    const original = digest(recipe, &left_pool).?;
    nodes[2].b = discarded;
    try std.testing.expect(!std.mem.eql(u8, &original, &digest(recipe, &left_pool).?));
    nodes[2].b = right;
    try std.testing.expectEqual(original, digest(recipe, &right_pool).?);
}

fn unknownIndexLaw(allocator: A) !void {
    var store: Store = .{};
    defer store.deinit(allocator);
    const hidden = try store.append(allocator, .{ .tag = .authority, .a = 1, .b = 2 });
    const first = try store.aggregate(allocator, .product, &.{ 0, hidden });
    const second = try store.aggregate(allocator, .product, &.{ 0, 0 });
    const outer = try store.aggregate(allocator, .product, &.{ first, second });
    const selected = try store.elements(allocator, outer);
    const leaf = try store.project(allocator, selected, 1, .index);
    const choices = store.view().children(store.nodes.items[leaf]);
    try std.testing.expectEqualSlices(Id, &.{ hidden, 0 }, choices);
    const before = store.mark();
    store.limits.visits = store.visits;
    try std.testing.expectError(error.CapabilityAnalysisLimit, store.elements(allocator, outer));
    try std.testing.expectEqual(before, store.mark());
}
test "owned capability recipe unknown indices preserve nested alternatives and budget rollback" {
    try unknownIndexLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, unknownIndexLaw, .{});
}

fn callableLaw(allocator: A) !void {
    var source: Store = .{};
    defer source.deinit(allocator);
    const input = try source.append(allocator, .{ .tag = .parameter });
    const record = try source.aggregate(allocator, .record, &.{ 1, input });
    var receiver: Store = .{};
    defer receiver.deinit(allocator);
    _ = try receiver.append(allocator, .{ .tag = .empty });
    const header: Recipe = .{ .arity = 1, .root = record, .nodes = source.nodes.items, .words = source.words.items };
    const callback = try receiver.callable(allocator, header, 0);
    try receiver.view().validate(callback, 0, true);
    const argument = try receiver.append(allocator, .{ .tag = .authority, .a = 7, .b = 9 });
    const result = try receiver.invoke(allocator, callback, &.{argument});
    try std.testing.expectEqual(argument, try receiver.project(allocator, result, 1, .field));
    var remaining: usize = 65_536;
    try std.testing.expect(try receiver.callableArity(callback, 1, &remaining, 0));
    try std.testing.expectError(error.InvalidCapabilityContract, receiver.invoke(allocator, callback, &.{}));
    const body = receiver.nodes.items[callback].c;
    const sealed_input = receiver.words.items[receiver.nodes.items[body].a + 1];
    try std.testing.expectError(error.InvalidCapabilityContract, receiver.view().validate(sealed_input, 1, false));
    receiver.nodes.items[sealed_input].a = 1;
    try std.testing.expectError(error.InvalidCapabilityContract, receiver.view().validate(callback, 0, false));
    receiver.nodes.items[sealed_input].a = 0;
    receiver.nodes.items[sealed_input].tag = .parameter;
    try std.testing.expectError(error.InvalidCapabilityContract, receiver.view().validate(callback, 1, false));
    receiver.nodes.items[sealed_input].tag = .argument;
    const before = receiver.mark();
    receiver.limits.visits = receiver.visits;
    try std.testing.expectError(error.CapabilityAnalysisLimit, receiver.invoke(allocator, callback, &.{argument}));
    try std.testing.expectEqualDeep(before, receiver.mark());
}
test "owned callable recipes seal input binders and preserve exact projected results through all allocation failures" {
    try callableLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, callableLaw, .{});
}

fn canonicalSelectLaw(allocator: A) !void {
    const Declared = struct { kind: enum { global, local }, capability_parameters: @import("capability_flow.zig").Parameters };
    const declared = [_]Declared{ .{ .kind = .local, .capability_parameters = .{} }, .{ .kind = .global, .capability_parameters = .init(1, 1) }, .{ .kind = .global, .capability_parameters = .init(1, 1) } };
    // One pair of recipes, join(wrapped(captures []), wrapped(p0)) and
    // record{9: callable(p0 -> argument)}, numbered once as a live check and
    // once as its frozen interface numbered the shared nodes.
    var live_nodes = [_]Term{ .{ .tag = .empty }, .{ .tag = .parameter }, .{ .tag = .wrapped, .a = 1 }, .{ .tag = .argument }, .{ .tag = .captures }, .{ .tag = .wrapped, .a = 4 }, .{ .tag = .join, .a = 0, .b = 2 }, .{ .tag = .callable, .a = 1, .b = 1, .c = 3 }, .{ .tag = .record, .a = 2, .b = 2 } };
    var live_words = [_]u32{ 5, 2, 9, 7 };
    var live_roots = [_]Binding{ .{ .binding = 1, .root = 6 }, .{ .binding = 2, .root = 8 } };
    var frozen_nodes = [_]Term{ .{ .tag = .empty }, .{ .tag = .parameter }, .{ .tag = .captures }, .{ .tag = .argument }, .{ .tag = .callable, .a = 1, .b = 1, .c = 3 }, .{ .tag = .record, .a = 0, .b = 2 }, .{ .tag = .wrapped, .a = 2 }, .{ .tag = .wrapped, .a = 1 }, .{ .tag = .join, .a = 2, .b = 2 } };
    var frozen_words = [_]u32{ 9, 4, 6, 7 };
    var frozen_roots = [_]Binding{ .{ .binding = 1, .root = 8 }, .{ .binding = 2, .root = 5 } };
    const live: Collection = .{ .nodes = &live_nodes, .words = &live_words, .bindings = &live_roots };
    const frozen: Collection = .{ .nodes = &frozen_nodes, .words = &frozen_words, .bindings = &frozen_roots };
    var left = try live.select(allocator, &declared, null);
    defer left.deinit(allocator);
    var right = try frozen.select(allocator, &declared, null);
    defer right.deinit(allocator);
    try std.testing.expectEqualDeep(left, right);
    try left.validate(declared.len, 10);
    const published: View = .{ .nodes = left.nodes, .words = left.words };
    for (left.bindings, live_roots) |entry, original| {
        try std.testing.expect(try equivalent(published, entry.root, .{ .nodes = live.nodes, .words = live.words }, original.root));
    }
    // Selecting a published collection again is the identity.
    var again = try left.select(allocator, &declared, null);
    defer again.deinit(allocator);
    try std.testing.expectEqualDeep(left, again);
}
test "published capability collections do not depend on their producer's node numbering" {
    try canonicalSelectLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, canonicalSelectLaw, .{});
}
