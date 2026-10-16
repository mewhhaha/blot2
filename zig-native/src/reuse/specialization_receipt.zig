//! PRIVATE successful exact-query receipts. Values and semantic IDs belong to
//! the artifact Snapshot; the record is never a principal scheme or startup proof.
const std = @import("std");
const core = @import("../check/core.zig");
const eval = @import("../eval/core_eval.zig");
const evidence = @import("../eval/type_evidence.zig");
const Allocator = std.mem.Allocator;
pub const ViewEffect = struct { value: u32, evidence: u32, selected: u32, existed: bool };
pub const CallRead = struct { unit: u32, binding: u32, evidence: u32, present: bool };
pub const ScalarRead = struct { target: core.BindingRef, evidence: u32 };
pub const PlainFact = struct { key: u64, plain: bool, read: bool = true, present: bool = true };
pub const ReadyRead = struct { target: core.BindingRef, value: u32 };
pub const PrincipalOutcome = enum { missing, declined, graph };
pub const PrincipalRead = struct { target: core.BindingRef, open: bool, source_interface: bool, deferred_member: bool, outcome: PrincipalOutcome };
pub const MemberTrace = struct {
    entries: [64]PrincipalRead = undefined,
    ready: [64]ReadyRead = undefined,
    ready_len: usize = 0,
    len: usize = 0,
    complete: bool = true,
    pub fn readyRead(self: *MemberTrace, read: ReadyRead, was_ready: bool) void {
        if (!was_ready or self.ready_len == self.ready.len) {
            self.complete = false;
            return;
        }
        self.ready[self.ready_len] = read;
        self.ready_len += 1;
    }
    pub fn append(self: *MemberTrace, read: PrincipalRead) void {
        if (self.len == self.entries.len) {
            self.complete = false;
            return;
        }
        self.entries[self.len] = read;
        self.len += 1;
    }
};
pub const Member = struct { ready: []ReadyRead = &.{}, principals: []PrincipalRead = &.{}, principal_graphs: bool, target: core.BindingRef, function: u32, query_budgets: [8]usize, principal_nodes: usize, principal_edges: usize, summary_work: usize, transitions: usize, exhausted: bool };
pub const Provider = struct {
    context: *anyopaque,
    lookup: *const fn (*anyopaque, *eval.Session, u32, u32) Allocator.Error!?u32,
    member: ?*const fn (*anyopaque, *eval.Session, core.BindingRef, u32, u32) Allocator.Error!?u32 = null,
};
pub const Record = struct {
    member: ?*Member = null,
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
        if (self.member) |member| {
            a.free(member.principals);
            a.free(member.ready);
            a.destroy(member);
        }
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
        result.member = null;
        if (self.member) |member| {
            const owned = try a.create(Member);
            owned.* = member.*;
            owned.principals = &.{};
            owned.ready = &.{};
            result.member = owned;
            errdefer a.destroy(owned);
            owned.principals = try a.dupe(PrincipalRead, member.principals);
            errdefer a.free(owned.principals);
            owned.ready = try a.dupe(ReadyRead, member.ready);
        }
        errdefer if (result.member) |member| {
            a.free(member.principals);
            a.free(member.ready);
            a.destroy(member);
        };
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
    if (record.member) |member| total += @sizeOf(Member) + member.principals.len * @sizeOf(PrincipalRead) + member.ready.len * @sizeOf(ReadyRead);
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
