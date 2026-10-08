//! Real project revisions exercise preparation, caller rejection and transfer.
const std = @import("std");
const retained = @import("retained_revision.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const dependency = @import("frozen_dependency.zig");
const metadata = @import("code_artifacts.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const main = "import * as dep from \"./dep\"\nentry const answer:U32=dep.read ()\n";
const original = "const value:U32=42\nconst read:Unit->U32=fn () => value\n";
const edited = "const value:U32=43\nconst read:Unit->U32=fn () => value\n";

const refinement_source =
    \\const changed = 8
    \\const fixed = 41
    \\const read = fn (value: U32) => @u32.add value fixed
    \\entry const answer = fn (value: U32) => @u32.add (read value) changed
;

const unaffected_producer =
    \\const marker: U32 = 1
    \\const factory = fn number => fn extra => number
    \\const callback = factory 42
;
const unaffected_query_main =
    \\import {marker, callback} from "./dep"
    \\entry const schema: U32 = marker
    \\entry const answer = fn (extra: U32) -> U32 => callback extra
    \\entry const changed = fn (value: U32) -> U32 => @u32.add value 7
    \\const run_value: U32 = callback 0
;
const unaffected_query_edit =
    \\import {marker, callback} from "./dep"
    \\entry const schema: U32 = marker
    \\entry const answer = fn (extra: U32) -> U32 => callback extra
    \\entry const changed = fn (value: U32) -> U32 => @u32.add value 8
    \\const run_value: U32 = callback 0
;

const catalog_producer =
    \\data Box a = #Box a
    \\const changed = fn (value: U32) -> U32 => @u32.add value 7
;
const catalog_consumer =
    \\import {Box, changed} from "./dep"
    \\const factory = fn value => fn () => value
    \\const boxed = factory (#Box 42)
    \\const listed = factory [41]
    \\const arrayed = factory #[43]
    \\entry const answer = fn () => do:
    \\  let #Box value = boxed ()
    \\  return value
    \\entry const list_value = fn () => (@array.from_list (listed ()))[0]
    \\entry const array_value = fn () => (arrayed ())[0]
    \\entry const runtime = fn (value: U32) => changed value
    \\entry const staged = changed 1
;

fn editedCatalog(fixture: *Fixture, number: u8) !void {
    const text = try a.dupe(u8, catalog_producer);
    defer a.free(text);
    text[text.len - 1] = number;
    try fixture.write("dep.blot", text);
}

test "catalog queries survive rebuilt dependencies with exact fresh staging and transactional retry" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("main.blot", catalog_consumer);
    try fixture.write("dep.blot", catalog_producer);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    try std.testing.expect(initial.result.diagnostic == null and initial.result.compiled.diagnostic == null);
    for ([_]u8{ '8', '7', '8' }) |number| {
        try editedCatalog(&fixture, number);
        var expected = try fresh(&fixture, .{});
        defer expected.deinit(a);
        const before = Stamp.read(&session);
        const pending = try ready(&session, &fixture, .{});
        defer pending.deinit();
        try std.testing.expect(pending.stats.rebuilt_seed);
        try equal(pending.result().?, &expected);
        try std.testing.expect(pending.result().?.result.compiled.completed_queries.reused > 0);
        try std.testing.expect(pending.result().?.result.compiled.reuse.reused_named > 0);
        try before.unchanged(&session);
        try std.testing.expect(session.discard(pending));
        try before.unchanged(&session);
        const retry = try ready(&session, &fixture, .{});
        defer retry.deinit();
        try equal(retry.result().?, &expected);
        try std.testing.expect(session.commit(retry));
    }
    try std.testing.expect(!std.mem.eql(u8, initial.result.compiled.bytes, session.current.?.output.?.bytes));
    const before = Stamp.read(&session);
    try fixture.write("dep.blot", "data Box a = #Box a\nconst changed = fn (value: U32) -> U32 => false\n");
    var rejected = try session.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try before.unchanged(&session);
    try editedCatalog(&fixture, '7');
    var restored = try session.revise(io, fixture.path, null, .{});
    defer restored.deinit(a);
    try std.testing.expectEqualSlices(u8, initial.result.compiled.bytes, restored.result.compiled.bytes);
}

fn catalogQueryFailure(allocator: std.mem.Allocator, session: *retained.Session, fixture: *Fixture, expected: *const partial.Result) !void {
    const previous = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous;
    const before = Stamp.read(session);
    defer std.debug.assert(std.meta.eql(before, Stamp.read(session)));
    const pending = try ready(session, fixture, .{});
    defer pending.deinit();
    try std.testing.expect(pending.stats.rebuilt_seed);
    try std.testing.expect(pending.result().?.result.compiled.completed_queries.reused > 0);
    try equal(pending.result().?, expected);
    const owned = try allocator.dupe(u8, pending.result().?.result.compiled.bytes);
    defer allocator.free(owned);
    pending.discard();
}

test "catalog queries decline unrepresented imported effect operations and preserve fresh staging" {
    const producer =
        \\type Payload is data = #Payload { value: U32 }
        \\const changed = fn (value: U32) -> U32 => @u32.add value 7
    ;
    const consumer =
        \\import {Payload, changed} from "./dep"
        \\import {Read} from "./effects"
        \\const factory = fn action => fn value => action value
        \\const callback = factory (fn () => Read.get ())
        \\entry const answer = fn () -> U32 => do:
        \\  let payload = @effect.reader Read.get (#Payload { value: 0 }) (fn () => #Payload { value: 42 }) callback
        \\  return payload.value
        \\entry const staged = changed 1
        \\const evaluated: U32 = answer ()
    ;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("main.blot", consumer);
    try fixture.write("effects.blot", "type Read a is effect = { get: Unit -> a }\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    for ([_]u8{ '7', '8', '7' }, 0..) |number, revision| {
        const text = try a.dupe(u8, producer);
        defer a.free(text);
        text[text.len - 1] = number;
        try fixture.write("dep.blot", text);
        var expected = try fresh(&fixture, .{});
        defer expected.deinit(a);
        var result = try session.revise(io, fixture.path, null, .{});
        defer result.deinit(a);
        try equal(&result, &expected);
        if (revision != 0) {
            // This imported effect member is materialized in the consumer,
            // absent from its declaring module's nominal/operation tables.
            // Exact catalog equality does not invent a declaration witness.
            const queries = result.result.compiled.completed_queries;
            try std.testing.expect(queries.candidates > 0);
            try std.testing.expectEqual(@as(usize, 0), queries.reused);
            try std.testing.expectEqual(queries.candidates, queries.reasons[@backingInt(@import("completed_specialization_query.zig").Reason.expected)]);
        }
    }
}

test "catalog queries preserve seed and capture through every failed rebuilt candidate allocation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("main.blot", catalog_consumer);
    try fixture.write("dep.blot", catalog_producer);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    try editedCatalog(&fixture, '8');
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, catalogQueryFailure, .{ &session, &fixture, &expected });
    var retried = try session.revise(io, fixture.path, null, .{});
    defer retried.deinit(a);
    try equal(&retried, &expected);
}
fn initializeUnaffectedQuery(fixture: *Fixture, session: *retained.Session) !void {
    try fixture.write("dep.blot", unaffected_producer);
    try fixture.write("main.blot", unaffected_query_main);
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(session.allocator);
    try std.testing.expect(initial.result.diagnostic == null and initial.result.compiled.diagnostic == null);
    try std.testing.expect(initial.result.compiled.completed_queries.complete_records > 0);
}

test "unaffected query revisions retain independent proofs across entry function edits discard revert and errors" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initializeUnaffectedQuery(&fixture, &session);
    const original_bytes = try a.dupe(u8, session.current.?.output.?.bytes);
    defer a.free(original_bytes);
    for ([_][]const u8{ unaffected_query_edit, unaffected_query_main, unaffected_query_edit }) |source| {
        try fixture.write("main.blot", source);
        const before = Stamp.read(&session);
        var expected = try fresh(&fixture, .{});
        defer expected.deinit(a);
        const pending = try ready(&session, &fixture, .{});
        defer pending.deinit();
        try std.testing.expect(!pending.stats.rebuilt_seed);
        try std.testing.expect(pending.result().?.result.compiled.completed_queries.reused > 0);
        try equal(pending.result().?, &expected);
        try before.unchanged(&session);
        try std.testing.expect(session.discard(pending));
        try before.unchanged(&session);
        const retry = try ready(&session, &fixture, .{});
        defer retry.deinit();
        try equal(retry.result().?, &expected);
        try std.testing.expect(session.commit(retry));
    }
    try std.testing.expect(!std.mem.eql(u8, original_bytes, session.current.?.output.?.bytes));
    const before_error = Stamp.read(&session);
    try fixture.write("main.blot", "entry const marker: U32 = false\n");
    var rejected = try session.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try before_error.unchanged(&session);
    try fixture.write("main.blot", unaffected_query_main);
    var recovered = try session.revise(io, fixture.path, null, .{});
    defer recovered.deinit(a);
    try std.testing.expectEqualSlices(u8, original_bytes, recovered.result.compiled.bytes);
}

fn unaffectedQueryFailure(allocator: std.mem.Allocator, session: *retained.Session, fixture: *Fixture, expected: *const partial.Result) !void {
    const previous_allocator = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous_allocator;
    const old = Stamp.read(session);
    defer std.debug.assert(std.meta.eql(old, Stamp.read(session)));
    const pending = try ready(session, fixture, .{});
    defer pending.deinit();
    try std.testing.expect(!pending.stats.rebuilt_seed);
    try std.testing.expect(pending.result().?.result.compiled.completed_queries.reused > 0);
    try equal(pending.result().?, expected);
    const encoded = try allocator.dupe(u8, pending.result().?.result.compiled.bytes);
    defer allocator.free(encoded);
    pending.discard();
}

test "unaffected query revisions release every failed entry candidate and keep the previous capture available for retry" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initializeUnaffectedQuery(&fixture, &session);
    try fixture.write("main.blot", unaffected_query_edit);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, unaffectedQueryFailure, .{ &session, &fixture, &expected });
    var retried = try session.revise(io, fixture.path, null, .{});
    defer retried.deinit(a);
    try equal(&retried, &expected);
    try std.testing.expect(retried.result.compiled.completed_queries.reused > 0);
}

test "unaffected query revisions keep List Array and nominal closure evidence distinct and reject changed collection interfaces" {
    const producer =
        \\data Box a = #Box a
        \\const factory = fn value => fn () => value
        \\const listed = factory [41]
        \\const arrayed = factory #[42]
        \\const boxed = factory (#Box 43)
    ;
    const consumer =
        \\import {listed, arrayed, boxed, Box} from "./dep"
        \\const first_list = fn (values: List U32) => (@array.from_list values)[0]
        \\const first_array = fn (values: Array U32) => values[0]
        \\entry const list_value = fn () => first_list (listed ())
        \\entry const array_value = fn () => first_array (arrayed ())
        \\entry const nominal_value = fn () => do:
        \\  let #Box value = boxed ()
        \\  return value
        \\entry const staged_list = first_list (listed ())
        \\entry const staged_array = first_array (arrayed ())
    ;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("dep.blot", producer);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var hits: usize = 0;
    for ([_]u32{ 7, 8, 7 }) |number| {
        const source = try a.print("{s}\nentry const changed = fn (value: U32) => @u32.add value {d}\n", .{ consumer, number });
        defer a.free(source);
        try fixture.write("main.blot", source);
        var expected = try fresh(&fixture, .{});
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        if (actual.result.diagnostic != null or actual.result.compiled.diagnostic != null) {
            std.debug.print("collection revision {d}: actual={any}/{any}, fresh={any}/{any}\n", .{ number, actual.result.diagnostic, actual.result.compiled.diagnostic, expected.result.diagnostic, expected.result.compiled.diagnostic });
        }
        try equal(&actual, &expected);
        hits += actual.result.compiled.completed_queries.reused;
    }
    try std.testing.expect(hits > 0);
    const previous = Stamp.read(&session);
    const wrong =
        \\data Box a = #Box a
        \\const factory = fn value => fn () => value
        \\const listed = factory #[41]
        \\const arrayed = factory #[42]
        \\const boxed = factory (#Box 43)
    ;
    try fixture.write("dep.blot", wrong);
    var rejected = try session.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try previous.unchanged(&session);
    try fixture.write("dep.blot", producer);
    var recovered = try session.revise(io, fixture.path, null, .{});
    defer recovered.deinit(a);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try equal(&recovered, &expected);
}

test "refinement receipt preserves generic collection record State and captured computation evidence" {
    const generic =
        \\type Point is data = #Point { x: U32, y: U32 }
        \\const fixed = 41
        \\const pair = fn value => (value, fixed)
        \\entry const integer = fn (value: U32) => do:
        \\  let (x, n) = pair value
        \\  return @u32.add x n
        \\entry const floating = fn (value: F32) => do:
        \\  let (x, n) = pair value
        \\  return @f32.add x (@u32.to_f32 n)
        \\entry const listed = fn (value: U32) => do:
        \\  let (x, n) = pair [value]
        \\  return @u32.add (@array.from_list x)[0] n
        \\entry const arrayed = fn (value: U32) => do:
        \\  let (x, n) = pair #[value]
        \\  return @u32.add x[0] n
        \\entry const physical = fn (value: U32) => do:
        \\  let (x, n) = pair (#Point { y: 2, x: value })
        \\  return @u32.add (@u32.add x.x x.y) n
    ;
    const cases = [_][]const u8{
        generic,
        @embedFile("retained-state-fixtures/state-annotation-scopes.blot"),
        @embedFile("retained-state-fixtures/local-aliases.blot"),
        @embedFile("retained-state-fixtures/local-snapshots-called.blot"),
        @embedFile("retained-state-fixtures/latent-never-called.blot"),
        @embedFile("retained-state-fixtures/local-initializer-effects.blot"),
        @embedFile("retained-state-fixtures/state-annotation-shared.blot"),
        @embedFile("retained-state-fixtures/where-annotation-scope.blot"),
    };
    for (cases, 0..) |body, index| {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        var session = try retained.Session.initEmpty(a, .{});
        defer session.deinit();
        var hits: usize = 0;
        for ([_]u32{ 8, 9, 8, 9 }) |version| {
            const source = try a.print("{s}\nentry const schema: U32 = {d}\n", .{ body, version });
            defer a.free(source);
            try fixture.write("main.blot", source);
            var expected = try fresh(&fixture, .{});
            defer expected.deinit(a);
            var result = try session.revise(io, fixture.path, null, .{});
            defer result.deinit(a);
            if (result.result.diagnostic != null or result.result.compiled.diagnostic != null) {
                std.debug.print("refinement matrix case {d} version {d}: actual frontend={any} backend={any}; fresh frontend={any} backend={any}\n", .{ index, version, result.result.diagnostic, result.result.compiled.diagnostic, expected.result.diagnostic, expected.result.compiled.diagnostic });
            }
            try equal(&result, &expected);
            hits += result.result.compiled.refinements.hits;
        }
        if (index == 0) try std.testing.expect(hits > 0);
    }
}

test "refinement receipt survives edits reverts rejected revisions and changed staging dependencies" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("main.blot", refinement_source);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    try std.testing.expect(initial.result.diagnostic == null and initial.result.compiled.diagnostic == null);
    try std.testing.expect(initial.result.compiled.refinements.complete > 0);
    for ([_]u8{ '9', '8', '9', '8' }) |value| {
        const source = try a.dupe(u8, refinement_source);
        defer a.free(source);
        source[std.mem.find(u8, source, "changed = 8").? + "changed = ".len] = value;
        try fixture.write("main.blot", source);
        var expected = try fresh(&fixture, .{});
        defer expected.deinit(a);
        var result = try session.revise(io, fixture.path, null, .{});
        defer result.deinit(a);
        try equal(&result, &expected);
        try std.testing.expect(result.result.compiled.refinements.hits > 0);
        try std.testing.expect(result.result.compiled.refinements.requests > result.result.compiled.reuse.refinement_regions);
        try std.testing.expect(result.result.compiled.reuse.fresh_named > 0);
    }
    const stamp = Stamp.read(&session);
    const receipts = session.current.?.artifacts.metadata.refinement_receipts.items.ptr;
    try fixture.write("main.blot", refinement_source ++ "\nentry const broken: U32 = false\n");
    var rejected = try session.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try stamp.unchanged(&session);
    try std.testing.expect(receipts == session.current.?.artifacts.metadata.refinement_receipts.items.ptr);
    try fixture.write("main.blot", refinement_source);
    var recovered = try session.revise(io, fixture.path, null, .{});
    defer recovered.deinit(a);
    try std.testing.expect(recovered.result.compiled.refinements.hits > 0);
    const changed_source = try a.dupe(u8, refinement_source);
    defer a.free(changed_source);
    changed_source[std.mem.find(u8, changed_source, "fixed = 41").? + "fixed = 4".len] = '2';
    try fixture.write("main.blot", changed_source);
    var changed_result = try session.revise(io, fixture.path, null, .{});
    defer changed_result.deinit(a);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try equal(&changed_result, &expected);
    try std.testing.expectEqual(@as(usize, 0), changed_result.result.compiled.refinements.hits);
    try std.testing.expect(!std.mem.eql(u8, expected.result.compiled.bytes, initial.result.compiled.bytes));
}

fn refinementAllocationScenario(allocator: std.mem.Allocator, session: *retained.Session, fixture: *Fixture) !void {
    const previous_allocator = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous_allocator;
    const stamp = Stamp.read(session);
    defer std.debug.assert(std.meta.eql(stamp, Stamp.read(session)));
    const candidate = try ready(session, fixture, .{});
    defer candidate.deinit();
    try std.testing.expect(candidate.result().?.result.compiled.refinements.hits > 0);
    candidate.discard();
}
test "refinement receipt every replay allocation failure leaves previous results available for retry" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("main.blot", refinement_source);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    const source = try a.dupe(u8, refinement_source);
    defer a.free(source);
    source[std.mem.find(u8, source, "changed = 8").? + "changed = ".len] = '9';
    try fixture.write("main.blot", source);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, refinementAllocationScenario, .{ &session, &fixture });
    var retry = try session.revise(io, fixture.path, null, .{});
    defer retry.deinit(a);
    try std.testing.expect(retry.result.compiled.refinements.hits > 0);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try equal(&retry, &expected);
}

test "List and Array prelude members retain code across real entry edits and catalog changes" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const prelude =
        \\const List.first = fn (values: List U32) => (@array.from_list values)[0]
        \\const Array.first = fn (values: Array U32) => values[0]
        \\const fixed = fn (value: U32) => do:
        \\  let result = 0
        \\  for i in 0..1:
        \\    result := @u32.add (List.first [value]) (Array.first #[value])
        \\  return result
    ;
    const main_before = "entry const answer = fn (value: U32) => @u32.add (fixed value) 8\n";
    const main_after = "entry const answer = fn (value: U32) => @u32.add (fixed value) 9\n";
    try fixture.write("prelude.blot", prelude);
    try fixture.write("main.blot", main_before);
    const options: project.Options = .{ .prelude_path = fixture.prelude };
    var session = try retained.Session.initEmpty(a, options);
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, options);
    defer initial.deinit(a);
    try std.testing.expect(initial.result.diagnostic == null and initial.result.compiled.diagnostic == null);
    for ([_][]const u8{ main_after, main_before, main_after }) |source| {
        try fixture.write("main.blot", source);
        var expected = try fresh(&fixture, options);
        defer expected.deinit(a);
        var result = try session.revise(io, fixture.path, null, options);
        defer result.deinit(a);
        try equal(&result, &expected);
        try std.testing.expect(!session.last.rebuilt_seed);
        try std.testing.expect(result.result.compiled.reuse.reused_named > 0);
        try std.testing.expect(result.result.compiled.reuse.refinement_regions < initial.result.compiled.reuse.refinement_regions);
    }
    try fixture.write("prelude.blot", prelude ++ "\nconst List.second = fn (values: List U32) => (@array.from_list values)[1]\n");
    var changed = try session.revise(io, fixture.path, null, options);
    defer changed.deinit(a);
    var expected = try fresh(&fixture, options);
    defer expected.deinit(a);
    try equal(&changed, &expected);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expectEqual(@as(usize, 0), changed.result.compiled.reuse.reused_named);
}

test "collection replay gate still rejects unknown builtin identities and local method targets" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("prelude.blot", "const List.first = fn (values: List U32) => (@array.from_list values)[0]\n");
    try fixture.write("main.blot", "entry const answer = fn (value: U32) => List.first [value]\n");
    const options: project.Options = .{ .prelude_path = fixture.prelude };
    var session = try retained.Session.initEmpty(a, options);
    defer session.deinit();
    for (0..2) |_| {
        var result = try session.revise(io, fixture.path, null, options);
        defer result.deinit(a);
        try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    }
    const current = &session.current.?;
    const units = current.prepared.units;
    const capture = &current.artifacts;
    const identity = current.prepared.identity.view();
    const cached = current.prepared.cached;
    try std.testing.expect(capture.selectionStable(units, identity, cached));
    const entry_module = &units[units.len - 1];
    var tested = false;
    for (entry_module.associated) |*member| {
        if (member.identity.unit != 0 or member.identity.decl != std.math.maxInt(u32) - 1) continue;
        const saved = member.*;
        defer member.* = saved;
        member.identity.decl = std.math.maxInt(u32) - 2;
        try std.testing.expect(!capture.selectionStable(units, identity, cached));
        member.* = saved;
        member.target.unit = 0;
        try std.testing.expect(!capture.selectionStable(units, identity, cached));
        member.* = saved;
        try std.testing.expect(capture.selectionStable(units, identity, cached));
        tested = true;
        break;
    }
    try std.testing.expect(tested);
}

fn unchangedOutput(session: *retained.Session, fixture: *const Fixture, options: project.Options) !*retained.Candidate {
    const candidate = try ready(session, fixture, options);
    errdefer candidate.deinit();
    try std.testing.expect(candidate.stats.reused_output);
    const result = candidate.result().?;
    try std.testing.expectEqual(@as(usize, 0), result.result.compiled.constant_steps);
    try std.testing.expectEqual(@as(usize, 0), result.result.stats.syntax_nodes);
    try std.testing.expectEqual(@as(usize, 0), result.result.stats.body_elaborations);
    try std.testing.expectEqual(@as(usize, 0), result.fresh_modules);
    try std.testing.expectEqual(session.current.?.prepared.units.len, result.cached_modules);
    try std.testing.expectEqual(session.current.?.prepared.source_bytes, result.source_bytes);
    return candidate;
}

test "unchanged-output exact reads preserve current owners through discard commit and late teardown" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    var session_alive = true;
    defer if (session_alive) session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    const before = Stamp.read(&session);
    const core_owner = session.current.?.prepared.units.ptr;
    const source_owner = session.current.?.snapshot.files.items.ptr;
    const output_owner = session.current.?.output.?.bytes.ptr;
    const candidate = try unchangedOutput(&session, &fixture, .{});
    defer candidate.deinit();
    try std.testing.expectEqualSlices(u8, initial.result.compiled.bytes, candidate.result().?.result.compiled.bytes);
    try std.testing.expect(initial.result.compiled.bytes.ptr != candidate.result().?.result.compiled.bytes.ptr);
    try before.unchanged(&session);
    try std.testing.expectError(error.CandidateActive, session.prepareRevision(io, fixture.path, null, .{}));
    try std.testing.expect(session.discard(candidate));
    try before.unchanged(&session);
    const retry = try unchangedOutput(&session, &fixture, .{});
    defer retry.deinit();
    try std.testing.expect(session.commit(retry));
    try std.testing.expectEqual(@as(usize, 2), session.revisions);
    try std.testing.expect(session.last.reused_output);
    try std.testing.expect(session.current.?.prepared.units.ptr == core_owner);
    try std.testing.expect(session.current.?.snapshot.files.items.ptr == source_owner);
    try std.testing.expect(session.current.?.output.?.bytes.ptr == output_owner);
    const late = try unchangedOutput(&session, &fixture, .{});
    defer late.deinit();
    session.deinit();
    session_alive = false;
    late.discard();
    var detached = late.takeResult().?;
    defer detached.deinit(a);
    try std.testing.expectEqualSlices(u8, initial.result.compiled.bytes, detached.result.compiled.bytes);
}

test "unchanged-output entry and producer changes reject reuse and failed revisions preserve the last good output" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    try fixture.write("main.blot", "entry const answer:U32=missing\n");
    const before = Stamp.read(&session);
    var rejected = try session.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try before.unchanged(&session);
    try fixture.write("main.blot", main);
    const correction = try unchangedOutput(&session, &fixture, .{});
    defer correction.deinit();
    try std.testing.expect(session.commit(correction));
    try fixture.write("dep.blot", edited);
    const changed = try ready(&session, &fixture, .{});
    defer changed.deinit();
    try std.testing.expect(!changed.stats.reused_output and changed.stats.rebuilt_seed);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try equal(changed.result().?, &expected);
    try std.testing.expect(session.commit(changed));
    const same = try unchangedOutput(&session, &fixture, .{});
    defer same.deinit();
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, same.result().?.result.compiled.bytes);
    try std.testing.expect(session.discard(same));
    try fixture.write("main.blot", "import * as dep from \"./dep\"\nentry const answer:U32=44\n");
    const entry_change = try ready(&session, &fixture, .{});
    defer entry_change.deinit();
    try std.testing.expect(!entry_change.stats.reused_output);
    var entry_expected = try fresh(&fixture, .{});
    defer entry_expected.deinit(a);
    try equal(entry_change.result().?, &entry_expected);
}

test "unchanged-output root identity policy and exact optional settings decline reuse" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    session.policy.share_machine_code = !session.policy.share_machine_code;
    const policy = try ready(&session, &fixture, .{});
    defer policy.deinit();
    try std.testing.expect(!policy.stats.reused_output);
    try std.testing.expect(session.discard(policy));
    session.policy.share_machine_code = !session.policy.share_machine_code;
    var other_identity = try session.prepareRevision(io, fixture.path, "", .{});
    defer other_identity.deinit();
    try std.testing.expect(other_identity == .ready);
    try std.testing.expect(!other_identity.ready.stats.reused_output);
    try std.testing.expect(session.discard(other_identity.ready));
    const alias_path = try a.print("{s}/../main.blot", .{fixture.path});
    defer a.free(alias_path);
    var invalid_root = try session.prepareRevision(io, alias_path, null, .{});
    defer invalid_root.deinit();
    try std.testing.expect(invalid_root == .rejected);
    const before = Stamp.read(&session);
    var invalid_prelude = try session.prepareRevision(io, fixture.path, null, .{ .prelude_path = "" });
    defer invalid_prelude.deinit();
    try std.testing.expect(invalid_prelude == .rejected);
    try before.unchanged(&session);
    var low_quota = try session.prepareRevision(io, fixture.path, null, .{ .max_files = 1 });
    defer low_quota.deinit();
    try std.testing.expect(low_quota == .rejected);
    try before.unchanged(&session);
}

fn unchangedOutputAllocationLaw(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var session = try retained.Session.initEmpty(allocator, .{});
    var session_alive = true;
    defer if (session_alive) session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(allocator);
    const before = Stamp.read(&session);
    var preparation = session.prepareRevision(io, fixture.path, null, .{}) catch |err| {
        try before.unchanged(&session);
        return err;
    };
    defer preparation.deinit();
    try std.testing.expect(preparation == .ready and preparation.ready.stats.reused_output);
    const candidate = preparation.ready;
    const encoded = allocator.dupe(u8, candidate.result().?.result.compiled.bytes) catch |err| {
        try std.testing.expect(session.discard(candidate));
        try before.unchanged(&session);
        return err;
    };
    defer allocator.free(encoded);
    try std.testing.expect(session.discard(candidate));
    try before.unchanged(&session);
    var retry = session.prepareRevision(io, fixture.path, null, .{}) catch |err| {
        try before.unchanged(&session);
        return err;
    };
    defer retry.deinit();
    try std.testing.expect(retry == .ready and retry.ready.stats.reused_output);
    try std.testing.expect(session.commit(retry.ready));
    try std.testing.expectEqualSlices(u8, encoded, retry.ready.result().?.result.compiled.bytes);
    session.deinit();
    session_alive = false;
    try std.testing.expectEqualSlices(u8, encoded, retry.ready.result().?.result.compiled.bytes);
}

test "unchanged-output every allocation failure preserves publication owners and retry" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, unchangedOutputAllocationLaw, .{&fixture});
}

test "unchanged-output identical bytes with a retargeted import symlink require fresh admission" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("a.blot", original);
    try fixture.write("b.blot", original);
    try fixture.dir.dir.deleteFile(io, "dep.blot");
    try fixture.dir.dir.symLink(io, "a.blot", "dep.blot", .{});
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    const before = Stamp.read(&session);
    try fixture.dir.dir.deleteFile(io, "dep.blot");
    try fixture.dir.dir.symLink(io, "b.blot", "dep.blot", .{});
    const changed = try ready(&session, &fixture, .{});
    defer changed.deinit();
    try std.testing.expect(!changed.stats.reused_output and changed.stats.rebuilt_seed);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try equal(changed.result().?, &expected);
    try std.testing.expect(session.discard(changed));
    try before.unchanged(&session);
    try fixture.dir.dir.deleteFile(io, "dep.blot");
    try fixture.dir.dir.symLink(io, "a.blot", "dep.blot", .{});
    const restored = try unchangedOutput(&session, &fixture, .{});
    defer restored.deinit();
    try std.testing.expectEqualSlices(u8, initial.result.compiled.bytes, restored.result().?.result.compiled.bytes);
}

test "unchanged-output owns its cached bytes independently of detached caller results and remains optional" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var ordinary = try retained.Session.initEmpty(a, .{});
    defer ordinary.deinit();
    var first = try ordinary.revise(io, fixture.path, null, .{});
    defer first.deinit(a);
    var second = try ordinary.revise(io, fixture.path, null, .{});
    defer second.deinit(a);
    try std.testing.expect(ordinary.current.?.output == null and !ordinary.last.reused_output);
    try equal(&first, &second);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    initial.result.compiled.bytes[0] ^= 255;
    const candidate = try unchangedOutput(&session, &fixture, .{});
    defer candidate.deinit();
    try std.testing.expectEqualSlices(u8, first.result.compiled.bytes, candidate.result().?.result.compiled.bytes);
    try std.testing.expect(session.commit(candidate));
    var detached = candidate.takeResult().?;
    defer detached.deinit(a);
    detached.result.compiled.bytes[0] ^= 255;
    const repeated = try unchangedOutput(&session, &fixture, .{});
    defer repeated.deinit();
    try std.testing.expectEqualSlices(u8, first.result.compiled.bytes, repeated.result().?.result.compiled.bytes);
}

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    prelude: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = original });
        try dir.dir.writeFile(io, .{ .sub_path = "prelude.blot", .data = "const chosen:U32=41\n" });
        const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
        errdefer a.free(path);
        const prelude = try dir.dir.realPathFileAlloc(io, "prelude.blot", a);
        return .{ .dir = dir, .path = path, .prelude = prelude };
    }
    fn write(self: *Fixture, name: []const u8, text: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        a.free(self.prelude);
        self.dir.cleanup();
    }
};
fn fresh(fixture: *const Fixture, options: project.Options) !partial.Result {
    var source = try project.load(a, io, fixture.path, options);
    defer source.deinit(a);
    const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var preparation = try partial.prepareProject(a, &source, fixture.path, null, &empty);
    switch (preparation) {
        .rejected => |result| return result,
        .ready => |*prepared| {
            defer prepared.deinit(a);
            return prepared.emit(a);
        },
    }
}
fn ready(session: *retained.Session, fixture: *const Fixture, options: project.Options) !*retained.Candidate {
    var preparation = try session.prepareRevision(io, fixture.path, null, options);
    return switch (preparation) {
        .ready => |candidate| candidate,
        .rejected => blk: {
            preparation.deinit();
            break :blk error.UnexpectedRejection;
        },
    };
}
fn equal(result: *const partial.Result, expected: *const partial.Result) !void {
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, result.result.compiled.bytes);
    // Existing constant_steps counts native backend work, not source fuel.
    try std.testing.expectEqual(expected.result.compiled.constant_steps, result.result.compiled.constant_steps);
}
const Stamp = struct {
    revision: usize,
    seed: [32]u8,
    settings: [32]u8,
    stats: [32]u8,
    core: [32]u8,
    instructions: [32]u8,
    cached_output: [32]u8,
    snapshot: [32]u8,
    fn outcomeStamp(outcome: anytype) [32]u8 {
        return switch (outcome) {
            .bytes => |bytes| metadata.stamp(.{ true, bytes }),
            .failure => |err| metadata.stamp(.{ false, @intFromError(err) }),
        };
    }
    fn snapshotStamp(snapshot: anytype) [32]u8 {
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update(&metadata.stamp(snapshot.options));
        hash.update(&metadata.stamp(snapshot.counts));
        for (snapshot.paths.items) |entry| {
            hash.update(&metadata.stamp(entry.key));
            hash.update(&outcomeStamp(entry.result));
        }
        for (snapshot.files.items) |entry| {
            hash.update(&metadata.stamp(entry.key));
            hash.update(&outcomeStamp(entry.result));
        }
        for (snapshot.imports.items) |entry| {
            hash.update(&metadata.stamp(entry.source));
            hash.update(&metadata.stamp(entry.request));
            hash.update(&outcomeStamp(entry.result));
        }
        var result: [32]u8 = undefined;
        hash.final(&result);
        return result;
    }
    fn read(session: *const retained.Session) Stamp {
        return .{
            .revision = session.revisions,
            .seed = metadata.stamp(session.seed),
            .settings = session.seed_settings,
            .stats = metadata.stamp(session.last),
            .core = if (session.current) |current| metadata.stamp(current.prepared.units) else @splat(0),
            .instructions = if (session.current) |current| metadata.stamp(current.artifacts.emission.instructions) else @splat(0),
            .cached_output = if (session.current) |current| metadata.stamp(current.output) else @splat(0),
            .snapshot = if (session.current) |current| snapshotStamp(current.snapshot) else @splat(0),
        };
    }
    fn unchanged(self: Stamp, session: *const retained.Session) !void {
        try std.testing.expectEqualDeep(self, read(session));
    }
};

const project_query_source =
    \\import {marker} from "./dep"
    \\const factory = fn number => fn extra => number
    \\const callback = factory 42
    \\entry const schema: U32 = 7
    \\entry const answer = fn (extra: U32) -> U32 => callback extra
    \\const run_value: U32 = callback 0
;
const project_query_edit =
    \\import {marker} from "./dep"
    \\const factory = fn number => fn extra => number
    \\const callback = factory 42
    \\entry const schema: U32 = 8
    \\entry const answer = fn (extra: U32) -> U32 => callback extra
    \\const run_value: U32 = callback 0
;
fn initializeProjectQuery(fixture: *Fixture, session: *retained.Session) !void {
    try fixture.write("dep.blot", "const marker:U32=1\n");
    try fixture.write("main.blot", project_query_source);
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(session.allocator);
    try std.testing.expect(initial.result.diagnostic == null and initial.result.compiled.diagnostic == null);
    try std.testing.expect(initial.result.compiled.completed_queries.complete_records > 0);
    try std.testing.expect(session.last.fallback.reused_core_bodies > 0);
    try std.testing.expectEqual(@as(usize, 0), session.last.fallback.recheck_body_elaborations);
    try fixture.write("main.blot", project_query_edit);
}
fn expectProjectQuery(candidate: *const retained.Candidate, expected: *const partial.Result) !void {
    const result = candidate.result().?;
    try equal(result, expected);
    try std.testing.expect(!candidate.stats.rebuilt_seed);
    try std.testing.expect(result.result.compiled.completed_queries.reused > 0);
    try std.testing.expectEqual(@as(usize, 1), result.result.compiled.completed_queries.prepared_importers);
    try std.testing.expectEqual(@as(usize, 0), result.result.compiled.completed_queries.fresh_importers);
    // The executable gate validated this exact pair; principal/query reuse
    // clones those flags rather than validating the same modules again.
    try std.testing.expectEqual(@as(usize, 0), result.result.compiled.principal.dependency_validations);
}

test "complete project policy preserves captured queries through candidate discard retry and source error recovery" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initializeProjectQuery(&fixture, &session);
    const old = Stamp.read(&session);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    const candidate = try ready(&session, &fixture, .{});
    defer candidate.deinit();
    try expectProjectQuery(candidate, &expected);
    try old.unchanged(&session);
    const encoded = try a.dupe(u8, candidate.result().?.result.compiled.bytes);
    defer a.free(encoded);
    try std.testing.expect(session.discard(candidate));
    try old.unchanged(&session);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, encoded);
    const retry = try ready(&session, &fixture, .{});
    defer retry.deinit();
    try expectProjectQuery(retry, &expected);
    try std.testing.expect(session.commit(retry));
    const committed = Stamp.read(&session);
    try fixture.write("main.blot", "entry const answer:U32=missing\n");
    var rejected = try session.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try committed.unchanged(&session);
    try fixture.write("main.blot", project_query_source);
    var reverted_expected = try fresh(&fixture, .{});
    defer reverted_expected.deinit(a);
    const reverted = try ready(&session, &fixture, .{});
    defer reverted.deinit();
    try expectProjectQuery(reverted, &reverted_expected);
    try std.testing.expect(session.commit(reverted));
    try std.testing.expectEqual(old.revision + 2, session.revisions);
}

fn projectQueryAllocationFailure(allocator: std.mem.Allocator, session: *retained.Session, fixture: *Fixture, expected: *const partial.Result) !void {
    const previous = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous;
    const old = Stamp.read(session);
    var preparation = session.prepareRevision(io, fixture.path, null, .{}) catch |err| {
        try old.unchanged(session);
        return err;
    };
    defer preparation.deinit();
    try old.unchanged(session);
    try std.testing.expect(preparation == .ready);
    const candidate = preparation.ready;
    try expectProjectQuery(candidate, expected);
    const header = try allocator.dupe(u8, "fallible reply encoding before publication");
    defer allocator.free(header);
    const bytes = try allocator.dupe(u8, candidate.result().?.result.compiled.bytes);
    defer allocator.free(bytes);
    candidate.discard();
    try old.unchanged(session);
}

test "complete project policy every queried preparation and reply encoding OOM preserves last good owners and retries" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initializeProjectQuery(&fixture, &session);
    const old = Stamp.read(&session);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, projectQueryAllocationFailure, .{ &session, &fixture, &expected });
    try old.unchanged(&session);
    const retry = try ready(&session, &fixture, .{});
    defer retry.deinit();
    try expectProjectQuery(retry, &expected);
    try std.testing.expect(session.commit(retry));
    try std.testing.expectEqual(old.revision + 1, session.revisions);
}

test "revision candidate empty initialization admits no-import source and checks imports and prelude before publication" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    for (0..3) |kind| {
        const text = switch (kind) {
            0 => "entry const answer:U32=42\n",
            1 => main,
            else => "entry const answer:U32=@u32.add chosen 1\n",
        };
        try fixture.write("main.blot", text);
        const options: project.Options = if (kind == 2) .{ .prelude_path = fixture.prelude } else .{};
        var expected = try fresh(&fixture, options);
        defer expected.deinit(a);
        var session = try retained.Session.initEmpty(a, options);
        defer session.deinit();
        const candidate = try ready(&session, &fixture, options);
        defer candidate.deinit();
        try equal(candidate.result().?, &expected);
        try std.testing.expectEqual(@as(usize, 0), session.revisions);
        try std.testing.expect(session.current == null and candidate.takeResult() == null);
        try std.testing.expectEqual(kind != 0, candidate.stats.rebuilt_seed);
        try std.testing.expect(session.commit(candidate));
        try std.testing.expectEqual(@as(usize, 1), session.revisions);
        try std.testing.expectEqual(@as(usize, if (kind == 0) 0 else 1), session.seed.modules.len);
        try equal(candidate.result().?, &expected);
        var result = candidate.takeResult().?;
        defer result.deinit(a);
        try std.testing.expect(candidate.result() == null);
    }
}

test "revision candidate discard preserves last-good seed capture inputs settings and statistics after dependency rebuild" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    const old = Stamp.read(&session);
    try fixture.write("dep.blot", edited);
    const options: project.Options = .{ .max_source_bytes = 4096 };
    var expected = try fresh(&fixture, options);
    defer expected.deinit(a);
    const candidate = try ready(&session, &fixture, options);
    defer candidate.deinit();
    try std.testing.expect(candidate.stats.rebuilt_seed and candidate.seed != null);
    try equal(candidate.result().?, &expected);
    try old.unchanged(&session);
    // Simulated caller rejection after fallible response encoding. These bytes
    // are caller-owned; no transport or cancellation contract is claimed.
    const encoded = try a.dupe(u8, candidate.result().?.result.compiled.bytes);
    defer a.free(encoded);
    try std.testing.expect(session.discard(candidate));
    try std.testing.expect(!session.commit(candidate) and !session.discard(candidate));
    try old.unchanged(&session);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, encoded);
    try equal(candidate.result().?, &expected);
    const retry = try ready(&session, &fixture, options);
    defer retry.deinit();
    try std.testing.expect(session.commit(retry));
    try std.testing.expectEqual(@as(usize, 2), session.revisions);
    try std.testing.expect(!std.mem.eql(u8, &old.settings, &session.seed_settings));
    try equal(retry.result().?, &expected);
}

test "revision candidate rejects concurrent wrong-owner moved and stale handles without disturbing the active revision" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var other = try retained.Session.initEmpty(a, .{});
    defer other.deinit();
    const candidate = try ready(&session, &fixture, .{});
    defer candidate.deinit();
    const old = Stamp.read(&session);
    try std.testing.expectError(error.CandidateActive, session.prepareRevision(io, fixture.path, null, .{}));
    try std.testing.expect(!other.commit(candidate) and !other.discard(candidate));
    var moved = session;
    // A moved value is not another owner; it must not deinitialize the borrow.
    try std.testing.expectError(error.SessionMoved, moved.prepareRevision(io, fixture.path, null, .{}));
    try std.testing.expect(!moved.commit(candidate) and !moved.discard(candidate));
    try old.unchanged(&session);
    try std.testing.expect(session.discard(candidate));
    const next = try ready(&session, &fixture, .{});
    defer next.deinit();
    try std.testing.expect(!session.commit(candidate));
    try std.testing.expectError(error.CandidateActive, session.revise(io, fixture.path, null, .{}));
    try std.testing.expect(session.commit(next));
    try std.testing.expect(!session.commit(next));
    try std.testing.expectEqual(@as(usize, 1), session.revisions);
}

test "revision candidate commit does not allocate or reread files and late emission owns bytes after Session teardown" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var failing: std.testing.FailingAllocator = .init(a, .{});
    const allocator = failing.allocator();
    var session = try retained.Session.initEmpty(allocator, .{});
    var alive = true;
    defer if (alive) session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(allocator);
    try fixture.write("dep.blot", edited);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    const candidate = try ready(&session, &fixture, .{});
    defer candidate.deinit();
    try fixture.dir.dir.deleteFile(io, "main.blot");
    try fixture.dir.dir.deleteFile(io, "dep.blot");
    const allocations = failing.alloc_index;
    failing.fail_index = allocations;
    try std.testing.expect(session.commit(candidate));
    try std.testing.expectEqual(allocations, failing.alloc_index);
    session.deinit();
    alive = false;
    try equal(candidate.result().?, &expected);
    var result = candidate.takeResult().?;
    defer result.deinit(allocator);
    try std.testing.expect(candidate.takeResult() == null);
}

test "revision candidate Session teardown destroys pending borrowed owners and a new epoch cannot commit its late handle" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    var alive = true;
    defer if (alive) session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    try fixture.write("dep.blot", edited);
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    const abandoned = try ready(&session, &fixture, .{});
    defer abandoned.deinit();
    try std.testing.expect(abandoned.seed != null and abandoned.pending != null);
    session.deinit();
    alive = false;
    try std.testing.expect(abandoned.pending == null and abandoned.seed == null);
    try equal(abandoned.result().?, &expected);
    // Reuse the exact Session stack address while the old lease is still live.
    session = try retained.Session.initEmpty(a, .{});
    alive = true;
    const next = try ready(&session, &fixture, .{});
    defer next.deinit();
    try std.testing.expect(!session.commit(abandoned) and !session.discard(abandoned));
    try std.testing.expect(session.commit(next));
    try std.testing.expectEqual(@as(usize, 1), session.revisions);
    try equal(abandoned.result().?, &expected);
}

test "revision candidate source and backend rejections own attempt inputs and diagnostics without replacing successful statistics" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    var alive = true;
    defer if (alive) session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    const old = Stamp.read(&session);
    try fixture.write("main.blot", "import * as dep from \"./dep\"\nentry const answer:U32=true\n");
    var frontend = try session.prepareRevision(io, fixture.path, null, .{});
    defer frontend.deinit();
    try std.testing.expect(frontend == .rejected);
    try std.testing.expect(frontend.rejected.result.result.diagnostic != null);
    try std.testing.expect(frontend.rejected.stats.inputs.source_reads != 0);
    try std.testing.expectEqual(@as(usize, 0), frontend.rejected.stats.fallback.body_lowerings);
    try old.unchanged(&session);
    try fixture.write("main.blot", main);
    try fixture.write("dep.blot", "const read:Unit->U32=fn () => read ()\n");
    var backend = try session.prepareRevision(io, fixture.path, null, .{});
    defer backend.deinit();
    try std.testing.expect(backend == .rejected);
    try std.testing.expect(backend.rejected.result.result.compiled.diagnostic != null);
    try std.testing.expect(backend.rejected.stats.rebuilt_seed and backend.rejected.stats.fallback.frozen_modules == 1);
    try old.unchanged(&session);
    session.deinit();
    alive = false;
    try std.testing.expect(frontend.rejected.result.diagnostic_filename.?.len != 0);
    try std.testing.expect(backend.rejected.result.result.compiled.diagnostic.?.message().len != 0);
    try std.testing.expect(frontend.rejected.snapshot.files.items.len != 0 and backend.rejected.snapshot.files.items.len != 0);
}

fn initialAllocationScenario(allocator: std.mem.Allocator, fixture: *Fixture) !void {
    const options: project.Options = .{ .prelude_path = fixture.prelude };
    var session = try retained.Session.initEmpty(allocator, options);
    defer session.deinit();
    const old = Stamp.read(&session);
    const candidate = ready(&session, fixture, options) catch |err| {
        try old.unchanged(&session);
        return err;
    };
    defer candidate.deinit();
    try old.unchanged(&session);
    try std.testing.expect(candidate.stats.rebuilt_seed);
    candidate.discard();
    try old.unchanged(&session);
}
test "revision candidate initial empty-seed preparation and checked prelude fallback release every failed allocation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, initialAllocationScenario, .{&fixture});
}

fn encodingAllocationScenario(allocator: std.mem.Allocator, session: *retained.Session, fixture: *Fixture) !void {
    const previous_allocator = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous_allocator;
    const old = Stamp.read(session);
    defer std.debug.assert(std.meta.eql(old, Stamp.read(session)));
    const candidate = try ready(session, fixture, .{ .max_source_bytes = 4096 });
    defer candidate.deinit();
    // Both encoding allocations belong to the caller and precede commit.
    const header = try allocator.dupe(u8, "owned reply metadata");
    defer allocator.free(header);
    const bytes = try allocator.dupe(u8, candidate.result().?.result.compiled.bytes);
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len != 0 and candidate.stats.rebuilt_seed);
    candidate.discard();
}
test "revision candidate every preparation and caller-encoding allocation failure preserves the previous published revision" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    const old = Stamp.read(&session);
    try fixture.write("dep.blot", edited);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, encodingAllocationScenario, .{ &session, &fixture });
    try old.unchanged(&session);
    const retry = try ready(&session, &fixture, .{});
    defer retry.deinit();
    try std.testing.expect(session.commit(retry));
    try std.testing.expectEqual(@as(usize, 2), session.revisions);
}

test "fresh principal capture serves the first edit and the edit after a dependency rebuild" {
    const main_source = unaffected_query_main ++ "\nentry const checked: U32 where { type_rep U32 } = marker\n";
    const edit_source = unaffected_query_edit ++ "\nentry const checked: U32 where { type_rep U32 } = marker\n";
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("dep.blot", unaffected_producer);
    try fixture.write("main.blot", main_source);
    var candidate = try retained.Session.initEmpty(a, .{});
    defer candidate.deinit();
    for (0..4) |revision| {
        if (revision == 1 or revision == 2) try fixture.write("main.blot", edit_source);
        if (revision == 2) {
            const producer = try a.dupe(u8, unaffected_producer);
            defer a.free(producer);
            producer[std.mem.find(u8, producer, "U32 = 1").? + "U32 = ".len] = '2';
            try fixture.write("dep.blot", producer);
        }
        if (revision == 3) try fixture.write("main.blot", main_source);
        var expected = try fresh(&fixture, .{});
        defer expected.deinit(a);
        var after = try candidate.revise(io, fixture.path, null, .{});
        defer after.deinit(a);
        try equal(&after, &expected);
        const current = after.result.compiled.principal;
        if (revision == 0 or revision == 2) {
            try std.testing.expect(candidate.last.rebuilt_seed);
            try std.testing.expect(current.captured > 0);
            if (revision == 2) try std.testing.expect(current.projected_empty_hits > 0);
        } else {
            try std.testing.expect(!candidate.last.rebuilt_seed);
            try std.testing.expect(current.hits > 0);
        }
    }
    const last_good = Stamp.read(&candidate);
    const proofs = metadata.stamp(candidate.current.?.artifacts.metadata.principal_proofs.items);
    try fixture.write("main.blot", "entry const wrong: U32 = false\n");
    var rejected = try candidate.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try last_good.unchanged(&candidate);
    try std.testing.expectEqualSlices(u8, &proofs, &metadata.stamp(candidate.current.?.artifacts.metadata.principal_proofs.items));
}

fn freshPrincipalFailure(allocator: std.mem.Allocator, fixture: *Fixture, expected: *const partial.Result) !void {
    var session = try retained.Session.initEmpty(allocator, .{});
    defer session.deinit();
    const old = Stamp.read(&session);
    const pending = try ready(&session, fixture, .{});
    defer pending.deinit();
    try std.testing.expect(pending.stats.rebuilt_seed);
    try std.testing.expect(pending.result().?.result.compiled.principal.captured > 0);
    try std.testing.expectEqual(@as(usize, 0), pending.result().?.result.compiled.principal.hits);
    try equal(pending.result().?, expected);
    const encoded = try allocator.dupe(u8, pending.result().?.result.compiled.bytes);
    defer allocator.free(encoded);
    try old.unchanged(&session);
    pending.discard();
    try old.unchanged(&session);
}

test "fresh principal capture releases every failed first candidate and publication remains transactional" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("dep.blot", "const identity = fn value => value\n");
    try fixture.write("main.blot",
        \\import {identity} from "./dep"
        \\entry const answer: U32 where { type_rep U32 } = identity 42
    );
    var expected = try fresh(&fixture, .{});
    defer expected.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, freshPrincipalFailure, .{ &fixture, &expected });
}
