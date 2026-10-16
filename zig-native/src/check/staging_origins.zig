//! Code provenance is sparse and never grants executable or type authority.
const std = @import("std");
const core = @import("core.zig");

pub const Source = struct { unit: u32, node: core.Id };
pub const Location = struct { unit: u32, span: core.Span };
pub const Record = struct { value: u32, generator: Source };
pub const Kind = enum { quote, generator, splice, invocation };
pub const Origin = struct { kind: Kind, location: Location };
pub const Trace = struct {
    entries: [8]Origin = @splat(.{ .kind = .quote, .location = .{ .unit = 0, .span = .{ .start = 0, .end = 0 } } }),
    len: u8 = 0,

    pub fn add(self: *Trace, kind: Kind, location: Location) error{Limit}!void {
        for (self.items()) |item| {
            if (item.kind == kind and std.meta.eql(item.location, location)) return;
        }
        if (self.len == self.entries.len) return error.Limit;
        self.entries[self.len] = .{ .kind = kind, .location = location };
        self.len += 1;
    }

    pub fn items(self: *const Trace) []const Origin {
        return self.entries[0..self.len];
    }
};

pub fn generator(records: []const Record, value: u32) ?Source {
    var start: usize = 0;
    var end = records.len;
    while (start < end) {
        const middle = start + (end - start) / 2;
        const record = records[middle];
        if (record.value == value) return record.generator;
        if (record.value < value) {
            start = middle + 1;
        } else {
            end = middle;
        }
    }
    return null;
}

pub fn module(units: []const core.Module, unit: u32) ?*const core.Module {
    for (units, 0..) |*owner, index| {
        var identity = owner.unit;
        if (identity == 0) identity = @intCast(index + 1);
        if (identity == unit) return owner;
    }
    return null;
}

pub fn sourceLocation(units: []const core.Module, source: Source) ?Location {
    const owner = module(units, source.unit) orelse return null;
    if (source.node == 0 or source.node >= owner.nodes.len or source.node >= owner.spans.len) return null;
    return .{ .unit = source.unit, .span = owner.span(source.node) };
}

pub fn code(trace: *Trace, units: []const core.Module, metadata: anytype, invocation: Source, selected_generator: ?Source, splice: bool) error{ Limit, InvalidOrigin }!void {
    const owner = module(units, metadata.unit) orelse return error.InvalidOrigin;
    var remaining: usize = 65_536;
    var quotation: ?Location = null;
    for (owner.nodes, 0..) |node, index| {
        if (remaining == 0) return error.Limit;
        remaining -= 1;
        if (node.tag != .staging or node.c != @backingInt(@import("typed_staging.zig").Op.quote)) continue;
        if (node.a != metadata.identity or node.ty != metadata.ty) continue;
        if (index >= owner.spans.len) return error.InvalidOrigin;
        quotation = .{ .unit = metadata.unit, .span = owner.span(@intCast(index)) };
        break;
    }
    try trace.add(.quote, quotation orelse return error.InvalidOrigin);
    if (selected_generator) |source| try trace.add(.generator, sourceLocation(units, source) orelse return error.InvalidOrigin);
    var kind: Kind = .invocation;
    if (splice) kind = .splice;
    try trace.add(kind, sourceLocation(units, invocation) orelse return error.InvalidOrigin);
}
