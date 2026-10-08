const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;

const declarations =
    \\type Box is data = #Box U32
    \\type Tick is effect = Unit -> Unit
    \\const Box.read: Box -> U32 ! {Tick} where {} = fn (value: Box) => value.read
    \\
;
const missing_entry = declarations ++ "entry const selected: Box -> U32 = fn value => value.read\nentry const answer = 42\n";
const pure_entry = "type Box is data = #Box U32\nconst Box.read: Box -> U32 where {} = fn (value: Box) => value.read\nentry const selected: Box -> U32 = fn value => value.read\nentry const answer = 42\n";
const literal_entry = declarations ++ "entry const selected: Box -> U32 = fn value => 42\nentry const answer = 42\n";
const abi_caller = declarations ++ "entry const selected: Unit -> U32 = fn () => (#Box 1).read\nentry const answer = 42\n";
const called_entry = declarations ++ "entry const selected: Box -> U32 = fn value => value.read\nentry const answer: Unit -> U32 = fn () => selected (#Box 1)\n";
const generic_message = "entry `selected` has a generic type, so it cannot be a Wasm export: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool";

fn lower(source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &tree, &names, &checked);
    errdefer result.deinit(a);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
fn target(module: *const core.Module, name: []const u8) !core.BindingRef {
    for (module.bodies[1..]) |body| if (std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = 1, .binding = body.binding };
    return error.TestUnexpectedResult;
}
fn missingScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(backend.Code.entry_type, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(u32, 152), result.diagnostic.?.span.start);
    try std.testing.expectEqual(@as(u32, 152), result.diagnostic.?.span.end);
    try std.testing.expectEqualStrings(generic_message, result.diagnostic.?.message());
    try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

test "entry phase rejected residual method template reports absent selection under every allocation failure" {
    var module = try lower(missing_entry);
    defer module.deinit(a);
    try missingScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, missingScenario, .{&module});
    var retained = owned: {
        var owner = try lower(missing_entry);
        defer owner.deinit(a);
        break :owned try backend.compile(a, &.{owner}, 1);
    };
    defer retained.deinit(a);
    try std.testing.expectEqualStrings(generic_message, retained.diagnostic.?.message());
}

test "entry phase complete pure and literal nominal interfaces remain selected" {
    for ([_][]const u8{ pure_entry, literal_entry }) |source| {
        var module = try lower(source);
        defer module.deinit(a);
        const units = [_]core.Module{module};
        var session = try eval.Session.init(a, &units);
        defer session.deinit();
        const interface = try session.sourceInterface(try target(&module, "selected"));
        try std.testing.expect(interface.selected);
        try std.testing.expect(!interface.generic);
        try std.testing.expectEqual(@as(usize, 0), interface.pending);
        try std.testing.expect(interface.evidence != 0);
        const arrow = session.evidence.node(interface.evidence);
        try std.testing.expectEqual(@import("type_evidence.zig").Tag.function, arrow.tag);
        try std.testing.expectEqual(@import("type_evidence.zig").Tag.nominal, session.evidence.node(arrow.a).tag);
        try std.testing.expectEqual(@import("type_evidence.zig").Tag.u32, session.evidence.node(arrow.b).tag);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
}
fn attemptThenDemand(allocator: std.mem.Allocator, module: *const core.Module) !void {
    const units = [_]core.Module{module.*};
    var session = try eval.Session.init(allocator, &units);
    defer session.deinit();
    session.options.retain_source_suspensions = true;
    session.retain_specialization_receipts = true;
    const first = try session.sourceInterface(try target(module, "selected"));
    try std.testing.expect(!first.selected);
    try std.testing.expectEqual(@as(u32, 0), first.evidence);
    try std.testing.expectEqual(@as(usize, 0), first.pending);
    try std.testing.expect(session.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), session.owned_diagnostic_message.len);
    try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
    inline for (.{ "children", "closures", "demands", "source_suspensions", "type_mappings", "row_mappings", "specialization_receipts", "pending" }) |field| try std.testing.expectEqual(@as(usize, 0), @field(session, field).items.len);
    inline for (.{ "validated_calls", "plain_nominals", "typed_views", "specialized_closures" }) |field| try std.testing.expectEqual(@as(usize, 0), @field(session, field).count());
    for (session.slots) |slot| {
        try std.testing.expect(slot.state == .unseen);
        try std.testing.expect(!slot.traced);
        try std.testing.expectEqual(@as(u32, 0), slot.value);
    }
    try std.testing.expectEqual(@as(usize, 0), session.traced_bodies);
    try std.testing.expectEqual(@as(usize, 0), session.traced_nodes);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    if (session.sourceInterface(try target(module, "answer"))) |_| return error.TestUnexpectedResult else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => try std.testing.expectEqual(error.Declined, err),
    }
    try std.testing.expectEqual(eval.Code.effect_mismatch, session.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "entry phase discarded nominal attempt publishes no facts and valid caller rechecks its effect" {
    var module = try lower(called_entry);
    defer module.deinit(a);
    try attemptThenDemand(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, attemptThenDemand, .{&module});
    for ([_][]const u8{ abi_caller, called_entry, declarations ++ "entry const ignored: Box -> U32 = fn value => 42\nentry const selected: Unit -> U32 = fn () => (#Box 1).read\n" }) |source| {
        var caller = try lower(source);
        defer caller.deinit(a);
        var result = try backend.compile(a, &.{caller}, 1);
        defer result.deinit(a);
        try std.testing.expectEqual(backend.Code.effect_mismatch, result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
        try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
    }
}

test "entry phase type witnesses and physical collection limits remain authoritative" {
    var witness = try lower("type Box is data = #Box U32\nentry const selected: Box -> Bool = fn value => @type.same (@panic \"left\") (@panic \"right\")\nentry const answer = 42\n");
    defer witness.deinit(a);
    var result = try backend.compile(a, &.{witness}, 1);
    defer result.deinit(a);
    try std.testing.expectEqual(backend.Code.invalid_annotation, result.diagnostic.?.code);
    var module = try lower(missing_entry);
    defer module.deinit(a);
    const units = [_]core.Module{module};
    for (0..2) |mode| for (0..12) |limit| {
        var session = try eval.Session.init(a, &units);
        defer session.deinit();
        if (mode == 0) session.options.max_values = limit else session.options.max_type_depth = limit;
        const interface = session.sourceInterface(try target(&module, "selected")) catch |err| {
            try std.testing.expectEqual(error.Declined, err);
            try std.testing.expectEqual(eval.Code.constant_fuel, session.diagnostic.?.code);
            continue;
        };
        try std.testing.expect(!interface.selected);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    };
}

test "entry phase ordinary initial type failures survive unsupported nominal entry shape" {
    const source = "type Box is data = #Box U32\nentry const selected: Box -> U32 = fn value => @u32.add 1 1.0\nentry const answer = 42\n";
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    var checked = try checker.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    try std.testing.expectEqual(checker.Code.type_mismatch, checked.diagnostics[0].code);
}

test "entry phase source identity and forward declaration order determine discarded selection" {
    const controls = [_]struct { source: []const u8, point: u32, message: []const u8 }{
        .{ .source = "type Box is data = #Box U32\ntype Tick is effect = Unit -> Unit\nentry const selected: Box -> U32 = fn value => value.read\nconst Box.read: Box -> U32 ! {Tick} where {} = fn (value: Box) => value.read\nentry const answer = 42\n", .point = 75, .message = "entry `selected` has a generic type, so it cannot be a Wasm export: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool" },
        .{ .source = "type Parcel is data = #Parcel F32\ntype Move is effect = Unit -> Unit\nentry const unpack: Parcel -> F32 = fn parcel => parcel.unpack\nconst Parcel.unpack: Parcel -> F32 ! {Move} where {} = fn (parcel: Parcel) => parcel.unpack\nentry const answer = 42\n", .point = 81, .message = "entry `unpack` has a generic type, so it cannot be a Wasm export: entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool" },
    };
    for (controls) |control| {
        var module = try lower(control.source);
        defer module.deinit(a);
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expectEqual(backend.Code.entry_type, result.diagnostic.?.code);
        try std.testing.expectEqual(control.point, result.diagnostic.?.span.start);
        try std.testing.expectEqual(control.point, result.diagnostic.?.span.end);
        try std.testing.expectEqualStrings(control.message, result.diagnostic.?.message());
        try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
    }
}

test "source interface inference does not consume the executed expression depth budget" {
    var module = try lower("const leaf = fn value => @u32.add value 1\nconst middle = fn value => leaf value\nentry const answer = fn (value: U32) => middle value\n");
    defer module.deinit(a);
    var session = try eval.Session.init(a, &.{module});
    defer session.deinit();
    session.options.max_depth = 0;
    session.options.max_steps = 0;
    const interface = try session.sourceInterface(try target(&module, "answer"));
    try std.testing.expect(interface.selected);
    try std.testing.expect(session.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
