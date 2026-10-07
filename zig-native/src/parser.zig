//! Recursive descent over the source grammar, with a flat operator stack.
//! Surface parsing is independent of the checker/backend's supported subset.
const std = @import("std");
const ast = @import("ast.zig");
const token = @import("token.zig");
const lexer = @import("lexer.zig");
const symbols = @import("symbols.zig");
const Id = ast.Id;
const Tag = token.Tag;
const Error = std.mem.Allocator.Error || error{Syntax};
const Fixity = struct { symbol: symbols.Symbol, precedence: u32, association: u32, named: bool, inherited: bool = false };
pub const InheritedFixity = struct { operator: symbols.Symbol, precedence: u32, association: u32, named: bool };
const Operator = struct { symbol: symbols.Symbol, precedence: u32, association: u32, span: ast.Span, known: bool, named: bool };

pub fn parse(allocator: std.mem.Allocator, source: []const u8, tokens: []const token.Token, pool: *symbols.Pool) std.mem.Allocator.Error!ast.Tree {
    return parseWithFixities(allocator, source, tokens, pool, &.{});
}
pub fn parseWithFixities(allocator: std.mem.Allocator, source: []const u8, tokens: []const token.Token, pool: *symbols.Pool, inherited: []const InheritedFixity) std.mem.Allocator.Error!ast.Tree {
    var p: Parser = .{ .allocator = allocator, .source = source, .tokens = tokens, .pool = pool, .tree = try ast.Tree.init(allocator) };
    errdefer p.tree.deinit(allocator);
    defer p.fixities.deinit(allocator);
    for (inherited) |fixity| try p.fixities.append(allocator, .{ .symbol = fixity.operator, .precedence = fixity.precedence, .association = fixity.association, .named = fixity.named, .inherited = true });
    var declarations_seen = false;
    var body_declarations_seen = false;
    while (!p.at(.eof)) {
        p.newlines();
        if (p.at(.eof)) break;
        const before = p.index;
        const root = p.declaration(declarations_seen, body_declarations_seen) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Syntax => {
                p.recover(before);
                continue;
            },
        };
        try p.tree.roots.append(allocator, root);
        if (p.tree.node(root).tag != .import_decl) declarations_seen = true;
        if (p.tree.node(root).tag != .import_decl and p.tree.node(root).tag != .fixity_decl) body_declarations_seen = true;
        if (!p.at(.newline) and !p.at(.eof)) {
            try p.report(.unexpected_token);
            p.recover(before);
        }
        p.newlines();
    }
    return p.tree;
}

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []const token.Token,
    pool: *symbols.Pool,
    tree: ast.Tree,
    index: usize = 0,
    expression_end: usize = std.math.maxInt(usize),
    depth: usize = 0,
    declaration_origin: ast.Span = .{ .start = 0, .end = 0 },
    fixities: std.ArrayList(Fixity) = .empty,
    fn current(self: *const Parser) token.Token {
        if (self.index >= self.expression_end) return .{ .tag = .eof, .start = self.tokens[self.index].start, .end = self.tokens[self.index].start };
        return if (self.index < self.tokens.len) self.tokens[self.index] else .{ .tag = .eof, .start = @intCast(self.source.len), .end = @intCast(self.source.len) };
    }
    fn at(self: *const Parser, tag: Tag) bool {
        return self.current().tag == tag;
    }
    fn peek(self: *const Parser, offset: usize) Tag {
        return if (self.index + offset < self.tokens.len) self.tokens[self.index + offset].tag else .eof;
    }
    fn text(self: *const Parser, t: token.Token) []const u8 {
        return self.source[t.start..t.end];
    }
    fn word(self: *const Parser, bytes: []const u8) bool {
        return std.mem.eql(u8, self.text(self.current()), bytes);
    }
    fn advance(self: *Parser) token.Token {
        const t = self.current();
        if (self.index < self.tokens.len) self.index += 1;
        return t;
    }
    fn eat(self: *Parser, tag: Tag) bool {
        if (!self.at(tag)) return false;
        _ = self.advance();
        return true;
    }
    fn expect(self: *Parser, tag: Tag) Error!token.Token {
        if (!self.at(tag)) {
            self.report(.expected_token) catch return error.OutOfMemory;
            self.tree.diagnostics.items[self.tree.diagnostics.items.len - 1].expected_token = tag;
            return error.Syntax;
        }
        return self.advance();
    }
    fn report(self: *Parser, code: ast.Code) std.mem.Allocator.Error!void {
        const t = self.current();
        try self.tree.diagnostics.append(self.allocator, .{ .code = code, .start = t.start, .end = t.end, .declaration_origin = self.declaration_origin, .actual_token = t.tag });
    }
    fn fail(self: *Parser, code: ast.Code) Error {
        self.report(code) catch return error.OutOfMemory;
        return error.Syntax;
    }
    fn newlines(self: *Parser) void {
        while (self.eat(.newline)) {}
    }
    fn recover(self: *Parser, before: usize) void {
        if (self.index == before and !self.at(.eof)) _ = self.advance();
        while (!self.at(.newline) and !self.at(.eof)) _ = self.advance();
        self.newlines();
        while (self.eat(.dedent)) self.newlines();
    }
    fn enter(self: *Parser) Error!void {
        if (self.depth >= 256) return self.fail(.nesting_limit);
        self.depth += 1;
    }
    fn add(self: *Parser, tag: ast.Tag, a: u32, b: u32, c: u32, start: u32) Error!Id {
        if (self.tree.nodes.items.len >= std.math.maxInt(u32)) return self.fail(.table_limit);
        try self.tree.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.tree.spans.ensureUnusedCapacity(self.allocator, 1);
        const id: Id = @intCast(self.tree.nodes.items.len);
        self.tree.nodes.appendAssumeCapacity(.{ .tag = tag, .a = a, .b = b, .c = c });
        const end = if (self.index > 0) self.tokens[self.index - 1].end else start;
        self.tree.spans.appendAssumeCapacity(.{ .start = start, .end = end });
        return id;
    }
    fn numericFailure(self: *Parser, t: token.Token, code: ast.NumericCode) Error!Id {
        return self.add(.numeric_error, @backingInt(code), t.start, t.end, t.start);
    }
    fn integerLiteral(self: *Parser, t: token.Token, tag: ast.Tag) Error!Id {
        const value = lexer.integerValue(self.text(t)) catch |err| switch (err) {
            error.IntegerRange => return self.numericFailure(t, .integer_range),
            error.InvalidInteger => return self.fail(.invalid_literal),
        };
        return self.add(tag, value, 0, 0, t.start);
    }
    fn extra(self: *Parser, values: []const u32) Error!u32 {
        if (values.len > std.math.maxInt(u32) - self.tree.extra.items.len) return self.fail(.table_limit);
        const start: u32 = @intCast(self.tree.extra.items.len);
        try self.tree.extra.appendSlice(self.allocator, values);
        return start;
    }
    fn list(self: *Parser, values: []const u32) Error!ast.List {
        return .{ .start = try self.extra(values), .len = @intCast(values.len) };
    }
    fn listNode(self: *Parser, tag: ast.Tag, values: []const Id, start: u32) Error!Id {
        const range = try self.list(values);
        return self.add(tag, range.start, range.len, 0, start);
    }
    fn intern(self: *Parser, bytes: []const u8) Error!symbols.Symbol {
        return self.pool.intern(self.allocator, bytes) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.SymbolLimit => self.fail(.table_limit),
        };
    }
    // Strict name positions follow the grammar's IDENT/TYPE_IDENT split.
    // Qualified names and member accesses use either token kind. Frozen syntax
    // failures here report the containing declaration's first source token.
    fn lowerIdentifier(self: *Parser) Error!symbols.Symbol {
        if (self.at(.type_identifier) or self.at(.kw_true) or self.at(.kw_false)) return self.identifierSyntax();
        return self.identifier();
    }
    fn typeIdentifier(self: *Parser) Error!symbols.Symbol {
        if (self.at(.identifier) or self.at(.kw_true) or self.at(.kw_false)) return self.identifierSyntax();
        _ = try self.expect(.type_identifier);
        const name = try self.intern(self.text(self.tokens[self.index - 1]));
        if (self.at(.dot)) return self.identifierSyntax();
        return name;
    }
    fn constructorPatternName(self: *Parser) Error!symbols.Symbol {
        const name = try self.qualified();
        if (self.tokens[self.index - 1].tag != .type_identifier) return self.identifierSyntaxAt(self.tokens[self.index - 1]);
        return name;
    }
    fn identifierSyntax(self: *Parser) Error {
        return self.identifierSyntaxAt(self.current());
    }
    fn identifierSyntaxAt(self: *Parser, t: token.Token) Error {
        self.tree.diagnostics.append(self.allocator, .{
            .code = .GPU_FRONTEND_SYNTAX_ERROR,
            .start = self.declaration_origin.start,
            .end = self.declaration_origin.end,
            .declaration_origin = self.declaration_origin,
            .detail_span = .{ .start = t.start, .end = t.end },
            .actual_token = t.tag,
        }) catch return error.OutOfMemory;
        return error.Syntax;
    }
    fn identifier(self: *Parser) Error!symbols.Symbol {
        const t = self.current();
        if (t.tag != .identifier and t.tag != .type_identifier) return self.fail(.expected_token);
        _ = self.advance();
        return self.intern(self.text(t));
    }
    fn qualified(self: *Parser) Error!symbols.Symbol {
        const first = self.current();
        const name = try self.identifier();
        if (!self.at(.dot) or (self.peek(1) != .identifier and self.peek(1) != .type_identifier)) return name;
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(self.allocator);
        try bytes.appendSlice(self.allocator, self.text(first));
        while (self.at(.dot) and (self.peek(1) == .identifier or self.peek(1) == .type_identifier)) {
            _ = self.advance();
            const t = self.advance();
            _ = try self.intern(self.text(t));
            try bytes.append(self.allocator, '.');
            try bytes.appendSlice(self.allocator, self.text(t));
        }
        return self.intern(bytes.items);
    }
    fn stringSymbol(self: *Parser) Error!symbols.Symbol {
        const t = try self.expect(.string);
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(self.allocator);
        const raw = self.text(t);
        var i: usize = 1;
        while (i + 1 < raw.len) : (i += 1) {
            var ch = raw[i];
            if (ch == '\\') {
                i += 1;
                ch = switch (raw[i]) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '"' => '"',
                    '\\' => '\\',
                    else => return self.fail(.invalid_literal),
                };
            }
            try bytes.append(self.allocator, ch);
        }
        return self.intern(bytes.items);
    }
    fn declaration(self: *Parser, declarations_seen: bool, body_declarations_seen: bool) Error!Id {
        _ = body_declarations_seen;
        self.declaration_origin = .{ .start = self.current().start, .end = self.current().end };
        const start = self.current().start;
        if (self.at(.kw_import)) {
            if (declarations_seen) return self.fail(.unexpected_token);
            return self.importDecl();
        }
        var attributes: std.ArrayList(Id) = .empty;
        defer attributes.deinit(self.allocator);
        while (self.at(.at)) {
            const attribute_start = self.current().start;
            _ = self.eat(.at);
            _ = try self.expect(.l_bracket);
            const body = try self.expression();
            _ = try self.expect(.r_bracket);
            try attributes.append(self.allocator, try self.add(.attribute, body, 0, 0, attribute_start));
            self.newlines();
        }
        const attrs = try self.list(attributes.items);
        if (self.at(.kw_infixl) or self.at(.kw_infixr) or self.at(.kw_infix)) {
            return self.fixityDecl(attrs, start);
        }
        if (self.at(.kw_type) or self.at(.kw_data)) return self.typeDeclaration(attrs, start);
        if (self.eat(.kw_effect)) {
            const name = try self.qualified();
            _ = try self.expect(.colon);
            const signature = try self.typeExpression();
            return self.add(.effect_decl, name, signature, try self.extra(&.{ attrs.start, attrs.len }), start);
        }
        var modifier: symbols.Symbol = 0;
        var flags: u32 = 0;
        if ((self.at(.type_identifier) or self.at(.kw_true) or self.at(.kw_false)) and (self.peek(1) == .kw_const or self.peek(1) == .kw_let)) return self.identifierSyntax();
        if (self.at(.identifier) and (self.peek(1) == .kw_const or self.peek(1) == .kw_let)) {
            flags = @intFromBool(self.word("entry"));
            modifier = try self.lowerIdentifier();
        }
        const runtime: u32 = if (self.eat(.kw_const)) 0 else if (self.eat(.kw_let)) 1 else return self.fail(.expected_token);
        const name_point = self.tokens[self.index].start;
        const name = try self.qualified();
        const annotation = if (self.eat(.colon)) try self.typeExpression() else 0;
        const constraints = try self.whereClause();
        _ = try self.expect(.equal);
        const body = try self.expression();
        const value_declaration = try self.add(.value_decl, name, body, try self.extra(&.{ annotation, modifier, runtime, constraints.predicates.start, constraints.predicates.len, attrs.start, attrs.len, flags, constraints.node }), start);
        if (runtime != 0) try self.tree.runtime_names.append(self.allocator, .{ .declaration = value_declaration, .point = name_point }) else try self.tree.constant_names.append(self.allocator, .{ .declaration = value_declaration, .point = name_point });
        return value_declaration;
    }
    fn importDecl(self: *Parser) Error!Id {
        const start = (try self.expect(.kw_import)).start;
        var bindings: std.ArrayList(Id) = .empty;
        defer bindings.deinit(self.allocator);
        var namespace: symbols.Symbol = 0;
        var namespace_span: ast.Span = .{ .start = start, .end = start };
        if (self.eat(.star)) {
            _ = try self.expect(.kw_as);
            const t = self.current();
            namespace = try self.lowerIdentifier();
            namespace_span = .{ .start = t.start, .end = t.end };
        } else {
            _ = try self.expect(.l_brace);
            while (!self.at(.r_brace)) {
                const item_start = self.current().start;
                const name = try self.identifier();
                const alias = if (self.eat(.kw_as)) try self.identifier() else name;
                try bindings.append(self.allocator, try self.add(.import_binding, name, alias, 0, item_start));
                if (!self.eat(.comma)) break;
            }
            _ = try self.expect(.r_brace);
        }
        if (!self.eat(.kw_from)) {
            if (!self.word("from")) return self.fail(.expected_token);
            _ = self.advance();
        }
        const path_token = self.current();
        const path = try self.stringSymbol();
        const range = try self.list(bindings.items);
        return self.add(.import_decl, path, range.start, try self.extra(&.{ range.len, namespace, path_token.start, path_token.end, namespace_span.start, namespace_span.end }), start);
    }
    fn fixityDecl(self: *Parser, attrs: ast.List, start: u32) Error!Id {
        const association: u32 = switch (self.advance().tag) {
            .kw_infixl => 0,
            .kw_infixr => 1,
            else => 2,
        };
        const literal = try self.expect(.integer);
        var literal_error: Id = 0;
        const precedence = lexer.integerValue(self.text(literal)) catch |err| switch (err) {
            error.IntegerRange => blk: {
                literal_error = try self.numericFailure(literal, .integer_range);
                break :blk 0;
            },
            error.InvalidInteger => return self.fail(.invalid_literal),
        };
        var symbol: symbols.Symbol = 0;
        var target: symbols.Symbol = 0;
        var target_span: ast.Span = undefined;
        var named = false;
        if (self.eat(.backtick)) {
            named = true;
            target_span = .{ .start = self.current().start, .end = self.current().end };
            symbol = try self.qualified();
            target = symbol;
            _ = try self.expect(.backtick);
        } else {
            _ = try self.expect(.l_paren);
            const op = self.advance();
            if (!operatorTag(op.tag)) return self.fail(.expected_token);
            symbol = try self.intern(self.text(op));
            _ = try self.expect(.r_paren);
            _ = try self.expect(.equal);
            target_span = .{ .start = self.current().start, .end = self.current().end };
            target = try self.qualified();
        }
        var replaced = false;
        for (self.fixities.items) |*existing| if (existing.symbol == symbol and existing.named == named) {
            existing.* = .{ .symbol = symbol, .precedence = @min(precedence, 255), .association = association, .named = named };
            replaced = true;
            break;
        };
        if (!replaced) try self.fixities.append(self.allocator, .{ .symbol = symbol, .precedence = @min(precedence, 255), .association = association, .named = named });
        const flags = @as(u32, @intFromBool(named)) | (@as(u32, @intFromBool(attrs.len != 0)) << 1) | (@as(u32, @intFromBool(literal_error != 0)) << 2);
        const metadata = try self.extra(&.{ precedence, association, flags, attrs.start, attrs.len });
        if (literal_error != 0) _ = try self.extra(&.{literal_error});
        const id = try self.add(.fixity_decl, symbol, target, metadata, start);
        try self.tree.operator_origins.append(self.allocator, .{ .node = id, .span = target_span });
        return id;
    }
    fn typeDeclaration(self: *Parser, attrs: ast.List, start: u32) Error!Id {
        const old_data = self.eat(.kw_data);
        if (!old_data) _ = try self.expect(.kw_type);
        const name = try self.typeIdentifier();
        var params: std.ArrayList(Id) = .empty;
        defer params.deinit(self.allocator);
        if (typeAtomTag(self.current().tag)) try params.append(self.allocator, try self.typeAtom());
        while (self.eat(.fat_arrow)) {
            _ = try self.expect(.kw_type);
            try params.append(self.allocator, try self.typeAtom());
        }
        if (!old_data and self.eat(.equal)) {
            const body = try self.typeExpression();
            const range = try self.list(params.items);
            return self.add(.type_alias_decl, name, body, try self.extra(&.{ range.start, range.len, attrs.start, attrs.len }), start);
        }
        var effect = false;
        if (!old_data) {
            _ = try self.expect(.kw_is);
            if (self.word("contract")) {
                _ = self.advance();
                _ = try self.expect(.equal);
                const body = try self.predicateBody(self.current().start);
                const range = try self.list(params.items);
                return self.add(.contract_decl, name, body.node, try self.extra(&.{ range.start, range.len, attrs.start, attrs.len }), start);
            }
            if (self.eat(.kw_effect)) effect = true else _ = try self.expect(.kw_data);
        }
        _ = try self.expect(.equal);
        var body: Id = 0;
        if (effect) {
            if (self.eat(.l_brace)) {
                var operations: std.ArrayList(Id) = .empty;
                defer operations.deinit(self.allocator);
                self.newlines();
                while (!self.at(.r_brace)) {
                    const item_start = self.current().start;
                    const field = try self.lowerIdentifier();
                    _ = try self.expect(.colon);
                    const ty = try self.typeExpression();
                    try operations.append(self.allocator, try self.add(.effect_operation, field, ty, 0, item_start));
                    if (self.eat(.comma)) {
                        self.newlines();
                        continue;
                    }
                    if (self.at(.newline)) {
                        self.newlines();
                        continue;
                    }
                    break;
                }
                _ = try self.expect(.r_brace);
                body = try self.listNode(.effect_operations, operations.items, start);
            } else body = try self.typeExpression();
        } else {
            var constructors: std.ArrayList(Id) = .empty;
            defer constructors.deinit(self.allocator);
            _ = self.eat(.pipe);
            while (true) {
                const item_start = (try self.expect(.hash)).start;
                const constructor = try self.typeIdentifier();
                const payload = if (typeAtomTag(self.current().tag)) try self.typeExpression() else 0;
                try constructors.append(self.allocator, try self.add(.constructor_ref, constructor, payload, 0, item_start));
                if (!self.eat(.pipe)) break;
            }
            body = try self.listNode(.constructors, constructors.items, start);
        }
        const range = try self.list(params.items);
        return self.add(if (effect) .effect_type_decl else .data_decl, name, body, try self.extra(&.{ range.start, range.len, attrs.start, attrs.len }), start);
    }
    const Where = struct { predicates: ast.List = .{}, node: ast.Id = 0 };
    fn whereClause(self: *Parser) Error!Where {
        const clause_start = self.current().start;
        if (!self.eat(.kw_where)) return .{};
        return self.predicateBody(clause_start);
    }
    fn predicateBody(self: *Parser, clause_start: u32) Error!Where {
        _ = try self.expect(.l_brace);
        self.newlines();
        var predicates: std.ArrayList(Id) = .empty;
        defer predicates.deinit(self.allocator);
        while (!self.at(.r_brace)) {
            const start = self.current().start;
            const kind = try self.qualified();
            const member = if (self.at(.string)) try self.stringSymbol() else 0;
            var args: std.ArrayList(Id) = .empty;
            defer args.deinit(self.allocator);
            while (typeAtomTag(self.current().tag)) {
                const argument_start = self.current().start;
                const grouped = self.at(.l_paren);
                const argument = try self.typeAtom();
                try args.append(self.allocator, if (grouped and self.tree.span(argument).start != argument_start) try self.add(.group, argument, 0, 0, argument_start) else argument);
            }
            const row = if (self.at(.bang)) try self.effectRow() else 0;
            const range = try self.list(args.items);
            try predicates.append(self.allocator, try self.add(.constraint, kind, member, try self.extra(&.{ range.start, range.len, row }), start));
            if (!self.eat(.comma)) break;
            self.newlines();
        }
        self.newlines();
        _ = try self.expect(.r_brace);
        const range = try self.list(predicates.items);
        return .{ .predicates = range, .node = try self.add(.where_clause, range.start, range.len, 0, clause_start) };
    }
    fn typeExpression(self: *Parser) Error!Id {
        try self.enter();
        defer self.depth -= 1;
        const start = self.current().start;
        var parts: std.ArrayList(Id) = .empty;
        defer parts.deinit(self.allocator);
        try parts.append(self.allocator, try self.typeApplication());
        while (self.eat(.arrow)) try parts.append(self.allocator, try self.typeApplication());
        const row = if (self.at(.bang)) try self.effectRow() else 0;
        var value = parts.items[parts.items.len - 1];
        var i = parts.items.len - 1;
        while (i != 0) {
            i -= 1;
            const result = value;
            value = try self.add(.type_function, parts.items[i], result, if (i == 0) row else 0, self.tree.span(parts.items[i]).start);
            self.tree.spans.items[value].end = if (i == 0 and row != 0) self.tree.span(row).end else self.tree.span(result).end;
        }
        if (parts.items.len == 1 and row != 0) return self.add(.type_effect, value, row, 0, start);
        return value;
    }
    fn typeApplication(self: *Parser) Error!Id {
        const start = self.current().start;
        var value = try self.typeAtom();
        while (typeAtomTag(self.current().tag)) value = try self.add(.type_apply, value, try self.typeAtom(), 0, start);
        return value;
    }
    fn typeAtom(self: *Parser) Error!Id {
        try self.enter();
        defer self.depth -= 1;
        const start = self.current().start;
        if (self.eat(.tilde)) return self.add(.type_demand, try self.typeAtom(), 0, 0, start);
        if (self.at(.identifier) or self.at(.type_identifier)) return self.add(.type_name, try self.qualified(), 0, 0, start);
        if (self.eat(.l_brace)) {
            var fields: std.ArrayList(Id) = .empty;
            defer fields.deinit(self.allocator);
            while (!self.at(.r_brace)) {
                const item_start = self.current().start;
                const name = try self.lowerIdentifier();
                const value = if (self.eat(.colon)) try self.typeExpression() else 0;
                try fields.append(self.allocator, try self.add(.type_field, name, value, 0, item_start));
                if (!self.eat(.comma)) break;
            }
            _ = try self.expect(.r_brace);
            return self.listNode(.type_record, fields.items, start);
        }
        const array = self.eat(.l_bracket);
        if (!array and !self.eat(.l_paren)) return self.fail(.expected_type);
        const end: Tag = if (array) .r_bracket else .r_paren;
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        var tuple = false;
        while (!self.at(end)) {
            try values.append(self.allocator, try self.typeExpression());
            if (!self.eat(.comma)) break;
            tuple = true;
        }
        _ = try self.expect(end);
        if (!array and !tuple and values.items.len == 1) {
            try self.tree.type_conversion_origins.append(self.allocator, .{ .node = values.items[0], .point = start });
            return values.items[0];
        }
        return self.listNode(if (array) .type_array else .type_product, values.items, start);
    }
    fn effectRow(self: *Parser) Error!Id {
        const start = (try self.expect(.bang)).start;
        _ = try self.expect(.l_brace);
        var labels: std.ArrayList(Id) = .empty;
        defer labels.deinit(self.allocator);
        while (!self.at(.pipe) and !self.at(.r_brace)) {
            try labels.append(self.allocator, try self.typeApplication());
            if (!self.eat(.comma)) break;
        }
        const tail = if (self.eat(.pipe)) blk: {
            const tail_token = self.current();
            const name = try self.lowerIdentifier();
            break :blk try self.add(.type_name, name, 0, 0, tail_token.start);
        } else 0;
        _ = try self.expect(.r_brace);
        const range = try self.list(labels.items);
        return self.add(.effect_row, range.start, range.len, tail, start);
    }
    fn expression(self: *Parser) Error!Id {
        try self.enter();
        defer self.depth -= 1;
        if (self.at(.kw_fn)) return self.lambda();
        if (self.at(.kw_do)) return self.doBlock();
        if (self.at(.kw_if)) return self.ifExpression();
        if (self.at(.kw_case)) return self.caseExpression();
        return self.infix();
    }
    fn lambda(self: *Parser) Error!Id {
        const start = (try self.expect(.kw_fn)).start;
        const item_start = self.current().start;
        const demanded = self.eat(.tilde);
        var unit = false;
        var name: symbols.Symbol = 0;
        var annotation: Id = 0;
        var constraints: Where = .{};
        if (self.eat(.l_paren)) {
            if (self.eat(.r_paren)) unit = true else {
                name = try self.lowerIdentifier();
                _ = try self.expect(.colon);
                annotation = try self.typeExpression();
                constraints = try self.whereClause();
                _ = try self.expect(.r_paren);
            }
        } else name = try self.lowerIdentifier();
        const parameter = try self.add(.parameter, name, annotation, try self.extra(&.{ @as(u32, @intFromBool(demanded)) | (@as(u32, @intFromBool(unit)) << 1), constraints.predicates.start, constraints.predicates.len, constraints.node }), item_start);
        const result = if (self.eat(.arrow)) try self.typeExpression() else 0;
        _ = try self.expect(.fat_arrow);
        return self.add(.lambda, parameter, try self.expression(), result, start);
    }
    fn doBlock(self: *Parser) Error!Id {
        const start = (try self.expect(.kw_do)).start;
        const resolver = if (self.at(.colon)) 0 else try self.application(false);
        _ = try self.expect(.colon);
        const block = try self.suite();
        self.tree.nodes.items[block].c = resolver;
        self.tree.spans.items[block].start = start;
        return block;
    }
    fn ifExpression(self: *Parser) Error!Id {
        const start = (try self.expect(.kw_if)).start;
        const condition = try self.infix();
        _ = try self.expect(.kw_then);
        const consequence = try self.expression();
        _ = try self.expect(.kw_else);
        return self.add(.if_expr, condition, consequence, try self.expression(), start);
    }
    fn lookupFixity(self: *const Parser, symbol: symbols.Symbol, named: bool) ?Fixity {
        for (self.fixities.items) |fixity| if (fixity.symbol == symbol and fixity.named == named) return fixity;
        if (named) return .{ .symbol = symbol, .precedence = 80, .association = 0, .named = true };
        return null;
    }
    fn readOperator(self: *Parser) Error!Operator {
        const t = self.advance();
        var named = false;
        var span: ast.Span = .{ .start = t.start, .end = t.end };
        const symbol = if (t.tag == .backtick) blk: {
            named = true;
            span.start = self.current().start;
            const value = try self.qualified();
            span.end = self.current().start;
            _ = try self.expect(.backtick);
            break :blk value;
        } else try self.intern(self.text(t));
        const found = self.lookupFixity(symbol, named);
        return .{ .symbol = symbol, .precedence = if (found) |f| f.precedence else 0, .association = if (found) |f| f.association else 0, .known = found != null, .named = named, .span = span };
    }
    fn infix(self: *Parser) Error!Id {
        const start = self.current().start;
        const head = try self.prefix();
        var operands: std.ArrayList(Id) = .empty;
        defer operands.deinit(self.allocator);
        var operators: std.ArrayList(Operator) = .empty;
        defer operators.deinit(self.allocator);
        var unknown = false;
        while (operatorTag(self.current().tag) or self.at(.backtick)) {
            const op = try self.readOperator();
            unknown = unknown or !op.known;
            try operators.append(self.allocator, op);
            const rhs = if (self.at(.kw_fn) or self.at(.kw_do) or self.at(.kw_if) or self.at(.kw_case)) try self.expression() else try self.prefix();
            try operands.append(self.allocator, rhs);
        }
        if (operators.items.len == 0) return head;
        if (unknown) return self.infixChain(head, operators.items, operands.items, start);
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        var stack: std.ArrayList(Operator) = .empty;
        defer stack.deinit(self.allocator);
        try values.append(self.allocator, head);
        for (operators.items, operands.items) |op, rhs| {
            while (stack.items.len != 0) {
                const top = stack.items[stack.items.len - 1];
                if (top.precedence < op.precedence) break;
                if (top.precedence == op.precedence) {
                    if (top.association != op.association or op.association == 2) return self.infixChain(head, operators.items, operands.items, start);
                    if (op.association == 1) break;
                }
                try self.reduce(&values, stack.pop().?);
            }
            try stack.append(self.allocator, op);
            try values.append(self.allocator, rhs);
        }
        while (stack.pop()) |op| try self.reduce(&values, op);
        return values.items[0];
    }
    // Unknown and ambiguous chains are grammar-valid. Preserve written tail
    // order so source validation can resolve operators before their operands.
    fn infixChain(self: *Parser, head: Id, operators: []const Operator, operands: []const Id, start: u32) Error!Id {
        var tails: std.ArrayList(Id) = .empty;
        defer tails.deinit(self.allocator);
        for (operators, operands) |op, rhs| {
            const flags = @as(u32, @intFromBool(op.named)) | (@as(u32, @intFromBool(op.known)) << 1) | (op.association << 2) | (op.precedence << 4);
            const tail = try self.add(.operator_tail, op.symbol, rhs, flags, op.span.start);
            self.tree.spans.items[tail].end = self.tree.span(rhs).end;
            try self.tree.operator_origins.append(self.allocator, .{ .node = tail, .span = op.span });
            try tails.append(self.allocator, tail);
        }
        const range = try self.list(tails.items);
        return self.add(.infix_chain, head, range.start, range.len, start);
    }
    fn reduce(self: *Parser, values: *std.ArrayList(Id), op: Operator) Error!void {
        const rhs = values.pop().?;
        const lhs = values.pop().?;
        const id = try self.add(.binary, op.symbol, lhs, rhs, self.tree.span(lhs).start);
        self.tree.spans.items[id].end = self.tree.span(rhs).end;
        try self.tree.operator_origins.append(self.allocator, .{ .node = id, .span = op.span });
        try values.append(self.allocator, id);
    }
    fn prefix(self: *Parser) Error!Id {
        const t = self.current();
        if (t.tag == .symbol or t.tag == .star or t.tag == .caret) {
            _ = self.advance();
            const op = try self.intern(self.text(t));
            return self.add(.unary, op, try self.application(true), 0, t.start);
        }
        return self.application(true);
    }
    fn application(self: *Parser, allow_witness: bool) Error!Id {
        const start = self.current().start;
        var value = try self.postfix();
        while (true) {
            if (!atomTag(self.current().tag) or (!allow_witness and self.at(.colon))) break;
            if (self.at(.colon) and self.peek(1) == .newline) break;
            value = try self.add(.apply, value, try self.postfix(), 0, start);
        }
        return value;
    }
    /// Projection/indexing belongs to an individual atom before that atom is
    /// supplied as an application argument. A spaced bracket begins an array
    /// argument; an adjacent bracket indexes the preceding value. An adjacent
    /// group supplies a call argument before a following projection or index.
    fn postfix(self: *Parser) Error!Id {
        const start = self.current().start;
        var value = try self.atom();
        while (true) {
            if (self.at(.dot)) {
                const dot = self.advance();
                const member_point = self.current().start;
                const member = try self.identifier();
                value = try self.add(.field_access, value, member, 0, start);
                try self.tree.operator_origins.append(self.allocator, .{ .node = value, .span = .{ .start = dot.start, .end = dot.end }, .member = member, .member_point = member_point });
            } else if (self.at(.l_paren) and self.current().start == self.tree.span(value).end) {
                value = try self.add(.apply, value, try self.atom(), 0, start);
            } else if (self.at(.l_bracket) and self.current().start == self.tree.span(value).end) {
                _ = self.advance();
                const index = try self.expression();
                _ = try self.expect(.r_bracket);
                value = try self.add(.index_access, value, index, 0, start);
            } else break;
        }
        return value;
    }
    fn atom(self: *Parser) Error!Id {
        try self.enter();
        defer self.depth -= 1;
        const t = self.current();
        const start = t.start;
        switch (t.tag) {
            .integer => {
                _ = self.advance();
                return self.integerLiteral(t, .integer);
            },
            .float => {
                _ = self.advance();
                const bits = lexer.floatBits(self.allocator, self.text(t)) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.FloatRange => return self.numericFailure(t, .float_range),
                    error.InvalidFloat => return self.numericFailure(t, .float_literal),
                };
                return self.add(.float, bits, 0, 0, start);
            },
            .string => return self.add(.string, try self.stringSymbol(), 0, 0, start),
            .intrinsic => {
                _ = self.advance();
                return self.add(.intrinsic, try self.intern(self.text(t)), 0, 0, start);
            },
            .identifier, .type_identifier => {
                const token_start = self.index;
                const name = try self.qualified();
                const id = try self.add(.name, name, 0, 0, start);
                for (self.tokens[token_start..self.index], token_start..) |item, index| if (item.tag == .dot) {
                    const member = self.pool.lookup(self.text(self.tokens[index + 1])).?;
                    try self.tree.operator_origins.append(self.allocator, .{ .node = id, .span = .{ .start = item.start, .end = item.end }, .member = member, .member_point = self.tokens[index + 1].start });
                };
                return id;
            },
            .selector => {
                _ = self.advance();
                return self.add(.selector, try self.qualified(), 0, 0, start);
            },
            .colon => {
                _ = self.advance();
                return self.add(.type_witness, try self.atom(), 0, 0, start);
            },
            .hash => {
                _ = self.advance();
                if (self.at(.l_bracket)) return self.collection(false, start);
                if (self.at(.l_brace)) return self.record(0, start);
                if (self.at(.kw_true) or self.at(.kw_false)) {
                    const value: u32 = @intFromBool(self.eat(.kw_true));
                    if (value == 0) _ = try self.expect(.kw_false);
                    return self.add(.boolean, value, 0, 0, start);
                }
                const name = try self.qualified();
                if (self.at(.l_brace)) return self.record(name, start);
                return self.add(.constructor_ref, name, 0, 0, start);
            },
            .l_brace => return self.record(0, start),
            .l_bracket => return self.collection(true, start),
            .l_paren => {
                _ = self.advance();
                const end: Tag = .r_paren;
                var values: std.ArrayList(Id) = .empty;
                defer values.deinit(self.allocator);
                var tuple = false;
                while (!self.at(end)) {
                    try values.append(self.allocator, try self.expression());
                    if (!self.eat(.comma)) break;
                    tuple = true;
                }
                _ = try self.expect(end);
                if (values.items.len == 0) return self.add(.unit, 0, 0, 0, start);
                if (!tuple and values.items.len == 1) return self.add(.group, values.items[0], 0, 0, start);
                return self.listNode(.product, values.items, start);
            },
            .private_from, .private_where => return self.fail(.private_marker),
            else => return self.fail(.expected_expression),
        }
    }
    /// A collection's top-level pipe separates its body from qualifiers (or
    /// a cons tail). Pipes inside parentheses and nested collections remain
    /// ordinary operators. The boundary is restored before consuming it.
    fn collectionElement(self: *Parser) Error!Id {
        const previous = self.expression_end;
        var nesting: usize = 0;
        var index = self.index;
        while (index < @min(self.tokens.len, previous)) : (index += 1) {
            switch (self.tokens[index].tag) {
                .l_paren, .l_bracket, .l_brace, .indent => nesting += 1,
                .r_paren, .r_bracket, .r_brace, .dedent => {
                    if (nesting == 0) break;
                    nesting -= 1;
                },
                .pipe => if (nesting == 0) {
                    self.expression_end = index;
                    break;
                },
                .comma, .eof => if (nesting == 0) break,
                else => {},
            }
        }
        defer self.expression_end = previous;
        return self.expression();
    }
    fn collectionLiteral(self: *Parser, is_list: bool, values: []const Id, start: u32) Error!Id {
        const range = try self.list(values);
        // Both use the homogeneous literal node; c distinguishes their types.
        return self.add(.array, range.start, range.len, @intFromBool(is_list), start);
    }
    fn collectionIntrinsic(self: *Parser, name: []const u8, args: []const Id, start: u32) Error!Id {
        var result = try self.add(.intrinsic, try self.intern(name), 0, 0, start);
        for (args) |arg| result = try self.add(.apply, result, arg, 0, start);
        return result;
    }
    fn collectionName(self: *Parser, start: u32) Error!symbols.Symbol {
        var buffer: [80]u8 = undefined;
        const text_ = std.mem.print(&buffer, "$collection.{d}.{d}", .{ start, self.tree.nodes.items.len }) catch unreachable;
        return self.intern(text_);
    }
    fn collectionBinding(self: *Parser, name: symbols.Symbol, value: Id, start: u32) Error!Id {
        const pattern_ = try self.add(.pattern_name, name, 0, 0, start);
        return self.add(.let_stmt, pattern_, value, try self.extra(&.{ 0, 0, 0, 0, 0 }), start);
    }
    fn collectionLoop(self: *Parser, pattern_: Id, value: Id, end: Id, body: Id, explicit: bool, start: u32) Error!Id {
        var expansion: Id = 0;
        if (end == 0) {
            const cursor = try self.collectionName(start);
            const cursor_ref = try self.add(.name, cursor, 0, 0, start);
            const initialize = try self.add(.iterator_bind, cursor, try self.add(.field_access, value, try self.intern("iter"), 0, start), 0, start);
            const step = try self.collectionName(start);
            const next_step = try self.add(.iterator_bind, step, try self.add(.field_access, cursor_ref, try self.intern("next"), 0, start), 0, start);
            const item = try self.collectionName(start);
            const item_pattern = try self.add(.pattern_name, item, 0, 0, start);
            const rest = try self.collectionName(start);
            const rest_pattern = try self.add(.pattern_name, rest, 0, 0, start);
            const pair = try self.listNode(.pattern_product, &.{ item_pattern, rest_pattern }, start);
            const some = try self.add(.pattern_constructor, try self.intern("Some"), pair, 0, start);
            const stop = try self.listNode(.block, &.{try self.add(.break_stmt, 0, 0, 0, start)}, start);
            const unpack = try self.add(.let_stmt, some, try self.add(.name, step, 0, 0, start), try self.extra(&.{ 0, 0, 0, stop, 0 }), start);
            const update = try self.add(.rebind_stmt, cursor_ref, try self.add(.name, rest, 0, 0, start), 0, start);
            const bind = try self.add(.let_stmt, pattern_, try self.add(.name, item, 0, 0, start), try self.extra(&.{ 0, 0, 0, 0, 0 }), start);
            var statements: std.ArrayList(Id) = .empty;
            defer statements.deinit(self.allocator);
            try statements.appendSlice(self.allocator, &.{ next_step, unpack, update, bind });
            try statements.appendSlice(self.allocator, self.tree.children(body));
            const iteration = try self.add(.forever_stmt, try self.listNode(.block, statements.items, start), 0, 0, start);
            expansion = try self.listNode(.block, &.{ initialize, iteration }, start);
        }
        return self.add(.for_stmt, pattern_, value, try self.extra(&.{ end, body, @intFromBool(explicit), expansion }), start);
    }
    fn collection(self: *Parser, is_list: bool, start: u32) Error!Id {
        _ = try self.expect(.l_bracket);
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        var spread: ?usize = null;
        while (!self.at(.r_bracket)) {
            if (self.eat(.ellipsis)) {
                if (spread != null) return self.fail(.unexpected_token);
                spread = values.items.len;
            }
            try values.append(self.allocator, try self.collectionElement());
            if (self.eat(.pipe)) {
                if (spread != null) return self.fail(.unexpected_token);
                if (values.items.len == 1 and self.at(.identifier) and self.peek(1) == .left_arrow)
                    return self.comprehension(is_list, values.items[0], start);
                spread = values.items.len;
                try values.append(self.allocator, try self.expression());
                break;
            }
            if (!self.eat(.comma)) break;
        }
        _ = try self.expect(.r_bracket);
        const spread_index = spread orelse return self.collectionLiteral(is_list, values.items, start);
        // Evaluate the written expressions once, in order, before composing
        // the result. Prepending can then traverse the prefix in reverse.
        var statements: std.ArrayList(Id) = .empty;
        defer statements.deinit(self.allocator);
        var refs: std.ArrayList(Id) = .empty;
        defer refs.deinit(self.allocator);
        for (values.items) |value| {
            const name = try self.collectionName(start);
            try statements.append(self.allocator, try self.collectionBinding(name, value, start));
            try refs.append(self.allocator, try self.add(.name, name, 0, 0, start));
        }
        var result = refs.items[spread_index];
        var index = spread_index;
        while (index != 0) {
            index -= 1;
            result = try self.collectionIntrinsic(if (is_list) "@list.prepend" else "@array.prepend", &.{ result, refs.items[index] }, start);
        }
        for (refs.items[spread_index + 1 ..]) |value|
            result = try self.collectionIntrinsic(if (is_list) "@list.append" else "@array.append", &.{ result, value }, start);
        if (values.items.len == 1) result = try self.collectionIntrinsic(if (is_list) "@list.identity" else "@array.identity", &.{result}, start);
        try statements.append(self.allocator, try self.add(.return_stmt, result, 0, 0, start));
        return self.listNode(.block, statements.items, start);
    }
    const Qualifier = struct { kind: enum { generator, guard, binding }, name: symbols.Symbol = 0, value: Id, start: u32 };
    fn comprehension(self: *Parser, is_list: bool, result: Id, start: u32) Error!Id {
        var qualifiers: std.ArrayList(Qualifier) = .empty;
        defer qualifiers.deinit(self.allocator);
        while (true) {
            const point = self.current().start;
            const qualifier: Qualifier = if (self.eat(.kw_let)) blk: {
                const name = try self.lowerIdentifier();
                _ = try self.expect(.equal);
                break :blk .{ .kind = .binding, .name = name, .value = try self.expression(), .start = point };
            } else if (self.at(.identifier) and self.peek(1) == .left_arrow) blk: {
                const name = try self.lowerIdentifier();
                _ = try self.expect(.left_arrow);
                break :blk .{ .kind = .generator, .name = name, .value = try self.expression(), .start = point };
            } else .{ .kind = .guard, .value = try self.expression(), .start = point };
            try qualifiers.append(self.allocator, qualifier);
            if (!self.eat(.comma)) break;
            if (self.at(.r_bracket)) return self.fail(.expected_expression);
        }
        _ = try self.expect(.r_bracket);
        const accumulator = try self.collectionName(start);
        const initial = try self.collectionBinding(accumulator, try self.collectionLiteral(true, &.{}, start), start);
        const target = try self.add(.name, accumulator, 0, 0, start);
        const receiver = try self.add(.name, accumulator, 0, 0, start);
        const appended = try self.collectionIntrinsic("@list.append", &.{ receiver, result }, start);
        var body = try self.listNode(.block, &.{try self.add(.rebind_stmt, target, appended, 0, start)}, start);
        var index = qualifiers.items.len;
        while (index != 0) {
            index -= 1;
            const qualifier = qualifiers.items[index];
            const statement_ = switch (qualifier.kind) {
                .generator => blk: {
                    const pattern_ = try self.add(.pattern_name, qualifier.name, 0, 0, qualifier.start);
                    break :blk try self.collectionLoop(pattern_, qualifier.value, 0, body, false, qualifier.start);
                },
                .guard => try self.add(.if_stmt, qualifier.value, body, 0, qualifier.start),
                .binding => {
                    const binding = try self.collectionBinding(qualifier.name, qualifier.value, qualifier.start);
                    const children = self.tree.children(body);
                    // listNode may grow extra, so copy the old child IDs first.
                    var joined: std.ArrayList(Id) = .empty;
                    defer joined.deinit(self.allocator);
                    try joined.append(self.allocator, binding);
                    try joined.appendSlice(self.allocator, children);
                    body = try self.listNode(.block, joined.items, qualifier.start);
                    continue;
                },
            };
            body = try self.listNode(.block, &.{statement_}, qualifier.start);
        }
        var final = try self.add(.name, accumulator, 0, 0, start);
        if (!is_list) final = try self.collectionIntrinsic("@array.from_list", &.{final}, start);
        const returned = try self.add(.return_stmt, final, 0, 0, start);
        var statements: std.ArrayList(Id) = .empty;
        defer statements.deinit(self.allocator);
        try statements.append(self.allocator, initial);
        try statements.appendSlice(self.allocator, self.tree.children(body));
        try statements.append(self.allocator, returned);
        return self.listNode(.block, statements.items, start);
    }
    fn record(self: *Parser, name: symbols.Symbol, start: u32) Error!Id {
        _ = try self.expect(.l_brace);
        var fields: std.ArrayList(Id) = .empty;
        defer fields.deinit(self.allocator);
        while (!self.at(.r_brace)) {
            const item_start = self.current().start;
            const key = try self.lowerIdentifier();
            const value = if (self.eat(.colon)) try self.expression() else 0;
            try fields.append(self.allocator, try self.add(.field, key, value, 0, item_start));
            if (!self.eat(.comma)) break;
        }
        _ = try self.expect(.r_brace);
        const range = try self.list(fields.items);
        return self.add(.record, name, range.start, range.len, start);
    }
    fn suite(self: *Parser) Error!Id {
        try self.enter();
        defer self.depth -= 1;
        const start = (try self.expect(.newline)).start;
        _ = try self.expect(.indent);
        var statements: std.ArrayList(Id) = .empty;
        defer statements.deinit(self.allocator);
        self.newlines();
        while (!self.at(.dedent) and !self.at(.eof)) {
            try statements.append(self.allocator, try self.statement());
            if (!self.at(.newline) and !self.at(.dedent)) return self.fail(.expected_token);
            self.newlines();
        }
        _ = try self.expect(.dedent);
        return self.listNode(.block, statements.items, start);
    }
    fn statement(self: *Parser) Error!Id {
        const start = self.current().start;
        if (self.eat(.kw_let)) {
            const pat = try self.pattern();
            const annotation = if (self.eat(.colon)) try self.typeExpression() else 0;
            const constraints = try self.whereClause();
            _ = try self.expect(.equal);
            const value = try self.expression();
            var fallback: Id = 0;
            if (self.eat(.kw_else)) {
                _ = try self.expect(.colon);
                fallback = try self.suite();
            }
            return self.add(.let_stmt, pat, value, try self.extra(&.{ annotation, constraints.predicates.start, constraints.predicates.len, fallback, constraints.node }), start);
        }
        if (self.eat(.kw_return)) {
            const forwarding: u32 = @intFromBool(self.eat(.dollar));
            return self.add(.return_stmt, try self.expression(), forwarding, 0, start);
        }
        if (self.eat(.kw_yield)) return self.add(.yield_stmt, try self.expression(), 0, 0, start);
        if (self.eat(.kw_break)) return self.add(.break_stmt, 0, 0, 0, start);
        if (self.at(.kw_if)) return self.ifStatement();
        if (self.at(.kw_for)) return self.forStatement();
        if (self.eat(.kw_use)) {
            if ((self.at(.type_identifier) or self.at(.kw_true) or self.at(.kw_false)) and self.hasUseBinding()) return self.identifierSyntax();
            if (self.at(.identifier) and self.hasUseBinding()) {
                const name = try self.lowerIdentifier();
                const annotation = if (self.eat(.colon)) try self.typeExpression() else 0;
                _ = try self.expect(.left_arrow);
                return self.add(.use_stmt, name, try self.expression(), annotation, start);
            }
            return self.add(.use_stmt, 0, try self.expression(), 0, start);
        }
        if ((self.at(.type_identifier) or self.at(.kw_true) or self.at(.kw_false)) and self.hasRebinding()) return self.identifierSyntax();
        if (self.at(.identifier) and self.hasRebinding()) {
            const name = try self.lowerIdentifier();
            var target = try self.add(.name, name, 0, 0, start);
            while (self.at(.dot) or self.at(.l_bracket)) {
                if (self.at(.dot)) {
                    const dot = self.advance();
                    const member = try self.identifier();
                    target = try self.add(.field_access, target, member, 0, start);
                    try self.tree.operator_origins.append(self.allocator, .{ .node = target, .span = .{ .start = dot.start, .end = dot.end }, .member = member });
                } else {
                    _ = self.advance();
                    const index = try self.expression();
                    _ = try self.expect(.r_bracket);
                    target = try self.add(.index_access, target, index, 0, start);
                }
            }
            _ = try self.expect(.colon_equal);
            return self.add(.rebind_stmt, target, try self.expression(), 0, start);
        }
        return self.expression();
    }
    // A colon also starts an expression witness. Only a top-level left arrow
    // in this statement makes the initial name an effect-binding declaration.
    fn hasUseBinding(self: *const Parser) bool {
        if (self.peek(1) == .left_arrow) return true;
        if (self.peek(1) != .colon) return false;
        var nesting: usize = 0;
        var i = self.index + 2;
        while (i < self.tokens.len) : (i += 1) {
            const tag = self.tokens[i].tag;
            if (nesting == 0) switch (tag) {
                .left_arrow => return true,
                .newline, .dedent, .eof => return false,
                else => {},
            };
            switch (tag) {
                .l_paren, .l_bracket, .l_brace => nesting += 1,
                .r_paren, .r_bracket, .r_brace => if (nesting != 0) {
                    nesting -= 1;
                },
                else => {},
            }
        }
        return false;
    }
    // Classify before allocating a target. An ordinary call such as f [a, b]
    // must not speculatively parse the argument as a rebinding index.
    fn hasRebinding(self: *const Parser) bool {
        var nesting: usize = 0;
        var i = self.index;
        while (i < self.tokens.len) : (i += 1) {
            const tag = self.tokens[i].tag;
            if (nesting == 0) switch (tag) {
                .colon_equal => return true,
                .newline, .dedent, .eof => return false,
                else => {},
            };
            switch (tag) {
                .l_paren, .l_bracket, .l_brace => nesting += 1,
                .r_paren, .r_bracket, .r_brace => if (nesting != 0) {
                    nesting -= 1;
                },
                else => {},
            }
        }
        return false;
    }
    fn trailingElse(self: *Parser) Error!Id {
        const saved = self.index;
        self.newlines();
        if (!self.eat(.kw_else)) {
            self.index = saved;
            return 0;
        }
        _ = try self.expect(.colon);
        return self.suite();
    }
    fn ifStatement(self: *Parser) Error!Id {
        const start = (try self.expect(.kw_if)).start;
        if (self.eat(.kw_let)) {
            const pat = try self.pattern();
            _ = try self.expect(.equal);
            const value = try self.expression();
            _ = try self.expect(.colon);
            const body = try self.suite();
            const fallback = try self.trailingElse();
            return self.add(.if_let_stmt, pat, value, try self.extra(&.{ body, fallback }), start);
        }
        const condition = try self.expression();
        if (self.eat(.kw_then)) {
            const consequence = try self.expression();
            _ = try self.expect(.kw_else);
            return self.add(.if_expr, condition, consequence, try self.expression(), start);
        }
        _ = try self.expect(.colon);
        const body = try self.suite();
        return self.add(.if_stmt, condition, body, try self.trailingElse(), start);
    }
    fn forStatement(self: *Parser) Error!Id {
        const start = (try self.expect(.kw_for)).start;
        if (self.eat(.kw_ever)) {
            _ = try self.expect(.colon);
            return self.add(.forever_stmt, try self.suite(), 0, 0, start);
        }
        const explicit = self.eat(.kw_let);
        var has_in = explicit;
        var i = self.index;
        var nesting: usize = 0;
        while (i < self.tokens.len) : (i += 1) {
            const t = self.tokens[i].tag;
            if (nesting == 0 and (t == .colon or t == .newline or t == .eof)) break;
            if (nesting == 0 and t == .kw_in) {
                has_in = true;
                break;
            }
            if (t == .l_paren or t == .l_bracket or t == .l_brace) nesting += 1;
            if ((t == .r_paren or t == .r_bracket or t == .r_brace) and nesting != 0) nesting -= 1;
        }
        if (has_in) {
            const pat = try self.pattern();
            _ = try self.expect(.kw_in);
            const value = try self.expression();
            const end = if (self.eat(.dot_dot)) try self.expression() else 0;
            _ = try self.expect(.colon);
            const body = try self.suite();
            return self.collectionLoop(pat, value, end, body, explicit, start);
        }
        const first = try self.expression();
        _ = try self.expect(.dot_dot);
        const end = try self.expression();
        _ = try self.expect(.colon);
        return self.add(.range_stmt, first, end, try self.suite(), start);
    }
    // Named and structural record patterns share field parsing.
    fn constructorFields(self: *Parser) Error!Id {
        try self.enter();
        defer self.depth -= 1;
        const start = (try self.expect(.l_brace)).start;
        var fields: std.ArrayList(Id) = .empty;
        defer fields.deinit(self.allocator);
        while (!self.at(.r_brace)) {
            const item_start = self.current().start;
            const name = try self.lowerIdentifier();
            const value = if (self.eat(.colon)) try self.pattern() else 0;
            try fields.append(self.allocator, try self.add(.pattern_field, name, value, 0, item_start));
            if (!self.eat(.comma)) break;
        }
        _ = try self.expect(.r_brace);
        return self.listNode(.pattern_record, fields.items, start);
    }
    fn pattern(self: *Parser) Error!Id {
        try self.enter();
        defer self.depth -= 1;
        const t = self.current();
        const start = t.start;
        if (self.eat(.caret)) return self.add(.pattern_value, try self.qualified(), 0, 0, start);
        if (self.at(.type_identifier) or self.at(.kw_true) or self.at(.kw_false)) return self.identifierSyntax();
        if (self.at(.identifier)) return self.add(.pattern_name, try self.lowerIdentifier(), 0, 0, start);
        if (self.eat(.integer)) return self.integerLiteral(t, .pattern_integer);
        if (self.eat(.hash)) {
            if (self.at(.kw_true) or self.at(.kw_false)) {
                const value: u32 = @intFromBool(self.eat(.kw_true));
                if (value == 0) _ = try self.expect(.kw_false);
                return self.add(.pattern_boolean, value, 0, 0, start);
            }
            const name = try self.constructorPatternName();
            const payload = if (self.at(.l_brace)) try self.constructorFields() else if (patternTag(self.current().tag)) try self.pattern() else 0;
            return self.add(.pattern_constructor, name, payload, 0, start);
        }
        if (self.at(.l_brace)) return self.constructorFields();
        if (self.eat(.l_paren)) {
            var values: std.ArrayList(Id) = .empty;
            defer values.deinit(self.allocator);
            var tuple = false;
            while (!self.at(.r_paren)) {
                try values.append(self.allocator, try self.pattern());
                if (!self.eat(.comma)) break;
                tuple = true;
            }
            _ = try self.expect(.r_paren);
            if (!tuple and values.items.len == 1) return values.items[0];
            return self.listNode(.pattern_product, values.items, start);
        }
        return self.fail(.expected_pattern);
    }
    fn patternRow(self: *Parser) Error!Id {
        const start = self.current().start;
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        try values.append(self.allocator, try self.pattern());
        while (self.eat(.comma)) try values.append(self.allocator, try self.pattern());
        return self.listNode(.pattern_row, values.items, start);
    }
    fn caseExpression(self: *Parser) Error!Id {
        const start = (try self.expect(.kw_case)).start;
        const request_name = self.at(.identifier) and self.peek(1) == .kw_of;
        var values: std.ArrayList(Id) = .empty;
        defer values.deinit(self.allocator);
        try values.append(self.allocator, try self.expression());
        while (self.eat(.comma)) try values.append(self.allocator, try self.expression());
        _ = try self.expect(.kw_of);
        _ = try self.expect(.newline);
        _ = try self.expect(.indent);
        self.newlines();
        var arms: std.ArrayList(Id) = .empty;
        defer arms.deinit(self.allocator);
        const requests = self.at(.kw_effect) or self.at(.kw_complete);
        if (requests and !request_name) return self.identifierSyntax();
        while (!self.at(.dedent) and !self.at(.eof)) {
            const item_start = self.current().start;
            if (requests) {
                const complete = self.eat(.kw_complete);
                var operation: Id = 0;
                if (!complete) {
                    _ = try self.expect(.kw_effect);
                    const operation_token = self.current().tag;
                    if (operation_token != .identifier and operation_token != .type_identifier and operation_token != .l_paren) return self.identifierSyntax();
                    // Braces after an operation name belong to its payload
                    // pattern, rather than an ordinary record application.
                    const operation_start = self.current().start;
                    operation = if (operation_token == .l_paren) try self.atom() else try self.add(.name, try self.qualified(), 0, 0, operation_start);
                }
                const pat = try self.pattern();
                _ = try self.expect(.fat_arrow);
                const body = try self.suite();
                try arms.append(self.allocator, try self.add(.request_arm, operation, pat, body, item_start));
            } else {
                var rows: std.ArrayList(Id) = .empty;
                defer rows.deinit(self.allocator);
                try rows.append(self.allocator, try self.patternRow());
                while (self.eat(.pipe)) try rows.append(self.allocator, try self.patternRow());
                const guard = if (self.eat(.kw_if)) try self.expression() else 0;
                _ = try self.expect(.fat_arrow);
                const body = try self.expression();
                const range = try self.list(rows.items);
                try arms.append(self.allocator, try self.add(.case_arm, range.start, range.len, try self.extra(&.{ guard, body }), item_start));
            }
            if (!self.at(.newline) and !self.at(.dedent)) return self.fail(.expected_token);
            self.newlines();
        }
        _ = try self.expect(.dedent);
        const inputs = try self.list(values.items);
        const cases = try self.list(arms.items);
        return self.add(if (requests) .request_case else .case_expr, try self.extra(&.{ inputs.start, inputs.len }), cases.start, cases.len, start);
    }
};
fn operatorTag(tag: Tag) bool {
    return switch (tag) {
        .symbol, .dollar, .star, .caret, .pipe => true,
        else => false,
    };
}
fn atomTag(tag: Tag) bool {
    return switch (tag) {
        .integer, .float, .string, .intrinsic, .identifier, .type_identifier, .selector, .hash, .l_paren, .l_bracket, .l_brace, .colon => true,
        else => false,
    };
}
fn typeAtomTag(tag: Tag) bool {
    return switch (tag) {
        .identifier, .type_identifier, .l_paren, .l_bracket, .l_brace, .tilde => true,
        else => false,
    };
}
fn patternTag(tag: Tag) bool {
    return switch (tag) {
        .identifier, .integer, .hash, .caret, .l_paren, .l_brace => true,
        else => false,
    };
}
