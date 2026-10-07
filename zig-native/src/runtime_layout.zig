//! Guest heap representation. All fields are Wasm32 words; compiler hosts may
//! have a different pointer size. Dynamic value slots need their checked type
//! before they can be classified as references.
const std = @import("std");
pub const Role = enum { scalar, reference, value, table_function, owner_token };
pub const Field = struct { offset: u32, role: Role };

pub const Closure = extern struct {
    function: u32,
    environment: u32,
    pub const roles = [_]Role{ .table_function, .reference };
};
pub const DemandStatus = enum(u32) { pending, evaluating, ready };
pub const Demand = extern struct {
    function: u32,
    environment: u32,
    status: DemandStatus,
    cached: u32,
    pub const roles = [_]Role{ .table_function, .reference, .scalar, .value };
};
pub const Pair = extern struct {
    first: u32,
    second: u32,
    pub const roles = [_]Role{ .value, .value };
};
pub const Cursor = extern struct {
    collection: u32,
    index: u32,
    // Each immutable position owns its leaf cache. Forked traversals must not
    // evict one another through the collection descriptor's lookup cache.
    leaf: u32 = 0,
    base: u32 = 0,
    pub const roles = [_]Role{ .reference, .scalar, .reference, .scalar };
};
pub const ProviderKind = enum(u32) { callback, state_read, state_write, request };
pub const ProviderFrame = extern struct {
    operation: u32,
    target: u32,
    outer: u32,
    kind: ProviderKind,
    pub const roles = [_]Role{ .scalar, .reference, .reference, .scalar };
};
pub const StateCell = extern struct {
    value: u32,
    pub const roles = [_]Role{.value};
};
pub const Provider = extern struct {
    operation: u32,
    implementation: u32,
    pub const roles = [_]Role{ .scalar, .reference };
};
pub const StateProvider = extern struct {
    read: u32,
    write: u32,
    initial: u32,
    pub const roles = [_]Role{ .scalar, .scalar, .value };
};
pub const RequestStatus = enum(u32) { running, exited, broken };
pub const RequestCell = extern struct {
    status: RequestStatus,
    exit: u32,
    state: u32,
    pub const roles = [_]Role{ .scalar, .value, .value };
};
pub const RequestFrame = extern struct {
    operation: u32,
    target: u32,
    outer: u32,
    kind: ProviderKind,
    cell: u32,
    runner_outer: u32,
    pub const roles = [_]Role{ .scalar, .reference, .reference, .scalar, .reference, .reference };
};
pub const Decision = extern struct {
    kind: u32,
    payload: u32,
    state: u32,
    pub const roles = [_]Role{ .scalar, .value, .value };
};
pub const Array = extern struct {
    length: u32,
    pub const roles = [_]Role{.scalar};
};
pub const ListDescriptor = extern struct {
    length: u32,
    root: u32,
    cached_leaf: u32,
    cached_base: u32,
    scalar_elements: u32,
    immutable: u32,
    pub const roles = [_]Role{ .scalar, .reference, .reference, .scalar, .scalar, .scalar };
};
pub const ListNode = extern struct {
    owner_token: u32,
    height: u32,
    length: u32,
    capacity: u32,
    pub const roles = [_]Role{ .owner_token, .scalar, .scalar, .scalar };
};
pub const ListBranch = extern struct {
    owner_token: u32,
    height: u32,
    length: u32,
    capacity: u32,
    left: u32,
    right: u32,
    pub const roles = [_]Role{ .owner_token, .scalar, .scalar, .scalar, .reference, .reference };
};
pub const ArenaHeader = extern struct {
    block_size: u32,
    requested: u32,
    flags: u32,
    next: u32,
    pub const roles = [_]Role{ .scalar, .scalar, .scalar, .reference };
};

pub fn offset(comptime T: type, comptime name: []const u8) u32 {
    return @intCast(@offsetOf(T, name));
}
pub fn fields(comptime T: type) [T.roles.len]Field {
    const names = @typeInfo(T).@"struct".field_names;
    if (names.len != T.roles.len or @sizeOf(T) != names.len * 4)
        @compileError("Runtime layouts require one role for each 32-bit word");
    var result: [names.len]Field = undefined;
    inline for (names, 0..) |name, i| result[i] = .{ .offset = offset(T, name), .role = T.roles[i] };
    return result;
}

comptime {
    for (.{ Closure, Demand, Pair, Cursor, ProviderFrame, StateCell, Provider, StateProvider, RequestCell, RequestFrame, Decision, Array, ListDescriptor, ListNode, ListBranch, ArenaHeader }) |T| {
        _ = fields(T);
    }
    for (@typeInfo(ListNode).@"struct".field_names) |name|
        std.debug.assert(offset(ListNode, name) == offset(ListBranch, name));
    for (@typeInfo(Closure).@"struct".field_names) |name|
        std.debug.assert(offset(Closure, name) == offset(Demand, name));
    for (@typeInfo(ProviderFrame).@"struct".field_names) |name|
        std.debug.assert(offset(ProviderFrame, name) == offset(RequestFrame, name));
}
