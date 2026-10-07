//! Physical record slots follow field-name identity, independently of source
//! evaluation order or an annotation's spelling. An empty permutation is the
//! identity; callers release nonempty results with their supplied allocator.
const std = @import("std");
const T = @import("types.zig");
const core = @import("core.zig");

/// Spellings borrow immutable Core for the lifetime of one emission session.
/// The numeric fallback is only for synthetic layout clients without Core.
pub const Names = struct {
    map: std.AutoHashMapUnmanaged(u32, []const u8) = .empty,
    pub fn deinit(self: *Names, allocator: std.mem.Allocator) void {
        self.map.deinit(allocator);
    }
    pub fn add(self: *Names, allocator: std.mem.Allocator, module: *const core.Module) (std.mem.Allocator.Error || error{TypeMismatch})!void {
        for (module.field_names) |field| {
            const text = module.name(field.spelling);
            const entry = try self.map.getOrPut(allocator, field.symbol);
            if (entry.found_existing) {
                if (!std.mem.eql(u8, entry.value_ptr.*, text)) return error.TypeMismatch;
            } else entry.value_ptr.* = text;
        }
    }
    pub fn less(self: *const Names, left: u32, right: u32) bool {
        const a = self.map.get(left);
        const b = self.map.get(right);
        if (a) |text| return if (b) |other| std.mem.order(u8, text, other) == .lt else false;
        return if (b != null) true else left < right;
    }
};

pub fn destinations(allocator: std.mem.Allocator, source: anytype, record: T.Node, names: *const Names) std.mem.Allocator.Error![]u32 {
    std.debug.assert(record.tag == .record);
    if (record.b < 2) return &.{};
    var ordered = true;
    for (1..record.b) |index| if (!names.less(source.recordField(record, index - 1).name, source.recordField(record, index).name)) {
        ordered = false;
        break;
    };
    if (ordered) return &.{};
    var buffer: [256]u8 align(@alignOf(u32)) = undefined;
    var scratch: std.heap.BufferFirstAllocator = .init(&buffer, allocator);
    const sorted = try scratch.allocator().alloc(u32, record.b);
    defer scratch.allocator().free(sorted);
    for (sorted, 0..) |*slot, index| slot.* = @intCast(index);
    const Context = struct {
        source: @TypeOf(source),
        record: T.Node,
        names: *const Names,
        fn less(self: @This(), left: u32, right: u32) bool {
            return self.names.less(self.source.recordField(self.record, left).name, self.source.recordField(self.record, right).name);
        }
    };
    std.mem.sortUnstable(u32, sorted, Context{ .source = source, .record = record, .names = names }, Context.less);
    const result = try allocator.alloc(u32, record.b);
    for (sorted, 0..) |original, index| result[original] = @intCast(index);
    return result;
}
