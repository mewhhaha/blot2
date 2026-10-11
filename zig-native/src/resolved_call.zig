//! Calls selected before instruction emission. A plan names the callee's
//! specialization and the semantic interface of every closure it applies, so
//! emission never derives a call signature from the machine types of the
//! values it happens to pass. Materializing a function index stays with
//! emission, which keeps the module's function order.
const std = @import("std");
const code_artifacts = @import("code_artifacts.zig");
const layout = @import("layout.zig");
const Allocator = std.mem.Allocator;

/// A closure's semantic interface: parameter, result and latent effect row.
pub const Arrow = struct { parameter: layout.Id, result: layout.Id, row: u32 };

/// A named call. The first `key.count` arguments are the callee's parameters;
/// each later argument applies the closure the previous application returned,
/// through the corresponding arrow.
pub const Named = struct {
    key: code_artifacts.Key,
    extra: std.ArrayList(Arrow) = .empty,
    pub fn deinit(self: *Named, a: Allocator) void {
        self.extra.deinit(a);
        self.* = undefined;
    }
};

/// A selected callee taking a known prefix of the arguments: its body's
/// parameters directly, or one argument through a callable wrapper. Later
/// arguments apply the returned closures through `extra`.
pub const Applied = struct {
    callee: union(enum) {
        direct: code_artifacts.Key,
        wrapper: code_artifacts.CallableKey,
    },
    consumed: usize,
    extra: std.ArrayList(Arrow) = .empty,
    pub fn deinit(self: *Applied, a: Allocator) void {
        self.extra.deinit(a);
        self.* = undefined;
    }
};

/// Follows `ty` through `count` applications, failing when a result is not a
/// closure. The arrows are appended to `out` in application order.
pub fn arrows(a: Allocator, store: *const layout.Store, ty: layout.Id, count: usize, out: *std.ArrayList(Arrow)) error{ OutOfMemory, NotFunction }!layout.Id {
    var current = ty;
    try out.ensureUnusedCapacity(a, count);
    for (0..count) |_| {
        const node = store.node(current);
        if (node.tag != .function) return error.NotFunction;
        out.appendAssumeCapacity(.{ .parameter = node.a, .result = node.b, .row = node.c });
        current = node.b;
    }
    return current;
}
