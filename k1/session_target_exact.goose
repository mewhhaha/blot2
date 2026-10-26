// Exact private scalar fixture custom-section checker. The independent
// executable/geometry validator must also run; metadata is never used as
// authority for source, memory, code, receipts, or K1 ABI provenance.
namespace session_target_exact;
import wasm_scalar_validation;
import work;

// 0 canonical metadata, 1 malformed/noncanonical, 4 telemetry failure.
fn verify(bytes: u8[:], meter: work::Meter&) -> i64 {
    if bytes.len < 8 { return 1; }
    var root = wasm_scalar_validation::Reader { at: 8, end: bytes.len };
    for id in [1, 3, 5, 7, 10] {
        if work::target_visit(meter).status != 0 { return 4; }
        let section = wasm_scalar_validation::section(bytes, root, id);
        if !section.ok { return 1; }
    }
    if work::target_visit(meter).status != 0 { return 4; }
    var custom = wasm_scalar_validation::section(bytes, root, 0);
    if !custom.ok || !wasm_scalar_validation::done(root) { return 1; }
    let name_len = wasm_scalar_validation::u32_leb(bytes, custom);
    if name_len < 0 || name_len > custom.end - custom.at ||
       bytes[custom.at..custom.at + name_len] != "blot.k1.fixture.memory" { return 1; }
    custom.at += name_len;
    let expected = "{\"version\":1,\"page_bytes\":65536,\"pages\":275,\"granule_bytes\":4096,\"static_bytes\":0,\"dictionary_bytes\":0,\"control\":[0,16],\"owners\":[16,8192],\"owner_slots\":256,\"owner_stride\":32,\"bitmap\":[8208,512],\"frame\":[8720,1048576],\"ingress\":[1057296,65536],\"egress\":[1122832,65536],\"alignment_padding\":[1188368,3568],\"pool\":[1191936,16777216],\"page_padding\":[17969152,53248],\"memory_bytes\":18022400}";
    if bytes[custom.at..custom.end] != expected { return 1; }
    return 0;
}
