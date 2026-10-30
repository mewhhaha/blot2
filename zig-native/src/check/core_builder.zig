//! Mutable Source-to-Core construction. Published tables, private remapping
//! scratch and borrowed source inputs have separate owners; finish transfers
//! complete immutable buffers transactionally to core.Module.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const checked_types = @import("check.zig");
const core = @import("core.zig");
const T = @import("types.zig");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{CoreLimit};
const Source = struct {
    tree: *const ast.Tree,
    names: *const symbols.Pool,
    checked: *const checked_types.Checked,
    diagnostic_origins: checked_types.ModuleOrigins = .{},
};
const Tables = struct {
    field_names: std.ArrayList(core.FieldName) = .empty,
    request_loops: std.ArrayList(core.RequestLoopInfo) = .empty,
    request_arms: std.ArrayList(core.RequestArm) = .empty,
    tag_calls: std.ArrayList(core.Id) = .empty,
    nodes: std.ArrayList(core.Node) = .empty,
    spans: std.ArrayList(core.Span) = .empty,
    extra: std.ArrayList(core.Id) = .empty,
    type_nodes: std.ArrayList(T.Node) = .empty,
    quantifier_goals: std.ArrayList(T.QuantifierGoals) = .empty,
    quantifier_obligations: std.ArrayList(T.Obligation) = .empty,
    type_extra: std.ArrayList(T.Id) = .empty,
    effect_rows: std.ArrayList(T.Effects.Row) = .empty,
    effect_labels: std.ArrayList(T.Effects.Label) = .empty,
    effect_operations: std.ArrayList(T.Operation) = .empty,
    bindings: std.ArrayList(core.Binding) = .empty,
    bodies: std.ArrayList(core.Body) = .empty,
    parameters: std.ArrayList(core.Parameter) = .empty,
    runtime_names: std.ArrayList(core.RuntimeName) = .empty,
    source_names: std.ArrayList(core.RuntimeName) = .empty,
    erased_declaration_references: std.ArrayList(core.ErasedDeclarationReference) = .empty,
    references: std.ArrayList(core.BindingRef) = .empty,
    calls: std.ArrayList(core.CallInfo) = .empty,
    merges: std.ArrayList(core.Merge) = .empty,
    merge_ranges: std.ArrayList(core.List) = .empty,
    name_bytes: std.ArrayList(u8) = .empty,
    obligations: std.ArrayList(core.Obligation) = .empty,
    diagnostics: std.ArrayList(core.Diagnostic) = .empty,
    nominals: std.ArrayList(core.Nominal) = .empty,
    operation_names: std.ArrayList(core.OperationName) = .empty,
    constructors: std.ArrayList(core.Constructor) = .empty,
    projections: std.ArrayList(core.Projection) = .empty,
    projection_variants: std.ArrayList(core.ProjectionVariant) = .empty,
    patterns: std.ArrayList(core.Pattern) = .empty,
    pattern_rows: std.ArrayList(core.PatternRow) = .empty,
    match_arms: std.ArrayList(core.MatchArm) = .empty,
    matches: std.ArrayList(core.MatchInfo) = .empty,
    updates: std.ArrayList(core.UpdateInfo) = .empty,
    update_steps: std.ArrayList(core.UpdateStep) = .empty,
    closures: std.ArrayList(core.ClosureInfo) = .empty,
    associated: std.ArrayList(core.Associated) = .empty,
    contracts: std.ArrayList(core.Contract) = .empty,
    contract_members: std.ArrayList(core.ContractMember) = .empty,
    implementations: std.ArrayList(core.Implementation) = .empty,
    implementation_members: std.ArrayList(core.ImplementationMember) = .empty,
    member_templates: std.ArrayList(core.MemberTemplate) = .empty,
    selected_proofs: std.ArrayList(core.SelectedProof) = .empty,
    selected_members: std.ArrayList(core.ImplementationMember) = .empty,
    selected_edges: std.ArrayList(u32) = .empty,
    selected_uses: std.ArrayList(core.SelectedUse) = .empty,
    dictionary_selections: std.ArrayList(core.DictionarySelection) = .empty,
    dictionary_uses: std.ArrayList(core.DictionaryUse) = .empty,
    primitives: std.ArrayList(core.Primitive) = .empty,
    loops: std.ArrayList(core.LoopInfo) = .empty,
    loop_carries: std.ArrayList(core.LoopCarry) = .empty,
    resolver_ops: std.ArrayList(core.ResolverInfo) = .empty,
    operation_values: std.ArrayList(core.OperationValue) = .empty,
    handle_effects: std.ArrayList(core.HandleEffects) = .empty,
    dispatch_signatures: std.ArrayList(T.Id) = .empty,
    proof_contracts: std.ArrayList(core.ProofContract) = .empty,
    fn deinit(self: *Tables, allocator: Allocator) void {
        for (self.proof_contracts.items) |*contract| contract.header.deinit(allocator);
        inline for (@typeInfo(Tables).@"struct".field_names) |field| @field(self, field).deinit(allocator);
    }
    fn finish(self: *Tables, allocator: Allocator, body_lowerings: usize, effect_variable_count: u32, ast_map: []const core.Id) Allocator.Error!core.Module {
        var result: core.Module = .{ .types = .{ .nodes = &.{}, .extra = &.{} }, .nodes = &.{}, .spans = &.{}, .extra = &.{}, .bindings = &.{}, .bodies = &.{}, .parameters = &.{}, .references = &.{}, .calls = &.{}, .merges = &.{}, .merge_ranges = &.{}, .names = &.{}, .obligations = &.{}, .diagnostics = &.{}, .body_lowerings = body_lowerings };
        errdefer result.deinit(allocator);
        result.proof_contracts = try self.proof_contracts.toOwnedSlice(allocator);
        std.mem.sortUnstable(core.FieldName, self.field_names.items, {}, struct {
            fn less(_: void, left: core.FieldName, right: core.FieldName) bool {
                return left.symbol < right.symbol;
            }
        }.less);
        result.field_names = try self.field_names.toOwnedSlice(allocator);
        result.types.nodes = try self.type_nodes.toOwnedSlice(allocator);
        for (result.types.nodes) |node| if (node.tag == .forall or node.tag == .existential) {
            result.has_rank_contracts = true;
            break;
        };
        for (result.types.nodes) |node| if (node.tag == .usage) {
            result.has_usage_contracts = true;
            break;
        };
        for (result.types.nodes) |node| if (node.tag == .erased_proof) {
            result.has_numeric_proofs = true;
            break;
        };
        result.types.extra = try self.type_extra.toOwnedSlice(allocator);
        result.types.effects.rows = try self.effect_rows.toOwnedSlice(allocator);
        result.types.effects.labels = try self.effect_labels.toOwnedSlice(allocator);
        result.types.effects.variable_count = effect_variable_count;
        result.types.operations = try self.effect_operations.toOwnedSlice(allocator);
        result.types.quantifier_goals = try self.quantifier_goals.toOwnedSlice(allocator);
        @import("quantifier_goals.zig").sort(result.types.quantifier_goals);
        result.types.quantifier_obligations = try self.quantifier_obligations.toOwnedSlice(allocator);
        for (self.nominals.items) |nominal| if (nominal.has_usage) {
            result.has_usage_contracts = true;
        };
        inline for (.{ "request_loops", "request_arms", "runtime_names", "source_names", "erased_declaration_references", "tag_calls", "nodes", "spans", "extra", "bindings", "bodies", "parameters", "references", "calls", "merges", "merge_ranges", "obligations", "diagnostics", "nominals", "operation_names", "constructors", "projections", "projection_variants", "patterns", "pattern_rows", "match_arms", "matches", "updates", "update_steps", "closures", "associated", "contracts", "contract_members", "implementations", "implementation_members", "member_templates", "selected_proofs", "selected_members", "selected_edges", "selected_uses", "dictionary_selections", "dictionary_uses", "primitives", "loops", "loop_carries", "resolver_ops", "operation_values", "handle_effects", "dispatch_signatures" }) |field| @field(result, field) = try @field(self, field).toOwnedSlice(allocator);
        for (result.dictionary_uses) |*use| {
            if (use.introduction == 0) continue;
            const mapped = ast_map[use.introduction];
            std.debug.assert(mapped != 0);
            use.introduction = mapped;
            if (result.node(mapped).tag == .closure) use.introduction = result.closures[result.node(mapped).a].body;
        }
        for (result.dictionary_selections) |*selection| switch (selection.proof) {
            .selected => {},
            .given => |*given| {
                if (given.introduction == 0) continue;
                const mapped = ast_map[given.introduction];
                std.debug.assert(mapped != 0);
                given.introduction = mapped;
                if (result.node(mapped).tag == .closure) given.introduction = result.closures[result.node(mapped).a].body;
            },
        };
        result.names = try self.name_bytes.toOwnedSlice(allocator);
        return result;
    }
};
const Scratch = struct {
    saved_fields: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// First published node of each argument-free nominal.
    nullary_nominals: std.AutoHashMapUnmanaged(T.NominalIdentity, T.Id) = .empty,
    request_callbacks: std.ArrayList(RequestCallbackFrame) = .empty,
    visit_epochs: std.ArrayList(u32) = .empty,
    resolver_loop_frames: std.ArrayList(ResolverLoopFrame) = .empty,
    type_map: []T.Id = &.{},
    closed_containers: [3][6]T.Id = @splat(@splat(0)),
    variable_map: []T.Id = &.{},
    effect_row_map: []u32 = &.{},
    effect_variable_map: []u32 = &.{},
    effect_operation_map: []u32 = &.{},
    ast_map: []core.Id = &.{},
    member_origin_heads: []u32 = &.{},
    member_origin_next: []u32 = &.{},
    signature_sources: []T.Id = &.{},
    merge_heads: []u32 = &.{},
    merge_next: []u32 = &.{},
    loop_exit_indices: []u32 = &.{},
    /// Nonzero for a statement case arm block that carries rebinding out.
    statement_arms: []u32 = &.{},
    definition_epochs: []u32 = &.{},
    reference_epochs: []u32 = &.{},
    capture_epoch: u32 = 0,
    return_target: core.Id = 0,
    function_target: core.Id = 0,
    variable_count: u32 = 0,
    effect_variable_count: u32 = 0,
    body_lowerings: usize = 0,
    proof_visits: usize = 0,
    fn deinit(self: *Scratch, allocator: Allocator) void {
        self.saved_fields.deinit(allocator);
        self.nullary_nominals.deinit(allocator);
        self.request_callbacks.deinit(allocator);
        self.visit_epochs.deinit(allocator);
        self.resolver_loop_frames.deinit(allocator);
        allocator.free(self.type_map);
        allocator.free(self.variable_map);
        allocator.free(self.effect_row_map);
        allocator.free(self.effect_variable_map);
        allocator.free(self.effect_operation_map);
        allocator.free(self.ast_map);
        allocator.free(self.member_origin_heads);
        allocator.free(self.member_origin_next);
        allocator.free(self.signature_sources);
        allocator.free(self.merge_heads);
        allocator.free(self.merge_next);
        allocator.free(self.loop_exit_indices);
        allocator.free(self.statement_arms);
        allocator.free(self.definition_epochs);
        allocator.free(self.reference_epochs);
    }
};
const ResolverLoopFrame = struct { source: ast.Id, cursor: T.Id, parameter: core.BindingId, finalizer: core.Id, continued: u32, continue_constructor: u32 };
const RequestCallbackFrame = struct { loop: ast.Id, return_target: core.Id, decision_type: T.Id, state_type: T.Id };
const Builder = struct {
    allocator: Allocator,
    source: Source,
    tables: Tables = .{},
    scratch: Scratch = .{},
    fn deinit(self: *Builder) void {
        self.tables.deinit(self.allocator);
        self.scratch.deinit(self.allocator);
    }
    fn allocateEmpty(self: *Builder, destination: *[]u32, count: usize) Error!void {
        std.debug.assert(destination.*.len == 0);
        const buffer = try self.allocator.alloc(u32, count);
        @memset(buffer, 0);
        destination.* = buffer;
    }
    fn initialize(self: *Builder) Error!void {
        try self.allocateEmpty(&self.scratch.type_map, self.source.checked.types.nodes.items.len);
        try self.allocateEmpty(&self.scratch.variable_map, self.source.checked.types.variables.items.len);
        try self.allocateEmpty(&self.scratch.effect_row_map, self.source.checked.types.effects.rows.items.len);
        try self.allocateEmpty(&self.scratch.effect_variable_map, self.source.checked.types.effects.variables.items.len);
        try self.allocateEmpty(&self.scratch.effect_operation_map, self.source.checked.types.operations.items.len);
        try self.tables.effect_rows.append(self.allocator, .{});
        try self.tables.effect_operations.appendSlice(self.allocator, &.{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } });
        self.scratch.effect_operation_map[T.foreign_operation] = T.foreign_operation;
        try self.allocateEmpty(&self.scratch.ast_map, self.source.tree.nodes.items.len);
        const origins = self.source.tree.operator_origins.items;
        const has_member_origin = for (origins) |origin| {
            if (origin.member_point != 0 and origin.node < self.source.tree.nodes.items.len) break true;
        } else false;
        if (has_member_origin) {
            if (origins.len > std.math.maxInt(u32)) return error.CoreLimit;
            try self.allocateEmpty(&self.scratch.member_origin_heads, self.source.tree.nodes.items.len);
            try self.allocateEmpty(&self.scratch.member_origin_next, origins.len);
            for (origins, 0..) |origin, index| {
                // Invalid owner IDs could not match a valid lowered source in
                // the former scan. Keep that diagnostic-origin fallback.
                if (origin.member_point == 0 or origin.node >= self.scratch.member_origin_heads.len) continue;
                self.scratch.member_origin_next[index] = self.scratch.member_origin_heads[origin.node];
                self.scratch.member_origin_heads[origin.node] = @intCast(index + 1);
            }
        }
        if (self.source.checked.dispatch_signatures.len != 0) for (self.source.checked.dispatch_signatures, 0..) |signature, source| {
            if (signature == 0) continue;
            if (self.scratch.signature_sources.len == 0) try self.allocateEmpty(&self.scratch.signature_sources, self.source.tree.nodes.items.len);
            self.scratch.signature_sources[source] = signature;
        };
        for (self.source.checked.obligations) |obligation| if (obligation.signature != 0) {
            if (self.scratch.signature_sources.len == 0) try self.allocateEmpty(&self.scratch.signature_sources, self.source.tree.nodes.items.len);
            self.scratch.signature_sources[obligation.source] = obligation.signature;
        };
        if (self.source.checked.merges.len != 0) {
            try self.allocateEmpty(&self.scratch.merge_heads, self.source.tree.nodes.items.len);
            @memset(self.scratch.merge_heads, std.math.maxInt(u32));
            try self.allocateEmpty(&self.scratch.merge_next, self.source.checked.merges.len);
            // Prepending backwards preserves source merge order without
            // depending on nested conditionals having contiguous records.
            var index = self.source.checked.merges.len;
            while (index != 0) {
                index -= 1;
                const source = self.source.checked.merges[index].node;
                self.scratch.merge_next[index] = self.scratch.merge_heads[source];
                self.scratch.merge_heads[source] = @intCast(index);
            }
        }
        if (self.source.checked.loop_exits.len != 0) {
            try self.allocateEmpty(&self.scratch.loop_exit_indices, self.source.tree.nodes.items.len);
            for (self.source.checked.loop_exits, 0..) |exit, index| self.scratch.loop_exit_indices[exit.node] = @intCast(index + 1);
        }
        if (self.source.checked.statement_arms.len != 0) {
            try self.allocateEmpty(&self.scratch.statement_arms, self.source.tree.nodes.items.len);
            for (self.source.checked.statement_arms) |arm| self.scratch.statement_arms[arm.node] = 1;
        }
        try self.tables.type_nodes.appendSlice(self.allocator, self.source.checked.types.nodes.items[0..6]);
        for (0..6) |i| self.scratch.type_map[i] = @intCast(i);
        _ = try self.reserve(0);
        try self.tables.bodies.append(self.allocator, .{});
    }
    fn diagnostic(self: *Builder, code: core.Code, source: ast.Id) Error!void {
        try self.tables.diagnostics.append(self.allocator, .{ .code = code, .span = self.source.checked.diagnosticSpan(self.source.tree, source) });
    }
    fn addType(self: *Builder, value: T.Node) Error!T.Id {
        const container: ?usize = switch (value.tag) {
            .array => 0,
            .list => 1,
            .cursor => 2,
            else => null,
        };
        var canonical: ?*T.Id = null;
        if (container) |kind| {
            if (value.a != 0 and value.a < 6 and value.b == 0 and value.c == 0) {
                canonical = &self.scratch.closed_containers[kind][value.a];
                if (canonical.?.* != 0) return canonical.?.*;
            }
        }
        if (self.tables.type_nodes.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const id: T.Id = @intCast(self.tables.type_nodes.items.len);
        const nullary = value.tag == .nominal and self.tables.type_extra.items[value.c] == 0;
        if (nullary) try self.scratch.nullary_nominals.ensureUnusedCapacity(self.allocator, 1);
        try self.tables.type_nodes.append(self.allocator, value);
        if (canonical) |slot| slot.* = id;
        if (nullary) {
            const entry = self.scratch.nullary_nominals.getOrPutAssumeCapacity(.{ .unit = value.a, .decl = value.b });
            if (!entry.found_existing) entry.value_ptr.* = id;
        }
        return id;
    }
    fn projectType(self: *Builder, source: T.Id, depth: usize) Error!T.Id {
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        if (source == 0) return 0;
        if (self.scratch.type_map[source] != 0) return self.scratch.type_map[source];
        if (depth >= 1024) return error.CoreLimit;
        const resolved = self.source.checked.types.head(source, 0);
        if (resolved != source) {
            const id = try self.projectType(resolved, depth + 1);
            self.scratch.type_map[source] = id;
            return id;
        }
        const original = self.source.checked.types.node(resolved);
        // A published root has already resolved all visible writes. Remaining
        // cursor views of one unbound variable therefore denote one principal
        // identity in the immutable artifact, with no future writes allowed.
        if (original.tag == .variable and self.scratch.variable_map[original.a] != 0) {
            const id = self.scratch.variable_map[original.a];
            self.scratch.type_map[source] = id;
            return id;
        }
        const value: T.Node = switch (original.tag) {
            .rigid => {
                if (original.c == 2) {
                    for (self.source.checked.usage_loans) |loan| {
                        const region = self.source.checked.types.node(loan.region);
                        if (region.a != original.a) continue;
                        const binding = self.source.checked.resolved[loan.parameter];
                        if (binding == 0) return error.CoreLimit;
                        const id = try self.addType(.{ .tag = .bound, .a = 0, .b = 2, .c = binding });
                        self.scratch.type_map[source] = id;
                        return id;
                    }
                }

                const owner = for (self.source.checked.rank_implementations) |implementation| {
                    if (implementation.scope == original.a) break implementation;
                } else return error.CoreLimit;
                var quantified_type = owner.quantified;
                if (owner.node != 0 and owner.node < self.source.checked.expr_types.len) {
                    var published = self.source.checked.types.head(self.source.checked.expr_types[owner.node], 0);
                    for (0..128) |_| {
                        const wrapper = self.source.checked.types.node(published);
                        if (wrapper.tag != .usage) break;
                        published = self.source.checked.types.head(wrapper.a, 0);
                    } else return error.CoreLimit;
                    // Solving a result after checking its rank callback may
                    // rebuild the quantifier with fresh owned binder IDs.
                    // Its executable rigid uses belong to that published
                    // callback, not the now unreferenced inference header.
                    if (self.source.checked.types.node(published).tag == .forall) quantified_type = published;
                }
                const quantifier = self.source.checked.types.node(self.source.checked.types.head(quantified_type, 0));
                if ((quantifier.tag != .forall and quantifier.tag != .existential) or original.b >= quantifier.c) return error.CoreLimit;
                const bound = self.source.checked.types.list(.{ .start = quantifier.b, .len = quantifier.c })[original.b];
                const leaf = self.source.checked.types.node(bound);
                if (leaf.tag != .bound or leaf.b != original.c) return error.CoreLimit;
                if (quantifier.tag == .existential) {
                    if (owner.node == 0 or owner.node >= self.source.checked.resolved.len) return error.CoreLimit;
                    const binding = self.source.checked.resolved[owner.node];
                    if (binding == 0 or binding >= self.source.checked.bindings.len or self.source.tree.node(owner.node).tag != .package_unpack) return error.CoreLimit;
                    // Each lexical opening owns separate bound leaves even
                    // when the same existential annotation is opened twice.
                    const id = try self.addType(.{ .tag = .bound, .a = original.b, .b = original.c, .c = binding });
                    self.scratch.type_map[source] = id;
                    return id;
                }
                const result = try self.projectType(bound, depth + 1);
                self.scratch.type_map[source] = result;
                return result;
            },
            .usage => .{ .tag = .usage, .a = try self.projectType(original.a, depth + 1), .b = original.b, .c = if (original.c == 0) 0 else try self.projectType(original.c, depth + 1) },
            .bound => .{ .tag = .bound, .a = original.a, .b = original.b },
            .forall, .existential => blk: {
                var binders: std.ArrayList(T.Id) = .empty;
                defer binders.deinit(allocator);
                for (self.source.checked.types.list(.{ .start = original.b, .len = original.c })) |binder| try binders.append(allocator, try self.projectType(binder, depth + 1));
                const body = try self.projectType(original.a, depth + 1);
                const span = try self.saveTypes(binders.items);
                break :blk .{ .tag = original.tag, .a = body, .b = span.start, .c = span.len };
            },
            .variable => blk: {
                const index = self.scratch.variable_count;
                self.scratch.variable_count += 1;
                break :blk .{ .tag = .variable, .a = index };
            },
            .function => .{ .tag = .function, .a = try self.projectType(original.a, depth + 1), .b = try self.projectType(original.b, depth + 1), .c = try self.projectRow(original.c, depth + 1) },
            .product => blk: {
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(allocator);
                for (self.source.checked.types.list(.{ .start = original.a, .len = original.b })) |child| try fields.append(allocator, try self.projectType(child, depth + 1));
                const span = try self.saveTypes(fields.items);
                break :blk .{ .tag = .product, .a = span.start, .b = span.len };
            },
            .record => blk: {
                var fields: std.ArrayList(T.Id) = .empty;
                defer fields.deinit(allocator);
                for (0..original.b) |index| {
                    const field = self.source.checked.types.recordField(original, index);
                    try self.saveFieldName(field.name);
                    try fields.appendSlice(allocator, &.{ field.name, try self.projectType(field.ty, depth + 1) });
                }
                const span = try self.saveTypes(fields.items);
                break :blk .{ .tag = .record, .a = span.start, .b = original.b };
            },
            .nominal, .projection, .instance_selection => blk: {
                if (original.tag == .nominal and self.source.checked.types.nominalArguments(original).len == 0) {
                    if (self.scratch.nullary_nominals.get(.{ .unit = original.a, .decl = original.b })) |id| {
                        self.scratch.type_map[source] = id;
                        return id;
                    }
                }
                var arguments: std.ArrayList(T.Id) = .empty;
                defer arguments.deinit(allocator);
                const source_arguments = self.source.checked.types.nominalArguments(original);
                try arguments.append(allocator, @intCast(source_arguments.len));
                for (source_arguments) |argument| try arguments.append(allocator, try self.projectType(argument, depth + 1));
                if (original.tag == .projection) try arguments.append(allocator, self.source.checked.types.projectionMember(original));
                const span = try self.saveTypes(arguments.items);
                break :blk .{ .tag = original.tag, .a = original.a, .b = original.b, .c = span.start };
            },
            .scoped => .{ .tag = .scoped, .a = try self.projectType(original.a, depth + 1), .b = original.b, .c = if (original.b == 0) try self.projectType(original.c, depth + 1) else original.c },
            .array, .list, .cursor, .resolver => .{ .tag = original.tag, .a = try self.projectType(original.a, depth + 1) },
            .demand, .provider => .{ .tag = original.tag, .a = try self.projectType(original.a, depth + 1), .c = try self.projectRow(original.c, depth + 1) },
            .state_provider => .{ .tag = .state_provider, .a = try self.projectType(original.a, depth + 1), .b = try self.projectType(original.b, depth + 1), .c = try self.projectType(original.c, depth + 1) },
            else => original,
        };
        const id = try self.addType(value);
        self.scratch.type_map[source] = id;
        if (original.tag == .variable) self.scratch.variable_map[original.a] = id;
        if (original.tag == .forall or original.tag == .existential) {
            const goals = self.source.checked.types.quantifierGoals(source);
            if (goals.len != 0) {
                const start: u32 = @intCast(self.tables.quantifier_obligations.items.len);
                try self.tables.quantifier_obligations.appendNTimes(self.allocator, .{ .ty = 0, .kind = .type_rep, .source = 0 }, goals.len);
                try self.tables.quantifier_goals.append(self.allocator, .{ .owner = id, .goals = .{ .start = start, .len = @intCast(goals.len) } });
                for (goals, 0..) |old, ordinal| {
                    var goal = old;
                    inline for (.{ "ty", "other", "result", "signature" }) |field| @field(goal, field) = try self.projectType(@field(old, field), depth + 1);
                    goal.source = 0;
                    self.tables.quantifier_obligations.items[start + ordinal] = goal;
                }
            }
        }
        return id;
    }
    fn projectRowVariable(self: *Builder, variable: u32) Error!u32 {
        if (variable >= self.scratch.effect_variable_map.len) return error.CoreLimit;
        if (self.scratch.effect_variable_map[variable] != 0) return self.scratch.effect_variable_map[variable] - 1;
        if (self.scratch.effect_variable_count == std.math.maxInt(u32)) return error.CoreLimit;
        const id = self.scratch.effect_variable_count;
        self.scratch.effect_variable_count += 1;
        self.scratch.effect_variable_map[variable] = id + 1;
        return id;
    }
    fn projectInstance(self: *Builder, original: T.NominalIdentity, depth: usize) Error!T.NominalIdentity {
        if (original.unit != 0 or original.decl == 0) return original;
        const projected = try self.projectType(original.decl, depth + 1);
        const node_ = self.tables.type_nodes.items[projected];
        // A quantified instance variable can resolve to its scoped carrier.
        // Freeze the carrier's owner, rather than publishing it as an instance term.
        if (node_.tag == .scoped) return .{ .unit = node_.b, .decl = node_.c };
        if (node_.tag != .variable and node_.tag != .instance_selection) return error.CoreLimit;
        return .{ .unit = 0, .decl = projected };
    }
    fn projectOperation(self: *Builder, label: T.Effects.Label, depth: usize) Error!T.Effects.Label {
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        if (depth >= 1024 or label == 0 or label >= self.scratch.effect_operation_map.len) return error.CoreLimit;
        if (self.scratch.effect_operation_map[label] != 0) return self.scratch.effect_operation_map[label];
        const source = self.source.checked.types.operations.items[label];
        var values: std.ArrayList(T.Id) = .empty;
        defer values.deinit(allocator);
        for (self.source.checked.types.list(source.arguments)) |argument| try values.append(allocator, try self.projectType(argument, depth + 1));
        const arguments = try self.saveTypes(values.items);
        if (self.tables.effect_operations.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const id: u32 = @intCast(self.tables.effect_operations.items.len);
        try self.tables.effect_operations.append(self.allocator, .{ .identity = source.identity, .arguments = arguments, .instance = try self.projectInstance(source.instance, depth + 1) });
        self.scratch.effect_operation_map[label] = id;
        return id;
    }
    fn projectRow(self: *Builder, source: T.Effects.Id, depth: usize) Error!T.Effects.Id {
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        if (source == 0) return 0;
        if (depth >= 1024 or source >= self.scratch.effect_row_map.len) return error.CoreLimit;
        if (self.scratch.effect_row_map[source] != 0) return self.scratch.effect_row_map[source] - 1;
        // Checker publication resolves the complete type graph at its exact
        // chronological cursor. Frozen rows retain labels and principal tail
        // identity, with no further substitutions or historical cursor.
        const original = self.source.checked.types.effects.node(source);
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(allocator);
        for (self.source.checked.types.effects.list(original.labels)) |label| try labels.append(allocator, try self.projectOperation(label, depth + 1));
        const tail: T.Effects.Tail = switch (original.tail) {
            .closed => .closed,
            .variable => |variable| .{ .variable = try self.projectRowVariable(variable) },
            .parameter => |parameter| .{ .parameter = parameter },
            .formal => |formal| .{ .formal = try self.projectType(formal, depth + 1) },
        };
        if (labels.items.len == 0 and tail == .closed) {
            self.scratch.effect_row_map[source] = 1;
            return 0;
        }
        if (self.tables.effect_rows.items.len == std.math.maxInt(u32) or labels.items.len > std.math.maxInt(u32) - self.tables.effect_labels.items.len) return error.CoreLimit;
        const start: u32 = @intCast(self.tables.effect_labels.items.len);
        try self.tables.effect_labels.appendSlice(allocator, labels.items);
        const id: u32 = @intCast(self.tables.effect_rows.items.len);
        try self.tables.effect_rows.append(self.allocator, .{ .labels = .{ .start = start, .len = @intCast(labels.items.len) }, .tail = tail });
        self.scratch.effect_row_map[source] = id + 1;
        return id;
    }
    fn saveTypes(self: *Builder, values: []const T.Id) Error!T.List {
        if (values.len > std.math.maxInt(u32) - self.tables.type_extra.items.len) return error.CoreLimit;
        const start: u32 = @intCast(self.tables.type_extra.items.len);
        try self.tables.type_extra.appendSlice(self.allocator, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    fn projectScheme(self: *Builder, scheme: T.Scheme, local: bool) Error!T.Scheme {
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        const root = try self.projectType(scheme.root, 0);
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(allocator);
        for (self.source.checked.types.list(scheme.variables)) |id| {
            const projected = try self.projectType(id, 0);
            // A local initializer can constrain an earlier inferred scheme
            // after generalization (for example a comprehension index). Core
            // owns the final resolved root and predicates: a solved ordinary
            // binder is no longer quantified, and aliased binders are one
            // variable. Exported and explicit quantifier owners stay intact.
            if (local and self.tables.type_nodes.items[root].tag != .forall and self.tables.type_nodes.items[root].tag != .existential) {
                if (self.tables.type_nodes.items[projected].tag != .variable) continue;
                if (std.mem.findScalar(T.Id, variables.items, projected) != null) continue;
            }
            try variables.append(allocator, projected);
        }
        var universal = root;
        var scopes: usize = 0;
        while (self.tables.type_nodes.items[universal].tag == .forall) {
            if (scopes == 128) return error.CoreLimit;
            scopes += 1;
            const quantifier = self.tables.type_nodes.items[universal];
            for (self.tables.type_extra.items[quantifier.b..][0..quantifier.c]) |binder| try variables.append(allocator, binder);
            universal = quantifier.a;
        }
        const span = try self.saveTypes(variables.items);
        var row_variables: std.ArrayList(T.Id) = .empty;
        defer row_variables.deinit(allocator);
        for (self.source.checked.types.list(scheme.row_variables)) |variable| try row_variables.append(allocator, try self.projectRowVariable(variable));
        const row_span = try self.saveTypes(row_variables.items);
        row_variables.clearRetainingCapacity();
        for (self.source.checked.types.list(scheme.closed_rows)) |variable| try row_variables.append(allocator, try self.projectRowVariable(variable));
        const closed_span = try self.saveTypes(row_variables.items);
        const start: u32 = @intCast(self.tables.obligations.items.len);
        for (self.source.checked.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |value| try self.tables.obligations.append(self.allocator, .{ .ty = try self.projectType(value.ty, 0), .kind = value.kind, .span = self.source.checked.diagnosticSpan(self.source.tree, value.source), .name = value.name, .result = try self.projectType(value.result, 0), .other = try self.projectType(value.other, 0), .signature = try self.projectType(value.signature, 0), .operator = value.operator, .identity = value.identity, .explicit = value.explicit, .qualification_span = value.qualification_span, .qualification_unit = value.qualification_unit, .diagnostic_name = if (value.explicit and value.name != 0) try self.saveName(self.source.names.get(value.name)) else .{} });
        return .{ .root = root, .variables = span, .row_variables = row_span, .closed_rows = closed_span, .generative = try self.projectPublic(scheme.generative, false), .obligations = .{ .start = start, .len = @intCast(self.tables.obligations.items.len - start) } };
    }
    fn projectPublic(self: *Builder, public: T.List, rows: bool) Error!T.List {
        var projected: std.ArrayList(T.Id) = .empty;
        defer projected.deinit(self.allocator);
        for (self.source.checked.types.list(public)) |id| try projected.append(self.allocator, if (rows) try self.projectRowVariable(id) else try self.projectType(id, 0));
        return self.saveTypes(projected.items);
    }
    fn reserve(self: *Builder, source: ast.Id) Error!core.Id {
        if (self.tables.nodes.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const id: core.Id = @intCast(self.tables.nodes.items.len);
        try self.tables.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.tables.spans.ensureUnusedCapacity(self.allocator, 1);
        try self.tables.merge_ranges.ensureUnusedCapacity(self.allocator, 1);
        try self.tables.dispatch_signatures.ensureUnusedCapacity(self.allocator, 1);
        self.tables.nodes.appendAssumeCapacity(.{ .tag = .invalid });
        self.tables.spans.appendAssumeCapacity(self.source.checked.diagnosticSpan(self.source.tree, source));
        self.tables.merge_ranges.appendAssumeCapacity(.{});
        self.tables.dispatch_signatures.appendAssumeCapacity(0);
        return id;
    }
    fn make(self: *Builder, source: ast.Id, value: core.Node) Error!core.Id {
        const id = try self.reserve(source);
        self.tables.nodes.items[id] = value;
        if (value.tag == .call or value.tag == .reference) {
            const span = self.source.tree.span(source);
            for (self.source.checked.selected_uses) |use| {
                const origin = self.source.tree.span(use.source);
                if (origin.start < span.start or origin.end > span.end) continue;
                try self.tables.selected_uses.append(self.allocator, .{ .node = id, .proof = use.proof });
            }
        }

        if (value.tag == .project and self.tables.projections.items[value.b].diagnostic_point == 0) {
            const field = self.tables.projections.items[value.b].field;
            var member_point: u32 = 0;
            var matches: usize = 0;
            var next = if (source < self.scratch.member_origin_heads.len) self.scratch.member_origin_heads[source] else 0;
            while (next != 0) {
                const index = next - 1;
                const origin = self.source.tree.operator_origins.items[index];
                next = self.scratch.member_origin_next[index];
                if (origin.member != field) continue;
                matches += 1;
                member_point = origin.member_point;
                if (matches == 2) break;
            }
            // Repeated same-name components require a path-level origin; do
            // not guess which source token produced a particular projection.
            if (matches == 1) {
                const ordinary = self.source.tree.span(source);
                const selected = self.source.checked.diagnosticSpan(self.source.tree, source);
                self.tables.projections.items[value.b].diagnostic_point = if (selected.start != ordinary.start or selected.end != ordinary.end) selected.start else member_point;
            }
        }
        if (value.tag == .bind and value.a != 0 and value.a < self.tables.bindings.items.len) {
            self.tables.bindings.items[value.a].initializer = value.b;
            if (self.tables.nodes.items[value.b].tag == .closure) {
                const template = &self.tables.closures.items[self.tables.nodes.items[value.b].a];
                if (template.qualifier == 0) template.qualifier = value.a;
            }
        }
        if (self.scratch.signature_sources.len != 0 and self.scratch.signature_sources[source] != 0) {
            const signature = try self.projectType(self.scratch.signature_sources[source], 0);
            const callable = self.tables.type_nodes.items[signature];
            // One selector AST may publish several path projections. Each
            // method consumes its immediate receiver and produces this path
            // component; the enclosing selector's leaf is a different result.
            self.tables.dispatch_signatures.items[id] = if (value.tag == .project and callable.tag == .function)
                try self.addType(.{ .tag = .function, .a = self.tables.nodes.items[value.a].ty, .b = value.ty, .c = callable.c })
            else
                signature;
        }
        return id;
    }
    fn save(self: *Builder, values: []const core.Id) Error!core.List {
        if (values.len > std.math.maxInt(u32) - self.tables.extra.items.len) return error.CoreLimit;
        const start: u32 = @intCast(self.tables.extra.items.len);
        try self.tables.extra.appendSlice(self.allocator, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    fn unwrap(self: *const Builder, original: ast.Id) ast.Id {
        var source = original;
        while (self.source.tree.node(source).tag == .group) source = self.source.tree.node(source).a;
        return source;
    }
    fn target(self: *const Builder, binding: core.BindingId) core.BindingRef {
        if (binding >= self.source.checked.bindings.len) return .{ .binding = binding };
        const value = self.source.checked.bindings[binding];
        return if (value.external) |external| .{ .unit = external.unit, .binding = external.binding } else .{ .binding = binding };
    }
    fn typeOf(self: *Builder, source: ast.Id) Error!T.Id {
        return self.projectType(self.source.checked.expr_types[source], 0);
    }
    fn referenceNode(self: *Builder, source: ast.Id, binding: core.BindingId, ty: T.Id) Error!core.Id {
        const index: u32 = @intCast(self.tables.references.items.len);
        try self.tables.references.append(self.allocator, self.target(binding));
        return self.make(source, .{ .tag = .reference, .ty = ty, .a = index });
    }
    fn saveFieldName(self: *Builder, symbol: u32) Error!void {
        if (symbol == 0) return;
        const saved = try self.scratch.saved_fields.getOrPut(self.allocator, symbol);
        if (!saved.found_existing) try self.tables.field_names.append(self.allocator, .{ .symbol = symbol, .spelling = try self.saveName(self.source.names.get(symbol)) });
    }
    fn projectionIndex(self: *Builder, catalog: u32, source_type: T.Id, result_type: T.Id) Error!u32 {
        const metadata = self.source.checked.projection_catalog[catalog];
        // A generic field constraint need not leave a concrete record type in
        // this module. Its executable projection still owns the field spelling.
        try self.saveFieldName(metadata.field);
        const start: u32 = @intCast(self.tables.projection_variants.items.len);
        const words = self.source.checked.types.list(metadata.variants);
        var offset: usize = 0;
        while (offset < words.len) : (offset += 2) try self.tables.projection_variants.append(self.allocator, .{ .tag = words[offset], .field = words[offset + 1] });
        const index: u32 = @intCast(self.tables.projections.items.len);
        try self.tables.projections.append(self.allocator, .{ .nominal = metadata.nominal, .field = metadata.field, .source_type = source_type, .result_type = result_type, .variants = .{ .start = start, .len = @intCast(words.len / 2) } });
        return index;
    }
    fn directProjection(self: *Builder, source_type: T.Id, result_type: T.Id, field: u32) Error!u32 {
        const start: u32 = @intCast(self.tables.projection_variants.items.len);
        try self.tables.projection_variants.append(self.allocator, .{ .tag = 0, .field = field });
        const index: u32 = @intCast(self.tables.projections.items.len);
        try self.tables.projections.append(self.allocator, .{ .nominal = .{ .unit = 0, .decl = 0 }, .source_type = source_type, .result_type = result_type, .variants = .{ .start = start, .len = 1 } });
        return index;
    }
    fn resolvedReference(self: *Builder, source: ast.Id, ty: T.Id) Error!core.Id {
        const binding = self.source.checked.resolved[source];
        if (binding == 0) {
            try self.diagnostic(.unresolved_binding, source);
            return 0;
        }
        return self.projectedReference(source, binding, ty, source);
    }
    fn projectedReference(self: *Builder, source: ast.Id, binding: core.BindingId, ty: T.Id, path_source: ast.Id) Error!core.Id {
        const path = if (path_source < self.source.checked.access_paths.len) self.source.checked.types.list(self.source.checked.access_paths[path_source]) else &.{};
        if (path.len == 0) return self.referenceNode(source, binding, ty);
        const type_path = self.source.checked.types.list(self.source.checked.access_types[path_source]);
        if (type_path.len != path.len + 1) {
            try self.diagnostic(.unresolved_binding, source);
            return 0;
        }
        var result = try self.referenceNode(source, binding, try self.projectType(type_path[0], 0));
        for (path, 0..) |catalog, index| {
            const result_ty = try self.projectType(type_path[index + 1], 0);
            const projection = try self.projectionIndex(catalog, self.tables.nodes.items[result].ty, result_ty);
            result = try self.make(source, .{ .tag = .project, .ty = result_ty, .a = result, .b = projection });
        }
        return result;
    }
    fn productExpression(self: *Builder, source: ast.Id, ty: T.Id, tag: core.Tag, depth: usize) Error!core.Id {
        var storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        var values: std.ArrayList(core.Id) = .empty;
        defer values.deinit(scratch);
        try values.ensureTotalCapacityPrecise(scratch, @min(self.source.tree.children(source).len, 16));
        for (self.source.tree.children(source)) |child| try values.append(scratch, try self.expression(child, depth + 1));
        const range = try self.save(values.items);
        return self.make(source, .{ .tag = tag, .ty = ty, .a = range.start, .b = range.len });
    }
    fn stringExpression(self: *Builder, source: ast.Id, ty: T.Id) Error!core.Id {
        const bytes = self.source.names.get(self.source.tree.node(source).a);
        var buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
        const scratch = storage.allocator();
        var values: std.ArrayList(core.Id) = .empty;
        defer values.deinit(scratch);
        var points = std.unicode.Utf8View.initUnchecked(bytes).iterator();
        while (points.nextCodepoint()) |point| {
            try values.append(scratch, try self.make(source, .{ .tag = .constant, .ty = T.u32_type, .a = point }));
        }
        const range = try self.save(values.items);
        return self.make(source, .{ .tag = .array, .ty = ty, .a = range.start, .b = range.len });
    }
    fn recordExpression(self: *Builder, source: ast.Id, ty: T.Id, depth: usize) Error!core.Id {
        const catalog = if (source < self.source.checked.constructor_resolved.len) self.source.checked.constructor_resolved[source] else 0;
        if (catalog == 0 and self.source.tree.node(source).a != 0) {
            try self.diagnostic(.unresolved_binding, source);
            return 0;
        }
        const fields = self.source.tree.children(source);
        if (catalog != 0 and fields.len == 0 and self.source.checked.constructors[catalog].payload == 0)
            return self.make(source, .{ .tag = .construct, .ty = ty, .a = catalog });
        var values: std.ArrayList(core.Id) = .empty;
        defer values.deinit(self.allocator);
        var destinations: std.ArrayList(core.Id) = .empty;
        defer destinations.deinit(self.allocator);
        const field_words = std.math.mul(usize, fields.len, 2) catch return error.CoreLimit;
        const field_types = try self.allocator.alloc(T.Id, field_words);
        defer self.allocator.free(field_types);
        @memset(field_types, 0);
        for (fields) |field| {
            const syntax = self.source.tree.node(field);
            const destination = self.source.checked.projections[field];
            if (destination >= fields.len) {
                try self.diagnostic(.unresolved_binding, field);
                return 0;
            }
            const value = if (syntax.b == 0) try self.resolvedReference(field, try self.typeOf(field)) else try self.expression(syntax.b, depth + 1);
            try values.append(self.allocator, value);
            try destinations.append(self.allocator, destination);
            field_types[destination * 2] = syntax.a;
            field_types[destination * 2 + 1] = self.tables.nodes.items[value].ty;
        }
        const type_range = try self.saveTypes(field_types);
        const payload_ty = try self.addType(.{ .tag = .record, .a = type_range.start, .b = @intCast(fields.len) });
        const value_range = try self.save(values.items);
        var result_ty = payload_ty;
        if (catalog == 0 and self.tables.type_nodes.items[ty].tag == .usage) {
            result_ty = ty;
            const required = self.tables.type_nodes.items[self.tables.type_nodes.items[ty].a];
            if (required.tag != .record or required.b != fields.len) return error.CoreLimit;
            for (fields, destinations.items) |field, *destination| {
                const name = self.source.tree.node(field).a;
                var found = false;
                for (0..required.b) |index| if (self.tables.type_extra.items[required.a + index * 2] == name) {
                    destination.* = @intCast(index);
                    found = true;
                    break;
                };
                if (!found) return error.CoreLimit;
            }
        }
        const destination_range = try self.save(destinations.items);
        const payload = try self.make(source, .{ .tag = .record, .ty = result_ty, .a = value_range.start, .b = value_range.len, .c = destination_range.start });
        if (catalog == 0) return payload;
        return self.make(source, .{ .tag = .construct, .ty = ty, .a = catalog, .b = payload });
    }
    fn addPattern(self: *Builder, source: ast.Id, value: core.Pattern) Error!core.PatternId {
        if (self.tables.patterns.items.len == 0) try self.tables.patterns.append(self.allocator, .{ .tag = .invalid });
        const index: core.PatternId = @intCast(self.tables.patterns.items.len);
        var owned = value;
        owned.span = self.source.tree.span(source);
        try self.tables.patterns.append(self.allocator, owned);
        return index;
    }
    fn patternNode(self: *Builder, source: ast.Id, depth: usize) Error!core.PatternId {
        if (depth >= 1024) {
            try self.diagnostic(.complexity, source);
            return 0;
        }
        const syntax = self.source.tree.node(source);
        const ty = try self.typeOf(source);
        return switch (syntax.tag) {
            .pattern_name => blk: {
                if (std.mem.eql(u8, self.source.names.get(syntax.a), "_")) break :blk try self.addPattern(source, .{ .tag = .wildcard, .ty = ty });
                const binding = self.source.checked.resolved[source];
                if (binding == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    break :blk 0;
                }
                break :blk try self.addPattern(source, .{ .tag = .bind, .ty = ty, .a = binding });
            },
            .pattern_integer, .pattern_boolean => self.addPattern(source, .{ .tag = .constant, .ty = ty, .a = syntax.a }),
            .pattern_value => self.addPattern(source, .{ .tag = .value, .ty = ty, .a = try self.resolvedReference(source, ty) }),
            .pattern_constructor => blk: {
                const catalog = self.source.checked.constructor_resolved[source];
                if (catalog == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    break :blk 0;
                }
                const metadata = self.source.checked.constructors[catalog];
                var payload: core.PatternId = 0;
                if (metadata.payload != 0 and syntax.b != 0) {
                    payload = try self.patternNode(syntax.b, depth + 1);
                    const record = self.source.checked.types.node(metadata.payload);
                    if (!self.source.checked.nominals[metadata.nominal].is_opaque and record.tag == .record and self.source.tree.node(syntax.b).tag != .pattern_record) {
                        const child_ty = self.tables.patterns.items[payload].ty;
                        const child = self.tables.type_nodes.items[child_ty];
                        if (record.b == 0 or (record.b != 1 and (child.tag != .product or child.b != record.b))) return error.CoreLimit;
                        var fields: std.ArrayList(T.Id) = .empty;
                        defer fields.deinit(self.allocator);
                        for (0..record.b) |index| {
                            const field = self.source.checked.types.recordField(record, index);
                            const field_ty = if (record.b == 1) child_ty else self.tables.type_extra.items[child.a + index];
                            try fields.appendSlice(self.allocator, &.{ field.name, field_ty });
                        }
                        const range = try self.saveTypes(fields.items);
                        const record_ty = try self.addType(.{ .tag = .record, .a = range.start, .b = record.b });
                        payload = try self.addPattern(syntax.b, .{ .tag = .record_payload, .ty = record_ty, .a = record.b, .b = payload });
                    }
                }
                break :blk try self.addPattern(source, .{ .tag = .constructor, .ty = ty, .a = catalog, .b = payload });
            },
            .pattern_product => blk: {
                if (self.source.tree.children(source).len == 0 and ty == T.unit)
                    break :blk try self.addPattern(source, .{ .tag = .constant, .ty = T.unit });
                var children: std.ArrayList(core.Id) = .empty;
                defer children.deinit(self.allocator);
                for (self.source.tree.children(source)) |child| try children.append(self.allocator, try self.patternNode(child, depth + 1));
                const range = try self.save(children.items);
                break :blk try self.addPattern(source, .{ .tag = .product, .ty = ty, .a = range.start, .b = range.len });
            },
            .pattern_record => blk: {
                const record_ty = self.tables.type_nodes.items[ty];
                if (record_ty.tag != .record) {
                    try self.diagnostic(.unsupported, source);
                    break :blk 0;
                }
                const children = try self.allocator.alloc(core.Id, record_ty.b);
                defer self.allocator.free(children);
                for (children, 0..) |*child, index| child.* = try self.addPattern(source, .{ .tag = .wildcard, .ty = self.tables.type_extra.items[record_ty.a + index * 2 + 1] });
                for (self.source.tree.children(source)) |field| {
                    const field_syntax = self.source.tree.node(field);
                    const destination = self.source.checked.projections[field];
                    if (destination >= children.len) {
                        try self.diagnostic(.unresolved_binding, field);
                        break :blk 0;
                    }
                    if (field_syntax.b != 0) {
                        children[destination] = try self.patternNode(field_syntax.b, depth + 1);
                    } else {
                        const binding = self.source.checked.resolved[field];
                        const field_ty = self.tables.type_extra.items[record_ty.a + destination * 2 + 1];
                        children[destination] = try self.addPattern(field, .{ .tag = if (binding == 0) .wildcard else .bind, .ty = field_ty, .a = binding });
                    }
                }
                const range = try self.save(children);
                break :blk try self.addPattern(source, .{ .tag = .product, .ty = ty, .a = range.start, .b = range.len });
            },
            else => blk: {
                try self.diagnostic(.unsupported, source);
                break :blk 0;
            },
        };
    }
    fn addPatternRow(self: *Builder, patterns: []const core.PatternId) Error!u32 {
        const range = try self.save(patterns);
        const index: u32 = @intCast(self.tables.pattern_rows.items.len);
        try self.tables.pattern_rows.append(self.allocator, .{ .patterns = range });
        return index;
    }
    fn caseExpression(self: *Builder, source: ast.Id, ty: T.Id, depth: usize) Error!core.Id {
        const syntax = self.source.tree.node(source);
        const source_inputs = self.source.tree.extra.items[syntax.a..][0..2];
        var inputs: std.ArrayList(core.Id) = .empty;
        defer inputs.deinit(self.allocator);
        for (self.source.tree.list(.{ .start = source_inputs[0], .len = source_inputs[1] })) |input| try inputs.append(self.allocator, try self.expression(input, depth + 1));
        const input_range = try self.save(inputs.items);
        var arms: std.ArrayList(core.MatchArm) = .empty;
        defer arms.deinit(self.allocator);
        for (self.source.tree.list(.{ .start = syntax.b, .len = syntax.c })) |arm_source| {
            const arm_syntax = self.source.tree.node(arm_source);
            const row_start: u32 = @intCast(self.tables.pattern_rows.items.len);
            for (self.source.tree.list(.{ .start = arm_syntax.a, .len = arm_syntax.b })) |row_source| {
                var patterns: std.ArrayList(core.Id) = .empty;
                defer patterns.deinit(self.allocator);
                for (self.source.tree.children(row_source)) |pattern_source| try patterns.append(self.allocator, try self.patternNode(pattern_source, depth + 1));
                _ = try self.addPatternRow(patterns.items);
            }
            const row_range: core.List = .{ .start = row_start, .len = @intCast(self.tables.pattern_rows.items.len - row_start) };
            const details = self.source.tree.extra.items[arm_syntax.c..][0..2];
            try arms.append(self.allocator, .{ .rows = row_range, .guard = try self.expression(details[0], depth + 1), .body = try self.expression(details[1], depth + 1), .span = self.source.tree.span(arm_source) });
        }
        const arm_start: u32 = @intCast(self.tables.match_arms.items.len);
        try self.tables.match_arms.appendSlice(self.allocator, arms.items);
        const index: u32 = @intCast(self.tables.matches.items.len);
        try self.tables.matches.append(self.allocator, .{ .inputs = input_range, .arms = .{ .start = arm_start, .len = @intCast(arms.items.len) } });
        return self.make(source, .{ .tag = .match, .ty = ty, .a = index });
    }
    fn noteCapture(self: *Builder, binding: core.BindingId, epoch: u32, captures: *std.ArrayList(core.BindingId)) Error!void {
        if (binding == 0 or self.tables.bindings.items[binding].kind == .global or self.tables.bindings.items[binding].kind == .external) return;
        if (self.scratch.reference_epochs[binding] == epoch) return;
        self.scratch.reference_epochs[binding] = epoch;
        try captures.append(self.allocator, binding);
    }
    fn patternCaptures(self: *Builder, id: core.PatternId, epoch: u32, captures: *std.ArrayList(core.BindingId), depth: usize) Error!void {
        if (id == 0) return;
        if (depth >= 1024) return error.CoreLimit;
        const value = self.tables.patterns.items[id];
        switch (value.tag) {
            .bind => self.scratch.definition_epochs[value.a] = epoch,
            .value => try self.nodeCaptures(value.a, epoch, captures, depth + 1),
            .product => for (self.tables.extra.items[value.a..][0..value.b]) |child| try self.patternCaptures(child, epoch, captures, depth + 1),
            .constructor, .record_payload => try self.patternCaptures(value.b, epoch, captures, depth + 1),
            else => {},
        }
    }
    /// Walk each direct body graph once. A nested closure contributes only its
    /// capture list, so its bound locals cannot leak into an enclosing frame.
    fn nodeCaptures(self: *Builder, id: core.Id, epoch: u32, captures: *std.ArrayList(core.BindingId), depth: usize) Error!void {
        if (id == 0 or self.scratch.visit_epochs.items[id] == epoch) return;
        if (depth >= 1024) return error.CoreLimit;
        self.scratch.visit_epochs.items[id] = epoch;
        const value = self.tables.nodes.items[id];
        switch (value.tag) {
            .staging => {
                const op: @import("typed_staging.zig").Op = @fromBackingInt(value.c);
                if (op == .quote) return self.quoteCaptures(value.a, epoch, captures, depth + 1);
                // Enclosing quotation walks own lift/splice construction.
                if (op == .lift or op == .splice) return;
                try self.nodeCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
            },
            .operation_value => try self.nodeCaptures(self.tables.operation_values.items[value.a].capability, epoch, captures, depth + 1),
            .effect_reflection => {
                const kind: checked_types.ReflectionKind = @fromBackingInt(@intCast(value.a));
                if (kind == .count or kind == .has or kind == .same) try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                if (value.c != 0) try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .resource_release, .usage_share, .usage_read, .computation, .effect_scope => try self.nodeCaptures(value.a, epoch, captures, depth + 1),
            .resource_scope => {
                try self.nodeCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .resource_acquire, .usage_borrow => {
                try self.nodeCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
            },
            .request_decision => {
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .request_loop => {
                const info = self.tables.request_loops.items[value.a];
                try self.nodeCaptures(info.computation, epoch, captures, depth + 1);
                for (self.tables.request_arms.items[info.arms.start..][0..info.arms.len]) |arm| {
                    try self.nodeCaptures(arm.callback, epoch, captures, depth + 1);
                    if (arm.selector != 0) try self.nodeCaptures(arm.selector, epoch, captures, depth + 1);
                }
                for (self.tables.loop_carries.items[info.carries.start..][0..info.carries.len]) |carry| {
                    try self.noteCapture(carry.incoming, epoch, captures);
                    self.scratch.definition_epochs[carry.outgoing] = epoch;
                }
                for (self.tables.extra.items[info.completion_state_bindings.start..][0..info.completion_state_bindings.len]) |binding| self.scratch.definition_epochs[binding] = epoch;
                try self.patternCaptures(info.completion_pattern, epoch, captures, depth + 1);
                try self.nodeCaptures(info.completion_body, epoch, captures, depth + 1);
            },
            .reference => {
                const ref = self.tables.references.items[value.a];
                if (ref.unit == 0) try self.noteCapture(ref.binding, epoch, captures);
            },
            .closure, .suspend_ => {
                const range = self.tables.closures.items[value.a].captures;
                for (self.tables.extra.items[range.start..][0..range.len]) |binding| try self.noteCapture(binding, epoch, captures);
            },
            .resolver_op => {
                const info = self.tables.resolver_ops.items[value.a];
                try self.nodeCaptures(info.resolver, epoch, captures, depth + 1);
                for (self.tables.extra.items[info.arguments.start..][0..info.arguments.len]) |argument| try self.nodeCaptures(argument, epoch, captures, depth + 1);
            },
            .bind => {
                self.scratch.definition_epochs[value.a] = epoch;
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
            },
            .return_, .result_associated, .force => try self.nodeCaptures(value.a, epoch, captures, depth + 1),
            .block, .suite, .product, .record, .array, .array_op, .storage, .task => {
                for (self.tables.extra.items[value.a..][0..value.b]) |child| try self.nodeCaptures(child, epoch, captures, depth + 1);
            },
            .call, .break_ => for (self.tables.extra.items[value.b..][0..value.c]) |child| try self.nodeCaptures(child, epoch, captures, depth + 1),
            .loop => {
                const info = self.tables.loops.items[value.a];
                try self.nodeCaptures(info.first, epoch, captures, depth + 1);
                try self.nodeCaptures(info.end, epoch, captures, depth + 1);
                const carries = self.tables.loop_carries.items[info.carries.start..][0..info.carries.len];
                for (carries) |carry| {
                    try self.noteCapture(carry.incoming, epoch, captures);
                    self.scratch.definition_epochs[carry.iteration] = epoch;
                    self.scratch.definition_epochs[carry.outgoing] = epoch;
                }
                try self.patternCaptures(info.pattern, epoch, captures, depth + 1);
                try self.nodeCaptures(info.body, epoch, captures, depth + 1);
                for (carries) |carry| try self.noteCapture(carry.backedge, epoch, captures);
            },
            .scalar, .logical, .apply, .associated, .record_merge, .type_same, .effect_provider, .handle, .proof_guard => {
                try self.nodeCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
            },
            .if_value, .if_stmt, .state_provider => {
                try self.nodeCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .construct => try self.nodeCaptures(value.b, epoch, captures, depth + 1),
            .project => try self.nodeCaptures(value.a, epoch, captures, depth + 1),
            .pattern_bind => {
                try self.patternCaptures(value.a, epoch, captures, depth + 1);
                try self.nodeCaptures(value.b, epoch, captures, depth + 1);
                try self.nodeCaptures(value.c, epoch, captures, depth + 1);
            },
            .match => {
                const info = self.tables.matches.items[value.a];
                for (self.tables.extra.items[info.inputs.start..][0..info.inputs.len]) |input| try self.nodeCaptures(input, epoch, captures, depth + 1);
                for (self.tables.match_arms.items[info.arms.start..][0..info.arms.len]) |arm| {
                    for (self.tables.pattern_rows.items[arm.rows.start..][0..arm.rows.len]) |row| {
                        for (self.tables.extra.items[row.patterns.start..][0..row.patterns.len]) |pattern| try self.patternCaptures(pattern, epoch, captures, depth + 1);
                    }
                    try self.nodeCaptures(arm.guard, epoch, captures, depth + 1);
                    try self.nodeCaptures(arm.body, epoch, captures, depth + 1);
                }
            },
            .update => {
                const info = self.tables.updates.items[value.a];
                if (info.self_binding != 0) self.scratch.definition_epochs[info.self_binding] = epoch;
                try self.nodeCaptures(info.root, epoch, captures, depth + 1);
                for (self.tables.update_steps.items[info.selectors.start..][0..info.selectors.len]) |step| try self.nodeCaptures(step.index, epoch, captures, depth + 1);
                try self.nodeCaptures(info.value, epoch, captures, depth + 1);
            },
            else => {},
        }
        const range = self.tables.merge_ranges.items[id];
        for (self.tables.merges.items[range.start..][0..range.len]) |merge| {
            self.scratch.definition_epochs[merge.result] = epoch;
            try self.noteCapture(merge.then_binding, epoch, captures);
            try self.noteCapture(merge.else_binding, epoch, captures);
        }
    }
    fn quoteCaptures(self: *Builder, root: core.Id, epoch: u32, captures: *std.ArrayList(core.BindingId), depth: usize) Error!void {
        // Borrow child tables only for this synchronous walk. The view never
        // becomes an artifact or owner and must not be deinitialized.
        const graph: core.Module = .{
            .types = .{ .nodes = &.{}, .extra = &.{} },
            .nodes = self.tables.nodes.items,
            .spans = self.tables.spans.items,
            .extra = self.tables.extra.items,
            .bindings = self.tables.bindings.items,
            .bodies = self.tables.bodies.items,
            .parameters = self.tables.parameters.items,
            .references = self.tables.references.items,
            .calls = self.tables.calls.items,
            .merges = self.tables.merges.items,
            .merge_ranges = self.tables.merge_ranges.items,
            .names = &.{},
            .obligations = self.tables.obligations.items,
            .diagnostics = self.tables.diagnostics.items,
            .body_lowerings = self.scratch.body_lowerings,
            .closures = self.tables.closures.items,
            .loops = self.tables.loops.items,
            .loop_carries = self.tables.loop_carries.items,
            .request_loops = self.tables.request_loops.items,
            .request_arms = self.tables.request_arms.items,
            .resolver_ops = self.tables.resolver_ops.items,
            .operation_values = self.tables.operation_values.items,
            .matches = self.tables.matches.items,
            .match_arms = self.tables.match_arms.items,
            .pattern_rows = self.tables.pattern_rows.items,
            .updates = self.tables.updates.items,
            .update_steps = self.tables.update_steps.items,
        };
        const Walk = struct {
            builder: *Builder,
            graph: *const core.Module,
            captures: *std.ArrayList(core.BindingId),
            epoch: u32,
            remaining: usize = 65_536,
            stage: u8 = 1,
            depth: usize,
            fn visit(walk: *@This(), id: core.Id, stage: u8, at: usize) Error!void {
                if (id == 0) return;
                if (stage == 0) return walk.builder.nodeCaptures(id, walk.epoch, walk.captures, at);
                if (at >= 1024 or stage >= 128 or walk.remaining == 0) return error.CoreLimit;
                walk.remaining -= 1;
                const node = walk.graph.node(id);
                if (node.tag == .staging) {
                    const op: @import("typed_staging.zig").Op = @fromBackingInt(node.c);
                    if (op == .quote) return walk.visit(node.a, stage + 1, at + 1);
                    if (op == .lift or op == .splice) return walk.visit(node.a, stage - 1, at + 1);
                }
                if (node.tag == .closure or node.tag == .suspend_) return walk.visit(walk.graph.closures[node.a].body, stage, at + 1);
                const parent_stage = walk.stage;
                const parent_depth = walk.depth;
                walk.stage = stage;
                walk.depth = at;
                defer {
                    walk.stage = parent_stage;
                    walk.depth = parent_depth;
                }
                @import("../eval/body_recipe.zig").appendChildren(walk, walk.builder.allocator, walk.graph, id, false) catch |err| return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.PlanLimit => error.CoreLimit,
                };
            }
            pub fn append(walk: *@This(), _: Allocator, id: core.Id) error{ OutOfMemory, PlanLimit }!void {
                walk.visit(id, walk.stage, walk.depth + 1) catch |err| return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    else => error.PlanLimit,
                };
            }
            pub fn appendSlice(walk: *@This(), allocator: Allocator, ids: []const core.Id) error{ OutOfMemory, PlanLimit }!void {
                for (ids) |id| try walk.append(allocator, id);
            }
        };
        var walk: Walk = .{ .builder = self, .graph = &graph, .captures = captures, .epoch = epoch, .depth = depth };
        try walk.visit(root, 1, depth);
    }
    fn closureExpression(self: *Builder, source: ast.Id, ty: T.Id, depth: usize) Error!core.Id {
        const syntax = self.source.tree.node(source);
        const parameter: core.Parameter = .{ .binding = self.source.checked.resolved[syntax.a], .ty = try self.typeOf(syntax.a), .span = self.source.checked.diagnosticSpan(self.source.tree, syntax.a), .inferred = self.source.tree.parameter(syntax.a).annotation == 0 and !self.source.tree.parameter(syntax.a).is_unit };
        const previous = self.scratch.return_target;
        const previous_function = self.scratch.function_target;
        const function_block = if (std.mem.findScalar(ast.Id, self.source.checked.function_exit_lambdas, source) != null) try self.reserve(syntax.b) else 0;
        self.scratch.return_target = 0;
        self.scratch.function_target = function_block;
        const body_value = self.expression(syntax.b, depth + 1) catch |err| {
            self.scratch.return_target = previous;
            self.scratch.function_target = previous_function;
            return err;
        };
        self.scratch.return_target = previous;
        self.scratch.function_target = previous_function;
        var body = body_value;
        if (function_block != 0) {
            const signature = try self.callableType(ty);
            if (signature.tag != .function) return error.CoreLimit;
            const completion = try self.make(syntax.b, .{ .tag = .return_, .ty = T.never, .a = body_value, .b = function_block });
            const children = try self.save(&.{completion});
            self.tables.nodes.items[function_block] = .{ .tag = .block, .ty = signature.b, .a = children.start, .b = children.len };
            body = function_block;
        }
        const index = try self.captureClosure(body, parameter, ty, source);
        if (source < self.source.checked.lambda_closed_rows.len)
            self.tables.closures.items[index].closed_rows = try self.projectedRowVariables(self.source.checked.lambda_closed_rows[source]);
        return self.make(source, .{ .tag = .closure, .ty = ty, .a = index });
    }
    fn captureClosure(self: *Builder, body: core.Id, parameter: core.Parameter, function_type: T.Id, introduction: ast.Id) Error!u32 {
        if (self.scratch.definition_epochs.len == 0) {
            try self.allocateEmpty(&self.scratch.definition_epochs, self.tables.bindings.items.len);
            try self.allocateEmpty(&self.scratch.reference_epochs, self.tables.bindings.items.len);
        }
        try self.growCaptureEpochs(&self.scratch.definition_epochs);
        try self.growCaptureEpochs(&self.scratch.reference_epochs);
        const old_len = self.scratch.visit_epochs.items.len;
        try self.scratch.visit_epochs.resize(self.allocator, self.tables.nodes.items.len);
        @memset(self.scratch.visit_epochs.items[old_len..], 0);
        if (self.scratch.capture_epoch == std.math.maxInt(u32)) return error.CoreLimit;
        self.scratch.capture_epoch += 1;
        const epoch = self.scratch.capture_epoch;
        if (parameter.binding != 0) self.scratch.definition_epochs[parameter.binding] = epoch;
        for (self.tables.dictionary_uses.items) |use| if (use.introduction != 0 and use.introduction == introduction) {
            self.scratch.definition_epochs[use.binding] = epoch;
        };
        var captures: std.ArrayList(core.BindingId) = .empty;
        defer captures.deinit(self.allocator);
        try self.nodeCaptures(body, epoch, &captures, 0);
        var count: usize = 0;
        for (captures.items) |binding| {
            if (self.scratch.definition_epochs[binding] != epoch) {
                captures.items[count] = binding;
                count += 1;
            }
        }
        const range = try self.save(captures.items[0..count]);
        const index: u32 = @intCast(self.tables.closures.items.len);
        try self.tables.closures.append(self.allocator, .{ .body = body, .parameter = parameter, .captures = range, .function_type = function_type });
        return index;
    }
    fn growCaptureEpochs(self: *Builder, epochs: *[]u32) Error!void {
        const old_len = epochs.*.len;
        if (old_len >= self.tables.bindings.items.len) return;
        epochs.* = try self.allocator.realloc(epochs.*, self.tables.bindings.items.len);
        @memset(epochs.*[old_len..], 0);
    }
    fn suspensionExpression(self: *Builder, source: ast.Id, ty: T.Id, depth: usize) Error!core.Id {
        if (self.tables.type_nodes.items[ty].tag != .demand) return error.CoreLimit;
        const previous = self.scratch.return_target;
        self.scratch.return_target = 0;
        const body = self.expression(source, depth + 1) catch |err| {
            self.scratch.return_target = previous;
            return err;
        };
        self.scratch.return_target = previous;
        const demanded = self.tables.type_nodes.items[ty];
        const function_type = try self.addType(.{ .tag = .function, .a = T.unit, .b = demanded.a, .c = demanded.c });
        const index = try self.captureClosure(body, .{ .binding = 0, .ty = T.unit, .span = self.source.tree.span(source) }, function_type, source);
        if (source < self.source.checked.lambda_closed_rows.len)
            self.tables.closures.items[index].closed_rows = try self.projectedRowVariables(self.source.checked.lambda_closed_rows[source]);
        return self.make(source, .{ .tag = .suspend_, .ty = ty, .a = index });
    }
    fn taggedExpression(self: *Builder, attributes: []const ast.Id, source: ast.Id, depth: usize) Error!core.Id {
        if (depth >= 1024) return error.CoreLimit;
        if (attributes.len == 0) return self.expression(source, depth + 1);
        const attribute = attributes[0];
        const callee = try self.expression(self.source.tree.node(attribute).a, depth + 1);
        const argument = try self.taggedExpression(attributes[1..], source, depth + 1);
        const call = try self.make(attribute, .{ .tag = .apply, .ty = try self.typeOf(attribute), .a = callee, .b = argument });
        try self.tables.tag_calls.append(self.allocator, call);
        return call;
    }
    fn selectorExpression(self: *Builder, source: ast.Id, ty: T.Id) Error!core.Id {
        const function = self.tables.type_nodes.items[ty];
        if (function.tag != .function) return error.CoreLimit;
        const body = try self.resolvedReference(source, function.b);
        const index: u32 = @intCast(self.tables.closures.items.len);
        try self.tables.closures.append(self.allocator, .{ .body = body, .parameter = .{ .binding = self.source.checked.resolved[source], .ty = function.a, .span = self.source.tree.span(source) }, .captures = .{}, .function_type = ty });
        return self.make(source, .{ .tag = .closure, .ty = ty, .a = index });
    }
    fn primitiveExpression(self: *Builder, source: ast.Id, ty: T.Id) Error!core.Id {
        const text = self.source.names.get(self.source.tree.node(source).a);
        const metadata: core.Primitive = if (intrinsic(text)) |value| .{ .kind = .scalar, .op = value.op, .arity = value.arity } else if (arrayIntrinsic(text)) |value| .{ .kind = .array, .array_op = value.op, .arity = value.arity } else {
            try self.diagnostic(.unsupported, source);
            return 0;
        };
        var index: u32 = 0;
        while (index < self.tables.primitives.items.len) : (index += 1) {
            const previous = self.tables.primitives.items[index];
            if (previous.kind == metadata.kind and previous.op == metadata.op and previous.array_op == metadata.array_op and previous.arity == metadata.arity) break;
        }
        if (index == self.tables.primitives.items.len) try self.tables.primitives.append(self.allocator, metadata);
        return self.make(source, .{ .tag = .primitive_function, .ty = ty, .a = index });
    }
    fn dictionaryReference(self: *Builder, source: ast.Id, ty: T.Id, opening: core.BindingId, introduction: ast.Id, quantifier: T.Id, goal: u32, member: u32) Error!core.Id {
        var binding: ?core.BindingId = null;
        for (self.tables.dictionary_uses.items) |previous| {
            if (previous.opening == opening and previous.introduction == introduction and previous.quantifier == quantifier and previous.goal == goal and previous.member == member) {
                binding = previous.binding;
                break;
            }
        }
        if (binding == null) {
            const next: core.BindingId = @intCast(self.tables.bindings.items.len);
            try self.tables.bindings.append(self.allocator, .{ .kind = .local, .ty = ty, .scheme = .{ .root = ty }, .target = .{ .unit = self.source.checked.unit, .binding = next }, .span = self.source.tree.span(source) });
            binding = next;
        }
        const reference: u32 = @intCast(self.tables.references.items.len);
        try self.tables.references.append(self.allocator, .{ .unit = self.source.checked.unit, .binding = binding.? });
        const node = try self.make(source, .{ .tag = .reference, .ty = ty, .a = reference });
        try self.tables.dictionary_uses.append(self.allocator, .{ .node = node, .binding = binding.?, .opening = opening, .introduction = introduction, .quantifier = quantifier, .goal = goal, .member = member });
        return node;
    }
    fn expression(self: *Builder, original: ast.Id, depth: usize) Error!core.Id {
        if (original == 0) return 0;
        if (self.scratch.ast_map[original] != 0) return self.scratch.ast_map[original];
        if (depth >= 1024) {
            try self.diagnostic(.complexity, original);
            return 0;
        }
        const source = self.unwrap(original);
        if (source != original) {
            const id = try self.expression(source, depth + 1);
            self.scratch.ast_map[original] = id;
            return id;
        }
        const syntax = self.source.tree.node(source);
        const ty = try self.typeOf(source);
        for (self.source.checked.dictionary_uses) |use| {
            if (use.source != source) continue;
            const node = try self.dictionaryReference(source, ty, use.opening, use.introduction, try self.projectType(use.quantifier, 0), use.goal, use.member);
            self.scratch.ast_map[source] = node;
            return node;
        }
        for (self.source.checked.effect_scopes) |scope_| if (scope_.node == source) {
            const callback = try self.expression(scope_.callback, depth + 1);
            const result = try self.make(source, .{ .tag = .effect_scope, .ty = ty, .a = callback });
            self.scratch.ast_map[source] = result;
            return result;
        };
        const runner = if (source < self.source.checked.effect_runner_ids.len) self.source.checked.effect_runner_ids[source] else 0;
        if (runner != 0) {
            const result = try self.effectRunner(source, self.source.checked.effect_runners[runner - 1], depth + 1);
            self.scratch.ast_map[source] = result;
            return result;
        }
        if (self.source.checked.reflection(source)) |reflection| {
            const left = switch (reflection.kind) {
                .of => try self.projectRow(reflection.row, 0),
                .descriptor => try self.projectOperation(reflection.label, 0),
                .count, .has, .same => try self.expression(reflection.left, depth + 1),
            };
            const right = if (reflection.right == 0) 0 else try self.expression(reflection.right, depth + 1);
            const result = try self.make(source, .{ .tag = .effect_reflection, .ty = ty, .a = @backingInt(reflection.kind), .b = left, .c = right });
            if (reflection.kind == .of) try self.tables.erased_declaration_references.append(self.allocator, .{ .node = result, .target = self.target(reflection.binding) });
            self.scratch.ast_map[source] = result;
            return result;
        }
        for (self.source.checked.computations) |computation| if (computation.node == source) {
            const result = try self.make(source, .{ .tag = .computation, .ty = ty, .a = try self.expression(computation.action, depth + 1) });
            self.scratch.ast_map[source] = result;
            return result;
        };
        const operation = if (source < self.source.checked.operation_refs.len) self.source.checked.operation_refs[source] else 0;
        if (operation != 0) {
            if (operation > self.source.checked.operation_uses.len) return error.CoreLimit;
            const use = self.source.checked.operation_uses[operation - 1];
            if (use.template == 0 or use.template >= self.source.checked.effect_templates.len) return error.CoreLimit;
            const catalog: u32 = @intCast(self.tables.operation_values.items.len);
            const metadata: core.OperationValue = .{ .identity = self.source.checked.effect_templates[use.template].identity, .arguments = try self.projectedTypeList(use.arguments), .signature = try self.projectType(use.signature, 0), .instance = try self.projectInstance(use.instance, 0), .capability = if (use.capability_binding != 0) try self.projectedReference(source, use.capability_binding, try self.projectType(self.source.checked.bindings[use.capability_binding].ty, 0), use.node) else if (use.capability == 0) 0 else try self.expression(use.capability, depth + 1) };
            try self.tables.operation_values.append(self.allocator, metadata);
            const operation_ty = if (use.call == .value) ty else metadata.signature;
            const operation_node = try self.make(source, .{ .tag = .operation_value, .ty = operation_ty, .a = catalog });
            const result = if (use.call == .value) operation_node else blk: {
                var prefix: std.ArrayList(core.Id) = .empty;
                defer prefix.deinit(self.allocator);
                const operand = try self.runnerOperand(use.operand, try self.typeOf(use.operand), &prefix, depth + 1);
                if (use.call == .state_read) {
                    self.tables.operation_values.items[catalog].witness = operand;
                    self.tables.operation_values.items[catalog].witness_result = ty;
                }
                const argument = if (use.call == .state_read) try self.make(source, .{ .tag = .constant, .ty = T.unit }) else operand;
                const call = try self.make(source, .{ .tag = .apply, .ty = ty, .a = operation_node, .b = argument });
                break :blk try self.sequenceValue(source, prefix.items, call);
            };
            self.scratch.ast_map[source] = result;
            return result;
        }
        const result: core.Id = switch (syntax.tag) {
            .package_pack => blk: {
                var witnesses: std.ArrayList(T.Id) = .empty;
                defer witnesses.deinit(self.allocator);
                for (self.source.tree.list(.{ .start = syntax.a, .len = syntax.b })) |witness| try witnesses.append(self.allocator, try self.typeOf(witness));
                const stored = try self.saveTypes(witnesses.items);
                const payload = try self.expression(self.source.tree.extra.items[syntax.c], depth + 1);
                const owner = try self.make(source, .{ .tag = .package_pack, .ty = ty, .a = payload, .b = stored.start, .c = stored.len });
                const dictionary_start = self.tables.dictionary_selections.items.len;
                var contents: std.ArrayList(core.Id) = .empty;
                defer contents.deinit(self.allocator);
                try contents.append(self.allocator, payload);
                for (self.source.checked.dictionary_selections) |selection| {
                    if (selection.source != source) continue;
                    var members: std.ArrayList(core.Id) = .empty;
                    defer members.deinit(self.allocator);
                    const proof: core.DictionaryProof = switch (selection.proof) {
                        .selected => |selected| selected: {
                            if (selected >= self.source.checked.selected_proofs.len) return error.CoreLimit;
                            const selected_proof = self.source.checked.selected_proofs[selected];
                            for (self.source.checked.selected_members[selected_proof.members.start..][0..selected_proof.members.len]) |member| {
                                if (member.kind == .type_) {
                                    try members.append(self.allocator, 0);
                                    continue;
                                }
                                const reference: u32 = @intCast(self.tables.references.items.len);
                                try self.tables.references.append(self.allocator, .{ .unit = member.target.unit, .binding = member.target.binding });
                                try members.append(self.allocator, try self.make(source, .{ .tag = .reference, .ty = try self.projectType(member.root, 0), .a = reference }));
                            }
                            break :selected .{ .selected = selected };
                        },
                        .given => |given| lexical: {
                            const quantifier = try self.projectType(given.quantifier, 0);
                            const arguments = try self.projectedTypeList(given.arguments);
                            for (self.source.checked.types.list(given.member_types), 0..) |member_type, ordinal| {
                                if (member_type == 0) {
                                    try members.append(self.allocator, 0);
                                    continue;
                                }
                                const member = try self.dictionaryReference(source, try self.projectType(member_type, 0), given.opening, given.introduction, quantifier, given.goal, @intCast(ordinal));
                                try members.append(self.allocator, member);
                            }
                            break :lexical .{ .given = .{ .opening = given.opening, .introduction = given.introduction, .quantifier = quantifier, .goal = given.goal, .arguments = arguments } };
                        },
                    };
                    for (members.items) |member| if (member != 0) try contents.append(self.allocator, member);
                    try self.tables.dictionary_selections.append(self.allocator, .{ .owner = owner, .quantifier = try self.projectType(selection.quantifier, 0), .goal = selection.goal, .proof = proof, .members = try self.save(members.items) });
                }
                if (self.tables.dictionary_selections.items.len != dictionary_start) {
                    const stored_contents = try self.save(contents.items);
                    for (self.tables.dictionary_selections.items[dictionary_start..]) |*selection| selection.contents = stored_contents;
                }
                break :blk owner;
            },
            .package_unpack => blk: {
                const package = try self.expression(syntax.a, depth + 1);
                const body = try self.expression(self.source.tree.extra.items[syntax.c + 2], depth + 1);
                var binders: std.ArrayList(T.Id) = .empty;
                defer binders.deinit(self.allocator);
                for (self.source.tree.list(.{ .start = syntax.b, .len = self.source.tree.extra.items[syntax.c] })) |binder| try binders.append(self.allocator, try self.typeOf(binder));
                const stored = try self.saveTypes(binders.items);
                const metadata = try self.save(&.{ body, stored.start, stored.len });
                break :blk try self.make(source, .{ .tag = .package_unpack, .ty = ty, .a = package, .b = self.source.checked.resolved[source], .c = metadata.start });
            },
            .integer, .float, .boolean => try self.make(source, .{ .tag = .constant, .ty = ty, .a = syntax.a }),
            .string => try self.stringExpression(source, ty),
            .unit => try self.make(source, .{ .tag = .constant, .ty = ty }),
            .name => if (self.tables.type_nodes.items[ty].tag == .type_constructor and self.source.checked.resolved[source] == 0)
                try self.make(source, .{ .tag = .type_constructor, .ty = ty })
            else
                try self.resolvedReference(source, ty),
            .task_region => try self.resolvedReference(source, ty),
            .selector => try self.selectorExpression(source, ty),
            .intrinsic => try self.primitiveExpression(source, ty),
            .field_access => blk: {
                const catalog = if (source < self.source.checked.projection_resolved.len) self.source.checked.projection_resolved[source] else 0;
                if (catalog == 0) {
                    if (self.tables.type_nodes.items[ty].tag == .type_constructor and self.source.checked.resolved[source] == 0)
                        break :blk try self.make(source, .{ .tag = .type_constructor, .ty = ty });
                    break :blk try self.resolvedReference(source, ty);
                }
                const owner = try self.expression(syntax.a, depth + 1);
                const projection = try self.projectionIndex(catalog, self.tables.nodes.items[owner].ty, ty);
                break :blk try self.make(source, .{ .tag = .project, .ty = ty, .a = owner, .b = projection });
            },
            .product => try self.productExpression(source, ty, .product, depth + 1),
            .array => try self.productExpression(source, ty, .array, depth + 1),
            .index_access => blk: {
                const values = try self.save(&.{ try self.expression(syntax.a, depth + 1), try self.expression(syntax.b, depth + 1) });
                break :blk try self.make(source, .{ .tag = .array_op, .ty = ty, .a = values.start, .b = values.len, .c = @backingInt(core.ArrayOp.get) });
            },
            .record => try self.recordExpression(source, ty, depth + 1),
            .type_witness => blk: {
                const catalog = if (source < self.source.checked.constructor_resolved.len) self.source.checked.constructor_resolved[source] else 0;
                if (catalog == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    break :blk 0;
                }
                break :blk try self.make(source, .{ .tag = .construct, .ty = ty, .a = catalog, .b = try self.expression(syntax.a, depth + 1) });
            },
            .lambda => try self.closureExpression(source, ty, depth + 1),
            .case_expr => try self.caseExpression(source, ty, depth + 1),
            .constructor_ref => blk: {
                const catalog = if (source < self.source.checked.constructor_resolved.len) self.source.checked.constructor_resolved[source] else 0;
                if (catalog == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    break :blk 0;
                }
                if (self.source.checked.constructors[catalog].payload != 0) break :blk try self.make(source, .{ .tag = .constructor_function, .ty = ty, .a = catalog });
                break :blk try self.make(source, .{ .tag = .construct, .ty = ty, .a = catalog });
            },
            .apply => try self.application(source, depth + 1),
            .binary => blk: {
                const left = if (self.source.checked.demand_binary_left[source])
                    try self.suspensionExpression(syntax.b, try self.projectType(self.source.checked.demand_binary_left_types[source], 0), depth + 1)
                else
                    try self.expression(syntax.b, depth + 1);
                const right = if (self.source.checked.demand_calls[source])
                    try self.suspensionExpression(syntax.c, try self.projectType(self.source.checked.demand_types[source], 0), depth + 1)
                else
                    try self.expression(syntax.c, depth + 1);
                const binding = self.source.checked.resolved[source];
                if (binding != 0) break :blk try self.namedCall(source, binding, &.{ left, right }, ty);
                const op = binaryOp(self.source.names.get(syntax.a)) orelse {
                    try self.diagnostic(.unsupported, source);
                    break :blk 0;
                };
                break :blk try self.make(source, .{ .tag = if (op == .and_ or op == .or_) .logical else .scalar, .op = op, .ty = ty, .a = left, .b = right, .c = 1 });
            },
            .unary => blk: {
                if (!std.mem.eql(u8, self.source.names.get(syntax.a), "-")) {
                    try self.diagnostic(.unsupported, source);
                    break :blk 0;
                }
                break :blk try self.make(source, .{ .tag = .scalar, .op = .neg, .ty = ty, .a = try self.expression(syntax.b, depth + 1) });
            },
            .if_expr => try self.make(source, .{ .tag = .if_value, .ty = ty, .a = try self.expression(syntax.a, depth + 1), .b = try self.expression(syntax.b, depth + 1), .c = try self.expression(syntax.c, depth + 1) }),
            .block => blk: {
                if (syntax.c != 0) {
                    const provider = self.source.checked.provider_block_ids[source];
                    if (provider != 0) break :blk try self.providerBlock(source, self.source.checked.provider_blocks[provider - 1], depth + 1);
                    const index = self.source.checked.resolver_block_ids[source];
                    if (index == 0) {
                        try self.diagnostic(.unresolved_binding, source);
                        break :blk 0;
                    }
                    break :blk try self.resolverBlock(source, self.source.checked.resolver_blocks[index - 1], depth + 1);
                }
                const id = try self.reserve(source);
                const previous = self.scratch.return_target;
                self.scratch.return_target = id;
                defer self.scratch.return_target = previous;
                const children = try self.statements(source, depth + 1);
                self.tables.nodes.items[id] = .{ .tag = .block, .ty = ty, .a = children.start, .b = children.len };
                break :blk id;
            },
            else => blk: {
                try self.diagnostic(.unsupported, source);
                break :blk 0;
            },
        };
        self.scratch.ast_map[source] = result;
        return result;
    }
    fn providerBlock(self: *Builder, source: ast.Id, metadata: checked_types.ProviderBlock, depth: usize) Error!core.Id {
        const provider = try self.expression(metadata.provider, depth + 1);
        const inner = try self.reserve(source);
        const previous = self.scratch.return_target;
        self.scratch.return_target = inner;
        defer self.scratch.return_target = previous;
        const children = try self.statements(source, depth + 1);
        self.tables.nodes.items[inner] = .{ .tag = .block, .ty = try self.projectType(metadata.body_result, 0), .a = children.start, .b = children.len };
        return self.make(source, .{ .tag = .handle, .ty = try self.projectType(metadata.result, 0), .a = provider, .b = inner });
    }
    fn runnerOperand(self: *Builder, source: ast.Id, ty: T.Id, prefix: *std.ArrayList(core.Id), depth: usize) Error!core.Id {
        const value = try self.expression(source, depth + 1);
        if (self.tables.bindings.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const binding: core.BindingId = @intCast(self.tables.bindings.items.len);
        try self.tables.bindings.append(self.allocator, .{ .kind = .local, .ty = ty, .scheme = .{ .root = ty }, .target = .{ .binding = 0 }, .span = self.source.tree.span(source) });
        try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = value }));
        return self.referenceNode(source, binding, ty);
    }
    fn runnerOperation(self: *Builder, source: ast.Id, token: T.Id, parameter: T.Id, result: T.Id, row: T.Effects.Id) Error!core.Id {
        const identity = self.tables.type_nodes.items[token];
        if (identity.tag != .nominal) return error.CoreLimit;
        const count = self.tables.type_extra.items[identity.c];
        const signature = try self.addType(.{ .tag = .function, .a = parameter, .b = result, .c = row });
        const index: u32 = @intCast(self.tables.operation_values.items.len);
        try self.tables.operation_values.append(self.allocator, .{ .identity = .{ .unit = identity.a, .decl = identity.b }, .arguments = .{ .start = identity.c + 1, .len = count }, .signature = signature });
        return self.make(source, .{ .tag = .operation_value, .ty = signature, .a = index });
    }
    fn effectRunner(self: *Builder, source: ast.Id, metadata: checked_types.EffectRunner, depth: usize) Error!core.Id {
        var prefix: std.ArrayList(core.Id) = .empty;
        defer prefix.deinit(self.allocator);
        const state = try self.projectType(metadata.state_type, 0);
        const result = try self.projectType(metadata.body_result, 0);
        const outer = try self.projectRow(metadata.outer_effects, 0);
        const extended = try self.projectRow(metadata.body_effects, 0);
        const read = try self.projectType(metadata.read_token, 0);
        const write = try self.projectType(metadata.write_token, 0);
        const initial = if (metadata.kind == .run) try self.runnerOperand(metadata.initial, state, &prefix, depth + 1) else 0;
        const witness = if (metadata.witness != 0) try self.runnerOperand(metadata.witness, try self.typeOf(metadata.witness), &prefix, depth + 1) else 0;
        const implementation = if (metadata.implementation != 0) try self.runnerOperand(metadata.implementation, try self.projectType(metadata.implementation_type, 0), &prefix, depth + 1) else 0;
        const action = try self.runnerOperand(metadata.action, try self.projectType(metadata.action_type, 0), &prefix, depth + 1);
        const first = if (read != 0) read else write;
        const provider = if (metadata.kind == .run) blk: {
            const reader = try self.runnerOperation(source, read, T.unit, state, extended);
            const writer = try self.runnerOperation(source, write, state, T.unit, extended);
            const ty = try self.addType(.{ .tag = .state_provider, .a = read, .b = write, .c = state });
            break :blk try self.make(source, .{ .tag = .state_provider, .ty = ty, .a = reader, .b = writer, .c = initial });
        } else blk: {
            const operation = try self.runnerOperation(source, first, if (read != 0) T.unit else state, if (read != 0) state else T.unit, extended);
            const operation_index = self.tables.nodes.items[operation].a;
            self.tables.operation_values.items[operation_index].witness = witness;
            self.tables.operation_values.items[operation_index].witness_result = state;
            const ty = try self.addType(.{ .tag = .provider, .a = first, .c = outer });
            break :blk try self.make(source, .{ .tag = .effect_provider, .ty = ty, .a = operation, .b = implementation });
        };
        const unit = try self.make(source, .{ .tag = .constant, .ty = T.unit });
        const call = try self.make(source, .{ .tag = .apply, .ty = result, .a = action, .b = unit });
        const handler = try self.make(source, .{ .tag = .handle, .ty = try self.projectType(metadata.result, 0), .a = provider, .b = call, .c = @intCast(self.tables.handle_effects.items.len + 1) });
        try self.tables.handle_effects.append(self.allocator, .{ .node = handler, .first = first, .second = if (metadata.kind == .run) write else 0, .extended = extended, .residual = outer });
        return self.sequenceValue(source, prefix.items, handler);
    }
    fn callableType(self: *Builder, original: T.Id) Error!T.Node {
        var id = original;
        for (0..128) |_| {
            const node = self.tables.type_nodes.items[id];
            if (node.tag != .usage and node.tag != .forall) return node;
            id = node.a;
        }
        return error.CoreLimit;
    }
    fn namedCall(self: *Builder, source: ast.Id, binding: core.BindingId, arguments: []const core.Id, result: T.Id) Error!core.Id {
        var callee_type = result;
        if (self.scratch.signature_sources.len != 0 and self.scratch.signature_sources[source] != 0) {
            callee_type = try self.projectType(self.scratch.signature_sources[source], 0);
        } else {
            var i = arguments.len;
            while (i != 0) {
                i -= 1;
                callee_type = try self.addType(.{ .tag = .function, .a = self.tables.nodes.items[arguments[i]].ty, .b = callee_type });
            }
        }
        const kind = self.source.checked.bindings[binding].kind;
        if (kind == .local or kind == .parameter or (try self.callableType(result)).tag == .function) {
            // Backtick names resolve to this lexical binding version. Their
            // checked call signature belongs to this use, as ordinary apply.
            // A function result also keeps the ordinary curried boundary: the
            // named definition can have unapplied source parameters remaining.
            var value = try self.referenceNode(source, binding, callee_type);
            for (arguments) |argument| {
                const signature = try self.callableType(self.tables.nodes.items[value].ty);
                if (signature.tag != .function) {
                    try self.diagnostic(.invalid_call, source);
                    return 0;
                }
                value = try self.make(source, .{ .tag = .apply, .ty = signature.b, .a = value, .b = argument });
            }
            return value;
        }
        return self.typedNamedCall(source, binding, arguments, result, callee_type);
    }
    fn typedNamedCall(self: *Builder, source: ast.Id, binding: core.BindingId, arguments: []const core.Id, result: T.Id, callee_type: T.Id) Error!core.Id {
        const index: u32 = @intCast(self.tables.calls.items.len);
        try self.tables.calls.append(self.allocator, .{ .target = self.target(binding), .callee_type = callee_type });
        const values = try self.save(arguments);
        return self.make(source, .{ .tag = .call, .ty = result, .a = index, .b = values.start, .c = values.len });
    }
    fn directArity(self: *const Builder, original: core.BindingId) ?usize {
        var binding = original;
        for (0..256) |_| {
            const metadata = self.source.checked.bindings[binding];
            if (metadata.kind == .external) return null;
            if (metadata.kind != .global) return 0;
            for (self.source.checked.member_templates) |template| if (template.binding == binding) return null;
            var source = self.unwrap(self.source.tree.valueDecl(metadata.declaration).body);
            var count: usize = 0;
            while (self.source.tree.node(source).tag == .lambda) {
                const boundary = self.source.checked.types.node(self.source.checked.types.head(self.source.checked.expr_types[source], 0)).tag;
                if (count != 0 and (boundary == .usage or boundary == .forall)) break;
                count += 1;
                source = self.unwrap(self.source.tree.node(source).b);
            }
            if (count != 0) return count;
            if (self.source.tree.node(source).tag != .name or self.source.checked.resolved[source] == 0) return 0;
            binding = self.source.checked.resolved[source];
        }
        return 0;
    }
    const ApplicationArgument = struct { value: ast.Id, site: ast.Id };
    fn appliedValue(self: *Builder, source: ast.Id, callee: ast.Id, arguments: []const core.Id, sites: []const ApplicationArgument, depth: usize) Error!core.Id {
        if (arguments.len != sites.len) return error.CoreLimit;
        var value = try self.expression(callee, depth + 1);
        for (arguments, 0..) |argument, index| {
            if (value == 0) return 0;
            var callable_type = self.tables.nodes.items[value].ty;
            while (self.tables.type_nodes.items[callable_type].tag == .usage) callable_type = self.tables.type_nodes.items[callable_type].a;
            const signature = self.tables.type_nodes.items[callable_type];
            if (signature.tag != .function and signature.tag != .never and signature.tag != .forall) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            // Preserve all checked operands and each application's semantic
            // result, including a callee that cannot produce a callable.
            const site = sites[sites.len - index - 1].site;
            var instance: T.Id = 0;
            if (signature.tag == .forall) instance = try self.typeOf(self.source.tree.node(site).a);
            value = try self.make(site, .{ .tag = .apply, .ty = try self.typeOf(site), .a = value, .b = argument, .c = instance });
        }
        return value;
    }
    fn application(self: *Builder, source: ast.Id, depth: usize) Error!core.Id {
        // Ordinary scalar calls fit in stack scratch; larger surface calls
        // retain the same heap-backed growth and explicit cleanup behavior.
        var backwards_storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var backwards_storage: std.heap.BufferFirstAllocator = .init(&backwards_storage_buffer, self.allocator);
        const backwards_allocator = backwards_storage.allocator();
        var backwards: std.ArrayList(ApplicationArgument) = .empty;
        defer backwards.deinit(backwards_allocator);
        // Zig's default growth starts above a cache line; precise initial
        // capacity prevents a one-argument call from bypassing stack scratch.
        try backwards.ensureTotalCapacityPrecise(backwards_allocator, 16);
        var callee = source;
        while (self.source.tree.node(callee).tag == .apply) {
            const value = self.source.tree.node(callee);
            try backwards.append(backwards_allocator, .{ .value = value.b, .site = callee });
            const inner = self.unwrap(value.a);
            if (inner < self.source.checked.operation_refs.len and self.source.checked.operation_refs[inner] != 0) {
                callee = inner;
                break;
            }
            // A grouped application may have already saturated a compiler
            // primitive and produced a callable. Preserve that call boundary
            // rather than counting its later runtime arguments as intrinsic
            // operands, as in (@array.get callbacks index) ().
            if (self.source.tree.node(value.a).tag == .group and self.source.tree.node(self.unwrap(value.a)).tag == .apply) {
                callee = value.a;
                break;
            }
            callee = self.unwrap(value.a);
        }
        const syntax = self.source.tree.node(callee);
        const result = try self.typeOf(source);
        if (syntax.tag == .intrinsic) if (@import("task_types.zig").lookup(self.source.names.get(syntax.a))) |operation| {
            if (backwards.items.len != @import("task_types.zig").arity(operation)) return error.CoreLimit;
            var values: [3]core.Id = undefined;
            for (0..backwards.items.len) |index| values[index] = try self.expression(backwards.items[backwards.items.len - index - 1].value, depth + 1);
            const operands = try self.save(values[0..backwards.items.len]);
            const selected = if ((operation == .join or operation == .receive) and self.tables.type_nodes.items[self.tables.nodes.items[values[0]].ty].tag == .product) @import("task_types.zig").Op.collect else operation;
            return self.make(source, .{ .tag = .task, .a = operands.start, .b = operands.len, .c = @backingInt(selected), .ty = result });
        };
        for (self.source.checked.usage_loans) |loan| {
            if (loan.source != source) continue;
            if (loan.acquire != 0) {
                if (loan.callback == 0) {
                    if (backwards.items.len != 2) return error.CoreLimit;
                    return self.make(source, .{ .tag = .resource_acquire, .a = try self.expression(loan.acquire, depth + 1), .b = try self.expression(loan.release, depth + 1), .ty = result });
                }
                if (backwards.items.len != 3) return error.CoreLimit;
                return self.make(source, .{ .tag = .resource_scope, .a = try self.expression(loan.acquire, depth + 1), .b = try self.expression(loan.release, depth + 1), .c = try self.expression(loan.callback, depth + 1), .ty = result });
            }
            if (backwards.items.len != 2) return error.CoreLimit;
            return self.make(source, .{ .tag = .usage_borrow, .a = try self.expression(backwards.items[1].value, depth + 1), .b = try self.expression(backwards.items[0].value, depth + 1), .c = @intFromBool(loan.mutable), .ty = result });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@resource.release")) {
            if (backwards.items.len != 1) return error.CoreLimit;
            return self.make(source, .{ .tag = .resource_release, .a = try self.expression(backwards.items[0].value, depth + 1), .ty = result });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@usage.share")) {
            if (backwards.items.len != 1) return error.CoreLimit;
            return self.make(source, .{ .tag = .usage_share, .a = try self.expression(backwards.items[0].value, depth + 1), .ty = result });
        }
        if (syntax.tag == .intrinsic and (std.mem.eql(u8, self.source.names.get(syntax.a), "@usage.read") or std.mem.eql(u8, self.source.names.get(syntax.a), "@usage.length"))) {
            if (backwards.items.len != 1) return error.CoreLimit;
            const input = try self.expression(backwards.items[0].value, depth + 1);
            var operation: u32 = 0;
            if (std.mem.eql(u8, self.source.names.get(syntax.a), "@usage.length")) {
                const payload = self.tables.type_nodes.items[self.tables.type_nodes.items[self.tables.nodes.items[input].ty].a];
                operation = 1;
                if (payload.tag == .list) operation = 2;
            }
            return self.make(source, .{ .tag = .usage_read, .a = input, .b = operation, .ty = result });
        }
        if (syntax.tag == .intrinsic and self.source.tree.has_typed_staging) {
            if (@import("typed_staging.zig").lookup(self.source.names.get(syntax.a))) |op| {
                if (backwards.items.len != @import("typed_staging.zig").arity(op)) return error.CoreLimit;
                const left = try self.expression(backwards.items[backwards.items.len - 1].value, depth + 1);
                var right: core.Id = 0;
                if (backwards.items.len == 2) right = try self.expression(backwards.items[0].value, depth + 1);
                return self.make(source, .{ .tag = .staging, .ty = result, .a = left, .b = right, .c = @backingInt(op) });
            }
        }
        if (syntax.tag == .intrinsic and self.source.tree.has_numeric_proofs) {
            if (@import("numeric_proof_terms.zig").constructor(self.source.names.get(syntax.a))) |relation| {
                if (backwards.items.len != 2) return error.CoreLimit;
                var matched = false;
                for (self.source.checked.proof_bodies.introductions) |introduction| {
                    if (self.scratch.proof_visits >= 65_536) return error.CoreLimit;
                    self.scratch.proof_visits += 1;
                    if (introduction.source != source) continue;
                    if (introduction.proposition.relation != relation or introduction.arguments[0] != backwards.items[1].value or introduction.arguments[1] != backwards.items[0].value) return error.CoreLimit;
                    matched = true;
                    break;
                }
                if (!matched or self.tables.type_nodes.items[result].tag != .erased_proof) return error.CoreLimit;
                const left = try self.expression(backwards.items[1].value, depth + 1);
                const right = try self.expression(backwards.items[0].value, depth + 1);
                return self.make(source, .{ .tag = .proof_guard, .ty = result, .a = left, .b = right, .c = @backingInt(relation) });
            }
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@effect.provider")) {
            if (backwards.items.len != 2) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const operation = try self.expression(backwards.items[1].value, depth + 1);
            const implementation = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .effect_provider, .ty = result, .a = operation, .b = implementation });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@effect.state")) {
            if (backwards.items.len != 3) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const read = try self.expression(backwards.items[2].value, depth + 1);
            const write = try self.expression(backwards.items[1].value, depth + 1);
            const initial = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .state_provider, .ty = result, .a = read, .b = write, .c = initial });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@do.monad")) {
            if (backwards.items.len != 1) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const operand = try self.expression(backwards.items[0].value, depth + 1);
            return self.resolverNode(source, .{ .operation = .monad, .resolver = operand }, &.{}, result);
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@panic")) {
            if (backwards.items.len != 1) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const literal = self.source.tree.node(self.unwrap(backwards.items[0].value));
            if (literal.tag != .string) {
                try self.diagnostic(.unsupported, source);
                return 0;
            }
            const message = self.source.names.get(literal.a);
            if (message.len > std.math.maxInt(u32) - self.tables.name_bytes.items.len) return error.CoreLimit;
            const start: u32 = @intCast(self.tables.name_bytes.items.len);
            try self.tables.name_bytes.appendSlice(self.allocator, message);
            return self.make(source, .{ .tag = .panic, .ty = result, .a = start, .b = @intCast(message.len) });
        }
        if (syntax.tag == .intrinsic and (std.mem.eql(u8, self.source.names.get(syntax.a), "@force") or std.mem.eql(u8, self.source.names.get(syntax.a), "@demand"))) {
            if (backwards.items.len != 1) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const operand = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .force, .ty = result, .a = operand });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@record.merge")) {
            if (backwards.items.len != 2) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const left = try self.expression(backwards.items[1].value, depth + 1);
            const right = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .record_merge, .ty = result, .a = left, .b = right });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@type.same")) {
            if (backwards.items.len != 2) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const left = try self.expression(backwards.items[1].value, depth + 1);
            const right = try self.expression(backwards.items[0].value, depth + 1);
            return self.make(source, .{ .tag = .type_same, .ty = result, .a = left, .b = right });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@type.result")) {
            if (backwards.items.len != 2) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const member = self.source.tree.node(self.unwrap(backwards.items[1].value));
            if (member.tag != .string) {
                try self.diagnostic(.unsupported, source);
                return 0;
            }
            const operand = try self.expression(backwards.items[0].value, depth + 1);
            const binding = self.source.checked.resolved[source];
            if (binding != 0) return self.namedCall(source, binding, &.{operand}, result);
            return self.make(source, .{ .tag = .result_associated, .ty = result, .a = operand, .b = member.a });
        }
        if (syntax.tag == .intrinsic and std.mem.eql(u8, self.source.names.get(syntax.a), "@type.call")) {
            if (backwards.items.len != 3) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const member = self.source.tree.node(self.unwrap(backwards.items[2].value));
            if (member.tag != .string) {
                try self.diagnostic(.unsupported, source);
                return 0;
            }
            const left = try self.expression(backwards.items[1].value, depth + 1);
            const right = try self.expression(backwards.items[0].value, depth + 1);
            const binding = self.source.checked.resolved[source];
            if (binding != 0) return self.namedCall(source, binding, &.{ left, right }, result);
            return self.make(source, .{ .tag = .associated, .op = memberOp(self.source.names.get(member.a)), .ty = result, .a = left, .b = right, .c = member.a });
        }
        var arguments_storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var arguments_storage: std.heap.BufferFirstAllocator = .init(&arguments_storage_buffer, self.allocator);
        const arguments_allocator = arguments_storage.allocator();
        var arguments: std.ArrayList(core.Id) = .empty;
        defer arguments.deinit(arguments_allocator);
        try arguments.ensureTotalCapacityPrecise(arguments_allocator, @min(backwards.items.len, 16));
        var i = backwards.items.len;
        while (i != 0) {
            i -= 1;
            const argument = backwards.items[i];
            const value = if (self.source.checked.demand_calls[argument.site])
                try self.suspensionExpression(argument.value, try self.projectType(self.source.checked.demand_types[argument.site], 0), depth + 1)
            else
                try self.expression(argument.value, depth + 1);
            try arguments.append(arguments_allocator, value);
        }
        if (syntax.tag == .constructor_ref) {
            const catalog = if (callee < self.source.checked.constructor_resolved.len) self.source.checked.constructor_resolved[callee] else 0;
            if (catalog == 0 or arguments.items.len != 1) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            const payload = self.source.checked.constructors[catalog].payload;
            const record = !self.source.checked.nominals[self.source.checked.constructors[catalog].nominal].is_opaque and payload != 0 and self.source.checked.types.node(payload).tag == .record;
            return self.make(source, .{ .tag = .construct, .ty = result, .a = catalog, .b = arguments.items[0], .c = @intFromBool(record) });
        }
        if (syntax.tag == .intrinsic) {
            if (@import("storage_ops.zig").lookup(self.source.names.get(syntax.a))) |op| {
                if (arguments.items.len != @import("storage_ops.zig").arity(op)) return error.CoreLimit;
                const values = try self.save(arguments.items);
                return self.make(source, .{ .tag = .storage, .ty = result, .a = values.start, .b = values.len, .c = @backingInt(op) });
            }
            if (arrayIntrinsic(self.source.names.get(syntax.a))) |primitive| {
                if (arguments.items.len < primitive.arity) return self.appliedValue(source, callee, arguments.items, backwards.items, depth);
                if (arguments.items.len != primitive.arity) {
                    try self.diagnostic(.invalid_call, source);
                    return 0;
                }
                const values = try self.save(arguments.items);
                return self.make(source, .{ .tag = .array_op, .ty = result, .a = values.start, .b = values.len, .c = @backingInt(primitive.op) });
            }
            if (std.mem.eql(u8, self.source.names.get(syntax.a), "@product.get")) {
                if (arguments.items.len != 2 or self.source.tree.node(self.unwrap(backwards.items[0].value)).tag != .integer) {
                    try self.diagnostic(.invalid_call, source);
                    return 0;
                }
                const field = self.source.tree.node(self.unwrap(backwards.items[0].value)).a;
                const projection = try self.directProjection(self.tables.nodes.items[arguments.items[0]].ty, result, field);
                return self.make(source, .{ .tag = .project, .ty = result, .a = arguments.items[0], .b = projection });
            }
            const primitive = intrinsic(self.source.names.get(syntax.a)) orelse {
                try self.diagnostic(.unsupported, source);
                return 0;
            };
            if (arguments.items.len < primitive.arity) return self.appliedValue(source, callee, arguments.items, backwards.items, depth);
            if (arguments.items.len != primitive.arity) {
                try self.diagnostic(.invalid_call, source);
                return 0;
            }
            return self.make(source, .{ .tag = .scalar, .op = primitive.op, .ty = result, .a = arguments.items[0], .b = if (primitive.arity == 2) arguments.items[1] else 0 });
        }
        for (self.source.checked.dictionary_uses) |use| if (use.source == callee) return self.appliedValue(source, callee, arguments.items, backwards.items, depth);
        const binding = self.source.checked.resolved[callee];
        if (binding != 0 and self.source.checked.operation_refs[callee] == 0 and (syntax.tag == .name or syntax.tag == .field_access) and
            (self.source.checked.bindings[binding].kind == .global or self.source.checked.bindings[binding].kind == .external) and
            (callee >= self.source.checked.access_paths.len or self.source.checked.access_paths[callee].len == 0) and
            self.tables.type_nodes.items[result].tag != .function)
        {
            const arity = self.directArity(binding);
            if (arity == null or arity.? == arguments.items.len) return self.typedNamedCall(source, binding, arguments.items, result, try self.typeOf(callee));
        }
        return self.appliedValue(source, callee, arguments.items, backwards.items, depth);
    }
    fn resolverNode(self: *Builder, source: ast.Id, original: core.ResolverInfo, arguments: []const core.Id, result: T.Id) Error!core.Id {
        var info = original;
        info.arguments = try self.save(arguments);
        if (self.tables.resolver_ops.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const index: u32 = @intCast(self.tables.resolver_ops.items.len);
        try self.tables.resolver_ops.append(self.allocator, info);
        return self.make(source, .{ .tag = .resolver_op, .ty = result, .a = index });
    }
    fn checkedResolverNode(self: *Builder, info: checked_types.ResolverOp, arguments: []const core.Id) Error!core.Id {
        const resolver = try self.referenceNode(info.node, info.resolver, self.tables.bindings.items[info.resolver].ty);
        const operation: core.ResolverOperation = switch (info.kind) {
            .monad => .monad,
            .pure => .pure,
            .bind => .bind,
            .forward => .forward,
            .iterate => .iterate,
        };
        return self.resolverNode(info.node, .{
            .operation = operation,
            .resolver = resolver,
            .member = info.member,
            .method = if (info.method == 0) .{ .binding = 0 } else self.target(info.method),
            .method_type = try self.projectType(info.method_type, 0),
        }, arguments, try self.projectType(info.result, 0));
    }
    fn closureNode(self: *Builder, source: ast.Id, body: core.Id, parameter: core.Parameter, ty: T.Id) Error!core.Id {
        const index = try self.captureClosure(body, parameter, ty, 0);
        return self.make(source, .{ .tag = .closure, .ty = ty, .a = index });
    }
    /// Source statements remain ordinary owned IR. A private value block makes
    /// their final expression explicit without a return crossing a callback.
    fn sequenceValue(self: *Builder, source: ast.Id, prefix: []const core.Id, value: core.Id) Error!core.Id {
        if (prefix.len == 0) return value;
        const id = try self.reserve(source);
        var children: std.ArrayList(core.Id) = .empty;
        defer children.deinit(self.allocator);
        try children.appendSlice(self.allocator, prefix);
        try children.append(self.allocator, try self.make(source, .{ .tag = .return_, .ty = T.never, .a = value, .b = id }));
        const range = try self.save(children.items);
        self.tables.nodes.items[id] = .{ .tag = .block, .ty = self.tables.nodes.items[value].ty, .a = range.start, .b = range.len };
        return id;
    }
    fn resolverBlock(self: *Builder, source: ast.Id, info: checked_types.ResolverBlock, depth: usize) Error!core.Id {
        const previous = self.scratch.return_target;
        self.scratch.return_target = 0;
        defer self.scratch.return_target = previous;
        const syntax = self.source.tree.node(source);
        const provider = try self.expression(syntax.c, depth + 1);
        const binding = try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = info.resolver, .b = provider });
        var tail: core.Id = 0;
        if (info.fallthrough != 0) {
            const unit_value = try self.make(source, .{ .tag = .constant, .ty = T.unit });
            tail = try self.checkedResolverNode(self.source.checked.resolver_ops[info.fallthrough - 1], &.{unit_value});
        }
        const body = try self.resolverStatements(source, self.source.tree.children(source), tail, depth + 1);
        const result = try self.projectType(info.result, 0);
        const fn_type = try self.addType(.{ .tag = .function, .a = T.unit, .b = result, .c = try self.projectRow(info.body_effects, 0) });
        const action = try self.closureNode(source, body, .{ .binding = 0, .ty = T.unit, .span = self.source.tree.span(source) }, fn_type);
        const resolver = try self.referenceNode(source, info.resolver, self.tables.bindings.items[info.resolver].ty);
        const run = try self.resolverNode(source, .{ .operation = .run, .resolver = resolver }, &.{action}, result);
        return self.sequenceValue(source, &.{binding}, run);
    }
    fn resolverStatements(self: *Builder, source: ast.Id, statements_: []const ast.Id, tail: core.Id, depth: usize) Error!core.Id {
        if (depth >= 1024) return error.CoreLimit;
        if (statements_.len == 0) return tail;
        if (self.source.checked.iterator_bodies.len != 0 and self.source.checked.iterator_bodies[statements_[0]] != 0) {
            var expanded: std.ArrayList(ast.Id) = .empty;
            defer expanded.deinit(self.allocator);
            try expanded.appendSlice(self.allocator, self.source.tree.children(self.source.checked.iterator_bodies[statements_[0]]));
            try expanded.appendSlice(self.allocator, statements_[1..]);
            return self.resolverStatements(source, expanded.items, tail, depth + 1);
        }
        // Ordinary statements do not introduce a continuation. Retain them in
        // one ordered block instead of making source length become IR nesting
        // and recursively lowering an identical suffix for every statement.
        var ordinary: usize = 0;
        while (ordinary < statements_.len) {
            const child = statements_[ordinary];
            const simple = switch (self.source.tree.node(child).tag) {
                .return_stmt,
                .break_stmt,
                .continue_stmt,
                .use_stmt,
                .if_stmt,
                .if_let_stmt,
                .for_stmt,
                .range_stmt,
                .forever_stmt,
                => false,
                .let_stmt => self.source.tree.binding(child).fallback == 0,
                else => true,
            };
            if (!simple) break;
            ordinary += 1;
        }
        if (ordinary != 0) {
            var prefix: std.ArrayList(core.Id) = .empty;
            defer prefix.deinit(self.allocator);
            for (statements_[0..ordinary]) |child| try prefix.append(self.allocator, try self.statement(child, depth + 1));
            const next = try self.resolverStatements(source, statements_[ordinary..], tail, depth + 1);
            return self.sequenceValue(statements_[0], prefix.items, next);
        }
        const statement_source = statements_[0];
        const syntax = self.source.tree.node(statement_source);
        if (syntax.tag == .return_stmt) {
            const index = self.source.checked.resolver_op_ids[statement_source];
            if (index == 0) return error.CoreLimit;
            const info = self.source.checked.resolver_ops[index - 1];
            var value = try self.expression(syntax.a, depth + 1);
            if (info.completion != 0) return self.resolverComplete(info.completion, value);
            value = try self.completedValue(statement_source, value, info.completed_types, info.done_constructor);
            return self.checkedResolverNode(info, &.{value});
        }
        if (syntax.tag == .break_stmt) return self.resolverBreak(statement_source);
        if (syntax.tag == .continue_stmt) return self.resolverContinue(statement_source);
        const next = try self.resolverStatements(source, statements_[1..], tail, depth + 1);
        switch (syntax.tag) {
            .use_stmt => {
                const index = self.source.checked.resolver_op_ids[statement_source];
                if (index == 0) return error.CoreLimit;
                const info = self.source.checked.resolver_ops[index - 1];
                const candidate = try self.expression(syntax.b, depth + 1);
                const method_type = self.tables.type_nodes.items[try self.projectType(info.method_type, 0)];
                if (method_type.tag != .function) return error.CoreLimit;
                const after_candidate = self.tables.type_nodes.items[method_type.b];
                if (after_candidate.tag != .function) return error.CoreLimit;
                const fn_type = after_candidate.a;
                const signature = self.tables.type_nodes.items[fn_type];
                if (signature.tag != .function) return error.CoreLimit;
                const continuation = try self.closureNode(statement_source, next, .{
                    .binding = info.continuation_parameter,
                    .ty = signature.a,
                    .span = self.source.tree.span(statement_source),
                }, fn_type);
                return self.checkedResolverNode(info, &.{ candidate, continuation });
            },
            .if_stmt, .if_let_stmt => return self.resolverConditional(statement_source, next, depth + 1),
            .let_stmt => {
                const binding = self.source.tree.binding(statement_source);
                if (binding.fallback != 0) return self.resolverGuard(statement_source, binding.pattern, binding.value, binding.fallback, next, depth + 1);
            },
            .for_stmt, .range_stmt, .forever_stmt => return self.resolverLoop(statement_source, next, depth + 1),
            else => {},
        }
        return error.CoreLimit;
    }
    fn resolverJoin(self: *Builder, source: ast.Id, body: core.Id) Error!core.Id {
        const index = self.source.checked.resolver_join_ids[source];
        if (index == 0) return error.CoreLimit;
        const info = self.source.checked.resolver_joins[index - 1];
        const ty = try self.projectType(info.ty, 0);
        var prefix: std.ArrayList(core.Id) = .empty;
        defer prefix.deinit(self.allocator);
        var merge = if (self.scratch.merge_heads.len == 0) std.math.maxInt(u32) else self.scratch.merge_heads[source];
        var field: u32 = 0;
        while (merge != std.math.maxInt(u32)) : (merge = self.scratch.merge_next[merge]) {
            const result = self.source.checked.merges[merge].result;
            const result_type = self.tables.bindings.items[result].ty;
            const parameter = try self.referenceNode(source, info.parameter, ty);
            const projection = try self.directProjection(ty, result_type, field);
            const value = try self.make(source, .{ .tag = .project, .ty = result_type, .a = parameter, .b = projection });
            try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = result, .b = value }));
            field += 1;
        }
        const fn_type = try self.addType(.{ .tag = .function, .a = ty, .b = try self.projectType(info.result, 0) });
        return self.closureNode(source, try self.sequenceValue(source, prefix.items, body), .{ .binding = info.parameter, .ty = ty, .span = self.source.tree.span(source) }, fn_type);
    }
    fn resolverBranchTail(self: *Builder, source: ast.Id, join: core.Id, selected: bool) Error!core.Id {
        var values: std.ArrayList(core.Id) = .empty;
        defer values.deinit(self.allocator);
        var merge = if (self.scratch.merge_heads.len == 0) std.math.maxInt(u32) else self.scratch.merge_heads[source];
        while (merge != std.math.maxInt(u32)) : (merge = self.scratch.merge_next[merge]) {
            const info = self.source.checked.merges[merge];
            const binding = if (selected) info.then_binding else info.else_binding;
            try values.append(self.allocator, try self.referenceNode(source, binding, self.tables.bindings.items[binding].ty));
        }
        const fn_type = self.tables.type_nodes.items[self.tables.nodes.items[join].ty];
        const argument = if (values.items.len == 0 and fn_type.a == T.unit)
            try self.make(source, .{ .tag = .constant, .ty = T.unit })
        else blk: {
            const range = try self.save(values.items);
            break :blk try self.make(source, .{ .tag = .product, .ty = fn_type.a, .a = range.start, .b = range.len });
        };
        return self.make(source, .{ .tag = .apply, .ty = fn_type.b, .a = join, .b = argument });
    }
    fn resolverConditional(self: *Builder, source: ast.Id, next: core.Id, depth: usize) Error!core.Id {
        const syntax = self.source.tree.node(source);
        const join = try self.resolverJoin(source, next);
        const yes_tail = try self.resolverBranchTail(source, join, true);
        const no_tail = try self.resolverBranchTail(source, join, false);
        if (syntax.tag == .if_stmt) {
            const yes = try self.resolverStatements(syntax.b, self.source.tree.children(syntax.b), yes_tail, depth + 1);
            const no = if (syntax.c == 0) no_tail else try self.resolverStatements(syntax.c, self.source.tree.children(syntax.c), no_tail, depth + 1);
            const ty = if (self.tables.nodes.items[yes].ty == T.never) self.tables.nodes.items[no].ty else self.tables.nodes.items[yes].ty;
            return self.make(source, .{ .tag = .if_value, .ty = ty, .a = try self.expression(syntax.a, depth + 1), .b = yes, .c = no });
        }
        const suites = self.source.tree.extra.items[syntax.c..][0..2];
        const yes = try self.resolverStatements(suites[0], self.source.tree.children(suites[0]), yes_tail, depth + 1);
        const no = if (suites[1] == 0) no_tail else try self.resolverStatements(suites[1], self.source.tree.children(suites[1]), no_tail, depth + 1);
        return self.resolverMatch(source, syntax.a, try self.expression(syntax.b, depth + 1), yes, no, depth + 1);
    }
    fn resolverGuard(self: *Builder, source: ast.Id, pattern: ast.Id, candidate: ast.Id, fallback: ast.Id, next: core.Id, depth: usize) Error!core.Id {
        const alternative = try self.resolverStatements(fallback, self.source.tree.children(fallback), next, depth + 1);
        return self.resolverMatch(source, pattern, try self.expression(candidate, depth + 1), next, alternative, depth + 1);
    }
    fn resolverMatch(self: *Builder, source: ast.Id, pattern_source: ast.Id, candidate: core.Id, yes: core.Id, no: core.Id, depth: usize) Error!core.Id {
        const inputs = try self.save(&.{candidate});
        const pattern = try self.patternNode(pattern_source, depth + 1);
        const yes_row = try self.addPatternRow(&.{pattern});
        const wildcard = try self.addPattern(source, .{ .tag = .wildcard, .ty = self.tables.nodes.items[candidate].ty });
        const no_row = try self.addPatternRow(&.{wildcard});
        const start: u32 = @intCast(self.tables.match_arms.items.len);
        try self.tables.match_arms.appendSlice(self.allocator, &.{
            .{ .rows = .{ .start = yes_row, .len = 1 }, .body = yes, .span = self.source.tree.span(source) },
            .{ .rows = .{ .start = no_row, .len = 1 }, .body = no, .span = self.source.tree.span(source) },
        });
        const index: u32 = @intCast(self.tables.matches.items.len);
        try self.tables.matches.append(self.allocator, .{ .inputs = inputs, .arms = .{ .start = start, .len = 2 } });
        const ty = if (self.tables.nodes.items[yes].ty == T.never) self.tables.nodes.items[no].ty else self.tables.nodes.items[yes].ty;
        return self.make(source, .{ .tag = .match, .ty = ty, .a = index });
    }
    fn completedValue(self: *Builder, source: ast.Id, original: core.Id, types: T.List, constructor: u32) Error!core.Id {
        var value = original;
        for (self.source.checked.types.list(types)) |ty| {
            if (constructor == 0) return error.CoreLimit;
            value = try self.make(source, .{ .tag = .construct, .ty = try self.projectType(ty, 0), .a = constructor, .b = value });
        }
        return value;
    }
    fn resolverComplete(self: *Builder, index: u32, candidate: core.Id) Error!core.Id {
        const info = self.source.checked.resolver_completions[index - 1];
        const bind = self.source.checked.resolver_ops[info.bind - 1];
        const pure = self.source.checked.resolver_ops[info.pure - 1];
        const method = self.tables.type_nodes.items[try self.projectType(bind.method_type, 0)];
        if (method.tag != .function) return error.CoreLimit;
        const after_candidate = self.tables.type_nodes.items[method.b];
        if (after_candidate.tag != .function) return error.CoreLimit;
        const fn_type = after_candidate.a;
        const signature = self.tables.type_nodes.items[fn_type];
        if (signature.tag != .function) return error.CoreLimit;
        const payload = try self.referenceNode(info.node, bind.continuation_parameter, signature.a);
        const completed = try self.completedValue(info.node, payload, info.completed_types, info.done_constructor);
        const body = try self.checkedResolverNode(pure, &.{completed});
        const continuation = try self.closureNode(info.node, body, .{ .binding = bind.continuation_parameter, .ty = signature.a, .span = self.source.tree.span(info.node) }, fn_type);
        return self.checkedResolverNode(bind, &.{ candidate, continuation });
    }
    fn productValue(self: *Builder, source: ast.Id, ty: T.Id, values: []const core.Id) Error!core.Id {
        if (ty == T.unit and values.len == 0) return self.make(source, .{ .tag = .constant, .ty = T.unit });
        const range = try self.save(values);
        return self.make(source, .{ .tag = .product, .ty = ty, .a = range.start, .b = range.len });
    }
    fn productField(self: *Builder, source: ast.Id, owner: core.Id, field: u32) Error!core.Id {
        const owner_type = self.tables.nodes.items[owner].ty;
        const ty = self.tables.type_nodes.items[owner_type];
        if (ty.tag != .product or field >= ty.b) return error.CoreLimit;
        const result_type = self.tables.type_extra.items[ty.a + field];
        const projection = try self.directProjection(owner_type, result_type, field);
        return self.make(source, .{ .tag = .project, .ty = result_type, .a = owner, .b = projection });
    }
    fn cursorValue(self: *Builder, source: ast.Id, ty: T.Id, index: core.Id, bindings: []const core.BindingId) Error!core.Id {
        const cursor = self.tables.type_nodes.items[ty];
        if (cursor.tag != .product or cursor.b != 2) return error.CoreLimit;
        const state_type = self.tables.type_extra.items[cursor.a + 1];
        var values: std.ArrayList(core.Id) = .empty;
        defer values.deinit(self.allocator);
        for (bindings) |binding| try values.append(self.allocator, try self.referenceNode(source, binding, self.tables.bindings.items[binding].ty));
        const state = try self.productValue(source, state_type, values.items);
        return self.productValue(source, ty, &.{ index, state });
    }
    fn resolverBreak(self: *Builder, source: ast.Id) Error!core.Id {
        const exit_index = if (self.scratch.loop_exit_indices.len == 0) 0 else self.scratch.loop_exit_indices[source];
        if (exit_index == 0) return error.CoreLimit;
        const exit = self.source.checked.loop_exits[exit_index - 1];
        // A resolver opened inside another loop returns its current carried
        // state from that resolver. The surrounding loop continues after the
        // nested do's value has been consumed or ignored.
        const operation = self.source.checked.resolver_op_ids[source];
        if (operation != 0) {
            const info = self.source.checked.resolver_ops[operation - 1];
            if (info.kind != .pure) return error.CoreLimit;
            var values: std.ArrayList(core.Id) = .empty;
            defer values.deinit(self.allocator);
            for (self.source.checked.types.list(exit.bindings)) |binding| {
                try values.append(self.allocator, try self.referenceNode(source, binding, self.tables.bindings.items[binding].ty));
            }
            const value = try self.productValue(source, try self.projectType(info.payload, 0), values.items);
            return self.checkedResolverNode(info, &.{value});
        }
        var index = self.scratch.resolver_loop_frames.items.len;
        while (index != 0) {
            index -= 1;
            const frame = self.scratch.resolver_loop_frames.items[index];
            if (frame.source != exit.loop) continue;
            const current = try self.referenceNode(source, frame.parameter, frame.cursor);
            const cursor = try self.cursorValue(source, frame.cursor, try self.productField(source, current, 0), self.source.checked.types.list(exit.bindings));
            const signature = self.tables.type_nodes.items[self.tables.nodes.items[frame.finalizer].ty];
            return self.make(source, .{ .tag = .apply, .ty = signature.b, .a = frame.finalizer, .b = cursor });
        }
        return error.CoreLimit;
    }
    fn resolverContinue(self: *Builder, source: ast.Id) Error!core.Id {
        const exit_index = if (self.scratch.loop_exit_indices.len == 0) 0 else self.scratch.loop_exit_indices[source];
        if (exit_index == 0) return error.CoreLimit;
        const exit = self.source.checked.loop_exits[exit_index - 1];
        var index = self.scratch.resolver_loop_frames.items.len;
        while (index != 0) {
            index -= 1;
            const frame = self.scratch.resolver_loop_frames.items[index];
            if (frame.source != exit.loop) continue;
            const current = try self.referenceNode(source, frame.parameter, frame.cursor);
            const counter = try self.productField(source, current, 0);
            const one = try self.make(source, .{ .tag = .constant, .ty = T.u32_type, .a = 1 });
            const successor = try self.make(source, .{ .tag = .scalar, .op = .add, .ty = T.u32_type, .a = counter, .b = one });
            const cursor = try self.cursorValue(source, frame.cursor, successor, self.source.checked.types.list(exit.bindings));
            const continued = self.source.checked.resolver_ops[frame.continued - 1];
            const progress = try self.make(source, .{ .tag = .construct, .ty = try self.projectType(continued.payload, 0), .a = frame.continue_constructor, .b = cursor });
            return self.checkedResolverNode(continued, &.{progress});
        }
        return error.CoreLimit;
    }
    fn resolverLoop(self: *Builder, source: ast.Id, next: core.Id, depth: usize) Error!core.Id {
        const index = self.source.checked.resolver_loop_ids[source];
        if (index == 0) return error.CoreLimit;
        const info = self.source.checked.resolver_loops[index - 1];
        const syntax = self.source.tree.node(source);
        const range = self.source.checked.loop_ranges[source];
        const carries = self.source.checked.loop_carries[range.start..][0..range.len];
        const cursor_type = try self.projectType(info.cursor, 0);
        const step_result = try self.projectType(info.step_result, 0);
        var first_source: ast.Id = 0;
        var end_source: ast.Id = 0;
        var pattern_source: ast.Id = 0;
        var body_source: ast.Id = syntax.a;
        var array = false;
        if (syntax.tag == .range_stmt) {
            first_source = syntax.a;
            end_source = syntax.b;
            body_source = syntax.c;
        } else if (syntax.tag == .for_stmt) {
            const parts = self.source.tree.extra.items[syntax.c..][0..3];
            first_source = syntax.b;
            end_source = parts[0];
            body_source = parts[1];
            pattern_source = syntax.a;
            array = end_source == 0;
        }
        var prefix: std.ArrayList(core.Id) = .empty;
        defer prefix.deinit(self.allocator);
        const first = if (first_source == 0) try self.make(source, .{ .tag = .constant, .ty = T.u32_type }) else try self.expression(first_source, depth + 1);
        try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = info.first_binding, .b = first }));
        const first_ref = try self.referenceNode(source, info.first_binding, self.tables.bindings.items[info.first_binding].ty);
        const end = if (array) blk: {
            const values = try self.save(&.{first_ref});
            break :blk try self.make(source, .{ .tag = .array_op, .ty = T.u32_type, .a = values.start, .b = values.len, .c = @backingInt(core.ArrayOp.length) });
        } else if (end_source == 0) try self.make(source, .{ .tag = .constant, .ty = T.u32_type }) else try self.expression(end_source, depth + 1);
        try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = info.end_binding, .b = end }));
        const cursor = try self.referenceNode(source, info.cursor_parameter, cursor_type);
        const counter = try self.productField(source, cursor, 0);
        const state = try self.productField(source, cursor, 1);
        var incoming: std.ArrayList(core.BindingId) = .empty;
        defer incoming.deinit(self.allocator);
        var backedge: std.ArrayList(core.BindingId) = .empty;
        defer backedge.deinit(self.allocator);
        var finalize_prefix: std.ArrayList(core.Id) = .empty;
        defer finalize_prefix.deinit(self.allocator);
        var step_prefix: std.ArrayList(core.Id) = .empty;
        defer step_prefix.deinit(self.allocator);
        for (carries, 0..) |carry, field| {
            try incoming.append(self.allocator, carry.incoming);
            try backedge.append(self.allocator, carry.backedge);
            const value = try self.productField(source, state, @intCast(field));
            try finalize_prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = carry.outgoing, .b = value }));
            try step_prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = carry.iteration, .b = value }));
        }
        const finalized = try self.resolverComplete(info.finish, next);
        const fn_type = try self.addType(.{ .tag = .function, .a = cursor_type, .b = step_result });
        const parameter: core.Parameter = .{ .binding = info.cursor_parameter, .ty = cursor_type, .span = self.source.tree.span(source) };
        const finalizer = try self.closureNode(source, try self.sequenceValue(source, finalize_prefix.items, finalized), parameter, fn_type);
        const exit = try self.make(source, .{ .tag = .apply, .ty = step_result, .a = finalizer, .b = cursor });
        const one = try self.make(source, .{ .tag = .constant, .ty = T.u32_type, .a = 1 });
        const successor = try self.make(source, .{ .tag = .scalar, .op = .add, .ty = T.u32_type, .a = counter, .b = one });
        const next_cursor = try self.cursorValue(source, cursor_type, successor, backedge.items);
        const continued = self.source.checked.resolver_ops[info.continued - 1];
        const progress = try self.make(source, .{ .tag = .construct, .ty = try self.projectType(continued.payload, 0), .a = info.continue_constructor, .b = next_cursor });
        const progress_tail = try self.checkedResolverNode(continued, &.{progress});
        if (pattern_source != 0) {
            const iterator = if (!array) counter else blk: {
                const values = try self.save(&.{ first_ref, counter });
                break :blk try self.make(source, .{ .tag = .array_op, .ty = try self.typeOf(pattern_source), .a = values.start, .b = values.len, .c = @backingInt(core.ArrayOp.get) });
            };
            try step_prefix.append(self.allocator, try self.make(source, .{ .tag = .pattern_bind, .ty = T.unit, .a = try self.patternNode(pattern_source, depth + 1), .b = iterator }));
        }
        const stack_mark = self.scratch.resolver_loop_frames.items.len;
        try self.scratch.resolver_loop_frames.append(self.allocator, .{ .source = source, .cursor = cursor_type, .parameter = info.cursor_parameter, .finalizer = finalizer, .continued = info.continued, .continue_constructor = info.continue_constructor });
        const iteration = self.resolverStatements(body_source, self.source.tree.children(body_source), progress_tail, depth + 1) catch |err| {
            self.scratch.resolver_loop_frames.shrinkRetainingCapacity(stack_mark);
            return err;
        };
        self.scratch.resolver_loop_frames.shrinkRetainingCapacity(stack_mark);
        // Iterator binding and array access happen only for an actual body
        // invocation, after the one-time bound check has selected this arm.
        const iteration_body = try self.sequenceValue(source, step_prefix.items, iteration);
        const step_body = if (syntax.tag == .forever_stmt) iteration_body else blk: {
            const end_ref = try self.referenceNode(source, info.end_binding, T.u32_type);
            const condition = try self.make(source, .{ .tag = .scalar, .op = .less, .ty = T.boolean, .a = counter, .b = end_ref });
            break :blk try self.make(source, .{ .tag = .if_value, .ty = step_result, .a = condition, .b = iteration_body, .c = exit });
        };
        const step = try self.closureNode(source, step_body, parameter, fn_type);
        const first_index = if (array) try self.make(source, .{ .tag = .constant, .ty = T.u32_type }) else first_ref;
        const initial = try self.cursorValue(source, cursor_type, first_index, incoming.items);
        const iterate = try self.checkedResolverNode(self.source.checked.resolver_ops[info.iterate - 1], &.{ initial, step });
        return self.sequenceValue(source, prefix.items, iterate);
    }
    fn statements(self: *Builder, source: ast.Id, depth: usize) Error!core.List {
        var children: std.ArrayList(core.Id) = .empty;
        defer children.deinit(self.allocator);
        for (self.source.tree.children(source)) |child| try children.append(self.allocator, try self.statement(child, depth + 1));
        return self.save(children.items);
    }
    fn suite(self: *Builder, source: ast.Id, depth: usize) Error!core.Id {
        if (source == 0) return 0;
        if (depth >= 1024) {
            try self.diagnostic(.complexity, source);
            return 0;
        }
        const children = try self.statements(source, depth + 1);
        const id = try self.make(source, .{ .tag = .suite, .ty = T.unit, .a = children.start, .b = children.len });
        self.scratch.ast_map[source] = id;
        return id;
    }
    fn requestState(self: *Builder, source: ast.Id, state_type: T.Id, bindings: []const core.BindingId) Error!core.Id {
        if (bindings.len == 0) return self.make(source, .{ .tag = .constant, .ty = T.unit });
        if (bindings.len == 1) return self.referenceNode(source, bindings[0], self.tables.bindings.items[bindings[0]].ty);
        var values: std.ArrayList(core.Id) = .empty;
        defer values.deinit(self.allocator);
        for (bindings) |binding| try values.append(self.allocator, try self.referenceNode(source, binding, self.tables.bindings.items[binding].ty));
        const range = try self.save(values.items);
        return self.make(source, .{ .tag = .product, .ty = state_type, .a = range.start, .b = range.len });
    }
    fn requestControl(self: *Builder, source: ast.Id, info: checked_types.RequestControl, depth: usize) Error!core.Id {
        var frame_index = self.scratch.request_callbacks.items.len;
        while (frame_index != 0) {
            frame_index -= 1;
            const frame = self.scratch.request_callbacks.items[frame_index];
            if (frame.loop != info.loop) continue;
            const kind: core.RequestDecisionKind = switch (info.kind) {
                .reply => .reply,
                .cancel => .cancel,
                .break_ => .break_,
            };
            const value = if (kind == .break_) 0 else try self.expression(self.source.tree.node(source).a, depth + 1);
            const state = if (kind == .cancel) 0 else try self.requestState(source, frame.state_type, self.source.checked.types.list(info.bindings));
            const decision = try self.make(source, .{ .tag = .request_decision, .ty = frame.decision_type, .a = @backingInt(kind), .b = value, .c = state });
            return self.make(source, .{ .tag = .return_, .ty = T.never, .a = decision, .b = frame.return_target });
        }
        // Completion executes in the surrounding block, without an operation
        // callback frame. Its return/break targets retain their source owners.
        if (info.kind == .cancel) return self.make(source, .{ .tag = .return_, .ty = T.never, .a = try self.expression(self.source.tree.node(source).a, depth + 1), .b = if (self.scratch.ast_map[info.target_scope] != 0) self.scratch.ast_map[info.target_scope] else self.scratch.return_target });
        if (info.kind == .break_) {
            var values: std.ArrayList(core.Id) = .empty;
            defer values.deinit(self.allocator);
            for (self.source.checked.types.list(info.bindings)) |binding| try values.append(self.allocator, try self.referenceNode(source, binding, self.tables.bindings.items[binding].ty));
            const range = try self.save(values.items);
            return self.make(source, .{ .tag = .break_, .ty = T.never, .a = self.scratch.ast_map[info.loop], .b = range.start, .c = range.len });
        }
        try self.diagnostic(.unresolved_binding, source);
        return 0;
    }
    fn requestCallback(self: *Builder, source: ast.Id, loop_source: ast.Id, info: checked_types.RequestArm, state_type: T.Id, depth: usize) Error!core.Id {
        const signature = try self.projectType(info.signature, 0);
        const arrow = self.tables.type_nodes.items[signature];
        if (arrow.tag != .function) return error.CoreLimit;
        if (self.tables.bindings.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const parameter_id: core.BindingId = @intCast(self.tables.bindings.items.len);
        const parameter: core.Parameter = .{ .binding = parameter_id, .ty = arrow.a, .span = self.source.tree.span(source) };
        try self.tables.bindings.append(self.allocator, .{ .kind = .parameter, .ty = arrow.a, .scheme = .{ .root = arrow.a }, .target = .{ .binding = parameter_id }, .span = parameter.span });
        const argument = try self.referenceNode(source, parameter_id, arrow.a);
        const operation_argument = try self.productField(source, argument, 0);
        const state = try self.productField(source, argument, 1);
        var prefix: std.ArrayList(core.Id) = .empty;
        defer prefix.deinit(self.allocator);
        try prefix.append(self.allocator, try self.make(source, .{ .tag = .pattern_bind, .ty = T.unit, .a = try self.patternNode(info.pattern, depth + 1), .b = operation_argument }));
        const bindings = self.source.checked.types.list(info.state_bindings);
        for (bindings, 0..) |binding, index| {
            const value = if (bindings.len == 1) state else try self.productField(source, state, @intCast(index));
            try prefix.append(self.allocator, try self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = value }));
        }
        const block = try self.reserve(source);
        const saved_return = self.scratch.return_target;
        self.scratch.return_target = block;
        defer self.scratch.return_target = saved_return;
        const stack_mark = self.scratch.request_callbacks.items.len;
        try self.scratch.request_callbacks.append(self.allocator, .{ .loop = loop_source, .return_target = block, .decision_type = arrow.b, .state_type = state_type });
        defer self.scratch.request_callbacks.shrinkRetainingCapacity(stack_mark);
        const callback_suite = try self.suite(info.suite, depth + 1);
        try prefix.append(self.allocator, callback_suite);
        const range = try self.save(prefix.items);
        self.tables.nodes.items[block] = .{ .tag = .block, .ty = arrow.b, .a = range.start, .b = range.len };
        return self.closureNode(source, block, parameter, signature);
    }
    fn requestLoop(self: *Builder, source: ast.Id, checked: checked_types.RequestLoop, depth: usize) Error!core.Id {
        const id = try self.reserve(source);
        self.scratch.ast_map[source] = id;
        if (self.tables.request_loops.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const catalog: u32 = @intCast(self.tables.request_loops.items.len);
        var info: core.RequestLoopInfo = .{
            .computation = 0,
            .action_type = try self.projectType(checked.action_type, 0),
            .value_type = try self.projectType(checked.value_type, 0),
            .result_type = try self.projectType(checked.result_type, 0),
            .state_type = try self.projectType(checked.state_type, 0),
            .return_target = if (self.scratch.ast_map[checked.return_scope] != 0) self.scratch.ast_map[checked.return_scope] else self.scratch.return_target,
        };
        try self.tables.request_loops.append(self.allocator, info);
        self.tables.nodes.items[id] = .{ .tag = .request_loop, .ty = T.unit, .a = catalog };
        const carries = self.source.checked.loop_carries[checked.carried.start..][0..checked.carried.len];
        if (carries.len > std.math.maxInt(u32) - self.tables.loop_carries.items.len) return error.CoreLimit;
        info.carries = .{ .start = @intCast(self.tables.loop_carries.items.len), .len = @intCast(carries.len) };
        for (carries) |carry| try self.tables.loop_carries.append(self.allocator, .{ .incoming = carry.incoming, .iteration = carry.iteration, .backedge = carry.backedge, .outgoing = carry.outgoing });
        info.computation = try self.expression(checked.computation, depth + 1);
        var arms: std.ArrayList(core.RequestArm) = .empty;
        defer arms.deinit(self.allocator);
        for (self.source.checked.types.list(checked.arms)) |index| {
            const arm = self.source.checked.request_arms[index];
            try arms.append(self.allocator, .{ .operation = try self.projectOperation(arm.operation, 0), .callback = try self.requestCallback(arm.node, source, arm, info.state_type, depth + 1), .selector = if (self.source.checked.types.operation(arm.operation).instance.decl == 0) 0 else try self.expression(arm.operation_source, depth + 1) });
        }
        if (arms.items.len > std.math.maxInt(u32) - self.tables.request_arms.items.len) return error.CoreLimit;
        info.arms = .{ .start = @intCast(self.tables.request_arms.items.len), .len = @intCast(arms.items.len) };
        try self.tables.request_arms.appendSlice(self.allocator, arms.items);
        info.completion_pattern = try self.patternNode(checked.complete_pattern, depth + 1);
        info.completion_body = try self.suite(checked.complete_suite, depth + 1);
        info.completion_state_bindings = try self.save(self.source.checked.types.list(checked.complete_state_bindings));
        self.tables.request_loops.items[catalog] = info;
        return id;
    }
    fn loopStatement(self: *Builder, source: ast.Id, checked_carries: anytype, depth: usize) Error!core.Id {
        const syntax = self.source.tree.node(source);
        var info: core.LoopInfo = .{ .kind = .forever, .body = 0 };
        var first_source: ast.Id = 0;
        var end_source: ast.Id = 0;
        var pattern_source: ast.Id = 0;
        const body_source: ast.Id = switch (syntax.tag) {
            .forever_stmt => syntax.a,
            .range_stmt => blk: {
                info.kind = .range;
                first_source = syntax.a;
                end_source = syntax.b;
                break :blk syntax.c;
            },
            .for_stmt => blk: {
                const details = self.source.tree.extra.items[syntax.c..][0..3];
                info.kind = if (details[0] == 0) .array else .range;
                first_source = syntax.b;
                end_source = details[0];
                pattern_source = syntax.a;
                break :blk details[1];
            },
            else => unreachable,
        };
        // Publish the numeric target before lowering its body, so a break
        // inside a nested do can reference the surrounding loop without a
        // backpointer into the source tree or a mutable lexical environment.
        const id = try self.reserve(source);
        if (self.tables.loops.items.len == std.math.maxInt(u32)) return error.CoreLimit;
        const catalog: u32 = @intCast(self.tables.loops.items.len);
        try self.tables.loops.append(self.allocator, info);
        self.tables.nodes.items[id] = .{ .tag = .loop, .ty = T.unit, .a = catalog };
        self.scratch.ast_map[source] = id;
        if (checked_carries.len > std.math.maxInt(u32) - self.tables.loop_carries.items.len) return error.CoreLimit;
        info.carries = .{ .start = @intCast(self.tables.loop_carries.items.len), .len = @intCast(checked_carries.len) };
        for (checked_carries) |carry| try self.tables.loop_carries.append(self.allocator, .{ .incoming = carry.incoming, .iteration = carry.iteration, .backedge = carry.backedge, .outgoing = carry.outgoing });
        info.first = try self.expression(first_source, depth + 1);
        info.end = try self.expression(end_source, depth + 1);
        info.pattern = if (pattern_source == 0) 0 else try self.patternNode(pattern_source, depth + 1);
        info.body = try self.suite(body_source, depth + 1);
        info.can_exit = self.tables.loops.items[catalog].can_exit;
        self.tables.loops.items[catalog] = info;
        return id;
    }
    fn breakStatement(self: *Builder, source: ast.Id, target_source: ast.Id, bindings: []const core.BindingId) Error!core.Id {
        const target_id = self.scratch.ast_map[target_source];
        if (target_id == 0 or self.tables.nodes.items[target_id].tag != .loop) {
            try self.diagnostic(.unresolved_binding, source);
            return 0;
        }
        const continues = self.source.tree.node(source).tag == .continue_stmt;
        if (!continues) self.tables.loops.items[self.tables.nodes.items[target_id].a].can_exit = true;
        var values: std.ArrayList(core.Id) = .empty;
        defer values.deinit(self.allocator);
        for (bindings) |binding| {
            if (binding == 0 or binding >= self.tables.bindings.items.len) {
                try self.diagnostic(.unresolved_binding, source);
                return 0;
            }
            try values.append(self.allocator, try self.referenceNode(source, binding, self.tables.bindings.items[binding].ty));
        }
        const range = try self.save(values.items);
        return self.make(source, .{ .tag = .break_, .op = if (continues) .continue_ else .none, .ty = T.never, .a = target_id, .b = range.start, .c = range.len });
    }
    fn statement(self: *Builder, source: ast.Id, depth: usize) Error!core.Id {
        if (depth >= 1024) {
            try self.diagnostic(.complexity, source);
            return 0;
        }
        const syntax = self.source.tree.node(source);
        if (self.source.checked.iterator_bodies.len != 0 and self.source.checked.iterator_bodies[source] != 0)
            return self.suite(self.source.checked.iterator_bodies[source], depth + 1);
        for (self.source.checked.request_controls) |control| if (control.node == source) return self.requestControl(source, control, depth + 1);
        for (self.source.checked.request_loops) |info| if (info.node == source) return self.requestLoop(source, info, depth + 1);
        switch (syntax.tag) {
            .for_stmt, .range_stmt, .forever_stmt => {
                const range = self.source.checked.loop_ranges[source];
                return self.loopStatement(source, self.source.checked.loop_carries[range.start..][0..range.len], depth + 1);
            },
            .break_stmt, .continue_stmt => {
                const index = if (self.scratch.loop_exit_indices.len == 0) 0 else self.scratch.loop_exit_indices[source];
                if (index == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    return 0;
                }
                const exit = self.source.checked.loop_exits[index - 1];
                return self.breakStatement(source, exit.loop, self.source.checked.types.list(exit.bindings));
            },
            .let_stmt => {
                const value = self.source.tree.binding(source);
                const binding = self.source.checked.resolved[source];
                if (self.source.tree.node(value.pattern).tag != .pattern_name or value.fallback != 0 or binding == 0) {
                    return self.make(source, .{ .tag = .pattern_bind, .ty = T.unit, .a = try self.patternNode(value.pattern, depth + 1), .b = try self.expression(value.value, depth + 1), .c = try self.suite(value.fallback, depth + 1) });
                }
                return self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = try self.expression(value.value, depth + 1) });
            },
            .use_stmt, .iterator_bind => {
                const value = try self.expression(syntax.b, depth + 1);
                if (syntax.a == 0 or std.mem.eql(u8, self.source.names.get(syntax.a), "_")) return value;
                const binding = self.source.checked.resolved[source];
                if (binding == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    return 0;
                }
                return self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = value });
            },
            .rebind_stmt => {
                const binding = self.source.checked.resolved[source];
                if (binding == 0) {
                    try self.diagnostic(.unresolved_binding, source);
                    return 0;
                }
                if (source < self.source.checked.rebindings.len and self.source.checked.rebindings[source].path.len != 0) {
                    const metadata = self.source.checked.rebindings[source];
                    const type_path = self.source.checked.types.list(self.source.checked.access_types[source]);
                    const source_path = self.source.checked.types.list(metadata.path);
                    if (type_path.len != source_path.len + 1) {
                        try self.diagnostic(.unresolved_binding, source);
                        return 0;
                    }
                    const root = try self.referenceNode(source, metadata.root, try self.projectType(type_path[0], 0));
                    var path: std.ArrayList(core.Id) = .empty;
                    defer path.deinit(self.allocator);
                    var selectors: std.ArrayList(core.UpdateStep) = .empty;
                    defer selectors.deinit(self.allocator);
                    var mixed = false;
                    for (source_path) |catalog| if (catalog == 0) {
                        mixed = true;
                        break;
                    };
                    if (mixed) {
                        const access_nodes = self.source.checked.types.list(self.source.checked.access_nodes[source]);
                        if (access_nodes.len != source_path.len) {
                            try self.diagnostic(.unresolved_binding, source);
                            return 0;
                        }
                        for (source_path, access_nodes, 0..) |catalog, access_id, index| {
                            const access = self.source.tree.node(access_id);
                            const owner_type = try self.projectType(type_path[index], 0);
                            const result_type = try self.projectType(type_path[index + 1], 0);
                            if (access.tag == .index_access and catalog == 0) {
                                try selectors.append(self.allocator, .{ .kind = .index, .index = try self.expression(access.b, depth + 1), .source_type = owner_type, .result_type = result_type });
                            } else if (access.tag == .field_access and catalog != 0) {
                                try selectors.append(self.allocator, .{ .kind = .field, .projection = try self.projectionIndex(catalog, owner_type, result_type), .source_type = owner_type, .result_type = result_type });
                            } else {
                                try self.diagnostic(.unresolved_binding, access_id);
                                return 0;
                            }
                        }
                    } else for (source_path, 0..) |catalog, index| try path.append(self.allocator, try self.projectionIndex(catalog, try self.projectType(type_path[index], 0), try self.projectType(type_path[index + 1], 0)));
                    const range = try self.save(path.items);
                    if (selectors.items.len > std.math.maxInt(u32) - self.tables.update_steps.items.len) return error.CoreLimit;
                    const selector_range: core.List = .{ .start = @intCast(self.tables.update_steps.items.len), .len = @intCast(selectors.items.len) };
                    try self.tables.update_steps.appendSlice(self.allocator, selectors.items);
                    const value = try self.expression(syntax.b, depth + 1);
                    const index: u32 = @intCast(self.tables.updates.items.len);
                    try self.tables.updates.append(self.allocator, .{ .root = root, .path = range, .value = value, .self_binding = metadata.self_binding, .selectors = selector_range });
                    const updated = try self.make(source, .{ .tag = .update, .ty = try self.projectType(self.source.checked.bindings[binding].ty, 0), .a = index });
                    return self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = updated });
                }
                return self.make(source, .{ .tag = .bind, .ty = T.unit, .a = binding, .b = try self.expression(syntax.b, depth + 1) });
            },
            .return_stmt => {
                if (syntax.b != 0 or self.scratch.return_target == 0) {
                    try self.diagnostic(.unsupported, source);
                    return 0;
                }
                return self.make(source, .{ .tag = .return_, .ty = T.never, .a = try self.expression(syntax.a, depth + 1), .b = self.scratch.return_target });
            },
            .function_return_stmt => {
                if (self.scratch.function_target == 0) {
                    try self.diagnostic(.unsupported, source);
                    return 0;
                }
                return self.make(source, .{ .tag = .return_, .ty = T.never, .a = try self.expression(syntax.a, depth + 1), .b = self.scratch.function_target });
            },
            .if_stmt => {
                const id = try self.make(source, .{ .tag = .if_stmt, .ty = T.unit, .a = try self.expression(syntax.a, depth + 1), .b = try self.suite(syntax.b, depth + 1), .c = try self.suite(syntax.c, depth + 1) });
                try self.copyMerges(source, id);
                return id;
            },
            .case_expr => {
                if (self.carryingCase(source)) return self.caseStatement(source, depth + 1);
                return self.expression(source, depth + 1);
            },
            .if_let_stmt => {
                const input = try self.expression(syntax.b, depth + 1);
                const input_range = try self.save(&.{input});
                const pattern = try self.patternNode(syntax.a, depth + 1);
                const success_row = try self.addPatternRow(&.{pattern});
                const wildcard = try self.addPattern(source, .{ .tag = .wildcard, .ty = self.tables.nodes.items[input].ty });
                const fallback_row = try self.addPatternRow(&.{wildcard});
                const suites = self.source.tree.extra.items[syntax.c..][0..2];
                const then_body = try self.suite(suites[0], depth + 1);
                const else_body = try self.suite(suites[1], depth + 1);
                const arm_start: u32 = @intCast(self.tables.match_arms.items.len);
                try self.tables.match_arms.appendSlice(self.allocator, &.{
                    .{ .rows = .{ .start = success_row, .len = 1 }, .body = then_body, .span = self.source.tree.span(source) },
                    .{ .rows = .{ .start = fallback_row, .len = 1 }, .body = else_body, .span = self.source.tree.span(source) },
                });
                const index: u32 = @intCast(self.tables.matches.items.len);
                try self.tables.matches.append(self.allocator, .{ .inputs = input_range, .arms = .{ .start = arm_start, .len = 2 }, .statement = true });
                const id = try self.make(source, .{ .tag = .match, .ty = T.unit, .a = index });
                try self.copyMerges(source, id);
                return id;
            },
            else => return self.expression(source, depth + 1),
        }
    }
    fn statementArm(self: *const Builder, source: ast.Id) bool {
        return self.scratch.statement_arms.len != 0 and self.scratch.statement_arms[source] != 0;
    }
    fn carryingCase(self: *const Builder, source: ast.Id) bool {
        const syntax = self.source.tree.node(source);
        for (self.source.tree.list(.{ .start = syntax.b, .len = syntax.c })) |arm| {
            if (self.statementArm(self.source.tree.extra.items[self.source.tree.node(arm).c + 1])) return true;
        }
        return false;
    }
    /// A statement case whose do: arms carry rebinding outward lowers to nested
    /// two-arm statement matches, so every level keeps an if let's binary
    /// merges. Level k tests arm k; otherwise it binds the inputs once and
    /// continues with level k + 1. The last level tests the last two arms, and
    /// a lone arm falls back to its unreachable incoming versions.
    fn caseStatement(self: *Builder, source: ast.Id, depth: usize) Error!core.Id {
        const syntax = self.source.tree.node(source);
        const source_inputs = self.source.tree.extra.items[syntax.a..][0..2];
        var inputs: std.ArrayList(core.Id) = .empty;
        defer inputs.deinit(self.allocator);
        for (self.source.tree.list(.{ .start = source_inputs[0], .len = source_inputs[1] })) |input| try inputs.append(self.allocator, try self.expression(input, depth + 1));
        const id = try self.caseLevel(source, self.source.tree.list(.{ .start = syntax.b, .len = syntax.c }), 0, inputs.items, depth + 1);
        self.scratch.ast_map[source] = id;
        return id;
    }
    fn caseLevel(self: *Builder, source: ast.Id, arms: []const ast.Id, level: usize, inputs: []const core.Id, depth: usize) Error!core.Id {
        if (depth >= 1024) {
            try self.diagnostic(.complexity, source);
            return 0;
        }
        const input_range = try self.save(inputs);
        const tested = try self.caseArm(arms[level], depth + 1);
        const fallback: core.MatchArm = switch (arms.len - level) {
            1 => blk: {
                var wildcards: std.ArrayList(core.PatternId) = .empty;
                defer wildcards.deinit(self.allocator);
                for (inputs) |input| try wildcards.append(self.allocator, try self.addPattern(source, .{ .tag = .wildcard, .ty = self.tables.nodes.items[input].ty }));
                const row = try self.addPatternRow(wildcards.items);
                break :blk .{ .rows = .{ .start = row, .len = 1 }, .body = 0, .span = self.source.tree.span(source) };
            },
            2 => try self.caseArm(arms[level + 1], depth + 1),
            else => blk: {
                const next = arms[level + 1];
                var binders: std.ArrayList(core.PatternId) = .empty;
                defer binders.deinit(self.allocator);
                var references: std.ArrayList(core.Id) = .empty;
                defer references.deinit(self.allocator);
                for (inputs) |input| {
                    const ty = self.tables.nodes.items[input].ty;
                    if (self.tables.bindings.items.len == std.math.maxInt(u32)) return error.CoreLimit;
                    const binding: core.BindingId = @intCast(self.tables.bindings.items.len);
                    try self.tables.bindings.append(self.allocator, .{ .kind = .local, .ty = ty, .scheme = .{ .root = ty }, .target = .{ .binding = 0 }, .span = self.source.tree.span(next) });
                    try binders.append(self.allocator, try self.addPattern(next, .{ .tag = .bind, .ty = ty, .a = binding }));
                    try references.append(self.allocator, try self.referenceNode(next, binding, ty));
                }
                const row = try self.addPatternRow(binders.items);
                const rest = try self.caseLevel(source, arms, level + 1, references.items, depth + 1);
                const children = try self.save(&.{rest});
                break :blk .{ .rows = .{ .start = row, .len = 1 }, .body = try self.make(next, .{ .tag = .suite, .ty = T.unit, .a = children.start, .b = children.len }), .span = self.source.tree.span(next) };
            },
        };
        const arm_start: u32 = @intCast(self.tables.match_arms.items.len);
        try self.tables.match_arms.appendSlice(self.allocator, &.{ tested, fallback });
        const index: u32 = @intCast(self.tables.matches.items.len);
        try self.tables.matches.append(self.allocator, .{ .inputs = input_range, .arms = .{ .start = arm_start, .len = 2 }, .statement = true });
        const id = try self.make(if (level == 0) source else arms[level], .{ .tag = .match, .ty = T.unit, .a = index });
        try self.copyMerges(arms[level], id);
        return id;
    }
    /// A carrying do: arm runs as its level's suite, like an if branch. A
    /// return written directly in it ends the arm, so only its value remains.
    /// Any other arm body is that suite's one discarded statement.
    fn caseArm(self: *Builder, source: ast.Id, depth: usize) Error!core.MatchArm {
        const syntax = self.source.tree.node(source);
        const row_start: u32 = @intCast(self.tables.pattern_rows.items.len);
        for (self.source.tree.list(.{ .start = syntax.a, .len = syntax.b })) |row_source| {
            var patterns: std.ArrayList(core.Id) = .empty;
            defer patterns.deinit(self.allocator);
            for (self.source.tree.children(row_source)) |pattern_source| try patterns.append(self.allocator, try self.patternNode(pattern_source, depth + 1));
            _ = try self.addPatternRow(patterns.items);
        }
        const rows: core.List = .{ .start = row_start, .len = @intCast(self.tables.pattern_rows.items.len - row_start) };
        const details = self.source.tree.extra.items[syntax.c..][0..2];
        const guard = try self.expression(details[0], depth + 1);
        var children: std.ArrayList(core.Id) = .empty;
        defer children.deinit(self.allocator);
        if (self.statementArm(details[1])) {
            for (self.source.tree.children(details[1])) |child| {
                const statement_ = self.source.tree.node(child);
                if (statement_.tag == .return_stmt) {
                    if (statement_.a != 0) try children.append(self.allocator, try self.expression(statement_.a, depth + 1));
                } else try children.append(self.allocator, try self.statement(child, depth + 1));
            }
        } else try children.append(self.allocator, try self.expression(details[1], depth + 1));
        const range = try self.save(children.items);
        const body = try self.make(details[1], .{ .tag = .suite, .ty = T.unit, .a = range.start, .b = range.len });
        if (self.statementArm(details[1])) self.scratch.ast_map[details[1]] = body;
        return .{ .rows = rows, .guard = guard, .body = body, .span = self.source.tree.span(source) };
    }
    fn copyMerges(self: *Builder, source: ast.Id, id: core.Id) Error!void {
        const start: u32 = @intCast(self.tables.merges.items.len);
        var index = if (self.scratch.merge_heads.len == 0) std.math.maxInt(u32) else self.scratch.merge_heads[source];
        while (index != std.math.maxInt(u32)) : (index = self.scratch.merge_next[index]) {
            const merge = self.source.checked.merges[index];
            try self.tables.merges.append(self.allocator, .{ .node = id, .result = merge.result, .then_binding = merge.then_binding, .else_binding = merge.else_binding });
        }
        self.tables.merge_ranges.items[id] = .{ .start = start, .len = @intCast(self.tables.merges.items.len - start) };
    }
    fn allBindings(self: *Builder) Error!void {
        for (self.source.checked.bindings, 0..) |value, i| {
            var has_explicit = value.summary.has_explicit;
            for (self.source.checked.obligations[value.scheme.obligations.start..][0..value.scheme.obligations.len]) |requirement| {
                has_explicit = has_explicit or requirement.explicit or (requirement.kind == .callee_use and self.source.checked.bindings[requirement.identity.decl].summary.has_explicit);
            }
            try self.tables.bindings.append(self.allocator, .{ .capability_flow = if (value.kind == .global) value.capability_flow else .unknown, .capability_parameters = if (value.kind == .global) value.capability_parameters else .{}, .private = value.private, .kind = value.kind, .ty = try self.projectType(value.ty, 0), .scheme = try self.projectScheme(value.scheme, value.kind == .local), .public_variables = try self.projectPublic(value.summary.public_variables, false), .public_rows = try self.projectPublic(value.summary.public_rows, true), .has_explicit = has_explicit, .target = if (i == 0) .{ .binding = 0 } else self.target(@intCast(i)), .span = self.source.tree.span(value.declaration) });
            // Source parameters have no generalization scheme. Core owns their
            // exact monomorphic storage root, just like synthetic parameters.
            if (value.kind == .parameter and value.scheme.root == 0 and value.scheme.variables.len == 0 and value.scheme.row_variables.len == 0 and value.scheme.closed_rows.len == 0 and value.scheme.obligations.len == 0) {
                const parameter = &self.tables.bindings.items[i];
                parameter.scheme.root = parameter.ty;
            }
        }
    }
    fn projectedTypeList(self: *Builder, source: T.List) Error!T.List {
        var values: std.ArrayList(T.Id) = .empty;
        defer values.deinit(self.allocator);
        for (self.source.checked.types.list(source)) |id| try values.append(self.allocator, try self.projectType(id, 0));
        return self.saveTypes(values.items);
    }
    fn projectedRows(self: *Builder, source: T.List) Error!T.List {
        var values: std.ArrayList(u32) = .empty;
        defer values.deinit(self.allocator);
        for (self.source.checked.types.list(source)) |row| try values.append(self.allocator, try self.projectRow(row, 0));
        return self.saveTypes(values.items);
    }
    fn projectedRowVariables(self: *Builder, source: T.List) Error!T.List {
        var values: std.ArrayList(u32) = .empty;
        defer values.deinit(self.allocator);
        for (self.source.checked.types.list(source)) |variable| try values.append(self.allocator, try self.projectRowVariable(variable));
        return self.saveTypes(values.items);
    }
    fn allCatalogs(self: *Builder) Error!void {
        try self.tables.proof_contracts.ensureUnusedCapacity(self.allocator, self.source.checked.proof_contracts.len);
        for (self.source.checked.proof_contracts) |contract| {
            const header = try contract.header.clone(self.allocator);
            self.tables.proof_contracts.appendAssumeCapacity(.{ .binding = contract.binding, .header = header });
        }
        for (self.source.checked.nominals) |metadata| {
            const constructors = try self.save(self.source.checked.types.list(metadata.constructors));
            const display = try self.nominalDiagnosticNames(metadata);
            try self.tables.nominals.append(self.allocator, .{ .affine = metadata.affine, .has_usage = metadata.has_usage, .closed_storage = metadata.closed_storage, .private = metadata.private, .is_opaque = metadata.is_opaque, .storage = metadata.storage, .diagnostic_name = display.name, .diagnostic_origin = display.origin, .identity = metadata.identity, .parameters = try self.projectedTypeList(metadata.parameters), .variables = try self.projectedTypeList(metadata.variables), .constructors = constructors });
        }
        for (self.source.checked.effect_templates) |metadata| {
            if (metadata.identity.decl == 0 or metadata.family == 0) continue;
            const family = self.source.checked.effect_families[metadata.family];
            if (family.name == 0 or (!family.callable and metadata.name == 0)) continue;
            const origin = self.source.diagnostic_origins.name(self.allocator, metadata.identity.unit, self.source.checked.unit) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };
            defer self.allocator.free(origin);
            const name = if (family.callable) try self.allocator.dupe(u8, self.source.names.get(family.name)) else try self.allocator.print("{s}.{s}", .{ self.source.names.get(family.name), self.source.names.get(metadata.name) });
            defer self.allocator.free(name);
            try self.tables.operation_names.append(self.allocator, .{
                .identity = metadata.identity,
                .diagnostic_name = try self.saveName(name),
                .diagnostic_origin = try self.saveName(origin),
                .variables = try self.projectedTypeList(family.variables),
                .parameters = try self.projectedTypeList(family.parameters),
                .parameter = try self.projectType(metadata.parameter, 0),
                .result = try self.projectType(metadata.result, 0),
            });
        }
        for (self.source.checked.contracts) |contract| {
            if (contract.members.len == 0) continue;
            const start: u32 = @intCast(self.tables.contract_members.items.len);
            for (self.source.checked.contract_members[contract.members.start..][0..contract.members.len]) |old| {
                var member = old;
                member.root = try self.projectType(old.root, 0);
                try self.tables.contract_members.append(self.allocator, member);
            }
            const predicate_start: u32 = @intCast(self.tables.obligations.items.len);
            for (self.source.checked.contract_predicates[contract.predicates.start..][0..contract.predicates.len]) |value| try self.tables.obligations.append(self.allocator, .{ .ty = try self.projectType(value.ty, 0), .kind = value.kind, .span = self.source.checked.diagnosticSpan(self.source.tree, value.source), .name = value.name, .result = try self.projectType(value.result, 0), .other = try self.projectType(value.other, 0), .signature = try self.projectType(value.signature, 0), .operator = value.operator, .identity = value.identity, .explicit = value.explicit, .qualification_span = value.qualification_span, .qualification_unit = value.qualification_unit });
            try self.tables.contracts.append(self.allocator, .{ .private = contract.private, .identity = contract.identity, .name = contract.name, .parameters = try self.projectedTypeList(contract.parameters), .variables = try self.projectedTypeList(contract.variables), .row_variables = try self.projectedRowVariables(contract.row_variables), .predicates = .{ .start = predicate_start, .len = contract.predicates.len }, .members = .{ .start = start, .len = contract.members.len }, .requires_implementation = contract.requires_implementation, .row_parameter_names = try self.saveTypes(self.source.checked.types.list(contract.row_parameter_names)), .row_parameters = try self.projectedRows(contract.row_parameters) });
        }
        for (self.source.checked.constructors) |metadata| try self.tables.constructors.append(self.allocator, .{ .identity = metadata.identity, .nominal = metadata.nominal, .tag = metadata.tag, .scheme = try self.projectScheme(metadata.scheme, false), .payload = try self.projectType(metadata.payload, 0) });
        for (self.source.checked.associated) |metadata| try self.tables.associated.append(self.allocator, .{ .identity = metadata.identity, .member = metadata.member, .operator = metadata.operator, .target = self.target(metadata.binding) });
        try self.implementationCatalog();
    }
    fn implementationCatalog(self: *Builder) Error!void {
        for (self.source.checked.implementations) |old| {
            var declaration = old;
            declaration.declaration = 0;
            declaration.head = try self.projectedTypeList(old.head);
            declaration.variables = try self.projectedTypeList(old.variables);
            declaration.parameter_names = try self.saveTypes(self.source.checked.types.list(old.parameter_names));
            declaration.row_variables = try self.projectedRowVariables(old.row_variables);
            declaration.row_parameter_names = try self.saveTypes(self.source.checked.types.list(old.row_parameter_names));
            declaration.row_parameters = try self.projectedRows(old.row_parameters);
            const members: u32 = @intCast(self.tables.implementation_members.items.len);
            for (self.source.checked.implementation_members[old.members.start..][0..old.members.len]) |before| {
                var member = before;
                member.root = try self.projectType(before.root, 0);
                try self.tables.implementation_members.append(self.allocator, member);
            }
            declaration.members = .{ .start = members, .len = old.members.len };
            const predicates: u32 = @intCast(self.tables.obligations.items.len);
            for (self.source.checked.implementation_predicates[old.predicates.start..][0..old.predicates.len]) |old_predicate| {
                var value = old_predicate;
                if (@import("../eval/implementation_predicates.zig").inferredCarrier(&self.source.checked.types, value, old.row_parameters)) value.signature = 0;
                try self.tables.obligations.append(self.allocator, .{ .ty = try self.projectType(value.ty, 0), .kind = value.kind, .span = self.source.checked.diagnosticSpan(self.source.tree, value.source), .name = value.name, .result = try self.projectType(value.result, 0), .other = try self.projectType(value.other, 0), .signature = try self.projectType(value.signature, 0), .operator = value.operator, .identity = value.identity, .explicit = true, .qualification_span = value.qualification_span, .qualification_unit = value.qualification_unit });
            }
            declaration.predicates = .{ .start = predicates, .len = old.predicates.len };
            try self.tables.implementations.append(self.allocator, declaration);
        }
        for (self.source.checked.member_templates) |old| {
            var template = old;
            template.arguments = try self.projectedTypeList(old.arguments);
            try self.tables.member_templates.append(self.allocator, template);
        }
        for (self.source.checked.selected_members) |old| {
            var member = old;
            member.root = try self.projectType(old.root, 0);
            try self.tables.selected_members.append(self.allocator, member);
        }
        try self.tables.selected_edges.appendSlice(self.allocator, self.source.checked.selected_edges);
        for (self.source.checked.selected_proofs) |old| {
            var proof = old;
            proof.arguments = try self.projectedTypeList(old.arguments);
            inline for (.{ "ty", "other", "result", "signature" }) |field| @field(proof.predicate, field) = try self.projectType(@field(old.predicate, field), 0);
            proof.predicate.source = 0;
            try self.tables.selected_proofs.append(self.allocator, proof);
        }
    }
    fn memberTemplateBody(self: *Builder, template_index: u32) Error!void {
        self.scratch.body_lowerings += 1;
        const template = self.tables.member_templates.items[template_index];
        const source = self.source.checked.bindings[template.binding].declaration;
        const span = self.source.tree.span(source);
        const body_id: core.BodyId = @intCast(self.tables.bodies.items.len);
        const start: u32 = @intCast(self.tables.parameters.items.len);
        var arguments: std.ArrayList(core.Id) = .empty;
        defer arguments.deinit(self.allocator);
        var root = self.tables.bindings.items[template.binding].ty;
        while (self.tables.type_nodes.items[root].tag == .function) {
            const arrow = self.tables.type_nodes.items[root];
            const parameter: core.BindingId = @intCast(self.tables.bindings.items.len);
            try self.tables.bindings.append(self.allocator, .{ .kind = .parameter, .ty = arrow.a, .scheme = .{ .root = arrow.a }, .target = .{ .unit = self.source.checked.unit, .binding = parameter }, .span = span });
            try self.tables.parameters.append(self.allocator, .{ .binding = parameter, .ty = arrow.a, .span = span });
            const reference: u32 = @intCast(self.tables.references.items.len);
            try self.tables.references.append(self.allocator, .{ .unit = self.source.checked.unit, .binding = parameter });
            try arguments.append(self.allocator, try self.make(source, .{ .tag = .reference, .ty = arrow.a, .a = reference }));
            root = arrow.b;
            if (arguments.items.len >= 256) return error.CoreLimit;
        }
        const list = try self.save(arguments.items);
        const body = try self.make(source, .{ .tag = .contract_method, .ty = root, .a = template_index, .b = list.start, .c = list.len });
        try self.tables.bodies.append(self.allocator, .{ .binding = template.binding, .root = body, .parameters = .{ .start = start, .len = list.len }, .scheme = self.tables.bindings.items[template.binding].scheme, .span = span, .is_function = true });
        self.tables.bindings.items[template.binding].body_id = body_id;
    }
    fn saveName(self: *Builder, text: []const u8) Error!core.Name {
        if (text.len > std.math.maxInt(u32) -| self.tables.name_bytes.items.len) return error.CoreLimit;
        const result: core.Name = .{ .start = @intCast(self.tables.name_bytes.items.len), .len = @intCast(text.len) };
        try self.tables.name_bytes.appendSlice(self.allocator, text);
        return result;
    }
    fn nominalDiagnosticNames(self: *Builder, nominal: checked_types.Nominal) Error!struct { name: core.Name = .{}, origin: core.Name = .{} } {
        if (nominal.name == 0 or nominal.identity.decl == 0) return .{};
        const owner = self.source.diagnostic_origins.name(self.allocator, nominal.identity.unit, self.source.checked.unit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{},
        };
        defer self.allocator.free(owner);
        return .{ .name = try self.saveName(self.source.names.get(nominal.name)), .origin = try self.saveName(owner) };
    }
    // A bare interface member denotes a dictionary abstraction. Materialize
    // one application boundary, preserving effects in later curried arrows.
    fn memberAlias(self: *Builder, source: ast.Id, owner: core.BindingId, root: core.Id) Error!?core.Id {
        const node = self.tables.nodes.items[root];
        if (node.tag != .reference or self.tables.type_nodes.items[node.ty].tag != .function) return null;
        const principal = self.tables.bindings.items[owner].scheme;
        if (principal.variables.len == 0 and self.tables.type_nodes.items[principal.root].tag != .forall) return null;
        const reference = self.tables.references.items[node.a];
        const template = for (self.tables.member_templates.items) |candidate| {
            if (std.meta.eql(self.target(candidate.binding), reference)) break candidate;
        } else return null;
        var required = false;
        for (self.tables.obligations.items[principal.obligations.start..][0..principal.obligations.len]) |goal| {
            if (goal.kind == .contract and std.meta.eql(goal.identity, template.contract)) required = true;
        }
        if (!required and self.tables.type_nodes.items[principal.root].tag != .forall) return null;
        const arrow = self.tables.type_nodes.items[node.ty];
        const parameter: core.BindingId = @intCast(self.tables.bindings.items.len);
        const span = self.source.tree.span(source);
        try self.tables.bindings.append(self.allocator, .{ .kind = .parameter, .ty = arrow.a, .scheme = .{ .root = arrow.a }, .target = .{ .unit = self.source.checked.unit, .binding = parameter }, .span = span });
        try self.tables.parameters.append(self.allocator, .{ .binding = parameter, .ty = arrow.a, .span = span });
        const operand: u32 = @intCast(self.tables.references.items.len);
        try self.tables.references.append(self.allocator, .{ .unit = self.source.checked.unit, .binding = parameter });
        const argument = try self.make(source, .{ .tag = .reference, .ty = arrow.a, .a = operand });
        const call: u32 = @intCast(self.tables.calls.items.len);
        try self.tables.calls.append(self.allocator, .{ .target = reference, .callee_type = node.ty });
        const values = try self.save(&.{argument});
        return try self.make(source, .{ .tag = .call, .ty = arrow.b, .a = call, .b = values.start, .c = values.len });
    }
    fn allBodies(self: *Builder) Error!void {
        // Group certificates once by owning body. Recursive inference may append
        // decisions out of declaration order, so a per-body full scan would
        // make publication quadratic in the number of bodies and row tails.
        const certificates = try self.allocator.alloc(T.List, self.source.checked.bindings.len);
        defer self.allocator.free(certificates);
        @memset(certificates, .{});
        if (self.source.checked.body_closed_rows.len > std.math.maxInt(u32) - self.tables.type_extra.items.len) return error.CoreLimit;
        for (self.source.checked.body_closed_rows) |decision| {
            if (decision.owner >= certificates.len) return error.CoreLimit;
            certificates[decision.owner].len += 1;
        }
        var certificate_start: u32 = @intCast(self.tables.type_extra.items.len);
        for (certificates) |*range| {
            range.start = certificate_start;
            certificate_start += range.len;
        }
        try self.tables.type_extra.appendNTimes(self.allocator, 0, self.source.checked.body_closed_rows.len);
        for (self.source.checked.body_closed_rows) |decision| {
            const range = &certificates[decision.owner];
            self.tables.type_extra.items[range.start] = try self.projectRowVariable(decision.variable);
            range.start += 1;
        }
        for (certificates) |*range| range.start -= range.len;
        for (self.source.checked.bindings, 0..) |value, index| {
            if (index == 0 or value.kind != .global) continue;
            const template = for (self.tables.member_templates.items, 0..) |candidate, ordinal| {
                if (candidate.binding == index) break @as(?u32, @intCast(ordinal));
            } else null;
            if (template) |ordinal| {
                try self.memberTemplateBody(ordinal);
                continue;
            }
            const declaration = self.source.tree.valueDecl(value.declaration);
            self.scratch.body_lowerings += 1;
            const body_id: core.BodyId = @intCast(self.tables.bodies.items.len);
            const start: u32 = @intCast(self.tables.parameters.items.len);
            var source = self.unwrap(declaration.body);
            const introduction = source;
            var function = declaration.attributes.len == 0 and self.source.tree.node(source).tag == .lambda;
            var innermost_lambda: ast.Id = 0;
            while (declaration.attributes.len == 0 and self.source.tree.node(source).tag == .lambda) {
                const boundary = self.source.checked.types.node(self.source.checked.types.head(self.source.checked.expr_types[source], 0)).tag;
                if (self.tables.parameters.items.len != start and (boundary == .usage or boundary == .forall)) break;
                const lambda = self.source.tree.node(source);
                innermost_lambda = source;
                try self.tables.parameters.append(self.allocator, .{ .binding = self.source.checked.resolved[lambda.a], .ty = try self.typeOf(lambda.a), .span = self.source.tree.span(lambda.a), .inferred = self.source.tree.parameter(lambda.a).annotation == 0 and !self.source.tree.parameter(lambda.a).is_unit });
                source = self.unwrap(lambda.b);
            }
            const function_block = if (function and std.mem.findScalar(ast.Id, self.source.checked.function_exit_lambdas, innermost_lambda) != null) try self.reserve(source) else 0;
            var root = blk: {
                const previous_function = self.scratch.function_target;
                self.scratch.function_target = function_block;
                defer self.scratch.function_target = previous_function;
                break :blk try self.taggedExpression(self.source.tree.list(declaration.attributes), source, 0);
            };
            if (function_block != 0) {
                var result_type = self.tables.bindings.items[index].ty;
                for (self.tables.parameters.items[start..]) |_| {
                    const arrow = try self.callableType(result_type);
                    if (arrow.tag != .function) return error.CoreLimit;
                    result_type = arrow.b;
                }
                const completion = try self.make(source, .{ .tag = .return_, .ty = T.never, .a = root, .b = function_block });
                const children = try self.save(&.{completion});
                self.tables.nodes.items[function_block] = .{ .tag = .block, .ty = result_type, .a = children.start, .b = children.len };
                root = function_block;
            }
            if (!function and !declaration.runtime and declaration.attributes.len == 0) {
                if (try self.memberAlias(source, @intCast(index), root)) |alias_root| {
                    root = alias_root;
                    function = true;
                }
            }
            self.scratch.ast_map[introduction] = root;
            // Own the spelling of unexported declarations too. Source offsets
            // are diagnostic coordinates and move after unrelated body edits.
            const bytes = self.source.names.get(value.name);
            const declaration_name: core.Name = .{ .start = @intCast(self.tables.name_bytes.items.len), .len = @intCast(bytes.len) };
            try self.tables.name_bytes.appendSlice(self.allocator, bytes);
            const export_name: core.Name = if (declaration.exported) declaration_name else .{};
            try self.tables.bodies.append(self.allocator, .{ .binding = @intCast(index), .root = root, .parameters = .{ .start = start, .len = @intCast(self.tables.parameters.items.len - start) }, .scheme = self.tables.bindings.items[index].scheme, .closed_rows = certificates[index], .span = self.source.tree.span(value.declaration), .declaration_name = declaration_name, .export_name = export_name, .exported = declaration.exported, .runtime = declaration.runtime, .is_function = function });
            self.tables.bindings.items[index].body_id = body_id;
            try self.tables.source_names.append(self.allocator, .{ .binding = @intCast(index), .point = self.source.tree.valueNamePoint(value.declaration) orelse self.source.tree.span(value.declaration).start });
            if (declaration.runtime) try self.tables.runtime_names.append(self.allocator, .{ .binding = @intCast(index), .point = self.source.tree.runtimeNamePoint(value.declaration) orelse self.source.tree.span(value.declaration).start });
        }
    }
    fn finish(self: *Builder) Allocator.Error!core.Module {
        var result = try self.tables.finish(self.allocator, self.scratch.body_lowerings, self.scratch.effect_variable_count, self.scratch.ast_map);
        errdefer result.deinit(self.allocator);
        result.capability_contracts = self.source.checked.capability_contracts.select(self.allocator, self.source.checked.bindings, null) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        return result;
    }
};

/// Produce immutable typed bodies without evaluating, specializing or emitting
/// any source constant. Dead constants and dead branches remain ordinary IR.
pub fn lower(allocator: Allocator, tree: *const ast.Tree, names: *const symbols.Pool, checked: *const checked_types.Checked) !core.Module {
    return lowerWithOrigins(allocator, tree, names, checked, .{});
}

/// Capture diagnostic spellings alongside immutable Core before source owners end.
pub fn lowerWithOrigins(allocator: Allocator, tree: *const ast.Tree, names: *const symbols.Pool, checked: *const checked_types.Checked, diagnostic_origins: checked_types.ModuleOrigins) !core.Module {
    var builder: Builder = .{ .allocator = allocator, .source = .{ .tree = tree, .names = names, .checked = checked, .diagnostic_origins = diagnostic_origins } };
    defer builder.deinit();
    try builder.initialize();
    if (checked.diagnostics.len != 0) {
        try builder.diagnostic(.unchecked, 0);
    } else {
        try builder.allBindings();
        try builder.allCatalogs();
        try builder.allBodies();
    }
    var result = try builder.finish();
    errdefer result.deinit(allocator);
    result.unit = checked.unit;
    // Capture before source/checker teardown. All arrays publish together.
    try @import("../reuse/declaration_dependencies.zig").capture(allocator, &result);
    return result;
}

fn binaryOp(text: []const u8) ?core.Op {
    const names = [_][]const u8{ "+", "-", "*", "/", "%", "==", "!=", "<", "<=", ">", ">=", "&", "|", "^", "<<", ">>", "and", "or" };
    const ops = [_]core.Op{ .add, .sub, .mul, .div, .rem, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .and_, .or_ };
    for (names, ops) |name, op| if (std.mem.eql(u8, text, name)) return op;
    return null;
}
fn memberOp(text: []const u8) core.Op {
    const names = [_][]const u8{ "add", "sub", "mul", "div", "rem", "eq", "ne", "lt", "le", "gt", "ge", "bit_and", "bit_or", "bit_xor", "shl", "shr" };
    const ops = [_]core.Op{ .add, .sub, .mul, .div, .rem, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right };
    for (names, ops) |name, op| if (std.mem.eql(u8, text, name)) return op;
    return .none;
}
const Intrinsic = struct { op: core.Op, arity: u8 };
const ArrayIntrinsic = struct { op: core.ArrayOp, arity: u8 };
fn arrayIntrinsic(text: []const u8) ?ArrayIntrinsic {
    const value = @import("../backend/collection_ops.zig").lookup(text) orelse return null;
    return .{ .op = value.op, .arity = value.arity };
}
fn intrinsic(text: []const u8) ?Intrinsic {
    if (@import("../backend/simd_intrinsics.zig").lookup(text)) |op| return .{ .op = op.op, .arity = op.arity };
    const entries = .{
        .{ "@u32.add", core.Op.add, 2 },        .{ "@u32.sub", core.Op.sub, 2 },         .{ "@u32.mul", core.Op.mul, 2 },                .{ "@u32.div", core.Op.div, 2 },       .{ "@u32.rem", core.Op.rem, 2 },
        .{ "@u32.eq", core.Op.equal, 2 },       .{ "@u32.lt", core.Op.less, 2 },         .{ "@u32.bit_and", core.Op.bit_and, 2 },        .{ "@u32.bit_or", core.Op.bit_or, 2 }, .{ "@u32.bit_xor", core.Op.bit_xor, 2 },
        .{ "@u32.shl", core.Op.shift_left, 2 }, .{ "@u32.shr", core.Op.shift_right, 2 }, .{ "@u32.to_f32", core.Op.convert_u32_f32, 1 }, .{ "@f32.add", core.Op.add, 2 },       .{ "@f32.sub", core.Op.sub, 2 },
        .{ "@f32.mul", core.Op.mul, 2 },        .{ "@f32.div", core.Op.div, 2 },         .{ "@f32.eq", core.Op.equal, 2 },               .{ "@f32.ne", core.Op.not_equal, 2 },  .{ "@f32.lt", core.Op.less, 2 },
        .{ "@f32.le", core.Op.less_equal, 2 },  .{ "@f32.gt", core.Op.greater, 2 },      .{ "@f32.ge", core.Op.greater_equal, 2 },       .{ "@f32.abs", core.Op.abs, 1 },       .{ "@f32.neg", core.Op.neg, 1 },
        .{ "@f32.ceil", core.Op.ceil, 1 },      .{ "@f32.floor", core.Op.floor, 1 },     .{ "@f32.trunc", core.Op.trunc, 1 },            .{ "@f32.sqrt", core.Op.sqrt, 1 },     .{ "@f32.to_u32", core.Op.convert_f32_u32, 1 },
    };
    inline for (entries) |entry| if (std.mem.eql(u8, text, entry[0])) return .{ .op = entry[1], .arity = entry[2] };
    return null;
}
