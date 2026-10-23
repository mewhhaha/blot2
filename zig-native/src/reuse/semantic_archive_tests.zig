const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const identity = @import("../backend/runtime_identity.zig");
const checkpoint = @import("../backend/backend_checkpoint.zig");
const archive = @import("semantic_archive.zig");
const format = @import("dependency_format.zig");
const portable = @import("portable_query.zig");
const a = std.testing.allocator;
const compiler: [32]u8 = @splat(23);

fn originArchive(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var semantic = try format.decodeWithLimits(archive.Snapshot, allocator, bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(allocator, &semantic);
    try std.testing.expect(semantic.evaluator.code_origins.len > 0);
    try archive.validate(allocator, &semantic);
}

test "persisted generated origins own exact source nodes and reject forged catalogs through OOM" {
    const staged =
        \\const make = fn (value: U32) => @code.quote (@code.lift value)
        \\const first = make 41
        \\const second = make 42
        \\const choices = {first: first, second: second}
        \\const number = @code.run choices.second
    ;
    const ordinary = try std.mem.replaceOwned(u8, a, source, "factory 42", "factory number");
    defer a.free(ordinary);
    const text = try std.mem.concat(a, u8, &.{ staged, "\n", ordinary });
    defer a.free(text);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var compiled = try fixture.compile(a, null);
    defer compiled.deinit(a);
    try successful(&compiled);
    const bytes = (try archive.encode(a, compiler, &compiled.capture.?)).?;
    defer a.free(bytes);
    try originArchive(a, bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, originArchive, .{bytes});
    var semantic = try format.decodeWithLimits(archive.Snapshot, a, bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &semantic);
    const record = &semantic.evaluator.code_origins[0];
    const saved = record.*;
    record.value = @intCast(semantic.evaluator.values.len);
    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &semantic));
    record.* = saved;
    record.generator.unit = @intCast(semantic.units.len + 1);
    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &semantic));
    record.* = saved;
    record.generator.node = @intCast(semantic.units[saved.generator.unit - 1].core.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &semantic));
    record.* = saved;
    try archive.validate(a, &semantic);
}

// A captured callback specialized at a typed entry, a nominal payload and a
// recursive helper: the selected receipt replays the closure graph.
const source =
    \\type Box is data = #Box U32
    \\const open = fn (box: Box) -> U32 => case box of
    \\  #Box value => value
    \\const factory = fn number => fn extra => @u32.add number (open (#Box extra))
    \\const callback = factory 42
    \\const count = fn (n: U32) -> U32 => if @u32.eq n 0 then 0 else @u32.add 1 (count (@u32.sub n 1))
    \\entry const schema: U32 = 7
    \\entry const answer = fn (extra: U32) -> U32 => callback (@u32.add extra (count 3))
;
const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,
    fn init(text: []const u8) !Fixture {
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        for (tree.diagnostics.items) |issue| std.debug.print("semantic archive parse {d}: {s}\n", .{ issue.start, issue.message() });
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        for (checked.diagnostics) |issue| std.debug.print("semantic archive fixture {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/semantic/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        a.free(self.units);
        self.names.deinit(a);
    }
    fn compile(self: *const Fixture, allocator: std.mem.Allocator, loaded: ?*const checkpoint.Checkpoint) !backend.Result {
        // These laws need an independently selected callable to exercise the
        // semantic archive. Inlining can legitimately eliminate that receipt.
        return backend.compileWithOptions(allocator, self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .checkpoint = loaded, .inline_named = false });
    }
};
fn successful(result: *const backend.Result) !void {
    if (result.diagnostic) |issue| std.debug.print("semantic archive backend {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
    try std.testing.expect(result.diagnostic == null);
}
/// The producer and its Core are released before decoding, as at restart.
fn produce(text: []const u8) ![]u8 {
    var before = try Fixture.init(text);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    try successful(&initial);
    try std.testing.expect(initial.capture.?.metadata.specialization_queries.records.items.len > 0);
    return checkpoint.encode(a, compiler, &initial.capture.?);
}
fn restartScenario(allocator: std.mem.Allocator, fixture: *const Fixture, bytes: []const u8, expected: []const u8) !void {
    var loaded = try checkpoint.decode(allocator, compiler, bytes);
    defer loaded.deinit();
    try std.testing.expect(loaded.semantic != null);
    var restarted = try fixture.compile(allocator, &loaded);
    defer restarted.deinit(allocator);
    try successful(&restarted);
    try std.testing.expect(restarted.completed_queries.reused > 0);
    try std.testing.expectEqualSlices(u8, expected, restarted.bytes);
}

fn inlinedRestart(allocator: std.mem.Allocator, fixture: *const Fixture, bytes: []const u8, expected: []const u8) !void {
    var loaded = try checkpoint.decode(allocator, compiler, bytes);
    defer loaded.deinit();
    try std.testing.expect(loaded.semantic == null);
    var restarted = try backend.compileWithOptions(allocator, fixture.units, 1, .{ .identity = fixture.names.view(), .retain_artifacts = true, .checkpoint = &loaded });
    defer restarted.deinit(allocator);
    try successful(&restarted);
    try std.testing.expectEqualSlices(u8, expected, restarted.bytes);
}

test "inlined callbacks preserve checkpoint restart without a semantic owner through OOM" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try backend.compileWithOptions(a, fixture.units, 1, .{ .identity = fixture.names.view(), .retain_artifacts = true });
    defer fresh.deinit(a);
    try successful(&fresh);
    const semantic = try archive.encode(a, compiler, &fresh.capture.?);
    defer if (semantic) |bytes| a.free(bytes);
    try std.testing.expect(semantic == null);
    const bytes = try checkpoint.encode(a, compiler, &fresh.capture.?);
    defer a.free(bytes);
    try inlinedRestart(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, inlinedRestart, .{ &fixture, bytes, fresh.bytes });
}

test "portable identity rank checkpoints admit canonical ordinal evidence after frontend teardown" {
    const rank_source =
        \\const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = fn identity => fn value => (identity value, identity (@u32.to_f32 value))
        \\const id: forall [a] => a -> a = fn value => value
        \\entry const whole = fn (value: U32) => @product.get (two id value) 0
        \\entry const fraction = fn (value: U32) => @product.get (two id value) 1
    ;
    var fixture = try Fixture.init(rank_source);
    defer fixture.deinit();
    var initial = try fixture.compile(a, null);
    defer initial.deinit(a);
    try successful(&initial);
    const bytes = try checkpoint.encode(a, compiler, &initial.capture.?);
    defer a.free(bytes);
    var decoded = try checkpoint.decode(a, compiler, bytes);
    defer decoded.deinit();
    var restarted = try fixture.compile(a, &decoded);
    defer restarted.deinit(a);
    try successful(&restarted);
    try std.testing.expect(restarted.runtime_optimization.reused > 0);
    try std.testing.expectEqualSlices(u8, initial.bytes, restarted.bytes);
}

test "persisted typed staging validates code owners replacements descriptors and restart through OOM" {
    const staged_source =
        \\effect Read: Unit -> U32
        \\const delayed = @code.quote (Read ())
        \\const delayed_shape = @code.describe delayed
        \\const other = @code.quote #True
        \\const pair = @code.quote (@code.lift (0, #True))
        \\const pair_value = @code.run pair
        \\const make = fn (step: U32) => @code.quote (@code.lift step)
        \\const generated = make 42
        \\const composed = @code.quote (@code.splice generated)
        \\const shape = @code.describe generated
        \\const same = @descriptor.same shape.result shape.result
        \\const effects_same = @descriptor.same delayed_shape.result shape.result
        \\const number = if @code.run other then if same then if effects_same then @u32.add (@product.get pair_value 0) (@code.run composed) else 0 else 0 else 0
        \\
    ;
    const ordinary = try std.mem.replaceOwned(u8, a, source, "factory 42", "factory number");
    defer a.free(ordinary);
    const text = try std.mem.concat(a, u8, &.{ staged_source, ordinary });
    defer a.free(text);
    const bytes = try produce(text);
    defer a.free(bytes);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    try restartScenario(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, restartScenario, .{ &fixture, bytes, fresh.bytes });
    const semantic_bytes = (try archive.encode(a, compiler, &fresh.capture.?)).?;
    defer a.free(semantic_bytes);
    var snapshot = try format.decodeWithLimits(archive.Snapshot, a, semantic_bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &snapshot);
    var codes: usize = 0;
    var descriptors: usize = 0;
    var scalar_mutants: usize = 0;
    var splice_mutants: usize = 0;
    var product_mutants: usize = 0;
    var effect_mutants: usize = 0;
    for (snapshot.evaluator.values, 0..) |*value, id| {
        const saved = value.*;
        if (value.kind == .code) {
            codes += 1;
            value.bits = @intCast(snapshot.evaluator.closures.len);
            try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
            value.* = saved;
            const closure = &snapshot.evaluator.closures[value.bits];
            const metadata = closure.*;
            closure.identity = @intCast(snapshot.units[closure.unit - 1].core.nodes.len);
            try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
            closure.* = metadata;
            if (snapshot.evaluator.value_evidence[id] != 0) {
                const evidence_node = snapshot.evaluator.evidence.nodes[snapshot.evaluator.value_evidence[id]];
                const result = &snapshot.evaluator.evidence.extra[evidence_node.c + 1];
                const original_result = result.*;
                result.* = @import("../check/types.zig").f32_type;
                try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
                result.* = original_result;
                const latent = &snapshot.evaluator.evidence.nodes[snapshot.evaluator.evidence.extra[evidence_node.c + 2]];
                if (latent.c != 0) {
                    effect_mutants += 1;
                    const original_row = latent.c;
                    latent.c = 0;
                    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
                    latent.c = original_row;
                }
            }
            for (snapshot.evaluator.children[value.start..][0..value.len]) |child| {
                const replacement = &snapshot.evaluator.values[child];
                const original = replacement.*;
                const payload_id = snapshot.evaluator.children[replacement.start];
                const payload = &snapshot.evaluator.values[payload_id];
                const original_payload = payload.*;
                payload.kind = .provider;
                try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
                payload.* = original_payload;
                if (payload.kind == .scalar) {
                    scalar_mutants += 1;
                    const original_evidence = snapshot.evaluator.value_evidence[payload_id];
                    snapshot.evaluator.value_evidence[payload_id] = 0;
                    payload.scalar = .f32;
                    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
                    payload.* = original_payload;
                    snapshot.evaluator.value_evidence[payload_id] = original_evidence;
                } else if (payload.kind == .product) {
                    product_mutants += 1;
                    const member = &snapshot.evaluator.values[snapshot.evaluator.children[payload.start]];
                    const original_member = member.*;
                    member.kind = .provider;
                    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
                    member.* = original_member;
                    const original_child = snapshot.evaluator.children[payload.start];
                    snapshot.evaluator.children[payload.start] = payload_id;
                    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
                    snapshot.evaluator.children[payload.start] = original_child;
                } else if (payload.kind == .code) {
                    const wrong = for (snapshot.evaluator.values[0..child], 0..) |candidate, candidate_id| {
                        if (candidate.kind != .code) continue;
                        const candidate_owner = snapshot.evaluator.closures[candidate.bits];
                        const module = &snapshot.units[candidate_owner.unit - 1].core;
                        const shape = @import("../check/typed_staging.zig").codeInfo(&module.types, candidate_owner.ty).?;
                        if (shape.result == @import("../check/types.zig").boolean) break candidate_id;
                    } else return error.TestUnexpectedResult;
                    splice_mutants += 1;
                    snapshot.evaluator.children[replacement.start] = @intCast(wrong);
                    try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
                    snapshot.evaluator.children[replacement.start] = payload_id;
                }
                replacement.bits = @backingInt(@import("../check/typed_staging.zig").Op.emit);
                try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
                replacement.* = original;
            }
        } else if (value.kind == .descriptor) {
            descriptors += 1;
            value.nominal = snapshot.evaluator.evidence.nodes.len;
            try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
            value.* = saved;
        }
    }
    try std.testing.expect(codes != 0 and descriptors != 0 and scalar_mutants != 0 and splice_mutants != 0 and product_mutants != 0 and effect_mutants != 0);
    try archive.validate(a, &snapshot);

    // Unsupported live staging values omit the entire semantic section. The
    // public checkpoint remains exportable and restart recompiles correctly.
    const retained = &fresh.capture.?.metadata.pools.?.evaluator;
    const unsupported = for (retained.values) |value| {
        if (value.kind != .code or value.len == 0) continue;
        const replacement = retained.values[retained.children[value.start]];
        const payload = &retained.values[retained.children[replacement.start]];
        if (payload.kind == .scalar) break payload;
    } else return error.TestUnexpectedResult;
    const retained_value = unsupported.*;
    unsupported.kind = .provider;
    const missing = try archive.encode(a, compiler, &fresh.capture.?);
    try std.testing.expectEqual(@as(?[]u8, null), missing);
    const fallback_bytes = try checkpoint.encode(a, compiler, &fresh.capture.?);
    defer a.free(fallback_bytes);
    unsupported.* = retained_value;
    var fallback = try checkpoint.decode(a, compiler, fallback_bytes);
    defer fallback.deinit();
    try std.testing.expect(fallback.semantic == null);
    var recomputed = try fixture.compile(a, &fallback);
    defer recomputed.deinit(a);
    try successful(&recomputed);
    try std.testing.expectEqualSlices(u8, fresh.bytes, recomputed.bytes);
}

test "persisted typed staging preserves ordinary snapshot allocation cost" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    const bytes = (try archive.encode(a, compiler, &fresh.capture.?)).?;
    defer a.free(bytes);
    var snapshot = try format.decodeWithLimits(archive.Snapshot, a, bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &snapshot);
    for (snapshot.evaluator.values) |value| try std.testing.expect(value.kind != .code and value.kind != .descriptor);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try @import("../check/staging_snapshot.zig").validate(failing.allocator(), &snapshot.evaluator, snapshot.units);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), failing.allocations);
}

test "persisted typed staging seals package recipes and never exposes cached bound descriptors through OOM" {
    const text =
        \\type Item = exists [a] => (a, a -> U32)
        \\const generated = @code.quote (fn (flag: Bool) -> Item ! {} => if flag then pack [U32] (42, fn number => number) as Item else pack [Bool] (flag, fn truth => if truth then 9 else 7) as Item)
        \\const sealed = @code.quote (pack [U32] (42, fn number => number) as Item)
        \\const shape = (@code.describe sealed).result
        \\const same = @descriptor.same shape shape
        \\const read: Item -> U32 = fn item => unpack item as [a] value in (@product.get value 1) (@product.get value 0)
        \\const factory = fn (number: U32) => fn (extra: U32) => @u32.add number extra
        \\const callback = factory (if same then read (@code.run sealed) else 0)
        \\entry const answer = fn (flag: Bool) => @u32.add (read ((@code.emit generated) flag)) (callback 0)
    ;
    const bytes = try produce(text);
    defer a.free(bytes);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    try restartScenario(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, restartScenario, .{ &fixture, bytes, fresh.bytes });
    const semantic_bytes = (try archive.encode(a, compiler, &fresh.capture.?)) orelse return error.MissingSemanticSnapshot;
    defer a.free(semantic_bytes);
    var snapshot = try format.decodeWithLimits(archive.Snapshot, a, semantic_bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &snapshot);
    const bound = for (snapshot.evaluator.evidence.nodes, 0..) |node, id| {
        if (node.tag == .bound) break id;
    } else return error.MissingBoundRecipe;
    var descriptors: usize = 0;
    for (snapshot.evaluator.values, 0..) |*value, id| {
        if (value.kind != .descriptor) continue;
        const original = value.*;
        const evidence = snapshot.evaluator.value_evidence[id];
        value.nominal = bound;
        snapshot.evaluator.value_evidence[id] = 0;
        try std.testing.expectError(error.InvalidArtifact, @import("../check/staging_snapshot.zig").validate(a, &snapshot.evaluator, snapshot.units));
        value.* = original;
        snapshot.evaluator.value_evidence[id] = evidence;
        descriptors += 1;
    }
    try std.testing.expect(descriptors != 0);
    try archive.validate(a, &snapshot);
}

test "persisted typed staging reconstructs nominal constructor substitutions and payloads" {
    const staged_source =
        \\type Packet a is data = #Packet {item: a}
        \\type Option a is data = #Absent | #Present a
        \\const make = fn (value: Option (Packet U32)) => @code.quote (@code.lift value)
        \\const generated = make (#Present (#Packet {item: 42}))
        \\const empty = make #Absent
        \\const floating = @code.quote (@code.lift (#Packet {item: 2.0}))
        \\const inspected = @code.describe generated
        \\const same = @descriptor.same inspected.result (@code.describe empty).result
        \\const restored = @code.run generated
        \\const number = case restored of
        \\  #Absent => 0
        \\  #Present (#Packet value) => if same then value else 0
        \\
    ;
    const ordinary = try std.mem.replaceOwned(u8, a, source, "factory 42", "factory number");
    defer a.free(ordinary);
    const text = try std.mem.concat(a, u8, &.{ staged_source, ordinary });
    defer a.free(text);
    const bytes = try produce(text);
    defer a.free(bytes);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    try restartScenario(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, restartScenario, .{ &fixture, bytes, fresh.bytes });
    const semantic_bytes = (try archive.encode(a, compiler, &fresh.capture.?)) orelse return error.MissingSemanticSnapshot;
    defer a.free(semantic_bytes);
    var snapshot = try format.decodeWithLimits(archive.Snapshot, a, semantic_bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &snapshot);
    var mutants: usize = 0;
    for (snapshot.evaluator.values) |code_value| {
        if (code_value.kind != .code) continue;
        for (snapshot.evaluator.children[code_value.start..][0..code_value.len]) |replacement_id| {
            const replacement = snapshot.evaluator.values[replacement_id];
            const payload_id = snapshot.evaluator.children[replacement.start];
            const value = &snapshot.evaluator.values[payload_id];
            if (value.kind != .nominal) continue;
            const saved = value.*;
            value.bits = std.math.maxInt(u32);
            try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
            value.* = saved;
            if (value.len != 1) continue;
            const original_child = snapshot.evaluator.children[value.start];
            snapshot.evaluator.children[value.start] = payload_id;
            try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
            snapshot.evaluator.children[value.start] = original_child;
            var member_id = original_child;
            while (snapshot.evaluator.values[member_id].kind != .scalar) {
                const member = snapshot.evaluator.values[member_id];
                try std.testing.expect(member.len != 0);
                member_id = snapshot.evaluator.children[member.start];
            }
            const member = &snapshot.evaluator.values[member_id];
            if (member.scalar != .u32) continue;
            const original_member = member.*;
            const original_evidence = snapshot.evaluator.value_evidence[member_id];
            snapshot.evaluator.value_evidence[member_id] = 0;
            member.scalar = .f32;
            try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
            member.* = original_member;
            snapshot.evaluator.value_evidence[member_id] = original_evidence;
            mutants += 1;
        }
    }
    try std.testing.expect(mutants != 0);
    var owner_mutants: usize = 0;
    for (snapshot.units) |*unit| for (unit.core.constructors) |*constructor| {
        if (constructor.scheme.variables.len == 0) continue;
        const saved = constructor.scheme.variables;
        constructor.scheme.variables = .{};
        try std.testing.expectError(error.InvalidArtifact, archive.validate(a, &snapshot));
        constructor.scheme.variables = saved;
        owner_mutants += 1;
    };
    try std.testing.expect(owner_mutants != 0);
    try archive.validate(a, &snapshot);
}

test "persisted typed staging opaque record lifts preserve whole producer payloads through OOM" {
    const text =
        \\opaque type Token = {item: U32}
        \\private const make = fn (number: U32) => #Token {item: number}
        \\private const open = fn (token: Token) => case token of
        \\  #Token payload => payload.item
        \\const generated = @code.quote (@code.lift (make 42))
        \\const restored = @code.run generated
        \\const factory = fn (number: U32) => fn (extra: U32) => @u32.add number extra
        \\const callback = factory (open restored)
        \\entry const answer = fn (extra: U32) => callback extra
    ;
    const bytes = try produce(text);
    defer a.free(bytes);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    try restartScenario(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, restartScenario, .{ &fixture, bytes, fresh.bytes });
}

test "persisted semantic owners replay selected receipts after restart and match fresh output through allocation failures" {
    const bytes = try produce(source);
    defer a.free(bytes);
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    try restartScenario(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, restartScenario, .{ &fixture, bytes, fresh.bytes });
}

test "persisted semantic owners follow edited bodies and failed sources like fresh compilation" {
    const bytes = try produce(source);
    defer a.free(bytes);
    var loaded = try checkpoint.decode(a, compiler, bytes);
    defer loaded.deinit();
    for ([_][]const u8{ "#Box value => @u32.add value 1", "factory 43", "@u32.eq n 1" }) |replacement| {
        const anchor = if (std.mem.startsWith(u8, replacement, "#Box")) "#Box value => value" else if (std.mem.startsWith(u8, replacement, "factory")) "factory 42" else "@u32.eq n 0";
        const edited = try std.mem.replaceOwned(u8, a, source, anchor, replacement);
        defer a.free(edited);
        var fixture = try Fixture.init(edited);
        defer fixture.deinit();
        var fresh = try fixture.compile(a, null);
        defer fresh.deinit(a);
        try successful(&fresh);
        var restarted = try fixture.compile(a, &loaded);
        defer restarted.deinit(a);
        try successful(&restarted);
        try std.testing.expectEqualSlices(u8, fresh.bytes, restarted.bytes);
    }
    // A source that fails to compile reports the fresh diagnostic.
    const broken = try std.mem.replaceOwned(u8, a, source, "entry const schema: U32 = 7", "entry const schema: U32 = @u32.div 8 0");
    defer a.free(broken);
    var fixture = try Fixture.init(broken);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    var restarted = try fixture.compile(a, &loaded);
    defer restarted.deinit(a);
    try std.testing.expect(fresh.diagnostic != null);
    try std.testing.expectEqualDeep(fresh.diagnostic, restarted.diagnostic);
}

fn rejects(expected: anyerror, snapshot: archive.Snapshot) !void {
    const bytes = try format.encodeWithLimits(a, archive.wireKey(compiler), snapshot, archive.limits);
    defer a.free(bytes);
    try std.testing.expectError(expected, archive.decode(a, compiler, bytes));
}
fn accepts(snapshot: archive.Snapshot) !void {
    const bytes = try format.encodeWithLimits(a, archive.wireKey(compiler), snapshot, archive.limits);
    defer a.free(bytes);
    var owner = try archive.decode(a, compiler, bytes);
    owner.deinit();
}

test "persisted semantic owners reject forged namespaces graphs ordinals and receipts before exposure" {
    const bytes = blk: {
        var before = try Fixture.init(source);
        defer before.deinit();
        var initial = try before.compile(a, null);
        defer initial.deinit(a);
        try successful(&initial);
        break :blk (try archive.encode(a, compiler, &initial.capture.?)).?;
    };
    defer a.free(bytes);
    try std.testing.expectError(error.StaleArtifact, archive.decode(a, @splat(24), bytes));
    try std.testing.expectError(error.InvalidArtifact, archive.decode(a, compiler, bytes[0 .. bytes.len - 1]));
    var owner = try format.decodeWithLimits(archive.Snapshot, a, bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &owner);
    try accepts(owner);
    {
        var copy = owner;
        copy.queries.header.version += 1;
        try rejects(error.UnsupportedVersion, copy);
        copy.queries.header = portable.header(.principal_complete_proof);
        try rejects(error.SchemaMismatch, copy);
    }
    const unit = owner.units[0];
    var units = [_]archive.Unit{unit};
    var copy = owner;
    copy.units = &units;
    {
        var path = "/semantic/other.blot".*;
        units[0].canonical_path = &path;
        try rejects(error.InvalidArtifact, copy);
        units[0] = unit;
        units[0].unit = 2;
        try rejects(error.InvalidArtifact, copy);
        units[0] = unit;
        var short = [_]u32{1};
        units[0].certificates = &short;
        try rejects(error.InvalidArtifact, copy);
        units[0] = unit;
        units[0].core.bindings = &.{};
        try rejects(error.InvalidArtifact, copy);
        units[0] = unit;
    }
    const evaluator = owner.evaluator;
    {
        const children = try a.dupe(u32, evaluator.children);
        defer a.free(children);
        try std.testing.expect(children.len != 0);
        copy.evaluator.children = children;
        children[0] = @intCast(evaluator.values.len);
        try rejects(error.InvalidArtifact, copy);
        copy.evaluator = evaluator;
        const values = try a.dupe(@TypeOf(evaluator.values[0]), evaluator.values);
        defer a.free(values);
        copy.evaluator.values = values;
        for (values) |*value| if (value.kind == .closure) {
            value.bits = @intCast(evaluator.closures.len);
            break;
        };
        try rejects(error.InvalidArtifact, copy);
        copy.evaluator = evaluator;
    }
    {
        try std.testing.expect(owner.slots.len > 1);
        copy.slots = owner.slots[0 .. owner.slots.len - 1];
        try rejects(error.InvalidArtifact, copy);
        const slots = try a.dupe(@TypeOf(owner.slots[0]), owner.slots);
        defer a.free(slots);
        slots[0].value = @intCast(evaluator.values.len);
        copy.slots = slots;
        try rejects(error.InvalidArtifact, copy);
        copy.slots = owner.slots;
    }
    {
        try std.testing.expect(owner.queries.records.len > 0);
        const first = owner.queries.records[0];
        var records = [_]archive.Record{first};
        copy.queries.records = &records;
        try accepts(copy);
        records[0].key.input = 0;
        try rejects(error.InvalidArtifact, copy);
        records[0] = first;
        records[0].key.expected = 1;
        try rejects(error.InvalidArtifact, copy);
        records[0] = first;
        records[0].result.selected = @intCast(evaluator.values.len);
        try rejects(error.InvalidArtifact, copy);
        records[0] = first;
        const forged = [_]core.BindingRef{.{ .unit = 2, .binding = 1 }};
        records[0].dependencies.sources = @constCast(&forged);
        try rejects(error.InvalidArtifact, copy);
        records[0] = first;
        records[0].dependencies.values_added = evaluator.values.len + 1;
        try rejects(error.InvalidArtifact, copy);
        copy.queries.records = owner.queries.records;
    }
    if (owner.field_locations.len != 0) {
        const fields = try a.dupe(@TypeOf(owner.field_locations[0]), owner.field_locations);
        defer a.free(fields);
        fields[0].name = @intCast(owner.identity.symbols.len);
        copy.field_locations = fields;
        try rejects(error.InvalidArtifact, copy);
        copy.field_locations = owner.field_locations;
    }
}

test "persisted semantic owners with a forged stamp decode but admit no receipt" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    try successful(&initial);
    const bytes = (try archive.encode(a, compiler, &initial.capture.?)).?;
    defer a.free(bytes);
    var owner = try format.decodeWithLimits(archive.Snapshot, a, bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(a, &owner);
    owner.units[0].stamp[0] ^= 1;
    const forged = try format.encodeWithLimits(a, archive.wireKey(compiler), owner, archive.limits);
    defer a.free(forged);
    var semantic = try archive.decode(a, compiler, forged);
    var loaded: checkpoint.Checkpoint = .{ .principal = .{ .allocator = a, .snapshot = .{ .modules = &.{}, .namespace = @splat(0), .queries = .{ .header = portable.header(.principal_complete_proof), .records = &.{} }, .evidence = emptyEvidence() } }, .optimizer = null, .semantic = semantic };
    semantic = undefined;
    defer loaded.semantic.?.deinit();
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    var restarted = try fixture.compile(a, &loaded);
    defer restarted.deinit(a);
    try successful(&restarted);
    try std.testing.expectEqual(@as(usize, 0), restarted.completed_queries.reused);
    try std.testing.expectEqualSlices(u8, fresh.bytes, restarted.bytes);
}
fn emptyEvidence() @import("../eval/type_evidence.zig").Snapshot {
    return .{ .nodes = &.{}, .extra = &.{}, .effects = .{ .operations = &.{}, .arguments = &.{}, .rows = &.{}, .labels = &.{} } };
}

test "semantic archives omit owners without a complete project namespace or a replayable receipt" {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var anonymous = try backend.compileWithOptions(a, fixture.units, 1, .{ .retain_artifacts = true });
    defer anonymous.deinit(a);
    try successful(&anonymous);
    try std.testing.expect((try archive.encode(a, compiler, &anonymous.capture.?)) == null);
    var plain = try Fixture.init("entry const answer = fn (x: U32) -> U32 => @u32.add x 1");
    defer plain.deinit();
    var compiled = try plain.compile(a, null);
    defer compiled.deinit(a);
    try successful(&compiled);
    try std.testing.expectEqual(@as(usize, 0), compiled.capture.?.metadata.specialization_queries.records.items.len);
    try std.testing.expect((try archive.encode(a, compiler, &compiled.capture.?)) == null);
    const bytes = try checkpoint.encode(a, compiler, &compiled.capture.?);
    defer a.free(bytes);
    var loaded = try checkpoint.decode(a, compiler, bytes);
    defer loaded.deinit();
    try std.testing.expect(loaded.semantic == null);
}

fn memberArchiveText() ![]u8 {
    var expression = try a.dupe(u8, "@array.length values");
    defer a.free(expression);
    for (0..80) |_| {
        const next = try a.print("@u32.add 0 ({s})", .{expression});
        a.free(expression);
        expression = next;
    }
    return a.print("const Array.count = fn values => {s}\nentry const warm: U32 = #[].count\nentry const result: U32 = #[].count\n", .{expression});
}
fn memberArchiveScenario(allocator: std.mem.Allocator, fixture: *const Fixture, captured: *const @import("artifact_capture.zig").Capture, expected: []const u8, portable_count: usize) !void {
    const bytes = (try archive.encode(allocator, compiler, captured)).?;
    defer allocator.free(bytes);
    var wire = try format.decodeWithLimits(archive.Snapshot, allocator, bytes, archive.wireKey(compiler), archive.limits);
    defer format.deinit(allocator, &wire);
    try std.testing.expectEqual(portable_count, wire.queries.records.len);
    var owner = try archive.decode(allocator, compiler, bytes);
    defer owner.deinit();
    for (owner.capture.metadata.specialization_queries.records.items) |query| {
        try std.testing.expect(query.dependencies.member == null);
    }
    const checkpoint_bytes = try checkpoint.encode(allocator, compiler, captured);
    defer allocator.free(checkpoint_bytes);
    try restartScenario(allocator, fixture, checkpoint_bytes, expected);
}
test "persisted semantic owners omit member authority while retaining old valid receipts and OOM restart" {
    const member_text = try memberArchiveText();
    defer a.free(member_text);
    var only = try Fixture.init(member_text);
    defer only.deinit();
    var only_result = try only.compile(a, null);
    defer only_result.deinit(a);
    try successful(&only_result);
    try std.testing.expectEqual(@as(usize, 1), only_result.capture.?.metadata.specialization_queries.records.items.len);
    try std.testing.expect(only_result.capture.?.metadata.specialization_queries.records.items[0].dependencies.member != null);
    try std.testing.expectEqual(@as(?[]u8, null), try archive.encode(a, compiler, &only_result.capture.?));
    const mixed = try a.print("{s}\n{s}", .{ source, member_text });
    defer a.free(mixed);
    var fixture = try Fixture.init(mixed);
    defer fixture.deinit();
    var initial = try fixture.compile(a, null);
    defer initial.deinit(a);
    try successful(&initial);
    var ordinary: usize = 0;
    var members: usize = 0;
    for (initial.capture.?.metadata.specialization_queries.records.items) |query| {
        if (query.dependencies.member != null) {
            members += 1;
        } else if (@import("../eval/selected_query.zig").Adapter.complete(query)) ordinary += 1;
    }
    try std.testing.expect(ordinary != 0 and members != 0);
    try memberArchiveScenario(a, &fixture, &initial.capture.?, initial.bytes, ordinary);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, memberArchiveScenario, .{ &fixture, &initial.capture.?, initial.bytes, ordinary });
}

test "persisted typed staging statement if helper restarts through OOM" {
    const text =
        \\const choose = fn (value: U32) => do:
        \\  if @u32.eq value 0:
        \\    let value = 40
        \\    break value
        \\  break @u32.add value 40
        \\const generated = @code.quote (choose 2)
        \\const factory = fn number => fn extra => @u32.add number extra
        \\const callback = factory (@code.run generated)
        \\entry const answer = fn (extra: U32) => callback extra
    ;
    const bytes = try produce(text);
    defer a.free(bytes);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    try restartScenario(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, restartScenario, .{ &fixture, bytes, fresh.bytes });
}

test "persisted typed staging Boolean case helper restarts through OOM" {
    const text =
        \\const choose = fn (flag: Bool) => case flag of
        \\  #False => 42
        \\  #True => do:
        \\    let flag = 40
        \\    break flag
        \\const generated = @code.quote (choose #False)
        \\const factory = fn number => fn extra => @u32.add number extra
        \\const callback = factory (@code.run generated)
        \\entry const answer = fn (extra: U32) => callback extra
    ;
    const bytes = try produce(text);
    defer a.free(bytes);
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    var fresh = try fixture.compile(a, null);
    defer fresh.deinit(a);
    try successful(&fresh);
    try restartScenario(a, &fixture, bytes, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, restartScenario, .{ &fixture, bytes, fresh.bytes });
}
