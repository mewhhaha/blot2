//! Lowering of independent source units on workers. Lowering one unit reads
//! only its syntax tree, its own checked module and the shared symbol pool,
//! all immutable while the batch runs, so each unit's Core is the serial one.
//! Callers keep their serial loop and take units in its order: diagnostics,
//! errors and ownership follow that order whatever finished first.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const core_builder = @import("core_builder.zig");
const LockedAllocator = @import("../eval/parallel_allocator.zig").LockedAllocator;
const A = std.mem.Allocator;

pub const Error = @typeInfo(@typeInfo(@TypeOf(core_builder.lowerWithOrigins)).@"fn".return_type.?).error_union.error_set;
/// One unit to lower. Callers pass null for a unit they obtain another way.
pub const Input = struct { tree: *const ast.Tree, checked: *const check.Checked };
/// Below this many syntax nodes in all, thread start-up costs more than it saves.
pub const min_nodes = 4096;

const Slot = struct { output: ?(Error!core.Module) = null };
const Work = struct {
    allocator: A,
    names: *const symbols.Pool,
    origins: check.ModuleOrigins,
    inputs: []const ?Input,
    slots: []Slot,
    /// Largest units first, so one large unit does not start last.
    order: []const u32,
    next: std.atomic.Value(usize) = .init(0),
    fn execute(self: *Work) void {
        while (true) {
            const at = self.next.fetchAdd(1, .monotonic);
            if (at >= self.order.len) return;
            const index = self.order[at];
            const input = self.inputs[index].?;
            self.slots[index].output = core_builder.lowerWithOrigins(self.allocator, input.tree, self.names, input.checked, self.origins);
        }
    }
};

pub const Batch = struct {
    allocator: A,
    slots: []Slot,
    workers: usize = 1,

    /// Lowers every non-null input, or returns null when the caller should
    /// lower serially (one worker, no Io, or too little work).
    pub fn run(a: A, io: ?std.Io, requested: u8, names: *const symbols.Pool, origins: check.ModuleOrigins, inputs: []const ?Input) A.Error!?Batch {
        return runAbove(a, io, requested, names, origins, inputs, min_nodes);
    }
    /// `run` with an explicit work threshold, for laws over small projects.
    pub fn runAbove(a: A, optional_io: ?std.Io, requested: u8, names: *const symbols.Pool, origins: check.ModuleOrigins, inputs: []const ?Input, minimum_nodes: usize) A.Error!?Batch {
        if (requested <= 1) return null;
        const io = optional_io orelse return null;
        var jobs: usize = 0;
        var nodes: usize = 0;
        for (inputs) |optional| if (optional) |input| {
            jobs += 1;
            nodes +|= input.tree.nodes.items.len;
        };
        if (jobs < 2 or nodes < minimum_nodes) return null;
        const order = try a.alloc(u32, jobs);
        defer a.free(order);
        var filled: usize = 0;
        for (inputs, 0..) |input, index| if (input != null) {
            order[filled] = @intCast(index);
            filled += 1;
        };
        const Larger = struct {
            fn lessThan(all: []const ?Input, left: u32, right: u32) bool {
                const l = all[left].?.tree.nodes.items.len;
                const r = all[right].?.tree.nodes.items.len;
                return l > r or (l == r and left < right);
            }
        };
        std.mem.sort(u32, order, inputs, Larger.lessThan);
        var batch: Batch = .{ .allocator = a, .slots = try a.alloc(Slot, inputs.len) };
        @memset(batch.slots, .{});
        var locked: LockedAllocator = .{ .backing = a, .io = io };
        var work: Work = .{ .allocator = locked.allocator(), .names = names, .origins = origins, .inputs = inputs, .slots = batch.slots, .order = order };
        var group: std.Io.Group = .init;
        // Lowering has no cancellation points. Join before any borrowed tree,
        // checked module or slot can be released.
        const protection = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(protection);
        defer group.cancel(io);
        const count = @min(@as(usize, requested), @min(jobs, 16));
        for (1..count) |_| {
            group.concurrent(io, Work.execute, .{&work}) catch break;
            batch.workers += 1;
        }
        work.execute();
        group.await(io) catch unreachable;
        return batch;
    }
    /// Moves unit `index`'s result out. Each lowered unit is taken at most once.
    pub fn take(self: *Batch, index: usize) Error!core.Module {
        const output = self.slots[index].output.?;
        self.slots[index].output = null;
        return output;
    }
    /// Releases every result the caller did not take.
    pub fn deinit(self: *Batch) void {
        for (self.slots) |*slot| if (slot.output) |output| {
            var module = output catch continue;
            module.deinit(self.allocator);
        };
        self.allocator.free(self.slots);
        self.* = undefined;
    }
};
