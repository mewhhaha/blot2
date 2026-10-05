//! Read-only type sources for principal imports. Frozen graphs contain no
//! substitutions, historical cursor views, mutable caches or caller evidence.
const T = @import("types.zig");
const P = @import("parameter_patterns.zig");

pub const Graph = struct {
    nodes: []T.Node,
    extra: []T.Id,
    rows: []T.Effects.Row,
    labels: []T.Effects.Label,
    operations: []T.Operation,
    row_variable_count: u32,
};

pub const Source = union(enum) {
    store: *const T.Store,
    frozen: *const Graph,

    pub fn head(self: Source, id: T.Id, at: T.Cursor) T.Id {
        return switch (self) {
            .store => |store| store.head(id, at),
            .frozen => id,
        };
    }
    pub fn node(self: Source, id: T.Id) T.Node {
        return switch (self) {
            .store => |store| store.node(id),
            .frozen => |graph| graph.nodes[id],
        };
    }
    pub fn list(self: Source, span: T.List) []const T.Id {
        return switch (self) {
            .store => |store| store.list(span),
            .frozen => |graph| graph.extra[span.start..][0..span.len],
        };
    }
    pub fn nominalArguments(self: Source, value: T.Node) []const T.Id {
        return switch (self) {
            .store => |store| store.nominalArguments(value),
            .frozen => |graph| graph.extra[value.c + 1 ..][0..graph.extra[value.c]],
        };
    }
    pub fn recordField(self: Source, value: T.Node, index: usize) T.Field {
        return switch (self) {
            .store => |store| store.recordField(value, index),
            .frozen => |graph| .{ .name = graph.extra[value.a + index * 2], .ty = graph.extra[value.a + index * 2 + 1] },
        };
    }
    pub fn operationCount(self: Source) usize {
        return switch (self) {
            .store => |store| store.operations.items.len,
            .frozen => |graph| graph.operations.len,
        };
    }
    pub fn operation(self: Source, id: T.Effects.Label) T.Operation {
        return switch (self) {
            .store => |store| store.operations.items[id],
            .frozen => |graph| graph.operations[id],
        };
    }
    pub fn row(self: Source, id: T.Effects.Id) T.Effects.Row {
        return switch (self) {
            .store => |store| store.effects.node(id),
            .frozen => |graph| graph.rows[id],
        };
    }
    pub fn rowLabels(self: Source, span: T.Effects.List) []const T.Effects.Label {
        return switch (self) {
            .store => |store| store.effects.list(span),
            .frozen => |graph| graph.labels[span.start..][0..span.len],
        };
    }
};

pub const PatternGraph = struct { nodes: []P.Node, extra: []u32 };
pub const Patterns = union(enum) {
    store: *const P.Store,
    frozen: *const PatternGraph,

    pub fn node(self: Patterns, id: P.Id) P.Node {
        return switch (self) {
            .store => |store| store.node(id),
            .frozen => |graph| graph.nodes[id],
        };
    }
    pub fn list(self: Patterns, span: P.List) []const P.Id {
        return switch (self) {
            .store => |store| store.list(span),
            .frozen => |graph| graph.extra[span.start..][0..span.len],
        };
    }
    pub fn field(self: Patterns, value: P.Node, index: usize) P.Field {
        return switch (self) {
            .store => |store| store.field(value, index),
            .frozen => |graph| .{ .name = graph.extra[value.a + index * 2], .pattern = graph.extra[value.a + index * 2 + 1] },
        };
    }
};
