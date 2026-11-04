// Legacy guest task adapters keep their original counted-root ABI.
namespace blot_runtime_task_abi;
import backend.runtime_ir;
import backend.wasm;
import support.error;

type ValueType = blot_backend_runtime_ir::ValueType;
struct Import { name: const u8[:], parameters: const ValueType[:], result: ValueType }
let word = blot_backend_runtime_ir::VT_i32;
let no_result = blot_backend_runtime_ir::VT_none;
let imports = [
    Import { "open", [], word }, Import { "close", [word], no_result },
    Import { "spawn", [word, word, word], word }, Import { "join", [word, word], word },
    Import { "collect", [word, word, word], no_result }, Import { "cancel", [word], no_result },
    Import { "poll", [word, word], word }, Import { "drop", [word, word], no_result },
    Import { "drain", [], no_result }, Import { "checkpoint", [], no_result },
    Import { "current", [], word }, Import { "resume", [word], no_result },
    Import { "transfer", [word], no_result },
];
fn ensure(module: blot_backend_wasm::Module&) -> blot_error::Error {
    for item in imports {
        let index, error = blot_backend_wasm::importFunction(module, "blot:task/1", item.name, item.parameters, item.result);
        if error != blot_error::Error.none { return error; }
    }
    return blot_error::Error.none;
}
