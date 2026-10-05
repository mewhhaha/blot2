//! A bounded, name-independent admission proof for local demand evaluation.
//! These expression bodies cannot store, forward or return a pending demand,
//! enter a provider, or revisit a demand in a loop. Everything else falls back
//! to the ordinary shared runtime cell.
const core = @import("core.zig");
pub const max_parameters = 16;
pub const Plan = struct {
    uses: [max_parameters]u8 = @splat(0),
    remaining: u8 = 48,

    pub fn init(module: *const core.Module, body: *const core.Body) ?Plan {
        if (!body.is_function or body.parameters.len > max_parameters) return null;
        var has_demand = false;
        for (module.bodyParameters(body)) |item| {
            has_demand = has_demand or module.types.node(item.ty).tag == .demand;
        }
        if (!has_demand) return null;
        var plan: Plan = .{};
        return if (plan.visit(module, body, body.root)) plan else null;
    }
    fn parameter(module: *const core.Module, body: *const core.Body, id: core.Id) ?usize {
        if (module.node(id).tag != .reference) return null;
        const reference = module.reference(id);
        if (reference.unit != 0 and reference.unit != module.unit) return null;
        for (module.bodyParameters(body), 0..) |item, i| {
            if (item.binding != 0 and item.binding == reference.binding) return i;
        }
        return null;
    }
    fn visit(self: *Plan, module: *const core.Module, body: *const core.Body, id: core.Id) bool {
        if (self.remaining == 0 or id == 0) return false;
        self.remaining -= 1;
        const node = module.node(id);
        return switch (node.tag) {
            .constant, .panic => true,
            .reference => if (parameter(module, body, id)) |index|
                module.types.node(module.bodyParameters(body)[index].ty).tag != .demand
            else
                false,
            .force => blk: {
                const index = parameter(module, body, node.a) orelse break :blk false;
                if (module.types.node(module.bodyParameters(body)[index].ty).tag != .demand) break :blk false;
                self.uses[index] += 1;
                break :blk true;
            },
            .if_value => self.visit(module, body, node.a) and self.visit(module, body, node.b) and self.visit(module, body, node.c),
            // Associated operations may execute an arbitrary source body.
            .scalar => node.c == 0 and self.visit(module, body, node.a) and (node.b == 0 or self.visit(module, body, node.b)),
            else => false,
        };
    }
};
