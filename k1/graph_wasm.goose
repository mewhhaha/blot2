// Private execution witness for an independently checked graph snapshot. One
// fixed, unexported memory holds immutable nodes and branded endpoint payloads.
// Two exports check the edge-array index; stored endpoints are not rescanned
// or revalidated on traversal. The module contains no imports, stores, grow,
// host bridge, dynamic package identity or K1 source-lowering authority.
namespace graph_wasm;
import graph_core;
import graph_validate;
import wasm;
fn byte(out: u8[>..]&, b: u8) { out.push(b); }
fn leb(out: u8[>..]&, n: i64) { wasm::unsigned_leb(out,n); }
fn c(out: u8[>..]&, n: u32) { byte(out,0x41); wasm::signed_i32_leb(out,n); }
fn section(out: u8[>..]&, id: u8, data: u8[:]) { byte(out,id); leb(out,data.len); out.append(data); }
fn reader(n: u32, m: u32, side: u32) -> u8[>..] {
    var b: u8[>..] = [0]; // one parameter, no locals
    byte(b,0x20); leb(b,0); c(b,m); byte(b,0x4f); // edge index >= m
    byte(b,0x04); byte(b,0x40); byte(b,0x00); byte(b,0x0b); // explicit invalid-index fault
    c(b,64); // nodes base
    c(b,64 + n*4); byte(b,0x20); leb(b,0); c(b,8); byte(b,0x6c); byte(b,0x6a);
    byte(b,0x28); byte(b,2); leb(b,side*4); // stored, already checked endpoint
    c(b,4); byte(b,0x6c); byte(b,0x6a);
    byte(b,0x28); byte(b,2); leb(b,0); byte(b,0x0b); return b;
}
fn emit(graph: graph_core::Graph&, source: u8[:], ticket: graph_core::Ticket) -> u8[] {
    if !graph_validate::verify(graph,source,ticket) { return []; }
    let n = graph.node_values.len as u32; let m = (graph.endpoints.len / 2) as u32;
    var out: u8[>..] = [0,0x61,0x73,0x6d,1,0,0,0];
    let types: u8[6] = [1,0x60,1,0x7f,1,0x7f]; section(out,1,types);
    let funcs: u8[3] = [2,0,0]; section(out,3,funcs);
    let memory: u8[4] = [1,1,1,1]; section(out,5,memory);
    let exports: u8[19] = [2,6,'s','o','u','r','c','e',0,0,6,'t','a','r','g','e','t',0,1]; section(out,7,exports);
    var code: u8[>..] = [2];
    let a = reader(n,m,0); let b = reader(n,m,1); leb(code,a.len); code.append(a); leb(code,b.len); code.append(b); section(out,10,code);
    // Active data offset expression. The private fixture's source payload is
    // canonical little-endian nodes followed by endpoint pairs.
    var data: u8[>..] = [1,0]; c(data,64); byte(data,0x0b); leb(data,source.len-8); data.append(source[8..]); section(out,11,data);
    return out;
}
