//! Module-owned use facts for eliding only unobserved aggregate storage.
const std = @import("std");
const core = @import("core.zig");
pub const Proof = struct {
    unused: []bool = &.{},
    pub fn deinit(self: *Proof, allocator: std.mem.Allocator) void {
        allocator.free(self.unused);
        self.* = .{};
    }
    pub fn admits(self: *const Proof, binding: core.BindingId) bool {
        return binding < self.unused.len and self.unused[binding];
    }
    pub fn init(allocator: std.mem.Allocator, module: *const core.Module, unit_id: u32) !Proof {
        var candidate = false;
        for (module.nodes) |node| if (node.tag == .bind) {
            const value = module.node(node.b);
            if (value.tag == .product or value.tag == .record) {
                candidate = true;
                break;
            }
        };
        if (!candidate) return .{};
        var proof: Proof = .{ .unused = try allocator.alloc(bool, module.bindings.len) };
        @memset(proof.unused, true);
        // Scan owned tables, not only ordinary expression children. Value
        // patterns hold references, and callbacks consume capture bindings.
        for (module.references) |reference| if (reference.unit == 0 or reference.unit == unit_id) proof.mark(reference.binding);
        for (module.closures) |closure| for (module.extra[closure.captures.start..][0..closure.captures.len]) |binding| proof.mark(binding);
        for (module.merges) |merge| {
            proof.mark(merge.then_binding);
            proof.mark(merge.else_binding);
            proof.mark(merge.result);
        }
        for (module.loop_carries) |carry| {
            proof.mark(carry.incoming);
            proof.mark(carry.iteration);
            proof.mark(carry.backedge);
            proof.mark(carry.outgoing);
        }
        for (module.request_loops) |loop| for (module.extra[loop.completion_state_bindings.start..][0..loop.completion_state_bindings.len]) |binding| proof.mark(binding);
        return proof;
    }
    fn mark(self: *Proof, binding: core.BindingId) void {
        if (binding < self.unused.len) self.unused[binding] = false;
    }
};
