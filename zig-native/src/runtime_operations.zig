//! Guest operation tags have their own owner. Semantic interner IDs are never
//! runtime integers. Project keys own producer paths and field spellings; the
//! explicit Core-only fallback uses compilation-local unit/Symbol IDs. Neither
//! domain is a complete portable code-fragment validity key.
const std = @import("std");
const evidence = @import("type_evidence.zig");
const wasm = @import("wasm.zig");
const runtime_identity = @import("runtime_identity.zig");
const artifact = @import("artifact_emitter.zig");
const Allocator = std.mem.Allocator;
pub const Id = u32;
pub const Error = Allocator.Error || error{ InvalidOperation, ModuleTooLarge };
const max_key_bytes = 1024 * 1024;
const Entry = struct { key: []u8, foreign: bool, runtime: u32 = 0 };
const Location = union(enum) { instruction: struct { function: u32, index: u32 }, word: u32 };
const Relocation = struct { operation: Id, location: Location };

const Encoder = struct {
    allocator: Allocator,
    view: evidence.View,
    identity: ?runtime_identity.View = null,
    bytes: std.ArrayList(u8) = .empty,
    fn deinit(self: *Encoder) void {
        self.bytes.deinit(self.allocator);
    }
    fn raw(self: *Encoder, bytes: []const u8) Error!void {
        if (bytes.len > max_key_bytes -| self.bytes.items.len) return error.ModuleTooLarge;
        try self.bytes.appendSlice(self.allocator, bytes);
    }
    fn word(self: *Encoder, value: u32) Error!void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .big);
        try self.raw(&bytes);
    }
    fn count(self: *Encoder, value: usize) Error!void {
        if (value > std.math.maxInt(u32)) return error.ModuleTooLarge;
        try self.word(@intCast(value));
    }
    fn owner(self: *Encoder, unit: u32) Error!void {
        if (self.identity) |names| {
            if (unit == 0 or unit == std.math.maxInt(u32)) {
                try self.raw(&.{0});
                return self.word(unit);
            }
            const path = names.owner(unit) orelse return error.InvalidOperation;
            try self.raw(&.{1});
            try self.count(path.len);
            return self.raw(path);
        }
        return self.word(unit);
    }
    fn operation(self: *Encoder, label: evidence.Effects.Label, depth: usize) Error!void {
        if (depth >= 1024 or label == 0 or label >= self.view.effects.operations.len) return error.InvalidOperation;
        const operation_ = self.view.effects.operation(label);
        if (operation_.identity.decl == 0 or operation_.arguments.start > self.view.effects.arguments.len or operation_.arguments.len > self.view.effects.arguments.len - operation_.arguments.start) return error.InvalidOperation;
        const arguments = self.view.effects.operationArguments(label);
        if (operation_.identity.unit == 0 and operation_.identity.decl == 1 and arguments.len != 0) return error.InvalidOperation;
        try self.owner(operation_.identity.unit);
        try self.word(operation_.identity.decl);
        try self.count(arguments.len);
        for (arguments) |argument| try self.ty(argument, depth + 1);
    }
    fn row(self: *Encoder, id: evidence.Effects.Id, depth: usize) Error!void {
        if (depth >= 1024 or id >= self.view.effects.rows.len) return error.InvalidOperation;
        const span = self.view.effects.rows[id];
        if (span.start > self.view.effects.labels.len or span.len > self.view.effects.labels.len - span.start) return error.InvalidOperation;
        const labels = self.view.effects.rowLabels(id);
        const keys = try self.allocator.alloc([]u8, labels.len);
        defer self.allocator.free(keys);
        var initialized: usize = 0;
        defer for (keys[0..initialized]) |key| self.allocator.free(key);
        for (labels, keys) |label, *key| {
            var child: Encoder = .{ .allocator = self.allocator, .view = self.view, .identity = self.identity };
            defer child.deinit();
            try child.operation(label, depth + 1);
            key.* = try child.bytes.toOwnedSlice(self.allocator);
            initialized += 1;
        }
        // Rows are semantic multisets. Keep duplicates; interner numeric label
        // sorting must not decide the canonical symbolic operation order.
        std.mem.sort([]u8, keys, {}, struct {
            fn less(_: void, left: []u8, right: []u8) bool {
                return std.mem.order(u8, left, right) == .lt;
            }
        }.less);
        try self.count(keys.len);
        for (keys) |key| {
            try self.count(key.len);
            try self.raw(key);
        }
    }
    fn ty(self: *Encoder, id: evidence.Id, depth: usize) Error!void {
        if (depth >= 1024 or id == 0 or id >= self.view.nodes.len) return error.InvalidOperation;
        const node = self.view.node(id);
        try self.raw(&.{@backingInt(node.tag)});
        switch (node.tag) {
            .absent => return error.InvalidOperation,
            .unit, .boolean, .u32, .f32, .never => {},
            .function => {
                try self.ty(node.a, depth + 1);
                try self.ty(node.b, depth + 1);
                try self.row(node.c, depth + 1);
            },
            .demand, .provider => {
                try self.ty(node.a, depth + 1);
                try self.row(node.c, depth + 1);
            },
            .array, .list, .resolver => try self.ty(node.a, depth + 1),
            .state_provider => {
                try self.ty(node.a, depth + 1);
                try self.ty(node.b, depth + 1);
                try self.ty(node.c, depth + 1);
            },
            .type_constructor => {
                try self.owner(node.a);
                try self.word(node.b);
            },
            .nominal => {
                try self.owner(node.a);
                try self.word(node.b);
                if (node.c >= self.view.extra.len) return error.InvalidOperation;
                const length = self.view.extra[node.c];
                if (length > self.view.extra.len - node.c - 1) return error.InvalidOperation;
                try self.count(length);
                for (self.view.children(id)) |child| try self.ty(child, depth + 1);
            },
            .product => {
                if (node.a > self.view.extra.len or node.b > self.view.extra.len - node.a) return error.InvalidOperation;
                try self.count(node.b);
                for (self.view.children(id)) |child| try self.ty(child, depth + 1);
            },
            .record => {
                if (node.a > self.view.extra.len or node.b > (self.view.extra.len - node.a) / 2) return error.InvalidOperation;
                const fields = self.view.children(id);
                // TypeEvidence publishes semantic fields sorted by Symbol ID.
                // This lane has no Core physical payload/record destination list.
                if (self.identity) |names| {
                    const Field = struct { name: []const u8, ty: evidence.Id };
                    const ordered = try self.allocator.alloc(Field, node.b);
                    defer self.allocator.free(ordered);
                    for (ordered, 0..) |*field, index| field.* = .{ .name = names.symbol(fields[index * 2]) orelse return error.InvalidOperation, .ty = fields[index * 2 + 1] };
                    std.mem.sort(Field, ordered, {}, struct {
                        fn less(_: void, left: Field, right: Field) bool {
                            return std.mem.order(u8, left.name, right.name) == .lt;
                        }
                    }.less);
                    try self.count(ordered.len);
                    for (ordered, 0..) |field, index| {
                        if (field.name.len == 0 or (index != 0 and std.mem.eql(u8, ordered[index - 1].name, field.name))) return error.InvalidOperation;
                        try self.count(field.name.len);
                        try self.raw(field.name);
                        try self.ty(field.ty, depth + 1);
                    }
                    return;
                }
                var prior: u32 = 0;
                try self.count(node.b);
                for (0..node.b) |index| {
                    const name = fields[index * 2];
                    if (name <= prior) return error.InvalidOperation;
                    prior = name;
                    try self.word(name);
                    try self.ty(fields[index * 2 + 1], depth + 1);
                }
            },
        }
    }
};

pub const Store = struct {
    allocator: Allocator,
    identity: ?runtime_identity.View = null,
    entries: std.ArrayList(Entry) = .empty,
    keys: std.StringHashMapUnmanaged(Id) = .empty,
    relocations: std.ArrayList(Relocation) = .empty,
    finalized: bool = false,
    artifacts: ?*artifact.Recorder = null,
    pub fn init(allocator: Allocator) Store {
        return .{ .allocator = allocator };
    }
    pub fn initProject(allocator: Allocator, names: runtime_identity.View) Store {
        return .{ .allocator = allocator, .identity = names };
    }
    pub fn deinit(self: *Store) void {
        for (self.entries.items) |entry| self.allocator.free(entry.key);
        self.entries.deinit(self.allocator);
        self.keys.deinit(self.allocator);
        self.relocations.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn intern(self: *Store, view: evidence.View, label: evidence.Effects.Label) Error!Id {
        if (self.finalized) return error.InvalidOperation;
        var encoder: Encoder = .{ .allocator = self.allocator, .view = view, .identity = self.identity };
        defer encoder.deinit();
        try encoder.raw(&.{ 1, if (self.identity != null) @as(u8, 'P') else @as(u8, 'S') });
        try encoder.operation(label, 0);
        const identity = view.effects.operation(label).identity;
        return self.internSymbol(encoder.bytes.items, identity.unit == 0 and identity.decl == 1);
    }
    /// Only validated owned symbol demands may use this entry point. It does
    /// not establish code validity; the retained job guard owns that decision.
    pub fn internSymbol(self: *Store, key: []const u8, foreign: bool) Error!Id {
        if (self.finalized or key.len < 2 or key[0] != 1 or key[1] != (if (self.identity != null) @as(u8, 'P') else @as(u8, 'S'))) return error.InvalidOperation;
        if (self.keys.get(key)) |id| {
            if (self.entries.items[id - 1].foreign != foreign) return error.InvalidOperation;
            if (self.artifacts) |journal| try journal.append(.{ .demand = .{ .kind = .operation, .id = id, .hit = true } });
            return id;
        }
        if (self.entries.items.len >= std.math.maxInt(Id) - 2) return error.ModuleTooLarge;
        const owned = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned);
        try self.entries.ensureUnusedCapacity(self.allocator, 1);
        try self.keys.ensureUnusedCapacity(self.allocator, 1);
        const id: Id = @intCast(self.entries.items.len + 1);
        if (self.artifacts) |journal| {
            try journal.operationSymbol(id, owned, foreign);
            try journal.append(.{ .demand = .{ .kind = .operation, .id = id, .hit = false } });
        }
        self.entries.appendAssumeCapacity(.{ .key = owned, .foreign = foreign });
        self.keys.putAssumeCapacityNoClobber(owned, id);
        return id;
    }
    pub fn emit(self: *Store, module: *wasm.Module, function: u32, operation: Id) Error!void {
        if (self.finalized or operation == 0 or operation > self.entries.items.len or function >= module.functions.items.len) return error.InvalidOperation;
        const index = module.functions.items[function].instructions.items.len;
        if (index > std.math.maxInt(u32)) return error.ModuleTooLarge;
        try self.relocations.ensureUnusedCapacity(self.allocator, 1);
        try module.emitReference(function, .{ .op = .i32_const, .operand = operation }, .operation);
        module.functions.items[function].instructions.items[index].operand = 0;
        self.relocations.appendAssumeCapacity(.{ .operation = operation, .location = .{ .instruction = .{ .function = function, .index = @intCast(index) } } });
    }
    pub fn dataWord(self: *Store, module: *wasm.Module, address: u32, operation: Id) Error!void {
        if (self.finalized or operation == 0 or operation > self.entries.items.len or address % 4 != 0 or address > module.data.items.len or 4 > module.data.items.len - address) return error.InvalidOperation;
        try module.dataReference(address, .{ .role = .operation, .value = operation });
        try self.relocations.append(self.allocator, .{ .operation = operation, .location = .{ .word = address } });
    }
    pub fn finish(self: *Store, module: *wasm.Module) Error!void {
        if (self.finalized) return error.InvalidOperation;
        const ordered = try self.allocator.alloc(Id, self.entries.items.len);
        defer self.allocator.free(ordered);
        for (ordered, 0..) |*id, index| id.* = @intCast(index);
        std.mem.sort(Id, ordered, self.entries.items, struct {
            fn less(entries: []const Entry, left: Id, right: Id) bool {
                return std.mem.order(u8, entries[left].key, entries[right].key) == .lt;
            }
        }.less);
        const Site = struct { function: u32, index: u32 };
        var sites: std.AutoHashMapUnmanaged(Site, void) = .empty;
        defer sites.deinit(self.allocator);
        // Validate every source site before changing any code/data word. No
        // allocation or fallible operation follows publication below.
        for (self.relocations.items) |relocation| {
            if (relocation.operation == 0 or relocation.operation > self.entries.items.len) return error.InvalidOperation;
            const key: Site = switch (relocation.location) {
                .instruction => |site| .{ .function = site.function, .index = site.index },
                .word => |address| .{ .function = std.math.maxInt(u32), .index = address },
            };
            const inserted = try sites.getOrPut(self.allocator, key);
            if (inserted.found_existing) return error.InvalidOperation;
            switch (relocation.location) {
                .instruction => |site| {
                    if (site.function >= module.functions.items.len) return error.InvalidOperation;
                    const instructions = module.functions.items[site.function].instructions.items;
                    if (site.index >= instructions.len or instructions[site.index].op != .i32_const or instructions[site.index].operand != 0) return error.InvalidOperation;
                },
                .word => |address| {
                    if (address % 4 != 0 or address > module.data.items.len or 4 > module.data.items.len - address or std.mem.readInt(u32, module.data.items[address..][0..4], .little) != 0) return error.InvalidOperation;
                },
            }
        }
        var next: u32 = 2; // Foreign is sealed and reserved as runtime operation 1.
        for (ordered) |index| {
            const entry = &self.entries.items[index];
            entry.runtime = if (entry.foreign) 1 else next;
            if (!entry.foreign) next += 1;
        }
        for (self.relocations.items) |relocation| {
            const id = self.entries.items[relocation.operation - 1].runtime;
            switch (relocation.location) {
                .instruction => |site| module.functions.items[site.function].instructions.items[site.index].operand = id,
                .word => |address| std.mem.writeInt(u32, module.data.items[address..][0..4], id, .little),
            }
        }
        self.finalized = true;
    }
    /// A Core-only table cannot publish a project-scoped operation symbol.
    /// Even a project symbol still requires module/settings/evidence validity
    /// to become a complete persistent code-fragment key.
    pub fn projectKey(self: *const Store, operation: Id) ?[]const u8 {
        if (self.identity == null or operation == 0 or operation > self.entries.items.len) return null;
        return self.entries.items[operation - 1].key;
    }
    pub fn runtimeId(self: *const Store, operation: Id) ?u32 {
        if (!self.finalized or operation == 0 or operation > self.entries.items.len) return null;
        return self.entries.items[operation - 1].runtime;
    }
};
