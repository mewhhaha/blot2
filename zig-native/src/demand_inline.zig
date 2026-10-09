//! A bounded, name-independent admission proof for local demand evaluation.
//! These expression bodies cannot store or return a pending demand, enter a
//! provider, or revisit a demand in a loop. Fully applied local calls may forward
//! it through another admitted body, within the same shared node budget.
const core = @import("core.zig");
pub const max_parameters = 16;
pub const Plan = struct {
    uses: [max_parameters]u8 = @splat(0),
    remaining: u8 = 96,
    bindings: [64]core.BindingId = @splat(0),
    binding_count: usize = 0,
    calls: [96]core.Id = @splat(0),
    call_count: usize = 0,
    multiplier: u8 = 1,

    pub fn init(module: *const core.Module, body: *const core.Body) ?Plan {
        return initBudget(module, body, 96);
    }
    fn initBudget(module: *const core.Module, body: *const core.Body, remaining: u8) ?Plan {
        if (!body.is_function or body.parameters.len > max_parameters) return null;
        var has_demand = false;
        for (module.bodyParameters(body)) |item| {
            has_demand = has_demand or module.types.node(item.ty).tag == .demand;
        }
        if (!has_demand) return null;
        var plan: Plan = .{ .remaining = remaining };
        return if (plan.visit(module, body, body.root)) plan else null;
    }
    fn call(self: *Plan, module: *const core.Module, body: *const core.Body, id: core.Id) bool {
        const target = module.call(id);
        if (target.target.unit != 0 and target.target.unit != module.unit) return false;
        const callee = module.body(target.target.binding) orelse return false;
        if (target.arguments.len != callee.parameters.len) return false;
        const child = initBudget(module, callee, self.remaining) orelse return false;
        self.remaining = child.remaining;
        if (self.call_count == self.calls.len) return false;
        self.calls[self.call_count] = id;
        self.call_count += 1;
        for (target.arguments, module.bodyParameters(callee), 0..) |argument, parameter_, index| {
            if (module.types.node(parameter_.ty).tag != .demand) {
                if (!self.visit(module, body, argument)) return false;
                continue;
            }
            if (module.node(argument).tag != .suspend_) return false;
            if (child.uses[index] == 0) continue;
            const previous = self.multiplier;
            self.multiplier = @min(2, previous *| child.uses[index]);
            defer self.multiplier = previous;
            const expression = module.closures[module.node(argument).a].body;
            if (!self.visit(module, body, expression)) return false;
        }
        return true;
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
    fn pattern(self: *Plan, module: *const core.Module, body: *const core.Body, id: core.PatternId) bool {
        if (self.remaining == 0) return false;
        self.remaining -= 1;
        const p = module.pattern(id);
        return switch (p.tag) {
            .wildcard, .constant => true,
            .bind => blk: {
                // A pattern must not smuggle a pending demand into a field.
                if (module.types.node(p.ty).tag == .demand or self.binding_count == self.bindings.len) break :blk false;
                self.bindings[self.binding_count] = p.a;
                self.binding_count += 1;
                break :blk true;
            },
            .value => self.visit(module, body, p.a),
            .constructor => p.b == 0 or self.pattern(module, body, p.b),
            .record_payload => self.pattern(module, body, p.b),
            .product => blk: {
                for (module.extra[p.a..][0..p.b]) |child| if (!self.pattern(module, body, child)) break :blk false;
                break :blk true;
            },
            else => false,
        };
    }
    fn visit(self: *Plan, module: *const core.Module, body: *const core.Body, id: core.Id) bool {
        if (self.remaining == 0 or id == 0) return false;
        self.remaining -= 1;
        const node = module.node(id);
        return switch (node.tag) {
            .constant, .panic => true,
            .reference => if (parameter(module, body, id)) |index|
                module.types.node(module.bodyParameters(body)[index].ty).tag != .demand
            else blk: {
                const ref = module.reference(id);
                if (ref.unit != 0 and ref.unit != module.unit) break :blk false;
                for (self.bindings[0..self.binding_count]) |binding| if (ref.binding == binding) break :blk true;
                break :blk false;
            },
            .project => self.visit(module, body, node.a),
            .construct => node.b == 0 or self.visit(module, body, node.b),
            .product, .record => blk: {
                for (module.children(id)) |child| if (!self.visit(module, body, child)) break :blk false;
                break :blk true;
            },
            .match => blk: {
                if (module.matchInfo(id).statement) break :blk false;
                for (module.matchInputs(id)) |subject| if (!self.visit(module, body, subject)) break :blk false;
                for (module.matchArms(id)) |arm| {
                    const saved = self.binding_count;
                    defer self.binding_count = saved;
                    for (module.armRows(arm)) |row| for (module.rowPatterns(row)) |pattern_| {
                        if (!self.pattern(module, body, pattern_)) break :blk false;
                    };
                    if (arm.guard != 0 and !self.visit(module, body, arm.guard)) break :blk false;
                    if (!self.visit(module, body, arm.body)) break :blk false;
                }
                break :blk true;
            },
            .force => blk: {
                const index = parameter(module, body, node.a) orelse break :blk false;
                if (module.types.node(module.bodyParameters(body)[index].ty).tag != .demand) break :blk false;
                self.uses[index] = @min(2, self.uses[index] +| self.multiplier);
                break :blk true;
            },
            .call => self.call(module, body, id),
            .if_value => self.visit(module, body, node.a) and self.visit(module, body, node.b) and self.visit(module, body, node.c),
            // Associated operations may execute an arbitrary source body.
            .scalar => node.c == 0 and self.visit(module, body, node.a) and (node.b == 0 or self.visit(module, body, node.b)),
            else => false,
        };
    }
};
