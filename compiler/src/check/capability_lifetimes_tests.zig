const std = @import("std");
const C = @import("core.zig");
const lifetime = @import("capability_lifetimes.zig");
const a = std.testing.allocator;
const header = "type State a is effect = {get: Unit -> a, set: a -> Unit}\n";
fn lower(allocator: std.mem.Allocator, source: []const u8) !C.Module {
    var tokens = try @import("../parse/lexer.zig").lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try @import("check.zig").checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("lifetime source {s} at {d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(0, checked.diagnostics.len);
    return C.lower(allocator, &tree, &names, &checked);
}
fn entry(module: *const C.Module) !u32 {
    for (module.bodies) |body| if (body.exported) return body.binding;
    return error.MissingEntry;
}
fn rejected(allocator: std.mem.Allocator, module: *const C.Module) !void {
    var result = lifetime.analyze(allocator, module, &.{}, .{ .binding = try entry(module) }) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.LifetimeEscape, err);
        try rejectCore(allocator, module);
        return;
    };
    defer result.deinit(allocator);
    return error.ExpectedLifetimeRejection;
}
fn directScope(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, header ++ "entry const answer = func () => return @effect.scope (func (s: State U32) => return do:\n  let ignored = s\n  break 42\n)\n");
    defer module.deinit(allocator);
    var result = try lifetime.analyze(allocator, &module, &.{}, .{ .binding = try entry(&module) });
    defer result.deinit(allocator);
    try std.testing.expect(result.complete);
    try lifetime.rejectSupportedEscapes(allocator, &module, &.{});
    try std.testing.expectEqual(2, result.boundaries.len);
    var tested: usize = 0;
    for (module.nodes) |node| {
        if (node.tag != .effect_scope) continue;
        const closure = &module.closures[module.node(node.a).a];
        const original = closure.body;
        for (module.nodes, 0..) |candidate, id| {
            if (candidate.tag != .reference) continue;
            if (module.reference(@intCast(id)).binding != closure.parameter.binding) continue;
            closure.body = @intCast(id);
            break;
        }
        try std.testing.expect(closure.body != original);
        try rejected(allocator, &module);
        closure.body = original;
        tested += 1;
        break;
    }
    try std.testing.expectEqual(1, tested);
}
test "immutable scope lifetime graph reconstructs fresh owners and rejects returned authority through OOM" {
    try directScope(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, directScope, .{});
}

const box = "type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}\n";
const local_state = header ++ box ++
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    use Box.set (func () => return do:
    \\      let (state, value) = do (@effect.state s.get s.set 7):
    \\        break s.get ()
    \\      break value
    \\    )
    \\    use callback <- Box.get ()
    \\    break callback ()
    \\  break result
    \\)
;
const older_state = header ++ box ++
    \\entry const answer = func () => return do:
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    break @effect.scope (func (s: State U32) => return do:
    \\      let ignored = s
    \\      use previous <- Box.get ()
    \\      use Box.set (func () => return 0)
    \\      break previous ()
    \\    )
    \\  break result
;
fn stateLaw(allocator: std.mem.Allocator) !void {
    var local = try lower(allocator, local_state);
    defer local.deinit(allocator);
    var result = try lifetime.analyze(allocator, &local, &.{&local}, .{ .binding = try entry(&local) });
    defer result.deinit(allocator);
    try std.testing.expect(result.complete);
    var cells: usize = 0;
    var stores: usize = 0;
    for (result.nodes) |node| if (node.kind == .cell) {
        cells += 1;
    };
    for (result.edges) |edge| if (edge.kind == .store) {
        stores += 1;
    };
    try std.testing.expect(cells != 0 and stores != 0);
    var older = try lower(allocator, older_state);
    defer older.deinit(allocator);
    var seed = try lifetime.analyze(allocator, &older, &.{}, .{ .binding = try entry(&older) });
    defer seed.deinit(allocator);
    var receiver: C.Id = 0;
    var scope_callback: C.Id = 0;
    for (older.nodes) |node| if (node.tag == .effect_scope) {
        scope_callback = node.a;
        const parameter = older.closures[older.node(node.a).a].parameter.binding;
        for (older.nodes, 0..) |candidate, id| if (candidate.tag == .reference and older.reference(@intCast(id)).binding == parameter) {
            receiver = @intCast(id);
            break;
        };
    };
    try std.testing.expect(receiver != 0);
    var changed = false;
    for (older.nodes, 0..) |node, id| {
        if (node.tag != .closure or id == scope_callback or older.spans[id].start <= older.spans[scope_callback].start) continue;
        const closure = &older.closures[node.a];
        if (older.node(closure.body).tag != .constant) continue;
        // The actual body gains a free read; the forged empty capture catalog
        // must not erase its dependency when it is written to the older cell.
        const original = closure.body;
        closure.body = receiver;
        try rejected(allocator, &older);
        closure.body = original;
        changed = true;
        break;
    }
    try std.testing.expect(changed);
}
test "immutable lifetime State installations own exact store lifetimes and rederive omitted captures through OOM" {
    try stateLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stateLaw, .{});
}

fn graphReaches(report: *const lifetime.Report, from: lifetime.Id, target: lifetime.Id) bool {
    var seen: [4096]bool = @splat(false);
    var pending: [4096]lifetime.Id = undefined;
    var count: usize = 1;
    pending[0] = from;
    seen[from] = true;
    while (count != 0) {
        count -= 1;
        const current = pending[count];
        if (current == target) return true;
        const node = report.nodes[current];
        if ((node.kind == .memo or node.kind == .cell) and !seen[node.contents]) {
            seen[node.contents] = true;
            pending[count] = node.contents;
            count += 1;
        }
        var cursor = node.first_edge;
        while (cursor) |index| {
            const edge = report.edges[index];
            cursor = edge.next;
            if (edge.kind == .store or edge.kind == .call or seen[edge.to]) continue;
            seen[edge.to] = true;
            pending[count] = edge.to;
            count += 1;
        }
    }
    return false;
}
fn cycleLaw(allocator: std.mem.Allocator) !void {
    const source = @import("fixtures").source("provider-fixtures/lifetime-cost.blot");
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    var boundary: u32 = 0;
    for (module.source_names) |name| if (std.mem.startsWith(u8, source[name.point..], "cycle =")) {
        boundary = name.binding;
        break;
    };
    try std.testing.expect(boundary != 0);
    var result = try lifetime.analyze(allocator, &module, &.{}, .{ .binding = boundary });
    defer result.deinit(allocator);
    try std.testing.expect(result.complete);
    var memo: lifetime.Id = 0;
    var memos: usize = 0;
    var cells: usize = 0;
    for (result.nodes, 0..) |node, index| {
        try std.testing.expect(node.context < result.invocations.len);
        if (node.kind == .memo and node.ready and node.contents != 0) {
            memo = @intCast(index);
            memos += 1;
        }
        if (node.kind == .cell) cells += 1;
    }
    try std.testing.expectEqual(1, memos);
    try std.testing.expectEqual(1, cells);
    var members: usize = 0;
    for (result.nodes, 0..) |_, id| if (graphReaches(&result, memo, @intCast(id)) and graphReaches(&result, @intCast(id), memo)) {
        members += 1;
    };
    try std.testing.expectEqual(3, members);
    for (result.invocations[1..], 1..) |invocation, index| {
        try std.testing.expect(invocation.parent.? < index);
        const callable = result.nodes[invocation.callable];
        try std.testing.expect(callable.target != null and callable.signature != null);
        try std.testing.expect(callable.target.?.binding != 0);
        try std.testing.expect(callable.mappings.start + callable.mappings.len <= result.mappings.len);
    }
    // A wrong tag cannot keep the original SCC authority. This malformed
    // payload/tag pair is rejected before graph traversal, independently of
    // diagnostic origins or an unchanged physical layout.
    var changed = false;
    for (module.nodes) |*node| if (node.tag == .construct and node.b != 0) {
        const nominal = module.constructors[node.a].nominal;
        for (module.constructors, 0..) |constructor, catalog| if (catalog != 0 and constructor.nominal == nominal and constructor.payload == 0) {
            const prior = node.a;
            node.a = @intCast(catalog);
            var invalid = lifetime.analyze(allocator, &module, &.{}, .{ .binding = boundary }) catch |err| {
                node.a = prior;
                if (err == error.OutOfMemory) return err;
                try std.testing.expectEqual(error.InvalidArtifact, err);
                changed = true;
                break;
            };
            defer invalid.deinit(allocator);
            return error.ExpectedTagRejection;
        };
        if (changed) break;
    };
    try std.testing.expect(changed);
}
test "immutable lifetime cycle report preserves constructor selection Memo cache and installed State edges through OOM" {
    try cycleLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, cycleLaw, .{});
}

const memo_source = header ++
    \\const delay = func ~value => return value
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let ignored = s
    \\  let pending = delay (do:
    \\    let discarded = 0
    \\    break 42
    \\  )
    \\  use finished <- @demand pending
    \\  break 42
    \\)
;
fn memoCaptureLaw(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, memo_source);
    defer module.deinit(allocator);
    var positive = try lifetime.analyze(allocator, &module, &.{}, .{ .binding = try entry(&module) });
    defer positive.deinit(allocator);
    var receiver: C.Id = 0;
    var scope_body: C.Id = 0;
    for (module.nodes) |node| if (node.tag == .effect_scope) {
        const callback = module.closures[module.node(node.a).a];
        scope_body = callback.body;
        for (module.nodes, 0..) |candidate, id| if (candidate.tag == .reference and module.reference(@intCast(id)).binding == callback.parameter.binding) {
            receiver = @intCast(id);
            break;
        };
    };
    var memo_body: C.Id = 0;
    var memo_binding: u32 = 0;
    for (module.nodes) |node| if (node.tag == .suspend_) {
        memo_body = module.closures[node.a].body;
    };
    for (module.nodes) |node| if (node.tag == .force) {
        memo_binding = module.reference(node.a).binding;
    };
    try std.testing.expect(receiver != 0 and memo_body != 0 and memo_binding != 0);
    var memo_reference: C.Id = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .reference and module.reference(@intCast(id)).binding == memo_binding) {
        memo_reference = @intCast(id);
    };
    var changed_capture = false;
    for (module.extra[module.node(memo_body).a..][0..module.node(memo_body).b]) |child| {
        if (module.node(child).tag != .bind) continue;
        module.nodes[child].b = receiver;
        const binding = module.nodes[child].a;
        module.bindings[binding].initializer = receiver;
        module.bindings[binding].ty = module.node(receiver).ty;
        module.bindings[binding].scheme.root = module.node(receiver).ty;
        changed_capture = true;
        break;
    }
    var changed_return = false;
    for (module.extra[module.node(scope_body).a..][0..module.node(scope_body).b]) |child| {
        if (module.node(child).tag != .return_) continue;
        module.nodes[child].a = memo_reference;
        changed_return = true;
    }
    try std.testing.expect(changed_capture and changed_return);
    try rejected(allocator, &module);
}
test "immutable lifetime forced scalar Memo retains its actual producer captures through OOM" {
    try memoCaptureLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, memoCaptureLaw, .{});
}

const control_header = header ++ box ++ "const delay = func ~value => return value\n";
const logical_source = control_header ++
    \\entry const answer = func (flag: Bool) => return @effect.scope (func (s: State U32) => return do:
    \\  let ignored = s
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    let captured = func () => return do:
    \\      let discarded = 0
    \\      break 42
    \\    use Box.set captured
    \\    use if flag then (do:
    \\      use Box.set (func () => return 0)
    \\      break true
    \\    ) else false
    \\    use later <- Box.get ()
    \\    break later ()
    \\  let saved = stored
    \\  break result
    \\)
;
const memo_branch_source = control_header ++
    \\entry const answer = func (flag: Bool) => return @effect.scope (func (s: State U32) => return do:
    \\  let ignored = s
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    let captured = func () => return do:
    \\      let discarded = 0
    \\      break 42
    \\    let pending = delay (do:
    \\      use Box.set captured
    \\      break true
    \\    )
    \\    use if flag then @demand pending else do (@effect.provider Box.set (func callback => return ())):
    \\      break @demand pending
    \\    break 42
    \\  break result
    \\)
;
fn addActualCapture(module: *C.Module) !C.Id {
    var receiver: C.Id = 0;
    for (module.nodes) |node| if (node.tag == .effect_scope) {
        const parameter = module.closures[module.node(node.a).a].parameter.binding;
        for (module.nodes, 0..) |candidate, id| if (candidate.tag == .reference and module.reference(@intCast(id)).binding == parameter) {
            receiver = @intCast(id);
            break;
        };
    };
    try std.testing.expect(receiver != 0);
    for (module.closures) |closure| {
        if (closure.parameter.ty != @import("types.zig").unit) continue;
        const body = module.node(closure.body);
        if (body.tag != .block) continue;
        for (module.extra[body.a..][0..body.b]) |child| {
            if (module.node(child).tag != .bind or module.node(module.node(child).b).tag != .constant) continue;
            module.nodes[child].b = receiver;
            const binding = module.nodes[child].a;
            module.bindings[binding].initializer = receiver;
            module.bindings[binding].ty = module.node(receiver).ty;
            module.bindings[binding].scheme.root = module.node(receiver).ty;
            return receiver;
        }
    }
    return error.MissingCapture;
}
fn controlLaw(allocator: std.mem.Allocator) !void {
    var logical = try lower(allocator, logical_source);
    defer logical.deinit(allocator);
    var logical_nodes: usize = 0;
    for (logical.nodes) |*node| if (node.tag == .if_value) {
        node.tag = .logical;
        node.op = .and_;
        node.c = 1;
        logical_nodes += 1;
    };
    try std.testing.expectEqual(1, logical_nodes);
    var seed = try lifetime.analyze(allocator, &logical, &.{}, .{ .binding = try entry(&logical) });
    defer seed.deinit(allocator);
    _ = try addActualCapture(&logical);
    var changed_return = false;
    for (logical.nodes) |node| {
        if (node.tag != .effect_scope) continue;
        const root = logical.closures[logical.node(node.a).a].body;
        const body = logical.node(root);
        var stored: C.Id = 0;
        for (logical.extra[body.a..][0..body.b]) |child| {
            const statement = logical.node(child);
            if (statement.tag == .bind and logical.node(statement.b).tag == .reference and logical.types.node(logical.node(statement.b).ty).tag == .function) stored = statement.b;
        }
        try std.testing.expect(stored != 0);
        for (logical.extra[body.a..][0..body.b]) |child| if (logical.node(child).tag == .return_) {
            logical.nodes[child].a = stored;
            changed_return = true;
        };
    }
    try std.testing.expect(changed_return);
    try rejected(allocator, &logical);
    var memo = try lower(allocator, memo_branch_source);
    defer memo.deinit(allocator);
    var baseline = try lifetime.analyze(allocator, &memo, &.{}, .{ .binding = try entry(&memo) });
    defer baseline.deinit(allocator);
    _ = try addActualCapture(&memo);
    try rejected(allocator, &memo);
}
test "immutable lifetime short circuit and branch Memo state cannot erase alternate storage sinks through OOM" {
    try controlLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, controlLaw, .{});
}

const witness_source = control_header ++
    \\entry const answer = func (flag: Bool) => return @effect.scope (func (s: State U32) => return do:
    \\  let ignored = s
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    let captured = func () => return do:
    \\      let discarded = 0
    \\      break 42
    \\    use @type.same flag (do:
    \\      use Box.set captured
    \\      break true
    \\    )
    \\    break 42
    \\  let saved = stored
    \\  break result
    \\)
;
fn witnessLaw(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, witness_source);
    defer module.deinit(allocator);
    var baseline = try lifetime.analyze(allocator, &module, &.{}, .{ .binding = try entry(&module) });
    defer baseline.deinit(allocator);
    _ = try addActualCapture(&module);
    var changed = false;
    for (module.nodes) |node| {
        if (node.tag != .effect_scope) continue;
        const root = module.closures[module.node(node.a).a].body;
        const body = module.node(root);
        var stored: C.Id = 0;
        for (module.extra[body.a..][0..body.b]) |child| {
            const statement = module.node(child);
            if (statement.tag == .bind and module.node(statement.b).tag == .reference and module.types.node(module.node(statement.b).ty).tag == .function) stored = statement.b;
        }
        try std.testing.expect(stored != 0);
        for (module.extra[body.a..][0..body.b]) |child| if (module.node(child).tag == .return_) {
            module.nodes[child].a = stored;
            changed = true;
        };
    }
    try std.testing.expect(changed);
    try rejected(allocator, &module);
}
test "immutable lifetime type comparison evaluates actual witness stores through OOM" {
    try witnessLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, witnessLaw, .{});
}

test "immutable lifetime overloaded scalar requires an executable implementation proof" {
    var module = try lower(a, header ++ "entry const answer = func () => return @effect.scope (func (s: State U32) => return @u32.add 20 22)\n");
    defer module.deinit(a);
    var changed = false;
    for (module.nodes) |*node| if (node.tag == .scalar) {
        node.c = 1;
        changed = true;
    };
    try std.testing.expect(changed);
    var result = lifetime.analyze(a, &module, &.{}, .{ .binding = try entry(&module) }) catch |err| {
        try std.testing.expectEqual(error.Unsupported, err);
        return;
    };
    defer result.deinit(a);
    return error.ExpectedImplementationDecline;
}

fn rejectCore(allocator: std.mem.Allocator, module: *const C.Module) !void {
    lifetime.rejectSupportedEscapes(allocator, module, &.{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
        try std.testing.expectError(error.InvalidArtifact, lifetime.rejectSupportedEscapesWithScratch(module, &.{}));
        @import("frozen_core_validation.zig").validate(allocator, module, .{}) catch |validation| {
            if (validation == error.OutOfMemory) return validation;
            try std.testing.expectEqual(error.InvalidArtifact, validation);
            return;
        };
        return error.ExpectedImmutableRejection;
    };
    return error.ExpectedScopeRejection;
}

fn coldScopeLaw(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, header ++ "const cold = func () => return @effect.scope (func (s: State U32) => return do:\n  let ignored = s\n  break 42\n)\nentry const answer = func () => return 42\n");
    defer module.deinit(allocator);
    try lifetime.rejectSupportedEscapes(allocator, &module, &.{});
    var changed = false;
    for (module.nodes) |node| {
        if (node.tag != .effect_scope) continue;
        const closure = &module.closures[module.node(node.a).a];
        for (module.nodes, 0..) |reference, id| if (reference.tag == .reference and module.reference(@intCast(id)).binding == closure.parameter.binding) {
            closure.body = @intCast(id);
            changed = true;
            break;
        };
    }
    try std.testing.expect(changed);
    // Whole entry execution does not visit this closure. Direct scope-root
    // enumeration must still reject its forged body independently.
    var entry_report = try lifetime.analyze(allocator, &module, &.{}, .{ .binding = try entry(&module) });
    defer entry_report.deinit(allocator);
    try std.testing.expect(entry_report.complete);
    try rejectCore(allocator, &module);
}
test "immutable scope rejection visits cold closure roots through OOM" {
    try coldScopeLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, coldScopeLaw, .{});
}

test "immutable scope rejection shares one work budget across repeated scope DAG roots" {
    var module = try lower(a, header ++ "entry const answer = func () => return @effect.scope (func (s: State U32) => return do:\n  let ignored = s\n  break 42\n)\n");
    defer module.deinit(a);
    var scope: C.Id = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .effect_scope) {
        scope = @intCast(id);
        break;
    };
    try std.testing.expect(scope != 0);
    const count = module.nodes.len;
    module.nodes = try a.realloc(module.nodes, count + 2000);
    module.spans = try a.realloc(module.spans, count + 2000);
    module.merge_ranges = try a.realloc(module.merge_ranges, count + 2000);
    if (module.dispatch_signatures.len != 0) module.dispatch_signatures = try a.realloc(module.dispatch_signatures, count + 2000);
    for (count..module.nodes.len) |index| {
        module.nodes[index] = module.nodes[scope];
        module.spans[index] = module.spans[scope];
        module.merge_ranges[index] = module.merge_ranges[scope];
        if (module.dispatch_signatures.len != 0) module.dispatch_signatures[index] = module.dispatch_signatures[scope];
    }
    // Every individual root is the same valid finite body. Canonical bounds
    // accept the DAG; restarting a private budget per root would accept it.
    try @import("frozen_core_validation.zig").validateBounds(&module, .{});
    try std.testing.expectError(error.InvalidArtifact, lifetime.rejectSupportedEscapes(a, &module, &.{}));
}

fn appendOrdinaryNodes(module: *C.Module, count: usize) !void {
    const before = module.nodes.len;
    const after = try std.math.add(usize, before, count);
    module.nodes = try a.realloc(module.nodes, after);
    module.spans = try a.realloc(module.spans, after);
    module.merge_ranges = try a.realloc(module.merge_ranges, after);
    if (module.dispatch_signatures.len != 0) module.dispatch_signatures = try a.realloc(module.dispatch_signatures, after);
    for (before..after) |index| {
        module.nodes[index] = .{ .tag = .constant, .ty = @import("types.zig").u32_type, .a = 42 };
        module.spans[index] = .{ .start = 0, .end = 0 };
        module.merge_ranges[index] = .{};
        if (module.dispatch_signatures.len != 0) module.dispatch_signatures[index] = @import("types.zig").u32_type;
    }
}
test "immutable scope rejection ignores unrelated owner and ordinary node population in its semantic budget" {
    var module = try lower(a, header ++ "entry const answer = func () => return @effect.scope (func (s: State U32) => return 42)\n");
    defer module.deinit(a);
    var unrelated = try lower(a, "entry const answer = func () => return 42\n");
    defer unrelated.deinit(a);
    unrelated.unit = 2;
    try appendOrdinaryNodes(&unrelated, 70_000);
    const owners = [_]*const C.Module{ &module, &unrelated };
    try @import("frozen_core_validation.zig").validateBounds(&unrelated, .{ .units = &owners });
    try lifetime.rejectSupportedEscapes(a, &module, &.{&unrelated});
    try appendOrdinaryNodes(&module, 70_000);
    try lifetime.rejectSupportedEscapes(a, &module, &.{&unrelated});
    try @import("frozen_core_validation.zig").validate(a, &module, .{ .units = &owners });
}

const generic_setter_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
    \\const store = func setter => return func value => return setter value
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    use store Box.set (func () => return do:
    \\      let (state, value) = do (@effect.state s.get s.set 42):
    \\        break s.get ()
    \\      break value
    \\    )
    \\    use callback <- Box.get ()
    \\    break callback ()
    \\  break result
    \\)
;
fn declinedStateProof(allocator: std.mem.Allocator, module: *const C.Module, root: C.Id, call: C.Id, callback: u8, argument: u8) !void {
    var remaining: usize = 65_536;
    var report = lifetime.analyzeScope(allocator, module, &.{}, root, &remaining) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.InvalidArtifact or err == error.Unsupported or err == error.LifetimeEscape);
        return;
    };
    defer report.deinit(allocator);
    try std.testing.expect(!try lifetime.localStateInvocation(&report, module.unit, call, callback, argument, &remaining));
}
fn genericSetterCoreLaw(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, generic_setter_source);
    defer module.deinit(allocator);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    try @import("capability_invocations.zig").validate(allocator, &module, &.{});
    var root: C.Id = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .effect_scope) {
        root = @intCast(id);
        break;
    };
    try std.testing.expect(root != 0);
    var remaining: usize = 65_536;
    var report = try lifetime.analyzeScope(allocator, &module, &.{}, root, &remaining);
    defer report.deinit(allocator);
    try std.testing.expect(report.complete);
    var tested = false;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .call and node.tag != .apply) continue;
        const call = @import("capability_flow.zig").coreCall(&module, @intCast(id)) orelse continue;
        const contract = module.bindings[call.target.binding].capability_parameters;
        if (!contract.inputInvokes() or !contract.valid() or call.len != contract.arity()) continue;
        try std.testing.expect(try lifetime.localStateInvocation(&report, module.unit, @intCast(id), contract.callback(), contract.argumentAt(0), &remaining));
        report.complete = false;
        try std.testing.expect(!try lifetime.localStateInvocation(&report, module.unit, @intCast(id), contract.callback(), contract.argumentAt(0), &remaining));
        report.complete = true;
        try std.testing.expect(!try lifetime.localStateInvocation(&report, module.unit, @intCast(id), contract.argumentAt(0), contract.callback(), &remaining));
        try std.testing.expect(!try lifetime.localStateInvocation(&report, module.unit, root, contract.callback(), contract.argumentAt(0), &remaining));
        var changed = false;
        for (module.nodes) |*provider| {
            if (provider.tag != .state_provider) continue;
            const original = provider.*;
            provider.a = original.b;
            provider.b = original.a;
            try declinedStateProof(allocator, &module, root, @intCast(id), contract.callback(), contract.argumentAt(0));
            provider.* = original;
            changed = true;
            break;
        }
        try std.testing.expect(changed);
        const original_type = module.nodes[root].ty;
        module.nodes[root].ty = std.math.maxInt(u32);
        try declinedStateProof(allocator, &module, root, @intCast(id), contract.callback(), contract.argumentAt(0));
        module.nodes[root].ty = original_type;
        tested = true;
        break;
    }
    try std.testing.expect(tested);
}
test "immutable generic setter invocation proves actual local State cell and rejects unrelated roles through OOM" {
    try genericSetterCoreLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, genericSetterCoreLaw, .{});
}

fn scopeAdmissionControlLaw(allocator: std.mem.Allocator) !void {
    const sources = [_][]const u8{
        header ++ "entry const answer = func (seed: U32) => return @effect.scope (func (s: State U32) => return do:\n  let ignored = s\n  break seed\n)\n",
        header ++ "const stop = func () : U32 => return @panic \"stop\"\nentry const answer = func () => return @effect.scope (func (s: State U32) => return do:\n  let ignored = s\n  break @u32.add (stop ()) 1\n)\n",
    };
    for (sources, 0..) |source, index| {
        var module = try lower(allocator, source);
        defer module.deinit(allocator);
        var tested = false;
        for (module.nodes, 0..) |node, id| {
            if (node.tag != .effect_scope) continue;
            var remaining: usize = 65_536;
            var report = try lifetime.analyzeScope(allocator, &module, &.{}, @intCast(id), &remaining);
            defer report.deinit(allocator);
            try std.testing.expectEqual(index == 0, report.complete);
            try std.testing.expect(remaining < 65_536);
            tested = true;
        }
        try std.testing.expect(tested);
    }
}
test "immutable scope admission accepts existing primitive parameters and declines terminating callees through OOM" {
    try scopeAdmissionControlLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scopeAdmissionControlLaw, .{});
}

test "immutable boundary lifetime work ignores unrelated catalog and ordinary node population" {
    var module = try lower(a, header ++ "entry const answer = func () => return @effect.scope (func (s: State U32) => return 42)\n");
    defer module.deinit(a);
    var unrelated = try lower(a, "entry const answer = func () => return 42\n");
    defer unrelated.deinit(a);
    unrelated.unit = 2;
    var baseline = try lifetime.analyze(a, &module, &.{&unrelated}, .{ .binding = try entry(&module) });
    defer baseline.deinit(a);
    try std.testing.expect(baseline.complete);
    try appendOrdinaryNodes(&unrelated, 70_000);
    var catalog_large = try lifetime.analyze(a, &module, &.{&unrelated}, .{ .binding = try entry(&module) });
    defer catalog_large.deinit(a);
    try std.testing.expect(catalog_large.complete);
    try std.testing.expectEqual(baseline.work, catalog_large.work);
    try appendOrdinaryNodes(&module, 70_000);
    var ordinary_large = try lifetime.analyze(a, &module, &.{&unrelated}, .{ .binding = try entry(&module) });
    defer ordinary_large.deinit(a);
    try std.testing.expect(ordinary_large.complete);
    try std.testing.expectEqual(baseline.work, ordinary_large.work);
    const owner = try entry(&unrelated);
    const root = unrelated.bodies[unrelated.bindings[owner].body_id].root;
    unrelated.nodes[root].ty = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidArtifact, lifetime.analyze(a, &module, &.{&unrelated}, .{ .unit = unrelated.unit, .binding = owner }));
}

fn executableOwnerBoundsLaw(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, "entry const answer = func () => return 0\n");
    defer module.deinit(allocator);
    var producer = try lower(allocator, "entry const answer = func () => return 42\n");
    defer producer.deinit(allocator);
    producer.unit = 2;
    const binding = try entry(&producer);
    var report = try lifetime.analyze(allocator, &module, &.{&producer}, .{ .unit = producer.unit, .binding = binding });
    defer report.deinit(allocator);
    try std.testing.expect(report.complete);
    const root = producer.bodies[producer.bindings[binding].body_id].root;
    producer.nodes[root].ty = std.math.maxInt(u32);
    var invalid = lifetime.analyze(allocator, &module, &.{&producer}, .{ .unit = producer.unit, .binding = binding }) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
        return;
    };
    invalid.deinit(allocator);
    return error.ExpectedMalformedProducerRejection;
}
test "immutable boundary lifetime reader validates selected producer bounds independently through OOM" {
    try executableOwnerBoundsLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, executableOwnerBoundsLaw, .{});
}

const deferred_migrate_source =
    \\type Maybe a is data = $Nothing | $Some a
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const scope_feature = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let ignored = s
    \\  break 0
    \\)
    \\const generate = func count => return func generator => return @array.generate count generator
    \\const migrate = func (version: U32) => return case version of
    \\  1 => $Some (func (values: Array F32) => return generate (@array.length values) (func index => return if @u32.lt 0 index then (if @u32.eq (@u32.rem (@u32.sub index 1) 6) 4 then @f32.mul values[index] 2.0 else values[index]) else values[index]))
    \\  _ => $Nothing
    \\entry const answer = func () => return case migrate 1 of
    \\  $Some callback => @array.get (callback #[1.0, 2.0, 3.0, 4.0, 5.0, 6.0]) 5
    \\  $Nothing => 0.0
;
fn derivedAbsent(allocator: std.mem.Allocator, module: *const C.Module, body: C.Body) !void {
    var terms: @import("capability_contracts.zig").Store = .{};
    defer terms.deinit(allocator);
    const root = try @import("capability_contract_core.zig").deriveWithOwners(allocator, &terms, module, body, module.bindings[body.binding].capability_parameters, &.{});
    try std.testing.expect(root == null);
}
fn deferredMigrateCase(allocator: std.mem.Allocator, source: []const u8) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    const catalogs = try allocator.alloc(C.List, module.closures.len);
    defer allocator.free(catalogs);
    for (module.closures, catalogs) |closure, *catalog| catalog.* = closure.captures;
    var tested = false;
    for (module.bodies) |body| {
        const binding = module.bindings[body.binding];
        if (binding.capability_flow != .input_shape or binding.capability_parameters.arity() != 1 or module.node(body.root).tag != .match) continue;
        var terms: @import("capability_contracts.zig").Store = .{};
        defer terms.deinit(allocator);
        const root = try @import("capability_contract_core.zig").deriveWithOwners(allocator, &terms, &module, body, binding.capability_parameters, &.{});
        try std.testing.expect(root != null);
        const parameter = module.parameters[body.parameters.start].binding;
        var parameter_reference: C.Id = 0;
        for (module.nodes, 0..) |node, id| {
            if (node.tag != .reference) continue;
            const reference = module.reference(@intCast(id));
            if ((reference.unit == 0 or reference.unit == module.unit) and reference.binding == parameter) {
                parameter_reference = @intCast(id);
                break;
            }
        }
        try std.testing.expect(parameter_reference != 0);
        var changed = false;
        for (module.nodes) |node| {
            if (node.tag != .call or node.c != 2 or module.types.node(node.ty).tag != .array) continue;
            const call = &module.calls[node.a];
            const target = call.target;
            call.target = .{ .binding = parameter };
            try derivedAbsent(allocator, &module, body);
            call.target = .{ .unit = std.math.maxInt(u32), .binding = target.binding };
            try derivedAbsent(allocator, &module, body);
            call.target = target;
            const original_argument = module.extra[node.b];
            module.extra[node.b] = parameter_reference;
            // Omitted redundant capture catalogs cannot erase this newly free
            // outer argument retained in the returned closure's future call.
            for (module.closures) |*closure| closure.captures.len = 0;
            try derivedAbsent(allocator, &module, body);
            module.extra[node.b] = original_argument;
            for (module.closures, catalogs) |*closure, catalog| closure.captures = catalog;
            changed = true;
            break;
        }
        try std.testing.expect(changed);
        tested = true;
    }
    try std.testing.expect(tested);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}

fn deferredMigrateLaw(allocator: std.mem.Allocator) !void {
    try deferredMigrateCase(allocator, deferred_migrate_source);
    const demand_body = try std.mem.replaceOwned(u8, allocator, deferred_migrate_source, "@f32.mul values[index] 2.0", "keep (@f32.mul values[index] 2.0)");
    defer allocator.free(demand_body);
    const demanded = try allocator.print("const keep = func ~value => return @demand value\n{s}", .{demand_body});
    defer allocator.free(demanded);
    try deferredMigrateCase(allocator, demanded);
    const associated = try std.mem.replaceOwned(u8, allocator, deferred_migrate_source, "@f32.mul values[index] 2.0", "@type.call \"mul\" values[index] 2.0");
    defer allocator.free(associated);
    try deferredMigrateCase(allocator, associated);
}
test "deferred ordinary named calls retain exact lexical construction captures through OOM" {
    try deferredMigrateLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, deferredMigrateLaw, .{});
}

fn nonfunctionGlobalContractLaw(allocator: std.mem.Allocator) !void {
    const source = "const amount = @u32.to_f32 7\ntype Payload is data = $Payload {input: U32, amount: F32}\nconst make = func (input: U32) => return $Payload {input, amount}\nentry const answer = func () => return make 42\n";
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    var computed = false;
    for (module.bodies) |body| {
        if (body.is_function or module.node(body.root).tag != .scalar) continue;
        try std.testing.expectEqual(0, body.parameters.len);
        try std.testing.expectEqual(@import("types.zig").f32_type, module.typeOf(body.root));
        computed = true;
    }
    try std.testing.expect(computed);
    var tested = false;
    for (module.bodies) |body| {
        if (!body.is_function or body.parameters.len != 1 or module.node(body.root).tag != .construct) continue;
        const binding = &module.bindings[body.binding];
        // This is an untrusted frozen claim, independently reconstructed below.
        // Its exact valid relationship returns its input and a static scalar.
        binding.capability_flow = .input_shape;
        binding.capability_parameters = .init(1, 1);
        try std.testing.expect(@import("capability_contract_core.zig").inputBodyWithOwners(&module, body, binding.capability_parameters, &.{}));
        var terms: @import("capability_contracts.zig").Store = .{};
        defer terms.deinit(allocator);
        const root = try @import("capability_contract_core.zig").deriveWithOwners(allocator, &terms, &module, body, binding.capability_parameters, &.{});
        try std.testing.expect(root != null);
        try std.testing.expectEqual(@as(u16, 1), try terms.view().parameterMask(root.?));
        tested = true;
    }
    try std.testing.expect(tested);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "computed nonfunction globals remain scalar values in independently rederived frozen constructor contracts through OOM" {
    try nonfunctionGlobalContractLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nonfunctionGlobalContractLaw, .{});
}

const resource_scope_return = header ++
    "type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}\nconst forbidden_cleanup = func () => return Box.set (func () => return 42)\n" ++
    \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
    \\  use escaped <- @effect.scope (func (younger: State F32) => return @resource.scope (func () => return 9) (func owner => return do:
    \\    let cleanup_capture = younger
    \\    break ()
    \\  ) (func loan => return do:
    \\    let observed = @usage.read loan
    \\    break func () => return do:
    \\      let retained = older
    \\      break 42
    \\  ))
    \\  break escaped ()
    \\)
;
fn resourceScopeFootprintCase(allocator: std.mem.Allocator, source: []const u8, complete: bool) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    var report = try lifetime.analyze(allocator, &module, &.{}, .{ .binding = try entry(&module) });
    defer report.deinit(allocator);
    try std.testing.expectEqual(complete, report.complete);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    for (module.nodes) |node| {
        if (node.tag != .effect_scope) continue;
        const ty = module.node(node.a).ty;
        const original = module.types.nodes[ty];
        module.types.nodes[ty].a = std.math.maxInt(u32);
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.types.nodes[ty] = original;
        module.types.nodes[ty].b = std.math.maxInt(u32);
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        module.types.nodes[ty] = original;
        break;
    }
    var store_body: C.Id = 0;
    for (module.bodies) |body| {
        if (body.exported or body.parameters.len != 1 or module.node(body.root).ty != @import("types.zig").unit) continue;
        store_body = body.root;
    }
    try std.testing.expect(store_body != 0);
    var resources: usize = 0;
    for (module.nodes) |node| {
        if (node.tag != .resource_scope) continue;
        var acquire_at: ?usize = null;
        var body_at: ?usize = null;
        var cleanup_at: ?usize = null;
        for (report.invocations, 0..) |invocation, index| {
            if (invocation.caller.node == node.a) acquire_at = index;
            if (invocation.caller.node == node.c) body_at = index;
            if (invocation.caller.node == node.b) cleanup_at = index;
        }
        try std.testing.expect(acquire_at.? < body_at.? and body_at.? < cleanup_at.?);
        var empty_budget: usize = 0;
        try std.testing.expectError(error.UnsafeCleanup, @import("cleanup_contracts.zig").immutableScalarWithBudget(&module, node.b, &empty_budget));
        try std.testing.expectEqual(0, empty_budget);
        var equality_budget: usize = 1;
        const callback_type = module.types.node(module.node(node.c).ty).a;
        try std.testing.expectError(error.TypeLimit, @import("rank_equal.zig").equalWithBudget(&module.types, callback_type, callback_type, true, &equality_budget));
        try std.testing.expectEqual(0, equality_budget);
        const original_type = module.nodes[node.b].ty;
        module.nodes[node.b].ty = module.nodes[node.a].ty;
        try rejectCore(allocator, &module);
        module.nodes[node.b].ty = original_type;
        const cleanup_catalog = module.node(node.b).a;
        const original_body = module.closures[cleanup_catalog].body;
        module.closures[cleanup_catalog].body = store_body;
        try std.testing.expectError(error.UnsafeCleanup, @import("cleanup_contracts.zig").immutable(&module, node.b));
        try rejectCore(allocator, &module);
        module.closures[cleanup_catalog].body = original_body;
        resources += 1;
    }
    try std.testing.expectEqual(1, resources);
    var younger_reference: C.Node = undefined;
    var loan_reference: C.Node = undefined;
    var retained: C.Id = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .reference) continue;
        const span = module.spans[id];
        const name = source[span.start..span.end];
        if (std.mem.eql(u8, name, "younger")) younger_reference = node;
        if (std.mem.eql(u8, name, "loan")) loan_reference = node;
        if (std.mem.eql(u8, name, "older")) retained = @intCast(id);
    }
    try std.testing.expect(retained != 0);
    const original = module.nodes[retained];
    const older_binding = module.reference(retained).binding;
    const younger_binding = module.references[younger_reference.a].binding;
    const loan_binding = module.references[loan_reference.a].binding;
    var retained_binding: u32 = 0;
    for (module.nodes) |node| if (node.tag == .bind and node.b == retained) {
        retained_binding = node.a;
    };
    try std.testing.expect(retained_binding != 0);
    const binding_before = module.bindings[retained_binding];
    module.nodes[retained] = loan_reference;
    module.bindings[retained_binding].ty = loan_reference.ty;
    module.bindings[retained_binding].scheme.root = loan_reference.ty;
    for (module.closures) |closure_| for (module.extra[closure_.captures.start..][0..closure_.captures.len]) |*capture_| {
        if (capture_.* == older_binding) capture_.* = loan_binding;
    };
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    try rejectCore(allocator, &module);
    module.nodes[retained] = original;
    module.bindings[retained_binding] = binding_before;
    for (module.closures) |closure_| for (module.extra[closure_.captures.start..][0..closure_.captures.len]) |*capture_| {
        if (capture_.* == loan_binding) capture_.* = older_binding;
    };
    module.nodes[retained] = younger_reference;
    for (module.nodes) |node| {
        if (node.tag != .bind or node.b != retained) continue;
        module.bindings[node.a].ty = younger_reference.ty;
        module.bindings[node.a].scheme.root = younger_reference.ty;
    }
    for (module.closures) |closure_| for (module.extra[closure_.captures.start..][0..closure_.captures.len]) |*capture_| {
        if (capture_.* == older_binding) capture_.* = younger_binding;
    };
    try rejected(allocator, &module);
    for (module.closures) |*closure_| closure_.captures.len = 0;
    try rejectCore(allocator, &module);
    module.nodes[retained] = original;
}
fn resourceScopeFootprintLaw(allocator: std.mem.Allocator) !void {
    try resourceScopeFootprintCase(allocator, resource_scope_return, true);
    const parameterized = try std.mem.replaceOwned(u8, allocator, resource_scope_return, "entry const answer = func ()", "entry const answer = func (host: Unit -> U32 ! {Foreign})");
    defer allocator.free(parameterized);
    const unknown_call = try std.mem.replaceOwned(u8, allocator, parameterized, "let observed = @usage.read loan", "use host ()\n    let observed = @usage.read loan");
    defer allocator.free(unknown_call);
    // An ordinary unknown callback still has no independent loan-result
    // recipe. Source spelling does not bypass immutable admission.
    var unknown = try lower(allocator, unknown_call);
    defer unknown.deinit(allocator);
    if (lifetime.analyze(allocator, &unknown, &.{}, .{ .binding = try entry(&unknown) })) |report_| {
        var unexpected = report_;
        unexpected.deinit(allocator);
        return error.ExpectedConservativeDecline;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
    }
    try rejectCore(allocator, &unknown);
    const failed_cleanup = try std.mem.replaceOwned(u8, allocator, resource_scope_return, "break ()", "break @panic \"cleanup\"");
    defer allocator.free(failed_cleanup);
    // Even an incomplete cleanup path cannot erase the later result graph.
    try resourceScopeFootprintCase(allocator, failed_cleanup, false);
}
test "resource scope callback results retain exact older owners and reject younger captures independently through OOM" {
    try resourceScopeFootprintLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, resourceScopeFootprintLaw, .{});
}

fn resourceFailureOrderLaw(allocator: std.mem.Allocator) !void {
    const sources = [_][]const u8{
        header ++ "entry const answer = func () => return @effect.scope (func (state: State U32) => return @resource.scope (func () => return 9) (func owner => return do:\n  let retained = state\n  break ()\n) (func loan => return @panic \"callback\"))\n",
        header ++ "entry const answer = func () => return @effect.scope (func (state: State U32) => return @resource.scope (func () => return 9) (func owner => return @panic \"cleanup\") (func loan => return @usage.read loan))\n",
    };
    for (sources, 0..) |source, ordinal| {
        var module = try lower(allocator, source);
        defer module.deinit(allocator);
        if (ordinal == 0) {
            try rejectCore(allocator, &module);
            continue;
        }
        var report = try lifetime.analyze(allocator, &module, &.{}, .{ .binding = try entry(&module) });
        defer report.deinit(allocator);
        try std.testing.expect(!report.complete);
        var tested = false;
        for (module.nodes) |node| {
            if (node.tag != .resource_scope) continue;
            var body_at: ?usize = null;
            var cleanup_at: ?usize = null;
            for (report.invocations, 0..) |invocation, index| {
                if (invocation.caller.node == node.c) body_at = index;
                if (invocation.caller.node == node.b) cleanup_at = index;
            }
            try std.testing.expect(body_at.? < cleanup_at.?);
            tested = true;
        }
        try std.testing.expect(tested);
    }
}
test "resource lifetime cleanup failure grants no complete report and unknown terminating callbacks decline through OOM" {
    try resourceFailureOrderLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, resourceFailureOrderLaw, .{});
}

fn rejectPartialScope(allocator: std.mem.Allocator, module: *const C.Module) !void {
    lifetime.rejectSupportedEscapes(allocator, module, &.{module}) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
        return;
    };
    return error.ExpectedScopeRejection;
}
fn scopedPartialResidualLaw(allocator: std.mem.Allocator) !void {
    const source = header ++
        \\const reader = func (ignored: State U32) => return func (state: State U32) => return func () => return state.get ()
        \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
        \\  let callback = @effect.scope (func (younger: State U32) => return reader younger older)
        \\  let (state, result) = do (@effect.state older.get older.set 7):
        \\    break callback ()
        \\  break result
        \\)
    ;
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    try lifetime.rejectSupportedEscapes(allocator, &module, &.{&module});
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{ .units = &.{&module} });
    const body = for (module.bodies) |candidate| {
        if (candidate.parameters.len == 3) break candidate;
    } else return error.MissingReader;
    const parameters = module.bodyParameters(&body);
    const reference = for (module.references) |*candidate| {
        if (candidate.binding == parameters[1].binding) break candidate;
    } else return error.MissingReaderReference;
    const original = reference.*;
    reference.binding = parameters[0].binding;
    // The same physical/type family cannot substitute the unused younger
    // argument for the residual body's actual older receiver.
    try rejectPartialScope(allocator, &module);
    const closures = try allocator.dupe(C.ClosureInfo, module.closures);
    defer allocator.free(closures);
    for (module.closures) |*closure_| closure_.captures.len = 0;
    try rejectPartialScope(allocator, &module);
    @memcpy(module.closures, closures);
    reference.* = original;
    try lifetime.rejectSupportedEscapes(allocator, &module, &.{&module});
}
test "scoped partial applications derive residual captures and reject younger substitution despite omitted catalogs through OOM" {
    try scopedPartialResidualLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scopedPartialResidualLaw, .{});
}

fn discardedUnitContractLaw(allocator: std.mem.Allocator) !void {
    const source =
        \\effect Tick: Unit -> Unit
        \\const effectful = func () => return Tick ()
        \\const increment = func (value: U32) => return @u32.add value 1
        \\entry const answer = func (value: U32) => return do:
        \\  use result: U32 <- increment value
        \\  use ()
        \\  break result
        \\const forward = func (value: U32) => return do:
        \\  use result: U32 <- value
        \\  use ()
        \\  break result
    ;
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    const reader = @import("capability_contract_core.zig");
    // These are claims at the immutable boundary; reconstruct each body rather
    // than relying on whether this small Source module needs to publish them.
    for (module.bodies) |body| {
        if (!body.is_function or module.node(body.root).tag == .apply) continue;
        module.bindings[body.binding].capability_flow = .input_shape;
        module.bindings[body.binding].capability_parameters = .init(1, if (!body.exported and module.node(body.root).tag == .block) 1 else 0);
    }
    var tested: usize = 0;
    for (module.bodies) |body| {
        if (!body.is_function or module.node(body.root).tag != .block) continue;
        const binding = module.bindings[body.binding];
        try std.testing.expectEqual(.input_shape, binding.capability_flow);
        try std.testing.expect(reader.inputBody(&module, body, binding.capability_parameters));
        var graph: @import("capability_contracts.zig").Store = .{};
        defer graph.deinit(allocator);
        const root = (try reader.derive(allocator, &graph, &module, body, binding.capability_parameters)).?;
        try std.testing.expectEqual(binding.capability_parameters.result(), try graph.view().parameterMask(root));
        const block = module.node(body.root);
        var unit: C.Id = 0;
        for (module.extra[block.a..][0..block.b]) |child| {
            if (module.node(child).tag == .constant and module.typeOf(child) == @import("types.zig").unit) unit = child;
        }
        try std.testing.expect(unit != 0);
        const original = module.nodes[unit];
        for (0..6) |mutation| {
            module.nodes[unit] = original;
            switch (mutation) {
                0 => module.nodes[unit].a = 1,
                1 => module.nodes[unit].b = 1,
                2 => module.nodes[unit].c = 1,
                3 => module.nodes[unit].op = .add,
                4 => module.nodes[unit].ty = @import("types.zig").u32_type,
                5 => module.nodes[unit] = .{ .tag = .apply, .ty = @import("types.zig").unit, .a = unit, .b = unit },
                else => unreachable,
            }
            try std.testing.expect(!reader.inputBody(&module, body, binding.capability_parameters));
            try derivedAbsent(allocator, &module, body);
        }
        module.nodes[unit] = original;
        var effectful_call: C.Id = 0;
        for (module.nodes, 0..) |node, id| {
            if (node.tag != .apply or node.ty != @import("types.zig").unit) continue;
            if (module.node(node.a).tag == .operation_value) effectful_call = @intCast(id);
        }
        try std.testing.expect(effectful_call != 0);
        for (module.extra[block.a..][0..block.b]) |*child| {
            if (child.* != unit) continue;
            child.* = effectful_call;
            try std.testing.expect(!reader.inputBody(&module, body, binding.capability_parameters));
            try derivedAbsent(allocator, &module, body);
            child.* = unit;
        }
        try std.testing.expect(reader.inputBody(&module, body, binding.capability_parameters));
        tested += 1;
    }
    try std.testing.expectEqual(2, tested);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}
test "discarded canonical Unit statements preserve exact immutable no-store contracts through OOM" {
    try discardedUnitContractLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, discardedUnitContractLaw, .{});
}

const ordinary_callback_values_source =
    \\const encode = func (value: F32) => return #[value]
    \\const decode = func (values: Array F32) => return values[0]
    \\const store_callback = func (callback: Unit -> U32) => return #[callback]
    \\const identity = func (value: U32) => return value
    \\const wrap = func (value: U32) => return {value}
    \\const metadata = func (key: U32) => return {key, encode, decode, store_callback, identity, wrap}
;

fn ordinaryCallbackValuesLaw(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, ordinary_callback_values_source);
    defer module.deinit(allocator);
    var factory: ?C.Body = null;
    var encode: C.BindingId = 0;
    var stored_callback: C.BindingId = 0;
    for (module.bodies) |body| {
        if (std.mem.eql(u8, module.name(body.declaration_name), "metadata")) factory = body;
        if (std.mem.eql(u8, module.name(body.declaration_name), "encode")) encode = body.binding;
        if (std.mem.eql(u8, module.name(body.declaration_name), "store_callback")) stored_callback = body.binding;
        if (std.mem.eql(u8, module.name(body.declaration_name), "identity")) module.bindings[body.binding].capability_flow = .identity;
        if (std.mem.eql(u8, module.name(body.declaration_name), "wrap")) {
            module.bindings[body.binding].capability_flow = .input_shape;
            module.bindings[body.binding].capability_parameters = .init(1, 1);
        }
    }
    try std.testing.expect(factory != null and encode != 0 and stored_callback != 0);
    // An ordinary syntactic product summary is not an advertised no-store
    // callable recipe. Frozen import contexts can retain these summaries.
    for ([_]C.BindingId{ encode, stored_callback }) |binding| {
        try std.testing.expectEqual(.unknown, module.bindings[binding].capability_flow);
        module.bindings[binding].capability_parameters = .init(1, 1);
    }
    const body = factory.?;
    // Install exact frozen claims independently of whether this small module
    // needs a public capability catalog. The immutable reader proves them.
    module.bindings[body.binding].capability_flow = .input_shape;
    module.bindings[body.binding].capability_parameters = .init(1, 1);
    const binding = module.bindings[body.binding];
    try std.testing.expectEqual(.input_shape, binding.capability_flow);
    try std.testing.expectEqual(@as(u16, 1), binding.capability_parameters.result());
    const reader = @import("capability_contract_core.zig");
    var graph: @import("capability_contracts.zig").Store = .{};
    defer graph.deinit(allocator);
    const root = (try reader.derive(allocator, &graph, &module, body, binding.capability_parameters)).?;
    try std.testing.expectEqual(@as(u16, 1), try graph.view().parameterMask(root));
    var checked_fields: usize = 0;
    for (module.field_names) |field| {
        const spelling = module.name(field.spelling);
        if (!std.mem.eql(u8, spelling, "encode") and !std.mem.eql(u8, spelling, "store_callback") and !std.mem.eql(u8, spelling, "identity") and !std.mem.eql(u8, spelling, "wrap")) continue;
        const selected = try graph.project(allocator, root, field.symbol, .field);
        const expected: @import("capability_contracts.zig").Tag = if (std.mem.eql(u8, spelling, "encode") or std.mem.eql(u8, spelling, "store_callback")) .empty else .callable;
        try std.testing.expectEqual(expected, graph.nodes.items[selected].tag);
        checked_fields += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), checked_fields);
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
    for ([_]C.BindingId{ encode, stored_callback }) |target| {
        // A forged marker must still force independent body reconstruction,
        // including when the callback is reached only as a returned field.
        module.bindings[target].capability_flow = .input_shape;
        try std.testing.expect(!reader.inputBody(&module, body, binding.capability_parameters));
        try derivedAbsent(allocator, &module, body);
        try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(allocator, &module, .{}));
        module.bindings[target].capability_flow = .unknown;
    }
    try @import("frozen_core_validation.zig").validate(allocator, &module, .{});
}

test "ordinary closed callback values retain footprints without gaining no-store recipes through OOM" {
    try ordinaryCallbackValuesLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, ordinaryCallbackValuesLaw, .{});
}
