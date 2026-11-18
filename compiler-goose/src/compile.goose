// The compile interface: checked, lowered Core modules in, one Wasm module or
// one diagnostic out. The direct backend (direct/) is the only code generator.
//
// Port of compiler/src/compile.zig. The caller provides the buffers: `bytes`
// receives the Wasm module, `detail` the diagnostic's detail.
namespace blot_compile;
import std;
import check.core;
import check.diagnostic_code;
import direct.direct;

type Code = blot_check_diagnostic_code::Code;

struct Diagnostic { unit: u32 = 0, span: blot_check_core::Span = blot_check_core::Span { 0, 0 }, code: Code = blot_check_diagnostic_code::Code.storage_unsupported }
fn message(self_: Diagnostic, detail: const u8[:]) -> const u8[:] { return blot_check_diagnostic_code::message(self_.code, detail); }

// Either `bytes` holds a module, or `has_diagnostic` is set and `detail`
// holds the diagnostic's detail.
struct Result { has_diagnostic: bool = false, diagnostic: Diagnostic = Diagnostic {}, emitted_functions: i64 = 0 }

fn compile(units: const blot_check_core::Module[:], entry: u32, bytes: u8[>..<]&, detail: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    let built = blot_direct::compile(units, entry, bytes, detail, build_inputs);
    if built.failed { return Result { has_diagnostic: true, diagnostic: Diagnostic { unit: built.unit, span: built.span, code: built.code } }; }
    return Result { emitted_functions: built.emitted_functions };
}
