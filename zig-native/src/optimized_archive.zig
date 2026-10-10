//! Portable optimizer captures for the dependency-cache experiment. This stores
//! no native pointers, allocator capacities or source/evaluator owners. Loading
//! supplies candidates only: the ordinary exact optimizer matcher must still
//! admit each body against freshly generated code and completed lifetime facts.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const bodies = @import("optimized_bodies.zig");
const lifetime = @import("wasm_lifetimes.zig");
const format = @import("dependency_format.zig");
const A = std.mem.Allocator;
const Body = struct { locals: []ir.ValueType, instructions: []ir.Instruction };
const Function = struct { parameters: []ir.ValueType, result: ir.ValueType, signature: u32, body: Body };
const Entry = struct {
    source: Function,
    parameters: []lifetime.Parameter,
    invalidates: bool,
    owned_result_bytes: ?u32,
    output: ?Body,
    output_ready: bool,
};
const Snapshot = struct {
    tier: @import("compilation_tier.zig").Tier,
    arena: ?@import("wasm.zig").Arena,
    entries: []Entry,
    signatures: []ir.Signature,
    imports: []u32,
    globals: []ir.ValueType,
};
fn key(compiler: format.Digest) format.Key {
    // Source and dependency validity is deliberately not granted by this
    // header. Matcher compares complete machine inputs after loading.
    return .{ .compiler = compiler, .settings = format.digest("blot-optimizer-capture-v1"), .source = @splat(0), .dependencies = @splat(0) };
}
pub fn encode(a: A, compiler: format.Digest, capture: *const bodies.Capture) format.Error![]u8 {
    const entries = try a.alloc(Entry, capture.entries.items.len);
    defer a.free(entries);
    for (capture.entries.items, entries) |entry, *wire| wire.* = .{
        .source = .{ .parameters = entry.source.parameters, .result = entry.source.result, .signature = entry.source.signature, .body = .{ .locals = entry.source.locals.items, .instructions = entry.source.instructions.items } },
        .parameters = entry.parameters,
        .invalidates = entry.invalidates,
        .owned_result_bytes = entry.owned_result_bytes,
        .output = if (entry.output) |output| .{ .locals = output.locals.items, .instructions = output.instructions.items } else null,
        .output_ready = entry.output_ready,
    };
    const snapshot: Snapshot = .{ .tier = capture.tier, .arena = capture.arena, .entries = entries, .signatures = capture.signatures.items, .imports = capture.imports.items, .globals = capture.globals.items };
    return format.encode(a, key(compiler), snapshot);
}
pub fn decode(a: A, compiler: format.Digest, bytes: []const u8) format.Error!bodies.Capture {
    var snapshot = try format.decode(Snapshot, a, bytes, key(compiler));
    defer format.deinit(a, &snapshot);
    for (snapshot.entries) |entry| {
        if (entry.source.signature >= snapshot.signatures.len or entry.parameters.len != entry.source.parameters.len or (!entry.output_ready and entry.output != null)) return error.InvalidArtifact;
        const signature = snapshot.signatures[entry.source.signature];
        if (signature.result != entry.source.result or !std.mem.eql(ir.ValueType, signature.parameters, entry.source.parameters)) return error.InvalidArtifact;
        if (!validTypes(entry.source.parameters) or !validTypes(entry.source.body.locals)) return error.InvalidArtifact;
        if (entry.output) |body| if (!validTypes(body.locals)) return error.InvalidArtifact;
    }
    for (snapshot.imports) |signature| if (signature >= snapshot.signatures.len) return error.InvalidArtifact;
    if (!validTypes(snapshot.globals)) return error.InvalidArtifact;
    var result: bodies.Capture = .{ .allocator = a, .tier = snapshot.tier, .arena = snapshot.arena };
    errdefer result.deinit();
    try result.entries.ensureTotalCapacity(a, snapshot.entries.len);
    for (snapshot.entries) |*entry| {
        result.entries.appendAssumeCapacity(.{
            .source = .{ .parameters = entry.source.parameters, .result = entry.source.result, .signature = entry.source.signature, .locals = .fromOwnedSlice(entry.source.body.locals), .instructions = .fromOwnedSlice(entry.source.body.instructions) },
            .parameters = entry.parameters,
            .invalidates = entry.invalidates,
            .owned_result_bytes = entry.owned_result_bytes,
            .output = if (entry.output) |body| .{ .locals = .fromOwnedSlice(body.locals), .instructions = .fromOwnedSlice(body.instructions) } else null,
            .output_ready = entry.output_ready,
        });
        entry.source.parameters = &.{};
        entry.source.body = .{ .locals = &.{}, .instructions = &.{} };
        entry.parameters = &.{};
        entry.output = null;
    }
    result.signatures = .fromOwnedSlice(snapshot.signatures);
    snapshot.signatures = &.{};
    result.imports = .fromOwnedSlice(snapshot.imports);
    snapshot.imports = &.{};
    result.globals = .fromOwnedSlice(snapshot.globals);
    snapshot.globals = &.{};
    try result.sealQueries();
    return result;
}
fn validTypes(values: []const ir.ValueType) bool {
    for (values) |value| if (value == .none) return false;
    return true;
}
