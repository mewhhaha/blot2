// Experimental source-only frontend for the restricted v3 module subset.
// No production driver or public K1 admission uses this model.
namespace module_frontend;
import lexer;
import frontend;
import scalar_core;
import validate;
import module_core;

struct Declaration {
    declaration_start: i64 = 0, declaration_end: i64 = 0,
    name_start: i64 = 0, name_end: i64 = 0,
    function_start: i64 = 0,
    parameter_start: i64 = 0, parameter_end: i64 = 0,
    return_start: i64 = 0,
    expression_start: i64 = 0, expression_end: i64 = 0,
    left_start: i64 = 0, left_end: i64 = 0,
    operator_start: i64 = 0, operator_end: i64 = 0,
    right_start: i64 = 0, right_end: i64 = 0,
    callee_start: i64 = 0, callee_end: i64 = 0,
    form: i64 = 0, left_kind: i64 = 0, left_literal: u32 = 0,
    right_kind: i64 = 0, right_literal: u32 = 0,
    callee_id: i64 = 0, depth: i64 = 0
}
struct Module { source: u8[] = [], declarations: Declaration[] = [] }
struct Cursor { lex: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, status: i64 = 0 }
struct Atom { ok: bool = false, kind: i64 = 0, literal: u32 = 0, start: i64 = 0, end: i64 = 0 }
fn advance(source: u8[:], c: Cursor&) {
    c.token = lexer::next(source, c.lex);
    if c.token.kind == 9 { c.status = c.token.status; }
}
fn word(source: u8[:], token: lexer::Token, text: u8[:]) -> bool {
    return token.kind == 1 && span(token.start, token.end, source.len) && source[token.start..token.end] == text;
}
fn symbol(source: u8[:], token: lexer::Token, text: u8[:]) -> bool {
    return token.kind == 5 && span(token.start, token.end, source.len) && source[token.start..token.end] == text;
}
fn reject(c: Cursor&) { if c.status == 0 { c.status = if c.token.kind == 0 { 1 } else { 2 }; } }
fn take_word(source: u8[:], c: Cursor&, text: u8[:]) -> bool {
    if c.status != 0 { return false; }
    if !word(source, c.token, text) { reject(c); return false; }
    advance(source, c); return c.status == 0;
}
fn take_symbol(source: u8[:], c: Cursor&, text: u8[:]) -> bool {
    if c.status != 0 { return false; }
    if !symbol(source, c.token, text) { reject(c); return false; }
    advance(source, c); return c.status == 0;
}
fn take_kind(source: u8[:], c: Cursor&, k: i64) -> bool {
    if c.status != 0 { return false; }
    if c.token.kind != k { reject(c); return false; }
    advance(source, c); return c.status == 0;
}
fn identifier(source: u8[:], t: lexer::Token) -> bool {
    return t.kind == 1 && span(t.start, t.end, source.len) && validate::name_valid(source[t.start..t.end]);
}
fn atom(source: u8[:], c: Cursor&, parameter: lexer::Token) -> Atom {
    if c.status != 0 { return Atom {}; }
    let t = c.token;
    if !span(t.start, t.end, source.len) || !span(parameter.start, parameter.end, source.len) { c.status = 1; return Atom {}; }
    var a = Atom { start: t.start, end: t.end };
    if t.kind == 1 {
        advance(source, c);
        if c.status != 0 { return Atom {}; }
        if symbol(source, c.token, "(") { c.status = 2; return Atom {}; }
        if source[t.start..t.end] != source[parameter.start..parameter.end] { c.status = 3; return Atom {}; }
        a.ok = true;
        return a;
    } else if t.kind == 2 {
        var n: u64 = 0;
        for i in t.start..t.end {
            if source[i] < '0' || source[i] > '9' { c.status = 1; return Atom {}; }
            let d = (source[i] - '0') as u64;
            if n > (4294967295 - d) / 10 { c.status = 1; return Atom {}; }
            n = n * 10 + d;
        }
        a.kind = 1; a.literal = n as u32;
    } else { reject(c); return Atom {}; }
    advance(source, c);
    a.ok = c.status == 0;
    return a;
}
fn same_name(source: u8[:], a_start: i64, a_end: i64, b_start: i64, b_end: i64) -> bool {
    return span(a_start, a_end, source.len) && span(b_start, b_end, source.len) &&
        source[a_start..a_end] == source[b_start..b_end];
}

// Returns a fully resolved owned module, or an empty module and a status.
fn parse(source: u8[:]) -> Module, i64 {
    var c = Cursor { lex: lexer::init(source) };
    advance(source, c);
    var declarations: Declaration[>..] = [];
    while c.status == 0 {
        while c.status == 0 && c.token.kind == 6 { advance(source, c); }
        if c.status != 0 { break; }
        if c.token.kind == 0 { break; }
        if c.token.kind == 7 || c.token.kind == 8 { return Module {}, 1; }
        if declarations.len >= 256 { return Module {}, 2; }
        let start = c.token.start;
        if !take_word(source, c, "let") { return Module {}, c.status; }
        let name = c.token;
        if !identifier(source, name) { return Module {}, 1; }
        for previous in declarations {
            if same_name(source, name.start, name.end, previous.name_start, previous.name_end) { return Module {}, 1; }
        }
        advance(source, c);
        if !take_symbol(source, c, ":") || !take_word(source, c, "U32") ||
           !take_symbol(source, c, "->") || !take_word(source, c, "U32") ||
           !take_symbol(source, c, "=") { return Module {}, c.status; }
        let function_start = c.token.start;
        if !take_word(source, c, "fn") { return Module {}, c.status; }
        let parameter = c.token;
        if !identifier(source, parameter) { return Module {}, 1; }
        advance(source, c);
        if !take_symbol(source, c, "=>") { return Module {}, c.status; }
        var body_suite = false;
        if word(source, c.token, "do") {
            body_suite = true; advance(source, c);
            if !take_symbol(source, c, ":") || !take_kind(source, c, 6) || !take_kind(source, c, 7) { return Module {}, c.status; }
        }
        let return_start = c.token.start;
        if word(source, c.token, "break") || word(source, c.token, "continue") { return Module {}, 6; }
        if !word(source, c.token, "return") {
            if c.token.kind == 1 || c.token.kind == 2 { return Module {}, 4; }
            reject(c); return Module {}, c.status;
        }
        advance(source, c);
        var value_suite = false;
        if word(source, c.token, "do") {
            value_suite = true; advance(source, c);
            if !take_symbol(source, c, ":") || !take_kind(source, c, 6) || !take_kind(source, c, 7) { return Module {}, c.status; }
            if word(source, c.token, "continue") { return Module {}, 6; }
            if !word(source, c.token, "break") && !word(source, c.token, "return") {
                if c.token.kind == 1 || c.token.kind == 2 { return Module {}, 4; }
                reject(c); return Module {}, c.status;
            }
            advance(source, c);
        }
        var decl = Declaration { declaration_start: start, name_start: name.start, name_end: name.end,
            function_start: function_start, parameter_start: parameter.start, parameter_end: parameter.end,
            return_start: return_start, expression_start: c.token.start };
        let first = c.token;
        if c.status != 0 { return Module {}, c.status; }
        if first.kind == 1 {
            advance(source, c);
            if symbol(source, c.token, "(") {
                if !identifier(source, first) { return Module {}, 1; }
                decl.form = 3; decl.callee_start = first.start; decl.callee_end = first.end;
                if same_name(source, first.start, first.end, parameter.start, parameter.end) { return Module {}, 7; }
                advance(source, c);
                let a = atom(source, c, parameter);
                if !a.ok { return Module {}, c.status; }
                decl.left_kind = a.kind; decl.left_literal = a.literal; decl.left_start = a.start; decl.left_end = a.end;
                decl.expression_end = c.token.end;
                if !take_symbol(source, c, ")") { return Module {}, c.status; }
            } else {
                if !same_name(source, first.start, first.end, parameter.start, parameter.end) { return Module {}, 3; }
                decl.form = 1; decl.left_start = first.start; decl.left_end = first.end; decl.expression_end = first.end;
            }
        } else {
            let a = atom(source, c, parameter);
            if !a.ok { return Module {}, c.status; }
            decl.form = 1; decl.left_kind = a.kind; decl.left_literal = a.literal;
            decl.left_start = a.start; decl.left_end = a.end; decl.expression_end = a.end;
        }
        if decl.form == 1 && symbol(source, c.token, "&") {
            decl.form = 2; decl.operator_start = c.token.start; decl.operator_end = c.token.end;
            advance(source, c);
            let right = atom(source, c, parameter);
            if !right.ok { return Module {}, c.status; }
            decl.right_kind = right.kind; decl.right_literal = right.literal;
            decl.right_start = right.start; decl.right_end = right.end; decl.expression_end = right.end;
        }
        decl.declaration_end = decl.expression_end;
        var ended_line = false;
        if c.token.kind == 6 { ended_line = true; advance(source, c); }
        if value_suite && !take_kind(source, c, 8) { return Module {}, c.status; }
        if body_suite && !take_kind(source, c, 8) { return Module {}, c.status; }
        if c.status != 0 { return Module {}, c.status; }
        if c.token.kind != 0 && !ended_line { return Module {}, 2; }
        declarations.push(decl);
    }
    if c.status != 0 { return Module {}, c.status; }
    if declarations.len == 0 { return Module {}, 1; }
    // Name resolution sees all declarations, including forward references.
    for i in declarations.len {
        if declarations[i].form == 3 {
            var found: i64 = -1;
            for j in declarations.len {
                if same_name(source, declarations[i].callee_start, declarations[i].callee_end,
                             declarations[j].name_start, declarations[j].name_end) { found = j; break; }
            }
            if found < 0 { return Module {}, 3; }
            declarations[i].callee_id = found;
        }
    }
    // Detect cycles before depth overflow so recursion always has its category.
    for root in declarations.len {
        var seen: u8[256] = [0; 256];
        var current = root;
        loop {
            if seen[current] != 0 { return Module {}, 8; }
            seen[current] = 1;
            if declarations[current].form != 3 { break; }
            current = declarations[current].callee_id;
        }
    }
    for root in declarations.len {
        var current = root;
        var depth: i64 = 1;
        while declarations[current].form == 3 {
            current = declarations[current].callee_id;
            depth += 1;
        }
        if depth > 128 { return Module {}, 9; }
        declarations[root].depth = depth;
    }
    var candidate = Module { source: source, declarations: copy(declarations) };
    // Never publish a candidate the independent source validator rejects.
    if verify(candidate) != 0 { return Module {}, 2; }
    return candidate, 0;
}

fn span(start: i64, end: i64, bound: i64) -> bool {
    return start >= 0 && start < end && end <= bound;
}
fn blank_right(d: Declaration) -> bool {
    return d.right_start == 0 && d.right_end == 0 && d.right_kind == 0 && d.right_literal == 0;
}
fn blank_operator(d: Declaration) -> bool { return d.operator_start == 0 && d.operator_end == 0; }
fn blank_callee(d: Declaration) -> bool { return d.callee_start == 0 && d.callee_end == 0 && d.callee_id == 0; }

// Verify a call as exactly identifier '(' one atom ')' using a fresh lexer.
// Spans are checked against the original source, not inferred from the record.
fn call_syntax(source: u8[:], d: Declaration) -> bool {
    if !span(d.expression_start, d.expression_end, source.len) ||
       !span(d.callee_start, d.callee_end, source.len) || !span(d.left_start, d.left_end, source.len) ||
       d.callee_start != d.expression_start || d.callee_end > d.left_start ||
       d.left_end > d.expression_end { return false; }
    let bytes = source[d.expression_start..d.expression_end];
    var state = lexer::init(bytes);
    var t = lexer::next(bytes, state);
    if t.kind != 1 || t.start != 0 || t.end != d.callee_end - d.expression_start ||
       !validate::name_valid(bytes[t.start..t.end]) { return false; }
    t = lexer::next(bytes, state);
    if !symbol(bytes, t, "(") { return false; }
    t = lexer::next(bytes, state);
    if t.start + d.expression_start != d.left_start || t.end + d.expression_start != d.left_end ||
       (t.kind != 1 && t.kind != 2) { return false; }
    t = lexer::next(bytes, state);
    if !symbol(bytes, t, ")") || t.end != bytes.len { return false; }
    return lexer::next(bytes, state).kind == 0;
}

// Independent source/record validation. It does not call parse or reuse the
// parser's resolution/depth results as authority. The old scalar validator
// independently recognizes each source body; calls are projected to their
// argument only after call_syntax validates every removed call token/span.
fn verify(module: Module&) -> i64 {
    let source = module.source[..];
    if source.len > 16777216 || module.declarations.len < 1 || module.declarations.len > 256 { return 1; }
    var lex = lexer::init(source);
    if lex.error_status != 0 { return 1; }
    var token = lexer::next(source, lex);
    var index: i64 = 0;
    var declaration_tokens: i64 = 0;
    while token.kind != 0 {
        if token.kind == 9 { return 1; }
        if token.kind != 6 && token.kind != 8 {
            while index < module.declarations.len && token.start >= module.declarations[index].declaration_end { index += 1; }
            if index >= module.declarations.len { return 1; }
            let d = module.declarations[index];
            if token.start < d.declaration_start || token.end > d.declaration_end { return 1; }
            if token.start == d.declaration_start {
                if !word(source, token, "let") { return 1; }
                declaration_tokens += 1;
            }
        }
        token = lexer::next(source, lex);
    }
    if declaration_tokens != module.declarations.len { return 1; }

    for i in module.declarations.len {
        let d = module.declarations[i];
        if !span(d.declaration_start, d.declaration_end, source.len) ||
           !span(d.name_start, d.name_end, source.len) ||
           !span(d.parameter_start, d.parameter_end, source.len) ||
           !span(d.expression_start, d.expression_end, source.len) ||
           !span(d.left_start, d.left_end, source.len) ||
           d.declaration_start > d.name_start || d.name_end > d.expression_start ||
           d.expression_end != d.declaration_end || d.left_start < d.expression_start ||
           d.left_end > d.expression_end || (d.left_kind != 0 && d.left_kind != 1) ||
           (d.left_kind == 0 && d.left_literal != 0) { return 1; }
        if i > 0 {
            let prior = module.declarations[i - 1];
            if d.declaration_start <= prior.declaration_end { return 1; }
            var has_newline = false;
            for j in prior.declaration_end..d.declaration_start { if source[j] == '\n' { has_newline = true; } }
            if !has_newline { return 1; }
        }
        for j in i {
            let prior = module.declarations[j];
            if same_name(source, d.name_start, d.name_end, prior.name_start, prior.name_end) { return 1; }
        }
        var projected: u8[>..] = [];
        if d.form == 1 {
            if !blank_operator(d) || !blank_right(d) || !blank_callee(d) ||
               d.expression_start != d.left_start || d.expression_end != d.left_end { return 1; }
            projected.append(source[d.declaration_start..d.declaration_end]);
        } else if d.form == 2 {
            if !blank_callee(d) || !span(d.operator_start, d.operator_end, source.len) ||
               !span(d.right_start, d.right_end, source.len) || d.operator_start < d.left_end ||
               d.right_start < d.operator_end || d.expression_start != d.left_start ||
               d.expression_end != d.right_end || (d.right_kind != 0 && d.right_kind != 1) ||
               (d.right_kind == 0 && d.right_literal != 0) { return 1; }
            projected.append(source[d.declaration_start..d.declaration_end]);
        } else if d.form == 3 {
            if !blank_operator(d) || !blank_right(d) || !call_syntax(source, d) ||
               d.callee_id < 0 || d.callee_id >= module.declarations.len { return 1; }
            let target = module.declarations[d.callee_id];
            if !span(target.name_start, target.name_end, source.len) ||
               same_name(source, d.callee_start, d.callee_end, d.parameter_start, d.parameter_end) ||
               !same_name(source, d.callee_start, d.callee_end, target.name_start, target.name_end) { return 1; }
            projected.append(source[d.declaration_start..d.expression_start]);
            projected.append(source[d.left_start..d.left_end]);
        } else { return 1; }
        let p = frontend::parse_scalar(projected);
        if p.status != 0 || p.result_type != 1 || p.name_start + d.declaration_start != d.name_start ||
           p.name_end + d.declaration_start != d.name_end ||
           p.parameter_start + d.declaration_start != d.parameter_start ||
           p.parameter_end + d.declaration_start != d.parameter_end ||
           p.kind != d.left_kind || p.literal != d.left_literal { return 1; }
        if d.form == 3 {
            if p.binary_op != 0 || p.start + d.declaration_start != d.expression_start { return 1; }
        } else {
            if p.start + d.declaration_start != d.left_start || p.end + d.declaration_start != d.left_end ||
               p.binary_op != (if d.form == 2 { 1 } else { 0 }) { return 1; }
            if d.form == 2 && (p.operator_start + d.declaration_start != d.operator_start ||
               p.operator_end + d.declaration_start != d.operator_end ||
               p.right_start + d.declaration_start != d.right_start || p.right_end + d.declaration_start != d.right_end ||
               p.right_kind != d.right_kind || p.right_literal != d.right_literal) { return 1; }
        }
        var scalar = scalar_core::build(p.result_type, p.binary_op, p.kind, p.literal, p.right_kind, p.right_literal);
        scalar.name_start = p.name_start; scalar.name_end = p.name_end;
        scalar.parameter_start = p.parameter_start; scalar.parameter_end = p.parameter_end;
        scalar.left_start = p.start; scalar.left_end = p.end;
        scalar.operator_start = p.operator_start; scalar.operator_end = p.operator_end;
        scalar.right_start = p.right_start; scalar.right_end = p.right_end;
        if validate::scalar_v2(projected, scalar, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") != 0 { return 1; }
        var sub = lexer::init(projected);
        var t = lexer::next(projected, sub);
        var function_start: i64 = -1;
        var return_start: i64 = -1;
        while t.kind != 0 {
            if t.kind == 9 { return 1; }
            if function_start < 0 && word(projected, t, "fn") { function_start = t.start; }
            if return_start < 0 && word(projected, t, "return") { return_start = t.start; }
            t = lexer::next(projected, sub);
        }
        if function_start + d.declaration_start != d.function_start ||
           return_start + d.declaration_start != d.return_start { return 1; }
    }
    // Recompute cycles and exact resources from source-resolved edges.
    for root in module.declarations.len {
        var seen: u8[256] = [0; 256];
        var current = root;
        var depth: i64 = 1;
        loop {
            if seen[current] != 0 { return 1; }
            seen[current] = 1;
            if module.declarations[current].form != 3 { break; }
            current = module.declarations[current].callee_id;
            depth += 1;
            if depth > 256 { return 1; }
        }
        if depth > 128 || module.declarations[root].depth != depth { return 1; }
    }
    return 0;
}

// Construct the canonical transient Core only from a verified Module. This is
// a builder, not independent validation of its own result.
fn to_core(module: Module&) -> module_core::ModuleCore {
    if verify(module) != 0 { return module_core::ModuleCore {}; }
    var functions: module_core::Function[>..] = [];
    for d in module.declarations {
        var f = module_core::Function {
            declaration_start: d.declaration_start, declaration_end: d.declaration_end,
            name_start: d.name_start, name_end: d.name_end, function_start: d.function_start,
            parameter_start: d.parameter_start, parameter_end: d.parameter_end, return_start: d.return_start,
            expression_start: d.expression_start, expression_end: d.expression_end,
            left_start: d.left_start, left_end: d.left_end, operator_start: d.operator_start, operator_end: d.operator_end,
            right_start: d.right_start, right_end: d.right_end, callee_start: d.callee_start, callee_end: d.callee_end,
            depth: d.depth, frame: 0, result_type: 1, terminator: 1, value_count: 1
        };
        f.values[0] = module_core::Value { producer: 1, type_id: 1 };
        var left: i64 = 0;
        if d.left_kind == 1 {
            left = f.value_count;
            f.values[f.value_count] = module_core::Value { producer: 2, type_id: 1, literal: d.left_literal };
            f.value_count += 1;
        }
        if d.form == 1 { f.result_id = left; }
        else if d.form == 2 {
            var right: i64 = 0;
            if d.right_kind == 1 {
                right = f.value_count;
                f.values[f.value_count] = module_core::Value { producer: 2, type_id: 1, literal: d.right_literal };
                f.value_count += 1;
            }
            f.result_id = f.value_count;
            f.values[f.value_count] = module_core::Value { producer: 3, type_id: 1, op_id: 1, left_id: left, right_id: right };
            f.value_count += 1;
        } else {
            f.result_id = f.value_count;
            f.values[f.value_count] = module_core::Value { producer: 4, type_id: 1, left_id: left, callee_id: d.callee_id };
            f.value_count += 1;
        }
        functions.push(f);
    }
    return module_core::ModuleCore { source: copy(module.source), functions: functions };
}
fn value_is(v: module_core::Value, kind: i64, literal: u32) -> bool {
    if kind == 0 { return v.producer == 1 && v.literal == 0; }
    return kind == 1 && v.producer == 2 && v.literal == literal;
}
// Validate the source-backed frontend independently, then structural Core and
// exact source/Core association. No invocation of to_core is needed here.
fn verify_core(module: Module&, core: module_core::ModuleCore&) -> i64 {
    if verify(module) != 0 || module_core::validate(core) != 0 ||
       module.source[..] != core.source[..] || module.declarations.len != core.functions.len { return 1; }
    for i in module.declarations.len {
        let d = module.declarations[i];
        let f = core.functions[i];
        if f.declaration_start != d.declaration_start || f.declaration_end != d.declaration_end ||
           f.name_start != d.name_start || f.name_end != d.name_end || f.function_start != d.function_start ||
           f.parameter_start != d.parameter_start || f.parameter_end != d.parameter_end || f.return_start != d.return_start ||
           f.expression_start != d.expression_start || f.expression_end != d.expression_end ||
           f.left_start != d.left_start || f.left_end != d.left_end ||
           f.operator_start != d.operator_start || f.operator_end != d.operator_end ||
           f.right_start != d.right_start || f.right_end != d.right_end ||
           f.callee_start != d.callee_start || f.callee_end != d.callee_end || f.depth != d.depth { return 1; }
        let result = f.values[f.result_id];
        if d.form == 1 {
            if !value_is(result, d.left_kind, d.left_literal) { return 1; }
        } else if d.form == 2 {
            if result.producer != 3 || result.op_id != 1 ||
               !value_is(f.values[result.left_id], d.left_kind, d.left_literal) ||
               !value_is(f.values[result.right_id], d.right_kind, d.right_literal) { return 1; }
        } else if d.form == 3 {
            if result.producer != 4 || result.callee_id != d.callee_id ||
               !value_is(f.values[result.left_id], d.left_kind, d.left_literal) { return 1; }
        } else { return 1; }
    }
    return 0;
}
