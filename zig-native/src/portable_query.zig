//! Versioned typed sections for portable query records. Each archive names one
//! complete claim; decoding never reinterprets another claim, schema or wire
//! version. Records hold validated artifact ordinals, never native handles,
//! allocator capacity, fingerprints, solver IDs or Session-local identities.
//! Refinement, canonical specialization, local principal templates, source
//! validation and executable fragments stay owner-local and are recomputed
//! after restart.
const std = @import("std");
const queries = @import("semantic_query_table.zig");
const types = @import("type_evidence.zig");

/// Interpretation of every portable section. Reflected schemas reject shape
/// changes; bump this when an unchanged shape changes meaning.
pub const version: u32 = 1;

pub const Claim = enum(u32) {
    /// Completed source-inferred principal types/rows with complete dynamic
    /// observations. Open residual templates are never portable.
    principal_complete_proof = 1,
    /// A ready optimizer result for one exact captured machine input.
    optimizer_output = 2,
    /// A completed selected specialization receipt, replayed only against
    /// its persisted previous-revision semantic owner and current source.
    selected_complete_proof = 3,
};

pub const Header = struct {
    version: u32,
    kind: queries.Kind,
    schema: u32,
    claim: Claim,
};

pub fn header(comptime claim: Claim) Header {
    return switch (claim) {
        .principal_complete_proof => .{ .version = version, .kind = .principal, .schema = 1, .claim = claim },
        .optimizer_output => .{ .version = version, .kind = .executable, .schema = 1, .claim = claim },
        .selected_complete_proof => .{ .version = version, .kind = .specialization, .schema = 1, .claim = claim },
    };
}

/// One archive section of complete records of exactly one claim.
pub fn Section(comptime claim_: Claim, comptime Record: type) type {
    return struct {
        pub const claim = claim_;
        header: Header,
        records: []Record,
        pub fn admitted(self: @This()) bool {
            return std.meta.eql(self.header, header(claim_));
        }
    };
}

fn validSpan(len: usize, start: usize, count: usize) bool {
    return start <= len and count <= len - start;
}
/// Structural evidence graph check shared by every portable owner. Every type
/// edge names an earlier node, as hash-consed publication does; rows and
/// operations stay in bounds. Nominal and operation identities may be builtin
/// (unit `maxInt(u32)`); importers validate them against the receiving units,
/// bound depth and work across the type/row spaces and reject unsupported
/// identities.
pub fn validEvidence(evidence: types.View) bool {
    const primitives = [_]types.Tag{ .absent, .unit, .boolean, .u32, .f32, .never };
    if (evidence.nodes.len < primitives.len) return false;
    for (evidence.nodes[0..primitives.len], primitives) |node, tag| if (!std.meta.eql(node, types.Node{ .tag = tag })) return false;
    const effects = evidence.effects;
    if (effects.operations.len == 0 or effects.rows.len == 0 or effects.rows[0].len != 0) return false;
    for (effects.operations[1..]) |operation| {
        if (!validSpan(effects.arguments.len, operation.arguments.start, operation.arguments.len)) return false;
        for (effects.arguments[operation.arguments.start..][0..operation.arguments.len]) |argument| if (argument == 0 or argument >= evidence.nodes.len) return false;
    }
    for (effects.rows[1..]) |row| {
        if (!validSpan(effects.labels.len, row.start, row.len)) return false;
        for (effects.labels[row.start..][0..row.len]) |label| if (label == 0 or label >= effects.operations.len) return false;
    }
    const rows = effects.rows.len;
    for (evidence.nodes[primitives.len..], primitives.len..) |node, id| {
        const child = struct {
            fn valid(value: u32, parent: usize) bool {
                return value != 0 and value < parent;
            }
        }.valid;
        switch (node.tag) {
            .absent, .unit, .boolean, .u32, .f32, .never => return false,
            .array, .list, .cursor, .resolver => if (!child(node.a, id) or node.b != 0 or node.c != 0) return false,
            .demand, .provider => if (!child(node.a, id) or node.b != 0 or node.c >= rows) return false,
            .function => if (!child(node.a, id) or !child(node.b, id) or node.c >= rows) return false,
            .state_provider => if (!child(node.a, id) or !child(node.b, id) or !child(node.c, id)) return false,
            .type_constructor => if (node.a == 0 or node.b == 0 or node.c != 0) return false,
            .product, .record => {
                const width: usize = if (node.tag == .record) 2 else 1;
                const count = std.math.mul(usize, node.b, width) catch return false;
                if (node.c != 0 or !validSpan(evidence.extra.len, node.a, count)) return false;
                for (evidence.extra[node.a..][0..count], 0..) |value, index| {
                    if (node.tag == .record and index % 2 == 0) {
                        if (value == 0) return false;
                    } else if (!child(value, id)) return false;
                }
            },
            .nominal => {
                const start = @as(usize, node.c) + 1;
                if (node.a == 0 or node.c >= evidence.extra.len or !validSpan(evidence.extra.len, start, evidence.extra[node.c])) return false;
                for (evidence.extra[start..][0..evidence.extra[node.c]]) |value| if (!child(value, id)) return false;
            },
        }
    }
    return true;
}

test "portable sections admit only their exact claim schema and version" {
    const Principal = Section(.principal_complete_proof, u32);
    var records = [_]u32{7};
    var section: Principal = .{ .header = header(.principal_complete_proof), .records = &records };
    try std.testing.expect(section.admitted());
    section.header.version += 1;
    try std.testing.expect(!section.admitted());
    section.header = header(.principal_complete_proof);
    section.header.schema += 1;
    try std.testing.expect(!section.admitted());
    section.header = header(.optimizer_output);
    try std.testing.expect(!section.admitted());
    section.header = header(.principal_complete_proof);
    section.header.kind = .refinement;
    try std.testing.expect(!section.admitted());
}
