//! Session-owned immutable value handles, parallel metadata and snapshot storage.
//! Inference/receipt authority stays with the evaluator; this owner publishes no judgments.
const std = @import("std");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const type_evidence = @import("type_evidence.zig");
const implementation_evidence = @import("implementation_evidence.zig");
const collection_growth = @import("eval_collection_growth.zig");
const Allocator = std.mem.Allocator;
pub const Value = @import("../backend/scalar_ops.zig").Value;
pub const ValueId = u32;
pub const ValueKind = enum(u8) { scalar, product, record, nominal, array, list, closure, suspension, type_constructor, resolver, provider, state_provider, effect_set, effect_descriptor, computation, request_decision, cursor, proof, package, code, descriptor, staged_value, capability };
pub const DemandState = enum { pending, evaluating, cached };
pub const Demand = struct { state: DemandState = .pending, value: ValueId = 0 };
/// A creation identity within one completed source constant evaluation. This
/// record is not a ready certificate: consumers must match exact captures and
/// inspect the current demand memo after completing their body/read proof.
pub const SourceSuspension = struct { producer: core.BindingRef, unit: u32, node: core.Id, value: ValueId };
pub const ClosureOrigin = enum(u8) { named, anonymous, constructor, primitive, operation };
/// Anonymous identities index core.Module.closures; named identities are binding
/// IDs; constructor identities index its constructor catalog. Children store
/// lexical captures or already supplied arguments in their immutable order.
pub const ClosureValue = struct { staged: ValueId = 0, unit: u32, identity: u32, applied: u32 = 0, origin: ClosureOrigin, mappings: core.List = .{}, row_mappings: core.List = .{}, ty: types.Id = 0 };
/// Scalars carry exact bits; nominal bits are the constructor tag. Aggregate
/// children are immutable handles in a separate contiguous buffer. Nominal
/// identity is the producer unit/declaration pair, independent of type arguments.
pub const ValueInfo = struct {
    nominal: u64 = 0,
    start: u32 = 0,
    len: u32 = 0,
    bits: u32 = 0,
    kind: ValueKind = .scalar,
    scalar: @TypeOf(@as(Value, undefined).scalar) = .unit,
};
pub const Snapshot = struct {
    code_origins: []@import("../check/staging_origins.zig").Record = &.{},
    values: []ValueInfo,
    children: []ValueId,
    closures: []ClosureValue,
    value_evidence: []type_evidence.Id,
    type_mappings: []type_evidence.Mapping,
    row_mappings: []type_evidence.RowMapping,
    evidence: type_evidence.Snapshot,
    value_records: []u32,
    record_layouts: []core.List,
    field_names: []u32,
    demands: []Demand,
    implementation_proofs: implementation_evidence.Snapshot = .{},
    pub fn deinit(self: *Snapshot, allocator: Allocator) void {
        allocator.free(self.code_origins);
        allocator.free(self.values);
        allocator.free(self.children);
        allocator.free(self.closures);
        allocator.free(self.value_evidence);
        allocator.free(self.type_mappings);
        allocator.free(self.row_mappings);
        self.evidence.deinit(allocator);
        allocator.free(self.value_records);
        allocator.free(self.record_layouts);
        allocator.free(self.field_names);
        allocator.free(self.demands);
        self.implementation_proofs.deinit(allocator);
        self.* = undefined;
    }
};
pub const View = struct { code_origins: []const @import("../check/staging_origins.zig").Record = &.{}, values: []const ValueInfo, children: []const ValueId, closures: []const ClosureValue, value_evidence: []const type_evidence.Id, type_mappings: []const type_evidence.Mapping, row_mappings: []const type_evidence.RowMapping, evidence: type_evidence.View, value_records: []const u32, record_layouts: []const core.List, field_names: []const u32, demands: []const Demand, implementation_proofs: implementation_evidence.View = .{} };
pub const ViewKey = struct { value: ValueId, evidence: type_evidence.Id, entry_interface: bool = false };
// Offsets remain stable when field_names grows. The context is supplied for
// every lookup, so no hash-table key borrows a reallocatable slice pointer.
pub const RecordNames = struct {
    words: []const u32,
    pub fn hash(self: @This(), key: core.List) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(self.words[key.start..][0..key.len]));
    }
    pub fn eql(self: @This(), a: core.List, b: core.List) bool {
        return std.mem.eql(u32, self.words[a.start..][0..a.len], self.words[b.start..][0..b.len]);
    }
    pub const Adapter = struct {
        words: []const u32,
        pub fn hash(_: @This(), names: []const u32) u64 {
            return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(names));
        }
        pub fn eql(self: @This(), names: []const u32, key: core.List) bool {
            return std.mem.eql(u32, names, self.words[key.start..][0..key.len]);
        }
    };
};
pub const RecordKey = struct { unit: usize, ty: types.Id };

pub const Store = struct {
    values: std.ArrayList(ValueInfo) = .empty,
    children: std.ArrayList(ValueId) = .empty,
    collection_buffers: collection_growth.Store = .{},
    closures: std.ArrayList(ClosureValue) = .empty,
    demands: std.ArrayList(Demand) = .empty,
    code_origins: std.ArrayList(@import("../check/staging_origins.zig").Record) = .empty,
    value_evidence: std.ArrayList(type_evidence.Id) = .empty,
    type_mappings: std.ArrayList(type_evidence.Mapping) = .empty,
    row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty,
    evidence: type_evidence.Store,
    typed_views: std.AutoHashMapUnmanaged(ViewKey, ValueId) = .empty,
    specialized_closures: std.AutoHashMapUnmanaged(ViewKey, ValueId) = .empty,
    value_records: std.ArrayList(u32) = .empty,
    record_layouts: std.ArrayList(core.List) = .empty,
    field_names: std.ArrayList(u32) = .empty,
    record_types: std.AutoHashMapUnmanaged(RecordKey, u32) = .empty,
    record_shapes: std.HashMapUnmanaged(core.List, u32, RecordNames, 80) = .empty,

    pub fn init(allocator: Allocator) Allocator.Error!Store {
        var values: std.ArrayList(ValueInfo) = .empty;
        errdefer values.deinit(allocator);
        try values.append(allocator, .{});
        var value_evidence: std.ArrayList(type_evidence.Id) = .empty;
        errdefer value_evidence.deinit(allocator);
        try value_evidence.append(allocator, types.unit);
        var value_records: std.ArrayList(u32) = .empty;
        errdefer value_records.deinit(allocator);
        try value_records.append(allocator, 0);
        var record_layouts: std.ArrayList(core.List) = .empty;
        errdefer record_layouts.deinit(allocator);
        try record_layouts.append(allocator, .{});
        var evidence = type_evidence.Store.init(allocator) catch return error.OutOfMemory;
        errdefer evidence.deinit();
        return .{ .values = values, .value_evidence = value_evidence, .evidence = evidence, .value_records = value_records, .record_layouts = record_layouts };
    }
    pub fn deinit(self: *Store, allocator: Allocator) void {
        self.values.deinit(allocator);
        self.children.deinit(allocator);
        self.collection_buffers.deinit(allocator);
        self.closures.deinit(allocator);
        self.demands.deinit(allocator);
        self.code_origins.deinit(allocator);
        self.value_evidence.deinit(allocator);
        self.type_mappings.deinit(allocator);
        self.row_mappings.deinit(allocator);
        self.evidence.deinit();
        self.typed_views.deinit(allocator);
        self.specialized_closures.deinit(allocator);
        self.value_records.deinit(allocator);
        self.record_layouts.deinit(allocator);
        self.field_names.deinit(allocator);
        self.record_types.deinit(allocator);
        self.record_shapes.deinit(allocator);
        self.* = undefined;
    }
    pub fn scalar(self: *Store, allocator: Allocator, value_: Value) Allocator.Error!ValueId {
        const id: ValueId = @intCast(self.values.items.len);
        try self.values.ensureUnusedCapacity(allocator, 1);
        try self.value_evidence.ensureUnusedCapacity(allocator, 1);
        try self.value_records.ensureUnusedCapacity(allocator, 1);
        self.values.appendAssumeCapacity(.{ .scalar = value_.scalar, .bits = value_.bits });
        self.value_evidence.appendAssumeCapacity(switch (value_.scalar) {
            .unit => types.unit,
            .bool => types.boolean,
            .u32 => types.u32_type,
            .f32 => types.f32_type,
            else => 0,
        });
        self.value_records.appendAssumeCapacity(0);
        return id;
    }
    pub fn aggregate(self: *Store, allocator: Allocator, kind: ValueKind, nominal: u64, tag: u32, children_: []const ValueId) Allocator.Error!ValueId {
        // Capacity growth precedes mutation, so failure leaves every
        // published handle and child span valid.
        try self.values.ensureUnusedCapacity(allocator, 1);
        try self.value_evidence.ensureUnusedCapacity(allocator, 1);
        try self.value_records.ensureUnusedCapacity(allocator, 1);
        try self.children.ensureUnusedCapacity(allocator, children_.len);
        const id: ValueId = @intCast(self.values.items.len);
        const start: u32 = @intCast(self.children.items.len);
        self.children.appendSliceAssumeCapacity(children_);
        self.values.appendAssumeCapacity(.{ .kind = kind, .nominal = nominal, .bits = tag, .start = start, .len = @intCast(children_.len) });
        self.value_evidence.appendAssumeCapacity(0);
        self.value_records.appendAssumeCapacity(0);
        return id;
    }
    pub fn view(self: *const Store, proofs: implementation_evidence.View) View {
        return .{ .code_origins = self.code_origins.items, .values = self.values.items, .children = self.children.items, .closures = self.closures.items, .value_evidence = self.value_evidence.items, .type_mappings = self.type_mappings.items, .row_mappings = self.row_mappings.items, .evidence = self.evidence.view(), .value_records = self.value_records.items, .record_layouts = self.record_layouts.items, .field_names = self.field_names.items, .demands = self.demands.items, .implementation_proofs = proofs };
    }
    pub fn copySnapshot(self: *const Store, allocator: Allocator, proofs: *const implementation_evidence.Store) Allocator.Error!Snapshot {
        const code_origins = try allocator.dupe(@import("../check/staging_origins.zig").Record, self.code_origins.items);
        errdefer allocator.free(code_origins);
        const values = try allocator.dupe(ValueInfo, self.values.items);
        errdefer allocator.free(values);
        const children = try allocator.dupe(ValueId, self.children.items);
        errdefer allocator.free(children);
        const closures = try allocator.dupe(ClosureValue, self.closures.items);
        errdefer allocator.free(closures);
        const value_evidence = try allocator.dupe(type_evidence.Id, self.value_evidence.items);
        errdefer allocator.free(value_evidence);
        const type_mappings = try allocator.dupe(type_evidence.Mapping, self.type_mappings.items);
        errdefer allocator.free(type_mappings);
        const row_mappings = try allocator.dupe(type_evidence.RowMapping, self.row_mappings.items);
        errdefer allocator.free(row_mappings);
        const value_records = try allocator.dupe(u32, self.value_records.items);
        errdefer allocator.free(value_records);
        const record_layouts = try allocator.dupe(core.List, self.record_layouts.items);
        errdefer allocator.free(record_layouts);
        const field_names = try allocator.dupe(u32, self.field_names.items);
        errdefer allocator.free(field_names);
        const demands = try allocator.dupe(Demand, self.demands.items);
        errdefer allocator.free(demands);
        var selected = try proofs.copyOwned(allocator);
        errdefer selected.deinit(allocator);
        return .{ .code_origins = code_origins, .implementation_proofs = selected, .values = values, .children = children, .closures = closures, .value_evidence = value_evidence, .type_mappings = type_mappings, .row_mappings = row_mappings, .evidence = try self.evidence.copyOwned(allocator), .value_records = value_records, .record_layouts = record_layouts, .field_names = field_names, .demands = demands };
    }
};
