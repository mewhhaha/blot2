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
const native_assets = @import("native_assets.zig");

const Request = struct {
    kind: enum { open, build, close, checkpoint, complete },
    id: u32,
    snapshot: ?u32 = null,
    filename: ?[]const u8 = null,
    position: ?u32 = null,
    version: ?u32 = null,
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
    nativeAssets: ?native_assets.Options = null,
    assetSources: []const SourceRange = &.{},
};
const request_parse_options: std.json.ParseOptions = .{ .allocate = .alloc_always, .duplicate_field_behavior = .@"error", .ignore_unknown_fields = false };
const SourceRange = struct { path: []const u8, start: u32, length: u32, deleted: bool = false };

fn sourceViews(a: Allocator, ranges: []const SourceRange, payload: []const u8) ![]inputs.overlays.Source {
    return rangeViews(a, ranges, payload, 0, true);
}
fn rangeViews(a: Allocator, ranges: []const SourceRange, payload: []const u8, start: usize, utf8: bool) ![]inputs.overlays.Source {
    if (ranges.len > 4096) return error.SourceLimit;
    if (start > payload.len) return error.InvalidSources;
    var end: usize = start;
    for (ranges) |range| {
        if (!validPath(range.path) or range.start != end or range.length > payload.len -| end or (range.deleted and range.length != 0)) return error.InvalidSources;
        end += range.length;
        if (utf8 and !std.unicode.utf8ValidateSlice(payload[range.start..end])) return error.InvalidSources;
    }
    if (end != payload.len) return error.InvalidSources;
    const sources = try a.alloc(inputs.overlays.Source, ranges.len);
    for (ranges, sources) |range, *source| source.* = .{
        .path = range.path,
        .contents = if (range.deleted) null else payload[range.start..][0..range.length],
    };
    return sources;
}
const protocol_version = 1;
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
    if (request.version == null or request.version.? != protocol_version) return error.VersionMismatch;
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
    assets: ?native_assets.Session = null,
    cache_file: ?restart_cache.File,
    cache_loaded: bool,
    saved_revision: usize = 0,

    fn init(a: Allocator, io: Io, request: Request, compiler: [32]u8, checkpoint_bytes: []const u8, cache_root: ?[]const u8) !OpenProject {
        const raw = try validateOpen(request);
        var assets = if (request.nativeAssets) |definitions| try native_assets.Session.init(a, definitions) else null;
        errdefer if (assets) |*owner| owner.deinit();
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
        return .{ .allocator = a, .entry = entry, .options_owner = options, .session = session, .assets = assets, .cache_file = cache_file, .cache_loaded = cache_loaded };
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
        if (self.assets) |*assets| assets.deinit();
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
    details: ?IssueDetails = null,
    related: ?@import("diagnostic_location.zig").Location = null,

    pub fn jsonStringify(self: Diagnostic, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginObject();
        inline for (@typeInfo(Diagnostic).@"struct".field_names) |name| {
            if (comptime std.mem.eql(u8, name, "related")) {
                if (self.related) |related| {
                    try stream.objectField(name);
                    try stream.write(related);
                }
            } else {
                try stream.objectField(name);
                try stream.write(@field(self, name));
            }
        }
        try stream.endObject();
    }
};
/// Forwarded diagnostic details: a frontend publication's JSON or the
/// backend's dispatch explanation.
const IssueDetails = union(enum) {
    bytes: []const u8,
    explanation: *const @import("dispatch_explanation.zig").Explanation,
    pub fn jsonStringify(self: IssueDetails, writer: anytype) !void {
        switch (self) {
            .bytes => |bytes| try (@import("dependency_consumer.zig").Details{ .bytes = bytes }).jsonStringify(writer),
            .explanation => |explanation| try writer.write(.{ .explanation = explanation.* }),
        }
    }
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
        .details = if (d.publication) |publication| if (publication.forwarded) .{ .bytes = publication.details_json } else null else null,
    };
    if (result.result.compiled.diagnostic) |d| return .{
        .filename = filename,
        .stage = "emit",
        .related = if (d.related) |location| @import("diagnostic_location.zig").Location.init(result.related_filename orelse return error.MissingRelatedFilename, location.span) else null,
        .code = @tagName(d.code),
        .start = d.span.start,
        .end = d.span.end,
        .message = d.message(),
        .details = if (result.result.compiled.explanation) |*explanation| .{ .explanation = explanation } else null,
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

const AssetRange = struct { id: u32, path: []const u8, mediaType: []const u8, sha256: []const u8, start: u32, length: u32 };
const AssetDependency = struct { path: []const u8, sha256: ?[]const u8 };

fn build(a: Allocator, io: Io, writer: *Io.Writer, opened: *OpenProject, id: u32, sources: []const inputs.overlays.Source, asset_sources: []const inputs.overlays.Source) !void {
    var assets: ?*native_assets.Candidate = null;
    defer if (assets) |candidate| candidate.deinit(a);
    if (opened.assets) |*owner| {
        assets = owner.prepare(io, opened.entry, sources, asset_sources) catch |err| {
            return operationFailure(a, writer, opened, id, @errorName(err), "Unable to prepare native asset inputs", null);
        };
        if (assets.?.issue) |diagnostic| return reject(a, writer, id, opened.session.revisions, .{
            .filename = diagnostic.filename,
            .stage = "asset",
            .code = diagnostic.code,
            .start = diagnostic.start,
            .end = diagnostic.end,
            .message = diagnostic.message,
        }, null);
    }
    var merged: std.ArrayList(inputs.overlays.Source) = .empty;
    defer merged.deinit(a);
    if (assets) |candidate| {
        try merged.appendSlice(a, candidate.sources.items);
        try merged.appendSlice(a, sources);
    }
    const complete_sources = if (assets != null) merged.items else sources;
    var preparation = opened.session.prepareRevisionWithSources(io, opened.entry, null, opened.options_owner.options, complete_sources) catch |err| {
        return operationFailure(a, writer, opened, id, @errorName(err), "Compiler operation failed", null);
    };
    defer preparation.deinit();
    switch (preparation) {
        .rejected => |*rejection| try reject(a, writer, id, opened.session.revisions, try issue(&rejection.result, opened.entry), rejection.stats),
        .ready => |candidate| {
            const result = candidate.result() orelse return error.MissingCandidateResult;
            const stats = .{
                .nativeWorkSteps = result.result.compiled.constant_steps,
                .frontend = result.result.stats,
                .backend = result.result.compiled.reuse,
                .optimization = result.result.compiled.optimization,
                .runtimeOptimization = result.result.compiled.runtime_optimization,
                .backendTiming = result.result.compiled.timing,
                .workCounters = result.result.compiled.counters,
                .principals = result.result.compiled.principal,
                .refinements = result.result.compiled.refinements,
                .selectedQueries = result.result.compiled.completed_queries,
                .restartCacheLoaded = opened.cache_loaded,
                .sourceBytes = result.source_bytes,
                .freshModules = result.fresh_modules,
                .cachedModules = result.cached_modules,
                .attemptStats = candidate.stats,
            };
            var assembled: std.ArrayList(u8) = .empty;
            defer assembled.deinit(a);
            var ranges: std.ArrayList(AssetRange) = .empty;
            defer ranges.deinit(a);
            var dependencies: std.ArrayList(AssetDependency) = .empty;
            defer dependencies.deinit(a);
            var payload_size = result.result.compiled.bytes.len;
            if (assets) |snapshot| {
                if (payload_size > frames.max_frame_bytes - 8) {
                    candidate.discard();
                    return operationFailure(a, writer, opened, id, "response_limit", "Build reply exceeds protocol limits", candidate.stats);
                }
                for (snapshot.resources.items) |resource| {
                    if (resource.bytes.len > frames.max_frame_bytes - 8 - payload_size) {
                        candidate.discard();
                        return operationFailure(a, writer, opened, id, "response_limit", "Build reply exceeds protocol limits", candidate.stats);
                    }
                    payload_size += resource.bytes.len;
                }
                var start = result.result.compiled.bytes.len;
                for (snapshot.resources.items) |*resource| {
                    try ranges.append(a, .{ .id = resource.id, .path = resource.path, .mediaType = resource.mediaType, .sha256 = &resource.sha256, .start = @intCast(start), .length = @intCast(resource.bytes.len) });
                    start += resource.bytes.len;
                }
                for (snapshot.dependencies.items) |*dependency| try dependencies.append(a, .{ .path = dependency.path, .sha256 = if (dependency.sha256) |*digest| digest else null });
            }
            const metadata = (if (assets) |snapshot| std.json.Stringify.valueAlloc(a, .{
                .kind = "build",
                .id = id,
                .epoch = epoch,
                .revision = opened.session.revisions + 1,
                .success = true,
                .stats = stats,
                .wasmBytes = result.result.compiled.bytes.len,
                .assets = ranges.items,
                .assetDependencies = dependencies.items,
                .assetStats = snapshot.stats,
            }, .{}) else std.json.Stringify.valueAlloc(a, .{
                .kind = "build",
                .id = id,
                .epoch = epoch,
                .revision = opened.session.revisions + 1,
                .success = true,
                .stats = stats,
            }, .{})) catch |err| {
                candidate.discard();
                return operationFailure(a, writer, opened, id, @errorName(err), "Unable to encode build reply", candidate.stats);
            };
            defer a.free(metadata);
            frames.checkLengths(metadata.len, payload_size) catch {
                candidate.discard();
                return operationFailure(a, writer, opened, id, "response_limit", "Build reply exceeds protocol limits", candidate.stats);
            };
            if (assets) |snapshot| {
                try assembled.ensureTotalCapacity(a, payload_size);
                assembled.appendSliceAssumeCapacity(result.result.compiled.bytes);
                for (snapshot.resources.items) |resource| assembled.appendSliceAssumeCapacity(resource.bytes);
            }
            const payload = if (assets != null) assembled.items else result.result.compiled.bytes;
            // Both owners transfer only after the entire reply has been encoded
            // and bounded. Neither commit allocates or performs I/O.
            if (!opened.session.commit(candidate)) return error.InvalidCandidate;
            if (assets) |snapshot| {
                opened.assets.?.commit(snapshot);
                assets = null;
            }
            if (opened.session.revisions == 1) opened.persist(io);
            try frames.write(writer, metadata, payload);
        },
    }
}

fn completionFailure(a: Allocator, writer: *Io.Writer, opened: *OpenProject, request: Request, code: []const u8, message: []const u8, position: u32) !void {
    var end = @min(message.len, 1024);
    while (end != 0 and end < message.len and message[end] & 0xc0 == 0x80) end -= 1;
    try reply(a, writer, .{ .kind = "complete", .id = request.id, .epoch = epoch, .revision = opened.session.revisions, .snapshot = request.snapshot.?, .filename = request.filename.?, .position = request.position.?, .success = false, .diagnostics = [_]Diagnostic{.{ .filename = request.filename.?, .stage = "complete", .code = code, .start = position, .end = position, .message = message[0..end] }} }, &.{});
}
fn complete(a: Allocator, io: Io, writer: *Io.Writer, opened: *OpenProject, request: Request, sources: []const inputs.overlays.Source) !void {
    if (request.snapshot.? == 0) return completionFailure(a, writer, opened, request, "invalid_completion", "Snapshot must be nonzero", 0);
    var assets: ?*native_assets.Candidate = null;
    defer if (assets) |candidate| candidate.deinit(a);
    var merged: std.ArrayList(inputs.overlays.Source) = .empty;
    defer merged.deinit(a);
    if (opened.assets) |*owner| {
        assets = owner.prepare(io, opened.entry, sources, &.{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.DuplicateSourcePath => return completionFailure(a, writer, opened, request, "duplicate_source", "Sources identify the same canonical file", 0),
            else => return completionFailure(a, writer, opened, request, "completion_failed", @errorName(err), 0),
        };
        if (assets.?.issue) |issue_| return completionFailure(a, writer, opened, request, "completion_failed", issue_.message, 0);
        try merged.appendSlice(a, assets.?.sources.items);
    }
    try merged.appendSlice(a, sources);
    var snapshot = inputs.Snapshot.initWithSources(a, io, opened.options_owner.options, merged.items) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.DuplicateSourcePath => return completionFailure(a, writer, opened, request, "duplicate_source", "Sources identify the same canonical file", 0),
        error.SourceLimit => return completionFailure(a, writer, opened, request, "source_limit", "Completion source acquisition limit", 0),
        else => return completionFailure(a, writer, opened, request, "completion_failed", @errorName(err), 0),
    };
    defer snapshot.deinit();
    var result = @import("editor_completion.zig").query(a, io, opened.entry, &snapshot, request.filename.?, request.position.?) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        var position: u32 = 0;
        if (err == error.InvalidPosition) {
            if (snapshot.canonical(io, request.filename.?)) |path| {
                if (snapshot.capturedSource(path)) |source| {
                    position = @intCast(@min(source.len, request.position.?));
                    while (position != 0 and position != source.len and source[position] & 0xc0 == 0x80) position -= 1;
                }
            } else |_| {}
        }
        const code = switch (err) {
            error.InvalidPosition => "invalid_position",
            error.InvalidCompletion => "invalid_completion",
            error.MissingSource => "missing_source",
            error.SourceLimit => "source_limit",
            else => "completion_failed",
        };
        return completionFailure(a, writer, opened, request, code, @errorName(err), position);
    };
    defer result.deinit(a);
    // A large context cannot evict already proved suggestions. Check it with
    // the required fields first, then preserve the best bounded item prefix.
    if (result.context) |context| {
        const context_bytes = try std.json.Stringify.valueAlloc(a, .{ .kind = "complete", .id = request.id, .epoch = epoch, .revision = opened.session.revisions, .snapshot = request.snapshot.?, .filename = request.filename.?, .position = request.position.?, .success = true, .replace = result.replace, .context = context, .items = [_]u8{}, .truncated = true, .diagnostics = [_]u8{} }, .{});
        defer a.free(context_bytes);
        if (context_bytes.len > 256 * 1024) {
            context.deinit(a);
            result.context = null;
            try result.noteLimit(a, request.filename.?);
        }
    }
    var item_count = result.items.len;
    var diagnostic_count = result.diagnostics.len;
    while (true) {
        const bytes = try std.json.Stringify.valueAlloc(a, .{ .kind = "complete", .id = request.id, .epoch = epoch, .revision = opened.session.revisions, .snapshot = request.snapshot.?, .filename = request.filename.?, .position = request.position.?, .success = true, .replace = result.replace, .context = result.context, .items = result.items[0..item_count], .truncated = result.truncated, .diagnostics = result.diagnostics[0..diagnostic_count] }, .{});
        defer a.free(bytes);
        if (bytes.len <= 256 * 1024) return frames.write(writer, bytes, &.{});
        if (!result.truncated) {
            try result.noteLimit(a, request.filename.?);
            diagnostic_count = result.diagnostics.len;
            continue;
        }
        if (diagnostic_count > 1) {
            diagnostic_count -= 1;
        } else if (item_count != 0) {
            item_count -= 1;
        } else if (result.context) |context| {
            context.deinit(a);
            result.context = null;
        } else {
            return error.FrameTooLarge;
        }
    }
}

/// No diagnostic/metrics text is written to stdout in serve mode.
pub fn run(a: Allocator, io: Io, reader: *Io.Reader, writer: *Io.Writer, compiler: [32]u8, cache_root: ?[]const u8) !void {
    return runWithPolicy(a, io, reader, writer, compiler, cache_root, .{});
}
pub fn runWithPolicy(a: Allocator, io: Io, reader: *Io.Reader, writer: *Io.Writer, compiler: [32]u8, cache_root: ?[]const u8, policy: @import("execution_policy.zig").Policy) !void {
    const identity = std.fmt.bytesToHex(compiler, .lower);
    try reply(a, writer, .{
        .kind = "hello",
        .protocol = "blot-zig-project",
        .version = protocol_version,
        .compilerIdentity = &identity,
        .capabilities = &[_][]const u8{ "project-build", "utf8_bytes", "abort-disposes-process", "source-overlays", "backend-checkpoints", "native-assets-v1", "editor-completion-v1" },
        .maxFrameBytes = frames.max_frame_bytes,
    }, &.{});
    var opened: ?OpenProject = null;
    defer if (opened) |*owner| owner.deinit();
    var last_id: u32 = 0;
    while (try frames.readRequestFrame(a, reader)) |frame_value| {
        var frame = frame_value;
        defer frame.deinit(a);
        const parsed = try std.json.parseFromSlice(Request, a, frame.metadata(), request_parse_options);
        defer parsed.deinit();
        const request = parsed.value;
        if (request.id == 0 or request.id <= last_id) return error.RequestOrder;
        last_id = request.id;
        if (request.kind != .complete and (request.snapshot != null or request.filename != null or request.position != null)) return error.InvalidRequest;
        switch (request.kind) {
            .open => {
                if (request.sources.len != 0 or request.assetSources.len != 0 or request.checkpoint != (frame.payload().len != 0)) return error.InvalidOpen;
                if (opened != null) return error.AlreadyOpen;
                // AlreadyOpen above proves the optional owns no previous session.
                // zig-analyzer: disable-next-line overwritten-owning-value
                opened = try OpenProject.init(a, io, request, compiler, frame.payload(), cache_root);
                opened.?.session.policy.semantic_workers = policy.semantic_workers;
                opened.?.session.policy.semantic_components = policy.semantic_components;
                try reply(a, writer, .{ .kind = "open", .id = request.id, .epoch = epoch, .revision = 0 }, &.{});
            },
            .build, .close, .checkpoint, .complete => {
                const owner = if (opened) |*value| value else return error.NotOpen;
                if (request.nativeAssets != null or request.version != null or request.entry != null or request.prelude != null or request.stdRoot != null or request.imports.len != 0 or request.dependencies != null or request.profileBackend or request.codegenTier != .optimized or request.shareMachineCode or request.codegenWorkers != 1 or request.checkpoint) return error.InvalidRequest;
                if (request.epoch == null or !std.mem.eql(u8, request.epoch.?, epoch) or request.revision == null or request.revision.? != owner.session.revisions) return error.RevisionMismatch;
                if (request.kind == .complete) {
                    if (request.snapshot == null or request.filename == null or request.position == null or request.filename.?.len > 4096 or !validPath(request.filename.?)) return error.InvalidCompletionRequest;
                    if (request.assetSources.len != 0) return error.InvalidRequest;
                    const sources = try sourceViews(a, request.sources, frame.payload());
                    defer a.free(sources);
                    try complete(a, io, writer, owner, request, sources);
                    continue;
                }
                if (request.kind == .checkpoint) {
                    if (request.sources.len != 0 or request.assetSources.len != 0 or frame.payload().len != 0) return error.InvalidRequest;
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
                    if (request.sources.len != 0 or request.assetSources.len != 0 or frame.payload().len != 0) return error.InvalidRequest;
                    owner.persist(io);
                    try reply(a, writer, .{ .kind = "close", .id = request.id, .epoch = epoch, .revision = owner.session.revisions }, &.{});
                    return;
                }
                if (owner.session.revisions >= frames.max_revision) return error.RevisionLimit;
                if (request.assetSources.len != 0 and owner.assets == null) return error.InvalidRequest;
                const source_bytes = if (request.assetSources.len != 0) request.assetSources[0].start else frame.payload().len;
                if (source_bytes > frame.payload().len) return error.InvalidSources;
                const sources = try sourceViews(a, request.sources, frame.payload()[0..source_bytes]);
                defer a.free(sources);
                const asset_sources = try rangeViews(a, request.assetSources, frame.payload(), source_bytes, false);
                defer a.free(asset_sources);
                try build(a, io, writer, owner, request.id, sources, asset_sources);
            },
        }
    }
}

test "project open requires the exact public protocol version" {
    const a = std.testing.allocator;
    for ([_]?u32{ null, 0, 2, std.math.maxInt(u32) }) |version| {
        try std.testing.expectError(error.VersionMismatch, validateOpen(.{ .kind = .open, .id = 1, .entry = "/main.blot", .version = version }));
    }
    _ = try validateOpen(.{ .kind = .open, .id = 1, .entry = "/main.blot", .version = protocol_version });
    try std.testing.expectError(error.DuplicateField, std.json.parseFromSlice(Request, a, "{\"kind\":\"open\",\"id\":1,\"id\":2}", request_parse_options));
    try std.testing.expectError(error.UnknownField, std.json.parseFromSlice(Request, a, "{\"kind\":\"open\",\"id\":1,\"unknown\":0}", request_parse_options));
}
