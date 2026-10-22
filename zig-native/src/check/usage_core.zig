//! Portable types are usage contracts, but immutable executable references
//! independently prove their move/capture obligations. Redundant capture lists
//! and source qualifier spelling confer no authority at this boundary.
const std = @import("std");
const T = @import("types.zig");
const core = @import("core.zig");
const usage = @import("usage_check.zig");
const Error = error{InvalidArtifact};
const State = struct { binding: u32, first: u32 = 0, loan: u32 = 0 };
const Outcome = enum { live, exit };
const ExitFrame = struct { target: u32, joined: []State, seen: bool = false, parent: ?*ExitFrame = null };
const StageEnvironment = struct {
    states: []State,
    regions: []const T.Id,
    bindings: []const u32,
    ambient: T.Effects.Id,
    returns: ?*ExitFrame,
    breaks: ?*ExitFrame,
    earlier: ?*StageEnvironment,
};
const Walker = struct {
    module: *const core.Module,
    states: [4096]State = undefined,
    len: usize = 0,
    snapshots: [65_536]State = undefined,
    snapshot_len: usize = 0,
    remaining: usize = 65_536,
    regions: [128]T.Id = undefined,
    region_bindings: [128]u32 = undefined,
    region_count: usize = 0,
    ambient: T.Effects.Id = 0,
    returns: ?*ExitFrame = null,
    breaks: ?*ExitFrame = null,
    earlier: ?*StageEnvironment = null,
    fn record(self: *Walker, frame: *ExitFrame) void {
        frame.seen = true;
        for (frame.joined, self.states[0..frame.joined.len]) |*entry, after| if (entry.first == 0) {
            entry.first = after.first;
        };
    }
    fn block(self: *Walker, source: u32, depth: usize) Error!Outcome {
        const count = self.len;
        const mark = self.snapshot_len;
        defer self.snapshot_len = mark;
        var frame: ExitFrame = .{ .target = source, .joined = try self.snapshot(), .parent = self.returns };
        const outer = self.returns;
        self.returns = &frame;
        defer self.returns = outer;
        const node = self.module.nodes[source];
        var flow: Outcome = .live;
        for (self.module.extra[node.a..][0..node.b]) |child| if (try self.expression(child, depth + 1) == .exit) {
            flow = .exit;
            break;
        };
        self.len = count;
        if (frame.seen) {
            if (flow == .exit) {
                @memcpy(self.states[0..count], frame.joined);
            } else {
                for (self.states[0..count], frame.joined) |*entry, after| if (entry.first == 0) {
                    entry.first = after.first;
                };
            }
            return .live;
        }
        return flow;
    }
    fn singleIteration(self: *Walker, loop: core.LoopInfo) bool {
        if (loop.kind != .range) return false;
        const first = self.module.nodes[loop.first];
        const end = self.module.nodes[loop.end];
        if (first.tag != .constant or end.tag != .constant or first.ty != T.u32_type or end.ty != T.u32_type) return false;
        return first.a < end.a and end.a - first.a == 1;
    }
    fn charge(self: *Walker, depth: usize) Error!void {
        if (depth >= 128 or self.remaining == 0) return error.InvalidArtifact;
        self.remaining -= 1;
    }
    fn snapshot(self: *Walker) Error![]State {
        if (self.len > self.snapshots.len - self.snapshot_len or self.len > self.remaining) return error.InvalidArtifact;
        self.remaining -= self.len;
        const values = self.snapshots[self.snapshot_len..][0..self.len];
        self.snapshot_len += self.len;
        @memcpy(values, self.states[0..self.len]);
        return values;
    }
    fn affine(self: *Walker, ty: T.Id) Error!bool {
        return usage.affineNominal(&self.module.types, self.module.nominals, ty) catch return error.InvalidArtifact;
    }
    fn state(self: *Walker, binding: u32) ?*State {
        for (self.states[0..self.len]) |*entry| if (entry.binding == binding) return entry;
        return null;
    }
    fn introduce(self: *Walker, binding: u32) Error!void {
        if (binding == 0) return;
        if (binding >= self.module.bindings.len) return error.InvalidArtifact;
        if (self.state(binding) != null or !try self.affine(self.module.bindings[binding].ty)) return;
        if (self.len == self.states.len) return error.InvalidArtifact;
        self.states[self.len] = .{ .binding = binding };
        self.len += 1;
    }
    fn use(self: *Walker, binding: u32, source: u32) Error!void {
        if (binding == 0 or binding >= self.module.bindings.len) return error.InvalidArtifact;
        if (!try self.affine(self.module.bindings[binding].ty)) return;
        const entry = self.state(binding) orelse return error.InvalidArtifact;
        if (entry.first != 0 or entry.loan != 0) return error.InvalidArtifact;
        entry.first = source;
    }
    fn liveLoans(self: *Walker, ty: T.Id, depth: usize) Error!void {
        try self.charge(depth);
        const node = self.module.types.node(ty);
        switch (node.tag) {
            .usage => {
                if (node.c != 0) {
                    var live = false;
                    for (self.regions[0..self.region_count]) |region| if (node.c == region) {
                        live = true;
                    };
                    if (!live) return error.InvalidArtifact;
                }
                try self.liveLoans(node.a, depth + 1);
            },
            .array, .list, .cursor, .demand => try self.liveLoans(node.a, depth + 1),
            .product => for (self.module.types.list(.{ .start = node.a, .len = node.b })) |child| try self.liveLoans(child, depth + 1),
            .record => for (0..node.b) |index| try self.liveLoans(self.module.types.recordField(node, index).ty, depth + 1),
            .nominal => for (self.module.types.nominalArguments(node)) |child| try self.liveLoans(child, depth + 1),
            else => {},
        }
    }
    fn activeType(self: *Walker, ty: T.Id, depth: usize) Error!bool {
        try self.charge(depth);
        const node = self.module.types.node(ty);
        switch (node.tag) {
            .usage => {
                for (self.regions[0..self.region_count]) |region| if (node.c == region) return true;
                return self.activeType(node.a, depth + 1);
            },
            .array, .list, .cursor, .demand => return self.activeType(node.a, depth + 1),
            .function => return try self.activeType(node.a, depth + 1) or try self.activeType(node.b, depth + 1),
            .product => for (self.module.types.list(.{ .start = node.a, .len = node.b })) |child| {
                if (try self.activeType(child, depth + 1)) return true;
            },
            .record => for (0..node.b) |index| {
                if (try self.activeType(self.module.types.recordField(node, index).ty, depth + 1)) return true;
            },
            .nominal => for (self.module.types.nominalArguments(node)) |child| {
                if (try self.activeType(child, depth + 1)) return true;
            },
            else => {},
        }
        return false;
    }
    fn scalar(self: *Walker, ty: T.Id) bool {
        return switch (self.module.types.node(ty).tag) {
            .unit, .boolean, .u32, .f32 => true,
            else => false,
        };
    }
    fn capturedLoan(self: *Walker, source: u32, excluded: u32, depth: usize) Error!bool {
        try self.charge(depth);
        if (source == 0) return false;
        const node = self.module.nodes[source];
        switch (node.tag) {
            .reference => return self.carriesLoan(source, excluded, depth + 1),
            .constant, .primitive_function, .constructor_function, .type_constructor, .panic => return false,
            .closure, .suspend_ => {
                const value = self.module.closures[node.a];
                return self.capturedLoan(value.body, value.parameter.binding, depth + 1);
            },
            .apply, .scalar, .logical, .record_merge, .proof_guard, .resource_acquire, .usage_borrow => return try self.capturedLoan(node.a, excluded, depth + 1) or try self.capturedLoan(node.b, excluded, depth + 1),
            .resource_release, .usage_share, .usage_read, .project, .return_, .force, .package_pack => return self.capturedLoan(node.a, excluded, depth + 1),
            .effect_scope => {
                if (node.a == 0 or node.a >= self.module.nodes.len) return error.InvalidArtifact;
                return self.capturedLoan(node.a, excluded, depth + 1);
            },
            .bind, .construct => return self.capturedLoan(node.b, excluded, depth + 1),
            .if_value, .if_stmt => return try self.capturedLoan(node.a, excluded, depth + 1) or try self.capturedLoan(node.b, excluded, depth + 1) or try self.capturedLoan(node.c, excluded, depth + 1),
            .task, .block, .suite, .product, .record, .array, .array_op => for (self.module.extra[node.a..][0..node.b]) |child| {
                if (try self.capturedLoan(child, excluded, depth + 1)) return true;
            },
            .call => {
                const target = self.module.calls[node.a].target;
                if (target.unit == 0 or target.unit == self.module.unit) {
                    for (self.module.nodes) |definition| {
                        try self.charge(depth);
                        if (definition.tag == .bind and definition.a == target.binding and try self.carriesLoan(definition.b, excluded, depth + 1)) return true;
                    }
                }
                for (self.module.extra[node.b..][0..node.c]) |child| if (try self.capturedLoan(child, excluded, depth + 1)) return true;
            },
            else => return error.InvalidArtifact,
        }
        return false;
    }
    fn carriesLoan(self: *Walker, source: u32, excluded: u32, depth: usize) Error!bool {
        try self.charge(depth);
        if (source == 0) return false;
        const node = self.module.nodes[source];
        if (try self.activeType(node.ty, depth + 1)) return true;
        switch (node.tag) {
            .reference => {
                const ref = self.module.references[node.a];
                if (ref.unit != 0 and ref.unit != self.module.unit) return false;
                if (ref.binding == excluded) return false;
                for (self.region_bindings[0..self.region_count]) |binding| if (binding == ref.binding) return true;
                // Follow the executable version's defining value. A claimed
                // scalar/function annotation cannot hide its borrowed origin.
                for (self.module.nodes) |definition| {
                    try self.charge(depth);
                    if (definition.tag == .bind and definition.a == ref.binding) return self.carriesLoan(definition.b, excluded, depth + 1);
                }
                if (try self.activeType(self.module.bindings[ref.binding].ty, depth + 1)) return true;
                const binding = self.module.bindings[ref.binding];
                if (binding.kind == .parameter or binding.kind == .global or binding.kind == .external or self.scalar(node.ty)) return false;
                return error.InvalidArtifact;
            },
            .constant => {
                if (!self.scalar(node.ty)) return error.InvalidArtifact;
            },
            .usage_share => return self.carriesLoan(node.a, excluded, depth + 1),
            .resource_release, .primitive_function, .constructor_function, .type_constructor, .usage_read => {},
            .resource_acquire => return false,
            .scalar, .logical, .call, .apply, .force => {
                // Their arguments are checked independently at invocation;
                // a checked primitive result cannot itself retain a loan.
                if (!self.scalar(node.ty)) return error.InvalidArtifact;
            },
            .closure, .suspend_ => {
                const value = self.module.closures[node.a];
                return self.capturedLoan(value.body, value.parameter.binding, depth + 1);
            },
            .project, .return_, .package_pack => return self.carriesLoan(node.a, excluded, depth + 1),
            .bind, .construct => return self.carriesLoan(node.b, excluded, depth + 1),
            .if_value, .if_stmt => return try self.carriesLoan(node.b, excluded, depth + 1) or try self.carriesLoan(node.c, excluded, depth + 1),
            .task, .block, .suite, .product, .record, .array, .array_op => for (self.module.extra[node.a..][0..node.b]) |child| {
                if (try self.carriesLoan(child, excluded, depth + 1)) return true;
            },
            // Storage, patterns, recursive aliases and unsupported result
            // producers need a complete path recipe before loan publication.
            else => return error.InvalidArtifact,
        }
        return false;
    }
    fn argument(self: *Walker, source: u32, parameter: T.Id, depth: usize) Error!void {
        if (self.region_count == 0 or !try self.carriesLoan(source, 0, depth + 1)) return;
        const actual = self.module.types.node(self.module.typeOf(source));
        const required = self.module.types.node(parameter);
        if (actual.tag != .usage or required.tag != .usage or actual.b != required.b or (actual.b != @backingInt(T.UsageKind.borrow) and actual.b != @backingInt(T.UsageKind.borrow_mut)) or !(@import("rank_equal.zig").equal(&self.module.types, actual.a, required.a, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        if (actual.c == required.c) return;
        const region = self.module.types.node(required.c);
        if (region.tag != .bound or region.b != 2 or region.c != 0 or !formalRegion(self.module, required.c, &self.remaining)) return error.InvalidArtifact;
    }
    fn argumentArrow(self: *Walker, ty: T.Id) Error!T.Node {
        var current = ty;
        while (true) {
            try self.charge(0);
            const node = self.module.types.node(current);
            if (node.tag != .usage and node.tag != .forall) return node;
            current = node.a;
        }
    }
    fn quantified(self: *Walker, ty: T.Id) Error!T.Node {
        var current = ty;
        while (true) {
            try self.charge(0);
            const node = self.module.types.node(current);
            if (node.tag == .usage) {
                current = node.a;
                continue;
            }
            if (node.tag != .forall) return node;
            if (node.c == 0 or node.c > 128 or node.b > self.module.types.extra.len or node.c > self.module.types.extra.len - node.b) return error.InvalidArtifact;
            for (self.module.types.list(.{ .start = node.b, .len = node.c }), 0..) |binder, ordinal| {
                if (binder >= self.module.types.nodes.len) return error.InvalidArtifact;
                const bound = self.module.types.node(binder);
                if (bound.tag != .bound or bound.c != 0 or bound.a != ordinal or (bound.b != 0 and bound.b != 2)) return error.InvalidArtifact;
                if (bound.b != 2) continue;
                if (self.region_count == self.regions.len) return error.InvalidArtifact;
                self.regions[self.region_count] = binder;
                self.region_bindings[self.region_count] = 0;
                self.region_count += 1;
            }
            current = node.a;
        }
    }
    fn reference(self: *Walker, catalog: u32, source: u32) Error!void {
        if (catalog >= self.module.references.len) return error.InvalidArtifact;
        const ref = self.module.references[catalog];
        try self.liveLoans(self.module.nodes[source].ty, 0);

        if (ref.unit != 0 and ref.unit != self.module.unit) {
            // An imported affine global is not a fresh owning path per read.
            if (try self.affine(self.module.nodes[source].ty)) return error.InvalidArtifact;
            return;
        }
        try self.use(ref.binding, source);
    }
    fn pattern(self: *Walker, source: u32, depth: usize) Error!void {
        try self.charge(depth);
        if (source == 0 or source >= self.module.patterns.len) return error.InvalidArtifact;
        const node = self.module.patterns[source];
        switch (node.tag) {
            .bind => try self.introduce(node.a),
            .constructor => if (node.b != 0) {
                try self.pattern(node.b, depth + 1);
            },
            .product => for (self.module.extra[node.a..][0..node.b]) |child| {
                try self.pattern(child, depth + 1);
            },
            else => {},
        }
    }
    fn branches(self: *Walker, left: u32, right: u32, depth: usize) Error!Outcome {
        const count = self.len;
        const mark = self.snapshot_len;
        defer self.snapshot_len = mark;
        const before = try self.snapshot();
        const left_flow = try self.expression(left, depth + 1);
        self.len = count;
        const after = try self.snapshot();
        @memcpy(self.states[0..count], before[0..count]);
        var right_flow: Outcome = .live;
        if (right != 0) right_flow = try self.expression(right, depth + 1);
        self.len = count;
        for (self.states[0..count], after[0..count]) |*entry, first| {
            if (right_flow == .exit) entry.* = first else if (left_flow != .exit and entry.first == 0) entry.first = first.first;
        }
        if (left_flow == .exit and right_flow == .exit) return .exit;
        return .live;
    }
    fn cases(self: *Walker, index: u32, depth: usize) Error!Outcome {
        const match = self.module.matches[index];
        for (self.module.extra[match.inputs.start..][0..match.inputs.len]) |input| _ = try self.expression(input, depth + 1);
        const count = self.len;
        const mark = self.snapshot_len;
        defer self.snapshot_len = mark;
        const before = try self.snapshot();
        const joined = try self.snapshot();
        var live = false;
        for (self.module.match_arms[match.arms.start..][0..match.arms.len]) |arm| {
            @memcpy(self.states[0..count], before[0..count]);
            for (self.module.pattern_rows[arm.rows.start..][0..arm.rows.len]) |row| for (self.module.extra[row.patterns.start..][0..row.patterns.len]) |pattern_| try self.pattern(pattern_, depth + 1);
            if (arm.guard != 0) {
                if (try self.expression(arm.guard, depth + 1) == .exit) {
                    self.len = count;
                    continue;
                }
                for (before[0..count], self.states[0..count]) |*entry, after| if (entry.first == 0) {
                    entry.first = after.first;
                };
                for (self.states[count..self.len]) |entry| if (entry.first != 0) return error.InvalidArtifact;
            }
            const flow = try self.expression(arm.body, depth + 1);
            self.len = count;
            if (flow == .live) {
                live = true;
                for (joined[0..count], self.states[0..count]) |*entry, after| if (entry.first == 0) {
                    entry.first = after.first;
                };
            }
        }
        @memcpy(self.states[0..count], joined[0..count]);
        if (!live) return .exit;
        return .live;
    }
    fn closure(self: *Walker, index: u32, ty: T.Id, affine_demand: bool, depth: usize) Error!void {
        if (index >= self.module.closures.len) return error.InvalidArtifact;
        const value = self.module.closures[index];
        const qualifier = self.module.types.node(ty);
        // A concurrent host contract is imported through an input boundary;
        // a source closure cannot manufacture it by changing its annotation.
        if (qualifier.tag == .usage and qualifier.b == @backingInt(T.UsageKind.concurrent)) return error.InvalidArtifact;
        const once = affine_demand or (qualifier.tag == .usage and qualifier.b == @backingInt(T.UsageKind.once));
        const count = self.len;
        // Discover physical free references, then check the closure in its new
        // environment. A claimed capture table cannot suppress a physical read.
        var found: [4096]bool = @splat(false);
        try self.capture(value.body, &found, depth + 1);
        for (found[0..count], self.states[0..count]) |captured, *entry| if (captured) {
            if (!once or entry.first != 0) return error.InvalidArtifact;
            entry.first = value.body;
        };
        const mark = self.snapshot_len;
        defer self.snapshot_len = mark;
        const saved = try self.snapshot();
        defer {
            self.len = count;
            @memcpy(self.states[0..count], saved[0..count]);
        }
        for (found[0..count], self.states[0..count]) |captured, *entry| if (captured) {
            entry.first = 0;
        };
        const region_count = self.region_count;
        defer self.region_count = region_count;
        const arrow = try self.quantified(ty);
        if (arrow.tag != .function) return error.InvalidArtifact;
        const outer_ambient = self.ambient;
        self.ambient = arrow.c;
        defer self.ambient = outer_ambient;
        const outer_returns = self.returns;
        const outer_breaks = self.breaks;
        self.returns = null;
        self.breaks = null;
        defer {
            self.returns = outer_returns;
            self.breaks = outer_breaks;
        }
        try self.introduce(value.parameter.binding);
        _ = try self.expression(value.body, depth + 1);
    }
    fn capturePattern(self: *Walker, id: core.PatternId, found: *[4096]bool, depth: usize) Error!void {
        try self.charge(depth);
        const pattern_ = self.module.pattern(id);
        switch (pattern_.tag) {
            .value => try self.capture(pattern_.a, found, depth + 1),
            .constructor, .record_payload => if (pattern_.b != 0) {
                try self.capturePattern(pattern_.b, found, depth + 1);
            },
            .product => for (self.module.patternChildren(id)) |child| try self.capturePattern(child, found, depth + 1),
            .wildcard, .bind, .constant => {},
            .invalid => return error.InvalidArtifact,
        }
    }
    const CaptureChildren = struct {
        walker: *Walker,
        found: *[4096]bool,
        depth: usize,
        pub fn append(self: *@This(), _: std.mem.Allocator, id: core.Id) (std.mem.Allocator.Error || error{PlanLimit})!void {
            if (id == 0) return;
            self.walker.capture(id, self.found, self.depth + 1) catch return error.PlanLimit;
        }
        pub fn appendSlice(self: *@This(), allocator: std.mem.Allocator, ids: []const core.Id) (std.mem.Allocator.Error || error{PlanLimit})!void {
            for (ids) |id| try self.append(allocator, id);
        }
    };
    fn capture(self: *Walker, source: u32, found: *[4096]bool, depth: usize) Error!void {
        try self.charge(depth);
        if (source == 0 or source >= self.module.nodes.len) return error.InvalidArtifact;
        const node = self.module.nodes[source];
        switch (node.tag) {
            .reference => {
                const actual_reference = self.module.reference(source);
                if (actual_reference.unit != 0 and actual_reference.unit != self.module.unit) return;
                for (self.states[0..self.len], 0..) |state_, index| if (state_.binding == actual_reference.binding) {
                    found[index] = true;
                };
                return;
            },
            .closure, .suspend_ => {
                if (node.a >= self.module.closures.len) return error.InvalidArtifact;
                return self.capture(self.module.closures[node.a].body, found, depth + 1);
            },
            .operation_value => {
                if (node.a >= self.module.operation_values.len or node.b != 0 or node.c != 0) return error.InvalidArtifact;
                const operation = self.module.operationValue(source);
                if (operation.capability != 0) try self.capture(operation.capability, found, depth + 1);
                if (operation.witness != 0) try self.capture(operation.witness, found, depth + 1);
                return;
            },
            .match => for (self.module.matchArms(source)) |arm| {
                for (self.module.armRows(arm)) |row| for (self.module.rowPatterns(row)) |pattern_| try self.capturePattern(pattern_, found, depth + 1);
            },
            .pattern_bind => try self.capturePattern(node.a, found, depth + 1),
            .loop => {
                const pattern_ = self.module.loopInfo(source).pattern;
                if (pattern_ != 0) try self.capturePattern(pattern_, found, depth + 1);
            },
            .request_loop => {
                const pattern_ = self.module.requestLoopInfo(source).completion_pattern;
                if (pattern_ != 0) try self.capturePattern(pattern_, found, depth + 1);
            },
            .invalid => return error.InvalidArtifact,
            else => {},
        }
        // Physical capture follows actual immutable operands, including state,
        // requests, resolvers and updates. The redundant capture list is never
        // consulted to establish absence of an affine or borrowed reference.
        var children: CaptureChildren = .{ .walker = self, .found = found, .depth = depth };
        @import("../eval/body_recipe.zig").appendChildren(&children, undefined, self.module, source, false) catch return error.InvalidArtifact;
    }
    noinline fn loanResult(self: *Walker, callback: core.ClosureInfo, depth: usize) Error!void {
        // The result-path owner proves captures, projections, aggregates and
        // aliases. A missing path recipe rejects rather than erasing the loan.
        {
            // The scratch frame exists only during result reconstruction; an
            // ordinary once/unique body no longer reserves this megabyte.
            var storage: [1024 * 1024]u8 align(@alignOf(usize)) = undefined;
            var buffer: std.heap.FixedBufferAllocator = .init(&storage);
            const allocator = buffer.allocator();
            const terms = @import("capability_contracts.zig");
            var paths: terms.Store = .{};
            defer paths.deinit(allocator);
            const result = (@import("capability_contract_core.zig").deriveClosure(allocator, &paths, self.module, callback) catch return error.InvalidArtifact) orelse return error.InvalidArtifact;
            // This graph's only formal is the fresh loan. All of its reachable
            // parameter paths would cross the scope boundary, including captures.
            var needed: [4096]bool = @splat(false);
            needed[result] = true;
            var index = paths.nodes.items.len;
            while (index != 0) {
                index -= 1;
                if (!needed[index]) continue;
                try self.charge(depth);
                const term = paths.nodes.items[index];
                if (term.tag == .parameter or term.tag == .unknown or term.tag == .authority) return error.InvalidArtifact;
                if (term.tag == .wrapped or term.tag == .project or term.tag == .elements) needed[term.a] = true;
                if (term.tag == .product or term.tag == .record or term.tag == .captures or term.tag == .join) for (paths.view().children(term), 0..) |child, slot| {
                    if (term.tag == .record and slot % 2 == 0) continue;
                    needed[child] = true;
                };
            }
        }
    }
    fn requireResourceEffect(self: *Walker) Error!void {
        for (self.module.types.rowLabels(self.ambient)) |label| {
            const operation = self.module.types.operation(label);
            if (operation.identity.unit == 0 and operation.identity.decl == 1 and operation.instance.unit == 0 and operation.instance.decl == 0 and operation.arguments.len == 0) return;
        }
        return error.InvalidArtifact;
    }
    fn resourceAcquire(self: *Walker, source: u32, depth: usize) Error!void {
        try self.requireResourceEffect();
        const node = self.module.node(source);
        if (node.c != 0 or self.module.node(node.a).tag != .closure or (self.module.node(node.b).tag != .closure and !@import("cleanup_contracts.zig").immutableHost(self.module, node.b))) return error.InvalidArtifact;
        const acquired = self.module.types.node(self.module.typeOf(node.a));
        const released = self.module.types.node(self.module.typeOf(node.b));
        if (acquired.tag != .usage or acquired.b != @backingInt(T.UsageKind.once) or acquired.c != 0 or released.tag != .usage or released.b != @backingInt(T.UsageKind.cleanup) or released.c != 0) return error.InvalidArtifact;
        const acquisition = self.module.types.node(acquired.a);
        const release = self.module.types.node(released.a);
        if (acquisition.tag != .function or acquisition.a != T.unit or release.tag != .function or release.b != T.unit or (release.c != 0 and !@import("cleanup_contracts.zig").hostNominal(&self.module.types, self.module.nominals, self.module.typeOf(node.b))) or !(@import("rank_equal.zig").equal(&self.module.types, release.a, acquisition.b, true) catch return error.InvalidArtifact) or !(@import("rank_equal.zig").equal(&self.module.types, node.ty, acquisition.b, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        const owner = self.module.types.node(acquisition.b);
        if (owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or owner.c != 0 or !@import("cleanup_contracts.zig").payloadNominal(&self.module.types, self.module.nominals, owner.a)) return error.InvalidArtifact;
        for ([_]u32{ node.a, node.b }) |callable| {
            if (@import("cleanup_contracts.zig").immutableHost(self.module, callable)) continue;
            const closure_ = self.module.closure(callable);
            const wrapper = self.module.types.node(self.module.typeOf(callable));
            const header = self.module.types.node(wrapper.a);
            if (!(@import("rank_equal.zig").equal(&self.module.types, header.a, closure_.parameter.ty, true) catch return error.InvalidArtifact) or (self.module.typeOf(closure_.body) != T.never and !(@import("rank_equal.zig").equal(&self.module.types, header.b, self.module.typeOf(closure_.body), true) catch return error.InvalidArtifact))) return error.InvalidArtifact;
        }
        @import("cleanup_contracts.zig").immutableTransferred(self.module, node.b) catch return error.InvalidArtifact;
        _ = try self.expression(node.a, depth + 1);
        _ = try self.expression(node.b, depth + 1);
    }
    fn resourceScope(self: *Walker, source: u32, depth: usize) Error!void {
        const node = self.module.node(source);
        var foreign = false;
        for (self.module.types.rowLabels(self.ambient)) |label| {
            const operation = self.module.types.operation(label);
            if (operation.identity.unit == 0 and operation.identity.decl == 1 and operation.instance.unit == 0 and operation.instance.decl == 0 and operation.arguments.len == 0) foreign = true;
        }
        if (!foreign) return error.InvalidArtifact;
        if (self.module.node(node.a).tag != .closure or (self.module.node(node.b).tag != .closure and !@import("cleanup_contracts.zig").immutableHost(self.module, node.b)) or self.module.node(node.c).tag != .closure) return error.InvalidArtifact;
        const acquired = self.module.types.node(self.module.typeOf(node.a));
        const released = self.module.types.node(self.module.typeOf(node.b));
        const called = self.module.types.node(self.module.typeOf(node.c));
        if (acquired.tag != .usage or acquired.b != @backingInt(T.UsageKind.once) or acquired.c != 0 or released.tag != .usage or released.b != @backingInt(T.UsageKind.cleanup) or released.c != 0 or called.tag != .usage or called.b != @backingInt(T.UsageKind.once) or called.c != 0) return error.InvalidArtifact;
        const acquisition = self.module.types.node(acquired.a);
        const release = self.module.types.node(released.a);
        const callback = self.module.closure(node.c);
        const parameter = self.module.types.node(callback.parameter.ty);
        if (acquisition.tag != .function or acquisition.a != T.unit or release.tag != .function or release.b != T.unit or !(@import("rank_equal.zig").equal(&self.module.types, release.a, acquisition.b, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        const owner = self.module.types.node(acquisition.b);
        if (owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or parameter.tag != .usage or parameter.b != @backingInt(T.UsageKind.borrow_mut) or !(@import("rank_equal.zig").equal(&self.module.types, parameter.a, owner.a, true) catch return error.InvalidArtifact) or parameter.c == 0) return error.InvalidArtifact;
        if (!@import("cleanup_contracts.zig").payloadNominal(&self.module.types, self.module.nominals, owner.a) or (release.c != 0 and !@import("cleanup_contracts.zig").hostNominal(&self.module.types, self.module.nominals, self.module.typeOf(node.b)))) return error.InvalidArtifact;
        for ([_]u32{ node.a, node.b }) |callable| {
            if (@import("cleanup_contracts.zig").immutableHost(self.module, callable)) continue;
            const closure_ = self.module.closure(callable);
            const wrapper = self.module.types.node(self.module.typeOf(callable));
            const header = self.module.types.node(wrapper.a);
            if (!(@import("rank_equal.zig").equal(&self.module.types, header.a, closure_.parameter.ty, true) catch return error.InvalidArtifact) or (self.module.typeOf(closure_.body) != T.never and !(@import("rank_equal.zig").equal(&self.module.types, header.b, self.module.typeOf(closure_.body), true) catch return error.InvalidArtifact))) return error.InvalidArtifact;
        }
        const body_arrow = self.module.types.node(called.a);
        if (body_arrow.tag != .function or !(@import("rank_equal.zig").equal(&self.module.types, body_arrow.a, callback.parameter.ty, true) catch return error.InvalidArtifact) or !(@import("rank_equal.zig").equal(&self.module.types, body_arrow.b, node.ty, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        const region = self.module.types.node(parameter.c);
        if (region.tag != .bound or region.a != 0 or region.b != 2 or region.c != callback.parameter.binding) return error.InvalidArtifact;
        @import("cleanup_contracts.zig").immutable(self.module, node.b) catch return error.InvalidArtifact;
        try self.loanResult(callback, depth);
        _ = try self.expression(node.a, depth + 1);
        _ = try self.expression(node.b, depth + 1);
        if (self.region_count == self.regions.len) return error.InvalidArtifact;
        self.regions[self.region_count] = parameter.c;
        self.region_bindings[self.region_count] = callback.parameter.binding;
        self.region_count += 1;
        defer self.region_count -= 1;
        _ = try self.expression(node.c, depth + 1);
    }
    fn loan(self: *Walker, source: u32, depth: usize) Error!void {
        const node = self.module.node(source);
        if (node.c > 1 or self.module.node(node.b).tag != .closure) return error.InvalidArtifact;
        const callback = self.module.closure(node.b);
        const qualified = self.module.types.node(self.module.typeOf(node.b));
        if (qualified.tag != .usage or qualified.b != @backingInt(T.UsageKind.once) or qualified.c != 0) return error.InvalidArtifact;
        const header = self.module.types.node(qualified.a);
        if (header.tag != .function or !(@import("rank_equal.zig").equal(&self.module.types, header.a, callback.parameter.ty, true) catch return error.InvalidArtifact) or !(@import("rank_equal.zig").equal(&self.module.types, header.b, node.ty, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        const owner = self.module.types.node(self.module.types.head(self.module.typeOf(node.a), 0));
        const parameter = self.module.types.node(self.module.types.head(callback.parameter.ty, 0));
        if (owner.tag != .usage or (owner.b != @backingInt(T.UsageKind.unique) and owner.b != @backingInt(T.UsageKind.borrow_mut) and (node.c != 0 or (owner.b != @backingInt(T.UsageKind.shared) and owner.b != @backingInt(T.UsageKind.borrow))))) return error.InvalidArtifact;
        var kind: T.UsageKind = .borrow;
        if (node.c != 0) kind = .borrow_mut;
        if (parameter.tag != .usage or parameter.b != @backingInt(kind) or !(@import("rank_equal.zig").equal(&self.module.types, parameter.a, owner.a, true) catch return error.InvalidArtifact) or parameter.c == 0) return error.InvalidArtifact;
        const region = self.module.types.node(parameter.c);
        if (region.tag != .bound or region.a != 0 or region.b != 2 or region.c != callback.parameter.binding) return error.InvalidArtifact;
        try self.loanResult(callback, depth);
        try self.liveLoans(self.module.typeOf(node.a), depth + 1);
        if (self.region_count == self.regions.len) return error.InvalidArtifact;
        self.regions[self.region_count] = parameter.c;
        self.region_bindings[self.region_count] = callback.parameter.binding;
        self.region_count += 1;
        defer self.region_count -= 1;
        var binding: u32 = 0;
        if (self.module.node(node.a).tag == .reference) {
            const reference_ = self.module.reference(node.a);
            if (reference_.unit == 0 or reference_.unit == self.module.unit) binding = reference_.binding;
        }
        if (self.state(binding)) |entry| {
            if (entry.first != 0 or entry.loan != 0) return error.InvalidArtifact;
            entry.loan = source;
        } else _ = try self.expression(node.a, depth + 1);
        defer if (self.state(binding)) |entry| {
            entry.loan = 0;
        };
        _ = try self.expression(node.b, depth + 1);
    }
    fn restoreStage(self: *Walker, environment: StageEnvironment) void {
        self.len = environment.states.len;
        @memcpy(self.states[0..self.len], environment.states);
        self.region_count = environment.regions.len;
        @memcpy(self.regions[0..self.region_count], environment.regions);
        @memcpy(self.region_bindings[0..self.region_count], environment.bindings);
        self.ambient = environment.ambient;
        self.returns = environment.returns;
        self.breaks = environment.breaks;
        self.earlier = environment.earlier;
    }
    fn earlierOperand(self: *Walker, source: u32, depth: usize) Error!Outcome {
        const earlier = self.earlier orelse return error.InvalidArtifact;
        const mark = self.snapshot_len;
        const saved = try self.snapshot();
        const count = self.region_count;
        var regions: [128]T.Id = undefined;
        var bindings: [128]u32 = undefined;
        @memcpy(regions[0..count], self.regions[0..count]);
        @memcpy(bindings[0..count], self.region_bindings[0..count]);
        const future: StageEnvironment = .{ .states = saved, .regions = regions[0..count], .bindings = bindings[0..count], .ambient = self.ambient, .returns = self.returns, .breaks = self.breaks, .earlier = self.earlier };
        defer {
            self.restoreStage(future);
            self.snapshot_len = mark;
        }
        self.restoreStage(earlier.*);
        // Construction is pure and cannot return or break into a future body.
        self.ambient = 0;
        self.returns = null;
        self.breaks = null;
        const outcome = try self.expression(source, depth + 1);
        if (outcome != .live or self.len != earlier.states.len) return error.InvalidArtifact;
        @memcpy(earlier.states, self.states[0..self.len]);
        return .live;
    }
    fn staging(self: *Walker, source: u32, depth: usize) Error!Outcome {
        const node = self.module.node(source);
        const typed = @import("typed_staging.zig");
        const operation: typed.Op = @fromBackingInt(node.c);
        if (operation == .lift or operation == .splice) return self.earlierOperand(node.a, depth + 1);
        if (operation != .quote) {
            if (try self.expression(node.a, depth + 1) == .exit) return .exit;
            return self.expression(node.b, depth + 1);
        }
        const shape = typed.codeInfo(&self.module.types, node.ty) orelse return error.InvalidArtifact;
        const mark = self.snapshot_len;
        const saved = try self.snapshot();
        const region_count = self.region_count;
        var regions: [128]T.Id = undefined;
        var bindings: [128]u32 = undefined;
        @memcpy(regions[0..region_count], self.regions[0..region_count]);
        @memcpy(bindings[0..region_count], self.region_bindings[0..region_count]);
        var earlier: StageEnvironment = .{ .states = saved, .regions = regions[0..region_count], .bindings = bindings[0..region_count], .ambient = self.ambient, .returns = self.returns, .breaks = self.breaks, .earlier = self.earlier };
        defer {
            self.restoreStage(earlier);
            self.snapshot_len = mark;
        }
        // Future owners are introduced by their own executable graph. A live
        // earlier-stage move or loan cannot supply a missing future owner.
        self.len = 0;
        self.region_count = 0;
        self.ambient = shape.effects;
        self.returns = null;
        self.breaks = null;
        self.earlier = &earlier;
        _ = try self.expression(node.a, depth + 1);
        return .live;
    }
    fn expression(self: *Walker, source: u32, depth: usize) Error!Outcome {
        if (source == 0) return .live;
        try self.charge(depth);
        if (source >= self.module.nodes.len) return error.InvalidArtifact;
        const node = self.module.nodes[source];
        if (node.ty >= self.module.types.nodes.len) return error.InvalidArtifact;
        try self.liveLoans(node.ty, depth + 1);
        switch (node.tag) {
            .staging => return self.staging(source, depth + 1),
            .constant, .primitive_function, .constructor_function, .type_constructor, .panic => {},
            .resource_acquire => try self.resourceAcquire(source, depth + 1),
            .resource_release => {
                try self.requireResourceEffect();
                const owner = self.module.types.node(self.module.typeOf(node.a));
                if (node.b != 0 or node.c != 0 or node.ty != T.unit or owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or owner.c != 0 or !@import("cleanup_contracts.zig").payloadNominal(&self.module.types, self.module.nominals, owner.a)) return error.InvalidArtifact;
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
            },
            .resource_scope => try self.resourceScope(source, depth + 1),
            .effect_scope => {
                if (node.op != .none or node.b != 0 or node.c != 0 or node.a == 0 or node.a >= self.module.nodes.len) return error.InvalidArtifact;
                const callback = self.module.node(node.a);
                if (callback.tag != .closure or callback.a >= self.module.closures.len or callback.ty >= self.module.types.nodes.len) return error.InvalidArtifact;
                const closure_ = self.module.closures[callback.a];
                if (closure_.parameter.ty >= self.module.types.nodes.len) return error.InvalidArtifact;
                const header = self.module.types.node(callback.ty);
                if (header.tag != .function or header.a >= self.module.types.nodes.len or header.b >= self.module.types.nodes.len or self.module.types.node(closure_.parameter.ty).tag != .scoped) return error.InvalidArtifact;
                if (!(@import("rank_equal.zig").equalWithBudget(&self.module.types, header.a, closure_.parameter.ty, true, &self.remaining) catch return error.InvalidArtifact) or !(@import("rank_equal.zig").equalWithBudget(&self.module.types, header.b, node.ty, true, &self.remaining) catch return error.InvalidArtifact)) return error.InvalidArtifact;
                _ = try self.expression(node.a, depth + 1);
            },
            .usage_borrow => try self.loan(source, depth + 1),
            .effect_provider, .handle => {
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                if (try self.expression(node.b, depth + 1) == .exit) return .exit;
            },
            .state_provider => {
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                // Ordinary provider storage cannot erase a linear initial
                // state. Its scalar/data state still follows the actual move.
                if (try self.affine(self.module.typeOf(node.c))) return error.InvalidArtifact;
                if (try self.expression(node.c, depth + 1) == .exit) return .exit;
            },
            .usage_share => {
                const owner = self.module.types.node(self.module.typeOf(node.a));
                const shared = self.module.types.node(node.ty);
                if (node.b != 0 or node.c != 0 or owner.tag != .usage or owner.b != @backingInt(T.UsageKind.unique) or owner.c != 0 or shared.tag != .usage or shared.b != @backingInt(T.UsageKind.shared) or shared.c != 0 or !@import("cleanup_contracts.zig").payloadNominal(&self.module.types, self.module.nominals, owner.a) or !(@import("rank_equal.zig").equal(&self.module.types, owner.a, shared.a, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
            },
            .usage_read => {
                try self.liveLoans(self.module.typeOf(node.a), depth + 1);
                const wrapper = self.module.types.node(self.module.typeOf(node.a));
                if (wrapper.tag != .usage or (wrapper.b != @backingInt(T.UsageKind.borrow) and wrapper.b != @backingInt(T.UsageKind.borrow_mut) and wrapper.b != @backingInt(T.UsageKind.shared))) return error.InvalidArtifact;
                const payload = self.module.types.node(wrapper.a);
                if (node.b == 0) {
                    if (payload.tag != .unit and payload.tag != .boolean and payload.tag != .u32 and payload.tag != .f32) return error.InvalidArtifact;
                    if (node.ty != wrapper.a) return error.InvalidArtifact;
                } else {
                    if ((node.b == 1 and payload.tag != .array) or (node.b == 2 and payload.tag != .list) or node.b > 2 or node.ty != T.u32_type) return error.InvalidArtifact;
                }
                const operand = self.module.node(node.a);
                if (operand.tag == .reference) {
                    const reference_ = self.module.reference(node.a);
                    if (reference_.unit == 0 or reference_.unit == self.module.unit) {
                        if (self.state(reference_.binding)) |entry| if (entry.first != 0 or entry.loan != 0) return error.InvalidArtifact;
                    }
                } else _ = try self.expression(node.a, depth + 1);
            },
            .reference => try self.reference(node.a, source),
            .apply, .scalar, .logical, .record_merge, .proof_guard => {
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                if (node.b != 0 and try self.expression(node.b, depth + 1) == .exit) return .exit;
                if (node.tag == .apply) {
                    const callee = try self.argumentArrow(self.module.typeOf(node.a));
                    if (callee.tag != .function) return error.InvalidArtifact;
                    try self.argument(node.b, callee.a, depth + 1);
                }
            },
            .call => {
                var callee = try self.argumentArrow(self.module.calls[node.a].callee_type);
                for (self.module.extra[node.b..][0..node.c]) |child| {
                    if (callee.tag != .function) return error.InvalidArtifact;
                    if (try self.expression(child, depth + 1) == .exit) return .exit;
                    try self.argument(child, callee.a, depth + 1);
                    callee = try self.argumentArrow(callee.b);
                }
            },
            .project, .force, .package_pack => {
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
            },
            .construct => {
                if (node.b != 0 and try self.expression(node.b, depth + 1) == .exit) return .exit;
            },
            .bind => {
                if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                try self.introduce(node.a);
            },
            .return_ => {
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                var frame = self.returns;
                while (frame) |target| : (frame = target.parent) if (target.target == node.b) {
                    self.record(target);
                    return .exit;
                };
                return error.InvalidArtifact;
            },
            .break_ => {
                for (self.module.extra[node.b..][0..node.c]) |child| if (try self.expression(child, depth + 1) == .exit) return .exit;
                const frame = self.breaks orelse return error.InvalidArtifact;
                if (frame.target != node.a) return error.InvalidArtifact;
                self.record(frame);
                return .exit;
            },
            .if_value, .if_stmt => {
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                return self.branches(node.b, node.c, depth + 1);
            },
            .block => return self.block(source, depth + 1),
            .task => {
                const operation = std.enums.fromInt(@import("task_types.zig").Op, node.c) orelse return error.InvalidArtifact;
                const operands = self.module.children(source);
                if (operation == .read or operation == .write) {
                    const owner = self.module.node(operands[0]);
                    if (owner.tag == .reference) {
                        const reference_ = self.module.reference(operands[0]);
                        if (reference_.unit == 0 or reference_.unit == self.module.unit) {
                            if (self.state(reference_.binding)) |entry| if (entry.first != 0 or entry.loan != 0) return error.InvalidArtifact;
                        }
                    } else if (try self.expression(operands[0], depth + 1) == .exit) return .exit;
                    for (operands[1..]) |child| if (try self.expression(child, depth + 1) == .exit) return .exit;
                } else for (operands) |child| if (try self.expression(child, depth + 1) == .exit) return .exit;
            },
            .suite, .product, .record, .array, .array_op => for (self.module.extra[node.a..][0..node.b]) |child| {
                if (try self.expression(child, depth + 1) == .exit) return .exit;
            },
            .match => return self.cases(node.a, depth + 1),
            .closure => try self.closure(node.a, node.ty, false, depth + 1),
            .suspend_ => {
                if (node.a >= self.module.closures.len or node.b != 0 or node.c != 0 or node.op != .none) return error.InvalidArtifact;
                const suspension = self.module.suspension(source);
                if (suspension.function_type == 0 or suspension.function_type >= self.module.types.nodes.len) return error.InvalidArtifact;
                const demand = self.module.types.node(node.ty);
                const arrow = self.module.types.node(suspension.function_type);
                if (demand.tag != .demand or arrow.tag != .function or arrow.a != T.unit or arrow.c != demand.c or !(@import("rank_equal.zig").equal(&self.module.types, arrow.b, demand.a, true) catch return error.InvalidArtifact)) return error.InvalidArtifact;
                // An affine cell moves its captures and is consumed on force.
                // Other cells retain the ordinary retryable many-body proof.
                try self.closure(node.a, suspension.function_type, try self.affine(node.ty), depth + 1);
            },
            .computation => {
                if (node.a == 0 or node.b != 0 or node.c != 0 or node.op != .none) return error.InvalidArtifact;
                _ = try self.expression(node.a, depth + 1);
            },
            .operation_value => {
                if (node.a >= self.module.operation_values.len or node.b != 0 or node.c != 0) return error.InvalidArtifact;
                const operation = self.module.operationValue(source);
                if (operation.capability != 0) _ = try self.expression(operation.capability, depth + 1);
            },
            .request_decision => {
                if (node.a > @backingInt(core.RequestDecisionKind.break_)) return error.InvalidArtifact;
                if (node.b != 0) _ = try self.expression(node.b, depth + 1);
                if (node.c != 0) _ = try self.expression(node.c, depth + 1);
                return .exit;
            },
            .request_loop => {
                if (node.a >= self.module.request_loops.len or node.b != 0 or node.c != 0 or node.op != .none) return error.InvalidArtifact;
                const loop = self.module.requestLoopInfo(source);
                if (loop.computation == 0 or loop.completion_body == 0 or loop.arms.start > self.module.request_arms.len or loop.arms.len > self.module.request_arms.len - loop.arms.start) return error.InvalidArtifact;
                _ = try self.expression(loop.computation, depth + 1);
                const count = self.len;
                const mark = self.snapshot_len;
                defer self.snapshot_len = mark;
                const before = try self.snapshot();
                for (self.module.requestArms(source)) |arm| {
                    _ = try self.expression(arm.callback, depth + 1);
                    for (self.states[0..count], before[0..count]) |after, prior| if (after.first != prior.first or after.loan != prior.loan) return error.InvalidArtifact;
                    self.len = count;
                }
                if (loop.carries.len != 0) return error.InvalidArtifact;
                if (loop.completion_pattern != 0) try self.pattern(loop.completion_pattern, depth + 1);
                _ = try self.expression(loop.completion_body, depth + 1);
                self.len = count;
            },
            .pattern_bind => {
                if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                if (node.c != 0) {
                    const count = self.len;
                    const mark = self.snapshot_len;
                    defer self.snapshot_len = mark;
                    const before = try self.snapshot();
                    _ = try self.expression(node.c, depth + 1);
                    self.len = count;
                    @memcpy(self.states[0..count], before);
                }
                try self.pattern(node.a, depth + 1);
            },
            .package_unpack => {
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                try self.introduce(node.b);
                return self.expression(self.module.extra[node.c], depth + 1);
            },
            .loop => {
                const loop = self.module.loops[node.a];
                if (try self.expression(loop.first, depth + 1) == .exit) return .exit;
                if (try self.expression(loop.end, depth + 1) == .exit) return .exit;
                const count = self.len;
                const mark = self.snapshot_len;
                defer self.snapshot_len = mark;
                const before = try self.snapshot();
                var frame: ExitFrame = .{ .target = source, .joined = try self.snapshot() };
                const outer_breaks = self.breaks;
                self.breaks = &frame;
                defer self.breaks = outer_breaks;
                if (loop.pattern != 0) try self.pattern(loop.pattern, depth + 1);
                const flow = try self.expression(loop.body, depth + 1);
                self.len = count;
                const single = self.singleIteration(loop);
                if (flow == .live and !single) for (self.states[0..count], before[0..count]) |after, prior| if (after.first != prior.first) return error.InvalidArtifact;
                if (flow == .live and single) self.record(&frame);
                @memcpy(self.states[0..count], frame.joined);
                if ((loop.kind == .forever or single) and !frame.seen) return .exit;
            },
            else => return error.InvalidArtifact,
        }
        return .live;
    }
};
fn relevant(module: *const core.Module, body: core.Body) Error!bool {
    if (usage.containsNominal(&module.types, module.nominals, module.bindings[body.binding].ty) catch return error.InvalidArtifact) return true;
    // Relevance comes from executable edges, never diagnostic source spans.
    // Both this preflight and the ownership pass have finite private storage.
    var storage: [1024 * 1024]u8 align(@alignOf(usize)) = undefined;
    var buffer: std.heap.FixedBufferAllocator = .init(&storage);
    const allocator = buffer.allocator();
    var walk: @import("../eval/body_recipe.zig").Walk = .{};
    defer walk.deinit(allocator);
    walk.append(allocator, body.root) catch return error.InvalidArtifact;
    while (walk.next(allocator) catch return error.InvalidArtifact) |id| {
        if (walk.count > 65_536) return error.InvalidArtifact;
        const node = module.nodes[id];
        if (node.ty >= module.types.nodes.len) return error.InvalidArtifact;
        if (usage.containsNominal(&module.types, module.nominals, node.ty) catch return error.InvalidArtifact) return true;
        if (node.tag == .closure or node.tag == .suspend_) {
            if (node.a >= module.closures.len) return error.InvalidArtifact;
            walk.append(allocator, module.closures[node.a].body) catch return error.InvalidArtifact;
        }
        if (node.tag == .computation and (node.a == 0 or node.a >= module.nodes.len)) return error.InvalidArtifact;
        if (node.tag == .request_loop) {
            if (node.a >= module.request_loops.len) return error.InvalidArtifact;
            const loop = module.requestLoopInfo(id);
            if (loop.computation == 0 or loop.completion_body == 0 or loop.arms.start > module.request_arms.len or loop.arms.len > module.request_arms.len - loop.arms.start) return error.InvalidArtifact;
        }
        @import("../eval/body_recipe.zig").appendChildren(&walk, allocator, module, id, true) catch return error.InvalidArtifact;
    }
    return false;
}
fn nominalFacts(module: *const core.Module) Error!void {
    if (module.nominals.len > 4096) return error.InvalidArtifact;
    var storage: [4096]core.Nominal = undefined;
    const facts = storage[0..module.nominals.len];
    @memcpy(facts, module.nominals);
    for (facts) |*nominal| if (nominal.identity.unit == module.unit) {
        nominal.affine = false;
        nominal.has_usage = false;
    };
    var work: usage.Work = .{};
    for (module.types.nodes) |node| usage.nominalShape(&module.types, facts, node, &work) catch return error.InvalidArtifact;
    for (0..facts.len) |_| {
        work.charge(1) catch return error.InvalidArtifact;
        var changed = false;
        for (module.constructors) |constructor| {
            work.charge(1) catch return error.InvalidArtifact;
            if (constructor.nominal >= facts.len or constructor.payload >= module.types.nodes.len) return error.InvalidArtifact;
            if (constructor.payload == 0 or facts[constructor.nominal].identity.unit != module.unit) continue;
            const nominal = &facts[constructor.nominal];
            if (!nominal.affine and (usage.affineNominalWork(&module.types, facts, constructor.payload, &work) catch return error.InvalidArtifact)) {
                nominal.affine = true;
                changed = true;
            }
            if (!nominal.has_usage and (usage.containsNominalWork(&module.types, facts, constructor.payload, &work) catch return error.InvalidArtifact)) {
                nominal.has_usage = true;
                changed = true;
            }
        }
        if (!changed) break;
    }
    for (facts, module.nominals) |proved, declared| if (proved.affine != declared.affine or proved.has_usage != declared.has_usage) return error.InvalidArtifact;
}
fn formalRegion(module: *const core.Module, id: T.Id, remaining: *usize) bool {
    for (module.types.nodes) |node| {
        if (remaining.* == 0) return false;
        remaining.* -= 1;
        if (node.tag != .forall or node.c > 128 or node.b > module.types.extra.len or node.c > module.types.extra.len - node.b) continue;
        for (module.types.list(.{ .start = node.b, .len = node.c }), 0..) |binder, ordinal| {
            if (remaining.* == 0) return false;
            remaining.* -= 1;
            if (binder != id) continue;
            if (binder >= module.types.nodes.len) return false;
            const bound = module.types.node(binder);
            if (bound.tag == .bound and bound.b == 2 and bound.c == 0 and bound.a == ordinal) return true;
        }
    }
    return false;
}
fn validateRegions(module: *const core.Module) Error!void {
    var bindings: [4096]u32 = undefined;
    var count: usize = 0;
    var remaining: usize = 65_536;
    for (module.nodes) |node| {
        if (remaining == 0) return error.InvalidArtifact;
        remaining -= 1;
        if (node.tag != .usage_borrow and node.tag != .resource_scope) continue;
        var callable = node.b;
        if (node.tag == .resource_scope) callable = node.c;
        if (count == bindings.len or callable >= module.nodes.len or module.node(callable).tag != .closure) return error.InvalidArtifact;
        const callback = module.closure(callable);
        for (bindings[0..count]) |binding| if (binding == callback.parameter.binding) return error.InvalidArtifact;
        bindings[count] = callback.parameter.binding;
        count += 1;
    }
    for (module.types.nodes, 0..) |node, type_index| {
        if (remaining == 0) return error.InvalidArtifact;
        remaining -= 1;
        if (node.tag == .bound and node.b == 2) {
            var owned = false;
            for (bindings[0..count]) |binding| if (binding == node.c) {
                owned = true;
                break;
            };
            if (node.c == 0) {
                if (!formalRegion(module, @intCast(type_index), &remaining)) return error.InvalidArtifact;
            } else if (!owned or node.a != 0) return error.InvalidArtifact;
        }
        if (node.tag == .usage) {
            if (node.b == @backingInt(T.UsageKind.concurrent) and !@import("task_types.zig").concurrentHost(&module.types, node.a)) return error.InvalidArtifact;
            const loan = node.b == @backingInt(T.UsageKind.borrow) or node.b == @backingInt(T.UsageKind.borrow_mut);
            if (loan != (node.c != 0)) return error.InvalidArtifact;
            if (loan) {
                if (node.c >= module.types.nodes.len) return error.InvalidArtifact;
                const region = module.types.node(node.c);
                if (region.tag != .bound or region.b != 2) return error.InvalidArtifact;
            }
            if (node.b == @backingInt(T.UsageKind.shared) and (usage.affineNominal(&module.types, module.nominals, node.a) catch return error.InvalidArtifact)) return error.InvalidArtifact;
        }
        // Region binders are identities, never ordinary data endpoints.
        var edges: [2]T.Id = .{ node.a, node.b };
        var values: []const T.Id = &.{};
        switch (node.tag) {
            .function => values = &edges,
            .usage, .array, .list, .cursor, .demand, .resolver, .provider, .scoped => values = edges[0..1],
            .product => values = module.types.list(.{ .start = node.a, .len = node.b }),
            .nominal => values = module.types.nominalArguments(node),
            .record => for (0..node.b) |index| {
                const field = module.types.node(module.types.recordField(node, index).ty);
                if (field.tag == .bound and field.b == 2) return error.InvalidArtifact;
            },
            else => {},
        }
        for (values) |edge| {
            const child = module.types.node(edge);
            if (child.tag == .bound and child.b == 2) return error.InvalidArtifact;
        }
    }
}
fn packageWitnesses(module: *const core.Module) Error!void {
    var work: usage.Work = .{};
    for (module.nodes) |node| {
        work.charge(1) catch return error.InvalidArtifact;
        if (node.tag != .package_pack) continue;
        if (node.b > module.types.extra.len or node.c > module.types.extra.len - node.b) return error.InvalidArtifact;
        for (module.types.list(.{ .start = node.b, .len = node.c })) |witness| {
            // A plain type binder has no authority to hide an owner, even if
            // the witness is phantom and therefore absent from the payload.
            if (usage.containsNominalWork(&module.types, module.nominals, witness, &work) catch return error.InvalidArtifact) return error.InvalidArtifact;
        }
    }
}
pub fn physicallyCaptures(module: *const core.Module, root: core.Id, binding: core.BindingId, remaining: *usize) Error!bool {
    var walker: Walker = .{ .module = module, .len = 1, .remaining = @min(remaining.*, 65_536) };
    const budget = walker.remaining;
    defer remaining.* -= budget - walker.remaining;
    walker.states[0] = .{ .binding = binding };
    var found: [4096]bool = @splat(false);
    try walker.capture(root, &found, 0);
    return found[0];
}
pub fn validate(module: *const core.Module) Error!void {
    try @import("closed_nominal_storage.zig").validate(module);
    for (module.nominals) |nominal| {
        if (nominal.affine and !nominal.has_usage) return error.InvalidArtifact;
        if (nominal.has_usage and !module.has_usage_contracts) return error.InvalidArtifact;
    }
    if (!module.has_usage_contracts) return;
    for (module.nodes) |node| if (node.ty >= module.types.nodes.len) return error.InvalidArtifact;
    try nominalFacts(module);
    try packageWitnesses(module);
    try validateRegions(module);
    try @import("cleanup_contracts.zig").validate(module);
    var walker: Walker = .{ .module = module };
    for (module.bodies) |body| {
        if (body.root == 0) continue;
        walker.len = 0;
        walker.snapshot_len = 0;
        walker.remaining = 65_536;
        walker.ambient = 0;
        walker.region_count = 0;
        var header = try walker.quantified(module.bindings[body.binding].ty);
        for (module.parameters[body.parameters.start..][0..body.parameters.len]) |_| {
            if (header.tag != .function) return error.InvalidArtifact;
            walker.ambient = header.c;
            header = module.types.node(header.b);
        }
        var required = try relevant(module, body);
        for (module.parameters[body.parameters.start..][0..body.parameters.len]) |parameter| {
            try walker.introduce(parameter.binding);
            required = required or walker.len != 0;
        }
        // Ordinary functions in a module with usage declarations preserve the
        // previous contract. A qualified result or input is checked separately.
        if (required) _ = try walker.expression(body.root, 0);
    }
}
