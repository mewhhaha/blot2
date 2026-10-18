//! Validated job replay into the candidate's shared resource domains.
//! No source-body inference occurs here. Unknown inputs decline in preflight.
const std = @import("std");
const capture = @import("artifact_capture.zig");
const artifacts = @import("code_artifacts.zig");
const emitter = @import("artifact_emitter.zig");
const importer = @import("artifact_import.zig");
const wasm = @import("../backend/wasm.zig");
const core = @import("../check/core.zig");
const identity = @import("../backend/runtime_identity.zig");
const Allocator = std.mem.Allocator;
const Arena = wasm.Arena;
const ListRuntime = @import("../runtime/list_runtime.zig").Runtime;
const HostReferences = wasm.HostReferences;
const absent = std.math.maxInt(u32);
const value_template = @import("source_value_template.zig");
const Error = Allocator.Error || error{ InvalidFunctionReference, InvalidGlobalReference, ModuleTooLarge, Declined };
const Address = struct { original: u32, actual: u32, len: u32, owner: u32 };
pub const Stats = struct { candidates: usize = 0, reused_named: usize = 0, reused_closures: usize = 0, fresh_named: usize = 0, fresh_closures: usize = 0, refinement_regions: usize = 0, declined: usize = 0, reused_scalar_constants: usize = 0, reused_aggregate_constants: usize = 0 };
/// An admitted aggregate constant child: the current request and the old
/// serialized root address that the retained caller's operands name.
const AggregateConstant = struct { request: artifacts.Request, root: u32 };
pub const State = struct {
    allocator: Allocator,
    old: *const capture.Capture,
    importer: importer.Importer,
    starts: []u64,
    ends: []u64,
    blocked: []bool,
    functions: []u32,
    signatures: []u32,
    /// First old emission record declaring each signature ID, or absent.
    signature_records: []u32,
    imports: []u32,
    globals: []u32,
    addresses: std.ArrayList(Address) = .empty,
    arena: ?Arena = null,
    lists: ?ListRuntime = null,
    host: ?HostReferences = null,
    enabled: bool,
    stats: Stats = .{},
    static_matches: std.AutoHashMapUnmanaged(artifacts.StaticRead, u32) = .empty,
    /// Old non-suspension serialized roots by value and layout.
    serialized_roots: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    aggregate_constants: std.AutoHashMapUnmanaged(u32, AggregateConstant) = .empty,
    /// Old aggregate root address to its current serialization, exact only.
    constant_addresses: std.ArrayList(Address) = .empty,
    /// Reused value-match buffers, bound to the live generator on first use.
    /// Heap-owned so its bound address stays fixed.
    match_scratch: ?*value_template.QueryScratch = null,

    pub fn init(a: Allocator, old: *const capture.Capture, units: []const core.Module, names: ?identity.View, cached: usize) Allocator.Error!State {
        return initWithStamps(a, old, units, names, cached, null);
    }
    pub fn initWithStamps(a: Allocator, old: *const capture.Capture, units: []const core.Module, names: ?identity.View, cached: usize, stamps: ?*artifacts.ModuleStamps) Allocator.Error!State {
        var graphs = try importer.Importer.initWithStamps(a, &old.metadata.pools.?, units, names, cached, stamps);
        errdefer graphs.deinit();
        var selection_stable = graphs.enabled and old.selectionStable(units, names, cached);
        if (graphs.code_gate) |*gate| {
            if (gate.semantic.enabled) selection_stable = true;
        }
        if (selection_stable and !(if (graphs.code_gate) |*gate| gate.semantic.enabled else false)) {
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
        var roots: std.AutoHashMapUnmanaged(u64, u32) = .empty;
        errdefer roots.deinit(a);
        for (old.metadata.pools.?.serialized) |entry| if (!entry.suspension) try roots.put(a, rootKey(entry.value, entry.ty), entry.address);
        for (old.metadata.jobs.items, 1..) |job, id| {
            var fresh = !job.reusable or switch (job.request) {
                .constant => !scalarConstant(old, job) and aggregateRoot(old, &roots, job) == null,
                .runtime_global => true,
                else => false,
            };
            for (job.inline_bodies.items) |target| if (!graphs.admitsBody(target)) {
                fresh = true;
            };
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
        var arena: ?Arena = null;
        var lists: ?ListRuntime = null;
        var host: ?HostReferences = null;
        for (old.emission.records.items) |record| switch (record.event) {
            .signature => |item| signature_count = @max(signature_count, @as(usize, item.id) + 1),
            .import_ => |item| import_count = @max(import_count, @as(usize, item.id) + 1),
            .global => |item| global_count = @max(global_count, @as(usize, item.id) + 1),
            .arena => arena = old.emission.arena,
            .lists => lists = old.emission.lists,
            .host_references => |value| host = value,
            else => {},
        };
        const functions = try slots(a, old.emission.functions.len);
        errdefer a.free(functions);
        const signatures = try slots(a, signature_count);
        errdefer a.free(signatures);
        const signature_records = try slots(a, signature_count);
        errdefer a.free(signature_records);
        for (old.emission.records.items, 0..) |record, index| switch (record.event) {
            .signature => |item| if (signature_records[item.id] == absent) {
                signature_records[item.id] = @intCast(index);
            },
            else => {},
        };
        const imports = try slots(a, import_count);
        errdefer a.free(imports);
        return .{ .allocator = a, .old = old, .importer = graphs, .starts = starts, .ends = ends, .blocked = blocked, .functions = functions, .signatures = signatures, .signature_records = signature_records, .imports = imports, .globals = try slots(a, global_count), .arena = arena, .lists = lists, .host = host, .enabled = selection_stable, .serialized_roots = roots };
    }
    pub fn deinit(self: *State) void {
        self.importer.deinit();
        self.allocator.free(self.starts);
        self.allocator.free(self.ends);
        self.allocator.free(self.blocked);
        self.allocator.free(self.functions);
        self.allocator.free(self.signatures);
        self.allocator.free(self.signature_records);
        if (self.match_scratch) |scratch| {
            scratch.deinit();
            self.allocator.destroy(scratch);
        }
        self.allocator.free(self.imports);
        self.allocator.free(self.globals);
        self.addresses.deinit(self.allocator);
        self.static_matches.deinit(self.allocator);
        self.serialized_roots.deinit(self.allocator);
        self.aggregate_constants.deinit(self.allocator);
        self.constant_addresses.deinit(self.allocator);
    }
    fn rootKey(value: u32, ty: u32) u64 {
        return (@as(u64, value) << 32) | ty;
    }
    /// A completed non-scalar, non-suspension constant whose old serialized
    /// root address is known. Demand cells keep their creation identity and
    /// always rebuild.
    fn aggregateRoot(old: *const capture.Capture, roots: *const std.AutoHashMapUnmanaged(u64, u32), job: artifacts.Job) ?u32 {
        if (job.request != .constant or job.state != .complete or job.value == null) return null;
        const result = job.value.?;
        const values = old.metadata.pools.?.evaluator.values;
        if (result.value >= values.len) return null;
        switch (values[result.value].kind) {
            .scalar, .suspension, .computation, .request_decision, .type_constructor, .resolver, .provider, .state_provider => return null,
            else => {},
        }
        return roots.get(rootKey(result.value, result.layout));
    }
    /// Observe an already completed aggregate, never demand evaluation during
    /// admission. Its complete value graph, including alias topology and
    /// nominal identities, must match the old constant before the retained
    /// caller may keep operands naming its serialized root.
    fn aggregateConstantRequest(self: *State, g: anytype, id: u32) Allocator.Error!?AggregateConstant {
        if (self.aggregate_constants.get(id)) |known| return known;
        const job = self.old.metadata.jobs.items[id - 1];
        const root = aggregateRoot(self.old, &self.serialized_roots, job) orelse return null;
        const request = job.request.constant;
        if (!self.importer.admitsBody(request.target) or request.target.unit == 0 or request.target.unit > self.importer.unit_map.len) return null;
        const unit = self.importer.unit_map[request.target.unit - 1];
        if (unit == 0 or unit > g.evaluator.units.len or request.target.binding >= g.evaluator.units[unit - 1].bindings.len) return null;
        const body = g.evaluator.units[unit - 1].body(request.target.binding) orelse return null;
        if (body.runtime) return null;
        const slot = g.evaluator.slots[g.evaluator.binding_offsets[unit - 1] + request.target.binding];
        if (slot.state != .complete) return null;
        const gate = if (self.importer.code_gate) |*owned| &owned.semantic else return null;
        if (!gate.enabled) return null;
        const inspection = try value_template.Plan.inspectRootsWithRows(self.allocator, &self.old.metadata.pools.?, gate, &.{job.value.?.value}, .source_declared);
        var plan = inspection.plan orelse return null;
        defer plan.deinit(self.allocator);
        if (!try self.matchValues(g, &plan, job.value.?.value, slot.value)) return null;
        const ty = (try self.importer.importLayout(g, request.ty)) orelse return null;
        const admitted: AggregateConstant = .{ .request = .{ .constant = .{ .target = .{ .unit = unit, .binding = request.target.binding }, .ty = ty } }, .root = root };
        try self.aggregate_constants.put(self.allocator, id, admitted);
        return admitted;
    }
    fn slots(a: Allocator, count: usize) Allocator.Error![]u32 {
        const result = try a.alloc(u32, count);
        @memset(result, absent);
        return result;
    }
    fn scalarConstant(old: *const capture.Capture, job: artifacts.Job) bool {
        if (job.request != .constant or job.state != .complete or job.value == null) return false;
        const pools = &(old.metadata.pools orelse return false);
        const result = job.value.?;
        return result.value < pools.evaluator.values.len and pools.evaluator.values[result.value].kind == .scalar and
            result.layout > 0 and result.layout <= @import("../check/types.zig").f32_type;
    }
    /// Observe an already completed scalar, never demand evaluation during
    /// admission. Exact current value/type equality protects literal operands
    /// in the retained caller; the ordinary constant job is replayed below.
    fn scalarConstantRequest(self: *State, g: anytype, job: artifacts.Job) Allocator.Error!?artifacts.Request {
        if (!scalarConstant(self.old, job)) return null;
        const request = job.request.constant;
        if (!self.importer.admitsBody(request.target) or request.target.unit == 0 or request.target.unit > self.importer.unit_map.len) return null;
        const unit = self.importer.unit_map[request.target.unit - 1];
        if (unit == 0 or unit > g.evaluator.units.len or request.target.binding >= g.evaluator.units[unit - 1].bindings.len) return null;
        const body = g.evaluator.units[unit - 1].body(request.target.binding) orelse return null;
        if (body.runtime) return null;
        const slot = g.evaluator.slots[g.evaluator.binding_offsets[unit - 1] + request.target.binding];
        if (slot.state != .complete) return null;
        const actual = g.evaluator.valueScalar(slot.value) orelse return null;
        const prior = self.old.metadata.pools.?.evaluator.values[job.value.?.value];
        if (actual.scalar != prior.scalar or actual.bits != prior.bits) return null;
        const ty = (try self.importer.importLayout(g, request.ty)) orelse return null;
        return .{ .constant = .{ .target = .{ .unit = unit, .binding = request.target.binding }, .ty = ty } };
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
        if (!self.enabled or !self.old.executable_queries_complete) return null;
        var candidates = self.old.executable_queries.candidates(@import("executable_query.zig").fragmentFingerprint(request), .oldest_first);
        while (candidates.next()) |position| {
            const record = self.old.executable_queries.records.items[position];
            const same_origin = switch (request) {
                .named => |key| switch (record.key.request) {
                    .named => |old| old.target.binding == key.target.binding and self.sameUnit(old.target.unit, key.target.unit),
                    else => false,
                },
                .closure => |key| switch (record.key.request) {
                    .closure => |old| old.catalog == key.catalog and self.sameUnit(old.unit, key.unit),
                    else => false,
                },
                else => false,
            };
            if (!same_origin) continue;
            const job = record.value.job;
            if (job == 0 or self.blocked[job - 1]) continue;
            if (!try self.importer.matches(g, record.key.request, request)) continue;
            var dependencies_match = true;
            for (record.dependencies.inline_bodies) |target| if (!self.importer.admitsBody(target)) {
                dependencies_match = false;
                break;
            };
            if (!dependencies_match) continue;
            for (record.dependencies.static_reads) |read| if (!try self.matchStatic(g, read)) {
                dependencies_match = false;
                break;
            };
            if (!dependencies_match) continue;
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
        if (address < @import("../runtime/arena_runtime.zig").metadata_bytes) return self.arena != null;
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
    fn admitOperand(self: *State, g: anytype, operand: emitter.Operand, owner: u32, roots: []const u32) Allocator.Error!bool {
        return switch (operand.role) {
            .literal, .signature, .import_, .host_table => true,
            .callable_layout => blk: {
                const ty = (try self.importer.importCallableLayout(g, operand.value, null)) orelse break :blk false;
                break :blk g.representations.store.node(ty).tag == .function;
            },
            // A retained caller may also name the exact serialized root of an
            // admitted aggregate constant child; interior addresses decline.
            .static_address => self.localAddress(operand.value, owner) or std.mem.findScalar(u32, roots, operand.value) != null,
            .global => self.knownGlobal(operand.value, g.request_owner),
            .operation => try self.importer.admitOperation(g, operand.value),
            .function, .table_function, .callable_function, .demand_function => blk: {
                if (operand.value >= self.old.emission.functions.len) break :blk false;
                const function = self.old.emission.functions[operand.value];
                if (self.staticHelper(function, owner)) break :blk true;
                if (function.owner == 0) break :blk arenaFunction(function.role) or switch (function.role) {
                    .list_address_unchecked, .list_set_unchecked, .list_snapshot, .host_retain, .host_release, .list_new, .list_address, .list_copy, .list_push, .list_set, .list_from_array, .list_to_array, .list_chunk_new, .list_edit, .list_branch, .list_own, .list_insert, .list_replace, .list_refresh, .list_rotate_left, .list_rotate_right, .list_balance, .list_concat, .list_slice, .list_join, .list_cut, .list_directory, .list_leaf_count, .list_write_leaves => true,
                    else => false,
                };
                break :blk try self.importer.importRequest(g, self.old.metadata.jobs.items[function.owner - 1].request) != null;
            },
        };
    }
    fn knownGlobal(self: *const State, id: u32, requests: ?u32) bool {
        if (self.arena) |value| inline for (Arena.global_fields) |field| {
            if (id == @field(value, field)) return true;
        };
        if (self.host) |value| if (id == value.cursor or id == value.active) return true;
        // The first recorded resource is the Requests root global, when any
        // source unit contains request loops. Every other global is explicit.
        return requests != null and id == 0 and self.old.emission.records.items.len != 0 and switch (self.old.emission.records.items[0].event) {
            .global => self.old.emission.records.items[0].owner == 0,
            else => false,
        };
    }
    fn matchStatic(self: *State, g: anytype, read: artifacts.StaticRead) Allocator.Error!bool {
        if (self.static_matches.contains(read)) return true;
        const gate = if (self.importer.code_gate) |*owned| &owned.semantic else return false;
        if (!gate.enabled or read.target.unit == 0 or read.target.unit > self.importer.unit_map.len) return false;
        const target: core.BindingRef = .{ .unit = self.importer.unit_map[read.target.unit - 1], .binding = read.target.binding };
        if (target.unit == 0) return false;
        const current = g.evaluator.richValue(target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        const inspection = try value_template.Plan.inspectRootsWithRows(self.allocator, &self.old.metadata.pools.?, gate, &.{read.value}, .source_declared);
        var plan = inspection.plan orelse return false;
        defer plan.deinit(self.allocator);
        if (!try self.matchValues(g, &plan, read.value, current)) return false;
        try self.static_matches.put(self.allocator, read, current);
        return true;
    }
    /// Matches an old value graph against a current value and records the
    /// correspondence. The scratch touches only matched entries, where a fresh
    /// map per read cleared and scanned every old and current value.
    fn matchValues(self: *State, g: anytype, plan: *const value_template.Plan, old_root: u32, current_root: u32) Allocator.Error!bool {
        const scratch = self.match_scratch orelse created: {
            const owned = try self.allocator.create(value_template.QueryScratch);
            owned.* = .{ .allocator = g.evaluator.allocator };
            self.match_scratch = owned;
            break :created owned;
        };
        const anchors = scratch.begin(plan, g) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        const same = plan.matchIntoWithScratch(g, &self.importer, old_root, current_root, anchors, scratch) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        if (!same) return false;
        return self.importer.recordValueAnchorIds(scratch.anchors.items, scratch.anchor_ids.items);
    }
    fn staticHelper(self: *const State, function: emitter.FunctionArtifact, owner: u32) bool {
        return function.role == .static_closure and owner != 0 and function.resource_owner == owner and !self.blocked[owner - 1] and self.old.metadata.jobs.items[owner - 1].hasStaticValues();
    }
    fn declaredCallableLayout(self: *const State, id: u32) ?u32 {
        if (id == 0 or id > self.old.metadata.jobs.items.len) return null;
        const request = self.old.metadata.jobs.items[id - 1].request;
        var applied: u32 = 0;
        var ty: u32 = switch (request) {
            .closure => |key| key.ty,
            .constructor => |key| key.ty,
            .operation => |key| key.ty,
            .callable => |key| blk: {
                applied = key.applied;
                break :blk key.ty;
            },
            .primitive => |key| blk: {
                applied = key.applied;
                break :blk key.ty;
            },
            .host => |key| key.ty,
            else => return null,
        };
        if (applied > artifacts.max_parameters) return null;
        const nodes = self.old.metadata.pools.?.layouts.nodes;
        while (applied != 0) : (applied -= 1) {
            if (ty == 0 or ty >= nodes.len or nodes[ty].tag != .function) return null;
            ty = nodes[ty].b;
        }
        if (ty == 0 or ty >= nodes.len or nodes[ty].tag != .function) return null;
        return ty;
    }
    fn admit(self: *State, g: anytype, id: u32) Allocator.Error!bool {
        const first = self.starts[id - 1];
        const last = self.ends[id - 1];
        if (first == std.math.maxInt(u64) or last <= first) return false;
        var roots: std.ArrayList(u32) = .empty;
        defer roots.deinit(self.allocator);
        // Admitted aggregate children are re-serialized fresh, so their own
        // subtree of jobs and records is never replayed or admitted here.
        var skipped: std.ArrayList(u32) = .empty;
        defer skipped.deinit(self.allocator);
        var m = self.metaAt(first);
        while (m < self.old.metadata.events.items.len) : (m += 1) {
            const event = self.old.metadata.events.items[m];
            if (event.sequence > last) break;
            switch (event.event) {
                .enter => |child| {
                    const child_job = self.old.metadata.jobs.items[child - 1];
                    for (child_job.static_reads.items) |read| if (!try self.matchStatic(g, read)) return false;
                    if (child_job.request == .constant and !scalarConstant(self.old, child_job)) {
                        const admitted = (try self.aggregateConstantRequest(g, child)) orelse return false;
                        try roots.append(self.allocator, admitted.root);
                        try skipped.append(self.allocator, child);
                        m = self.metaAt(self.ends[child - 1] + 1) - 1;
                        continue;
                    }
                    const request = if (child_job.request == .constant) try self.scalarConstantRequest(g, child_job) else try self.importer.importRequest(g, child_job.request);
                    if (request == null) return false;
                },
                else => {},
            }
        }
        // Skipped children's sequence ranges are disjoint and ascending (the
        // walk above resumes after each one), so one cursor follows them and
        // their records are passed over by binary search.
        var skip: usize = 0;
        var e = self.emissionAt(first);
        while (e < self.old.emission.records.items.len) : (e += 1) {
            const record = self.old.emission.records.items[e];
            if (record.sequence > last) break;
            while (skip < skipped.items.len and self.ends[skipped.items[skip] - 1] < record.sequence) skip += 1;
            if (skip < skipped.items.len and record.sequence >= self.starts[skipped.items[skip] - 1]) {
                e = self.emissionAt(self.ends[skipped.items[skip] - 1] + 1) - 1;
                continue;
            }
            switch (record.event) {
                .function => |item| if (self.old.emission.functions[item.id].role == .static_closure and !self.staticHelper(self.old.emission.functions[item.id], record.owner)) return false,
                .callable_layout => |item| {
                    // A caller's range includes nested jobs. Each endpoint
                    // belongs to its own checked request, not the outer caller.
                    const owner = record.owner;
                    if (owner == 0 or owner > self.old.metadata.jobs.items.len) return false;
                    const job = self.old.metadata.jobs.items[owner - 1];
                    if (job.function != item.function or self.declaredCallableLayout(owner) != item.layout) return false;
                    const ty = (try self.importer.importCallableLayout(g, item.layout, self.declaredCallableLayout(owner))) orelse return false;
                    if (g.representations.store.node(ty).tag != .function) return false;
                },
                .semantic_site => |site| {
                    if (site.function >= self.old.emission.functions.len) return false;
                    const function = self.old.emission.functions[site.function];
                    if (site.place >= function.instructions.len) return false;
                    const inst = self.old.emission.instructions[function.instructions.start + site.place];
                    if (inst.op != .call and inst.op != .call_indirect and inst.op != .call_import) return false;
                    if (site.kind == .allocation) {
                        const arena = self.old.emission.arena orelse return false;
                        if (inst.op != .call or !arena.isAllocation(inst.operand.value)) return false;
                    }
                    if (try self.importer.importSemanticSite(g, site) == null) return false;
                },
                .instruction => |item| if (!try self.admitOperand(g, item.operand, record.owner, roots.items)) return false,
                .data_word => |item| if (!self.localAddress(item.address, record.owner) or !try self.admitOperand(g, item.operand, record.owner, roots.items)) return false,
                .global => |item| if (!self.knownGlobal(item.id, g.request_owner)) return false,
                .global_bits => |item| if (!self.knownGlobal(item.id, g.request_owner)) return false,
                .data => |item| if (item.bytes.len % 4 != 0) return false,
                .operation_symbol => |item| if (!try self.importer.admitOperation(g, item.id)) return false,
                .demand => |item| if (item.kind == .operation and !try self.importer.admitOperation(g, item.id)) return false,
                .mutable_static, .static_field => {},
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
        const position = self.signature_records[id];
        if (position == absent) return error.InvalidFunctionReference;
        const item = switch (self.old.emission.records.items[position].event) {
            .signature => |value| value,
            else => return error.InvalidFunctionReference,
        };
        const actual = try g.module.internType(self.old.emission.parameters.items[item.parameters.start..][0..item.parameters.len], item.result);
        self.signatures[id] = actual;
        return actual;
    }
    fn ensureArena(self: *State, g: anytype) Error!void {
        const old = self.arena orelse return error.InvalidFunctionReference;
        const actual = try g.module.ensureArena();
        inline for (Arena.global_fields) |field| self.globals[@field(old, field)] = @field(actual, field);
        inline for (Arena.function_fields) |field| self.functions[@field(old, field)] = @field(actual, field);
    }
    fn ensureLists(self: *State, g: anytype) Error!void {
        const old = self.lists orelse return error.InvalidFunctionReference;
        const actual = try g.module.ensureLists();
        inline for (@typeInfo(@TypeOf(old)).@"struct".field_names) |field|
            if (old.functionId(field)) |id| {
                if (actual.functionId(field)) |actual_id| {
                    self.functions[id] = actual_id;
                } else if (@TypeOf(@field(old, field)) != ?u32) return error.InvalidFunctionReference;
            };
    }
    fn ensureHost(self: *State, g: anytype) Error!void {
        const old = self.host orelse return error.InvalidFunctionReference;
        const actual = try g.module.ensureHostReferences();
        self.globals[old.cursor] = actual.cursor;
        self.globals[old.active] = actual.active;
        self.functions[old.retain] = actual.retain;
        self.functions[old.release] = actual.release;
    }
    fn global(self: *State, g: anytype, id: u32) Error!u32 {
        if (id >= self.globals.len) return error.InvalidGlobalReference;
        if (self.globals[id] != absent) return self.globals[id];
        if (self.arena) |value| inline for (Arena.global_fields) |field| {
            if (id == @field(value, field)) try self.ensureArena(g);
        };
        if (self.host) |value| if (id == value.cursor or id == value.active) try self.ensureHost(g);
        if (self.globals[id] == absent and id == 0 and g.request_owner != null) self.globals[id] = g.request_owner.?;
        if (self.globals[id] == absent) return error.InvalidGlobalReference;
        return self.globals[id];
    }
    fn resolveAddress(self: *const State, original: u32) Error!u32 {
        if (original < @import("../runtime/arena_runtime.zig").metadata_bytes and self.arena != null) return original;
        for (self.constant_addresses.items) |item| if (original == item.original) return item.actual;
        for (self.addresses.items) |item| if (original >= item.original and original < item.original + item.len) return item.actual + original - item.original;
        return error.InvalidFunctionReference;
    }
    fn operation(self: *State, g: anytype, id: u32) Error!u32 {
        if (id == 0 or id > self.old.metadata.pools.?.operations.len) return error.InvalidFunctionReference;
        if (!try self.importer.admitOperation(g, id)) return error.InvalidFunctionReference;
        const symbol = self.old.metadata.pools.?.operations[id - 1];
        return g.planning.runtime_operations.internSymbol(symbol.key, symbol.foreign) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.ModuleTooLarge => error.ModuleTooLarge,
            else => error.InvalidFunctionReference,
        };
    }
    fn arenaFunction(role: emitter.FunctionRole) bool {
        inline for (Arena.function_fields) |field| {
            if (role == @field(emitter.FunctionRole, "arena_" ++ field)) return true;
        }
        return false;
    }
    fn ensureRuntimeFunction(self: *State, g: anytype, role: emitter.FunctionRole) Error!void {
        if (arenaFunction(role)) return self.ensureArena(g);
        switch (role) {
            .list_snapshot => {
                _ = try g.module.ensureListSnapshot();
                try self.ensureLists(g);
            },
            .list_address_unchecked => {
                _ = try g.module.ensureUncheckedListAddress();
                try self.ensureLists(g);
            },
            .list_set_unchecked => {
                _ = try g.module.ensureUncheckedListSet();
                try self.ensureLists(g);
            },
            .host_retain, .host_release => try self.ensureHost(g),
            .list_new, .list_address, .list_copy, .list_push, .list_set, .list_from_array, .list_to_array, .list_chunk_new, .list_edit, .list_branch, .list_own, .list_insert, .list_replace, .list_refresh, .list_rotate_left, .list_rotate_right, .list_balance, .list_concat, .list_slice, .list_join, .list_cut, .list_directory, .list_leaf_count, .list_write_leaves => try self.ensureLists(g),
            else => return error.InvalidFunctionReference,
        }
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
        try self.ensureRuntimeFunction(g, function_.role);
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
            .callable_layout => blk: {
                const ty = (try self.importer.importCallableLayout(g, value.value, null)) orelse return error.InvalidFunctionReference;
                if (g.representations.store.node(ty).tag != .function or ty >= 1 << 26) return error.InvalidFunctionReference;
                break :blk ty;
            },
            .function, .table_function, .callable_function, .demand_function => self.resolveFunction(g, value.value),
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
                        if (old_child.request == .constant and !scalarConstant(self.old, old_child.*)) {
                            // Serialize the current, graph-equal value in the
                            // current owner exactly as fresh compilation does,
                            // then relocate the caller's root operand.
                            const admitted = self.aggregate_constants.get(child) orelse return error.InvalidFunctionReference;
                            const actual = try g.replayConstant(admitted.request);
                            try self.constant_addresses.append(self.allocator, .{ .original = admitted.root, .actual = actual, .len = 1, .owner = child });
                            self.stats.reused_aggregate_constants += 1;
                        } else if (old_child.request == .constant) {
                            const actual_request = (try self.scalarConstantRequest(g, old_child.*)) orelse return error.InvalidFunctionReference;
                            try g.replayScalarConstant(actual_request);
                            self.stats.reused_scalar_constants += 1;
                        } else {
                            const actual_request = (try self.importer.importRequest(g, old_child.request)) orelse return error.InvalidFunctionReference;
                            const actual = try g.replayRequest(actual_request);
                            if (old_child.function) |function_id| self.functions[function_id] = actual;
                        }
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
                        const actual = try g.module.addTypedFunctionForSignature(try self.signature(g, item.signature), item.result_role);
                        self.functions[item.id] = actual;
                        try g.publishRetained(request, actual);
                    } else if (self.staticHelper(fact, record.owner)) {
                        const actual = try g.module.addTypedFunctionForSignature(try self.signature(g, item.signature), item.result_role);
                        self.functions[item.id] = actual;
                        try g.publishRetainedStatic(actual);
                    } else try self.ensureRuntimeFunction(g, fact.role);
                },
                .local => |item| if (self.old.emission.functions[item.function].owner != 0 or self.staticHelper(self.old.emission.functions[item.function], record.owner)) {
                    _ = try g.module.addLocal(try self.resolveFunction(g, item.function), item.ty);
                },
                .parameter_roles => |item| if (self.old.emission.functions[item.function].owner != 0 or self.staticHelper(self.old.emission.functions[item.function], record.owner)) {
                    try g.module.setParameterRoles(try self.resolveFunction(g, item.function), item.roles);
                },
                .provider_parameter => |item| if (self.old.emission.functions[item.function].owner != 0 or self.staticHelper(self.old.emission.functions[item.function], record.owner)) {
                    try g.module.setProviderParameter(try self.resolveFunction(g, item.function), item.index);
                },
                .callable_layout => |item| if (self.old.emission.functions[item.function].owner != 0 or self.staticHelper(self.old.emission.functions[item.function], record.owner)) {
                    const ty = (try self.importer.importCallableLayout(g, item.layout, self.declaredCallableLayout(id))) orelse return error.InvalidFunctionReference;
                    if (g.representations.store.node(ty).tag != .function) return error.InvalidFunctionReference;
                    try g.module.setCallableLayout(try self.resolveFunction(g, item.function), ty);
                },
                .semantic_site => |site| if (self.old.emission.functions[site.function].owner != 0 or self.staticHelper(self.old.emission.functions[site.function], record.owner)) {
                    var imported = (try self.importer.importSemanticSite(g, site)) orelse return error.InvalidFunctionReference;
                    imported.function = try self.resolveFunction(g, site.function);
                    if (imported.place != g.module.functions.items[imported.function].instructions.items.len) return error.InvalidFunctionReference;
                    try g.module.recordSemanticSite(imported);
                },
                .instruction => |item| if (self.old.emission.functions[item.function].owner != 0 or self.staticHelper(self.old.emission.functions[item.function], record.owner)) {
                    const target = try self.resolveFunction(g, item.function);
                    if (item.operand.role == .operation) {
                        g.planning.runtime_operations.emit(&g.module, target, try self.operation(g, item.operand.value)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference;
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
                        g.planning.runtime_operations.dataWord(&g.module, actual, try self.operation(g, item.operand.value)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference;
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
                .list_extension => |item| {
                    if (item.address != null) _ = try g.module.ensureUncheckedListAddress();
                    if (item.set != null) _ = try g.module.ensureUncheckedListSet();
                    if (item.snapshot != null) _ = try g.module.ensureListSnapshot();
                    try self.ensureLists(g);
                },
                .demand => |item| if (item.hit) switch (item.kind) {
                    .arena => try self.ensureArena(g),
                    .host_references => try self.ensureHost(g),
                    .lists => try self.ensureLists(g),
                    .operation => _ = try self.operation(g, item.id),
                    else => {},
                },
                .global_bits => |item| {
                    // Static bytes relocate the arena bounds. Wide payloads
                    // also demand their immutable bitmap reader on replay.
                    const old_arena = self.arena orelse continue;
                    const wide = @import("../runtime/shared_rc.zig").shaped_mode;
                    if (item.id != old_arena.rc_enabled or item.bits.value & wide == 0) continue;
                    try self.ensureArena(g);
                    const flag_id = g.module.arena.?.rc_enabled;
                    const bits = g.module.globals.items[flag_id].bits | wide;
                    if (g.module.artifacts) |journal| try journal.append(.{ .global_bits = .{ .id = flag_id, .bits = .{ .value = bits } } });
                    g.module.globals.items[flag_id].bits = bits;
                },
                .mutable_static => g.module.mutable_static = true,
                .static_field => |item| try g.module.staticField(try self.resolveAddress(item.address), item.role),
                .export_, .start, .public_arena, .public_owners, .cleanup_data => return error.InvalidFunctionReference,
            }
        }
        const actual = self.functions[old_function];
        if (actual == absent) return error.InvalidFunctionReference;
        const template = if (job.result_template) |old| (try self.importer.importResultTemplate(g, old)) orelse return error.InvalidFunctionReference else null;
        try g.publishRetainedResult(request, template);
        if (scope) |actor| {
            for (job.static_reads.items) |read| {
                const value = self.static_matches.get(read) orelse return error.InvalidFunctionReference;
                try actor.context.readStaticValue(.{ .unit = self.importer.unit_map[read.target.unit - 1], .binding = read.target.binding }, value);
            }
            for (job.inline_bodies.items) |target| {
                const mapped = self.importer.unit_map[target.unit - 1];
                if (mapped == 0) return error.InvalidFunctionReference;
                try actor.context.readInlineBody(.{ .unit = mapped, .binding = target.binding });
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
