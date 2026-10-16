//! Exact intersection of executable Core and Source activation graphs.
//! Neither graph, emission coordinates, nor a scalar result grants ownership
//! authority alone. Unsupported correspondence declines the whole candidate.
const std = @import("std");
const C = @import("../check/core.zig");
const E = @import("../eval/type_evidence.zig");
const W = @import("wasm.zig");
const G = @import("activation_graph.zig");
const L = @import("../check/capability_lifetimes.zig");
const K = @import("../reuse/code_artifacts.zig");
const A = std.mem.Allocator;
const Error = A.Error || error{Declined};
const absent = std.math.maxInt(u32);

pub const Model = struct {
    units: []const C.Module,
    functions: []const K.Function,
    evidence: E.View,
    rows: K.Substitutions,
    templates: K.Substitutions,
    captures: []const K.CapturedTemplate,
    operations: []const K.Operation,
    identity: ?@import("runtime_identity.zig").View = null,
};
const Context = struct { invocation: u32, callable: ?L.Id = null, event: ?L.Id = null, creation: ?L.Id = null };
pub const Intersection = struct {
    runtime: G.Cohort,
    semantic: L.Report,
    mapping: Mapping,
    pub fn deinit(self: *Intersection, a: A) void {
        self.runtime.deinit(a);
        self.semantic.deinit(a);
        self.mapping.deinit(a);
    }
};
pub const Mapping = struct {
    contexts: []Context,
    members: []L.Id,
    owner: L.Id,
    pub fn deinit(self: Mapping, a: A) void {
        a.free(self.contexts);
        a.free(self.members);
    }
};
const Scan = struct {
    a: A,
    source: *const W.Module,
    model: Model,
    runtime: *const G.Cohort,
    semantic: *L.Report,
    contexts: []Context,
    remaining: usize = 262144,
    fn step(self: *Scan) Error!void {
        if (self.remaining == 0) return error.Declined;
        self.remaining -= 1;
    }
    fn unit(self: *Scan, id: u32) Error!*const C.Module {
        if (id == 0 or id > self.model.units.len) return error.Declined;
        const result = &self.model.units[id - 1];
        if (result.unit != id) return error.Declined;
        return result;
    }
    fn request(self: *Scan, function: u32) Error!K.Request {
        var result: ?K.Request = null;
        for (self.model.functions) |entry| {
            try self.step();
            if (entry.function != function) continue;
            if (result != null) return error.Declined;
            result = entry.request;
        }
        return result orelse error.Declined;
    }
    fn receipt(self: *Scan, function: u32, place: u32) Error!?W.Module.SemanticSite {
        var result: ?W.Module.SemanticSite = null;
        for (self.source.semantic_sites.items) |site| {
            try self.step();
            if (site.function != function or site.place != place) continue;
            if (result != null) return error.Declined;
            const producer = try self.unit(site.unit);
            if (site.node == 0 or site.node >= producer.nodes.len or site.root == 0 or site.root >= producer.nodes.len) return error.Declined;
            result = site;
        }
        return result;
    }
    fn target(self: *Scan, request_: K.Request, callable: L.Id) Error!void {
        if (callable >= self.semantic.nodes.len) return error.Declined;
        const node = self.semantic.nodes[callable];
        const actual = node.target orelse return error.Declined;
        const producer = try self.unit(actual.unit);
        if (actual.node == 0 or actual.node >= producer.nodes.len) return error.Declined;
        switch (request_) {
            .named => |key| {
                if (key.target.unit != actual.unit or key.target.binding != actual.binding) return error.Declined;
                const body = producer.body(actual.binding) orelse return error.Declined;
                if (body.root != actual.node or key.count != body.parameters.len or key.template_result or key.instance_arguments != 0) return error.Declined;
            },
            .callable => |key| {
                if (key.target.unit != actual.unit or key.target.binding != actual.binding) return error.Declined;
                const body = producer.body(actual.binding) orelse return error.Declined;
                if (body.root != actual.node or key.applied >= body.parameters.len) return error.Declined;
                if (key.bound_dictionaries) return error.Declined;
            },
            .closure => |key| {
                if (key.unit != actual.unit or node.closure == null or key.catalog != node.closure.? or key.catalog >= producer.closures.len or key.static_values != 0 or key.staged != 0 or key.template_result) return error.Declined;
                if (producer.closures[key.catalog].body != actual.node) return error.Declined;
            },
            else => return error.Declined,
        }
    }
    fn sameMappings(self: *Scan, site: W.Module.SemanticSite, callable: L.Id) Error!void {
        const node = self.semantic.nodes[callable];
        const evidence = self.model.evidence;
        if (site.mappings == 0 or site.mappings >= evidence.nodes.len or evidence.node(site.mappings).tag != .record) return error.Declined;
        const actual = evidence.children(site.mappings);
        const span = node.mappings;
        if (span.start > self.semantic.mappings.len or span.len > self.semantic.mappings.len - span.start or actual.len != span.len * 2) return error.Declined;
        const wanted = self.semantic.mappings[span.start..][0..span.len];
        var importer: @import("../eval/semantic_evidence_import.zig").Importer = .{ .allocator = self.a, .source = evidence, .destination = &self.semantic.evidence, .max_depth = 128, .remaining = &self.remaining };
        defer importer.deinit();
        for (wanted) |mapping| {
            try self.step();
            var found = false;
            var index: usize = 0;
            while (index < actual.len) : (index += 2) {
                if (actual[index] != mapping.variable) continue;
                const copied = importer.ty(actual[index + 1], 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
                if (copied != mapping.evidence) return error.Declined;
                if (found) return error.Declined;
                found = true;
            }
            if (!found) return error.Declined;
        }
        // The declaration-to-use relation preserves owned symbolic row tails.
        // Source physical substitutions may erase a specialized Demand row;
        // they cannot close or rename the logical caller's row variable.
        const origin = node.target orelse return error.Declined;
        const producer = try self.unit(origin.unit);
        const signature = node.signature orelse return error.Declined;
        const caller = try self.unit(signature.unit);
        const actual_span = node.actual_mappings;
        if (actual_span.start > self.semantic.mappings.len or actual_span.len > self.semantic.mappings.len - actual_span.start or signature.ty >= caller.types.nodes.len) return error.Declined;
        const actual_maps = self.semantic.mappings[actual_span.start..][0..actual_span.len];
        const entries = try self.rowEntries(site.rows);
        if (entries.len > 32) return error.Declined;
        if (node.closure != null) {
            if (node.site.unit != origin.unit or signature.unit != origin.unit or node.site.node == 0 or node.site.node >= producer.nodes.len or signature.ty != producer.typeOf(node.site.node)) return error.Declined;
            for (entries) |entry| if (entry.value != 0) return error.Declined;
            return;
        }
        const body = producer.body(origin.binding) orelse return error.Declined;
        const relation = @import("../check/generative_relocation.zig").Relocation.init(producer, caller, body.scheme, signature.ty, signature.ty, 0, 0) catch return error.Declined;
        const spent = 65536 - relation.remaining;
        if (spent > self.remaining) return error.Declined;
        self.remaining -= spent;
        for (relation.pairs[0..relation.len]) |pair| {
            if (producer.types.node(pair.before).tag != .variable) continue;
            const actual_type = self.semantic.evidence.projectWithBudget(&caller.types, pair.after, actual_maps, &.{}, &self.remaining) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
            var found = false;
            for (wanted) |mapping| if (mapping.variable == pair.before and mapping.evidence == actual_type) {
                found = true;
            };
            if (!found) return error.Declined;
        }
        for (entries) |entry| {
            if (entry.variable >= producer.types.effects.variable_count) return error.Declined;
            var matched = false;
            for (relation.rows[0..relation.row_len]) |row| if (row.variable == entry.variable) {
                // A symbolic tail is carried by the exact owned use signature,
                // never compared to a physically erased empty row.
                if (row.tail != .closed) return error.Declined;
                if (row.labels.len != 0 or entry.value != 0) return error.Declined;
                matched = true;
            };
            if (!matched and entry.value != 0) return error.Declined;
        }
        const request_ = try self.request(site.function);
        if (request_ == .named and request_.named.templates != 0 and body.parameters.len != 0) {
            const parameter = producer.bodyParameters(body)[0];
            const parameter_type = producer.types.node(parameter.ty);
            if (parameter_type.tag == .demand) {
                const row = producer.types.row(parameter_type.c);
                if (row.tail != .variable) return error.Declined;
                try self.demandRow(site.function, callable, row.tail.variable);
            }
        }
    }
    fn demandRow(self: *Scan, function: u32, callable: L.Id, variable: u32) Error!void {
        const request_ = try self.request(function);
        if (request_ != .named) return error.Declined;
        const key = request_.named;
        const producer = try self.unit(key.target.unit);
        const body = producer.body(key.target.binding) orelse return error.Declined;
        if (key.templates == 0 or key.templates > self.model.templates.spans.len or body.parameters.len != 2) return error.Declined;
        const span = self.model.templates.spans[key.templates - 1];
        if (span.start > self.model.templates.entries.len or span.len > self.model.templates.entries.len - span.start or span.len != 1) return error.Declined;
        const template = self.model.templates.entries[span.start];
        const parameter = producer.bodyParameters(body)[0];
        if (template.variable != parameter.binding or parameter.ty >= producer.types.nodes.len or template.value == 0 or template.value > self.model.captures.len) return error.Declined;
        const demand = producer.types.node(parameter.ty);
        if (demand.tag != .demand or demand.c >= producer.types.effects.rows.len or producer.types.row(demand.c).tail != .variable or producer.types.row(demand.c).tail.variable != variable) return error.Declined;
        const memo_id = try self.edge(callable, .capture, 1);
        const memo = self.semantic.nodes[memo_id];
        const capture = self.model.captures[template.value - 1];
        if (memo.kind != .memo or memo.closure == null or capture.unit != memo.site.unit or capture.node != memo.site.node or !capture.demand_cell or !capture.has_environment or capture.computation or capture.templates != 0 or capture.staged != 0 or capture.rows != 0 or capture.evidence != 0) return error.Declined;
        const owner = try self.unit(capture.unit);
        if (capture.node == 0 or capture.node >= owner.nodes.len or owner.node(capture.node).tag != .suspend_ or owner.node(capture.node).a != memo.closure.?) return error.Declined;
        const force = @import("../eval/demand_origins.zig").force(self.source, function) orelse return error.Declined;
        if (force.cell_parameter != 0) return error.Declined;
        try self.target(try self.request(force.producer), memo_id);
    }
    fn rowEntries(self: *Scan, id: u32) Error![]const @import("../reuse/substitution_keys.zig").Entry {
        if (id == 0) return &.{};
        if (id > self.model.rows.spans.len) return error.Declined;
        const span = self.model.rows.spans[id - 1];
        if (span.start > self.model.rows.entries.len or span.len > self.model.rows.entries.len - span.start) return error.Declined;
        return self.model.rows.entries[span.start..][0..span.len];
    }
    fn edge(self: *Scan, from: L.Id, kind: L.EdgeKind, field: u32) Error!L.Id {
        var result: ?L.Id = null;
        for (self.semantic.edges) |entry| {
            try self.step();
            if (entry.from != from or entry.kind != kind or entry.field != field) continue;
            if (result != null and result.? != entry.to) return error.Declined;
            result = entry.to;
        }
        return result orelse error.Declined;
    }
    fn operation(self: *Scan, request_: K.OperationKey, event: L.Id) Error!void {
        if (request_.scoped or request_.operation == 0 or request_.operation > self.model.operations.len) return error.Declined;
        const value = try self.edge(event, .call, 0);
        const node = self.semantic.nodes[value];
        const producer = try self.unit(node.site.unit);
        if (node.kind != .operation or node.site.node == 0 or node.site.node >= producer.nodes.len) return error.Declined;
        const syntax = producer.node(node.site.node);
        if (syntax.tag != .operation_value or syntax.a >= producer.operation_values.len) return error.Declined;
        const metadata = producer.operation_values[syntax.a];
        if (metadata.capability != 0 or metadata.arguments.len > 16 or metadata.arguments.start > producer.types.extra.len or metadata.arguments.len > producer.types.extra.len - metadata.arguments.start) return error.Declined;
        const invocation = self.semantic.invocations[node.context];
        var mappings: []const E.Mapping = &.{};
        if (invocation.callable != 0) {
            const span = self.semantic.nodes[invocation.callable].mappings;
            if (span.start > self.semantic.mappings.len or span.len > self.semantic.mappings.len - span.start) return error.Declined;
            mappings = self.semantic.mappings[span.start..][0..span.len];
        }
        var arguments: [16]u32 = undefined;
        for (producer.types.extra[metadata.arguments.start..][0..metadata.arguments.len], arguments[0..metadata.arguments.len]) |argument, *slot| slot.* = self.semantic.evidence.projectWithBudget(&producer.types, argument, mappings, &.{}, &self.remaining) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
        const label = self.semantic.evidence.effects.internOperationInstance(metadata.identity, arguments[0..metadata.arguments.len], metadata.instance) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
        var operations: @import("runtime_operations.zig").Store = .{ .allocator = self.a, .identity = self.model.identity };
        defer operations.deinit();
        const id = operations.intern(self.semantic.evidence.view(), label) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
        const expected = self.model.operations[request_.operation - 1];
        if (expected.foreign or !std.mem.eql(u8, operations.entries.items[id - 1].key, expected.key)) return error.Declined;
    }
    fn mapContexts(self: *Scan, boundary: C.BindingRef) Error!void {
        if (self.contexts.len == 0 or self.semantic.invocations.len == 0) return error.Declined;
        self.contexts[0] = .{ .invocation = 0 };
        for (self.runtime.graph.contexts[1..], 1..) |context, id| {
            try self.step();
            if (context.parent >= id) return error.Declined;
            const parent = self.contexts[context.parent];
            const parent_function = self.runtime.graph.contexts[context.parent].function;
            const child_request = try self.request(context.function);
            if (try self.receipt(parent_function, context.at)) |site| {
                const invocation = self.semantic.invocations[parent.invocation];
                var parent_target: L.Site = .{ .unit = boundary.unit, .binding = boundary.binding, .node = (try self.unit(boundary.unit)).body(boundary.binding).?.root };
                if (invocation.callable != 0) parent_target = self.semantic.nodes[invocation.callable].target orelse return error.Declined;
                if (site.unit != parent_target.unit or site.root != parent_target.node or site.kind != .call) return error.Declined;
                if (invocation.callable != 0) {
                    try self.sameMappings(site, invocation.callable);
                } else {
                    if (site.mappings == 0 or site.mappings >= self.model.evidence.nodes.len or self.model.evidence.node(site.mappings).tag != .record or self.model.evidence.children(site.mappings).len != 0) return error.Declined;
                    for (try self.rowEntries(site.rows)) |entry| if (entry.value != 0) return error.Declined;
                }
                var selected: ?u32 = null;
                for (self.semantic.invocations, 0..) |candidate, index| {
                    try self.step();
                    if (candidate.parent != parent.invocation or candidate.caller.unit != site.unit or candidate.caller.binding != parent_target.binding or candidate.caller.node != site.node) continue;
                    if (selected != null) return error.Declined;
                    selected = @intCast(index);
                }
                if (selected) |index| {
                    const callable = self.semantic.invocations[index].callable;
                    try self.target(child_request, callable);
                    self.contexts[id] = .{ .invocation = index, .callable = callable };
                } else if (child_request == .operation) {
                    var selected_event: ?u32 = null;
                    for (self.semantic.nodes, 0..) |node, index| {
                        try self.step();
                        if (node.context != parent.invocation or node.kind != .event or node.site.unit != site.unit or node.site.binding != parent_target.binding or node.site.node != site.node) continue;
                        if (selected_event != null) return error.Declined;
                        selected_event = @intCast(index);
                    }
                    const event = selected_event orelse return error.Declined;
                    try self.operation(child_request.operation, event);
                    self.contexts[id] = .{ .invocation = parent.invocation, .event = event };
                } else {
                    // A partial application constructs a callable without
                    // entering its declaring body.
                    if (child_request != .callable or child_request.callable.applied != 0) return error.Declined;
                    var creation: ?u32 = null;
                    for (self.semantic.nodes, 0..) |node, index| {
                        try self.step();
                        if (node.context != parent.invocation or node.site.unit != site.unit or node.site.node != site.node or node.kind != .callable) continue;
                        if (creation != null) return error.Declined;
                        creation = @intCast(index);
                    }
                    const callable = creation orelse return error.Declined;
                    try self.target(child_request, callable);
                    self.contexts[id] = .{ .invocation = parent.invocation, .creation = callable, .callable = callable };
                }
            } else {
                // Synthetic applied-call adapters have no Core expression.
                // Contract only their exact declaring target and argument
                // progression; the executable graph still checks the body.
                const parent_request = try self.request(parent_function);
                if (parent_request != .callable or child_request != .named or parent.callable == null) return error.Declined;
                if (!std.meta.eql(parent_request.callable.target, child_request.named.target) or parent_request.callable.applied + 1 != child_request.named.count) return error.Declined;
                try self.target(child_request, parent.callable.?);
                self.contexts[id] = parent;
            }
        }
        for (self.semantic.invocations, 0..) |_, invocation| {
            var mapped = false;
            for (self.contexts) |context| mapped = mapped or context.invocation == invocation;
            if (!mapped) return error.Declined;
        }
    }
    fn semanticAt(self: *Scan, site: W.Module.SemanticSite, context: u32, kind: L.Kind) Error!L.Id {
        if (context >= self.semantic.invocations.len) return error.Declined;
        const invocation = self.semantic.invocations[context];
        const target_ = if (invocation.callable == 0) invocation.caller else self.semantic.nodes[invocation.callable].target orelse return error.Declined;
        const root = if (invocation.callable == 0) (try self.unit(target_.unit)).body(target_.binding).?.root else target_.node;
        if (site.unit != target_.unit or site.root != root) return error.Declined;
        if (invocation.callable != 0) {
            try self.sameMappings(site, invocation.callable);
        } else {
            if (site.mappings == 0 or site.mappings >= self.model.evidence.nodes.len or self.model.evidence.node(site.mappings).tag != .record or self.model.evidence.children(site.mappings).len != 0) return error.Declined;
            for (try self.rowEntries(site.rows)) |entry| if (entry.value != 0) return error.Declined;
        }
        var result: ?L.Id = null;
        for (self.semantic.nodes, 0..) |node, id| {
            try self.step();
            if (node.kind != kind or node.context != context or node.site.unit != site.unit or node.site.binding != target_.binding or node.site.node != site.node) continue;
            if (result != null) return error.Declined;
            result = @intCast(id);
        }
        return result orelse error.Declined;
    }
    fn construction(self: *Scan, site: G.Site) Error!@import("callable_origins.zig").Construction {
        var result: ?@import("callable_origins.zig").Construction = null;
        for (self.source.table_origins.items) |origin| {
            try self.step();
            if (origin.function != site.function) continue;
            const fact = @import("callable_origins.zig").construction(self.source, origin) orelse continue;
            if (fact.allocation != site.at) continue;
            if (result != null) return error.Declined;
            result = fact;
        }
        return result orelse error.Declined;
    }
    fn mapSites(self: *Scan, members: []L.Id) Error!L.Id {
        @memset(members, absent);
        const owner_site = self.runtime.graph.sites[self.runtime.owner];
        const owner_receipt = (try self.receipt(owner_site.function, owner_site.at)) orelse return error.Declined;
        if (owner_receipt.kind != .allocation) return error.Declined;
        const owner = try self.semanticAt(owner_receipt, 0, .cell);
        const scope = self.semantic.nodes[owner].owner;
        if (scope >= self.semantic.nodes.len or self.semantic.nodes[scope].kind != .activation) return error.Declined;
        members[self.runtime.owner] = owner;
        var pending = self.runtime.members;
        while (pending != 0) {
            const id: u6 = @intCast(@ctz(pending));
            pending &= pending - 1;
            const site = self.runtime.graph.sites[id];
            const context = self.contexts[site.context];
            var value: L.Id = undefined;
            switch (site.kind) {
                .memo => {
                    const receipt_ = (try self.receipt(site.function, site.at)) orelse return error.Declined;
                    if (receipt_.kind != .allocation) return error.Declined;
                    value = try self.semanticAt(receipt_, context.invocation, .memo);
                    if (!self.semantic.nodes[value].ready) return error.Declined;
                    const fact = try self.construction(site);
                    if (fact.kind != .demand or fact.environment != .zero or site.bytes != fact.bytes) return error.Declined;
                    try self.target(try self.request(fact.target), value);
                    for (self.semantic.edges) |edge_| if (edge_.from == value and edge_.kind == .capture and edge_.to != 0) return error.Declined;
                },
                .closure => {
                    value = context.creation orelse return error.Declined;
                    const fact = @import("callable_origins.zig").resultConstruction(self.source, site.function) orelse return error.Declined;
                    if (fact.allocation != site.at or fact.environment != .local or fact.environment.local != 1 or fact.kind != .callable or site.bytes != fact.bytes) return error.Declined;
                    const declaring = try self.request(site.function);
                    const applied = try self.request(fact.target);
                    if (declaring != .callable or applied != .callable or declaring.callable.applied != 0 or applied.callable.applied != 1 or !std.meta.eql(declaring.callable.target, applied.callable.target) or declaring.callable.templates != applied.callable.templates) return error.Declined;
                    try self.target(applied, value);
                    const original = try self.edge(value, .capture, 0);
                    if (self.semantic.nodes[original].kind != .callable or self.semantic.nodes[original].first_edge != null) return error.Declined;
                    try self.target(declaring, original);
                },
                .ordinary => {
                    const receipt_ = (try self.receipt(site.function, site.at)) orelse return error.Declined;
                    if (receipt_.kind != .allocation or site.bytes != 8) return error.Declined;
                    value = try self.semanticAt(receipt_, context.invocation, .nominal);
                    const producer = try self.unit(receipt_.unit);
                    const node = producer.node(receipt_.node);
                    if (node.tag != .construct or node.a >= producer.constructors.len) return error.Declined;
                    const constructor = producer.constructors[node.a];
                    if (constructor.nominal >= producer.nominals.len or !std.meta.eql(producer.nominals[constructor.nominal].identity, self.semantic.nodes[value].nominal) or constructor.tag != self.semantic.nodes[value].field or node.b == 0) return error.Declined;
                    const code = self.source.functions.items[site.function].instructions.items;
                    const at = site.at;
                    if (at + 7 >= code.len or code[at + 1].op != .local_set or code[at + 2].op != .local_get or code[at + 2].operand != code[at + 1].operand or code[at + 3].op != .i32_const or code[at + 3].table_reference or code[at + 3].operand != constructor.tag or code[at + 4].op != .i32_store or code[at + 4].operand != 0 or code[at + 5].op != .local_get or code[at + 5].operand != code[at + 1].operand or code[at + 6].op != .local_get or code[at + 7].op != .i32_store or code[at + 7].operand != 4) return error.Declined;
                },
                else => return error.Declined,
            }
            if (self.semantic.nodes[value].owner != scope) return error.Declined;
            for (members) |mapped| if (mapped != absent and mapped == value) return error.Declined;
            members[id] = value;
        }
        // Every operation in this activation addresses this exact installation.
        for (self.contexts) |context| if (context.event) |event| {
            if (try self.edge(event, .call, 1) != owner) return error.Declined;
        };
        for (self.runtime.graph.stores) |store| {
            var owners = store.owners & (self.runtime.members | (@as(u64, 1) << self.runtime.owner));
            while (owners != 0) {
                const id: u6 = @intCast(@ctz(owners));
                owners &= owners - 1;
                const physical = self.runtime.graph.sites[id];
                const semantic = members[id];
                var expected: ?L.Id = null;
                if (id == self.runtime.owner) {
                    if (store.offset != 4) continue;
                    if (self.contexts[store.context].event) |event| expected = try self.edge(event, .call, 2) else {
                        // Initial immutable state remains ordinary storage.
                        if (store.values & self.runtime.members != 0) return error.Declined;
                        continue;
                    }
                } else switch (physical.kind) {
                    .memo => {
                        if (store.offset == 4) {
                            if (store.values != 0) return error.Declined;
                            continue;
                        }
                        if (store.offset != 12) {
                            if (store.values != 0) return error.Declined;
                            continue;
                        }
                        expected = self.semantic.nodes[semantic].contents;
                    },
                    .closure => {
                        if (store.offset != 4) {
                            if (store.values != 0) return error.Declined;
                            continue;
                        }
                        expected = try self.edge(semantic, .capture, 1);
                    },
                    .ordinary => {
                        if (store.offset != 4) {
                            if (store.values != 0) return error.Declined;
                            continue;
                        }
                        expected = try self.edge(semantic, .value, 0);
                    },
                    else => return error.Declined,
                }
                // A null initialization does not publish a completed cache.
                if (physical.kind == .memo and store.values == 0) continue;
                var values = store.values;
                var owns_expected = false;
                while (values != 0) {
                    const child: u6 = @intCast(@ctz(values));
                    values &= values - 1;
                    if (members[child] != absent) {
                        if (members[child] != expected.?) return error.Declined;
                        owns_expected = true;
                    } else if (self.runtime.graph.sites[child].kind != .static_data or self.runtime.graph.sites[child].children != 0) return error.Declined;
                }
                var semantic_is_member = false;
                for (members) |mapped| if (mapped != absent and mapped == expected.?) {
                    semantic_is_member = true;
                };
                if (semantic_is_member != owns_expected) return error.Declined;
            }
        }
        return owner;
    }
};

/// Rederive both reports and their exact owned correspondence. Callers must
/// retain the immutable Core and current request pools throughout this query.
pub fn analyze(a: A, source: *const W.Module, model: Model, boundary: u32) A.Error!?Intersection {
    return analyzeChecked(a, source, model, boundary) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
}
fn analyzeChecked(a: A, source: *const W.Module, model: Model, boundary: u32) Error!Intersection {
    var runtime = (G.cohort(a, source, boundary) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined) orelse return error.Declined;
    errdefer runtime.deinit(a);
    var request_: ?K.Request = null;
    for (model.functions) |entry| if (entry.function == boundary) {
        if (request_ != null) return error.Declined;
        request_ = entry.request;
    };
    const root = request_ orelse return error.Declined;
    if (root != .named) return error.Declined;
    const target_ = root.named.target;
    if (target_.unit == 0 or target_.unit > model.units.len) return error.Declined;
    const owners = try a.alloc(*const C.Module, model.units.len);
    defer a.free(owners);
    for (owners, model.units) |*owner, *unit_| owner.* = unit_;
    var semantic = L.analyze(a, &model.units[target_.unit - 1], owners, target_) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
    errdefer semantic.deinit(a);
    if (!semantic.complete) return error.Declined;
    const mapped = try correspondence(a, source, model, &runtime, &semantic, target_);
    return .{ .runtime = runtime, .semantic = semantic, .mapping = mapped };
}

/// Independent allocation boundary for testing new mapping ownership. This
/// returns coordinates only; the production consumer rederives both reports.
pub fn correspondence(a: A, source: *const W.Module, model: Model, runtime: *const G.Cohort, semantic: *const L.Report, boundary: C.BindingRef) Error!Mapping {
    var local = semantic.*;
    local.evidence = try semantic.evidence.clone(a);
    defer local.evidence.deinit();
    const contexts = try a.alloc(Context, runtime.graph.contexts.len);
    errdefer a.free(contexts);
    var scan: Scan = .{ .a = a, .source = source, .model = model, .runtime = runtime, .semantic = &local, .contexts = contexts };
    try scan.mapContexts(boundary);
    const members = try a.alloc(L.Id, runtime.graph.sites.len);
    errdefer a.free(members);
    const owner = try scan.mapSites(members);
    return .{ .contexts = contexts, .members = members, .owner = owner };
}
