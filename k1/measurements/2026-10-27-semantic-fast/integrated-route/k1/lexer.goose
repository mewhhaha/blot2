// Experimental streaming K1 lexer. It does not admit source or replace the
// compiler parser. The caller must keep the exact source bytes immutable from
// init through the last next call. All spans are half-open byte offsets.
namespace lexer;

// Token kinds: 0 EOF, 1 identifier/keyword, 2 U32 integer, 3 decimal F32,
// 4 quoted metadata, 5 punctuation/operator, 6 newline, 7 indent, 8 dedent,
// 9 error. Error status 1 = k1_syntax, 5 = k1_source_limit. The parser must
// distinguish keywords and punctuation by the bytes in each token's span.
struct Token { kind: i64 = 0, start: i64 = 0, end: i64 = 0, status: i64 = 0 }
struct State {
    position: i64 = 0, source_len: i64 = 0,
    at_line_start: bool = true, finished: bool = false,
    error_status: i64 = 0, error_start: i64 = 0, error_end: i64 = 0,
    indentation: i64[65] = [0; 65], indent_depth: i64 = 0,
    delimiters: u8[64] = [0; 64], delimiter_depth: i64 = 0,
    pending_dedents: i64 = 0
}
fn letter(c: u8) -> bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
fn digit(c: u8) -> bool { return c >= '0' && c <= '9'; }

// Return first invalid UTF-8 lead offset, or -1. Validate comments and quoted
// metadata too; no token is issued before this complete check.
fn invalid_utf8(source: u8[:]) -> i64 {
    var p: i64 = 0;
    while p < source.len {
        let a = source[p];
        if a < 128 { p += 1; continue; }
        if a >= 194 && a <= 223 {
            if p + 1 >= source.len || source[p + 1] < 128 || source[p + 1] > 191 { return p; }
            p += 2; continue;
        }
        if a >= 224 && a <= 239 {
            if p + 2 >= source.len { return p; }
            let b = source[p + 1]; let c = source[p + 2];
            if b < 128 || b > 191 || c < 128 || c > 191 ||
               (a == 224 && b < 160) || (a == 237 && b > 159) { return p; }
            p += 3; continue;
        }
        if a >= 240 && a <= 244 {
            if p + 3 >= source.len { return p; }
            let b = source[p + 1]; let c = source[p + 2]; let d = source[p + 3];
            if b < 128 || b > 191 || c < 128 || c > 191 || d < 128 || d > 191 ||
               (a == 240 && b < 144) || (a == 244 && b > 143) { return p; }
            p += 4; continue;
        }
        return p;
    }
    return -1;
}
fn init(source: u8[:]) -> State {
    var state = State { source_len: source.len };
    if source.len > 16777216 {
        state.error_status = 5; state.error_start = 0; state.error_end = source.len;
        return state;
    }
    let invalid = invalid_utf8(source);
    if invalid >= 0 {
        state.error_status = 1; state.error_start = invalid; state.error_end = invalid + 1;
    }
    return state;
}
fn fail(state: State&, start: i64, end: i64) -> Token {
    state.finished = true;
    return Token { kind: 9, start: start, end: end, status: 1 };
}
fn nesting_limit(state: State&, start: i64, end: i64) -> Token {
    state.finished = true;
    return Token { kind: 9, start: start, end: end, status: 5 };
}
fn next(source: u8[:], state: State&) -> Token {
    if state.finished { return Token { start: state.position, end: state.position }; }
    if source.len != state.source_len { return fail(state, 0, 0); }
    if state.error_status != 0 {
        state.finished = true;
        return Token { kind: 9, start: state.error_start, end: state.error_end, status: state.error_status };
    }
    if state.pending_dedents > 0 {
        state.pending_dedents -= 1;
        return Token { kind: 8, start: state.position, end: state.position };
    }
    loop {
        // Physical indentation is checked even when a delimiter makes the
        // newline whitespace. Indentation inside delimiters does not emit
        // INDENT/DEDENT, but a tab before the first token is still forbidden.
        if state.at_line_start && state.delimiter_depth != 0 {
            var p = state.position;
            while p < source.len && source[p] == ' ' { p += 1; }
            if p < source.len && source[p] == '\t' { return fail(state, p, p + 1); }
            state.position = p; state.at_line_start = false;
        }
        if state.at_line_start && state.delimiter_depth == 0 {
            let start = state.position;
            var p = start;
            while p < source.len && source[p] == ' ' { p += 1; }
            if p < source.len && source[p] == '\t' { return fail(state, p, p + 1); }
            // Blank/comment-only lines do not change indentation.
            if p + 1 < source.len && source[p] == '/' && source[p + 1] == '/' {
                p += 2;
                while p < source.len && source[p] != '\n' && !(source[p] == '\r' && p + 1 < source.len && source[p + 1] == '\n') { p += 1; }
            }
            if p < source.len && source[p] == '\r' {
                if p + 1 >= source.len || source[p + 1] != '\n' { return fail(state, p, p + 1); }
                p += 1;
            }
            if p < source.len && source[p] == '\n' { state.position = p + 1; continue; }
            if p == source.len { state.position = p; }
            else {
                let width = p - start;
                let old = state.indentation[state.indent_depth];
                if width % 2 != 0 { return fail(state, start, p); }
                if width > old {
                    if width != old + 2 { return fail(state, start, p); }
                    if state.indent_depth >= 64 { return nesting_limit(state, start, p); }
                    state.indent_depth += 1;
                    state.indentation[state.indent_depth] = width;
                    state.position = p; state.at_line_start = false;
                    return Token { kind: 7, start: start, end: p };
                }
                if width < old {
                    var count: i64 = 0;
                    while state.indent_depth > 0 && state.indentation[state.indent_depth] > width {
                        state.indent_depth -= 1; count += 1;
                    }
                    if state.indentation[state.indent_depth] != width { return fail(state, start, p); }
                    state.position = p; state.at_line_start = false; state.pending_dedents = count - 1;
                    return Token { kind: 8, start: p, end: p };
                }
                state.position = p; state.at_line_start = false;
            }
        }
        let p = state.position;
        if p >= source.len {
            if state.delimiter_depth != 0 { return fail(state, p, p); }
            if state.indent_depth > 0 {
                state.indent_depth -= 1;
                return Token { kind: 8, start: p, end: p };
            }
            state.finished = true;
            return Token { start: p, end: p };
        }
        let c = source[p];
        if c == ' ' || c == '\t' { state.position += 1; continue; }
        if c == '/' && p + 1 < source.len && source[p + 1] == '/' {
            state.position += 2;
            while state.position < source.len && source[state.position] != '\n' && !(source[state.position] == '\r' && state.position + 1 < source.len && source[state.position + 1] == '\n') { state.position += 1; }
            continue;
        }
        if c == '\n' || c == '\r' {
            var end = p + 1;
            if c == '\r' {
                if end >= source.len || source[end] != '\n' { return fail(state, p, end); }
                end += 1;
            }
            state.position = end;
            state.at_line_start = true;
            if state.delimiter_depth != 0 { continue; }
            return Token { kind: 6, start: p, end: end };
        }
        if letter(c) {
            var end = p + 1;
            while end < source.len && (letter(source[end]) || digit(source[end])) { end += 1; }
            state.position = end;
            return Token { kind: 1, start: p, end: end };
        }
        if digit(c) {
            var end = p;
            var value: u64 = 0;
            var overflow = false;
            while end < source.len && digit(source[end]) {
                let d = (source[end] - '0') as u64;
                if value > (4294967295 - d) / 10 { overflow = true; }
                else if !overflow { value = value * 10 + d; }
                end += 1;
            }
            var is_float = false;
            if end < source.len && source[end] == '.' && !(end + 1 < source.len && source[end + 1] == '.') {
                is_float = true; end += 1;
                while end < source.len && digit(source[end]) { end += 1; }
            }
            if end < source.len && (source[end] == 'e' || source[end] == 'E') {
                is_float = true; end += 1;
                if end < source.len && (source[end] == '+' || source[end] == '-') { end += 1; }
                let exponent = end;
                while end < source.len && digit(source[end]) { end += 1; }
                if end == exponent { return fail(state, p, end); }
            }
            if !is_float && overflow { return fail(state, p, end); }
            state.position = end;
            return Token { kind: if is_float { 3 } else { 2 }, start: p, end: end };
        }
        if c == '"' {
            var end = p + 1;
            while end < source.len {
                let d = source[end];
                if d == '"' { state.position = end + 1; return Token { kind: 4, start: p, end: end + 1 }; }
                if d < 32 { return fail(state, p, end + 1); }
                if d == '\\' {
                    end += 1;
                    if end >= source.len || source[end] < 32 { return fail(state, p, end); }
                }
                end += 1;
            }
            return fail(state, p, end);
        }
        if c == '(' || c == '[' || c == '{' {
            if state.delimiter_depth >= 64 { return nesting_limit(state, p, p + 1); }
            state.delimiters[state.delimiter_depth] = c;
            state.delimiter_depth += 1; state.position += 1;
            return Token { kind: 5, start: p, end: p + 1 };
        }
        if c == ')' || c == ']' || c == '}' {
            if state.delimiter_depth == 0 { return fail(state, p, p + 1); }
            let open = state.delimiters[state.delimiter_depth - 1];
            if !((open == '(' && c == ')') || (open == '[' && c == ']') || (open == '{' && c == '}')) {
                return fail(state, p, p + 1);
            }
            state.delimiter_depth -= 1; state.position += 1;
            return Token { kind: 5, start: p, end: p + 1 };
        }
        if c == ':' || c == ',' || c == '.' || c == '#' || c == '@' || c == '=' ||
           c == '!' || c == '~' || c == '*' || c == '/' || c == '%' || c == '+' ||
           c == '-' || c == '<' || c == '>' || c == '&' || c == '^' || c == '|' {
            var end = p + 1;
            if end < source.len {
                let d = source[end];
                if (c == '.' && d == '.') || (c == '-' && d == '>') || (c == '=' && (d == '=' || d == '>')) ||
                   (c == '!' && d == '=') || (c == '<' && (d == '=' || d == '<')) ||
                   (c == '>' && (d == '=' || d == '>')) || (c == '&' && d == '&') || (c == '|' && d == '|') { end += 1; }
            }
            state.position = end;
            return Token { kind: 5, start: p, end: end };
        }
        return fail(state, p, p + 1);
    }
}
