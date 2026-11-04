//! Candidate-owned wire and current-source admission. No symbols or principal
//! interfaces are published until every producer and provenance key agrees.
const std = @import("std");
const project = @import("project.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const closure = @import("dependency_closure.zig");

pub const Stats = struct { decode_us: i64 = 0, validation_us: i64 = 0, source_us: i64 = 0, source_bytes: usize = 0 };
fn elapsed(io: std.Io, at: std.Io.Timestamp) i64 {
    return at.durationTo(std.Io.Clock.awake.now(io)).toMicroseconds();
}
fn sameKey(left: format.Key, right: format.Key) bool {
    inline for (@typeInfo(format.Key).@"struct".field_names) |name| if (!std.mem.eql(u8, &@field(left, name), &@field(right, name))) return false;
    return true;
}

/// Header source/edge digests are initially untrusted discovery facts. The
/// decoder proves wire integrity against the actual compiler/settings; current
/// raw producer reads and payloadKey independently establish source provenance.
/// Nothing here parses a producer, creates a Store, or publishes a symbol Pool.
pub fn load(a: std.mem.Allocator, io: std.Io, bytes: []const u8, compiler: [32]u8, settings: [32]u8, options: project.Options, stats: *Stats) !D.FrozenDependency {
    var expected = try format.inspectKey(bytes);
    expected.compiler = compiler;
    expected.settings = settings;
    var at = std.Io.Clock.awake.now(io);
    var candidate = try format.decode(D.FrozenDependency, a, bytes, expected);
    errdefer format.deinit(a, &candidate);
    stats.decode_us = elapsed(io, at);
    if (candidate.modules.len >= options.max_files) return error.FileLimit;
    at = std.Io.Clock.awake.now(io);
    try closure.validate(a, &candidate);
    stats.validation_us = elapsed(io, at);
    at = std.Io.Clock.awake.now(io);
    var found_prelude = false;
    for (candidate.modules) |*module| {
        const canonical = try std.Io.Dir.cwd().realPathFileAlloc(io, module.identity.normalized_path, a);
        defer a.free(canonical);
        const source = try std.Io.Dir.cwd().readFileAlloc(io, canonical, a, .limited(options.max_source_bytes));
        defer a.free(source);
        try closure.validateProducer(module, canonical, source);
        if (source.len > options.max_total_source_bytes -| stats.source_bytes) return error.SourceLimit;
        stats.source_bytes += source.len;
        if (module.identity.prelude) {
            const prelude = options.prelude_path orelse return error.StaleArtifact;
            if (!std.mem.eql(u8, canonical, prelude)) return error.StaleArtifact;
            found_prelude = true;
        }
        // Producer bytes do not prove the filesystem resolution that selected
        // their dependencies. Check every request before caller publication.
        for (module.source_imports) |request| {
            const resolved = try project.resolveImportPath(a, canonical, request.path, options);
            defer a.free(resolved);
            const target_path = try std.Io.Dir.cwd().realPathFileAlloc(io, resolved, a);
            defer a.free(target_path);
            const expected_target = candidate.modules[request.target - 1].identity.normalized_path;
            if (!std.mem.eql(u8, target_path, expected_target)) return error.StaleArtifact;
        }
    }
    if (found_prelude != (options.prelude_path != null)) return error.StaleArtifact;
    if (!sameKey(expected, closure.payloadKey(compiler, settings, &candidate))) return error.StaleArtifact;
    stats.source_us = elapsed(io, at);
    return candidate;
}
