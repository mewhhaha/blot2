import add_parser;
import add_frontend;
import parser;
import syntax;
fn accepted(source: u8[:], count: i64) {
    let candidate = add_frontend::parse(source);
    assert(candidate.status == 0);
    var arena, status = add_parser::parse(source);
    assert(status == 0 && arena.nodes.len == count && add_parser::verify(arena, candidate.core));
    let op = candidate.core.operator_start;
    assert(arena.source[op] == '+');
    var found = false;
    for n in arena.nodes {
        if n.start == op && n.end == op + 1 { found = true; }
    }
    assert(found); // The AST retains the original plus-token byte span.
    let old, old_status = parser::parse(source);
    assert(old_status != 0 && old.nodes.len == 0); // v2 remains fenced.
}
fn main() {
    accepted("let f: U32 -> U32 = fn x => return x + 0", 9);
    accepted("let f: U32 -> U32 = fn x => do:\n  return x + 0\n", 9);
    accepted("let f: U32 -> U32 = fn x => return do:\n  break x + 0\n", 11);
    accepted("let f: U32 -> U32 = fn x => do:\n  return do:\n    return x + 0\n", 11);
    let source = "let f: U32 -> U32 = fn x => return do:\n  break x + 0\n";
    let candidate = add_frontend::parse(source);
    var arena, status = add_parser::parse(source);
    assert(status == 0 && add_parser::verify(arena, candidate.core));
    assert(arena.nodes[6].tag == 8 && arena.nodes[6].target == 6);
    arena.nodes[6].target = 3; assert(!add_parser::verify(arena, candidate.core)); arena.nodes[6].target = 6;
    arena.nodes[9].start += 1; assert(!add_parser::verify(arena, candidate.core)); arena.nodes[9].start -= 1;
    arena.source[candidate.core.operator_start] = '&'; assert(!add_parser::verify(arena, candidate.core));
    let invalid, invalid_status = add_parser::parse("let f: U32 -> U32 = fn x => return x + 1");
    assert(invalid_status == 10 && invalid.nodes.len == 0);
    print("checked-add source syntax: passed");
}
