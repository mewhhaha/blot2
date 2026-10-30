//! Canonical structural DAGs for one selected-call key. No proof is cached.
//! Only completed descriptors are interned; source references accelerate this
//! construction but never appear in its encoding.
const std = @import("std");
pub const Error = std.mem.Allocator.Error || error{ Limit, Cycle };
pub const Reference = struct {
    unit: u32,
    ty: u32,
    environment: usize = 0,
    environment_len: usize = 0,
    captured: bool = false,
};
pub const Result = struct { id: u32, height: usize };
pub const Options = struct {
    encoded_words: usize = 65_536,
    word_work: usize = 262_144,
    hash_mask: u64 = std.math.maxInt(u64),
};
pub const Builder = struct {
    const Node = struct { start: usize, len: usize, height: usize, next: ?u32 };
    const Memo = union(enum) { active: usize, complete: Result };
    allocator: std.mem.Allocator,
    remaining: *usize,
    options: Options,
    word_work: usize,
    words: std.ArrayList(u32) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    buckets: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    memo: std.AutoHashMapUnmanaged(Reference, Memo) = .empty,
    poisoned: bool = false,
    finished: bool = false,

    pub fn init(allocator: std.mem.Allocator, remaining: *usize, options: Options) Builder {
        return .{ .allocator = allocator, .remaining = remaining, .options = options, .word_work = options.word_work };
    }
    pub fn deinit(self: *Builder) void {
        self.memo.deinit(self.allocator);
        self.buckets.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
        self.words.deinit(self.allocator);
    }
    fn charge(self: *Builder) Error!void {
        if (self.poisoned or self.finished or self.remaining.* == 0) return error.Limit;
        self.remaining.* -= 1;
    }
    fn wordWork(self: *Builder, count: usize) Error!void {
        if (self.poisoned or self.finished or count > self.word_work) return error.Limit;
        self.word_work -= count;
    }
    fn encodedSize(self: *const Builder) Error!usize {
        const count = std.math.add(usize, self.words.items.len, self.nodes.items.len) catch return error.Limit;
        return std.math.add(usize, count, 4) catch error.Limit;
    }
    pub fn enter(self: *Builder, reference: Reference, depth: usize) Error!?Result {
        errdefer self.poisoned = true;
        try self.charge();
        if (depth > 128) return error.Limit;
        if (self.memo.get(reference)) |entry| switch (entry) {
            .active => return error.Cycle,
            .complete => |result| {
                if (result.height > 128 - depth) return error.Limit;
                return result;
            },
        };
        try self.memo.put(self.allocator, reference, .{ .active = depth });
        return null;
    }
    pub fn addWord(self: *Builder, descriptor: *std.ArrayList(u32), word: u32) Error!void {
        errdefer self.poisoned = true;
        if (descriptor.items.len >= self.options.encoded_words) return error.Limit;
        try self.wordWork(1);
        try descriptor.append(self.allocator, word);
    }
    pub fn addWords(self: *Builder, descriptor: *std.ArrayList(u32), words: []const u32) Error!void {
        errdefer self.poisoned = true;
        if (descriptor.items.len > self.options.encoded_words or words.len > self.options.encoded_words - descriptor.items.len) return error.Limit;
        try self.wordWork(words.len);
        try descriptor.appendSlice(self.allocator, words);
    }
    fn equal(self: *Builder, stored: []const u32, candidate: []const u32) Error!bool {
        if (stored.len != candidate.len) return false;
        for (stored, candidate) |a, b| {
            try self.wordWork(1);
            if (a != b) return false;
        }
        return true;
    }
    pub fn complete(self: *Builder, reference: Reference, descriptor: []const u32, height: usize) Error!Result {
        errdefer self.poisoned = true;
        if (self.poisoned or self.finished or height > 128) return error.Limit;
        const pending = self.memo.get(reference) orelse return error.Cycle;
        if (pending != .active) return error.Cycle;
        if (height > 128 - pending.active) return error.Limit;
        try self.wordWork(descriptor.len);
        const hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(descriptor)) & self.options.hash_mask;
        var next = self.buckets.get(hash);
        while (next) |id| {
            try self.charge();
            const node = self.nodes.items[id];
            if (try self.equal(self.words.items[node.start..][0..node.len], descriptor)) {
                if (node.height != height) return error.Cycle;
                const result: Result = .{ .id = id, .height = height };
                self.memo.getPtr(reference).?.* = .{ .complete = result };
                return result;
            }
            next = node.next;
        }
        const growth = std.math.add(usize, descriptor.len, 1) catch return error.Limit;
        const encoded = try self.encodedSize();
        if (encoded > self.options.encoded_words or growth > self.options.encoded_words - encoded) return error.Limit;
        const id = std.math.cast(u32, self.nodes.items.len) orelse return error.Limit;
        // Reserve all publication capacity before installing a completed node.
        try self.wordWork(descriptor.len);
        try self.words.ensureUnusedCapacity(self.allocator, descriptor.len);
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.buckets.ensureUnusedCapacity(self.allocator, 1);
        const start = self.words.items.len;
        self.words.appendSliceAssumeCapacity(descriptor);
        self.nodes.appendAssumeCapacity(.{ .start = start, .len = descriptor.len, .height = height, .next = self.buckets.get(hash) });
        self.buckets.putAssumeCapacity(hash, id);
        const result: Result = .{ .id = id, .height = height };
        self.memo.getPtr(reference).?.* = .{ .complete = result };
        return result;
    }
    pub fn root(self: *Builder, output: *std.ArrayList(u32), result: Result) Error!void {
        errdefer self.poisoned = true;
        if (result.id >= self.nodes.items.len or self.nodes.items[result.id].height != result.height) return error.Limit;
        const table = try self.encodedSize();
        if (table >= self.options.encoded_words or output.items.len >= self.options.encoded_words - table) return error.Limit;
        try self.wordWork(1);
        try output.append(self.allocator, result.id);
    }
    /// Append one versioned, length-delimited table atomically. Root references
    /// and non-type evidence are already in the caller's unpublished buffer.
    pub fn finish(self: *Builder, output: *std.ArrayList(u32)) Error!void {
        errdefer self.poisoned = true;
        if (self.poisoned or self.finished) return error.Limit;
        var entries = self.memo.iterator();
        while (entries.next()) |entry| {
            try self.charge();
            if (entry.value_ptr.* == .active) return error.Cycle;
        }
        const count = try self.encodedSize();
        if (count > self.options.encoded_words or output.items.len > self.options.encoded_words - count) return error.Limit;
        try self.wordWork(count);
        try output.ensureUnusedCapacity(self.allocator, count);
        output.appendSliceAssumeCapacity(&.{ 0x53444b31, 1, @intCast(self.nodes.items.len), @intCast(self.words.items.len) });
        for (self.nodes.items) |node| {
            output.appendAssumeCapacity(@intCast(node.len));
            output.appendSliceAssumeCapacity(self.words.items[node.start..][0..node.len]);
        }
        self.finished = true;
    }
};
