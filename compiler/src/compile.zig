//! The compile interface: checked, lowered Core modules in, one Wasm module or
//! one diagnostic out. The direct backend (direct/) is the only code generator.
const std = @import("std");
const core = @import("check/core.zig");
const Allocator = std.mem.Allocator;
pub const Code = @import("check/diagnostic_code.zig").Code;

pub const Diagnostic = struct {
    unit: u32,
    span: core.Span,
    code: Code,
    detail: []const u8 = &.{},
    pub fn message(self: Diagnostic) []const u8 {
        return self.code.message(self.detail);
    }
};

/// Either `bytes` or `diagnostic` is present. `owned_message` owns the
/// diagnostic's detail.
pub const Result = struct {
    bytes: []u8 = &.{},
    diagnostic: ?Diagnostic = null,
    owned_message: []u8 = &.{},
    emitted_functions: usize = 0,
    /// Set by the direct backend; nothing reads it.
    whole_module_only: bool = false,
    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.owned_message);
        self.* = .{};
    }
};

pub fn compile(allocator: Allocator, units: []const core.Module, entry: u32) Allocator.Error!Result {
    return @import("direct/direct.zig").compile(allocator, units, entry);
}
