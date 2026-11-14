//! Uniqueness of `:=` paths through storage (tasks/MEMORY_MODEL.md, rules 4
//! and 5). A path update that reaches storage writes in place, which is only
//! the successor semantics of `:=` when nothing else can observe the old
//! root. This pass proves that inside one body and rejects the rest with
//! `aliased_update`; no fact crosses a call.
//!
//! Facts belong to binding versions and follow evaluation order. A version is
//! unique after it is bound to a fresh allocation, stays unique across its own
//! `:=` updates, and stops being unique once the same version escapes: bound
//! to another name, captured, passed, placed in an aggregate, returned or
//! broken out, or read out as a storage-holding element or field. Branches
//! meet their arms through an undo trail; an arm that leaves the function
//! contributes nothing. Each loop body is first probed with its carries'
//! incoming facts, then checked once with the carries met with that probe's
//! backedges; nested loops are probed by a single pass, so a body is visited
//! once more per enclosing loop.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const storage_types = @import("storage_types.zig");
const storage_ops = @import("storage_ops.zig");
const body_recipe = @import("body_recipe.zig");
const Allocator = std.mem.Allocator;

/// `none`: something else may observe it. `shell`: its own storage is unique,
/// but storage held by its elements may be shared. `deep`: it and all storage
/// reachable inside it are unique. Larger values name record facts, whose
/// fields have facts of their own. `top` only seeds a meet.
const Fact = u32;
const none: Fact = 0;
const shell: Fact = 1;
const deep: Fact = 2;
const first_record: Fact = 3;
const top: Fact = std.math.maxInt(u32);

const Entry = struct { field: u32, fact: Fact };
/// A record's facts by field symbol, sorted; unlisted fields have `default`.
const Record = struct { default: Fact, start: u32, len: u32 };
const Change = struct { binding: core.BindingId, old: Fact };
/// An expression's result: the fact of a fresh value, or the version whose
/// storage it may alias. `exits` means control only leaves the function.
const Value = struct { fact: Fact = none, origin: core.BindingId = 0, exits: bool = false };
/// A loop being visited: its carries' continue facts, then their break facts,
/// at `start` in the shared `carried` buffer.
const LoopFrame = struct { id: core.Id, start: usize, len: usize };
const BlockFrame = struct { id: core.Id, fact: Fact = top, broken: bool = false };
const Rejection = struct { node: core.Id, span: core.Span };
/// A nominal being expanded, with whether each type argument holds storage.
const Expansion = struct { identity: T.NominalIdentity, arguments: [16]bool, len: usize };

pub const Error = Allocator.Error;

/// Appends one `aliased_update` diagnostic per rejected `:=` in `module`.
pub fn check(allocator: Allocator, module: *const core.Module, out: *std.ArrayList(core.Diagnostic)) Error!void {
    if (module.updates.len == 0) return;
    var analyzer: Analyzer = .{ .allocator = allocator, .m = module };
    defer analyzer.deinit();
    analyzer.facts = try allocator.alloc(Fact, module.bindings.len);
    @memset(analyzer.facts, none);
    for (module.bodies, 0..) |body, index| {
        if (index == 0 or body.root == 0) continue;
        try analyzer.function_roots.append(allocator, body.root);
        try analyzer.escape(try analyzer.visit(body.root));
        _ = analyzer.function_roots.pop();
    }
    const found = analyzer.rejections.items;
    std.mem.sortUnstable(Rejection, found, {}, struct {
        fn less(_: void, left: Rejection, right: Rejection) bool {
            return left.node < right.node;
        }
    }.less);
    var previous: core.Id = 0;
    for (found) |rejection| {
        if (rejection.node == previous) continue;
        previous = rejection.node;
        try out.append(allocator, .{ .code = .aliased_update, .span = rejection.span });
    }
}

const Analyzer = struct {
    allocator: Allocator,
    m: *const core.Module,
    facts: []Fact = &.{},
    trail: std.ArrayList(Change) = .empty,
    records: std.ArrayList(Record) = .empty,
    entries: std.ArrayList(Entry) = .empty,
    holds_cache: std.AutoHashMapUnmanaged(T.Id, bool) = .empty,
    nominal_index: std.AutoHashMapUnmanaged(T.NominalIdentity, u32) = .empty,
    expanding: std.ArrayList(Expansion) = .empty,
    loops: std.ArrayList(LoopFrame) = .empty,
    carried: std.ArrayList(Fact) = .empty,
    blocks: std.ArrayList(BlockFrame) = .empty,
    function_roots: std.ArrayList(core.Id) = .empty,
    rejections: std.ArrayList(Rejection) = .empty,
    children: std.ArrayList(core.Id) = .empty,
    /// While positive, loop bodies are only probed: rejections are dropped.
    probing: u32 = 0,

    fn deinit(self: *Analyzer) void {
        const a = self.allocator;
        a.free(self.facts);
        self.trail.deinit(a);
        self.records.deinit(a);
        self.entries.deinit(a);
        self.holds_cache.deinit(a);
        self.nominal_index.deinit(a);
        self.expanding.deinit(a);
        self.loops.deinit(a);
        self.carried.deinit(a);
        self.blocks.deinit(a);
        self.function_roots.deinit(a);
        self.rejections.deinit(a);
        self.children.deinit(a);
    }

    // ---- Facts -------------------------------------------------------------

    fn local(self: *const Analyzer, binding: core.BindingId) bool {
        return binding != 0 and binding < self.facts.len;
    }
    fn set(self: *Analyzer, binding: core.BindingId, fact: Fact) Error!void {
        if (!self.local(binding) or self.facts[binding] == fact) return;
        try self.trail.append(self.allocator, .{ .binding = binding, .old = self.facts[binding] });
        self.facts[binding] = fact;
    }
    fn kill(self: *Analyzer, binding: core.BindingId) Error!void {
        try self.set(binding, none);
    }
    fn escape(self: *Analyzer, value: Value) Error!void {
        if (value.origin != 0) try self.kill(value.origin);
    }
    fn undo(self: *Analyzer, mark: usize) void {
        while (self.trail.items.len > mark) {
            const change = self.trail.pop().?;
            self.facts[change.binding] = change.old;
        }
    }
    fn unique(fact: Fact) bool {
        return fact == shell or fact == deep;
    }
    fn record(self: *const Analyzer, fact: Fact) Record {
        return self.records.items[fact - first_record];
    }
    fn recordEntries(self: *const Analyzer, value: Record) []const Entry {
        return self.entries.items[value.start..][0..value.len];
    }
    fn field(self: *const Analyzer, fact: Fact, symbol: u32) Fact {
        if (fact < first_record) return if (fact == deep) deep else none;
        const value = self.record(fact);
        for (self.recordEntries(value)) |entry| if (entry.field == symbol) return entry.fact;
        return value.default;
    }
    /// A record fact from sorted entries; plain facts when no field differs.
    fn makeRecord(self: *Analyzer, default: Fact, sorted: []const Entry) Error!Fact {
        var differs = false;
        for (sorted) |entry| differs = differs or entry.fact != default;
        if (!differs) return default;
        const start: u32 = @intCast(self.entries.items.len);
        try self.entries.appendSlice(self.allocator, sorted);
        try self.records.append(self.allocator, .{ .default = default, .start = start, .len = @intCast(sorted.len) });
        return first_record + @as(Fact, @intCast(self.records.items.len - 1));
    }
    fn withField(self: *Analyzer, fact: Fact, symbol: u32, replacement: Fact) Error!Fact {
        var scratch: std.ArrayList(Entry) = .empty;
        defer scratch.deinit(self.allocator);
        var default: Fact = if (fact == deep) deep else none;
        if (fact >= first_record) {
            const value = self.record(fact);
            default = value.default;
            try scratch.appendSlice(self.allocator, self.recordEntries(value));
        }
        const found = for (scratch.items) |*entry| {
            if (entry.field == symbol) {
                entry.fact = replacement;
                break true;
            }
        } else false;
        if (!found) {
            try scratch.append(self.allocator, .{ .field = symbol, .fact = replacement });
            std.mem.sortUnstable(Entry, scratch.items, {}, entryLess);
        }
        return self.makeRecord(default, scratch.items);
    }
    fn entryLess(_: void, left: Entry, right: Entry) bool {
        return left.field < right.field;
    }
    fn meet(self: *Analyzer, left: Fact, right: Fact) Error!Fact {
        if (left == top) return right;
        if (right == top) return left;
        if (left == right) return left;
        if (left == none or right == none) return none;
        if (left < first_record and right < first_record) return @min(left, right);
        // A record meets `deep` as itself; a record never has a `shell`.
        if (left == deep) return right;
        if (right == deep) return left;
        if (left == shell or right == shell) return none;
        const l = self.record(left);
        const r = self.record(right);
        var merged: std.ArrayList(Entry) = .empty;
        defer merged.deinit(self.allocator);
        var i: usize = 0;
        var j: usize = 0;
        // Nested meets may append entries, so meet owned copies.
        const le = try self.allocator.dupe(Entry, self.recordEntries(l));
        defer self.allocator.free(le);
        const re = try self.allocator.dupe(Entry, self.recordEntries(r));
        defer self.allocator.free(re);
        while (i < le.len or j < re.len) {
            if (j == re.len or (i < le.len and le[i].field < re[j].field)) {
                try merged.append(self.allocator, .{ .field = le[i].field, .fact = try self.meet(le[i].fact, r.default) });
                i += 1;
            } else if (i == le.len or re[j].field < le[i].field) {
                try merged.append(self.allocator, .{ .field = re[j].field, .fact = try self.meet(l.default, re[j].fact) });
                j += 1;
            } else {
                try merged.append(self.allocator, .{ .field = le[i].field, .fact = try self.meet(le[i].fact, re[j].fact) });
                i += 1;
                j += 1;
            }
        }
        return self.makeRecord(try self.meet(l.default, r.default), merged.items);
    }
    fn same(self: *const Analyzer, left: Fact, right: Fact) bool {
        if (left == right) return true;
        if (left < first_record or right < first_record or left == top or right == top) return false;
        const l = self.record(left);
        const r = self.record(right);
        if (!self.same(l.default, r.default) or l.len != r.len) return false;
        for (self.recordEntries(l), self.recordEntries(r)) |a, b| if (a.field != b.field or !self.same(a.fact, b.fact)) return false;
        return true;
    }

    // ---- Types -------------------------------------------------------------

    /// Whether a value of `ty` can hold storage. Unknown shapes can.
    fn holds(self: *Analyzer, ty: T.Id) Error!bool {
        if (self.holds_cache.get(ty)) |known| return known;
        const result = try self.holdsIn(ty, &.{}, &.{}, 0);
        try self.holds_cache.put(self.allocator, ty, result);
        return result;
    }
    fn holdsIn(self: *Analyzer, ty: T.Id, variables: []const T.Id, arguments: []const bool, depth: usize) Error!bool {
        switch (ty) {
            T.unit, T.boolean, T.u32_type, T.f32_type, T.never => return false,
            else => {},
        }
        if (depth > 64 or ty >= self.m.types.nodes.len) return true;
        for (variables, arguments) |variable, argument| if (variable == ty) return argument;
        if (variables.len == 0) if (self.holds_cache.get(ty)) |known| return known;
        const n = self.m.types.node(ty);
        switch (n.tag) {
            .unit, .boolean, .u32, .f32, .never => return false,
            .array, .list, .cursor, .function => return true,
            .product => {
                for (self.m.types.list(.{ .start = n.a, .len = n.b })) |item| if (try self.holdsIn(item, variables, arguments, depth + 1)) return true;
                return false;
            },
            .record => {
                for (0..n.b) |index| if (try self.holdsIn(self.m.types.recordField(n, index).ty, variables, arguments, depth + 1)) return true;
                return false;
            },
            .nominal => {
                if (storage_types.identity(n.a, n.b) != null or n.a == std.math.maxInt(u32)) return true;
                const identity: T.NominalIdentity = .{ .unit = n.a, .decl = n.b };
                const index = try self.nominalIndex(identity) orelse return true;
                const nominal = self.m.nominal(index);
                if (nominal.is_opaque) return true;
                const own = self.m.types.list(nominal.variables);
                const given = self.m.types.nominalArguments(n);
                if (own.len != given.len or own.len > 16) return true;
                var bits: [16]bool = undefined;
                for (given, 0..) |argument, at| bits[at] = try self.holdsIn(argument, variables, arguments, depth + 1);
                // A recursive occurrence at the same arguments adds no storage
                // its first expansion lacks; one at other arguments might.
                for (self.expanding.items) |outer| if (outer.identity.unit == identity.unit and outer.identity.decl == identity.decl) {
                    return !std.mem.eql(bool, outer.arguments[0..outer.len], bits[0..own.len]);
                };
                try self.expanding.append(self.allocator, .{ .identity = identity, .arguments = bits, .len = own.len });
                defer _ = self.expanding.pop();
                for (self.m.nominalConstructors(index)) |constructor| {
                    const payload = self.m.constructor(constructor).payload;
                    if (payload != 0 and try self.holdsIn(payload, own, bits[0..own.len], depth + 1)) return true;
                }
                return false;
            },
            else => return true,
        }
    }
    fn nominalIndex(self: *Analyzer, identity: T.NominalIdentity) Error!?u32 {
        if (self.nominal_index.count() == 0) {
            for (self.m.nominals, 0..) |nominal, index| try self.nominal_index.put(self.allocator, nominal.identity, @intCast(index));
        }
        return self.nominal_index.get(identity);
    }
    fn element(self: *const Analyzer, ty: T.Id) ?T.Id {
        if (ty == 0 or ty >= self.m.types.nodes.len) return null;
        const n = self.m.types.node(ty);
        if (n.tag == .list) return n.a;
        return storage_types.readableElement(&self.m.types, ty);
    }
    fn elementHolds(self: *Analyzer, container: T.Id) Error!bool {
        return self.holds(self.element(container) orelse return true);
    }
    /// The fact of a fresh container of `ty` whose elements are fresh only
    /// when `elements_deep`.
    fn freshContainer(self: *Analyzer, ty: T.Id, elements_deep: bool) Error!Fact {
        return if (elements_deep or !try self.elementHolds(ty)) deep else shell;
    }

    // ---- Places ------------------------------------------------------------

    const Place = struct { binding: core.BindingId, fields: [8]u32 = undefined, len: usize = 0 };
    /// The local version a projection chain starts from, and its fields.
    fn place(self: *const Analyzer, id: core.Id) ?Place {
        var reverse: [8]u32 = undefined;
        var count: usize = 0;
        var cursor = id;
        while (true) {
            const n = self.m.node(cursor);
            switch (n.tag) {
                .reference => {
                    const ref = self.m.reference(cursor);
                    if (ref.unit != 0 and ref.unit != self.m.unit) return null;
                    var result: Place = .{ .binding = ref.binding, .len = count };
                    for (0..count) |at| result.fields[at] = reverse[count - 1 - at];
                    return result;
                },
                .project => {
                    if (count == reverse.len) return null;
                    reverse[count] = self.m.projection(n.b).field;
                    count += 1;
                    cursor = n.a;
                },
                else => return null,
            }
        }
    }
    /// `fact` with the storage at `fields` no longer known to own its
    /// elements: a store or push put a value there that may be shared.
    fn weaken(self: *Analyzer, fact: Fact, fields: []const u32) Error!Fact {
        if (fields.len == 0) return if (fact == deep) shell else if (fact >= first_record) none else fact;
        return self.withField(fact, fields[0], try self.weaken(self.field(fact, fields[0]), fields[1..]));
    }
    /// After a value that may be shared is stored into the storage that `id`
    /// and the field steps of `selectors` before their first index select.
    fn sharedInto(self: *Analyzer, id: core.Id, selectors: []const core.UpdateStep) Error!void {
        var target = self.place(id) orelse return;
        if (!self.local(target.binding)) return;
        for (selectors) |step| {
            if (step.kind == .index) break;
            if (target.len == target.fields.len) return self.kill(target.binding);
            target.fields[target.len] = self.m.projection(step.projection).field;
            target.len += 1;
        }
        try self.set(target.binding, try self.weaken(self.facts[target.binding], target.fields[0..target.len]));
    }

    // ---- Visits ------------------------------------------------------------

    fn visitEscaping(self: *Analyzer, id: core.Id) Error!Value {
        const value = try self.visit(id);
        try self.escape(value);
        return value;
    }
    fn visitChildren(self: *Analyzer, id: core.Id) Error!bool {
        const start = self.children.items.len;
        defer self.children.shrinkRetainingCapacity(start);
        body_recipe.appendChildren(&ChildList{ .owner = self }, self.allocator, self.m, id, false) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.PlanLimit => unreachable,
        };
        var exits = false;
        var at = start;
        while (at < self.children.items.len) : (at += 1) {
            const value = try self.visitEscaping(self.children.items[at]);
            exits = exits or value.exits;
        }
        return exits;
    }
    const ChildList = struct {
        owner: *Analyzer,
        pub fn append(list: *const ChildList, allocator: Allocator, id: core.Id) error{ OutOfMemory, PlanLimit }!void {
            try list.owner.children.append(allocator, id);
        }
        pub fn appendSlice(list: *const ChildList, allocator: Allocator, ids: []const core.Id) error{ OutOfMemory, PlanLimit }!void {
            try list.owner.children.appendSlice(allocator, ids);
        }
    };

    fn visit(self: *Analyzer, id: core.Id) Error!Value {
        if (id == 0 or id >= self.m.nodes.len) return .{};
        const n = self.m.node(id);
        switch (n.tag) {
            .constant, .constructor_function, .primitive_function, .type_constructor, .operation_value, .invalid => return .{},
            .panic => return .{ .exits = true },
            .reference => {
                const ref = self.m.reference(id);
                if (ref.unit != 0 and ref.unit != self.m.unit) return .{};
                return .{ .origin = if (self.local(ref.binding)) ref.binding else 0 };
            },
            .suite => {
                var exits = false;
                for (self.m.children(id)) |child| exits = (try self.visit(child)).exits or exits;
                return .{ .exits = exits };
            },
            .block => return self.block(id),
            .bind => {
                const value = self.m.node(n.b);
                if (value.tag == .update and !self.m.updateInfo(n.b).store) return self.update(n.b, n.a);
                const result = if (value.tag == .array_op) try self.arrayOp(n.b, true) else try self.visit(n.b);
                try self.escape(result);
                try self.set(n.a, if (result.origin != 0) none else result.fact);
                return .{ .exits = result.exits };
            },
            .update => return self.update(id, 0),
            .return_ => {
                const result = try self.visitEscaping(n.a);
                const fact = if (result.origin != 0) none else result.fact;
                if (self.function_roots.items.len != 0 and n.b == self.function_roots.items[self.function_roots.items.len - 1]) return .{ .exits = true };
                var at = self.blocks.items.len;
                while (at != 0) {
                    at -= 1;
                    const frame = &self.blocks.items[at];
                    if (frame.id != n.b) continue;
                    frame.fact = try self.meet(frame.fact, fact);
                    frame.broken = true;
                    break;
                }
                return .{};
            },
            .if_value, .if_stmt => return self.conditional(id),
            .match => return self.match(id),
            .pattern_bind => {
                _ = try self.visitEscaping(n.b);
                if (n.c != 0) {
                    const mark = self.trail.items.len;
                    if ((try self.visit(n.c)).exits) self.undo(mark);
                }
                return .{};
            },
            .loop => return self.loop(id),
            .break_ => return self.breakNode(id),
            .closure => {
                for (self.m.closureCaptures(id)) |captured| try self.kill(captured);
                const body = self.m.closure(id).body;
                try self.function_roots.append(self.allocator, body);
                defer _ = self.function_roots.pop();
                try self.escape(try self.visit(body));
                return .{};
            },
            .project => {
                if (try self.memberCopy(id)) |fact| {
                    // `values.copy` is the prelude's spelling of `@storage.copy`.
                    const value = try self.visit(n.a);
                    if (try self.elementHolds(n.ty)) try self.escape(value);
                    return .{ .fact = fact, .exits = value.exits };
                }
                const value = try self.visit(n.a);
                if (!try self.holds(n.ty)) return .{ .exits = value.exits };
                return .{ .origin = value.origin, .exits = value.exits };
            },
            .array => {
                var elements_deep = true;
                var exits = false;
                for (self.m.children(id)) |child| {
                    const value = try self.visitEscaping(child);
                    exits = exits or value.exits;
                    elements_deep = elements_deep and value.origin == 0 and value.fact == deep;
                }
                return .{ .fact = try self.freshContainer(n.ty, elements_deep), .exits = exits };
            },
            .record => return self.recordLiteral(id),
            .construct => {
                const payload = try self.visitEscaping(n.b);
                const literal = n.b != 0 and self.m.node(n.b).tag == .record;
                return .{ .fact = if (literal and payload.origin == 0) payload.fact else none, .exits = payload.exits };
            },
            .array_op => return self.arrayOp(id, false),
            .storage => return self.storageOp(id),
            else => return .{ .exits = try self.visitChildren(id) },
        }
    }

    /// The fresh fact of `values.copy` on an array, which only the prelude
    /// can define; null for every other projection.
    fn memberCopy(self: *Analyzer, id: core.Id) Error!?Fact {
        const n = self.m.node(id);
        const spelling = self.m.fieldSpelling(self.m.projection(n.b).field) orelse return null;
        if (!std.mem.eql(u8, spelling, "copy")) return null;
        if (storage_types.arrayElement(&self.m.types, self.m.typeOf(n.a)) == null or storage_types.arrayElement(&self.m.types, n.ty) == null) return null;
        return try self.freshContainer(n.ty, false);
    }
    fn block(self: *Analyzer, id: core.Id) Error!Value {
        try self.blocks.append(self.allocator, .{ .id = id });
        var exits = false;
        for (self.m.children(id)) |child| exits = (try self.visit(child)).exits or exits;
        const frame = self.blocks.pop().?;
        if (frame.broken) return .{ .fact = if (frame.fact == top) none else frame.fact };
        return .{ .exits = exits };
    }

    fn recordLiteral(self: *Analyzer, id: core.Id) Error!Value {
        const n = self.m.node(id);
        const children = self.m.children(id);
        const shape = if (n.ty != 0 and n.ty < self.m.types.nodes.len) self.m.types.node(n.ty) else T.Node{ .tag = .absent };
        var scratch: std.ArrayList(Entry) = .empty;
        defer scratch.deinit(self.allocator);
        var exits = false;
        for (children, 0..) |child, index| {
            const value = try self.visitEscaping(child);
            exits = exits or value.exits;
            if (shape.tag != .record) continue;
            const destination = self.m.recordDestinations(id)[index];
            if (destination >= shape.b) continue;
            const declared = self.m.types.recordField(shape, destination);
            if (!try self.holds(declared.ty)) continue;
            try scratch.append(self.allocator, .{ .field = declared.name, .fact = if (value.origin != 0) none else value.fact });
        }
        if (shape.tag != .record) return .{ .exits = exits };
        std.mem.sortUnstable(Entry, scratch.items, {}, entryLess);
        return .{ .fact = try self.makeRecord(none, scratch.items), .exits = exits };
    }

    /// A `:=` path update bound to `successor`, or a store when the update
    /// is flagged as one (then `successor` is zero).
    fn update(self: *Analyzer, id: core.Id, successor: core.BindingId) Error!Value {
        const info = self.m.updateInfo(id);
        const selectors = self.m.updateSelectors(id);
        const root = try self.visit(info.root);
        for (selectors) |step| if (step.kind == .index) {
            _ = try self.visitEscaping(step.index);
        };
        const value = try self.visitEscaping(info.value);
        const replacement = if (value.origin != 0) none else value.fact;
        var through_storage = false;
        for (selectors) |step| through_storage = through_storage or step.kind == .index;
        const leaf = if (selectors.len != 0) selectors[selectors.len - 1].result_type else self.m.typeOf(info.value);
        const shared = try self.holds(leaf) and replacement != deep;
        if (info.store) {
            if (shared) try self.sharedInto(info.root, selectors);
            return .{};
        }
        const old = if (self.local(root.origin)) self.facts[root.origin] else none;
        if (!through_storage) {
            // A value path rebuilds records; the replaced field takes the
            // value's fact and every other field keeps its storage.
            var fields: std.ArrayList(u32) = .empty;
            defer fields.deinit(self.allocator);
            if (selectors.len != 0) {
                for (selectors) |step| try fields.append(self.allocator, self.m.projection(step.projection).field);
            } else for (self.m.updatePath(id)) |projection| try fields.append(self.allocator, self.m.projection(projection).field);
            try self.set(successor, try self.replace(old, fields.items, replacement));
            return .{ .exits = value.exits };
        }
        if (!try self.accepts(old, selectors) and self.probing == 0) try self.rejections.append(self.allocator, .{ .node = id, .span = self.m.span(id) });
        var prefix: std.ArrayList(u32) = .empty;
        defer prefix.deinit(self.allocator);
        for (selectors) |step| {
            if (step.kind == .index) break;
            try prefix.append(self.allocator, self.m.projection(step.projection).field);
        }
        try self.set(successor, if (shared) try self.weaken(old, prefix.items) else old);
        return .{ .exits = value.exits };
    }
    fn replace(self: *Analyzer, fact: Fact, fields: []const u32, replacement: Fact) Error!Fact {
        if (fields.len == 0) return replacement;
        return self.withField(fact, fields[0], try self.replace(self.field(fact, fields[0]), fields[1..], replacement));
    }
    /// Every storage the path writes through must be unique.
    fn accepts(self: *Analyzer, fact: Fact, selectors: []const core.UpdateStep) Error!bool {
        var current = fact;
        for (selectors) |step| switch (step.kind) {
            .field => current = self.field(current, self.m.projection(step.projection).field),
            .index => {
                if (!unique(current)) return false;
                current = if (current == deep) deep else none;
            },
        };
        return true;
    }

    /// `bound`: the operation is a binding's whole value, where the backend
    /// appends in place to an input named once.
    fn arrayOp(self: *Analyzer, id: core.Id, bound: bool) Error!Value {
        const n = self.m.node(id);
        const children = self.m.children(id);
        const operation = self.m.arrayOperation(id);
        switch (operation) {
            .length => {
                const container = try self.visit(children[0]);
                return .{ .exits = container.exits };
            },
            .get, .simd_load => {
                const container = try self.visit(children[0]);
                const index = try self.visitEscaping(children[1]);
                const exits = container.exits or index.exits;
                if (operation == .get and try self.holds(n.ty)) return .{ .origin = container.origin, .exits = exits };
                return .{ .exits = exits };
            },
            .identity => return self.visit(children[0]),
            .simd_store => {
                // Writes four elements in place and returns the same storage.
                const container = try self.visit(children[0]);
                for (children[1..]) |child| _ = try self.visitEscaping(child);
                return .{ .origin = container.origin, .exits = container.exits };
            },
            .set, .concat, .slice, .flatten, .convert, .prepend, .append => {
                // A new container whose elements are copies of the inputs'.
                const shares = try self.elementHolds(n.ty);
                var exits = false;
                var inputs_unique = true;
                for (children, 0..) |child, position| {
                    const container_input = switch (operation) {
                        .set, .slice, .flatten, .convert, .prepend, .append => position == 0,
                        .concat => true,
                        else => false,
                    };
                    const value = try self.visit(child);
                    exits = exits or value.exits;
                    if (!container_input or shares) try self.escape(value);
                    // A bound append to a reference used once grows that
                    // input in place, so the result shares its storage.
                    if (bound and operation == .append and position == 0 and self.m.node(child).tag == .reference)
                        inputs_unique = self.local(value.origin) and unique(self.facts[value.origin]);
                }
                if (!inputs_unique) return .{ .exits = exits };
                return .{ .fact = try self.freshContainer(n.ty, false), .exits = exits };
            },
            .fill, .generate => {
                var exits = false;
                for (children) |child| exits = (try self.visitEscaping(child)).exits or exits;
                return .{ .fact = try self.freshContainer(n.ty, false), .exits = exits };
            },
            .cursor, .cursor_has, .cursor_value, .cursor_advance => return .{ .exits = try self.visitChildren(id) },
        }
    }

    fn storageOp(self: *Analyzer, id: core.Id) Error!Value {
        const n = self.m.node(id);
        const children = self.m.children(id);
        const operation: storage_ops.Op = std.enums.fromInt(storage_ops.Op, n.c) orelse return .{ .exits = try self.visitChildren(id) };
        switch (operation) {
            .length, .truncate, .reserve, .pop => {
                const container = try self.visit(children[0]);
                var exits = container.exits;
                for (children[1..]) |child| exits = (try self.visitEscaping(child)).exits or exits;
                return .{ .exits = exits };
            },
            .read => {
                const container = try self.visit(children[0]);
                const index = try self.visitEscaping(children[1]);
                const exits = container.exits or index.exits;
                if (try self.holds(n.ty)) return .{ .origin = container.origin, .exits = exits };
                return .{ .exits = exits };
            },
            .push => {
                const container = try self.visit(children[0]);
                const value = try self.visitEscaping(children[1]);
                if (try self.elementHolds(self.m.typeOf(children[0])) and (value.origin != 0 or value.fact != deep)) try self.sharedInto(children[0], &.{});
                return .{ .exits = container.exits or value.exits };
            },
            .copy => {
                const container = try self.visit(children[0]);
                if (try self.elementHolds(n.ty)) try self.escape(container);
                return .{ .fact = try self.freshContainer(n.ty, false), .exits = container.exits };
            },
            .freeze => {
                const container = try self.visit(children[0]);
                return .{ .origin = container.origin, .exits = container.exits };
            },
            // References, views and links alias the storage they name.
            .ref, .at, .link, .view, .load => return .{ .exits = try self.visitChildren(id) },
        }
    }

    fn conditional(self: *Analyzer, id: core.Id) Error!Value {
        const n = self.m.node(id);
        const condition = try self.visitEscaping(n.a);
        var join: Join = .{ .base = self.trail.items.len, .merges = self.m.branchMerges(id) };
        defer join.deinit(self.allocator);
        try join.arm(self, 0, try self.visit(n.b));
        try join.arm(self, 1, if (n.c != 0) try self.visit(n.c) else .{});
        const value = try join.finish(self);
        return .{ .fact = if (n.tag == .if_value) value.fact else none, .exits = condition.exits or value.exits };
    }

    fn match(self: *Analyzer, id: core.Id) Error!Value {
        const info = self.m.matchInfo(id);
        var exits = false;
        for (self.m.matchInputs(id)) |input| exits = (try self.visitEscaping(input)).exits or exits;
        var join: Join = .{ .base = self.trail.items.len, .merges = self.m.branchMerges(id) };
        defer join.deinit(self.allocator);
        for (self.m.matchArms(id), 0..) |arm, index| {
            var guard_exits = false;
            if (arm.guard != 0) guard_exits = (try self.visitEscaping(arm.guard)).exits;
            var body = if (arm.body != 0) try self.visit(arm.body) else Value{};
            body.exits = body.exits or guard_exits;
            try join.arm(self, index, body);
        }
        const value = try join.finish(self);
        return .{ .fact = if (info.statement) none else value.fact, .exits = exits or value.exits };
    }

    fn loop(self: *Analyzer, id: core.Id) Error!Value {
        const info = self.m.loopInfo(id);
        const carries = self.m.loopCarries(id);
        var exits = false;
        var iterated: core.BindingId = 0;
        switch (info.kind) {
            .forever => {},
            .range => {
                exits = (try self.visitEscaping(info.first)).exits or exits;
                exits = (try self.visitEscaping(info.end)).exits or exits;
            },
            .array => {
                // The pattern binds elements, so storage-holding ones alias.
                // The loop reads its source throughout, so a carry that
                // starts as the source is observed by every iteration.
                const source = try self.visit(info.first);
                exits = source.exits;
                if (try self.elementHolds(self.m.typeOf(info.first))) try self.escape(source) else iterated = source.origin;
            },
        }
        const incoming = try self.allocator.alloc(Fact, carries.len);
        defer self.allocator.free(incoming);
        for (carries, incoming) |carry, *fact| fact.* = if (self.local(carry.incoming) and carry.incoming != iterated) self.facts[carry.incoming] else none;
        const assumed = try self.allocator.dupe(Fact, incoming);
        defer self.allocator.free(assumed);
        const result = try self.allocator.alloc(Fact, carries.len);
        defer self.allocator.free(result);
        const outgoing = try self.allocator.alloc(Fact, carries.len);
        defer self.allocator.free(outgoing);
        if (self.probing != 0) {
            // Inside a probe: one optimistic pass approximates the carries.
            try self.loopPass(id, carries, assumed, result, outgoing);
        } else {
            self.probing += 1;
            const mark = self.trail.items.len;
            try self.loopPass(id, carries, assumed, result, outgoing);
            self.undo(mark);
            self.probing -= 1;
            for (assumed, incoming, result) |*fact, before, after| fact.* = try self.meet(before, after);
            var attempt: usize = 0;
            while (true) : (attempt += 1) {
                const checked = self.trail.items.len;
                const rejected = self.rejections.items.len;
                try self.loopPass(id, carries, assumed, result, outgoing);
                var stable = true;
                for (assumed, incoming, result) |*fact, before, after| {
                    const next = try self.meet(fact.*, try self.meet(before, after));
                    if (!self.same(next, fact.*)) stable = false;
                    fact.* = if (attempt >= 2) none else next;
                }
                if (stable) break;
                // A probe that underestimated the carries: check again.
                self.undo(checked);
                self.rejections.shrinkRetainingCapacity(rejected);
            }
        }
        for (carries, assumed, outgoing) |carry, fact, broken| try self.set(carry.outgoing, try self.meet(fact, broken));
        return .{ .exits = exits or (info.kind == .forever and !info.can_exit) };
    }
    /// One pass over a loop body with its carries at `assumed`. `result`
    /// receives the facts reaching the next iteration, `outgoing` those
    /// carried out by breaks.
    fn loopPass(self: *Analyzer, id: core.Id, carries: []const core.LoopCarry, assumed: []const Fact, result: []Fact, outgoing: []Fact) Error!void {
        const info = self.m.loopInfo(id);
        for (carries, assumed) |carry, fact| try self.set(carry.iteration, fact);
        const start = self.carried.items.len;
        defer self.carried.shrinkRetainingCapacity(start);
        try self.carried.appendNTimes(self.allocator, top, carries.len * 2);
        try self.loops.append(self.allocator, .{ .id = id, .start = start, .len = carries.len });
        const body = self.visit(info.body) catch |err| {
            _ = self.loops.pop();
            return err;
        };
        _ = self.loops.pop();
        const continues = self.carried.items[start..][0..carries.len];
        const breaks = self.carried.items[start + carries.len ..][0..carries.len];
        for (carries, continues, breaks, result, outgoing) |carry, continued, broken, *next, *out| {
            const backedge = if (body.exits) top else if (self.local(carry.backedge)) self.facts[carry.backedge] else none;
            next.* = try self.meet(backedge, continued);
            out.* = broken;
        }
    }
    fn breakNode(self: *Analyzer, id: core.Id) Error!Value {
        const n = self.m.node(id);
        const values = self.m.breakValues(id);
        var at = self.loops.items.len;
        const frame: ?LoopFrame = while (at != 0) {
            at -= 1;
            if (self.loops.items[at].id == n.a) break self.loops.items[at];
        } else null;
        for (values, 0..) |child, position| {
            // A carried version moves to the loop's next iteration or exit;
            // that is not an alias.
            const value = try self.visit(child);
            var fact = value.fact;
            if (self.m.node(child).tag == .reference and value.origin != 0) {
                fact = self.facts[value.origin];
            } else {
                try self.escape(value);
                if (value.origin != 0) fact = none;
            }
            const target = frame orelse continue;
            if (position >= target.len) continue;
            const slot = target.start + position + (if (n.op == .continue_) 0 else target.len);
            self.carried.items[slot] = try self.meet(self.carried.items[slot], fact);
        }
        return .{};
    }
};

/// The meet of a branch's arms. Each arm runs from the same trail mark; an
/// arm that leaves the function contributes nothing.
const Join = struct {
    base: usize,
    merges: []const core.Merge,
    falls: usize = 0,
    value: Fact = top,
    exits: bool = true,
    changed: std.AutoHashMapUnmanaged(core.BindingId, Changed) = .empty,
    merged: std.ArrayList(Fact) = .empty,
    const Changed = struct { fact: Fact, arms: usize, last: usize };

    fn deinit(self: *Join, allocator: Allocator) void {
        self.changed.deinit(allocator);
        self.merged.deinit(allocator);
    }
    fn arm(self: *Join, analyzer: *Analyzer, index: usize, result: Value) Error!void {
        const a = analyzer.allocator;
        if (self.merged.items.len == 0) {
            try self.merged.appendNTimes(a, top, self.merges.len);
        }
        if (!result.exits) {
            try analyzer.escape(result);
            self.exits = false;
            self.falls += 1;
            self.value = try analyzer.meet(self.value, if (result.origin != 0) none else result.fact);
            if (index < 2) for (self.merges, self.merged.items) |merge, *slot| {
                const binding = if (index == 0) merge.then_binding else merge.else_binding;
                slot.* = try analyzer.meet(slot.*, if (analyzer.local(binding)) analyzer.facts[binding] else none);
            };
            for (analyzer.trail.items[self.base..]) |change| {
                const entry = try self.changed.getOrPut(a, change.binding);
                if (!entry.found_existing) {
                    entry.value_ptr.* = .{ .fact = analyzer.facts[change.binding], .arms = 1, .last = index };
                } else if (entry.value_ptr.last != index) {
                    entry.value_ptr.fact = try analyzer.meet(entry.value_ptr.fact, analyzer.facts[change.binding]);
                    entry.value_ptr.arms += 1;
                    entry.value_ptr.last = index;
                }
            }
        }
        analyzer.undo(self.base);
    }
    fn finish(self: *Join, analyzer: *Analyzer) Error!Value {
        var it = self.changed.iterator();
        while (it.next()) |entry| {
            var fact = entry.value_ptr.fact;
            // An arm that left this binding alone carries the base fact.
            if (entry.value_ptr.arms < self.falls) fact = try analyzer.meet(fact, analyzer.facts[entry.key_ptr.*]);
            try analyzer.set(entry.key_ptr.*, fact);
        }
        for (self.merges, 0..) |merge, index| {
            const fact = if (index < self.merged.items.len and self.merged.items[index] != top) self.merged.items[index] else none;
            try analyzer.set(merge.result, fact);
        }
        return .{ .fact = if (self.value == top) none else self.value, .exits = self.exits };
    }
};
