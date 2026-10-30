//! Fixed inline storage arithmetic shared by source admission and emission.
//! A variant has one discriminant word and the largest constructor payload;
//! every payload is initialized, but only its selected typed arm is accessed.
const std = @import("std");
const plan = @import("storage_plan.zig");
pub const alignment: u32 = 4;
pub const Error = error{InvalidLayout};

pub fn productBytes(fields: []const u32) Error!u32 {
    var size: u32 = 0;
    for (fields) |field| {
        if (field == 0 or field & 3 != 0) return error.InvalidLayout;
        size = std.math.add(u32, size, field) catch return error.InvalidLayout;
    }
    return @max(alignment, size);
}
pub fn variantBytes(payloads: []const u32) Error!u32 {
    if (payloads.len == 0) return error.InvalidLayout;
    var payload: u32 = 0;
    for (payloads) |size| {
        if (size == 0 or size & 3 != 0) return error.InvalidLayout;
        payload = @max(payload, size);
    }
    return std.math.add(u32, alignment, payload) catch error.InvalidLayout;
}
pub fn bytes(value: anytype) Error!u32 {
    return switch (value.tag) {
        .scalar => alignment,
        .ref, .link => plan.borrow_words * alignment,
        .view => plan.view_words * alignment,
        .aggregate => blk: {
            var size: u32 = 0;
            for (value.fields) |field| {
                const field_size = try bytes(field);
                if (value.variant_tags.len != 0) {
                    size = @max(size, field_size);
                } else size = std.math.add(u32, size, field_size) catch return error.InvalidLayout;
            }
            if (value.variant_tags.len != 0) {
                if (value.variant_tags.len != value.fields.len) return error.InvalidLayout;
                break :blk std.math.add(u32, alignment, size) catch error.InvalidLayout;
            }
            break :blk @max(alignment, size);
        },
        .array, .callable => error.InvalidLayout,
    };
}
pub fn variantIndex(tags: []const u32, tag: u32) ?usize {
    for (tags, 0..) |candidate, index| if (candidate == tag) return index;
    return null;
}
