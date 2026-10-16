//! Read-only lifetime analysis of executable Core. Values, mutable locations and
//! call edges stay distinct; a scalar result does not erase a store or a sink.
const std = @import("std");
const C = @import("core.zig");
const T = @import("types.zig");
const A = std.mem.Allocator;
const E = @import("../eval/type_evidence.zig");
pub const Id = u32;
pub const Error = A.Error || error{ InvalidArtifact, LifetimeEscape, AnalysisLimit, Unsupported };
pub const Site = struct { unit: u32 = 0, binding: u32 = 0, node: C.Id = 0 };
pub const TypeOrigin = struct { unit: u32, ty: T.Id };
pub const Kind = enum { scalar, unknown, capability, product, record, wrapper, selection, callable, memo, operation, provider, state_provider, cell, scope, activation, nominal, event, external };
pub const Node = struct { site: Site, context: u32 = 0, invocation: ?u32 = null, closure: ?u32 = null, kind: Kind, owner: Id, depth: u32, field: u32 = 0, contents: Id = 0, first_edge: ?u32 = null, ready: bool = false, nominal: T.NominalIdentity = .{ .unit = 0, .decl = 0 }, target: ?Site = null, signature: ?TypeOrigin = null, mappings: C.List = .{}, actual_mappings: C.List = .{} };
pub const EdgeKind = enum { value, capture, store, result, call };
pub const Edge = struct { from: Id, to: Id, kind: EdgeKind, field: u32 = 0, next: ?u32 = null };
pub const Invocation = struct { parent: ?u32, caller: Site, callable: Id };
pub const Boundary = struct { site: Site, owner: Id, result: Id };
pub const Report = struct {
    nodes: []Node,
    edges: []Edge,
    evidence: E.Store,
    mappings: []E.Mapping,
    boundaries: []Boundary,
    invocations: []Invocation,
    /// Unknown executable edges prevent this report certifying confinement.
    complete: bool,
    work: usize,
    pub fn deinit(self: *Report, a: A) void {
        self.evidence.deinit();
        a.free(self.mappings);
        a.free(self.nodes);
        a.free(self.edges);
        a.free(self.boundaries);
        a.free(self.invocations);
        self.* = undefined;
    }
};
const Entry = struct { binding: u32, value: Id, depth: u32 };
const Environment = struct {
    entries: [256]Entry = undefined,
    len: usize = 0,
    types: [64]E.Mapping = undefined,
    type_len: usize = 0,
    fn get(self: *const Environment, binding: u32, remaining: *usize) Error!?Entry {
        var index = self.len;
        while (index != 0) {
            if (remaining.* == 0) return error.AnalysisLimit;
            remaining.* -= 1;
            index -= 1;
            if (self.entries[index].binding == binding) return self.entries[index];
        }
        return null;
    }
    fn bind(self: *Environment, binding: u32, value: Id, depth: u32) Error!void {
        if (binding == 0) return;
        if (self.len == self.entries.len) return error.AnalysisLimit;
        self.entries[self.len] = .{ .binding = binding, .value = value, .depth = depth };
        self.len += 1;
    }
};
const ActiveCall = struct { module: *const C.Module, body: C.Id, parent: ?*const ActiveCall };
const Callable = struct { value: Id, module: *const C.Module, binding: u32, body: C.Id, parameters: []const C.Parameter, environment: Environment, arguments: [16]Id = undefined, count: usize = 0, runtime: bool = false, memo_state: enum { pending, forcing, cached } = .pending, cached: Id = 0 };
const Operation = struct { value: Id, module: *const C.Module, metadata: C.OperationValue, receiver: Id, arguments: [16]E.Id = undefined, argument_count: usize = 0 };
const Provider = struct { read: Id, write: Id = 0, initial: Id, callback: Id = 0 };
const Frame = struct { read: Id, write: Id, cell: Id, depth: u32, callback: Id, outer: usize };
const Exit = struct { module: *const C.Module, target: C.Id, value: Id };
const Control = struct { module: *const C.Module, target: C.Id, depth: u32 };
const MemoSnapshot = struct { state: @FieldType(Callable, "memo_state"), value: Id };
const Locations = struct {
    before: []Id,
    joined: []Id,
    memos: []MemoSnapshot,
    joined_memos: []MemoSnapshot,
    started: bool = false,
    fn init(scan: *Scan) Error!Locations {
        if (scan.nodes.items.len > scan.remaining) return error.AnalysisLimit;
        scan.remaining -= scan.nodes.items.len;
        if (scan.callables.items.len > scan.remaining) return error.AnalysisLimit;
        scan.remaining -= scan.callables.items.len;
        const before = try scan.a.alloc(Id, scan.nodes.items.len);
        errdefer scan.a.free(before);
        const joined = try scan.a.alloc(Id, before.len);
        errdefer scan.a.free(joined);
        const memos = try scan.a.alloc(MemoSnapshot, scan.callables.items.len);
        errdefer scan.a.free(memos);
        const joined_memos = try scan.a.alloc(MemoSnapshot, memos.len);
        for (scan.nodes.items, before) |value_, *slot| slot.* = value_.contents;
        for (scan.callables.items, memos) |callable, *slot| slot.* = .{ .state = callable.memo_state, .value = callable.cached };
        return .{ .before = before, .joined = joined, .memos = memos, .joined_memos = joined_memos };
    }
    fn deinit(self: Locations, a: A) void {
        a.free(self.before);
        a.free(self.joined);
        a.free(self.memos);
        a.free(self.joined_memos);
    }
    fn reset(self: Locations, scan: *Scan) Error!void {
        for (scan.nodes.items[0..self.before.len], self.before) |*value_, slot| {
            try scan.step(0);
            value_.contents = slot;
        }
        for (scan.callables.items[0..self.memos.len], self.memos) |*callable, saved| {
            try scan.step(0);
            callable.memo_state = saved.state;
            callable.cached = saved.value;
            scan.nodes.items[callable.value].ready = saved.state == .cached;
        }
    }
    fn collect(self: *Locations, scan: *Scan, module: *const C.Module, source: C.Id) Error!void {
        for (0..self.before.len) |index| {
            try scan.step(0);
            const actual = scan.nodes.items[index].contents;
            if (!self.started or self.joined[index] == actual) self.joined[index] = actual else self.joined[index] = try scan.aggregate(module, source, .selection, &.{ self.joined[index], actual });
        }
        for (scan.callables.items[0..self.memos.len], 0..) |callable, index| {
            try scan.step(0);
            const actual: MemoSnapshot = .{ .state = callable.memo_state, .value = callable.cached };
            if (!self.started) self.joined_memos[index] = actual else {
                if (self.joined_memos[index].state != actual.state) return error.Unsupported;
                if (actual.state == .cached) self.joined_memos[index].value = self.joined[callable.value];
            }
        }
        self.started = true;
    }
    fn finish(self: Locations, scan: *Scan) Error!void {
        if (!self.started) return;
        for (scan.nodes.items[0..self.joined.len], self.joined) |*value_, slot| {
            try scan.step(0);
            value_.contents = slot;
        }
        for (scan.callables.items[0..self.joined_memos.len], self.joined_memos) |*callable, saved| {
            try scan.step(0);
            callable.memo_state = saved.state;
            callable.cached = saved.value;
            scan.nodes.items[callable.value].ready = saved.state == .cached;
        }
    }
};
const Scan = struct {
    a: A,
    module: *const C.Module,
    evidence: E.Store,
    evidence_transferred: bool = false,
    type_mappings: std.ArrayList(E.Mapping) = .empty,
    owners: []const *const C.Module,
    nodes: std.ArrayList(Node) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    boundaries: std.ArrayList(Boundary) = .empty,
    invocations: std.ArrayList(Invocation) = .empty,
    context: u32 = 0,
    callables: std.ArrayList(Callable) = .empty,
    operations: std.ArrayList(Operation) = .empty,
    providers: std.ArrayList(struct { value: Id, provider: Provider }) = .empty,
    frames: std.ArrayList(Frame) = .empty,
    exits: std.ArrayList(Exit) = .empty,
    controls: std.ArrayList(Control) = .empty,
    remaining: usize = 65_536,
    owner: Id = 0,
    scope_depth: u32 = 0,
    binding: u32 = 0,
    complete: bool = true,
    scope_validation: bool = false,
    checked_owners: std.ArrayList(*const C.Module) = .empty,
    active_calls: ?*const ActiveCall = null,
    fn deinit(self: *Scan) void {
        if (!self.evidence_transferred) self.evidence.deinit();
        self.type_mappings.deinit(self.a);
        self.nodes.deinit(self.a);
        self.edges.deinit(self.a);
        self.boundaries.deinit(self.a);
        self.callables.deinit(self.a);
        self.invocations.deinit(self.a);
        self.operations.deinit(self.a);
        self.providers.deinit(self.a);
        self.frames.deinit(self.a);
        self.exits.deinit(self.a);
        self.controls.deinit(self.a);
        self.checked_owners.deinit(self.a);
    }
    fn step(self: *Scan, depth: usize) Error!void {
        if (self.remaining == 0 or depth >= 128) return error.AnalysisLimit;
        self.remaining -= 1;
    }
    fn site(self: *const Scan, module: *const C.Module, source: C.Id) Site {
        return .{ .unit = module.unit, .binding = self.binding, .node = source };
    }
    fn value(self: *Scan, module: *const C.Module, source: C.Id, kind: Kind) Error!Id {
        try self.step(0);
        if (self.nodes.items.len >= 4096) return error.AnalysisLimit;
        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(self.a, .{ .site = self.site(module, source), .context = self.context, .kind = kind, .owner = self.owner, .depth = self.scope_depth });
        return id;
    }
    fn mappings(self: *Scan, values: []const E.Mapping) Error!C.List {
        try self.step(0);
        if (values.len > self.remaining or self.type_mappings.items.len > 65_536 or values.len > 65_536 - self.type_mappings.items.len) return error.AnalysisLimit;
        self.remaining -= values.len;
        const start: u32 = @intCast(self.type_mappings.items.len);
        try self.type_mappings.appendSlice(self.a, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    fn edge(self: *Scan, from: Id, to: Id, kind: EdgeKind, field: u32) Error!void {
        try self.step(0);
        if (from >= self.nodes.items.len or to >= self.nodes.items.len) return error.InvalidArtifact;
        if (self.edges.items.len >= 65_536) return error.AnalysisLimit;
        const index: u32 = @intCast(self.edges.items.len);
        try self.edges.append(self.a, .{ .from = from, .to = to, .kind = kind, .field = field, .next = self.nodes.items[from].first_edge });
        self.nodes.items[from].first_edge = index;
    }
    fn ownerModule(self: *Scan, current: *const C.Module, unit: u32) Error!*const C.Module {
        if (unit == 0 or unit == current.unit) return current;
        var found: ?*const C.Module = null;
        for (self.owners) |candidate| {
            try self.step(0);
            if (candidate.unit != unit) continue;
            if (found) |prior| if (prior != candidate) return error.InvalidArtifact;
            found = candidate;
        }
        const selected = found orelse return error.Unsupported;
        for (self.checked_owners.items) |prior| {
            try self.step(0);
            if (prior == selected) return selected;
        }
        try @import("frozen_core_validation.zig").validateBounds(selected, .{ .units = self.owners });
        try self.checked_owners.append(self.a, selected);
        return selected;
    }
    fn node(self: *Scan, module: *const C.Module, id: C.Id, depth: usize) Error!C.Node {
        try self.step(depth);
        if (id == 0 or id >= module.nodes.len or module.nodes[id].ty >= module.types.nodes.len) return error.InvalidArtifact;
        return module.nodes[id];
    }
    fn span(self: *Scan, module: *const C.Module, start: u32, len: u32) Error![]const u32 {
        try self.step(0);
        if (start > module.extra.len or len > module.extra.len - start) return error.InvalidArtifact;
        return module.extra[start..][0..len];
    }
    fn reaches(self: *Scan, root: Id, owner: ?Id, younger: ?u32) Error!bool {
        if (root >= self.nodes.items.len) return error.InvalidArtifact;
        var pending: [4096]Id = undefined;
        var seen: [4096]bool = @splat(false);
        var len: usize = 1;
        pending[0] = root;
        seen[root] = true;
        while (len != 0) {
            len -= 1;
            const id = pending[len];
            const current = self.nodes.items[id];
            try self.step(0);
            if (current.kind == .capability) {
                if (owner) |wanted| if (current.owner == wanted) return true;
                if (younger) |depth| if (current.depth > depth) return true;
            }
            if ((current.kind == .cell or current.kind == .memo) and !seen[current.contents]) {
                seen[current.contents] = true;
                pending[len] = current.contents;
                len += 1;
            }
            var cursor = current.first_edge;
            while (cursor) |index| {
                try self.step(0);
                const edge_ = self.edges.items[index];
                cursor = edge_.next;
                if (edge_.kind == .call or edge_.kind == .store or seen[edge_.to]) continue;
                seen[edge_.to] = true;
                pending[len] = edge_.to;
                len += 1;
            }
        }
        return false;
    }
    fn sink(self: *Scan, module: *const C.Module, source: C.Id, arguments: []const Id) Error!Id {
        self.complete = false;
        const result = try self.value(module, source, .external);
        for (arguments) |argument| {
            try self.edge(result, argument, .store, 0);
            if (try self.reaches(argument, null, 0)) return error.LifetimeEscape;
        }
        return result;
    }
    fn aggregate(self: *Scan, module: *const C.Module, source: C.Id, kind: Kind, children: []const Id) Error!Id {
        const result = try self.value(module, source, kind);
        for (children, 0..) |child, index| try self.edge(result, child, .value, @intCast(index));
        return result;
    }
    fn select(self: *Scan, module: *const C.Module, source: C.Id, value_: Id, field: u32, depth: usize) Error!Id {
        try self.step(depth);
        if (value_ >= self.nodes.items.len) return error.InvalidArtifact;
        const kind = self.nodes.items[value_].kind;
        if (kind == .selection) {
            var alternatives: [256]Id = undefined;
            var len: usize = 0;
            var cursor = self.nodes.items[value_].first_edge;
            while (cursor) |index| {
                const item = self.edges.items[index];
                cursor = item.next;
                try self.step(depth);
                if (item.kind != .value) continue;
                if (len == alternatives.len) return error.AnalysisLimit;
                alternatives[len] = try self.select(module, source, item.to, field, depth + 1);
                len += 1;
            }
            return try self.aggregate(module, source, .selection, alternatives[0..len]);
        }
        var cursor = self.nodes.items[value_].first_edge;
        while (cursor) |index| {
            try self.step(depth);
            const item = self.edges.items[index];
            cursor = item.next;
            if (item.field == field and item.kind == .value) return item.to;
        }
        if (kind == .scalar) return 0;
        return try self.aggregate(module, source, .unknown, &.{value_});
    }
    fn capture(self: *Scan, module: *const C.Module, source: C.Id, environment: *const Environment, result: Id, depth: usize) Error!void {
        const n = try self.node(module, source, depth);
        if (n.tag == .reference) {
            if (n.a >= module.references.len) return error.InvalidArtifact;
            const reference = module.references[n.a];
            if (reference.unit == 0 or reference.unit == module.unit) {
                if (try environment.get(reference.binding, &self.remaining)) |entry| {
                    try self.edge(result, entry.value, .capture, entry.binding);
                } else if (self.scope_validation and reference.binding < module.bindings.len and (module.bindings[reference.binding].kind == .local or module.bindings[reference.binding].kind == .parameter)) {
                    var nested = environment.*;
                    const actual = try self.freeScopeValue(module, reference.binding, &nested, depth + 1);
                    try self.edge(result, actual, .capture, reference.binding);
                }
            }
            return;
        }
        const graph = @import("frozen_core_validation.zig").Graph.init(module) catch return error.InvalidArtifact;
        try self.captureVertex(module, graph, graph.vertex(.node, source), environment, result, depth + 1);
    }
    fn captureVertex(self: *Scan, module: *const C.Module, graph: @import("frozen_core_validation.zig").Graph, vertex: usize, environment: *const Environment, result: Id, depth: usize) Error!void {
        try self.step(depth);
        const item = graph.item(vertex);
        if (item.kind == .node and item.id != 0 and module.nodes[item.id].tag == .reference) {
            const reference = module.references[module.nodes[item.id].a];
            if (reference.unit == 0 or reference.unit == module.unit) {
                if (try environment.get(reference.binding, &self.remaining)) |entry| {
                    try self.edge(result, entry.value, .capture, entry.binding);
                } else if (self.scope_validation and reference.binding < module.bindings.len and (module.bindings[reference.binding].kind == .local or module.bindings[reference.binding].kind == .parameter)) {
                    var nested = environment.*;
                    const actual = try self.freeScopeValue(module, reference.binding, &nested, depth + 1);
                    try self.edge(result, actual, .capture, reference.binding);
                }
            }
            return;
        }
        var slot: usize = 0;
        while (graph.edge(vertex, slot)) |child| : (slot += 1) try self.captureVertex(module, graph, child, environment, result, depth + 1);
    }
    fn captureBindings(self: *Scan, graph: @import("frozen_core_validation.zig").Graph, vertex: usize, environment: *Environment, depth: usize) Error!void {
        try self.step(depth);
        const item = graph.item(vertex);
        if (item.kind == .node and item.id != 0) {
            const n = graph.m.nodes[item.id];
            if (n.tag == .bind) try environment.bind(n.a, 0, self.scope_depth);
        } else if (item.kind == .closure) {
            try environment.bind(graph.m.closures[item.id].parameter.binding, 0, self.scope_depth);
        } else if (item.kind == .pattern and graph.m.patterns[item.id].tag == .bind) {
            try environment.bind(graph.m.patterns[item.id].a, 0, self.scope_depth);
        }
        var slot: usize = 0;
        while (graph.edge(vertex, slot)) |child| : (slot += 1) try self.captureBindings(graph, child, environment, depth + 1);
    }
    fn closure(self: *Scan, module: *const C.Module, source: C.Id, catalog: u32, environment: *const Environment, memo: bool, depth: usize) Error!Id {
        if (catalog >= module.closures.len) return error.InvalidArtifact;
        const closure_ = module.closures[catalog];
        const result = try self.value(module, source, if (memo) .memo else .callable);
        const mappings_ = try self.mappings(environment.types[0..environment.type_len]);
        self.nodes.items[result].closure = catalog;
        self.nodes.items[result].target = .{ .unit = module.unit, .binding = self.binding, .node = closure_.body };
        self.nodes.items[result].signature = .{ .unit = module.unit, .ty = module.nodes[source].ty };
        self.nodes.items[result].mappings = mappings_;
        self.nodes.items[result].actual_mappings = mappings_;
        if (self.scope_validation) {
            var captures = environment.*;
            try captures.bind(closure_.parameter.binding, 0, self.scope_depth);
            const graph = @import("frozen_core_validation.zig").Graph.init(module) catch return error.InvalidArtifact;
            try self.captureBindings(graph, graph.vertex(.node, closure_.body), &captures, depth + 1);
            try self.capture(module, closure_.body, &captures, result, depth + 1);
        } else try self.capture(module, closure_.body, environment, result, depth + 1);
        try self.callables.append(self.a, .{ .value = result, .module = module, .binding = self.binding, .body = closure_.body, .parameters = (&module.closures[catalog].parameter)[0..1], .environment = environment.* });
        return result;
    }
    fn named(self: *Scan, module: *const C.Module, source: C.Id, original: C.BindingRef, actual: u32, environment: *const Environment) Error!Id {
        var producer = module;
        var target = original;
        for (0..128) |_| {
            try self.step(0);
            producer = try self.ownerModule(producer, target.unit);
            if (target.binding == 0 or target.binding >= producer.bindings.len) return error.InvalidArtifact;
            const binding = producer.bindings[target.binding];
            if (binding.kind == .external) {
                target = binding.target;
                continue;
            }
            if (binding.kind != .global or binding.body_id == 0 or binding.body_id >= producer.bodies.len) return error.Unsupported;
            const body = producer.bodies[binding.body_id];
            if (!body.is_function) return error.Unsupported;
            if (body.parameters.start > producer.parameters.len or body.parameters.len > producer.parameters.len - body.parameters.start or body.parameters.len > 16) return error.InvalidArtifact;
            var imported: Environment = .{};
            if (producer.types.node(binding.ty).tag == .forall) {
                var views: @import("package_contracts.zig").Context = .{ .types = &module.types, .remaining = &self.remaining };
                try views.initialize();
                var instance: @import("package_contracts.zig").Principal = .{ .left = &producer.types, .right = &module.types, .remaining = &self.remaining, .views = &views, .left_rows = body.closed_rows, .foreign_views = true };
                try instance.instantiate(binding.ty, actual);
                const quantifier = producer.types.node(binding.ty);
                for (producer.types.list(.{ .start = quantifier.b, .len = quantifier.c }), instance.witnesses[0..quantifier.c]) |formal, witness| {
                    try self.step(0);
                    // Lexical regions remain value-graph authority. They are
                    // not portable data evidence and cannot become a scalar.
                    if (producer.types.node(formal).b != 0 or witness == 0) continue;
                    if (imported.type_len == imported.types.len) return error.AnalysisLimit;
                    const evidence = self.evidence.projectWithBudget(&module.types, witness, environment.types[0..environment.type_len], &.{}, &self.remaining) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Unsupported;
                    imported.types[imported.type_len] = .{ .variable = formal, .evidence = evidence };
                    imported.type_len += 1;
                }
            } else {
                const relation = @import("generative_relocation.zig").Relocation.init(producer, module, binding.scheme, actual, actual, 0, 0) catch return error.InvalidArtifact;
                const spent = 65_536 - relation.remaining;
                if (spent > self.remaining) return error.AnalysisLimit;
                self.remaining -= spent;
                for (relation.pairs[0..relation.len]) |pair| {
                    try self.step(0);
                    if (producer.types.node(pair.before).tag != .variable) continue;
                    if (imported.type_len == imported.types.len) return error.AnalysisLimit;
                    const evidence = self.evidence.projectWithBudget(&module.types, pair.after, environment.types[0..environment.type_len], &.{}, &self.remaining) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Unsupported;
                    imported.types[imported.type_len] = .{ .variable = pair.before, .evidence = evidence };
                    imported.type_len += 1;
                }
            }
            const result = try self.value(module, source, .callable);
            const mappings_ = try self.mappings(imported.types[0..imported.type_len]);
            const actual_mappings = try self.mappings(environment.types[0..environment.type_len]);
            self.nodes.items[result].target = .{ .unit = producer.unit, .binding = body.binding, .node = body.root };
            self.nodes.items[result].signature = .{ .unit = module.unit, .ty = actual };
            self.nodes.items[result].mappings = mappings_;
            self.nodes.items[result].actual_mappings = actual_mappings;
            try self.callables.append(self.a, .{ .value = result, .module = producer, .binding = body.binding, .body = body.root, .parameters = producer.parameters[body.parameters.start..][0..body.parameters.len], .environment = imported, .runtime = body.runtime });
            return result;
        }
        return error.AnalysisLimit;
    }
    fn operationEqual(self: *Scan, left: Id, right: Id) Error!bool {
        if (left == right) return true;
        var lhs: ?Operation = null;
        var rhs: ?Operation = null;
        for (self.operations.items) |item| {
            try self.step(0);
            if (item.value == left) lhs = item;
            if (item.value == right) rhs = item;
        }
        const a = lhs orelse return false;
        const b = rhs orelse return false;
        if (!std.meta.eql(a.metadata.identity, b.metadata.identity) or a.receiver != b.receiver or (a.receiver == 0 and !std.meta.eql(a.metadata.instance, b.metadata.instance)) or a.metadata.arguments.len != b.metadata.arguments.len) return false;
        try self.step(0);
        return std.mem.eql(E.Id, a.arguments[0..a.argument_count], b.arguments[0..b.argument_count]);
    }
    fn invoke(self: *Scan, module: *const C.Module, source: C.Id, function: Id, argument: Id, depth: usize) Error!Id {
        try self.step(depth);
        for (self.operations.items) |operation| {
            try self.step(depth);
            if (operation.value != function) continue;
            var index = self.frames.items.len;
            while (index != 0) {
                try self.step(depth);
                index -= 1;
                const frame = self.frames.items[index];
                if (try self.operationEqual(frame.read, function)) {
                    if (frame.cell == 0) {
                        if (try self.reaches(argument, null, 0)) return error.LifetimeEscape;
                        const saved = try self.a.dupe(Frame, self.frames.items[index..]);
                        defer self.a.free(saved);
                        self.frames.shrinkRetainingCapacity(index);
                        defer self.frames.appendSliceAssumeCapacity(saved);
                        return try self.invoke(module, source, frame.callback, argument, depth + 1);
                    }
                    const call = try self.value(module, source, .event);
                    try self.edge(call, function, .call, 0);
                    try self.edge(call, frame.cell, .call, 1);
                    try self.edge(call, self.nodes.items[frame.cell].contents, .result, 0);
                    return self.nodes.items[frame.cell].contents;
                }
                if (frame.write != 0 and try self.operationEqual(frame.write, function)) {
                    if (try self.reaches(argument, null, frame.depth)) return error.LifetimeEscape;
                    const call = try self.value(module, source, .event);
                    try self.edge(call, function, .call, 0);
                    try self.edge(call, frame.cell, .call, 1);
                    try self.edge(call, argument, .call, 2);
                    try self.edge(frame.cell, argument, .store, 0);
                    self.nodes.items[frame.cell].contents = argument;
                    return 0;
                }
            }
            return try self.sink(module, source, &.{ function, argument });
        }
        for (self.callables.items, 0..) |callable, index| {
            try self.step(depth);
            if (callable.value != function) continue;
            var invocation = callable;
            if (invocation.count >= invocation.parameters.len or invocation.count == invocation.arguments.len) return error.InvalidArtifact;
            invocation.arguments[invocation.count] = argument;
            invocation.count += 1;
            if (invocation.count < invocation.parameters.len) {
                const partial = try self.value(module, source, .callable);
                invocation.value = partial;
                const origin = self.nodes.items[function];
                self.nodes.items[partial].target = origin.target;
                self.nodes.items[partial].closure = origin.closure;
                self.nodes.items[partial].signature = origin.signature;
                self.nodes.items[partial].mappings = origin.mappings;
                self.nodes.items[partial].actual_mappings = origin.actual_mappings;
                if (self.scope_validation) {
                    // A semantic partial call retains only the arguments used
                    // by its owned residual body. Physical wrapper storage is
                    // still conservative in the complete allocation report.
                    var captures = callable.environment;
                    for (invocation.parameters, 0..) |parameter, ordinal| {
                        var actual: Id = 0;
                        if (ordinal < invocation.count) actual = invocation.arguments[ordinal];
                        try captures.bind(parameter.binding, actual, self.scope_depth);
                    }
                    const graph = @import("frozen_core_validation.zig").Graph.init(callable.module) catch return error.InvalidArtifact;
                    try self.captureBindings(graph, graph.vertex(.node, callable.body), &captures, depth + 1);
                    try self.capture(callable.module, callable.body, &captures, partial, depth + 1);
                } else {
                    try self.edge(partial, function, .capture, 0);
                    try self.edge(partial, argument, .capture, 1);
                }
                try self.callables.append(self.a, invocation);
                return partial;
            }
            if (self.nodes.items[function].kind == .memo) {
                if (callable.memo_state == .cached) return callable.cached;
                if (callable.memo_state == .forcing) return error.Unsupported;
                self.callables.items[index].memo_state = .forcing;
            }
            if (callable.runtime) return try self.sink(module, source, invocation.arguments[0..invocation.count]);
            // Recursive execution is outside this finite value graph's proof
            // domain. It supplies no complete confinement report; the other
            // immutable ownership/call guards remain independently required.
            var active = self.active_calls;
            while (active) |prior| : (active = prior.parent) {
                try self.step(depth);
                if (prior.module == callable.module and prior.body == callable.body) return error.Unsupported;
            }
            var current: ActiveCall = .{ .module = callable.module, .body = callable.body, .parent = self.active_calls };
            self.active_calls = &current;
            defer self.active_calls = current.parent;
            var nested = callable.environment;
            for (invocation.parameters, invocation.arguments[0..invocation.count]) |parameter, actual| try nested.bind(parameter.binding, actual, self.scope_depth);
            const call = try self.value(module, source, .event);
            try self.edge(call, function, .call, 0);
            for (invocation.arguments[0..invocation.count], 0..) |actual, ordinal| try self.edge(call, actual, .call, @intCast(ordinal + 1));
            const caller = self.site(module, source);
            const saved_binding = self.binding;
            const saved_context = self.context;
            self.context = @intCast(self.invocations.items.len);
            try self.invocations.append(self.a, .{ .parent = saved_context, .caller = caller, .callable = function });
            self.nodes.items[call].invocation = self.context;
            self.binding = callable.binding;
            defer {
                self.binding = saved_binding;
                self.context = saved_context;
            }
            const evaluated = try self.expression(callable.module, callable.body, &nested, depth + 1);
            if (evaluated == null) self.complete = false;
            const result = evaluated orelse 0;
            try self.edge(call, result, .result, 0);
            if (self.nodes.items[function].kind == .memo) {
                self.callables.items[index].memo_state = .cached;
                self.callables.items[index].cached = result;
                self.nodes.items[function].contents = result;
                self.nodes.items[function].ready = true;
                try self.edge(function, result, .result, 0);
            }
            return result;
        }
        return try self.sink(module, source, &.{ function, argument });
    }
    fn pattern(self: *Scan, module: *const C.Module, id: u32, origin: Id, environment: *Environment, depth: usize) Error!void {
        try self.step(depth);
        if (id == 0 or id >= module.patterns.len) return error.InvalidArtifact;
        const pattern_ = module.patterns[id];
        switch (pattern_.tag) {
            .wildcard, .constant => {},
            .bind => try environment.bind(pattern_.a, origin, self.scope_depth),
            .record_payload => if (pattern_.b != 0) try self.pattern(module, pattern_.b, origin, environment, depth + 1),
            .constructor => if (pattern_.b != 0) try self.pattern(module, pattern_.b, try self.select(module, 0, origin, 0, depth + 1), environment, depth + 1),
            .product => {
                if (pattern_.ty >= module.types.nodes.len) return error.InvalidArtifact;
                const shape = module.types.node(pattern_.ty);
                if (shape.tag == .record and (shape.a > module.types.extra.len or shape.b > (module.types.extra.len - shape.a) / 2)) return error.InvalidArtifact;
                for (try self.span(module, pattern_.a, pattern_.b), 0..) |child, index| {
                    var field: u32 = @intCast(index);
                    if (shape.tag == .record) {
                        if (index >= shape.b) return error.InvalidArtifact;
                        field = module.types.extra[shape.a + index * 2];
                    }
                    try self.pattern(module, child, try self.select(module, 0, origin, field, depth + 1), environment, depth + 1);
                }
            },
            else => return error.Unsupported,
        }
    }
    fn branches(self: *Scan, module: *const C.Module, source: C.Id, first: C.Id, second: C.Id, environment: *const Environment, depth: usize) Error!?Id {
        var locations = try Locations.init(self);
        defer locations.deinit(self.a);
        var left = environment.*;
        const lhs = try self.expression(module, first, &left, depth + 1);
        try locations.collect(self, module, source);
        try locations.reset(self);
        var right = environment.*;
        const rhs = if (second == 0) @as(?Id, 0) else try self.expression(module, second, &right, depth + 1);
        try locations.collect(self, module, source);
        try locations.finish(self);
        if (lhs == null) return rhs;
        if (rhs == null) return lhs;
        return try self.aggregate(module, source, .selection, &.{ lhs.?, rhs.? });
    }
    fn matches(self: *Scan, module: *const C.Module, pattern_id: u32, origin: Id, environment: *Environment, start: usize, depth: usize) Error!bool {
        try self.step(depth);
        if (pattern_id == 0 or pattern_id >= module.patterns.len or origin >= self.nodes.items.len) return error.InvalidArtifact;
        const pattern_ = module.patterns[pattern_id];
        const actual = self.nodes.items[origin];
        if (actual.kind == .selection) {
            var matched = false;
            var cursor = actual.first_edge;
            while (cursor) |index| {
                try self.step(depth);
                const edge_ = self.edges.items[index];
                cursor = edge_.next;
                if (edge_.kind != .value) continue;
                matched = (try self.matches(module, pattern_id, edge_.to, environment, start, depth + 1)) or matched;
            }
            return matched;
        }
        switch (pattern_.tag) {
            .wildcard, .constant, .value => return true,
            .bind => {
                for (environment.entries[start..environment.len]) |*entry_| {
                    try self.step(depth);
                    if (entry_.binding != pattern_.a) continue;
                    if (entry_.value != origin) entry_.value = try self.aggregate(module, 0, .selection, &.{ entry_.value, origin });
                    return true;
                }
                try environment.bind(pattern_.a, origin, self.scope_depth);
                return true;
            },
            .constructor => {
                if (pattern_.a >= module.constructors.len) return error.InvalidArtifact;
                const constructor = module.constructors[pattern_.a];
                if (constructor.nominal >= module.nominals.len) return error.InvalidArtifact;
                if (actual.kind == .nominal and (!std.meta.eql(actual.nominal, module.nominals[constructor.nominal].identity) or actual.field != constructor.tag)) return false;
                if (actual.kind != .nominal) return error.Unsupported;
                if (pattern_.b == 0) return true;
                return self.matches(module, pattern_.b, try self.select(module, 0, origin, 0, depth + 1), environment, start, depth + 1);
            },
            .record_payload => {
                if (pattern_.b == 0) return true;
                return self.matches(module, pattern_.b, origin, environment, start, depth + 1);
            },
            .product => {
                if (pattern_.ty >= module.types.nodes.len) return error.InvalidArtifact;
                const shape = module.types.node(pattern_.ty);
                if (shape.tag == .record and (shape.a > module.types.extra.len or shape.b > (module.types.extra.len - shape.a) / 2)) return error.InvalidArtifact;
                for (try self.span(module, pattern_.a, pattern_.b), 0..) |child, index| {
                    var field: u32 = @intCast(index);
                    if (shape.tag == .record) {
                        if (index >= shape.b) return error.InvalidArtifact;
                        field = module.types.extra[shape.a + index * 2];
                    }
                    if (!try self.matches(module, child, try self.select(module, 0, origin, field, depth + 1), environment, start, depth + 1)) return false;
                }
                return true;
            },
            .invalid => return error.InvalidArtifact,
        }
    }
    fn freeScopeValue(self: *Scan, module: *const C.Module, binding_id: u32, environment: *Environment, depth: usize) Error!Id {
        try self.step(depth);
        if (binding_id == 0 or binding_id >= module.bindings.len) return error.InvalidArtifact;
        const binding = module.bindings[binding_id];
        if (binding.initializer != 0) {
            const initial = try self.node(module, binding.initializer, depth + 1);
            // These forms reconstruct an existing value, without reexecuting
            // outside stores or arbitrary initialization calls in this scope.
            switch (initial.tag) {
                .constant, .type_constructor, .reference, .closure, .suspend_, .record, .product, .array, .construct => {},
                else => return error.Unsupported,
            }
            const actual = (try self.expression(module, binding.initializer, environment, depth + 1)) orelse return error.Unsupported;
            try environment.bind(binding_id, actual, 0);
            return actual;
        }
        const primitive = switch (module.types.node(binding.ty).tag) {
            .unit, .boolean, .u32, .f32, .never => true,
            else => false,
        };
        if (!primitive) self.complete = false;
        const actual = if (primitive) 0 else try self.value(module, 0, .unknown);
        try environment.bind(binding_id, actual, 0);
        return actual;
    }
    fn sameType(self: *Scan, module: *const C.Module, left: T.Id, right: T.Id) Error!bool {
        if (left >= module.types.nodes.len or right >= module.types.nodes.len) return error.InvalidArtifact;
        return @import("rank_equal.zig").equalWithBudget(&module.types, left, right, true, &self.remaining) catch return if (self.remaining == 0) error.AnalysisLimit else error.InvalidArtifact;
    }
    fn resourceClosure(self: *Scan, module: *const C.Module, source: C.Id, kind: T.UsageKind, depth: usize) Error!T.Node {
        const n = try self.node(module, source, depth);
        if (n.tag != .closure) return error.Unsupported;
        if (n.a >= module.closures.len or n.op != .none or n.b != 0 or n.c != 0) return error.InvalidArtifact;
        const wrapper = module.types.node(n.ty);
        if (wrapper.tag != .usage or wrapper.b != @backingInt(kind) or wrapper.c != 0 or wrapper.a >= module.types.nodes.len) return error.InvalidArtifact;
        const arrow = module.types.node(wrapper.a);
        const closure_ = module.closures[n.a];
        const body = try self.node(module, closure_.body, depth + 1);
        if (arrow.tag != .function or !try self.sameType(module, arrow.a, closure_.parameter.ty) or (body.ty != T.never and !try self.sameType(module, body.ty, arrow.b))) return error.InvalidArtifact;
        return arrow;
    }
    fn resource(self: *Scan, module: *const C.Module, source: C.Id, n: C.Node, environment: *Environment, depth: usize) Error!?Id {
        const acquire = try self.resourceClosure(module, n.a, .once, depth + 1);
        const release = try self.resourceClosure(module, n.b, .cleanup, depth + 1);
        const callback = try self.resourceClosure(module, n.c, .once, depth + 1);
        if (acquire.a != T.unit or acquire.b >= module.types.nodes.len or !try self.sameType(module, release.a, acquire.b) or release.b != T.unit or !try self.sameType(module, callback.b, n.ty) or callback.a >= module.types.nodes.len) return error.InvalidArtifact;
        const owner = module.types.node(acquire.b);
        const loan = module.types.node(callback.a);
        if (owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or owner.c != 0 or owner.a >= module.types.nodes.len) return error.InvalidArtifact;
        // Scalar closed storage cannot conceal a callable or provider. General
        // owner payloads and host cleanup require their own lifetime recipe.
        const payload = module.types.node(owner.a);
        if (payload.tag != .unit and payload.tag != .boolean and payload.tag != .u32 and payload.tag != .f32) return error.Unsupported;
        if (payload.a != 0 or payload.b != 0 or payload.c != 0 or loan.tag != .usage or loan.b != @backingInt(T.UsageKind.borrow_mut) or loan.a != owner.a or loan.c == 0 or loan.c >= module.types.nodes.len) return error.InvalidArtifact;
        const region = module.types.node(loan.c);
        if (region.tag != .bound or region.a != 0 or region.b != 2 or region.c != module.closures[module.node(n.c).a].parameter.binding) return error.InvalidArtifact;
        if (release.c != 0) return error.Unsupported;
        @import("cleanup_contracts.zig").immutableScalarWithBudget(module, n.b, &self.remaining) catch return if (self.remaining == 0) error.AnalysisLimit else error.InvalidArtifact;
        const acquisition = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
        const cleanup = (try self.expression(module, n.b, environment, depth + 1)) orelse return null;
        const body = (try self.expression(module, n.c, environment, depth + 1)) orelse return null;
        const acquired = try self.invoke(module, n.a, acquisition, 0, depth + 1);
        if (acquired != 0) return error.Unsupported;
        const resource_owner = try self.value(module, source, .scope);
        self.scope_depth += 1;
        defer self.scope_depth -= 1;
        const borrowed = try self.value(module, source, .capability);
        self.nodes.items[borrowed].owner = resource_owner;
        const result = try self.invoke(module, n.c, body, borrowed, depth + 1);
        // Cleanup runs even when the callback terminates. Its capture graph is
        // local, while any store or unknown call still gets ordinary checking.
        const cleaned = try self.invoke(module, n.b, cleanup, acquired, depth + 1);
        if (cleaned != 0) return error.InvalidArtifact;
        if (try self.reaches(result, resource_owner, null)) return error.LifetimeEscape;
        try self.boundaries.append(self.a, .{ .site = self.site(module, source), .owner = resource_owner, .result = result });
        return result;
    }
    fn taskScope(self: *Scan, module: *const C.Module, source: C.Id, callback_id: C.Id, environment: *Environment, depth: usize) Error!?Id {
        const callback = try self.node(module, callback_id, depth + 1);
        if (callback.tag != .closure or callback.a >= module.closures.len) return error.InvalidArtifact;
        const closure_ = module.closures[callback.a];
        const saved_owner = self.owner;
        const owner = try self.value(module, source, .scope);
        self.owner = owner;
        self.scope_depth += 1;
        defer {
            self.scope_depth -= 1;
            self.owner = saved_owner;
        }
        const capability = try self.value(module, callback_id, .capability);
        _ = closure_;
        const function = try self.closure(module, callback_id, callback.a, environment, false, depth + 1);
        const result = try self.invoke(module, callback_id, function, capability, depth + 1);
        if (try self.reaches(result, owner, null)) return error.LifetimeEscape;
        try self.boundaries.append(self.a, .{ .site = self.site(module, source), .owner = owner, .result = result });
        return result;
    }
    fn expression(self: *Scan, module: *const C.Module, source: C.Id, environment: *Environment, depth: usize) Error!?Id {
        const n = try self.node(module, source, depth);
        switch (n.tag) {
            .constant, .type_constructor => return 0,
            .type_same, .proof_guard => {
                _ = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                _ = (try self.expression(module, n.b, environment, depth + 1)) orelse return null;
                return 0;
            },
            .reference => {
                if (n.a >= module.references.len) return error.InvalidArtifact;
                const reference = module.references[n.a];
                if (reference.unit == 0 or reference.unit == module.unit) {
                    if (try environment.get(reference.binding, &self.remaining)) |entry| return entry.value;
                    if (self.scope_validation and reference.binding < module.bindings.len and (module.bindings[reference.binding].kind == .local or module.bindings[reference.binding].kind == .parameter)) return try self.freeScopeValue(module, reference.binding, environment, depth + 1);
                }
                return try self.named(module, source, reference, n.ty, environment);
            },
            .scalar => {
                // Overloaded scalar syntax executes an owned implementation;
                // primitive operand evaluation alone cannot certify that call.
                if (n.c != 0) return error.Unsupported;
                _ = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                if (n.b != 0) _ = (try self.expression(module, n.b, environment, depth + 1)) orelse return null;
                return 0;
            },
            .logical => {
                _ = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                return self.branches(module, source, n.b, 0, environment, depth + 1);
            },
            .closure, .suspend_ => return try self.closure(module, source, n.a, environment, n.tag == .suspend_, depth),
            .force => {
                const demand = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                return try self.invoke(module, source, demand, 0, depth + 1);
            },
            .apply => {
                const function = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                const argument = (try self.expression(module, n.b, environment, depth + 1)) orelse return null;
                return try self.invoke(module, source, function, argument, depth + 1);
            },
            .call => {
                if (n.a >= module.calls.len) return error.InvalidArtifact;
                const call = module.calls[n.a];
                var function = try self.named(module, source, call.target, call.callee_type, environment);
                for (try self.span(module, n.b, n.c)) |argument| function = try self.invoke(module, source, function, (try self.expression(module, argument, environment, depth + 1)) orelse return null, depth + 1);
                return function;
            },
            .operation_value => {
                if (n.a >= module.operation_values.len) return error.InvalidArtifact;
                const metadata = module.operation_values[n.a];
                if (metadata.witness != 0) _ = (try self.expression(module, metadata.witness, environment, depth + 1)) orelse return null;
                const receiver = if (metadata.capability == 0) 0 else (try self.expression(module, metadata.capability, environment, depth + 1)) orelse return null;
                const result = try self.value(module, source, .operation);
                try self.edge(result, receiver, .capture, 0);
                var operation: Operation = .{ .value = result, .module = module, .metadata = metadata, .receiver = receiver };
                const arguments = metadata.arguments;
                if (arguments.len > operation.arguments.len or arguments.start > module.types.extra.len or arguments.len > module.types.extra.len - arguments.start) return error.InvalidArtifact;
                for (module.types.extra[arguments.start..][0..arguments.len], 0..) |argument, index| operation.arguments[index] = self.evidence.projectWithBudget(&module.types, argument, environment.types[0..environment.type_len], &.{}, &self.remaining) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Unsupported;
                operation.argument_count = arguments.len;
                try self.operations.append(self.a, operation);
                return result;
            },
            .effect_provider, .state_provider => {
                const read = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                const second = (try self.expression(module, n.b, environment, depth + 1)) orelse return null;
                const initial = if (n.tag == .state_provider) (try self.expression(module, n.c, environment, depth + 1)) orelse return null else 0;
                const result = try self.aggregate(module, source, if (n.tag == .state_provider) .state_provider else .provider, &.{ read, second, initial });
                try self.providers.append(self.a, .{ .value = result, .provider = .{ .read = read, .write = if (n.tag == .state_provider) second else 0, .initial = initial, .callback = if (n.tag == .effect_provider) second else 0 } });
                return result;
            },
            .handle => {
                const provider = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                const definition = for (self.providers.items) |item| {
                    try self.step(depth);
                    if (item.value == provider) break item.provider;
                } else return error.Unsupported;
                const mark = self.frames.items.len;
                defer self.frames.shrinkRetainingCapacity(mark);
                const cell = if (definition.write == 0) 0 else try self.value(module, source, .cell);
                if (cell != 0) self.nodes.items[cell].contents = definition.initial;
                try self.frames.append(self.a, .{ .read = definition.read, .write = definition.write, .cell = cell, .depth = self.scope_depth, .callback = definition.callback, .outer = mark });
                const result = (try self.expression(module, n.b, environment, depth + 1)) orelse return null;
                if (cell == 0) return result;
                return try self.aggregate(module, source, .product, &.{ self.nodes.items[cell].contents, result });
            },
            .effect_scope => return self.taskScope(module, source, n.a, environment, depth),
            .task => {
                const operation = std.enums.fromInt(@import("task_types.zig").Op, n.c) orelse return error.InvalidArtifact;
                const operands = module.children(source);
                switch (operation) {
                    .scope => return self.taskScope(module, source, operands[0], environment, depth),
                    .spawn => {
                        const group = (try self.expression(module, operands[0], environment, depth + 1)) orelse return null;
                        const thunk = (try self.expression(module, operands[1], environment, depth + 1)) orelse return null;
                        const result = try self.invoke(module, source, thunk, 0, depth + 1);
                        const handle = try self.aggregate(module, source, .wrapper, &.{ group, result });
                        self.nodes.items[handle].contents = result;
                        return handle;
                    },
                    .join, .cancel => {
                        const handle = (try self.expression(module, operands[0], environment, depth + 1)) orelse return null;
                        if (operation == .cancel) return try self.value(module, source, .scalar);
                        if (handle >= self.nodes.items.len or self.nodes.items[handle].kind != .wrapper) return error.Unsupported;
                        return self.nodes.items[handle].contents;
                    },
                    .split => {
                        const owner_value = (try self.expression(module, operands[0], environment, depth + 1)) orelse return null;
                        const plan = @import("task_regions.zig").partition(module, source) catch return error.InvalidArtifact;
                        const saved_owner = self.owner;
                        const owner = try self.value(module, source, .scope);
                        self.owner = owner;
                        self.scope_depth += 1;
                        defer {
                            self.scope_depth -= 1;
                            self.owner = saved_owner;
                        }
                        const arguments = try self.value(module, source, .product);
                        for (0..plan.len) |ordinal| {
                            const view = try self.value(module, source, .capability);
                            self.nodes.items[view].contents = owner_value;
                            try self.edge(view, owner_value, .value, 0);
                            try self.edge(arguments, view, .value, @intCast(ordinal));
                        }
                        const callback = (try self.expression(module, operands[2], environment, depth + 1)) orelse return null;
                        const result = try self.invoke(module, source, callback, arguments, depth + 1);
                        if (try self.reaches(result, owner, null)) return error.LifetimeEscape;
                        return try self.aggregate(module, source, .product, &.{ owner_value, result });
                    },
                    .read, .write => {
                        _ = (try self.expression(module, operands[0], environment, depth + 1)) orelse return null;
                        _ = (try self.expression(module, operands[1], environment, depth + 1)) orelse return null;
                        if (operation == .write) {
                            const value_ = (try self.expression(module, operands[2], environment, depth + 1)) orelse return null;
                            if (try self.reaches(value_, null, 0)) return error.LifetimeEscape;
                            return 0;
                        }
                        const ty = module.types.node(n.ty);
                        if (ty.tag == .unit or ty.tag == .boolean or ty.tag == .u32 or ty.tag == .f32) return 0;
                        return error.Unsupported;
                    },
                }
            },
            .resource_scope => return self.resource(module, source, n, environment, depth + 1),
            .computation, .usage_share, .usage_read => {
                const result = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                if (n.tag == .usage_read) return 0;
                return result;
            },
            .product, .array, .record => {
                const result = try self.value(module, source, if (n.tag == .record) .record else .product);
                const children = try self.span(module, n.a, n.b);
                var record: T.Node = .{ .tag = .absent };
                if (n.tag == .record) {
                    record = module.types.node(n.ty);
                    if (record.tag != .record or record.a > module.types.extra.len or record.b > (module.types.extra.len - record.a) / 2) return error.InvalidArtifact;
                    _ = try self.span(module, n.c, n.b);
                }
                for (children, 0..) |child, index| {
                    var field: u32 = @intCast(index);
                    if (n.tag == .record) {
                        const destination = module.extra[n.c + index];
                        if (destination >= record.b) return error.InvalidArtifact;
                        field = module.types.extra[record.a + destination * 2];
                    }
                    const value_ = (try self.expression(module, child, environment, depth + 1)) orelse return null;
                    try self.edge(result, value_, .value, field);
                }
                return result;
            },
            .construct => {
                if (n.a >= module.constructors.len) return error.InvalidArtifact;
                const constructor = module.constructors[n.a];
                if (n.a == 0 or (constructor.payload == 0) != (n.b == 0) or constructor.nominal >= module.nominals.len) return error.InvalidArtifact;
                const result = try self.value(module, source, .nominal);
                self.nodes.items[result].nominal = module.nominals[constructor.nominal].identity;
                self.nodes.items[result].field = constructor.tag;
                if (n.b != 0) try self.edge(result, (try self.expression(module, n.b, environment, depth + 1)) orelse return null, .value, 0);
                return result;
            },
            .package_pack => return try self.aggregate(module, source, .wrapper, &.{(try self.expression(module, n.a, environment, depth + 1)) orelse return null}),
            .project => {
                if (n.b >= module.projections.len) return error.InvalidArtifact;
                const projection = module.projections[n.b];
                var field = projection.field;
                if (field == 0) {
                    if (projection.variants.len != 1 or projection.variants.start >= module.projection_variants.len) return error.Unsupported;
                    field = module.projection_variants[projection.variants.start].field;
                }
                return try self.select(module, source, (try self.expression(module, n.a, environment, depth + 1)) orelse return null, field, depth + 1);
            },
            .if_value, .if_stmt => {
                _ = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                return self.branches(module, source, n.b, n.c, environment, depth + 1);
            },
            .match => {
                if (n.a >= module.matches.len) return error.InvalidArtifact;
                const match = module.matches[n.a];
                if (match.inputs.len > 16 or match.arms.start > module.match_arms.len or match.arms.len > module.match_arms.len - match.arms.start) return error.InvalidArtifact;
                var inputs: [16]Id = undefined;
                for (try self.span(module, match.inputs.start, match.inputs.len), 0..) |input, index| inputs[index] = (try self.expression(module, input, environment, depth + 1)) orelse return null;
                var locations = try Locations.init(self);
                defer locations.deinit(self.a);
                var values: [256]Id = undefined;
                var count: usize = 0;
                for (module.match_arms[match.arms.start..][0..match.arms.len]) |arm| {
                    try self.step(depth);
                    // A false guard carries its stores into the next arm. Until
                    // these continuations are modeled, no guarded match grants
                    // a complete lifetime report.
                    if (arm.guard != 0) return error.Unsupported;
                    if (arm.rows.start > module.pattern_rows.len or arm.rows.len > module.pattern_rows.len - arm.rows.start) return error.InvalidArtifact;
                    var nested = environment.*;
                    var possible = false;
                    for (module.pattern_rows[arm.rows.start..][0..arm.rows.len]) |row| {
                        try self.step(depth);
                        if (row.patterns.len != match.inputs.len) return error.InvalidArtifact;
                        var alternative = environment.*;
                        var matched = true;
                        for (try self.span(module, row.patterns.start, row.patterns.len), inputs[0..match.inputs.len]) |pattern_, input| matched = (try self.matches(module, pattern_, input, &alternative, environment.len, depth + 1)) and matched;
                        if (!matched) continue;
                        for (alternative.entries[environment.len..alternative.len]) |entry_| {
                            var found = false;
                            for (nested.entries[environment.len..nested.len]) |*prior| {
                                try self.step(depth);
                                if (prior.binding != entry_.binding) continue;
                                if (prior.value != entry_.value) prior.value = try self.aggregate(module, source, .selection, &.{ prior.value, entry_.value });
                                found = true;
                                break;
                            }
                            if (!found) try nested.bind(entry_.binding, entry_.value, entry_.depth);
                        }
                        possible = true;
                    }
                    if (!possible) continue;
                    try locations.reset(self);
                    if (arm.guard != 0) _ = try self.expression(module, arm.guard, &nested, depth + 1);
                    if (try self.expression(module, arm.body, &nested, depth + 1)) |value_| {
                        if (count == values.len) return error.AnalysisLimit;
                        values[count] = value_;
                        count += 1;
                    }
                    try locations.collect(self, module, source);
                }
                try locations.finish(self);
                if (count == 0) return null;
                if (count == 1) return values[0];
                return try self.aggregate(module, source, .selection, values[0..count]);
            },
            .block, .suite => {
                var nested = environment.*;
                try self.controls.append(self.a, .{ .module = module, .target = source, .depth = self.scope_depth });
                defer _ = self.controls.pop();
                const mark = self.exits.items.len;
                var current: ?Id = 0;
                for (try self.span(module, n.a, n.b)) |child| {
                    if (current == null) break;
                    current = try self.expression(module, child, &nested, depth + 1);
                }
                var results: [256]Id = undefined;
                var len: usize = 0;
                if (current) |normal| {
                    results[0] = normal;
                    len = 1;
                }
                var index = mark;
                while (index < self.exits.items.len) {
                    try self.step(depth);
                    const exit = self.exits.items[index];
                    if (exit.module == module and exit.target == source) {
                        if (len == results.len) return error.AnalysisLimit;
                        results[len] = exit.value;
                        len += 1;
                        _ = self.exits.swapRemove(index);
                    } else index += 1;
                }
                if (len == 0) return null;
                if (len == 1) return results[0];
                return try self.aggregate(module, source, .selection, results[0..len]);
            },
            .pattern_bind => {
                if (n.c != 0) return error.Unsupported;
                const result = (try self.expression(module, n.b, environment, depth + 1)) orelse return null;
                try self.pattern(module, n.a, result, environment, depth + 1);
                return 0;
            },
            .bind => {
                const result = (try self.expression(module, n.b, environment, depth + 1)) orelse return null;
                try environment.bind(n.a, result, self.scope_depth);
                return 0;
            },
            .return_ => {
                const result = (try self.expression(module, n.a, environment, depth + 1)) orelse return null;
                var target_depth: ?u32 = null;
                for (self.controls.items) |control| {
                    try self.step(depth);
                    if (control.module == module and control.target == n.b) target_depth = control.depth;
                }
                if (try self.reaches(result, null, target_depth orelse return error.InvalidArtifact)) return error.LifetimeEscape;
                try self.exits.append(self.a, .{ .module = module, .target = n.b, .value = result });
                return null;
            },
            .panic => return null,
            else => return error.Unsupported,
        }
    }
};

/// Reconstruct an executable boundary. No serialized flag or caller-provided
/// no-store claim can make an incomplete report certify confinement.
pub fn analyze(a: A, module: *const C.Module, owners: []const *const C.Module, boundary: C.BindingRef) Error!Report {
    const all = try a.alloc(*const C.Module, owners.len + 1);
    defer a.free(all);
    all[0] = module;
    var count: usize = 1;
    var remaining: usize = 65_536;
    for (owners) |owner_| {
        if (owner_ == module) continue;
        for (all[0..count]) |prior| {
            if (remaining == 0) return error.AnalysisLimit;
            remaining -= 1;
            if (prior.unit == owner_.unit) return error.InvalidArtifact;
        }
        all[count] = owner_;
        count += 1;
    }
    const context: @import("frozen_core_validation.zig").Context = .{ .units = all[0..count] };
    try @import("frozen_core_validation.zig").validateBounds(module, context);
    var scan: Scan = .{ .a = a, .module = module, .remaining = remaining, .evidence = E.Store.init(a) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.AnalysisLimit, .owners = all[0..count] };
    defer scan.deinit();
    try scan.invocations.append(a, .{ .parent = null, .caller = .{ .unit = module.unit, .binding = boundary.binding }, .callable = 0 });
    _ = try scan.value(module, 0, .scalar);
    scan.binding = boundary.binding;
    const owner = try scan.ownerModule(module, boundary.unit);
    if (boundary.binding == 0 or boundary.binding >= owner.bindings.len) return error.InvalidArtifact;
    const binding = owner.bindings[boundary.binding];
    if (binding.body_id == 0 or binding.body_id >= owner.bodies.len) return error.InvalidArtifact;
    const body = owner.bodies[binding.body_id];
    if (body.parameters.start > owner.parameters.len or body.parameters.len > owner.parameters.len - body.parameters.start) return error.InvalidArtifact;
    var environment: Environment = .{};
    for (owner.parameters[body.parameters.start..][0..body.parameters.len]) |parameter| {
        const unknown = try scan.value(owner, body.root, .unknown);
        try environment.bind(parameter.binding, unknown, 0);
    }
    scan.owner = try scan.value(owner, body.root, .activation);
    const result = (try scan.expression(owner, body.root, &environment, 0)) orelse return error.InvalidArtifact;
    if (scan.exits.items.len != 0) return error.InvalidArtifact;
    try scan.boundaries.append(a, .{ .site = scan.site(owner, body.root), .owner = scan.owner, .result = result });
    return takeReport(&scan, 65_536);
}

/// Additional immutable rejection guard. Unsupported scope paths keep their
/// existing independent admission guards; they acquire no new lifetime fact.
/// One shared work budget covers all roots in this validation.
pub fn rejectSupportedEscapes(a: A, module: *const C.Module, owners: []const *const C.Module) (A.Error || error{InvalidArtifact})!void {
    var active = false;
    for (module.nodes) |n| if (isScope(n)) {
        active = true;
        break;
    };
    if (!active) return;
    const all = try a.alloc(*const C.Module, owners.len + 1);
    defer a.free(all);
    all[0] = module;
    var count: usize = 1;
    var remaining: usize = 65_536;
    for (owners) |owner_| {
        if (owner_ == module) continue;
        for (all[0..count]) |prior| {
            if (remaining == 0) return error.InvalidArtifact;
            remaining -= 1;
            if (prior.unit == owner_.unit) return error.InvalidArtifact;
        }
        all[count] = owner_;
        count += 1;
    }
    const context: @import("frozen_core_validation.zig").Context = .{ .units = all[0..count] };
    try @import("frozen_core_validation.zig").validateBounds(module, context);
    var scan: Scan = .{ .a = a, .module = module, .owners = all[0..count], .remaining = remaining, .scope_validation = true, .evidence = E.Store.init(a) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidArtifact };
    defer scan.deinit();
    for (module.nodes, 0..) |n, id| {
        if (!isScope(n)) continue;
        scan.step(0) catch return error.InvalidArtifact;
        scan.nodes.clearRetainingCapacity();
        scan.edges.clearRetainingCapacity();
        scan.callables.clearRetainingCapacity();
        scan.operations.clearRetainingCapacity();
        scan.providers.clearRetainingCapacity();
        scan.frames.clearRetainingCapacity();
        scan.exits.clearRetainingCapacity();
        scan.controls.clearRetainingCapacity();
        scan.invocations.clearRetainingCapacity();
        scan.type_mappings.clearRetainingCapacity();
        scan.complete = true;
        _ = scan.value(module, 0, .scalar) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidArtifact;
        var environment: Environment = .{};
        _ = scan.expression(module, @intCast(id), &environment, 0) catch |err| switch (err) {
            error.Unsupported => continue,
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        };
    }
}

pub fn rejectSupportedEscapesWithScratch(module: *const C.Module, owners: []const *const C.Module) error{InvalidArtifact}!void {
    for (module.nodes) |n| if (isScope(n)) return rejectBuffered(module, owners);
}
noinline fn rejectBuffered(module: *const C.Module, owners: []const *const C.Module) error{InvalidArtifact}!void {
    var memory: [1_048_576]u8 align(@alignOf(usize)) = undefined;
    var allocator: std.heap.FixedBufferAllocator = .init(&memory);
    rejectSupportedEscapes(allocator.allocator(), module, owners) catch return error.InvalidArtifact;
}

fn takeReport(scan: *Scan, initial: usize) Error!Report {
    const nodes = try scan.nodes.toOwnedSlice(scan.a);
    errdefer scan.a.free(nodes);
    const edges = try scan.edges.toOwnedSlice(scan.a);
    errdefer scan.a.free(edges);
    const boundaries = try scan.boundaries.toOwnedSlice(scan.a);
    errdefer scan.a.free(boundaries);
    const mappings_ = try scan.type_mappings.toOwnedSlice(scan.a);
    errdefer scan.a.free(mappings_);
    const invocations = try scan.invocations.toOwnedSlice(scan.a);
    scan.evidence_transferred = true;
    return .{ .invocations = invocations, .nodes = nodes, .edges = edges, .evidence = scan.evidence, .mappings = mappings_, .boundaries = boundaries, .complete = scan.complete, .work = initial - scan.remaining };
}

/// A complete execution of one actual lexical scope, charged to its caller's
/// validation budget. This grants no fact when any executable edge is unknown.
pub fn analyzeScope(a: A, module: *const C.Module, owners: []const *const C.Module, root: C.Id, remaining: *usize) Error!Report {
    if (root == 0 or root >= module.nodes.len or !isScope(module.node(root))) return error.InvalidArtifact;
    const all = try a.alloc(*const C.Module, owners.len + 1);
    defer a.free(all);
    all[0] = module;
    var count: usize = 1;
    for (owners) |owner_| {
        if (owner_ == module) continue;
        for (all[0..count]) |prior| {
            try reportStep(remaining);
            if (prior.unit == owner_.unit) return error.InvalidArtifact;
        }
        all[count] = owner_;
        count += 1;
    }
    try @import("frozen_core_validation.zig").validateBounds(module, .{ .units = all[0..count] });
    var scan: Scan = .{ .a = a, .module = module, .owners = all[0..count], .remaining = remaining.*, .scope_validation = true, .evidence = E.Store.init(a) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.AnalysisLimit };
    defer scan.deinit();
    defer remaining.* = scan.remaining;
    const initial = remaining.*;
    try scan.invocations.append(a, .{ .parent = null, .caller = .{ .unit = module.unit, .node = root }, .callable = 0 });
    _ = try scan.value(module, 0, .scalar);
    var environment: Environment = .{};
    _ = try scan.expression(module, root, &environment, 0);
    if (scan.exits.items.len != 0) return error.InvalidArtifact;
    return takeReport(&scan, initial);
}

fn reportStep(remaining: *usize) Error!void {
    if (remaining.* == 0) return error.AnalysisLimit;
    remaining.* -= 1;
}
fn callArgument(report: *const Report, event: Id, field: u32, remaining: *usize) Error!?Id {
    if (event >= report.nodes.len) return error.InvalidArtifact;
    var edge_ = report.nodes[event].first_edge;
    while (edge_) |index| {
        try reportStep(remaining);
        if (index >= report.edges.len) return error.InvalidArtifact;
        const item = report.edges[index];
        if (item.from != event or item.to >= report.nodes.len) return error.InvalidArtifact;
        if (item.kind == .call and item.field == field) return item.to;
        edge_ = item.next;
    }
    return null;
}
/// Match the actual helper invocation to its exact callback/value and a local
/// State write in that invocation's execution subtree. Neither a function type
/// nor a coincidentally equal operation row licenses a storage transfer.
pub fn localStateInvocation(report: *const Report, unit: u32, call: C.Id, callback: u8, argument: u8, remaining: *usize) Error!bool {
    if (!report.complete) return false;
    var found = false;
    for (report.nodes, 0..) |node_, index| {
        try reportStep(remaining);
        if (node_.kind != .event or node_.site.unit != unit or node_.site.node != call) continue;
        const invocation = node_.invocation orelse continue;
        if (invocation >= report.invocations.len) return error.InvalidArtifact;
        const operation = (try callArgument(report, @intCast(index), @as(u32, callback) + 1, remaining)) orelse return false;
        const value = (try callArgument(report, @intCast(index), @as(u32, argument) + 1, remaining)) orelse return false;
        if (report.nodes[operation].kind != .operation) return false;
        var stored = false;
        for (report.nodes, 0..) |write, write_index| {
            try reportStep(remaining);
            if (write.kind != .event or (try callArgument(report, @intCast(write_index), 0, remaining)) != operation or (try callArgument(report, @intCast(write_index), 2, remaining)) != value) continue;
            const cell = (try callArgument(report, @intCast(write_index), 1, remaining)) orelse continue;
            if (report.nodes[cell].kind != .cell) continue;
            var context: ?u32 = write.context;
            while (context) |current| {
                try reportStep(remaining);
                if (current >= report.invocations.len) return error.InvalidArtifact;
                if (current == invocation) {
                    stored = true;
                    break;
                }
                context = report.invocations[current].parent;
            }
            if (stored) break;
        }
        if (!stored) return false;
        found = true;
    }
    return found;
}

pub fn isScope(node: C.Node) bool {
    return node.tag == .effect_scope or (node.tag == .task and (node.c == @backingInt(@import("task_types.zig").Op.scope) or node.c == @backingInt(@import("task_types.zig").Op.split)));
}
