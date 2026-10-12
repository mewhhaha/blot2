//! A bounded, name-independent admission proof for local demand evaluation.
//! These structured bodies cannot store or return a pending demand or enter a
//! provider. Local reads may repeat across loops. Fully applied calls may forward
//! it through another admitted body, within the same shared node budget.
const core = @import("core.zig");
const Reason = @import("demand_lowering.zig").Reason;
pub const max_parameters = 16;
/// A lexical callback is an immutable closure or a bounded chain of local
/// aliases. Global/foreign values and computed callback choices stay ordinary.
pub fn localClosure(module: *const core.Module, id: core.Id) ?core.Id {
    var current = id;
    for (0..64) |_| {
        if (current == 0) return null;
        const node = module.node(current);
        if (node.tag == .closure) return current;
        if (node.tag != .reference) return null;
        const reference = module.reference(current);
        if (reference.unit != 0 and reference.unit != module.unit) return null;
        const binding = module.binding(reference.binding);
        if (binding.kind == .global or binding.kind == .external) return null;
        current = binding.initializer;
    }
    return null;
}
pub const Plan = struct {
    uses: [max_parameters]u8 = @splat(0),
    remaining: u8 = 96,
    bindings: [64]core.BindingId = @splat(0),
    binding_count: usize = 0,
    calls: [96]core.Id = @splat(0),
    call_count: usize = 0,
    multiplier: u8 = 1,
    local_callbacks: bool = false,
    failure: Reason = .unresolved_control,
    /// Borrowed only while the complete proof runs; prepared emission keeps
    /// the resulting use counts, never this source graph.
    units: []const core.Module = &.{},

    pub const Analysis = struct { plan: ?Plan, reason: Reason, visited: u8 };
    pub fn analyze(module: *const core.Module, body: *const core.Body) Analysis {
        return analyzeGraph(&.{}, module, body);
    }
    pub fn analyzeGraph(units: []const core.Module, module: *const core.Module, body: *const core.Body) Analysis {
        return analyzeBudget(units, module, body, 96);
    }
    pub fn initCalleeGraph(units: []const core.Module, module: *const core.Module, body: *const core.Body) ?Plan {
        return analyzeGraph(units, module, body).plan;
    }

    pub fn init(module: *const core.Module, body: *const core.Body) ?Plan {
        var has_demand = false;
        for (module.bodyParameters(body)) |item| {
            has_demand = has_demand or module.types.node(item.ty).tag == .demand;
        }
        if (!has_demand) return null;
        return initCallee(module, body);
    }
    pub fn initCallee(module: *const core.Module, body: *const core.Body) ?Plan {
        return initBudget(module, body, 96);
    }
    fn initBudget(module: *const core.Module, body: *const core.Body, remaining: u8) ?Plan {
        return analyzeBudget(&.{}, module, body, remaining).plan;
    }
    fn analyzeBudget(units: []const core.Module, module: *const core.Module, body: *const core.Body, remaining: u8) Analysis {
        if (!body.is_function) return .{ .plan = null, .reason = .unresolved_shape, .visited = 0 };
        if (body.parameters.len > max_parameters) return .{ .plan = null, .reason = .inlining_limit, .visited = 0 };
        var plan: Plan = .{ .remaining = remaining, .units = units };
        if (!plan.visit(module, body, body.root)) return .{ .plan = null, .reason = plan.failure, .visited = remaining - plan.remaining };
        return .{ .plan = plan, .reason = .proved_local, .visited = remaining - plan.remaining };
    }
    const Target = struct { module: *const core.Module, binding: core.BindingId };
    fn target(self: *Plan, module: *const core.Module, reference: core.BindingRef) ?Target {
        var ref = reference;
        var producer = module;
        for (0..256) |_| {
            if (ref.unit != 0 and ref.unit != producer.unit) {
                if (ref.unit > self.units.len) return null;
                producer = &self.units[ref.unit - 1];
                if (producer.unit != ref.unit) return null;
            }
            if (ref.binding == 0 or ref.binding >= producer.bindings.len) return null;
            const binding = producer.binding(ref.binding);
            if (binding.kind == .external) {
                ref = binding.target;
                continue;
            }
            if (producer.body(ref.binding)) |definition| {
                if (producer.types.node(binding.ty).tag == .function and definition.parameters.len == 0 and producer.node(definition.root).tag == .reference) {
                    ref = producer.reference(definition.root);
                    continue;
                }
            }
            return .{ .module = producer, .binding = ref.binding };
        }
        _ = self.reject(.inlining_limit);
        return null;
    }
    fn call(self: *Plan, module: *const core.Module, body: *const core.Body, id: core.Id) bool {
        const call_ = module.call(id);
        const resolved = self.target(module, call_.target) orelse {
            if (self.failure == .inlining_limit) return false;
            return self.reject(.unknown_callee);
        };
        const producer = resolved.module;
        const callee = producer.body(resolved.binding) orelse return self.reject(.unavailable_body);
        if (call_.arguments.len != callee.parameters.len) return false;
        const analysis = analyzeBudget(self.units, producer, callee, self.remaining);
        self.remaining -= analysis.visited;
        const child = analysis.plan orelse return self.reject(analysis.reason);
        self.local_callbacks = self.local_callbacks or child.local_callbacks;
        if (self.call_count == self.calls.len) return self.reject(.inlining_limit);
        self.calls[self.call_count] = id;
        self.call_count += 1;
        for (call_.arguments, producer.bodyParameters(callee), 0..) |argument, parameter_, index| {
            if (producer.types.node(parameter_.ty).tag != .demand) {
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
        var expression = id;
        for (0..64) |_| {
            if (module.node(expression).tag != .reference) return null;
            const reference = module.reference(expression);
            if (reference.unit != 0 and reference.unit != module.unit) return null;
            for (module.bodyParameters(body), 0..) |item, i| {
                if (item.binding != 0 and item.binding == reference.binding) return i;
            }
            expression = module.binding(reference.binding).initializer;
            if (expression == 0) return null;
        }
        return null;
    }
    fn addBinding(self: *Plan, module: *const core.Module, id: core.BindingId) bool {
        if (id == 0) return true;
        if (module.types.node(module.binding(id).ty).tag == .demand) return self.reject(.escaping_use);
        for (self.bindings[0..self.binding_count]) |known| if (known == id) return true;
        if (self.binding_count == self.bindings.len) return self.reject(.inlining_limit);
        self.bindings[self.binding_count] = id;
        self.binding_count += 1;
        return true;
    }
    fn pattern(self: *Plan, module: *const core.Module, body: *const core.Body, id: core.PatternId) bool {
        if (self.remaining == 0) return self.reject(.inlining_limit);
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
        if (id == 0) return true;
        if (self.remaining == 0) return self.reject(.inlining_limit);
        self.remaining -= 1;
        const node = module.node(id);
        return switch (node.tag) {
            .constant, .panic => true,
            .reference => blk: {
                if (localClosure(module, id) != null) break :blk self.reject(.escaping_use);
                if (parameter(module, body, id)) |index| {
                    if (module.types.node(module.bodyParameters(body)[index].ty).tag == .demand) break :blk self.reject(.escaping_use);
                    break :blk true;
                }
                const ref = module.reference(id);
                if (ref.unit == 0 or ref.unit == module.unit) {
                    for (self.bindings[0..self.binding_count]) |binding| if (ref.binding == binding) break :blk true;
                }
                if (self.target(module, ref)) |resolved| {
                    if (resolved.module.body(resolved.binding)) |captured| {
                        // Ordinary emission reads the current compile-time value
                        // and its dependencies. The proof does not evaluate it.
                        if (!captured.is_function and !captured.runtime and resolved.module.types.node(resolved.module.binding(resolved.binding).ty).tag != .demand) break :blk true;
                    }
                }
                break :blk false;
            },
            .project => self.visit(module, body, node.a),
            .construct => node.b == 0 or self.visit(module, body, node.b),
            .product, .record, .array => blk: {
                for (module.children(id)) |child| if (!self.visit(module, body, child)) break :blk false;
                break :blk true;
            },
            .array_op => blk: {
                // Generation invokes an arbitrary callback. Other primitive
                // collection operations only consume their completed inputs.
                if (module.arrayOperation(id) == .generate) break :blk false;
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
            .bind => blk: {
                if (localClosure(module, node.b) != null) {
                    self.local_callbacks = true;
                    break :blk self.addBinding(module, node.a);
                }
                if (module.types.node(module.typeOf(node.b)).tag == .demand) {
                    const index = parameter(module, body, node.b) orelse break :blk false;
                    break :blk module.types.node(module.bodyParameters(body)[index].ty).tag == .demand;
                }
                break :blk self.visit(module, body, node.b) and self.addBinding(module, node.a);
            },
            .block, .suite => blk: {
                for (module.children(id)) |child| if (!self.visit(module, body, child)) break :blk false;
                break :blk true;
            },
            .return_ => self.visit(module, body, node.a),
            .break_ => blk: {
                for (module.breakValues(id)) |value| if (!self.visit(module, body, value)) break :blk false;
                break :blk true;
            },
            .if_stmt => blk: {
                if (!self.visit(module, body, node.a) or !self.visit(module, body, node.b) or !self.visit(module, body, node.c)) break :blk false;
                for (module.branchMerges(id)) |merge| if (!self.addBinding(module, merge.result)) break :blk false;
                break :blk true;
            },
            .loop => blk: {
                const loop = module.loopInfo(id);
                if (!self.visit(module, body, loop.first) or !self.visit(module, body, loop.end)) break :blk false;
                if (loop.pattern != 0 and !self.pattern(module, body, loop.pattern)) break :blk false;
                for (module.loopCarries(id)) |carry| if (!self.addBinding(module, carry.iteration) or !self.addBinding(module, carry.outgoing)) break :blk false;
                const multiplier = self.multiplier;
                self.multiplier = 2;
                defer self.multiplier = multiplier;
                break :blk self.visit(module, body, loop.body);
            },
            .call => self.call(module, body, id),
            .apply => blk: {
                const closure_id = localClosure(module, node.a) orelse break :blk self.reject(.unknown_callee);
                const closure = module.closure(closure_id);
                if (module.types.node(closure.parameter.ty).tag == .demand) break :blk false;
                if (!self.visit(module, body, node.b)) break :blk false;
                self.local_callbacks = true;
                const saved = self.binding_count;
                defer self.binding_count = saved;
                if (!self.addBinding(module, closure.parameter.binding)) break :blk false;
                break :blk self.visit(module, body, closure.body);
            },
            .if_value => self.visit(module, body, node.a) and self.visit(module, body, node.b) and self.visit(module, body, node.c),
            // Associated operations may execute an arbitrary source body.
            .scalar => node.c == 0 and self.visit(module, body, node.a) and (node.b == 0 or self.visit(module, body, node.b)),
            .closure, .suspend_ => self.reject(.escaping_use),
            else => false,
        };
    }
    fn reject(self: *Plan, reason: Reason) bool {
        self.failure = reason;
        return false;
    }
};
