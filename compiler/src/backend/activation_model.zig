//! Short-lived views of current Generator ownership. No compiler pool or
//! mutable inference owner escapes the late assembly query.
const std = @import("std");
const K = @import("../reuse/code_artifacts.zig");
const I = @import("activation_intersection.zig");
const A = std.mem.Allocator;
pub const Borrowed = struct {
    borrowed: I.Model,
    functions: []K.Function,
    rows: []K.Span,
    templates: []K.Span,
    operations: []K.Operation,
    pub fn model(self: *const Borrowed) I.Model {
        var result = self.borrowed;
        result.functions = self.functions;
        result.rows.spans = self.rows;
        result.templates.spans = self.templates;
        result.operations = self.operations;
        return result;
    }
    fn spanCopy(a: A, store: anytype) A.Error![]K.Span {
        const result = try a.alloc(K.Span, store.spans.items.len);
        for (result, store.spans.items) |*to, from| to.* = .{ .start = from.start, .len = from.len };
        return result;
    }
    pub fn init(a: A, generator: anytype, identity: ?@import("runtime_identity.zig").View) A.Error!Borrowed {
        var functions: std.ArrayList(K.Function) = .empty;
        errdefer functions.deinit(a);
        var named = generator.planning.instances.iterator();
        while (named.next()) |entry| try functions.append(a, .{ .request = .{ .named = entry.key_ptr.* }, .function = entry.value_ptr.* });
        var closures = generator.planning.closures.iterator();
        while (closures.next()) |entry| try functions.append(a, .{ .request = .{ .closure = entry.key_ptr.* }, .function = entry.value_ptr.* });
        var callables = generator.planning.callables.iterator();
        while (callables.next()) |entry| try functions.append(a, .{ .request = .{ .callable = entry.key_ptr.* }, .function = entry.value_ptr.* });
        var constructors = generator.planning.constructor_functions.iterator();
        while (constructors.next()) |entry| try functions.append(a, .{ .request = .{ .constructor = entry.key_ptr.* }, .function = entry.value_ptr.* });
        var primitives = generator.planning.primitive_functions.iterator();
        while (primitives.next()) |entry| try functions.append(a, .{ .request = .{ .primitive = entry.key_ptr.* }, .function = entry.value_ptr.* });
        var operations = generator.planning.operation_functions.iterator();
        while (operations.next()) |entry| try functions.append(a, .{ .request = .{ .operation = entry.key_ptr.* }, .function = entry.value_ptr.* });
        var hosts = generator.planning.host_functions.iterator();
        while (hosts.next()) |entry| try functions.append(a, .{ .request = .{ .host = entry.key_ptr.* }, .function = entry.value_ptr.* });
        const rows = try spanCopy(a, &generator.representations.row_keys);
        errdefer a.free(rows);
        const templates = try spanCopy(a, &generator.representations.template_keys);
        errdefer a.free(templates);
        const symbols = try a.alloc(K.Operation, generator.planning.runtime_operations.entries.items.len);
        errdefer a.free(symbols);
        for (symbols, generator.planning.runtime_operations.entries.items) |*to, from| to.* = .{ .key = from.key, .foreign = from.foreign, .runtime = from.runtime };
        return .{ .borrowed = .{
            .units = generator.units,
            .functions = &.{},
            .evidence = generator.evaluator.storage.evidence.view(),
            .rows = .{ .entries = generator.representations.row_keys.entries.items, .spans = &.{} },
            .templates = .{ .entries = generator.representations.template_keys.entries.items, .spans = &.{} },
            .captures = generator.planning.template_catalog.items,
            .operations = &.{},
            .identity = identity,
        }, .functions = try functions.toOwnedSlice(a), .rows = rows, .templates = templates, .operations = symbols };
    }
    pub fn deinit(self: Borrowed, a: A) void {
        a.free(self.functions);
        a.free(self.rows);
        a.free(self.templates);
        a.free(self.operations);
    }
};

pub fn fromPools(units: []const @import("../check/core.zig").Module, pools: *const K.Pools) I.Model {
    return .{ .units = units, .functions = pools.functions, .evidence = pools.evaluator.evidence.view(), .rows = pools.rows, .templates = pools.templates, .captures = pools.captures, .operations = pools.operations, .identity = if (pools.identity) |*owned| owned.view() else null };
}

const Fixture = struct {
    planning: @import("backend_plan.zig").State,
    units: []const @import("../check/core.zig").Module = &.{},
    representations: struct { row_keys: @import("../reuse/substitution_keys.zig").Store, template_keys: @import("../reuse/substitution_keys.zig").Store },
    evaluator: struct { storage: struct { evidence: @import("../eval/type_evidence.zig").Store } },
    fn deinit(self: *Fixture, a: A) void {
        self.planning.deinit(a);
        self.representations.row_keys.deinit();
        self.representations.template_keys.deinit();
        self.evaluator.storage.evidence.deinit();
    }
};
fn borrowedOwnership(a: A, fixture: *Fixture) !void {
    const view = try Borrowed.init(a, fixture, null);
    defer view.deinit(a);
    try std.testing.expectEqual(@as(usize, 7), view.model().functions.len);
    try std.testing.expectEqual(@as(usize, 1), view.model().rows.spans.len);
    try std.testing.expectEqual(@as(usize, 1), view.model().templates.spans.len);
    try std.testing.expectEqual(@as(usize, 1), view.model().operations.len);
    try std.testing.expectEqual(@as(usize, 1), fixture.planning.runtime_operations.entries.items.len);
}
test "late activation model owns only temporary view arrays through every allocation failure" {
    const a = std.testing.allocator;
    var fixture: Fixture = .{ .representations = .{ .row_keys = .init(a), .template_keys = .init(a) }, .evaluator = .{ .storage = .{ .evidence = try @import("../eval/type_evidence.zig").Store.init(a) } }, .planning = .init(a) };
    defer fixture.deinit(a);
    try fixture.planning.instances.put(a, .{ .target = .{ .unit = 1, .binding = 1 } }, 0);
    try fixture.planning.closures.put(a, .{ .unit = 1, .catalog = 1, .ty = 1, .captures = 1 }, 1);
    try fixture.planning.callables.put(a, .{ .target = .{ .unit = 1, .binding = 1 }, .ty = 1 }, 2);
    try fixture.planning.constructor_functions.put(a, .{ .unit = 1, .catalog = 1, .ty = 1 }, 3);
    try fixture.planning.primitive_functions.put(a, .{ .unit = 1, .catalog = 1, .ty = 1 }, 4);
    try fixture.planning.operation_functions.put(a, .{ .operation = 1, .ty = 1 }, 5);
    try fixture.planning.host_functions.put(a, .{ .ty = 1 }, 6);
    _ = try fixture.representations.row_keys.intern(&.{.{ .variable = 1, .value = 0 }});
    _ = try fixture.representations.template_keys.intern(&.{.{ .variable = 1, .value = 1 }});
    const label = try fixture.evaluator.storage.evidence.effects.internOperation(.{ .unit = 1, .decl = 1 }, &.{3});
    _ = try fixture.planning.runtime_operations.intern(fixture.evaluator.storage.evidence.view(), label);
    try borrowedOwnership(a, &fixture);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, borrowedOwnership, .{&fixture});
}
