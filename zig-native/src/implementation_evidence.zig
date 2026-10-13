//! Complete selected semantic proofs. These flat owners contain only closed
//! evidence IDs, original identities and ordinary method targets; selection
//! never evaluates a body or materializes its captures.
const std = @import("std");
const T = @import("types.zig");
const E = @import("type_evidence.zig");
const C = @import("core.zig");
pub const Error = std.mem.Allocator.Error || error{ MissingImplementation, IncompatibleImplementation, RecursiveEvidence, AssociatedLimit, EvidenceLimit, UnresolvedType, TypeMismatch };
pub const Code = enum { missing_implementation, incompatible_implementation, recursive_evidence, recursive_associated_type, associated_limit };
pub const Member = struct { name: u32, kind: @FieldType(C.ImplementationMember, "kind") = .type_, root: E.Id, target: C.BindingRef };
pub const LegacyChoice = struct { target: C.BindingRef, carrier: E.Id = 0 };
pub const Fact = struct { kind: T.ObligationKind = .type_rep, operator: T.Operator = .none, identity: T.NominalIdentity = .{ .unit = 0, .decl = 0 }, name: u32 = 0, operands: [4]E.Id = @splat(0), target: C.BindingRef = .{ .unit = 0, .binding = 0 } };
pub const Proof = struct { kind: enum { implementation, predicate } = .implementation, predicate: Fact = .{}, context: u32, implementation: T.NominalIdentity, contract: T.NominalIdentity, arguments: T.List, members: T.List, prerequisites: T.List };
pub const Snapshot = struct {
    proofs: []Proof = &.{},
    arguments: []E.Id = &.{},
    members: []Member = &.{},
    edges: []u32 = &.{},
    pub fn deinit(self: *Snapshot, a: std.mem.Allocator) void {
        inline for (@typeInfo(Snapshot).@"struct".field_names) |name| a.free(@field(self, name));
    }
};
pub const View = struct { proofs: []const Proof = &.{}, arguments: []const E.Id = &.{}, members: []const Member = &.{}, edges: []const u32 = &.{} };
const FactKey = struct { context: u32, fact: Fact };
pub const Store = struct {
    allocator: std.mem.Allocator,
    proofs: std.ArrayList(Proof) = .empty,
    arguments: std.ArrayList(E.Id) = .empty,
    members: std.ArrayList(Member) = .empty,
    edges: std.ArrayList(u32) = .empty,
    active_arguments: std.ArrayList(E.Id) = .empty,
    active: std.ArrayList(struct { context: u32, contract: T.NominalIdentity, arguments: T.List }) = .empty,
    active_projections: std.ArrayList(struct { context: u32, contract: T.NominalIdentity, member: u32, arguments: T.List }) = .empty,
    provisional_equations: std.ArrayList(struct { context: u32, declaration: C.Implementation, arguments: T.List, mappings: []const E.Mapping, rows: []const E.RowMapping }) = .empty,
    buckets: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    next: std.ArrayList(u32) = .empty,
    facts: std.AutoHashMapUnmanaged(FactKey, u32) = .empty,
    active_facts: std.ArrayList(FactKey) = .empty,
    trace: @import("implementation_trace.zig").Record = .{},
    failure: ?Code = null,
    candidates: u64 = 0,
    prerequisite_edges: u64 = 0,
    hits: u64 = 0,
    max_depth: usize = 0,
    pub fn deinit(self: *Store) void {
        inline for (.{ "proofs", "arguments", "members", "edges", "active", "active_projections", "active_arguments", "provisional_equations", "active_facts", "next" }) |field| @field(self, field).deinit(self.allocator);
        self.facts.deinit(self.allocator);
        self.buckets.deinit(self.allocator);
    }
    pub fn view(self: *const Store) View {
        return .{ .proofs = self.proofs.items, .arguments = self.arguments.items, .members = self.members.items, .edges = self.edges.items };
    }
    pub fn copyOwned(self: *const Store, a: std.mem.Allocator) std.mem.Allocator.Error!Snapshot {
        var result: Snapshot = .{};
        errdefer result.deinit(a);
        inline for (@typeInfo(Snapshot).@"struct".field_names) |name| @field(result, name) = try a.dupe(std.meta.Elem(@FieldType(Snapshot, name)), @field(self, name).items);
        return result;
    }
    fn step(self: *Store, host: anytype) Error!void {
        if (host.associated_remaining == 0) {
            self.failure = .associated_limit;
            for (self.trace.candidates[0..self.trace.len]) |*candidate| if (candidate.outcome == .selected) {
                candidate.outcome = .limit;
            };
            return error.AssociatedLimit;
        }
        host.associated_remaining -= 1;
    }
    fn rejectedPrerequisite(self: *Store, err: Error, identity: T.NominalIdentity, traced: ?usize, kind: T.ObligationKind) Error {
        if (err == error.OutOfMemory) return err;
        if (self.failure == .recursive_evidence or self.failure == .recursive_associated_type) return err;
        if (err == error.AssociatedLimit or err == error.EvidenceLimit or self.failure == .associated_limit) {
            self.failure = .associated_limit;
            self.trace.candidate(identity, .limit);
            self.trace.setOutcome(traced, .limit);
            return error.AssociatedLimit;
        }
        self.failure = .incompatible_implementation;
        self.trace.candidate(identity, .requires_evidence);
        self.trace.setOutcome(traced, @import("implementation_predicates.zig").failureOutcome(kind));
        return error.IncompatibleImplementation;
    }
    fn owner(host: anytype, unit: u32) ?usize {
        for (host.units, 0..) |module, index| {
            var identity = module.unit;
            if (identity == 0) identity = @intCast(index + 1);
            if (identity == unit) return index;
        }
        return null;
    }
    fn canonicalLess(host: anytype, left: C.Implementation, right: C.Implementation) bool {
        const Host = @typeInfo(@TypeOf(host)).pointer.child;
        if (@hasField(Host, "diagnostic_context")) {
            if (host.diagnostic_context.identity) |identity| {
                if (identity.owner(left.identity.unit)) |before| if (identity.owner(right.identity.unit)) |after| {
                    const order = std.mem.order(u8, before, after);
                    if (order != .eq) return order == .lt;
                };
            }
        }
        if (left.identity.unit != right.identity.unit) return left.identity.unit < right.identity.unit;
        if (left.origin_span) |before| if (right.origin_span) |after| {
            if (before.start != after.start) return before.start < after.start;
        };
        if (@hasField(Host, "diagnostic_context")) {
            if (host.diagnostic_context.identity) |identity| {
                if (identity.symbol(left.name)) |before| if (identity.symbol(right.name)) |after| return std.mem.lessThan(u8, before, after);
            }
        }
        return left.identity.decl < right.identity.decl;
    }
    fn key(context: u32, contract: T.NominalIdentity, arguments: []const E.Id) u64 {
        var hash: std.hash.Wyhash = .init(0);
        hash.update(std.mem.asBytes(&context));
        hash.update(std.mem.asBytes(&contract));
        hash.update(std.mem.sliceAsBytes(arguments));
        return hash.final();
    }
    fn sameArguments(self: *const Store, list: T.List, arguments: []const E.Id) bool {
        return list.len == arguments.len and std.mem.eql(E.Id, self.arguments.items[list.start..][0..list.len], arguments);
    }
    fn sameActiveArguments(self: *const Store, list: T.List, arguments: []const E.Id) bool {
        return list.len == arguments.len and std.mem.eql(E.Id, self.active_arguments.items[list.start..][0..list.len], arguments);
    }
    fn depthAvailable(self: *const Store) bool {
        if (self.active.items.len >= 256) return false;
        const remaining = 256 - self.active.items.len;
        if (self.active_projections.items.len >= remaining) return false;
        return self.active_facts.items.len < remaining - self.active_projections.items.len;
    }
    const Mark = struct { proofs: usize, arguments: usize, members: usize, edges: usize };
    fn mark(self: *const Store) Mark {
        return .{ .proofs = self.proofs.items.len, .arguments = self.arguments.items.len, .members = self.members.items.len, .edges = self.edges.items.len };
    }
    fn rollback(self: *Store, point: Mark) void {
        var facts = self.facts.iterator();
        while (facts.next()) |fact| if (fact.value_ptr.* >= point.proofs) {
            _ = self.facts.remove(fact.key_ptr.*);
        };
        var buckets = self.buckets.iterator();
        while (buckets.next()) |entry| {
            var head = entry.value_ptr.*;
            while (head != 0 and head - 1 >= point.proofs) head = self.next.items[head - 1];
            if (head == 0) {
                _ = self.buckets.remove(entry.key_ptr.*);
            } else entry.value_ptr.* = head;
        }
        self.next.shrinkRetainingCapacity(point.proofs);
        inline for (@typeInfo(Mark).@"struct".field_names) |field| @field(self, field).shrinkRetainingCapacity(@field(point, field));
    }
    fn saveActive(self: *Store, arguments: []const E.Id) std.mem.Allocator.Error!T.List {
        const start: u32 = @intCast(self.active_arguments.items.len);
        try self.active_arguments.appendSlice(self.allocator, arguments);
        return .{ .start = start, .len = @intCast(arguments.len) };
    }
    fn saveArguments(self: *Store, arguments: []const E.Id) std.mem.Allocator.Error!T.List {
        const start: u32 = @intCast(self.arguments.items.len);
        try self.arguments.appendSlice(self.allocator, arguments);
        return .{ .start = start, .len = @intCast(arguments.len) };
    }
    fn proveRequirement(self: *Store, host: anytype, context: u32, module: *const C.Module, value: C.Obligation, mappings: []const E.Mapping, rows: []const E.RowMapping, resolver: E.ProjectionResolver) Error!u32 {
        try self.step(host);
        self.prerequisite_edges += 1;
        if (value.kind == .contract) {
            const product = try host.evidence.projectSelected(&module.types, value.ty, mappings, rows, resolver);
            if (host.evidence.node(product).tag != .product) return error.TypeMismatch;
            return self.resolve(host, context, value.identity, host.evidence.children(product));
        }
        const fact = try closedPredicateFrom(host, context, module, value, mappings, rows, resolver, null) orelse {
            self.failure = .incompatible_implementation;
            return error.IncompatibleImplementation;
        };
        return self.proveFact(host, context, fact, resolver);
    }
    fn proveFact(self: *Store, host: anytype, context: u32, value: Fact, resolver: E.ProjectionResolver) Error!u32 {
        try self.step(host);
        const fact_key: FactKey = .{ .context = context, .fact = value };
        if (self.facts.get(fact_key)) |known| {
            self.hits += 1;
            return known;
        }
        if (!self.depthAvailable()) {
            self.failure = .associated_limit;
            return error.AssociatedLimit;
        }
        for (self.active_facts.items) |active| {
            try self.step(host);
            if (active.context == context and std.meta.eql(active.fact, value)) {
                self.failure = .recursive_evidence;
                return error.RecursiveEvidence;
            }
        }
        try self.active_facts.append(self.allocator, fact_key);
        defer _ = self.active_facts.pop();
        var prerequisites: std.ArrayList(u32) = .empty;
        defer prerequisites.deinit(self.allocator);
        if (value.target.binding != 0) {
            // An admitted local external signature preserves the producer's
            // principal clauses without evaluating the producer's captures.
            const module = &host.units[owner(host, context) orelse return error.TypeMismatch];
            var binding_id: C.BindingId = 0;
            const binding = for (module.bindings, 0..) |candidate, ordinal| {
                try self.step(host);
                if ((value.target.unit == context and value.target.binding == ordinal) or (candidate.kind == .external and std.meta.eql(candidate.target, value.target))) {
                    binding_id = @intCast(ordinal);
                    break candidate;
                }
            } else return error.TypeMismatch;
            var mappings: std.ArrayList(E.Mapping) = .empty;
            defer mappings.deinit(self.allocator);
            var rows: std.ArrayList(E.RowMapping) = .empty;
            defer rows.deinit(self.allocator);
            var arity: usize = 2;
            if (value.kind == .field or value.kind == .writable_field or value.kind == .result_dispatch) arity = 1;
            if (value.kind == .callee_use) {
                const pack = host.evidence.node(value.operands[0]);
                if (pack.tag != .product or pack.b != binding.public_variables.len + binding.public_rows.len) return error.TypeMismatch;
                const parts = host.evidence.children(value.operands[0]);
                for (module.types.list(binding.public_variables), parts[0..binding.public_variables.len]) |variable, actual| {
                    try self.step(host);
                    try mappings.append(self.allocator, .{ .variable = variable, .evidence = actual });
                }
                for (module.types.list(binding.public_rows), parts[binding.public_variables.len..]) |variable, actual| {
                    try self.step(host);
                    const carrier = host.evidence.node(actual);
                    if (carrier.tag != .function or carrier.a != T.unit or carrier.b != T.unit) return error.TypeMismatch;
                    try rows.append(self.allocator, .{ .variable = variable, .evidence = carrier.c });
                }
            } else {
                if (value.kind == .resolver_dispatch) {
                    if (!try host.evidence.matchLegacySignature(&module.types, binding.scheme.root, value.operands[1], &mappings, &rows, resolver)) return error.TypeMismatch;
                } else _ = try host.evidence.matchPrerequisite(&module.types, binding.scheme.root, value.operands, arity, &mappings, &rows, resolver) orelse return error.TypeMismatch;
            }
            const clauses = module.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len];
            var certificates: std.ArrayList(u32) = .empty;
            defer certificates.deinit(self.allocator);
            try certificates.appendSlice(self.allocator, module.types.list(binding.scheme.closed_rows));
            if (module.body(binding_id)) |body| try certificates.appendSlice(self.allocator, module.types.list(body.closed_rows));
            try @import("implementation_rows.zig").reconstruct(&host.evidence, &module.types, clauses, certificates.items, module.types.list(binding.scheme.variables), &mappings, &rows, resolver);
            for (rows.items) |mapping| {
                var declared = false;
                for (module.types.list(binding.scheme.row_variables)) |variable| {
                    try self.step(host);
                    if (variable == mapping.variable) {
                        declared = true;
                        break;
                    }
                }
                if (!declared) return error.TypeMismatch;
            }
            for (clauses) |clause| {
                try prerequisites.append(self.allocator, try self.proveRequirement(host, context, module, clause, mappings.items, rows.items, resolver));
            }
        }
        const start: u32 = @intCast(self.edges.items.len);
        try self.edges.appendSlice(self.allocator, prerequisites.items);
        const ordinal: u32 = @intCast(self.proofs.items.len);
        try self.next.append(self.allocator, 0);
        try self.proofs.append(self.allocator, .{ .kind = .predicate, .predicate = value, .context = context, .implementation = .{ .unit = 0, .decl = 0 }, .contract = .{ .unit = 0, .decl = 0 }, .arguments = .{}, .members = .{}, .prerequisites = .{ .start = start, .len = @intCast(prerequisites.items.len) } });
        try self.facts.put(self.allocator, fact_key, ordinal);
        return ordinal;
    }
    fn Context(comptime Host: type) type {
        return struct {
            host: Host,
            store: *Store,
            context: u32,
            fn resolveProjection(raw: *anyopaque, contract: T.NominalIdentity, member: u32, arguments: []const E.Id) E.Error!E.Id {
                const self: *@This() = @ptrCast(@alignCast(raw));
                return self.store.projection(self.host, self.context, contract, member, arguments) catch |err| switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.AssociatedLimit => error.EvidenceLimit,
                    error.UnresolvedType => error.UnresolvedType,
                    else => error.TypeMismatch,
                };
            }
            fn resolver(self: *@This()) E.ProjectionResolver {
                return .{ .context = self, .remaining = &self.host.associated_remaining, .resolve = resolveProjection };
            }
        };
    }
    pub fn projection(self: *Store, host: anytype, context: u32, contract: T.NominalIdentity, member_name: u32, input: []const E.Id) Error!E.Id {
        const point = self.mark();
        errdefer self.rollback(point);
        if (self.active.items.len == 0 and self.active_projections.items.len == 0 and self.active_facts.items.len == 0) {
            self.failure = null;
            self.trace = .{ .context = context, .contract = contract };
        }
        const arguments = try self.allocator.dupe(E.Id, input);
        defer self.allocator.free(arguments);
        try self.step(host);
        if (!self.depthAvailable()) {
            self.failure = .associated_limit;
            return error.AssociatedLimit;
        }
        for (self.active_projections.items) |active| {
            if (active.context == context and std.meta.eql(active.contract, contract) and active.member == member_name and self.sameActiveArguments(active.arguments, arguments)) {
                self.failure = .recursive_associated_type;
                return error.IncompatibleImplementation;
            }
        }
        const saved = try self.saveActive(arguments);
        defer self.active_arguments.shrinkRetainingCapacity(saved.start);
        try self.active_projections.append(self.allocator, .{ .context = context, .contract = contract, .member = member_name, .arguments = saved });
        defer _ = self.active_projections.pop();
        const module = &host.units[owner(host, context) orelse return error.TypeMismatch];
        const definition = for (module.contracts) |declaration| {
            if (std.meta.eql(declaration.identity, contract)) break declaration;
        } else return error.TypeMismatch;
        const descriptor = for (module.contract_members[definition.members.start..][0..definition.members.len]) |member| {
            if (member.name == member_name) break member;
        } else return error.TypeMismatch;
        if (descriptor.kind == .defined_type) {
            var mappings: std.ArrayList(E.Mapping) = .empty;
            defer mappings.deinit(self.allocator);
            var rows: std.ArrayList(E.RowMapping) = .empty;
            defer rows.deinit(self.allocator);
            if (arguments.len != definition.parameters.len) return error.TypeMismatch;
            for (module.types.list(definition.parameters), arguments) |pattern, actual| {
                if (!try host.evidence.matchWithRowsBudget(&module.types, pattern, actual, &mappings, &rows, &host.associated_remaining)) return error.TypeMismatch;
            }
            var state: Context(@TypeOf(host)) = .{ .host = host, .store = self, .context = context };
            return host.evidence.projectSelected(&module.types, descriptor.root, mappings.items, rows.items, state.resolver()) catch |err| switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.UnresolvedType => error.UnresolvedType,
                error.EvidenceLimit => error.AssociatedLimit,
                error.TypeMismatch => error.TypeMismatch,
            };
        }
        var provisional = self.provisional_equations.items.len;
        while (provisional != 0) {
            provisional -= 1;
            const frame = self.provisional_equations.items[provisional];
            if (frame.context != context or !std.meta.eql(frame.declaration.contract, contract) or !self.sameActiveArguments(frame.arguments, arguments)) continue;
            for (module.implementation_members[frame.declaration.members.start..][0..frame.declaration.members.len]) |member| {
                if (member.name != member_name or member.kind != .type_) continue;
                var state: Context(@TypeOf(host)) = .{ .host = host, .store = self, .context = context };
                return host.evidence.projectSelected(&module.types, member.root, frame.mappings, frame.rows, state.resolver());
            }
        }
        const proof = try self.resolve(host, context, contract, arguments);
        for (self.members.items[self.proofs.items[proof].members.start..][0..self.proofs.items[proof].members.len]) |member| if (member.name == member_name) return member.root;
        return error.TypeMismatch;
    }
    pub fn resolve(self: *Store, host: anytype, context: u32, contract: T.NominalIdentity, input: []const E.Id) Error!u32 {
        const point = self.mark();
        errdefer self.rollback(point);
        if (self.active.items.len == 0 and self.active_projections.items.len == 0 and self.active_facts.items.len == 0) {
            self.failure = null;
            self.trace = .{ .context = context, .contract = contract };
        }
        try self.step(host);
        const arguments = try self.allocator.dupe(E.Id, input);
        defer self.allocator.free(arguments);
        for (arguments) |argument| if (argument == 0) return error.UnresolvedType;
        if (!self.depthAvailable()) {
            self.failure = .associated_limit;
            return error.AssociatedLimit;
        }
        const depth = self.active.items.len + self.active_projections.items.len + self.active_facts.items.len;
        self.max_depth = @max(self.max_depth, depth + 1);
        for (self.active.items) |active| {
            if (active.context == context and std.meta.eql(active.contract, contract) and self.sameActiveArguments(active.arguments, arguments)) {
                self.failure = .recursive_evidence;
                return error.RecursiveEvidence;
            }
        }
        for (arguments) |_| try self.step(host);
        const fingerprint = key(context, contract, arguments);
        var known = self.buckets.get(fingerprint) orelse 0;
        while (known != 0) {
            try self.step(host);
            const ordinal = known - 1;
            const proof = self.proofs.items[ordinal];
            if (proof.context == context and std.meta.eql(proof.contract, contract) and self.sameArguments(proof.arguments, arguments)) {
                try host.implementationRead(context, proof.implementation);
                self.trace.candidate(proof.implementation, .selected);
                self.hits += 1;
                return ordinal;
            }
            known = self.next.items[ordinal];
        }
        const saved = try self.saveActive(arguments);
        defer self.active_arguments.shrinkRetainingCapacity(saved.start);
        try self.active.append(self.allocator, .{ .context = context, .contract = contract, .arguments = saved });
        defer _ = self.active.pop();
        const module = &host.units[owner(host, context) orelse return error.TypeMismatch];
        var winner: ?C.Implementation = null;
        var selected_mappings: std.ArrayList(E.Mapping) = .empty;
        defer selected_mappings.deinit(self.allocator);
        var selected_rows: std.ArrayList(E.RowMapping) = .empty;
        defer selected_rows.deinit(self.allocator);
        var order: std.ArrayList(u32) = .empty;
        defer order.deinit(self.allocator);
        for (module.implementations, 0..) |candidate, ordinal| {
            try self.step(host);
            if (!std.meta.eql(candidate.contract, contract) or candidate.head.len != arguments.len) continue;
            if (candidate.private and candidate.identity.unit != context) continue;
            try order.append(self.allocator, @intCast(ordinal));
        }
        const OrderContext = struct {
            host: @TypeOf(host),
            module: *const C.Module,
            exhausted: *bool,
            fn less(context_: @This(), left: u32, right: u32) bool {
                if (context_.host.associated_remaining == 0) {
                    context_.exhausted.* = true;
                    return left < right;
                }
                context_.host.associated_remaining -= 1;
                return canonicalLess(context_.host, context_.module.implementations[left], context_.module.implementations[right]);
            }
        };
        var exhausted = false;
        std.mem.sortUnstable(u32, order.items, OrderContext{ .host = host, .module = module, .exhausted = &exhausted }, OrderContext.less);
        if (exhausted) {
            self.failure = .associated_limit;
            return error.AssociatedLimit;
        }
        for (order.items) |ordinal| {
            const candidate = module.implementations[ordinal];
            try self.step(host);
            self.candidates += 1;
            self.trace.candidate(candidate.identity, .head_mismatch);
            var mappings: std.ArrayList(E.Mapping) = .empty;
            defer mappings.deinit(self.allocator);
            var rows: std.ArrayList(E.RowMapping) = .empty;
            defer rows.deinit(self.allocator);
            var matches = true;
            for (module.types.list(candidate.head), arguments) |pattern, actual| {
                if (!try host.evidence.matchWithRowsBudget(&module.types, pattern, actual, &mappings, &rows, &host.associated_remaining)) {
                    matches = false;
                    break;
                }
            }
            if (!matches) continue;
            self.trace.candidate(candidate.identity, .selected);
            if (winner != null) return error.TypeMismatch;
            winner = candidate;
            try selected_mappings.appendSlice(self.allocator, mappings.items);
            try selected_rows.appendSlice(self.allocator, rows.items);
        }
        const declaration = winner orelse {
            self.failure = .missing_implementation;
            return error.MissingImplementation;
        };
        try host.implementationRead(context, declaration.identity);
        try self.provisional_equations.append(self.allocator, .{ .context = context, .declaration = declaration, .arguments = saved, .mappings = selected_mappings.items, .rows = selected_rows.items });
        defer _ = self.provisional_equations.pop();
        var state: Context(@TypeOf(host)) = .{ .host = host, .store = self, .context = context };
        var edges: std.ArrayList(u32) = .empty;
        defer edges.deinit(self.allocator);
        for (module.obligations[declaration.predicates.start..][0..declaration.predicates.len]) |requirement| {
            try self.step(host);
            self.prerequisite_edges += 1;
            if (requirement.kind == .contract) {
                const product = try host.evidence.projectSelected(&module.types, requirement.ty, selected_mappings.items, selected_rows.items, state.resolver());
                const node = host.evidence.node(product);
                if (node.tag != .product) return error.TypeMismatch;
                const traced = self.trace.step(product, 0, .requires_evidence);
                try edges.append(self.allocator, try self.resolve(host, context, requirement.identity, host.evidence.children(product)));
                self.trace.setOutcome(traced, .selected);
            } else {
                const traced = self.trace.step(0, requirement.name, .requires_evidence);
                var observed: [4]E.Id = @splat(0);
                const optional_fact = closedPredicateFrom(host, context, module, requirement, selected_mappings.items, selected_rows.items, state.resolver(), &observed) catch |err| {
                    if (traced) |ordinal| self.trace.steps[ordinal].ty = observed[0];
                    return self.rejectedPrerequisite(err, declaration.identity, traced, requirement.kind);
                };
                if (traced) |ordinal| self.trace.steps[ordinal].ty = observed[0];
                const fact = optional_fact orelse {
                    self.trace.candidate(declaration.identity, .requires_evidence);
                    self.trace.setOutcome(traced, @import("implementation_predicates.zig").failureOutcome(requirement.kind));
                    self.failure = .incompatible_implementation;
                    return error.IncompatibleImplementation;
                };
                self.trace.setOutcome(traced, .selected);
                if (traced) |ordinal| self.trace.steps[ordinal].ty = fact.operands[0];
                const child = self.proveFact(host, context, fact, state.resolver()) catch |err| return self.rejectedPrerequisite(err, declaration.identity, traced, requirement.kind);
                try edges.append(self.allocator, child);
            }
        }
        var members: std.ArrayList(Member) = .empty;
        defer members.deinit(self.allocator);
        for (module.implementation_members[declaration.members.start..][0..declaration.members.len]) |member| {
            try self.step(host);
            const root = try host.evidence.projectSelected(&module.types, member.root, selected_mappings.items, selected_rows.items, state.resolver());
            _ = self.trace.step(root, member.name, .selected);
            try members.append(self.allocator, .{ .name = member.name, .kind = member.kind, .root = root, .target = .{ .unit = member.target.unit, .binding = member.target.binding } });
        }
        const member_start: u32 = @intCast(self.members.items.len);
        try self.members.appendSlice(self.allocator, members.items);
        const edge_start: u32 = @intCast(self.edges.items.len);
        try self.edges.appendSlice(self.allocator, edges.items);
        const ordinal: u32 = @intCast(self.proofs.items.len);
        try self.next.append(self.allocator, self.buckets.get(fingerprint) orelse 0);
        try self.proofs.append(self.allocator, .{ .context = context, .implementation = declaration.identity, .contract = contract, .arguments = try self.saveArguments(arguments), .members = .{ .start = member_start, .len = @intCast(members.items.len) }, .prerequisites = .{ .start = edge_start, .len = @intCast(edges.items.len) } });
        try self.buckets.put(self.allocator, fingerprint, ordinal + 1);
        return ordinal;
    }
};

/// Closed ordinary facts inside a selected proof. Legacy dispatch keeps its
/// existing target rules, supplied by the host without invoking the target.
pub fn closedPredicate(host: anytype, context: u32, value: C.Obligation, mappings: []const E.Mapping, rows: []const E.RowMapping, resolver: E.ProjectionResolver) E.Error!?Fact {
    const module = &host.units[Store.owner(host, context) orelse return error.TypeMismatch];
    return closedPredicateFrom(host, context, module, value, mappings, rows, resolver, null);
}
fn closedPredicateFrom(host: anytype, context: u32, module: *const C.Module, value: C.Obligation, mappings: []const E.Mapping, rows: []const E.RowMapping, resolver: E.ProjectionResolver, observed: ?*[4]E.Id) E.Error!?Fact {
    if (value.kind == .effect_operation) {
        const signature = module.types.node(value.signature);
        if (signature.tag != .function) return null;
        const pack = try host.evidence.projectSelected(&module.types, value.other, mappings, rows, resolver);
        if (host.evidence.node(pack).tag != .product) return null;
        const label = try host.evidence.effects.internOperation(value.identity, host.evidence.children(pack));
        const own_row = try host.evidence.effects.internRow(&.{label});
        var inferred: std.ArrayList(E.RowMapping) = .empty;
        defer inferred.deinit(host.evidence.allocator);
        try inferred.appendSlice(host.evidence.allocator, rows);
        const row = module.types.row(signature.c);
        if (row.tail == .variable) {
            var known = false;
            for (rows) |mapping| if (mapping.variable == row.tail.variable) {
                known = true;
                break;
            };
            if (!known) try inferred.append(host.evidence.allocator, .{ .variable = row.tail.variable, .evidence = own_row });
        }
        var operands: [4]E.Id = @splat(0);
        for ([_]T.Id{ value.ty, value.other, value.result, value.signature }, &operands) |root, *operand| {
            if (root != 0) operand.* = try host.evidence.projectSelected(&module.types, root, mappings, inferred.items, resolver);
            if (observed) |record| record.* = operands;
        }
        const closed = host.evidence.node(operands[3]);
        if (closed.tag != .function) return null;
        for (host.evidence.effects.view().rowLabels(closed.c)) |known| {
            if (host.associated_remaining == 0) return error.EvidenceLimit;
            host.associated_remaining -= 1;
            if (known == label) return .{ .kind = value.kind, .operator = value.operator, .identity = value.identity, .name = value.name, .operands = operands };
        }
        return null;
    }
    var operands: [4]E.Id = @splat(0);
    for ([_]T.Id{ value.ty, value.other, value.result, value.signature }, &operands) |root, *result| {
        if (root != 0) result.* = host.evidence.projectSelected(&module.types, root, mappings, rows, resolver) catch |err| switch (err) {
            error.UnresolvedType => {
                const node = module.types.node(root);
                if (root != value.signature or node.tag != .function or node.a != T.unit or node.b != T.unit or module.types.rowLabels(node.c).len != 0 or module.types.row(node.c).tail != .variable) return err;
                result.* = 0;
                continue;
            },
            else => return err,
        };
        if (observed) |record| record.* = operands;
    }
    var target: C.BindingRef = .{ .unit = 0, .binding = 0 };
    var accepted = false;
    switch (value.kind) {
        .resolver_shape => {
            const resolver_type = host.evidence.node(operands[0]);
            const result = host.evidence.node(operands[2]);
            if (resolver_type.tag == .resolver and result.tag == .nominal) {
                const token = host.evidence.node(resolver_type.a);
                if (token.tag == .type_constructor and token.a == result.a and token.b == result.b) {
                    for (module.nominals) |nominal| {
                        if (host.associated_remaining == 0) return error.EvidenceLimit;
                        host.associated_remaining -= 1;
                        if (nominal.identity.unit == token.a and nominal.identity.decl == token.b) accepted = nominal.parameters.len == host.evidence.children(operands[2]).len;
                    }
                }
            }
        },
        .monad_factory => accepted = host.evidence.node(operands[0]).tag == .type_constructor,
        .effect_handler => {
            const token = host.evidence.node(operands[0]);
            const extended = host.evidence.node(operands[3]);
            const residual = host.evidence.node(operands[1]);
            if (token.tag == .nominal and extended.tag == .function and residual.tag == .function) {
                const label = try host.evidence.effects.internOperation(.{ .unit = token.a, .decl = token.b }, host.evidence.children(operands[0]));
                var labels: std.ArrayList(E.Effects.Label) = .empty;
                defer labels.deinit(host.evidence.allocator);
                try labels.append(host.evidence.allocator, label);
                for (host.evidence.effects.view().rowLabels(residual.c)) |known| {
                    if (host.associated_remaining == 0) return error.EvidenceLimit;
                    host.associated_remaining -= 1;
                    try labels.append(host.evidence.allocator, known);
                }
                accepted = try host.evidence.effects.internRow(labels.items) == extended.c;
            }
        },
        .collection => {
            const collection = host.evidence.node(operands[0]);
            accepted = (collection.tag == .array or collection.tag == .list) and collection.a == operands[2];
        },
        .type_head => {
            var head = operands[0];
            var depth: usize = 0;
            while (host.evidence.node(head).tag == .function) {
                if (depth >= 256 or host.associated_remaining == 0) return error.EvidenceLimit;
                host.associated_remaining -= 1;
                head = host.evidence.node(head).b;
                depth += 1;
            }
            accepted = head == operands[2];
        },
        .record_merge => {
            if (host.evidence.node(operands[0]).tag == .never or host.evidence.node(operands[1]).tag == .never) {
                accepted = host.evidence.node(operands[2]).tag == .never;
            } else if (host.evidence.node(operands[0]).tag == .record and host.evidence.node(operands[1]).tag == .record) {
                var fields: std.ArrayList(E.Id) = .empty;
                defer fields.deinit(host.evidence.allocator);
                const left = host.evidence.children(operands[0]);
                const right = host.evidence.children(operands[1]);
                var first: usize = 0;
                var second: usize = 0;
                while (first < left.len or second < right.len) {
                    if (host.associated_remaining == 0) return error.EvidenceLimit;
                    host.associated_remaining -= 1;
                    if (second == right.len or (first < left.len and left[first] < right[second])) {
                        try fields.appendSlice(host.evidence.allocator, left[first..][0..2]);
                        first += 2;
                    } else {
                        if (first < left.len and left[first] == right[second]) first += 2;
                        try fields.appendSlice(host.evidence.allocator, right[second..][0..2]);
                        second += 2;
                    }
                }
                accepted = operands[2] == try host.evidence.intern(.record, 0, 0, fields.items);
            }
        },
        .update => {
            if (host.evidence.node(operands[0]).tag == .record) {
                const fields = try host.evidence.allocator.dupe(E.Id, host.evidence.children(operands[0]));
                defer host.evidence.allocator.free(fields);
                var found = false;
                var index: usize = 0;
                while (index < fields.len) : (index += 2) {
                    if (host.associated_remaining == 0) return error.EvidenceLimit;
                    host.associated_remaining -= 1;
                    if (fields[index] == value.name) {
                        fields[index + 1] = operands[1];
                        found = true;
                    }
                }
                accepted = found and operands[2] == try host.evidence.intern(.record, 0, 0, fields);
                if (operands[3] == 0) operands[3] = try host.evidence.intern(.function, T.unit, T.unit, &.{});
            } else if (host.evidence.node(operands[0]).tag == .nominal) {
                accepted = try nominalFields(host, context, module, value, operands, resolver) == .matched;
                if (operands[3] == 0) operands[3] = try host.evidence.intern(.function, T.unit, T.unit, &.{});
            }
        },
        .field, .writable_field => {
            var structural: FieldCheck = .absent;
            if (host.evidence.node(operands[0]).tag == .nominal) structural = try nominalFields(host, context, module, value, operands, resolver);
            if (structural == .incompatible) return null;
            if (structural == .matched) {
                accepted = true;
            } else {
                const selected = try host.implementationLegacyPredicate(context, value, operands, resolver) orelse return null;
                target = selected.target;
                operands[3] = selected.carrier;
                accepted = true;
            }
        },
        .callee_use => {
            const binding = for (module.bindings, 0..) |candidate, ordinal| {
                if ((value.identity.unit == module.unit or value.identity.unit == 0) and value.identity.decl == ordinal) break candidate;
                if (candidate.kind == .external and candidate.target.unit == value.identity.unit and candidate.target.binding == value.identity.decl) break candidate;
            } else return null;
            target = binding.target;
            if (target.unit == 0) target.unit = module.unit;
            accepted = target.binding != 0;
        },
        .type_eq => accepted = operands[0] == operands[2],
        .type_rep, .effect_rep => accepted = true,
        .arithmetic, .ordered => {
            const tag = host.evidence.node(operands[0]).tag;
            accepted = tag == .u32 or tag == .f32;
        },
        .integer => accepted = host.evidence.node(operands[0]).tag == .u32,
        .equality => {
            const tag = host.evidence.node(operands[0]).tag;
            accepted = tag == .u32 or tag == .f32 or tag == .boolean;
        },
        else => {
            const selected = try host.implementationLegacyPredicate(context, value, operands, resolver) orelse return null;
            target = selected.target;
            operands[3] = selected.carrier;
            accepted = true;
        },
    }
    if (!accepted) return null;
    return .{ .kind = value.kind, .operator = value.operator, .identity = value.identity, .name = value.name, .operands = operands, .target = target };
}
const FieldCheck = enum { absent, matched, incompatible };
fn nominalFields(host: anytype, context: u32, module: *const C.Module, value: C.Obligation, operands: [4]E.Id, resolver: E.ProjectionResolver) E.Error!FieldCheck {
    const input = host.evidence.node(operands[0]);
    const identity: T.NominalIdentity = .{ .unit = input.a, .decl = input.b };
    const nominal = for (module.nominals) |candidate| {
        if (std.meta.eql(candidate.identity, identity)) break candidate;
    } else return .absent;
    if (nominal.is_opaque and nominal.identity.unit != context) return .absent;
    if (nominal.constructors.len == 0) return .absent;
    var getter = false;
    if (value.kind == .field) for (module.associated) |method| {
        if (std.meta.eql(method.identity, identity) and method.member == value.name) getter = true;
    };
    var compatible = true;
    for (module.extra[nominal.constructors.start..][0..nominal.constructors.len]) |constructor_index| {
        if (host.associated_remaining == 0) return error.EvidenceLimit;
        host.associated_remaining -= 1;
        const constructor = module.constructors[constructor_index];
        const signature = module.types.node(constructor.scheme.root);
        if (signature.tag != .function) return .absent;
        var input_mappings: std.ArrayList(E.Mapping) = .empty;
        defer input_mappings.deinit(host.evidence.allocator);
        var input_rows: std.ArrayList(E.RowMapping) = .empty;
        defer input_rows.deinit(host.evidence.allocator);
        if (!try host.evidence.matchWithRowsBudget(&module.types, signature.b, operands[0], &input_mappings, &input_rows, &host.associated_remaining)) return .absent;
        if (constructor.payload == 0) return .absent;
        const payload = try host.evidence.projectSelected(&module.types, constructor.payload, input_mappings.items, input_rows.items, resolver);
        if (host.evidence.node(payload).tag != .record) return .absent;
        var expected_payload = payload;
        if (value.kind == .update) {
            var output_mappings: std.ArrayList(E.Mapping) = .empty;
            defer output_mappings.deinit(host.evidence.allocator);
            var output_rows: std.ArrayList(E.RowMapping) = .empty;
            defer output_rows.deinit(host.evidence.allocator);
            if (!try host.evidence.matchWithRowsBudget(&module.types, signature.b, operands[2], &output_mappings, &output_rows, &host.associated_remaining)) return .absent;
            expected_payload = try host.evidence.projectSelected(&module.types, constructor.payload, output_mappings.items, output_rows.items, resolver);
            if (host.evidence.node(expected_payload).tag != .record) return .absent;
        }
        const fields = host.evidence.children(payload);
        const expected = host.evidence.children(expected_payload);
        if (fields.len != expected.len) return .absent;
        var found = false;
        var index: usize = 0;
        while (index < fields.len) : (index += 2) {
            if (host.associated_remaining == 0) return error.EvidenceLimit;
            host.associated_remaining -= 1;
            if (fields[index] != expected[index]) return .absent;
            if (fields[index] == value.name) {
                found = true;
                if (value.kind == .update) {
                    if (expected[index + 1] != operands[1]) compatible = false;
                } else if (fields[index + 1] != operands[2]) compatible = false;
            } else if (fields[index + 1] != expected[index + 1]) compatible = false;
        }
        if (!found) return .absent;
    }
    if (!compatible or getter) return .incompatible;
    return .matched;
}
/// Written legacy invocation predicates retain a row carrier, not the method's
/// full signature. Build its ordinary application type from its operands.
pub fn invocation(host: anytype, value: C.Obligation, operands: [4]E.Id) E.Error!E.Id {
    var row: E.Effects.Id = 0;
    if (operands[3] != 0) {
        const carrier = host.evidence.node(operands[3]);
        if (carrier.tag != .function) return error.TypeMismatch;
        row = carrier.c;
    }
    if (value.kind == .field or value.kind == .writable_field) return host.evidence.internWithEffects(.function, operands[0], operands[2], row, &.{});
    const result = try host.evidence.internWithEffects(.function, operands[1], operands[2], row, &.{});
    return host.evidence.internWithEffects(.function, operands[0], result, row, &.{});
}

pub fn predicate(host: anytype, context: u32, value: C.Obligation, mappings: []const E.Mapping, rows: []const E.RowMapping, resolver: E.ProjectionResolver) E.Error!bool {
    return try closedPredicate(host, context, value, mappings, rows, resolver) != null;
}
