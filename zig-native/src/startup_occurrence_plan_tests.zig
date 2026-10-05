const std = @import("std");
const core = @import("core.zig");
const graph = @import("startup_graph.zig");
const flow = @import("startup_occurrence_flow.zig");
const occurrence = @import("startup_occurrence_plan.zig");
const a = std.testing.allocator;
fn ref(binding: u32) core.BindingRef {
    return .{ .unit = 1, .binding = binding };
}
fn edge(root: u32, target: u32, weak: bool) flow.Edge {
    return .{ .root = ref(root), .target = ref(target), .weak = weak, .kind = .selected_call, .unit = 1, .node = 1 };
}

test "complete occurrence ordering accepts weak selected self read and keeps source capture cycles strong" {
    var original = try graph.Graph.init(a, &.{
        .{ .target = ref(1), .references = &.{ref(4)}, .is_function = true },
        .{ .target = ref(2), .references = &.{}, .is_function = true },
        .{ .target = ref(3), .references = &.{ref(2)} },
        .{ .target = ref(4), .references = &.{ref(3)}, .runtime = true },
    });
    defer original.deinit(a);
    var permitted = try occurrence.plan(a, &original, &.{edge(4, 1, true)}, &.{ true, true, true, true });
    defer permitted.deinit(a);
    try std.testing.expect(permitted.cycle == null);
    try std.testing.expectEqualSlices(core.BindingRef, &.{ref(4)}, permitted.initializers);
    var strict = try occurrence.plan(a, &original, &.{edge(4, 1, false)}, &.{ true, true, true, true });
    defer strict.deinit(a);
    try std.testing.expectEqual(ref(4), strict.cycle.?);
    var captured = try graph.Graph.init(a, &.{
        .{ .target = ref(1), .references = &.{ref(4)}, .is_function = true },
        .{ .target = ref(2), .references = &.{ref(4)}, .is_function = true },
        .{ .target = ref(3), .references = &.{ref(2)} },
        .{ .target = ref(4), .references = &.{ref(3)}, .runtime = true },
    });
    defer captured.deinit(a);
    var rejected = try occurrence.plan(a, &captured, &.{edge(4, 1, true)}, &.{ true, true, true, true });
    defer rejected.deinit(a);
    try std.testing.expectEqual(ref(4), rejected.cycle.?);
}

test "shared helper ready and waiting occurrences keep distinct cycle obligations" {
    var original = try graph.Graph.init(a, &.{
        .{ .target = ref(1), .references = &.{ref(5)}, .is_function = true },
        .{ .target = ref(2), .references = &.{}, .is_function = true },
        .{ .target = ref(3), .references = &.{ref(2)} },
        .{ .target = ref(4), .references = &.{ref(3)}, .runtime = true },
        .{ .target = ref(5), .references = &.{ref(3)}, .runtime = true },
    });
    defer original.deinit(a);
    var rejected = try occurrence.plan(a, &original, &.{ edge(4, 1, true), edge(5, 1, false) }, &.{ true, true, true, true, true });
    defer rejected.deinit(a);
    try std.testing.expectEqual(ref(5), rejected.cycle.?);
}

test "original declaration vertices preserve diagnostic order during occurrence admission" {
    var original = try graph.Graph.init(a, &.{
        .{ .target = ref(1), .references = &.{}, .is_function = true },
        .{ .target = ref(2), .references = &.{ref(3)}, .runtime = true },
        .{ .target = ref(3), .references = &.{ ref(1), ref(2) }, .runtime = true },
    });
    defer original.deinit(a);
    var ordinary = try original.plan(a, &.{ true, true, true });
    defer ordinary.deinit(a);
    var exact = try occurrence.plan(a, &original, &.{}, &.{ true, true, true });
    defer exact.deinit(a);
    try std.testing.expectEqual(ordinary.cycle.?, exact.cycle.?);
}
