//! Pure, bounded native readers. Scratch graphs never escape a generation.
const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Kind = enum { json, catalog, text, tunables };
pub const Issue = struct { start: u32 = 0, end: u32 = 0, code: []const u8, message: []const u8 };
pub const Result = union(enum) { source: []u8, issue: Issue };
const Error = Allocator.Error || error{InvalidAsset};
const limit = 16 * 1024 * 1024;

pub fn deinit(allocator: Allocator, result: *Result) void {
    switch (result.*) {
        .source => |source| allocator.free(source),
        .issue => |issue| allocator.free(issue.message),
    }
    result.* = undefined;
}

pub fn generate(allocator: Allocator, kind: Kind, bytes: []const u8) Allocator.Error!Result {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var reader: Reader = .{ .a = arena.allocator(), .input = bytes };
    reader.run(kind) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidAsset => {
            var issue = reader.issue.?;
            issue.message = try allocator.dupe(u8, issue.message);
            return .{ .issue = issue };
        },
    };
    const length = std.math.add(usize, reader.header.items.len, reader.body.items.len) catch unreachable;
    const source = try allocator.alloc(u8, length);
    @memcpy(source[0..reader.header.items.len], reader.header.items);
    @memcpy(source[reader.header.items.len..], reader.body.items);
    return .{ .source = source };
}

const Tag = enum { null_value, boolean, number, string, array, object };
const Member = struct { name: []const u8 = "", value: u32 };
const Node = struct {
    tag: Tag,
    start: u32,
    end: u32 = 0,
    text: []const u8 = "",
    number: f64 = 0,
    boolean: bool = false,
    wellformed: bool = true,
    members: []Member = &.{},
    shape: u32 = 0,
};
const ShapeTag = enum { unit, boolean, u32_value, f32_value, array, tuple, record, utf8 };
const Field = struct { name: []const u8, shape: u32 };
const Shape = struct { tag: ShapeTag, name: []const u8 = "", fields: []const Field = &.{}, elements: []const u32 = &.{}, emitted: bool = false };
const Text = std.ArrayList(u8);
const Reader = struct {
    a: Allocator,
    input: []const u8,
    at: usize = 0,
    nodes: std.ArrayList(Node) = .empty,
    shapes: std.ArrayList(Shape) = .empty,
    interned: std.StringHashMapUnmanaged(u32) = .empty,
    serial: usize = 0,
    visits: usize = 0,
    header: Text = .empty,
    body: Text = .empty,
    issue: ?Issue = null,
    string_wellformed: bool = true,

    fn fail(self: *Reader, start: usize, end: usize, code: []const u8, message: []const u8) Error {
        self.issue = .{ .start = @intCast(@min(start, self.input.len)), .end = @intCast(@min(@max(start, end), self.input.len)), .code = code, .message = message };
        return error.InvalidAsset;
    }
    fn problem(self: *Reader, id: u32, code: []const u8, message: []const u8) Error {
        const node = self.nodes.items[id];
        return self.fail(node.start, node.end, code, message);
    }
    fn budget(self: *Reader, depth: usize) Error!void {
        self.visits += 1;
        if (depth > 128 or self.visits > 1_000_000) return self.fail(self.at, self.at, "asset_limit", "Asset exceeds the structural budget");
    }
    fn put(self: *Reader, out: *Text, text: []const u8) Error!void {
        if (text.len > limit or out.items.len > limit - text.len) return self.fail(0, self.input.len, "asset_limit", "Generated asset module exceeds 16 MiB");
        try out.appendSlice(self.a, text);
    }
    fn integer(self: *Reader, out: *Text, value: anytype) Error!void {
        var buffer: [32]u8 = undefined;
        try self.put(out, std.mem.print(&buffer, "{d}", .{value}) catch unreachable);
    }
    fn float32(self: *Reader, out: *Text, value: f64) Error!void {
        const rounded: f32 = @floatCast(value);
        const magnitude: f64 = @abs(@as(f64, rounded));
        const negative = std.math.signbit(rounded);
        if (negative) try self.put(out, "(-");
        var buffer: [400]u8 = undefined;
        var mode: std.fmt.float.Mode = .decimal;
        if (magnitude >= 1e21 or (magnitude != 0 and magnitude < 1e-6)) mode = .scientific;
        const text = std.fmt.float.render(&buffer, magnitude, .{ .mode = mode }) catch unreachable;
        if (std.mem.findScalar(u8, text, 'e')) |exponent| {
            try self.put(out, text[0 .. exponent + 1]);
            if (text[exponent + 1] != '-') try self.put(out, "+");
            try self.put(out, text[exponent + 1 ..]);
        } else {
            try self.put(out, text);
            if (std.mem.findScalar(u8, text, '.') == null) try self.put(out, ".0");
        }
        if (negative) try self.put(out, ")");
    }
    fn skip(self: *Reader) void {
        while (self.at < self.input.len and std.mem.findScalar(u8, " \t\r\n", self.input[self.at]) != null) self.at += 1;
    }
    fn take(self: *Reader, byte: u8) bool {
        self.skip();
        if (self.at == self.input.len or self.input[self.at] != byte) return false;
        self.at += 1;
        return true;
    }
    fn syntax(self: *Reader) Error {
        return self.fail(self.at, self.at + 1, "asset_json", "Malformed JSON asset");
    }
    fn string(self: *Reader) Error![]const u8 {
        const start = self.at;
        self.string_wellformed = true;
        if (!self.take('"')) return self.syntax();
        while (self.at < self.input.len) {
            const byte = self.input[self.at];
            self.at += 1;
            if (byte == '"') {
                const parsed = std.json.parseFromSlice([]const u8, self.a, self.input[start..self.at], .{ .allocate = .alloc_always }) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => try self.repairString(start, self.at),
                };
                defer parsed.deinit();
                if (!std.unicode.utf8ValidateSlice(parsed.value)) return self.fail(start, self.at, "asset_unicode", "JSON strings must be well-formed Unicode");
                return self.a.dupe(u8, parsed.value);
            }
            if (byte == '\\') {
                if (self.at == self.input.len) return self.syntax();
                self.at += 1;
            } else if (byte < 0x20) return self.syntax();
        }
        return self.syntax();
    }
    // JSON.parse permits unpaired UTF-16 halves. Defer their rejection until
    // inference so overwritten members disappear; font readers see one glyph.
    fn repairString(self: *Reader, start: usize, end: usize) Error!std.json.Parsed([]const u8) {
        const source = self.input[start..end];
        var repaired: Text = .empty;
        defer repaired.deinit(self.a);
        var index: usize = 0;
        while (index < source.len) {
            if (source[index] == '\\' and source.len - index >= 2) {
                if (source[index + 1] == 'u' and source.len - index >= 6) {
                    const half = std.fmt.parseInt(u16, source[index + 2 ..][0..4], 16) catch return self.fail(start, end, "asset_json", "Malformed JSON string");
                    if (half >= 0xd800 and half <= 0xdfff) {
                        if (half < 0xdc00 and source.len - index >= 12 and std.mem.startsWith(u8, source[index + 6 ..], "\\u")) {
                            const low = std.fmt.parseInt(u16, source[index + 8 ..][0..4], 16) catch 0;
                            if (low >= 0xdc00 and low <= 0xdfff) {
                                try repaired.appendSlice(self.a, source[index..][0..12]);
                                index += 12;
                                continue;
                            }
                        }
                        self.string_wellformed = false;
                        try repaired.appendSlice(self.a, "\\ufffd");
                        index += 6;
                        continue;
                    }
                }
                try repaired.appendSlice(self.a, source[index..][0..2]);
                index += 2;
                continue;
            }
            try repaired.append(self.a, source[index]);
            index += 1;
        }
        if (self.string_wellformed) return self.fail(start, end, "asset_json", "Malformed JSON string");
        return std.json.parseFromSlice([]const u8, self.a, repaired.items, .{ .allocate = .alloc_always }) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => self.fail(start, end, "asset_json", "Malformed JSON string"),
        };
    }
    fn parse(self: *Reader, depth: usize) Error!u32 {
        try self.budget(depth);
        self.skip();
        const start = self.at;
        if (start == self.input.len) return self.syntax();
        var node: Node = .{ .tag = .null_value, .start = @intCast(start) };
        const byte = self.input[self.at];
        if (byte == '"') {
            node.tag = .string;
            node.text = try self.string();
            node.wellformed = self.string_wellformed;
        } else if (byte == '[' or byte == '{') {
            self.at += 1;
            node.tag = .array;
            var close: u8 = ']';
            if (byte == '{') {
                node.tag = .object;
                close = '}';
            }
            var members: std.ArrayList(Member) = .empty;
            defer members.deinit(self.a);
            var keys: std.StringHashMapUnmanaged(usize) = .empty;
            defer keys.deinit(self.a);
            if (!self.take(close)) {
                while (true) {
                    var name: []const u8 = "";
                    if (node.tag == .object) {
                        self.skip();
                        name = try self.string();
                        if (!self.take(':')) return self.syntax();
                    }
                    const child = try self.parse(depth + 1);
                    if (node.tag == .object) {
                        const found = try keys.getOrPut(self.a, name);
                        if (found.found_existing) members.items[found.value_ptr.*].value = child else {
                            found.value_ptr.* = members.items.len;
                            try members.append(self.a, .{ .name = name, .value = child });
                        }
                    } else try members.append(self.a, .{ .value = child });
                    if (self.take(close)) break;
                    if (!self.take(',')) return self.syntax();
                }
            }
            node.members = try members.toOwnedSlice(self.a);
        } else if (byte == 't' or byte == 'f' or byte == 'n') {
            var token: []const u8 = "null";
            if (byte == 't') {
                token = "true";
                node.tag = .boolean;
                node.boolean = true;
            }
            if (byte == 'f') {
                token = "false";
                node.tag = .boolean;
            }
            if (!std.mem.startsWith(u8, self.input[self.at..], token)) return self.syntax();
            self.at += token.len;
        } else {
            node.tag = .number;
            if (self.input[self.at] == '-') self.at += 1;
            if (self.at == self.input.len) return self.syntax();
            if (self.input[self.at] == '0') self.at += 1 else {
                if (self.input[self.at] < '1' or self.input[self.at] > '9') return self.syntax();
                while (self.at < self.input.len and std.ascii.isDigit(self.input[self.at])) self.at += 1;
            }
            if (self.at < self.input.len and self.input[self.at] == '.') {
                self.at += 1;
                const digits = self.at;
                while (self.at < self.input.len and std.ascii.isDigit(self.input[self.at])) self.at += 1;
                if (digits == self.at) return self.syntax();
            }
            if (self.at < self.input.len and (self.input[self.at] == 'e' or self.input[self.at] == 'E')) {
                self.at += 1;
                if (self.at < self.input.len and (self.input[self.at] == '+' or self.input[self.at] == '-')) self.at += 1;
                const digits = self.at;
                while (self.at < self.input.len and std.ascii.isDigit(self.input[self.at])) self.at += 1;
                if (digits == self.at) return self.syntax();
            }
            node.number = std.fmt.parseFloat(f64, self.input[start..self.at]) catch return self.syntax();
        }
        node.end = @intCast(self.at);
        const id: u32 = @intCast(self.nodes.items.len);
        try self.nodes.append(self.a, node);
        return id;
    }
    fn identifier(self: *Reader, id: u32, name: []const u8) Error!void {
        const keywords = " const let type data effect is func do use return yield break for ever continue in case of if then else as import infix infixl infixr self where and or true false ";
        var valid = name.len > 0 and !std.mem.eql(u8, name, "_");
        if (valid) valid = std.ascii.isLower(name[0]) or name[0] == '_';
        for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') {
            valid = false;
            break;
        };
        var iter = std.mem.tokenizeScalar(u8, keywords, ' ');
        while (iter.next()) |keyword| if (std.mem.eql(u8, name, keyword)) {
            valid = false;
            break;
        };
        if (!valid) return self.problem(id, "asset_identifier", try self.a.print("Invalid Blot value/field name: {s}", .{boundedUtf8Prefix(name, 256)}));
    }
    fn member(self: *Reader, id: u32, name: []const u8) ?u32 {
        for (self.nodes.items[id].members) |item| if (std.mem.eql(u8, item.name, name)) return item.value;
        return null;
    }
    fn object(self: *Reader, id: u32) Error!void {
        if (self.nodes.items[id].tag != .object) return self.problem(id, "asset_shape", "Expected a JSON object");
    }
    fn run(self: *Reader, kind: Kind) Error!void {
        if (self.input.len > limit) return self.fail(0, self.input.len, "asset_limit", "Asset input exceeds 16 MiB");
        if (!std.unicode.utf8ValidateSlice(self.input)) {
            var at: usize = 0;
            while (at < self.input.len) {
                const length = std.unicode.utf8ByteSequenceLength(self.input[at]) catch break;
                if (length > self.input.len - at) break;
                _ = decodePoint(self.input[at..][0..length]) catch break;
                at += length;
            }
            return self.fail(at, at + 1, "asset_unicode", "Asset input must be UTF-8");
        }
        if (std.mem.startsWith(u8, self.input, "\xef\xbb\xbf")) self.at = 3;
        const root = try self.parse(0);
        self.skip();
        if (self.at != self.input.len) return self.syntax();
        self.visits = 0;
        switch (kind) {
            .json => try self.json(root),
            .catalog => try self.catalog(root),
            .text => try self.textModule(root),
            .tunables => try self.tunables(root),
        }
        if (self.header.items.len > limit - self.body.items.len) return self.problem(root, "asset_limit", "Generated asset module exceeds 16 MiB");
    }
    fn infer(self: *Reader, id: u32, depth: usize) Error!u32 {
        try self.budget(depth);
        const node = self.nodes.items[id];
        var shape_id: u32 = 0;
        switch (node.tag) {
            .null_value => shape_id = 0,
            .boolean => shape_id = 1,
            .number => {
                const value = node.number;
                if (std.math.isFinite(value) and @trunc(value) == value and @abs(value) > 9007199254740991) return self.problem(id, "asset_number", "JSON integer exceeds exact host representation");
                shape_id = 3;
                if (@trunc(value) == value and value >= 0 and value <= 4294967295 and !(value == 0 and std.math.signbit(value))) shape_id = 2;
                const single: f32 = @floatCast(value);
                if (!std.math.isFinite(single)) return self.problem(id, "asset_number", "Asset number does not fit finite F32");
            },
            .string => {
                if (!node.wellformed) return self.problem(id, "asset_unicode", "JSON strings must be well-formed Unicode");
                shape_id = 4;
            },
            .array => {
                const elements = try self.a.alloc(u32, node.members.len);
                var homogeneous = elements.len > 0;
                for (node.members, 0..) |item, index| {
                    elements[index] = try self.infer(item.value, depth + 1);
                    if (elements[index] != elements[0]) homogeneous = false;
                }
                var shape: Shape = .{ .tag = .tuple, .elements = elements };
                if (homogeneous) {
                    shape.tag = .array;
                    shape.elements = elements[0..1];
                }
                shape_id = try self.intern(shape);
            },
            .object => {
                std.mem.sort(Member, node.members, {}, struct {
                    fn less(_: void, left: Member, right: Member) bool {
                        return std.mem.lessThan(u8, left.name, right.name);
                    }
                }.less);
                const fields = try self.a.alloc(Field, node.members.len);
                for (node.members, 0..) |item, index| {
                    try self.identifier(item.value, item.name);
                    fields[index] = .{ .name = item.name, .shape = try self.infer(item.value, depth + 1) };
                }
                var shape: Shape = .{ .tag = .record, .fields = fields };
                if (depth == 0) {
                    shape.name = "Data";
                    shape_id = @intCast(self.shapes.items.len);
                    try self.shapes.append(self.a, shape);
                } else shape_id = try self.intern(shape);
            },
        }
        self.nodes.items[id].shape = shape_id;
        return shape_id;
    }
    fn intern(self: *Reader, shape: Shape) Error!u32 {
        var key: Text = .empty;
        try self.put(&key, @tagName(shape.tag));
        for (shape.elements) |item| {
            try self.put(&key, ":");
            try self.integer(&key, item);
        }
        for (shape.fields) |field| {
            try self.put(&key, ":");
            try self.put(&key, field.name);
            try self.put(&key, "=");
            try self.integer(&key, field.shape);
        }
        const found = try self.interned.getOrPut(self.a, key.items);
        if (found.found_existing) return found.value_ptr.*;
        var named = shape;
        if (shape.tag == .record) {
            self.serial += 1;
            named.name = try self.a.print("JsonRecord{d}", .{self.serial});
        }
        const id: u32 = @intCast(self.shapes.items.len);
        try self.shapes.append(self.a, named);
        found.value_ptr.* = id;
        return id;
    }
    fn shapeType(self: *Reader, out: *Text, id: u32, depth: usize) Error!void {
        try self.budget(depth);
        const shape = self.shapes.items[id];
        switch (shape.tag) {
            .unit => try self.put(out, "Unit"),
            .boolean => try self.put(out, "Bool"),
            .u32_value => try self.put(out, "U32"),
            .f32_value => try self.put(out, "F32"),
            .utf8 => {
                if (!shape.emitted) {
                    try self.put(&self.header, "type Utf8 is data = $Utf8 { bytes: (Array U32) }\n");
                    self.shapes.items[id].emitted = true;
                }
                try self.put(out, "Utf8");
            },
            .array => {
                try self.put(out, "(Array ");
                try self.shapeType(out, shape.elements[0], depth + 1);
                try self.put(out, ")");
            },
            .tuple => {
                try self.put(out, "(");
                for (shape.elements, 0..) |element, index| {
                    if (index > 0) try self.put(out, ", ");
                    try self.shapeType(out, element, depth + 1);
                }
                if (shape.elements.len == 1) try self.put(out, ",");
                try self.put(out, ")");
            },
            .record => {
                if (!shape.emitted) {
                    var declaration: Text = .empty;
                    try self.put(&declaration, "type ");
                    try self.put(&declaration, shape.name);
                    try self.put(&declaration, " is data = $");
                    try self.put(&declaration, shape.name);
                    try self.put(&declaration, " { ");
                    for (shape.fields, 0..) |field, index| {
                        if (index > 0) try self.put(&declaration, ", ");
                        try self.put(&declaration, field.name);
                        try self.put(&declaration, ": ");
                        try self.shapeType(&declaration, field.shape, depth + 1);
                    }
                    try self.put(&declaration, " }\n");
                    try self.put(&self.header, declaration.items);
                    self.shapes.items[id].emitted = true;
                }
                try self.put(out, shape.name);
            },
        }
    }
    fn jsonValue(self: *Reader, out: *Text, id: u32, depth: usize) Error!void {
        try self.budget(depth);
        const node = self.nodes.items[id];
        const shape = self.shapes.items[node.shape];
        switch (node.tag) {
            .null_value => try self.put(out, "()"),
            .boolean => {
                if (node.boolean) try self.put(out, "true") else try self.put(out, "false");
            },
            .number => {
                if (node.shape == 2) try self.integer(out, @as(u32, @intFromFloat(node.number))) else try self.float32(out, node.number);
            },
            .string => {
                try self.put(out, "($Utf8 { bytes: #[");
                for (node.text, 0..) |byte, index| {
                    try self.budget(depth + 2);
                    if (index > 0) try self.put(out, ", ");
                    try self.integer(out, byte);
                }
                try self.put(out, "] })");
            },
            .array => {
                if (shape.tag == .array) try self.put(out, "#[") else try self.put(out, "(");
                for (node.members, 0..) |item, index| {
                    if (index > 0) try self.put(out, ", ");
                    try self.jsonValue(out, item.value, depth + 1);
                }
                if (shape.tag == .array) try self.put(out, "]") else {
                    if (node.members.len == 1) try self.put(out, ",");
                    try self.put(out, ")");
                }
            },
            .object => {
                try self.put(out, "($");
                try self.put(out, shape.name);
                try self.put(out, " { ");
                for (node.members, 0..) |item, index| {
                    if (index > 0) try self.put(out, ", ");
                    try self.put(out, item.name);
                    try self.put(out, ": ");
                    try self.jsonValue(out, item.value, depth + 1);
                }
                try self.put(out, " })");
            },
        }
    }
    fn json(self: *Reader, root: u32) Error!void {
        try self.shapes.appendSlice(self.a, &.{ .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32_value }, .{ .tag = .f32_value }, .{ .tag = .utf8 } });
        const shape = try self.infer(root, 0);
        self.visits = 0;
        var annotation: Text = .empty;
        try self.shapeType(&annotation, shape, 0);
        if (self.nodes.items[root].tag != .object) {
            try self.put(&self.header, "type Data = ");
            try self.put(&self.header, annotation.items);
            try self.put(&self.header, "\n");
        }
        try self.put(&self.body, "const value: ");
        try self.put(&self.body, annotation.items);
        try self.put(&self.body, " = ");
        try self.jsonValue(&self.body, root, 0);
        try self.put(&self.body, "\n");
    }
    fn recordStart(self: *Reader, name: []const u8, value: []const u8) Error!void {
        try self.put(&self.header, "type ");
        try self.put(&self.header, name);
        try self.put(&self.header, " is data = $");
        try self.put(&self.header, name);
        try self.put(&self.header, " { ");
        try self.put(&self.body, "const ");
        try self.put(&self.body, value);
        try self.put(&self.body, ": ");
        try self.put(&self.body, name);
        try self.put(&self.body, " = ($");
        try self.put(&self.body, name);
        try self.put(&self.body, " { ");
    }
    fn recordEnd(self: *Reader) Error!void {
        try self.put(&self.header, " }\n");
        try self.put(&self.body, " })\n");
    }
    fn emitField(self: *Reader, name: []const u8, shape: []const u8, index: usize) Error!void {
        if (index > 0) {
            try self.put(&self.header, ", ");
            try self.put(&self.body, ", ");
        }
        try self.put(&self.header, name);
        try self.put(&self.header, ": ");
        try self.put(&self.header, shape);
        try self.put(&self.body, name);
        try self.put(&self.body, ": ");
    }
    fn catalog(self: *Reader, root: u32) Error!void {
        try self.object(root);
        const categories = [_][]const u8{ "meshes", "materials", "sounds" };
        const names = [_][]const u8{ "Meshes", "Materials", "Sounds" };
        for (categories, names) |category, name| {
            try self.recordStart(name, category);
            if (self.member(root, category)) |list_id| {
                const list = self.nodes.items[list_id];
                if (list.tag != .null_value) {
                    if (list.tag != .array) return self.problem(list_id, "asset_catalog", "Catalog category must be a list of filenames");
                    var used: std.StringHashMapUnmanaged(void) = .empty;
                    for (list.members, 0..) |item, index| {
                        const file = self.nodes.items[item.value];
                        if (file.tag != .string) return self.problem(item.value, "asset_catalog", "Catalog filename must be text");
                        var basename = file.text;
                        for ([_][]const u8{ ".mesh.json", ".material.json" }) |suffix| if (std.mem.endsWith(u8, basename, suffix)) {
                            basename = basename[0 .. basename.len - suffix.len];
                            break;
                        };
                        for ([_][]const u8{ ".wav", ".ogg", ".json" }) |suffix| if (std.mem.endsWith(u8, basename, suffix)) {
                            basename = basename[0 .. basename.len - suffix.len];
                            break;
                        };
                        // JS's non-Unicode regexp replaces each UTF-16 code unit.
                        var field_name: Text = .empty;
                        var iterator = std.unicode.Utf8View.initUnchecked(basename).iterator();
                        while (iterator.nextCodepoint()) |point| {
                            var byte: u8 = '_';
                            if (point < 128 and (std.ascii.isAlphanumeric(@intCast(point)) or point == '_')) byte = @intCast(point);
                            try field_name.append(self.a, byte);
                            if (point > 0xffff) try field_name.append(self.a, '_');
                        }
                        try self.identifier(item.value, field_name.items);
                        const found = try used.getOrPut(self.a, field_name.items);
                        if (found.found_existing) return self.problem(item.value, "asset_catalog", try self.a.print("catalog {s}: two files share a name", .{category}));
                        try self.emitField(field_name.items, "U32", index);
                        try self.integer(&self.body, index);
                    }
                }
            }
            try self.recordEnd();
        }
    }
    fn points(self: *Reader, out: *Text, id: u32, name: []const u8, shown: bool) Error!void {
        const node = self.nodes.items[id];
        if (node.tag != .string) return self.problem(id, "asset_text", "Text must be a string or a list of strings");
        if (!shown) {
            var missing: Text = .empty;
            defer missing.deinit(self.a);
            var seen: std.AutoHashMapUnmanaged(u21, void) = .empty;
            defer seen.deinit(self.a);
            var scan = std.unicode.Utf8View.initUnchecked(node.text).iterator();
            while (scan.nextCodepointSlice()) |encoded| {
                const point = decodePoint(encoded) catch unreachable;
                if (!inFont(point) and missing.items.len < 512) {
                    const found = try seen.getOrPut(self.a, point);
                    if (!found.found_existing) try missing.appendSlice(self.a, encoded);
                }
            }
            if (missing.items.len > 0) return self.problem(id, "asset_font", try self.a.print("text {s}: the font has no {s}", .{ boundedUtf8Prefix(name, 256), missing.items }));
        }
        var iterator = std.unicode.Utf8View.initUnchecked(node.text).iterator();
        try self.put(out, "#[");
        var index: usize = 0;
        while (iterator.nextCodepoint()) |point| {
            try self.budget(1);
            var value: u21 = point;
            if (shown and !inFont(point)) value = 63;
            if (index > 0) try self.put(out, ", ");
            try self.integer(out, value);
            index += 1;
        }
        try self.put(out, "]");
    }
    fn textModule(self: *Reader, root: u32) Error!void {
        try self.object(root);
        try self.recordStart("Text", "text");
        for (self.nodes.items[root].members, 0..) |item, index| {
            try self.identifier(item.value, item.name);
            const node = self.nodes.items[item.value];
            if (node.tag == .string) {
                try self.emitField(item.name, "(Array U32)", index);
                try self.points(&self.body, item.value, item.name, false);
            } else {
                if (node.tag != .array) return self.problem(item.value, "asset_text", "Text must be a string or a list of strings");
                try self.emitField(item.name, "(Array (Array U32))", index);
                try self.put(&self.body, "#[");
                for (node.members, 0..) |line, line_index| {
                    if (line_index > 0) try self.put(&self.body, ", ");
                    try self.points(&self.body, line.value, item.name, false);
                }
                try self.put(&self.body, "]");
            }
        }
        try self.recordEnd();
    }
    fn tunableNumber(self: *Reader, id: u32, key: []const u8) Error!f64 {
        const value_id = self.member(id, key) orelse return self.problem(id, "asset_tunables", try self.a.print("{s} must be a finite number", .{key}));
        const node = self.nodes.items[value_id];
        const single: f32 = @floatCast(node.number);
        if (node.tag != .number or !std.math.isFinite(single)) return self.problem(value_id, "asset_tunables", try self.a.print("{s} must be a finite number", .{key}));
        return node.number;
    }
    fn shownSpan(self: *Reader, out: *Text, count: *u32, id: ?u32) Error![2]u32 {
        const start = count.*;
        if (id) |node| {
            var iterator = std.unicode.Utf8View.initUnchecked(self.nodes.items[node].text).iterator();
            while (iterator.nextCodepoint()) |point| {
                try self.budget(1);
                if (count.* != 0) try self.put(out, ", ");
                try self.integer(out, if (inFont(point)) point else 63);
                count.* += 1;
            }
        }
        return .{ start, count.* - start };
    }
    fn tunables(self: *Reader, root: u32) Error!void {
        const list_id = self.member(root, "tunables") orelse return self.problem(root, "asset_tunables", "tunables.json: expected { \"tunables\": [...] }");
        const list = self.nodes.items[list_id];
        if (self.nodes.items[root].tag != .object or list.tag != .array) return self.problem(root, "asset_tunables", "tunables.json: expected { \"tunables\": [...] }");
        var fields: std.StringHashMapUnmanaged(void) = .empty;
        defer fields.deinit(self.a);
        var ids: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer ids.deinit(self.a);
        var declarations: Text = .empty;
        var text: Text = .empty;
        var text_count: u32 = 0;
        try self.put(&text, "const declaration_text: Array U32 = #[");
        try self.put(&declarations, "const declarations: (Array Declaration) = #[");
        try self.recordStart("Tunables", "tunables");
        for (list.members, 0..) |item, index| {
            const id = item.value;
            try self.object(id);
            const name_id = self.member(id, "name") orelse return self.problem(id, "asset_tunables", "Tunable needs a name of lowercase words joined by dots");
            const name_node = self.nodes.items[name_id];
            if (name_node.tag != .string or !tunableName(name_node.text)) return self.problem(name_id, "asset_tunables", "Tunable needs a name of lowercase words joined by dots");
            for (self.nodes.items[id].members) |entry| {
                var known = false;
                for ([_][]const u8{ "name", "default", "min", "max", "step", "doc" }) |key| if (std.mem.eql(u8, key, entry.name)) {
                    known = true;
                    break;
                };
                if (!known) return self.problem(entry.value, "asset_tunables", try self.a.print("Unknown tunable field: {s}", .{boundedUtf8Prefix(entry.name, 256)}));
            }
            const initial = try self.tunableNumber(id, "default");
            const least = try self.tunableNumber(id, "min");
            const most = try self.tunableNumber(id, "max");
            if (!(@as(f32, @floatCast(least)) < @as(f32, @floatCast(most)))) return self.problem(id, "asset_tunables", "min must be below max");
            if (@as(f32, @floatCast(initial)) < @as(f32, @floatCast(least)) or @as(f32, @floatCast(initial)) > @as(f32, @floatCast(most))) return self.problem(id, "asset_tunables", "Tunable default is outside min..max");
            if (self.member(id, "step") != null) {
                if (!(try self.tunableNumber(id, "step") > 0)) return self.problem(self.member(id, "step").?, "asset_tunables", "step must be positive");
            }
            const doc_id = self.member(id, "doc");
            if (doc_id) |doc| if (self.nodes.items[doc].tag != .string) return self.problem(doc, "asset_tunables", "doc must be text");
            const field_name = try self.a.dupe(u8, name_node.text);
            for (field_name) |*byte| if (byte.* == '.') {
                byte.* = '_';
            };
            try self.identifier(name_id, field_name);
            const field_found = try fields.getOrPut(self.a, field_name);
            if (field_found.found_existing) return self.problem(name_id, "asset_tunables", "Two tunables share a field; rename one");
            const stable_id = tunableId(name_node.text);
            const id_found = try ids.getOrPut(self.a, stable_id);
            if (id_found.found_existing) return self.problem(name_id, "asset_tunables", "Two tunables share an id; rename one");
            try self.emitField(field_name, "(U32, F32, F32, F32)", index);
            try self.put(&self.body, "(");
            try self.integer(&self.body, stable_id);
            for ([_]f64{ initial, least, most }) |value| {
                try self.put(&self.body, ", ");
                try self.float32(&self.body, value);
            }
            try self.put(&self.body, ")");
            if (index > 0) try self.put(&declarations, ", ");
            const name_span = try self.shownSpan(&text, &text_count, name_id);
            const doc_span = try self.shownSpan(&text, &text_count, doc_id);
            try self.put(&declarations, "($Declaration { name_start: ");
            try self.integer(&declarations, name_span[0]);
            try self.put(&declarations, ", name_count: ");
            try self.integer(&declarations, name_span[1]);
            try self.put(&declarations, ", id: ");
            try self.integer(&declarations, stable_id);
            try self.put(&declarations, ", initial: ");
            try self.float32(&declarations, initial);
            try self.put(&declarations, ", least: ");
            try self.float32(&declarations, least);
            try self.put(&declarations, ", most: ");
            try self.float32(&declarations, most);
            try self.put(&declarations, ", doc_start: ");
            try self.integer(&declarations, doc_span[0]);
            try self.put(&declarations, ", doc_count: ");
            try self.integer(&declarations, doc_span[1]);
            try self.put(&declarations, " })");
        }
        try self.recordEnd();
        try self.put(&self.header, "type Declaration is data = $Declaration { name_start: U32, name_count: U32, id: U32, initial: F32, least: F32, most: F32, doc_start: U32, doc_count: U32 }\n");
        try self.put(&text, "]\n");
        try self.put(&declarations, "]\n");
        try self.put(&self.body, text.items);
        try self.put(&self.body, declarations.items);
        try self.put(&self.body, "const name = func (row: Declaration) => return &declaration_text[row.name_start..row.name_start + row.name_count]\n");
        try self.put(&self.body, "const doc = func (row: Declaration) => return &declaration_text[row.doc_start..row.doc_start + row.doc_count]\n");
    }
};

fn decodePoint(bytes: []const u8) !u21 {
    return switch (bytes.len) {
        1 => bytes[0],
        2 => std.unicode.utf8Decode2(bytes[0..2].*),
        3 => std.unicode.utf8Decode3(bytes[0..3].*),
        4 => std.unicode.utf8Decode4(bytes[0..4].*),
        else => unreachable,
    };
}
fn boundedUtf8Prefix(bytes: []const u8, maximum: usize) []const u8 {
    var end = @min(bytes.len, maximum);
    while (end > 0 and end < bytes.len and bytes[end] & 0xc0 == 0x80) end -= 1;
    return bytes[0..end];
}

fn inFont(point: u21) bool {
    if (point >= 32 and point <= 126) return true;
    const extras = "åäöÅÄÖéüÉ‹›•…×–—";
    var iterator = std.unicode.Utf8View.initUnchecked(extras).iterator();
    while (iterator.nextCodepoint()) |extra| if (extra == point) return true;
    return false;
}
fn tunableName(name: []const u8) bool {
    var first = true;
    if (name.len == 0) return false;
    for (name) |byte| {
        if (first) {
            if (!std.ascii.isLower(byte)) return false;
            first = false;
        } else if (byte == '.') first = true else if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '_') return false;
    }
    return !first;
}
fn tunableId(name: []const u8) u32 {
    var hash: u32 = 0x811c9dc5;
    for (name) |byte| hash = (hash ^ byte) *% 0x01000193;
    return ((hash >> 24) ^ hash) & 0xffffff;
}

fn sourceLaw(a: Allocator, kind: Kind, input: []const u8, expected: []const u8) !void {
    var result = try generate(a, kind, input);
    defer deinit(a, &result);
    if (result == .issue) {
        std.debug.print("asset issue: {s}\n", .{result.issue.message});
        return error.TestUnexpectedResult;
    }
    try std.testing.expectEqualStrings(expected, result.source);
}
fn allocationLaw(a: Allocator) !void {
    try sourceLaw(a, .json, "{\"z\":[{\"a\":1},{\"a\":2}],\"label\":\"å\",\"zero\":-0}", "type Utf8 is data = $Utf8 { bytes: (Array U32) }\n" ++
        "type JsonRecord1 is data = $JsonRecord1 { a: U32 }\n" ++
        "type Data is data = $Data { label: Utf8, z: (Array JsonRecord1), zero: F32 }\n" ++
        "const value: Data = ($Data { label: ($Utf8 { bytes: #[195, 165] }), z: #[($JsonRecord1 { a: 1 }), ($JsonRecord1 { a: 2 })], zero: (-0.0) })\n");
    var issue = try generate(a, .text, "{\"greeting\":\"😀😀\\n\"}");
    defer deinit(a, &issue);
    try std.testing.expect(issue == .issue);
    try std.testing.expectEqualStrings("text greeting: the font has no 😀\n", issue.issue.message);
    try std.testing.expectEqual(@as(u32, 12), issue.issue.start);
    try std.testing.expectEqual(@as(u32, 24), issue.issue.end);
}
test "native assets infer shared records and release success and issue allocation failures" {
    try allocationLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationLaw, .{});
}
test "native assets preserve last-wins JSON and exact tuples and float spelling" {
    try sourceLaw(std.testing.allocator, .json, "{\"x\":false,\"x\":true,\"n\":0.1,\"items\":[1,false],\"empty\":[]}", "type Data is data = $Data { empty: (), items: (U32, Bool), n: F32, x: Bool }\nconst value: Data = ($Data { empty: (), items: (1, false), n: 0.10000000149011612, x: true })\n");
    try sourceLaw(std.testing.allocator, .json, "{\"x\":\"\\ud800\",\"x\":1}", "type Data is data = $Data { x: U32 }\nconst value: Data = ($Data { x: 1 })\n");
    try sourceLaw(std.testing.allocator, .json, "-0", "type Data = F32\nconst value: F32 = (-0.0)\n");
    try sourceLaw(std.testing.allocator, .json, "[[1]]", "type Data = (Array (Array U32))\nconst value: (Array (Array U32)) = #[#[1]]\n");
}
test "native assets catalog suffixes indexes and text codepoints" {
    try sourceLaw(std.testing.allocator, .catalog, "{\"meshes\":[\"small.box.mesh.json\",\"other-name.json\"],\"ignored\":true}", "type Meshes is data = $Meshes { small_box: U32, other_name: U32 }\ntype Materials is data = $Materials {  }\ntype Sounds is data = $Sounds {  }\nconst meshes: Meshes = ($Meshes { small_box: 0, other_name: 1 })\nconst materials: Materials = ($Materials {  })\nconst sounds: Sounds = ($Sounds {  })\n");
    try sourceLaw(std.testing.allocator, .text, "{\"z\":[\"å\",\"\"],\"empty\":[]}", "type Text is data = $Text { z: (Array (Array U32)), empty: (Array (Array U32)) }\nconst text: Text = ($Text { z: #[#[229], #[]], empty: #[] })\n");
}
fn issueLaw(a: Allocator, kind: Kind, input: []const u8, code: []const u8) !void {
    var result = try generate(a, kind, input);
    defer deinit(a, &result);
    try std.testing.expect(result == .issue);
    try std.testing.expectEqualStrings(code, result.issue.code);
    try std.testing.expect(result.issue.end >= result.issue.start);
    try std.testing.expect(result.issue.end <= input.len);
    try std.testing.expect(result.issue.message.len <= 1024);
}
fn tunablesLaw(a: Allocator) !void {
    var result = try generate(a, .tunables, "{\"tunables\":[{\"name\":\"camera.zoom\",\"default\":0.1,\"min\":-1,\"max\":2,\"step\":1e-100,\"doc\":\"å😀\\n\"}],\"extra\":true}");
    defer deinit(a, &result);
    try std.testing.expect(result == .source);
    try std.testing.expect(std.mem.find(u8, result.source, "camera_zoom: (U32, F32, F32, F32)") != null);
    try std.testing.expect(std.mem.find(u8, result.source, "camera_zoom: (16562854, ") != null);
    try std.testing.expect(std.mem.find(u8, result.source, "doc_start: 11, doc_count: 3") != null);
    try std.testing.expect(std.mem.find(u8, result.source, "declaration_text: Array U32 = #[99, 97, 109, 101, 114, 97, 46, 122, 111, 111, 109, 229, 63, 63]") != null);
    try std.testing.expect(std.mem.find(u8, result.source, "name_start: 0, name_count: 11") != null);
    try std.testing.expect(std.mem.find(u8, result.source, "0.10000000149011612, (-1.0), 2.0") != null);
    try std.testing.expect(std.mem.find(u8, result.source, "step") == null);
    try issueLaw(a, .tunables, "{\"tunables\":[{\"name\":\"x\",\"default\":0,\"min\":0,\"max\":1,\"step\":0}]}", "asset_tunables");
}
test "native assets tunables round bounds preserve tiny steps and replace unsupported codepoints" {
    try tunablesLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, tunablesLaw, .{});
    const a = std.testing.allocator;
    try issueLaw(a, .tunables, "{\"tunables\":[{\"name\":\"x\",\"default\":1,\"min\":1,\"max\":1.000000001}]}", "asset_tunables");
    try issueLaw(a, .tunables, "{\"tunables\":[{\"name\":\"a.b\",\"default\":0,\"min\":0,\"max\":1},{\"name\":\"a_b\",\"default\":0,\"min\":0,\"max\":1}]}", "asset_tunables");
    try issueLaw(a, .tunables, "{\"tunables\":[{\"name\":\"x\",\"default\":0,\"min\":0,\"max\":1,\"extra\":0}]}", "asset_tunables");
    try std.testing.expectEqual(@as(u32, 16562854), tunableId("camera.zoom"));
}
test "native assets reject malformed numbers identifiers Unicode and catalog collisions" {
    const a = std.testing.allocator;
    for ([_][]const u8{ "9007199254740992", "1e40", "1e400", "-9007199254740992" }) |input| try issueLaw(a, .json, input, "asset_number");
    for ([_][]const u8{ "01", "1.", "1e", "[1,]", "{\"x\":true} rubbish" }) |input| try issueLaw(a, .json, input, "asset_json");
    try issueLaw(a, .json, "\"\\ud800\"", "asset_unicode");
    try issueLaw(a, .json, "\"\xff\"", "asset_unicode");
    try issueLaw(a, .json, "{\"const\":0}", "asset_identifier");
    try issueLaw(a, .catalog, "{\"meshes\":[\"a-b.json\",\"a.b.mesh.json\"]}", "asset_catalog");
    try issueLaw(a, .catalog, "{\"sounds\":[\"0.wav\"]}", "asset_identifier");
    try issueLaw(a, .text, "{\"x\":\"\\t\\n \"}", "asset_font");
}

test "native assets bound JSON depth before recursive graph construction" {
    var input: [259]u8 = undefined;
    @memset(input[0..129], '[');
    input[129] = '0';
    @memset(input[130..], ']');
    try issueLaw(std.testing.allocator, .json, &input, "asset_limit");
}

test "native asset diagnostics preserve UTF-8 when bounding long field names" {
    const a = std.testing.allocator;
    var name: [257]u8 = undefined;
    @memset(name[0..255], 'a');
    @memcpy(name[255..], "å");
    for ([_]struct { kind: Kind, prefix: []const u8, suffix: []const u8, code: []const u8 }{
        .{ .kind = .json, .prefix = "{\"", .suffix = "\":true}", .code = "asset_identifier" },
        .{ .kind = .tunables, .prefix = "{\"tunables\":[{\"name\":\"x\",\"", .suffix = "\":true,\"default\":0,\"min\":0,\"max\":1}]}", .code = "asset_tunables" },
    }) |case| {
        const input = try std.mem.concat(a, u8, &.{ case.prefix, &name, case.suffix });
        defer a.free(input);
        var result = try generate(a, case.kind, input);
        defer deinit(a, &result);
        try std.testing.expect(result == .issue);
        try std.testing.expectEqualStrings(case.code, result.issue.code);
        try std.testing.expect(std.unicode.utf8ValidateSlice(result.issue.message));
        try std.testing.expect(result.issue.message.len <= 1024);
        const start: u32 = @intCast(case.prefix.len + name.len + 2);
        try std.testing.expectEqual(start, result.issue.start);
        try std.testing.expectEqual(start + 4, result.issue.end);
    }
}
