// Private Bool -> U32 flow experiment. The function parameter and export name
// are supplied by the fixture caller, not parsed from a function declaration.
// No public admission, artifact authority, effects, resources or ABI claim.
namespace flow_typed;
import flow_syntax;
import flow_parse;
import flow_verify;
import flow_completion;
import validate;

// Types: 1 Bool, 2 U32, 3 statement. A literal value is recorded only for
// decimal nodes. Every accepted node is checked even when a branch is pruned.
struct Program { tree: flow_syntax::Tree = flow_syntax::Tree {}, name: u8[] = [], parameter: u8[] = [], types: u8[] = [], literals: u32[] = [] }
struct Result { status: i64 = 0, program: Program = Program {} }

// 1 syntax, 2 unsupported form, 3 unbound name, 4 type mismatch,
// 5 missing return/break, 6 unreachable code, 7 invalid fixture name.
fn build(source: u8[:], name: u8[:], parameter: u8[:]) -> Result {
    if !validate::name_valid(name) || !validate::name_valid(parameter) { return Result { status: 7 }; }
    var tree, status = flow_parse::parse(source);
    if status != 0 || !flow_verify::verify(tree) { return Result { status: 1 }; }
    let completion = flow_completion::check(tree);
    if completion == 4 || completion == 9 { return Result { status: 5 }; }
    if completion == 8 { return Result { status: 6 }; }
    if completion != 0 { return Result { status: 1 }; }
    var types: u8[>..] = []; var literals: u32[>..] = [];
    for n in tree.nodes {
        var t: u8 = 0; var literal: u32 = 0;
        if n.tag == 1 {
            if tree.source[n.start..n.end] != parameter { return Result { status: 3 }; }
            t = 1;
        } else if n.tag == 2 {
            var value: u64 = 0;
            for c in tree.source[n.start..n.end] { value = value * 10 + (c - '0') as u64; }
            literal = value as u32; t = 2;
        } else if n.tag == 3 || n.tag == 4 { t = 1; }
        else if n.tag == 5 { t = types[n.a-1]; }
        else if n.tag == 7 || n.tag == 8 {
            if types[n.a-1] != 1 || types[n.b-1] != 1 { return Result { status: 4 }; }
            t = 1;
        } else if n.tag == 9 {
            if types[n.a-1] != 2 { return Result { status: 4 }; }
            t = 3;
        } else if n.tag == 10 {
            if types[n.a-1] != 1 || types[n.b-1] != 3 || (n.c != 0 && types[n.c-1] != 3) { return Result { status: 4 }; }
            t = 3;
        } else if n.tag == 11 {
            if types[n.a-1] != 3 || types[n.b-1] != 3 { return Result { status: 4 }; }
            t = 3;
        } else { return Result { status: 2 }; }
        types.push(t); literals.push(literal);
    }
    if types[tree.root-1] != 3 { return Result { status: 4 }; }
    return Result { program: Program { tree: tree, name: name, parameter: parameter, types: types, literals: literals } };
}
