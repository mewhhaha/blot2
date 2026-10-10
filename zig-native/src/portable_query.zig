//! Versioned typed sections for portable query records. Each archive names one
//! complete claim; decoding never reinterprets another claim, schema or wire
//! version. Records hold validated artifact ordinals, never native handles,
//! allocator capacity, fingerprints, solver IDs or Session-local identities.
//! Refinement, selected/canonical specialization, local principal templates,
//! source validation and executable fragments stay owner-local and are
//! recomputed after restart until a later task represents their graphs.
const std = @import("std");
const queries = @import("semantic_query_table.zig");

/// Interpretation of every portable section. Reflected schemas reject shape
/// changes; bump this when an unchanged shape changes meaning.
pub const version: u32 = 1;

pub const Claim = enum(u32) {
    /// Completed source-inferred principal types/rows with complete dynamic
    /// observations. Open residual templates are never portable.
    principal_complete_proof = 1,
    /// A ready optimizer result for one exact captured machine input.
    optimizer_output = 2,
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
