// Private candidate/validation experiment for a single public scalar declaration.
// It does not publish an interface, link modules, or enable public K1 admission.
namespace public_frontend;
import lexer;
import frontend;
import scalar_core;
import validate;
import catalog;

struct Candidate {
    status: i64 = 0,
    core: scalar_core::ScalarCore = scalar_core::ScalarCore {},
    pub_start: i64 = 0, pub_end: i64 = 0,
    let_start: i64 = 0, let_end: i64 = 0,
    effect_start: i64 = 0, effect_end: i64 = 0,
    resources_start: i64 = 0, resources_end: i64 = 0,
    depth_start: i64 = 0, depth_end: i64 = 0,
    frame_start: i64 = 0, frame_end: i64 = 0,
    declared_depth: u32 = 0, declared_frame: u32 = 0
}
struct Cursor { lex: lexer::State = lexer::State {}, token: lexer::Token = lexer::Token {}, status: i64 = 0 }
fn advance(source: u8[:], cursor: Cursor&) {
    cursor.token = lexer::next(source, cursor.lex);
    if cursor.token.kind == 9 { cursor.status = cursor.token.status; }
}
fn in_bounds(source: u8[:], t: lexer::Token) -> bool { return t.start >= 0 && t.end > t.start && t.end <= source.len; }
fn word(source: u8[:], t: lexer::Token, text: u8[:]) -> bool {
    return t.kind == 1 && in_bounds(source, t) && source[t.start..t.end] == text;
}
fn sym(source: u8[:], t: lexer::Token, text: u8[:]) -> bool {
    return t.kind == 5 && in_bounds(source, t) && source[t.start..t.end] == text;
}
fn take_word(source: u8[:], c: Cursor&, text: u8[:]) -> bool {
    if c.status != 0 { return false; }
    if !word(source, c.token, text) { c.status = 1; return false; }
    advance(source, c); return c.status == 0;
}
fn take_sym(source: u8[:], c: Cursor&, text: u8[:]) -> bool {
    if c.status != 0 { return false; }
    if !sym(source, c.token, text) { c.status = 1; return false; }
    advance(source, c); return c.status == 0;
}
fn number(source: u8[:], t: lexer::Token) -> u32, bool {
    if t.kind != 2 || !in_bounds(source, t) { return 0, false; }
    var value: u64 = 0;
    for i in t.start..t.end {
        if source[i] < '0' || source[i] > '9' { return 0, false; }
        let digit = (source[i] - '0') as u64;
        if value > (4294967295 - digit) / 10 { return 0, false; }
        value = value * 10 + digit;
    }
    return value as u32, true;
}
fn projected(source: u8[:], let_start: i64, effect_start: i64, resources_end: i64) -> u8[>..] {
    var out: u8[>..] = [];
    if let_start < 0 || let_start > source.len || effect_start < let_start ||
       resources_end < effect_start || resources_end > source.len { return out; }
    out.append(source[let_start..]);
    for i in effect_start - let_start..resources_end - let_start { out[i] = ' '; }
    return out;
}
fn parse(source: u8[:]) -> Candidate {
    var c = Cursor { lex: lexer::init(source) };
    advance(source, c);
    while c.status == 0 && c.token.kind == 6 { advance(source, c); }
    if c.status != 0 { return Candidate { status: c.status }; }
    if c.token.kind == 7 || c.token.kind == 8 { return Candidate { status: 1 }; }
    let pub_token = c.token;
    if !word(source, c.token, "pub") { return Candidate { status: 2 }; }
    advance(source, c);
    let let_token = c.token;
    if !take_word(source, c, "let") { return Candidate { status: c.status }; }
    if c.token.kind != 1 || !in_bounds(source, c.token) || !validate::name_valid(source[c.token.start..c.token.end]) { return Candidate { status: 1 }; }
    advance(source, c);
    if !take_sym(source, c, ":") || !take_word(source, c, "U32") || !take_sym(source, c, "->") { return Candidate { status: c.status }; }
    if !word(source, c.token, "U32") && !word(source, c.token, "Bool") {
        return Candidate { status: if c.status != 0 { c.status } else { 2 } };
    }
    advance(source, c);
    if !sym(source, c.token, "!") {
        if sym(source, c.token, "=") || word(source, c.token, "resources") || c.token.kind == 0 { return Candidate { status: 8 }; }
        return Candidate { status: 2 };
    }
    let effect_start = c.token.start;
    advance(source, c);
    if !take_sym(source, c, "{") { return Candidate { status: c.status }; }
    if !sym(source, c.token, "}") { return Candidate { status: 2 }; }
    let effect_end = c.token.end;
    advance(source, c);
    if !word(source, c.token, "resources") {
        if sym(source, c.token, "=") || c.token.kind == 0 { return Candidate { status: 8 }; }
        return Candidate { status: 2 };
    }
    let resources_start = c.token.start;
    advance(source, c);
    if !take_sym(source, c, "{") || !take_word(source, c, "depth") || !take_sym(source, c, ":") { return Candidate { status: c.status }; }
    let depth = c.token;
    if c.status != 0 { return Candidate { status: c.status }; }
    if depth.kind != 2 { return Candidate { status: 1 }; }
    let d, d_ok = number(source, depth);
    if !d_ok { return Candidate { status: 1 }; }
    advance(source, c);
    if !take_sym(source, c, ",") || !take_word(source, c, "frame") || !take_sym(source, c, ":") { return Candidate { status: c.status }; }
    let frame = c.token;
    if c.status != 0 { return Candidate { status: c.status }; }
    if frame.kind != 2 { return Candidate { status: 1 }; }
    let f, f_ok = number(source, frame);
    if !f_ok { return Candidate { status: 1 }; }
    advance(source, c);
    if !sym(source, c.token, "}") { return Candidate { status: if c.status != 0 { c.status } else { 1 } }; }
    let resources_end = c.token.end;
    advance(source, c);
    if !sym(source, c.token, "=") { return Candidate { status: if c.status != 0 { c.status } else { 1 } }; }
    // Wrapped public headers are valid K1 but outside this prototype. Do not
    // erase a physical newline while constructing the private projection.
    for i in pub_token.start..c.token.start {
        if source[i] == '\n' || source[i] == '\r' { return Candidate { status: 2 }; }
    }
    if d < 1 || d > 128 { return Candidate { status: 9 }; }
    let flat = projected(source, let_token.start, effect_start, resources_end);
    let p = frontend::parse_scalar(flat);
    if p.status != 0 { return Candidate { status: p.status }; }
    var core = scalar_core::build(p.result_type, p.binary_op, p.kind, p.literal, p.right_kind, p.right_literal);
    core.name_start = p.name_start + let_token.start; core.name_end = p.name_end + let_token.start;
    core.parameter_start = p.parameter_start + let_token.start; core.parameter_end = p.parameter_end + let_token.start;
    core.left_start = p.start + let_token.start; core.left_end = p.end + let_token.start;
    if p.binary_op != 0 {
        core.operator_start = p.operator_start + let_token.start; core.operator_end = p.operator_end + let_token.start;
        core.right_start = p.right_start + let_token.start; core.right_end = p.right_end + let_token.start;
    }
    let candidate = Candidate { core: core, pub_start: pub_token.start, pub_end: pub_token.end,
        let_start: let_token.start, let_end: let_token.end, effect_start: effect_start, effect_end: effect_end,
        resources_start: resources_start, resources_end: resources_end,
        depth_start: depth.start, depth_end: depth.end, frame_start: frame.start, frame_end: frame.end,
        declared_depth: d, declared_frame: f };
    if !verify(source, candidate) { return Candidate { status: 11 }; }
    return candidate;
}

// Independently recognize the original public header and exact declared
// resources; then validate an equal-offset projection through the independent
// scalar source/Core recognizer. This does not call parse or frontend.
fn verify(source: u8[:], candidate: Candidate) -> bool {
    if candidate.status != 0 || source.len > 16777216 { return false; }
    var state = lexer::init(source);
    var t = lexer::next(source, state);
    while t.kind == 6 { t = lexer::next(source, state); }
    if !word(source, t, "pub") || t.start != candidate.pub_start || t.end != candidate.pub_end { return false; }
    var line = t.start;
    while line > 0 && source[line - 1] != '\n' { line -= 1; }
    if line != t.start { return false; }
    t = lexer::next(source, state);
    if !word(source, t, "let") || t.start != candidate.let_start || t.end != candidate.let_end { return false; }
    let base = t.start;
    t = lexer::next(source, state);
    if t.kind != 1 || !in_bounds(source, t) || !validate::name_valid(source[t.start..t.end]) ||
       t.start != candidate.core.name_start || t.end != candidate.core.name_end { return false; }
    t = lexer::next(source, state); if !sym(source, t, ":") { return false; }
    t = lexer::next(source, state); if !word(source, t, "U32") { return false; }
    t = lexer::next(source, state); if !sym(source, t, "->") { return false; }
    t = lexer::next(source, state);
    if candidate.core.result_type == 1 {
        if !word(source, t, "U32") { return false; }
    } else if candidate.core.result_type == 2 {
        if !word(source, t, "Bool") { return false; }
    } else { return false; }
    t = lexer::next(source, state);
    if !sym(source, t, "!") || t.start != candidate.effect_start { return false; }
    t = lexer::next(source, state); if !sym(source, t, "{") { return false; }
    t = lexer::next(source, state);
    if !sym(source, t, "}") || t.end != candidate.effect_end { return false; }
    t = lexer::next(source, state);
    if !word(source, t, "resources") || t.start != candidate.resources_start { return false; }
    t = lexer::next(source, state); if !sym(source, t, "{") { return false; }
    t = lexer::next(source, state); if !word(source, t, "depth") { return false; }
    t = lexer::next(source, state); if !sym(source, t, ":") { return false; }
    t = lexer::next(source, state);
    if t.start != candidate.depth_start || t.end != candidate.depth_end { return false; }
    let depth, depth_ok = number(source, t);
    if !depth_ok || depth < 1 || depth > 128 || depth != candidate.declared_depth { return false; }
    t = lexer::next(source, state); if !sym(source, t, ",") { return false; }
    t = lexer::next(source, state); if !word(source, t, "frame") { return false; }
    t = lexer::next(source, state); if !sym(source, t, ":") { return false; }
    t = lexer::next(source, state);
    if t.start != candidate.frame_start || t.end != candidate.frame_end { return false; }
    let frame, frame_ok = number(source, t);
    if !frame_ok || frame != candidate.declared_frame { return false; }
    t = lexer::next(source, state);
    if !sym(source, t, "}") || t.end != candidate.resources_end { return false; }
    t = lexer::next(source, state); if !sym(source, t, "=") { return false; }
    for i in candidate.pub_start..t.start { if source[i] == '\n' || source[i] == '\r' { return false; } }
    if candidate.effect_start < base || candidate.resources_end < candidate.effect_start ||
       candidate.resources_end > source.len { return false; }
    var core = candidate.core;
    // Avoid overflow from forged offsets before rebasing to the projection.
    for offset in [core.name_start, core.name_end, core.parameter_start, core.parameter_end,
                   core.left_start, core.left_end] {
        if offset < base || offset > source.len { return false; }
    }
    core.name_start -= base; core.name_end -= base;
    core.parameter_start -= base; core.parameter_end -= base;
    core.left_start -= base; core.left_end -= base;
    if core.operator_start != 0 || core.operator_end != 0 || core.right_start != 0 || core.right_end != 0 {
        for offset in [core.operator_start, core.operator_end, core.right_start, core.right_end] {
            if offset < base || offset > source.len { return false; }
        }
        core.operator_start -= base; core.operator_end -= base;
        core.right_start -= base; core.right_end -= base;
    }
    let flat = projected(source, base, candidate.effect_start, candidate.resources_end);
    return validate::scalar_v2(flat, core, catalog::edition(), catalog::semantic_policy(),
        catalog::optimization_policy(), catalog::wasm_abi()) == 0;
}
