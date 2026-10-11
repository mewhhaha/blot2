//! Count with raw scalar locals and immutable borrowed handles. This interpreter
//! cannot publish values, mutate source frames, set diagnostics or spend fuel.
const core = @import("core.zig");
const scalar = @import("scalar_ops.zig");
const ragged = @import("ragged_builder.zig");
pub const Value = union(enum) { scalar: scalar.Value, borrowed: u32 };
const Failure = error{Declined};

pub fn Counter(comptime Adapter: type) type {
    return struct {
        adapter: Adapter,
        plan: ragged.Plan,
        remaining: usize = ragged.probe_limit,
        visits: usize = 0,
        limit: u32,
        count: u32 = 0,
        locals: [80]struct { binding: core.BindingId, value: Value } = undefined,
        local_count: usize = 0,

        pub fn run(self: *@This()) ?u32 {
            self.program(self.plan.root) catch return null;
            return self.count;
        }
        fn step(self: *@This()) Failure!void {
            if (self.remaining == 0) return error.Declined;
            self.remaining -= 1;
            self.visits += 1;
        }
        fn put(self: *@This(), binding: core.BindingId, value: Value) Failure!void {
            for (self.locals[0..self.local_count]) |*slot| if (slot.binding == binding) {
                slot.value = value;
                return;
            };
            if (self.local_count == self.locals.len) return error.Declined;
            self.locals[self.local_count] = .{ .binding = binding, .value = value };
            self.local_count += 1;
        }
        fn number(self: *@This(), value: Value) Failure!scalar.Value {
            if (value == .scalar) return value.scalar;
            return self.adapter.scalar(value.borrowed) orelse return error.Declined;
        }
        fn expression(self: *@This(), id: core.Id) Failure!Value {
            if (id == 0) return .{ .scalar = .{ .scalar = .unit, .bits = 0 } };
            try self.step();
            const m = self.adapter.module;
            const n = m.node(id);
            switch (n.tag) {
                .constant => return .{ .scalar = .{ .scalar = self.adapter.constantType(id) orelse return error.Declined, .bits = n.a } },
                .reference => {
                    const reference = m.reference(id);
                    if (reference.unit == 0 or reference.unit == m.unit) {
                        for (self.locals[0..self.local_count]) |slot| if (slot.binding == reference.binding) return slot.value;
                    }
                    return self.adapter.lookup(reference) orelse return error.Declined;
                },
                .scalar, .associated, .call => {
                    const operation = self.adapter.operation(id) orelse return error.Declined;
                    var first = n.a;
                    var second = n.b;
                    if (n.tag == .call) {
                        first = m.children(id)[0];
                        second = m.children(id)[1];
                    }
                    var left = try self.number(try self.expression(first));
                    var right = try self.number(try self.expression(second));
                    if (operation.reverse) {
                        const previous = left;
                        left = right;
                        right = previous;
                    }
                    return .{ .scalar = scalar.evaluate(operation.op, left, right) catch return error.Declined };
                },
                .logical => {
                    const left = try self.number(try self.expression(n.a));
                    if (left.scalar != .bool) return error.Declined;
                    if (n.op == .and_ and left.bits == 0) return .{ .scalar = left };
                    if (n.op == .or_ and left.bits != 0) return .{ .scalar = left };
                    return self.expression(n.b);
                },
                .if_value => {
                    const condition = try self.number(try self.expression(n.a));
                    if (condition.bits != 0) return self.expression(n.b);
                    return self.expression(n.c);
                },
                .array_op => {
                    const operand = try self.expression(m.children(id)[0]);
                    if (operand != .borrowed) return error.Declined;
                    const length = self.adapter.length(operand.borrowed) orelse return error.Declined;
                    return .{ .scalar = .{ .scalar = .u32, .bits = length } };
                },
                .project => {
                    const operand = try self.expression(n.a);
                    if (operand != .borrowed) return error.Declined;
                    return self.adapter.project(id, operand.borrowed) orelse return error.Declined;
                },
                else => return error.Declined,
            }
        }
        fn pattern(self: *@This(), id: core.PatternId, value: Value) Failure!void {
            if (id == 0) return;
            try self.step();
            const m = self.adapter.module;
            const p = m.pattern(id);
            switch (p.tag) {
                .wildcard => {},
                .bind => try self.put(p.a, value),
                .product => {
                    if (value != .borrowed) return error.Declined;
                    const children = self.adapter.children(value.borrowed);
                    const patterns = m.patternChildren(id);
                    if (children.len != patterns.len) return error.Declined;
                    for (patterns, children) |child, existing| try self.pattern(child, .{ .borrowed = existing });
                },
                else => return error.Declined,
            }
        }
        fn program(self: *@This(), id: core.Id) Failure!void {
            if (id == 0 or id == self.plan.storage.initial) return;
            try self.step();
            if (id == self.plan.storage.append) {
                if (self.count == self.limit) return error.Declined;
                self.count += 1;
                return;
            }
            if (id == self.plan.storage.conversion) return;
            const m = self.adapter.module;
            const n = m.node(id);
            switch (n.tag) {
                .block, .suite => for (m.children(id)) |child| try self.program(child),
                .bind => {
                    if (self.plan.alias(n.a)) return self.program(n.b);
                    if (n.a != self.plan.payload_binding) try self.put(n.a, try self.expression(n.b));
                },
                .return_ => {
                    if (m.node(n.a).tag == .reference) return;
                    try self.program(n.a);
                },
                .reference => {},
                .if_stmt => {
                    const condition = try self.number(try self.expression(n.a));
                    if (condition.bits != 0) return self.program(n.b);
                    return self.program(n.c);
                },
                .loop => {
                    const loop = m.loopInfo(id);
                    const source = try self.expression(loop.first);
                    var first: u32 = 0;
                    var end: u32 = 0;
                    if (loop.kind == .range) {
                        first = (try self.number(source)).bits;
                        end = (try self.number(try self.expression(loop.end))).bits;
                    } else {
                        if (source != .borrowed) return error.Declined;
                        end = self.adapter.length(source.borrowed) orelse return error.Declined;
                    }
                    const before = self.local_count;
                    defer self.local_count = before;
                    while (first < end) : (first += 1) {
                        try self.step();
                        var element: Value = .{ .scalar = .{ .scalar = .u32, .bits = first } };
                        if (loop.kind == .array) element = .{ .borrowed = self.adapter.children(source.borrowed)[first] };
                        try self.pattern(loop.pattern, element);
                        try self.program(loop.body);
                    }
                },
                else => return error.Declined,
            }
        }
    };
}
