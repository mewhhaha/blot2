// Independent source-to-Core recognizer for the private checked-add fixture.
// This does not build a proof or admit a source program.
namespace add_source;
import scalar_core;
import validate;
import catalog;

// Returns 0 only for exact x + 0 with the frozen op-3 Core. It never calls the
// frontend or trusts the producer. Check the original plus byte and exact
// Core operation first, then use an equal-length, private bitand projection to
// reuse the independent v2 recognizer for every remaining source token, span,
// parameter binding, lexical target and canonical value field. The replacement
// is one byte at a verified operator span; no input or caller Core is mutated.
fn validate(source: u8[:], core: scalar_core::ScalarCore) -> i64 {
    if source.len > 16777216 || core.operator_start < 0 ||
       core.operator_start >= source.len || core.operator_end != core.operator_start + 1 ||
       source[core.operator_start] != '+' || core.value_count != 3 || core.result_id != 2 ||
       core.values[2].op_id != 3 { return 1; }
    var projected: u8[>..] = [];
    projected.append(source);
    projected[core.operator_start] = '&';
    var projected_core = core;
    projected_core.values[2].op_id = 1;
    if validate::scalar_v2(projected, projected_core, catalog::edition(), catalog::semantic_policy(),
       catalog::optimization_policy(), catalog::wasm_abi()) != 0 { return 1; }
    if core.values[0].producer != 1 || core.values[1].producer != 2 ||
       core.values[1].literal != 0 || core.values[2].left_id != 0 || core.values[2].right_id != 1 { return 1; }
    return 0;
}
