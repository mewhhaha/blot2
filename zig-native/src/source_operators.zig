//! Source operator validation precedes inference. Unknown and ambiguous chains
//! remain grammar-valid; lexical names and written tails retain lowering order.
const std = @import("std");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const T = @import("types.zig");
pub const Code = enum { effect_member, constructor_marker, integer_range, float_range, float_literal, duplicate_name, unknown_operator, unknown_value, unknown_rebinding, unreachable_statement, operator_associativity, operator_header_order, operator_precedence, duplicate_operator, unsupported_prefix, unknown_intrinsic, unsupported_expression, unknown_constructor, sealed_effect, call_arity, requests_scope, yield_scope, break_scope, literal_required, product_index_literal, alternative_bindings, duplicate_pattern_binding, duplicate_record_field, unknown_record_field, record_constructor, missing_record_field, unknown_modifier, nesting_limit };
pub const Terminator = enum { none, return_, break_, yield_ };
pub const Issue = struct { code: Code, node: ast.Id, point: u32, symbol: symbols.Symbol = 0, implicit_type_witness: bool = false, terminator: Terminator = .none, numeric_literal: ?ast.NumericFault = null };
pub fn origin(tree: *const ast.Tree, id: ast.Id) u32 {
    for (tree.operator_origins.items) |item| if (item.node == id) return item.span.start;
    return tree.span(id).start;
}
fn numericIssue(tree: *const ast.Tree, id: ast.Id, point: u32) Issue {
    const fault = tree.numericFault(id);
    return .{ .code = switch (fault.code) {
        .integer_range => .integer_range,
        .float_range => .float_range,
        .float_literal => .float_literal,
    }, .node = id, .point = point, .numeric_literal = fault };
}
fn named(pool: *const symbols.Pool, symbol: symbols.Symbol) bool {
    const text = pool.get(symbol);
    return text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_');
}

pub fn validate(allocator: std.mem.Allocator, tree: *const ast.Tree, pool: *const symbols.Pool, context: anytype) T.Error!?Issue {
    // Name collection lowers declarations from the tail. A direct record
    // payload declares its field schema before any annotation is inferred.
    const duplicate = context.sourceDuplicateName();
    var collected = tree.roots.items.len;
    while (collected != 0) {
        collected -= 1;
        const id = tree.roots.items[collected];
        if (duplicate == id) return .{ .code = .duplicate_name, .node = id, .point = tree.span(id).start };
        if (tree.node(id).tag != .data_decl) continue;
        for (tree.children(tree.node(id).b)) |constructor| {
            const payload = tree.node(constructor).b;
            if (payload == 0 or tree.node(payload).tag != .type_record or tree.typeConversionOrigin(payload) != tree.span(payload).start) continue;
            const fields = tree.children(payload);
            for (fields, 0..) |field, index| for (fields[0..index]) |earlier| if (tree.node(field).a == tree.node(earlier).a)
                return .{ .code = .duplicate_record_field, .node = field, .point = tree.span(field).start, .symbol = tree.node(field).a };
        }
    }
    if (duplicate) |id| return .{ .code = .duplicate_name, .node = id, .point = tree.span(id).start };
    // Header collection lowers the tail first, including target resolution.
    var index = tree.roots.items.len;
    while (index != 0) {
        index -= 1;
        const id = tree.roots.items[index];
        if (tree.node(id).tag != .fixity_decl) continue;
        const fixity = tree.fixity(id);
        for (tree.roots.items[0..index]) |earlier| if (tree.node(earlier).tag != .import_decl and tree.node(earlier).tag != .fixity_decl)
            return .{ .code = .operator_header_order, .node = id, .point = tree.span(id).start };
        if (fixity.literal_error != 0) return numericIssue(tree, fixity.literal_error, tree.span(fixity.literal_error).start);
        for (tree.roots.items[index + 1 ..]) |later| if (tree.node(later).tag == .fixity_decl) {
            const other = tree.fixity(later);
            if (fixity.operator == other.operator and fixity.named == other.named) return .{ .code = .duplicate_operator, .node = id, .point = tree.span(id).start };
        };
        if (fixity.precedence > 255) return .{ .code = .operator_precedence, .node = id, .point = tree.span(id).start };
        if (!try context.sourceOperatorTargetExists(fixity.target)) return .{ .code = .unknown_value, .node = id, .point = origin(tree, id), .symbol = fixity.target };
    }
    // Resolve source names before inference, in the same declaration and
    // lexical order as lowering. This pass never chooses semantic types.
    var validator: Validator(@TypeOf(context)) = .{ .allocator = allocator, .tree = tree, .pool = pool, .context = context };
    defer validator.locals.deinit(allocator);
    index = tree.roots.items.len;
    while (index != 0) {
        index -= 1;
        const id = tree.roots.items[index];
        if (comptime @hasDecl(@TypeOf(context.*), "sourceDeclarationHeader")) try context.sourceDeclarationHeader(id);
        if (validator.annotationsStopped()) return null;
        if (tree.node(id).tag != .value_decl) continue;
        const value = tree.valueDecl(id);
        if (value.modifier != 0 and !std.mem.eql(u8, pool.get(value.modifier), "entry"))
            return .{ .code = .unknown_modifier, .node = id, .point = tree.span(id).start };
        const scope = if (comptime @hasDecl(@TypeOf(context.*), "sourceBindingStart")) try context.sourceBindingStart(id) else {};
        defer if (comptime @hasDecl(@TypeOf(context.*), "sourceBindingEnd")) context.sourceBindingEnd(scope);
        if (comptime @hasDecl(@TypeOf(context.*), "sourceBindingAnnotation")) try context.sourceBindingAnnotation(id);
        if (validator.annotationsStopped()) return null;
        try validator.walk(value.body, 0);
        var attribute_index = value.attributes.len;
        const attributes = tree.list(value.attributes);
        while (attribute_index != 0) {
            attribute_index -= 1;
            try validator.walk(tree.node(attributes[attribute_index]).a, 0);
        }
        if (validator.issue != null) return validator.issue;
        if (comptime @hasDecl(@TypeOf(context.*), "sourceBindingFinish")) try context.sourceBindingFinish(id);
        if (validator.annotationsStopped()) return null;
    }
    return null;
}
fn Validator(comptime Context: type) type {
    return struct {
        allocator: std.mem.Allocator,
        tree: *const ast.Tree,
        pool: *const symbols.Pool,
        context: Context,
        locals: std.ArrayList(symbols.Symbol) = .empty,
        issue: ?Issue = null,
        pattern_scope: ?usize = null,
        record_constructor: symbols.Symbol = 0,
        loops: usize = 0,
        replies: bool = false,
        permitted_requests: ast.Id = 0,
        const Self = @This();
        fn annotationsStopped(self: *const Self) bool {
            return if (comptime @hasDecl(@TypeOf(self.context.*), "sourceAnnotationsStopped")) self.context.sourceAnnotationsStopped() else false;
        }
        fn validateControls(self: *const Self) bool {
            return if (comptime @hasDecl(@TypeOf(self.context.*), "sourceControlValidation")) self.context.sourceControlValidation() else false;
        }
        fn fail(self: *Self, code: Code, id: ast.Id, point: u32, symbol: symbols.Symbol) void {
            if (self.issue == null and !self.annotationsStopped()) self.issue = .{ .code = code, .node = id, .point = point, .symbol = symbol };
        }
        fn numericFailure(self: *Self, id: ast.Id) void {
            if (self.issue != null or self.annotationsStopped()) return;
            const point = if (@hasDecl(@typeInfo(Context).pointer.child, "sourceLiteralPoint")) self.context.sourceLiteralPoint(id) else self.tree.span(id).start;
            self.issue = numericIssue(self.tree, id, point);
        }
        fn local(self: *const Self, symbol: symbols.Symbol) bool {
            for (self.locals.items[0 .. self.pattern_scope orelse self.locals.items.len]) |item| if (item == symbol) return true;
            const text = self.pool.get(symbol);
            if (std.mem.indexOfScalar(u8, text, '.')) |separator|
                if (self.pool.lookup(text[0..separator])) |root|
                    for (self.locals.items[0 .. self.pattern_scope orelse self.locals.items.len]) |item| if (item == root) return true;
            return false;
        }
        fn name(self: *Self, symbol: symbols.Symbol, id: ast.Id, point: u32) T.Error!void {
            if (!self.local(symbol) and !try self.context.sourceValueExists(symbol)) self.fail(.unknown_value, id, point, symbol);
        }
        fn bind(self: *Self, symbol: symbols.Symbol) T.Error!void {
            if (symbol != 0 and !std.mem.eql(u8, self.pool.get(symbol), "_")) try self.locals.append(self.allocator, symbol);
        }
        fn recordTarget(self: *Self, id: ast.Id, symbol: symbols.Symbol) T.Error!bool {
            const point = self.tree.span(id).start + 1;
            var lexical = false;
            for (self.locals.items[0 .. self.pattern_scope orelse self.locals.items.len]) |item| if (item == symbol) {
                lexical = true;
                break;
            };
            if (lexical) {
                self.fail(.record_constructor, id, point, 0);
                return false;
            }
            switch (try self.context.sourceRecordTarget(symbol)) {
                .record => return true,
                .other => self.fail(.record_constructor, id, point, 0),
                .missing => self.fail(.unknown_constructor, id, point, symbol),
            }
            return false;
        }
        fn typeApplication(self: *const Self, id: ast.Id) bool {
            var head = id;
            while (true) {
                const node = self.tree.node(head);
                switch (node.tag) {
                    .apply, .group => head = node.a,
                    .name => return !self.local(node.a) and self.context.sourceTypeApplication(node.a),
                    else => return false,
                }
            }
        }
        fn pattern(self: *Self, id: ast.Id, depth: usize) T.Error!void {
            const previous = self.pattern_scope;
            self.pattern_scope = previous orelse self.locals.items.len;
            defer self.pattern_scope = previous;
            try self.patternResult(id, depth);
        }
        fn patternNames(self: *Self, id: ast.Id, depth: usize) T.Error!void {
            const saved = self.locals.items.len;
            defer self.locals.shrinkRetainingCapacity(saved);
            try self.pattern(id, depth);
        }
        fn uniquePattern(self: *Self, first: []const symbols.Symbol, second: []const symbols.Symbol, id: ast.Id) void {
            for (first) |name_| for (second) |other| if (name_ == other) {
                self.fail(.duplicate_pattern_binding, id, self.tree.span(id).start, 0);
                return;
            };
        }
        fn patternResult(self: *Self, id: ast.Id, depth: usize) T.Error!void {
            if (id == 0 or self.issue != null or self.annotationsStopped()) return;
            if (depth >= 1024) {
                self.fail(.nesting_limit, id, self.tree.span(id).start, 0);
                return;
            }
            const node = self.tree.node(id);
            switch (node.tag) {
                .numeric_error => self.numericFailure(id),
                .pattern_name => try self.bind(node.a),
                .pattern_field => if (node.b == 0) {
                    try self.bind(node.a);
                } else try self.patternResult(node.b, depth + 1),
                .pattern_constructor => {
                    if (node.b != 0 and self.tree.node(node.b).tag == .pattern_record) {
                        if (!try self.recordTarget(id, node.a)) return;
                    } else try self.name(node.a, id, self.tree.span(id).start + 1);
                    const previous = self.record_constructor;
                    self.record_constructor = node.a;
                    defer self.record_constructor = previous;
                    try self.patternResult(node.b, depth + 1);
                },
                .pattern_product, .pattern_record => {
                    const base = self.locals.items.len;
                    const children = self.tree.children(id);
                    for (children, 0..) |child, index| {
                        if (node.tag == .pattern_record) {
                            const field = self.tree.node(child).a;
                            if (self.context.sourceRecordFieldExists(self.record_constructor, field)) |known| if (!known) {
                                self.fail(.unknown_record_field, child, self.tree.span(child).start, field);
                                return;
                            };
                            for (children[0..index]) |previous| if (self.tree.node(previous).a == field) {
                                self.fail(.duplicate_record_field, child, self.tree.span(child).start, field);
                                return;
                            };
                        }
                        const start = self.locals.items.len;
                        try self.patternResult(child, depth + 1);
                        if (self.issue != null or self.annotationsStopped()) return;
                        self.uniquePattern(self.locals.items[base..start], self.locals.items[start..], child);
                        if (self.issue != null or self.annotationsStopped()) return;
                    }
                },
                .pattern_row => {
                    var scratch_buffer: [64]u8 align(@alignOf(usize)) = undefined;
                    var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
                    const scratch_allocator = scratch.allocator();
                    var starts: std.ArrayList(usize) = .empty;
                    defer starts.deinit(scratch_allocator);
                    const children = self.tree.children(id);
                    for (children) |child| {
                        try starts.append(scratch_allocator, self.locals.items.len);
                        try self.patternResult(child, depth + 1);
                        if (self.issue != null or self.annotationsStopped()) return;
                    }
                    try starts.append(scratch_allocator, self.locals.items.len);
                    var index = children.len;
                    while (index != 0) {
                        index -= 1;
                        self.uniquePattern(self.locals.items[starts.items[index]..starts.items[index + 1]], self.locals.items[starts.items[index + 1]..], children[index]);
                        if (self.issue != null or self.annotationsStopped()) return;
                    }
                },
                .pattern_value => try self.name(node.a, id, self.tree.span(id).start + 1),
                else => {},
            }
        }
        fn requestInput(self: *const Self, id: ast.Id) bool {
            var head = id;
            while (self.tree.node(head).tag == .apply or self.tree.node(head).tag == .group) head = self.tree.node(head).a;
            return self.tree.node(head).tag == .intrinsic and std.mem.eql(u8, self.pool.get(self.tree.node(head).a), "@requests");
        }
        fn suite(self: *Self, children: []const ast.Id, depth: usize) T.Error!void {
            const Deferred = struct { node: ast.Id, locals: usize, handlers: bool = false };
            var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
            var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
            const scratch_allocator = scratch.allocator();
            var deferred: std.ArrayList(Deferred) = .empty;
            defer deferred.deinit(scratch_allocator);
            for (children, 0..) |child, index_| {
                const node = self.tree.node(child);
                const terminator: Terminator = switch (node.tag) {
                    .return_stmt => .return_,
                    .break_stmt => .break_,
                    .yield_stmt => .yield_,
                    else => .none,
                };
                if (terminator != .none and index_ + 1 < children.len) {
                    const following = children[index_ + 1];
                    self.fail(.unreachable_statement, following, self.tree.span(following).start, 0);
                    self.issue.?.terminator = terminator;
                    return;
                }
                if (node.tag == .for_stmt and self.requestInput(node.b)) {
                    if (comptime @hasDecl(@TypeOf(self.context.*), "sourceRequestHeader")) try self.context.sourceRequestHeader(child);
                    if (self.annotationsStopped()) return;
                }
                if (node.tag == .for_stmt and self.requestInput(node.b) and self.requestDispatch(child) != null) {
                    const saved_request = self.permitted_requests;
                    var head = node.b;
                    while (self.tree.node(head).tag == .apply or self.tree.node(head).tag == .group) head = self.tree.node(head).a;
                    self.permitted_requests = head;
                    try self.walk(node.b, depth + 1);
                    self.permitted_requests = saved_request;
                    const saved = self.locals.items.len;
                    try self.pattern(node.a, depth + 1);
                    try self.requestCase(self.requestDispatch(child).?, true, depth + 1);
                    self.locals.shrinkRetainingCapacity(saved);
                    try deferred.append(scratch_allocator, .{ .node = child, .locals = saved, .handlers = true });
                } else if (node.tag == .for_stmt and !self.requestInput(node.b)) {
                    const metadata = self.tree.extra.items[node.c..][0..2];
                    try self.loopScope(node.a, metadata[1], depth + 1);
                    try deferred.append(scratch_allocator, .{ .node = child, .locals = self.locals.items.len });
                } else if (node.tag == .range_stmt) {
                    try self.loopScope(0, node.c, depth + 1);
                    try deferred.append(scratch_allocator, .{ .node = child, .locals = self.locals.items.len });
                } else try self.walk(child, depth + 1);
                if (self.issue != null or self.annotationsStopped()) return;
            }
            // Lowering constructs the body and suffix before range operands.
            // Reverse deferred traversal lets each header borrow its original
            // lexical prefix without copying locals or admitting suffix names.
            var index = deferred.items.len;
            while (index != 0) {
                index -= 1;
                const item = deferred.items[index];
                self.locals.shrinkRetainingCapacity(item.locals);
                const node = self.tree.node(item.node);
                if (item.handlers) {
                    try self.pattern(node.a, depth + 1);
                    try self.requestCase(self.requestDispatch(item.node).?, false, depth + 1);
                } else if (node.tag == .for_stmt) {
                    try self.walk(node.b, depth + 1);
                    try self.walk(self.tree.extra.items[node.c], depth + 1);
                } else {
                    try self.walk(node.a, depth + 1);
                    try self.walk(node.b, depth + 1);
                }
                if (self.issue != null or self.annotationsStopped()) return;
            }
        }
        fn requestDispatch(self: *const Self, id: ast.Id) ?ast.Id {
            const body = self.tree.extra.items[self.tree.node(id).c + 1];
            if (self.tree.node(body).tag != .block) return null;
            const statements = self.tree.children(body);
            if (statements.len != 1 or self.tree.node(statements[0]).tag != .request_case) return null;
            return statements[0];
        }
        fn requestCase(self: *Self, id: ast.Id, completion: bool, depth: usize) T.Error!void {
            const saved_replies = self.replies;
            const saved_loops = self.loops;
            self.replies = !completion;
            self.loops += 1;
            defer {
                self.replies = saved_replies;
                self.loops = saved_loops;
            }
            const node = self.tree.node(id);
            if (completion) {
                const input = self.tree.extra.items[node.a..][0..2];
                for (self.tree.list(.{ .start = input[0], .len = input[1] })) |child| try self.walk(child, depth + 1);
            }
            for (self.tree.list(.{ .start = node.b, .len = node.c })) |child| {
                if ((self.tree.node(child).a == 0) == completion) try self.walk(child, depth + 1);
            }
        }
        fn scope(self: *Self, pattern_id: ast.Id, body: ast.Id, depth: usize) T.Error!void {
            const saved = self.locals.items.len;
            defer self.locals.shrinkRetainingCapacity(saved);
            try self.pattern(pattern_id, depth);
            try self.walk(body, depth);
        }
        fn loopScope(self: *Self, pattern_id: ast.Id, body: ast.Id, depth: usize) T.Error!void {
            self.loops += 1;
            defer self.loops -= 1;
            try self.scope(pattern_id, body, depth);
        }
        fn operator(self: *Self, symbol: symbols.Symbol, is_named: bool, id: ast.Id) T.Error!void {
            const point = origin(self.tree, id);
            if (is_named) try self.name(symbol, id, point) else if (!self.context.sourceSymbolicDeclared(symbol)) self.fail(.unknown_operator, id, point, symbol);
        }
        fn primitive(self: *Self, id: ast.Id, head: ast.Id, argument_count: usize, depth: usize) T.Error!void {
            const symbol = self.tree.node(head).a;
            if (self.validateControls() and std.mem.eql(u8, self.pool.get(symbol), "@requests") and head != self.permitted_requests) {
                self.fail(.requests_scope, head, self.tree.span(head).start, 0);
                return;
            }
            if (!self.context.sourceIntrinsicKnown(symbol)) {
                self.fail(.unknown_intrinsic, head, self.tree.span(head).start, symbol);
                return;
            }
            const arity = self.context.sourceIntrinsicArity(symbol) orelse return;
            if (argument_count != arity or argument_count > 4) {
                self.fail(.call_arity, head, self.tree.span(head).start, 0);
                return;
            }
            var arguments: [4]ast.Id = undefined;
            var current = id;
            var index = argument_count;
            while (self.tree.node(current).tag == .apply) {
                index -= 1;
                arguments[index] = self.tree.node(current).b;
                current = self.tree.node(current).a;
            }
            const name_text = self.pool.get(symbol);
            if (std.mem.eql(u8, name_text, "@type.call") or std.mem.eql(u8, name_text, "@type.result") or std.mem.eql(u8, name_text, "@panic")) {
                if (self.tree.node(arguments[0]).tag != .string) {
                    self.fail(.literal_required, arguments[0], self.tree.span(arguments[0]).start, 0);
                    return;
                }
            }
            const selectors: usize = if (std.mem.eql(u8, name_text, "@effect.state") or std.mem.eql(u8, name_text, "@effect.run")) 2 else if (std.mem.eql(u8, name_text, "@effect.provider") or std.mem.eql(u8, name_text, "@effect.reader") or std.mem.eql(u8, name_text, "@effect.writer")) 1 else 0;
            for (arguments[0..selectors]) |argument| if (self.tree.node(argument).tag == .name and std.mem.eql(u8, self.pool.get(self.tree.node(argument).a), "Foreign")) {
                self.fail(.sealed_effect, argument, self.tree.span(argument).start, 0);
                return;
            };
            for (arguments[0..arity], 0..) |argument, argument_index| {
                // Literal descriptors are consumed by primitive lowering; they
                // are not executable string expressions.
                if (argument_index == 0 and (std.mem.eql(u8, name_text, "@type.call") or std.mem.eql(u8, name_text, "@type.result") or std.mem.eql(u8, name_text, "@panic"))) continue;
                if (std.mem.eql(u8, name_text, "@product.get") and argument_index == 1) {
                    // A group containing an integer is intentionally not a
                    // literal index in the reference source grammar.
                    if (self.tree.node(argument).tag == .numeric_error and self.tree.numericFault(argument).code == .integer_range) self.numericFailure(argument) else if (self.tree.node(argument).tag != .integer) self.fail(.product_index_literal, argument, self.tree.span(argument).start, 0);
                    return;
                }
                const foreign_descriptor = std.mem.eql(u8, name_text, "@effect.descriptor") and argument_index == 0 or std.mem.eql(u8, name_text, "@effect.has") and argument_index == 1;
                if (foreign_descriptor and self.tree.node(argument).tag == .name and std.mem.eql(u8, self.pool.get(self.tree.node(argument).a), "Foreign")) continue;
                try self.walk(argument, depth);
                if (self.issue != null or self.annotationsStopped()) return;
            }
        }
        fn walk(self: *Self, id: ast.Id, depth: usize) T.Error!void {
            if (id == 0 or self.issue != null or self.annotationsStopped()) return;
            if (depth >= 1024) {
                self.fail(.nesting_limit, id, self.tree.span(id).start, 0);
                return;
            }
            const node = self.tree.node(id);
            switch (node.tag) {
                .numeric_error => self.numericFailure(id),
                .string => if (self.validateControls()) self.fail(.unsupported_expression, id, self.tree.span(id).start, 0),
                .name => if (self.validateControls() and !self.local(node.a) and self.context.sourceNonCallableEffect(node.a)) {
                    self.fail(.effect_member, id, self.tree.span(id).start, 0);
                } else try self.name(node.a, id, self.tree.span(id).start),
                .intrinsic => if (self.validateControls() and std.mem.eql(u8, self.pool.get(node.a), "@requests") and id != self.permitted_requests) {
                    self.fail(.requests_scope, id, self.tree.span(id).start, 0);
                } else if (!self.context.sourceIntrinsicKnown(node.a)) {
                    self.fail(.unknown_intrinsic, id, self.tree.span(id).start, node.a);
                } else if ((self.context.sourceIntrinsicArity(node.a) orelse 0) != 0) self.fail(.call_arity, id, self.tree.span(id).start, 0),
                .constructor_ref => if (!try self.context.sourceOperatorTargetExists(node.a)) {
                    self.fail(.unknown_value, id, self.tree.span(id).start + 1, node.a);
                },
                .type_witness => {
                    try self.walk(node.a, depth + 1);
                    if (self.issue != null or self.annotationsStopped()) return;
                    const constructor = self.pool.lookup("Type");
                    if (constructor == null or !try self.context.sourceOperatorTargetExists(constructor.?)) self.issue = .{ .code = .unknown_value, .node = id, .point = self.tree.span(id).start, .symbol = constructor orelse 0, .implicit_type_witness = constructor == null };
                },
                .group, .return_stmt => try self.walk(node.a, depth + 1),
                .yield_stmt => if (self.validateControls() and !self.replies) {
                    self.fail(.yield_scope, id, self.tree.span(id).start, 0);
                } else try self.walk(node.a, depth + 1),
                .break_stmt => if (self.validateControls() and self.loops == 0) self.fail(.break_scope, id, self.tree.span(id).start, 0),
                .forever_stmt => try self.loopScope(0, node.a, depth + 1),
                .field_access => {
                    var base = node.a;
                    while (self.tree.node(base).tag == .group) base = self.tree.node(base).a;
                    const source = self.tree.node(base);
                    if (source.tag == .name and !self.local(source.a) and self.context.sourceQualifiedExists(source.a, node.b)) return;
                    try self.walk(node.a, depth + 1);
                },
                .field => if (node.b != 0) {
                    try self.walk(node.b, depth + 1);
                } else try self.name(node.a, id, self.tree.span(id).start),
                .unary => {
                    try self.walk(node.b, depth + 1);
                    if (!std.mem.eql(u8, self.pool.get(node.a), "-")) self.fail(.unsupported_prefix, id, self.tree.span(id).start, 0);
                },
                .binary => {
                    try self.walk(node.b, depth + 1);
                    if (self.issue != null or self.annotationsStopped()) return;
                    try self.operator(node.a, named(self.pool, node.a), id);
                    try self.walk(node.c, depth + 1);
                },
                .infix_chain => {
                    try self.walk(node.a, depth + 1);
                    const tails = self.tree.list(.{ .start = node.b, .len = node.c });
                    for (tails) |tail| {
                        if (self.issue != null or self.annotationsStopped()) return;
                        const operation = self.tree.node(tail);
                        try self.operator(operation.a, operation.c & 1 != 0, tail);
                        try self.walk(operation.b, depth + 1);
                    }
                    if (self.issue != null or self.annotationsStopped()) return;
                    var stack: std.ArrayList(ast.Id) = .empty;
                    defer stack.deinit(self.allocator);
                    for (tails) |tail| {
                        const flags = self.tree.node(tail).c;
                        const power = flags >> 4;
                        const association = (flags >> 2) & 3;
                        while (stack.items.len != 0) {
                            const previous = self.tree.node(stack.items[stack.items.len - 1]).c;
                            if (previous >> 4 < power) break;
                            if (previous >> 4 == power) {
                                if ((previous >> 2) & 3 != association or association == 2) {
                                    self.fail(.operator_associativity, tail, origin(self.tree, tail), 0);
                                    return;
                                }
                                if (association == 1) break;
                            }
                            _ = stack.pop();
                        }
                        try stack.append(self.allocator, tail);
                    }
                },
                .apply => {
                    var head = id;
                    var argument_count: usize = 0;
                    while (true) {
                        const current = self.tree.node(head);
                        if (current.tag == .apply) {
                            argument_count += 1;
                            head = current.a;
                        } else break;
                    }
                    const callee = self.tree.node(head);
                    if (self.validateControls() and callee.tag == .name and self.tree.node(node.b).tag == .record and self.context.sourceConstructorExists(callee.a) and !self.local(callee.a)) {
                        self.fail(.constructor_marker, id, self.tree.span(id).start, 0);
                        return;
                    }
                    if (callee.tag == .intrinsic) {
                        try self.primitive(id, head, argument_count, depth + 1);
                        return;
                    }
                    try self.walk(node.a, depth + 1);
                    const type_argument = self.typeApplication(node.a) and (!self.validateControls() or try self.context.sourceArgumentIsType(node.a, node.b));
                    if (!type_argument) try self.walk(node.b, depth + 1);
                },
                .index_access => {
                    try self.walk(node.a, depth + 1);
                    try self.walk(node.b, depth + 1);
                },
                .record => {
                    if (node.a != 0 and !try self.recordTarget(id, node.a)) return;
                    const fields = self.tree.children(id);
                    for (fields, 0..) |child, index| {
                        const field = self.tree.node(child).a;
                        if (node.a != 0) if (self.context.sourceRecordFieldExists(node.a, field)) |known| if (!known) {
                            self.fail(.unknown_record_field, child, self.tree.span(child).start, field);
                            return;
                        };
                        for (fields[0..index]) |earlier| if (self.tree.node(earlier).a == field) {
                            self.fail(.duplicate_record_field, child, self.tree.span(child).start, field);
                            return;
                        };
                        try self.walk(child, depth + 1);
                        if (self.issue != null or self.annotationsStopped()) return;
                    }
                    if (node.a != 0) if (self.context.sourceMissingRecordField(node.a, fields)) |field|
                        self.fail(.missing_record_field, id, self.tree.span(id).start + 1, field);
                },
                .product, .array => for (self.tree.children(id)) |child| try self.walk(child, depth + 1),
                .lambda => {
                    if (comptime @hasDecl(@TypeOf(self.context.*), "sourceExpressionAnnotations")) try self.context.sourceExpressionAnnotations(id);
                    if (self.annotationsStopped()) return;
                    const saved_loops = self.loops;
                    const saved_replies = self.replies;
                    self.loops = 0;
                    self.replies = false;
                    defer {
                        self.loops = saved_loops;
                        self.replies = saved_replies;
                    }
                    const saved = self.locals.items.len;
                    defer self.locals.shrinkRetainingCapacity(saved);
                    try self.bind(self.tree.parameter(node.a).name);
                    try self.walk(node.b, depth + 1);
                },
                .block => {
                    const saved = self.locals.items.len;
                    try self.suite(self.tree.children(id), depth + 1);
                    self.locals.shrinkRetainingCapacity(saved);
                    try self.walk(node.c, depth + 1);
                },
                .let_stmt => {
                    const binding = self.tree.binding(id);
                    const annotation_scope = if (comptime @hasDecl(@TypeOf(self.context.*), "sourceBindingStart")) try self.context.sourceBindingStart(id) else {};
                    defer if (comptime @hasDecl(@TypeOf(self.context.*), "sourceBindingEnd")) self.context.sourceBindingEnd(annotation_scope);
                    try self.patternNames(binding.pattern, depth + 1);
                    if (self.issue != null or self.annotationsStopped()) return;
                    if (comptime @hasDecl(@TypeOf(self.context.*), "sourceBindingAnnotation")) try self.context.sourceBindingAnnotation(id);
                    try self.walk(binding.value, depth + 1);
                    if (self.issue != null or self.annotationsStopped()) return;
                    if (comptime @hasDecl(@TypeOf(self.context.*), "sourceBindingFinish")) try self.context.sourceBindingFinish(id);
                    try self.walk(binding.fallback, depth + 1);
                    try self.pattern(binding.pattern, depth + 1);
                },
                .use_stmt => {
                    if (comptime @hasDecl(@TypeOf(self.context.*), "sourceExpressionAnnotations")) try self.context.sourceExpressionAnnotations(id);
                    try self.walk(node.b, depth + 1);
                    try self.bind(node.a);
                },
                .rebind_stmt => {
                    var root = node.a;
                    while (self.tree.node(root).tag == .field_access or self.tree.node(root).tag == .index_access) root = self.tree.node(root).a;
                    const target = self.tree.node(root);
                    if (target.tag == .name and !self.local(target.a)) {
                        self.fail(.unknown_rebinding, id, self.tree.span(root).start, target.a);
                        return;
                    }
                    const saved = self.locals.items.len;
                    defer self.locals.shrinkRetainingCapacity(saved);
                    try self.bind(self.pool.lookup("self") orelse 0);
                    try self.walk(node.a, depth + 1);
                    try self.walk(node.b, depth + 1);
                },
                .if_expr, .if_stmt, .range_stmt => {
                    try self.walk(node.a, depth + 1);
                    try self.scope(0, node.b, depth + 1);
                    try self.scope(0, node.c, depth + 1);
                },
                .if_let_stmt => {
                    try self.patternNames(node.a, depth + 1);
                    try self.walk(node.b, depth + 1);
                    const metadata = self.tree.extra.items[node.c..][0..2];
                    try self.scope(node.a, metadata[0], depth + 1);
                    try self.scope(0, metadata[1], depth + 1);
                },
                .for_stmt => {
                    try self.walk(node.b, depth + 1);
                    const metadata = self.tree.extra.items[node.c..][0..2];
                    try self.walk(metadata[0], depth + 1);
                    try self.scope(node.a, metadata[1], depth + 1);
                },
                .case_expr => {
                    const input = self.tree.extra.items[node.a..][0..2];
                    for (self.tree.list(.{ .start = input[0], .len = input[1] })) |child| try self.walk(child, depth + 1);
                    for (self.tree.list(.{ .start = node.b, .len = node.c })) |child| try self.walk(child, depth + 1);
                },
                .request_case => {
                    try self.requestCase(id, true, depth + 1);
                    try self.requestCase(id, false, depth + 1);
                },
                .case_arm => {
                    const saved = self.locals.items.len;
                    defer self.locals.shrinkRetainingCapacity(saved);
                    const rows = self.tree.list(.{ .start = node.a, .len = node.b });
                    if (rows.len != 0) try self.pattern(rows[0], depth + 1);
                    const canonical_end = self.locals.items.len;
                    for (rows[if (rows.len == 0) @as(usize, 0) else 1..]) |row| {
                        const previous = self.pattern_scope;
                        self.pattern_scope = saved;
                        try self.pattern(row, depth + 1);
                        self.pattern_scope = previous;
                        if (self.issue != null or self.annotationsStopped()) return;
                        var same = canonical_end - saved == self.locals.items.len - canonical_end;
                        for (self.locals.items[saved..canonical_end]) |name_| {
                            same = same and std.mem.indexOfScalar(symbols.Symbol, self.locals.items[canonical_end..], name_) != null;
                        }
                        if (!same) self.fail(.alternative_bindings, row, self.tree.span(row).start, 0);
                        self.locals.shrinkRetainingCapacity(canonical_end);
                        if (self.issue != null or self.annotationsStopped()) return;
                    }
                    const metadata = self.tree.extra.items[node.c..][0..2];
                    try self.walk(metadata[1], depth + 1);
                    try self.walk(metadata[0], depth + 1);
                },
                .request_arm => {
                    try self.walk(node.a, depth + 1);
                    try self.scope(node.b, node.c, depth + 1);
                },
                else => {},
            }
        }
    };
}
