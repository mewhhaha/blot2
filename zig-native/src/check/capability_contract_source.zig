//! Positional result shapes for already admitted no-store source relationships.
//! Source names are consumed here; only owned slots and field paths survive.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const flow = @import("capability_flow.zig");
const terms = @import("capability_contracts.zig");
const A = std.mem.Allocator;
const Unavailable = error{Unavailable};
const Error = terms.Error || Unavailable;
pub const Functions = struct {
    context: *const anyopaque,
    lookup: *const fn (*const anyopaque, ast.Id) ?terms.Recipe,
};
const Entry = struct { name: symbols.Symbol, value: terms.Id };
const Environment = struct {
    entries: [128]Entry = undefined,
    len: usize = 0,
    fn bind(self: *Environment, name: symbols.Symbol, value: terms.Id) terms.Error!void {
        if (self.len == self.entries.len) return error.CapabilityAnalysisLimit;
        self.entries[self.len] = .{ .name = name, .value = value };
        self.len += 1;
    }
    fn get(self: *const Environment, name: symbols.Symbol) ?terms.Id {
        var index = self.len;
        while (index != 0) {
            index -= 1;
            if (self.entries[index].name == name) return self.entries[index].value;
        }
        return null;
    }
};
const Builder = struct {
    allocator: A,
    store: *terms.Store,
    tree: *const ast.Tree,
    pool: *const symbols.Pool,
    remaining: usize = 65_536,
    operations: []const u32 = &.{},
    lexical_captures: bool = false,
    input_types: ?*const @import("types.zig").Store = null,
    input_expr_types: []const @import("types.zig").Id = &.{},
    functions: ?Functions = null,
    fn node(self: *Builder, initial: ast.Id, depth: usize) Error!ast.Node {
        if (depth >= 128 or self.remaining == 0) return error.CapabilityAnalysisLimit;
        self.remaining -= 1;
        var current = initial;
        for (0..128) |_| {
            if (current == 0 or current >= self.tree.nodes.items.len) return error.Unavailable;
            const value = self.tree.node(current);
            if (value.tag != .group) return value;
            current = value.a;
        }
        return error.CapabilityAnalysisLimit;
    }
    fn name(self: *Builder, name_: symbols.Symbol, environment: *const Environment, capturing: bool) Error!terms.Id {
        return self.namePath(name_, environment, capturing, false);
    }
    fn namePath(self: *Builder, name_: symbols.Symbol, environment: *const Environment, capturing: bool, operation: bool) Error!terms.Id {
        if (environment.get(name_)) |known| return known;
        const text = self.pool.get(name_);
        const separator = std.mem.findScalar(u8, text, '.') orelse {
            if (self.lexical_captures) return 0;
            return error.Unavailable;
        };
        const root = self.pool.lookup(text[0..separator]) orelse return error.Unavailable;
        var value = environment.get(root) orelse {
            if (self.lexical_captures) return 0;
            return error.Unavailable;
        };
        // Capturing a field expression's receiver retains that complete value,
        // whereas evaluating the field produces just the selected value.
        if (capturing) return value;
        var limit = text.len;
        if (operation) limit = std.mem.findScalarLast(u8, text, '.') orelse return error.Unavailable;
        var start = separator + 1;
        while (start < limit) {
            var end = limit;
            if (std.mem.findScalar(u8, text[start..limit], '.')) |next| end = start + next;
            const field = self.pool.lookup(text[start..end]) orelse return error.Unavailable;
            value = try self.store.project(self.allocator, value, field, .field);
            start = end + 1;
        }
        return value;
    }
    fn expression(self: *Builder, source: ast.Id, environment: *const Environment, depth: usize) Error!terms.Id {
        const value = try self.node(source, depth);
        var ungrouped = source;
        while (self.tree.node(ungrouped).tag == .group) ungrouped = self.tree.node(ungrouped).a;
        switch (value.tag) {
            .name => {
                if (ungrouped < self.operations.len and self.operations[ungrouped] != 0) return self.store.aggregate(self.allocator, .captures, &.{try self.namePath(value.a, environment, false, true)});
                if (environment.get(value.a) == null) if (self.functions) |functions| if (functions.lookup(functions.context, ungrouped)) |header| return self.store.callable(self.allocator, header, 0);
                return self.name(value.a, environment, false);
            },
            .integer, .float, .string, .boolean, .unit => return 0,
            .constructor_ref => return self.store.append(self.allocator, .{ .tag = .wrapped }),
            .type_witness => return self.store.append(self.allocator, .{ .tag = .wrapped, .a = try self.expression(value.a, environment, depth + 1) }),
            .field => {
                if (value.b == 0) return environment.get(value.a) orelse error.Unavailable;
                return self.expression(value.b, environment, depth + 1);
            },
            .field_access => {
                const receiver = try self.expression(value.a, environment, depth + 1);
                if (ungrouped < self.operations.len and self.operations[ungrouped] != 0) return self.store.aggregate(self.allocator, .captures, &.{receiver});
                return self.store.project(self.allocator, receiver, value.b, .field);
            },
            .index_access => return self.selectIndex(value.a, value.b, environment, depth + 1),
            .apply => {
                if (self.lexical_captures) {
                    const argument = try self.node(value.b, depth + 1);
                    var callee_source = value.a;
                    while (self.tree.node(callee_source).tag == .group) callee_source = self.tree.node(callee_source).a;
                    var head = ungrouped;
                    var operands: [16]ast.Id = undefined;
                    var count: usize = 0;
                    while (true) {
                        const applied = try self.node(head, depth + 1);
                        if (applied.tag != .apply) break;
                        if (count == operands.len) return error.Unavailable;
                        operands[count] = applied.b;
                        count += 1;
                        head = applied.a;
                    }
                    const primitive = try self.node(head, depth + 1);
                    if (primitive.tag == .intrinsic) {
                        const text = self.pool.get(primitive.a);
                        if (std.mem.startsWith(u8, text, "@u32.") or std.mem.startsWith(u8, text, "@f32.")) {
                            for (operands[0..count]) |operand| _ = try self.expression(operand, environment, depth + 1);
                            return 0;
                        }
                    }
                    if (argument.tag == .unit and callee_source < self.operations.len and self.operations[callee_source] != 0) {
                        _ = try self.expression(callee_source, environment, depth + 1);
                        if (self.input_types) |types| {
                            if (ungrouped >= self.input_expr_types.len) return error.Unavailable;
                            switch (types.node(types.head(self.input_expr_types[ungrouped], 0)).tag) {
                                .unit, .boolean, .u32, .f32, .never => return 0,
                                else => {},
                            }
                        }
                        return self.store.append(self.allocator, .{ .tag = .unknown });
                    }
                }
                if (flow.localSourceCall(self.tree, ungrouped)) |call| {
                    if (environment.get(call.name) != null) return error.Unavailable;
                    var nested: Environment = .{};
                    for (call.parameters[0..call.len], call.arguments[0..call.len]) |parameter, argument| try nested.bind(parameter, try self.expression(argument, environment, depth + 1));
                    return self.expression(call.body, &nested, depth + 1);
                }
                if (self.lexical_captures) if (self.functions) |functions| {
                    var callee = ungrouped;
                    var reverse: [16]ast.Id = undefined;
                    var count: usize = 0;
                    while (true) {
                        const node_ = try self.node(callee, depth + 1);
                        if (node_.tag != .apply) break;
                        if (count == reverse.len) return error.Unavailable;
                        reverse[count] = node_.b;
                        count += 1;
                        callee = node_.a;
                    }
                    if (functions.lookup(functions.context, callee)) |header| {
                        if (header.arity != count) return error.Unavailable;
                        var arguments: [16]terms.Id = undefined;
                        for (0..count) |index| arguments[index] = try self.expression(reverse[count - index - 1], environment, depth + 1);
                        return self.store.instantiate(self.allocator, header, arguments[0..count]);
                    }
                };
                if (flow.constructionSource(self.tree, self.pool, ungrouped)) |construction| {
                    var children: [3]terms.Id = undefined;
                    for (construction.inputs[0..construction.len], 0..) |input, index| children[index] = try self.expression(input, environment, depth + 1);
                    for (children[0..construction.len]) |child| try self.inputStore(child);
                    if (construction.kind == .computation) return self.store.append(self.allocator, .{ .tag = .wrapped, .a = children[0] });
                    return self.store.aggregate(self.allocator, .captures, children[0..construction.len]);
                }
                if (flow.projectionSource(self.tree, self.pool, ungrouped)) |projection| return self.selectIndex(projection.receiver, projection.index, environment, depth + 1);
                const callee = try self.node(value.a, depth + 1);
                if (callee.tag == .intrinsic) {
                    const intrinsic_name = self.pool.get(callee.a);
                    if (std.mem.eql(u8, intrinsic_name, "@usage.read") or std.mem.eql(u8, intrinsic_name, "@usage.length")) {
                        if (self.lexical_captures) _ = try self.expression(value.b, environment, depth + 1);
                        return 0;
                    }
                }
                if (callee.tag != .constructor_ref) return error.Unavailable;
                return self.store.append(self.allocator, .{ .tag = .wrapped, .a = try self.expression(value.b, environment, depth + 1) });
            },
            .product, .array => {
                var children: [4096]u32 = undefined;
                const sources = self.tree.children(ungrouped);
                if (sources.len > children.len) return error.CapabilityAnalysisLimit;
                for (sources, 0..) |child, index| {
                    children[index] = try self.expression(child, environment, depth + 1);
                    if (value.tag == .array) try self.inputStore(children[index]);
                }
                return self.store.aggregate(self.allocator, .product, children[0..sources.len]);
            },
            .record => {
                var fields: [4096]u32 = undefined;
                const sources = self.tree.children(ungrouped);
                if (sources.len > fields.len / 2) return error.CapabilityAnalysisLimit;
                for (sources, 0..) |child, index| {
                    const field = self.tree.node(child);
                    fields[index * 2] = field.a;
                    fields[index * 2 + 1] = try self.expression(child, environment, depth + 1);
                }
                const record: terms.Id = try self.store.aggregate(self.allocator, .record, fields[0 .. sources.len * 2]);
                if (value.a != 0) return self.store.append(self.allocator, .{ .tag = .wrapped, .a = record });
                // aggregate copies field words; this result is a node ID.
                // zig-analyzer: disable-next-line returning-local-slice
                return record;
            },
            .if_expr => {
                if (self.lexical_captures) _ = try self.expression(value.a, environment, depth + 1);
                return self.store.aggregate(self.allocator, .join, &.{ try self.expression(value.b, environment, depth + 1), try self.expression(value.c, environment, depth + 1) });
            },
            .block => {
                if (value.c != 0) return error.Unavailable;
                var nested = environment.*;
                const children = self.tree.children(ungrouped);
                for (children, 0..) |child, index| {
                    const statement = self.tree.node(child);
                    if (statement.tag == .return_stmt and index + 1 == children.len) return self.expression(statement.a, &nested, depth + 1);
                    if (self.lexical_captures and statement.tag == .use_stmt) {
                        const retained = try self.expression(statement.b, &nested, depth + 1);
                        if (statement.a != 0) try nested.bind(statement.a, retained);
                        continue;
                    }
                    if (statement.tag != .let_stmt) return error.Unavailable;
                    const binding = self.tree.binding(child);
                    const alias_pattern = self.tree.node(binding.pattern);
                    if (alias_pattern.tag != .pattern_name or binding.fallback != 0) return error.Unavailable;
                    try nested.bind(alias_pattern.a, try self.expression(binding.value, &nested, depth + 1));
                }
                return error.Unavailable;
            },
            .case_expr => {
                const inputs = self.tree.extra.items[value.a..][0..2];
                if (inputs[1] > 16 or value.c > 4096) return error.CapabilityAnalysisLimit;
                var retained: [16]terms.Id = undefined;
                for (self.tree.list(.{ .start = inputs[0], .len = inputs[1] }), 0..) |input, index| retained[index] = try self.expression(input, environment, depth + 1);
                var arms: [4096]terms.Id = undefined;
                for (self.tree.list(.{ .start = value.b, .len = value.c }), 0..) |arm_id, index| {
                    const arm = self.tree.node(arm_id);
                    var nested = environment.*;
                    const start = nested.len;
                    for (self.tree.list(.{ .start = arm.a, .len = arm.b })) |row| {
                        const patterns = self.tree.children(row);
                        if (patterns.len != inputs[1]) return error.Unavailable;
                        for (patterns, retained[0..inputs[1]]) |pattern, origin| try self.bindShapePattern(pattern, origin, &nested, start, depth + 1);
                    }
                    const details = self.tree.extra.items[arm.c..][0..2];
                    if (self.lexical_captures and details[0] != 0) _ = try self.expression(details[0], &nested, depth + 1);
                    arms[index] = try self.expression(details[1], &nested, depth + 1);
                }
                return self.store.aggregate(self.allocator, .join, arms[0..value.c]);
            },
            .lambda => {
                var captures: [4096]terms.Id = undefined;
                var count: usize = 0;
                try self.capture(source, environment, &captures, &count, depth + 1);
                for (captures[0..count]) |capture_| try self.inputStore(capture_);
                return self.store.aggregate(self.allocator, .captures, captures[0..count]);
            },
            else => return error.Unavailable,
        }
    }
    fn inputStore(self: *Builder, root: terms.Id) Error!void {
        if (self.lexical_captures and try self.store.view().containsParameter(root, &self.remaining)) return error.Unavailable;
    }
    fn selectIndex(self: *Builder, receiver: ast.Id, index: ast.Id, environment: *const Environment, depth: usize) Error!terms.Id {
        const base = try self.expression(receiver, environment, depth + 1);
        const selector = try self.node(index, depth + 1);
        if (selector.tag != .integer) return self.store.elements(self.allocator, base);
        return self.store.project(self.allocator, base, selector.a, .index);
    }
    fn bindPattern(self: *Builder, environment: *Environment, start: usize, name_: symbols.Symbol, value: terms.Id) Error!void {
        for (environment.entries[start..environment.len]) |*entry| if (entry.name == name_) {
            if (entry.value != value) entry.value = try self.store.aggregate(self.allocator, .join, &.{ entry.value, value });
            return;
        };
        try environment.bind(name_, value);
    }
    fn directPayload(self: *Builder, name_: symbols.Symbol) bool {
        for (self.tree.roots.items) |root| {
            const declaration = self.tree.node(root);
            if (declaration.tag != .data_decl) continue;
            for (self.tree.children(declaration.b)) |constructor| {
                const node_ = self.tree.node(constructor);
                if (node_.a != name_) continue;
                for (self.tree.declaration_traits.items) |traits| if (traits.declaration == root and traits.is_opaque) return true;
                return node_.b == 0 or self.tree.node(node_.b).tag != .type_record;
            }
        }
        return false;
    }
    fn bindShapePattern(self: *Builder, source: ast.Id, origin: terms.Id, environment: *Environment, start: usize, depth: usize) Error!void {
        const value = try self.node(source, depth);
        switch (value.tag) {
            .pattern_name => try self.bindPattern(environment, start, value.a, origin),
            .pattern_integer, .pattern_boolean => {},
            .pattern_field => {
                const field = try self.store.project(self.allocator, origin, value.a, .field);
                if (value.b != 0) try self.bindShapePattern(value.b, field, environment, start, depth + 1) else try self.bindPattern(environment, start, value.a, field);
            },
            .pattern_constructor => {
                if (value.b != 0) {
                    if (!self.directPayload(value.a)) return error.Unavailable;
                    try self.bindShapePattern(value.b, try self.store.project(self.allocator, origin, 0, .payload), environment, start, depth + 1);
                }
            },
            .pattern_product => for (self.tree.children(source), 0..) |child, index| try self.bindShapePattern(child, try self.store.project(self.allocator, origin, @intCast(index), .index), environment, start, depth + 1),
            .pattern_record => for (self.tree.children(source)) |child| try self.bindShapePattern(child, origin, environment, start, depth + 1),
            else => return error.Unavailable,
        }
    }
    fn capture(self: *Builder, source: ast.Id, environment: *const Environment, captures: *[4096]terms.Id, count: *usize, depth: usize) Error!void {
        const value = try self.node(source, depth);
        var ungrouped = source;
        while (self.tree.node(ungrouped).tag == .group) ungrouped = self.tree.node(ungrouped).a;
        switch (value.tag) {
            .name => {
                const captured = try self.name(value.a, environment, true);
                if (captured == 0) return;
                for (captures[0..count.*]) |known| if (known == captured) return;
                if (count.* == captures.len) return error.CapabilityAnalysisLimit;
                captures[count.*] = captured;
                count.* += 1;
            },
            .intrinsic, .integer, .float, .string, .boolean, .unit => {},
            .lambda => {
                var nested = environment.*;
                try nested.bind(self.tree.parameter(value.a).name, 0);
                try self.capture(value.b, &nested, captures, count, depth + 1);
            },
            .apply, .index_access => {
                try self.capture(value.a, environment, captures, count, depth + 1);
                try self.capture(value.b, environment, captures, count, depth + 1);
            },
            .field_access, .return_stmt, .function_return_stmt, .yield_stmt => try self.capture(value.a, environment, captures, count, depth + 1),
            .field => {
                if (value.b != 0) try self.capture(value.b, environment, captures, count, depth + 1) else {
                    const known = environment.get(value.a) orelse return error.Unavailable;
                    if (count.* == captures.len) return error.CapabilityAnalysisLimit;
                    captures[count.*] = known;
                    count.* += 1;
                }
            },
            .unary, .operator_tail => try self.capture(value.b, environment, captures, count, depth + 1),
            .binary => {
                try self.capture(value.b, environment, captures, count, depth + 1);
                try self.capture(value.c, environment, captures, count, depth + 1);
            },
            .block => {
                if (value.c != 0) return error.Unavailable;
                var nested = environment.*;
                for (self.tree.children(ungrouped)) |child| {
                    const statement = self.tree.node(child);
                    if (statement.tag == .let_stmt) {
                        const binding = self.tree.binding(child);
                        if (binding.fallback != 0) return error.Unavailable;
                        try self.capture(binding.value, &nested, captures, count, depth + 1);
                        try self.bindShapePattern(binding.pattern, 0, &nested, nested.len, depth + 1);
                    } else try self.capture(child, &nested, captures, count, depth + 1);
                }
            },
            .case_expr => {
                const inputs = self.tree.extra.items[value.a..][0..2];
                if (inputs[1] > 16) return error.Unavailable;
                for (self.tree.list(.{ .start = inputs[0], .len = inputs[1] })) |input| try self.capture(input, environment, captures, count, depth + 1);
                for (self.tree.list(.{ .start = value.b, .len = value.c })) |arm_id| {
                    const arm = self.tree.node(arm_id);
                    var nested = environment.*;
                    const start = nested.len;
                    for (self.tree.list(.{ .start = arm.a, .len = arm.b })) |row| {
                        const patterns = self.tree.children(row);
                        if (patterns.len != inputs[1]) return error.Unavailable;
                        for (patterns) |pattern| try self.bindShapePattern(pattern, 0, &nested, start, depth + 1);
                    }
                    const details = self.tree.extra.items[arm.c..][0..2];
                    if (details[0] != 0) try self.capture(details[0], &nested, captures, count, depth + 1);
                    try self.capture(details[1], &nested, captures, count, depth + 1);
                }
            },
            .if_expr => {
                try self.capture(value.a, environment, captures, count, depth + 1);
                try self.capture(value.b, environment, captures, count, depth + 1);
                try self.capture(value.c, environment, captures, count, depth + 1);
            },
            .product, .record, .array => for (self.tree.children(ungrouped)) |child| try self.capture(child, environment, captures, count, depth + 1),
            else => return error.Unavailable,
        }
    }
};
/// Optional result; absence does not alter the existing conservative contract.
/// Every failed/unsupported derivation rolls back its private construction.
pub fn derive(allocator: A, store: *terms.Store, tree: *const ast.Tree, pool: *const symbols.Pool, source: ast.Id, summary: flow.Parameters) terms.Error!?terms.Id {
    return deriveChecked(allocator, store, tree, pool, source, summary, &.{});
}
pub fn deriveChecked(allocator: A, store: *terms.Store, tree: *const ast.Tree, pool: *const symbols.Pool, source: ast.Id, summary: flow.Parameters, operations: []const u32) terms.Error!?terms.Id {
    if (!summary.valid() or !summary.present() or summary.invokes()) return null;
    const checkpoint = store.mark();
    errdefer store.rollback(checkpoint);
    var builder: Builder = .{ .allocator = allocator, .store = store, .tree = tree, .pool = pool, .operations = operations };
    _ = try store.append(allocator, .{ .tag = .empty });
    var environment: Environment = .{};
    var body = source;
    for (0..summary.arity()) |index| {
        const lambda = builder.node(body, 0) catch |err| {
            store.rollback(checkpoint);
            switch (err) {
                error.Unavailable => return null,
                else => return @errorCast(err),
            }
        };
        if (lambda.tag != .lambda) {
            store.rollback(checkpoint);
            return null;
        }
        try environment.bind(tree.parameter(lambda.a).name, try store.append(allocator, .{ .tag = .parameter, .a = @intCast(index) }));
        body = lambda.b;
    }
    const result = builder.expression(body, &environment, 0) catch |err| {
        store.rollback(checkpoint);
        switch (err) {
            error.Unavailable => return null,
            else => return @errorCast(err),
        }
    };
    // Optional precision may decline a large source relationship; never admit
    // a source claim that its bounded portable validator cannot reconstruct.
    store.view().validate(result, summary.arity(), true) catch {
        store.rollback(checkpoint);
        return null;
    };
    return result;
}

/// A lexical callback's formal input graph. Earlier captures are owned by the
/// receiver's separate capture graph, never erased from its lifetime proof.
pub fn deriveClosure(allocator: A, store: *terms.Store, tree: *const ast.Tree, pool: *const symbols.Pool, source: ast.Id, operations: []const u32, types: *const @import("types.zig").Store, expr_types: []const @import("types.zig").Id) terms.Error!?terms.Id {
    return deriveInputFunction(allocator, store, tree, pool, source, operations, types, expr_types, 1);
}
pub fn deriveInputFunction(allocator: A, store: *terms.Store, tree: *const ast.Tree, pool: *const symbols.Pool, source: ast.Id, operations: []const u32, types: *const @import("types.zig").Store, expr_types: []const @import("types.zig").Id, arity: u8) terms.Error!?terms.Id {
    return deriveInputFunctionWithFunctions(allocator, store, tree, pool, source, operations, types, expr_types, arity, null);
}
pub fn deriveInputFunctionWithFunctions(allocator: A, store: *terms.Store, tree: *const ast.Tree, pool: *const symbols.Pool, source: ast.Id, operations: []const u32, types: *const @import("types.zig").Store, expr_types: []const @import("types.zig").Id, arity: u8, functions: ?Functions) terms.Error!?terms.Id {
    if (arity == 0 or arity > 16) return null;
    const checkpoint = store.mark();
    errdefer store.rollback(checkpoint);
    var builder: Builder = .{ .allocator = allocator, .store = store, .tree = tree, .pool = pool, .operations = operations, .lexical_captures = true, .input_types = types, .input_expr_types = expr_types, .functions = functions };
    _ = try store.append(allocator, .{ .tag = .empty });
    var environment: Environment = .{};
    var body = source;
    for (0..arity) |index| {
        const lambda = builder.node(body, 0) catch |err| {
            store.rollback(checkpoint);
            if (err == error.Unavailable) return null;
            return @errorCast(err);
        };
        if (lambda.tag != .lambda or (tree.parameter(lambda.a).name == 0 and !tree.parameter(lambda.a).is_unit) or tree.parameter(lambda.a).demanded) {
            store.rollback(checkpoint);
            return null;
        }
        if (tree.parameter(lambda.a).name != 0) try environment.bind(tree.parameter(lambda.a).name, try store.append(allocator, .{ .tag = .parameter, .a = @intCast(index) }));
        body = lambda.b;
    }
    const result = builder.expression(body, &environment, 0) catch |err| {
        store.rollback(checkpoint);
        if (err == error.Unavailable) return null;
        return @errorCast(err);
    };
    store.view().validate(result, arity, true) catch {
        store.rollback(checkpoint);
        return null;
    };
    return result;
}

fn shapeLaw(allocator: A) !void {
    const text = "const pack = fn left => fn right => {young: fn () => left (), old: fn () => right ()}\n";
    var tokens = try @import("../parse/lexer.zig").lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const body = tree.valueDecl(tree.roots.items[0]).body;
    const summary = flow.parameterSource(&tree, &pool, body, 0);
    try std.testing.expectEqual(@as(u16, 3), summary.mask);
    var prototype: terms.Store = .{};
    defer prototype.deinit(allocator);
    const result = (try derive(allocator, &prototype, &tree, &pool, body, summary)).?;
    var header = try prototype.own(allocator, summary.arity(), result);
    defer header.deinit(allocator);
    var receiver: terms.Store = .{};
    defer receiver.deinit(allocator);
    const younger = try receiver.append(allocator, .{ .tag = .authority, .a = 7, .b = 3 });
    const older = try receiver.append(allocator, .{ .tag = .authority, .a = 7, .b = 1 });
    const whole = try receiver.instantiate(allocator, header, &.{ younger, older });
    const selected = try receiver.project(allocator, whole, pool.lookup("old").?, .field);
    const captures = receiver.nodes.items[selected];
    try std.testing.expectEqual(terms.Tag.captures, captures.tag);
    try std.testing.expectEqualSlices(u32, &.{older}, receiver.view().children(captures));
}
test "owned source result recipes preserve separate closure fields" {
    try shapeLaw(std.testing.allocator);
}

/// The separate no-store marker is proved with the lexical input reader. An
/// ordinary public result recipe can retain input stores and is insufficient.
pub fn inputFunction(tree: *const ast.Tree, pool: *const symbols.Pool, source: ast.Id, operations: []const u32, types: *const @import("types.zig").Store, expr_types: []const @import("types.zig").Id, arity: u8) bool {
    var storage: [1024 * 1024]u8 align(@alignOf(usize)) = undefined;
    var buffers: std.heap.FixedBufferAllocator = .init(&storage);
    const allocator = buffers.allocator();
    var reconstructed: terms.Store = .{};
    defer reconstructed.deinit(allocator);
    const root = (deriveInputFunction(allocator, &reconstructed, tree, pool, source, operations, types, expr_types, arity) catch return false) orelse return false;
    reconstructed.view().validate(root, arity, true) catch return false;
    for (reconstructed.nodes.items) |node_| if (node_.tag == .unknown) return false;
    return true;
}
