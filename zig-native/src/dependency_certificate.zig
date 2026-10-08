//! A successful frozen-Core/dependency validation, owned by one published
//! revision. The source stamps and every foreign bound read by validation
//! travel together. A certificate never authorizes semantic or code reuse.
const std = @import("std");
const validation = @import("frozen_core_validation.zig");
const A = std.mem.Allocator;

pub const Certificate = struct {
    context: validation.ContextImage,
    modules: [][32]u8,

    pub fn capture(a: A, context: validation.Context, pins: anytype) A.Error!Certificate {
        var image = try validation.ContextImage.capture(a, context);
        errdefer image.deinit(a);
        const modules = try a.alloc([32]u8, pins.len);
        for (modules, pins) |*digest, pin| digest.* = pin.stamp;
        return .{ .context = image, .modules = modules };
    }

    pub fn deinit(self: *Certificate, a: A) void {
        self.context.deinit(a);
        a.free(self.modules);
        self.* = undefined;
    }

    pub fn matches(self: *const Certificate, context: validation.Context) bool {
        return self.modules.len == context.units.len and self.context.matches(context);
    }

    pub fn admits(self: *const Certificate, unit: usize, digest: [32]u8) bool {
        return unit < self.modules.len and std.mem.eql(u8, &self.modules[unit], &digest);
    }
};
