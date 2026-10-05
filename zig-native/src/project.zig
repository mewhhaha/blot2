//! Source-loading validation only. Units retain separate immutable syntax;
//! imports carry numeric module/declaration references, never rewritten names.
const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const syntax_diagnostics = @import("syntax_diagnostics.zig");
const symbol = @import("symbols.zig");
const D = @import("frozen_dependency.zig");
const relink = @import("dependency_relink.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const UnitId = u32;
pub const DeclarationId = struct { unit: UnitId, node: ast.Id };
pub const Range = struct { start: u32 = 0, len: u32 = 0 };
pub const Alias = struct { prefix: []const u8, root: []const u8 };
pub const InputMode = enum { project, source };
pub const Options = struct {
    input_mode: InputMode = .project,
    prelude_path: ?[]const u8 = null,
    std_root: ?[]const u8 = null,
    aliases: []const Alias = &.{},
    max_source_bytes: usize = 16 * 1024 * 1024,
    max_total_source_bytes: usize = 64 * 1024 * 1024,
    max_files: usize = 4096,
};

pub const Code = enum {
    import_path,
    missing_file,
    import_cycle,
    duplicate_alias,
    invalid_alias,
    source_limit,
    file_limit,
    io_error,
    lexical_error,
    syntax_error,
    invalid_prelude,
};
pub const Diagnostic = struct {
    unit: UnitId,
    span: ast.Span,
    code: Code,
    target: symbol.Symbol = 0,
    cause: ?anyerror = null,
    lex_code: ?lexer.Code = null,
    parse_code: ?ast.Code = null,
    publication: ?syntax_diagnostics.Publication = null,
    parse_detail: ?ast.Diagnostic = null,
    lexical_details: []lexer.Diagnostic = &.{},

    pub fn codeName(self: Diagnostic) []const u8 {
        if (self.lex_code) |code| return @tagName(code);
        if (self.parse_code) |code| return @tagName(code);
        return @tagName(self.code);
    }
    pub fn message(self: Diagnostic) []const u8 {
        if (self.lex_code) |code| return (lexer.Diagnostic{ .code = code, .start = self.span.start, .end = self.span.end }).message();
        if (self.parse_code) |code| return (ast.Diagnostic{ .code = code, .start = self.span.start, .end = self.span.end }).message();
        return switch (self.code) {
            .import_path => "Import requires a relative path or an explicitly configured directory alias",
            .missing_file => "Imported source file does not exist",
            .import_cycle => "Source import cycle",
            .duplicate_alias => "Import aliases must have distinct names",
            .invalid_alias => "Directory aliases need a nonempty prefix ending in '/' and a local root",
            .source_limit => "Project source byte budget exceeded",
            .file_limit => "Project source file budget exceeded",
            .io_error => "Unable to read source file",
            .lexical_error => "Invalid source token",
            .syntax_error => "Invalid source syntax",
            .invalid_prelude => "Prelude requires a nonempty local source path",
        };
    }
};

pub const Import = struct {
    declaration: DeclarationId,
    target: UnitId = 0,
    path: symbol.Symbol,
    namespace: symbol.Symbol,
    bindings: ast.List,
    span: ast.Span,
};
pub const Unit = struct {
    filename: symbol.Symbol,
    source: []const u8,
    tree: ast.Tree,
    imports: Range = .{},
    implicit_prelude: bool = false,

    fn deinit(self: *Unit, allocator: Allocator) void {
        self.tree.deinit(allocator);
        allocator.free(self.source);
    }
};

pub const Project = struct {
    input_mode: InputMode = .project,
    /// Borrowed, admitted module owners. Their dense unit IDs occupy the prefix.
    /// The bundle must outlive project checking/lowering; no syntax is recreated.
    compiled_modules: []const D.Module = &.{},
    /// Borrowed per-slot validity for a transactional mixed frontend.
    compiled_reuse: []const bool = &.{},
    symbols: symbol.Pool = .{},
    units: std.ArrayList(Unit) = .empty,
    order: std.ArrayList(UnitId) = .empty,
    imports: std.ArrayList(Import) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    entry: UnitId = 0,
    prelude_unit: UnitId = 0,
    source_bytes: usize = 0,

    pub fn deinit(self: *Project, allocator: Allocator) void {
        for (self.units.items) |*unit_| unit_.deinit(allocator);
        self.units.deinit(allocator);
        self.order.deinit(allocator);
        self.imports.deinit(allocator);
        for (self.diagnostics.items) |item| allocator.free(item.lexical_details);
        self.diagnostics.deinit(allocator);
        self.symbols.deinit(allocator);
        self.* = .{};
    }
    pub fn compiledModule(self: *const Project, id: usize) ?*const D.Module {
        if (id == 0 or id > self.compiled_modules.len) return null;
        if (self.compiled_reuse.len != 0 and !self.compiled_reuse[id - 1]) return null;
        return &self.compiled_modules[id - 1];
    }
    pub fn compiledCount(self: *const Project) usize {
        if (self.compiled_reuse.len == 0) return self.compiled_modules.len;
        var count: usize = 0;
        for (self.compiled_reuse) |reuse| count += @intFromBool(reuse);
        return count;
    }
    pub fn unit(self: *const Project, id: UnitId) *const Unit {
        std.debug.assert(id != 0);
        return &self.units.items[id - 1];
    }
    pub fn filename(self: *const Project, id: UnitId) []const u8 {
        return self.symbols.get(self.unit(id).filename);
    }
    pub fn unitImports(self: *const Project, id: UnitId) []const Import {
        const range = self.unit(id).imports;
        return self.imports.items[range.start..][0..range.len];
    }
    pub fn declaration(self: *const Project, id: DeclarationId) ast.Node {
        return self.unit(id.unit).tree.node(id.node);
    }
    pub fn declarationSpan(self: *const Project, id: DeclarationId) ast.Span {
        return self.unit(id.unit).tree.span(id.node);
    }
};

/// A candidate-owned source provider. Each returned slice belongs to the loader;
/// a provider may retain its own independent immutable copy for validation.
/// Import resolution remains pure; filesystem failures are diagnosed by read.
pub const InputProvider = struct {
    context: *anyopaque,
    canonical: *const fn (*anyopaque, Allocator, Io, []const u8) anyerror![:0]u8,
    read: *const fn (*anyopaque, Allocator, Io, []const u8, usize) anyerror![]u8,
    resolve: *const fn (*anyopaque, Allocator, []const u8, []const u8, Options) (Allocator.Error || error{InvalidPath})![]u8,
};

const Origin = struct { unit: UnitId = 0, span: ast.Span = .{ .start = 0, .end = 0 } };
const Visit = enum { unloaded, pending, active, finished };
const Frame = struct { unit: UnitId, next: u32 = 0 };
const Loader = struct {
    allocator: Allocator,
    io: Io,
    options: Options,
    project: Project = .{},
    files: std.AutoHashMapUnmanaged(symbol.Symbol, UnitId) = .empty,
    visits: std.ArrayList(Visit) = .empty,
    stack: std.ArrayList(Frame) = .empty,
    inherited_fixities: std.ArrayList(parser.InheritedFixity) = .empty,
    prelude_ready: bool = false,
    inputs: ?InputProvider = null,

    fn deinitScratch(self: *Loader) void {
        self.files.deinit(self.allocator);
        self.visits.deinit(self.allocator);
        self.stack.deinit(self.allocator);
        self.inherited_fixities.deinit(self.allocator);
    }
    fn report(self: *Loader, origin: Origin, code: Code, target: []const u8, cause: ?anyerror) Allocator.Error!void {
        const name = self.project.symbols.intern(self.allocator, target) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.SymbolLimit => 0,
        };
        try self.project.diagnostics.append(self.allocator, .{ .unit = origin.unit, .span = origin.span, .code = code, .target = name, .cause = cause });
    }
    fn validateAliases(self: *Loader) Allocator.Error!bool {
        if (self.options.prelude_path) |path| if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null) {
            try self.report(.{}, .invalid_prelude, path, null);
            return false;
        };
        for (self.options.aliases, 0..) |alias, index| {
            if (alias.prefix.len == 0 or !std.mem.endsWith(u8, alias.prefix, "/") or alias.root.len == 0 or
                std.mem.indexOfScalar(u8, alias.prefix, 0) != null or std.mem.indexOfScalar(u8, alias.root, 0) != null or
                std.mem.startsWith(u8, alias.prefix, "./") or std.mem.startsWith(u8, alias.prefix, "../"))
            {
                try self.report(.{}, .invalid_alias, alias.prefix, null);
                return false;
            }
            if (self.options.std_root != null and std.mem.eql(u8, alias.prefix, "std/")) {
                try self.report(.{}, .duplicate_alias, alias.prefix, null);
                return false;
            }
            for (self.options.aliases[0..index]) |prior| if (std.mem.eql(u8, alias.prefix, prior.prefix)) {
                try self.report(.{}, .duplicate_alias, alias.prefix, null);
                return false;
            };
        }
        if (self.options.std_root) |root| if (root.len == 0 or std.mem.indexOfScalar(u8, root, 0) != null) {
            try self.report(.{}, .invalid_alias, "std/", null);
            return false;
        };
        return true;
    }

    fn read(self: *Loader, path: []const u8, origin: Origin) Allocator.Error!?UnitId {
        const canonical = (if (self.inputs) |inputs| inputs.canonical(inputs.context, self.allocator, self.io, path) else Io.Dir.cwd().realPathFileAlloc(self.io, path, self.allocator)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            try self.report(origin, if (err == error.FileNotFound) .missing_file else .io_error, path, err);
            return null;
        };
        defer self.allocator.free(canonical);
        const filename_ = self.project.symbols.intern(self.allocator, canonical) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.SymbolLimit => {
                try self.report(origin, .file_limit, canonical, err);
                return null;
            },
        };
        const reserved: ?UnitId = if (self.files.get(filename_)) |existing| blk: {
            if (self.visits.items[existing - 1] != .unloaded) return existing;
            break :blk existing;
        } else null;
        if (reserved == null and (self.project.units.items.len >= self.options.max_files or self.project.units.items.len >= std.math.maxInt(UnitId))) {
            try self.report(origin, .file_limit, canonical, null);
            return null;
        }
        const remaining = self.options.max_total_source_bytes -| self.project.source_bytes;
        const allowed = @min(@min(self.options.max_source_bytes, remaining), std.math.maxInt(u32));
        const source = (if (self.inputs) |inputs| inputs.read(inputs.context, self.allocator, self.io, canonical, allowed +| 1) else Io.Dir.cwd().readFileAlloc(self.io, canonical, self.allocator, .limited(allowed +| 1))) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            try self.report(origin, if (err == error.StreamTooLong) .source_limit else if (err == error.FileNotFound) .missing_file else .io_error, canonical, err);
            return null;
        };
        var transferred = false;
        defer if (!transferred) self.allocator.free(source);
        if (source.len > allowed) {
            try self.report(origin, .source_limit, canonical, null);
            return null;
        }
        var tokens = lexer.lex(self.allocator, source) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.SourceLimit => {
                try self.report(origin, .source_limit, canonical, err);
                return null;
            },
        };
        defer tokens.deinit(self.allocator);
        var tree = if (tokens.diagnostics.items.len == 0)
            try parser.parseWithFixities(self.allocator, source, tokens.tokens.items, &self.project.symbols, self.inherited_fixities.items)
        else
            try ast.Tree.init(self.allocator);
        defer if (!transferred) tree.deinit(self.allocator);
        const id: UnitId = reserved orelse @intCast(self.project.units.items.len + 1);
        const unit_: Unit = .{ .filename = filename_, .source = source, .tree = tree, .implicit_prelude = self.prelude_ready };
        if (reserved != null) self.project.units.items[id - 1] = unit_ else try self.project.units.append(self.allocator, unit_);
        transferred = true;
        // From this point the Project exclusively owns source/tree. Handle all
        // later allocation failures in load's project-wide errdefer.
        return try self.finishRead(id, tokens.diagnostics.items, tokens.tokens.items);
    }

    fn finishRead(self: *Loader, id: UnitId, lexical: []const lexer.Diagnostic, tokens: []const @import("token.zig").Token) Allocator.Error!UnitId {
        const source_len = self.project.unit(id).source.len;
        self.project.source_bytes += source_len;
        try self.files.put(self.allocator, self.project.unit(id).filename, id);
        if (id <= self.visits.items.len) self.visits.items[id - 1] = .pending else try self.visits.append(self.allocator, .pending);
        if (lexical.len != 0) {
            const item = lexical[0];
            const details = try self.allocator.dupe(lexer.Diagnostic, lexical);
            errdefer self.allocator.free(details);
            try self.project.diagnostics.append(self.allocator, .{
                .unit = id,
                .span = .{ .start = item.start, .end = item.end },
                .code = .lexical_error,
                .lex_code = item.code,
                .publication = syntax_diagnostics.lexical(tokens, item),
                .lexical_details = details,
            });
        }
        const tree = &self.project.units.items[id - 1].tree;
        if (tree.diagnostics.items.len != 0) {
            const item = tree.diagnostics.items[0];
            try self.project.diagnostics.append(self.allocator, .{
                .unit = id,
                .span = .{ .start = item.start, .end = item.end },
                .code = .syntax_error,
                .parse_code = item.code,
                .parse_detail = item,
                .publication = try syntax_diagnostics.parse(self.allocator, tokens, item),
            });
        }
        const first: u32 = @intCast(self.project.imports.items.len);
        if (lexical.len == 0 and tree.diagnostics.items.len == 0) {
            for (tree.roots.items) |root| {
                if (tree.node(root).tag != .import_decl) continue;
                const info = tree.importDecl(root);
                try self.project.imports.append(self.allocator, .{
                    .declaration = .{ .unit = id, .node = root },
                    .path = info.path,
                    .namespace = info.namespace,
                    .bindings = info.bindings,
                    .span = info.path_span,
                });
            }
        }
        self.project.units.items[id - 1].imports = .{ .start = first, .len = @intCast(self.project.imports.items.len - first) };
        return id;
    }

    fn resolve(self: *Loader, imported: Import) (Allocator.Error || error{InvalidPath})![]u8 {
        if (self.inputs) |inputs| return inputs.resolve(inputs.context, self.allocator, self.project.filename(imported.declaration.unit), self.project.symbols.get(imported.path), self.options);
        return resolveImportPath(self.allocator, self.project.filename(imported.declaration.unit), self.project.symbols.get(imported.path), self.options);
    }
    fn walk(self: *Loader, root: UnitId) Allocator.Error!void {
        if (self.visits.items[root - 1] == .finished) return;
        self.visits.items[root - 1] = .active;
        try self.stack.append(self.allocator, .{ .unit = root });
        while (self.stack.items.len != 0) {
            const top = self.stack.items.len - 1;
            const frame = self.stack.items[top];
            const unit_ = self.project.unit(frame.unit);
            if (frame.next == unit_.imports.len) {
                try self.project.order.append(self.allocator, frame.unit);
                self.visits.items[frame.unit - 1] = .finished;
                _ = self.stack.pop();
                continue;
            }
            const edge = unit_.imports.start + frame.next;
            self.stack.items[top].next += 1;
            const imported = self.project.imports.items[edge];
            const origin: Origin = .{ .unit = frame.unit, .span = imported.span };
            const resolved = self.resolve(imported) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidPath => {
                    try self.report(origin, .import_path, self.project.symbols.get(imported.path), err);
                    continue;
                },
            };
            defer self.allocator.free(resolved);
            const target = try self.read(resolved, origin) orelse continue;
            self.project.imports.items[edge].target = target;
            if (self.visits.items[target - 1] == .pending) {
                self.visits.items[target - 1] = .active;
                try self.stack.append(self.allocator, .{ .unit = target });
            } else if (self.visits.items[target - 1] == .active) {
                try self.report(origin, .import_cycle, self.project.filename(target), null);
            }
        }
    }
};

fn hexDigit(c: u8) ?u8 {
    return if (c >= '0' and c <= '9') c - '0' else if (c >= 'a' and c <= 'f') c - 'a' + 10 else if (c >= 'A' and c <= 'F') c - 'A' + 10 else null;
}

/// Same source import path policy for normal loading and admitted frozen catalogs.
/// Canonical filesystem identity is checked separately by each loader owner.
pub fn resolveImportPath(allocator: Allocator, source_filename: []const u8, raw: []const u8, options: Options) (Allocator.Error || error{InvalidPath})![]u8 {
    if (raw.len == 0 or std.mem.indexOfScalar(u8, raw, '?') != null or std.mem.indexOfScalar(u8, raw, '#') != null)
        return error.InvalidPath;
    var root: []const u8 = undefined;
    var tail: []const u8 = undefined;
    if (std.mem.startsWith(u8, raw, "./") or std.mem.startsWith(u8, raw, "../")) {
        root = std.fs.path.dirname(source_filename) orelse return error.InvalidPath;
        tail = raw;
    } else {
        var matched: usize = 0;
        if (options.std_root) |standard| if (std.mem.startsWith(u8, raw, "std/")) {
            root = standard;
            matched = 4;
        };
        for (options.aliases) |alias| if (alias.prefix.len > matched and std.mem.startsWith(u8, raw, alias.prefix)) {
            matched = alias.prefix.len;
            root = alias.root;
        };
        if (matched == 0) return error.InvalidPath;
        tail = raw[matched..];
    }
    const decoded = try decodePath(allocator, tail);
    defer allocator.free(decoded);
    // Filesystem resolve must not let an alias-relative absolute spelling
    // discard its configured root.
    if (std.fs.path.isAbsolute(decoded)) return error.InvalidPath;
    const full = if (std.mem.endsWith(u8, decoded, ".blot")) try allocator.dupe(u8, decoded) else try std.mem.concat(allocator, u8, &.{ decoded, ".blot" });
    defer allocator.free(full);
    return std.fs.path.resolve(allocator, &.{ root, full });
}

fn decodePath(allocator: Allocator, path: []const u8) (Allocator.Error || error{InvalidPath})![]u8 {
    var decoded: std.ArrayList(u8) = .empty;
    defer decoded.deinit(allocator);
    try decoded.ensureTotalCapacity(allocator, path.len);
    var at: usize = 0;
    while (at < path.len) {
        var c = path[at];
        if (c == '%') {
            if (at + 2 >= path.len) return error.InvalidPath;
            const a = hexDigit(path[at + 1]) orelse return error.InvalidPath;
            const b = hexDigit(path[at + 2]) orelse return error.InvalidPath;
            c = a * 16 + b;
            if (c == '/') return error.InvalidPath;
            at += 3;
        } else at += 1;
        if (c == 0) return error.InvalidPath;
        decoded.appendAssumeCapacity(c);
    }
    if (!std.unicode.utf8ValidateSlice(decoded.items)) return error.InvalidPath;
    return decoded.toOwnedSlice(allocator);
}

test "import path decoding preserves Unicode and rejects malformed escapes" {
    const a = std.testing.allocator;
    const plain = try decodePath(a, "%73hared%2Eblot");
    defer a.free(plain);
    try std.testing.expectEqualStrings("shared.blot", plain);
    const unicode = try decodePath(a, "snow%20%E9%9B%AA");
    defer a.free(unicode);
    try std.testing.expectEqualStrings("snow 雪", unicode);
    for ([_][]const u8{ "%", "%3", "%zz", "%00", "%ff", "%2F" }) |invalid|
        try std.testing.expectError(error.InvalidPath, decodePath(a, invalid));
}

/// Combine an admitted unchanged dependency closure with ordinary new source
/// modules. The caller proves wire/compiler/settings/source/import resolution
/// before this operation. All symbol publication and project mutation are owned
/// by the returned candidate; failure leaves no caller project to repair.
pub fn loadCompiled(allocator: Allocator, io: Io, entrypath: []const u8, options: Options, dependency: *D.FrozenDependency) !Project {
    return loadCompiledMode(allocator, io, entrypath, options, dependency, dependency, null, null);
}

/// Dense artifact owners and their exact dictionary are borrowed unchanged.
/// Unlike relink, this path can safely consume an already published seed.
pub fn loadCompiledReadOnly(allocator: Allocator, io: Io, entrypath: []const u8, options: Options, dependency: *const D.FrozenDependency, inputs: ?InputProvider) !Project {
    return loadCompiledMode(allocator, io, entrypath, options, dependency, null, inputs, null);
}
/// Reused frontend results must form a closed dependency subgraph. Callers
/// also admit exact source bytes, settings and resolution before using this API.
pub fn validateReuseMask(dependency: *const D.FrozenDependency, reuse: []const bool) error{InvalidArtifact}!void {
    if (reuse.len != dependency.modules.len) return error.InvalidArtifact;
    var prelude: ?usize = null;
    for (dependency.modules, 0..) |module, id| if (module.identity.prelude) {
        if (prelude != null) return error.InvalidArtifact;
        prelude = id;
    };
    for (dependency.modules, reuse) |module, cached| {
        if (!cached) continue;
        if (module.implicit_prelude) {
            const id = prelude orelse return error.InvalidArtifact;
            if (!reuse[id]) return error.InvalidArtifact;
        }
        for (module.imports) |target| {
            if (target == 0 or target > reuse.len or !reuse[target - 1]) return error.InvalidArtifact;
        }
        for (module.source_imports) |request| {
            if (request.target == 0 or request.target > reuse.len or !reuse[request.target - 1]) return error.InvalidArtifact;
        }
    }
}
pub fn loadCompiledMixedReadOnly(allocator: Allocator, io: Io, entrypath: []const u8, options: Options, dependency: *const D.FrozenDependency, inputs: ?InputProvider, reuse: []const bool) !Project {
    try validateReuseMask(dependency, reuse);
    return loadCompiledMode(allocator, io, entrypath, options, dependency, null, inputs, reuse);
}
fn loadCompiledMode(allocator: Allocator, io: Io, entrypath: []const u8, options: Options, dependency: *const D.FrozenDependency, mutable: ?*D.FrozenDependency, inputs: ?InputProvider, reuse: ?[]const bool) !Project {
    if (options.input_mode != .project) return error.InputModeUnsupported;
    if (dependency.modules.len >= options.max_files or dependency.modules.len >= std.math.maxInt(u32)) return error.FileLimit;
    var loader: Loader = .{ .allocator = allocator, .io = io, .options = options, .inputs = inputs, .project = .{ .input_mode = options.input_mode, .compiled_modules = dependency.modules, .compiled_reuse = reuse orelse &.{} } };
    errdefer loader.project.deinit(allocator);
    defer loader.deinitScratch();
    if (!try loader.validateAliases()) return loader.project;
    if (mutable) |unpublished| {
        const units = try allocator.alloc(u32, dependency.modules.len);
        defer allocator.free(units);
        for (units, 1..) |*unit, id| unit.* = @intCast(id);
        try relink.relink(allocator, unpublished, &loader.project.symbols, units);
    } else {
        if (dependency.symbols.len == 0 or dependency.symbols[0].text.len != 0) return error.InvalidArtifact;
        for (dependency.symbols[1..], 1..) |name, ordinal| {
            if (try loader.project.symbols.intern(allocator, name.text) != ordinal) return error.InvalidArtifact;
        }
        for (dependency.modules, 1..) |module, ordinal| {
            if (module.core.unit != ordinal or module.interface.unit != ordinal) return error.InvalidArtifact;
        }
    }
    for (dependency.modules, 1..) |*module, index| {
        const id: u32 = @intCast(index);
        const cached = loader.project.compiledModule(id) != null;
        if (cached and (module.identity.source_bytes > options.max_source_bytes or module.identity.source_bytes > options.max_total_source_bytes -| loader.project.source_bytes)) return error.SourceLimit;
        const filename_ = try loader.project.symbols.intern(allocator, module.identity.normalized_path);
        try loader.project.units.append(allocator, .{ .filename = filename_, .source = &.{}, .tree = .{}, .implicit_prelude = module.implicit_prelude });
        if (cached) loader.project.source_bytes += module.identity.source_bytes;
        try loader.files.put(allocator, filename_, id);
        try loader.visits.append(allocator, if (cached) .finished else .unloaded);
        const first: u32 = @intCast(loader.project.imports.items.len);
        for (module.source_imports) |request| {
            const path = try loader.project.symbols.intern(allocator, request.path);
            try loader.project.imports.append(allocator, .{ .declaration = .{ .unit = id, .node = 0 }, .target = request.target, .path = path, .namespace = 0, .bindings = .{}, .span = .{ .start = 0, .end = 0 } });
        }
        loader.project.units.items[id - 1].imports = .{ .start = first, .len = @intCast(loader.project.imports.items.len - first) };
        if (module.identity.prelude) {
            if (!cached) return error.DependencySetChanged;
            if (loader.project.prelude_unit != 0) return error.InvalidArtifact;
            const expected = options.prelude_path orelse return error.StaleArtifact;
            if (inputs) |provider| {
                const canonical = try provider.canonical(provider.context, allocator, io, expected);
                defer allocator.free(canonical);
                if (!std.mem.eql(u8, canonical, module.identity.normalized_path)) return error.StaleArtifact;
            } else if (!std.mem.eql(u8, expected, module.identity.normalized_path)) return error.StaleArtifact;
            loader.project.prelude_unit = id;
            for (module.fixities) |fixity| try loader.inherited_fixities.append(allocator, .{ .operator = fixity.operator, .precedence = fixity.precedence, .association = fixity.association, .named = fixity.named });
        }
    }
    if ((loader.project.prelude_unit != 0) != (options.prelude_path != null)) return error.StaleArtifact;
    loader.prelude_ready = loader.project.prelude_unit != 0;
    const entry = try loader.read(entrypath, .{}) orelse return loader.project;
    if (entry <= dependency.modules.len) return error.DependencySetChanged;
    loader.project.entry = entry;
    try loader.walk(entry);
    if (reuse != null and loader.project.units.items.len != dependency.modules.len + 1) return error.DependencySetChanged;
    if (loader.project.diagnostics.items.len == 0) {
        // An unused retained catalog could participate in backend-wide selection.
        // Until subset relocation exists, require every seed producer reachable.
        const seen = try allocator.alloc(bool, loader.project.units.items.len);
        defer allocator.free(seen);
        @memset(seen, false);
        var stack: std.ArrayList(UnitId) = .empty;
        defer stack.deinit(allocator);
        try stack.append(allocator, entry);
        while (stack.pop()) |unit_| {
            if (unit_ == 0 or unit_ > seen.len) return error.InvalidArtifact;
            if (seen[unit_ - 1]) continue;
            seen[unit_ - 1] = true;
            if (loader.project.unit(unit_).implicit_prelude) try stack.append(allocator, loader.project.prelude_unit);
            for (loader.project.unitImports(unit_)) |edge| try stack.append(allocator, edge.target);
        }
        for (seen) |reached| if (!reached) return error.DependencySetChanged;
    }
    return loader.project;
}

pub fn load(allocator: Allocator, io: Io, entrypath: []const u8, options: Options) Allocator.Error!Project {
    return loadWithInputs(allocator, io, entrypath, options, null);
}

pub fn loadWithInputs(allocator: Allocator, io: Io, entrypath: []const u8, options: Options, inputs: ?InputProvider) Allocator.Error!Project {
    var loader: Loader = .{ .allocator = allocator, .io = io, .options = options, .inputs = inputs, .project = .{ .input_mode = options.input_mode } };
    errdefer loader.project.deinit(allocator);
    defer loader.deinitScratch();
    if (!try loader.validateAliases()) return loader.project;
    if (options.prelude_path) |path| {
        const prelude = try loader.read(path, .{}) orelse return loader.project;
        loader.project.prelude_unit = prelude;
        try loader.walk(prelude);
        if (options.input_mode == .source and loader.project.diagnostics.items.len != 0) return loader.project;
        const tree = &loader.project.unit(prelude).tree;
        for (tree.roots.items) |root| {
            if (tree.node(root).tag != .fixity_decl) continue;
            const fixity = tree.fixity(root);
            try loader.inherited_fixities.append(allocator, .{ .operator = fixity.operator, .precedence = fixity.precedence, .association = fixity.association, .named = fixity.named });
        }
        // The prelude and its explicit dependency closure bootstrap from
        // their own syntax. Later user modules inherit this actual interface.
        loader.prelude_ready = true;
    }
    const entry = try loader.read(entrypath, .{}) orelse return loader.project;
    loader.project.entry = entry;
    if (options.input_mode == .source) {
        // The entry is standalone source. Prelude dependencies retain their
        // normal loader; entry imports are syntax until checkProject rejects
        // them after successful prelude preparation. Never open their targets.
        if (loader.visits.items[entry - 1] != .finished) {
            try loader.project.order.append(allocator, entry);
            loader.visits.items[entry - 1] = .finished;
        }
    } else try loader.walk(entry);
    return loader.project;
}

fn fixtureFile(dir: Io.Dir, path: []const u8, source: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try dir.createDirPath(std.testing.io, parent);
    try dir.writeFile(std.testing.io, .{ .sub_path = path, .data = source });
}

fn fixturePath(dir: Io.Dir, file: []const u8) ![]u8 {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const count = try dir.realPath(std.testing.io, &buffer);
    return std.fs.path.join(std.testing.allocator, &.{ buffer[0..count], file });
}

fn expectValid(project_: *const Project) !void {
    for (project_.diagnostics.items) |item| std.debug.print("Project unit {d}: {s}: {s}\n", .{ item.unit, item.codeName(), item.message() });
    try std.testing.expectEqual(@as(usize, 0), project_.diagnostics.items.len);
    try std.testing.expectEqual(project_.units.items.len, project_.order.items.len);
    // Check dependency-first order without assigning semantic meaning to the
    // discovery IDs or reconstructing declarations as qualified strings.
    const positions = try std.testing.allocator.alloc(usize, project_.units.items.len + 1);
    defer std.testing.allocator.free(positions);
    for (project_.order.items, 0..) |id, index| positions[id] = index;
    for (project_.imports.items) |imported| {
        try std.testing.expect(imported.target != 0);
        try std.testing.expect(positions[imported.target] < positions[imported.declaration.unit]);
        try std.testing.expectEqual(ast.Tag.import_decl, project_.unit(imported.declaration.unit).tree.node(imported.declaration.node).tag);
    }
}

test "project diamond imports preserve separate syntax, aliases and discovery IDs" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try fixtureFile(tmp.dir, "main.blot", "import * as left from \"./left\"\nimport { value as right_value } from \"./right\"\nconst value = left.value\n");
    try fixtureFile(tmp.dir, "left.blot", "import { value } from \"./shared\"\nconst local = value\n");
    try fixtureFile(tmp.dir, "right.blot", "import * as common from \"./shared.blot\"\nconst value = common.value\n");
    try fixtureFile(tmp.dir, "shared.blot", "const value = 42\n");
    const path = try fixturePath(tmp.dir, "main.blot");
    defer a.free(path);
    var project_ = try load(a, std.testing.io, path, .{});
    defer project_.deinit(a);
    try expectValid(&project_);
    try std.testing.expectEqual(@as(usize, 4), project_.units.items.len);
    try std.testing.expectEqual(@as(UnitId, 1), project_.entry);
    try std.testing.expectEqualSlices(UnitId, &.{ 3, 2, 4, 1 }, project_.order.items);
    const imports_ = project_.unitImports(project_.entry);
    try std.testing.expectEqualStrings("left", project_.symbols.get(imports_[0].namespace));
    try std.testing.expectEqual(@as(symbol.Symbol, 0), imports_[1].namespace);
    try std.testing.expectEqual(@as(u32, 1), imports_[1].bindings.len);
    const binding_id = project_.unit(project_.entry).tree.list(imports_[1].bindings)[0];
    try std.testing.expectEqual(ast.Tag.import_binding, project_.unit(project_.entry).tree.node(binding_id).tag);
    try std.testing.expectEqual(@as(UnitId, 3), project_.unitImports(2)[0].target);
    try std.testing.expectEqual(@as(UnitId, 3), project_.unitImports(4)[0].target);
    try std.testing.expectEqualStrings("const value = 42\n", project_.unit(3).source);
}

test "canonical escaped paths and symlinks share one unit identity" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try fixtureFile(tmp.dir, "main.blot", "import * as direct from \"./shared.blot\"\nimport * as escaped from \"./%73hared%2Eblot\"\nimport * as linked from \"./link.blot\"\nconst answer = direct.value\n");
    try fixtureFile(tmp.dir, "shared.blot", "const value = 42\n");
    try tmp.dir.symLink(std.testing.io, "shared.blot", "link.blot", .{});
    const path = try fixturePath(tmp.dir, "main.blot");
    defer a.free(path);
    var project_ = try load(a, std.testing.io, path, .{});
    defer project_.deinit(a);
    try expectValid(&project_);
    try std.testing.expectEqual(@as(usize, 2), project_.units.items.len);
    for (project_.unitImports(1)) |imported| try std.testing.expectEqual(@as(UnitId, 2), imported.target);
}

test "cycles and missing imports identify the exact importing unit and path span" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const looping = "import * as main from \"./%6dain.blot\"\n";
    try fixtureFile(tmp.dir, "main.blot", "import * as loop from \"./loop\"\n");
    try fixtureFile(tmp.dir, "loop.blot", looping);
    const path = try fixturePath(tmp.dir, "main.blot");
    defer a.free(path);
    var cycle = try load(a, std.testing.io, path, .{});
    defer cycle.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), cycle.diagnostics.items.len);
    const diagnostic = cycle.diagnostics.items[0];
    try std.testing.expectEqual(Code.import_cycle, diagnostic.code);
    try std.testing.expectEqual(@as(UnitId, 2), diagnostic.unit);
    try std.testing.expectEqualStrings("\"./%6dain.blot\"", cycle.unit(diagnostic.unit).source[diagnostic.span.start..diagnostic.span.end]);
    try fixtureFile(tmp.dir, "main.blot", "import * as missing from \"./absent\"\n");
    var missing = try load(a, std.testing.io, path, .{});
    defer missing.deinit(a);
    try std.testing.expectEqual(Code.missing_file, missing.diagnostics.items[0].code);
    try std.testing.expectEqual(@as(UnitId, 1), missing.diagnostics.items[0].unit);
    const where = missing.diagnostics.items[0].span;
    try std.testing.expectEqualStrings("\"./absent\"", missing.unit(1).source[where.start..where.end]);
    try fixtureFile(tmp.dir, "main.blot", "import * as invalid from \"unmapped/value\"\n");
    var invalid = try load(a, std.testing.io, path, .{});
    defer invalid.deinit(a);
    try std.testing.expectEqual(Code.import_path, invalid.diagnostics.items[0].code);
}

test "explicit aliases choose the longest prefix and reject duplicate configuration" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try fixtureFile(tmp.dir, "main.blot", "import * as value from \"lib/nested/value\"\n");
    try fixtureFile(tmp.dir, "one/value.blot", "const chosen = 1\n");
    try fixtureFile(tmp.dir, "two/value.blot", "const chosen = 2\n");
    const path = try fixturePath(tmp.dir, "main.blot");
    defer a.free(path);
    const one = try fixturePath(tmp.dir, "one");
    defer a.free(one);
    const two = try fixturePath(tmp.dir, "two");
    defer a.free(two);
    var project_ = try load(a, std.testing.io, path, .{ .aliases = &.{ .{ .prefix = "lib/", .root = one }, .{ .prefix = "lib/nested/", .root = two } } });
    defer project_.deinit(a);
    try expectValid(&project_);
    try std.testing.expectEqualStrings("const chosen = 2\n", project_.unit(2).source);
    var duplicate = try load(a, std.testing.io, path, .{ .aliases = &.{ .{ .prefix = "lib/", .root = one }, .{ .prefix = "lib/", .root = two } } });
    defer duplicate.deinit(a);
    try std.testing.expectEqual(Code.duplicate_alias, duplicate.diagnostics.items[0].code);
    try std.testing.expectEqual(@as(usize, 0), duplicate.units.items.len);
    var invalid = try load(a, std.testing.io, path, .{ .aliases = &.{.{ .prefix = "lib", .root = one }} });
    defer invalid.deinit(a);
    try std.testing.expectEqual(Code.invalid_alias, invalid.diagnostics.items[0].code);
}

test "source byte and file limits bound the whole project" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source = "import * as child from \"./child\"\n";
    try fixtureFile(tmp.dir, "main.blot", source);
    try fixtureFile(tmp.dir, "child.blot", "const answer = 42\n");
    const path = try fixturePath(tmp.dir, "main.blot");
    defer a.free(path);
    var limited = try load(a, std.testing.io, path, .{ .max_files = 1 });
    defer limited.deinit(a);
    try std.testing.expectEqual(Code.file_limit, limited.diagnostics.items[0].code);
    try std.testing.expectEqual(@as(usize, 1), limited.units.items.len);
    var bytes = try load(a, std.testing.io, path, .{ .max_total_source_bytes = source.len });
    defer bytes.deinit(a);
    try std.testing.expectEqual(Code.source_limit, bytes.diagnostics.items[0].code);
    try std.testing.expectEqual(source.len, bytes.source_bytes);
    var per_file = try load(a, std.testing.io, path, .{ .max_source_bytes = 4 });
    defer per_file.deinit(a);
    try std.testing.expectEqual(Code.source_limit, per_file.diagnostics.items[0].code);
    try std.testing.expectEqual(@as(usize, 0), per_file.units.items.len);
}

fn allocationScenario(allocator: Allocator, entry: []const u8) !void {
    var project_ = try load(allocator, std.testing.io, entry, .{});
    defer project_.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), project_.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 3), project_.units.items.len);
}

fn invalidAllocationScenario(allocator: Allocator, entry: []const u8) !void {
    var project_ = try load(allocator, std.testing.io, entry, .{});
    defer project_.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), project_.units.items.len);
    try std.testing.expectEqual(@as(usize, 1), project_.diagnostics.items.len);
    try std.testing.expectEqual(Code.syntax_error, project_.diagnostics.items[0].code);
    try std.testing.expectEqual(@as(UnitId, 2), project_.diagnostics.items[0].unit);
}

test "invalid imported source retains exact diagnostics and owns failed parse buffers" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try fixtureFile(tmp.dir, "main.blot", "import * as child from \"./child\"\nconst answer = 42\n");
    const path = try fixturePath(tmp.dir, "main.blot");
    defer a.free(path);
    const malformed = "const answer =\n";
    try fixtureFile(tmp.dir, "child.blot", malformed);
    var syntax = try load(a, std.testing.io, path, .{});
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), syntax.diagnostics.items.len);
    const failed = syntax.diagnostics.items[0];
    try std.testing.expectEqual(Code.syntax_error, failed.code);
    try std.testing.expectEqual(@as(UnitId, 2), failed.unit);
    try std.testing.expectEqualStrings(malformed, syntax.unit(failed.unit).source);
    try std.testing.expect(failed.span.start <= failed.span.end and failed.span.end <= malformed.len);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, invalidAllocationScenario, .{path});

    const private = "const answer = \xEE\x80\x80\n";
    try fixtureFile(tmp.dir, "child.blot", private);
    var lexical = try load(a, std.testing.io, path, .{});
    defer lexical.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), lexical.diagnostics.items.len);
    const invalid = lexical.diagnostics.items[0];
    try std.testing.expectEqual(Code.lexical_error, invalid.code);
    try std.testing.expectEqual(@as(UnitId, 2), invalid.unit);
    try std.testing.expectEqualStrings("\xEE\x80\x80", lexical.unit(invalid.unit).source[invalid.span.start..invalid.span.end]);
    try std.testing.expectEqual(@as(usize, 0), lexical.unit(invalid.unit).tree.roots.items.len);
}

fn lexicalCopyAllocationScenario(allocator: Allocator, entry: []const u8) !void {
    var loaded = try load(allocator, std.testing.io, entry, .{});
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), loaded.units.items.len);
    try std.testing.expectEqual(@as(usize, 1), loaded.diagnostics.items.len);
    const failure = loaded.diagnostics.items[0];
    try std.testing.expectEqual(@as(UnitId, 2), failure.unit);
    try std.testing.expectEqual(@as(usize, 2), failure.lexical_details.len);
    try std.testing.expectEqual(lexer.Code.string_escape, failure.lexical_details[0].code);
    try std.testing.expectEqual(lexer.Code.string_literal, failure.lexical_details[1].code);
    try std.testing.expectEqual(syntax_diagnostics.Cause.lexical, failure.publication.?.cause);
    try std.testing.expectEqualStrings("LEX_UNEXPECTED_CHARACTER", failure.publication.?.code);
    try std.testing.expectEqual(ast.Span{ .start = 12, .end = 13 }, failure.publication.?.span);
    // lexer's token and diagnostic owners have already been destroyed. New
    // scratch must not alter the project's copies or publication evidence.
    const scratch = try allocator.alloc(u8, 4096);
    defer allocator.free(scratch);
    @memset(scratch, 0xa5);
    try std.testing.expectEqual(@as(u32, 13), failure.lexical_details[0].start);
    try std.testing.expectEqual(@as(u32, 12), failure.lexical_details[1].start);
}

test "failed imported lexical owners copy every detail and release all allocation failures" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try fixtureFile(tmp.dir, "main.blot", "import * as child from \"./child\"\nconst answer = 42\n");
    try fixtureFile(tmp.dir, "child.blot", "const bad = \"\\q\n");
    const path = try fixturePath(tmp.dir, "main.blot");
    defer allocator.free(path);
    try lexicalCopyAllocationScenario(allocator, path);
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, lexicalCopyAllocationScenario, .{path});
}

test "allocation failures release every source, syntax and traversal buffer" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try fixtureFile(tmp.dir, "main.blot", "import * as left from \"./left\"\nimport * as right from \"./right\"\nconst answer = 42\n");
    try fixtureFile(tmp.dir, "left.blot", "const value = 1\n");
    try fixtureFile(tmp.dir, "right.blot", "const value = 2\n");
    const path = try fixturePath(tmp.dir, "main.blot");
    defer a.free(path);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{path});
}

test "gdev dependency closure loads separate source units with the std alias" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const entry = Io.Dir.cwd().realPathFileAlloc(io, "../gdev/src/main.blot", a) catch |err| switch (err) {
        error.FileNotFound => Io.Dir.cwd().realPathFileAlloc(io, "../../gdev/src/main.blot", a) catch |fallback| switch (fallback) {
            error.FileNotFound => return error.SkipZigTest,
            else => return fallback,
        },
        else => return err,
    };
    defer a.free(entry);
    const packages = try std.fs.path.resolve(a, &.{ std.fs.path.dirname(entry).?, "../packages" });
    defer a.free(packages);
    const standard = Io.Dir.cwd().realPathFileAlloc(io, "std", a) catch |err| switch (err) {
        error.FileNotFound => try Io.Dir.cwd().realPathFileAlloc(io, "../std", a),
        else => return err,
    };
    defer a.free(standard);
    var project_ = try load(a, io, entry, .{ .std_root = standard, .aliases = &.{.{ .prefix = "gdev/", .root = packages }} });
    defer project_.deinit(a);
    try expectValid(&project_);
    // This is a live sibling project, not a pinned file-count fixture.
    // Check actual alias resolution and distinct unit ownership as it grows.
    var standard_imports: usize = 0;
    for (project_.imports.items) |imported| {
        if (!std.mem.startsWith(u8, project_.symbols.get(imported.path), "std/")) continue;
        standard_imports += 1;
        try std.testing.expect(std.mem.startsWith(u8, project_.filename(imported.target), standard));
    }
    try std.testing.expect(standard_imports != 0);
    for (project_.units.items, 0..) |unit_, index| {
        for (project_.units.items[0..index]) |previous| try std.testing.expect(unit_.filename != previous.filename);
    }
    try std.testing.expectEqual(project_.entry, project_.order.items[project_.order.items.len - 1]);
    // No checker/backend result is implied by successful source loading.
}
