//! Ephemeral access to complete method facts while a public relationship is
//! compared. No source borrow or capability recipe enters a returned slot map.
const std = @import("std");
const PI = @import("principal_interface.zig");
const T = @import("../check/types.zig");
const flow = @import("../check/capability_flow.zig");
const capabilities = @import("../check/capability_contracts.zig");
const symbols = @import("../parse/symbols.zig");
pub const Role = struct { implementation: T.NominalIdentity, member: u32 };
pub const Header = struct { flow: flow.Contract, parameters: flow.Parameters, recipe: ?capabilities.Recipe };
pub const Sources = struct {
    context: *anyopaque,
    before: *const fn (*anyopaque, Role, u32) ?Header,
    after: *const fn (*anyopaque, Role, u32) ?Header,
};

/// The before owner is complete frozen Core, the after owner is the current
/// successful Checked result. Both remain immutable throughout comparison.
pub fn Context(comptime Before: type, comptime After: type) type {
    return struct {
        before: *const Before,
        after: *const After,
        names: *const symbols.Pool,
        remaining: usize = 4096,
        const Self = @This();
        pub fn view(self: *Self) Sources {
            return .{ .context = self, .before = readBefore, .after = readAfter };
        }
        fn readBefore(context: *anyopaque, role: Role, binding: u32) ?Header {
            const self: *Self = @ptrCast(@alignCast(context));
            return self.read(self.before, role, binding, false);
        }
        fn readAfter(context: *anyopaque, role: Role, binding: u32) ?Header {
            const self: *Self = @ptrCast(@alignCast(context));
            return self.read(self.after, role, binding, true);
        }
        fn work(self: *Self) bool {
            if (self.remaining == 0) return false;
            self.remaining -= 1;
            return true;
        }
        fn read(self: *Self, owner: anytype, role: Role, binding: u32, comptime current: bool) ?Header {
            if (!self.work() or owner.unit != role.implementation.unit or binding == 0 or binding >= owner.bindings.len) return null;
            var found = false;
            for (owner.implementations) |implementation| {
                if (!self.work()) return null;
                if (implementation.private or !std.meta.eql(implementation.identity, role.implementation)) continue;
                for (owner.implementation_members[implementation.members.start..][0..implementation.members.len]) |member| {
                    if (!self.work()) return null;
                    if (member.kind != .value or member.name != role.member or member.target.unit != owner.unit or member.target.binding != binding) continue;
                    if (found) return null;
                    found = true;
                }
            }
            if (!found) return null;
            const source = owner.bindings[binding];
            if (!source.private or source.kind != .global) return null;
            if (comptime current) {
                if (!source.named_function or source.name == 0 or role.implementation.decl & T.opaque_name_bit == 0) return null;
                const name = self.names.get(source.name);
                const implementation_name = self.names.get(role.implementation.decl & ~T.opaque_name_bit);
                const member_name = self.names.get(role.member);
                if (name.len != implementation_name.len + 1 + member_name.len or !std.mem.eql(u8, name[0..implementation_name.len], implementation_name) or name[implementation_name.len] != '.' or !std.mem.eql(u8, name[implementation_name.len + 1 ..], member_name)) return null;
            }
            return .{ .flow = source.capability_flow, .parameters = source.capability_parameters, .recipe = owner.capability_contracts.header(binding, source.capability_parameters.arity()) };
        }
    };
}

fn sourceScenario(a: std.mem.Allocator) !void {
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    const implementation_name = try names.intern(a, "Chosen");
    const member_name = try names.intern(a, "first");
    const method_name = try names.intern(a, "Chosen.first");
    const other_name = try names.intern(a, "Other.first");
    const identity: T.NominalIdentity = .{ .unit = 1, .decl = T.opaque_name_bit | implementation_name };
    const Binding = struct { private: bool = true, kind: PI.Kind = .global, name: u32 = 0, named_function: bool = true, capability_flow: flow.Contract = .unknown, capability_parameters: flow.Parameters = .{} };
    const Owner = struct { unit: u32 = 1, bindings: []Binding, implementations: []PI.Implementation, implementation_members: []PI.ImplementationMember, capability_contracts: capabilities.Collection = .{} };
    var implementations = [_]PI.Implementation{.{ .identity = identity, .name = implementation_name, .contract = .{ .unit = 1, .decl = T.opaque_name_bit | member_name }, .members = .{ .start = 0, .len = 1 } }};
    var old_members = [_]PI.ImplementationMember{.{ .name = member_name, .kind = .value, .root = 1, .target = .{ .unit = 1, .binding = 1 } }};
    var new_members = old_members;
    new_members[0].target.binding = 2;
    var old_bindings = [_]Binding{ .{}, .{ .name = method_name } };
    var new_bindings = [_]Binding{ .{}, .{}, .{ .name = method_name } };
    const old: Owner = .{ .bindings = &old_bindings, .implementations = &implementations, .implementation_members = &old_members };
    const after: Owner = .{ .bindings = &new_bindings, .implementations = &implementations, .implementation_members = &new_members };
    var context: Context(Owner, Owner) = .{ .before = &old, .after = &after, .names = &names };
    const sources = context.view();
    const role: Role = .{ .implementation = identity, .member = member_name };
    try std.testing.expect(sources.before(sources.context, role, 1) != null);
    try std.testing.expect(sources.after(sources.context, role, 2) != null);
    // Equal method types or numeric slots cannot authorize another public
    // producer, a differently named private body or an unclaimed target.
    new_bindings[2].name = other_name;
    try std.testing.expect(sources.after(sources.context, role, 2) == null);
    new_bindings[2].name = method_name;
    try std.testing.expect(sources.after(sources.context, role, 1) == null);
    var other = role;
    other.implementation.unit = 2;
    try std.testing.expect(sources.before(sources.context, other, 1) == null);
    implementations[0].private = true;
    try std.testing.expect(sources.after(sources.context, role, 2) == null);
    implementations[0].private = false;
    context.remaining = 0;
    try std.testing.expect(sources.after(sources.context, role, 2) == null);
}

test "frontend relocation method source contexts retain original public roles private names and bounds through OOM" {
    try sourceScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sourceScenario, .{});
}
