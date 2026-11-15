//! `blotc migrate-stores`: turns each `:=` that the uniqueness analysis
//! rejects (`aliased_update`) into the store `=`. A `:=` through storage
//! already writes in place, so the rewrite keeps each program's meaning; it
//! changes only the `:=` token. Every pass loads, checks and lowers each
//! entry and rewrites the rejected sites, and passes repeat until none is
//! rejected. Only files under the write root change, and std only on request.
const std = @import("std");
const project = @import("reuse/project.zig");
const project_check = @import("reuse/project_check.zig");
const inputs = @import("reuse/revision_inputs.zig");
const assets = @import("assets/native_assets.zig");
const core_builder = @import("check/core_builder.zig");
const Io = std.Io;
const A = std.mem.Allocator;

pub const Settings = struct {
    options: project.Options = .{},
    assets: ?assets.Options = null,
    inference_budget: ?usize = null,
};

pub const Request = struct {
    entries: []const []const u8,
    settings: Settings,
    /// Absolute; only files below it are rewritten.
    write_root: []const u8,
    include_std: bool = false,
    /// Report the sites of one pass without writing them.
    dry_run: bool = false,
};

const maximum_passes = 16;

pub fn run(a: A, io: Io, writer: *Io.Writer, request: Request) !bool {
    var rewritten: usize = 0;
    var passes: usize = 0;
    while (passes < maximum_passes) {
        passes += 1;
        var pass: Outcome = .{};
        for (request.entries) |entry| {
            const outcome = try migrateEntry(a, io, writer, request, entry);
            if (outcome.failed) {
                try summary(writer, false, passes, rewritten + pass.rewritten, pass.blocked);
                return false;
            }
            pass.rewritten += outcome.rewritten;
            pass.blocked += outcome.blocked;
        }
        rewritten += pass.rewritten;
        if (pass.rewritten == 0 or request.dry_run) {
            const ok = pass.blocked == 0 or request.dry_run;
            try summary(writer, ok, passes, rewritten, pass.blocked);
            return ok;
        }
    }
    try summary(writer, false, passes, rewritten, 0);
    return false;
}

fn summary(writer: *Io.Writer, ok: bool, passes: usize, rewritten: usize, blocked: usize) !void {
    try std.json.Stringify.value(.{ .kind = "migrate-stores", .success = ok, .passes = passes, .rewritten = rewritten, .outside = blocked }, .{}, writer);
    try writer.writeByte('\n');
}

const Outcome = struct { rewritten: usize = 0, blocked: usize = 0, failed: bool = false };
const Site = struct { unit: u32, start: u32 };

fn migrateEntry(a: A, io: Io, writer: *Io.Writer, request: Request, entry: []const u8) !Outcome {
    var session: ?assets.Session = if (request.settings.assets) |options| try assets.Session.init(a, options) else null;
    defer if (session) |*owner| owner.deinit();
    var candidate: ?*assets.Candidate = null;
    defer if (candidate) |owner| owner.deinit(a);
    if (session) |*owner| {
        candidate = try owner.prepare(io, entry, &.{}, &.{});
        if (candidate.?.issue) |issue| {
            try diagnostic(writer, issue.filename, "assets", issue.code, issue.start, issue.end, issue.message);
            return .{ .failed = true };
        }
    }
    var snapshot = try inputs.Snapshot.initWithSources(a, io, request.settings.options, if (candidate) |owner| owner.sources.items else &.{});
    defer snapshot.deinit();
    var loaded = try project.loadWithInputs(a, io, entry, request.settings.options, snapshot.provider());
    defer loaded.deinit(a);
    if (loaded.diagnostics.items.len != 0) {
        for (loaded.diagnostics.items) |item| try diagnostic(writer, if (item.unit == 0) entry else loaded.filename(item.unit), "parse-project", item.codeName(), item.span.start, item.span.end, item.message());
        return .{ .failed = true };
    }
    var checked = try project_check.checkProject(a, &loaded);
    defer checked.deinit(a);
    if (checked.diagnostics.len != 0) {
        for (checked.diagnostics) |item| try diagnostic(writer, if (item.unit == 0) entry else loaded.filename(item.unit), "check-project", item.codeName(), item.span.start, item.span.end, item.message());
        return .{ .failed = true };
    }
    var sites: std.ArrayList(Site) = .empty;
    defer sites.deinit(a);
    for (loaded.units.items, 1..) |*unit, index| {
        const id: u32 = @intCast(index);
        var lowered = try core_builder.lowerWithOrigins(a, &unit.tree, &loaded.symbols, &checked.module(id).checked, .{ .context = &loaded, .lookup = project_check.diagnosticModuleOrigin });
        defer lowered.deinit(a);
        for (lowered.diagnostics) |item| {
            if (item.code != .aliased_update) {
                // A dry run reports every other lowering diagnostic too.
                try diagnostic(writer, loaded.filename(id), "lower", @tagName(item.code), item.span.start, item.span.end, item.message());
                if (request.dry_run) continue;
                return .{ .failed = true };
            }
            try sites.append(a, .{ .unit = id, .start = item.span.start });
        }
    }
    var outcome: Outcome = .{};
    var at: usize = 0;
    while (at < sites.items.len) {
        const unit = sites.items[at].unit;
        var end = at;
        while (end < sites.items.len and sites.items[end].unit == unit) end += 1;
        const group = sites.items[at..end];
        at = end;
        const path = loaded.filename(unit);
        if (!try writable(a, io, request, path)) {
            for (group) |site| try report(writer, "outside", path, loaded.unit(unit).source, site.start);
            outcome.blocked += group.len;
            continue;
        }
        const source = loaded.unit(unit).source;
        var rewritten = try a.dupe(u8, source);
        defer a.free(rewritten);
        std.mem.sortUnstable(Site, group, {}, struct {
            fn later(_: void, left: Site, right: Site) bool {
                return left.start > right.start;
            }
        }.later);
        var length = rewritten.len;
        var previous: ?u32 = null;
        for (group) |site| {
            if (previous != null and previous.? == site.start) continue;
            previous = site.start;
            const operator = rebindOperator(rewritten[0..length], site.start) orelse {
                try diagnostic(writer, path, "migrate-stores", "missing_rebind_operator", site.start, site.start, "No := follows this rejected update's place");
                return .{ .failed = true };
            };
            try report(writer, "store", path, source, site.start);
            // `:=` becomes `=`: drop the colon.
            std.mem.copyForwards(u8, rewritten[operator .. length - 1], rewritten[operator + 1 .. length]);
            length -= 1;
            outcome.rewritten += 1;
        }
        if (!request.dry_run) try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = rewritten[0..length] });
    }
    return outcome;
}

/// The offset of the `:=` after the place that starts at `start`: the first
/// one outside brackets and string literals.
fn rebindOperator(source: []const u8, start: u32) ?usize {
    var nesting: usize = 0;
    var at: usize = start;
    while (at + 1 < source.len) : (at += 1) {
        switch (source[at]) {
            '(', '[', '{' => nesting += 1,
            ')', ']', '}' => nesting -|= 1,
            '"' => {
                at += 1;
                while (at < source.len and source[at] != '"') : (at += 1) {
                    if (source[at] == '\\') at += 1;
                }
            },
            '\n' => if (nesting == 0) return null,
            ':' => if (nesting == 0 and source[at + 1] == '=') return at,
            else => {},
        }
    }
    return null;
}

fn writable(a: A, io: Io, request: Request, path: []const u8) !bool {
    const real = Io.Dir.cwd().realPathFileAlloc(io, path, a) catch return false;
    defer a.free(real);
    if (!under(real, request.write_root)) return false;
    if (request.include_std) return true;
    const root = request.settings.options.std_root orelse return true;
    const std_real = Io.Dir.cwd().realPathFileAlloc(io, root, a) catch return true;
    defer a.free(std_real);
    return !under(real, std_real);
}

fn under(path: []const u8, root: []const u8) bool {
    const trimmed = std.mem.trimEnd(u8, root, "/");
    return std.mem.startsWith(u8, path, trimmed) and path.len > trimmed.len and path[trimmed.len] == '/';
}

fn report(writer: *Io.Writer, kind: []const u8, path: []const u8, source: []const u8, start: u32) !void {
    var line: usize = 1;
    var column: usize = 1;
    for (source[0..@min(start, source.len)]) |byte| {
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else column += 1;
    }
    try std.json.Stringify.value(.{ .kind = kind, .filename = path, .start = start, .line = line, .column = column }, .{}, writer);
    try writer.writeByte('\n');
}

fn diagnostic(writer: *Io.Writer, filename: []const u8, stage: []const u8, code: []const u8, start: u32, end: u32, message: []const u8) !void {
    try std.json.Stringify.value(.{ .kind = "diagnostic", .filename = filename, .stage = stage, .code = code, .start = start, .end = end, .message = message }, .{}, writer);
    try writer.writeByte('\n');
}

/// Settings from a pen.json `compiler.settings`: std root and prelude,
/// import aliases, native assets and the inference budget. Paths resolve
/// against the file's directory. `arena` owns the result.
pub fn projectSettings(arena: A, io: Io, pen_path: []const u8) !Settings {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, pen_path, arena, .limited(1 << 20));
    const root_relative = Io.Dir.path.dirname(pen_path) orelse ".";
    const root = try Io.Dir.cwd().realPathFileAlloc(io, root_relative, arena);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
    const compiler = object(parsed, "compiler") orelse return error.InvalidProjectSettings;
    const settings = object(compiler, "settings") orelse return error.InvalidProjectSettings;
    var result: Settings = .{};
    if (settings.object.get("std")) |value| {
        const std_root = try absolute(arena, root, try string(value));
        result.options.std_root = std_root;
        result.options.prelude_path = try Io.Dir.path.join(arena, &.{ std_root, "prelude.blot" });
    }
    if (object(settings, "imports")) |imports| {
        const aliases = try arena.alloc(project.Alias, imports.object.count());
        var iterator = imports.object.iterator();
        var index: usize = 0;
        while (iterator.next()) |item| : (index += 1) aliases[index] = .{ .prefix = item.key_ptr.*, .root = try absolute(arena, root, try string(item.value_ptr.*)) };
        result.options.aliases = aliases;
    }
    if (settings.object.get("inferenceBudget")) |value| switch (value) {
        .integer => |budget| result.inference_budget = std.math.cast(usize, budget) orelse return error.InvalidProjectSettings,
        else => return error.InvalidProjectSettings,
    };
    if (object(settings, "nativeAssets")) |native| {
        const roots_value = if (native.object.get("roots")) |value| value.array.items else &.{};
        const roots = try arena.alloc([]const u8, roots_value.len);
        for (roots_value, roots) |value, *path| path.* = try absolute(arena, root, try string(value));
        const imports_value = if (native.object.get("imports")) |value| value.array.items else &.{};
        const definitions = try arena.alloc(assets.Definition, imports_value.len);
        for (imports_value, definitions) |value, *definition| {
            const kind = try string(value.object.get("kind") orelse return error.InvalidProjectSettings);
            definition.* = .{
                .module = try absolute(arena, root, try string(value.object.get("module") orelse return error.InvalidProjectSettings)),
                .path = try absolute(arena, root, try string(value.object.get("path") orelse return error.InvalidProjectSettings)),
                .kind = std.meta.stringToEnum(assets.Kind, kind) orelse return error.InvalidProjectSettings,
                .type = if (value.object.get("type")) |item| try string(item) else null,
                .@"export" = if (value.object.get("export")) |item| try string(item) else null,
                .mediaType = if (value.object.get("mediaType")) |item| try string(item) else null,
            };
        }
        result.assets = .{ .roots = roots, .imports = definitions };
    }
    return result;
}

fn object(value: std.json.Value, key: []const u8) ?std.json.Value {
    if (value != .object) return null;
    const found = value.object.get(key) orelse return null;
    return if (found == .object) found else null;
}

fn string(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.InvalidProjectSettings,
    };
}

fn absolute(a: A, root: []const u8, path: []const u8) ![]u8 {
    const joined = if (Io.Dir.path.isAbsolute(path)) try a.dupe(u8, path) else try Io.Dir.path.join(a, &.{ root, path });
    defer a.free(joined);
    return Io.Dir.path.resolveAlloc(a, &.{joined});
}
