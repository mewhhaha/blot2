//! Validated job replay into the candidate's shared resource domains.
//! No source-body inference occurs here. Unknown inputs decline in preflight.
const std = @import("std");
const capture = @import("artifact_capture.zig");
const artifacts = @import("code_artifacts.zig");
const emitter = @import("artifact_emitter.zig");
const importer = @import("artifact_import.zig");
const wasm = @import("wasm.zig");
const core = @import("core.zig");
const identity = @import("runtime_identity.zig");
const Allocator = std.mem.Allocator;
const absent = std.math.maxInt(u32);
const Error = Allocator.Error || error{ InvalidFunctionReference, InvalidGlobalReference, ModuleTooLarge, Declined };
const Address = struct { original: u32, actual: u32, len: u32, owner: u32 };
pub const Stats = struct { candidates: usize = 0, reused_named: usize = 0, reused_closures: usize = 0, fresh_named: usize = 0, fresh_closures: usize = 0, refinement_regions: usize = 0, declined: usize = 0 };
pub const State = struct {
    allocator: Allocator,
    old: *const capture.Capture,
    importer: importer.Importer,
    starts: []u64,
    ends: []u64,
    blocked: []bool,
    functions: []u32,
    signatures: []u32,
    imports: []u32,
    globals: []u32,
    addresses: std.ArrayList(Address) = .empty,
    arena: ?wasm.Arena = null,
    lists: ?@import("list_runtime.zig").Runtime = null,
    host: ?wasm.HostReferences = null,
    enabled: bool,
    stats: Stats = .{},

    pub fn init(a: Allocator, old: *const capture.Capture, units: []const core.Module, names: ?identity.View, cached: usize) Allocator.Error!State {
        return initWithStamps(a, old, units, names, cached, null);
    }
    pub fn initWithStamps(a: Allocator, old: *const capture.Capture, units: []const core.Module, names: ?identity.View, cached: usize, stamps: ?*artifacts.ModuleStamps) Allocator.Error!State {
        var graphs = try importer.Importer.initWithStamps(a, &old.metadata.pools.?, units, names, cached, stamps);
        errdefer graphs.deinit();
        var selection_stable = graphs.enabled and old.selectionStable(units, names, cached);
        // Selection can consume another producer's catalog, even when a code
        // job's own producer is unchanged. Require the complete imported
        // prefix to retain its exact owner-qualified Core before any hit.
        if (selection_stable) {
            for (graphs.stable[0..cached]) |stable| if (!stable) {
                selection_stable = false;
                break;
            };
        }
        const starts = try a.alloc(u64, old.metadata.jobs.items.len);
        errdefer a.free(starts);
        const ends = try a.alloc(u64, starts.len);
        errdefer a.free(ends);
        const blocked = try a.alloc(bool, starts.len);
        errdefer a.free(blocked);
        @memset(starts, std.math.maxInt(u64));
        @memset(ends, 0);
        @memset(blocked, false);
        for (old.metadata.events.items) |event| switch (event.event) {
            .enter => |id| starts[id - 1] = event.sequence,
            .leave => |item| ends[item.job - 1] = event.sequence,
            else => {},
        };
        for (old.metadata.jobs.items, 1..) |job, id| {
            var fresh = !job.reusable or switch (job.request) {
                .constant, .runtime_global => true,
                else => false,
            };
            for (job.inline_units.items) |unit| {
                if (unit == 0 or unit > graphs.stable.len or !graphs.stable[unit - 1]) fresh = true;
            }
            if (fresh) {
                var parent: u32 = @intCast(id);
                while (parent != 0) {
                    blocked[parent - 1] = true;
                    parent = old.metadata.jobs.items[parent - 1].parent;
                }
            }
        }
        var signature_count: usize = 0;
        var import_count: usize = 0;
        var global_count: usize = 0;
        var arena: ?wasm.Arena = null;
        var lists: ?@import("list_runtime.zig").Runtime = null;
        var host: ?wasm.HostReferences = null;
        for (old.emission.records.items) |record| switch (record.event) {
            .signature => |item| signature_count = @max(signature_count, @as(usize, item.id) + 1),
            .import_ => |item| import_count = @max(import_count, @as(usize, item.id) + 1),
            .global => |item| global_count = @max(global_count, @as(usize, item.id) + 1),
            .arena => |value| arena = value,
            .lists => |value| lists = value,
            .host_references => |value| host = value,
            else => {},
        };
        const functions = try slots(a, old.emission.functions.len);
        errdefer a.free(functions);
        const signatures = try slots(a, signature_count);
        errdefer a.free(signatures);
        const imports = try slots(a, import_count);
        errdefer a.free(imports);
        return .{ .allocator = a, .old = old, .importer = graphs, .starts = starts, .ends = ends, .blocked = blocked, .functions = functions, .signatures = signatures, .imports = imports, .globals = try slots(a, global_count), .arena = arena, .lists = lists, .host = host, .enabled = selection_stable };
    }
    pub fn deinit(self: *State) void {
        self.importer.deinit();
        self.allocator.free(self.starts);
        self.allocator.free(self.ends);
        self.allocator.free(self.blocked);
        self.allocator.free(self.functions);
        self.allocator.free(self.signatures);
        self.allocator.free(self.imports);
        self.allocator.free(self.globals);
        self.addresses.deinit(self.allocator);
    }
    fn slots(a: Allocator, count: usize) Allocator.Error![]u32 {
        const result = try a.alloc(u32, count);
        @memset(result, absent);
        return result;
    }
    fn metaAt(self: *const State, sequence: u64) usize {
        var left: usize = 0;
        var right = self.old.metadata.events.items.len;
        while (left < right) {
            const middle = left + (right - left) / 2;
            if (self.old.metadata.events.items[middle].sequence < sequence) left = middle + 1 else right = middle;
        }
        return left;
    }
    fn emissionAt(self: *const State, sequence: u64) usize {
        var left: usize = 0;
        var right = self.old.emission.records.items.len;
        while (left < right) {
            const middle = left + (right - left) / 2;
            if (self.old.emission.records.items[middle].sequence < sequence) left = middle + 1 else right = middle;
        }
        return left;
    }
    pub fn find(self: *State, g: anytype, request: artifacts.Request) Allocator.Error!?u32 {
        if (!self.enabled) return null;
        for (self.old.metadata.pools.?.functions) |function| {
            const same_origin = switch (request) {
                .named => |key| switch (function.request) {
                    .named => |old| old.target.binding == key.target.binding and self.sameUnit(old.target.unit, key.target.unit),
                    else => false,
                },
                .closure => |key| switch (function.request) {
                    .closure => |old| old.catalog == key.catalog and self.sameUnit(old.unit, key.unit),
                    else => false,
                },
                else => false,
            };
            if (!same_origin) continue;
            const job = self.old.emission.functions[function.function].owner;
            if (job == 0 or self.blocked[job - 1]) continue;
            if (!try self.importer.matches(g, function.request, request)) continue;
            self.stats.candidates += 1;
            if (try self.admit(g, job)) return job;
            self.stats.declined += 1;
        }
        return null;
    }
    /// Reject only a source-owner mismatch after canonical unit translation.
    /// Matching owners still require complete shape/evidence/capture import.
    fn sameUnit(self: *const State, old: u32, current: u32) bool {
        return old != 0 and old <= self.importer.unit_map.len and current != 0 and self.importer.unit_map[old - 1] == current;
    }
    fn localAddress(self: *const State, address: u32, owner: u32) bool {
        if (address < 256) return self.arena != null;
        var cursor = self.emissionAt(self.starts[owner - 1]);
        while (cursor < self.old.emission.records.items.len) : (cursor += 1) {
            const record = self.old.emission.records.items[cursor];
            if (record.sequence >= self.ends[owner - 1]) break;
            if (record.owner != owner) continue;
            switch (record.event) {
                .data => |item| if (address >= item.address and address < item.address + item.bytes.len) return true,
                else => {},
            }
        }
        return address == 0;
    }
    fn admitOperand(self: *State, g: anytype, operand: emitter.Operand, owner: u32) Allocator.Error!bool {
        return switch (operand.role) {
            .literal, .signature, .import_, .host_table => true,
            .static_address => self.localAddress(operand.value, owner),
            .global => self.knownGlobal(operand.value, g.request_owner),
            .operation => try self.importer.admitOperation(g, operand.value),
            .function, .table_function => blk: {
                if (operand.value >= self.old.emission.functions.len) break :blk false;
                const function = self.old.emission.functions[operand.value];
                if (function.owner == 0) break :blk switch (function.role) {
                    .arena_allocate, .arena_reset, .arena_mark, .arena_collect, .host_retain, .host_release, .list_new, .list_address, .list_copy, .list_push, .list_set, .list_from_array, .list_to_array, .list_chunk_new, .list_edit => true,
                    else => false,
                };
                break :blk try self.importer.importRequest(g, self.old.metadata.jobs.items[function.owner - 1].request) != null;
            },
        };
    }
    fn knownGlobal(self: *const State, id: u32, requests: ?u32) bool {
        if (self.arena) |value| if (id == value.heap or id == value.base or id == value.static_end) return true;
        if (self.host) |value| if (id == value.cursor) return true;
        // The first recorded resource is the Requests root global, when any
        // source unit contains request loops. Every other global is explicit.
        return requests != null and id == 0 and self.old.emission.records.items.len != 0 and switch (self.old.emission.records.items[0].event) {
            .global => self.old.emission.records.items[0].owner == 0,
            else => false,
        };
    }
    fn admit(self: *State, g: anytype, id: u32) Allocator.Error!bool {
        const first = self.starts[id - 1];
        const last = self.ends[id - 1];
        if (first == std.math.maxInt(u64) or last <= first) return false;
        var m = self.metaAt(first);
        while (m < self.old.metadata.events.items.len) : (m += 1) {
            const event = self.old.metadata.events.items[m];
            if (event.sequence > last) break;
            switch (event.event) {
                .enter => |child| {
                    if (try self.importer.importRequest(g, self.old.metadata.jobs.items[child - 1].request) == null) return false;
                },
                else => {},
            }
        }
        var e = self.emissionAt(first);
        while (e < self.old.emission.records.items.len) : (e += 1) {
            const record = self.old.emission.records.items[e];
            if (record.sequence > last) break;
            switch (record.event) {
                .function => |item| if (self.old.emission.functions[item.id].role == .static_closure) return false,
                .instruction => |item| if (!try self.admitOperand(g, item.operand, record.owner)) return false,
                .data_word => |item| if (!self.localAddress(item.address, record.owner) or !try self.admitOperand(g, item.operand, record.owner)) return false,
                .global => |item| if (!self.knownGlobal(item.id, g.request_owner)) return false,
                .global_bits => |item| if (!self.knownGlobal(item.id, g.request_owner)) return false,
                .data => |item| if (item.bytes.len % 4 != 0) return false,
                .operation_symbol => |item| if (!try self.importer.admitOperation(g, item.id)) return false,
                .demand => |item| if (item.kind == .operation and !try self.importer.admitOperation(g, item.id)) return false,
                .export_, .start, .public_arena => return false,
                else => {},
            }
        }
        const job = &self.old.metadata.jobs.items[id - 1];
        if (job.result_template) |template| if (try self.importer.importResultTemplate(g, template) == null) return false;
        if (job.solved) {
            var solved = (try self.importer.importSolved(g, job)) orelse return false;
            solved.deinit(self.allocator);
        }
        return true;
    }
    fn signature(self: *State, g: anytype, id: u32) Error!u32 {
        if (id >= self.signatures.len) return error.InvalidFunctionReference;
        if (self.signatures[id] != absent) return self.signatures[id];
        for (self.old.emission.records.items) |record| switch (record.event) {
            .signature => |item| if (item.id == id) {
                const actual = try g.module.internType(self.old.emission.parameters.items[item.parameters.start..][0..item.parameters.len], item.result);
                self.signatures[id] = actual;
                return actual;
            },
            else => {},
        };
        return error.InvalidFunctionReference;
    }
    fn ensureArena(self: *State, g: anytype) Error!void {
        const old = self.arena orelse return error.InvalidFunctionReference;
        const actual = try g.module.ensureArena();
        inline for (.{ "heap", "base", "static_end" }) |field| self.globals[@field(old, field)] = @field(actual, field);
        inline for (.{ "allocate", "reset", "mark", "collect" }) |field| self.functions[@field(old, field)] = @field(actual, field);
    }
    fn ensureLists(self: *State, g: anytype) Error!void {
        const old = self.lists orelse return error.InvalidFunctionReference;
        const actual = try g.module.ensureLists();
        inline for (@typeInfo(@TypeOf(old)).@"struct".field_names) |field|
            self.functions[@field(old, field)] = @field(actual, field);
    }
    fn ensureHost(self: *State, g: anytype) Error!void {
        const old = self.host orelse return error.InvalidFunctionReference;
        const actual = try g.module.ensureHostReferences();
        self.globals[old.cursor] = actual.cursor;
        self.functions[old.retain] = actual.retain;
        self.functions[old.release] = actual.release;
    }
    fn global(self: *State, g: anytype, id: u32) Error!u32 {
        if (id >= self.globals.len) return error.InvalidGlobalReference;
        if (self.globals[id] != absent) return self.globals[id];
        if (self.arena) |value| if (id == value.heap or id == value.base or id == value.static_end) try self.ensureArena(g);
        if (self.host) |value| if (id == value.cursor) try self.ensureHost(g);
        if (self.globals[id] == absent and id == 0 and g.request_owner != null) self.globals[id] = g.request_owner.?;
        if (self.globals[id] == absent) return error.InvalidGlobalReference;
        return self.globals[id];
    }
    fn resolveAddress(self: *const State, original: u32) Error!u32 {
        if (original < 256 and self.arena != null) return original;
        for (self.addresses.items) |item| if (original >= item.original and original < item.original + item.len) return item.actual + original - item.original;
        return error.InvalidFunctionReference;
    }
    fn operation(self: *State, g: anytype, id: u32) Error!u32 {
        if (id == 0 or id > self.old.metadata.pools.?.operations.len) return error.InvalidFunctionReference;
        if (!try self.importer.admitOperation(g, id)) return error.InvalidFunctionReference;
        const symbol = self.old.metadata.pools.?.operations[id - 1];
        return g.runtime_operations.internSymbol(symbol.key, symbol.foreign) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.ModuleTooLarge => error.ModuleTooLarge,
            else => error.InvalidFunctionReference,
        };
    }
    fn resolveFunction(self: *State, g: anytype, id: u32) Error!u32 {
        if (id >= self.functions.len) return error.InvalidFunctionReference;
        if (self.functions[id] != absent) return self.functions[id];
        const function_ = self.old.emission.functions[id];
        if (function_.owner != 0) {
            const request = (try self.importer.importRequest(g, self.old.metadata.jobs.items[function_.owner - 1].request)) orelse return error.InvalidFunctionReference;
            self.functions[id] = try g.replayRequest(request);
            return self.functions[id];
        }
        switch (function_.role) {
            .arena_allocate, .arena_reset, .arena_mark, .arena_collect => try self.ensureArena(g),
            .host_retain, .host_release => try self.ensureHost(g),
            .list_new, .list_address, .list_copy, .list_push, .list_set, .list_from_array, .list_to_array, .list_chunk_new, .list_edit => try self.ensureLists(g),
            else => return error.InvalidFunctionReference,
        }
        return self.functions[id];
    }
    fn importFunction(self: *State, g: anytype, id: u32) Error!u32 {
        if (id >= self.imports.len) return error.InvalidFunctionReference;
        if (self.imports[id] != absent) return self.imports[id];
        for (self.old.emission.records.items) |record| switch (record.event) {
            .import_ => |item| if (item.id == id) {
                const sig = g.module.signatures.items[try self.signature(g, item.signature)];
                self.imports[id] = try g.module.importFunction(self.old.emission.bytes.items[item.module.start..][0..item.module.len], self.old.emission.bytes.items[item.name.start..][0..item.name.len], sig.parameters, sig.result);
                return self.imports[id];
            },
            else => {},
        };
        return error.InvalidFunctionReference;
    }
    fn resolveOperand(self: *State, g: anytype, value: emitter.Operand) Error!u32 {
        return switch (value.role) {
            .literal, .host_table => value.value,
            .function, .table_function => self.resolveFunction(g, value.value),
            .signature => self.signature(g, value.value),
            .import_ => self.importFunction(g, value.value),
            .global => self.global(g, value.value),
            .static_address => self.resolveAddress(value.value),
            .operation => self.operation(g, value.value),
        };
    }
    pub fn reconstruct(self: *State, g: anytype, id: u32, request: artifacts.Request, scope: ?*artifacts.Scope) Error!u32 {
        const job = &self.old.metadata.jobs.items[id - 1];
        const old_function = job.function orelse return error.InvalidFunctionReference;
        var m = self.metaAt(self.starts[id - 1]);
        var e = self.emissionAt(self.starts[id - 1]);
        const end = self.ends[id - 1];
        while (true) {
            const next_m = if (m < self.old.metadata.events.items.len) self.old.metadata.events.items[m].sequence else std.math.maxInt(u64);
            const next_e = if (e < self.old.emission.records.items.len) self.old.emission.records.items[e].sequence else std.math.maxInt(u64);
            if (@min(next_m, next_e) > end) break;
            if (next_m < next_e) {
                const event = self.old.metadata.events.items[m].event;
                m += 1;
                switch (event) {
                    .enter => |child| if (child != id) {
                        const old_child = &self.old.metadata.jobs.items[child - 1];
                        const actual_request = (try self.importer.importRequest(g, old_child.request)) orelse return error.InvalidFunctionReference;
                        const actual = try g.replayRequest(actual_request);
                        if (old_child.function) |function_id| self.functions[function_id] = actual;
                        m = self.metaAt(self.ends[child - 1] + 1);
                        e = self.emissionAt(self.ends[child - 1] + 1);
                    },
                    .reserve => if (scope) |actor| try actor.reserve(self.functions[old_function]),
                    else => {},
                }
                continue;
            }
            const record = self.old.emission.records.items[e];
            e += 1;
            switch (record.event) {
                .signature => |item| _ = try self.signature(g, item.id),
                .function => |item| {
                    const fact = self.old.emission.functions[item.id];
                    if (fact.owner != 0) {
                        const actual = try g.module.addFunctionForSignature(try self.signature(g, item.signature));
                        self.functions[item.id] = actual;
                        try g.publishRetained(request, actual);
                    } else switch (fact.role) {
                        .arena_allocate, .arena_reset, .arena_mark, .arena_collect => try self.ensureArena(g),
                        .host_retain, .host_release => try self.ensureHost(g),
                        .list_new, .list_address, .list_copy, .list_push, .list_set, .list_from_array, .list_to_array, .list_chunk_new, .list_edit => try self.ensureLists(g),
                        else => return error.InvalidFunctionReference,
                    }
                },
                .local => |item| if (self.old.emission.functions[item.function].owner != 0) {
                    _ = try g.module.addLocal(try self.resolveFunction(g, item.function), item.ty);
                },
                .instruction => |item| if (self.old.emission.functions[item.function].owner != 0) {
                    const target = try self.resolveFunction(g, item.function);
                    if (item.operand.role == .operation) {
                        g.runtime_operations.emit(&g.module, target, try self.operation(g, item.operand.value)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference;
                    } else try g.module.emitReference(target, .{ .op = item.op, .operand = try self.resolveOperand(g, item.operand) }, item.operand.role);
                },
                .import_ => |item| _ = try self.importFunction(g, item.id),
                .operation_symbol => |item| _ = try self.operation(g, item.id),
                .data => |item| {
                    if (item.address == 0) try self.ensureArena(g) else {
                        const actual = try g.module.staticBytes(self.old.emission.bytes.items[item.bytes.start..][0..item.bytes.len]);
                        try self.addresses.append(self.allocator, .{ .original = item.address, .actual = actual, .len = item.bytes.len, .owner = record.owner });
                    }
                },
                .data_word => |item| {
                    const actual = try self.resolveAddress(item.address);
                    if (item.operand.role == .operation) {
                        std.mem.writeInt(u32, g.module.data.items[actual..][0..4], 0, .little);
                        g.runtime_operations.dataWord(&g.module, actual, try self.operation(g, item.operand.value)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference;
                    } else {
                        const relocated = try self.resolveOperand(g, item.operand);
                        std.mem.writeInt(u32, g.module.data.items[actual..][0..4], relocated, .little);
                        try g.module.dataReference(actual, .{ .role = item.operand.role, .value = relocated });
                    }
                },
                .global => |item| _ = try self.global(g, item.id),
                .arena => try self.ensureArena(g),
                .host_references => try self.ensureHost(g),
                .lists => try self.ensureLists(g),
                .demand => |item| if (item.hit) switch (item.kind) {
                    .arena => try self.ensureArena(g),
                    .host_references => try self.ensureHost(g),
                    .lists => try self.ensureLists(g),
                    .operation => _ = try self.operation(g, item.id),
                    else => {},
                },
                .global_bits => {}, // staticBytes updates the shared arena end.
                .export_, .start, .public_arena => return error.InvalidFunctionReference,
            }
        }
        const actual = self.functions[old_function];
        if (actual == absent) return error.InvalidFunctionReference;
        const template = if (job.result_template) |old| (try self.importer.importResultTemplate(g, old)) orelse return error.InvalidFunctionReference else null;
        try g.publishRetainedResult(request, template);
        if (scope) |actor| {
            for (job.inline_units.items) |unit| {
                const mapped = self.importer.unit_map[unit - 1];
                if (mapped == 0) return error.InvalidFunctionReference;
                try actor.context.readInlineBody(mapped);
            }
            if (job.solved) {
                var solved = (try self.importer.importSolved(g, job)) orelse return error.InvalidFunctionReference;
                defer solved.deinit(self.allocator);
                try actor.solved(solved.mappings, solved.rows, solved.templates);
            }
            try actor.complete(actual, template);
        }
        switch (request) {
            .named => self.stats.reused_named += 1,
            .closure => self.stats.reused_closures += 1,
            else => {},
        }
        return actual;
    }
};
