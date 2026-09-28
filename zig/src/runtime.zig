//! Native values and primitives for the first semantic port.
//! Every compilation owns an arena; retained session state is copied between
//! revisions, preserving graph sharing. No Bend runtime or generated C is used.
const std = @import("std");
const generated = @import("generated/functions.zig");
pub const Tag = @import("generated/tags.zig").Tag;
pub const Primitive = @import("generated/primitives.zig").Primitive;
pub const Value = u64;
pub const assert = std.debug.assert;
pub const mask: u64 = (1 << 48) - 1;
const Kind = enum(u16) { natural, integer, real, char, constant, object, string, closure, array };
const Header = extern struct { identity: u32, length: u32 };
pub const Step = union(enum) { value: Value, tail: u32 };
pub const erased: Value = empty(.Unit);
pub inline fn ignore(_: Value) void {}
pub inline fn ignoreContext(_: *Context) void {}
inline fn kind(v: Value) Kind {
    return @enumFromInt(v >> 48);
}
inline fn pack(k: Kind, bits: u64) Value {
    return (@as(u64, @intFromEnum(k)) << 48) | (bits & mask);
}
inline fn pointer(k: Kind, p: anytype) Value {
    const address = @intFromPtr(p);
    assert(address <= mask);
    return pack(k, address);
}
inline fn ptr(comptime T: type, v: Value) T {
    return @ptrFromInt(v & mask);
}
pub inline fn nat(v: u64) Value {
    return pack(.natural, v);
}
pub inline fn word(v: u32) Value {
    return pack(.integer, v);
}
pub inline fn float(v: f32) Value {
    return pack(.real, @as(u32, @bitCast(v)));
}
pub inline fn character(v: u32) Value {
    return pack(.char, v);
}
pub inline fn empty(t: Tag) Value {
    return pack(.constant, @intFromEnum(t));
}
pub inline fn boolean(v: bool) Value {
    return empty(if (v) .True else .False);
}
pub inline fn truth(v: Value) bool {
    assert(v == empty(.True) or v == empty(.False));
    return v == empty(.True);
}
pub inline fn toNat(v: Value) u64 {
    assert(kind(v) == .natural);
    return v & mask;
}
pub inline fn toWord(v: Value) u32 {
    assert(kind(v) == .integer);
    return @truncate(v);
}
pub inline fn toFloat(v: Value) f32 {
    assert(kind(v) == .real);
    return @bitCast(@as(u32, @truncate(v)));
}
fn objectFields(v: Value) []Value {
    const head = ptr(*Header, v);
    const values: [*]Value = @ptrFromInt((v & mask) + @sizeOf(Header));
    return values[0..head.length];
}
pub inline fn tag(v: Value) Tag {
    return switch (kind(v)) {
        .constant => @enumFromInt(v & mask),
        .object => @enumFromInt(ptr(*const Header, v).identity),
        .string => if (ptr([*]const u32, v)[0] == 0xffffffff) .SNil else .SCon,
        .integer => .U32,
        .real => .F32,
        .char => .Chr,
        else => @panic("a numeric/opaque value was matched as a constructor"),
    };
}
pub inline fn field(v: Value, index: usize) Value {
    return switch (kind(v)) {
        .object => objectFields(v)[index],
        .string => switch (index) {
            0 => character(ptr([*]const u32, v)[0]),
            1 => pointer(.string, ptr([*]const u32, v) + 1),
            else => @panic("invalid string field"),
        },
        .integer, .real => blk: {
            assert(index == 0);
            break :blk nat(v & 0xffffffff);
        },
        .char => blk: {
            assert(index == 0);
            break :blk word(@truncate(v));
        },
        else => @panic("field access on an immediate constructor"),
    };
}
pub fn literal(comptime source: []const u8) Value {
    const storage = comptime blk: {
        @setEvalBranchQuota(100000);
        var bytes: [source.len + 1]u32 = @splat(0xffffffff);
        var it = std.unicode.Utf8View.initComptime(source).iterator();
        var i: usize = 0;
        while (it.nextCodepoint()) |cp| : (i += 1) bytes[i] = cp;
        break :blk bytes;
    };
    return pointer(.string, &storage);
}
pub fn stringOrder(a: Value, b: Value) std.math.Order {
    var x = a;
    var y = b;
    while (tag(x) == .SCon and tag(y) == .SCon) {
        const xc: u32 = @truncate(field(x, 0));
        const yc: u32 = @truncate(field(y, 0));
        if (xc != yc) return std.math.order(xc, yc);
        x = field(x, 1);
        y = field(y, 1);
        if (x == y) return .eq;
    }
    return if (tag(x) == .SNil) (if (tag(y) == .SNil) .eq else .lt) else .gt;
}
pub fn stringEqual(a: Value, b: Value) bool {
    return a == b or stringOrder(a, b) == .eq;
}
fn length(v: Value, cons: Tag) usize {
    var n: usize = 0;
    var cursor = v;
    while (tag(cursor) == cons) : (cursor = field(cursor, 1)) n += 1;
    return n;
}
fn drop(v: Value, count: u64, cons: Tag) Value {
    var n = count;
    var cursor = v;
    while (n > 0 and tag(cursor) == cons) : (n -= 1) cursor = field(cursor, 1);
    return cursor;
}
const Numeric = enum { add, sub, mul, div };
pub fn numeric(op: Numeric, a: Value, b: Value) Value {
    assert(kind(a) == kind(b));
    if (kind(a) == .real) {
        const x = toFloat(a);
        const y = toFloat(b);
        return float(switch (op) {
            .add => x + y,
            .sub => x - y,
            .mul => x * y,
            .div => x / y,
        });
    }
    if (kind(a) == .integer) {
        const x = toWord(a);
        const y = toWord(b);
        return word(switch (op) {
            .add => x +% y,
            .sub => x -% y,
            .mul => x *% y,
            .div => if (y == 0) 0 else x / y,
        });
    }
    const x = toNat(a);
    const y = toNat(b);
    return nat(switch (op) {
        .add => x +% y,
        .sub => x -| y,
        .mul => x *% y,
        .div => if (y == 0) 0 else x / y,
    });
}
fn compareResult(order: std.math.Order) Value {
    return empty(switch (order) {
        .lt => .LT,
        .eq => .EQ,
        .gt => .GT,
    });
}

pub const Context = struct {
    pub const Pool = @import("pool.zig").Pool;
    const Job = @import("pool.zig").Job;
    pool: ?*Pool = null,
    shared_allocator: ?std.mem.Allocator = null,
    arena: std.heap.ArenaAllocator,
    pending: [64]Value = undefined,
    pending_len: usize = 0,
    calls: u64 = 0,
    allocated: usize = 0,
    pub fn init(backing: std.mem.Allocator) Context {
        return .{ .arena = std.heap.ArenaAllocator.init(backing) };
    }
    pub fn deinit(self: *Context) void {
        self.arena.deinit();
    }
    pub fn allocator(self: *Context) std.mem.Allocator {
        return self.shared_allocator orelse self.arena.allocator();
    }
    fn allocate(self: *Context, comptime T: type, n: usize) []T {
        const bytes = std.math.mul(usize, n, @sizeOf(T)) catch @panic("allocation size overflow");
        self.allocated = std.math.add(usize, self.allocated, bytes) catch @panic("allocation accounting overflow");
        return self.allocator().alloc(T, n) catch @panic("Zig compiler ran out of memory");
    }
    fn rawNode(self: *Context, k: Kind, identity: u32, fields: []const Value) Value {
        const storage = self.allocate(Value, fields.len + 1);
        const h: *Header = @ptrCast(storage.ptr);
        h.* = .{ .identity = identity, .length = @intCast(fields.len) };
        @memcpy(storage[1..], fields);
        return pointer(k, storage.ptr);
    }
    pub fn node(self: *Context, t: Tag, fields: []const Value) Value {
        if (fields.len == 0) return empty(t);
        return switch (t) {
            .Chr => character(toWord(fields[0])),
            .U32 => word(@truncate(toNat(fields[0]))),
            .F32 => pack(.real, toNat(fields[0]) & 0xffffffff),
            else => self.rawNode(.object, @intFromEnum(t), fields),
        };
    }
    pub fn closure(self: *Context, function: u32, captures: []const Value) Value {
        return self.rawNode(.closure, function, captures);
    }
    pub fn next(self: *Context, function: u32, args: []const Value) Step {
        assert(args.len <= self.pending.len);
        @memcpy(self.pending[0..args.len], args);
        self.pending_len = args.len;
        return .{ .tail = function };
    }
    pub fn call(self: *Context, function: u32, args: []const Value) Value {
        var id = function;
        var arguments = args;
        while (true) {
            self.calls += 1;
            const step = generated.table[id](self, arguments);
            switch (step) {
                .value => |v| return v,
                .tail => |next_id| {
                    id = next_id;
                    arguments = self.pending[0..self.pending_len];
                },
            }
        }
    }
    pub fn nextClosure(self: *Context, fn_value: Value, args: []const Value) Step {
        assert(kind(fn_value) == .closure);
        const h = ptr(*const Header, fn_value);
        const captures = objectFields(fn_value);
        const arity = generated.arities[h.identity];
        assert(captures.len <= arity);
        const needed = arity - captures.len;
        var values: [64]Value = undefined;
        const consumed = @min(needed, args.len);
        assert(captures.len + consumed <= values.len);
        @memcpy(values[0..captures.len], captures);
        @memcpy(values[captures.len..][0..consumed], args[0..consumed]);
        const complete = values[0 .. captures.len + consumed];
        if (args.len < needed) return .{ .value = self.closure(h.identity, complete) };
        if (args.len == needed) return self.next(h.identity, complete);
        // Uncurried call syntax also applies curried lambda chains.
        // Keep the remainder independent of trampoline scratch arguments.
        const remainder = self.allocator().dupe(Value, args[consumed..]) catch @panic("out of memory");
        const intermediate = self.call(h.identity, complete);
        return .{ .value = self.invoke(intermediate, remainder) };
    }
    pub fn invoke(self: *Context, fn_value: Value, args: []const Value) Value {
        const step = self.nextClosure(fn_value, args);
        return switch (step) {
            .value => |v| v,
            .tail => |id| self.call(id, self.pending[0..self.pending_len]),
        };
    }
    /// Each task has independent trampoline scratch. Its immutable result is
    /// allocated in the parent's request arena, whose allocator is thread-safe
    /// in Zig 0.16. No arena can be destroyed until every task has been joined.
    pub fn parallel(self: *Context, comptime count: usize, thunks: [count]Value) [count]Value {
        const Task = struct {
            context: Context,
            thunk: Value,
            result: Value = undefined,
            fn run(raw: *anyopaque) void {
                const task: *@This() = @ptrCast(@alignCast(raw));
                task.result = task.context.invoke(task.thunk, &.{});
            }
        };
        var results: [count]Value = undefined;
        const pool = self.pool;
        if (pool == null or pool.?.worker_count == 0) {
            for (thunks, &results) |thunk, *result| result.* = self.invoke(thunk, &.{});
            return results;
        }
        var tasks: [count]Task = undefined;
        var jobs: [count]Job = undefined;
        for (thunks, &tasks, &jobs) |thunk, *task, *job| {
            task.* = .{ .context = Context.init(std.heap.page_allocator), .thunk = thunk };
            task.context.pool = pool;
            task.context.shared_allocator = self.allocator();
            job.* = .{ .run = Task.run, .data = task };
        }
        // Keep the first task on this thread, and expose the remaining siblings.
        // Waiting threads help execute queued work, including nested batches.
        for (jobs[1..]) |*job| pool.?.submit(job);
        Task.run(&tasks[0]);
        for (jobs[1..]) |*job| pool.?.wait(job);
        for (&tasks, &results) |*task, *result| {
            result.* = task.result;
            self.calls += task.context.calls;
            self.allocated += task.context.allocated;
            task.context.deinit();
        }
        return results;
    }
    pub fn fromCodepoints(self: *Context, points: []const u32) Value {
        const result = self.allocate(u32, points.len + 1);
        @memcpy(result[0..points.len], points);
        result[points.len] = 0xffffffff;
        return pointer(.string, result.ptr);
    }
    pub fn string(self: *Context, bytes: []const u8) Value {
        var it = (std.unicode.Utf8View.init(bytes) catch @panic("invalid UTF-8 string")).iterator();
        const points = self.allocate(u32, bytes.len + 1);
        var i: usize = 0;
        while (it.nextCodepoint()) |cp| : (i += 1) points[i] = cp;
        points[i] = 0xffffffff;
        return pointer(.string, points.ptr);
    }
    pub fn utf8(self: *Context, value: Value) []const u8 {
        const bytes = self.allocate(u8, length(value, .SCon) * 4);
        var n: usize = 0;
        var cursor = value;
        while (tag(cursor) == .SCon) : (cursor = field(cursor, 1)) {
            const count = std.unicode.utf8Encode(@intCast(field(cursor, 0) & mask), bytes[n..][0..4]) catch @panic("invalid Unicode scalar");
            n += count;
        }
        return bytes[0..n];
    }
    pub fn concat(self: *Context, a: Value, b: Value) Value {
        const result = self.allocate(u32, length(a, .SCon) + length(b, .SCon) + 1);
        var i: usize = 0;
        for ([_]Value{ a, b }) |start| {
            var cursor = start;
            while (tag(cursor) == .SCon) : (cursor = field(cursor, 1)) {
                result[i] = @truncate(field(cursor, 0));
                i += 1;
            }
        }
        result[i] = 0xffffffff;
        return pointer(.string, result.ptr);
    }
    fn reverse(self: *Context, value: Value, suffix: Value, cons: Tag) Value {
        var result = suffix;
        var cursor = value;
        while (tag(cursor) == cons) : (cursor = field(cursor, 1)) result = self.node(cons, &.{ field(cursor, 0), result });
        return result;
    }
    fn append(self: *Context, a: Value, b: Value) Value {
        const count = length(a, .Cons);
        // Temporary storage shares the request arena; it is freed by Context.deinit.
        // zig-analyzer: disable-next-line unreleased-allocation
        const items = self.allocate(Value, count);
        var cursor = a;
        for (items) |*item| {
            item.* = field(cursor, 0);
            cursor = field(cursor, 1);
        }
        var result = b;
        var i = count;
        while (i > 0) {
            i -= 1;
            result = self.node(.Cons, &.{ items[i], result });
        }
        return result;
    }
    fn take(self: *Context, value: Value, count: u64) Value {
        var cursor = value;
        var n = count;
        var result = empty(.Nil);
        while (n > 0 and tag(cursor) == .Cons) : (n -= 1) {
            result = self.node(.Cons, &.{ field(cursor, 0), result });
            cursor = field(cursor, 1);
        }
        return self.reverse(result, empty(.Nil), .Cons);
    }
    pub fn arrayRepeat(self: *Context, value: Value, count: u64) Value {
        const fields = self.allocate(Value, @intCast(count + 1));
        const h: *Header = @ptrCast(fields.ptr);
        h.* = .{ .identity = 0, .length = @intCast(count) };
        @memset(fields[1..], value);
        return pointer(.array, fields.ptr);
    }
    pub fn arrayWords(self: *Context, words: []const u32) Value {
        const result = self.arrayRepeat(word(0), words.len);
        for (objectFields(result), words) |*destination, source| destination.* = word(source);
        return result;
    }
    fn sort(self: *Context, values: Value, less: Value) Value {
        const n = length(values, .Cons);
        if (n < 2) return values;
        // Both merge buffers share the request arena, including all error paths.
        // zig-analyzer: disable-next-line unreleased-allocation
        var a = self.allocate(Value, n);
        // zig-analyzer: disable-next-line unreleased-allocation
        var b = self.allocate(Value, n);
        var cursor = values;
        for (a) |*item| {
            item.* = field(cursor, 0);
            cursor = field(cursor, 1);
        }
        var width: usize = 1;
        while (width < n) : (width = std.math.mul(usize, width, 2) catch n) {
            var start: usize = 0;
            while (start < n) {
                var i = start;
                const mid = start + @min(width, n - start);
                var j = mid;
                const end = mid + @min(width, n - mid);
                var at = start;
                while (i < mid and j < end) : (at += 1) {
                    if (truth(self.invoke(less, &.{ a[i], a[j] }))) {
                        b[at] = a[i];
                        i += 1;
                    } else {
                        b[at] = a[j];
                        j += 1;
                    }
                }
                while (i < mid) : (i += 1) {
                    b[at] = a[i];
                    at += 1;
                }
                while (j < end) : (j += 1) {
                    b[at] = a[j];
                    at += 1;
                }
                start = end;
            }
            const tmp = a;
            a = b;
            b = tmp;
        }
        var result = empty(.Nil);
        var i = n;
        while (i > 0) {
            i -= 1;
            result = self.node(.Cons, &.{ a[i], result });
        }
        return result;
    }
    fn merge(self: *Context, less: Value, state: Value) Value {
        var reversed = field(state, 0);
        var a = field(field(state, 1), 0);
        var b = field(field(state, 1), 1);
        while (tag(a) == .Cons and tag(b) == .Cons) {
            if (truth(self.invoke(less, &.{ field(a, 0), field(b, 0) }))) {
                reversed = self.node(.Cons, &.{ field(a, 0), reversed });
                a = field(a, 1);
            } else {
                reversed = self.node(.Cons, &.{ field(b, 0), reversed });
                b = field(b, 1);
            }
        }
        return self.reverse(reversed, if (tag(a) == .Nil) b else a, .Cons);
    }
    fn bit(key: Value, position: u64) bool {
        const suffix = drop(key, position / 33, .SCon);
        if (tag(suffix) == .SNil) return false;
        const offset = position % 33;
        if (offset == 0) return true;
        const cp: u32 = @truncate(field(suffix, 0));
        return (cp >> @as(u5, @intCast(32 - offset))) & 1 != 0;
    }
    fn difference(a: Value, b: Value) ?u64 {
        var x = a;
        var y = b;
        var at: u64 = 0;
        while (tag(x) == .SCon and tag(y) == .SCon) : (at += 33) {
            const p: u32 = @truncate(field(x, 0));
            const q: u32 = @truncate(field(y, 0));
            if (p != q) return at + 1 + @clz(p ^ q);
            x = field(x, 1);
            y = field(y, 1);
        }
        return if (tag(x) == tag(y)) null else at;
    }
    fn replaceMap(self: *Context, root: Value, key: Value, value: Value) Value {
        if (tag(root) == .MLeaf) return self.node(.MLeaf, &.{ key, value });
        const position = field(root, 0);
        var left = field(root, 1);
        var right = field(root, 2);
        if (bit(key, toNat(position))) right = self.replaceMap(right, key, value) else left = self.replaceMap(left, key, value);
        return self.node(.MNode, &.{ position, left, right });
    }
    fn insertMap(self: *Context, root: Value, key: Value, value: Value, position: u64) Value {
        if (tag(root) == .MNode and toNat(field(root, 0)) < position) {
            const at = field(root, 0);
            var left = field(root, 1);
            var right = field(root, 2);
            if (bit(key, toNat(at))) right = self.insertMap(right, key, value, position) else left = self.insertMap(left, key, value, position);
            return self.node(.MNode, &.{ at, left, right });
        }
        const leaf = self.node(.MLeaf, &.{ key, value });
        return self.node(.MNode, &.{ nat(position), if (bit(key, position)) root else leaf, if (bit(key, position)) leaf else root });
    }
    pub fn mapSet(self: *Context, root: Value, key: Value, value: Value) Value {
        if (tag(root) == .MTip) return self.node(.MLeaf, &.{ key, value });
        var leaf = root;
        while (tag(leaf) == .MNode) leaf = field(leaf, if (bit(key, toNat(field(leaf, 0)))) 2 else 1);
        if (difference(key, field(leaf, 0))) |position| return self.insertMap(root, key, value, position);
        return self.replaceMap(root, key, value);
    }
    pub fn mapGet(root: Value, key: Value) ?Value {
        var node_value = root;
        while (tag(node_value) == .MNode) node_value = field(node_value, if (bit(key, toNat(field(node_value, 0)))) 2 else 1);
        if (tag(node_value) == .MLeaf and stringEqual(key, field(node_value, 0))) return field(node_value, 1);
        return null;
    }
    fn mapList(self: *Context, root: Value, suffix: Value, keys: bool) Value {
        return switch (tag(root)) {
            .MTip => suffix,
            .MLeaf => self.node(.Cons, &.{ field(root, if (keys) 0 else 1), suffix }),
            .MNode => self.mapList(field(root, 1), self.mapList(field(root, 2), suffix, keys), keys),
            else => @panic("invalid map"),
        };
    }
    fn mapUnion(self: *Context, left: Value, right: Value) Value {
        return switch (tag(left)) {
            .MTip => right,
            .MLeaf => self.mapSet(right, field(left, 0), field(left, 1)),
            .MNode => self.mapUnion(field(left, 1), self.mapUnion(field(left, 2), right)),
            else => @panic("invalid map union"),
        };
    }
    fn numberString(self: *Context, number: u64) Value {
        var buf: [32]u8 = undefined;
        return self.string(std.fmt.bufPrint(&buf, "{d}", .{number}) catch unreachable);
    }
    fn floatToWord(value: f32) u32 {
        if (!(value > 0)) return 0;
        if (value >= 4294967296.0) return 0xffffffff;
        return @intFromFloat(@trunc(value));
    }
    pub fn primitive(self: *Context, op: Primitive, args: []const Value) Value {
        const a: Value = if (args.len == 0) erased else args[0];
        const b: Value = if (args.len < 2) erased else args[1];
        return switch (op) {
            .Bool_and => boolean(truth(a) and truth(b)),
            .Bool_or => boolean(truth(a) or truth(b)),
            .Bool_xor => boolean(truth(a) != truth(b)),
            .Bool_not => boolean(!truth(a)),
            .Bool_pick => if (truth(b)) args[2] else args[3],
            .Char_is_eq => boolean(a == b),
            .Char_to_u32 => word(@truncate(a)),
            .Nat_add, .U32_add, .F32_add => numeric(.add, a, b),
            .Nat_sub, .U32_sub, .F32_sub => numeric(.sub, a, b),
            .Nat_mul, .U32_mul, .F32_mul => numeric(.mul, a, b),
            .Nat_div, .U32_div, .F32_div => numeric(.div, a, b),
            .Nat_mod => nat(if (toNat(b) == 0) toNat(a) else toNat(a) % toNat(b)),
            .U32_mod => word(if (toWord(b) == 0) 0 else toWord(a) % toWord(b)),
            .Nat_min => nat(@min(toNat(a), toNat(b))),
            .Nat_max => nat(@max(toNat(a), toNat(b))),
            .Nat_is_eq, .U32_is_eq => boolean(a == b),
            .Nat_is_ne, .U32_is_ne => boolean(a != b),
            .Nat_is_lt, .U32_is_lt => boolean(a < b),
            .Nat_is_le, .U32_is_le => boolean(a <= b),
            .Nat_is_gt, .U32_is_gt => boolean(a > b),
            .Nat_is_ge, .U32_is_ge => boolean(a >= b),
            .Nat_cmp, .U32_cmp => compareResult(std.math.order(a, b)),
            .Nat_show => self.numberString(toNat(a)),
            .U32_show => self.numberString(toWord(a)),
            .Nat_read => blk: {
                const text = self.utf8(a);
                if (text.len == 0) break :blk empty(.None);
                var value: u64 = 0;
                for (text) |c| {
                    if (c < '0' or c > '9') break :blk empty(.None);
                    const digit: u64 = c - '0';
                    if (value > (mask - digit) / 10) break :blk empty(.None);
                    value = value * 10 + digit;
                }
                break :blk self.node(.Some, &.{nat(value)});
            },
            .U32_and => word(toWord(a) & toWord(b)),
            .U32_or => word(toWord(a) | toWord(b)),
            .U32_from_nat => word(@truncate(toNat(a))),
            .U32_to_nat => nat(toWord(a)),
            .U32_to_f32 => float(@floatFromInt(toWord(a))),
            .U32_shln => word(if (toNat(b) >= 32) 0 else toWord(a) << @as(u5, @intCast(toNat(b)))),
            .U32_shrn => word(if (toNat(b) >= 32) 0 else toWord(a) >> @as(u5, @intCast(toNat(b)))),
            .U32_shr => word(toWord(a) >> 1),
            .F32_abs => float(@abs(toFloat(a))),
            .F32_neg => float(-toFloat(a)),
            .F32_floor => float(@floor(toFloat(a))),
            .F32_ceil => float(@ceil(toFloat(a))),
            .F32_trunc => float(@trunc(toFloat(a))),
            .F32_sqrt => float(@sqrt(toFloat(a))),
            .F32_bits => word(@truncate(a)),
            .F32_to_u32 => word(floatToWord(toFloat(a))),
            .F32_is_eq => boolean(toFloat(a) == toFloat(b)),
            .F32_is_ne => boolean(toFloat(a) != toFloat(b)),
            .F32_is_lt => boolean(toFloat(a) < toFloat(b)),
            .F32_is_le => boolean(toFloat(a) <= toFloat(b)),
            .F32_is_gt => boolean(toFloat(a) > toFloat(b)),
            .F32_is_ge => boolean(toFloat(a) >= toFloat(b)),
            .F32_read => blk: {
                const value = std.fmt.parseFloat(f32, self.utf8(a)) catch break :blk empty(.None);
                break :blk self.node(.Some, &.{float(value)});
            },
            .Maybe_is_none => boolean(tag(args[2]) == .None),
            .Maybe_is_some => boolean(tag(args[2]) == .Some),
            .Maybe_or => if (tag(args[2]) == .Some) args[2] else args[3],
            .List_is_empty => boolean(tag(args[2]) == .Nil),
            .List_length => nat(length(args[2], .Cons)),
            .List_reverse => self.reverse(args[2], empty(.Nil), .Cons),
            .List_reverse_go => self.reverse(args[2], args[3], .Cons),
            .List_append => self.append(args[2], args[3]),
            .List_drop => drop(args[2], toNat(args[3]), .Cons),
            .List_take => self.take(args[2], toNat(args[3])),
            .List_sort => self.sort(args[2], b),
            .List_merge_go => self.merge(b, args[3]),
            .List_replicate => blk: {
                var n = toNat(args[1]);
                var result = empty(.Nil);
                while (n > 0) : (n -= 1) result = self.node(.Cons, &.{ args[2], result });
                break :blk result;
            },
            .String_is_lt => boolean(stringOrder(a, b) == .lt),
            .String_is_le => boolean(stringOrder(a, b) != .gt),
            .String_length => nat(length(a, .SCon)),
            .String_drop => drop(a, toNat(b), .SCon),
            .String_reverse => self.reverse(a, empty(.SNil), .SCon),
            .String_starts_with => blk: {
                var x = a;
                var y = b;
                while (tag(y) == .SCon) {
                    if (tag(x) != .SCon or field(x, 0) != field(y, 0)) break :blk boolean(false);
                    x = field(x, 1);
                    y = field(y, 1);
                }
                break :blk boolean(true);
            },
            .String_split => blk: {
                var x = a;
                var current = empty(.SNil);
                var result = empty(.Nil);
                while (tag(x) == .SCon) : (x = field(x, 1)) {
                    if (field(x, 0) == b) {
                        result = self.node(.Cons, &.{ self.reverse(current, empty(.SNil), .SCon), result });
                        current = empty(.SNil);
                    } else current = self.node(.SCon, &.{ field(x, 0), current });
                }
                result = self.node(.Cons, &.{ self.reverse(current, empty(.SNil), .SCon), result });
                break :blk self.reverse(result, empty(.Nil), .Cons);
            },
            .String_join => blk: {
                var x = a;
                var result = empty(.SNil);
                var first = true;
                while (tag(x) == .Cons) : (x = field(x, 1)) {
                    if (!first) result = self.concat(result, b);
                    result = self.concat(result, field(x, 0));
                    first = false;
                }
                break :blk result;
            },
            .Map_new, .Set_new => empty(.MTip),
            .Map_set => self.mapSet(args[2], args[3], args[4]),
            .Map_values => self.mapList(args[2], empty(.Nil), false),
            .Map_union => self.mapUnion(args[3], args[2]),
            .Set_add => self.mapSet(a, b, empty(.Unit)),
            .Set_to_list => self.mapList(a, empty(.Nil), true),
            .Set_size => nat(length(self.mapList(a, empty(.Nil), true), .Cons)),
            .Set_from_list => blk: {
                var x = a;
                var result = empty(.MTip);
                while (tag(x) == .Cons) : (x = field(x, 1)) result = self.mapSet(result, field(x, 0), empty(.Unit));
                break :blk result;
            },
            .Array_new => self.arrayRepeat(args[2], @as(u64, 1) << @as(u6, @intCast(toNat(b)))),
            .Array_get => blk: {
                assert(kind(b) == .array);
                const items = objectFields(b);
                break :blk self.node(.Pair, &.{ b, items[toWord(args[2])] });
            },
            .Array_set => blk: {
                assert(kind(b) == .array);
                const items = objectFields(b);
                items[toWord(args[2])] = args[3];
                break :blk b;
            },
        };
    }

    /// Copy a retained graph into this arena without recursive traversal.
    /// Pointer sharing is preserved, so a session never retains old arenas.
    pub fn retain(self: *Context, root: Value) Value {
        const Work = struct { source: Value, destination: *Value };
        var memo = std.AutoHashMap(Value, Value).init(std.heap.page_allocator);
        defer memo.deinit();
        var work: std.ArrayList(Work) = .empty;
        defer work.deinit(std.heap.page_allocator);
        var result: Value = undefined;
        work.append(std.heap.page_allocator, .{ .source = root, .destination = &result }) catch @panic("out of memory");
        while (work.pop()) |task| {
            const source = task.source;
            const k = kind(source);
            if (k != .object and k != .closure and k != .array and k != .string) {
                task.destination.* = source;
                continue;
            }
            if (memo.get(source)) |v| {
                task.destination.* = v;
                continue;
            }
            if (k == .string) {
                const points = ptr([*]const u32, source);
                var n: usize = 0;
                while (points[n] != 0xffffffff) : (n += 1) {}
                const v = self.fromCodepoints(points[0..n]);
                memo.put(source, v) catch @panic("out of memory");
                task.destination.* = v;
                continue;
            }
            const h = ptr(*const Header, source);
            const fields = objectFields(source);
            const value = self.rawNode(k, h.identity, fields);
            memo.put(source, value) catch @panic("out of memory");
            task.destination.* = value;
            for (fields, objectFields(value)) |child, *destination| work.append(std.heap.page_allocator, .{ .source = child, .destination = destination }) catch @panic("out of memory");
        }
        return result;
    }
};

test "numeric values preserve binary32 and unsigned wrapping" {
    try std.testing.expectEqual(@as(u32, 0), toWord(numeric(.add, word(0xffffffff), word(1))));
    try std.testing.expectEqual(@as(u64, 0), toNat(numeric(.sub, nat(0), nat(1))));
    try std.testing.expectEqual(@as(f32, 16777216), toFloat(numeric(.add, float(16777216), float(1))));
}
test "Unicode strings, persistent maps and retained sharing" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();
    const a = literal("héllo 🌍");
    const b = ctx.string("héllo 🌍");
    try std.testing.expect(stringEqual(a, b));
    var root = empty(.MTip);
    const keys = [_]Value{ literal(""), literal("a"), literal("ab"), literal("aa"), literal("😀"), literal("é") };
    for (keys, 0..) |key, i| root = ctx.mapSet(root, key, word(@intCast(i)));
    for (keys, 0..) |key, i| try std.testing.expectEqual(word(@intCast(i)), Context.mapGet(root, key).?);
    const original = root;
    root = ctx.mapSet(root, literal("a"), word(42));
    try std.testing.expectEqual(word(1), Context.mapGet(original, literal("a")).?);
    const shared = ctx.node(.Pair, &.{ root, root });
    var retained = Context.init(std.testing.allocator);
    defer retained.deinit();
    const copy = retained.retain(shared);
    try std.testing.expectEqual(field(copy, 0), field(copy, 1));
    try std.testing.expectEqual(word(42), Context.mapGet(field(copy, 0), literal("a")).?);
}

test "right-biased map union and strict bounded decimal naturals" {
    var ctx = Context.init(std.testing.allocator);
    defer ctx.deinit();
    const left = ctx.mapSet(empty(.MTip), literal("same"), word(1));
    const right = ctx.mapSet(empty(.MTip), literal("same"), word(2));
    const merged = ctx.primitive(.Map_union, &.{ erased, erased, left, right });
    try std.testing.expectEqual(word(2), Context.mapGet(merged, literal("same")).?);
    try std.testing.expectEqual(nat(7), ctx.primitive(.Nat_mod, &.{ nat(7), nat(0) }));
    for ([_]Value{ literal(""), literal("+1"), literal("1_0"), literal("-1"), literal("281474976710656") }) |text| {
        try std.testing.expectEqual(empty(.None), ctx.primitive(.Nat_read, &.{text}));
    }
    try std.testing.expectEqual(nat(mask), field(ctx.primitive(.Nat_read, &.{literal("281474976710655")}), 0));
}
