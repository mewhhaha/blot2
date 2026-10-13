//! Opt-in sweep records; symbol resolution and reporting happen after timing.
const std = @import("std");

pub const enabled = @import("test_options").oom_profile;

pub const Measurement = struct {
    kind: []const u8,
    scenario_address: usize,
    caller_address: usize,
    started: std.Io.Timestamp,
    allocations: usize = 0,
    runs: usize = 0,
    completed: bool = false,

    pub fn start(kind: []const u8, scenario_address: usize, caller_address: usize) Measurement {
        return .{
            .kind = kind,
            .scenario_address = scenario_address,
            .caller_address = caller_address,
            .started = std.Io.Clock.awake.now(std.testing.io),
        };
    }

    pub fn finish(self: Measurement) void {
        const duration = self.started.durationTo(std.Io.Clock.awake.now(std.testing.io));
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const scenario = symbol(allocator, self.scenario_address);
        const caller = symbol(allocator, self.caller_address -| 1);
        const record = std.json.Stringify.valueAlloc(allocator, .{
            .kind = self.kind,
            .duration_ns = duration.nanoseconds,
            .allocations = self.allocations,
            .runs = self.runs,
            .completed = self.completed,
            .scenario = scenario.name,
            .scenario_source = scenario.source_location,
            .caller = caller.name,
            .source = caller.source_location,
            .scenario_address = self.scenario_address,
            .caller_address = self.caller_address,
        }, .{}) catch {
            std.debug.print("BLOT_OOM_PROFILE_ERROR\tOutOfMemory\n", .{});
            return;
        };
        std.debug.print("BLOT_OOM_PROFILE\t{s}\n", .{record});
    }
};

fn symbol(allocator: std.mem.Allocator, address: usize) std.debug.Symbol {
    const debug_info = std.debug.getSelfDebugInfo() catch return .unknown;
    var symbols: std.ArrayList(std.debug.Symbol) = .empty;
    debug_info.getSymbols(std.testing.io, allocator, allocator, address, true, &symbols) catch return .unknown;
    if (symbols.items.len == 0) return .unknown;
    return symbols.items[0];
}
