//! Standalone allocation observations; compiler inputs are imported unchanged.
//! zig test -O safe -fno-llvm --dep test_options
//!   -Mroot=bench_module_cutoffs.zig
//!   -Mtest_options=bench_options.zig --test-filter "cutoff allocation observations"
const std = @import("std");
const retained = @import("src/reuse/retained_revision.zig");
const memory = @import("src/runtime/memory.zig");
const Tier = @import("src/compilation_tier.zig").Tier;
const io = std.testing.io;
const harness = std.testing.allocator;
pub const compiler_defaults = struct {
    pub const artifact_replay = true;
};
const bridge =
    \\import {make, read} from "./tokens"
    \\const factories = #[make, fn value => make value]
    \\const readers = #[read, fn value => read value]
    \\const transform = fn (value: U32) => (readers[@u32.rem value 2]) ((factories[@u32.rem value 2]) value)
    \\
;
const entry =
    \\import {transform} from "./bridge"
    \\entry const answer = fn (value: U32) => transform value
    \\
;
const scalar =
    \\opaque type Token = U32
    \\private const offset = 2
    \\const make: U32 -> Token = fn value => #Token (@u32.add value offset)
    \\const read: Token -> U32 = fn (#Token value) => value
    \\
;
const floating =
    \\opaque type Token = F32
    \\private const offset = 2
    \\const make: U32 -> Token = fn value => #Token (@u32.to_f32 (@u32.add value offset))
    \\const read: Token -> U32 = fn (#Token value) => @f32.to_u32 value
    \\
;
const reference =
    \\opaque type Token = Array U32
    \\private const offset = 2
    \\const make: U32 -> Token = fn value => #Token #[@u32.add value offset]
    \\const read: Token -> U32 = fn (#Token value) => value[0]
    \\
;
const record =
    \\opaque type Token = {word: U32}
    \\private const offset = 2
    \\const make: U32 -> Token = fn value => #Token {word: @u32.add value offset}
    \\const read: Token -> U32 = fn (#Token value) => value.word
    \\
;
const renamed =
    \\opaque type Token = {renamed: U32}
    \\private const offset = 2
    \\const make: U32 -> Token = fn value => #Token {renamed: @u32.add value offset}
    \\const read: Token -> U32 = fn (#Token value) => value.renamed
    \\
;
const moved =
    \\opaque type Token = U32
    \\const make: U32 -> Token = fn value => #Token (@u32.add value offset)
    \\const read: Token -> U32 = fn (#Token value) => value
    \\private const offset = 2
    \\
;
const alpha =
    \\opaque type Token = U32
    \\private const offset = 2
    \\const make: U32 -> Token = fn argument => #Token (@u32.add argument offset)
    \\const read: Token -> U32 = fn (#Token argument) => argument
    \\
;
const generic =
    \\opaque type Token element = element
    \\private const offset = 2
    \\const make: a -> Token a = fn value => #Token value
    \\const read: Token a -> a = fn (#Token value) => value
    \\const adjust: U32 -> U32 = fn value => @u32.add value offset
    \\
;
const generic_type_alpha =
    \\opaque type Token payload = payload
    \\private const offset = 2
    \\const make: a -> Token a = fn value => #Token value
    \\const read: Token a -> a = fn (#Token value) => value
    \\const adjust: U32 -> U32 = fn value => @u32.add value offset
    \\
;
const generic_scheme_alpha =
    \\opaque type Token payload = payload
    \\private const offset = 2
    \\const make: item -> Token item = fn argument => #Token argument
    \\const read: Token item -> item = fn (#Token argument) => argument
    \\const adjust: U32 -> U32 = fn value => @u32.add value offset
    \\
;
const generic_bridge =
    \\import {Token, make, read, adjust} from "./tokens"
    \\const factories = #[make, fn value => make value]
    \\const readers = #[read, fn value => read value]
    \\const transform = fn (value: U32) => do:
    \\  let token: Token U32 = (factories[@u32.rem value 2]) (adjust value)
    \\  return (readers[@u32.rem value 2]) token
    \\
;
const Case = struct { name: []const u8, source: []const u8, expected: u32 = 42 };
const cases = [_]Case{
    .{ .name = "initial", .source = scalar },
    .{ .name = "private_binding_insert", .source = "private const unrelated = 99\n" ++ scalar },
    .{ .name = "private_type_insert", .source = "private type Spare is data = #Spare U32\n" ++ scalar },
    .{ .name = "private_effect_insert", .source = "private type PrivateRead is effect = Unit -> U32\n" ++ scalar },
    .{ .name = "private_contract_insert", .source = "private type Hidden a is contract = {type_rep a}\n" ++ scalar },
    .{ .name = "private_binding_move", .source = moved },
    .{ .name = "value_parameter_alpha", .source = alpha },
    .{ .name = "private_body", .expected = 43, .source = "opaque type Token = U32\nprivate const offset = 3\nconst make: U32 -> Token = fn value => #Token (@u32.add value offset)\nconst read: Token -> U32 = fn (#Token value) => value\n" },
    .{ .name = "opaque_f32", .source = floating },
    .{ .name = "opaque_reference", .source = reference },
    .{ .name = "opaque_record", .source = record },
    .{ .name = "private_field_rename", .source = renamed },
    .{ .name = "revert", .source = scalar },
};
const generic_cases = [_]Case{
    .{ .name = "generic_initial", .source = generic },
    .{ .name = "type_parameter_alpha", .source = generic_type_alpha },
    .{ .name = "scheme_parameter_alpha", .source = generic_scheme_alpha },
    .{ .name = "generic_revert", .source = generic },
};
const Work = struct {
    elaborations: usize,
    lowerings: usize,
    entry_elaborations: usize,
    entry_lowerings: usize,
    module_reused: usize,
    entry_reused: usize,
};
const Observation = struct {
    requested_bytes: usize,
    allocations: usize,
    live_before: usize,
    peak_live_bytes: usize,
    live_after_build: usize,
    live_after_result: usize,
    live_after_teardown: ?usize = null,
    work: Work,
    wasm_sha256: [32]u8,
};
fn observe(session: *retained.Session, meter: *memory.TrackedAllocator, path: [:0]const u8, output: std.Io.Dir, wasm: []const u8) !Observation {
    const before = meter.counts;
    // Rearm only the high-water mark; existing live owners remain counted.
    meter.counts.peak_bytes = before.live_bytes;
    var result = try session.revise(io, path, null, .{});
    var result_alive = true;
    defer if (result_alive) result.deinit(meter.allocator());
    try std.testing.expect(result.result.diagnostic == null);
    try std.testing.expect(result.result.compiled.diagnostic == null);
    const counts = meter.counts;
    const work: Work = .{
        .elaborations = session.last.fallback.body_elaborations,
        .lowerings = session.last.fallback.body_lowerings,
        .entry_elaborations = result.result.stats.body_elaborations,
        .entry_lowerings = result.result.stats.body_lowerings,
        .module_reused = session.last.fallback.module_cutoff.reused,
        .entry_reused = session.last.fallback.entry_cutoff.reused,
    };
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(result.result.compiled.bytes, &digest, .{});
    try output.writeFile(io, .{ .sub_path = wasm, .data = result.result.compiled.bytes });
    // The final result buffer is released before observing the retained state.
    result.deinit(meter.allocator());
    result_alive = false;
    return .{
        .requested_bytes = counts.allocated_bytes - before.allocated_bytes,
        .allocations = counts.allocations - before.allocations,
        .live_before = before.live_bytes,
        .peak_live_bytes = counts.peak_bytes,
        .live_after_build = counts.live_bytes,
        .live_after_result = meter.counts.live_bytes,
        .work = work,
        .wasm_sha256 = digest,
    };
}
fn report(group: []const u8, tier: Tier, item: Case, mode: []const u8, observation: Observation) !void {
    const hex = std.fmt.bytesToHex(observation.wasm_sha256, .lower);
    const row = try std.json.Stringify.valueAlloc(harness, .{
        .group = group,
        .tier = @tagName(tier),
        .case = item.name,
        .mode = mode,
        .expected = item.expected,
        .requested_bytes = observation.requested_bytes,
        .allocations = observation.allocations,
        .live_before = observation.live_before,
        .peak_live_bytes = observation.peak_live_bytes,
        .live_after_build = observation.live_after_build,
        .live_after_result = observation.live_after_result,
        .live_after_teardown = observation.live_after_teardown,
        .work = observation.work,
        .wasm_sha256 = @as([]const u8, &hex),
    }, .{});
    defer harness.free(row);
    std.debug.print("BLOT_MODULE_CUTOFF {s}\n", .{row});
}
fn campaign(group: []const u8, bridge_text: []const u8, inputs: []const Case) !void {
    var fixture = std.testing.tmpDir(.{});
    defer fixture.cleanup();
    try fixture.dir.writeFile(io, .{ .sub_path = "main.blot", .data = entry });
    try fixture.dir.writeFile(io, .{ .sub_path = "bridge.blot", .data = bridge_text });
    const path = try fixture.dir.realPathFileAlloc(io, "main.blot", harness);
    defer harness.free(path);
    for ([_]Tier{ .development, .optimized }) |tier| {
        var meter: memory.TrackedAllocator = .{ .backing = std.heap.smp_allocator };
        var session = try retained.Session.initEmpty(meter.allocator(), .{});
        var alive = true;
        defer if (alive) session.deinit();
        session.policy.codegen_tier = tier;
        session.policy.codegen_workers = 1;
        for (inputs, 0..) |item, index| {
            try fixture.dir.writeFile(io, .{ .sub_path = "tokens.blot", .data = item.source });
            const retained_name = try harness.print("{s}-{s}-retained.wasm", .{ @tagName(tier), item.name });
            defer harness.free(retained_name);
            const actual = try observe(&session, &meter, path, fixture.dir, retained_name);
            if (index != 0) {
                try std.testing.expectEqual(@as(usize, 1), actual.work.module_reused);
                try std.testing.expectEqual(@as(usize, 1), actual.work.entry_reused);
            }
            try report(group, tier, item, "retained", actual);
            var fresh_meter: memory.TrackedAllocator = .{ .backing = std.heap.smp_allocator };
            var fresh = try retained.Session.initEmpty(fresh_meter.allocator(), .{});
            var fresh_alive = true;
            defer if (fresh_alive) fresh.deinit();
            fresh.policy.codegen_tier = tier;
            fresh.policy.codegen_workers = 1;
            const fresh_name = try harness.print("{s}-{s}-fresh.wasm", .{ @tagName(tier), item.name });
            defer harness.free(fresh_name);
            var control = try observe(&fresh, &fresh_meter, path, fixture.dir, fresh_name);
            try std.testing.expectEqualSlices(u8, &control.wasm_sha256, &actual.wasm_sha256);
            fresh.deinit();
            fresh_alive = false;
            control.live_after_teardown = fresh_meter.counts.live_bytes;
            try std.testing.expectEqual(@as(usize, 0), control.live_after_teardown.?);
            try report(group, tier, item, "fresh", control);
        }
        session.deinit();
        alive = false;
        try std.testing.expectEqual(@as(usize, 0), meter.counts.live_bytes);
        std.debug.print("BLOT_MODULE_CUTOFF_FINAL {{\"group\":\"{s}\",\"tier\":\"{s}\",\"live_bytes\":{d}}}\n", .{ group, @tagName(tier), meter.counts.live_bytes });
    }
}
test "cutoff allocation observations" {
    try campaign("storage", bridge, &cases);
    try campaign("generic", generic_bridge, &generic_cases);
}
