//! One source-only query. Owned answers outlive its checker and input snapshot.
const std = @import("std");
const P = @import("project.zig");
const PC = @import("project_check.zig");
const C = @import("check.zig");
const T = @import("types.zig");
const inputs = @import("revision_inputs.zig");
const probes = @import("completion_probe.zig");
const fitting = @import("completion_fit.zig");
const ast = @import("ast.zig");
const Allocator = std.mem.Allocator;

pub const Item = struct {
    label: []const u8,
    insertText: []const u8,
    kind: enum { value, function, type, constructor, field, member, module },
    detail: ?[]const u8,
    match: fitting.Match,
    distance: u32,
    filename: []const u8,
    start: u32,

    pub fn jsonStringify(self: Item, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.write(.{ .label = self.label, .insertText = self.insertText, .kind = self.kind, .detail = self.detail, .match = self.match });
    }
    pub fn deinit(self: Item, a: Allocator) void {
        a.free(self.label);
        a.free(self.insertText);
        if (self.detail) |detail| a.free(detail);
        a.free(self.filename);
    }
};
pub const Diagnostic = struct {
    filename: []const u8,
    stage: []const u8 = "check",
    code: []const u8,
    start: u32,
    end: u32,
    message: []const u8,
    offset_encoding: []const u8 = "utf8_bytes",
    utf16: ?ast.Span = null,
    details: ?struct {
        hole: ?@import("hole_diagnostics.zig").Snapshot = null,
        explanation: ?@import("dispatch_explanation.zig").Explanation = null,
    } = null,

    pub fn deinit(self: Diagnostic, a: Allocator) void {
        a.free(self.filename);
        a.free(self.code);
        a.free(self.message);
        if (self.details) |details| {
            if (details.hole) |hole| hole.deinit(a);
            if (details.explanation) |explanation| explanation.deinit(a);
        }
    }
};
pub const Result = struct {
    replace: ast.Span,
    context: ?@import("hole_diagnostics.zig").Snapshot = null,
    items: []Item = &.{},
    diagnostics: []Diagnostic = &.{},
    truncated: bool = false,

    pub fn noteLimit(self: *Result, a: Allocator, filename: []const u8) !void {
        self.truncated = true;
        for (self.diagnostics) |issue| if (std.mem.eql(u8, issue.code, "completion_limit")) return;
        const issue = try diagnostic(a, filename, "completion_limit", "Completion result limit", self.replace, &self.truncated);
        errdefer issue.deinit(a);
        const kept: usize = @min(15, self.diagnostics.len);
        const diagnostics = try a.alloc(Diagnostic, kept + 1);
        diagnostics[0] = issue;
        @memcpy(diagnostics[1..], self.diagnostics[0..kept]);
        for (self.diagnostics[kept..]) |dropped| dropped.deinit(a);
        a.free(self.diagnostics);
        self.diagnostics = diagnostics;
    }

    pub fn deinit(self: Result, a: Allocator) void {
        if (self.context) |context| context.deinit(a);
        for (self.items) |item| item.deinit(a);
        a.free(self.items);
        for (self.diagnostics) |issue| issue.deinit(a);
        a.free(self.diagnostics);
    }
};

const Provider = struct {
    ordinary: P.InputProvider,
    filename: []const u8,
    replacement: ?[]const u8,

    fn canonical(context: *anyopaque, a: Allocator, io: std.Io, path: []const u8) anyerror![:0]u8 {
        const self: *Provider = @ptrCast(@alignCast(context));
        return self.ordinary.canonical(self.ordinary.context, a, io, path);
    }
    fn read(context: *anyopaque, a: Allocator, io: std.Io, path: []const u8, limit: usize) anyerror![]u8 {
        const self: *Provider = @ptrCast(@alignCast(context));
        if (self.replacement) |source| if (std.mem.eql(u8, self.filename, path)) {
            if (source.len > limit) return error.SourceLimit;
            return a.dupe(u8, source);
        };
        return self.ordinary.read(self.ordinary.context, a, io, path, limit);
    }
    fn resolve(context: *anyopaque, a: Allocator, source: []const u8, request: []const u8, options: P.Options) (Allocator.Error || error{InvalidPath})![]u8 {
        const self: *Provider = @ptrCast(@alignCast(context));
        return self.ordinary.resolve(self.ordinary.context, a, source, request, options);
    }
    fn view(self: *Provider) P.InputProvider {
        return .{ .context = self, .canonical = canonical, .read = read, .resolve = resolve };
    }
};

fn bounded(text: []const u8, limit: usize) []const u8 {
    var end = @min(text.len, limit);
    while (end != text.len and end != 0 and text[end] & 0xc0 == 0x80) end -= 1;
    return text[0..end];
}
fn earlier(_: void, left: Item, right: Item) bool {
    if (left.match != right.match) return @backingInt(left.match) < @backingInt(right.match);
    if (left.distance != right.distance) return left.distance < right.distance;
    const insertion = std.mem.order(u8, left.insertText, right.insertText);
    if (insertion != .eq) return insertion == .lt;
    if (left.kind != right.kind) return @backingInt(left.kind) < @backingInt(right.kind);
    const filename = std.mem.order(u8, left.filename, right.filename);
    if (filename != .eq) return filename == .lt;
    return left.start < right.start;
}

fn detailText(a: Allocator, loaded: *P.Project, checked: *C.Checked, name: C.EditorName, truncated: *bool) !?[]const u8 {
    if (name.ambiguous) return try a.dupe(u8, "ambiguous field/member");
    if (name.scheme.root == 0) return null;
    var adapter = .{ .allocator = a, .pool = &loaded.symbols, .types = &checked.types, .nominals = .{ .items = checked.nominals }, .contracts = .{ .items = checked.contracts }, .effect_templates = .{ .items = checked.effect_templates } };
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    const display = @import("type_display.zig");
    var visits: usize = 1024;
    display.appendBounded(&adapter, &text, name.scheme.root, &visits) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            truncated.* = true;
            return null;
        },
    };
    if (name.scheme.obligations.len != 0) {
        try text.appendSlice(a, " where {");
        const requirements = checked.obligations[name.scheme.obligations.start..][0..name.scheme.obligations.len];
        for (requirements[0..@min(32, requirements.len)], 0..) |requirement, index| {
            if (index != 0) try text.appendSlice(a, ", ");
            if (requirement.name != 0) try display.text(&adapter, &text, loaded.symbols.get(requirement.name));
            try text.append(a, ' ');
            display.appendBounded(&adapter, &text, requirement.ty, &visits) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => truncated.* = true,
            };
        }
        if (requirements.len > 32) truncated.* = true;
        try text.append(a, '}');
    }
    if (visits == 0) truncated.* = true;
    const slice = bounded(text.items, 1024);
    if (slice.len != text.items.len) truncated.* = true;
    return try a.dupe(u8, slice);
}
fn makeItem(a: Allocator, loaded: *P.Project, project_checked: *PC.CheckedProject, checked: *C.Checked, captured: C.EditorCapture, name: C.EditorName, prefix_kind: probes.Kind, budget: *fitting.Budget, truncated: *bool) !?Item {
    const text = loaded.symbols.get(name.name);
    if (text.len > 256) {
        truncated.* = true;
        return null;
    }
    var item: Item = .{ .label = try a.dupe(u8, text), .insertText = &.{}, .kind = @fromBackingInt(@intCast(@backingInt(name.kind))), .detail = null, .match = .unknown, .distance = name.distance, .filename = &.{}, .start = 0 };
    errdefer item.deinit(a);
    if (name.kind == .constructor and prefix_kind != .constructor) {
        if (text.len == 256) {
            truncated.* = true;
            item.deinit(a);
            return null;
        }
        item.insertText = try std.mem.concat(a, u8, &.{ "#", text });
    } else item.insertText = try a.dupe(u8, text);
    if (name.identity.unit != 0 and name.identity.unit <= loaded.units.items.len) {
        item.filename = try a.dupe(u8, loaded.filename(name.identity.unit));
        var declaration_ = name.identity.decl;
        if (declaration_ & T.opaque_name_bit != 0) {
            declaration_ = 0;
            if (name.identity.unit <= project_checked.modules.len) if (project_checked.modules[name.identity.unit - 1]) |module| {
                for (module.checked.nominals) |nominal| if (std.meta.eql(nominal.identity, name.identity)) {
                    declaration_ = nominal.declaration;
                    break;
                };
            };
        }
        if (name.external) |external| if (external.unit <= project_checked.modules.len) if (project_checked.modules[external.unit - 1]) |module| {
            declaration_ = module.checked.bindings[external.binding].declaration;
        };
        if (declaration_ != 0) item.start = loaded.unit(name.identity.unit).tree.span(declaration_).start;
    } else item.filename = try a.dupe(u8, "");
    item.detail = try detailText(a, loaded, checked, name, truncated);
    var expected = checked.expr_types[captured.node];
    if (name.receiver and captured.kind != .selector)
        expected = try checked.types.function(captured.receiver, expected);
    var enclosing: T.Scheme = .{};
    if (captured.owner != 0) enclosing = checked.bindings[captured.owner].scheme;
    item.match = try fitting.fit(a, &checked.types, expected, name.scheme, enclosing, checked.obligations, budget);
    if (name.ambiguous) item.match = .incompatible;
    return item;
}

fn diagnostic(a: Allocator, filename: []const u8, code: []const u8, message: []const u8, span: ast.Span, truncated: *bool) !Diagnostic {
    const text = bounded(message, 1024);
    if (text.len != message.len) truncated.* = true;
    const owned_filename = try a.dupe(u8, filename);
    errdefer a.free(owned_filename);
    const owned_code = try a.dupe(u8, code);
    errdefer a.free(owned_code);
    return .{ .filename = owned_filename, .code = owned_code, .message = try a.dupe(u8, text), .start = span.start, .end = span.end };
}
fn checkedDiagnostic(a: Allocator, filename: []const u8, issue: PC.Diagnostic, span: ast.Span, truncated: *bool) !Diagnostic {
    var owned = try diagnostic(a, filename, issue.codeName(), issue.message(), span, truncated);
    errdefer owned.deinit(a);
    if (issue.hole != null or issue.explanation != null) {
        owned.details = .{};
        if (issue.hole) |hole| owned.details.?.hole = try hole.clone(a);
        if (issue.explanation) |explanation| owned.details.?.explanation = try explanation.clone(a);
    }
    return owned;
}
fn publishDiagnostics(a: Allocator, result: *Result, diagnostics: *std.ArrayList(Diagnostic), target: []const u8) !void {
    if (result.truncated) {
        if (diagnostics.items.len == 16) diagnostics.pop().?.deinit(a);
        const owned = try diagnostic(a, target, "completion_limit", "Completion result limit", result.replace, &result.truncated);
        diagnostics.insert(a, 0, owned) catch |err| {
            owned.deinit(a);
            return err;
        };
    }
    result.diagnostics = try diagnostics.toOwnedSlice(a);
}

// Failed declarations never contribute binders. The parser retains complete
// roots, so fallback can use their spelling/scope without guessing any types.
const Lexical = struct {
    a: Allocator,
    loaded: *P.Project,
    unit: u32,
    probe: probes.Probe,
    items: std.ArrayList(Item) = .empty,
    visits: usize = 0,
    truncated: *bool,

    fn add(self: *Lexical, symbol: u32, kind: @FieldType(Item, "kind"), node: u32, distance: u32) !void {
        if (symbol == 0) return;
        const name = self.loaded.symbols.get(symbol);
        if (!std.mem.startsWith(u8, name, self.probe.prefix)) return;
        if (name.len > 256 or (kind == .constructor and self.probe.kind != .constructor and name.len == 256)) {
            self.truncated.* = true;
            return;
        }
        for (self.items.items, 0..) |old, index| if (std.mem.eql(u8, old.label, name)) {
            if (old.distance <= distance) return;
            self.items.orderedRemove(index).deinit(self.a);
            break;
        };
        if (self.items.items.len == 4096) {
            self.truncated.* = true;
            return;
        }
        var item: Item = .{ .label = try self.a.dupe(u8, name), .insertText = &.{}, .kind = kind, .detail = null, .match = .unknown, .distance = distance, .filename = &.{}, .start = self.loaded.unit(self.unit).tree.span(node).start };
        errdefer item.deinit(self.a);
        if (kind == .constructor and self.probe.kind != .constructor) item.insertText = try std.mem.concat(self.a, u8, &.{ "#", name }) else item.insertText = try self.a.dupe(u8, name);
        item.filename = try self.a.dupe(u8, self.loaded.filename(self.unit));
        try self.items.append(self.a, item);
    }
    fn contains(self: *Lexical, node: u32) bool {
        if (node == 0) return false;
        const span = self.loaded.unit(self.unit).tree.span(node);
        return span.start <= self.probe.marker.start and self.probe.marker.end <= span.end;
    }
    fn pattern(self: *Lexical, id: u32, distance: u32, depth: usize) !void {
        if (id == 0) return;
        if (depth > 32 or self.visits == 4096) {
            self.truncated.* = true;
            return;
        }
        self.visits += 1;
        const tree = &self.loaded.unit(self.unit).tree;
        const node = tree.node(id);
        if (node.tag == .pattern_name) try self.add(node.a, .value, id, distance);
        if (node.tag == .pattern_field) try self.pattern(node.b, distance, depth + 1);
        if (node.tag == .pattern_constructor) try self.pattern(node.b, distance, depth + 1);
        for (tree.children(id)) |child| try self.pattern(child, distance, depth + 1);
    }
    fn scope(self: *Lexical, id: u32, depth: usize) !void {
        if (!self.contains(id)) return;
        if (depth > 32 or self.visits == 4096) {
            self.truncated.* = true;
            return;
        }
        self.visits += 1;
        const tree = &self.loaded.unit(self.unit).tree;
        const node = tree.node(id);
        const distance: u32 = @intCast(64 - depth);
        switch (node.tag) {
            .lambda => {
                if (self.contains(node.b)) try self.add(tree.parameter(node.a).name, .value, node.a, distance);
                try self.scope(node.b, depth + 1);
            },
            .block => {
                for (tree.children(id)) |child| {
                    const statement = tree.node(child);
                    if (tree.span(child).end <= self.probe.marker.start and statement.tag == .let_stmt)
                        try self.pattern(statement.a, distance, 0);
                    try self.scope(child, depth + 1);
                }
            },
            .let_stmt, .rebind_stmt, .unary => try self.scope(node.b, depth + 1),
            .return_stmt, .yield_stmt, .group, .field => try self.scope(node.a, depth + 1),
            .apply, .field_access, .index_access => {
                try self.scope(node.a, depth + 1);
                if (node.tag != .field_access) try self.scope(node.b, depth + 1);
            },
            .binary => {
                try self.scope(node.b, depth + 1);
                try self.scope(node.c, depth + 1);
            },
            .if_expr => {
                try self.scope(node.a, depth + 1);
                try self.scope(node.b, depth + 1);
                try self.scope(node.c, depth + 1);
            },
            else => for (tree.children(id)) |child| try self.scope(child, depth + 1),
        }
    }
};
fn lexicalFallback(a: Allocator, loaded: *P.Project, unit: u32, probe: probes.Probe, result: *Result) !void {
    if (probe.kind == .member or probe.kind == .selector or probe.kind == .intrinsic) return;
    var collector: Lexical = .{ .a = a, .loaded = loaded, .unit = unit, .probe = probe, .truncated = &result.truncated };
    defer {
        for (collector.items.items) |item| item.deinit(a);
        collector.items.deinit(a);
    }
    var cutoff: u32 = std.math.maxInt(u32);
    for (loaded.diagnostics.items) |issue| if (issue.unit == unit) {
        var start = issue.span.start;
        if (issue.parse_detail) |detail| if (detail.declaration_origin) |origin| {
            start = origin.start;
        };
        cutoff = @min(cutoff, start);
    };
    const tree = &loaded.unit(unit).tree;
    for (tree.roots.items) |root| {
        if (tree.span(root).end > cutoff) continue;
        const node = tree.node(root);
        if (probe.kind == .expression and node.tag == .value_decl) {
            var kind: @FieldType(Item, "kind") = .value;
            if (tree.node(node.b).tag == .lambda) kind = .function;
            try collector.add(node.a, kind, root, 1_000_000);
            try collector.scope(node.b, 0);
        }
        if (probe.kind == .type_ and (node.tag == .data_decl or node.tag == .type_alias_decl or node.tag == .contract_decl)) try collector.add(node.a, .type, root, 1_000_000);
        if ((probe.kind == .expression or probe.kind == .constructor) and node.tag == .data_decl)
            for (tree.children(node.b)) |constructor| {
                try collector.add(tree.node(constructor).a, .constructor, constructor, 1_000_000);
            };
        if (probe.kind == .expression and node.tag == .import_decl) {
            const import = tree.importDecl(root);
            try collector.add(import.namespace, .module, root, 1_000_001);
            for (tree.list(import.bindings)) |binding| try collector.add(tree.importBinding(binding).alias, .value, binding, 1_000_001);
        }
    }
    std.mem.sort(Item, collector.items.items, {}, earlier);
    if (collector.items.items.len > 128) {
        for (collector.items.items[128..]) |item| item.deinit(a);
        collector.items.items.len = 128;
        result.truncated = true;
    }
    result.items = try collector.items.toOwnedSlice(a);
}

pub fn query(a: Allocator, io: std.Io, entry: []const u8, snapshot: *inputs.Snapshot, filename: []const u8, position: u32) !Result {
    const target = snapshot.canonical(io, filename) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.MissingSource,
    };
    const original = snapshot.read(io, target) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SourceLimit, error.FileTooBig => return error.SourceLimit,
        else => return error.MissingSource,
    };
    const probe = try probes.capture(a, original, position);
    defer if (probe) |value| value.deinit(a);
    var provider: Provider = .{ .ordinary = snapshot.provider(), .filename = target, .replacement = null };
    if (probe) |value| provider.replacement = value.source;
    var loaded = try P.loadWithInputs(a, io, entry, snapshot.options, provider.view());
    defer loaded.deinit(a);
    var unit: u32 = 0;
    for (loaded.units.items, 1..) |_, index| if (std.mem.eql(u8, loaded.filename(@intCast(index)), target)) {
        unit = @intCast(index);
        break;
    };
    if (unit == 0) return error.InvalidCompletion;
    for (loaded.diagnostics.items) |issue| if (issue.code == .source_limit or issue.code == .file_limit) return error.SourceLimit;
    // Membership still applies in text tokens; syntax errors stay invisible.
    if (probe == null) return .{ .replace = .{ .start = position, .end = position } };
    var result: Result = .{ .replace = .{ .start = position, .end = position } };
    errdefer result.deinit(a);
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    defer {
        for (diagnostics.items) |issue| issue.deinit(a);
        diagnostics.deinit(a);
    }
    for (loaded.diagnostics.items) |issue| {
        if (diagnostics.items.len == 16) {
            result.truncated = true;
            break;
        }
        var span = issue.span;
        if (issue.unit == unit) if (probe) |value| {
            span = value.originalSpan(span);
        };
        var path = target;
        if (issue.unit != 0) path = loaded.filename(issue.unit);
        const owned = try diagnostic(a, path, issue.codeName(), issue.message(), span, &result.truncated);
        diagnostics.append(a, owned) catch |err| {
            owned.deinit(a);
            return err;
        };
    }
    if (probe) |value| {
        result.replace = value.replace;
        if (loaded.diagnostics.items.len != 0) {
            try lexicalFallback(a, &loaded, unit, value, &result);
            try publishDiagnostics(a, &result, &diagnostics, target);
            return result;
        }
        var budget: fitting.Budget = .{};
        // This query owns the pool. Checking only borrows it, so seed legal
        // implicit names here with its owner allocator, before any inference.
        _ = try loaded.symbols.intern(a, "self");
        for (@import("completion_names.zig").builtin_types) |name| _ = try loaded.symbols.intern(a, name);
        var checked = try PC.checkProjectForEditor(a, &loaded, .{ .unit = unit, .marker = .{ .span = value.marker, .kind = value.kind, .prefix = value.prefix }, .budget = &budget });
        defer checked.deinit(a);
        for (checked.diagnostics) |issue| {
            if (diagnostics.items.len == 16) {
                result.truncated = true;
                break;
            }
            var span = issue.span;
            if (issue.unit == unit) span = value.originalSpan(span);
            const owned = try checkedDiagnostic(a, loaded.filename(issue.unit), issue, span, &result.truncated);
            diagnostics.append(a, owned) catch |err| {
                owned.deinit(a);
                return err;
            };
        }
        if (unit <= checked.modules.len) if (checked.modules[unit - 1]) |*module| if (module.checked.editor) |captured| {
            if (captured.context) |context| {
                result.context = try context.clone(a);
                result.truncated = result.truncated or context.truncated;
            }
            result.truncated = result.truncated or captured.truncated;
            var items: std.ArrayList(Item) = .empty;
            defer {
                for (items.items) |item| item.deinit(a);
                items.deinit(a);
            }
            for (captured.names) |name| {
                if (try makeItem(a, &loaded, &checked, &module.checked, captured, name, value.kind, &budget, &result.truncated)) |item|
                    items.append(a, item) catch |err| {
                        item.deinit(a);
                        return err;
                    };
            }
            std.mem.sort(Item, items.items, {}, earlier);
            if (items.items.len > 128) {
                for (items.items[128..]) |item| item.deinit(a);
                items.items.len = 128;
                result.truncated = true;
            }
            result.items = try items.toOwnedSlice(a);
        };
        result.truncated = result.truncated or budget.exhausted;
    }
    try publishDiagnostics(a, &result, &diagnostics, target);
    return result;
}

fn queryLaw(a: Allocator) !void {
    var snapshot = try inputs.Snapshot.initWithSources(a, std.testing.io, .{}, &.{
        .{ .path = "/editor/main.blot", .contents = "import * as lib from \"./library\"\nconst work = fn (value: F32) -> F32 => val\n" },
        .{ .path = "/editor/library.blot", .contents = "const hidden = 99\n" },
    });
    defer snapshot.deinit();
    const source = snapshot.sources.?.files.get("/editor/main.blot").?.?;
    const result = try query(a, std.testing.io, "/editor/main.blot", &snapshot, "/editor/main.blot", @intCast(std.mem.findLast(u8, source, "val").? + 3));
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqualStrings("value", result.items[0].insertText);
    try std.testing.expectEqual(fitting.Match.exact, result.items[0].match);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}
test "editor completion query owns answers and preserves semantic visibility through every allocation failure" {
    try queryLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, queryLaw, .{});
}

fn find(result: Result, insertion: []const u8) ?Item {
    for (result.items) |item| if (std.mem.eql(u8, item.insertText, insertion)) return item;
    return null;
}
test "editor completion follows named aliases namespace boundaries fields constructors and types" {
    const a = std.testing.allocator;
    const cases = [_]struct { text: []const u8, offered: []const u8, absent: []const u8, match: fitting.Match }{
        .{ .text = "import { value as renamed } from \"./library\"\nconst work = fn () -> F32 => ren", .offered = "renamed", .absent = "value", .match = .exact },
        .{ .text = "import * as lib from \"./library\"\nconst work = fn () -> F32 => lib.", .offered = "value", .absent = "lib", .match = .exact },
        .{ .text = "type Point = { x: U32, y: F32 }\nconst work = fn (point: Point) -> F32 => point.", .offered = "y", .absent = "point", .match = .exact },
        .{ .text = "import * as lib from \"./library\"\nconst work: lib.Choice = #lib.", .offered = "Chosen", .absent = "#Chosen", .match = .exact },
        .{ .text = "const work: F = 1.0", .offered = "F32", .absent = "#False", .match = .exact },
        .{ .text = "type U32 = F32\nconst work: U = 1", .offered = "U32", .absent = "#False", .match = .exact },
    };
    for (cases) |case| {
        var snapshot = try inputs.Snapshot.initWithSources(a, std.testing.io, .{}, &.{
            .{ .path = "/editor/main.blot", .contents = case.text },
            .{ .path = "/editor/library.blot", .contents = "const value = 1.0\ntype Choice is data = #Chosen | #Other\n" },
        });
        defer snapshot.deinit();
        var position: u32 = @intCast(case.text.len);
        if (std.mem.eql(u8, case.offered, "F32")) position = @intCast(std.mem.find(u8, case.text, "F").? + 1);
        if (std.mem.eql(u8, case.offered, "U32")) position = @intCast(std.mem.findLast(u8, case.text, "U").? + 1);
        const result = try query(a, std.testing.io, "/editor/main.blot", &snapshot, "/editor/main.blot", position);
        defer result.deinit(a);
        const item = find(result, case.offered) orelse return error.MissingCompletion;
        try std.testing.expectEqual(case.match, item.match);
        try std.testing.expect(find(result, case.absent) == null);
        try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    }
}

test "module abstraction completion keeps source origins without exposing constructors or fields" {
    const a = std.testing.allocator;
    const library = "opaque type Token = { secret: U32 }\nprivate const hidden = 7\nconst make = fn value => #Token { secret: value }\n";
    for ([_][]const u8{
        "import * as lib from \"./library\"\nconst work = lib.",
        "import {Token} from \"./library\"\nconst work = fn (value: Token) => value.",
        "opaque type Token = U32\nconst work = To",
    }, 0..) |text, index| {
        var snapshot = try inputs.Snapshot.initWithSources(a, std.testing.io, .{}, &.{
            .{ .path = "/editor/main.blot", .contents = text },
            .{ .path = "/editor/library.blot", .contents = library },
        });
        defer snapshot.deinit();
        const result = try query(a, std.testing.io, "/editor/main.blot", &snapshot, "/editor/main.blot", @intCast(text.len));
        defer result.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
        try std.testing.expect(find(result, "hidden") == null);
        try std.testing.expect(find(result, "secret") == null);
        if (index < 2) try std.testing.expect(find(result, "#Token") == null);
        if (index != 1) {
            const item = find(result, "Token") orelse return error.MissingCompletion;
            var filename: []const u8 = "/editor/library.blot";
            if (index == 2) filename = "/editor/main.blot";
            try std.testing.expectEqualStrings(filename, item.filename);
            try std.testing.expect(item.start < library.len);
        }
    }
}

fn limitLaw(a: Allocator) !void {
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    defer {
        for (diagnostics.items) |issue| issue.deinit(a);
        diagnostics.deinit(a);
    }
    var result: Result = .{ .replace = .{ .start = 4, .end = 4 } };
    defer result.deinit(a);
    for (0..16) |_| {
        const issue = try diagnostic(a, "/editor/main.blot", "syntax", "Original diagnostic", result.replace, &result.truncated);
        diagnostics.append(a, issue) catch |err| {
            issue.deinit(a);
            return err;
        };
    }
    result.diagnostics = try diagnostics.toOwnedSlice(a);
    try result.noteLimit(a, "/editor/main.blot");
    try result.noteLimit(a, "/editor/main.blot");
    try std.testing.expect(result.truncated);
    try std.testing.expectEqual(@as(usize, 16), result.diagnostics.len);
    try std.testing.expectEqualStrings("completion_limit", result.diagnostics[0].code);
    for (result.diagnostics[1..]) |issue| try std.testing.expectEqualStrings("syntax", issue.code);
}
test "completion metadata limits preserve one limit diagnostic with allocation-safe ownership" {
    try limitLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, limitLaw, .{});
}

fn lexicalLaw(a: Allocator) !void {
    const text = "const good = 42\nconst bad = (\nconst invented = 3\nconst work = goo";
    var snapshot = try inputs.Snapshot.initWithSources(a, std.testing.io, .{}, &.{.{ .path = "/editor/main.blot", .contents = text }});
    defer snapshot.deinit();
    const result = try query(a, std.testing.io, "/editor/main.blot", &snapshot, "/editor/main.blot", @intCast(text.len));
    defer result.deinit(a);
    try std.testing.expect(result.context == null);
    try std.testing.expect(result.diagnostics.len != 0);
    const item = find(result, "good") orelse return error.MissingLexicalCompletion;
    try std.testing.expectEqual(fitting.Match.unknown, item.match);
    try std.testing.expect(find(result, "invented") == null);
}
test "editor lexical fallback owns only well-formed binders before the first error under allocation failure" {
    try lexicalLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, lexicalLaw, .{});
}
test "editor ignores comments and strings even when the surrounding source is malformed" {
    const a = std.testing.allocator;
    const cases = [_][]const u8{ "const bad = (\n// cursor", "const bad = \"cursor" };
    for (cases) |text| {
        var snapshot = try inputs.Snapshot.initWithSources(a, std.testing.io, .{}, &.{.{ .path = "/editor/main.blot", .contents = text }});
        defer snapshot.deinit();
        const result = try query(a, std.testing.io, "/editor/main.blot", &snapshot, "/editor/main.blot", @intCast(text.len));
        defer result.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), result.items.len);
        try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
        try std.testing.expectEqual(ast.Span{ .start = @intCast(text.len), .end = @intCast(text.len) }, result.replace);
    }
}

test "editor text-token queries still enforce opened project membership" {
    const a = std.testing.allocator;
    var snapshot = try inputs.Snapshot.initWithSources(a, std.testing.io, .{}, &.{
        .{ .path = "/editor/main.blot", .contents = "const value = 42" },
        .{ .path = "/editor/other.blot", .contents = "// text" },
    });
    defer snapshot.deinit();
    try std.testing.expectError(error.InvalidCompletion, query(a, std.testing.io, "/editor/main.blot", &snapshot, "/editor/other.blot", 7));
}

fn selfLaw(a: Allocator) !void {
    const text = "const work = fn (value: U32) => do:\n  value := @hole";
    var snapshot = try inputs.Snapshot.initWithSources(a, std.testing.io, .{}, &.{.{ .path = "/editor/main.blot", .contents = text }});
    defer snapshot.deinit();
    const result = try query(a, std.testing.io, "/editor/main.blot", &snapshot, "/editor/main.blot", @intCast(text.len));
    defer result.deinit(a);
    const context = result.context orelse return error.MissingContext;
    for ([_][]const u8{ "self", "value" }) |name| {
        const item = find(result, name) orelse return error.MissingAlias;
        try std.testing.expectEqualStrings("U32", item.detail.?);
        var found = false;
        for (context.scope) |binding| if (std.mem.eql(u8, binding.name, name)) {
            found = true;
            try std.testing.expectEqual(.u32, context.nodes[binding.type].kind);
        };
        try std.testing.expect(found);
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}
test "editor rebinding aliases retain their actual names and old types under allocation failure" {
    try selfLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, selfLaw, .{});
}
