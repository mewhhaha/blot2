//! Finite closed data initializers may stay in the ordinary evaluator. This
//! proof never chooses a physical representation for a generalized field.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
pub const Proof = struct {
    dependencies: [16]core.BindingRef = undefined,
    len: usize = 0,
};
const Scan = struct {
    units: []const core.Module,
    proof: Proof = .{},
    remaining: usize = 512,
    fn unit(self: *Scan, id: u32) ?*const core.Module {
        for (self.units, 0..) |*module, index| {
            const actual = if (module.unit == 0) @as(u32, @intCast(index + 1)) else module.unit;
            if (actual == id) return module;
        }
        return null;
    }
    fn step(self: *Scan, depth: usize) bool {
        if (depth >= 32 or self.remaining == 0) return false;
        self.remaining -= 1;
        return true;
    }
    fn row(m: *const core.Module, id: T.Effects.Id, certificates: T.List) bool {
        const value_ = m.types.row(id);
        if (value_.labels.len != 0) return false;
        if (value_.tail == .closed) return true;
        if (value_.tail != .variable) return false;
        return std.mem.findScalar(u32, m.types.list(certificates), value_.tail.variable) != null;
    }
    fn shape(self: *Scan, m: *const core.Module, id: T.Id, certificates: T.List, pure: bool, depth: usize) bool {
        if (!self.step(depth)) return false;
        const n = m.types.node(id);
        switch (n.tag) {
            .unit, .boolean, .u32, .f32, .variable => return true,
            .function => {
                if (pure and !row(m, n.c, certificates)) return false;
                const input = m.types.node(n.a);
                if (input.tag == .scoped) {
                    // A generalized callable's receiver is supplied when called;
                    // constructing its value stores no active receiver handle.
                    if (input.b != 0 or input.c == 0 or m.types.node(input.c).tag != .variable or !self.shape(m, input.a, certificates, false, depth + 1)) return false;
                } else if (!self.shape(m, n.a, certificates, pure, depth + 1)) return false;
                return self.shape(m, n.b, certificates, pure, depth + 1);
            },
            .array, .list => return self.shape(m, n.a, certificates, pure, depth + 1),
            .product => for (m.types.list(.{ .start = n.a, .len = n.b })) |child| {
                if (!self.shape(m, child, certificates, pure, depth + 1)) return false;
            },
            .record => for (0..n.b) |index| {
                if (!self.shape(m, m.types.recordField(n, index).ty, certificates, pure, depth + 1)) return false;
            },
            .nominal => {
                if (n.a == std.math.maxInt(u32)) return false;
                for (m.types.nominalArguments(n)) |child| if (!self.shape(m, child, certificates, pure, depth + 1)) return false;
            },
            else => return false,
        }
        return true;
    }
    fn dependency(self: *Scan, target: core.BindingRef) bool {
        for (self.proof.dependencies[0..self.proof.len]) |prior| if (std.meta.eql(prior, target)) return true;
        if (self.proof.len == self.proof.dependencies.len) return false;
        self.proof.dependencies[self.proof.len] = target;
        self.proof.len += 1;
        return true;
    }
    fn value(self: *Scan, owner: u32, id: core.Id, parameters: []const core.Parameter, depth: usize) bool {
        if (!self.step(depth) or id == 0) return false;
        const m = self.unit(owner) orelse return false;
        const n = m.node(id);
        // Phantom arguments retain semantic authority even without a
        // physical payload. Check every value type recursively; purity stays
        // owned by each exact closure or selected wrapper below.
        // A return has the control type Never; its payload is checked below.
        if (n.tag != .return_ or m.types.node(n.ty).tag != .never) {
            if (!self.shape(m, n.ty, .{}, false, depth + 1)) return false;
        }
        switch (n.tag) {
            .constant => return self.shape(m, n.ty, .{}, true, depth + 1),
            .reference => {
                const reference = m.reference(id);
                if (reference.unit == 0 or reference.unit == owner) {
                    for (parameters) |parameter| if (parameter.binding != 0 and parameter.binding == reference.binding) return true;
                }
                var target = reference;
                if (target.unit == 0) target.unit = owner;
                for (0..16) |_| {
                    const producer = self.unit(target.unit) orelse return false;
                    const binding = producer.binding(target.binding);
                    if (binding.kind == .external) {
                        target = binding.target;
                        continue;
                    }
                    const body = producer.body(target.binding) orelse return false;
                    // Constructing a checked named callable does not run its
                    // actions. Its input relationship is independently checked
                    // against this exact body before code generation.
                    if (!body.is_function or body.runtime or binding.capability_flow != .input_shape or binding.scheme.generative.len != 0 or !binding.capability_parameters.valid()) return false;
                    return self.dependency(target);
                }
                return false;
            },
            .product, .record, .array => {
                for (m.children(id)) |child| if (!self.value(owner, child, parameters, depth + 1)) return false;
                return true;
            },
            .construct => {
                const constructor = m.constructors[n.a];
                if (m.nominals[constructor.nominal].is_opaque) return false;
                if (n.b == 0) return true;
                return self.value(owner, n.b, parameters, depth + 1);
            },
            .closure => {
                const closure = m.closure(id);
                if (closure.captures.len != 0 or closure.qualifier != 0) return false;
                if (!self.shape(m, closure.function_type, closure.closed_rows, true, depth + 1)) return false;
                return self.value(owner, closure.body, &.{closure.parameter}, depth + 1);
            },
            .return_ => return self.value(owner, n.a, parameters, depth + 1),
            .call => {
                var target = m.call(id).target;
                if (target.unit == 0) target.unit = owner;
                for (0..16) |_| {
                    const producer = self.unit(target.unit) orelse return false;
                    const binding = producer.binding(target.binding);
                    if (binding.kind == .external) {
                        target = binding.target;
                        continue;
                    }
                    const body = producer.body(target.binding) orelse return false;
                    if (!body.is_function or body.runtime or body.scheme.obligations.len != 0) return false;
                    const arguments = m.children(id);
                    if (arguments.len != body.parameters.len) return false;
                    if (!self.shape(producer, binding.ty, body.closed_rows, false, depth + 1)) return false;
                    var arrow = binding.ty;
                    for (0..body.parameters.len) |_| {
                        if (!self.step(depth + 1)) return false;
                        const signature = producer.types.node(arrow);
                        if (signature.tag != .function or !row(producer, signature.c, body.closed_rows)) return false;
                        arrow = signature.b;
                    }
                    for (arguments) |argument| if (!self.value(owner, argument, parameters, depth + 1)) return false;
                    if (!self.dependency(target)) return false;
                    return self.value(target.unit, body.root, producer.bodyParameters(body), depth + 1);
                }
                return false;
            },
            // Arithmetic, dispatch, handlers, mutable/usage data, suspensions
            // and unowned references do not receive a totality certificate.
            else => return false,
        }
    }
};
pub fn analyze(units: []const core.Module, owner: u32, initializer: core.Id) ?Proof {
    var scan: Scan = .{ .units = units };
    if (!scan.value(owner, initializer, &.{}, 0)) return null;
    return scan.proof;
}
/// Whether a type has a representation-free value graph: scalars, variables,
/// functions and transparent data, never authority-bearing types.
pub fn dataShape(units: []const core.Module, owner: u32, ty: T.Id) bool {
    var scan: Scan = .{ .units = units };
    const module = scan.unit(owner) orelse return false;
    return scan.shape(module, ty, .{}, false, 0);
}
