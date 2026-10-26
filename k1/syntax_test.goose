import syntax;
import std;

fn node(tag: i64, parent: i64, target: i64) -> syntax::Node {
    return syntax::Node { tag: tag, start: 0, end: 10, parent: parent, target: target };
}
fn main() {
    var source: u8[>..] = [];
    source.append("0123456789");
    var nodes: syntax::Node[>..] = [];
    nodes.push(node(0, 0, 0)); // root 1
    nodes.push(node(2, 1, 0)); // function 2
    nodes.push(node(3, 2, 0)); // value block 3
    nodes.push(node(4, 3, 0)); // non-carry loop 4
    nodes.push(node(8, 4, 3)); // break value crosses loop to value block
    nodes.push(node(9, 4, 4)); // bare break
    nodes.push(node(2, 4, 0)); // nested function resets targets
    nodes.push(node(7, 7, 7)); // return nested function
    nodes.push(node(6, 7, 0)); // owned construction
    nodes.push(node(13, 9, 9)); // seal owned construction
    nodes.push(node(5, 2, 0)); // carry loop
    nodes.push(node(11, 11, 11)); // next carry
    var arena, ok = syntax::own(source, nodes);
    assert(ok && syntax::validate(arena) == 0);
    assert(syntax::validate_budget(arena, 1) == 2);
    assert(syntax::validate_budget(arena, 29) == 2);
    assert(syntax::validate_budget(arena, 30) == 0);
    assert(syntax::validate_budget(arena, -1) == 1);
    assert(syntax::validate_budget(arena, 1048577) == 1);
    source[0] = 'x'; nodes[1].tag = 1;
    assert(arena.source[0] == '0' && arena.nodes[1].tag == 2); // snapshot copies

    arena.nodes[7].target = 2; assert(syntax::validate(arena) == 1); arena.nodes[7].target = 7;
    arena.nodes[7].tag = 8; arena.nodes[7].target = 3; assert(syntax::validate(arena) == 1);
    arena.nodes[7].tag = 7; arena.nodes[7].target = 7;
    arena.nodes[5].target = 3; assert(syntax::validate(arena) == 1); arena.nodes[5].target = 4;
    arena.nodes[11].tag = 9; assert(syntax::validate(arena) == 1); arena.nodes[11].tag = 11;
    arena.nodes[4].target = 4; assert(syntax::validate(arena) == 1); arena.nodes[4].target = 3;
    arena.nodes[9].target = 2; assert(syntax::validate(arena) == 1); arena.nodes[9].target = 9;
    // A return from inside an active owned construction cannot reach its
    // enclosing function before the required seal/abort terminal.
    arena.nodes[9].tag = 7; arena.nodes[9].target = 7;
    assert(syntax::validate(arena) == 1);
    arena.nodes[9].tag = 13; arena.nodes[9].target = 9;
    arena.nodes[4].parent = 6; assert(syntax::validate(arena) == 1); arena.nodes[4].parent = 4;
    arena.nodes[4].reference = 3; assert(syntax::validate(arena) == 0);
    arena.nodes[4].reference = 5; assert(syntax::validate(arena) == 1);
    arena.nodes[4].reference = 6; assert(syntax::validate(arena) == 1);
    arena.nodes[4].reference = 0;
    arena.nodes[4].end = 11; assert(syntax::validate(arena) == 1); arena.nodes[4].end = 10;
    arena.nodes[4].start = 11; assert(syntax::validate(arena) == 1); arena.nodes[4].start = 0;
    arena.nodes[3].target = 2; assert(syntax::validate(arena) == 1); arena.nodes[3].target = 0;
    arena.nodes[3].tag = 15; assert(syntax::validate(arena) == 1); arena.nodes[3].tag = 4;
    arena.nodes[0].end = 9; assert(syntax::validate(arena) == 1); arena.nodes[0].end = 10;
    assert(syntax::validate(arena) == 0);
    // A nested value block shadows the outer target; a nested function also
    // cannot capture a parent owned-construction target.
    var nested: syntax::Node[>..] = [];
    nested.push(node(0, 0, 0)); nested.push(node(2, 1, 0));
    nested.push(node(3, 2, 0)); nested.push(node(3, 3, 0));
    nested.push(node(8, 4, 4));
    var shadow, shadow_ok = syntax::own(source, nested);
    assert(shadow_ok && syntax::validate(shadow) == 0);
    shadow.nodes[4].target = 3; assert(syntax::validate(shadow) == 1);
    var invalid: u8[>..] = []; invalid.push(255);
    var root: syntax::Node[>..] = [];
    root.push(syntax::Node { tag: 0, start: 0, end: 1 });
    var malformed, malformed_ok = syntax::own(invalid, root);
    assert(malformed_ok && syntax::validate(malformed) == 1);
    var too_large: u8[>..] = [];
    for i in 16777217 { too_large.push(0); }
    let declined, within_bound = syntax::own(too_large, root);
    assert(!within_bound && declined.source.len == 0 && declined.nodes.len == 0);
    var excessive_nodes: syntax::Node[>..] = [];
    for i in 1048577 { excessive_nodes.push(node(1, 1, 0)); }
    let declined_nodes, node_bound = syntax::own(source, excessive_nodes);
    assert(!node_bound && declined_nodes.nodes.len == 0);
    print("owned syntax structure: passed");
}
