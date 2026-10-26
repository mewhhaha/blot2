// Independently recognizes the restricted generic declaration and checks all
// completed-body fields. It does not call generic_identity::parse.
namespace generic_identity_verify;
import lexer;
import validate;
import generic_identity;

fn verify(source: u8[:], body: generic_identity::Body) -> bool {
    if body.status != 0 || body.binder_count != 1 || body.depth != 1 || body.frame != 256 ||
       body.moved != 1 || body.copied != 0 || body.discarded != 0 { return false; }
    let expected = ["pub", "let", "", ":", "forall", "[", "", ":", "Type", "]", "=>",
        "Fn", "[", "static", ",", "Many", ",", "", ",", "", "]", "!", "{", "}",
        "resources", "{", "depth", ":", "1", ",", "frame", ":", "256", "}", "=", "fn", "", "=>", "return", ""];
    var state = lexer::init(source);
    var binder_start: i64 = 0; var binder_end: i64 = 0;
    var parameter_start: i64 = 0; var parameter_end: i64 = 0;
    for value, i in expected {
        let t = lexer::next(source, state);
        if t.kind == 0 || t.kind >= 6 || t.start < 0 || t.end <= t.start || t.end > source.len { return false; }
        let bytes = source[t.start..t.end];
        if i == 2 || i == 6 || i == 36 {
            if t.kind != 1 || !validate::name_valid(bytes) { return false; }
            if i == 2 && (t.start != body.name_start || t.end != body.name_end) { return false; }
            if i == 6 {
                if t.start != body.binder_start || t.end != body.binder_end { return false; }
                binder_start = t.start; binder_end = t.end;
            }
            if i == 36 {
                if t.start != body.parameter_start || t.end != body.parameter_end { return false; }
                parameter_start = t.start; parameter_end = t.end;
            }
        } else if i == 17 || i == 19 {
            if t.kind != 1 || bytes != source[binder_start..binder_end] { return false; }
        } else if i == 39 {
            if t.kind != 1 || bytes != source[parameter_start..parameter_end] { return false; }
        } else if bytes != value { return false; }
    }
    var tail = lexer::next(source, state);
    while tail.kind == 6 { tail = lexer::next(source, state); }
    return tail.kind == 0;
}
