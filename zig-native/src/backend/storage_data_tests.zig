const std = @import("std");
const layout = @import("storage_layout.zig");
test "flat storage layouts bound products and discriminated payloads" {
    try std.testing.expectEqual(@as(u32, 8), try layout.productBytes(&.{ 4, 4 }));
    try std.testing.expectEqual(@as(u32, 12), try layout.variantBytes(&.{ 4, 8 }));
    try std.testing.expectEqual(@as(u32, 24), try layout.productBytes(&.{ 4, 20 }));
    try std.testing.expectError(error.InvalidLayout, layout.productBytes(&.{ 0xfffffffc, 4 }));
    try std.testing.expectError(error.InvalidLayout, layout.variantBytes(&.{0xfffffffc}));
    try std.testing.expectError(error.InvalidLayout, layout.productBytes(&.{3}));
    try std.testing.expectEqual(@as(?usize, 1), layout.variantIndex(&.{ 2, 7 }, 7));
    try std.testing.expectEqual(@as(?usize, null), layout.variantIndex(&.{ 2, 7 }, 0));
}
