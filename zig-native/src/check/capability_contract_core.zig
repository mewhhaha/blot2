//! Immutable Core independently reconstructs the claimed value relationship.
//! Closure capture catalogs are redundant information, never absence proofs.
const std = @import("std");
const flow = @import("capability_flow.zig");
const terms = @import("capability_contracts.zig");
const A = std.mem.Allocator;
const Error = terms.Error || error{Unavailable};
const Alias = struct { binding: u32, value: terms.Id, callable: ?usize = null };
const Environment = struct {
    values: [128]Alias = undefined,
    len: usize = 0,
    fn bind(self: *Environment, binding: u32, value: terms.Id) terms.Error!void {
        if (self.len == self.values.len) return error.CapabilityAnalysisLimit;
        self.values[self.len] = .{ .binding = binding, .value = value };
        self.len += 1;
    }
    fn get(self: *const Environment, binding: u32) ?terms.Id {
        const entry = self.alias(binding) orelse return null;
        return entry.value;
    }
    fn alias(self: *const Environment, binding: u32) ?Alias {
        var index = self.len;
        while (index != 0) {
            index -= 1;
            if (self.values[index].binding == binding) return self.values[index];
        }
        return null;
    }
};
fn Builder(comptime Module: type) type {
    return struct {
        const Self = @This();
        allocator: A,
        store: *terms.Store,
        module: Module,
        remaining: usize = 65_536,
        input_globals: bool = false,
        value_origins: bool = false,
        owners: []const *const @typeInfo(Module).pointer.child = &.{},
        closed_rows: @import("types.zig").List = .{},
        callables: std.ArrayList(struct { source: u32, environment: Environment }) = .empty,
        fn deinit(self: *Self) void {
            self.callables.deinit(self.allocator);
        }
        fn callableOrigin(self: *Self, source: u32, environment: *const Environment, depth: usize) Error!?usize {
            const value = try self.node(source, depth);
            if (value.tag == .reference) {
                if (value.a >= self.module.references.len) return error.Unavailable;
                const reference_ = self.module.references[value.a];
                if (reference_.unit != 0 and reference_.unit != self.module.unit) return null;
                const alias = environment.alias(reference_.binding) orelse return null;
                return alias.callable;
            }
            if (value.tag != .closure) return null;
            const index = self.callables.items.len;
            try self.callables.append(self.allocator, .{ .source = source, .environment = environment.* });
            return index;
        }
        fn closureCall(self: *Self, call: flow.LocalCoreCall, environment: *const Environment, depth: usize) Error!?terms.Id {
            if (call.len != 1 or (call.target.unit != 0 and call.target.unit != self.module.unit)) return null;
            const alias = environment.alias(call.target.binding) orelse return null;
            const origin = alias.callable orelse return null;
            if (origin >= self.callables.items.len) return error.Unavailable;
            const source = self.callables.items[origin].source;
            const value = try self.node(source, depth + 1);
            if (value.tag != .closure or value.a >= self.module.closures.len) return error.Unavailable;
            const callback = self.module.closures[value.a];
            const argument = try self.expression(call.arguments[0], environment, depth + 1);
            // Arguments can append new origins. Copy the immutable creation
            // environment after that growth, before entering the actual body.
            var callee = self.callables.items[origin].environment;
            if (callback.parameter.binding != 0) try callee.bind(callback.parameter.binding, argument);
            return try self.expression(callback.body, &callee, depth + 1);
        }
        fn node(self: *Self, source: u32, depth: usize) Error!@TypeOf(self.module.nodes[0]) {
            if (depth >= 128 or self.remaining == 0) return error.CapabilityAnalysisLimit;
            self.remaining -= 1;
            if (source == 0 or source >= self.module.nodes.len) return error.Unavailable;
            return self.module.nodes[source];
        }
        fn namedFunction(self: *Self, original: @import("core.zig").BindingRef, actual: u32, depth: usize) Error!?terms.Id {
            var target = original;
            var producer: *const @typeInfo(Module).pointer.child = self.module;
            for (0..128) |_| {
                if (self.remaining == 0 or depth >= 128) return error.CapabilityAnalysisLimit;
                self.remaining -= 1;
                if (target.unit != 0 and target.unit != producer.unit) {
                    var selected: ?*const @typeInfo(Module).pointer.child = null;
                    for (self.owners) |owner| {
                        if (self.remaining == 0) return error.CapabilityAnalysisLimit;
                        self.remaining -= 1;
                        if (owner.unit != target.unit) continue;
                        if (selected) |prior| if (prior != owner) return error.Unavailable;
                        selected = owner;
                    }
                    producer = selected orelse return null;
                }
                if (target.binding == 0 or target.binding >= producer.bindings.len) return error.Unavailable;
                const binding = producer.bindings[target.binding];
                if (binding.kind == .external) {
                    target = binding.target;
                    continue;
                }
                if (binding.kind != .global or binding.body_id == 0 or binding.body_id >= producer.bodies.len or binding.scheme.generative.len != 0) return null;
                const body = producer.bodies[binding.body_id];
                if (!body.is_function) return null;
                const relocation = @import("generative_relocation.zig").Relocation.init(producer, self.module, binding.scheme, actual, actual, 0, 0) catch return error.Unavailable;
                const work = 65_536 - relocation.remaining;
                if (work > self.remaining) return error.CapabilityAnalysisLimit;
                self.remaining -= work;
                var arity = binding.capability_parameters.arity();
                if (binding.capability_flow == .identity) {
                    if (!flow.unaryCore(producer, body, .identity)) return error.Unavailable;
                    arity = 1;
                } else if (binding.capability_flow != .input_shape and (binding.capability_flow != .unknown or binding.capability_parameters.kind != .product or !binding.capability_parameters.valid() or !binding.capability_parameters.present())) return null;
                if (arity == 0 or arity > 16 or body.parameters.len != arity or body.parameters.start > producer.parameters.len or body.parameters.len > producer.parameters.len - body.parameters.start) return error.Unavailable;
                var reader: Builder(@TypeOf(producer)) = .{ .allocator = self.allocator, .store = self.store, .module = producer, .owners = self.owners, .remaining = self.remaining, .input_globals = true, .closed_rows = body.closed_rows };
                defer reader.deinit();
                defer self.remaining = reader.remaining;
                var parameters: Environment = .{};
                for (producer.parameters[body.parameters.start..][0..arity], 0..) |parameter, index| {
                    if (parameter.binding == 0) {
                        if (index != 0 or parameter.ty != @import("types.zig").unit) return error.Unavailable;
                        continue;
                    }
                    if (parameter.binding >= producer.bindings.len or producer.bindings[parameter.binding].kind != .parameter) return error.Unavailable;
                    try parameters.bind(parameter.binding, try self.store.append(self.allocator, .{ .tag = .argument, .a = @intCast(index) }));
                }
                const result = try reader.expression(body.root, &parameters, depth + 1);
                var expected = binding.capability_parameters.result();
                if (binding.capability_flow == .identity) expected = 1;
                if (try self.store.view().argumentMask(result, &reader.remaining) != expected) return error.Unavailable;
                return try self.store.append(self.allocator, .{ .tag = .callable, .a = arity, .c = result });
            }
            return error.CapabilityAnalysisLimit;
        }
        fn reference(self: *Self, catalog: u32, actual: u32, environment: *const Environment, depth: usize) Error!terms.Id {
            if (catalog >= self.module.references.len) return error.Unavailable;
            const value = self.module.references[catalog];
            if (value.unit == 0 or value.unit == self.module.unit) {
                if (environment.get(value.binding)) |known| return known;
                if (self.value_origins and value.binding < self.module.bindings.len) {
                    const binding = self.module.bindings[value.binding];
                    if (binding.kind == .local and binding.initializer != 0) return self.expression(binding.initializer, environment, depth + 1);
                    if (binding.kind == .parameter) return 0;
                }
            }
            if (self.input_globals) if (try self.namedFunction(value, actual, depth + 1)) |function| return function;
            if (self.input_globals) {
                if (value.unit != 0 and value.unit != self.module.unit) return 0;
                if (value.binding < self.module.bindings.len and self.module.bindings[value.binding].kind == .global) return 0;
            }
            if (value.unit != 0 and value.unit != self.module.unit) return error.Unavailable;
            return environment.get(value.binding) orelse error.Unavailable;
        }
        fn expression(self: *Self, source: u32, environment: *const Environment, depth: usize) Error!terms.Id {
            const value = try self.node(source, depth);
            switch (value.tag) {
                .call, .apply => {
                    if (flow.coreCall(self.module, source)) |call| {
                        if (try self.closureCall(call, environment, depth + 1)) |result| return result;
                    }
                    if (self.input_globals and value.tag == .apply) {
                        const argument = try self.node(value.b, depth + 1);
                        const callee = try self.node(value.a, depth + 1);
                        if (argument.tag == .constant and argument.ty == @import("types.zig").unit and argument.a == 0 and callee.tag == .operation_value) {
                            if (value.ty >= self.module.types.nodes.len) return error.Unavailable;
                            _ = try self.expression(value.a, environment, depth + 1);
                            switch (self.module.types.node(value.ty).tag) {
                                .unit, .boolean, .u32, .f32, .never => return 0,
                                else => return self.store.append(self.allocator, .{ .tag = .unknown }),
                            }
                        }
                    }
                    if (flow.localCoreCall(self.module, source)) |call| {
                        var nested: Environment = .{};
                        for (call.bindings[0..call.len], call.arguments[0..call.len]) |binding, argument| try nested.bind(binding, try self.expression(argument, environment, depth + 1));
                        return self.expression(call.body, &nested, depth + 1);
                    }
                    if (self.input_globals) if (flow.coreCall(self.module, source)) |call| {
                        const function = (try self.namedFunction(call.target, call.signature, depth + 1)) orelse return error.Unavailable;
                        var arguments: [16]terms.Id = undefined;
                        for (call.arguments[0..call.len], 0..) |argument, index| arguments[index] = try self.expression(argument, environment, depth + 1);
                        return self.store.invoke(self.allocator, function, arguments[0..call.len]);
                    };
                    return error.Unavailable;
                },
                .reference => return self.reference(value.a, value.ty, environment, depth + 1),
                .computation => {
                    const child = try self.expression(value.a, environment, depth + 1);
                    try self.inputStore(child);
                    return self.store.append(self.allocator, .{ .tag = .wrapped, .a = child });
                },
                .effect_provider, .state_provider => {
                    var children: [3]terms.Id = undefined;
                    children[0] = try self.expression(value.a, environment, depth + 1);
                    children[1] = try self.expression(value.b, environment, depth + 1);
                    var count: usize = 2;
                    if (value.tag == .state_provider) {
                        children[2] = try self.expression(value.c, environment, depth + 1);
                        count = 3;
                    }
                    for (children[0..count]) |child| try self.inputStore(child);
                    return self.store.aggregate(self.allocator, .captures, children[0..count]);
                },
                .usage_borrow => {
                    if (value.b >= self.module.nodes.len or self.module.nodes[value.b].tag != .closure) return error.Unavailable;
                    const callback = self.module.closure(value.b);
                    var nested = environment.*;
                    try nested.bind(callback.parameter.binding, try self.expression(value.a, environment, depth + 1));
                    return self.expression(callback.body, &nested, depth + 1);
                },
                .task => {
                    const op = std.enums.fromInt(@import("task_types.zig").Op, value.c) orelse return error.Unavailable;
                    if (value.a > self.module.extra.len or value.b > self.module.extra.len - value.a or value.b != @import("task_types.zig").arity(op)) return error.Unavailable;
                    const operands = self.module.extra[value.a..][0..value.b];
                    switch (op) {
                        .scope, .spawn, .split => {
                            var callback_id = operands[if (op == .scope) 0 else if (op == .spawn) 1 else 2];
                            if (op == .spawn) callback_id = @import("task_core.zig").callable(self.module, callback_id) catch return error.Unavailable;
                            const callback_node = try self.node(callback_id, depth + 1);
                            if (callback_node.tag != .closure) return error.Unavailable;
                            const callback = self.module.closure(callback_id);
                            var nested = environment.*;
                            var input: terms.Id = 0;
                            if (op == .split) {
                                const plan = @import("task_regions.zig").partition(self.module, source) catch return error.Unavailable;
                                const owner = try self.expression(operands[0], environment, depth + 1);
                                var views: [16]terms.Id = undefined;
                                @memset(views[0..plan.len], owner);
                                input = try self.store.aggregate(self.allocator, .product, views[0..plan.len]);
                            }
                            try nested.bind(callback.parameter.binding, input);
                            const result = try self.expression(callback.body, &nested, depth + 1);
                            if (op == .scope) return result;
                            const owner = try self.expression(operands[0], environment, depth + 1);
                            if (op == .spawn) {
                                if (self.input_globals) try self.inputStore(try self.expression(callback_id, environment, depth + 1));
                                return self.store.aggregate(self.allocator, .product, &.{ owner, result });
                            }
                            return self.store.aggregate(self.allocator, .product, &.{ owner, result });
                        },
                        .join => return self.store.project(self.allocator, try self.expression(operands[0], environment, depth + 1), 1, .index),
                        .cancel, .write => {
                            if (self.input_globals) for (operands) |operand| try self.inputStore(try self.expression(operand, environment, depth + 1));
                            return 0;
                        },
                        .read => {
                            switch (self.module.types.nodes[value.ty].tag) {
                                .unit, .boolean, .u32, .f32 => return 0,
                                else => {},
                            }
                            return self.store.elements(self.allocator, try self.expression(operands[0], environment, depth + 1));
                        },
                    }
                },
                .usage_share => return self.expression(value.a, environment, depth + 1),
                .resource_acquire, .resource_release, .resource_scope, .usage_read, .scalar, .logical => {
                    if (self.input_globals) {
                        if (value.tag == .resource_acquire or value.tag == .resource_release or value.tag == .resource_scope) return error.Unavailable;
                        _ = try self.expression(value.a, environment, depth + 1);
                        if ((value.tag == .scalar or value.tag == .logical) and value.b != 0) _ = try self.expression(value.b, environment, depth + 1);
                    }
                    if (value.ty >= self.module.types.nodes.len) return error.Unavailable;
                    switch (self.module.types.nodes[value.ty].tag) {
                        .unit, .boolean, .u32, .f32 => return 0,
                        else => return error.Unavailable,
                    }
                },
                .constant => {
                    if (value.ty >= self.module.types.nodes.len) return error.Unavailable;
                    switch (self.module.types.nodes[value.ty].tag) {
                        .unit, .boolean, .u32, .f32 => return 0,
                        else => return error.Unavailable,
                    }
                },
                .construct => {
                    if (value.b == 0) return self.store.append(self.allocator, .{ .tag = .wrapped });
                    return self.store.append(self.allocator, .{ .tag = .wrapped, .a = try self.expression(value.b, environment, depth + 1) });
                },
                .product, .array, .record => {
                    if (value.a > self.module.extra.len or value.b > self.module.extra.len - value.a or value.b > 2048) return error.Unavailable;
                    var words: [4096]u32 = undefined;
                    const children = self.module.extra[value.a..][0..value.b];
                    if (value.tag == .record) {
                        if (value.ty >= self.module.types.nodes.len or value.c > self.module.extra.len or value.b > self.module.extra.len - value.c) return error.Unavailable;
                        const record = self.module.types.nodes[value.ty];
                        if (record.tag != .record or record.a > self.module.types.extra.len or record.b > (self.module.types.extra.len - record.a) / 2) return error.Unavailable;
                        for (children, 0..) |child, index| {
                            const destination = self.module.extra[value.c + index];
                            if (destination >= record.b) return error.Unavailable;
                            words[index * 2] = self.module.types.extra[record.a + destination * 2];
                            words[index * 2 + 1] = try self.expression(child, environment, depth + 1);
                        }
                        return self.store.aggregate(self.allocator, .record, words[0 .. children.len * 2]);
                    }
                    for (children, 0..) |child, index| {
                        words[index] = try self.expression(child, environment, depth + 1);
                        if (value.tag == .array) try self.inputStore(words[index]);
                    }
                    return self.store.aggregate(self.allocator, .product, words[0..children.len]);
                },
                .array_op => {
                    if (value.c != @backingInt(@import("core.zig").ArrayOp.get) or value.b != 2 or value.a > self.module.extra.len or value.b > self.module.extra.len - value.a) return error.Unavailable;
                    const receiver = try self.expression(self.module.extra[value.a], environment, depth + 1);
                    const index = try self.node(self.module.extra[value.a + 1], depth + 1);
                    if (index.tag != .constant or index.ty >= self.module.types.nodes.len or self.module.types.nodes[index.ty].tag != .u32) return self.store.elements(self.allocator, receiver);
                    return self.store.project(self.allocator, receiver, index.a, .index);
                },
                .operation_value => {
                    if (value.a >= self.module.operation_values.len) return error.Unavailable;
                    return self.store.aggregate(self.allocator, .captures, &.{try self.expression(self.module.operation_values[value.a].capability, environment, depth + 1)});
                },
                .project => {
                    if (value.b >= self.module.projections.len) return error.Unavailable;
                    const projection = self.module.projections[value.b];
                    if (projection.field == 0) {
                        if (projection.nominal.unit != 0 or projection.nominal.decl != 0 or projection.variants.len != 1 or projection.variants.start >= self.module.projection_variants.len) return error.Unavailable;
                        const variant = self.module.projection_variants[projection.variants.start];
                        if (variant.tag != 0) return error.Unavailable;
                        return self.store.project(self.allocator, try self.expression(value.a, environment, depth + 1), variant.field, .index);
                    }
                    return self.store.project(self.allocator, try self.expression(value.a, environment, depth + 1), projection.field, .field);
                },
                .if_value => {
                    if (self.input_globals) _ = try self.expression(value.a, environment, depth + 1);
                    return self.store.aggregate(self.allocator, .join, &.{ try self.expression(value.b, environment, depth + 1), try self.expression(value.c, environment, depth + 1) });
                },
                .block => {
                    if (value.a > self.module.extra.len or value.b > self.module.extra.len - value.a) return error.Unavailable;
                    var nested = environment.*;
                    const children = self.module.extra[value.a..][0..value.b];
                    for (children, 0..) |child, index| {
                        const statement = try self.node(child, depth + 1);
                        if (statement.tag == .return_ and index + 1 == children.len and statement.b == source) return self.expression(statement.a, &nested, depth + 1);
                        // A discarded `use ()` lowers directly to this inert
                        // statement, rather than a bind with an unused name.
                        if (statement.tag == .constant and statement.ty == @import("types.zig").unit and statement.op == .none and statement.a == 0 and statement.b == 0 and statement.c == 0) continue;
                        if (statement.tag != .bind) return error.Unavailable;
                        const result = try self.expression(statement.b, &nested, depth + 1);
                        const origin = try self.callableOrigin(statement.b, &nested, depth + 1);
                        try nested.bind(statement.a, result);
                        nested.values[nested.len - 1].callable = origin;
                    }
                    return error.Unavailable;
                },
                .match => {
                    if (value.a >= self.module.matches.len) return error.Unavailable;
                    const match = self.module.matches[value.a];
                    if (match.statement or match.inputs.len > 16 or match.arms.len > 4096) return error.Unavailable;
                    var retained: [16]terms.Id = undefined;
                    for (self.module.extra[match.inputs.start..][0..match.inputs.len], 0..) |input, index| retained[index] = try self.expression(input, environment, depth + 1);
                    var arms: [4096]terms.Id = undefined;
                    for (self.module.match_arms[match.arms.start..][0..match.arms.len], 0..) |arm, index| {
                        var nested = environment.*;
                        const start = nested.len;
                        for (self.module.pattern_rows[arm.rows.start..][0..arm.rows.len]) |row| {
                            if (row.patterns.len != match.inputs.len) return error.Unavailable;
                            for (self.module.extra[row.patterns.start..][0..row.patterns.len], retained[0..match.inputs.len]) |pattern_, origin| try self.pattern(pattern_, origin, &nested, start, depth + 1);
                        }
                        if (self.input_globals and arm.guard != 0) _ = try self.expression(arm.guard, &nested, depth + 1);
                        arms[index] = try self.expression(arm.body, &nested, depth + 1);
                    }
                    return self.store.aggregate(self.allocator, .join, arms[0..match.arms.len]);
                },
                .closure => {
                    if (value.a >= self.module.closures.len) return error.Unavailable;
                    const closure = self.module.closures[value.a];
                    var nested = environment.*;
                    try nested.bind(closure.parameter.binding, 0);
                    var captures: [4096]terms.Id = undefined;
                    var count: usize = 0;
                    try self.capture(closure.body, &nested, &captures, &count, depth + 1);
                    for (captures[0..count]) |capture_| try self.inputStore(capture_);
                    return self.store.aggregate(self.allocator, .captures, captures[0..count]);
                },
                else => return error.Unavailable,
            }
        }
        fn inputStore(self: *Self, root: terms.Id) Error!void {
            if (self.input_globals and try self.store.view().containsParameter(root, &self.remaining)) return error.Unavailable;
        }
        fn bindPattern(self: *Self, environment: *Environment, start: usize, binding: u32, origin: terms.Id) Error!void {
            for (environment.values[start..environment.len]) |*entry| if (entry.binding == binding) {
                if (entry.value != origin) entry.value = try self.store.aggregate(self.allocator, .join, &.{ entry.value, origin });
                return;
            };
            try environment.bind(binding, origin);
        }
        fn pattern(self: *Self, source: u32, origin: terms.Id, environment: *Environment, start: usize, depth: usize) Error!void {
            if (source == 0 or source >= self.module.patterns.len or depth >= 128 or self.remaining == 0) return error.Unavailable;
            self.remaining -= 1;
            const value = self.module.patterns[source];
            switch (value.tag) {
                .wildcard, .constant => {},
                .bind => try self.bindPattern(environment, start, value.a, origin),
                .constructor => if (value.b != 0) try self.pattern(value.b, try self.store.project(self.allocator, origin, 0, .payload), environment, start, depth + 1),
                .record_payload => if (value.b != 0) try self.pattern(value.b, origin, environment, start, depth + 1),
                .product => {
                    if (value.ty >= self.module.types.nodes.len) return error.Unavailable;
                    const shape = self.module.types.nodes[value.ty];
                    for (self.module.extra[value.a..][0..value.b], 0..) |child, index| {
                        var selector: u32 = @intCast(index);
                        var kind: terms.Projection = .index;
                        if (shape.tag == .record) {
                            if (index >= shape.b) return error.Unavailable;
                            selector = self.module.types.extra[shape.a + index * 2];
                            kind = .field;
                        }
                        try self.pattern(child, try self.store.project(self.allocator, origin, selector, kind), environment, start, depth + 1);
                    }
                },
                else => return error.Unavailable,
            }
        }
        // A deferred call captures its arguments and a statically owned global
        // target. Construction does not execute that target or prove no-store.
        fn captureCallTarget(self: *Self, original: @import("core.zig").BindingRef, depth: usize) Error!void {
            var target = original;
            var producer: *const @typeInfo(Module).pointer.child = self.module;
            for (0..128) |_| {
                if (self.remaining == 0 or depth >= 128) return error.CapabilityAnalysisLimit;
                self.remaining -= 1;
                if (target.unit != 0 and target.unit != producer.unit) {
                    var selected: ?*const @typeInfo(Module).pointer.child = null;
                    for (self.owners) |owner| {
                        if (self.remaining == 0) return error.CapabilityAnalysisLimit;
                        self.remaining -= 1;
                        if (owner.unit != target.unit) continue;
                        if (selected) |prior| if (prior != owner) return error.Unavailable;
                        selected = owner;
                    }
                    producer = selected orelse return error.Unavailable;
                }
                if (target.binding == 0 or target.binding >= producer.bindings.len) return error.Unavailable;
                const binding = producer.bindings[target.binding];
                if (binding.kind == .external) {
                    target = binding.target;
                    continue;
                }
                if (binding.kind != .global or binding.body_id == 0 or binding.body_id >= producer.bodies.len) return error.Unavailable;
                return;
            }
            return error.CapabilityAnalysisLimit;
        }
        fn capture(self: *Self, source: u32, environment: *const Environment, captures: *[4096]terms.Id, count: *usize, depth: usize) Error!void {
            const value = try self.node(source, depth);
            switch (value.tag) {
                .reference => {
                    if (value.a >= self.module.references.len) return error.Unavailable;
                    const reference_ = self.module.references[value.a];
                    var captured: terms.Id = 0;
                    if (reference_.unit == 0 or reference_.unit == self.module.unit) {
                        if (environment.get(reference_.binding)) |known| captured = known else if (!self.input_globals) {
                            captured = try self.reference(value.a, value.ty, environment, depth + 1);
                        } else if (reference_.binding >= self.module.bindings.len or self.module.bindings[reference_.binding].kind != .global) return error.Unavailable;
                    } else if (!self.input_globals) return error.Unavailable;
                    if (captured == 0) return;
                    for (captures[0..count.*]) |known| if (known == captured) return;
                    if (count.* == captures.len) return error.CapabilityAnalysisLimit;
                    captures[count.*] = captured;
                    count.* += 1;
                },
                .constant, .primitive_function => {},
                .operation_value => {
                    if (value.a >= self.module.operation_values.len) return error.Unavailable;
                    const receiver = self.module.operation_values[value.a].capability;
                    if (receiver != 0) try self.capture(receiver, environment, captures, count, depth + 1);
                },
                .call => {
                    if (value.a >= self.module.calls.len or value.b > self.module.extra.len or value.c > self.module.extra.len - value.b) return error.Unavailable;
                    try self.captureCallTarget(self.module.calls[value.a].target, depth + 1);
                    for (self.module.extra[value.b..][0..value.c]) |operand| try self.capture(operand, environment, captures, count, depth + 1);
                },
                .apply => {
                    try self.capture(value.a, environment, captures, count, depth + 1);
                    try self.capture(value.b, environment, captures, count, depth + 1);
                },
                .scalar, .logical, .associated => {
                    try self.capture(value.a, environment, captures, count, depth + 1);
                    if (value.b != 0) try self.capture(value.b, environment, captures, count, depth + 1);
                },
                .resource_release, .usage_share, .usage_read, .project, .return_, .force => try self.capture(value.a, environment, captures, count, depth + 1),
                .task => for (self.module.children(source)) |operand| try self.capture(operand, environment, captures, count, depth + 1),
                .resource_scope => {
                    try self.capture(value.a, environment, captures, count, depth + 1);
                    try self.capture(value.b, environment, captures, count, depth + 1);
                    try self.capture(value.c, environment, captures, count, depth + 1);
                },
                .resource_acquire, .usage_borrow => {
                    try self.capture(value.a, environment, captures, count, depth + 1);
                    try self.capture(value.b, environment, captures, count, depth + 1);
                },
                .construct => {
                    if (value.a == 0 or value.a >= self.module.constructors.len) return error.Unavailable;
                    if ((self.module.constructors[value.a].payload == 0) != (value.b == 0)) return error.Unavailable;
                    if (value.b != 0) try self.capture(value.b, environment, captures, count, depth + 1);
                },
                .closure, .suspend_ => {
                    if (value.a >= self.module.closures.len) return error.Unavailable;
                    const closure = self.module.closures[value.a];
                    var nested = environment.*;
                    try nested.bind(closure.parameter.binding, 0);
                    try self.capture(closure.body, &nested, captures, count, depth + 1);
                },
                .block, .suite => {
                    if (value.a > self.module.extra.len or value.b > self.module.extra.len - value.a) return error.Unavailable;
                    var nested = environment.*;
                    for (self.module.extra[value.a..][0..value.b]) |child| {
                        const statement = try self.node(child, depth + 1);
                        if (statement.tag == .bind) {
                            try self.capture(statement.b, &nested, captures, count, depth + 1);
                            try nested.bind(statement.a, 0);
                        } else if (statement.tag == .pattern_bind) {
                            try self.capture(statement.b, &nested, captures, count, depth + 1);
                            if (statement.c != 0) try self.capture(statement.c, &nested, captures, count, depth + 1);
                            try self.pattern(statement.a, 0, &nested, nested.len, depth + 1);
                        } else try self.capture(child, &nested, captures, count, depth + 1);
                    }
                },
                .match => {
                    if (value.a >= self.module.matches.len) return error.Unavailable;
                    const match = self.module.matches[value.a];
                    if (match.inputs.len > 16 or match.inputs.start > self.module.extra.len or match.inputs.len > self.module.extra.len - match.inputs.start) return error.Unavailable;
                    if (match.arms.start > self.module.match_arms.len or match.arms.len > self.module.match_arms.len - match.arms.start) return error.Unavailable;
                    for (self.module.extra[match.inputs.start..][0..match.inputs.len]) |input| try self.capture(input, environment, captures, count, depth + 1);
                    for (self.module.match_arms[match.arms.start..][0..match.arms.len]) |arm| {
                        if (arm.rows.start > self.module.pattern_rows.len or arm.rows.len > self.module.pattern_rows.len - arm.rows.start) return error.Unavailable;
                        var nested = environment.*;
                        const start = nested.len;
                        for (self.module.pattern_rows[arm.rows.start..][0..arm.rows.len]) |row| {
                            if (row.patterns.len != match.inputs.len or row.patterns.start > self.module.extra.len or row.patterns.len > self.module.extra.len - row.patterns.start) return error.Unavailable;
                            for (self.module.extra[row.patterns.start..][0..row.patterns.len]) |pattern_| try self.pattern(pattern_, 0, &nested, start, depth + 1);
                        }
                        if (arm.guard != 0) try self.capture(arm.guard, &nested, captures, count, depth + 1);
                        try self.capture(arm.body, &nested, captures, count, depth + 1);
                    }
                },
                .if_value => {
                    try self.capture(value.a, environment, captures, count, depth + 1);
                    try self.capture(value.b, environment, captures, count, depth + 1);
                    try self.capture(value.c, environment, captures, count, depth + 1);
                },
                .product, .record, .array, .array_op => {
                    if (value.a > self.module.extra.len or value.b > self.module.extra.len - value.a) return error.Unavailable;
                    for (self.module.extra[value.a..][0..value.b]) |child| try self.capture(child, environment, captures, count, depth + 1);
                },
                else => return error.Unavailable,
            }
        }
    };
}
pub fn derive(allocator: A, store: *terms.Store, module: anytype, body: anytype, summary: flow.Parameters) terms.Error!?terms.Id {
    return deriveWithOwners(allocator, store, module, body, summary, &.{});
}
pub fn deriveWithOwners(allocator: A, store: *terms.Store, module: anytype, body: anytype, summary: flow.Parameters, owners: []const *const @TypeOf(module.*)) terms.Error!?terms.Id {
    if (!flow.parameterCoreWithOwners(module, body, summary, owners) or summary.invokes()) return null;
    const checkpoint = store.mark();
    errdefer store.rollback(checkpoint);
    var arity: u32 = summary.arity();
    if (summary.kind == .member_closure_unit or summary.kind == .captured_unit) arity += 1;
    if (body.parameters.len != arity or body.parameters.start > module.parameters.len or body.parameters.len > module.parameters.len - body.parameters.start) return null;
    _ = try store.append(allocator, .{ .tag = .empty });
    var builder: Builder(@TypeOf(module)) = .{ .allocator = allocator, .store = store, .module = module, .owners = owners, .input_globals = body.binding < module.bindings.len and module.bindings[body.binding].capability_flow == .input_shape, .closed_rows = body.closed_rows };
    defer builder.deinit();
    var environment: Environment = .{};
    for (module.parameters[body.parameters.start..][0..summary.arity()], 0..) |parameter, index| try environment.bind(parameter.binding, try store.append(allocator, .{ .tag = .parameter, .a = @intCast(index) }));
    if (summary.kind == .member_closure_unit or summary.kind == .captured_unit) {
        try environment.bind(module.parameters[body.parameters.start + summary.arity()].binding, 0);
        var captures: [4096]terms.Id = undefined;
        var count: usize = 0;
        builder.capture(body.root, &environment, &captures, &count, 0) catch |err| {
            store.rollback(checkpoint);
            if (err == error.Unavailable) return null;
            return @errorCast(err);
        };
        return try store.aggregate(allocator, .captures, captures[0..count]);
    }
    return builder.expression(body.root, &environment, 0) catch |err| {
        store.rollback(checkpoint);
        if (err == error.Unavailable) return null;
        return @errorCast(err);
    };
}

/// A closed named callback owns the same no-store result graph as its public
/// relationship. Reconstruct its executable body; an arrow or capture catalog
/// alone cannot certify this transfer or an empty generative declaring set.
pub fn inputBody(module: anytype, body: anytype, summary: flow.Parameters) bool {
    return inputBodyWithOwners(module, body, summary, &.{});
}
pub fn inputBodyWithOwners(module: anytype, body: anytype, summary: flow.Parameters, owners: []const *const @TypeOf(module.*)) bool {
    if (!summary.valid() or summary.kind != .product or summary.arity() == 0 or body.scheme.generative.len != 0) return false;
    if (body.parameters.len != summary.arity() or body.parameters.start > module.parameters.len or body.parameters.len > module.parameters.len - body.parameters.start) return false;
    var storage: [1024 * 1024]u8 align(@alignOf(usize)) = undefined;
    var buffers: std.heap.FixedBufferAllocator = .init(&storage);
    const allocator = buffers.allocator();
    var reconstructed: terms.Store = .{};
    defer reconstructed.deinit(allocator);
    _ = reconstructed.append(allocator, .{ .tag = .empty }) catch return false;
    var builder: Builder(@TypeOf(module)) = .{ .allocator = allocator, .store = &reconstructed, .module = module, .owners = owners, .input_globals = true, .closed_rows = body.closed_rows };
    defer builder.deinit();
    var environment: Environment = .{};
    if (!body.is_function) return false;
    for (module.parameters[body.parameters.start..][0..body.parameters.len], 0..) |parameter, index| {
        if (parameter.binding == 0) {
            if (index != 0 or parameter.ty != @import("types.zig").unit) return false;
            continue;
        }
        if (parameter.binding >= module.bindings.len or module.bindings[parameter.binding].kind != .parameter) return false;
        const formal = reconstructed.append(allocator, .{ .tag = .parameter, .a = @intCast(index) }) catch return false;
        environment.bind(parameter.binding, formal) catch return false;
    }
    const root = builder.expression(body.root, &environment, 0) catch return false;
    reconstructed.view().validate(root, summary.arity(), true) catch return false;
    for (reconstructed.nodes.items) |node_| if (node_.tag == .unknown) return false;
    return (reconstructed.view().parameterMask(root) catch return false) == summary.result();
}

pub fn deriveInputFunctionClosure(allocator: A, store: *terms.Store, module: anytype, initial: anytype, arity: u8) terms.Error!?terms.Id {
    return deriveInputFunctionClosureWithOwners(allocator, store, module, initial, arity, &.{});
}
pub fn deriveInputFunctionClosureWithOwners(allocator: A, store: *terms.Store, module: anytype, initial: anytype, arity: u8, owners: []const *const @TypeOf(module.*)) terms.Error!?terms.Id {
    if (arity == 0 or arity > 16) return null;
    const checkpoint = store.mark();
    var published = false;
    defer if (!published) store.rollback(checkpoint);
    _ = try store.append(allocator, .{ .tag = .empty });
    var builder: Builder(@TypeOf(module)) = .{ .allocator = allocator, .store = store, .module = module, .input_globals = true, .owners = owners };
    defer builder.deinit();
    var environment: Environment = .{};
    if (initial.captures.start > module.extra.len or initial.captures.len > module.extra.len - initial.captures.start) return error.InvalidCapabilityContract;
    for (module.extra[initial.captures.start..][0..initial.captures.len]) |binding| try environment.bind(binding, 0);
    var closure = initial;
    for (0..arity) |index| {
        try environment.bind(closure.parameter.binding, try store.append(allocator, .{ .tag = .parameter, .a = @intCast(index) }));
        if (index + 1 == arity) {
            const root = builder.expression(closure.body, &environment, 0) catch |err| {
                if (err == error.Unavailable) return null;
                return @errorCast(err);
            };
            store.view().validate(root, arity, false) catch {
                return null;
            };
            published = true;
            return root;
        }
        const next = builder.node(closure.body, 0) catch return null;
        if ((next.tag != .closure and next.tag != .suspend_) or next.a >= module.closures.len) return null;
        closure = module.closures[next.a];
    }
    return null;
}

/// One lexical callback's result paths, with captures predating its fresh loan.
/// Those captures cannot name this parameter; unknown relationships decline.
pub fn deriveClosure(allocator: A, store: *terms.Store, module: anytype, closure: anytype) terms.Error!?terms.Id {
    return closureResult(allocator, store, module, closure, false);
}

/// Preexisting global reads do not receive the input. The caller still owns
/// their actual value/capture footprint; unknown applications remain declined.
pub fn deriveInputClosure(allocator: A, store: *terms.Store, module: anytype, closure: anytype) terms.Error!?terms.Id {
    const checkpoint = store.mark();
    const root = (try closureResult(allocator, store, module, closure, true)) orelse return null;
    // A Unit request transfers no input authority. Its unknown payload
    // result is not a result-lifetime recipe; the caller checks that separately.
    store.view().validate(root, 1, false) catch {
        store.rollback(checkpoint);
        return null;
    };
    return root;
}

fn closureResult(allocator: A, store: *terms.Store, module: anytype, closure: anytype, input_globals: bool) terms.Error!?terms.Id {
    const checkpoint = store.mark();
    errdefer store.rollback(checkpoint);
    _ = try store.append(allocator, .{ .tag = .empty });
    var builder: Builder(@TypeOf(module)) = .{ .allocator = allocator, .store = store, .module = module, .input_globals = input_globals };
    defer builder.deinit();
    var environment: Environment = .{};
    for (module.extra[closure.captures.start..][0..closure.captures.len]) |binding| try environment.bind(binding, 0);
    try environment.bind(closure.parameter.binding, try store.append(allocator, .{ .tag = .parameter }));
    return builder.expression(closure.body, &environment, 0) catch |err| {
        store.rollback(checkpoint);
        if (err == error.Unavailable) return null;
        return @errorCast(err);
    };
}

/// Derive callable provenance from the actual local aggregate/value expression.
/// Formal callbacks need no public type promise: every retained callable body is
/// sealed by its own producer and independently read from executable Core.
pub fn callableValue(allocator: A, store: *terms.Store, module: anytype, source: u32, owners: []const *const @TypeOf(module.*)) terms.Error!?terms.Id {
    const checkpoint = store.mark();
    errdefer store.rollback(checkpoint);
    _ = try store.append(allocator, .{ .tag = .empty });
    var reader: Builder(@TypeOf(module)) = .{ .allocator = allocator, .store = store, .module = module, .owners = owners, .input_globals = true, .value_origins = true };
    defer reader.deinit();
    const environment: Environment = .{};
    return reader.expression(source, &environment, 0) catch |err| {
        store.rollback(checkpoint);
        if (err == error.Unavailable) return null;
        return @errorCast(err);
    };
}
