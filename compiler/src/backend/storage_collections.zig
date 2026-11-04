//! Flat immutable sequences reuse the owned fixed-inline array representation.
//! Conversion is an explicit copy; no mutable array alias becomes a List.
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const storage = @import("../check/storage_types.zig");
pub fn element(m: *const core.Module, ty: T.Id) ?T.Id {
    const node = m.types.node(ty);
    return if (node.tag == .list) node.a else storage.arrayElement(&m.types, ty);
}
pub fn immutable(m: *const core.Module, ty: T.Id) bool {
    return m.types.node(ty).tag == .list;
}
