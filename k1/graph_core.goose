// Private graph-data snapshot. The raw input encoding is a fixture, not K1
// source, a portable artifact, a checked host schema, or a domain proof.
// Node and edge brands are model-local stamps from ONE trusted Clock. Raw
// integers or caller-supplied Ticket values never establish K1 authority.
namespace graph_core;
struct Ticket { owner: u64 = 0, nodes: u64 = 0, edges: u64 = 0 }
struct Clock { next: u64 = 0 }
struct Graph { source: u8[] = [], node_values: u32[] = [], endpoints: u32[] = [], ticket: Ticket = Ticket {} }
struct Result {
    // 0 success, 1 malformed/unsupported data, 2 out-of-range endpoint,
    // 3 model-local stamp exhaustion. checked counts inspected endpoint words.
    status: i64 = 0, checked: i64 = 0, bad_edge: i64 = -1, bad_side: i64 = -1
}
struct Opening { owner: u64 = 0, nodes: u64 = 0, edges: u64 = 0, node_binder: u64 = 0, edge_binder: u64 = 0 }
struct Index { owner: u64 = 0, node_binder: u64 = 0, value: u32 = 0 }
fn valid_ticket(t: Ticket) -> bool { return t.owner != 0 && t.nodes != 0 && t.edges != 0 && t.owner != t.nodes && t.owner != t.edges && t.nodes != t.edges; }
fn same_ticket(a: Ticket, b: Ticket) -> bool { return a.owner == b.owner && a.nodes == b.nodes && a.edges == b.edges; }
// These numbers model rigid fresh binders; only a source/type checker can make
// them meaningful. Opening the same graph twice deliberately yields distinct
// binder identities. The one-clock and immutable-graph preconditions matter.
fn open(clock: Clock&, graph: Graph&) -> Opening, bool {
    if !valid_ticket(graph.ticket) || clock.next < graph.ticket.owner || clock.next < graph.ticket.nodes ||
       clock.next < graph.ticket.edges || clock.next > 18446744073709551613 { return Opening {}, false; }
    let d = clock.next + 1; let e = clock.next + 2; clock.next += 2;
    return Opening { owner: graph.ticket.owner, nodes: graph.ticket.nodes, edges: graph.ticket.edges, node_binder: d, edge_binder: e }, true;
}
fn matches(graph: Graph&, opened: Opening) -> bool {
    return valid_ticket(graph.ticket) && opened.owner == graph.ticket.owner && opened.nodes == graph.ticket.nodes &&
        opened.edges == graph.ticket.edges && opened.node_binder > graph.ticket.owner && opened.node_binder > graph.ticket.nodes &&
        opened.node_binder > graph.ticket.edges && opened.edge_binder > graph.ticket.owner && opened.edge_binder > graph.ticket.nodes &&
        opened.edge_binder > graph.ticket.edges && opened.node_binder != opened.edge_binder;
}
fn try_index(graph: Graph&, opened: Opening, value: u32) -> Index, bool {
    if !matches(graph,opened) || value >= graph.node_values.len { return Index {}, false; }
    return Index { owner: opened.owner, node_binder: opened.node_binder, value: value }, true;
}
fn read_index(graph: Graph&, opened: Opening, idx: Index) -> u32, bool {
    if !matches(graph,opened) || idx.owner != opened.owner || idx.node_binder != opened.node_binder || idx.value >= graph.node_values.len { return 0,false; }
    return graph.node_values[idx.value], true;
}
