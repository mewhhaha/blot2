//! Fresh consumer checking from a previously loaded principal dependency.
//! The dependency owns source-free Core; no source body is checked again.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const D = @import("frozen_dependency.zig");
const Allocator = std.mem.Allocator;
const syntax = @import("syntax_diagnostics.zig");
const token = @import("token.zig");

pub const Stats = struct { syntax_nodes: usize, body_elaborations: usize, body_lowerings: usize, imported_schemes: usize };
/// Failure metadata is snapped while frontend owners are live. JSON details
/// contain the actual evidence, independently owned after frontend teardown.
pub const Publication = struct {
    utf16: ?ast.Span,
    cause: syntax.Cause,
    expected_token: ?token.Tag,
    actual_token: ?token.Tag,
    details_json: []u8,
};
pub const Details = struct {
    bytes: []const u8,
    pub fn jsonStringify(self: Details, writer: anytype) !void {
        // These bytes are produced only by std.json.Stringify.valueAlloc.
        // They are not untrusted source text or artifact wire contents.
        try writer.print("{s}", .{self.bytes});
    }
};
pub const Diagnostic = struct {
    stage: []const u8,
    unit: u32,
    code: []u8,
    start: u32,
    end: u32,
    message: []u8,
    publication: ?Publication = null,
    pub fn init(allocator: Allocator, unit: u32, stage: []const u8, code: []const u8, span: ast.Span, message: []const u8) !Diagnostic {
        const owned_code = try allocator.dupe(u8, code);
        errdefer allocator.free(owned_code);
        return .{ .stage = stage, .unit = unit, .code = owned_code, .start = span.start, .end = span.end, .message = try allocator.dupe(u8, message) };
    }
    pub fn deinit(self: *Diagnostic, allocator: Allocator) void {
        if (self.publication) |published| allocator.free(published.details_json);
        allocator.free(self.code);
        allocator.free(self.message);
        self.* = undefined;
    }
    pub fn write(self: *const Diagnostic, writer: *std.Io.Writer, filename: []const u8) !void {
        if (self.publication) |published| {
            try std.json.Stringify.value(.{ .kind = "diagnostic", .filename = filename, .stage = self.stage, .code = self.code, .start = self.start, .end = self.end, .message = self.message, .offset_encoding = "utf8_bytes", .utf16 = published.utf16, .cause = published.cause, .expected_token = published.expected_token, .actual_token = published.actual_token, .details = Details{ .bytes = published.details_json } }, .{}, writer);
        } else {
            try std.json.Stringify.value(.{ .kind = "diagnostic", .filename = filename, .stage = self.stage, .unit = self.unit, .code = self.code, .start = self.start, .end = self.end, .message = self.message }, .{}, writer);
        }
        try writer.writeByte('\n');
    }
};
pub fn publishedDiagnostic(allocator: Allocator, unit: u32, stage: []const u8, source: []const u8, publication: syntax.Publication, details: anytype) !Diagnostic {
    var result = try Diagnostic.init(allocator, unit, stage, publication.code, publication.span, publication.message);
    errdefer result.deinit(allocator);
    // Publish the optional payload only after all fallible ownership exists.
    const details_json = try std.json.Stringify.valueAlloc(allocator, details, .{});
    result.publication = .{ .utf16 = publication.utf16(source), .cause = publication.cause, .expected_token = publication.expected_token, .actual_token = publication.actual_token, .details_json = details_json };
    return result;
}
pub const Result = struct {
    compiled: backend.Result,
    stats: Stats,
    diagnostic: ?Diagnostic = null,
    pub fn deinit(self: *Result, allocator: Allocator) void {
        self.compiled.deinit(allocator);
        if (self.diagnostic) |*item| item.deinit(allocator);
        self.* = undefined;
    }
};
fn rejected(allocator: Allocator, stage: []const u8, code: []const u8, span: ast.Span, message: []const u8) !Result {
    const diagnostic = try Diagnostic.init(allocator, 1, stage, code, span, message);
    const stats: Stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 };
    return .{ .compiled = .{}, .stats = stats, .diagnostic = diagnostic };
}

/// First useful no-import application gate. Dependency unit2 and fresh entry
/// unit1 are explicitly selected by the loader, independent of artifact IDs.
pub fn compile(allocator: Allocator, source: []const u8, pool: *symbols.Pool, dependency: *const D.Module) !Result {
    if (dependency.core.unit != 2 or dependency.interface.unit != 2) return error.InvalidArtifact;
    var inherited: std.ArrayList(parser.InheritedFixity) = .empty;
    defer inherited.deinit(allocator);
    for (dependency.fixities) |value| try inherited.append(allocator, .{ .operator = value.operator, .precedence = value.precedence, .association = value.association, .named = value.named });
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    if (tokens.diagnostics.items.len != 0) {
        const item = tokens.diagnostics.items[0];
        return .{ .compiled = .{}, .stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 }, .diagnostic = try publishedDiagnostic(allocator, 1, "parse-project", source, syntax.lexical(tokens.tokens.items, item), tokens.diagnostics.items) };
    }
    var tree = try parser.parseWithFixities(allocator, source, tokens.tokens.items, pool, inherited.items);
    defer tree.deinit(allocator);
    if (tree.diagnostics.items.len != 0) {
        const item = tree.diagnostics.items[0];
        return .{ .compiled = .{}, .stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 }, .diagnostic = try publishedDiagnostic(allocator, 1, "parse-project", source, try syntax.parse(allocator, tokens.tokens.items, item), tree.diagnostics.items) };
    }
    var occupied: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer occupied.deinit(allocator);
    for (tree.roots.items) |id| {
        const node = tree.node(id);
        switch (node.tag) {
            .import_decl => return error.ImportedConsumerUnsupported,
            .value_decl, .data_decl, .effect_type_decl, .effect_decl => try occupied.put(allocator, node.a, {}),
            else => {},
        }
        if (node.tag == .data_decl) for (tree.children(node.b)) |constructor| try occupied.put(allocator, tree.node(constructor).a, {});
    }
    var imports: std.ArrayList(check.ImportedBinding) = .empty;
    defer imports.deinit(allocator);
    var catalogs: std.ArrayList(check.ImportedCatalog) = .empty;
    defer catalogs.deinit(allocator);
    var checked_fixities: std.ArrayList(check.ImportedFixity) = .empty;
    defer checked_fixities.deinit(allocator);
    try catalogs.append(allocator, .{ .frozen = &dependency.interface, .kind = .catalog, .index = 0, .origin = 0 });
    for (dependency.exports) |exported| {
        if (occupied.contains(exported.name)) continue;
        if (exported.kind == .value) {
            const definition = dependency.interface.bindings[exported.target.binding];
            try imports.append(allocator, .{ .name = exported.name, .target = exported.target, .origin = 0, .interface = .{ .types = .{ .frozen = &dependency.interface.graph }, .scheme = definition.scheme, .obligations = dependency.interface.obligations, .named_function = definition.named_function, .callees = .{ .frozen = &dependency.interface } } });
        } else try catalogs.append(allocator, .{ .frozen = &dependency.interface, .name = exported.name, .kind = switch (exported.kind) {
            .nominal => .nominal,
            .constructor => .constructor,
            .effect_family => .effect_family,
            .contract => .contract,
            .value => unreachable,
        }, .index = exported.catalog, .origin = 0 });
    }
    for (dependency.fixities) |value| {
        if (!value.named) {
            const definition = dependency.interface.bindings[value.producer.binding];
            try imports.append(allocator, .{ .expose = false, .target = value.producer, .origin = 0, .interface = .{ .types = .{ .frozen = &dependency.interface.graph }, .scheme = definition.scheme, .obligations = dependency.interface.obligations, .named_function = definition.named_function, .callees = .{ .frozen = &dependency.interface } } });
        }
        try checked_fixities.append(allocator, .{ .operator = value.operator, .target = value.target, .named = value.named, .external = if (value.named) null else value.producer });
    }
    var checked = try check.checkModuleWithOptions(allocator, &tree, pool, imports.items, catalogs.items, 1, .{ .prelude_unit = 2, .inherited_fixities = checked_fixities.items });
    defer checked.deinit(allocator);
    if (checked.diagnostics.len != 0) {
        const item = checked.diagnostics[0];
        if (item.hole) |hole| return .{ .compiled = .{}, .stats = .{ .syntax_nodes = tree.nodes.items.len - 1, .body_elaborations = checked.body_elaborations, .body_lowerings = 0, .imported_schemes = checked.imported_schemes }, .diagnostic = try publishedDiagnostic(allocator, 1, "check", source, .{ .cause = .native_detail, .code = @tagName(item.code), .span = item.span, .message = item.message() }, .{ .hole = hole }) };
        if (item.symbol == 0) return rejected(allocator, "check", @tagName(item.code), item.span, item.message());
        const message = try allocator.print("{s}{s}{s}", .{ item.message(), if (item.code == .unknown_intrinsic or item.code == .unknown_record_field) " " else ": ", pool.get(item.symbol) });
        defer allocator.free(message);
        return rejected(allocator, "check", @tagName(item.code), item.span, message);
    }
    var ir = try core.lower(allocator, &tree, pool, &checked);
    defer ir.deinit(allocator);
    // Unit0 in fresh Core denotes its containing module (the first backend
    // table here); its actual nominal producers already carry checker unit1.
    if (ir.diagnostics.len != 0) {
        const item = ir.diagnostics[0];
        return rejected(allocator, "lower", @tagName(item.code), item.span, item.message());
    }
    const elaborations: usize = checked.body_elaborations;
    const lowerings: usize = ir.body_lowerings;
    const imported_schemes: usize = checked.imported_schemes;
    const stats: Stats = .{ .syntax_nodes = tree.nodes.items.len - 1, .body_elaborations = elaborations, .body_lowerings = lowerings, .imported_schemes = imported_schemes };
    return .{ .compiled = try backend.compile(allocator, &.{ ir, dependency.core }, 1), .stats = stats };
}
