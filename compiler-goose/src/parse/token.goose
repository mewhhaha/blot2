// Source contract: compiler/src/parse/token.zig. Stable public ordinals.
namespace blot_parse_token;

type Tag = u32;
let eof: Tag = 0;
let identifier: Tag = 1;
let type_identifier: Tag = 2;
let integer: Tag = 3;
let float: Tag = 4;
let string: Tag = 5;
let intrinsic: Tag = 6;
let symbol: Tag = 7;
let comment: Tag = 8;
let l_paren: Tag = 9;
let r_paren: Tag = 10;
let l_bracket: Tag = 11;
let r_bracket: Tag = 12;
let l_brace: Tag = 13;
let r_brace: Tag = 14;
let comma: Tag = 15;
let dot: Tag = 16;
let selector: Tag = 17;
let dot_dot: Tag = 18;
let colon: Tag = 19;
let colon_equal: Tag = 20;
let arrow: Tag = 21;
let fat_arrow: Tag = 22;
let left_arrow: Tag = 23;
let hash: Tag = 24;
let at: Tag = 25;
let ellipsis: Tag = 26;
let backtick: Tag = 27;
let dollar: Tag = 28;
let star: Tag = 29;
let caret: Tag = 30;
let pipe: Tag = 31;
let bang: Tag = 32;
let equal: Tag = 33;
let kw_import: Tag = 34;
let kw_as: Tag = 35;
let kw_const: Tag = 36;
let kw_let: Tag = 37;
let kw_type: Tag = 38;
let kw_is: Tag = 39;
let kw_data: Tag = 40;
let kw_effect: Tag = 41;
let kw_infixl: Tag = 42;
let kw_infixr: Tag = 43;
let kw_infix: Tag = 44;
let kw_func: Tag = 45;
let kw_if: Tag = 46;
let kw_then: Tag = 47;
let kw_else: Tag = 48;
let kw_do: Tag = 49;
let kw_case: Tag = 50;
let kw_of: Tag = 51;
let kw_for: Tag = 52;
let kw_in: Tag = 53;
let kw_ever: Tag = 54;
let kw_use: Tag = 55;
let kw_return: Tag = 56;
let kw_yield: Tag = 57;
let kw_break: Tag = 58;
let kw_continue: Tag = 59;
let kw_complete: Tag = 60;
let kw_true: Tag = 61;
let kw_false: Tag = 62;
let kw_and: Tag = 63;
let kw_or: Tag = 64;
let kw_from: Tag = 65;
let kw_where: Tag = 66;
let private_from: Tag = 67;
let private_where: Tag = 68;
let newline: Tag = 69;
let indent: Tag = 70;
let dedent: Tag = 71;
let kw_not: Tag = 72;
let kw_fork: Tag = 74;
let semicolon: Tag = 75;
let kw_spark: Tag = 76;
let char_literal: Tag = 77;
let byte_string: Tag = 78;

struct Token { tag: Tag, start: u32, end: u32 }
fn text(value: Token, source: const u8[:]) -> const u8[:] { return source[value.start..value.end]; }
fn keyword(value: const u8[:]) -> Tag {
    // Every keyword is two to eight lowercase letters. Dispatching on the
    // first letter eliminates almost all comparisons on identifiers.
    let len = value.len;
    if len < 2 || len > 8 { return identifier; }
    match value[0] {
        'a' => {
            if value == "as" { return kw_as; }
            if value == "and" { return kw_and; }
        },
        'b' => { if value == "break" { return kw_break; } },
        'c' => {
            if value == "const" { return kw_const; }
            if value == "case" { return kw_case; }
            if value == "continue" { return kw_continue; }
        },
        'd' => {
            if value == "do" { return kw_do; }
            if value == "data" { return kw_data; }
        },
        'e' => {
            if value == "else" { return kw_else; }
            if value == "ever" { return kw_ever; }
            if value == "effect" { return kw_effect; }
        },
        'f' => {
            if value == "for" { return kw_for; }
            if value == "func" { return kw_func; }
            if value == "false" { return kw_false; }
        },
        'i' => {
            if value == "in" { return kw_in; }
            if value == "if" { return kw_if; }
            if value == "is" { return kw_is; }
            if value == "import" { return kw_import; }
        },
        'l' => { if value == "let" { return kw_let; } },
        'n' => { if value == "not" { return kw_not; } },
        'o' => {
            if value == "or" { return kw_or; }
            if value == "of" { return kw_of; }
        },
        'r' => { if value == "return" { return kw_return; } },
        's' => { if value == "spark" { return kw_spark; } },
        't' => {
            if value == "true" { return kw_true; }
            if value == "then" { return kw_then; }
            if value == "type" { return kw_type; }
        },
        'u' => { if value == "use" { return kw_use; } },
        _ => {},
    }
    return identifier;
}
