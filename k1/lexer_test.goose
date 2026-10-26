import lexer;

fn token(source: u8[:], state: lexer::State&, kind: i64, text: u8[:]) {
    let item = lexer::next(source, state);
    assert(item.kind == kind && item.status == 0);
    assert(item.start >= 0 && item.end >= item.start && item.end <= source.len);
    assert(source[item.start..item.end] == text);
}
fn expect_error(source: u8[:]) -> i64 {
    var state = lexer::init(source);
    loop {
        let item = lexer::next(source, state);
        if item.kind == 9 { return item.status; }
        assert(item.kind != 0);
    }
}
fn main() {
    let code = "let f: U32 -> U32 = fn x => do:\n  // comment\n  return x\nlet z = 1\n";
    var state = lexer::init(code);
    token(code, state, 1, "let"); token(code, state, 1, "f");
    token(code, state, 5, ":"); token(code, state, 1, "U32");
    token(code, state, 5, "->"); token(code, state, 1, "U32");
    token(code, state, 5, "="); token(code, state, 1, "fn");
    token(code, state, 1, "x"); token(code, state, 5, "=>");
    token(code, state, 1, "do"); token(code, state, 5, ":");
    token(code, state, 6, "\n"); token(code, state, 7, "  ");
    token(code, state, 1, "return"); token(code, state, 1, "x");
    token(code, state, 6, "\n"); token(code, state, 8, "");
    token(code, state, 1, "let"); token(code, state, 1, "z");
    token(code, state, 5, "="); token(code, state, 2, "1");
    token(code, state, 6, "\n"); token(code, state, 0, "");

    let nums = "0 4294967295 1.0 1e-2 1. 1..2 a.0";
    state = lexer::init(nums);
    token(nums, state, 2, "0"); token(nums, state, 2, "4294967295");
    token(nums, state, 3, "1.0"); token(nums, state, 3, "1e-2");
    token(nums, state, 3, "1."); token(nums, state, 2, "1");
    token(nums, state, 5, ".."); token(nums, state, 2, "2");
    token(nums, state, 1, "a"); token(nums, state, 5, ".");
    token(nums, state, 2, "0"); token(nums, state, 0, "");
    assert(expect_error("4294967296") == 1);
    assert(expect_error("1e+") == 1);

    let ladder = "a\n  b\n    c\n  d\nz";
    state = lexer::init(ladder);
    token(ladder, state, 1, "a"); token(ladder, state, 6, "\n");
    token(ladder, state, 7, "  "); token(ladder, state, 1, "b"); token(ladder, state, 6, "\n");
    token(ladder, state, 7, "    "); token(ladder, state, 1, "c"); token(ladder, state, 6, "\n");
    token(ladder, state, 8, ""); token(ladder, state, 1, "d"); token(ladder, state, 6, "\n");
    token(ladder, state, 8, ""); token(ladder, state, 1, "z"); token(ladder, state, 0, "");
    let final_indent = "a\n  b";
    state = lexer::init(final_indent);
    token(final_indent, state, 1, "a"); token(final_indent, state, 6, "\n");
    token(final_indent, state, 7, "  "); token(final_indent, state, 1, "b");
    token(final_indent, state, 8, ""); token(final_indent, state, 0, "");
    let multi = "(a,\n  b)\n  // café\n  c\n";
    state = lexer::init(multi);
    token(multi, state, 5, "("); token(multi, state, 1, "a");
    token(multi, state, 5, ","); token(multi, state, 1, "b");
    token(multi, state, 5, ")"); token(multi, state, 6, "\n");
    token(multi, state, 7, "  "); token(multi, state, 1, "c");
    token(multi, state, 6, "\n"); token(multi, state, 8, "");
    token(multi, state, 0, "");
    let inner_tab = "(a,\n  b\t, c)";
    state = lexer::init(inner_tab);
    token(inner_tab, state, 5, "("); token(inner_tab, state, 1, "a");
    token(inner_tab, state, 5, ","); token(inner_tab, state, 1, "b");
    token(inner_tab, state, 5, ","); token(inner_tab, state, 1, "c");
    token(inner_tab, state, 5, ")"); token(inner_tab, state, 0, "");
    let continuation = "(a,\r\n      b)\r\n";
    state = lexer::init(continuation);
    token(continuation, state, 5, "("); token(continuation, state, 1, "a");
    token(continuation, state, 5, ","); token(continuation, state, 1, "b");
    token(continuation, state, 5, ")"); token(continuation, state, 6, "\r\n");
    token(continuation, state, 0, "");
    let between = "let\tf";
    state = lexer::init(between);
    token(between, state, 1, "let"); token(between, state, 1, "f");
    token(between, state, 0, "");
    let operators = "-> => .. <= >= == != && || << >> @[T] #[1]";
    state = lexer::init(operators);
    token(operators, state, 5, "->"); token(operators, state, 5, "=>");
    token(operators, state, 5, ".."); token(operators, state, 5, "<=");
    token(operators, state, 5, ">="); token(operators, state, 5, "==");
    token(operators, state, 5, "!="); token(operators, state, 5, "&&");
    token(operators, state, 5, "||"); token(operators, state, 5, "<<");
    token(operators, state, 5, ">>"); token(operators, state, 5, "@");
    token(operators, state, 5, "["); token(operators, state, 1, "T");
    token(operators, state, 5, "]"); token(operators, state, 5, "#");
    token(operators, state, 5, "["); token(operators, state, 2, "1");
    token(operators, state, 5, "]"); token(operators, state, 0, "");
    let comment_cr = "a // first\rsecond\r\nb";
    state = lexer::init(comment_cr);
    token(comment_cr, state, 1, "a"); token(comment_cr, state, 6, "\r\n");
    token(comment_cr, state, 1, "b"); token(comment_cr, state, 0, "");
    let path = "import \"./café.blot\" as m\r\n";
    state = lexer::init(path);
    token(path, state, 1, "import"); token(path, state, 4, "\"./café.blot\"");
    token(path, state, 1, "as"); token(path, state, 1, "m");
    token(path, state, 6, "\r\n"); token(path, state, 0, "");

    assert(expect_error("a\n   b") == 1);
    assert(expect_error("a\n    b") == 1);
    assert(expect_error("a\n\tb") == 1);
    assert(expect_error("(a,\n\tb)") == 1);
    assert(expect_error("(a,\n  \tb)") == 1);
    assert(expect_error("(a,\n\t)") == 1);
    assert(expect_error("(a,\n  \t// blank\n b)") == 1);
    assert(expect_error("a\rb") == 1);
    assert(expect_error("([)]") == 1);
    assert(expect_error("(") == 1);
    assert(expect_error("\"unterminated") == 1);
    let invalid: u8[] = ['/', '/', ' ', 255];
    assert(expect_error(invalid[..]) == 1);
    let overlong: u8[] = ['/', '/', 192, 128];
    let surrogate: u8[] = ['/', '/', 237, 160, 128];
    let too_large: u8[] = ['/', '/', 244, 144, 128, 128];
    let truncated: u8[] = ['/', '/', 226, 130];
    assert(expect_error(overlong[..]) == 1);
    assert(expect_error(surrogate[..]) == 1);
    assert(expect_error(too_large[..]) == 1);
    assert(expect_error(truncated[..]) == 1);
    var deep_ok: u8[>..] = [];
    for i in 64 { deep_ok.push('('); }
    for i in 64 { deep_ok.push(')'); }
    var deep_state = lexer::init(deep_ok[..]);
    for i in 128 { assert(lexer::next(deep_ok[..], deep_state).kind == 5); }
    assert(lexer::next(deep_ok[..], deep_state).kind == 0);
    var deep: u8[>..] = [];
    for i in 65 { deep.push('('); }
    assert(expect_error(deep[..]) == 5);
    var indented: u8[>..] = [];
    for level in 66 {
        for i in level * 2 { indented.push(' '); }
        indented.push('x'); indented.push('\n');
    }
    assert(expect_error(indented[..]) == 5);
    var boundary: u8[>..] = [];
    for i in 16777216 { boundary.push('a'); }
    var boundary_state = lexer::init(boundary[..]);
    assert(boundary_state.error_status == 0);
    boundary.push('a');
    assert(lexer::init(boundary[..]).error_status == 5);
    print("lexer laws passed");
}
