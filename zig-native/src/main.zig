const std = @import("std");
const builtin = @import("builtin");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const syntax_diagnostics = @import("syntax_diagnostics.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const memory = @import("memory.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const Io = std.Io;
const usage =
    \\Usage: blotc lex|parse|check SOURCE [SOURCE...]
    \\       blotc build ENTRY OUTPUT.wasm [--dependencies FILE] [project options]
    \\       blotc dependencies ENTRY OUTPUT.blotdep [project options]
    \\       blotc parse-project ENTRY [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]
    \\       blotc check-project ENTRY [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]
    \\       blotc build-project ENTRY OUTPUT.wasm [--std-root DIR] [--alias PREFIX=DIR] [--prelude PATH|none]
    \\       blotc serve-project (owned project-build byte protocol)
    \\       blotc check|build also accepts explicit --prelude PATH|none (default: none).
    \\       Project options accept --input-mode project|source (default: project).
    \\
    \\Handwritten Zig source compiler. JSON-lines diagnostics and stage metrics
    \\are written to stdout. Parse coverage and executable coverage are distinct.
    \\
;
const dependency_cli = @import("dependency_cli.zig");
const compiler_identity = @import("compiler_identity");
/// Immutable executable defaults; individual compiler invocations own options.
pub const compiler_defaults = .{ .artifact_replay = compiler_identity.artifact_replay };

const Command = enum { lex, parse, check, build, dependencies, parse_project, check_project, build_project };
const Stats = struct {
    optimization: @import("function_facts.zig").Stats = .{},
    source_bytes: usize = 0,
    tokens: usize = 0,
    syntax_nodes: usize = 0,
    syntax_extra_words: usize = 0,
    symbols: usize = 0,
    symbol_bytes: usize = 0,
    type_nodes: usize = 0,
    type_versions: usize = 0,
    bindings: usize = 0,
    body_elaborations: usize = 0,
    wasm_bytes: usize = 0,
    code_instances: usize = 0,
    callable_wrappers: usize = 0,
    emitted_functions: usize = 0,
    core_nodes: usize = 0,
    body_lowerings: usize = 0,
    constant_steps: usize = 0,
    lex_us: i64 = 0,
    parse_us: i64 = 0,
    check_us: i64 = 0,
    lower_us: i64 = 0,
    emit_us: i64 = 0,
};
fn now(io: Io) Io.Timestamp {
    return Io.Clock.awake.now(io);
}
fn elapsed(start: Io.Timestamp, io: Io) i64 {
    return start.durationTo(now(io)).toMicroseconds();
}

fn diagnostic(writer: *Io.Writer, filename: []const u8, stage: []const u8, code: []const u8, start: u32, end: u32, message: []const u8) !void {
    try std.json.Stringify.value(.{ .kind = "diagnostic", .filename = filename, .stage = stage, .code = code, .start = start, .end = end, .message = message }, .{}, writer);
    try writer.writeByte('\n');
}
fn frontendDiagnostic(writer: *Io.Writer, filename: []const u8, stage: []const u8, source: []const u8, publication: syntax_diagnostics.Publication, details: anytype) !void {
    try std.json.Stringify.value(.{
        .kind = "diagnostic",
        .filename = filename,
        .stage = stage,
        .code = publication.code,
        .start = publication.span.start,
        .end = publication.span.end,
        .message = publication.message,
        .offset_encoding = "utf8_bytes",
        .utf16 = publication.utf16(source),
        .cause = publication.cause,
        .expected_token = publication.expected_token,
        .actual_token = publication.actual_token,
        .details = details,
    }, .{}, writer);
    try writer.writeByte('\n');
}

fn purityDiagnostic(allocator: std.mem.Allocator, writer: *Io.Writer, filename: []const u8, stage: []const u8, source: []const u8, code: []const u8, span: @import("ast.zig").Span, pool: *const symbols.Pool, module_name: []const u8, witness: checker.PurityWitness) !void {
    const message = try @import("purity_diagnostics.zig").format(allocator, pool, module_name, witness);
    defer allocator.free(message);
    try frontendDiagnostic(writer, filename, stage, source, .{ .cause = .native_detail, .code = code, .span = span, .message = message }, @as([]const checker.PurityWitness, &.{witness}));
}
fn purityModuleName(allocator: std.mem.Allocator, loaded: *const project.Project, witness: checker.PurityWitness) ![]u8 {
    if (witness.operation_name != null) return allocator.dupe(u8, "");
    if (witness.foreign) return allocator.dupe(u8, "blot:compiler");
    if (witness.identity.unit == loaded.prelude_unit) return allocator.dupe(u8, "std/prelude");
    if (loaded.input_mode == .source and witness.identity.unit == loaded.entry) return allocator.dupe(u8, "main");
    if (witness.identity.unit == 0 or witness.identity.unit > loaded.units.items.len) return error.OperationPurityOriginRequired;
    const directory = std.fs.path.dirname(loaded.filename(loaded.entry)) orelse return error.OperationPurityOriginRequired;
    return std.fs.path.relative(allocator, directory, null, directory, loaded.filename(witness.identity.unit));
}
fn namedDiagnostic(allocator: std.mem.Allocator, writer: *Io.Writer, filename: []const u8, stage: []const u8, code: []const u8, span: @import("ast.zig").Span, message: []const u8, pool: *const symbols.Pool, symbol: symbols.Symbol) !void {
    if (symbol == 0) return diagnostic(writer, filename, stage, code, span.start, span.end, message);
    const full = try allocator.print("{s}{s}{s}", .{ message, if (std.mem.eql(u8, code, "unknown_intrinsic") or std.mem.eql(u8, code, "unknown_record_field")) " " else ": ", pool.get(symbol) });
    defer allocator.free(full);
    try diagnostic(writer, filename, stage, code, span.start, span.end, full);
}

fn process(io: Io, backing: std.mem.Allocator, writer: *Io.Writer, command: Command, filename: []const u8, output_path: ?[]const u8) !bool {
    var tracked: memory.TrackedAllocator = .{ .backing = backing };
    const allocator = tracked.allocator();
    var stats: Stats = .{};
    const start = now(io);
    const ok = compilation: {
        const source = try Io.Dir.cwd().readFileAlloc(io, filename, allocator, .limited(32 * 1024 * 1024));
        var source_live = true;
        defer if (source_live) allocator.free(source);
        stats.source_bytes = source.len;
        var names: symbols.Pool = .{};
        defer names.deinit(allocator);
        var tree = parsed: {
            const lex_start = now(io);
            var lexed = try lexer.lex(allocator, source);
            defer lexed.deinit(allocator);
            stats.lex_us = elapsed(lex_start, io);
            stats.tokens = lexed.tokens.items.len;
            if (lexed.diagnostics.items.len != 0) {
                try frontendDiagnostic(writer, filename, "lex", source, syntax_diagnostics.lexical(lexed.tokens.items, lexed.diagnostics.items[0]), lexed.diagnostics.items);
                break :compilation false;
            }
            if (command == .lex) break :compilation true;
            const parse_start = now(io);
            var syntax = try parser.parse(allocator, source, lexed.tokens.items, &names);
            errdefer syntax.deinit(allocator);
            if (syntax.diagnostics.items.len != 0) {
                const published = try syntax_diagnostics.parse(allocator, lexed.tokens.items, syntax.diagnostics.items[0]);
                try frontendDiagnostic(writer, filename, "parse", source, published, syntax.diagnostics.items);
            }
            stats.parse_us = elapsed(parse_start, io);
            // Tokens are parser scratch; retained syntax owns only IDs/spans.
            break :parsed syntax;
        };
        defer tree.deinit(allocator);
        stats.syntax_nodes = tree.nodes.items.len - 1;
        stats.syntax_extra_words = tree.extra.items.len;
        stats.symbols = names.entries.items.len;
        stats.symbol_bytes = names.bytes.items.len;
        if (tree.diagnostics.items.len != 0) {
            break :compilation false;
        }
        if (command == .parse) break :compilation true;
        const check_start = now(io);
        var checked = try checker.check(allocator, &tree, &names);
        var checked_live = true;
        defer if (checked_live) checked.deinit(allocator);
        stats.check_us = elapsed(check_start, io);
        stats.type_nodes = checked.types.nodes.items.len;
        stats.type_versions = checked.types.versions.items.len;
        stats.bindings = checked.bindings.len - 1;
        stats.body_elaborations = checked.body_elaborations;
        if (checked.diagnostics.len != 0) {
            for (checked.diagnostics) |item| {
                if (item.hole) |hole| {
                    try frontendDiagnostic(writer, filename, "check", source, .{ .cause = .native_detail, .code = @tagName(item.code), .span = item.span, .message = item.message() }, .{ .hole = hole });
                } else if (item.purity) |witness| {
                    try purityDiagnostic(allocator, writer, filename, "check", source, @tagName(item.code), item.span, &names, "main", witness);
                } else if (item.code == .module_loader_required or item.numeric_literal != null) {
                    try frontendDiagnostic(writer, filename, "check", source, .{ .cause = .native_detail, .code = @tagName(item.code), .span = item.span, .message = item.message() }, @as([]const checker.Diagnostic, &.{item}));
                } else try namedDiagnostic(allocator, writer, filename, "check", @tagName(item.code), item.span, item.message(), &names, item.symbol);
            }
            break :compilation false;
        }
        if (command == .check) break :compilation true;
        const lower_start = now(io);
        var lowered = try core.lower(allocator, &tree, &names, &checked);
        defer lowered.deinit(allocator);
        lowered.unit = 1;
        stats.lower_us = elapsed(lower_start, io);
        stats.core_nodes = lowered.nodes.len - 1;
        stats.body_lowerings = lowered.body_lowerings;
        for (lowered.diagnostics) |item| try diagnostic(writer, filename, "lower", @tagName(item.code), item.span.start, item.span.end, item.message());
        if (lowered.diagnostics.len != 0) break :compilation false;
        checked.deinit(allocator);
        checked_live = false;
        tree.deinit(allocator);
        names.deinit(allocator);
        allocator.free(source);
        source_live = false;
        const emit_start = now(io);
        var compiled = try backend.compile(allocator, &.{lowered}, 1);
        defer compiled.deinit(allocator);
        stats.emit_us = elapsed(emit_start, io);
        // A declined backend still owns measured work. Preserve it before
        // reporting the diagnostic and leaving compilation.
        stats.code_instances = compiled.code_instances;
        stats.optimization = compiled.optimization;
        stats.callable_wrappers = compiled.callable_wrappers;
        stats.emitted_functions = compiled.emitted_functions;
        stats.constant_steps = compiled.constant_steps;
        if (compiled.diagnostic) |item| {
            try diagnostic(writer, filename, "emit", @tagName(item.code), item.span.start, item.span.end, item.message());
            break :compilation false;
        }
        stats.wasm_bytes = compiled.bytes.len;
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path.?, .data = compiled.bytes });
        break :compilation true;
    };
    // All compiler/source/result owners have been destroyed before reporting.
    std.debug.assert(tracked.counts.live_bytes == 0);
    try std.json.Stringify.value(.{
        .kind = "compilation",
        .filename = filename,
        .stage = @tagName(command),
        .success = ok,
        .total_us = elapsed(start, io),
        .stats = stats,
        .memory = tracked.counts,
        .memory_scope = "Requested bytes for source and compiler-owned buffers; excludes allocator overhead and process RSS. All owners released before this record.",
    }, .{}, writer);
    try writer.writeByte('\n');
    return ok;
}

fn processProject(io: Io, backing: std.mem.Allocator, writer: *Io.Writer, command: Command, filename: []const u8, options: project.Options, output_path: ?[]const u8) !bool {
    var tracked: memory.TrackedAllocator = .{ .backing = backing };
    const allocator = tracked.allocator();
    const start = now(io);
    var source_bytes: usize = 0;
    var files: usize = 0;
    var syntax_nodes: usize = 0;
    var symbol_bytes: usize = 0;
    var type_nodes: usize = 0;
    var type_versions: usize = 0;
    var row_versions: usize = 0;
    var effect_rows: usize = 0;
    var body_elaborations: usize = 0;
    var imported_schemes: usize = 0;
    var core_nodes: usize = 0;
    var body_lowerings: usize = 0;
    var code_instances: usize = 0;
    var optimization: @import("function_facts.zig").Stats = .{};
    var callable_wrappers: usize = 0;
    var emitted_functions: usize = 0;
    var wasm_bytes: usize = 0;
    var constant_steps: usize = 0;
    var load_us: i64 = 0;
    var check_us: i64 = 0;
    var lower_us: i64 = 0;
    var emit_us: i64 = 0;
    var write_us: i64 = 0;
    var teardown_us: i64 = 0;
    const ok = compilation: {
        var loaded = try project.load(allocator, io, filename, options);
        defer {
            const release_start = now(io);
            loaded.deinit(allocator);
            teardown_us += elapsed(release_start, io);
        }
        source_bytes = loaded.source_bytes;
        files = loaded.units.items.len;
        symbol_bytes = loaded.symbols.bytes.items.len;
        for (loaded.units.items) |unit| syntax_nodes += unit.tree.nodes.items.len - 1;
        for (loaded.diagnostics.items) |item| {
            const path = if (item.unit == 0) filename else loaded.filename(item.unit);
            if (item.publication) |published| {
                const unit_ = loaded.unit(item.unit);
                if (item.parse_code != null) {
                    try frontendDiagnostic(writer, path, "parse-project", unit_.source, published, unit_.tree.diagnostics.items);
                } else {
                    try frontendDiagnostic(writer, path, "parse-project", unit_.source, published, item.lexical_details);
                }
            } else try diagnostic(writer, path, "parse-project", item.codeName(), item.span.start, item.span.end, item.message());
        }
        load_us = elapsed(start, io);
        if (loaded.diagnostics.items.len != 0) break :compilation false;
        if (command == .parse_project) break :compilation true;
        const check_start = now(io);
        var checked = try project_check.checkProject(allocator, &loaded);
        var checked_live = true;
        defer if (checked_live) {
            const release_start = now(io);
            checked.deinit(allocator);
            teardown_us += elapsed(release_start, io);
        };
        body_elaborations = checked.body_elaborations;
        imported_schemes = checked.imported_schemes;
        for (checked.modules) |optional_module| if (optional_module) |module_| {
            const types_ = &module_.checked.types;
            type_nodes += types_.nodes.items.len;
            type_versions += types_.versions.items.len;
            row_versions += types_.effects.versions.items.len;
            effect_rows += types_.effects.rows.items.len;
        };
        for (checked.diagnostics) |item| {
            const path = if (item.unit == 0) filename else loaded.filename(item.unit);
            if (item.semantic == .module_loader_required) {
                const unit_ = loaded.unit(item.unit);
                const detail = checker.sourceImportDiagnostic(&unit_.tree).?;
                try frontendDiagnostic(writer, path, "check-project", unit_.source, .{ .cause = .native_detail, .code = item.codeName(), .span = item.span, .message = item.message() }, @as([]const checker.Diagnostic, &.{detail}));
            } else if (item.hole) |hole| {
                try frontendDiagnostic(writer, path, "check-project", loaded.unit(item.unit).source, .{ .cause = .native_detail, .code = item.codeName(), .span = item.span, .message = item.message() }, .{ .hole = hole });
            } else if (item.numeric_literal) |detail| {
                const unit_ = loaded.unit(item.unit);
                try frontendDiagnostic(writer, path, "check-project", unit_.source, .{ .cause = .native_detail, .code = item.codeName(), .span = item.span, .message = item.message(), .actual_token = detail.actual_token }, @as([]const @import("ast.zig").NumericFault, &.{detail}));
            } else if (item.purity) |witness| {
                const module_name = try purityModuleName(allocator, &loaded, witness);
                defer allocator.free(module_name);
                try purityDiagnostic(allocator, writer, path, "check-project", loaded.unit(item.unit).source, item.codeName(), item.span, &loaded.symbols, module_name, witness);
            } else try namedDiagnostic(allocator, writer, path, "check-project", item.codeName(), item.span, item.message(), &loaded.symbols, item.symbol);
        }
        check_us = elapsed(check_start, io);
        if (checked.diagnostics.len != 0) break :compilation false;
        if (command == .check_project) break :compilation true;
        const lower_start = now(io);
        const units = try allocator.alloc(core.Module, loaded.units.items.len);
        var initialized: usize = 0;
        defer {
            const release_start = now(io);
            for (units[0..initialized]) |*unit_| unit_.deinit(allocator);
            allocator.free(units);
            teardown_us += elapsed(release_start, io);
        }
        for (loaded.units.items, 0..) |*unit_, index| {
            const id: u32 = @intCast(index + 1);
            units[index] = try core.lowerWithOrigins(allocator, &unit_.tree, &loaded.symbols, &checked.module(id).checked, .{ .context = &loaded, .lookup = project_check.diagnosticModuleOrigin });
            units[index].unit = id;
            initialized += 1;
            core_nodes += units[index].nodes.len - 1;
            body_lowerings += units[index].body_lowerings;
            for (units[index].diagnostics) |item| try diagnostic(writer, loaded.filename(id), "lower", @tagName(item.code), item.span.start, item.span.end, item.message());
            lower_us = elapsed(lower_start, io);
            if (units[index].diagnostics.len != 0) break :compilation false;
        }
        const emission_owners = try allocator.alloc(@import("runtime_identity.zig").Owner, units.len);
        defer allocator.free(emission_owners);
        for (emission_owners, 0..) |*owner, index| owner.* = .{ .unit = @intCast(index + 1), .path = loaded.filename(@intCast(index + 1)) };
        var emission_identity = try @import("runtime_identity.zig").Metadata.capture(allocator, &loaded.symbols, emission_owners, units.len);
        defer emission_identity.deinit(allocator);
        const release_start = now(io);
        checked.deinit(allocator);
        checked_live = false;
        // Paths and the tiny import catalog remain for diagnostics; source,
        // syntax and mutable inference state cannot be consulted by emission.
        for (loaded.units.items) |*unit_| {
            unit_.tree.deinit(allocator);
            allocator.free(unit_.source);
            unit_.source = &.{};
        }
        teardown_us += elapsed(release_start, io);
        const emit_start = now(io);
        var compiled = try backend.compileWithOptions(allocator, units, loaded.entry, .{ .identity = emission_identity.view(), .unit_order = loaded.order.items, .diagnostic_source_mode = loaded.input_mode == .source, .diagnostic_prelude_unit = loaded.prelude_unit });
        defer {
            const result_release_start = now(io);
            compiled.deinit(allocator);
            teardown_us += elapsed(result_release_start, io);
        }
        code_instances = compiled.code_instances;
        optimization = compiled.optimization;
        callable_wrappers = compiled.callable_wrappers;
        emitted_functions = compiled.emitted_functions;
        constant_steps = compiled.constant_steps;
        if (compiled.diagnostic) |item| {
            try diagnostic(writer, loaded.filename(item.unit), "emit", @tagName(item.code), item.span.start, item.span.end, item.message());
            emit_us = elapsed(emit_start, io);
            break :compilation false;
        }
        wasm_bytes = compiled.bytes.len;
        emit_us = elapsed(emit_start, io);
        const write_start = now(io);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = output_path.?, .data = compiled.bytes });
        write_us = elapsed(write_start, io);
        break :compilation true;
    };
    std.debug.assert(tracked.counts.live_bytes == 0);
    try std.json.Stringify.value(.{
        .kind = "compilation",
        .filename = filename,
        .stage = switch (command) {
            .parse_project => "parse-project",
            .check_project => "check-project",
            else => "build-project",
        },
        .success = ok,
        .total_us = elapsed(start, io),
        .source_bytes = source_bytes,
        .files = files,
        .syntax_nodes = syntax_nodes,
        .symbol_bytes = symbol_bytes,
        .type_nodes = type_nodes,
        .type_versions = type_versions,
        .row_versions = row_versions,
        .effect_rows = effect_rows,
        .body_elaborations = body_elaborations,
        .imported_schemes = imported_schemes,
        .core_nodes = core_nodes,
        .body_lowerings = body_lowerings,
        .code_instances = code_instances,
        .optimization = optimization,
        .callable_wrappers = callable_wrappers,
        .emitted_functions = emitted_functions,
        .constant_steps = constant_steps,
        .wasm_bytes = wasm_bytes,
        .load_us = load_us,
        .check_us = check_us,
        .lower_us = lower_us,
        .emit_us = emit_us,
        .write_us = write_us,
        .teardown_us = teardown_us,
        .memory = tracked.counts,
        .memory_scope = "Requested bytes for project source, syntax, symbols, typed core and compiler scratch; excludes allocator overhead and process RSS. All owners released before this record.",
    }, .{}, writer);
    try writer.writeByte('\n');
    return ok;
}

fn run(init: std.process.Init) !bool {
    // Zig 0.17 defaults safe Init.gpa to a validating allocator.
    // Keep compiler checks, but use the standard production heap in releases.
    const backing = if (builtin.mode == .debug) init.gpa else std.heap.smp_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 1 or std.mem.eql(u8, args[1], "--help")) {
        try Io.File.stdout().writeStreamingAll(init.io, usage);
        return true;
    }
    if (std.mem.eql(u8, args[1], "serve-project")) {
        if (args.len != 2) return error.InvalidServeArguments;
        var input_buffer: [4096]u8 = undefined;
        var output_buffer: [4096]u8 = undefined;
        var input = Io.File.stdin().readerStreaming(init.io, &input_buffer);
        var output = Io.File.stdout().writerStreaming(init.io, &output_buffer);
        try @import("zig_project_server.zig").run(backing, init.io, &input.interface, &output.interface, compiler_identity.digest);
        return true;
    }
    const command = (if (std.mem.eql(u8, args[1], "parse-project")) Command.parse_project else if (std.mem.eql(u8, args[1], "check-project")) Command.check_project else if (std.mem.eql(u8, args[1], "build-project")) Command.build_project else std.meta.stringToEnum(Command, args[1])) orelse {
        try Io.File.stderr().writeStreamingAll(init.io, usage);
        return false;
    };
    if (args.len < 3 or ((command == .build or command == .build_project or command == .dependencies) and args.len < 4)) {
        try Io.File.stderr().writeStreamingAll(init.io, usage);
        return false;
    }
    var buffer: [4096]u8 = undefined;
    var output = Io.File.stdout().writerStreaming(init.io, &buffer);
    defer output.interface.flush() catch {};
    const project_command = command == .parse_project or command == .check_project or command == .build_project or command == .dependencies;
    var first_option = if (command == .build or command == .build_project or command == .dependencies) @as(usize, 4) else @as(usize, 3);
    if (!project_command and command != .build) {
        first_option = args.len;
        for (args[3..], 3..) |arg, index| if (std.mem.startsWith(u8, arg, "--")) {
            first_option = index;
            break;
        };
    }
    if (project_command or first_option < args.len) {
        if (command == .lex) return false;
        var aliases: std.ArrayList(project.Alias) = .empty;
        defer aliases.deinit(backing);
        var options: project.Options = .{};
        var dependency_path: ?[]const u8 = null;
        var at = first_option;
        while (at < args.len) : (at += 2) {
            if (at + 1 >= args.len) return false;
            if (std.mem.eql(u8, args[at], "--std-root")) {
                options.std_root = args[at + 1];
            } else if (std.mem.eql(u8, args[at], "--alias")) {
                const split = std.mem.indexOfScalar(u8, args[at + 1], '=') orelse return false;
                try aliases.append(backing, .{ .prefix = args[at + 1][0..split], .root = args[at + 1][split + 1 ..] });
            } else if (std.mem.eql(u8, args[at], "--input-mode")) {
                options.input_mode = std.meta.stringToEnum(project.InputMode, args[at + 1]) orelse return false;
            } else if (std.mem.eql(u8, args[at], "--prelude")) {
                options.prelude_path = if (std.mem.eql(u8, args[at + 1], "none")) null else args[at + 1];
            } else if (std.mem.eql(u8, args[at], "--dependencies")) {
                if ((command != .build and command != .build_project) or dependency_path != null) return false;
                dependency_path = args[at + 1];
            } else return false;
        }
        options.aliases = aliases.items;
        if (command == .dependencies or dependency_path != null) {
            const success = try dependency_cli.process(init.io, backing, &output.interface, command == .dependencies, args[2], args[3], dependency_path, options, compiler_identity.digest);
            try output.interface.flush();
            return success;
        }
        const selected: Command = switch (command) {
            .parse, .parse_project => .parse_project,
            .check, .check_project => .check_project,
            .build, .build_project => .build_project,
            else => unreachable,
        };
        const inputs = if (selected == .build_project or project_command) args[2..3] else args[2..first_option];
        var success = true;
        for (inputs) |filename| {
            const ok = processProject(init.io, backing, &output.interface, selected, filename, options, if (selected == .build_project) args[3] else null) catch |err| {
                const stage = switch (selected) {
                    .parse_project => "parse-project",
                    .check_project => "check-project",
                    else => "build-project",
                };
                try diagnostic(&output.interface, filename, stage, @errorName(err), 0, 0, "Compiler operation failed");
                try output.interface.flush();
                return false;
            };
            success = success and ok;
        }
        try output.interface.flush();
        return success;
    }
    var success = true;
    const inputs = if (command == .build) args[2..3] else args[2..];
    for (inputs) |filename| {
        const ok = process(init.io, backing, &output.interface, command, filename, if (command == .build) args[3] else null) catch |err| {
            try diagnostic(&output.interface, filename, @tagName(command), @errorName(err), 0, 0, "Compiler operation failed");
            success = false;
            continue;
        };
        success = success and ok;
    }
    try output.interface.flush();
    return success;
}
pub fn main(init: std.process.Init) void {
    const success = run(init) catch |err| {
        std.debug.print("blotc: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    if (!success) std.process.exit(1);
}
