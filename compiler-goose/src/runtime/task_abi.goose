// Legacy guest task adapters keep their original counted-root ABI.
namespace blot_runtime_task_abi;
import backend.runtime_ir;
import backend.wasm;
import support.error;

type ValueType = blot_backend_runtime_ir::ValueType;
struct Import { name: const u8[:], parameters: const ValueType[:], result: ValueType }
let word = blot_backend_runtime_ir::VT_i32;
let no_result = blot_backend_runtime_ir::VT_none;
let no_parameters:ValueType[0]=[];
let one_parameter:ValueType[1]=[word];
let two_parameters:ValueType[2]=[word,word];
let three_parameters:ValueType[3]=[word,word,word];
let imports = [
    Import { "open", no_parameters, word , ..}, Import { "close", one_parameter, no_result , ..},
    Import { "spawn", three_parameters, word , ..}, Import { "join", two_parameters, word , ..},
    Import { "collect", three_parameters, no_result , ..}, Import { "cancel", one_parameter, no_result , ..},
    Import { "poll", two_parameters, word , ..}, Import { "drop", two_parameters, no_result , ..},
    Import { "drain", no_parameters, no_result , ..}, Import { "checkpoint", no_parameters, no_result , ..},
    Import { "current", no_parameters, word , ..}, Import { "resume", one_parameter, no_result , ..},
    Import { "transfer", one_parameter, no_result , ..},
];
fn ensure(module: blot_backend_wasm::Module&) -> blot_error::Error {
    for item in imports {
        let index, error = blot_backend_wasm::importFunction(module, "blot:task/1", item.name, item.parameters, item.result);
        if error != blot_error::Error.none { return error; }
    }
    return blot_error::Error.none;
}
