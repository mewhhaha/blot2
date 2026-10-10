//! PRIVATE successful exact-query receipts. Values and semantic IDs belong to
//! the artifact Snapshot; the record is never a principal scheme or startup proof.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const evidence = @import("type_evidence.zig");
const Allocator = std.mem.Allocator;
pub const ViewEffect = struct { value: u32, evidence: u32, selected: u32, existed: bool };
pub const CallRead = struct { unit: u32, binding: u32, evidence: u32, present: bool };
pub const ScalarRead = struct { target: core.BindingRef, evidence: u32 };
pub const PlainFact = struct { key: u64, plain: bool, read: bool = true, present: bool = true };
pub const Provider = struct {
    context: *anyopaque,
    lookup: *const fn (*anyopaque, *eval.Session, u32, u32) Allocator.Error!?u32,
};
pub const Record = struct {
    input: u32,
    expected: u32,
    selected: u32,
    options: eval.Options,
    depth: usize,
    values_before: usize,
    children_before: usize,
    values_added: usize,
    children_added: usize,
    steps: usize,
    collected: usize,
    source_scopes: usize,
    solver_nodes: usize,
    complete: bool,
    sources: []core.BindingRef,
    scalar_reads: []ScalarRead,
    call_reads: []CallRead,
    call_publications: []CallRead,
    views: []ViewEffect,
    plain_facts: []PlainFact,
    pub fn deinit(self: *Record, a: Allocator) void {
        a.free(self.sources);
        a.free(self.scalar_reads);
        a.free(self.call_reads);
        a.free(self.call_publications);
        a.free(self.views);
        a.free(self.plain_facts);
        self.* = undefined;
    }
    pub fn clone(self: Record, a: Allocator) Allocator.Error!Record {
        var result = self;
        result.sources = try a.dupe(core.BindingRef, self.sources);
        errdefer a.free(result.sources);
        result.scalar_reads = try a.dupe(ScalarRead, self.scalar_reads);
        errdefer a.free(result.scalar_reads);
        result.call_reads = try a.dupe(CallRead, self.call_reads);
        errdefer a.free(result.call_reads);
        result.call_publications = try a.dupe(CallRead, self.call_publications);
        errdefer a.free(result.call_publications);
        result.views = try a.dupe(ViewEffect, self.views);
        errdefer a.free(result.views);
        result.plain_facts = try a.dupe(PlainFact, self.plain_facts);
        return result;
    }
};
pub fn ownedBytes(record: Record) usize {
    var total: usize = 0;
    inline for (.{ "sources", "scalar_reads", "call_reads", "call_publications", "views", "plain_facts" }) |field| {
        const entries = @field(record, field);
        total +|= entries.len *| @sizeOf(@TypeOf(entries[0]));
    }
    return total;
}
pub const Tape = struct {
    sources: std.ArrayList(core.BindingRef) = .empty,
    scalar_reads: std.ArrayList(ScalarRead) = .empty,
    call_reads: std.ArrayList(CallRead) = .empty,
    call_publications: std.ArrayList(CallRead) = .empty,
    views: std.ArrayList(ViewEffect) = .empty,
    plain_facts: std.ArrayList(PlainFact) = .empty,
    nested: bool = false,
    unknown: bool = false,
    collected: usize = 0,
    pub fn deinit(self: *Tape, a: Allocator) void {
        self.sources.deinit(a);
        self.scalar_reads.deinit(a);
        self.call_reads.deinit(a);
        self.call_publications.deinit(a);
        self.views.deinit(a);
        self.plain_facts.deinit(a);
    }
    pub fn finish(self: *Tape, a: Allocator, base: Record) Allocator.Error!Record {
        var result = base;
        result.sources = try self.sources.toOwnedSlice(a);
        errdefer a.free(result.sources);
        result.scalar_reads = try self.scalar_reads.toOwnedSlice(a);
        errdefer a.free(result.scalar_reads);
        result.call_reads = try self.call_reads.toOwnedSlice(a);
        errdefer a.free(result.call_reads);
        result.call_publications = try self.call_publications.toOwnedSlice(a);
        errdefer a.free(result.call_publications);
        result.views = try self.views.toOwnedSlice(a);
        errdefer a.free(result.views);
        result.plain_facts = try self.plain_facts.toOwnedSlice(a);
        result.complete = result.complete and !self.nested and !self.unknown;
        return result;
    }
};
