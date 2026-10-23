//! One backend run's static data owner. Cache keys borrow the live evaluator
//! and representation IDs; no pointer into either growing table is retained.
const std = @import("std");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const wasm = @import("wasm.zig");
const core_eval = @import("../eval/core_eval.zig");
const type_evidence = @import("../eval/type_evidence.zig");
const layout = @import("layout.zig");
const heap = @import("../runtime/runtime_layout.zig");
const code_artifacts = @import("../reuse/code_artifacts.zig");
const Allocator = std.mem.Allocator;
const Scalar = wasm.Scalar;
const Key = code_artifacts.Key;
const Mapping = layout.Mapping;
const RowMapping = layout.RowMapping;
const ClosureKey = code_artifacts.ClosureKey;
const CallableKey = code_artifacts.CallableKey;
const ConstructorKey = code_artifacts.ConstructorKey;
const PrimitiveKey = code_artifacts.PrimitiveKey;
const OperationKey = code_artifacts.OperationKey;
const Error = Allocator.Error || error{ Declined, ModuleTooLarge, InvalidFunctionReference, InvalidGlobalReference };
const SerializedKey = struct { value: core_eval.ValueId, ty: layout.Id, suspension: bool = false };
pub const State = struct {
    fn taskCallbackRows(source: *const core.Module, ty: types.Id, depth: usize) bool {
        if (depth >= 128) return false;
        if (@import("../check/task_types.zig").scopeCallback(&source.types, ty) != null) return true;
        const node = source.types.node(ty);
        return switch (node.tag) {
            .function => taskCallbackRows(source, node.a, depth + 1) or taskCallbackRows(source, node.b, depth + 1),
            .usage, .forall => taskCallbackRows(source, node.a, depth + 1),
            else => false,
        };
    }
    cache: std.AutoHashMapUnmanaged(SerializedKey, u32) = .empty,
    closures: std.ArrayList(u32) = .empty,
    pub fn deinit(self: *State, a: Allocator) void {
        self.cache.deinit(a);
        self.closures.deinit(a);
    }
    pub fn dataValueReference(_: *State, g: anytype, address: u32, value: core_eval.ValueId, bits: u32) Error!void {
        if (bits == 0) return;
        var child = value;
        for (0..256) |_| {
            if (g.evaluator.valueScalar(child) != null) return;
            const info = g.evaluator.valueInfo(child);
            if (info.kind != .nominal or info.len != 1) break;
            const owner: u32 = @intCast(info.nominal >> 32);
            const declaration: u32 = @truncate(info.nominal);
            var is_opaque = false;
            for (g.unit(owner).nominals) |nominal| if (nominal.identity.decl == declaration and nominal.is_opaque) {
                is_opaque = true;
                break;
            };
            if (!is_opaque) break;
            child = g.evaluator.valueChildren(child)[0];
        }
        try g.module.dataReference(address, .{ .role = .static_address, .value = bits });
    }

    pub fn closureData(_: *State, g: anytype, function_id: u32, environment: u32) Error!u32 {
        const address = try g.module.dataObject(heap.Closure{ .function = function_id, .environment = environment });
        try g.module.dataReference(address, .{ .role = .callable_function, .value = function_id });
        try g.module.dataReference(address + heap.offset(heap.Closure, "environment"), .{ .role = .static_address, .value = environment });
        return address;
    }

    pub fn serializeCarrier(self: *State, g: anytype, value: core_eval.ValueId, from: layout.Id, to: layout.Id, owner: u32, depth: usize) Error!u32 {
        if (depth >= 128) return g.decline(owner, .{ .start = 0, .end = 0 }, .complexity);
        if (from == to) return self.serialize(g, value, to, depth + 1);
        const input = g.representations.store.node(from);
        const output = g.representations.store.node(to);
        if (output.tag == .opened or output.tag == .associated) {
            const payload = try self.serialize(g, value, from, depth + 1);
            const cell = try g.module.dataWords(&.{ 0, payload });
            if (g.layoutRole(from) == .reference) try self.dataValueReference(g, cell + 4, value, payload);
            return cell;
        }
        if (input.tag != output.tag) return g.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
        if (input.tag == .function) {
            var emitter: @TypeOf(g.*).Emission = .{ .generator = g, .unit_id = owner, .function_id = 0, .provider_local = 0, .mappings = &.{} };
            defer emitter.deinit();
            try emitter.carrierRows(input.c, output.c, 0);
            const adapter = try emitter.carrierFunction(from, to, depth + 1);
            return self.closureData(g, adapter, try self.serialize(g, value, from, depth + 1));
        }
        if (input.tag == .nominal) {
            const info = g.evaluator.valueInfo(value);
            if (input.a != output.a or input.b != output.b or info.kind != .nominal or info.len > 1) return g.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
            if (g.representations.store.scalar(to) != null) return info.bits;
            var payload: u32 = 0;
            var payload_reference = false;
            if (info.len != 0) {
                const actual = try g.nominalPayload(info.nominal, info.bits, from);
                const expected = try g.nominalPayload(info.nominal, info.bits, to);
                payload_reference = g.layoutRole(expected) == .reference;
                payload = try self.serializeCarrier(g, g.evaluator.valueChildren(value)[0], actual, expected, owner, depth + 1);
            }
            const producer: u32 = @intCast(info.nominal >> 32);
            const declaration: u32 = @truncate(info.nominal);
            for (g.unit(producer).nominals) |nominal| if (nominal.identity.decl == declaration and nominal.is_opaque) return payload;
            const address = try g.module.dataWords(&.{ info.bits, payload });
            if (payload_reference) try g.module.dataReference(address + 4, .{ .role = .static_address, .value = payload });
            return address;
        }
        if (input.tag == .array or input.tag == .list) {
            if (try g.rowWords(output.a) != 0) return g.decline(owner, .{ .start = 0, .end = 0 }, .unsupported);
            var words: std.ArrayList(u32) = .empty;
            defer words.deinit(g.allocator);
            const count = g.evaluator.valueChildren(value).len;
            if (input.tag == .array) try words.append(g.allocator, @intCast(count));
            for (0..count) |index| {
                const child = g.evaluator.valueChildren(value)[index];
                try words.append(g.allocator, try self.serializeCarrier(g, child, input.a, output.a, owner, depth + 1));
            }
            if (input.tag == .array) {
                const address = try g.module.dataWords(words.items);
                if (g.layoutRole(output.a) == .reference) for (words.items[1..], 1..) |word, index| try g.module.dataReference(address + @as(u32, @intCast(index * 4)), .{ .role = .static_address, .value = word });
                return address;
            }
            const lists = @import("../runtime/list_runtime.zig");
            var leaves: std.ArrayList(u32) = .empty;
            defer leaves.deinit(g.allocator);
            var offset: usize = 0;
            while (offset < words.items.len) {
                const end = @min(words.items.len, offset +| lists.leafLimit(1));
                const leaf = try lists.staticChunk(&g.module, words.items[offset..end]);
                if (g.layoutRole(output.a) == .reference) for (words.items[offset..end], 0..) |word, index| try g.module.dataReference(leaf + lists.header + @as(u32, @intCast(index * 4)), .{ .role = .static_address, .value = word });
                try leaves.append(g.allocator, leaf);
                offset = end;
            }
            if (g.layoutRole(output.a) == .scalar) return lists.staticScalarDescriptor(&g.module, @intCast(count), leaves.items, 1);
            return lists.staticDescriptor(&g.module, @intCast(count), leaves.items);
        }
        if (input.tag == .product or input.tag == .record) {
            const field_count = g.representations.store.children(from).len;
            const record = input.tag == .record;
            var stride: usize = 1;
            if (record) stride = 2;
            if (field_count != g.representations.store.children(to).len or g.evaluator.valueChildren(value).len != field_count / stride) return g.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
            var words: std.ArrayList(u32) = .empty;
            defer words.deinit(g.allocator);
            for (0..field_count / stride) |index| {
                var slot = index;
                if (record) {
                    const name = g.representations.store.children(from)[index * 2];
                    if (name != g.representations.store.children(to)[index * 2]) return g.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
                    slot = for (g.evaluator.recordFieldNames(value), 0..) |field, at| {
                        if (field == name) break at;
                    } else return g.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
                }
                const child = g.evaluator.valueChildren(value)[slot];
                const position = index * stride + @intFromBool(record);
                const actual = g.representations.store.children(from)[position];
                const expected = g.representations.store.children(to)[position];
                try words.append(g.allocator, try self.serializeCarrier(g, child, actual, expected, owner, depth + 1));
            }
            const address = try g.module.dataWords(words.items);
            for (words.items, 0..) |word, index| if (g.layoutRole(g.representations.store.children(to)[index * stride + @intFromBool(record)]) == .reference) try g.module.dataReference(address + @as(u32, @intCast(index * 4)), .{ .role = .static_address, .value = word });
            return address;
        }
        return g.decline(owner, .{ .start = 0, .end = 0 }, .unsupported);
    }

    pub fn serializePackage(self: *State, g: anytype, value: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        const info = g.evaluator.valueInfo(value);
        const package = g.representations.store.node(ty);
        if (package.tag != .existential or info.len == 0 or info.bits == 0 or info.nominal > std.math.maxInt(u32)) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        var selected: ?struct { unit: u32, quantifier: types.Id } = null;
        var remaining: usize = 65_536;
        outer: for (g.units) |*source| for (source.types.nodes, 0..) |node, ordinal| {
            if (remaining == 0) return g.decline(source.unit, .{ .start = 0, .end = 0 }, .complexity);
            remaining -= 1;
            if (node.tag != .existential) continue;
            const semantic = g.evaluator.storage.evidence.projectWithRows(&source.types, @intCast(ordinal), &.{}, &.{}) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            if (semantic == info.bits) {
                selected = .{ .unit = source.unit, .quantifier = @intCast(ordinal) };
                break :outer;
            }
        };
        const recipe = selected orelse return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        const source = g.unit(recipe.unit);
        const quantifier = source.types.node(recipe.quantifier);
        const dictionary: u32 = @intCast(info.nominal);
        const witnesses = try g.allocator.dupe(type_evidence.Id, g.evaluator.storage.evidence.children(dictionary));
        defer g.allocator.free(witnesses);
        if (witnesses.len != quantifier.c) return g.decline(recipe.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        for (source.types.list(.{ .start = quantifier.b, .len = quantifier.c }), witnesses) |binder, witness| {
            const actual = g.representations.fromEvidence(g.evaluator.evidenceStore(), witness) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.decline(recipe.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
            try mappings.append(g.allocator, .{ .variable = binder, .layout = actual });
        }
        const payload_type = g.representations.store.fromTypeWithRows(source, quantifier.a, mappings.items, &.{}, false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.decline(recipe.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(g.allocator);
        try words.append(g.allocator, try self.serializeCarrier(g, g.evaluator.valueChildren(value)[0], payload_type, package.a, recipe.unit, depth + 1));
        var abstract: @TypeOf(g.*).Emission = .{ .generator = g, .unit_id = recipe.unit, .function_id = 0, .provider_local = 0, .mappings = &.{} };
        defer abstract.deinit();
        var concrete: @TypeOf(g.*).Emission = .{ .generator = g, .unit_id = recipe.unit, .function_id = 0, .provider_local = 0, .mappings = mappings.items };
        defer concrete.deinit();
        const goals = try g.allocator.dupe(types.Obligation, source.types.quantifierGoals(recipe.quantifier));
        defer g.allocator.free(goals);
        for (goals, 0..) |goal, goal_ordinal| {
            const contract = for (source.contracts) |candidate| {
                if (std.meta.eql(candidate.identity, goal.identity)) break candidate;
            } else return g.decline(recipe.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
            for (source.contract_members[contract.members.start..][0..contract.members.len], 0..) |member, ordinal| {
                if (member.kind != .value) continue;
                const index = words.items.len;
                if (index >= info.len) return g.decline(recipe.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
                const implementation = g.evaluator.valueChildren(value)[index];
                const member_signature = g.evaluator.valueEvidence(implementation);
                var from: layout.Id = undefined;
                if (member_signature != 0) {
                    from = g.representations.fromEvidence(g.evaluator.evidenceStore(), member_signature) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.decline(recipe.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
                } else from = try concrete.dictionaryMemberLayout(0, recipe.quantifier, @intCast(goal_ordinal), ordinal);
                const to = try abstract.dictionaryMemberLayout(0, recipe.quantifier, @intCast(goal_ordinal), ordinal);
                try words.append(g.allocator, try self.serializeCarrier(g, implementation, from, to, recipe.unit, depth + 1));
            }
        }
        if (words.items.len != info.len) return g.decline(recipe.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
        const address = try g.module.dataWords(words.items);
        if (g.layoutRole(package.a) == .reference) try g.module.dataReference(address, .{ .role = .static_address, .value = words.items[0] });
        for (words.items[1..], 1..) |word, index| try g.module.dataReference(address + @as(u32, @intCast(index * 4)), .{ .role = .static_address, .value = word });
        return address;
    }

    pub fn serialize(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        if (depth >= 256) return g.decline(1, .{ .start = 0, .end = 0 }, .complexity);
        const shape = g.representations.store.node(ty);
        if (shape.tag == .owning) {
            if (g.artifacts) |context| context.materializeStaticValue();
            const payload = try self.serialize(g, id, shape.a, depth + 1);
            const address = try g.module.dataObject(heap.Owning{ .payload = payload, .token = 0 });
            if (g.layoutRole(shape.a) == .reference) try self.dataValueReference(g, address, id, payload);
            return address;
        }
        if (g.evaluator.valueScalar(id)) |value| return value.bits;
        const info = g.evaluator.valueInfo(id);
        if (info.kind == .nominal) {
            const owner: u32 = @intCast(info.nominal >> 32);
            const declaration: u32 = @truncate(info.nominal);
            for (g.unit(owner).nominals) |nominal| {
                if (!nominal.is_opaque or nominal.identity.decl != declaration) continue;
                if (info.len == 0) return 0;
                if (info.len != 1) return g.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
                return self.serialize(g, g.evaluator.valueChildren(id)[0], try g.nominalPayload(info.nominal, info.bits, ty), depth + 1);
            }
        }
        try g.planning.startup_facts.event(g.allocator, .{ .kind = .retained_value, .caller = g.planning.startup_facts.active, .target = id, .auxiliary = @backingInt(info.kind) });
        if (info.kind == .suspension) if (g.evaluator.suspensionCached(id)) |cached| try g.planning.startup_facts.event(g.allocator, .{ .kind = .cached_demand, .caller = g.planning.startup_facts.active, .target = id, .auxiliary = cached });
        if (info.kind == .type_constructor or info.kind == .resolver) return 0;
        const key: SerializedKey = .{ .value = if (info.kind == .suspension) @intCast(info.nominal) else id, .ty = ty, .suspension = info.kind == .suspension };
        if (self.cache.get(key)) |address| {
            try g.module.demandResource(.static_data, address, true);
            return address;
        }
        if (g.artifacts) |context| context.materializeStaticValue();
        if (info.kind == .package) {
            const address = try self.serializePackage(g, id, ty, depth);
            try self.cache.put(g.allocator, key, address);
            return address;
        }
        if (info.kind == .computation or info.kind == .request_decision) return self.serializeDecision(g, id, ty, depth, info, key);
        if (info.kind == .provider or info.kind == .state_provider) return self.serializeProvider(g, id, ty, depth, info, key);
        if (info.kind == .suspension) return self.serializeDemand(g, id, ty, depth, info, key);
        if (info.kind == .closure) return self.serializeClosureValue(g, id, ty, depth, info, key);
        if (info.kind == .cursor) {
            if (info.len != 1 or g.representations.store.node(ty).tag != .cursor) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const source = g.evaluator.valueChildren(id)[0];
            const pointer = try self.serialize(g, source, g.representations.store.node(ty).a, depth + 1);
            const address = try g.module.dataObject(heap.Cursor{ .collection = pointer, .index = info.bits });
            try self.dataValueReference(g, address, source, pointer);
            try self.cache.put(g.allocator, key, address);
            return address;
        }
        if (info.kind == .array or info.kind == .list) {
            const row_words = try g.collectionRowWords(ty);
            if (row_words != 0) return self.serializePackedCollection(g, id, ty, depth, info, key, row_words);
        }
        return self.serializeAggregate(g, id, ty, depth, info, key);
    }
    fn serializeDecision(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize, info: core_eval.ValueInfo, key: SerializedKey) Error!u32 {
        const representation = g.representations.store.node(ty);
        if (representation.tag != .nominal or representation.a != std.math.maxInt(u32)) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        const arguments = g.representations.store.children(ty);
        const children = g.evaluator.valueChildren(id);
        if (info.kind == .computation) {
            if (representation.b != 5 or arguments.len != 1 or children.len != 1) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const action_type = arguments[0];
            const action = children[0];
            const address = try self.serialize(g, action, action_type, depth + 1);
            try self.cache.put(g.allocator, key, address);
            return address;
        }
        if (representation.b != 6 or arguments.len != 3 or children.len != 2 or info.bits > @backingInt(core.RequestDecisionKind.break_)) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        const kind: core.RequestDecisionKind = @fromBackingInt(@intCast(info.bits));
        const payload_type = if (kind == .reply) arguments[0] else if (kind == .cancel) arguments[2] else 1;
        const state_type = arguments[1];
        const payload = children[0];
        const state = children[1];
        const decision: heap.Decision = .{ .kind = info.bits, .payload = try self.serialize(g, payload, payload_type, depth + 1), .state = try self.serialize(g, state, state_type, depth + 1) };
        const address = try g.module.dataObject(decision);
        try self.dataValueReference(g, address + heap.offset(heap.Decision, "payload"), payload, decision.payload);
        try self.dataValueReference(g, address + heap.offset(heap.Decision, "state"), state, decision.state);
        try self.cache.put(g.allocator, key, address);
        return address;
    }
    fn serializeProvider(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize, info: core_eval.ValueInfo, key: SerializedKey) Error!u32 {
        const provider_type = g.representations.store.node(ty);
        if (info.len != 1) return g.decline(1, .{ .start = 0, .end = 0 }, .constant_expression);
        const child = g.evaluator.valueChildren(id)[0];
        const address = if (info.kind == .provider) ordinary: {
            if (provider_type.tag != .provider) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const actual = g.evaluator.valueEvidence(child);
            if (actual == 0) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const implementation_type = g.representations.fromEvidence(g.evaluator.evidenceStore(), actual) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const operation = try g.runtimeOperation(info.bits, 1, .{ .start = 0, .end = 0 });
            const implementation = try self.serialize(g, child, implementation_type, depth + 1);
            const address = try g.module.dataObject(heap.Provider{ .operation = 0, .implementation = implementation });
            try self.dataValueReference(g, address + heap.offset(heap.Provider, "implementation"), child, implementation);
            try g.runtimeDataWord(address + heap.offset(heap.Provider, "operation"), operation);
            break :ordinary address;
        } else state: {
            if (provider_type.tag != .state_provider or info.nominal > std.math.maxInt(u32)) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const read = try g.runtimeOperation(info.bits, 1, .{ .start = 0, .end = 0 });
            const write = try g.runtimeOperation(@intCast(info.nominal), 1, .{ .start = 0, .end = 0 });
            const state_value = try self.serialize(g, child, provider_type.c, depth + 1);
            const address = try g.module.dataObject(heap.StateProvider{ .read = 0, .write = 0, .initial = state_value });
            try self.dataValueReference(g, address + heap.offset(heap.StateProvider, "initial"), child, state_value);
            try g.runtimeDataWord(address + heap.offset(heap.StateProvider, "read"), read);
            try g.runtimeDataWord(address + heap.offset(heap.StateProvider, "write"), write);
            break :state address;
        };
        try self.cache.put(g.allocator, key, address);
        return address;
    }
    fn serializeDemand(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize, _: core_eval.ValueInfo, key: SerializedKey) Error!u32 {
        var selected = ty;
        const expected = g.representations.toEvidence(g.evaluator.evidenceStore(), ty) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnresolvedType => inferred: {
                var budget: usize = 100_000;
                if (!g.retainedLayoutConcrete(ty, true, 0, &budget)) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                const inferred = g.evaluator.inferSuspension(id) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
                const actual = g.representations.fromEvidence(g.evaluator.evidenceStore(), g.evaluator.valueEvidence(inferred)) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                selected = try g.completeRetainedRows(ty, actual, 0);
                break :inferred g.representations.toEvidence(g.evaluator.evidenceStore(), selected) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            },
            else => return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type),
        };
        const demanded = g.representations.store.node(selected);
        if (demanded.tag != .demand) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        const specialized = g.evaluator.specializeSuspension(id, expected) catch |err| switch (err) {
            error.RequestUnwind => return g.evaluationFailure(),
            error.Declined => return g.evaluationFailure(),
            error.OutOfMemory => return error.OutOfMemory,
        };
        const function_type = try g.internLayoutWithEffects(.function, 1, demanded.a, demanded.c, &.{});
        const closure_address = try self.serializeClosure(g, specialized, function_type, depth);
        const function_id = std.mem.readInt(u32, g.module.data.items[closure_address..][0..4], .little);
        const environment = std.mem.readInt(u32, g.module.data.items[closure_address + heap.offset(heap.Closure, "environment") ..][0..4], .little);
        const cached = g.evaluator.suspensionCached(id);
        const cached_word = if (cached) |value| try self.serialize(g, value, demanded.a, depth + 1) else 0;
        const address = try g.module.dataObject(heap.Demand{ .function = function_id, .environment = environment, .status = if (cached != null) .ready else .pending, .cached = cached_word });
        try g.module.staticField(address + heap.offset(heap.Demand, "status"), .scalar);
        try g.module.staticField(address + heap.offset(heap.Demand, "cached"), g.layoutRole(demanded.a));
        try g.module.dataReference(address, .{ .role = .demand_function, .value = function_id });
        try g.module.dataReference(address + 4, .{ .role = .static_address, .value = environment });
        if (cached) |value| try self.dataValueReference(g, address + heap.offset(heap.Demand, "cached"), value, cached_word);
        try self.cache.put(g.allocator, key, address);
        return address;
    }
    fn serializeClosureValue(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize, _: core_eval.ValueInfo, key: SerializedKey) Error!u32 {
        // A quantified field retains its checked parametric implementation;
        // it has no single monomorphic evaluator invocation to specialize.
        if (g.representations.store.node(ty).tag == .universal) return self.serializeClosure(g, id, ty, depth);
        const arrow = g.representations.store.node(ty);
        if (arrow.tag == .function and g.representations.store.node(arrow.a).tag == .universal) return self.serializeClosure(g, id, ty, depth);
        var selected = ty;
        // A constant sum/array may contain callbacks whose parameter is
        // unobserved by this consumer. Infer that callback independently;
        // only a concrete source proof can fill its erased interface.
        // Selected types and rows still undergo ordinary specialization.
        const expected = g.representations.toEvidence(g.evaluator.evidenceStore(), ty) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnresolvedType => inferred: {
                const inferred = g.evaluator.inferClosure(id) catch |failure| {
                    if (failure == error.OutOfMemory) return error.OutOfMemory;
                    // A still-generic alias has no concrete representation.
                    // Preserve that boundary's diagnostic when the optional
                    // independent proof cannot fill its erased interface.
                    if (g.evaluator.diagnostic) |diagnostic| if (diagnostic.code == .unsupported) {
                        var budget: usize = 100_000;
                        if (!g.retainedLayoutConcrete(ty, true, 0, &budget)) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                    };
                    return g.evaluationFailure();
                };
                const actual = g.representations.fromEvidence(g.evaluator.evidenceStore(), g.evaluator.valueEvidence(inferred)) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                selected = try g.completeRetainedRows(ty, actual, 0);
                break :inferred g.representations.toEvidence(g.evaluator.evidenceStore(), selected) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            },
            else => return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type),
        };
        const specialized = g.evaluator.specializeClosure(id, expected) catch |err| switch (err) {
            error.RequestUnwind => return g.evaluationFailure(),
            error.Declined => return g.evaluationFailure(),
            error.OutOfMemory => return error.OutOfMemory,
        };
        const address = try self.serializeClosure(g, specialized, selected, depth);
        try self.cache.put(g.allocator, key, address);
        return address;
    }
    fn numericChild(g: anytype, value: core_eval.ValueId, ty: layout.Id, offset: u32) Error!core_eval.ValueId {
        const node = g.representations.store.node(ty);
        const values = g.evaluator.valueChildren(value);
        if (node.tag == .nominal) {
            if (offset != 4 or values.len != 1) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            return values[0];
        }
        const index = offset / 4;
        if (node.tag == .record) {
            const fields = g.representations.store.children(ty);
            if (index >= fields.len / 2) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const name = fields[index * 2];
            for (g.evaluator.recordFieldNames(value), 0..) |field, slot| {
                if (field == name and slot < values.len) return values[slot];
            }
            return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        }
        if (node.tag != .product or index >= values.len) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        return values[index];
    }
    fn serializeNumericRow(self: *State, g: anytype, row: core_eval.ValueId, plan: @import("numeric_rows.zig").Plan, depth: usize, words: *std.ArrayList(u32)) Error!void {
        var values: [32]core_eval.ValueId = undefined;
        values[0] = row;
        for (plan.storage[1..plan.storage_count], 1..) |storage, index| {
            const owner = storage.parent.?;
            values[index] = try numericChild(g, values[owner], plan.storage[owner].layout, storage.offset);
        }
        for (plan.leaves[0..plan.leaf_count]) |leaf| {
            const storage = plan.storage[leaf.owner];
            const value = try numericChild(g, values[leaf.owner], storage.layout, leaf.offset);
            const node = g.representations.store.node(storage.layout);
            const fields = g.representations.store.children(storage.layout);
            const child = if (node.tag == .nominal)
                try g.nominalPayload((@as(u64, node.a) << 32) | node.b, storage.tag.?, storage.layout)
            else
                fields[if (node.tag == .record) leaf.offset / 2 + 1 else leaf.offset / 4];
            try words.append(g.allocator, try self.serialize(g, value, child, depth + 1));
        }
    }
    fn serializePackedCollection(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize, info: core_eval.ValueInfo, key: SerializedKey, row_words: u32) Error!u32 {
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(g.allocator);
        if (info.kind == .array) try words.append(g.allocator, info.len);
        const element = g.representations.store.node(ty).a;
        const row_tag = g.representations.store.node(element).tag;
        const fields = g.representations.store.children(element);
        const nested = try g.nestedRow(element);
        for (g.evaluator.valueChildren(id)) |row| {
            if (nested) |plan| {
                try self.serializeNumericRow(g, row, plan, depth, &words);
                continue;
            }
            const values = g.evaluator.valueChildren(row);
            if (values.len != row_words) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            for (0..row_words) |i| {
                var slot = i;
                if (row_tag == .record) {
                    slot = for (g.evaluator.recordFieldNames(row), 0..) |name, index| {
                        if (name == fields[i * 2]) break index;
                    } else return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                }
                const child_type = fields[if (row_tag == .record) i * 2 + 1 else i];
                // Only scalar children are admitted; serialization cannot
                // specialize a closure or grow the borrowed layout table.
                try words.append(g.allocator, try self.serialize(g, values[slot], child_type, depth + 1));
            }
        }
        const address = if (info.kind == .array) try g.module.dataWords(words.items) else blk: {
            const lists = @import("../runtime/list_runtime.zig");
            var leaves: std.ArrayList(u32) = .empty;
            defer leaves.deinit(g.allocator);
            var offset: usize = 0;
            while (offset < words.items.len) {
                const remaining = words.items[offset..];
                const count = @min(remaining.len, lists.leafLimit(row_words));
                try leaves.append(g.allocator, try lists.staticChunk(&g.module, remaining[0..count]));
                offset += count;
            }
            break :blk try lists.staticScalarDescriptor(&g.module, @intCast(words.items.len), leaves.items, row_words);
        };
        try self.cache.put(g.allocator, key, address);
        return address;
    }
    fn serializeAggregate(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize, info: core_eval.ValueInfo, key: SerializedKey) Error!u32 {
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(g.allocator);
        var word_values: std.ArrayList(core_eval.ValueId) = .empty;
        defer word_values.deinit(g.allocator);
        if (info.kind == .effect_set or info.kind == .effect_descriptor) return g.decline(1, .{ .start = 0, .end = 0 }, .backend_const_only);
        if (info.kind == .nominal) {
            const payload = if (info.len == 0) 0 else try g.nominalPayload(info.nominal, info.bits, ty);
            try words.appendSlice(g.allocator, &.{ info.bits, if (info.len == 0) 0 else try self.serialize(g, g.evaluator.valueChildren(id)[0], payload, depth + 1) });
            try word_values.appendSlice(g.allocator, &.{ 0, if (info.len == 0) 0 else g.evaluator.valueChildren(id)[0] });
        } else {
            if (info.kind == .array) {
                try words.append(g.allocator, info.len);
                try word_values.append(g.allocator, 0);
            }
            const n = g.representations.store.node(ty);
            if (info.kind == .record) {
                if (g.evaluator.recordFieldNames(id).len != info.len or g.representations.store.children(ty).len != @as(usize, info.len) * 2) return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                var index: usize = 0;
                // Recursive closure specialization can grow both side tables.
                // Keep stable IDs and reload each slot before descending.
                while (index < info.len) : (index += 1) {
                    const name_ = g.representations.store.children(ty)[index * 2];
                    const child_type = g.representations.store.children(ty)[index * 2 + 1];
                    var source_slot: ?usize = null;
                    for (g.evaluator.recordFieldNames(id), 0..) |name, slot| if (name == name_) {
                        source_slot = slot;
                        break;
                    };
                    const child = g.evaluator.valueChildren(id)[source_slot orelse return g.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type)];
                    try words.append(g.allocator, try self.serialize(g, child, child_type, depth + 1));
                    try word_values.append(g.allocator, child);
                }
            } else for (0..info.len) |index| {
                const child_type = switch (info.kind) {
                    .array, .list => n.a,
                    .product => g.representations.store.children(ty)[index],
                    else => unreachable,
                };
                const child = g.evaluator.valueChildren(id)[index];
                try words.append(g.allocator, try self.serialize(g, child, child_type, depth + 1));
                try word_values.append(g.allocator, child);
            }
        }
        if (info.kind == .list) {
            if (info.len > 0x10000000) return g.decline(1, .{ .start = 0, .end = 0 }, .complexity);
            const lists = @import("../runtime/list_runtime.zig");
            var leaves: std.ArrayList(u32) = .empty;
            defer leaves.deinit(g.allocator);
            var offset: usize = 0;
            while (offset < words.items.len) {
                const end = @min(words.items.len, offset + lists.capacity);
                const chunk = try lists.staticChunk(&g.module, words.items[offset..end]);
                for (offset..end) |index| try self.dataValueReference(g, chunk + lists.header + @as(u32, @intCast((index - offset) * 4)), word_values.items[index], words.items[index]);
                try leaves.append(g.allocator, chunk);
                offset = end;
            }
            // Later writers derive leaf ownership from the descriptor, too.
            // Scalar words must stay scalar when an immutable seed is copied
            // or grown; their numeric bits never confer reference authority.
            const element = g.representations.store.node(ty).a;
            const address = if (g.layoutRole(element) == .scalar)
                try lists.staticScalarDescriptor(&g.module, info.len, leaves.items, 1)
            else
                try lists.staticDescriptor(&g.module, info.len, leaves.items);
            try self.cache.put(g.allocator, key, address);
            return address;
        }
        const address = if (words.items.len == 0) 0 else try g.module.dataWords(words.items);
        for (word_values.items, words.items, 0..) |value, bits, index| if (value != 0) try self.dataValueReference(g, address + @as(u32, @intCast(index * 4)), value, bits);
        try self.cache.put(g.allocator, key, address);
        return address;
    }

    pub fn serializeClosure(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        const metadata = g.evaluator.closureInfo(id);
        const source = g.unit(metadata.unit);
        const child_count = g.evaluator.valueInfo(id).len;
        var child_types: std.ArrayList(layout.Id) = .empty;
        defer child_types.deinit(g.allocator);
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        try g.loadSemanticRows(g.evaluator.storage.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len], &rows);
        defer mappings.deinit(g.allocator);
        var function_id: u32 = undefined;
        switch (metadata.origin) {
            .anonymous => {
                const closure_ = source.closures[metadata.identity];
                for (g.evaluator.storage.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| {
                    const concrete = g.representations.fromEvidence(g.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(metadata.unit, closure_.body, .unresolved_type);
                    try g.mapType(metadata.unit, &mappings, mapping.variable, concrete, source.span(closure_.body));
                }
                var implementation = ty;
                var dictionaries = false;
                if (g.representations.store.node(ty).tag == .universal) {
                    if (source.types.node(closure_.function_type).tag != .forall) return g.fail(metadata.unit, closure_.body, .unresolved_type);
                    try g.mapTypeDepth(metadata.unit, &mappings, &rows, closure_.function_type, ty, source.span(closure_.body), 0);
                    dictionaries = source.types.quantifierGoals(closure_.function_type).len != 0;
                    implementation = g.representations.store.node(ty).a;
                }
                const fn_type = g.representations.store.node(implementation);
                if (fn_type.tag != .function) return g.fail(metadata.unit, closure_.body, .unresolved_type);
                if (taskCallbackRows(source, closure_.parameter.ty, 0)) {
                    try g.mapTypeDepth(metadata.unit, &mappings, &rows, closure_.parameter.ty, fn_type.a, closure_.parameter.span, 0);
                } else try g.mapType(metadata.unit, &mappings, closure_.parameter.ty, fn_type.a, closure_.parameter.span);
                if (taskCallbackRows(source, source.typeOf(closure_.body), 0)) {
                    try g.mapFunctionResult(metadata.unit, &mappings, &rows, source.typeOf(closure_.body), fn_type.b, source.span(closure_.body));
                } else try g.mapType(metadata.unit, &mappings, source.typeOf(closure_.body), fn_type.b, source.span(closure_.body));
                const captures = source.extra[closure_.captures.start..][0..closure_.captures.len];
                if (captures.len != child_count) return g.fail(metadata.unit, closure_.body, .constant_expression);
                for (captures, 0..) |binding, index| try child_types.append(g.allocator, try g.captureLayout(metadata.unit, binding, g.evaluator.valueChildren(id)[index], &mappings, &rows));
                for (child_types.items) |capture_type| {
                    var budget: usize = 1_000_000;
                    if (!g.retainedLayoutConcrete(capture_type, false, 0, &budget)) return self.serializeStagedClosure(g, id, ty);
                }
                // Contextual effect widening preserves the retained implementation's row.
                var implementation_type = if (closure_.function_type == 0) implementation else try g.codeLayoutWithRows(metadata.unit, closure_.function_type, mappings.items, rows.items, source.span(closure_.body));
                if (g.representations.store.node(ty).tag == .universal) implementation_type = g.representations.store.node(implementation_type).a;
                function_id = try g.closureFunction(.{ .unit = metadata.unit, .catalog = metadata.identity, .staged = metadata.staged, .ty = implementation_type, .captures = try g.internLayout(.product, 0, 0, child_types.items), .evidence = try g.mappingEvidence(mappings.items), .rows = try g.rowMappingEvidence(rows.items), .dictionaries = dictionaries });
            },
            .constructor => {
                var implementation = ty;
                if (g.representations.store.node(ty).tag == .universal) {
                    const constructor = source.constructor(metadata.identity);
                    implementation = g.representations.store.node(ty).a;
                    try g.mapTypeDepth(metadata.unit, &mappings, &rows, constructor.scheme.root, implementation, .{ .start = 0, .end = 0 }, 0);
                    if (try g.codeLayoutWithRows(metadata.unit, constructor.scheme.root, mappings.items, rows.items, .{ .start = 0, .end = 0 }) != implementation) return g.decline(metadata.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
                }
                function_id = try g.constructorFunction(.{ .unit = metadata.unit, .catalog = metadata.identity, .ty = implementation });
            },
            .named => return self.serializeNamedClosure(g, id, ty, depth),
            .primitive => return self.serializePrimitiveClosure(g, id, ty, depth),
            .operation => {
                if (metadata.applied != 0 or child_count != 0) return g.decline(metadata.unit, .{ .start = 0, .end = 0 }, .unsupported);
                for (g.evaluator.storage.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| {
                    const concrete = g.representations.fromEvidence(g.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.decline(metadata.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
                    try g.mapType(metadata.unit, &mappings, mapping.variable, concrete, .{ .start = 0, .end = 0 });
                }
                function_id = try g.operationFunction(.{ .operation = try g.runtimeOperation(try g.operationLabel(metadata.unit, metadata.identity, mappings.items, rows.items, .{ .start = 0, .end = 0 }), metadata.unit, .{ .start = 0, .end = 0 }), .ty = ty });
            },
        }
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(g.allocator);
        for (child_types.items, 0..) |child_type, index| try words.append(g.allocator, try self.serialize(g, g.evaluator.valueChildren(id)[index], child_type, depth + 1));
        const environment = if (words.items.len == 0) 0 else try g.module.dataWords(words.items);
        for (words.items, 0..) |bits, slot| try self.dataValueReference(g, environment + @as(u32, @intCast(slot * 4)), g.evaluator.valueChildren(id)[slot], bits);
        const address = try self.closureData(g, function_id, environment);
        try self.cache.put(g.allocator, .{ .value = id, .ty = ty }, address);
        return address;
    }
    /// A closed selected interface can capture generic helpers whose unused
    /// interfaces remain open. Keep the exact live graph while proving and
    /// emitting this invocation, rather than serializing those open helpers.
    pub fn serializeStagedClosure(self: *State, g: anytype, value: core_eval.ValueId, ty: layout.Id) Error!u32 {
        const header = g.evaluator.closureInfo(value);
        const source = g.unit(header.unit);
        const metadata = source.closures[header.identity];
        const bindings = source.extra[metadata.captures.start..][0..metadata.captures.len];
        const captured = try g.allocator.dupe(core_eval.ValueId, g.evaluator.valueChildren(value));
        defer g.allocator.free(captured);
        if (bindings.len != captured.len) return g.fail(header.unit, metadata.body, .unsupported);
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        for (g.evaluator.storage.type_mappings.items[header.mappings.start..][0..header.mappings.len]) |mapping| {
            const concrete = g.representations.fromEvidence(g.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(header.unit, metadata.body, .unresolved_type);
            try g.mapType(header.unit, &mappings, mapping.variable, concrete, source.span(metadata.body));
        }
        try g.loadSemanticRows(g.evaluator.storage.row_mappings.items[header.row_mappings.start..][0..header.row_mappings.len], &rows);
        const arrow = g.representations.store.node(ty);
        if (metadata.function_type != 0) {
            try g.mapCapturedFunction(header.unit, metadata.function_type, ty, &mappings, &rows, source.span(metadata.body));
        } else {
            try g.mapType(header.unit, &mappings, metadata.parameter.ty, arrow.a, metadata.parameter.span);
            try g.mapType(header.unit, &mappings, source.typeOf(metadata.body), arrow.b, source.span(metadata.body));
        }
        const hints = try g.allocator.alloc(core_eval.RetainedCapture, captured.len);
        defer g.allocator.free(hints);
        for (bindings, captured, hints) |binding, actual, *hint| hint.* = .{ .binding = binding, .unit = header.unit, .node = 0, .value = actual };
        try g.refineAccessorMappings(header.unit, header.identity, ty, &mappings, &rows, source.span(metadata.body), hints);
        const function_id = try g.capturedClosureFunction(header, ty, captured, mappings.items, rows.items);
        const address = try self.closureData(g, function_id, 0);
        try self.cache.put(g.allocator, .{ .value = value, .ty = ty }, address);
        return address;
    }
    pub fn serializeNamedClosure(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        const metadata = g.evaluator.closureInfo(id);
        const target: core.BindingRef = .{ .unit = metadata.unit, .binding = metadata.identity };
        const source = g.unit(metadata.unit);
        const body = source.body(metadata.identity) orelse return g.decline(metadata.unit, source.binding(metadata.identity).span, .constant_expression);
        const child_count = g.evaluator.valueInfo(id).len;
        if (child_count != metadata.applied or child_count >= body.parameters.len) return g.decline(metadata.unit, body.span, .constant_expression);
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        try g.loadSemanticRows(g.evaluator.storage.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len], &rows);
        defer mappings.deinit(g.allocator);
        var types_: std.ArrayList(layout.Id) = .empty;
        defer types_.deinit(g.allocator);
        for (g.evaluator.storage.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| {
            const concrete = g.representations.fromEvidence(g.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.decline(metadata.unit, body.span, .unresolved_type);
            try g.mapType(metadata.unit, &mappings, mapping.variable, concrete, body.span);
        }
        var source_ty = try g.functionRoot(metadata.unit, source.binding(metadata.identity).ty, body.span);
        for (source.bodyParameters(body)[0..child_count], 0..) |parameter, index| {
            const child = g.evaluator.valueChildren(id)[index];
            // Unnamed applied parameters (including Unit patterns) have no
            // lexical BindingId. Their declared type still owns the argument.
            const concrete = try g.captureTypeLayout(metadata.unit, parameter.ty, parameter.span, child, &mappings, &rows);
            try types_.append(g.allocator, concrete);
            const n = source.types.node(source_ty);
            if (n.tag != .function) return g.decline(metadata.unit, body.span, .unresolved_type);
            try g.mapType(metadata.unit, &mappings, n.a, concrete, body.span);
            source_ty = n.b;
        }
        var dictionaries = false;
        if (g.representations.store.node(ty).tag == .universal) {
            if (metadata.applied != 0 or source.types.node(source.binding(metadata.identity).ty).tag != .forall) return g.decline(metadata.unit, body.span, .unresolved_type);
            try g.mapTypeDepth(metadata.unit, &mappings, &rows, source.binding(metadata.identity).ty, ty, body.span, 0);
            dictionaries = source.types.quantifierGoals(source.binding(metadata.identity).ty).len != 0;
        } else if (taskCallbackRows(source, source_ty, 0)) {
            // A stored implementation keeps its own effects even when its
            // consumer permits a wider row. Infer open rows without imposing
            // that consumer's effects on a closed, pure captured helper.
            try g.mapFunctionResult(metadata.unit, &mappings, &rows, source_ty, ty, body.span);
        } else try g.mapType(metadata.unit, &mappings, source_ty, ty, body.span);
        var full_type = try g.codeLayoutWithRows(metadata.unit, source.binding(metadata.identity).ty, mappings.items, rows.items, body.span);
        if (g.representations.store.node(ty).tag == .universal) full_type = g.representations.store.node(full_type).a;
        const function_id = try g.callable(.{ .target = target, .ty = full_type, .applied = metadata.applied, .dictionaries = dictionaries });
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(g.allocator);
        for (types_.items, 0..) |child_type, index| try words.append(g.allocator, try self.serialize(g, g.evaluator.valueChildren(id)[index], child_type, depth + 1));
        var environment: u32 = 0;
        if (g.directCallableEnvironment(full_type, metadata.applied)) {
            environment = words.items[0];
        } else if (words.items.len != 0) {
            environment = try g.module.dataWords(words.items);
            for (words.items, 0..) |bits, slot| try self.dataValueReference(g, environment + @as(u32, @intCast(slot * 4)), g.evaluator.valueChildren(id)[slot], bits);
        }
        const address = try self.closureData(g, function_id, environment);
        try self.cache.put(g.allocator, .{ .value = id, .ty = ty }, address);
        return address;
    }

    pub fn serializePrimitiveClosure(self: *State, g: anytype, id: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        const metadata = g.evaluator.closureInfo(id);
        const child_count = g.evaluator.valueInfo(id).len;
        const primitive = g.unit(metadata.unit).primitives[metadata.identity];
        if (primitive.kind != .scalar) return g.decline(metadata.unit, .{ .start = 0, .end = 0 }, .constant_expression);
        var full_type = ty;
        var index = child_count;
        while (index != 0) {
            index -= 1;
            const value = g.evaluator.valueScalar(g.evaluator.valueChildren(id)[index]) orelse return g.decline(metadata.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
            const argument: layout.Id = if (value.scalar == .f32) 4 else 3;
            full_type = try g.internLayout(.function, argument, full_type, &.{});
        }
        const function_id = try g.primitiveFunction(.{ .unit = metadata.unit, .catalog = metadata.identity, .ty = full_type, .applied = metadata.applied });
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(g.allocator);
        var current = full_type;
        for (0..child_count) |child_index| {
            const child = g.evaluator.valueChildren(id)[child_index];
            const n = g.representations.store.node(current);
            try words.append(g.allocator, try self.serialize(g, child, n.a, depth + 1));
            current = n.b;
        }
        const environment = if (words.items.len == 0) 0 else try g.module.dataWords(words.items);
        for (words.items, 0..) |bits, slot| try self.dataValueReference(g, environment + @as(u32, @intCast(slot * 4)), g.evaluator.valueChildren(id)[slot], bits);
        const address = try self.closureData(g, function_id, environment);
        try self.cache.put(g.allocator, .{ .value = id, .ty = ty }, address);
        return address;
    }
};
