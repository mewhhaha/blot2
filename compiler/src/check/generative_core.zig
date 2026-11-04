//! Invocation claims are checked against the immutable expression that creates
//! the selection. A closure capture alone never declares another invocation.
const std = @import("std");
const C = @import("core.zig");
const T = @import("types.zig");
const equal = @import("rank_equal.zig").equal;
const Error = error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
const Fact = struct { arrow: T.Id, selected: T.Id, value: C.Id };
const Site = struct { point: u32, ordinal: u32, node: C.Id };
const Sites = struct {
    values: [4096]Site = undefined,
    len: usize = 0,
    fn claim(self: *Sites, version: T.Node, node: C.Id) Error!void {
        for (self.values[0..self.len]) |site| if (site.point == version.b and site.ordinal == version.c) {
            try require(site.node == node);
            return;
        };
        try require(self.len < self.values.len);
        self.values[self.len] = .{ .point = version.b, .ordinal = version.c, .node = node };
        self.len += 1;
    }
};
const Scan = struct {
    module: *const C.Module,
    owners: []const *const C.Module,
    graph: @import("frozen_core_validation.zig").Graph,
    sites: *Sites,
    variables: T.List,
    facts: [256]Fact = undefined,
    len: usize = 0,
    remaining: usize = 65_536,
    fn ownerModule(self: *const Scan, unit: u32) Error!*const C.Module {
        if (unit == 0 or unit == self.module.unit) return self.module;
        for (self.owners) |owner| if (owner.unit == unit) return owner;
        return error.InvalidArtifact;
    }
    fn same(self: *const Scan, left: T.Id, right: T.Id) Error!bool {
        return equal(&self.module.types, left, right, true) catch return error.InvalidArtifact;
    }
    fn arrow(self: *const Scan, left: T.Id, right: T.Id) Error!bool {
        const a = self.module.types.node(left);
        const b = self.module.types.node(right);
        if (a.tag != .function or b.tag != .function) return false;
        // Generalization only closes the owned ambient tail.
        return try self.same(a.a, b.a) and try self.same(a.b, b.b) and std.mem.eql(T.Effects.Label, self.module.types.rowLabels(a.c), self.module.types.rowLabels(b.c));
    }
    fn selected(self: *const Scan, ty: T.Id) ?T.Node {
        const value = self.module.types.node(ty);
        if (value.tag != .scoped or value.b != 0) return null;
        const term = self.module.types.node(value.c);
        if (term.tag != .instance_selection or self.module.types.nominalArguments(term).len != 3) return null;
        return term;
    }
    fn fact(self: *Scan, arrow_: T.Id, ty: T.Id, value_: C.Id) Error!void {
        if (arrow_ == 0) return;
        for (self.facts[0..self.len]) |value| if (value.value == value_ and try self.arrow(value.arrow, arrow_) and try self.same(value.selected, ty)) return;
        try require(self.len < self.facts.len);
        self.facts[self.len] = .{ .arrow = arrow_, .selected = ty, .value = value_ };
        self.len += 1;
    }
    fn callResult(self: *Scan, id: C.Id, arrow_: T.Id, value_: C.Id, root: T.Id, depth: usize) Error!void {
        if (root == 0) return;
        try require(depth < 128 and self.remaining != 0);
        self.remaining -= 1;
        if (self.selected(root)) |term| {
            const version = self.module.types.node(self.module.types.nominalArguments(term)[2]);
            if (version.a == self.module.unit and version.b == self.module.span(id).end + 1) {
                try self.calledBinder(id, term);
                try self.sites.claim(version, id);
                try self.fact(arrow_, root, value_);
            }
            return;
        }
        const n = self.module.types.node(root);
        switch (n.tag) {
            .function => {
                try self.callResult(id, arrow_, value_, n.a, depth + 1);
                try self.callResult(id, arrow_, value_, n.b, depth + 1);
                try self.callRows(id, arrow_, value_, n.c, depth + 1);
            },
            .demand, .provider => {
                try self.callResult(id, arrow_, value_, n.a, depth + 1);
                try self.callRows(id, arrow_, value_, n.c, depth + 1);
            },
            .usage, .array, .list, .cursor, .resolver => try self.callResult(id, arrow_, value_, n.a, depth + 1),
            .state_provider => for ([_]T.Id{ n.a, n.b, n.c }) |child| try self.callResult(id, arrow_, value_, child, depth + 1),
            .product => for (self.module.types.list(.{ .start = n.a, .len = n.b })) |child| try self.callResult(id, arrow_, value_, child, depth + 1),
            .record => for (0..n.b) |i| try self.callResult(id, arrow_, value_, self.module.types.recordField(n, i).ty, depth + 1),
            .nominal => for (self.module.types.nominalArguments(n)) |child| try self.callResult(id, arrow_, value_, child, depth + 1),
            else => {},
        }
    }
    fn calledBinder(self: *const Scan, id: C.Id, selection: T.Node) Error!void {
        const call = @import("capability_flow.zig").coreCall(self.module, id) orelse return error.InvalidArtifact;
        const reference = call.target;
        const owner = try self.ownerModule(reference.unit);
        if (reference.binding >= owner.bindings.len) return error.InvalidArtifact;
        if (try self.formalBinder(id, selection, owner, call)) return;
        const binding = owner.bindings[reference.binding];
        const scheme_ = binding.scheme;
        if (binding.kind == .local) {
            try require(owner == self.module and binding.initializer != 0 and try self.callbackValue(binding.initializer, scheme_.root, 0));
        } else try require(binding.kind == .global);
        try require(call.len != 0 and call.len <= 16 and scheme_.root < owner.types.nodes.len);
        var declaring: T.Id = 0;
        var root = scheme_.root;
        for (0..call.len) |_| {
            try require(root < owner.types.nodes.len);
            const value = owner.types.node(root);
            try require(value.tag == .function);
            declaring = root;
            root = value.b;
        }
        const span = owner.bindings[reference.binding].scheme.generative;
        try require(span.len <= 32 and span.len % 2 == 0 and span.start <= owner.types.extra.len and span.len <= owner.types.extra.len - span.start);
        const words = owner.types.list(span);
        for (0..words.len / 2) |index| {
            try require(words[index * 2] < owner.types.nodes.len and words[index * 2 + 1] < owner.types.nodes.len);
            const scope = owner.types.node(words[index * 2 + 1]);
            try require(scope.tag == .scoped and scope.b == 0 and scope.c < owner.types.nodes.len);
            const term = owner.types.node(scope.c);
            try require(term.tag == .instance_selection);
            if (term.a != selection.a or term.b != selection.b) continue;
            const arrow_ = owner.types.node(words[index * 2]);
            const called = owner.types.node(declaring);
            try require(arrow_.tag == .function);
            if (!(equal(&owner.types, arrow_.a, called.a, true) catch false) or !(equal(&owner.types, arrow_.b, called.b, true) catch false)) continue;
            const relocation = @import("generative_relocation.zig");
            if (!std.mem.eql(T.Effects.Label, try relocation.labels(&owner.types, arrow_.c), try relocation.labels(&owner.types, called.c))) continue;
            var actual = call.signature;
            for (call.arguments[0..call.len]) |argument| {
                try require(actual < self.module.types.nodes.len);
                const parameter = self.module.types.node(actual);
                try require(parameter.tag == .function and (equal(&self.module.types, parameter.a, self.module.node(argument).ty, true) catch false));
                actual = parameter.b;
            }
            var map = try @import("generative_relocation.zig").Relocation.init(owner, self.module, scheme_, call.signature, self.module.node(id).ty, call.len, self.module.span(id).end + 1);
            try map.applications(id);
            return;
        }
        return error.InvalidArtifact;
    }
    const Creators = struct {
        values: [16]C.Id = undefined,
        len: usize = 0,
        remaining: usize = 4096,
        fn visit(self: *Creators) Error!void {
            try require(self.remaining != 0);
            self.remaining -= 1;
        }
        fn add(self: *Creators, value: C.Id) Error!void {
            for (self.values[0..self.len]) |prior| if (prior == value) return;
            try require(self.len < self.values.len);
            self.values[self.len] = value;
            self.len += 1;
        }
    };
    fn valueOrigins(self: *const Scan, id: C.Id, expected: T.Id, values: *Creators, depth: usize) Error!bool {
        try values.visit();
        try require(depth < 64 and id != 0 and id < self.module.nodes.len);
        const node = self.module.node(id);
        try require(node.ty < self.module.types.nodes.len and expected < self.module.types.nodes.len);
        try @import("generative_relocation.zig").Relocation.invoked(self.module, self.variables, node.ty, expected, &.{}, 0);
        if (node.tag == .reference) {
            const reference = self.module.reference(id);
            if (reference.unit != 0 and reference.unit != self.module.unit) return false;
            try require(reference.binding < self.module.bindings.len);
            const binding = self.module.bindings[reference.binding];
            if (binding.initializer == 0) return false;
            try require(binding.initializer < self.module.nodes.len);
            const raw = self.module.node(binding.initializer).ty;
            const relocation = @import("generative_relocation.zig").Relocation;
            try relocation.generalized(self.module, binding.scheme, raw);
            _ = try relocation.init(self.module, self.module, binding.scheme, node.ty, node.ty, 0, 0);
            return self.valueOrigins(binding.initializer, raw, values, depth + 1);
        }
        if (node.tag == .if_value) {
            const left = try self.valueOrigins(node.b, expected, values, depth + 1);
            const right = try self.valueOrigins(node.c, expected, values, depth + 1);
            return left and right;
        }
        if (node.tag == .project) {
            try require(node.b < self.module.projections.len);
            const recipe = self.module.projections[node.b];
            try require(recipe.source_type < self.module.types.nodes.len and recipe.result_type < self.module.types.nodes.len);
            if (recipe.nominal.unit != 0 or recipe.nominal.decl != 0) return false;
            try require(try self.same(recipe.result_type, expected));
            try require(recipe.variants.len == 1 and recipe.variants.start < self.module.projection_variants.len);
            const variant = self.module.projection_variants[recipe.variants.start];
            try require(variant.tag == 0);
            const container = self.module.types.node(recipe.source_type);
            if (container.tag != .record and container.tag != .product) return false;
            try require(variant.field < container.b);
            var field_type: T.Id = 0;
            if (container.tag == .record) {
                const field = self.module.types.recordField(container, variant.field);
                try require(recipe.field == 0 or recipe.field == field.name);
                field_type = field.ty;
            } else {
                try require(recipe.field == 0);
                field_type = self.module.types.list(.{ .start = container.a, .len = container.b })[variant.field];
            }
            try require(try self.same(field_type, expected));
            var receivers: Creators = .{ .remaining = values.remaining };
            if (!try self.valueOrigins(node.a, recipe.source_type, &receivers, depth + 1)) return false;
            values.remaining = receivers.remaining;
            for (receivers.values[0..receivers.len]) |receiver| {
                const value = self.module.node(receiver);
                if (container.tag == .record) {
                    if (value.tag != .record) return false;
                } else if (value.tag != .product) return false;
                try require(value.b == container.b and value.a <= self.module.extra.len and value.b <= self.module.extra.len - value.a);
                var argument: C.Id = 0;
                if (value.tag == .record) {
                    try require(value.c <= self.module.extra.len and value.b <= self.module.extra.len - value.c);
                    for (self.module.extra[value.c..][0..value.b], 0..) |destination, index| {
                        try require(destination < container.b);
                        if (destination != variant.field) continue;
                        try require(argument == 0);
                        argument = self.module.extra[value.a + index];
                    }
                } else argument = self.module.extra[value.a + variant.field];
                try require(argument != 0);
                try require(value.ty < self.module.types.nodes.len);
                const raw_container = self.module.types.node(value.ty);
                try require(raw_container.tag == container.tag and raw_container.b == container.b);
                var raw_field: T.Id = 0;
                if (raw_container.tag == .record) {
                    const field = self.module.types.recordField(raw_container, variant.field);
                    try require(field.name == self.module.types.recordField(container, variant.field).name);
                    raw_field = field.ty;
                } else raw_field = self.module.types.list(.{ .start = raw_container.a, .len = raw_container.b })[variant.field];
                if (!try self.valueOrigins(argument, raw_field, values, depth + 1)) return false;
            }
            return true;
        }
        if (node.tag != .record and node.tag != .product and node.tag != .closure and node.tag != .suspend_ and node.tag != .call and node.tag != .apply) return false;
        try values.add(id);
        return true;
    }
    fn callbackCreators(self: *const Scan, id: C.Id, expected: T.Id, creators: *Creators, depth: usize) Error!bool {
        try creators.visit();
        try require(depth < 64 and id != 0 and id < self.module.nodes.len);
        const node = self.module.node(id);
        if (!try self.arrow(node.ty, expected)) return false;
        if (node.tag == .reference) {
            const reference = self.module.reference(id);
            const owner = try self.ownerModule(reference.unit);
            try require(reference.binding < owner.bindings.len);
            const binding = owner.bindings[reference.binding];
            if (owner == self.module and binding.initializer != 0) return self.callbackCreators(binding.initializer, expected, creators, depth + 1);
            // These unary bodies transfer an existing input or issue a Unit
            // request. Their exact body supplies an empty declaring set.
            const flow = @import("capability_flow.zig");
            if (binding.kind != .global or binding.body_id == 0 or binding.body_id >= owner.bodies.len) return false;
            const body = owner.bodies[binding.body_id];
            try require(binding.scheme.generative.len == 0 and body.scheme.generative.len == 0);
            if (binding.capability_flow == .identity or binding.capability_flow == .member_unit) {
                try require(flow.unaryCore(owner, body, binding.capability_flow));
            } else {
                if (binding.capability_flow != .input_shape or !@import("capability_contract_core.zig").inputBody(owner, body, binding.capability_parameters)) return false;
            }
            _ = try @import("generative_relocation.zig").Relocation.init(owner, self.module, binding.scheme, node.ty, node.ty, 0, 0);
            try creators.add(id);
            return true;
        }
        if (node.tag == .if_value) {
            const left = try self.callbackCreators(node.b, expected, creators, depth + 1);
            const right = try self.callbackCreators(node.c, expected, creators, depth + 1);
            return left and right;
        }
        if (node.tag == .project) {
            var values: Creators = .{ .remaining = creators.remaining };
            if (!try self.valueOrigins(id, expected, &values, depth + 1)) return false;
            creators.remaining = values.remaining;
            for (values.values[0..values.len]) |value| if (!try self.callbackCreators(value, expected, creators, depth + 1)) return false;
            return true;
        }
        if (node.tag != .closure and node.tag != .suspend_ and node.tag != .call and node.tag != .apply) return false;
        for (self.facts[0..self.len]) |fact_| if (fact_.value == id and try self.arrow(fact_.arrow, expected)) {
            try creators.add(id);
            return true;
        };
        // A proven capture-only creator has an empty declaration set. It must
        // still participate in branch agreement instead of borrowing another
        // equal arrow's declarations or skipping the result relationship.
        if (node.tag == .closure or node.tag == .suspend_) {
            try require(node.a < self.module.closures.len);
            const closure = self.module.closures[node.a];
            try require(try self.arrow(node.ty, closure.function_type));
            try require(closure.body != 0 and closure.body < self.module.nodes.len);
            try require(try self.same(self.module.types.node(node.ty).b, self.module.node(closure.body).ty));
        } else {
            const call = @import("capability_flow.zig").coreCall(self.module, id) orelse return false;
            const owner = try self.ownerModule(call.target.unit);
            try require(call.target.binding < owner.bindings.len);
            const binding = owner.bindings[call.target.binding];
            if (binding.kind != .global) return false;
            var map = try @import("generative_relocation.zig").Relocation.init(owner, self.module, binding.scheme, call.signature, node.ty, call.len, self.module.span(id).end + 1);
            try map.applications(id);
        }
        try creators.add(id);
        return true;
    }
    fn callbackValue(self: *const Scan, id: C.Id, expected: T.Id, depth: usize) Error!bool {
        var creators: Creators = .{};
        return self.callbackCreators(id, expected, &creators, depth);
    }
    fn creatorVersions(self: *const Scan, creator: C.Id, arrow_: T.Id, versions: *[16]T.Id) Error!usize {
        var count: usize = 0;
        for (self.facts[0..self.len]) |fact_| {
            if (fact_.value != creator or !try self.arrow(arrow_, fact_.arrow)) continue;
            const term = self.selected(fact_.selected) orelse return error.InvalidArtifact;
            const version = self.module.types.nominalArguments(term)[2];
            var known = false;
            for (versions[0..count]) |prior| if (try self.same(prior, version)) {
                known = true;
                break;
            };
            if (known) continue;
            try require(count < versions.len);
            versions[count] = version;
            count += 1;
        }
        return count;
    }
    fn sameVersions(self: *const Scan, left: []const T.Id, right: []const T.Id) Error!bool {
        if (left.len != right.len) return false;
        for (left) |version| {
            var found = false;
            for (right) |other| if (try self.same(version, other)) {
                found = true;
                break;
            };
            if (!found) return false;
        }
        return true;
    }
    fn versionReachable(self: *const Scan, vertex: usize, remaining: *usize, depth: usize) Error!bool {
        try require(depth < 128 and remaining.* != 0);
        remaining.* -= 1;
        const item = self.graph.item(vertex);
        if (item.kind == .type_ and self.module.types.nodes[item.id].tag == .instance_version) return true;
        if (item.kind == .operation) {
            const instance = self.module.types.operations[item.id].instance;
            if (instance.unit == 0 and instance.decl != 0 and try self.versionReachable(self.graph.vertex(.type_, instance.decl), remaining, depth + 1)) return true;
        }
        var slot: usize = 0;
        while (self.graph.edge(vertex, slot)) |child| : (slot += 1) if (try self.versionReachable(child, remaining, depth + 1)) return true;
        return false;
    }
    fn formalBinder(self: *const Scan, id: C.Id, selection: ?T.Node, owner: *const C.Module, call: @import("capability_flow.zig").LocalCoreCall) Error!bool {
        const binding = owner.bindings[call.target.binding];
        var callback: usize = 0;
        if (binding.capability_flow == .invoke_unit) {
            if (call.len != 1) return false;
        } else {
            const contract = binding.capability_parameters;
            if (!contract.invokes() or !contract.valid() or contract.arity() != call.len) return false;
            callback = contract.callback();
        }
        var actual = call.signature;
        for (call.arguments[0..call.len]) |argument| {
            try require(actual < self.module.types.nodes.len);
            const parameter = self.module.types.node(actual);
            try require(parameter.tag == .function and try self.same(parameter.a, self.module.node(argument).ty));
            actual = parameter.b;
        }
        const callback_type = self.module.node(call.arguments[callback]).ty;
        try require(callback_type != 0 and callback_type < self.module.types.nodes.len);
        const function = self.module.types.node(callback_type);
        var callback_result = callback_type;
        if (binding.capability_parameters.inputInvokes()) {
            const contract = binding.capability_parameters;
            for (0..contract.argumentCount()) |index| {
                try require(callback_result != 0 and callback_result < self.module.types.nodes.len);
                const callable = self.module.types.node(callback_result);
                const argument = self.module.node(call.arguments[contract.argumentAt(index)]);
                try require(callable.tag == .function and try self.same(callable.a, argument.ty));
                callback_result = callable.b;
            }
        } else {
            try require(function.tag == .function and function.a == T.unit);
            callback_result = function.b;
        }
        try require(try self.same(callback_result, actual));
        const endpoint = self.module.span(id).end + 1;
        const relocation = @import("generative_relocation.zig");
        _ = try relocation.Relocation.init(owner, self.module, binding.scheme, call.signature, callback_result, call.len, endpoint);
        var creators: Creators = .{};
        if (!try self.callbackCreators(call.arguments[callback], callback_type, &creators, 0)) {
            if (selection != null or creators.len != 0) return error.InvalidArtifact;
            // Unchanged output cannot stand in for an unavailable invocation
            // owner. A hidden declaring callback still creates fresh versions.
            var remaining: usize = 4096;
            try require(!try self.versionReachable(self.graph.vertex(.type_, callback_result), &remaining, 0));
            try require(try self.same(callback_result, self.module.node(id).ty));
            return true;
        }
        var versions: [16]T.Id = undefined;
        const count = try self.creatorVersions(creators.values[0], callback_type, &versions);
        for (creators.values[1..creators.len]) |creator| {
            var other: [16]T.Id = undefined;
            const length = try self.creatorVersions(creator, callback_type, &other);
            // A captured version in one branch cannot become generative merely
            // because another equal-typed callback declares that version.
            try require(try self.sameVersions(versions[0..count], other[0..length]));
        }
        if (selection) |selected_| {
            var found = false;
            for (self.facts[0..self.len]) |fact_| {
                if (fact_.value != creators.values[0] or !try self.arrow(callback_type, fact_.arrow)) continue;
                const term = self.selected(fact_.selected) orelse return error.InvalidArtifact;
                if (term.a == selected_.a and term.b == selected_.b) found = true;
            }
            try require(found);
        }
        try relocation.Relocation.invoked(self.module, self.variables, function.b, self.module.node(id).ty, versions[0..count], endpoint);
        return true;
    }
    fn returnedBinders(self: *Scan, id: C.Id) Error!void {
        const call = @import("capability_flow.zig").coreCall(self.module, id) orelse return;
        const owner = try self.ownerModule(call.target.unit);
        try require(call.target.binding < owner.bindings.len);
        const binding_ = owner.bindings[call.target.binding];
        const scheme_ = binding_.scheme;
        if (scheme_.generative.len == 0) return;
        if (binding_.body_id == 0 or binding_.body_id >= owner.bodies.len or owner.bodies[binding_.body_id].parameters.len < call.len) return;
        var map = try @import("generative_relocation.zig").Relocation.init(owner, self.module, scheme_, call.signature, self.module.node(id).ty, call.len, self.module.span(id).end + 1);
        try map.applications(id);
        const words = owner.types.list(scheme_.generative);
        for (0..words.len / 2) |index| {
            const arrow_ = map.get(words[index * 2]) orelse continue;
            var remaining: usize = 65_536;
            if (!try self.reachable(self.module.node(id).ty, arrow_, 0, &remaining)) continue;
            try self.fact(arrow_, map.get(words[index * 2 + 1]) orelse return error.InvalidArtifact, id);
        }
    }
    fn callRows(self: *Scan, id: C.Id, arrow_: T.Id, value_: C.Id, row: T.Effects.Id, depth: usize) Error!void {
        for (self.module.types.rowLabels(row)) |label| {
            const operation = self.module.types.operation(label);
            if (operation.instance.unit != 0 or operation.instance.decl == 0) continue;
            for (self.module.types.nodes, 0..) |node, selected_| {
                if (node.tag == .scoped and node.b == 0 and node.c == operation.instance.decl) {
                    try self.callResult(id, arrow_, value_, @intCast(selected_), depth + 1);
                    break;
                }
            }
        }
    }
    fn expression(self: *Scan, vertex: usize, declaring_arrow: T.Id, declaring_value: C.Id, application_parent: C.Id, depth: usize) Error!void {
        try require(depth < 128 and self.remaining != 0);
        self.remaining -= 1;
        const item = self.graph.item(vertex);
        var arrow_ = declaring_arrow;
        var value_ = declaring_value;
        if (item.kind == .node) {
            if (item.id == 0) return;
            const id: C.Id = @intCast(item.id);
            const n = self.module.node(id);
            if (self.selected(n.ty)) |term| {
                const args = self.module.types.nominalArguments(term);
                const version = self.module.types.node(args[2]);
                if (n.tag == .if_value) {
                    try require(term.a == self.module.unit and version.a == self.module.unit and version.b == self.module.span(id).end + 1);
                    try self.sites.claim(version, id);
                    try require(try self.same(args[0], self.module.node(n.b).ty) and try self.same(args[1], self.module.node(n.c).ty));
                    try self.fact(arrow_, n.ty, value_);
                }
            }
            if (n.tag == .closure or n.tag == .suspend_) {
                arrow_ = n.ty;
                value_ = id;
            }
        }
        var slot: usize = 0;
        while (self.graph.edge(vertex, slot)) |child| : (slot += 1) {
            var parent: C.Id = 0;
            if (item.kind == .node and item.id != 0) {
                const node = self.module.node(@intCast(item.id));
                const target = self.graph.item(child);
                if (node.tag == .apply and target.kind == .node and target.id == node.a) {
                    parent = @intCast(item.id);
                    if (application_parent != 0) parent = application_parent;
                }
            }
            try self.expression(child, arrow_, value_, parent, depth + 1);
        }
        if (item.kind == .node and item.id != 0) {
            const id: C.Id = @intCast(item.id);
            const node = self.module.node(id);
            if (application_parent == 0 and (node.tag == .call or node.tag == .apply)) {
                if (@import("capability_flow.zig").coreCall(self.module, id)) |call| {
                    const owner = try self.ownerModule(call.target.unit);
                    try require(call.target.binding < owner.bindings.len);
                    _ = try self.formalBinder(id, null, owner, call);
                }
                try self.callResult(id, arrow_, value_, node.ty, 0);
                try self.returnedBinders(id);
            }
        }
    }
    fn reachable(self: *const Scan, root: T.Id, arrow_: T.Id, depth: usize, remaining: *usize) Error!bool {
        if (root == 0) return false;
        try require(depth < 128 and remaining.* != 0);
        remaining.* -= 1;
        const n = self.module.types.node(root);
        if (n.tag == .function) {
            if (try self.arrow(root, arrow_)) return true;
            if (try self.reachable(n.a, arrow_, depth + 1, remaining)) return true;
            return self.reachable(n.b, arrow_, depth + 1, remaining);
        }
        switch (n.tag) {
            .usage, .array, .list, .cursor, .resolver, .demand, .provider => return self.reachable(n.a, arrow_, depth + 1, remaining),
            .state_provider => for ([_]T.Id{ n.a, n.b, n.c }) |child| {
                if (try self.reachable(child, arrow_, depth + 1, remaining)) return true;
            },
            .product => for (self.module.types.list(.{ .start = n.a, .len = n.b })) |child| {
                if (try self.reachable(child, arrow_, depth + 1, remaining)) return true;
            },
            .record => for (0..n.b) |i| {
                if (try self.reachable(self.module.types.recordField(n, i).ty, arrow_, depth + 1, remaining)) return true;
            },
            .nominal => for (self.module.types.nominalArguments(n)) |child| {
                if (try self.reachable(child, arrow_, depth + 1, remaining)) return true;
            },
            else => {},
        }
        return false;
    }
    fn scheme(self: *const Scan, value: T.Scheme) Error!void {
        const words = self.module.types.list(value.generative);
        for (0..words.len / 2) |index| {
            var found = false;
            for (self.facts[0..self.len]) |fact_| if (try self.arrow(words[index * 2], fact_.arrow) and try self.same(words[index * 2 + 1], fact_.selected)) {
                found = true;
                break;
            };
            try require(found);
        }
        for (self.facts[0..self.len]) |fact_| {
            var remaining: usize = 65_536;
            if (!try self.reachable(value.root, fact_.arrow, 0, &remaining)) continue;
            var found = false;
            for (0..words.len / 2) |index| if (try self.arrow(words[index * 2], fact_.arrow) and try self.same(words[index * 2 + 1], fact_.selected)) {
                found = true;
                break;
            };
            try require(found);
        }
    }
};
pub fn validate(module: *const C.Module, owners: []const *const C.Module) Error!void {
    var active = false;
    for (module.types.nodes) |node| if (node.tag == .instance_version) {
        active = true;
        break;
    };
    if (!active) return;
    var sites: Sites = .{};
    for (module.bodies) |body| {
        if (body.root == 0) continue;
        var scan: Scan = .{ .module = module, .owners = owners, .sites = &sites, .variables = body.scheme.variables, .graph = try @import("frozen_core_validation.zig").Graph.init(module) };
        var arrow_: T.Id = 0;
        var root = body.scheme.root;
        if (module.types.node(root).tag == .forall) root = module.types.node(root).a;
        for (module.bodyParameters(&body)) |_| {
            const n = module.types.node(root);
            try require(n.tag == .function);
            arrow_ = root;
            root = n.b;
        }
        try scan.expression(scan.graph.vertex(.node, body.root), arrow_, 0, 0, 0);
        try scan.scheme(body.scheme);
        try scan.scheme(module.bindings[body.binding].scheme);
    }
}

test "formal invocation keeps captured versions beside an equal typed unrelated creator" {
    var types = try T.Store.init(std.testing.allocator);
    defer types.deinit();
    const state = try types.nominal(.{ .unit = 1, .decl = 9 }, &.{T.u32_type});
    const left = try types.scoped(state, .{ .unit = 1, .decl = 40 });
    const right = try types.scoped(state, .{ .unit = 1, .decl = 41 });
    const captured_version = try types.instanceVersion(.{ .unit = 1, .decl = 77 }, 0);
    const declared_version = try types.instanceVersion(.{ .unit = 1, .decl = 78 }, 0);
    const captured_term = try types.instanceSelection(.{ .unit = 1, .decl = 100 }, &.{ left, right, captured_version });
    const declared_term = try types.instanceSelection(.{ .unit = 1, .decl = 101 }, &.{ left, right, declared_version });
    const captured = try types.scoped(state, .{ .unit = 0, .decl = captured_term });
    const declared = try types.scoped(state, .{ .unit = 0, .decl = declared_term });
    const before = try types.record(&.{ .{ .name = 1, .ty = captured }, .{ .name = 2, .ty = declared } });
    const arrow = try types.function(T.unit, before);
    const result_variable = try types.fresh();
    const helper = try types.function(try types.function(T.unit, result_variable), result_variable);
    const variables = try types.saveList(&.{result_variable});
    const signature = try types.function(arrow, before);
    const fresh_declared_version = try types.instanceVersion(.{ .unit = 1, .decl = 200 }, 0);
    const fresh_declared_term = try types.instanceSelection(.{ .unit = 1, .decl = 101 }, &.{ left, right, fresh_declared_version });
    const fresh_declared = try types.scoped(state, .{ .unit = 0, .decl = fresh_declared_term });
    const correct = try types.record(&.{ .{ .name = 1, .ty = captured }, .{ .name = 2, .ty = fresh_declared } });
    const fresh_captured_version = try types.instanceVersion(.{ .unit = 1, .decl = 200 }, 1);
    const fresh_captured_term = try types.instanceSelection(.{ .unit = 1, .decl = 100 }, &.{ left, right, fresh_captured_version });
    const fresh_captured = try types.scoped(state, .{ .unit = 0, .decl = fresh_captured_term });
    const forged = try types.record(&.{ .{ .name = 1, .ty = fresh_captured }, .{ .name = 2, .ty = fresh_declared } });
    const callback_container = try types.record(&.{ .{ .name = 1, .ty = arrow }, .{ .name = 2, .ty = arrow } });
    var nodes = [_]C.Node{
        .{ .tag = .invalid },
        .{ .tag = .closure, .ty = arrow },
        .{ .tag = .closure, .ty = arrow },
        .{ .tag = .if_value, .ty = arrow, .b = 1, .c = 2 },
        .{ .tag = .call, .ty = correct, .c = 1 },
        .{ .tag = .reference, .ty = arrow },
        .{ .tag = .constant, .ty = before },
        .{ .tag = .record, .ty = callback_container, .a = 1, .b = 2, .c = 3 },
        .{ .tag = .project, .ty = arrow, .a = 7 },
    };
    var spans: [9]C.Span = @splat(.{ .start = 0, .end = 199 });
    var arguments_ = [_]C.Id{ 5, 2, 1, 1, 0 };
    var bindings = [_]C.Binding{
        .{ .kind = .local, .ty = 0, .scheme = .{}, .target = .{ .binding = 0 }, .span = spans[0] },
        .{ .kind = .global, .ty = helper, .scheme = .{ .root = helper, .variables = variables }, .target = .{ .binding = 0 }, .span = spans[0], .capability_flow = .invoke_unit },
        .{ .kind = .local, .ty = arrow, .scheme = .{ .root = arrow }, .target = .{ .binding = 0 }, .span = spans[0], .initializer = 1 },
    };
    var references = [_]C.BindingRef{.{ .binding = 2 }};
    var calls = [_]C.CallInfo{.{ .target = .{ .binding = 1 }, .callee_type = signature }};
    var closures = [_]C.ClosureInfo{.{ .body = 6, .parameter = .{ .binding = 0, .ty = T.unit, .span = spans[0] }, .captures = .{}, .function_type = arrow }};
    var projections = [_]C.Projection{.{ .nominal = .{ .unit = 0, .decl = 0 }, .field = 1, .source_type = callback_container, .result_type = arrow, .variants = .{ .len = 1 } }};
    var variants = [_]C.ProjectionVariant{.{ .tag = 0, .field = 0 }};
    const module: C.Module = .{ .projections = &projections, .projection_variants = &variants, .unit = 1, .types = .{ .nodes = types.nodes.items, .extra = types.extra.items, .effects = .{ .rows = types.effects.rows.items, .labels = types.effects.labels.items }, .operations = types.operations.items }, .nodes = &nodes, .spans = &spans, .extra = &arguments_, .bindings = &bindings, .bodies = &.{}, .parameters = &.{}, .references = &references, .calls = &calls, .closures = &closures, .merges = &.{}, .merge_ranges = &.{}, .names = &.{}, .obligations = &.{}, .diagnostics = &.{}, .body_lowerings = 0 };
    var sites: Sites = .{};
    var scan: Scan = .{ .module = &module, .owners = &.{}, .sites = &sites, .variables = .{}, .graph = try @import("frozen_core_validation.zig").Graph.init(&module) };
    // Facts are independently established inputs to this reader. Both creators
    // have the same arrow, but one declares the other's captured version.
    scan.facts[0] = .{ .arrow = arrow, .selected = declared, .value = 1 };
    scan.facts[1] = .{ .arrow = arrow, .selected = captured, .value = 2 };
    scan.len = 2;
    var call = @import("capability_flow.zig").coreCall(&module, 4).?;
    try std.testing.expect(try scan.formalBinder(4, null, &module, call));
    nodes[4].ty = forged;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    arguments_[0] = 3;
    call = @import("capability_flow.zig").coreCall(&module, 4).?;
    nodes[4].ty = correct;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    nodes[4].ty = forged;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    scan.facts[1].selected = declared;
    nodes[4].ty = correct;
    try std.testing.expect(try scan.formalBinder(4, null, &module, call));
    scan.len = 1;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    scan.len = 0;
    nodes[4].ty = before;
    try std.testing.expect(try scan.formalBinder(4, null, &module, call));
    // Physical record evaluation order differs from its field order. The
    // selected field owns its actual creator even when both arrows are equal.
    scan.len = 2;
    scan.facts[1].selected = captured;
    arguments_[0] = 8;
    nodes[4].ty = correct;
    call = @import("capability_flow.zig").coreCall(&module, 4).?;
    try std.testing.expect(try scan.formalBinder(4, null, &module, call));
    variants[0].field = 1;
    projections[0].field = 2;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    variants[0].field = 0;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    projections[0].field = 1;
    arguments_[2] = 2;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    arguments_[2] = 1;
    arguments_[4] = 1;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    arguments_[4] = 0;
    nodes[8].b = 1;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    nodes[8].b = 0;
    arguments_[2] = 8;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
    arguments_[2] = 1;
    try std.testing.expect(try scan.formalBinder(4, null, &module, call));
    nodes[8].tag = .primitive_function;
    nodes[4].ty = before;
    try std.testing.expectError(error.InvalidArtifact, scan.formalBinder(4, null, &module, call));
}
