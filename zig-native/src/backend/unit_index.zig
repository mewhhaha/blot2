//! Per-unit indexes the backend builds once per compile attempt, on first
//! use, from a unit's immutable Core tables.
const std = @import("std");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const Allocator = std.mem.Allocator;

/// The type variables and row variables some scheme, type declaration,
/// operation, closure, contract or implementation of one unit quantifies or
/// closes. A variable outside both sets is ambiguous: checking left it
/// unconstrained.
pub const Quantified = struct {
    types: std.AutoHashMapUnmanaged(types.Id, void) = .empty,
    rows: std.AutoHashMapUnmanaged(u32, void) = .empty,

    pub fn init(allocator: Allocator, source: *const core.Module) Allocator.Error!Quantified {
        var result: Quantified = .{};
        errdefer result.deinit(allocator);
        const t = &source.types;
        for (source.bindings) |binding| {
            try result.add(allocator, false, t, &.{ binding.scheme.variables, binding.scheme.generative, binding.public_variables });
            try result.add(allocator, true, t, &.{ binding.scheme.row_variables, binding.scheme.closed_rows, binding.public_rows });
        }
        for (source.bodies) |body| {
            try result.add(allocator, false, t, &.{ body.scheme.variables, body.scheme.generative });
            try result.add(allocator, true, t, &.{ body.scheme.row_variables, body.scheme.closed_rows, body.closed_rows });
        }
        for (source.constructors) |constructor| {
            try result.add(allocator, false, t, &.{ constructor.scheme.variables, constructor.scheme.generative });
            try result.add(allocator, true, t, &.{constructor.scheme.row_variables});
        }
        for (source.nominals) |nominal| try result.add(allocator, false, t, &.{ nominal.parameters, nominal.variables });
        for (source.operation_names) |operation| try result.add(allocator, false, t, &.{ operation.variables, operation.parameters });
        for (source.closures) |metadata| try result.add(allocator, true, t, &.{metadata.closed_rows});
        for (source.contracts) |contract| {
            try result.add(allocator, false, t, &.{ contract.parameters, contract.variables });
            try result.add(allocator, true, t, &.{ contract.row_variables, contract.row_parameters });
        }
        for (source.implementations) |implementation| {
            try result.add(allocator, false, t, &.{ implementation.variables, implementation.head });
            try result.add(allocator, true, t, &.{ implementation.row_variables, implementation.row_parameters });
        }
        return result;
    }
    pub fn deinit(self: *Quantified, allocator: Allocator) void {
        self.types.deinit(allocator);
        self.rows.deinit(allocator);
    }
    /// Whether type variable or, for `row`, row variable `variable` is
    /// quantified or closed by some declaration of the unit.
    pub fn has(self: *const Quantified, variable: u32, row: bool) bool {
        return if (row) self.rows.contains(variable) else self.types.contains(variable);
    }
    fn add(self: *Quantified, allocator: Allocator, row: bool, t: *const core.Types, lists: []const types.List) Allocator.Error!void {
        for (lists) |list| for (t.list(list)) |variable| {
            if (row) try self.rows.put(allocator, variable, {}) else try self.types.put(allocator, variable, {});
        };
    }
};
