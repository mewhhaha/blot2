//! One owned project and serial build stream per child process. A ready
//! revision is committed only after its complete reply has been encoded and
//! bounded. Failure delivering a committed reply terminates this process.
const std = @import("std");
const frames = @import("zig_project_frames.zig");
const project = @import("project.zig");
const inputs = @import("revision_inputs.zig");
const retained = @import("retained_revision.zig");
const partial = @import("partial_dependency.zig");
const dep_cli = @import("dependency_cli.zig");
const dep_loader = @import("dependency_project_loader.zig");
const ast = @import("ast.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const restart_cache = @import("restart_cache.zig");

const Request = struct {
    kind: enum { open, build, close, checkpoint },
    id: u32,
    epoch: ?[]const u8 = null,
    revision: ?u64 = null,
    entry: ?[]const u8 = null,
    prelude: ?[]const u8 = null,
    stdRoot: ?[]const u8 = null,
    imports: []const project.Alias = &.{},
    dependencies: ?[]const u8 = null,
    profileBackend: bool = false,
    codegenTier: @import("compilation_tier.zig").Tier = .optimized,
    shareMachineCode: bool = false,
    codegenWorkers: u8 = 1,
    checkpoint: bool = false,
    sources: []const SourceRange = &.{},
};
const SourceRange = struct { path: []const u8, start: u32, length: u32, deleted: bool = false };

fn sourceViews(a: Allocator, ranges: []const SourceRange, payload: []const u8) ![]inputs.overlays.Source {
    if (ranges.len > 4096) return error.SourceLimit;
    var end: usize = 0;
    for (ranges) |range| {
        if (!validPath(range.path) or range.start != end or range.length > payload.len -| end or (range.deleted and range.length != 0)) return error.InvalidSources;
        end += range.length;
        if (!std.unicode.utf8ValidateSlice(payload[range.start..end])) return error.InvalidSources;
    }
    if (end != payload.len) return error.InvalidSources;
    const sources = try a.alloc(inputs.overlays.Source, ranges.len);
    for (ranges, sources) |range, *source| source.* = .{
        .path = range.path,
        .contents = if (range.deleted) null else payload[range.start..][0..range.length],
    };
    return sources;
}
const epoch = "1"; // Channel-local: a process permits one open and no reopening.

test "source overlay ranges partition payload before allocating or preparing a revision" {
    const a = std.testing.allocator;
    const valid = try sourceViews(a, &.{ .{ .path = "/main.blot", .start = 0, .length = 2 }, .{ .path = "/hidden.blot", .start = 2, .length = 0, .deleted = true } }, "42");
    defer a.free(valid);
    try std.testing.expectEqualStrings("42", valid[0].contents.?);
    try std.testing.expect(valid[1].contents == null);
    const failing = std.testing.failing_allocator;
    try std.testing.expectError(error.InvalidSources, sourceViews(failing, &.{.{ .path = "/main.blot", .start = 1, .length = 1 }}, "42"));
    try std.testing.expectError(error.InvalidSources, sourceViews(failing, &.{.{ .path = "/main.blot", .start = 0, .length = 3 }}, "42"));
    try std.testing.expectError(error.InvalidSources, sourceViews(failing, &.{.{ .path = "/main.blot", .start = 0, .length = 2, .deleted = true }}, "42"));
    try std.testing.expectError(error.InvalidSources, sourceViews(failing, &.{.{ .path = "/main.blot", .start = 0, .length = 2 }}, &.{ 0xff, 0xfe }));
    try std.testing.expectError(error.InvalidSources, sourceViews(failing, &.{}, "42"));
}

fn validPath(path: []const u8) bool {
    return path.len != 0 and std.Io.Dir.path.isAbsolute(path) and std.mem.findScalar(u8, path, 0) == null;
}
fn validateOpen(request: Request) !project.Options {
    if (request.codegenWorkers == 0 or request.codegenWorkers > 16) return error.InvalidOpen;
    if (request.entry == null or !validPath(request.entry.?) or request.epoch != null or request.revision != null) return error.InvalidOpen;
    for ([_]?[]const u8{ request.prelude, request.stdRoot, request.dependencies }) |path| if (path) |p| {
        if (!validPath(p)) return error.InvalidOpen;
    };
    for (request.imports, 0..) |alias, i| {
        if (alias.prefix.len == 0 or alias.prefix[alias.prefix.len - 1] != '/' or std.mem.findScalar(u8, alias.prefix, 0) != null or !validPath(alias.root)) return error.InvalidOpen;
        for (request.imports[0..i]) |old| if (std.mem.eql(u8, old.prefix, alias.prefix)) return error.InvalidOpen;
    }
    return .{ .prelude_path = request.prelude, .std_root = request.stdRoot, .aliases = request.imports };
}

const OpenProject = struct {
    allocator: Allocator,
    entry: []u8,
    options_owner: inputs.Snapshot,
    session: retained.Session,
    cache_file: ?restart_cache.File,
    cache_loaded: bool,
    saved_revision: usize = 0,

    fn init(a: Allocator, io: Io, request: Request, compiler: [32]u8, checkpoint_bytes: []const u8, cache_root: ?[]const u8) !OpenProject {
        const raw = try validateOpen(request);
        const entry = try a.dupe(u8, request.entry.?);
        errdefer a.free(entry);
        var options = try inputs.Snapshot.init(a, raw);
        errdefer options.deinit();
        var session = if (request.dependencies) |path| blk: {
            // Wire admission uses the artifact's canonical settings. Keep the
            // original absolute lexical resolver inputs for subsequent builds;
            // every revision re-resolves them, including symlink retargeting.
            var canonical = try dep_cli.CanonicalOptions.init(a, io, raw);
            defer canonical.deinit(a);
            const actual = canonical.view(raw);
            const bytes = try Io.Dir.cwd().readFileAlloc(io, path, a, .limited(512 * 1024 * 1024));
            defer a.free(bytes);
            var stats: dep_loader.Stats = .{};
            const seed = try dep_loader.load(a, io, bytes, compiler, dep_cli.settings(actual), actual, &stats);
            break :blk retained.Session.init(a, seed, options.options);
        } else try retained.Session.initEmpty(a, options.options);
        errdefer session.deinit();
        session.profile_backend = request.profileBackend;
        session.policy.codegen_tier = request.codegenTier;
        session.policy.share_machine_code = request.shareMachineCode;
        var cache_file: ?restart_cache.File = if (cache_root) |root| restart_cache.File.init(a, root, compiler, entry) catch null else null;
        errdefer if (cache_file) |*file| file.deinit();
        var cache_loaded = false;
        if (checkpoint_bytes.len != 0) session.checkpoint = @import("backend_checkpoint.zig").decode(a, compiler, checkpoint_bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => null, // Optional candidates never replace source validation.
        } else if (cache_file) |*file| {
            session.checkpoint = file.load(io);
            cache_loaded = session.checkpoint != null;
        }
        session.policy.codegen_workers = request.codegenWorkers;
        return .{ .allocator = a, .entry = entry, .options_owner = options, .session = session, .cache_file = cache_file, .cache_loaded = cache_loaded };
    }
    fn persist(self: *OpenProject, io: Io) void {
        if (self.saved_revision == self.session.revisions) return;
        const file = &(self.cache_file orelse return);
        const bytes = self.session.checkpointBytes(file.compiler) catch return;
        defer self.allocator.free(bytes);
        if (file.save(io, bytes)) self.saved_revision = self.session.revisions;
    }
    fn deinit(self: *OpenProject) void {
        self.session.deinit();
        if (self.cache_file) |*file| file.deinit();
        self.options_owner.deinit();
        self.allocator.free(self.entry);
        self.* = undefined;
    }
};

const Diagnostic = struct {
    filename: []const u8,
    stage: []const u8,
    code: []const u8,
    start: u32,
    end: u32,
    message: []const u8,
    offset_encoding: []const u8 = "utf8_bytes",
    utf16: ?ast.Span = null,
    details: ?@import("dependency_consumer.zig").Details = null,
};
fn issue(result: *const partial.Result, entry: []const u8) !Diagnostic {
    const filename = result.diagnostic_filename orelse entry;
    if (result.result.diagnostic) |d| return .{
        .filename = filename,
        .stage = d.stage,
        .code = d.code,
        .start = d.start,
        .end = d.end,
        .message = d.message,
        .utf16 = if (d.publication) |publication| publication.utf16 else null,
        .details = if (d.publication) |publication| if (std.mem.eql(u8, d.code, "typed_hole")) .{ .bytes = publication.details_json } else null else null,
    };
    if (result.result.compiled.diagnostic) |d| return .{
        .filename = filename,
        .stage = "emit",
        .code = @tagName(d.code),
        .start = d.span.start,
        .end = d.span.end,
        .message = d.message(),
    };
    return error.MissingRejectionDiagnostic;
}
fn reply(a: Allocator, writer: *Io.Writer, metadata: anytype, payload: []const u8) !void {
    const bytes = try std.json.Stringify.valueAlloc(a, metadata, .{});
    defer a.free(bytes);
    try frames.write(writer, bytes, payload);
}
fn reject(a: Allocator, writer: *Io.Writer, id: u32, revision: usize, diagnostic: Diagnostic, attempt: ?retained.Stats) !void {
    try reply(a, writer, .{ .kind = "build", .id = id, .epoch = epoch, .revision = revision, .success = false, .diagnostics = &[_]Diagnostic{diagnostic}, .attemptStats = attempt }, &.{});
}
fn operationFailure(a: Allocator, writer: *Io.Writer, opened: *OpenProject, id: u32, code: []const u8, message: []const u8, attempt: ?retained.Stats) !void {
    try reject(a, writer, id, opened.session.revisions, .{ .filename = opened.entry, .stage = "build-project", .code = code, .start = 0, .end = 0, .message = message }, attempt);
}

fn build(a: Allocator, io: Io, writer: *Io.Writer, opened: *OpenProject, id: u32, sources: []const inputs.overlays.Source) !void {
    var preparation = opened.session.prepareRevisionWithSources(io, opened.entry, null, opened.options_owner.options, sources) catch |err| {
        // No attempt counters survived this throwing path. Never substitute
        // Session.last (which describes an earlier successful revision).
        return operationFailure(a, writer, opened, id, @errorName(err), "Compiler operation failed", null);
    };
    defer preparation.deinit();
    switch (preparation) {
        .rejected => |*rejection| try reject(a, writer, id, opened.session.revisions, try issue(&rejection.result, opened.entry), rejection.stats),
        .ready => |candidate| {
            const result = candidate.result() orelse return error.MissingCandidateResult;
            const metadata = std.json.Stringify.valueAlloc(a, .{
                .kind = "build",
                .id = id,
                .epoch = epoch,
                .revision = opened.session.revisions + 1,
                .success = true,
                .stats = .{
                    .nativeWorkSteps = result.result.compiled.constant_steps,
                    .frontend = result.result.stats,
                    .backend = result.result.compiled.reuse,
                    .optimization = result.result.compiled.optimization,
                    .runtimeOptimization = result.result.compiled.runtime_optimization,
                    .backendTiming = result.result.compiled.timing,
                    .workCounters = result.result.compiled.counters,
                    .principals = result.result.compiled.principal,
                    .restartCacheLoaded = opened.cache_loaded,
                    .sourceBytes = result.source_bytes,
                    .freshModules = result.fresh_modules,
                    .cachedModules = result.cached_modules,
                    .attemptStats = candidate.stats,
                },
            }, .{}) catch |err| {
                candidate.discard();
                return operationFailure(a, writer, opened, id, @errorName(err), "Unable to encode build reply", candidate.stats);
            };
            defer a.free(metadata);
            frames.checkLengths(metadata.len, result.result.compiled.bytes.len) catch {
                candidate.discard();
                return operationFailure(a, writer, opened, id, "response_limit", "Build reply exceeds protocol limits", candidate.stats);
            };
            // This transfer performs no allocation or I/O. Result bytes remain
            // independently owned by Candidate until the complete reply is sent.
            if (!opened.session.commit(candidate)) return error.InvalidCandidate;
            // Seed restarts before the first reply. Later edits keep their cheap
            // retained path; graceful close saves the latest committed revision.
            if (opened.session.revisions == 1) opened.persist(io);
            try frames.write(writer, metadata, result.result.compiled.bytes);
        },
    }
}

/// No diagnostic/metrics text is written to stdout in serve mode.
pub fn run(a: Allocator, io: Io, reader: *Io.Reader, writer: *Io.Writer, compiler: [32]u8, cache_root: ?[]const u8) !void {
    const identity = std.fmt.bytesToHex(compiler, .lower);
    try reply(a, writer, .{
        .kind = "hello",
        .protocol = "blot-zig-project",
        .version = 1,
        .compilerIdentity = &identity,
        .capabilities = &[_][]const u8{ "project-build", "utf8_bytes", "abort-disposes-process", "source-overlays", "backend-checkpoints" },
        .maxFrameBytes = frames.max_frame_bytes,
    }, &.{});
    var opened: ?OpenProject = null;
    defer if (opened) |*owner| owner.deinit();
    var last_id: u32 = 0;
    while (try frames.readRequestFrame(a, reader)) |frame_value| {
        var frame = frame_value;
        defer frame.deinit(a);
        const parsed = try std.json.parseFromSlice(Request, a, frame.metadata(), .{ .allocate = .alloc_always });
        defer parsed.deinit();
        const request = parsed.value;
        if (request.id == 0 or request.id <= last_id) return error.RequestOrder;
        last_id = request.id;
        switch (request.kind) {
            .open => {
                if (request.sources.len != 0 or request.checkpoint != (frame.payload().len != 0)) return error.InvalidOpen;
                if (opened != null) return error.AlreadyOpen;
                // AlreadyOpen above proves the optional owns no previous session.
                // zig-analyzer: disable-next-line overwritten-owning-value
                opened = try OpenProject.init(a, io, request, compiler, frame.payload(), cache_root);
                try reply(a, writer, .{ .kind = "open", .id = request.id, .epoch = epoch, .revision = 0 }, &.{});
            },
            .build, .close, .checkpoint => {
                const owner = if (opened) |*value| value else return error.NotOpen;
                if (request.entry != null or request.prelude != null or request.stdRoot != null or request.imports.len != 0 or request.dependencies != null or request.profileBackend or request.codegenTier != .optimized or request.shareMachineCode or request.codegenWorkers != 1 or request.checkpoint) return error.InvalidRequest;
                if (request.epoch == null or !std.mem.eql(u8, request.epoch.?, epoch) or request.revision == null or request.revision.? != owner.session.revisions) return error.RevisionMismatch;
                if (request.kind == .checkpoint) {
                    if (request.sources.len != 0 or frame.payload().len != 0) return error.InvalidRequest;
                    const bytes = owner.session.checkpointBytes(compiler) catch |err| {
                        try reply(a, writer, .{ .kind = "checkpoint", .id = request.id, .epoch = epoch, .revision = owner.session.revisions, .success = false, .code = @errorName(err) }, &.{});
                        continue;
                    };
                    defer a.free(bytes);
                    if (bytes.len > frames.max_frame_bytes - 1024) {
                        try reply(a, writer, .{ .kind = "checkpoint", .id = request.id, .epoch = epoch, .revision = owner.session.revisions, .success = false, .code = "checkpoint_limit" }, &.{});
                    } else try reply(a, writer, .{ .kind = "checkpoint", .id = request.id, .epoch = epoch, .revision = owner.session.revisions, .success = true }, bytes);
                    continue;
                }
                if (request.kind == .close) {
                    if (request.sources.len != 0 or frame.payload().len != 0) return error.InvalidRequest;
                    owner.persist(io);
                    try reply(a, writer, .{ .kind = "close", .id = request.id, .epoch = epoch, .revision = owner.session.revisions }, &.{});
                    return;
                }
                if (owner.session.revisions >= frames.max_revision) return error.RevisionLimit;
                const sources = try sourceViews(a, request.sources, frame.payload());
                defer a.free(sources);
                try build(a, io, writer, owner, request.id, sources);
            },
        }
    }
}
