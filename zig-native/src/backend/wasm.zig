//! Flat symbolic function bodies, assembled deterministically into Wasm.
//! Function handles are semantic instance IDs until final assembly.
const std = @import("std");
const arena_runtime = @import("../runtime/arena_runtime.zig");
const artifact = @import("../reuse/artifact_emitter.zig");
const heap_layout = @import("../runtime/runtime_layout.zig");
const Allocator = std.mem.Allocator;

const ir = @import("runtime_ir.zig");
pub const ValueType = ir.ValueType;
pub const Scalar = ir.Scalar;
pub const Op = ir.Op;
pub const Instruction = ir.Instruction;
pub const Signature = ir.Signature;
pub const Function = ir.Function;
pub const Global = struct { scalar: Scalar, bits: u32, mutable: bool = false };
const Import = struct { module: []u8, name: []u8, signature: u32 };
pub const Callback = struct { parameter: Scalar, result: Scalar, cleanup: bool = false, owned: bool = false, data: bool = false, schema: u32 = 0, concurrent: bool = false };
pub const OwnershipFallback = enum(u8) { none, no_arena, public_arena, host_references, imports, initializer, static_sequence_cache, unproven_body };
pub const OwnerBoundary = struct { schema: u32, kind: enum(u8) { unique = 1, shared = 2 }, fresh: ?Scalar = null };
const Export = struct { name: []u8, index: u32, parameter: Scalar, result: Scalar, global: bool, callback: ?Callback = null, once: bool = false, parameter_owner: ?OwnerBoundary = null, result_owner: ?OwnerBoundary = null, owner_adapter: bool = false, task_adapter: bool = false, task_runtime: bool = false };
pub const Arena = struct {
    pub const function_fields = .{ "allocate", "allocate_scalar", "recycle", "reset", "allocate_typed", "retain", "release", "release_lease", "retire", "free", "store_word", "copy_words", "decrement", "root_allocate", "root_reserve", "root_pop", "root_open", "root_close", "root_enter", "root_leave", "root_store", "root_public_allocate", "root_public_reset", "root_force", "root_authority", "cycle_enqueue", "cycle_unlink", "cycle_visit", "cycle_collect", "cycle_safe", "mark_acyclic", "allocate_shaped", "root_allocate_shaped" };
    pub const global_fields = .{ "heap", "base", "static_end", "allocated", "rc_enabled", "rc_leases", "rc_retains", "rc_releases", "rc_destroyed", "root_enabled", "root_page", "root_top", "root_frame", "root_active", "root_external", "root_count", "root_globals", "root_started", "root_host_cursor", "root_host_active", "root_static_map", "root_static_count", "root_global_count", "cycle_head", "cycle_members", "cycle_work", "cycle_phase", "cycle_removed", "cycle_cadence", "cycle_passes", "cycle_vertices", "cycle_edges", "cycle_bytes", "cycle_threshold" };
    mark_acyclic: u32,
    allocate_shaped: u32,
    root_allocate_shaped: u32,
    allocate: u32,
    allocate_scalar: u32,
    recycle: u32,
    reset: u32,
    heap: u32,
    base: u32,
    static_end: u32,
    allocated: u32,
    rc_enabled: u32,
    rc_leases: u32,
    rc_retains: u32,
    rc_releases: u32,
    rc_destroyed: u32,
    allocate_typed: u32,
    retain: u32,
    release: u32,
    release_lease: u32,
    retire: u32,
    free: u32,
    store_word: u32,
    copy_words: u32,
    decrement: u32,
    root_allocate: u32,
    root_reserve: u32,
    root_pop: u32,
    root_open: u32,
    root_close: u32,
    root_enter: u32,
    root_leave: u32,
    root_store: u32,
    root_public_allocate: u32,
    root_public_reset: u32,
    root_force: u32,
    root_authority: u32,
    root_enabled: u32,
    root_page: u32,
    root_top: u32,
    root_frame: u32,
    root_active: u32,
    root_external: u32,
    root_count: u32,
    root_globals: u32,
    root_started: u32,
    root_host_cursor: u32,
    root_host_active: u32,
    root_static_map: u32,
    root_static_count: u32,
    root_global_count: u32,

    cycle_enqueue: u32,
    cycle_unlink: u32,
    cycle_visit: u32,
    cycle_collect: u32,
    cycle_safe: u32,
    cycle_head: u32,
    cycle_members: u32,
    cycle_work: u32,
    cycle_phase: u32,
    cycle_removed: u32,
    cycle_cadence: u32,
    cycle_passes: u32,
    cycle_vertices: u32,
    cycle_edges: u32,
    cycle_bytes: u32,
    cycle_threshold: u32,

    pub fn isAllocation(self: Arena, function: u32) bool {
        return function == self.allocate or function == self.allocate_scalar;
    }
};
pub const OwnershipFailure = struct { fallback: OwnershipFallback = .none, function: ?u32 = null };
pub const AssemblyOptions = struct {
    rejection: ?*OwnershipFailure = null,
    io: ?std.Io = null,
    workers: u8 = 1,
    tier: @import("../compilation_tier.zig").Tier = .optimized,
    share_machine_code: bool = false,
    /// Experimental scalar patch linker. Imported tables are never initialized
    /// by an element segment; the host publishes replacements after validation.
    import_function_table: ?u32 = null,
    export_function_table: bool = false,
    /// Private execution laws inspect counted headers without the Array ABI.
    export_memory: bool = false,
    previous: ?*const @import("optimized_bodies.zig").Capture = null,
    current: ?*@import("optimized_bodies.zig").Capture = null,
    stats: ?*@import("optimized_bodies.zig").Stats = null,
};
/// Handles are indexes into an externref table, never encoded host pointers.
/// Callers retain a cursor mark and release only handles owned by that scope.
pub const HostReferences = struct { retain: u32, release: u32, cursor: u32, active: u32 };
fn isArray(scalar: Scalar) bool {
    return scalar == .array_u32 or scalar == .array_f32;
}
fn callbackName(scalar: Scalar) ?[]const u8 {
    return switch (scalar) {
        .unit => "unit",
        .u32 => "u32",
        .bool => "bool",
        .f32 => "f32",
        .array_u32 => "array_u32",
        .array_f32 => "array_f32",
        .pointer => null,
    };
}

pub const Module = struct {
    allocator: Allocator,
    artifacts: ?*artifact.Recorder = null,
    functions: std.ArrayList(Function) = .empty,
    signatures: std.ArrayList(Signature) = .empty,
    imports: std.ArrayList(Import) = .empty,
    globals: std.ArrayList(Global) = .empty,
    exports: std.ArrayList(Export) = .empty,
    data: std.ArrayList(u8) = .empty,
    arena: ?Arena = null,
    /// Explicit raw reference-fixture helpers; never recorded or accepted by production.
    fixture_helpers: ?[3]u32 = null,
    lists: ?@import("../runtime/list_runtime.zig").Runtime = null,
    /// Installed only in an admitted late assembly view, never Source artifacts.
    cohorts: ?@import("../runtime/cohort_runtime.zig").Runtime = null,
    regions: ?@import("../runtime/region_runtime.zig").Prepared = null,
    host_references: ?HostReferences = null,
    public_arena: bool = false,
    cleanup_data: []u8 = &.{},
    /// Source generation decides cycle helper demand after completing bodies.
    defer_cycles: bool = false,
    mutable_static: bool = false,
    static_fields: std.ArrayList(u32) = .empty,
    /// Compiler-owned callable table references, including immutable data.
    table_functions: std.ArrayList(u32) = .empty,
    table_origins: std.ArrayList(TableOrigin) = .empty,
    semantic_sites: std.ArrayList(SemanticSite) = .empty,
    indirect: bool = false,
    start: ?u32 = null,
    /// Owned Core emission coordinates, independent of diagnostic provenance.
    /// Consumers must rederive every logical relationship from the pinned Core.
    pub const SemanticSite = struct {
        function: u32,
        place: u32,
        unit: u32,
        node: u32,
        root: u32,
        mappings: u32,
        rows: u32,
        kind: enum { allocation, call },
    };
    pub fn recordSemanticSite(self: *Module, site: SemanticSite) Allocator.Error!void {
        if (self.artifacts) |journal| try journal.append(.{ .semantic_site = site });
        try self.semantic_sites.append(self.allocator, site);
    }
    pub const TableOrigin = struct { target: u32, kind: ir.TableKind, function: ?u32, place: u32 };
    pub fn init(allocator: Allocator) Module {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Module) void {
        for (self.functions.items) |*function| function.deinit(self.allocator);
        for (self.signatures.items) |signature| self.allocator.free(signature.parameters);
        for (self.imports.items) |item| {
            self.allocator.free(item.module);
            self.allocator.free(item.name);
        }
        for (self.exports.items) |item| self.allocator.free(item.name);
        self.functions.deinit(self.allocator);
        self.signatures.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.exports.deinit(self.allocator);
        self.data.deinit(self.allocator);
        self.static_fields.deinit(self.allocator);
        self.table_functions.deinit(self.allocator);
        self.allocator.free(self.cleanup_data);
        self.table_origins.deinit(self.allocator);
        self.semantic_sites.deinit(self.allocator);
    }
    pub fn internType(self: *Module, parameters: []const ValueType, result: ValueType) !u32 {
        for (self.signatures.items, 0..) |signature, index| {
            if (signature.result == result and std.mem.eql(ValueType, signature.parameters, parameters)) {
                try self.demandResource(.signature, @intCast(index), true);
                return @intCast(index);
            }
        }
        if (self.signatures.items.len == std.math.maxInt(u32)) return error.ModuleTooLarge;
        const owned = try self.allocator.dupe(ValueType, parameters);
        errdefer self.allocator.free(owned);
        const id: u32 = @intCast(self.signatures.items.len);
        if (self.artifacts) |journal| try journal.signature(id, parameters, result);
        try self.demandResource(.signature, id, false);
        try self.signatures.append(self.allocator, .{ .parameters = owned, .result = result });
        return id;
    }
    pub fn addFunction(self: *Module, parameters: []const ValueType, result: ValueType) !u32 {
        return self.addTypedFunction(parameters, result, .unknown);
    }
    pub fn addTypedFunction(self: *Module, parameters: []const ValueType, result: ValueType, role: ir.Role) !u32 {
        const signature = try self.internType(parameters, result);
        return self.addTypedFunctionForSignature(signature, role);
    }
    pub fn addFunctionForSignature(self: *Module, signature: u32) !u32 {
        return self.addTypedFunctionForSignature(signature, .unknown);
    }
    pub fn addTypedFunctionForSignature(self: *Module, signature: u32, role: ir.Role) !u32 {
        std.debug.assert(signature < self.signatures.items.len);
        if (self.functions.items.len == std.math.maxInt(u32)) return error.ModuleTooLarge;
        const id: u32 = @intCast(self.functions.items.len);
        if (self.artifacts) |journal| try journal.append(.{ .function = .{ .id = id, .signature = signature, .result_role = role } });
        try self.demandResource(.function, id, false);
        try self.functions.append(self.allocator, .{ .parameters = self.signatures.items[signature].parameters, .result = self.signatures.items[signature].result, .result_role = role, .signature = signature });
        return id;
    }
    /// Records parameter roles from checked layouts; replay restores them.
    pub fn setParameterRoles(self: *Module, id: u32, roles: u64) !void {
        if (roles == 0) return;
        if (self.artifacts) |journal| try journal.append(.{ .parameter_roles = .{ .function = id, .roles = roles } });
        self.functions.items[id].parameter_roles = roles;
    }
    pub fn setProviderParameter(self: *Module, id: u32, index: u16) !void {
        if (id >= self.functions.items.len or index == ir.unknown_provider) return error.InvalidFunctionReference;
        const function = &self.functions.items[id];
        if (index != ir.no_provider and (index >= function.parameters.len or function.parameters[index] != .i32 or function.parameterRole(index) != .reference)) return error.InvalidFunctionReference;
        if (self.artifacts) |journal| try journal.append(.{ .provider_parameter = .{ .function = id, .index = index } });
        function.provider_parameter = @intCast(index);
    }
    pub fn importFunction(self: *Module, namespace: []const u8, name: []const u8, parameters: []const ValueType, result: ValueType) !u32 {
        const signature = try self.internType(parameters, result);
        for (self.imports.items, 0..) |item, index| if (std.mem.eql(u8, item.module, namespace) and std.mem.eql(u8, item.name, name)) {
            if (item.signature != signature) return error.InvalidFunctionReference;
            try self.demandResource(.import_, @intCast(index), true);
            return @intCast(index);
        };
        if (self.imports.items.len >= std.math.maxInt(u32)) return error.ModuleTooLarge;
        const owned_namespace = try self.allocator.dupe(u8, namespace);
        errdefer self.allocator.free(owned_namespace);
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const index: u32 = @intCast(self.imports.items.len);
        if (self.artifacts) |journal| try journal.importFunction(index, namespace, name, signature);
        try self.demandResource(.import_, index, false);
        try self.imports.append(self.allocator, .{ .module = owned_namespace, .name = owned_name, .signature = signature });
        return index;
    }
    pub fn addLocal(self: *Module, id: u32, ty: ValueType) !u32 {
        const function = &self.functions.items[id];
        const index: u32 = @intCast(function.parameters.len + function.locals.items.len);
        if (self.artifacts) |journal| try journal.append(.{ .local = .{ .function = id, .ty = ty } });
        try function.locals.append(self.allocator, ty);
        return index;
    }
    pub fn setCallableLayout(self: *Module, id: u32, ty: u32) !void {
        if (id >= self.functions.items.len or ty == 0 or ty >= 1 << 26) return error.InvalidFunctionReference;
        if (self.artifacts) |journal| try journal.append(.{ .callable_layout = .{ .function = id, .layout = ty } });
        self.functions.items[id].callable_layout = ty;
    }
    pub fn emit(self: *Module, id: u32, instruction: Instruction) !void {
        if (instruction.op == .ownership) {
            const annotation: ir.Ownership = @bitCast(instruction.operand);
            if (annotation.kind == .rest and annotation.chunk == 7 and annotation.roles != 0) return self.emitReference(id, .{ .op = .ownership, .operand = annotation.roles }, .callable_layout);
        }
        if (instruction.table_reference) return self.emitReference(id, instruction, switch (instruction.table_kind) {
            .unknown => .table_function,
            .callable => .callable_function,
            .demand => .demand_function,
        });
        const role: artifact.Role = switch (instruction.op) {
            .call => .function,
            .call_import => .import_,
            .call_indirect => .signature,
            .global_get, .global_set => .global,
            .host_ref_get, .host_ref_set, .host_ref_size, .host_ref_grow => .host_table,
            else => .literal,
        };
        return self.emitReference(id, instruction, role);
    }
    pub fn emitReference(self: *Module, id: u32, instruction: Instruction, role: artifact.Role) !void {
        const table_kind: ?ir.TableKind = switch (role) {
            .table_function => .unknown,
            .callable_function => .callable,
            .demand_function => .demand,
            else => null,
        };
        std.debug.assert(table_kind == null or instruction.op == .i32_const);
        try self.recordTableReference(role, instruction.operand, id, @intCast(self.functions.items[id].instructions.items.len));
        if (self.artifacts) |journal| try journal.append(.{ .instruction = .{ .function = id, .op = instruction.op, .operand = .{ .role = role, .value = instruction.operand } } });
        var owned = instruction;
        if (role == .callable_layout) {
            std.debug.assert(instruction.op == .ownership and instruction.operand != 0 and instruction.operand < 1 << 26);
            owned = ir.callableCodeRead(instruction.operand);
        }
        owned.table_reference = table_kind != null;
        owned.table_kind = table_kind orelse .unknown;
        try self.functions.items[id].instructions.append(self.allocator, owned);
        if (instruction.op == .call_indirect) self.indirect = true;
        if (instruction.op == .ownership) self.functions.items[id].annotations += 1;
    }
    pub fn emitSlice(self: *Module, id: u32, instructions: []const Instruction) !void {
        for (instructions) |instruction| try self.emit(id, instruction);
    }
    pub fn demandResource(self: *Module, kind: artifact.ResourceKind, id: u32, hit: bool) !void {
        if (self.artifacts) |journal| try journal.append(.{ .demand = .{ .kind = kind, .id = id, .hit = hit } });
    }
    pub fn recordTableReference(self: *Module, role: artifact.Role, target: u32, function: ?u32, place: u32) !void {
        const kind: ir.TableKind = switch (role) {
            .table_function => .unknown,
            .callable_function => .callable,
            .demand_function => .demand,
            else => return,
        };
        try self.table_functions.ensureUnusedCapacity(self.allocator, 1);
        try self.table_origins.ensureUnusedCapacity(self.allocator, 1);
        self.table_functions.appendAssumeCapacity(target);
        self.table_origins.appendAssumeCapacity(.{ .target = target, .kind = kind, .function = function, .place = place });
    }
    pub fn dataReference(self: *Module, address: u32, operand: artifact.Operand) !void {
        try self.recordTableReference(operand.role, operand.value, null, address);
        if (self.artifacts) |journal| try journal.append(.{ .data_word = .{ .address = address, .operand = operand } });
    }
    pub fn setStart(self: *Module, id: u32) !void {
        if (self.artifacts) |journal| try journal.append(.{ .start = id });
        self.start = id;
    }
    fn publicArena(self: *Module) !void {
        if (!self.public_arena) {
            if (self.artifacts) |journal| try journal.append(.public_arena);
            self.public_arena = true;
        }
    }
    pub fn staticField(self: *Module, address: u32, role: ir.Role) !void {
        if (role != .scalar and role != .reference) return self.mutableStatic();
        if (address % 4 != 0 or address > self.data.items.len or self.data.items.len - address < 4) return error.InvalidGlobalReference;
        const encoded = address | @as(u32, @backingInt(role));
        for (self.static_fields.items) |previous| {
            if (previous == encoded) return;
            if ((previous & ~@as(u32, 3)) == address) return error.InvalidGlobalReference;
        }
        try self.static_fields.ensureUnusedCapacity(self.allocator, 1);
        if (self.artifacts) |journal| try journal.append(.{ .static_field = .{ .address = address, .role = role } });
        self.static_fields.appendAssumeCapacity(encoded);
    }
    pub fn finishStaticFields(self: *Module) !void {
        const arena = self.arena orelse return;
        const address = if (self.static_fields.items.len == 0) 0 else try self.dataWords(self.static_fields.items);
        for (self.static_fields.items, 0..) |encoded, index| try self.dataReference(address + @as(u32, @intCast(index * 4)), .{ .role = .static_address, .value = encoded });
        inline for (.{ .{ "root_static_map", address }, .{ "root_static_count", @as(u32, @intCast(self.static_fields.items.len)) }, .{ "root_global_count", @as(u32, @intCast(self.globals.items.len)) } }) |item| {
            const id = @field(arena, item[0]);
            if (self.artifacts) |journal| try journal.append(.{ .global_bits = .{ .id = id, .bits = .{ .role = if (std.mem.eql(u8, item[0], "root_static_map")) .static_address else .literal, .value = item[1] } } });
            self.globals.items[id].bits = item[1];
        }
    }
    pub fn mutableStatic(self: *Module) !void {
        if (self.mutable_static) return;
        if (self.artifacts) |journal| try journal.append(.mutable_static);
        self.mutable_static = true;
    }
    pub fn addGlobal(self: *Module, scalar: Scalar, bits: u32, mutable: bool) !u32 {
        if (self.globals.items.len == std.math.maxInt(u32)) return error.ModuleTooLarge;
        const id: u32 = @intCast(self.globals.items.len);
        if (self.artifacts) |journal| try journal.append(.{ .global = .{ .id = id, .scalar = scalar, .bits = .{ .value = bits }, .mutable = mutable } });
        try self.demandResource(.global, id, false);
        try self.globals.append(self.allocator, .{ .scalar = scalar, .bits = bits, .mutable = mutable });
        return id;
    }
    pub fn ensureHostReferences(self: *Module) !HostReferences {
        if (self.host_references) |references| {
            try self.demandResource(.host_references, 0, true);
            return references;
        }
        const cursor = try self.addGlobal(.u32, 0, true);
        const active = try self.addGlobal(.u32, 0, true);
        const retain = try self.addTypedFunction(&.{.externref}, .i32, .scalar);
        const slot = try self.addLocal(retain, .i32);
        for ([_]Instruction{
            .{ .op = .global_get, .operand = cursor },              .{ .op = .local_tee, .operand = slot },
            .{ .op = .host_ref_size },                              .{ .op = .i32_eq },
            .{ .op = .if_ },                                        .{ .op = .host_ref_null },
            .{ .op = .i32_const, .operand = 1 },                    .{ .op = .host_ref_grow },
            .{ .op = .i32_const, .operand = std.math.maxInt(u32) }, .{ .op = .i32_eq },
            .{ .op = .if_ },                                        .{ .op = .unreachable_ },
            .{ .op = .end },                                        .{ .op = .end },
            .{ .op = .local_get, .operand = slot },                 .{ .op = .local_get, .operand = 0 },
            .{ .op = .host_ref_set },                               .{ .op = .local_get, .operand = slot },
            .{ .op = .i32_const, .operand = 1 },                    .{ .op = .i32_add },
            .{ .op = .global_set, .operand = cursor },              .{ .op = .local_get, .operand = slot },
        }) |instruction| try self.emit(retain, instruction);
        const release = try self.addTypedFunction(&.{.i32}, .none, .scalar);
        const current = try self.addLocal(release, .i32);
        for ([_]Instruction{
            .{ .op = .local_get, .operand = 0 },       .{ .op = .global_get, .operand = cursor },
            .{ .op = .i32_gt_u },                      .{ .op = .if_ },
            .{ .op = .unreachable_ },                  .{ .op = .end },
            .{ .op = .local_get, .operand = 0 },       .{ .op = .local_set, .operand = current },
            .{ .op = .block },                         .{ .op = .loop },
            .{ .op = .local_get, .operand = current }, .{ .op = .global_get, .operand = cursor },
            .{ .op = .i32_ge_u },                      .{ .op = .br_if, .operand = 1 },
            .{ .op = .local_get, .operand = current }, .{ .op = .host_ref_null },
            .{ .op = .host_ref_set },                  .{ .op = .local_get, .operand = current },
            .{ .op = .i32_const, .operand = 1 },       .{ .op = .i32_add },
            .{ .op = .local_set, .operand = current }, .{ .op = .br },
            .{ .op = .end },                           .{ .op = .end },
            .{ .op = .local_get, .operand = 0 },       .{ .op = .global_set, .operand = cursor },
        }) |instruction| try self.emit(release, instruction);
        try self.emitSlice(release, &.{
            .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_eqz },                       .{ .op = .if_ },
            .{ .op = .i32_const },               .{ .op = .global_set, .operand = active }, .{ .op = .end },
        });
        const references: HostReferences = .{ .retain = retain, .release = release, .cursor = cursor, .active = active };
        if (self.artifacts) |journal| try journal.append(.{ .host_references = references });
        self.host_references = references;
        if (self.arena) |arena| try @import("../runtime/root_runtime.zig").hostCleanup(self, arena);
        try self.demandResource(.host_references, 0, false);
        return references;
    }
    pub fn dataObject(self: *Module, value: anytype) !u32 {
        const T = @TypeOf(value);
        const fields = comptime heap_layout.fields(T);
        var words: [fields.len]u32 = undefined;
        inline for (@typeInfo(T).@"struct".field_names, 0..) |name, i| {
            const field = @field(value, name);
            words[i] = if (@typeInfo(@TypeOf(field)) == .@"enum") @backingInt(field) else field;
        }
        return self.dataWords(&words);
    }
    pub fn dataWords(self: *Module, words: []const u32) !u32 {
        _ = try self.ensureArena();
        if (words.len > (std.math.maxInt(u32) - self.data.items.len) / 4) return error.ModuleTooLarge;
        const address: u32 = @intCast(self.data.items.len);
        try self.data.ensureUnusedCapacity(self.allocator, words.len * 4);
        for (words) |word| {
            var bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &bytes, word, .little);
            self.data.appendSliceAssumeCapacity(&bytes);
        }
        try self.finishStaticData(address);
        return address;
    }
    /// Reuse the module's single arena domain and append relocatable payloads
    /// above its existing static resources. Metadata is never copied twice.
    pub fn staticBytes(self: *Module, bytes: []const u8) !u32 {
        _ = try self.ensureArena();
        if (bytes.len % 4 != 0) return error.InvalidFunctionReference;
        if (bytes.len > std.math.maxInt(u32) - self.data.items.len) return error.ModuleTooLarge;
        const address: u32 = @intCast(self.data.items.len);
        try self.data.appendSlice(self.allocator, bytes);
        try self.finishStaticData(address);
        return address;
    }
    fn finishStaticData(self: *Module, address: u32) !void {
        if (self.artifacts) |journal| try journal.data(address, self.data.items[address..]);
        try self.demandResource(.static_data, address, false);
        const end: u32 = @intCast(self.data.items.len);
        if (self.artifacts) |journal| for ([_]u32{ self.arena.?.heap, self.arena.?.base, self.arena.?.static_end }) |id| try journal.append(.{ .global_bits = .{ .id = id, .bits = .{ .role = .static_address, .value = end } } });
        self.globals.items[self.arena.?.heap].bits = end;
        self.globals.items[self.arena.?.base].bits = end;
        self.globals.items[self.arena.?.static_end].bits = end;
    }
    /// Static data and mutable arena metadata have disjoint storage. Dynamic
    /// blocks begin above static data and 64 KiB; payload addresses stay stable.
    pub fn ensureArena(self: *Module) (Allocator.Error || error{ModuleTooLarge})!Arena {
        if (self.arena) |arena| {
            try self.demandResource(.arena, 0, true);
            return arena;
        }
        try self.data.appendNTimes(self.allocator, 0, arena_runtime.metadata_bytes);
        std.mem.writeInt(u32, self.data.items[arena_runtime.empty_list_address + heap_layout.offset(heap_layout.ListDescriptor, "immutable") ..][0..4], 1, .little);
        std.mem.writeInt(u32, self.data.items[arena_runtime.empty_scalar_list_address + heap_layout.offset(heap_layout.ListDescriptor, "immutable") ..][0..4], 1, .little);
        std.mem.writeInt(u32, self.data.items[arena_runtime.empty_scalar_list_address + heap_layout.offset(heap_layout.ListDescriptor, "scalar_elements") ..][0..4], 1, .little);
        inline for (.{ arena_runtime.empty_list_address, arena_runtime.empty_scalar_list_address }) |address|
            std.mem.writeInt(u32, self.data.items[address + heap_layout.offset(heap_layout.ListDescriptor, "leaf_limit") ..][0..4], @import("../runtime/list_runtime.zig").capacity, .little);
        for (2..17) |width| {
            const address = arena_runtime.empty_rows_address + (width - 2) * @sizeOf(heap_layout.ListDescriptor);
            std.mem.writeInt(u32, self.data.items[address + heap_layout.offset(heap_layout.ListDescriptor, "scalar_elements") ..][0..4], @intCast(width), .little);
            std.mem.writeInt(u32, self.data.items[address + heap_layout.offset(heap_layout.ListDescriptor, "immutable") ..][0..4], 1, .little);
            std.mem.writeInt(u32, self.data.items[address + heap_layout.offset(heap_layout.ListDescriptor, "leaf_limit") ..][0..4], @import("../runtime/list_runtime.zig").leafLimit(@intCast(width)), .little);
        }
        if (self.artifacts) |journal| try journal.data(0, self.data.items);
        const heap = try self.addGlobal(.u32, arena_runtime.metadata_bytes, true);
        const base = try self.addGlobal(.u32, arena_runtime.metadata_bytes, true);
        const static_end = try self.addGlobal(.u32, arena_runtime.metadata_bytes, false);
        const allocated = try self.addGlobal(.u32, 0, true);
        const rc_enabled = try self.addGlobal(.u32, 0, false);
        const rc_leases = try self.addGlobal(.u32, 0, true);
        const rc_retains = try self.addGlobal(.u32, 0, true);
        const rc_releases = try self.addGlobal(.u32, 0, true);
        const rc_destroyed = try self.addGlobal(.u32, 0, true);
        const root_enabled = try self.addGlobal(.u32, 0, false);
        const root_page = try self.addGlobal(.u32, 0, true);
        const root_top = try self.addGlobal(.u32, 0, true);
        const root_frame = try self.addGlobal(.u32, 0, true);
        const root_active = try self.addGlobal(.u32, 0, true);
        const root_external = try self.addGlobal(.u32, 0, true);
        const root_count = try self.addGlobal(.u32, 0, true);
        const root_globals = try self.addGlobal(.pointer, 0, true);
        const root_started = try self.addGlobal(.u32, 0, true);
        const root_host_cursor = try self.addGlobal(.u32, 0, true);
        const root_host_active = try self.addGlobal(.u32, 0, true);
        const root_static_map = try self.addGlobal(.pointer, 0, false);
        const root_static_count = try self.addGlobal(.u32, 0, false);
        const root_global_count = try self.addGlobal(.u32, 0, false);
        const cycle_head = try self.addGlobal(.u32, 0, true);
        const cycle_members = try self.addGlobal(.u32, 0, true);
        const cycle_work = try self.addGlobal(.u32, 0, true);
        const cycle_phase = try self.addGlobal(.u32, 0, true);
        const cycle_removed = try self.addGlobal(.u32, 0, true);
        const cycle_cadence = try self.addGlobal(.u32, 0, true);
        const cycle_passes = try self.addGlobal(.u32, 0, true);
        const cycle_vertices = try self.addGlobal(.u32, 0, true);
        const cycle_edges = try self.addGlobal(.u32, 0, true);
        const cycle_bytes = try self.addGlobal(.u32, 0, true);
        const cycle_threshold = try self.addGlobal(.u32, @import("../runtime/cycles_runtime.zig").minimum_traffic, true);
        const allocate = try self.addFunction(&.{.i32}, .i32);
        const allocate_scalar = try self.addFunction(&.{.i32}, .i32);
        const recycle = try self.addFunction(&.{.i32}, .none);
        const reset = try self.addFunction(&.{.i32}, .i32);
        const allocate_typed = try self.addFunction(&.{ .i32, .i32 }, .i32);
        const retain = try self.addFunction(&.{.i32}, .none);
        const release = try self.addTypedFunction(&.{.i32}, .none, .scalar);
        const release_lease = try self.addFunction(&.{.i32}, .none);
        const retire = try self.addFunction(&.{.i32}, .none);
        const free = try self.addFunction(&.{.i32}, .none);
        const store_word = try self.addFunction(&.{ .i32, .i32, .i32 }, .none);
        const copy_words = try self.addFunction(&.{ .i32, .i32, .i32, .i32 }, .none);
        const decrement = try self.addFunction(&.{.i32}, .none);
        const root_allocate = try self.addFunction(&.{ .i32, .i32 }, .i32);
        const root_reserve = try self.addFunction(&.{}, .i32);
        const root_pop = try self.addFunction(&.{}, .i32);
        const root_open = try self.addFunction(&.{}, .i32);
        const root_close = try self.addFunction(&.{.i32}, .none);
        const root_enter = try self.addFunction(&.{}, .none);
        const root_leave = try self.addFunction(&.{.i32}, .none);
        const root_store = try self.addFunction(&.{ .i32, .i32 }, .none);
        const root_public_allocate = try self.addFunction(&.{.i32}, .i32);
        const root_force = try self.addFunction(&.{.i32}, .none);
        const root_authority = try self.addFunction(&.{.i32}, .none);
        const root_public_reset = try self.addFunction(&.{.i32}, .i32);
        const cycle_enqueue = try self.addFunction(&.{.i32}, .none);
        const cycle_unlink = try self.addFunction(&.{.i32}, .none);
        const cycle_visit = try self.addFunction(&.{.i32}, .none);
        const cycle_collect = try self.addFunction(&.{}, .none);
        const cycle_safe = try self.addFunction(&.{.i32}, .none);
        const mark_acyclic = try self.addFunction(&.{.i32}, .none);
        const allocate_shaped = try self.addFunction(&.{ .i32, .i32 }, .i32);
        const root_allocate_shaped = try self.addFunction(&.{ .i32, .i32 }, .i32);
        const arena: Arena = .{
            .root_allocate_shaped = root_allocate_shaped,
            .allocate_shaped = allocate_shaped,
            .mark_acyclic = mark_acyclic,
            .cycle_enqueue = cycle_enqueue,
            .cycle_unlink = cycle_unlink,
            .cycle_visit = cycle_visit,
            .cycle_collect = cycle_collect,
            .cycle_safe = cycle_safe,
            .cycle_head = cycle_head,
            .cycle_members = cycle_members,
            .cycle_work = cycle_work,
            .cycle_phase = cycle_phase,
            .cycle_removed = cycle_removed,
            .cycle_cadence = cycle_cadence,
            .cycle_passes = cycle_passes,
            .cycle_vertices = cycle_vertices,
            .cycle_edges = cycle_edges,
            .cycle_bytes = cycle_bytes,
            .cycle_threshold = cycle_threshold,
            .root_force = root_force,
            .root_authority = root_authority,
            .root_public_allocate = root_public_allocate,
            .root_public_reset = root_public_reset,
            .root_started = root_started,
            .root_host_cursor = root_host_cursor,
            .root_host_active = root_host_active,
            .root_static_map = root_static_map,
            .root_static_count = root_static_count,
            .root_global_count = root_global_count,
            .root_globals = root_globals,
            .root_store = root_store,
            .root_allocate = root_allocate,
            .root_reserve = root_reserve,
            .root_pop = root_pop,
            .root_open = root_open,
            .root_close = root_close,
            .root_enter = root_enter,
            .root_leave = root_leave,
            .root_enabled = root_enabled,
            .root_page = root_page,
            .root_top = root_top,
            .root_frame = root_frame,
            .root_active = root_active,
            .root_external = root_external,
            .root_count = root_count,
            .rc_enabled = rc_enabled,
            .rc_leases = rc_leases,
            .rc_retains = rc_retains,
            .rc_releases = rc_releases,
            .rc_destroyed = rc_destroyed,
            .allocate_typed = allocate_typed,
            .retain = retain,
            .release = release,
            .release_lease = release_lease,
            .retire = retire,
            .free = free,
            .store_word = store_word,
            .copy_words = copy_words,
            .decrement = decrement,
            .heap = heap,
            .base = base,
            .static_end = static_end,
            .allocated = allocated,
            .allocate = allocate,
            .allocate_scalar = allocate_scalar,
            .recycle = recycle,
            .reset = reset,
        };
        try arena_runtime.emit(self, arena);
        if (!self.defer_cycles) try @import("../runtime/cycles_runtime.zig").emit(self, arena);
        try @import("../runtime/root_runtime.zig").emit(self, arena);
        // Journals retire temporary owners. Reset preserves allocator storage
        // and strong roots; trial deletion handles newly unreachable cycles.
        try self.emitSlice(reset, &.{
            .{ .op = .global_get, .operand = cycle_head }, .{ .op = .if_ },
            .{ .op = .i32_const, .operand = 1 },           .{ .op = .call, .operand = cycle_safe },
            .{ .op = .end },                               .{ .op = .global_get, .operand = heap },
            .{ .op = .return_ },
        });
        if (self.artifacts) |journal| try journal.recordArena(arena);
        self.arena = arena;
        try self.demandResource(.arena, 0, false);
        return arena;
    }
    /// All source bodies are roots; allocator demand follows checked direct and
    /// table references through compiler helpers. Foreign/public allocation and
    /// initialization are explicit roots too. Helpers keep stable early IDs.
    pub fn prepareCycles(self: *Module) Allocator.Error!void {
        const arena = self.arena orelse return;
        if (self.functions.items[arena.cycle_collect].instructions.items.len != 0) return;
        if (self.public_arena or self.host_references != null or self.start != null) {
            try @import("../runtime/cycles_runtime.zig").emit(self, arena);
            return;
        }
        const seen = try self.allocator.alloc(bool, self.functions.items.len);
        defer self.allocator.free(seen);
        for (seen, 0..) |*slot, id| slot.* = !self.runtimeHelper(id);
        for (self.exports.items) |item| if (!item.global) {
            seen[item.index] = true;
        };
        var changed = true;
        while (changed) {
            changed = false;
            for (self.functions.items, 0..) |function, id| {
                if (!seen[id]) continue;
                if (id == arena.allocate or id == arena.allocate_typed or id == arena.root_allocate or id == arena.root_public_allocate) {
                    try @import("../runtime/cycles_runtime.zig").emit(self, arena);
                    return;
                }
                for (function.instructions.items) |inst| {
                    if (inst.op != .call and !inst.table_reference) continue;
                    // The checked scalar allocator is a zero-child terminal;
                    // following its raw allocator would erase that proof.
                    if (inst.op == .call and inst.operand == arena.allocate_scalar) continue;
                    if (inst.operand >= seen.len or seen[inst.operand]) continue;
                    seen[inst.operand] = true;
                    changed = true;
                }
            }
        }
    }
    pub fn ensureLists(self: *Module) (Allocator.Error || error{ ModuleTooLarge, InvalidGlobalReference })!@import("../runtime/list_runtime.zig").Runtime {
        if (self.lists) |runtime| {
            try self.demandResource(.lists, 0, true);
            return runtime;
        }
        const arena = try self.ensureArena();
        const runtime = try @import("../runtime/list_runtime.zig").emit(self, arena);
        if (self.artifacts) |journal| try journal.recordLists(runtime);
        self.lists = runtime;
        try self.demandResource(.lists, 0, false);
        return runtime;
    }
    pub fn ensureListSnapshot(self: *Module) (Allocator.Error || error{ ModuleTooLarge, InvalidGlobalReference })!u32 {
        var runtime = try self.ensureLists();
        if (runtime.snapshot) |id| return id;
        const id = try @import("../runtime/list_runtime.zig").emitSnapshot(self);
        runtime.snapshot = id;
        if (self.artifacts) |journal| try journal.recordListsExtension(runtime);
        self.lists = runtime;
        return id;
    }
    pub fn ensureUncheckedListAddress(self: *Module) (Allocator.Error || error{ ModuleTooLarge, InvalidGlobalReference })!u32 {
        var runtime = try self.ensureLists();
        if (runtime.address_unchecked) |id| return id;
        const id = try @import("../runtime/list_runtime.zig").emitUncheckedAddress(self);
        runtime.address_unchecked = id;
        if (self.artifacts) |journal| try journal.recordListsExtension(runtime);
        self.lists = runtime;
        return id;
    }
    pub fn ensureUncheckedListSet(self: *Module) (Allocator.Error || error{ ModuleTooLarge, InvalidGlobalReference })!u32 {
        _ = try self.ensureUncheckedListAddress();
        var runtime = self.lists.?;
        if (runtime.set_unchecked) |id| return id;
        const id = try @import("../runtime/list_runtime.zig").emitUncheckedSet(self, runtime);
        runtime.set_unchecked = id;
        if (self.artifacts) |journal| try journal.recordListsExtension(runtime);
        self.lists = runtime;
        return id;
    }
    pub fn exportFunction(self: *Module, id: u32, name: []const u8, parameter: Scalar, result: Scalar) !void {
        return self.exportUsageFunction(id, name, parameter, result, false);
    }
    pub fn exportUsageFunction(self: *Module, id: u32, name: []const u8, parameter: Scalar, result: Scalar, once: bool) !void {
        return self.exportOwnerFunction(id, name, parameter, result, once, null, null, false);
    }
    pub fn exportOwnerFunction(self: *Module, id: u32, name: []const u8, parameter: Scalar, result: Scalar, once: bool, parameter_owner: ?OwnerBoundary, result_owner: ?OwnerBoundary, owner_adapter: bool) !void {
        if (id >= self.functions.items.len) return error.InvalidFunctionReference;
        if (parameter == .array_u32 or parameter == .array_f32 or result == .array_u32 or result == .array_f32) {
            _ = try self.ensureArena();
            try self.publicArena();
        }
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        if (self.artifacts) |journal| try journal.exportItem(@as(Export, .{ .name = owned, .index = id, .parameter = parameter, .result = result, .global = false, .once = once, .parameter_owner = parameter_owner, .result_owner = result_owner, .owner_adapter = owner_adapter }), true);
        try self.exports.append(self.allocator, .{ .name = owned, .index = id, .parameter = parameter, .result = result, .global = false, .once = once, .parameter_owner = parameter_owner, .result_owner = result_owner, .owner_adapter = owner_adapter });
        self.functions.items[id].entry = true;
    }
    pub fn resourceCount(self: *const Module) u32 {
        var count: u32 = 0;
        for (self.exports.items) |item| if (std.mem.startsWith(u8, item.name, "blot:resource_cleanup/")) {
            count += 1;
        };
        return count;
    }
    pub fn resourceTransferImports(self: *Module) !struct { reserve: u32, register: u32, release: u32, retire: u32, drain: u32 } {
        try self.publicArena();
        _ = try self.importFunction("blot:resource/1", "register", &.{ .i32, .i32, .i32, .i32, .i32 }, .none);
        return .{
            .reserve = try self.importFunction("blot:resource/1", "reserve", &.{}, .i32),
            .release = try self.importFunction("blot:resource/1", "release", &.{.i32}, .none),
            .register = try self.importFunction("blot:resource/2", "register_owned", &.{ .i32, .i32, .i32, .i32, .i32, .i32 }, .none),
            .retire = try self.importFunction("blot:resource/2", "retire", &.{.i32}, .none),
            .drain = try self.importFunction("blot:resource/2", "drain", &.{}, .none),
        };
    }
    pub fn resourceDrainImport(self: *const Module) ?u32 {
        for (self.imports.items, 0..) |item, index| {
            if (!std.mem.eql(u8, item.module, "blot:resource/2") or !std.mem.eql(u8, item.name, "drain")) continue;
            const signature = self.signatures.items[item.signature];
            if (signature.parameters.len == 0 and signature.result == .none) return @intCast(index);
        }
        return null;
    }
    pub fn resourceRetireImport(self: *const Module) ?u32 {
        for (self.imports.items, 0..) |item, index| {
            if (!std.mem.eql(u8, item.module, "blot:resource/2") or !std.mem.eql(u8, item.name, "retire")) continue;
            const signature = self.signatures.items[item.signature];
            if (std.mem.eql(ValueType, signature.parameters, &.{.i32}) and signature.result == .none) return @intCast(index);
        }
        return null;
    }
    pub fn resourceImport(self: *const Module, id: usize) bool {
        if (id >= self.imports.items.len or self.resourceCount() == 0) return false;
        const item = self.imports.items[id];
        const signature = self.signatures.items[item.signature];
        if (std.mem.eql(u8, item.module, "blot:resource/2")) {
            if (std.mem.eql(u8, item.name, "retire")) return std.mem.eql(ValueType, signature.parameters, &.{.i32}) and signature.result == .none;
            if (std.mem.eql(u8, item.name, "drain")) return signature.parameters.len == 0 and signature.result == .none;
            if (std.mem.eql(u8, item.name, "register_owned")) return std.mem.eql(ValueType, signature.parameters, &.{ .i32, .i32, .i32, .i32, .i32, .i32 }) and signature.result == .none;
            return false;
        }
        if (!std.mem.eql(u8, item.module, "blot:resource/1")) return false;
        if (std.mem.eql(u8, item.name, "reserve")) return signature.parameters.len == 0 and signature.result == .i32;
        if (std.mem.eql(u8, item.name, "release")) return std.mem.eql(ValueType, signature.parameters, &.{.i32}) and signature.result == .none;
        if (std.mem.eql(u8, item.name, "register")) return std.mem.eql(ValueType, signature.parameters, &.{ .i32, .i32, .i32, .i32, .i32 }) and signature.result == .none;
        return false;
    }
    /// The journal calls these while the invocation root owner is still live.
    /// They are hidden typed adapters, never ordinary user ABI entrypoints.
    pub fn exportResourceAdapter(self: *Module, id: u32, name: []const u8) !void {
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        const item: Export = .{ .name = owned, .index = id, .parameter = .unit, .result = .unit, .global = false };
        if (self.artifacts) |journal| try journal.exportItem(item, false);
        try self.exports.append(self.allocator, item);
    }
    pub fn exportTaskAdapter(self: *Module, id: u32, name: []const u8, runtime: bool) !void {
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        const item: Export = .{ .name = owned, .index = id, .parameter = .unit, .result = .unit, .global = false, .task_adapter = true, .task_runtime = runtime };
        if (self.artifacts) |journal| try journal.exportItem(item, false);
        try self.exports.append(self.allocator, item);
    }
    pub fn taskAdapterFunction(self: *const Module, id: usize) bool {
        for (self.exports.items) |item| if (!item.global and item.index == id and item.task_adapter) return true;
        return false;
    }
    pub fn taskCount(self: *const Module) u32 {
        var count: u32 = 0;
        for (self.exports.items) |item| if (item.task_adapter and std.mem.startsWith(u8, item.name, "blot:task_start/")) {
            count += 1;
        };
        return count;
    }
    pub fn taskImport(self: *const Module, id: usize) bool {
        if (id >= self.imports.items.len) return false;
        const item = self.imports.items[id];
        if (!std.mem.eql(u8, item.module, "blot:task/1")) return false;
        const signature = self.signatures.items[item.signature];
        const names = @import("../runtime/task_abi.zig").imports;
        inline for (names) |entry| if (std.mem.eql(u8, item.name, entry.name)) return signature.result == entry.result and std.mem.eql(ValueType, signature.parameters, entry.parameters);
        return false;
    }
    pub fn taskImportNamed(self: *const Module, name: []const u8) ?u32 {
        for (self.imports.items, 0..) |item, index| if (std.mem.eql(u8, item.module, "blot:task/1") and std.mem.eql(u8, item.name, name) and self.taskImport(index)) return @intCast(index);
        return null;
    }
    fn resourceAdapter(item: Export) bool {
        return std.mem.startsWith(u8, item.name, "blot:resource_cleanup/") or std.mem.startsWith(u8, item.name, "blot:resource_drop/");
    }
    pub fn resourceAdapterFunction(self: *const Module, id: usize) bool {
        for (self.exports.items) |item| if (!item.global and item.index == id and resourceAdapter(item) and !self.functions.items[id].entry) return true;
        return false;
    }
    /// These helpers do no user/host work and cannot set request cancellation.
    pub fn fixtureHelper(self: *const Module, id: usize) bool {
        if (self.fixture_helpers) |ids| for (ids) |helper| if (id == helper) return true;
        return false;
    }
    pub fn runtimeHelper(self: *const Module, id: usize) bool {
        for (self.exports.items) |item| if (!item.global and item.index == id and item.task_runtime) return true;
        if (self.fixtureHelper(id)) return true;
        if (self.regions) |regions| if (regions.runtime.contains(id)) return true;
        if (self.arena) |arena| inline for (Arena.function_fields) |field| {
            if (id == @field(arena, field)) return true;
        };
        if (self.lists) |lists| inline for (@typeInfo(@TypeOf(lists)).@"struct".field_names) |field| {
            if (lists.functionId(field)) |function_id| if (id == function_id) return true;
        };
        if (self.cohorts) |cohorts| {
            if (id == cohorts.begin or id == cohorts.allocate or id == cohorts.retire_members) return true;
        }
        if (self.host_references) |references| {
            if (id == references.retain or id == references.release) return true;
        }
        return false;
    }
    /// Exact generated host ABI: the adapter copies Array arguments/replies.
    /// Other imports keep whole-module tracing admission closed.
    pub fn hostCallbackImport(self: *const Module, id: usize) ?Callback {
        if (id >= self.imports.items.len) return null;
        const item = self.imports.items[id];
        const data = std.mem.eql(u8, item.module, "blot:cleanup_data/1") or std.mem.eql(u8, item.module, "blot:cleanup_data/2");
        if (data) {
            const owned_data = std.mem.eql(u8, item.module, "blot:cleanup_data/2");
            if (item.signature >= self.signatures.items.len) return null;
            const signature = self.signatures.items[item.signature];
            var handle: ValueType = .externref;
            if (owned_data) handle = .i32;
            if (!std.mem.eql(u8, item.name, "call_data_unit") or signature.result != .i32 or !std.mem.eql(ValueType, signature.parameters, &.{ handle, .i32, .i32 })) return null;
            return .{ .parameter = .u32, .result = .unit, .cleanup = true, .owned = owned_data, .data = true };
        }
        const owned = std.mem.eql(u8, item.module, "blot:cleanup/2");
        const cleanup = owned or std.mem.eql(u8, item.module, "blot:cleanup/1");
        if ((!cleanup and !std.mem.eql(u8, item.module, "blot:host/1")) or item.signature >= self.signatures.items.len) return null;
        const signature = self.signatures.items[item.signature];
        var handle: ValueType = .externref;
        if (owned) handle = .i32;
        inline for (.{ Scalar.unit, Scalar.u32, Scalar.bool, Scalar.f32, Scalar.array_u32, Scalar.array_f32 }) |parameter| {
            inline for (.{ Scalar.unit, Scalar.u32, Scalar.bool, Scalar.f32, Scalar.array_u32, Scalar.array_f32 }) |result| {
                const name = comptime std.fmt.comptimePrint("call_{s}_{s}", .{ callbackName(parameter).?, callbackName(result).? });
                if ((!cleanup or result == .unit) and std.mem.eql(u8, item.name, name) and signature.result == result.machine() and std.mem.eql(ValueType, signature.parameters, &.{ handle, parameter.machine() })) return .{ .parameter = parameter, .result = result, .cleanup = cleanup, .owned = owned };
            }
        }
        return null;
    }
    pub fn setCleanupDataMetadata(self: *Module, bytes: []const u8) !void {
        if (self.cleanup_data.len != 0) return error.InvalidFunctionReference;
        const owned = try self.allocator.dupe(u8, bytes);
        errdefer self.allocator.free(owned);
        if (self.artifacts) |journal| try journal.cleanupData(bytes);
        self.allocator.free(self.cleanup_data);
        self.cleanup_data = owned;
    }
    pub fn importHostCallback(self: *Module, callback: Callback) !u32 {
        if (callback.data) {
            if (!callback.cleanup or callback.parameter != .u32 or callback.result != .unit or callback.schema == 0) return error.InvalidFunctionReference;
            var namespace: []const u8 = "blot:cleanup_data/1";
            var handle: ValueType = .externref;
            if (callback.owned) {
                namespace = "blot:cleanup_data/2";
                handle = .i32;
            }
            return self.importFunction(namespace, "call_data_unit", &.{ handle, .i32, .i32 }, .i32);
        }
        const parameter = callbackName(callback.parameter) orelse return error.InvalidFunctionReference;
        const result = callbackName(callback.result) orelse return error.InvalidFunctionReference;
        const name = try self.allocator.print("call_{s}_{s}", .{ parameter, result });
        defer self.allocator.free(name);
        var namespace: []const u8 = "blot:host/1";
        if (callback.cleanup) {
            if (callback.result != .unit) return error.InvalidFunctionReference;
            namespace = "blot:cleanup/1";
            if (callback.owned) namespace = "blot:cleanup/2";
        }
        var handle: ValueType = .externref;
        if (callback.owned) {
            if (!callback.cleanup) return error.InvalidFunctionReference;
            handle = .i32;
        }
        return self.importFunction(namespace, name, &.{ handle, callback.parameter.machine() }, callback.result.machine());
    }
    pub fn ownedCleanupBindImport(self: *const Module, id: usize) bool {
        if (id >= self.imports.items.len) return false;
        const item = self.imports.items[id];
        if (std.mem.eql(u8, item.module, "blot:cleanup_data_bind/1")) {
            if (item.signature >= self.signatures.items.len or !std.mem.eql(u8, item.name, "call_data_unit")) return false;
            const signature = self.signatures.items[item.signature];
            return signature.result == .i32 and std.mem.eql(ValueType, signature.parameters, &.{ .externref, .i32 });
        }
        if (!std.mem.eql(u8, item.module, "blot:cleanup_bind/1") or item.signature >= self.signatures.items.len) return false;
        const signature = self.signatures.items[item.signature];
        if (signature.result != .i32 or !std.mem.eql(ValueType, signature.parameters, &.{.externref})) return false;
        inline for (.{ Scalar.unit, Scalar.u32, Scalar.bool, Scalar.f32, Scalar.array_u32, Scalar.array_f32 }) |parameter| {
            if (std.mem.eql(u8, item.name, comptime std.fmt.comptimePrint("call_{s}_unit", .{callbackName(parameter).?}))) return true;
        }
        return false;
    }
    pub fn importOwnedCleanupBind(self: *Module, callback: Callback) !u32 {
        if (!callback.cleanup or !callback.owned or callback.result != .unit) return error.InvalidFunctionReference;
        if (callback.data) return self.importFunction("blot:cleanup_data_bind/1", "call_data_unit", &.{ .externref, .i32 }, .i32);
        const parameter = callbackName(callback.parameter) orelse return error.InvalidFunctionReference;
        const name = try self.allocator.print("call_{s}_unit", .{parameter});
        defer self.allocator.free(name);
        return self.importFunction("blot:cleanup_bind/1", name, &.{.externref}, .i32);
    }
    pub fn exportCallbackFunction(self: *Module, id: u32, name: []const u8, callback: Callback, result: Scalar) !void {
        return self.exportUsageCallbackFunction(id, name, callback, result, false);
    }
    pub fn exportUsageCallbackFunction(self: *Module, id: u32, name: []const u8, callback: Callback, result: Scalar, once: bool) !void {
        return self.exportOwnerCallbackFunction(id, name, callback, result, once, null);
    }
    pub fn exportOwnerCallbackFunction(self: *Module, id: u32, name: []const u8, callback: Callback, result: Scalar, once: bool, result_owner: ?OwnerBoundary) !void {
        if (id >= self.functions.items.len) return error.InvalidFunctionReference;
        if (callbackName(callback.parameter) == null or callbackName(callback.result) == null or callbackName(result) == null) return error.InvalidFunctionReference;
        if (callback.data or isArray(callback.parameter) or isArray(callback.result) or isArray(result)) {
            _ = try self.ensureArena();
            try self.publicArena();
        }
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        if (self.artifacts) |journal| try journal.exportItem(@as(Export, .{ .name = owned, .index = id, .parameter = .unit, .result = result, .global = false, .callback = callback, .once = once, .result_owner = result_owner }), true);
        try self.exports.append(self.allocator, .{ .name = owned, .index = id, .parameter = .unit, .result = result, .global = false, .callback = callback, .once = once, .result_owner = result_owner });
        self.functions.items[id].entry = true;
    }
    pub fn exportConstant(self: *Module, name: []const u8, scalar: Scalar, bits: u32) !void {
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        try self.globals.ensureUnusedCapacity(self.allocator, 1);
        try self.exports.ensureUnusedCapacity(self.allocator, 1);
        const id: u32 = @intCast(self.globals.items.len);
        if (self.artifacts) |journal| {
            try journal.append(.{ .global = .{ .id = id, .scalar = scalar, .bits = .{ .role = if (scalar == .pointer or scalar == .array_u32 or scalar == .array_f32) .static_address else .literal, .value = bits }, .mutable = false } });
            try journal.exportItem(@as(Export, .{ .name = owned, .index = id, .parameter = Scalar.unit, .result = scalar, .global = true, .callback = @as(?Callback, null) }), false);
        }
        self.globals.appendAssumeCapacity(.{ .scalar = scalar, .bits = bits });
        self.exports.appendAssumeCapacity(.{ .name = owned, .index = id, .parameter = .unit, .result = scalar, .global = true });
    }
    pub fn exportGlobal(self: *Module, id: u32, name: []const u8) !void {
        if (id >= self.globals.items.len) return error.InvalidGlobalReference;
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        if (self.artifacts) |journal| try journal.exportItem(@as(Export, .{ .name = owned, .index = id, .parameter = .unit, .result = self.globals.items[id].scalar, .global = true }), false);
        try self.exports.append(self.allocator, .{ .name = owned, .index = id, .parameter = .unit, .result = self.globals.items[id].scalar, .global = true });
    }
    pub fn assemble(self: *const Module) ![]u8 {
        return self.assembleWithOptions(.{});
    }
    pub fn assembleWithOptions(self: *const Module, options: AssemblyOptions) ![]u8 {
        return self.assemblePrepared(options, true, false);
    }
    /// Production source emission requires complete, immutable ownership.
    /// The checked instantiation has no reachable legacy scanner generator.
    pub fn assembleCheckedWithOptions(self: *const Module, options: AssemblyOptions) ![]u8 {
        if (self.fixture_helpers != null) return error.InvalidFunctionReference;
        return self.assemblePrepared(options, true, true);
    }
    fn hasOwningFieldLayouts(self: *const Module) bool {
        const arena = self.arena orelse return false;
        // SROA accepts at most sixteen words. Scan source and helper bodies:
        // inlining can expose their allocations in another function.
        for (self.functions.items) |function| for (function.instructions.items, 0..) |inst, at| {
            if (inst.op != .call or inst.operand != arena.allocate) continue;
            const roles = ir.allocationAnnotations(function.instructions.items, at);
            for (0..16) |word| if (ir.Ownership.wordRole(roles, word) == .reference) return true;
        };
        return false;
    }
    /// Whether `function`'s final body leaves an allocation uncounted.
    fn rcUnproven(self: *const Module, function: *const Function, body: ?ir.Body, passes: *@import("runtime_pipeline.zig").Session) !bool {
        var view = function.*;
        if (body) |final| {
            view.locals = final.locals;
            view.instructions = final.instructions;
        }
        var proof = try @import("wasm_lifetimes.zig").rcPlan(self.allocator, self, &view, &passes.summaries, null);
        defer proof.deinit(self.allocator);
        return !proof.admitted or proof.allocations.items.len != 0;
    }
    fn assemblePrepared(self: *const Module, options: AssemblyOptions, journals: bool, comptime checked: bool) ![]u8 {
        if (options.import_function_table != null and self.host_references != null) return error.InvalidFunctionReference;
        for (self.functions.items) |function| if (!function.validProviderParameter()) return error.InvalidFunctionReference;
        if (options.stats) |stats| stats.tier = options.tier;
        if (options.current) |current| current.tier = options.tier;
        var passes = try @import("runtime_pipeline.zig").Session.init(self.allocator, self);
        defer passes.deinit();
        passes.tier = options.tier;
        if (!journals or options.import_function_table != null or options.export_function_table) passes.roots = false;
        var root_slots: u32 = 0;
        if (passes.roots) {
            const limit = std.math.maxInt(u32) / 4;
            if (self.globals.items.len > limit or self.static_fields.items.len > limit - self.globals.items.len) return error.ModuleTooLarge;
            root_slots = @intCast(self.globals.items.len + self.static_fields.items.len);
        }
        if (options.current) |current| {
            current.roots = passes.roots;
            current.needs_roots = passes.roots and passes.needs_roots;
            current.root_slots = root_slots;
            if (passes.roots) try current.providers.appendSlice(current.allocator, passes.providers.entries.items);
        }
        if (options.stats) |stats| stats.role_conflicts = passes.summaries.role_conflicts;
        if (options.current) |current| try current.recordInputs(self, &passes.summaries);
        var matcher: ?@import("optimized_bodies.zig").Matcher = if (options.previous != null and options.current != null) try .init(self.allocator, options.previous.?, options.current.?) else null;
        defer if (matcher) |*matches| matches.deinit();
        if (options.stats) |stats| if (matcher) |matches| {
            stats.match_candidates = matches.candidates;
            stats.match_work = matches.work;
            stats.match_budget_exhausted = matches.budget_exhausted;
        };
        var ownership_fallback: OwnershipFallback = .none;
        var unproven_function: ?u32 = null;
        if (self.arena == null) ownership_fallback = .no_arena else if (self.public_arena and !passes.roots) ownership_fallback = .public_arena else if (self.host_references != null and !passes.roots) ownership_fallback = .host_references else if (self.imports.items.len != 0 and !passes.roots) ownership_fallback = .imports else if (self.start != null and !passes.roots) ownership_fallback = .initializer;
        if (ownership_fallback == .none and (self.mutable_static or (self.static_fields.items.len != 0 and !passes.roots))) ownership_fallback = .static_sequence_cache;
        var parallel = try @import("runtime_parallel.zig").Batch.run(self.allocator, options.io, &passes, if (matcher) |*matches| matches else null, options.workers, ownership_fallback == .none);
        defer if (parallel) |*batch| batch.deinit();
        if (options.stats) |stats| if (parallel) |batch| {
            stats.workers = batch.workers;
            stats.parallel_jobs = batch.jobs;
        };
        const Prepared = struct { body: ?ir.Body = null, borrowed: bool = false };
        const bodies = try self.allocator.alloc(Prepared, self.functions.items.len);
        defer self.allocator.free(bodies);
        @memset(bodies, .{});
        defer for (bodies) |*prepared| if (!prepared.borrowed) {
            if (prepared.body) |*body| body.deinit(self.allocator);
        };
        for (self.functions.items, 0..) |*function, id| {
            if (options.stats) |stats| stats.functions += 1;
            const reused = if (matcher) |*matches| matches.matches(id) else false;
            bodies[id] = .{ .body = if (reused) matcher.?.output(id) else if (parallel) |*batch| batch.take(id) else try passes.optimize(function), .borrowed = reused };
            if (options.current) |current| try current.recordOutput(id, bodies[id].body);
            if (options.stats) |stats| {
                if (reused) stats.reused += 1 else stats.optimized += 1;
            }
            if (ownership_fallback == .none and !passes.runtimeHelper(function)) {
                const unproven = if (parallel) |*batch| batch.unproven(id) else null;
                if (unproven orelse try self.rcUnproven(function, bodies[id].body, &passes)) {
                    ownership_fallback = .unproven_body;
                    unproven_function = @intCast(id);
                }
            }
        }
        const rc_admitted = ownership_fallback == .none;
        if (checked and self.arena != null and (!rc_admitted or !passes.roots)) {
            if (options.rejection) |rejection| rejection.* = .{ .fallback = ownership_fallback, .function = unproven_function };
            return error.IncompleteOwnership;
        }
        // Virtual reference fields rely on enabled journals. A late module
        // failure must rebuild ordinary bodies before disabling those journals.
        if (passes.roots and !rc_admitted and self.hasOwningFieldLayouts()) {
            if (options.current) |current| {
                current.deinit();
            }
            if (options.stats) |stats| stats.* = .{};
            return self.assemblePrepared(options, false, checked);
        }
        const roots_admitted = rc_admitted and passes.roots;
        const resources = self.resourceCount();
        if (resources != 0 and !roots_admitted) return error.InvalidFunctionReference;
        const root_mode = blk: {
            const arena = self.arena orelse break :blk 0;
            if (roots_admitted) break :blk @import("../runtime/root_runtime.zig").enabled | @import("../runtime/root_runtime.zig").complete;
            break :blk self.globals.items[arena.root_enabled].bits & ~@import("../runtime/root_runtime.zig").complete;
        };
        const flags: @import("runtime_flags.zig").Facts = .{ .module = self, .root_mode = root_mode, .rc_admitted = rc_admitted };
        var code = try @import("machine_code_sharing.zig").Index.initPrepared(self.allocator, self, bodies, options.share_machine_code);
        defer code.deinit();
        if (options.stats) |stats| stats.shared = self.functions.items.len - code.unique;
        if (checked and self.arena != null and !flags.complete()) return error.IncompleteOwnership;
        var output = Bytes.init(self.allocator);
        defer output.deinit();
        try output.raw(&.{ 0, 97, 115, 109, 1, 0, 0, 0 });
        var payload = Bytes.init(self.allocator);
        defer payload.deinit();

        try payload.uleb(@intCast(self.signatures.items.len));
        for (self.signatures.items) |function| {
            try payload.byte(0x60);
            try payload.uleb(@intCast(function.parameters.len));
            for (function.parameters) |ty| try payload.byte(@backingInt(ty));
            try payload.byte(if (function.result == .none) 0 else 1);
            if (function.result != .none) try payload.byte(@backingInt(function.result));
        }
        if (self.signatures.items.len != 0) try output.section(1, payload.items());
        payload.clear();
        if (self.functions.items.len > std.math.maxInt(u32) - self.imports.items.len) return error.ModuleTooLarge;
        const import_count: u32 = @intCast(self.imports.items.len);
        if (import_count != 0 or options.import_function_table != null) {
            try payload.uleb(import_count + @as(u32, @intFromBool(options.import_function_table != null)));
            for (self.imports.items) |item| {
                try payload.name(item.module);
                try payload.name(item.name);
                try payload.byte(0);
                try payload.uleb(item.signature);
            }
            if (options.import_function_table) |minimum| {
                try payload.name("blot:patch");
                try payload.name("table");
                try payload.byte(1); // table import, not a function index
                try payload.byte(0x70);
                try payload.byte(0);
                try payload.uleb(minimum);
            }
            try output.section(2, payload.items());
            payload.clear();
        }
        try payload.uleb(@intCast(code.unique));
        for (self.functions.items, 0..) |function, id| if (code.emits(id)) {
            try payload.uleb(function.signature);
        };
        if (self.functions.items.len != 0) try output.section(3, payload.items());
        payload.clear();
        if (options.import_function_table == null and (self.indirect or self.host_references != null or options.export_function_table)) {
            try payload.uleb(if (self.host_references != null) 2 else 1);
            try payload.byte(0x70); // funcref
            try payload.byte(0); // minimum only
            try payload.uleb(if (self.indirect or options.export_function_table) @intCast(self.functions.items.len) else 0);
            if (self.host_references != null) {
                try payload.byte(0x6f); // externref, separate from callable handles
                try payload.byte(0); // minimum only
                try payload.uleb(0);
            }
            try output.section(4, payload.items());
            payload.clear();
        }
        if (self.arena != null) {
            try payload.uleb(1);
            try payload.byte(1); // bounded Wasm32 memory
            const pages: u32 = @intCast(@max(1, (self.data.items.len + 65535) / 65536));
            try payload.uleb(pages);
            try payload.uleb(65536);
            try output.section(5, payload.items());
            payload.clear();
        }
        if (self.globals.items.len != 0) {
            try payload.uleb(@intCast(self.globals.items.len));
            for (self.globals.items, 0..) |global, id| {
                try payload.byte(@backingInt(global.scalar.machine()));
                try payload.byte(@intFromBool(global.mutable));
                var bits = global.bits;
                if (self.arena) |arena| {
                    if (id == arena.rc_enabled) bits = @intFromBool(rc_admitted);
                    if (id == arena.root_enabled) bits = root_mode;
                }
                try encodeInstruction(&payload, .{ .op = if (global.scalar == .f32) .f32_const else .i32_const, .operand = bits }, self.functions.items.len, self.functions.items.len, self.globals.items.len, self.signatures.items.len, import_count);
                try payload.byte(0x0b);
            }
            try output.section(6, payload.items());
            payload.clear();
        }
        try payload.uleb(@intCast(self.exports.items.len + @as(usize, if (self.public_arena) 2 else 0) + @intFromBool(self.public_arena or options.export_memory or self.taskImportNamed("open") != null) + @intFromBool(options.export_function_table) + @as(usize, if (self.arena != null) 8 else 0) + @as(usize, if (roots_admitted) 3 else 0) + @intFromBool(roots_admitted and self.host_references != null)));
        for (self.exports.items) |item| {
            try payload.name(item.name);
            try payload.byte(if (item.global) 3 else 0);
            if (!item.global and item.index >= self.functions.items.len) return error.InvalidFunctionReference;
            try payload.uleb(if (item.global) item.index else code.function(item.index) + import_count);
        }
        if (self.public_arena or options.export_memory or self.taskImportNamed("open") != null) {
            try payload.name("blot:memory");
            try payload.byte(2);
            try payload.uleb(0);
        }
        if (self.public_arena) {
            try payload.name("blot:allocate");
            try payload.byte(0);
            try payload.uleb(code.function(if (roots_admitted) self.arena.?.root_public_allocate else self.arena.?.allocate) + import_count);
            try payload.name("blot:reset");
            try payload.byte(0);
            try payload.uleb(code.function(if (roots_admitted) self.arena.?.root_public_reset else self.arena.?.reset) + import_count);
        }
        if (roots_admitted) if (self.host_references) |references| {
            try payload.name("blot:rc_host_refs");
            try payload.byte(3);
            try payload.uleb(references.cursor);
        };
        if (self.arena) |arena| inline for (.{ "rc_leases", "rc_retains", "rc_releases", "rc_destroyed" }) |field| {
            try payload.name("blot:" ++ field);
            try payload.byte(3);
            try payload.uleb(@field(arena, field));
        };
        if (self.arena) |arena| inline for (.{ "cycle_passes", "cycle_vertices", "cycle_edges", "cycle_bytes" }) |field| {
            try payload.name("blot:" ++ field);
            try payload.byte(3);
            try payload.uleb(@field(arena, field));
        };
        if (roots_admitted) {
            inline for (.{ .{ "blot:ownership_enter", "root_enter" }, .{ "blot:ownership_leave", "root_leave" } }) |item| {
                try payload.name(item[0]);
                try payload.byte(0);
                try payload.uleb(code.function(@field(self.arena.?, item[1])) + import_count);
            }
            try payload.name("blot:rc_roots");
            try payload.byte(3);
            try payload.uleb(self.arena.?.root_count);
        }
        if (options.export_function_table) {
            try payload.name("blot:patch:table");
            try payload.byte(1);
            try payload.uleb(0);
        }
        try output.section(7, payload.items());
        payload.clear();
        if (self.start) |start| {
            if (start >= self.functions.items.len or self.functions.items[start].parameters.len != 0 or self.functions.items[start].result != .none) return error.InvalidFunctionReference;
            try payload.uleb(code.function(start) + import_count);
            try output.section(8, payload.items());
            payload.clear();
        }
        if (self.indirect and options.import_function_table == null) {
            try payload.uleb(1);
            try payload.byte(0); // active segment at table zero
            try payload.raw(&.{ 0x41, 0, 0x0b });
            try payload.uleb(@intCast(self.functions.items.len));
            for (0..self.functions.items.len) |id| try payload.uleb(code.function(@intCast(id)) + import_count);
            try output.section(9, payload.items());
            payload.clear();
        }
        if (self.functions.items.len != 0) {
            try payload.uleb(@intCast(code.unique));
            var body = Bytes.init(self.allocator);
            defer body.deinit();
            for (self.functions.items, 0..) |function, id| {
                if (!code.emits(id)) continue;
                body.clear();
                const optimized = bodies[id].body;
                const locals = if (optimized) |owned| owned.locals.items else function.locals.items;
                var instructions: []const Instruction = function.instructions.items;
                if (optimized) |owned| instructions = owned.instructions.items;
                var lowered: @import("runtime_flags.zig").Iterator = .{ .facts = flags, .instructions = instructions };
                try body.uleb(@intCast(locals.len));
                for (locals) |local| {
                    try body.byte(1);
                    try body.byte(@backingInt(local));
                }
                while (lowered.next()) |instruction| {
                    var encoded = instruction;
                    if (encoded.op == .call) {
                        if (encoded.operand >= self.functions.items.len) return error.InvalidFunctionReference;
                        encoded.operand = code.function(encoded.operand);
                    }
                    try encodeInstruction(&body, encoded, code.unique, self.functions.items.len, self.globals.items.len, self.signatures.items.len, import_count);
                }
                try body.byte(0x0b);
                try payload.uleb(@intCast(body.items().len));
                try payload.raw(body.items());
            }
            try output.section(10, payload.items());
            payload.clear();
            if (options.current) |current| try current.sealQueries();
            if (options.stats) |stats| if (options.current) |current| {
                stats.retained_bytes = current.bytes();
            };
        }
        if (self.arena != null and self.data.items.len != 0) {
            try payload.uleb(1); // one active data segment at memory zero
            try payload.byte(0);
            try payload.byte(0x41);
            try payload.byte(0);
            try payload.byte(0x0b);
            try payload.uleb(@intCast(self.data.items.len));
            try payload.raw(self.data.items);
            try output.section(11, payload.items());
            payload.clear();
        }
        try payload.name("blot:ownership");
        try payload.byte(if (roots_admitted) 2 else 1);
        try payload.byte(if (roots_admitted) 2 else @intFromBool(rc_admitted));
        try payload.byte(@backingInt(ownership_fallback));
        try output.section(0, payload.items());
        payload.clear();
        if (self.arena != null) {
            try payload.name("blot:cycles");
            try payload.byte(1);
            try payload.byte(@intFromBool(rc_admitted));
            try output.section(0, payload.items());
            payload.clear();
        }
        if (self.taskImportNamed("open") != null) {
            if (!roots_admitted) return error.InvalidFunctionReference;
            try payload.name("blot:tasks");
            // Typed start/move adapters own the capture and result contract.
            // Private representation-store IDs have no meaning in guest ABI.
            try payload.byte(2);
            try payload.uleb(self.taskCount());
            try output.section(0, payload.items());
            payload.clear();
        }
        try payload.name("blot:abi");
        var version: u8 = 2;
        if (roots_admitted) version = 3;
        if (resources != 0) version = 4;
        if (resources != 0 and self.resourceRetireImport() != null) version = 5;
        for (self.exports.items) |item| if (item.parameter_owner != null or item.result_owner != null) {
            if (!roots_admitted) return error.InvalidFunctionReference;
            version = 6;
            break;
        };
        const public_owners = version == 6;
        if (self.cleanup_data.len != 0) version = 7;
        try payload.byte(version);
        if (resources != 0 or version >= 6) try payload.uleb(resources);
        if (version >= 6) {
            var abi_flags: u8 = @intFromBool(self.resourceRetireImport() != null);
            if (version == 7 and public_owners) abi_flags |= 2;
            try payload.byte(abi_flags);
        }
        var function_count: u32 = 0;
        for (self.exports.items) |item| if (!item.global and !resourceAdapter(item) and !item.owner_adapter and !item.task_adapter) {
            function_count += 1;
        };
        try payload.uleb(function_count);
        for (self.exports.items) |item| if (!item.global and !resourceAdapter(item) and !item.owner_adapter and !item.task_adapter) {
            try payload.name(item.name);
            if (item.callback) |callback| {
                var marker: u8 = 4;
                if (callback.cleanup) marker = 7;
                if (callback.owned) marker = 10;
                if (callback.concurrent) marker = 13;
                if (callback.data) {
                    marker = 11;
                    if (callback.owned) marker = 12;
                }
                try payload.byte(marker);
                if (callback.data) {
                    if (self.cleanup_data.len == 0 or callback.schema == 0) return error.InvalidFunctionReference;
                    try payload.uleb(callback.schema);
                } else {
                    try payload.byte(@backingInt(callback.parameter));
                    try payload.byte(@backingInt(callback.result));
                }
            } else try abiValue(&payload, item.parameter, item.parameter_owner);
            try abiValue(&payload, item.result, item.result_owner);
        };
        var constant_count: u32 = 0;
        for (self.exports.items) |item| if (item.global) {
            constant_count += 1;
        };
        try payload.uleb(constant_count);
        for (self.exports.items) |item| if (item.global) {
            try payload.name(item.name);
            try payload.byte(@backingInt(item.result));
        };
        try output.section(0, payload.items());
        if (self.cleanup_data.len != 0) {
            payload.clear();
            try payload.name("blot:cleanup_data");
            try payload.raw(self.cleanup_data);
            try output.section(0, payload.items());
        }
        var once_count: u32 = 0;
        for (self.exports.items) |item| if (item.once and !item.owner_adapter) {
            once_count += 1;
        };
        if (once_count != 0) {
            payload.clear();
            try payload.name("blot:multiplicity");
            try payload.byte(1);
            try payload.uleb(once_count);
            for (self.exports.items) |item| if (item.once and !item.owner_adapter) {
                std.debug.assert(!item.global and !resourceAdapter(item) and !item.owner_adapter and !item.task_adapter);
                try payload.name(item.name);
                try payload.byte(1);
            };
            try output.section(0, payload.items());
        }
        return output.buffer.toOwnedSlice(self.allocator);
    }
};

fn abiValue(payload: *Bytes, scalar: Scalar, owner: ?OwnerBoundary) !void {
    if (owner) |boundary| {
        try payload.byte(7 + @backingInt(boundary.kind));
        try payload.uleb(boundary.schema);
        var fresh: u8 = 255;
        if (boundary.fresh) |value| fresh = @backingInt(value);
        try payload.byte(fresh);
    } else try payload.byte(@backingInt(scalar));
}

pub const Bytes = struct {
    allocator: Allocator,
    buffer: std.ArrayList(u8) = .empty,
    pub fn init(allocator: Allocator) Bytes {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Bytes) void {
        self.buffer.deinit(self.allocator);
    }
    pub fn items(self: *const Bytes) []const u8 {
        return self.buffer.items;
    }
    pub fn clear(self: *Bytes) void {
        self.buffer.clearRetainingCapacity();
    }
    pub fn byte(self: *Bytes, value: u8) !void {
        try self.buffer.append(self.allocator, value);
    }
    pub fn raw(self: *Bytes, bytes: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, bytes);
    }
    pub fn name(self: *Bytes, bytes: []const u8) !void {
        if (bytes.len > std.math.maxInt(u32)) return error.ModuleTooLarge;
        try self.uleb(@intCast(bytes.len));
        try self.raw(bytes);
    }
    pub fn uleb(self: *Bytes, value: u32) !void {
        var remaining = value;
        while (true) {
            const low: u8 = @truncate(remaining & 127);
            remaining >>= 7;
            try self.byte(low | @as(u8, if (remaining != 0) 128 else 0));
            if (remaining == 0) return;
        }
    }
    pub fn sleb(self: *Bytes, value: i32) !void {
        var remaining = value;
        while (true) {
            const low: u8 = @truncate(@as(u32, @bitCast(remaining)) & 127);
            remaining >>= 7;
            const done = (remaining == 0 and low & 64 == 0) or (remaining == -1 and low & 64 != 0);
            try self.byte(low | @as(u8, if (done) 0 else 128));
            if (done) return;
        }
    }
    pub fn section(self: *Bytes, id: u8, payload: []const u8) !void {
        try self.byte(id);
        if (payload.len > std.math.maxInt(u32)) return error.ModuleTooLarge;
        try self.uleb(@intCast(payload.len));
        try self.raw(payload);
    }
};
fn encodeInstruction(bytes: *Bytes, inst: Instruction, functions: usize, table_slots: usize, globals: usize, signatures: usize, imports: u32) !void {
    if (inst.table_reference and (inst.op != .i32_const or inst.operand >= table_slots)) return error.InvalidFunctionReference;
    // Ownership annotations are analysis facts, not code.
    if (inst.op == .ownership) return;
    if (@import("wasm_simd_ops.zig").code(inst.op)) |opcode| {
        try bytes.byte(0xfd);
        try bytes.uleb(opcode);
        switch (inst.op) {
            .v128_load, .v128_store => {
                try bytes.uleb(2);
                try bytes.uleb(inst.operand);
            },
            .i32x4_replace_lane, .i32x4_extract_lane, .f32x4_extract_lane, .f32x4_replace_lane => {
                if (inst.operand >= 4) return error.ModuleTooLarge;
                try bytes.byte(@intCast(inst.operand));
            },
            // Each 32-bit lane selector expands to its four byte lanes.
            .i8x16_shuffle => {
                if (inst.operand >= 1 << 12) return error.ModuleTooLarge;
                for (0..4) |lane| {
                    const selected: u8 = @intCast((inst.operand >> @intCast(lane * 3)) & 7);
                    for (0..4) |byte| try bytes.byte(selected * 4 + @as(u8, @intCast(byte)));
                }
            },
            else => {},
        }
        return;
    }
    const code: u8 = switch (inst.op) {
        .unreachable_ => 0x00,
        .ownership => unreachable,
        .wide_layouts, .resource_retire => return error.ModuleTooLarge,
        .nop => 0x01,
        .block => 0x02,
        .loop => 0x03,
        .if_ => 0x04,
        .else_ => 0x05,
        .end => 0x0b,
        .br => 0x0c,
        .br_if => 0x0d,
        .return_ => 0x0f,
        .call, .call_import => 0x10,
        .call_indirect => 0x11,
        .host_ref_get => 0x25,
        .host_ref_set => 0x26,
        .host_ref_size, .host_ref_grow => 0xfc,
        .host_ref_null => 0xd0,
        .host_ref_is_null => 0xd1,
        .drop => 0x1a,
        .local_get => 0x20,
        .local_set => 0x21,
        .local_tee => 0x22,
        .global_get => 0x23,
        .global_set => 0x24,
        .i32_load => 0x28,
        .f32_load => 0x2a,
        .i32_store => 0x36,
        .f32_store => 0x38,
        .memory_size => 0x3f,
        .memory_grow => 0x40,
        .memory_copy, .memory_fill => 0xfc,
        .i32_reinterpret_f32 => 0xbc,
        .f32_reinterpret_i32 => 0xbe,
        .i32_const => 0x41,
        .f32_const => 0x43,
        .i32_eqz => 0x45,
        .i32_eq => 0x46,
        .i32_ne => 0x47,
        .i32_lt_u => 0x49,
        .i32_gt_u => 0x4b,
        .i32_le_u => 0x4d,
        .i32_ge_u => 0x4f,
        .f32_eq => 0x5b,
        .f32_ne => 0x5c,
        .f32_lt => 0x5d,
        .f32_gt => 0x5e,
        .f32_le => 0x5f,
        .f32_ge => 0x60,
        .i32_add => 0x6a,
        .i32_sub => 0x6b,
        .i32_mul => 0x6c,
        .i32_div_u => 0x6e,
        .i32_rem_u => 0x70,
        .i32_and => 0x71,
        .i32_or => 0x72,
        .i32_xor => 0x73,
        .i32_shl => 0x74,
        .i32_shr_u => 0x76,
        .i32_clz => 0x67,
        .i32_ctz => 0x68,
        .f32_abs => 0x8b,
        .f32_neg => 0x8c,
        .f32_ceil => 0x8d,
        .f32_floor => 0x8e,
        .f32_trunc => 0x8f,
        .f32_sqrt => 0x91,
        .f32_add => 0x92,
        .f32_sub => 0x93,
        .f32_mul => 0x94,
        .f32_div => 0x95,
        .f32_min => 0x96,
        .f32_max => 0x97,
        .f32_convert_i32_u => 0xb3,
        .i32_trunc_sat_f32_u => 0xfc,
        .v128_load => unreachable,
        .v128_store => unreachable,
        .i32x4_splat => unreachable,
        .f32x4_splat => unreachable,
        .i32x4_replace_lane => unreachable,
        .i32x4_extract_lane => unreachable,
        .f32x4_extract_lane => unreachable,
        .f32x4_replace_lane => unreachable,
        .i32x4_add => unreachable,
        .i32x4_sub => unreachable,
        .i32x4_mul => unreachable,
        .v128_and => unreachable,
        .v128_or => unreachable,
        .v128_xor => unreachable,
        .f32x4_abs => unreachable,
        .f32x4_neg => unreachable,
        .f32x4_ceil => unreachable,
        .f32x4_floor => unreachable,
        .f32x4_trunc => unreachable,
        .f32x4_sqrt => unreachable,
        .f32x4_add => unreachable,
        .f32x4_sub => unreachable,
        .f32x4_mul => unreachable,
        .f32x4_div => unreachable,
        .f32x4_convert_i32x4_u => unreachable,
        .i32x4_trunc_sat_f32x4_u => unreachable,
        .i8x16_shuffle, .i32x4_shl, .i32x4_shr_s, .i32x4_shr_u, .i32x4_min_u, .i32x4_max_u, .f32x4_pmin, .f32x4_pmax => unreachable,
        .i32x4_eq, .i32x4_ne, .i32x4_lt_u, .i32x4_gt_u, .i32x4_le_u, .i32x4_ge_u, .f32x4_eq, .f32x4_ne, .f32x4_lt, .f32x4_gt, .f32x4_le, .f32x4_ge => unreachable,
        .v128_not, .v128_andnot, .v128_bitselect, .v128_any_true, .i32x4_all_true, .f32x4_relaxed_madd => unreachable,
    };
    try bytes.byte(code);
    switch (inst.op) {
        .block, .loop, .if_ => try bytes.byte(if (inst.operand == 0) 0x40 else @intCast(inst.operand)),
        .br, .br_if, .local_get, .local_set, .local_tee => try bytes.uleb(inst.operand),
        .call => {
            if (inst.operand >= functions) return error.InvalidFunctionReference;
            try bytes.uleb(inst.operand + imports);
        },
        .call_import => {
            if (inst.operand >= imports) return error.InvalidFunctionReference;
            try bytes.uleb(inst.operand);
        },
        .call_indirect => {
            if (inst.operand >= signatures) return error.InvalidFunctionReference;
            try bytes.uleb(inst.operand);
            try bytes.byte(0);
        },
        .global_get, .global_set => {
            if (inst.operand >= globals) return error.InvalidGlobalReference;
            try bytes.uleb(inst.operand);
        },
        .i32_const => try bytes.sleb(@bitCast(inst.operand)),
        .f32_const => {
            var raw: [4]u8 = undefined;
            std.mem.writeInt(u32, &raw, inst.operand, .little);
            try bytes.raw(&raw);
        },
        .i32_trunc_sat_f32_u => try bytes.byte(1),
        .i32_load, .f32_load, .i32_store, .f32_store => {
            try bytes.uleb(2);
            try bytes.uleb(inst.operand);
        },
        .memory_size, .memory_grow => try bytes.byte(0),
        .memory_copy => try bytes.raw(&.{ 10, 0, 0 }),
        .memory_fill => try bytes.raw(&.{ 11, 0 }),
        .host_ref_get, .host_ref_set => try bytes.uleb(1),
        .host_ref_size => try bytes.raw(&.{ 16, 1 }),
        .host_ref_grow => try bytes.raw(&.{ 15, 1 }),
        .host_ref_null => try bytes.byte(0x6f),
        else => {},
    }
}

test "signed LEB preserves unsigned scalar bits and boundaries" {
    var bytes = Bytes.init(std.testing.allocator);
    defer bytes.deinit();
    try bytes.sleb(-1);
    try std.testing.expectEqualSlices(u8, &.{0x7f}, bytes.items());
    bytes.clear();
    try bytes.sleb(64);
    try std.testing.expectEqualSlices(u8, &.{ 0xc0, 0x00 }, bytes.items());
    bytes.clear();
    try bytes.sleb(std.math.minInt(i32));
    try std.testing.expectEqualSlices(u8, &.{ 0x80, 0x80, 0x80, 0x80, 0x78 }, bytes.items());
}
test "flat symbolic scalar module owns output independently" {
    const allocator = std.testing.allocator;
    var module = Module.init(allocator);
    const id = try module.addFunction(&.{.i32}, .i32);
    try module.emit(id, .{ .op = .i32_const, .operand = 42 });
    try module.exportFunction(id, "answer", .unit, .u32);
    const bytes = try module.assemble();
    defer module.allocator.free(bytes);
    module.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109, 1, 0, 0, 0 }, bytes[0..8]);
    try std.testing.expect(std.mem.find(u8, bytes, "blot:abi") != null);
}
test "serialization folds exact immutable admission flags after deciding enabled and disabled modes" {
    const a = std.testing.allocator;
    for ([_]bool{ false, true }) |enabled| for ([_]bool{ false, true }) |mutable| {
        var module = Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        module.public_arena = true;
        module.mutable_static = !enabled;
        module.globals.items[arena.rc_enabled].mutable = mutable;
        module.globals.items[arena.root_enabled].mutable = mutable;
        // A claimed proof bit does not enable an unadmitted graph.
        module.globals.items[arena.root_enabled].bits = @import("../runtime/root_runtime.zig").complete;
        const unrelated = try module.addGlobal(.u32, 73, false);
        const id = try module.addFunction(&.{}, .i32);
        module.functions.items[id].result_role = .scalar;
        const source = [_]Instruction{
            .{ .op = .global_get, .operand = arena.rc_enabled },
            .{ .op = .global_get, .operand = arena.root_enabled },
            .{ .op = .i32_add },
            .{ .op = .global_get, .operand = unrelated },
            .{ .op = .i32_add },
        };
        try module.emitSlice(id, &source);
        try module.exportFunction(id, "flag_probe", .unit, .u32);
        const bytes = try module.assemble();
        defer a.free(bytes);
        var expected = Bytes.init(a);
        defer expected.deinit();
        for (source) |instruction| {
            var encoded = instruction;
            if (!mutable and instruction.op == .global_get and instruction.operand != unrelated) {
                var bits: u32 = @intFromBool(enabled);
                if (enabled and instruction.operand == arena.root_enabled) bits = @import("../runtime/root_runtime.zig").enabled | @import("../runtime/root_runtime.zig").complete;
                encoded = .{ .op = .i32_const, .operand = bits };
            }
            try encodeInstruction(&expected, encoded, module.functions.items.len, module.functions.items.len, module.globals.items.len, module.signatures.items.len, 0);
        }
        try std.testing.expect(std.mem.find(u8, bytes, expected.items()) != null);
        try std.testing.expectEqualSlices(Instruction, &source, module.functions.items[id].instructions.items);
    };
}
test "backend reports stale symbolic function references" {
    var module = Module.init(std.testing.allocator);
    defer module.deinit();
    const id = try module.addFunction(&.{.i32}, .i32);
    try module.emit(id, .{ .op = .call, .operand = 10 });
    try std.testing.expectError(error.InvalidFunctionReference, module.assemble());
}

fn hostReferenceOwnership(allocator: Allocator) !void {
    var module = Module.init(allocator);
    defer module.deinit();
    const references = try module.ensureHostReferences();
    const reused = try module.ensureHostReferences();
    try std.testing.expectEqual(references, reused);
    const bytes = try module.assemble();
    defer module.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109, 1, 0, 0, 0 }, bytes[0..8]);
}
test "scoped host reference storage owns every allocation" {
    try hostReferenceOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, hostReferenceOwnership, .{});
}

fn arenaOwnership(allocator: Allocator) !void {
    var module = Module.init(allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    try std.testing.expectEqual(arena, try module.ensureArena());
    _ = try module.dataWords(&.{ 0, 65552, 42 });
    try module.exportFunction(arena.allocate, "allocate", .u32, .u32);
    const bytes = try module.assemble();
    defer module.allocator.free(bytes);
    try std.testing.expect(std.mem.find(u8, bytes, "allocate") != null);
}
test "arena allocation collection and static roots release every failed compiler allocation" {
    try arenaOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, arenaOwnership, .{});
}

fn importOwnership(allocator: Allocator) !void {
    var module = Module.init(allocator);
    defer module.deinit();
    var namespace = "provider".*;
    var name = "execute".*;
    const imported = try module.importFunction(&namespace, &name, &.{ .externref, .i32 }, .i32);
    @memset(&namespace, 'x');
    @memset(&name, 'x');
    const same = try module.importFunction("provider", "execute", &.{ .externref, .i32 }, .i32);
    try std.testing.expectEqual(imported, same);
    const function = try module.addFunction(&.{ .externref, .i32 }, .i32);
    try module.emit(function, .{ .op = .local_get, .operand = 0 });
    try module.emit(function, .{ .op = .local_get, .operand = 1 });
    try module.emit(function, .{ .op = .call_import, .operand = imported });
    const bytes = try module.assemble();
    defer module.allocator.free(bytes);
    try std.testing.expect(std.mem.find(u8, bytes, "provider") != null);
}
test "imports own names and signatures through mutation and allocation failure" {
    try importOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, importOwnership, .{});
}
test "import signature conflicts and stale references are rejected" {
    var module = Module.init(std.testing.allocator);
    defer module.deinit();
    _ = try module.importFunction("provider", "execute", &.{ .externref, .i32 }, .i32);
    try std.testing.expectError(error.InvalidFunctionReference, module.importFunction("provider", "execute", &.{.i32}, .f32));
    const function = try module.addFunction(&.{.i32}, .i32);
    try module.emit(function, .{ .op = .call_import, .operand = 100 });
    try std.testing.expectError(error.InvalidFunctionReference, module.assemble());
}
