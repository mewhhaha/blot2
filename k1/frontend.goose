// The initial K1 scalar slice. This produces a transient parse result, not a
// validated CheckedFunction or a portable artifact. Unsupported syntax never
// falls through to the legacy compiler.
namespace frontend;
import work;

struct ParseResult {
    status: i64 = 0,  // 0 ok, 1 syntax, 2 unsupported, 3 unbound, 4 missing return, 5 source limit, 6 bad target, 7 type mismatch, 12 semantic limit, 13 internal accounting
    kind: i64 = 0,    // 0 parameter, 1 constant
    literal: u32 = 0,
    start: i64 = 0,
    end: i64 = 0,
    name_start: i64 = 0,
    name_end: i64 = 0,
    result_type: i64 = 0,
    binary_op: i64 = 0,
    parameter_start: i64 = 0,
    parameter_end: i64 = 0,
    operator_start: i64 = 0,
    operator_end: i64 = 0,
    right_start: i64 = 0,
    right_end: i64 = 0,
    right_kind: i64 = 0,
    right_literal: u32 = 0
}

// Token spans are byte offsets in the immutable UTF-8 source. K1 identifiers
// are ASCII, so a non-ASCII byte is never accepted as an identifier here.
struct Token { kind: i64, start: i64, end: i64 }

// Tracks a failed token charge without treating the resulting sentinel as
// source syntax. The meter is compiler-owned and never comes from an artifact.
struct TokenLimit { enabled: bool = false, hit: bool = false, offset: i64 = 0, cause: u32 = 0, phase: u32 = 1 }

fn letter(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
fn digit(c: u8) -> bool { return c >= '0' && c <= '9'; }

// Return the first invalid sequence's byte offset, or -1. Check the complete
// source, including comments, before discarding any trivia. The lead-byte
// restrictions exclude overlong forms, UTF-16 surrogates, and code points
// above U+10FFFF.
fn invalid_utf8(source: u8[:]) -> i64 {
    var p = 0;
    while p < source.len {
        let c = source[p];
        if c < 128 { p += 1; continue; }
        if c >= 194 && c <= 223 {
            if p + 1 >= source.len || source[p + 1] < 128 || source[p + 1] > 191 { return p; }
            p += 2;
            continue;
        }
        if c >= 224 && c <= 239 {
            if p + 2 >= source.len { return p; }
            let b = source[p + 1];
            let d = source[p + 2];
            if b < 128 || b > 191 || d < 128 || d > 191 ||
               (c == 224 && b < 160) || (c == 237 && b >= 160) { return p; }
            p += 3;
            continue;
        }
        if c >= 240 && c <= 244 {
            if p + 3 >= source.len { return p; }
            let b = source[p + 1];
            let d = source[p + 2];
            let e = source[p + 3];
            if b < 128 || b > 191 || d < 128 || d > 191 || e < 128 || e > 191 ||
               (c == 240 && b < 144) || (c == 244 && b >= 144) { return p; }
            p += 4;
            continue;
        }
        return p;
    }
    return -1;
}

// kind: EOF 0, identifier 1, decimal 2, colon 3, equals 4, arrow 5,
// fat arrow 6, newline 7, unsupported punctuation 8, invalid byte 9.
fn token(source: u8[:], from: i64) -> Token {
    var p = from;
    while p < source.len {
        let c = source[p];
        if c == ' ' { p += 1; continue; }
        if c == '\r' && p + 1 < source.len && source[p + 1] == '\n' { p += 1; continue; }
        if c == '/' && p + 1 < source.len && source[p + 1] == '/' {
            p += 2;
            while p < source.len && source[p] != '\n' { p += 1; }
            continue;
        }
        break;
    }
    let start = p;
    if p == source.len { return Token { 0, p, p }; }
    let c = source[p];
    if c == '\n' { return Token { 7, p, p + 1 }; }
    if c == '\t' || c < 32 || c >= 127 { return Token { 9, p, p + 1 }; }
    if letter(c) {
        p += 1;
        while p < source.len && (letter(source[p]) || digit(source[p])) { p += 1; }
        return Token { 1, start, p };
    }
    if digit(c) {
        p += 1;
        while p < source.len && digit(source[p]) { p += 1; }
        return Token { 2, start, p };
    }
    if c == ':' { return Token { 3, p, p + 1 }; }
    if c == '=' {
        if p + 1 < source.len && source[p + 1] == '>' { return Token { 6, p, p + 2 }; }
        return Token { 4, p, p + 1 };
    }
    if c == '-' && p + 1 < source.len && source[p + 1] == '>' { return Token { 5, p, p + 2 }; }
    if c == '&' {
        if p + 1 < source.len && source[p + 1] == '&' { return Token { 8, p, p + 2 }; }
        return Token { 10, p, p + 1 };
    }
    if c == '<' {
        if p + 1 < source.len && (source[p + 1] == '<' || source[p + 1] == '=') { return Token { 8, p, p + 2 }; }
        return Token { 11, p, p + 1 };
    }
    return Token { 8, p, p + 1 };
}

// Return source trivia without charging it as a semantic node. The scanner
// classifies bytes first; before a meaningful token is returned to the parser,
// charge its visit. A suite delimiter is charged separately by `suite`.
// Source-byte inspection telemetry is not yet instrumented in this fixture.
fn charged_token(source: u8[:], from: i64, meter: work::Meter&, limit: TokenLimit&) -> Token {
    if !limit.enabled { return token(source, from); }
    if limit.hit { return Token { 12, limit.offset, limit.offset }; }
    let next = token(source, from);
    if next.kind == 0 || next.kind == 7 { return next; }
    let receipt = work::charge(meter, limit.phase, 1);
    if receipt.status != 0 {
        limit.hit = true;
        limit.offset = next.start;
        limit.cause = receipt.status;
        return Token { 12, next.start, next.start };
    }
    return next;
}

fn word(source: u8[:], t: Token, expected: u8[:]) -> bool {
    return t.kind == 1 && source[t.start..t.end] == expected;
}
fn reserved(s: u8[:]) -> bool {
    return s == "import" || s == "as" || s == "pub" || s == "let" ||
        s == "static" || s == "local" || s == "type" || s == "fn" ||
        s == "in" || s == "do" || s == "return" || s == "break" ||
        s == "continue" || s == "next" || s == "stop" || s == "seal" ||
        s == "abort" || s == "if" || s == "else" || s == "case" ||
        s == "for" || s == "carry" || s == "invariant" || s == "forall" ||
        s == "exists" || s == "where" || s == "requires" || s == "ensures" ||
        s == "on_true" || s == "on_false" || s == "resources" || s == "region" ||
        s == "owned" || s == "pack" || s == "open" || s == "space" ||
        s == "dest" || s == "env" || s == "builder" || s == "view" ||
        s == "index" || s == "array" || s == "U32" || s == "F32" ||
        s == "Unit" || s == "Bool" || s == "RegionOwner" || s == "Space" ||
        s == "Dest" || s == "EnvDest" || s == "Builder" || s == "View" ||
        s == "Index" || s == "Fn" || s == "Owned" || s == "Result" ||
        s == "Many" || s == "Once" || s == "Append" || s == "Resize" ||
        s == "Type" || s == "Region" || s == "Nat" || s == "Domain" ||
        s == "Plain" || s == "Share" || s == "_";
}
fn failure(status: i64, t: Token) -> ParseResult {
    return ParseResult { status: status, start: t.start, end: t.end };
}
fn expected(t: Token) -> ParseResult {
    if t.kind == 0 || t.kind == 9 { return failure(1, t); }
    return failure(2, t);
}

// The header stays on one physical line. The short body, body do/return and
// value do/break all compile to the same scalar result. Other suites remain
// unsupported rather than being silently partially checked.
fn suite(source: u8[:], from: i64, indent: i64, meter: work::Meter&, limit: TokenLimit&) -> Token {
    var t = charged_token(source, from, meter, limit);
    if t.kind != 7 { return Token { 9, t.start, t.end }; }
    if limit.enabled {
        let receipt = work::charge(meter, limit.phase, 1);
        if receipt.status != 0 {
            limit.hit = true; limit.offset = t.start; limit.cause = receipt.status;
            return Token { 12, t.start, t.start };
        }
    }
    t = charged_token(source, t.end, meter, limit);
    while t.kind == 7 { t = charged_token(source, t.end, meter, limit); }
    if t.kind == 0 { return Token { 9, t.start, t.end }; }
    var start = t.start;
    while start > 0 && source[start - 1] != '\n' { start -= 1; }
    if t.start - start != indent { return Token { 9, start, t.start }; }
    return t;
}
fn parse_scalar_impl(source: u8[:], meter: work::Meter&, limit: TokenLimit&) -> ParseResult {
    if source.len > 16777216 { return ParseResult { status: 5, start: 0, end: source.len }; }
    let invalid = invalid_utf8(source);
    if invalid >= 0 { return ParseResult { status: 1, start: invalid, end: invalid + 1 }; }
    var t = charged_token(source, 0, meter, limit);
    while t.kind == 7 { t = charged_token(source, t.end, meter, limit); }
    if t.kind == 9 { return failure(1, t); }
    if !word(source, t, "let") { return failure(2, t); }
    // A top-level declaration cannot be indented. Find its physical line start.
    var line = t.start;
    while line > 0 && source[line - 1] != '\n' { line -= 1; }
    if line != t.start { return failure(1, t); }
    t = charged_token(source, t.end, meter, limit);
    if t.kind != 1 || reserved(source[t.start..t.end]) { return failure(1, t); }
    let name_start = t.start;
    let name_end = t.end;
    t = charged_token(source, t.end, meter, limit);
    if t.kind != 3 { return expected(t); }
    t = charged_token(source, t.end, meter, limit);
    if !word(source, t, "U32") { return expected(t); }
    t = charged_token(source, t.end, meter, limit);
    if t.kind != 5 { return expected(t); }
    t = charged_token(source, t.end, meter, limit);
    var result_type: i64 = 0;
    if word(source, t, "U32") { result_type = 1; }
    else if word(source, t, "Bool") { result_type = 2; }
    else { return expected(t); }
    t = charged_token(source, t.end, meter, limit);
    if t.kind != 4 { return expected(t); }
    t = charged_token(source, t.end, meter, limit);
    if !word(source, t, "fn") { return expected(t); }
    t = charged_token(source, t.end, meter, limit);
    if t.kind != 1 || reserved(source[t.start..t.end]) { return failure(1, t); }
    let parameter_start = t.start;
    let parameter_end = t.end;
    t = charged_token(source, t.end, meter, limit);
    if t.kind != 6 { return expected(t); }
    t = charged_token(source, t.end, meter, limit);
    var body_indent: i64 = 0;
    if word(source, t, "do") {
        t = charged_token(source, t.end, meter, limit);
        if t.kind != 3 { return expected(t); }
        t = suite(source, t.end, 2, meter, limit);
        if t.kind == 9 { return failure(1, t); }
        body_indent = 2;
    }
    if word(source, t, "break") || word(source, t, "continue") { return failure(6, t); }
    if !word(source, t, "return") {
        if t.kind == 1 || t.kind == 2 { return failure(4, t); }
        return expected(t);
    }
    t = charged_token(source, t.end, meter, limit);
    if word(source, t, "do") {
        t = charged_token(source, t.end, meter, limit);
        if t.kind != 3 { return expected(t); }
        t = suite(source, t.end, body_indent + 2, meter, limit);
        if t.kind == 9 { return failure(1, t); }
        if word(source, t, "return") {
            // A return inside a value block transfers directly from the function.
        } else if word(source, t, "continue") {
            return failure(6, t);
        } else if !word(source, t, "break") {
            if t.kind == 1 || t.kind == 2 { return failure(4, t); }
            return expected(t);
        }
        t = charged_token(source, t.end, meter, limit);
    }
    if word(source, t, "break") || word(source, t, "continue") { return failure(6, t); }
    var result = ParseResult { name_start: name_start, name_end: name_end,
        parameter_start: parameter_start, parameter_end: parameter_end,
        result_type: result_type, start: t.start, end: t.end };
    if t.kind == 1 {
        if source[t.start..t.end] != source[parameter_start..parameter_end] { return failure(3, t); }
    } else if t.kind == 2 {
        var n: u64 = 0;
        for i in t.start..t.end {
            n = n * 10 + (source[i] - '0');
            if n > 4294967295 { return failure(1, t); }
        }
        result.kind = 1;
        result.literal = n as u32;
    } else { return expected(t); }
    t = charged_token(source, t.end, meter, limit);
    if t.kind == 10 || t.kind == 11 {
        result.binary_op = if t.kind == 10 { 1 } else { 2 };
        result.operator_start = t.start; result.operator_end = t.end;
        t = charged_token(source, t.end, meter, limit);
        result.right_start = t.start; result.right_end = t.end;
        if t.kind == 1 {
            if source[t.start..t.end] != source[parameter_start..parameter_end] { return failure(3, t); }
        } else if t.kind == 2 {
            var n: u64 = 0;
            for i in t.start..t.end {
                n = n * 10 + (source[i] - '0');
                if n > 4294967295 { return failure(1, t); }
            }
            result.right_kind = 1;
            result.right_literal = n as u32;
        } else { return expected(t); }
        t = charged_token(source, t.end, meter, limit);
    }
    while t.kind == 7 { t = charged_token(source, t.end, meter, limit); }
    if t.kind != 0 { return failure(2, t); }
    if (result.binary_op == 2 && result_type != 2) ||
       (result.binary_op != 2 && result_type != 1) { return failure(7, t); }
    return result;
}

// The measured entry accepts one caller-owned meter for this declaration.
// The rest of the prototype still contains unmetered source/Core/plan checks;
// this alone is not a complete K1-SEM-POLICY-1 receipt.
fn parse_scalar_with_work_at_phase(source: u8[:], meter: work::Meter&, phase: u32) -> ParseResult {
    if phase != 1 && phase != 2 { return ParseResult { status: 13 }; }
    var limit = TokenLimit { enabled: true, phase: phase };
    let result = parse_scalar_impl(source, meter, limit);
    if limit.hit {
        return ParseResult { status: if limit.cause == 1 { 12 } else { 13 },
                             start: limit.offset, end: limit.offset };
    }
    return result;
}

fn parse_scalar_with_work(source: u8[:], meter: work::Meter&) -> ParseResult {
    return parse_scalar_with_work_at_phase(source, meter, 1);
}

// Compatibility entry preserves existing fixture admission until the complete
// required work schedule has been integrated and qualified.
fn parse_scalar(source: u8[:]) -> ParseResult {
    var meter = work::Meter {};
    var limit = TokenLimit {};
    return parse_scalar_impl(source, meter, limit);
}
