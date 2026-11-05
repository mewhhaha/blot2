// Preserve IEEE F32 comparison semantics while descriptors carry integer bits.
namespace blot_backend_storage_patterns;
import .runtime_code;
import .runtime_ir;
import .wasm;
import support.emitter;
import support.error;
fn equal<M>(c: blot_backend_runtime_code::Code<M>&,left: blot_backend_runtime_code::Local,right: blot_backend_runtime_code::Local,floating: bool) -> blot_backend_runtime_code::Local,blot_error::Error {
    var code = blot_emitter::init(c.module,c.function); let result = code.temp(); code.value(left); if floating { code.op(blot_backend_runtime_ir::OP_f32_reinterpret_i32); } code.value(right); if floating { code.op(blot_backend_runtime_ir::OP_f32_reinterpret_i32); code.op(blot_backend_runtime_ir::OP_f32_eq); } else { code.op(blot_backend_runtime_ir::OP_i32_eq); } code.set(result); return result,code.failure;
}
