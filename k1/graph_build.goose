// Private graph constructor. Input layout is little-endian n,m, n U32 node
// values, then m (U32,U32) raw endpoint pairs. Both counts are <=128. This is
// not a source or host ABI. Every endpoint is checked exactly once against the
// frozen input node count before its pair enters the private construction.
// On failure no Graph or model identities are published, and the caller's raw
// input and clock are unchanged. No affine K1 capability is represented here.
namespace graph_build;
import graph_core;
fn word(s: u8[:], p: i64) -> u32 { return s[p] | (s[p+1] as u32 << 8) | (s[p+2] as u32 << 16) | (s[p+3] as u32 << 24); }
fn make(clock: graph_core::Clock&, source: u8[:]) -> graph_core::Graph, graph_core::Result {
    if source.len < 8 { return graph_core::Graph {}, graph_core::Result { status: 1 }; }
    let n = word(source,0); let m = word(source,4);
    if n > 128 || m > 128 || source.len != 8 + n as i64 * 4 + m as i64 * 8 {
        return graph_core::Graph {}, graph_core::Result { status: 1 };
    }
    var nodes: u32[>..] = [];
    for i in n { nodes.push(word(source,8+i as i64 * 4)); }
    var edges: u32[>..] = []; var checked: i64 = 0;
    for i in m {
        let p = 8 + n as i64 * 4 + i as i64 * 8;
        let a = word(source,p); checked += 1;
        if a >= n { return graph_core::Graph {}, graph_core::Result { status: 2, checked: checked, bad_edge: i, bad_side: 0 }; }
        let b = word(source,p+4); checked += 1;
        if b >= n { return graph_core::Graph {}, graph_core::Result { status: 2, checked: checked, bad_edge: i, bad_side: 1 }; }
        edges.push(a); edges.push(b);
    }
    if clock.next > 18446744073709551612 { return graph_core::Graph {}, graph_core::Result { status: 3, checked: checked }; }
    let ticket = graph_core::Ticket { owner: clock.next + 1, nodes: clock.next + 2, edges: clock.next + 3 };
    // Complete all owned copies before publishing the model clock transition.
    let result = graph_core::Graph { source: source, node_values: copy(nodes), endpoints: copy(edges), ticket: ticket };
    clock.next += 3;
    return result, graph_core::Result { checked: checked };
}
