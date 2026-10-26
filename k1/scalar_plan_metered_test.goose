import work;
import scalar_core_metered;
import scalar_plan;
import scalar_plan_metered;
import scalar_wasm_metered;
import wasm;
import os;

fn main() {
    for op in 3 {
        for lkind in 2 {
            for rkind in 2 {
                if op == 0 && rkind != 0 { continue; }
                let result_type = if op == 2 { 2 } else { 1 };
                let lv: u32 = if lkind == 1 { 4294967295 } else { 0 };
                let rv: u32 = if rkind == 1 { 7 } else { 0 };
                var m = work::Meter {};
                var built = scalar_core_metered::make(result_type, op, lkind, lv, rkind, rv, m);
                assert(built.status == 0);
                built.core.name_start = 4; built.core.name_end = 5;
                built.core.parameter_start = 24; built.core.parameter_end = 25;
                built.core.left_start = 36; built.core.left_end = 37;
                if op != 0 { built.core.operator_start = 38; built.core.operator_end = 39; built.core.right_start = 40; built.core.right_end = 41; }
                let expected_plan = scalar_plan::make(built.core);
                let result = scalar_plan_metered::make(built.core, m);
                assert(result.status == 0 && result.plan.opcode == expected_plan.opcode && scalar_plan::validate(result.plan));
                var make_measure = work::Meter {};
                assert(scalar_plan_metered::make(built.core, make_measure).status == 0);
                let make_visits = make_measure.semantic;
                var make_exact = work::Meter { semantic: 1048576 - make_visits };
                assert(scalar_plan_metered::make(built.core, make_exact).status == 0 && make_exact.semantic == 1048576);
                var make_short = work::Meter { semantic: 1048577 - make_visits };
                let unmade = scalar_plan_metered::make(built.core, make_short);
                assert(unmade.status == 2 && unmade.plan.schema == 0 && make_short.semantic == 1048576);
                for available in make_visits {
                    var stopped_make = work::Meter { semantic: 1048576 - available };
                    let partial = scalar_plan_metered::make(built.core, stopped_make);
                    assert(partial.status == 2 && partial.plan.schema == 0 && stopped_make.semantic == 1048576);
                }
                assert(scalar_plan_metered::validate(result.plan, m, 6).status == 0);
                let original = wasm::emit_scalar_v2("f", expected_plan);
                let emitted = scalar_wasm_metered::emit("f", result.plan, m);
                assert(emitted.status == 0 && emitted.bytes[..] == original[..]);
                assert(m.phase_semantic[2] > 0 && m.phase_semantic[5] > 0 && m.phase_semantic[6] > 0);
                var bad = result.plan; bad.opcode = 42;
                var invalid = work::Meter {};
                assert(scalar_plan_metered::validate(bad, invalid, 6).status == 1);
                assert(scalar_wasm_metered::emit("f", bad, invalid).status == 1);
                assert(scalar_wasm_metered::emit("U32", result.plan, invalid).status == 1);
                var baseline = work::Meter {};
                let expected_emit = scalar_wasm_metered::emit("f", result.plan, baseline);
                assert(expected_emit.status == 0);
                let visits = baseline.semantic;
                var exact = work::Meter { semantic: 1048576 - visits };
                assert(scalar_wasm_metered::emit("f", result.plan, exact).status == 0 && exact.semantic == 1048576);
                var short = work::Meter { semantic: 1048577 - visits };
                let stopped = scalar_wasm_metered::emit("f", result.plan, short);
                assert(stopped.status == 2 && stopped.bytes.len == 0 && short.semantic == 1048576);
                for available in visits {
                    var stopped_emit = work::Meter { semantic: 1048576 - available };
                    let partial = scalar_wasm_metered::emit("f", result.plan, stopped_emit);
                    assert(partial.status == 2 && partial.bytes.len == 0 && stopped_emit.semantic == 1048576);
                }
                if op == 2 && lkind == 0 && rkind == 1 {
                    assert(write_file("metered_scalar.wasm", emitted.bytes));
                }
            }
        }
    }
    print("metered scalar plan and Wasm laws passed");
}
