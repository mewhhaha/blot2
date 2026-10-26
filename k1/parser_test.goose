import parser;
import syntax;
import frontend;

fn accepted(source: u8[:], nodes: i64) {
    var arena, status = parser::parse(source);
    assert(status == 0 && arena.nodes.len == nodes);
    assert(parser::verify(arena));
}
fn rejected(source: u8[:], status: i64) {
    let arena, found = parser::parse(source);
    assert(found == status && arena.nodes.len == 0 && arena.source.len == 0);
}
// Differential check: an already accepted frontend program must not be
// rejected by the private Arena validation gate. No conclusion is drawn for
// inputs outside the existing frontend's accepted subset.
fn parity() {
    let prefixes: const u8[:][4] = ["", "\n", "// heading\n", "// comment\rtext\n"];
    let headers: const u8[:][5] = [
        "let f: U32 -> U32 = fn x => ", "let f:U32->U32=fn x=>",
        "let  f : U32 -> U32 = fn  x => ", "let f: U32->U32=fn x => ",
        "let f: U32 -> Bool = fn x => "
    ];
    let bodies: const u8[:][10] = [
        "return x", "return 0", "return x & 1", "return x < 1",
        "do:\n  return x", "return do:\n  break x",
        "do:\n  return do:\n    break 42", "return do:\n  return x",
        "do: // inline\n  // blank\n  return x",
        "return do:\r\n  break x\r\n"
    ];
    let tails: const u8[:][6] = ["", "\n", " // comment", " // comment\r\n",
                            " // one\rtwo", "\n    // trailing\n"];
    var accepted_count: i64 = 0;
    for prefix in prefixes {
        for header in headers {
            for body in bodies {
                for tail in tails {
                    var source: u8[>..] = [];
                    source.append(prefix); source.append(header); source.append(body); source.append(tail);
                    let parsed = frontend::parse_scalar(source);
                    if parsed.status == 0 {
                        var arena, status = parser::parse(source);
                        assert(status == 0 && parser::verify(arena));
                        accepted_count += 1;
                    }
                }
            }
        }
    }
    assert(accepted_count > 500);
    print("frontend/parser accepted-case parity: ", accepted_count);
}
fn main() {
    parity();
    accepted("let f: U32 -> U32 = fn x => return x", 7);
    accepted("let f: U32 -> U32 = fn x => return x // first\rsecond", 7);
    accepted("// first\rsecond\nlet f: U32 -> U32 = fn x => return x", 7);
    accepted("let f: U32 -> U32 = fn x => return x // tail\r\n", 7);
    accepted("let f: U32 -> U32 = fn x => do:\n // comment\n  return x\n", 7);
    accepted("let f: U32 -> U32 = fn x => return do:\r\n  break x\r\n   // trailing\n", 9);
    accepted("let f: U32 -> U32 = fn x => do:\n  return x\n", 7);
    accepted("let f: U32 -> U32 = fn x => return do:\n  break x\n", 9);
    accepted("let f: U32 -> U32 = fn x => do:\n  return do:\n    break 42\n", 9);
    accepted("let f: U32 -> U32 = fn x => return do:\n  return x\n", 9);
    accepted("let f: U32 -> U32 = fn x => return x & 4294967295", 9);
    accepted("let f: U32 -> Bool = fn x => return 0 < x", 9);
    accepted("let f: U32 -> Bool = fn x => do:\n  return do:\n    break x < 1\n", 11);
    rejected("let f: U32 -> U32 = fn x => do:\n  break x\n", 6);
    rejected("let f: U32 -> U32 = fn x => x", 4);
    rejected("let f: U32 -> U32 = fn x => return y", 3);
    rejected("let f: U32 -> U32 = fn x => return x < 1", 7);
    rejected("let f: U32 -> U32 = fn x => return x + 1", 2);
    rejected("let f: U32 -> U32 = fn x => return x & 1 & 2", 2);
    rejected("let f: U32 -> U32 = fn x => do:\n    return x\n", 1);
    rejected("let f: U32 -> U32 = fn x => return x\nlet g: U32 -> U32 = fn x => return x", 2);
    let invalid: u8[] = ['/', '/', 255];
    rejected(invalid[..], 1);
    var source: u8[>..] = [];
    source.append("let f: U32 -> U32 = fn x => return do:\n  break x\n");
    var arena, status = parser::parse(source);
    assert(status == 0 && parser::verify(arena));
    assert(arena.nodes[4].tag == 7 && arena.nodes[4].target == 3);
    assert(arena.nodes[5].tag == 3 && arena.nodes[5].parent == 5);
    assert(arena.nodes[6].tag == 8 && arena.nodes[6].target == 6);
    source[0] = 'X'; // Arena owns its source snapshot.
    assert(arena.source[0] == 'l' && parser::verify(arena));
    arena.nodes[6].target = 3; assert(!parser::verify(arena)); arena.nodes[6].target = 6;
    arena.nodes[5].tag = 1; assert(!parser::verify(arena)); arena.nodes[5].tag = 3;
    arena.nodes[7].start += 1; assert(!parser::verify(arena)); arena.nodes[7].start -= 1;
    arena.nodes[8].start += 1;
    assert(syntax::validate(arena) == 0 && !parser::verify(arena));
    arena.nodes[8].start -= 1;
    arena.nodes[8].reference = 1; assert(!parser::verify(arena)); arena.nodes[8].reference = 0;
    arena.source[arena.nodes[6].start] = 'X'; assert(!parser::verify(arena));
    print("lexer to owned scalar syntax: passed");
}
