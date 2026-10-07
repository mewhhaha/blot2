//! Project dependency artifact creation and strict cache admission for the CLI.
//! Source, settings, catalogs and Core are validated before publication.
const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const closure = @import("dependency_closure.zig");
const loader = @import("dependency_project_loader.zig");
const partial = @import("partial_dependency.zig");
const memory = @import("memory.zig");
const Io = std.Io;
const purity = @import("purity_diagnostics.zig");
const diagnostic = @import("dependency_consumer.zig");
const syntax = @import("syntax_diagnostics.zig");
pub const Metrics = struct {
    frontend_us: i64 = 0,
    freeze_us: i64 = 0,
    frontend_teardown_us: i64 = 0,
    encode_us: i64 = 0,
    decode_us: i64 = 0,
    validation_us: i64 = 0,
    source_us: i64 = 0,
    relink_us: i64 = 0,
    compile_us: i64 = 0,
    source_bytes: usize = 0,
    artifact_bytes: usize = 0,
    wasm_bytes: usize = 0,
    modules: usize = 0,
    cached_modules: usize = 0,
    fresh_modules: usize = 0,
    dictionary: usize = 0,
    syntax_nodes: usize = 0,
    body_elaborations: usize = 0,
    body_lowerings: usize = 0,
    interface_bytes: usize = 0,
    core_bytes: usize = 0,
    interface_bindings: usize = 0,
    interface_global_bindings: usize = 0,
};
fn elapsed(io: Io, start: Io.Timestamp) i64 {
    return start.durationTo(Io.Clock.awake.now(io)).toMicroseconds();
}
fn ownedBytes(value: anytype) usize {
    return switch (@typeInfo(@TypeOf(value))) {
        .pointer => |p| blk: {
            if (p.size != .slice) @compileError("Only slices in frozen payloads");
            var bytes = value.len * @sizeOf(p.child);
            for (value) |item| bytes += ownedBytes(item);
            break :blk bytes;
        },
        .@"struct" => |s| blk: {
            var bytes: usize = 0;
            inline for (s.field_names) |name| bytes += ownedBytes(@field(value, name));
            break :blk bytes;
        },
        .optional => if (value) |item| ownedBytes(item) else 0,
        .array => blk: {
            var bytes: usize = 0;
            for (value) |item| bytes += ownedBytes(item);
            break :blk bytes;
        },
        .@"union" => switch (value) {
            inline else => |item| ownedBytes(item),
        },
        else => 0,
    };
}
fn payloadMetrics(value: *const D.FrozenDependency, metrics: *Metrics) void {
    metrics.modules = value.modules.len;
    metrics.dictionary = value.symbols.len;
    for (value.modules) |module| {
        metrics.interface_bytes += ownedBytes(module.interface);
        metrics.core_bytes += ownedBytes(module.core);
        metrics.interface_bindings += module.interface.bindings.len;
        for (module.interface.bindings) |binding| if (binding.kind == .global or binding.kind == .external) {
            metrics.interface_global_bindings += 1;
        };
    }
}
fn emit(writer: *Io.Writer, value: anytype) !void {
    try std.json.Stringify.value(value, .{}, writer);
    try writer.writeByte('\n');
}
fn frontend(a: std.mem.Allocator, writer: *Io.Writer, filename: []const u8, unit: u32, stage: []const u8, source: []const u8, publication: syntax.Publication, details: anytype) !void {
    var issue = try diagnostic.publishedDiagnostic(a, unit, stage, source, publication, details);
    defer issue.deinit(a);
    try issue.write(writer, filename);
}
fn word(hash: *std.crypto.hash.Blake3, value: usize) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hash.update(&bytes);
}
fn text(hash: *std.crypto.hash.Blake3, value: []const u8) void {
    word(hash, value.len);
    hash.update(value);
}
pub fn settings(options: project.Options) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    text(&hash, "blotc-dependencies-v1:project:default-check-and-backend:generic-core:no-evaluated-values:ordered-dictionary");
    text(&hash, options.prelude_path orelse "");
    text(&hash, options.std_root orelse "");
    word(&hash, options.aliases.len);
    for (options.aliases) |alias| {
        text(&hash, alias.prefix);
        text(&hash, alias.root);
    }
    word(&hash, options.max_source_bytes);
    word(&hash, options.max_total_source_bytes);
    word(&hash, options.max_files);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return digest;
}
fn canonicalPath(a: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    const terminated = try Io.Dir.cwd().realPathFileAlloc(io, path, a);
    defer a.free(terminated);
    // Options exposes ordinary slices. Preserve that exact allocation shape
    // rather than discarding the sentinel owner's allocation length.
    return a.dupe(u8, terminated);
}
pub const CanonicalOptions = struct {
    prelude_path: ?[]u8 = null,
    std_root: ?[]u8 = null,
    aliases: []project.Alias = &.{},
    pub fn init(a: std.mem.Allocator, io: Io, options: project.Options) !CanonicalOptions {
        if (options.input_mode != .project) return error.InputModeUnsupported;
        var result: CanonicalOptions = .{};
        errdefer result.deinit(a);
        if (options.prelude_path) |path| result.prelude_path = try canonicalPath(a, io, path);
        if (options.std_root) |path| result.std_root = try canonicalPath(a, io, path);
        const aliases = try a.alloc(project.Alias, options.aliases.len);
        var initialized: usize = 0;
        errdefer {
            for (aliases[0..initialized]) |alias| a.free(alias.root);
            a.free(aliases);
        }
        for (options.aliases, aliases) |alias, *target| {
            target.* = .{ .prefix = alias.prefix, .root = try canonicalPath(a, io, alias.root) };
            initialized += 1;
        }
        result.aliases = aliases;
        return result;
    }
    /// Borrowed options are valid only while this owner remains live.
    pub fn view(self: *const CanonicalOptions, raw: project.Options) project.Options {
        var result = raw;
        result.prelude_path = self.prelude_path;
        result.std_root = self.std_root;
        result.aliases = self.aliases;
        return result;
    }
    pub fn deinit(self: *CanonicalOptions, a: std.mem.Allocator) void {
        if (self.prelude_path) |path| a.free(path);
        if (self.std_root) |path| a.free(path);
        for (self.aliases) |alias| a.free(alias.root);
        a.free(self.aliases);
        self.* = undefined;
    }
};

/// The destination changes only after the complete artifact/Wasm is available.
/// Rejected admission and partial writes leave any prior destination intact.
pub fn publish(io: Io, output: []const u8, bytes: []const u8) !void {
    var file = try Io.Dir.cwd().createFileAtomic(io, output, .{ .replace = true });
    defer file.deinit(io);
    try file.file.writeStreamingAll(io, bytes);
    try file.file.sync(io);
    try file.replace(io);
}

fn existingOutput(a: std.mem.Allocator, io: Io, output: []const u8) !?[:0]u8 {
    return Io.Dir.cwd().realPathFileAlloc(io, output, a) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
}

pub fn work(io: Io, a: std.mem.Allocator, writer: *Io.Writer, create: bool, entry_path: []const u8, output: []const u8, artifact: ?[]const u8, raw_options: project.Options, compiler: [32]u8, metrics: *Metrics) !bool {
    var canonical = try CanonicalOptions.init(a, io, raw_options);
    defer canonical.deinit(a);
    const options = canonical.view(raw_options);
    const digest = settings(options);
    var at = Io.Clock.awake.now(io);
    if (create) {
        var source = try project.load(a, io, entry_path, options);
        var source_live = true;
        defer if (source_live) source.deinit(a);
        if (source.diagnostics.items.len != 0) {
            const issue = source.diagnostics.items[0];
            const filename = if (issue.unit == 0) entry_path else source.filename(issue.unit);
            if (issue.publication) |publication| {
                const unit = source.unit(issue.unit);
                if (issue.parse_code != null) {
                    try frontend(a, writer, filename, issue.unit, "parse-project", unit.source, publication, unit.tree.diagnostics.items);
                } else {
                    try frontend(a, writer, filename, issue.unit, "parse-project", unit.source, publication, issue.lexical_details);
                }
            } else try emit(writer, .{ .kind = "diagnostic", .filename = filename, .stage = "parse-project", .unit = issue.unit, .code = issue.codeName(), .start = issue.span.start, .end = issue.span.end, .message = issue.message() });
            return false;
        }
        var checked = try checker.checkProject(a, &source);
        var checked_live = true;
        defer if (checked_live) checked.deinit(a);
        if (checked.diagnostics.len != 0) {
            const issue = checked.diagnostics[0];
            const filename = if (issue.unit == 0) entry_path else source.filename(issue.unit);
            if (issue.hole) |hole| {
                try frontend(a, writer, filename, issue.unit, "check-project", source.unit(issue.unit).source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message() }, .{ .hole = hole });
                return false;
            }
            if (issue.numeric_literal) |detail| {
                try frontend(a, writer, filename, issue.unit, "check-project", source.unit(issue.unit).source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message(), .actual_token = detail.actual_token }, @as([]const @import("ast.zig").NumericFault, &.{detail}));
                return false;
            }
            const message = if (issue.purity) |witness| blk: {
                if (witness.operation_name == null and !witness.foreign) return error.OperationPurityOriginRequired;
                break :blk try purity.format(a, &source.symbols, "", witness);
            } else if (issue.symbol != 0)
                try a.print("{s}{s}{s}", .{ issue.message(), if (std.mem.eql(u8, issue.codeName(), "unknown_intrinsic") or std.mem.eql(u8, issue.codeName(), "unknown_record_field")) " " else ": ", source.symbols.get(issue.symbol) })
            else
                try a.dupe(u8, issue.message());
            defer a.free(message);
            if (issue.purity) |witness| {
                try frontend(a, writer, filename, issue.unit, "check-project", source.unit(issue.unit).source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = message }, @as([]const @import("check.zig").PurityWitness, &.{witness}));
            } else try emit(writer, .{ .kind = "diagnostic", .filename = filename, .stage = "check-project", .unit = issue.unit, .code = issue.codeName(), .start = issue.span.start, .end = issue.span.end, .message = message });
            return false;
        }
        metrics.frontend_us = elapsed(io, at);
        metrics.source_bytes = source.source_bytes;
        for (source.units.items) |unit| metrics.syntax_nodes += unit.tree.nodes.items.len - 1;
        for (checked.modules) |module| metrics.body_elaborations += module.?.checked.body_elaborations;
        at = Io.Clock.awake.now(io);
        var frozen = try closure.freeze(a, &source, &checked);
        defer format.deinit(a, &frozen);
        metrics.freeze_us = elapsed(io, at);
        payloadMetrics(&frozen, metrics);
        for (frozen.modules) |module| metrics.body_lowerings += module.core.body_lowerings;
        const key = try closure.sourceKey(compiler, digest, &source);
        if (try existingOutput(a, io, output)) |destination| {
            defer a.free(destination);
            for (source.units.items) |unit| if (std.mem.eql(u8, destination, source.symbols.get(unit.filename))) return error.OutputIsSource;
        }
        at = Io.Clock.awake.now(io);
        checked.deinit(a);
        checked_live = false;
        source.deinit(a);
        source_live = false;
        metrics.frontend_teardown_us = elapsed(io, at);
        at = Io.Clock.awake.now(io);
        const bytes = try format.encode(a, key, frozen);
        defer a.free(bytes);
        metrics.encode_us = elapsed(io, at);
        metrics.artifact_bytes = bytes.len;
        try publish(io, output, bytes);
        return true;
    }
    var load_stats: loader.Stats = .{};
    var frozen = blk: {
        const bytes = try Io.Dir.cwd().readFileAlloc(io, artifact.?, a, .limited(64 * 1024 * 1024 + 212));
        defer a.free(bytes);
        metrics.artifact_bytes = bytes.len;
        // Decoder owners are independent; release the input file before fresh
        // checking and backend proof rather than retaining both representations.
        break :blk try loader.load(a, io, bytes, compiler, digest, options, &load_stats);
    };
    defer format.deinit(a, &frozen);
    metrics.decode_us = load_stats.decode_us;
    metrics.validation_us = load_stats.validation_us;
    metrics.source_us = load_stats.source_us;
    metrics.source_bytes = load_stats.source_bytes;
    payloadMetrics(&frozen, metrics);
    const entry_identity = try Io.Dir.cwd().realPathFileAlloc(io, entry_path, a);
    defer a.free(entry_identity);
    if (try existingOutput(a, io, output)) |destination| {
        defer a.free(destination);
        if (std.mem.eql(u8, destination, entry_identity)) return error.OutputIsSource;
        for (frozen.modules) |module| if (std.mem.eql(u8, destination, module.identity.normalized_path)) return error.OutputIsSource;
        const input_artifact = try Io.Dir.cwd().realPathFileAlloc(io, artifact.?, a);
        defer a.free(input_artifact);
        if (std.mem.eql(u8, destination, input_artifact)) return error.OutputIsArtifact;
    }
    const protected_output = try existingOutput(a, io, output);
    defer if (protected_output) |path| a.free(path);
    at = Io.Clock.awake.now(io);
    var composed = try partial.compileOwned(a, io, entry_identity, protected_output, options, &frozen);
    defer composed.deinit(a);
    const result = &composed.result;
    metrics.source_bytes = composed.source_bytes;
    metrics.cached_modules = composed.cached_modules;
    metrics.fresh_modules = composed.fresh_modules;
    metrics.compile_us = elapsed(io, at);
    metrics.syntax_nodes = result.stats.syntax_nodes;
    metrics.body_elaborations = result.stats.body_elaborations;
    metrics.body_lowerings = result.stats.body_lowerings;
    var rejected = false;
    if (result.diagnostic) |issue| {
        try issue.write(writer, composed.diagnostic_filename orelse entry_identity);
        rejected = true;
    }
    if (result.compiled.diagnostic) |issue| {
        try emit(writer, .{ .kind = "diagnostic", .filename = composed.diagnostic_filename orelse entry_identity, .stage = "emit", .unit = issue.unit, .code = @tagName(issue.code), .start = issue.span.start, .end = issue.span.end, .message = issue.message() });
        rejected = true;
    }
    if (rejected) return false;
    metrics.wasm_bytes = result.compiled.bytes.len;
    try publish(io, output, result.compiled.bytes);
    return true;
}
/// All owners from work are gone on success, diagnostic rejection and I/O/OOM
/// failure before the final metrics record. No implicit source fallback occurs.
pub fn process(io: Io, backing: std.mem.Allocator, writer: *Io.Writer, create: bool, entry: []const u8, output: []const u8, artifact: ?[]const u8, options: project.Options, compiler: [32]u8) !bool {
    var tracked: memory.TrackedAllocator = .{ .backing = backing };
    var metrics: Metrics = .{};
    const started = Io.Clock.awake.now(io);
    var failure: ?anyerror = null;
    const success = work(io, tracked.allocator(), writer, create, entry, output, artifact, options, compiler, &metrics) catch |err| blk: {
        failure = err;
        break :blk false;
    };
    std.debug.assert(tracked.counts.live_bytes == 0);
    if (failure) |err| try emit(writer, .{ .kind = "diagnostic", .filename = entry, .stage = "dependencies", .code = @errorName(err), .start = 0, .end = 0, .message = "Dependency artifact operation declined; no source fallback performed" });
    const identity_hex = std.fmt.bytesToHex(compiler, .lower);
    try emit(writer, .{ .kind = "cache_metrics", .compiler_identity = @as([]const u8, &identity_hex), .operation = if (create) "create" else "build", .filename = entry, .success = success, .error_name = if (failure) |err| @errorName(err) else null, .total_us = elapsed(io, started), .work = metrics, .memory = tracked.counts });
    return success;
}
