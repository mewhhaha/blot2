// Emits fixture modules in the current temporary test directory.
import std;
import os;
import scalar_core;
import scalar_plan;
import scalar_thin;

fn main() {
    for op in 0..3 {
        let result_type = if op == 2 { 2 } else { 1 };
        var core = scalar_core::build(result_type, op, 0, 0,
                                       if op == 0 { 0 } else { 1 },
                                       if op == 0 { 0 } else { 255 });
        core.name_start = 1; core.name_end = 2;
        core.parameter_start = 3; core.parameter_end = 4;
        core.left_start = 5; core.left_end = 6;
        if op != 0 { core.operator_start = 7; core.operator_end = 8; core.right_start = 9; core.right_end = 10; }
        let plan = scalar_plan::make(core);
        let bytes = scalar_thin::emit("f", plan);
        assert(bytes.len > 0 && write_file(str("thin_", op, ".wasm"), bytes));
        var forged = plan;
        forged.memory_maximum_pages = 276;
        assert(scalar_thin::emit("f", forged).len == 0);
        assert(scalar_thin::emit("return", plan).len == 0);
    }
}
