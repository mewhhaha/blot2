import os;
import graph_core;
import graph_build;
import graph_validate;
import graph_wasm;
fn word(out: u8[>..]&, value: u32) { for i in 4 { out.push((value >> (8*i) & 255) as u8); } }
fn source() -> u8[>..] {
    var s: u8[>..] = []; word(s,3); word(s,2);
    for n in [100, 0xffffffff, 17] { word(s,n as u32); }
    for e in [0,1,2,0] { word(s,e as u32); } return s;
}
fn same(g: graph_core::Graph&) -> graph_core::Graph {
    return graph_core::Graph { source: copy(g.source), node_values: copy(g.node_values), endpoints: copy(g.endpoints), ticket: g.ticket };
}
fn main() {
    var clock = graph_core::Clock {}; var input = source(); let trusted = copy(input);
    var g, result = graph_build::make(clock,input);
    assert(result.status == 0 && result.checked == 4 && g.node_values.len == 3 && g.endpoints.len == 4);
    let first_ticket = g.ticket;
    assert(graph_validate::verify(g,trusted,first_ticket));
    // Producer owns input; later mutation of caller's original bytes cannot
    // alter the frozen source or expected data.
    input[8] ^= 0xff; assert(graph_validate::verify(g,trusted,first_ticket));
    let first_wasm = graph_wasm::emit(g,trusted,first_ticket); assert(first_wasm.len > 0 && write_file("graph-fixture.wasm",first_wasm));
    let opened1, a = graph_core::open(clock,g); let opened2, b = graph_core::open(clock,g);
    assert(a && b && opened1.node_binder != opened2.node_binder && opened1.edge_binder != opened2.edge_binder);
    var wrong_clock = graph_core::Clock {};
    let _, wrong_clock_ok = graph_core::open(wrong_clock,g); assert(!wrong_clock_ok && wrong_clock.next == 0);
    let index, present = graph_core::try_index(g,opened1,1); assert(present);
    let value, found = graph_core::read_index(g,opened1,index); assert(found && value == 0xffffffff);
    let _, wrong_open = graph_core::read_index(g,opened2,index); assert(!wrong_open);
    let _, absent = graph_core::try_index(g,opened1,3); assert(!absent);
    // Two equal-content constructions at one site have distinct local model
    // stamps; neither equal lengths nor equal bytes equate their openings.
    var other, second = graph_build::make(clock,trusted); assert(second.status == 0);
    assert(!graph_core::same_ticket(first_ticket,other.ticket));
    assert(!graph_validate::verify(other,trusted,first_ticket));
    let open_other, made = graph_core::open(clock,other); assert(made);
    let _, cross_owner = graph_core::read_index(other,open_other,index); assert(!cross_owner);
    let _, cross_open = graph_core::try_index(other,opened1,0); assert(!cross_open);
    assert(graph_validate::verify(other,trusted,other.ticket));
    let other_wasm = graph_wasm::emit(other,trusted,other.ticket); assert(other_wasm.len > 0 && write_file("graph-other.wasm",other_wasm));
    // Forged fields, data, identity, length, and source mismatches never reach
    // the private emitter. The expected ticket/source are trusted inputs.
    for field in 6 {
        var fake = same(g);
        if field == 0 { fake.node_values[0] ^= 1; }
        else if field == 1 { fake.endpoints[0] = 3; }
        else if field == 2 { fake.endpoints[1] = 0xffffffff; }
        else if field == 3 { fake.source[8] ^= 1; }
        else if field == 4 { fake.ticket.nodes = fake.ticket.edges; }
        else { fake.ticket.owner = other.ticket.owner; }
        assert(!graph_validate::verify(fake,trusted,first_ticket));
        assert(graph_wasm::emit(fake,trusted,first_ticket).len == 0);
    }
    var no_nodes = graph_core::Graph { source: copy(g.source), node_values: [], endpoints: copy(g.endpoints), ticket: g.ticket };
    var no_edges = graph_core::Graph { source: copy(g.source), node_values: copy(g.node_values), endpoints: [], ticket: g.ticket };
    assert(!graph_validate::verify(no_nodes,trusted,first_ticket) && graph_wasm::emit(no_nodes,trusted,first_ticket).len == 0);
    assert(!graph_validate::verify(no_edges,trusted,first_ticket) && graph_wasm::emit(no_edges,trusted,first_ticket).len == 0);
    var altered = copy(trusted); altered[8] ^= 1;
    assert(!graph_validate::verify(g,altered,first_ticket));
    // Invalid second edge: the first pair and first endpoint of the second
    // were checked, but no partial graph or fresh IDs are published.
    var bad = source(); bad[28] = 3;
    let before = clock.next; let absent_graph, failure = graph_build::make(clock,bad);
    assert(failure.status == 2 && failure.checked == 3 && failure.bad_edge == 1 && failure.bad_side == 0);
    assert(clock.next == before && absent_graph.source.len == 0 && absent_graph.node_values.len == 0 && absent_graph.endpoints.len == 0);
    // Zero-node view cannot mint even an index whose numeric value is zero.
    var empty: u8[>..] = []; word(empty,0); word(empty,0);
    var eg, empty_result = graph_build::make(clock,empty); assert(empty_result.status == 0 && empty_result.checked == 0);
    let eo, eo_ok = graph_core::open(clock,eg); assert(eo_ok);
    let _, empty_index = graph_core::try_index(eg,eo,0); assert(!empty_index);
    let empty_wasm = graph_wasm::emit(eg,empty,eg.ticket); assert(empty_wasm.len > 0 && write_file("graph-empty.wasm",empty_wasm));
    var max: u8[>..] = []; word(max,128); word(max,128);
    for i in 128 { word(max,i as u32); }
    for i in 128 { word(max,i as u32); word(max,(127-i) as u32); }
    var mg, mr = graph_build::make(clock,max); assert(mr.status == 0 && mr.checked == 256);
    let max_wasm = graph_wasm::emit(mg,max,mg.ticket); assert(max_wasm.len > 0 && write_file("graph-max.wasm",max_wasm));
    word(empty,0); word(empty,0); empty[4] = 1;
    let empty_before = clock.next; let _, empty_bad = graph_build::make(clock,empty);
    assert(empty_bad.status == 2 && empty_bad.bad_edge == 0 && empty_bad.checked == 1 && clock.next == empty_before);
    // Bounds and identity exhaustion never alter the clock or emit data.
    var short: u8[3] = [0,0,0]; let _, malformed = graph_build::make(clock,short); assert(malformed.status == 1);
    var exhausted = graph_core::Clock { next: 18446744073709551613 };
    let _, no_ids = graph_build::make(exhausted,trusted); assert(no_ids.status == 3 && exhausted.next == 18446744073709551613);
    var exhausted_open = graph_core::Clock { next: 18446744073709551614 };
    let _, no_open = graph_core::open(exhausted_open,g); assert(!no_open && exhausted_open.next == 18446744073709551614);
    print("private checked graph snapshot laws passed");
}
