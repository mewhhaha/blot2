//! Extract closed machine ranges after source ownership checks complete.
//! A source-local ID is virtual until finalize. Helpers are () -> none and
//! share a private bank with their original root; only root entry resets it.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const A = std.mem.Allocator;
const absent = std.math.maxInt(u32);
pub const Error = A.Error || error{ InvalidOutline, OutlineLimit };
pub const Contract = enum { scoped_numeric_adapter_nonreentrant };
pub const Options = struct {
    minimum_instructions: usize = 5_000,
    maximum_range_instructions: usize = 1_800_000,
    maximum_helpers: usize = 8_192,
    maximum_control_depth: usize = 1_024,
    maximum_globals: usize = 1_000_000,
    maximum_locals: usize = 49_000,
    maximum_body_bytes: usize = 7_500_000,
};
pub const Work = struct { expressions: usize, layouts: usize };
pub const Ticket = struct { function: u32, start: usize, work: Work };
pub const Credit = Work;
pub const Stats = struct { regions: u64 = 0, globals: u64 = 0 };
const Total = struct { references: usize = 0, writes: usize = 0 };
const Root = struct {
    function: u32,
    scanned: usize = 0,
    totals: std.ArrayList(Total) = .empty,
    helpers: std.ArrayList(u32) = .empty, // indexes in Context.helpers
    fn deinit(self: *Root, a: A) void {
        self.totals.deinit(a);
        self.helpers.deinit(a);
    }
};
const Helper = struct { function: u32, root: u32, read_before_def: []u32, credit: Credit };
const Prepared = struct { function: u32, body: ir.Body };
const Bank = struct { root: u32, globals: []u32 }; // source local -> global/absent

pub const Context = struct {
    allocator: A,
    module: *wasm.Module,
    options: Options,
    roots: std.ArrayList(Root) = .empty,
    helpers: std.ArrayList(Helper) = .empty,
    stats: Stats = .{}, // final publication only; never decrements total work
    finalized: bool = false,

    pub fn init(a: A, module: *wasm.Module, contract: Contract, options: Options) Context {
        _ = contract; // Explicit caller assertion of the existing adapter contract.
        return .{ .allocator = a, .module = module, .options = options };
    }
    pub fn deinit(self: *Context) void {
        for (self.roots.items) |*root| root.deinit(self.allocator);
        for (self.helpers.items) |helper| self.allocator.free(helper.read_before_def);
        self.roots.deinit(self.allocator);
        self.helpers.deinit(self.allocator);
    }
    fn rootIndex(self: *const Context, function: u32) ?usize {
        for (self.roots.items, 0..) |root, index| if (root.function == function) return index;
        return null;
    }
    pub fn registerRoot(self: *Context, function: u32) Error!void {
        if (self.options.maximum_globals == 0 or self.options.maximum_globals > 1_000_000 or self.options.maximum_locals > 50_000 or self.options.maximum_body_bytes > 7_654_321 or self.options.minimum_instructions == 0 or self.options.minimum_instructions > self.options.maximum_range_instructions) return error.InvalidOutline;
        if (self.finalized or self.module.memory_model != .data_stacks or self.module.artifacts != null or function >= self.module.functions.items.len) return error.InvalidOutline;
        if (self.rootIndex(function) != null) return error.InvalidOutline;
        try self.roots.append(self.allocator, .{ .function = function });
    }
    pub fn begin(self: *const Context, function: u32, work: Work) ?Ticket {
        if (self.finalized or self.rootIndex(function) == null) return null;
        return .{ .function = function, .start = self.module.functions.items[function].instructions.items.len, .work = work };
    }
    fn sync(self: *Context, index: usize) Error!void {
        const function = &self.module.functions.items[self.roots.items[index].function];
        const root = &self.roots.items[index];
        const count = std.math.add(usize, function.parameters.len, function.locals.items.len) catch return error.InvalidOutline;
        if (count >= absent or count < root.totals.items.len or root.scanned > function.instructions.items.len) return error.InvalidOutline;
        try root.totals.appendNTimes(self.allocator, .{}, count - root.totals.items.len);
        // Moving a scanned suffix preserves these total reference counts. The
        // next scan starts after the replacement call, never counts moved IR twice.
        for (function.instructions.items[root.scanned..]) |inst| if (local(inst.op)) {
            if (inst.operand >= count) return error.InvalidOutline;
            root.totals.items[inst.operand].references += 1;
            if (inst.op != .local_get) root.totals.items[inst.operand].writes += 1;
        };
        root.scanned = function.instructions.items.len;
    }
    pub fn tryExtract(self: *Context, ticket: Ticket, after: Work) Error!?Credit {
        const root_index = self.rootIndex(ticket.function) orelse return null;
        if (self.finalized) return error.InvalidOutline;
        const source = &self.module.functions.items[ticket.function];
        if (ticket.start > source.instructions.items.len or after.expressions < ticket.work.expressions or after.layouts < ticket.work.layouts) return error.InvalidOutline;
        const length = source.instructions.items.len - ticket.start;
        if (length == 0 or length < self.options.minimum_instructions or length > self.options.maximum_range_instructions or self.helpers.items.len >= self.options.maximum_helpers) return null;
        if (hasCoordinates(self.module, ticket.function)) return null;
        var proof = (try Proof.analyze(self.allocator, self.module, source, source.instructions.items[ticket.start..], self.options.maximum_control_depth)) orelse return null;
        defer proof.deinit(self.allocator);
        try self.sync(root_index);
        var provisional: std.AutoHashMapUnmanaged(u32, u32) = .empty;
        defer provisional.deinit(self.allocator);
        var uses = proof.uses.iterator();
        while (uses.next()) |entry| {
            const id = entry.key_ptr.*;
            const total = self.roots.items[root_index].totals.items[id];
            if (id < source.parameters.len or total.references > entry.value_ptr.references or (proof.read_before_def.contains(id) and total.writes != 0))
                try provisional.put(self.allocator, id, @intCast(self.options.maximum_globals - 1));
        }
        // Future references only promote more locals. This lower bound on the
        // bank gives an upper bound on helper local pressure; final bytes checked again.
        var preview = try prepareBody(self.allocator, source, source.instructions.items[ticket.start..], false, .{ .sparse = &provisional });
        defer preview.deinit(self.allocator);
        if (!bounded(&preview, 0, self.options)) return null;
        const code = try self.allocator.dupe(ir.Instruction, source.instructions.items[ticket.start..]);
        errdefer self.allocator.free(code);
        const rbd = try self.allocator.alloc(u32, proof.read_before_def.count());
        errdefer self.allocator.free(rbd);
        var rbd_it = proof.read_before_def.keyIterator();
        var rbd_at: usize = 0;
        while (rbd_it.next()) |id| : (rbd_at += 1) rbd[rbd_at] = id.*;
        try self.helpers.ensureUnusedCapacity(self.allocator, 1);
        try self.roots.items[root_index].helpers.ensureUnusedCapacity(self.allocator, 1);
        // All source-pointer uses end here: addTypedFunction can move functions.
        const helper = self.module.addTypedFunction(&.{}, .none, .scalar) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.OutlineLimit,
        };
        self.module.functions.items[helper].instructions = std.ArrayList(ir.Instruction).fromOwnedSlice(code);
        const credit: Credit = .{ .expressions = after.expressions - ticket.work.expressions, .layouts = after.layouts - ticket.work.layouts };
        const ordinal: u32 = @intCast(self.helpers.items.len);
        self.helpers.appendAssumeCapacity(.{ .function = helper, .root = ticket.function, .read_before_def = rbd, .credit = credit });
        self.roots.items[root_index].helpers.appendAssumeCapacity(ordinal);
        const caller = &self.module.functions.items[ticket.function];
        const origin = caller.instructions.items[ticket.start].origin;
        caller.instructions.shrinkRetainingCapacity(ticket.start);
        caller.instructions.appendAssumeCapacity(.{ .op = .call, .operand = helper, .origin = origin });
        self.roots.items[root_index].scanned = caller.instructions.items.len;
        return credit; // Only now can the Generator subtract these per-body debits.
    }

    pub fn finalize(self: *Context) Error!Stats {
        if (self.finalized) return error.InvalidOutline;
        if (self.module.memory_model != .data_stacks or self.module.artifacts != null) return error.InvalidOutline;
        if (self.module.functions.items.len > 1_000_000 or self.module.imports.items.len > 1_000_000 - self.module.functions.items.len) return error.OutlineLimit;
        var banks: std.ArrayList(Bank) = .empty;
        defer {
            for (banks.items) |bank| self.allocator.free(bank.globals);
            banks.deinit(self.allocator);
        }
        var prepared: std.ArrayList(Prepared) = .empty;
        defer {
            for (prepared.items) |*item| item.body.deinit(self.allocator);
            prepared.deinit(self.allocator);
        }
        const first_global = self.module.globals.items.len;
        var next_global = first_global;
        for (0..self.roots.items.len) |root_index| {
            try self.sync(root_index);
            const root = &self.roots.items[root_index];
            if (root.helpers.items.len == 0) continue;
            if (hasCoordinates(self.module, root.function)) return error.InvalidOutline;
            try acyclic(self.allocator, self.module, root.function);
            const source = &self.module.functions.items[root.function];
            const count = std.math.add(usize, source.parameters.len, source.locals.items.len) catch return error.InvalidOutline;
            const map = try self.allocator.alloc(u32, count);
            var map_owned = true;
            errdefer if (map_owned) self.allocator.free(map);
            @memset(map, absent);
            const first = try self.allocator.alloc(u32, count);
            defer self.allocator.free(first);
            @memset(first, absent);
            const shared = try self.allocator.alloc(bool, count);
            defer self.allocator.free(shared);
            @memset(shared, false);
            try observe(source.instructions.items, root.function, first, shared);
            for (root.helpers.items) |ordinal| {
                const helper = self.helpers.items[ordinal];
                if (hasCoordinates(self.module, helper.function)) return error.InvalidOutline;
                try observe(self.module.functions.items[helper.function].instructions.items, helper.function, first, shared);
                for (helper.read_before_def) |id| {
                    if (id >= count) return error.InvalidOutline;
                    if (id < source.parameters.len or root.totals.items[id].writes != 0) shared[id] = true;
                }
            }
            for (shared, 0..) |yes, id| {
                if (!yes or (id >= source.parameters.len and root.totals.items[id].writes == 0)) continue; // independently zero
                if (localType(source, @intCast(id)) != .i32) return error.InvalidOutline;
                if (next_global >= self.options.maximum_globals or next_global >= absent) return error.OutlineLimit;
                map[id] = @intCast(next_global);
                next_global += 1;
            }
            try banks.append(self.allocator, .{ .root = root.function, .globals = map });
            map_owned = false;
            var caller = try prepareBody(self.allocator, source, source.instructions.items, true, .{ .dense = map });
            var caller_owned = true;
            errdefer if (caller_owned) caller.deinit(self.allocator);
            if (!bounded(&caller, source.parameters.len, self.options)) return error.OutlineLimit;
            try prepared.append(self.allocator, .{ .function = root.function, .body = caller });
            caller_owned = false;
            for (root.helpers.items) |ordinal| {
                const helper = self.helpers.items[ordinal];
                var body = try prepareBody(self.allocator, source, self.module.functions.items[helper.function].instructions.items, false, .{ .dense = map });
                errdefer body.deinit(self.allocator);
                if (!bounded(&body, 0, self.options)) return error.OutlineLimit;
                try prepared.append(self.allocator, .{ .function = helper.function, .body = body });
            }
        }
        // All body/global/cycle checks succeed before publication. Any failure
        // after tryExtract is terminal for this compile; never assemble staged IR.
        try self.module.globals.ensureTotalCapacity(self.allocator, next_global);
        for (first_global..next_global) |_| _ = self.module.addGlobal(.u32, 0, true) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.OutlineLimit,
        };
        for (prepared.items) |*item| {
            const destination = &self.module.functions.items[item.function];
            destination.locals.deinit(self.allocator);
            destination.instructions.deinit(self.allocator);
            destination.locals = item.body.locals;
            destination.instructions = item.body.instructions;
            destination.annotations = 0;
            item.body = .{};
        }
        self.stats = .{ .regions = self.helpers.items.len, .globals = next_global - first_global };
        self.finalized = true;
        return self.stats;
    }
};

fn local(op: ir.Op) bool {
    return op == .local_get or op == .local_set or op == .local_tee;
}
fn localType(function: *const ir.Function, id: u32) ?ir.ValueType {
    if (id < function.parameters.len) return function.parameters[id];
    const index = id - function.parameters.len;
    return if (index < function.locals.items.len) function.locals.items[index] else null;
}
fn hasCoordinates(module: *const wasm.Module, function: u32) bool {
    // Scoped emission currently has neither coordinate catalog. Decline until
    // relocation of these out-of-band instruction positions is implemented.
    for (module.semantic_sites.items) |site| if (site.function == function) return true;
    for (module.table_origins.items) |site| if (site.function == function) return true;
    return false;
}
const Use = struct { references: usize = 0, writes: usize = 0 };
const Set = std.AutoHashMapUnmanaged(u32, void);
const Frame = struct {
    op: ir.Op,
    height: usize,
    entry_poly: bool,
    entry_flow: bool,
    mark: usize,
    alternate: bool = false,
    exits: std.ArrayList(u32) = .empty,
    has_exit: bool = false,
};
fn pop(stack: *std.ArrayList(ir.ValueType), floor: usize, poly: bool, wanted: ir.ValueType) bool {
    if (stack.items.len == floor and poly) return true;
    if (stack.items.len <= floor) return false;
    const actual = stack.pop().?;
    return wanted == .none or actual == wanted;
}
fn restore(initialized: *Set, journal: *std.ArrayList(u32), mark: usize) void {
    for (journal.items[mark..]) |id| _ = initialized.remove(id);
    journal.shrinkRetainingCapacity(mark);
}
fn mergeExit(a: A, frame: *Frame, initialized: *const Set, inputs: *const Set, journal: []const u32) A.Error!void {
    if (!frame.has_exit) {
        try frame.exits.appendSlice(a, journal[frame.mark..]);
        frame.has_exit = true;
        return;
    }
    var kept: usize = 0;
    for (frame.exits.items) |id| if (initialized.contains(id) or inputs.contains(id)) {
        frame.exits.items[kept] = id;
        kept += 1;
    };
    frame.exits.shrinkRetainingCapacity(kept);
}
const Proof = struct {
    uses: std.AutoHashMapUnmanaged(u32, Use) = .empty,
    read_before_def: Set = .empty,
    fn deinit(self: *Proof, a: A) void {
        self.uses.deinit(a);
        self.read_before_def.deinit(a);
    }
    fn analyze(a: A, module: *const wasm.Module, source: *const ir.Function, code: []const ir.Instruction, control_limit: usize) A.Error!?Proof {
        var proof: Proof = .{};
        errdefer proof.deinit(a);
        if (!try proof.scan(a, module, source, code, control_limit)) {
            proof.deinit(a);
            return null;
        }
        return proof;
    }
    fn scan(self: *Proof, a: A, module: *const wasm.Module, source: *const ir.Function, code: []const ir.Instruction, control_limit: usize) A.Error!bool {
        var stack: std.ArrayList(ir.ValueType) = .empty;
        defer stack.deinit(a);
        var frames: std.ArrayList(Frame) = .empty;
        defer {
            for (frames.items) |*frame| frame.exits.deinit(a);
            frames.deinit(a);
        }
        var initialized: Set = .empty;
        defer initialized.deinit(a);
        var journal: std.ArrayList(u32) = .empty;
        defer journal.deinit(a);
        var poly = false; // Wasm stack-polymorphic unreachable path.
        var flow = true; // Reachable definite-initialization path.
        for (code) |inst| {
            if (inst.op == .ownership or inst.op == .resource_retire or inst.op == .wide_layouts or inst.op == .return_ or inst.op == .call_indirect) return false;
            const floor = if (frames.items.len == 0) 0 else frames.items[frames.items.len - 1].height;
            if (local(inst.op)) {
                if (localType(source, inst.operand) != .i32) return false;
                const entry = try self.uses.getOrPut(a, inst.operand);
                if (!entry.found_existing) entry.value_ptr.* = .{};
                entry.value_ptr.references += 1;
                if (inst.op != .local_get) entry.value_ptr.writes += 1;
                if (flow) {
                    if (inst.op == .local_get) {
                        if (!initialized.contains(inst.operand)) try self.read_before_def.put(a, inst.operand, {});
                    } else if (!initialized.contains(inst.operand) and !self.read_before_def.contains(inst.operand)) {
                        try initialized.put(a, inst.operand, {});
                        try journal.append(a, inst.operand);
                    }
                }
            }
            switch (inst.op) {
                .block, .loop, .if_ => {
                    if ((inst.operand != 0 and inst.operand != @backingInt(ir.ValueType.none)) or frames.items.len >= control_limit) return false;
                    if (inst.op == .if_ and !pop(&stack, floor, poly, .i32)) return false;
                    try frames.append(a, .{ .op = inst.op, .height = stack.items.len, .entry_poly = poly, .entry_flow = flow, .mark = journal.items.len });
                    continue;
                },
                .else_ => {
                    if (frames.items.len == 0) return false;
                    const frame = &frames.items[frames.items.len - 1];
                    if (frame.op != .if_ or frame.alternate or (!poly and stack.items.len != frame.height)) return false;
                    if (flow) try mergeExit(a, frame, &initialized, &self.read_before_def, journal.items);
                    restore(&initialized, &journal, frame.mark);
                    stack.shrinkRetainingCapacity(frame.height);
                    frame.alternate = true;
                    poly = frame.entry_poly;
                    flow = frame.entry_flow;
                    continue;
                },
                .end => {
                    var frame = frames.pop() orelse return false;
                    defer frame.exits.deinit(a);
                    if (!poly and stack.items.len != frame.height) return false;
                    if (flow) try mergeExit(a, &frame, &initialized, &self.read_before_def, journal.items);
                    if (frame.op == .if_ and !frame.alternate and frame.entry_flow) {
                        frame.has_exit = true;
                        frame.exits.clearRetainingCapacity();
                    }
                    restore(&initialized, &journal, frame.mark);
                    flow = frame.has_exit;
                    if (flow) for (frame.exits.items) |id| if (!initialized.contains(id) and !self.read_before_def.contains(id)) {
                        try initialized.put(a, id, {});
                        try journal.append(a, id);
                    };
                    stack.shrinkRetainingCapacity(frame.height);
                    poly = frame.entry_poly;
                    continue;
                },
                .br, .br_if => {
                    // Equality would branch to the ORIGINAL function exit.
                    if (inst.operand >= frames.items.len) return false;
                    if (inst.op == .br_if and !pop(&stack, floor, poly, .i32)) return false;
                    const target = &frames.items[frames.items.len - 1 - inst.operand];
                    if (flow and target.op != .loop) try mergeExit(a, target, &initialized, &self.read_before_def, journal.items);
                    if (inst.op == .br) {
                        stack.shrinkRetainingCapacity(floor);
                        poly = true;
                        flow = false;
                    }
                    continue;
                },
                .unreachable_ => {
                    stack.shrinkRetainingCapacity(floor);
                    poly = true;
                    flow = false;
                    continue;
                },
                .call, .call_import => {
                    if (inst.op == .call and inst.operand >= module.functions.items.len) return false;
                    if (inst.op == .call_import and (inst.operand >= module.imports.items.len or module.imports.items[inst.operand].signature >= module.signatures.items.len)) return false;
                    const signature = ir.call(module, inst);
                    var at = signature.parameters.len;
                    while (at != 0) {
                        at -= 1;
                        if (!pop(&stack, floor, poly, signature.parameters[at])) return false;
                    }
                    if (signature.result != .none) try stack.append(a, signature.result);
                    continue;
                },
                .global_get, .global_set => if (inst.operand >= module.globals.items.len) return false,
                else => {},
            }
            // Calls are handled above: Contract.inputs only has three slots.
            const contract = ir.contract(module, source, inst);
            if (contract.arity > contract.inputs.len) return false;
            var at = contract.arity;
            while (at != 0) {
                at -= 1;
                if (!pop(&stack, floor, poly, contract.inputs[at])) return false;
            }
            if (contract.result != .none) try stack.append(a, contract.result);
        }
        return frames.items.len == 0 and (poly or stack.items.len == 0);
    }
};

const GlobalMap = union(enum) {
    sparse: *const std.AutoHashMapUnmanaged(u32, u32),
    dense: []const u32,
    fn get(self: GlobalMap, id: u32) ?u32 {
        return switch (self) {
            .sparse => |map| map.get(id),
            .dense => |map| if (id < map.len and map[id] != absent) map[id] else null,
        };
    }
};
fn prepareBody(a: A, source: *const ir.Function, code: []const ir.Instruction, is_root: bool, globals: GlobalMap) Error!ir.Body {
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    var locals: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer locals.deinit(a);
    const parameters: []ir.ValueType = if (is_root) source.parameters else &.{};
    if (is_root) switch (globals) {
        .dense => |mapping| for (mapping, 0..) |global, id| {
            if (global == absent) continue;
            // Root signature remains unchanged. Parameters are copied; locals
            // receive exactly their original function-entry zero bits.
            try result.emit(a, if (id < source.parameters.len) .local_get else .i32_const, if (id < source.parameters.len) @intCast(id) else 0);
            try result.emit(a, .global_set, global);
        },
        .sparse => return error.InvalidOutline,
    };
    for (code) |inst| {
        if (inst.op == .ownership or inst.op == .resource_retire or inst.op == .wide_layouts) return error.InvalidOutline;
        var output = inst; // Keep all packed flags and origin fields.
        if (local(inst.op)) {
            if (globals.get(inst.operand)) |global| {
                output.op = if (inst.op == .local_get) .global_get else .global_set;
                output.operand = global;
                try result.instructions.append(a, output);
                if (inst.op == .local_tee) {
                    output.op = .global_get;
                    try result.instructions.append(a, output);
                }
                continue;
            }
            if (is_root and inst.operand < parameters.len) {
                output.operand = inst.operand;
            } else {
                // An original parameter used in a helper MUST be a bank slot.
                if (inst.operand < source.parameters.len) return error.InvalidOutline;
                const entry = try locals.getOrPut(a, inst.operand);
                if (!entry.found_existing) {
                    entry.value_ptr.* = @intCast(parameters.len + result.locals.items.len);
                    try result.locals.append(a, localType(source, inst.operand) orelse return error.InvalidOutline);
                }
                output.operand = entry.value_ptr.*;
            }
        }
        try result.instructions.append(a, output);
    }
    // Pruning above is mandatory: the existing compactor pins unused locals.
    const view: ir.Function = .{ .parameters = parameters, .result = if (is_root) source.result else .none, .signature = source.signature, .locals = result.locals, .instructions = result.instructions };
    if (try @import("wasm_local_compact.zig").run(a, &view)) |compacted| {
        result.deinit(a);
        result = compacted;
    }
    return result;
}
fn observe(code: []const ir.Instruction, function: u32, first: []u32, shared: []bool) Error!void {
    for (code) |inst| if (local(inst.op)) {
        if (inst.operand >= first.len) return error.InvalidOutline;
        if (first[inst.operand] == absent) first[inst.operand] = function else if (first[inst.operand] != function) shared[inst.operand] = true;
    };
}
fn acyclic(a: A, module: *const wasm.Module, root: u32) Error!void {
    // Reject cycles reachable from this banked root and all unknown indirect
    // dispatch. Host nonreentry does not establish internal Wasm acyclicity.
    const colors = try a.alloc(u2, module.functions.items.len);
    defer a.free(colors);
    @memset(colors, 0);
    const Visit = struct { function: u32, at: usize = 0 };
    var pending: std.ArrayList(Visit) = .empty;
    defer pending.deinit(a);
    try pending.append(a, .{ .function = root });
    colors[root] = 1;
    while (pending.items.len != 0) {
        const current = &pending.items[pending.items.len - 1];
        const instructions = module.functions.items[current.function].instructions.items;
        if (current.at == instructions.len) {
            colors[current.function] = 2;
            _ = pending.pop();
            continue;
        }
        const inst = instructions[current.at];
        current.at += 1;
        if (inst.op == .call_indirect) return error.InvalidOutline;
        if (inst.op != .call) continue;
        if (inst.operand >= colors.len or colors[inst.operand] == 1) return error.InvalidOutline;
        if (colors[inst.operand] == 2) continue;
        colors[inst.operand] = 1;
        try pending.append(a, .{ .function = inst.operand });
    }
}
fn uleb(value: usize) usize {
    var remaining = value;
    var bytes: usize = 1;
    while (remaining >= 128) {
        remaining >>= 7;
        bytes += 1;
    }
    return bytes;
}
fn sleb(value: u32) usize {
    var remaining: i32 = @bitCast(value);
    var bytes: usize = 0;
    while (true) {
        const byte: u8 = @truncate(@as(u32, @bitCast(remaining)) & 127);
        remaining >>= 7;
        bytes += 1;
        if ((remaining == 0 and byte & 64 == 0) or (remaining == -1 and byte & 64 != 0)) return bytes;
    }
}
fn instructionBound(inst: ir.Instruction) ?usize {
    if (inst.table_reference) return 6;
    if (@import("wasm_simd_ops.zig").code(inst.op)) |opcode| return 1 + uleb(opcode) + switch (inst.op) {
        .v128_load, .v128_store => @as(usize, 1) + uleb(inst.operand),
        .i32x4_replace_lane, .i32x4_extract_lane, .f32x4_extract_lane, .f32x4_replace_lane => @as(usize, 1),
        .i8x16_shuffle => @as(usize, 16),
        else => @as(usize, 0),
    };
    return switch (inst.op) {
        .ownership, .wide_layouts, .resource_retire, .call_indirect => null,
        .block, .loop, .if_, .memory_size, .memory_grow, .host_ref_get, .host_ref_set, .host_ref_null, .i32_trunc_sat_f32_u => 2,
        .local_get, .local_set, .local_tee, .global_get, .global_set, .br, .br_if => 1 + uleb(inst.operand),
        .call, .call_import => 6, // Any future valid u32 function/import index.
        .i32_const => 1 + sleb(inst.operand),
        .f32_const => 5,
        .i32_load, .f32_load, .i32_store, .f32_store => 2 + uleb(inst.operand),
        .memory_copy => 4,
        .memory_fill, .host_ref_size, .host_ref_grow => 3,
        else => 1,
    };
}
fn bounded(body: *const ir.Body, parameters: usize, options: Options) bool {
    if (parameters > options.maximum_locals or body.locals.items.len > options.maximum_locals - parameters) return false;
    var bytes = uleb(body.locals.items.len) + 2 * body.locals.items.len + 1;
    for (body.instructions.items) |inst| {
        bytes += instructionBound(inst) orelse return false;
        if (bytes > options.maximum_body_bytes) return false;
    }
    return true;
}

test {
    _ = @import("wasm_scope_outline_tests.zig");
}
