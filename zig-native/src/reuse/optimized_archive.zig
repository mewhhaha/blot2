//! Portable optimizer captures and their complete query records. This stores
//! no native pointers, allocator capacities, fingerprints or source/evaluator
//! owners. Loading supplies candidates only: the ordinary exact optimizer
//! matcher must still admit each body against freshly generated code and
//! completed lifetime facts.
const std = @import("std");
const ir = @import("../backend/runtime_ir.zig");
const bodies = @import("../backend/optimized_bodies.zig");
const executable = @import("executable_query.zig");
const lifetime = @import("../backend/wasm_lifetimes.zig");
const wasm = @import("../backend/wasm.zig");
const portable = @import("portable_query.zig");
const format = @import("dependency_format.zig");
const Tier = @import("../compilation_tier.zig").Tier;
const A = std.mem.Allocator;
pub const Body = struct { locals: []ir.ValueType, instructions: []ir.Instruction };
pub const Function = struct { parameters: []ir.ValueType, result: ir.ValueType, result_role: ir.Role = .unknown, entry: bool = false, provider_parameter: u16 = ir.unknown_provider, callable_layout: u32 = 0, parameter_roles: u64, annotations: u32, signature: u32, body: Body };
pub const Entry = struct {
    source: Function,
    parameters: []lifetime.Parameter,
    invalidates: bool,
    owned_result_bytes: ?u32,
    output: ?Body,
    output_ready: bool,
};
/// Entry ordinals name `Snapshot.entries`. Bucket fingerprints are
/// recomputed from the decoded machine input, never trusted from the wire.
pub const Key = struct { tier: Tier };
pub const Dependencies = struct {
    callees: []u32,
    parameters: []lifetime.Parameter,
    invalidates: bool,
    owned_result_bytes: ?u32,
};
pub const Result = struct { function: u32 };
pub const Record = struct { key: Key, dependencies: Dependencies, result: Result };
pub const Section = portable.Section(.optimizer_output, Record);
pub const Snapshot = struct {
    tier: Tier,
    roots: bool = false,
    needs_roots: bool = false,
    root_slots: u32 = 0,
    arena: ?wasm.Arena,
    regions: ?@import("../runtime/region_runtime.zig").Prepared = null,
    entries: []Entry,
    signatures: []ir.Signature,
    imports: []bodies.Import,
    globals: []wasm.Global,
    providers: []@import("../backend/provider_modes.zig").Mode = &.{},
    /// False for an unsealed or saturated table, which carries no records and
    /// declines all reuse after loading.
    sealed: bool,
    queries: Section,
};
pub fn wireKey(compiler: format.Digest) format.Key {
    // Source and dependency validity is deliberately not granted by this
    // header. Matcher compares complete machine inputs after loading.
    return .{ .compiler = compiler, .settings = format.digest("blot-optimizer-capture-v39:owned-region-preparation-context+physical-tracing-absent+checked-logical-callable-endpoints+checked-provider-modes+checked-provider-parameters+selected-implementations+associated-types+checked-call-results+root-frame-demand+compact-roots+row-fusion+forwarded-roots+paired-state+numeric-scopes+row-products+conditional-roots+private-local-storage+immutable-acyclic-layouts+direct-callable-environments+scalar-journals+owned-field-locals+small-producer-groups+qualified-journal-fallback+private-cursors+private-table-projections+private-cursor-word-positions+snapshot-leaf-directory+eager-tuple-reductions+symbolic-empty-constructor-fields+activation-owned-field-roots+checked-nonempty-loads+private-absent-fields+journal-only-carriers+immortal-reference-facts+prefix-owned-fields+progress-sized-replacement+per-loop-journal-cost+bounded-private-scalar-consumers+bounded-invalidation-worklist+structured-control-reachability+completed-empty-producer-loops+checked-scalar-self-identities+checked-field-update-layouts+checked-scalar-stores+wide-counted-shapes+deferred-partial-tracing+checked-list-literal-publication+prepared-machine-sharing+proved-list-runtime-access+checked-production-emission+resolved-collection-iteration+exact-empty-cursor"), .source = @splat(0), .dependencies = @splat(0) };
}
pub fn encode(a: A, compiler: format.Digest, capture: *const bodies.Capture) format.Error![]u8 {
    const entries = try a.alloc(Entry, capture.entries.items.len);
    defer a.free(entries);
    for (capture.entries.items, entries) |entry, *wire| wire.* = .{
        .source = .{ .parameters = entry.source.parameters, .result = entry.source.result, .result_role = entry.source.result_role, .entry = entry.source.entry, .parameter_roles = entry.source.parameter_roles, .provider_parameter = entry.source.provider_parameter, .callable_layout = entry.source.callable_layout, .annotations = entry.source.annotations, .signature = entry.source.signature, .body = .{ .locals = entry.source.locals.items, .instructions = entry.source.instructions.items } },
        .parameters = entry.parameters,
        .invalidates = entry.invalidates,
        .owned_result_bytes = entry.owned_result_bytes,
        .output = if (entry.output) |output| .{ .locals = output.locals.items, .instructions = output.instructions.items } else null,
        .output_ready = entry.output_ready,
    };
    // An incomplete table certifies nothing, so none of its records persist.
    const sealed = capture.queries_complete;
    const records = try a.alloc(Record, if (sealed) capture.queries.records.items.len else 0);
    defer a.free(records);
    for (records, capture.queries.records.items[0..records.len]) |*wire, record| wire.* = .{
        .key = .{ .tier = record.key.tier },
        .dependencies = .{ .callees = record.dependencies.callees, .parameters = record.dependencies.parameters, .invalidates = record.dependencies.invalidates, .owned_result_bytes = record.dependencies.owned_result_bytes },
        .result = .{ .function = record.value.function },
    };
    const snapshot: Snapshot = .{ .tier = capture.tier, .roots = capture.roots, .needs_roots = capture.needs_roots, .root_slots = capture.root_slots, .arena = capture.arena, .regions = capture.regions, .entries = entries, .signatures = capture.signatures.items, .imports = capture.imports.items, .globals = capture.globals.items, .providers = capture.providers.items, .sealed = sealed, .queries = .{ .header = portable.header(Section.claim), .records = records } };
    return format.encode(a, wireKey(compiler), snapshot);
}
pub fn decode(a: A, compiler: format.Digest, bytes: []const u8) format.Error!bodies.Capture {
    var snapshot = try format.decode(Snapshot, a, bytes, wireKey(compiler));
    defer format.deinit(a, &snapshot);
    try validate(a, &snapshot);
    var result: bodies.Capture = .{ .allocator = a, .tier = snapshot.tier, .roots = snapshot.roots, .needs_roots = snapshot.needs_roots, .root_slots = snapshot.root_slots, .arena = snapshot.arena };
    errdefer result.deinit();
    result.regions = snapshot.regions;
    snapshot.regions = null;
    try result.entries.ensureTotalCapacity(a, snapshot.entries.len);
    for (snapshot.entries) |*entry| {
        result.entries.appendAssumeCapacity(.{
            .source = .{ .parameters = entry.source.parameters, .result = entry.source.result, .result_role = entry.source.result_role, .entry = entry.source.entry, .parameter_roles = entry.source.parameter_roles, .provider_parameter = @intCast(entry.source.provider_parameter), .callable_layout = entry.source.callable_layout, .annotations = entry.source.annotations, .signature = entry.source.signature, .locals = .fromOwnedSlice(entry.source.body.locals), .instructions = .fromOwnedSlice(entry.source.body.instructions) },
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
    result.providers = .fromOwnedSlice(snapshot.providers);
    snapshot.providers = &.{};
    result.globals = .fromOwnedSlice(snapshot.globals);
    snapshot.globals = &.{};
    if (snapshot.sealed) try seal(&result, snapshot.queries.records);
    return result;
}
/// Rebuild the native index in wire order from validated owned records. The
/// table's own limits still apply; saturation leaves it unsealed and declines.
fn seal(capture: *bodies.Capture, records: []Record) A.Error!void {
    const a = capture.allocator;
    for (records) |*record| {
        var builder = executable.OptimizerTable.begin(a, .{ .local_fingerprint = @import("../backend/runtime_body_relocation.zig").hash(capture.entries.items[record.result.function].source), .tier = record.key.tier });
        defer builder.abort();
        builder.read(.{ .callees = record.dependencies.callees, .parameters = record.dependencies.parameters, .invalidates = record.dependencies.invalidates, .owned_result_bytes = record.dependencies.owned_result_bytes, .context_complete = true });
        record.dependencies.callees = &.{};
        record.dependencies.parameters = &.{};
        builder.stage(.{ .function = record.result.function, .ready = true });
        var candidate = builder.complete() orelse return;
        defer candidate.abort();
        const prepared = try capture.queries.prepare(a, &candidate) orelse return;
        _ = capture.queries.publish(prepared, &candidate);
    }
    capture.queries_complete = true;
}
/// Structural context checks grant no ownership. Reuse still requires exact
/// equality with a context independently reconstructed from executable source.
pub fn validateRegions(a: A, snapshot: *const Snapshot) format.Error!void {
    if (snapshot.regions) |regions| {
        if (!snapshot.roots or !snapshot.needs_roots or snapshot.arena == null or regions.scopes.len > snapshot.entries.len or !regions.plan.valid()) return error.InvalidArtifact;
        const functions = try a.alloc(ir.Function, snapshot.entries.len);
        defer a.free(functions);
        for (functions, snapshot.entries) |*function, entry| {
            if (entry.source.provider_parameter > std.math.maxInt(u8)) return error.InvalidArtifact;
            function.* = .{
                .parameters = entry.source.parameters,
                .result = entry.source.result,
                .result_role = entry.source.result_role,
                .entry = entry.source.entry,
                .parameter_roles = entry.source.parameter_roles,
                .provider_parameter = @intCast(entry.source.provider_parameter),
                .signature = entry.source.signature,
            };
            if (!function.validProviderParameter()) return error.InvalidArtifact;
        }
        var module = wasm.Module.init(a);
        module.functions = .fromOwnedSlice(functions);
        if (!regions.valid(&module)) return error.InvalidArtifact;
    }
}
/// Every ordinal is checked before the Capture is exposed: call, import,
/// indirect-signature, global and local operands, block types, lanes and
/// structured control in source and output bodies, the arena's functions and
/// globals, and each record against the exact machine input it names.
pub fn validate(a: A, snapshot: *const Snapshot) format.Error!void {
    const section = snapshot.queries;
    if (section.header.version != portable.version) return error.UnsupportedVersion;
    if (!section.admitted()) return error.SchemaMismatch;
    var frames: std.ArrayList(bool) = .empty;
    defer frames.deinit(a);
    const resources: Resources = .{ .functions = snapshot.entries.len, .imports = snapshot.imports.len, .signatures = snapshot.signatures.len, .globals = snapshot.globals.len, .frames = &frames };
    if (snapshot.providers.len > 4096) return error.InvalidArtifact;
    for (snapshot.providers, 0..) |mode, index| {
        if (mode.operation == 0 or (index != 0 and snapshot.providers[index - 1].operation >= mode.operation)) return error.InvalidArtifact;
        if (mode.access != .unsupported and ((mode.role != .scalar and mode.role != .reference) or (mode.machine != .i32 and mode.machine != .f32) or (mode.role == .reference and mode.machine != .i32))) return error.InvalidArtifact;
    }
    for (snapshot.signatures) |signature| if (!validTypes(signature.parameters)) return error.InvalidArtifact;
    for (snapshot.imports) |item| {
        if (item.signature >= snapshot.signatures.len or !std.unicode.utf8ValidateSlice(item.module) or !std.unicode.utf8ValidateSlice(item.name)) return error.InvalidArtifact;
    }
    if (snapshot.arena) |arena| {
        inline for (wasm.Arena.function_fields) |field| if (@field(arena, field) >= resources.functions) return error.InvalidArtifact;
        inline for (wasm.Arena.global_fields) |field| if (@field(arena, field) >= resources.globals) return error.InvalidArtifact;
    }
    if (snapshot.roots and (snapshot.arena == null or snapshot.root_slots < snapshot.globals.len or snapshot.root_slots > std.math.maxInt(u32) / 4)) return error.InvalidArtifact;
    if (!snapshot.roots and snapshot.needs_roots) return error.InvalidArtifact;
    if (!snapshot.roots and snapshot.root_slots != 0) return error.InvalidArtifact;
    for (snapshot.entries) |entry| {
        if (entry.source.signature >= snapshot.signatures.len or entry.parameters.len != entry.source.parameters.len or (!entry.output_ready and entry.output != null)) return error.InvalidArtifact;
        if (entry.source.result_role == .reference and entry.source.result != .i32) return error.InvalidArtifact;
        if (entry.source.callable_layout >= 1 << 26) return error.InvalidArtifact;
        const provider = entry.source.provider_parameter;
        if (provider != ir.unknown_provider and provider != ir.no_provider and (provider >= entry.source.parameters.len or entry.source.parameters[provider] != .i32 or provider >= 32 or @as(u2, @truncate(entry.source.parameter_roles >> @as(u6, @intCast(provider * 2)))) != @backingInt(ir.Role.reference))) return error.InvalidArtifact;
        const signature = snapshot.signatures[entry.source.signature];
        if (signature.result != entry.source.result or !std.mem.eql(ir.ValueType, signature.parameters, entry.source.parameters)) return error.InvalidArtifact;
        if (!validTypes(entry.source.parameters) or !validTypes(entry.source.body.locals)) return error.InvalidArtifact;
        var annotations: usize = 0;
        for (entry.source.body.instructions) |inst| annotations += @intFromBool(inst.op == .ownership);
        if (annotations != entry.source.annotations) return error.InvalidArtifact;
        if (!try resources.body(a, entry.source.parameters.len, entry.source.body)) return error.InvalidArtifact;
        if (entry.output) |body| if (!validTypes(body.locals) or !try resources.body(a, entry.source.parameters.len, body)) return error.InvalidArtifact;
    }
    try validateRegions(a, snapshot);
    if (!snapshot.sealed) {
        if (section.records.len != 0) return error.InvalidArtifact;
        return;
    }
    // A sealed table holds exactly one record per ready entry, in ascending
    // source order, each equal to the facts derived from that entry.
    var next: usize = 0;
    for (snapshot.entries, 0..) |entry, id| {
        if (!entry.output_ready) continue;
        if (next == section.records.len or !recordMatches(section.records[next], snapshot, id)) return error.InvalidArtifact;
        next += 1;
    }
    if (next != section.records.len) return error.InvalidArtifact;
}
fn recordMatches(record: Record, snapshot: *const Snapshot, id: usize) bool {
    const entry = snapshot.entries[id];
    if (record.result.function != id or record.key.tier != snapshot.tier) return false;
    const observed = record.dependencies;
    if (observed.invalidates != entry.invalidates or observed.owned_result_bytes != entry.owned_result_bytes or observed.parameters.len != entry.parameters.len) return false;
    for (observed.parameters, entry.parameters) |left, right| if (!std.meta.eql(left, right)) return false;
    var cursor: usize = 0;
    for (entry.source.body.instructions) |inst| if (inst.op == .call or inst.table_reference) {
        if (cursor == observed.callees.len or observed.callees[cursor] != inst.operand) return false;
        cursor += 1;
    };
    return cursor == observed.callees.len;
}
const Resources = struct {
    functions: usize,
    imports: usize,
    signatures: usize,
    globals: usize,
    /// One entry per open frame: true while an `if` may still take `else`.
    frames: *std.ArrayList(bool),
    /// Mirrors the encoder's operand interpretation: structured control
    /// closes within the body, whose final `end` the encoder appends.
    fn body(self: Resources, a: A, parameters: usize, value: Body) A.Error!bool {
        const locals = parameters +| value.locals.len;
        const frames = self.frames;
        frames.clearRetainingCapacity();
        for (value.instructions, 0..) |inst, at| {
            if (inst.op == .ownership) {
                const annotation: ir.Ownership = @bitCast(inst.operand);
                if (annotation.kind == .call_result) {
                    if (annotation.chunk != 0 or annotation.roles > @backingInt(ir.Role.value)) return false;
                    if (at + 1 >= value.instructions.len or value.instructions[at + 1].op != .call_indirect) return false;
                }
            }
            if ((!inst.table_reference and inst.table_kind != .unknown) or (inst.table_reference and (inst.op != .i32_const or inst.operand >= self.functions))) return false;
            const valid = switch (inst.op) {
                .block, .loop, .if_ => opens: {
                    if (inst.operand != 0 and std.enums.fromInt(ir.ValueType, inst.operand) == null) break :opens false;
                    try frames.append(a, inst.op == .if_);
                    break :opens true;
                },
                .else_ => alternative: {
                    if (frames.items.len == 0) break :alternative false;
                    const open = &frames.items[frames.items.len - 1];
                    const allowed = open.*;
                    open.* = false;
                    break :alternative allowed;
                },
                .end => frames.pop() != null,
                .br, .br_if => inst.operand <= frames.items.len,
                .call => inst.operand < self.functions,
                .call_import => inst.operand < self.imports,
                .call_indirect => inst.operand < self.signatures,
                .global_get, .global_set => inst.operand < self.globals,
                .local_get, .local_set, .local_tee => inst.operand < locals,
                .i32x4_replace_lane, .i32x4_extract_lane, .f32x4_extract_lane, .f32x4_replace_lane => inst.operand < 4,
                else => true,
            };
            if (!valid) return false;
        }
        return frames.items.len == 0;
    }
};
fn validTypes(values: []const ir.ValueType) bool {
    for (values) |value| if (value == .none) return false;
    return true;
}
