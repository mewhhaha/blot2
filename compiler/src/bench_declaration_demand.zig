//! Load a real Gdev source project and print declaration-demand inventory.
//! This intentionally stops before project checking, lowering, or compilation.
const std = @import("std");
const project = @import("reuse/project.zig");
const inputs = @import("reuse/revision_inputs.zig");
const assets = @import("backend/native_assets.zig");
const demand = @import("reuse/declaration_demand.zig");
const ast = @import("parse/ast.zig");
const lexer = @import("parse/lexer.zig");
const parser = @import("parse/parser.zig");
const symbols = @import("parse/symbols.zig");
const A = std.mem.Allocator;
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const root_arg, const entry_arg, const ablated = try arguments(args[1..]);
    const io = init.io;
    const root_z = try Io.Dir.cwd().realPathFileAlloc(io, root_arg, a);
    const root: []const u8 = root_z;
    const entry = try absolute(a, root, entry_arg);
    const original_entry = try Io.Dir.cwd().readFileAlloc(io, entry, a, .limited(16 * 1024 * 1024));
    const original_entry_digest = sha256(original_entry);
    const original_entry_sha256 = try a.dupe(u8, &original_entry_digest);
    const pen_path = try Io.Dir.path.join(a, &.{ root, "pen.json" });
    const pen = try Io.Dir.cwd().readFileAlloc(io, pen_path, a, .limited(1 << 20));
    const parsed = try std.json.parseFromSlice(std.json.Value, a, pen, .{});
    const settings = objectField(objectField(parsed.value, "compiler"), "settings");
    const loader_options = try projectOptions(a, root, settings);
    const asset_options = try assetOptions(a, root, settings);

    var asset_session = try assets.Session.init(a, asset_options);
    defer asset_session.deinit();
    const asset_started = now(io);
    var asset_candidate = try asset_session.prepare(io, entry, &.{}, &.{});
    defer asset_candidate.deinit(a);
    const asset_us = elapsed(asset_started, io);
    if (asset_candidate.issue != null) return error.NativeAssetIssue;

    var source_overlays: std.ArrayList(inputs.overlays.Source) = .empty;
    try source_overlays.appendSlice(a, asset_candidate.sources.items);
    if (ablated) try source_overlays.append(a, .{ .path = entry, .contents = try tinyEntrySource(a, original_entry) });
    var snapshot = try inputs.Snapshot.initWithSources(a, io, loader_options, source_overlays.items);
    defer snapshot.deinit();
    const load_started = now(io);
    var loaded = try project.loadWithInputs(a, io, entry, loader_options, snapshot.provider());
    const load_us = elapsed(load_started, io);
    defer loaded.deinit(a);
    if (loaded.compiled_modules.len != 0) return error.CompiledInputsNotSupported;
    if (loaded.diagnostics.items.len != 0) return error.ProjectLoadDiagnostics;

    const plan_started = now(io);
    var selection = (try demand.Plan.prepare(a, &loaded)) orelse return error.DemandPlanDeclined;
    const plan_us = elapsed(plan_started, io);
    defer selection.deinit();

    const modules = try a.alloc(ModuleReport, loaded.units.items.len);
    var original_bodies: BodyWeights = .{};
    var generated_bodies: BodyWeights = .{};
    for (loaded.units.items, modules, 1..) |unit, *report, id| {
        const selected = selection.units[id - 1].declarations.len;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(unit.source, &digest, .{});
        const digest_hex = std.fmt.bytesToHex(digest, .lower);
        const path = loaded.filename(@intCast(id));
        const generated_asset = isGeneratedAsset(path, asset_candidate.sources.items);
        var bodies: BodyWeights = .{};
        for (unit.tree.roots.items) |declaration| {
            switch (unit.tree.node(declaration).tag) {
                .value_decl => addBody(&bodies, &unit.tree, unit.source, declaration, selection.wants(@intCast(id), declaration)),
                .implementation_decl => {
                    const implementation = unit.tree.implementation(declaration);
                    for (unit.tree.list(implementation.members)) |member| {
                        if (unit.tree.node(member).tag == .value_decl) {
                            addBody(&bodies, &unit.tree, unit.source, member, selection.wants(@intCast(id), member));
                        }
                    }
                },
                else => {},
            }
        }
        if (generated_asset) {
            generated_bodies.add(bodies);
        } else {
            original_bodies.add(bodies);
        }
        report.* = .{
            .path = path,
            .source_sha256 = try a.dupe(u8, &digest_hex),
            .generated_asset = generated_asset,
            .selected = selected,
            .skipped = selection.units[id - 1].total -| selected,
            .bodies = bodies,
        };
    }
    const output = try std.json.Stringify.valueAlloc(a, .{
        .kind = "declaration-demand-inventory-v1",
        .entry = entry,
        .ablated = ablated,
        .original_entry_sha256 = original_entry_sha256,
        .effective_entry_sha256 = modules[loaded.entry - 1].source_sha256,
        .semantic_check = false,
        .lowering = false,
        .compilation = false,
        .module_count = loaded.units.items.len,
        .import_count = loaded.imports.items.len,
        .source_bytes = loaded.source_bytes,
        .asset_us = asset_us,
        .load_us = load_us,
        .plan_us = plan_us,
        .assets = .{
            .parsed = asset_candidate.stats.parsed,
            .reused = asset_candidate.stats.reused,
            .input_bytes = asset_candidate.stats.inputBytes,
            .generated_bytes = asset_candidate.stats.generatedBytes,
        },
        .plan = .{
            .total = selection.stats.total,
            .reached = selection.stats.reached,
            .fallback_units = selection.stats.fallback_units,
            .transitions = selection.stats.transitions,
        },
        .body_weights = .{
            .scope = "top_level_and_implementation_members",
            .original_modules = original_bodies,
            .generated_asset_modules = generated_bodies,
        },
        .modules = modules,
    }, .{});
    try Io.File.stdout().writeStreamingAll(io, output);
    try Io.File.stdout().writeStreamingAll(io, "\n");
}

const BodyCount = struct {
    declarations: usize = 0,
    selected: usize = 0,
    source_bytes: usize = 0,
    selected_source_bytes: usize = 0,

    fn add(self: *BodyCount, other: BodyCount) void {
        self.declarations += other.declarations;
        self.selected += other.selected;
        self.source_bytes += other.source_bytes;
        self.selected_source_bytes += other.selected_source_bytes;
    }
};

const BodyWeights = struct {
    lambda: BodyCount = .{},
    non_lambda: BodyCount = .{},

    fn add(self: *BodyWeights, other: BodyWeights) void {
        self.lambda.add(other.lambda);
        self.non_lambda.add(other.non_lambda);
    }
};

const ModuleReport = struct {
    path: []const u8,
    source_sha256: []const u8,
    generated_asset: bool,
    selected: usize,
    skipped: usize,
    bodies: BodyWeights,
};

fn isGeneratedAsset(path: []const u8, sources: []const inputs.overlays.Source) bool {
    for (sources) |source| if (std.mem.eql(u8, path, source.path)) return true;
    return false;
}

fn addBody(weights: *BodyWeights, tree: *const ast.Tree, source: []const u8, declaration: ast.Id, selected: bool) void {
    const body = tree.valueDecl(declaration).body;
    const span = tree.span(body);
    const start: usize = span.start;
    const end: usize = span.end;
    std.debug.assert(end <= source.len);
    const byte_count = end - start;
    var count: *BodyCount = undefined;
    if (tree.node(body).tag == .lambda) {
        count = &weights.lambda;
    } else {
        count = &weights.non_lambda;
    }
    count.declarations += 1;
    count.source_bytes += byte_count;
    if (selected) {
        count.selected += 1;
        count.selected_source_bytes += byte_count;
    }
}

fn arguments(args: []const []const u8) !struct { []const u8, []const u8, bool } {
    var root: []const u8 = "../gdev";
    var entry: []const u8 = "src/main.blot";
    var tiny = false;
    var positional: usize = 0;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--tiny-entry")) {
            tiny = true;
        } else if (positional == 0) {
            root = arg;
            positional += 1;
        } else if (positional == 1) {
            entry = arg;
            positional += 1;
        } else return error.InvalidArguments;
    }
    return .{ root, entry, tiny };
}

fn tinyEntrySource(a: A, source: []const u8) ![]u8 {
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var tree = try parser.parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);

    var body_start: usize = source.len;
    for (tree.roots.items) |root| {
        const tag = tree.node(root).tag;
        if (tag != .import_decl and tag != .export_decl) {
            body_start = tree.span(root).start;
            break;
        }
    }
    for (lexed.diagnostics.items) |issue| if (issue.start < body_start) return error.InvalidEntryImports;
    for (tree.diagnostics.items) |issue| if (issue.start < body_start) return error.InvalidEntryImports;

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(a);
    for (tree.roots.items) |root| {
        const tag = tree.node(root).tag;
        if (tag != .import_decl and tag != .export_decl) break;
        const span = tree.span(root);
        try output.appendSlice(a, source[span.start..span.end]);
        try output.append(a, '\n');
    }
    try output.appendSlice(a, "entry const main = func (value: U32) : U32 => return value\n");
    return output.toOwnedSlice(a);
}

fn sha256(source: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn objectField(value: std.json.Value, key: []const u8) std.json.Value {
    return value.object.get(key) orelse unreachable;
}

fn string(value: std.json.Value) []const u8 {
    return switch (value) {
        .string => |text| text,
        else => unreachable,
    };
}

fn absolute(a: A, root: []const u8, path: []const u8) ![]u8 {
    const joined = if (Io.Dir.path.isAbsolute(path)) try a.dupe(u8, path) else try Io.Dir.path.join(a, &.{ root, path });
    defer a.free(joined);
    return Io.Dir.path.resolveAlloc(a, &.{joined});
}

fn projectOptions(a: A, root: []const u8, settings: std.json.Value) !project.Options {
    const std_root = try absolute(a, root, string(objectField(settings, "std")));
    const imports = objectField(settings, "imports").object;
    const aliases = try a.alloc(project.Alias, imports.count());
    var iterator = imports.iterator();
    var index: usize = 0;
    while (iterator.next()) |item| : (index += 1) aliases[index] = .{
        .prefix = item.key_ptr.*,
        .root = try absolute(a, root, string(item.value_ptr.*)),
    };
    const prelude = try Io.Dir.path.join(a, &.{ std_root, "prelude.blot" });
    return .{ .prelude_path = prelude, .std_root = std_root, .aliases = aliases };
}

fn assetOptions(a: A, root: []const u8, settings: std.json.Value) !assets.Options {
    const native = objectField(settings, "nativeAssets");
    const roots_value = objectField(native, "roots").array.items;
    const roots = try a.alloc([]const u8, roots_value.len);
    for (roots_value, roots) |value, *path| path.* = try absolute(a, root, string(value));
    const imports_value = objectField(native, "imports").array.items;
    const imports = try a.alloc(assets.Definition, imports_value.len);
    for (imports_value, imports) |value, *definition| {
        const module = value.object.get("module") orelse unreachable;
        const path = value.object.get("path") orelse unreachable;
        const kind = value.object.get("kind") orelse unreachable;
        definition.* = .{
            .module = try absolute(a, root, string(module)),
            .path = try absolute(a, root, string(path)),
            .kind = std.meta.stringToEnum(assets.Kind, string(kind)) orelse return error.InvalidNativeAssetKind,
            .type = if (value.object.get("type")) |item| string(item) else null,
            .@"export" = if (value.object.get("export")) |item| string(item) else null,
            .mediaType = if (value.object.get("mediaType")) |item| string(item) else null,
        };
    }
    return .{ .roots = roots, .imports = imports };
}

fn now(io: Io) Io.Timestamp {
    return Io.Clock.awake.now(io);
}

fn elapsed(start: Io.Timestamp, io: Io) i64 {
    return start.durationTo(now(io)).toMicroseconds();
}
