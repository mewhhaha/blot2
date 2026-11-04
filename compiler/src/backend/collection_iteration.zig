//! Physical collection iteration requires the exact ordinary cursor producers.
//! Unknown methods and observable cursor progress keep their original protocol.
const std = @import("std");
const core = @import("../check/core.zig");
const Uses = @import("unit_index.zig").Uses;
pub const Candidate = struct { iter: core.Id, next: core.Id, receiver: core.Id, incoming: core.BindingId, iteration: core.BindingId, rest: core.BindingId, pattern: core.PatternId, constructor: u32 };
fn local(source: *const core.Module, id: core.Id, binding: core.BindingId) bool {
    if (id == 0 or source.node(id).tag != .reference) return false;
    const reference = source.reference(id);
    return (reference.unit == 0 or reference.unit == source.unit) and reference.binding == binding;
}
pub fn candidate(source: *const core.Module, uses: *const Uses, id: core.Id) ?Candidate {
    const loop = source.loopInfo(id);
    if (loop.kind != .forever) return null;
    const children = source.children(loop.body);
    if (children.len < 3) return null;
    const step = source.node(children[0]);
    const pattern = source.node(children[1]);
    const update = source.node(children[2]);
    if (step.tag != .bind or pattern.tag != .pattern_bind or update.tag != .bind or !local(source, pattern.b, step.a)) return null;
    const next = source.node(step.b);
    if (next.tag != .project) return null;
    const matched = source.pattern(pattern.a);
    if (matched.tag != .constructor or matched.b == 0) return null;
    const payload = source.pattern(matched.b);
    if (payload.tag != .product) return null;
    const items = source.patternChildren(matched.b);
    if (items.len != 2 or source.pattern(items[1]).tag != .bind) return null;
    const rest = source.pattern(items[1]).a;
    if (!local(source, update.b, rest)) return null;
    const fallback = source.children(pattern.c);
    if (fallback.len != 1 or source.node(fallback[0]).tag != .break_ or source.node(fallback[0]).a != id) return null;
    for (source.loopCarries(id)) |carry| {
        if (carry.backedge != update.a or !local(source, next.a, carry.iteration)) continue;
        const iter = source.binding(carry.incoming).initializer;
        if (iter == 0 or source.node(iter).tag != .project) return null;
        // The generated cursor is private. A manual loop that observes its
        // progress, retains its step/rest, or consumes its final cursor declines.
        const named = [_]core.BindingId{ carry.outgoing, step.a, rest, carry.iteration, carry.backedge };
        for (named, 0..) |held, position| {
            if (std.mem.findScalar(core.BindingId, named[0..position], held) != null) continue;
            for (uses.references.get(held)) |index| {
                const reference = source.reference(index);
                if (reference.unit != 0 and reference.unit != source.unit) continue;
                if (reference.binding == carry.outgoing) return null;
                if (reference.binding == step.a and index != pattern.b) return null;
                if (reference.binding == rest and index != update.b) return null;
                if (reference.binding != carry.iteration and reference.binding != carry.backedge) continue;
                if (index == next.a) continue;
                const broken = for (uses.values.get(index)) |exit| {
                    if (source.node(exit.exit).a == id) break true;
                } else false;
                if (!broken) return null;
            }
        }
        return .{ .iter = iter, .next = step.b, .receiver = next.a, .incoming = carry.incoming, .iteration = carry.iteration, .rest = rest, .pattern = items[0], .constructor = matched.a };
    }
    return null;
}
fn parameter(source: *const core.Module, body: *const core.Body, id: core.Id) bool {
    return local(source, id, source.bodyParameters(body)[0].binding);
}
pub fn cursorCreation(source: *const core.Module, target: core.BindingId) bool {
    const body = source.body(target) orelse return false;
    if (!body.is_function or body.parameters.len != 1) return false;
    const root = source.node(body.root);
    return root.tag == .array_op and source.arrayOperation(body.root) == .cursor and source.children(body.root).len == 1 and parameter(source, body, source.children(body.root)[0]);
}
pub fn cursorNext(source: *const core.Module, target: core.BindingId, consumer: *const core.Module, constructor: u32) bool {
    const body = source.body(target) orelse return false;
    if (!body.is_function or body.parameters.len != 1) return false;
    const root = source.node(body.root);
    if (root.tag != .if_value) return false;
    const predicate = source.node(root.a);
    if (predicate.tag != .array_op or source.arrayOperation(root.a) != .cursor_has or source.children(root.a).len != 1 or !parameter(source, body, source.children(root.a)[0])) return false;
    const some = source.node(root.b);
    const empty = source.node(root.c);
    if (some.tag != .construct or empty.tag != .construct or empty.b != 0 or some.b == 0) return false;
    const actual = source.constructor(some.a);
    const wanted = consumer.constructor(constructor);
    const absent = source.constructor(empty.a);
    if (absent.tag == actual.tag or !std.meta.eql(source.nominal(absent.nominal).identity, source.nominal(actual.nominal).identity)) return false;
    if (actual.tag != wanted.tag or !std.meta.eql(source.nominal(actual.nominal).identity, consumer.nominal(wanted.nominal).identity)) return false;
    if (source.node(some.b).tag != .product) return false;
    const values = source.children(some.b);
    if (values.len != 2) return false;
    for (values, [_]core.ArrayOp{ .cursor_value, .cursor_advance }) |value, operation| {
        if (source.node(value).tag != .array_op or source.arrayOperation(value) != operation or source.children(value).len != 1 or !parameter(source, body, source.children(value)[0])) return false;
    }
    return true;
}

pub const StepSink = struct { pattern: core.Id, constructor: u32 };
/// The successful payload is observable only through this immediately adjacent
/// constructor pattern. Retained steps and closure/call escapes keep the ABI.
pub fn stepSink(source: *const core.Module, uses: *const Uses, binding: core.Id) ?StepSink {
    const node = source.node(binding);
    if (node.tag == .pattern_bind) return patternSink(source, binding);
    if (node.tag != .bind or node.a == 0) return null;
    // The statement must appear in exactly one block or suite, not last.
    const parent = uses.parentOf(binding);
    if (parent.count != 1) return null;
    const siblings = source.children(parent.node);
    if (parent.position + 1 == siblings.len) return null;
    const pattern_id = siblings[parent.position + 1];
    const pattern = source.node(pattern_id);
    if (pattern.tag != .pattern_bind or !local(source, pattern.b, node.a)) return null;
    const sink = patternSink(source, pattern_id) orelse return null;
    for (uses.references.get(node.a)) |id| {
        if (local(source, id, node.a) and id != pattern.b) return null;
    }
    if (uses.flagsOf(node.a).captured) return null;
    return sink;
}
fn patternSink(source: *const core.Module, id: core.Id) ?StepSink {
    const node = source.node(id);
    const matched = source.pattern(node.a);
    if (matched.tag != .constructor or matched.b == 0 or source.pattern(matched.b).tag != .product) return null;
    const fields = source.patternChildren(matched.b);
    if (fields.len != 2) return null;
    for (fields) |field| {
        const tag = source.pattern(field).tag;
        if (tag != .bind and tag != .wildcard) return null;
    }
    return .{ .pattern = id, .constructor = matched.a };
}
