// The compile interface: checked, lowered Core modules in, one Wasm module or
// one diagnostic out. The direct backend (direct/) is the only code generator.
//
// Port of compiler/src/compile.zig. The caller provides the buffers: `bytes`
// receives the Wasm module, `detail` the diagnostic's detail.
namespace squid_compile;
import std;
import check.core;
import check.diagnostic_code;
import check.wire_schema;
import direct.direct;

type Code = squid_check_diagnostic_code::Code;

struct Diagnostic { unit: u32 = 0, span: squid_check_core::Span = squid_check_core::Span { 0, 0 }, code: Code = squid_check_diagnostic_code::Code.storage_unsupported }
fn message(self_: Diagnostic, detail: const u8[:]) -> const u8[:] { return squid_check_diagnostic_code::message(self_.code, detail); }

// Either `bytes` holds a module, or `has_diagnostic` is set and `detail`
// holds the diagnostic's detail.
struct Result { has_diagnostic: bool = false, diagnostic: Diagnostic = Diagnostic {}, emitted_functions: i64 = 0, sparks_vectorized: i64 = 0, sparks_scalar_fallback: i64 = 0, staged_dep_units_valid: bool = false, staged_value_digest: u64 = 0 }

fn compile(units: const squid_check_core::Module[:], entry: u32, bytes: u8[>..<]&, detail: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    var staged_units: u32[>..<] = [];
    return compileWithStaged(units, entry, bytes, detail, staged_units, build_inputs);
}

fn compileWithStaged(units: const squid_check_core::Module[:], entry: u32, bytes: u8[>..<]&, detail: u8[>..<]&, staged_units: u32[>..<]&, build_inputs:i64 = -1) -> Result {
    let built = squid_direct::compileWithStaged(units, entry, bytes, detail, staged_units, build_inputs);
    if built.failed { return Result { has_diagnostic: true, diagnostic: Diagnostic { unit: built.unit, span: built.span, code: built.code } }; }
    return Result { emitted_functions: built.emitted_functions, sparks_vectorized: built.sparks_vectorized, sparks_scalar_fallback: built.sparks_scalar_fallback, staged_dep_units_valid: built.staged_dep_units_valid, staged_value_digest: built.staged_value_digest };
}

fn compileWithStagedAndAnalysis(units: const squid_check_core::Module[:], entry: u32, pinfo: const squid_check_wire_schema::ProgramInfo&, bytes: u8[>..<]&, detail: u8[>..<]&, staged_units: u32[>..<]&, build_inputs:i64 = -1) -> Result {
    let built = squid_direct::compileWithStagedAndAnalysis(units, entry, pinfo, bytes, detail, staged_units, build_inputs);
    if built.failed { return Result { has_diagnostic: true, diagnostic: Diagnostic { unit: built.unit, span: built.span, code: built.code } }; }
    return Result { emitted_functions: built.emitted_functions, sparks_vectorized: built.sparks_vectorized, sparks_scalar_fallback: built.sparks_scalar_fallback, staged_dep_units_valid: built.staged_dep_units_valid, staged_value_digest: built.staged_value_digest };
}
