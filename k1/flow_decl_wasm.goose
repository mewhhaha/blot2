// Private whole-source entry: no bytes escape if rechecking fails.
namespace flow_decl_wasm;
import flow_decl;
import flow_decl_check;
import flow_typed_wasm;
// expected_source must be the caller's independently retained immutable source.
// Exact equality binds this candidate to that source; its digest cannot do so.
fn emit(expected_source: u8[:], d: flow_decl::Declaration&) -> u8[] {
    if expected_source.len > 16777216 || expected_source != d.source || !flow_decl_check::verify(d) { return []; }
    return flow_typed_wasm::emit(d.body);
}
