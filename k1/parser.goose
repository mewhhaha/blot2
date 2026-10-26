// Experimental lexer-to-owned-Arena scalar parser. It is not integrated into
// K1 source admission or the production driver.
namespace parser;
import lexer;
import syntax;
import frontend;
import scalar_core;
import validate;

struct Cursor { lex: lexer::State = lexer::State {}, current: lexer::Token = lexer::Token {}, status: i64 = 0 }
fn advance(source: u8[:], cursor: Cursor&) {
    cursor.current = lexer::next(source, cursor.lex);
    if cursor.current.kind == 9 { cursor.status = cursor.current.status; }
}
fn is_word(source: u8[:], tok: lexer::Token, text: u8[:]) -> bool {
    return tok.kind == 1 && source[tok.start..tok.end] == text;
}
fn is_symbol(source: u8[:], tok: lexer::Token, text: u8[:]) -> bool {
    return tok.kind == 5 && source[tok.start..tok.end] == text;
}
fn reject(cursor: Cursor&) {
    if cursor.status == 0 { cursor.status = if cursor.current.kind == 0 { 1 } else { 2 }; }
}
fn word(source: u8[:], cursor: Cursor&, text: u8[:]) -> bool {
    if cursor.status != 0 { return false; }
    if !is_word(source, cursor.current, text) { reject(cursor); return false; }
    advance(source, cursor); return cursor.status == 0;
}
fn symbol(source: u8[:], cursor: Cursor&, text: u8[:]) -> bool {
    if cursor.status != 0 { return false; }
    if !is_symbol(source, cursor.current, text) { reject(cursor); return false; }
    advance(source, cursor); return cursor.status == 0;
}
fn kind(source: u8[:], cursor: Cursor&, expected: i64) -> bool {
    if cursor.status != 0 { return false; }
    if cursor.current.kind != expected { reject(cursor); return false; }
    advance(source, cursor); return cursor.status == 0;
}
fn identifier(source: u8[:], tok: lexer::Token) -> bool {
    return tok.kind == 1 && validate::name_valid(source[tok.start..tok.end]);
}
fn atom(source: u8[:], cursor: Cursor&, parameter: lexer::Token) -> bool {
    if cursor.status != 0 { return false; }
    let t = cursor.current;
    if t.kind == 1 {
        if source[t.start..t.end] != source[parameter.start..parameter.end] { cursor.status = 3; return false; }
    } else if t.kind != 2 { reject(cursor); return false; }
    advance(source, cursor); return cursor.status == 0;
}

// Status: 0 parsed, 1 syntax, 2 unsupported, 3 unbound, 4 missing return,
// 5 input/nesting limit, 6 bad control target, 7 type mismatch. Error carries
// an empty Arena. This deliberately recognizes only a single scalar declaration.
fn parse(source: u8[:]) -> syntax::Arena, i64 {
    var cursor = Cursor { lex: lexer::init(source) };
    advance(source, cursor);
    while cursor.status == 0 && cursor.current.kind == 6 { advance(source, cursor); }
    if cursor.status != 0 { return syntax::Arena {}, cursor.status; }
    let declaration = cursor.current;
    if !word(source, cursor, "let") { return syntax::Arena {}, cursor.status; }
    if !identifier(source, cursor.current) { return syntax::Arena {}, 1; }
    advance(source, cursor);
    if !symbol(source, cursor, ":") || !word(source, cursor, "U32") || !symbol(source, cursor, "->") {
        return syntax::Arena {}, cursor.status;
    }
    var result_type: i64 = 0;
    if is_word(source, cursor.current, "U32") { result_type = 1; }
    else if is_word(source, cursor.current, "Bool") { result_type = 2; }
    else { reject(cursor); return syntax::Arena {}, cursor.status; }
    advance(source, cursor);
    if !symbol(source, cursor, "=") { return syntax::Arena {}, cursor.status; }
    let function = cursor.current;
    if !word(source, cursor, "fn") { return syntax::Arena {}, cursor.status; }
    let parameter = cursor.current;
    if !identifier(source, parameter) { return syntax::Arena {}, 1; }
    advance(source, cursor);
    if !symbol(source, cursor, "=>") { return syntax::Arena {}, cursor.status; }
    var body_suite = false;
    if is_word(source, cursor.current, "do") {
        body_suite = true; advance(source, cursor);
        if !symbol(source, cursor, ":") || !kind(source, cursor, 6) || !kind(source, cursor, 7) {
            return syntax::Arena {}, cursor.status;
        }
    }
    let outer_return = cursor.current;
    if is_word(source, cursor.current, "break") || is_word(source, cursor.current, "continue") {
        return syntax::Arena {}, 6;
    }
    if !is_word(source, cursor.current, "return") {
        if cursor.current.kind == 1 || cursor.current.kind == 2 { return syntax::Arena {}, 4; }
        reject(cursor); return syntax::Arena {}, cursor.status;
    }
    advance(source, cursor);
    var value_suite = false;
    var value_do = lexer::Token {};
    var inner_transfer = lexer::Token {};
    var inner_kind: i64 = 0;
    if is_word(source, cursor.current, "do") {
        value_suite = true; value_do = cursor.current; advance(source, cursor);
        if !symbol(source, cursor, ":") || !kind(source, cursor, 6) || !kind(source, cursor, 7) {
            return syntax::Arena {}, cursor.status;
        }
        inner_transfer = cursor.current;
        if is_word(source, cursor.current, "break") { inner_kind = 8; }
        else if is_word(source, cursor.current, "return") { inner_kind = 7; }
        else if is_word(source, cursor.current, "continue") { return syntax::Arena {}, 6; }
        else {
            if cursor.current.kind == 1 || cursor.current.kind == 2 { return syntax::Arena {}, 4; }
            reject(cursor); return syntax::Arena {}, cursor.status;
        }
        advance(source, cursor);
    }
    if is_word(source, cursor.current, "break") || is_word(source, cursor.current, "continue") {
        return syntax::Arena {}, 6;
    }
    let left = cursor.current;
    if !atom(source, cursor, parameter) { return syntax::Arena {}, cursor.status; }
    var operation = lexer::Token {};
    var right = lexer::Token {};
    var binary: i64 = 0;
    var expression_end = left.end;
    if is_symbol(source, cursor.current, "&") || is_symbol(source, cursor.current, "<") {
        operation = cursor.current;
        binary = if is_symbol(source, operation, "&") { 1 } else { 2 };
        advance(source, cursor);
        right = cursor.current;
        if !atom(source, cursor, parameter) { return syntax::Arena {}, cursor.status; }
        expression_end = right.end;
    }
    if (binary == 2 && result_type != 2) || (binary != 2 && result_type != 1) { return syntax::Arena {}, 7; }
    if cursor.current.kind == 6 { advance(source, cursor); }
    if value_suite && !kind(source, cursor, 8) { return syntax::Arena {}, cursor.status; }
    if body_suite && !kind(source, cursor, 8) { return syntax::Arena {}, cursor.status; }
    while cursor.status == 0 && cursor.current.kind == 6 { advance(source, cursor); }
    if cursor.status != 0 { return syntax::Arena {}, cursor.status; }
    if cursor.current.kind != 0 { return syntax::Arena {}, 2; }

    var nodes: syntax::Node[>..] = [];
    nodes.push(syntax::Node { tag: 0, start: 0, end: source.len }); // 1
    nodes.push(syntax::Node { tag: 1, start: declaration.start, end: expression_end, parent: 1 }); // 2
    nodes.push(syntax::Node { tag: 2, start: function.start, end: expression_end, parent: 2 }); // 3
    nodes.push(syntax::Node { tag: 1, start: parameter.start, end: parameter.end, parent: 3 }); // 4
    nodes.push(syntax::Node { tag: 7, start: outer_return.start, end: expression_end, parent: 3, target: 3 }); // 5
    var expression_parent: i64 = 5;
    if value_suite {
        nodes.push(syntax::Node { tag: 3, start: value_do.start, end: expression_end, parent: 5 }); // 6
        nodes.push(syntax::Node { tag: inner_kind, start: inner_transfer.start, end: expression_end,
            parent: 6, target: if inner_kind == 8 { 6 } else { 3 } }); // 7
        expression_parent = 7;
    }
    let expression_id = nodes.len + 1;
    nodes.push(syntax::Node { tag: 1, start: left.start, end: expression_end, parent: expression_parent });
    nodes.push(syntax::Node { tag: 1, start: left.start, end: left.end, parent: expression_id });
    if binary != 0 {
        nodes.push(syntax::Node { tag: 1, start: operation.start, end: operation.end, parent: expression_id });
        nodes.push(syntax::Node { tag: 1, start: right.start, end: right.end, parent: expression_id });
    }
    var arena, ok = syntax::own(source, nodes);
    if !ok { return syntax::Arena {}, 5; }
    if !verify(arena) { return syntax::Arena {}, 1; }
    return arena, 0;
}

fn exact(arena: syntax::Arena&, index: i64, tag: i64, start: i64, end: i64,
         parent: i64, target: i64) -> bool {
    if index < 0 || index >= arena.nodes.len { return false; }
    let node = arena.nodes[index];
    return node.tag == tag && node.start == start && node.end == end &&
        node.parent == parent && node.target == target && node.reference == 0;
}

// Separately check source spelling and the canonical Arena shape. Scalar
// syntax is re-recognized by the independent scalar validator; that validator
// does not inspect this Arena. The Arena check below independently derives
// control targets and token spans and checks every node, including unused links.
fn verify(arena: syntax::Arena&) -> bool {
    if syntax::validate(arena) != 0 { return false; }
    let source = arena.source[..];
    let parsed = frontend::parse_scalar(source);
    if parsed.status != 0 { return false; }
    var core = scalar_core::build(parsed.result_type, parsed.binary_op, parsed.kind,
        parsed.literal, parsed.right_kind, parsed.right_literal);
    core.name_start = parsed.name_start; core.name_end = parsed.name_end;
    core.parameter_start = parsed.parameter_start; core.parameter_end = parsed.parameter_end;
    core.left_start = parsed.start; core.left_end = parsed.end;
    core.operator_start = parsed.operator_start; core.operator_end = parsed.operator_end;
    core.right_start = parsed.right_start; core.right_end = parsed.right_end;
    if validate::scalar_v2(source, core, "k1", "K1-SEM-POLICY-1",
       "K1-OPT-POLICY-1", "K1-WASM32-ABI1") != 0 { return false; }

    var lex = lexer::init(source);
    var t = lexer::next(source, lex);
    var declaration = lexer::Token {};
    var function = lexer::Token {};
    var outer_return = lexer::Token {};
    var value_do = lexer::Token {};
    var inner = lexer::Token {};
    var found_declaration = false;
    var found_function = false;
    var found_return = false;
    var found_value = false;
    var found_inner = false;
    var count: i64 = 0;
    while t.kind != 0 {
        if t.kind == 9 || count >= 64 { return false; }
        count += 1;
        if !found_declaration && is_word(source, t, "let") { declaration = t; found_declaration = true; }
        else if !found_function && is_word(source, t, "fn") { function = t; found_function = true; }
        else if !found_return && is_word(source, t, "return") { outer_return = t; found_return = true; }
        else if found_return && !found_value && is_word(source, t, "do") { value_do = t; found_value = true; }
        else if found_value && !found_inner && (is_word(source, t, "return") || is_word(source, t, "break")) {
            inner = t; found_inner = true;
        }
        t = lexer::next(source, lex);
    }
    if !found_declaration || !found_function || !found_return || (found_value && !found_inner) { return false; }
    let expression_end = if parsed.binary_op == 0 { parsed.end } else { parsed.right_end };
    let expected_count = 7 + (if found_value { 2 } else { 0 }) + (if parsed.binary_op != 0 { 2 } else { 0 });
    if arena.nodes.len != expected_count { return false; }
    if !exact(arena, 0, 0, 0, source.len, 0, 0) ||
       !exact(arena, 1, 1, declaration.start, expression_end, 1, 0) ||
       !exact(arena, 2, 2, function.start, expression_end, 2, 0) ||
       !exact(arena, 3, 1, parsed.parameter_start, parsed.parameter_end, 3, 0) ||
       !exact(arena, 4, 7, outer_return.start, expression_end, 3, 3) { return false; }
    var expression_parent: i64 = 5;
    var expr_index: i64 = 5;
    if found_value {
        let tag = if is_word(source, inner, "break") { 8 } else { 7 };
        let target = if tag == 8 { 6 } else { 3 };
        if !exact(arena, 5, 3, value_do.start, expression_end, 5, 0) ||
           !exact(arena, 6, tag, inner.start, expression_end, 6, target) { return false; }
        expression_parent = 7; expr_index = 7;
    }
    let expr_id = expr_index + 1;
    if !exact(arena, expr_index, 1, parsed.start, expression_end, expression_parent, 0) ||
       !exact(arena, expr_index + 1, 1, parsed.start, parsed.end, expr_id, 0) { return false; }
    if parsed.binary_op != 0 {
        if !exact(arena, expr_index + 2, 1, parsed.operator_start, parsed.operator_end, expr_id, 0) ||
           !exact(arena, expr_index + 3, 1, parsed.right_start, parsed.right_end, expr_id, 0) { return false; }
    }
    return true;
}
