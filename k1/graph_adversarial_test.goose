// Independently generated raw graph data and forged snapshots; this checks the
// private model and does not make its numeric stamps into source authority.
import graph_core;
import graph_build;
import graph_validate;
import graph_wasm;
fn random(seed: u32&) -> u32 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed; }
fn word(out: u8[>..]&, value: u32) { for i in 4 { out.push((value >> (8*i) & 255) as u8); } }
fn main() {
    var seed: u32 = 0x42ac17d2; var clock = graph_core::Clock {}; var good = 0; var bad = 0;
    for trial in 3000 {
        let n = random(seed) % 129; let m = random(seed) % 129;
        var src: u8[>..] = []; word(src,n); word(src,m);
        for i in n { word(src,random(seed)); }
        var expected_edge: i64 = -1; var expected_side: i64 = -1; var expected_checks: i64 = 0;
        for i in m {
            for side in 2 {
                let candidate = if n == 0 || random(seed) % 30 == 0 { n } else { random(seed) % n };
                word(src,candidate);
                if expected_edge < 0 {
                    expected_checks += 1;
                    if candidate >= n { expected_edge = i; expected_side = side; }
                }
            }
        }
        let before = clock.next;
        var graph, result = graph_build::make(clock,src);
        if expected_edge >= 0 {
            bad += 1;
            assert(result.status == 2 && result.checked == expected_checks && result.bad_edge == expected_edge && result.bad_side == expected_side);
            assert(clock.next == before && graph.source.len == 0 && graph.node_values.len == 0 && graph.endpoints.len == 0);
        } else {
            good += 1;
            assert(result.status == 0 && result.checked == m as i64 * 2 && clock.next == before + 3);
            assert(graph_validate::verify(graph,src,graph.ticket));
            assert(graph_wasm::emit(graph,src,graph.ticket).len > 0);
            if m > 0 {
                var forged = graph_core::Graph { source: copy(graph.source), node_values: copy(graph.node_values), endpoints: copy(graph.endpoints), ticket: graph.ticket };
                forged.endpoints[random(seed) % forged.endpoints.len] = n;
                assert(!graph_validate::verify(forged,src,graph.ticket));
                assert(graph_wasm::emit(forged,src,graph.ticket).len == 0);
            }
        }
    }
    assert(good > 0 && bad > 0);
    // Exact implementation bound: 128 nodes, 128 endpoint pairs, 1544 bytes.
    var max: u8[>..] = []; word(max,128); word(max,128);
    for i in 128 { word(max,i as u32); }
    for i in 128 { word(max,i as u32); word(max,(127-i) as u32); }
    assert(max.len == 1544);
    var biggest, max_result = graph_build::make(clock,max);
    assert(max_result.status == 0 && max_result.checked == 256 && graph_validate::verify(biggest,max,biggest.ticket));
    max.push(0); assert(!graph_validate::verify(biggest,max,biggest.ticket));
    let before = clock.next; let _, too_long = graph_build::make(clock,max);
    assert(too_long.status == 1 && clock.next == before);
    print("private graph independent raw-data adversarial tests passed");
}
