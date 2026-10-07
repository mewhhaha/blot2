//! One owner for runtime optimization scratch and transformed bodies. A pass
//! consumes a typed IR view; replacement drops the previous body immediately.
//! The retained source/artifact body is immutable and survives every failure.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const lifetimes = @import("wasm_lifetimes.zig");
const A = std.mem.Allocator;

pub const Session = struct {
    allocator: A,
    module: *const wasm.Module,
    summaries: lifetimes.Summaries,

    pub fn init(a: A, module: *const wasm.Module) A.Error!Session {
        return .{ .allocator = a, .module = module, .summaries = try lifetimes.Summaries.init(a, module) };
    }
    pub fn deinit(self: *Session) void {
        self.summaries.deinit();
    }
    pub fn optimize(self: *Session, source: *const ir.Function) A.Error!?ir.Body {
        var owned: ?ir.Body = null;
        errdefer if (owned) |*body| body.deinit(self.allocator);
        var view = source.*;
        inline for (.{ "scalar", "vector", "lifetime" }) |pass| {
            const next = if (comptime std.mem.eql(u8, pass, "scalar"))
                try @import("wasm_sroa.zig").run(self.allocator, self.module, &view)
            else if (comptime std.mem.eql(u8, pass, "vector"))
                try @import("wasm_vectorize.zig").run(self.allocator, self.module, &view)
            else
                try lifetimes.runWithSummaries(self.allocator, self.module, &view, &self.summaries);
            if (next) |replacement| {
                if (owned) |*body| body.deinit(self.allocator);
                owned = replacement;
                view.locals = replacement.locals;
                view.instructions = replacement.instructions;
            }
        }
        return owned;
    }
};
