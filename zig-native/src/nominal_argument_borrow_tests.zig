const std = @import("std");
const T = @import("types.zig");
const failures = @import("allocation_failures.zig");

// Force growable Store tables to move. Pending work uses a separate allocation
// from Store.extra, even when both ultimately have this same backing allocator.
const Probe = struct {
    backing: std.mem.Allocator,
    requests: usize = 0,
    requested_bytes: usize = 0,

    fn allocator(self: *Probe) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Probe = @ptrCast(@alignCast(raw));
        const result = self.backing.rawAlloc(len, alignment, ra) orelse return null;
        self.requests += 1;
        self.requested_bytes += len;
        return result;
    }
    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }
    fn free(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.backing.rawFree(memory, alignment, ra);
    }
};

fn wideGrowth(a: std.mem.Allocator) !void {
    var probe: Probe = .{ .backing = a };
    var store = try T.Store.initWithOptions(probe.allocator(), .{ .resolution_cache = false });
    defer store.deinit();
    var left_args: [160]T.Id = undefined;
    var right_args: [160]T.Id = undefined;
    const first = try store.fresh();
    left_args[0] = first;
    right_args[0] = T.boolean;
    // The first popped equation binds first. Resolving the second equation
    // then normalizes this product and grows Store.extra after all 160 IDs
    // have been copied into the pending vector.
    left_args[1] = try store.product(&.{ first, try store.array(first), first });
    right_args[1] = try store.product(&.{ T.boolean, try store.array(T.boolean), T.boolean });
    for (2..left_args.len) |i| {
        left_args[i] = try store.fresh();
        right_args[i] = if (i % 2 == 0) T.u32_type else T.f32_type;
    }
    const identity: T.NominalIdentity = .{ .unit = 7, .decl = 19 };
    const left = try store.nominal(identity, &left_args);
    const right = try store.nominal(identity, &right_args);
    const remaining = store.extra.capacity - store.extra.items.len;
    for (0..remaining) |_| _ = try store.saveList(&.{T.unit});
    const before = store.mark();
    const extra_address = @intFromPtr(store.extra.items.ptr);
    store.unify(left, right) catch |err| {
        if (err == error.OutOfMemory) {
            try std.testing.expectEqualDeep(before, store.mark());
            try std.testing.expectEqualSlices(T.Id, &left_args, store.nominalArguments(store.node(left)));
            try std.testing.expectEqualSlices(T.Id, &right_args, store.nominalArguments(store.node(right)));
        }
        return err;
    };
    try std.testing.expect(extra_address != @intFromPtr(store.extra.items.ptr));
    try std.testing.expectEqual(@as(usize, 159), store.versions.items.len - before.versions);
    for (store.versions.items[before.versions..], 0..) |write, index| {
        const arg_index = if (index == 0) 0 else index + 1;
        try std.testing.expectEqual(store.node(left_args[arg_index]).a, write.variable);
        try std.testing.expectEqual(right_args[arg_index], write.replacement);
        try std.testing.expectEqual(before.effects.next_position + @as(T.Cursor, @intCast(index)), write.position);
        try std.testing.expectEqual(write.replacement, try store.resolve(left_args[arg_index], write.position));
        const after_write = try store.resolve(left_args[arg_index], write.position + 1);
        try std.testing.expectEqual(T.Tag.variable, store.node(after_write).tag);
        try std.testing.expectEqual(write.position + 1, store.node(after_write).b);
    }
    try std.testing.expectEqualSlices(T.Id, &left_args, store.nominalArguments(store.node(left)));
    try std.testing.expectEqualSlices(T.Id, &right_args, store.nominalArguments(store.node(right)));
}

test "nominal borrowed children survive spilled pending work and later Store relocation" {
    try wideGrowth(std.testing.allocator);
}

test "nominal pending growth and partial writes roll back every allocation failure" {
    try failures.checkAllAllocationFailures(std.testing.allocator, wideGrowth, .{});
}

const Report = struct {
    allocator: std.mem.Allocator,
    equation: ?[]T.Id = null,
    versions: usize = 0,
    row_versions: usize = 0,
    cursor: T.Cursor = 0,

    fn deinit(self: *Report) void {
        if (self.equation) |ids| self.allocator.free(ids);
    }
    fn observe(raw: *anyopaque, store: *const T.Store, left: T.Id, right: T.Id) std.mem.Allocator.Error!void {
        const self: *Report = @ptrCast(@alignCast(raw));
        const owned = try self.allocator.dupe(T.Id, &.{ left, right });
        self.equation = owned;
        self.versions = store.versions.items.len;
        self.row_versions = store.effects.versions.items.len;
        self.cursor = store.cursor();
    }
};

fn mismatchAndRetry(a: std.mem.Allocator) !void {
    var store = try T.Store.initWithOptions(a, .{ .resolution_cache = false });
    defer store.deinit();
    const first = try store.fresh();
    const parameter = try store.fresh();
    const row = try store.freshEffects();
    const function = try store.functionWithEffects(parameter, T.boolean, row);
    const failed_function = try store.functionWithEffects(T.u32_type, T.f32_type, 0);
    const valid_function = try store.functionWithEffects(T.u32_type, T.boolean, 0);
    var left_args: [96]T.Id = @splat(T.unit);
    var failed_args: [96]T.Id = @splat(T.unit);
    var valid_args: [96]T.Id = @splat(T.unit);
    left_args[0] = first;
    failed_args[0] = T.boolean;
    valid_args[0] = T.boolean;
    left_args[1] = function;
    failed_args[1] = failed_function;
    valid_args[1] = valid_function;
    const identity: T.NominalIdentity = .{ .unit = 3, .decl = 5 };
    const left = try store.nominal(identity, &left_args);
    const failed = try store.nominal(identity, &failed_args);
    const valid = try store.nominal(identity, &valid_args);
    const before = store.mark();
    var report: Report = .{ .allocator = a };
    defer report.deinit();
    store.unifyWithReporter(left, failed, .{ .context = &report, .report = Report.observe }) catch |err| {
        try std.testing.expectEqualDeep(before, store.mark());
        try std.testing.expectEqualSlices(T.Id, &left_args, store.nominalArguments(store.node(left)));
        if (err == error.OutOfMemory) return err;
        if (err != error.TypeMismatch) return err;
        try std.testing.expectEqualSlices(T.Id, &.{ T.boolean, T.f32_type }, report.equation orelse return error.MissingMismatchEquation);
        // Outer argument 0 and nested function parameter precede the result;
        // the function's latent effect equation is still pending at failure.
        try std.testing.expectEqual(before.versions + 2, report.versions);
        try std.testing.expectEqual(before.effects.versions, report.row_versions);
        try std.testing.expectEqual(before.effects.next_position + 2, report.cursor);
        const retry_mark = store.mark();
        store.unify(left, valid) catch |retry_err| {
            if (retry_err == error.OutOfMemory) try std.testing.expectEqualDeep(retry_mark, store.mark());
            return retry_err;
        };
        try std.testing.expectEqual(T.boolean, try store.resolve(first, 0));
        try std.testing.expectEqual(T.u32_type, try store.resolve(parameter, 0));
        try std.testing.expect(store.row(try store.resolveEffects(row, 0)).tail == .closed);
        try std.testing.expectEqualSlices(T.Id, &left_args, store.nominalArguments(store.node(left)));
        return;
    };
    return error.ExpectedNominalMismatch;
}

test "nominal mismatch reports the first nested equation before rollback and retry" {
    try mismatchAndRetry(std.testing.allocator);
}

test "nominal reporter and nested row retry release every failed allocation" {
    try failures.checkAllAllocationFailures(std.testing.allocator, mismatchAndRetry, .{});
}

test "equal closed nominal graphs need no backing allocation during unification" {
    var probe: Probe = .{ .backing = std.testing.allocator };
    var store = try T.Store.initWithOptions(probe.allocator(), .{ .resolution_cache = false });
    defer store.deinit();
    const array = try store.array(T.u32_type);
    const identity: T.NominalIdentity = .{ .unit = 4, .decl = 11 };
    const left = try store.nominal(identity, &.{array});
    const right = try store.nominal(identity, &.{array});
    const before = store.mark();
    const requests = probe.requests;
    const requested_bytes = probe.requested_bytes;
    try store.unify(left, right);
    try std.testing.expectEqual(requests, probe.requests);
    try std.testing.expectEqual(requested_bytes, probe.requested_bytes);
    try std.testing.expectEqualDeep(before, store.mark());
}
