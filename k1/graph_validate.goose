// Separate admission over immutable raw bytes and a trusted expected ticket.
// This independently decodes and compares every input/value/endpoint before
// using any extent, including exact producer bytes. The caller must provide
// the trusted expected identity; these numeric stamps are not authorization.
namespace graph_validate;
import graph_core;
fn read32(s: u8[:], p: i64) -> u32 { return s[p] as u32 | (s[p+1] as u32 << 8) | (s[p+2] as u32 << 16) | (s[p+3] as u32 << 24); }
fn verify(graph: graph_core::Graph&, expected_source: u8[:], expected_ticket: graph_core::Ticket) -> bool {
    if !graph_core::valid_ticket(expected_ticket) || !graph_core::same_ticket(graph.ticket,expected_ticket) ||
       expected_source.len < 8 || expected_source.len > 1544 || graph.source[..] != expected_source { return false; }
    let n = read32(expected_source,0); let m = read32(expected_source,4);
    if n > 128 || m > 128 || expected_source.len != 8 + n as i64 * 4 + m as i64 * 8 ||
       graph.node_values.len != n || graph.endpoints.len != m as i64 * 2 { return false; }
    for i in n { if graph.node_values[i] != read32(expected_source,8+i as i64*4) { return false; } }
    for i in m {
        let p = 8 + n as i64*4 + i as i64*8;
        let left = read32(expected_source,p); let right = read32(expected_source,p+4);
        if left >= n || right >= n || graph.endpoints[i*2] != left || graph.endpoints[i*2+1] != right { return false; }
    }
    return true;
}
