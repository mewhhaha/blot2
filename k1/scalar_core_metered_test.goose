import work;
import scalar_core;
import scalar_core_metered;

fn spans(c: scalar_core::ScalarCore, op: i64) -> scalar_core::ScalarCore {
    var result = c;
    result.name_start = 4; result.name_end = 5;
    result.parameter_start = 24; result.parameter_end = 25;
    result.left_start = 36; result.left_end = 37;
    if op != 0 { result.operator_start = 38; result.operator_end = 39; result.right_start = 40; result.right_end = 41; }
    return result;
}
fn compare(c: scalar_core::ScalarCore) {
    let expected = scalar_core::validate_structure(c);
    var m = work::Meter {};
    let checked = scalar_core_metered::validate(c, m, 5);
    assert((checked.status == 0) == expected);
}
fn main() {
    // Every shape in the closed scalar subset matches the existing builder
    // and structural checker, including two distinct constant occurrences.
    for op in 3 {
        for lkind in 2 {
            for rkind in 2 {
                if op == 0 && rkind != 0 { continue; }
                let result_type = if op == 2 { 2 } else { 1 };
                let l: u32 = if lkind == 1 { 4294967295 } else { 0 };
                let rv: u32 = if rkind == 1 { 7 } else { 0 };
                var meter = work::Meter {};
                let built = scalar_core_metered::make(result_type, op, lkind, l, rkind, rv, meter);
                assert(built.status == 0 && meter.core_blocks == 1);
                let old = scalar_core::build(result_type, op, lkind, l, rkind, rv);
                assert(built.core.value_count == old.value_count && built.core.result_id == old.result_id);
                for i in 4 { assert(scalar_core::same_value(built.core.values[i], old.values[i])); }
                let core = spans(built.core, op);
                compare(core);
                var valid_meter = work::Meter {};
                assert(scalar_core_metered::validate(core, valid_meter, 5).status == 0);
                let visits = valid_meter.semantic;
                var exact = work::Meter { semantic: 1048576 - visits };
                assert(scalar_core_metered::validate(core, exact, 5).status == 0 && exact.semantic == 1048576);
                var short = work::Meter { semantic: 1048577 - visits };
                assert(scalar_core_metered::validate(core, short, 5).status == 2 && short.semantic == 1048576);
                var scratch = work::Meter {};
                let scratch_core = scalar_core_metered::make_scratch(result_type, op, lkind, l, rkind, rv, scratch, 2);
                assert(scratch_core.status == 0 && scratch.core_operations == 0 && scratch.core_blocks == 0 && scratch.semantic > 0);
                var wrong = core; wrong.terminator = 0; compare(wrong);
                wrong = core; wrong.value_count = 5; compare(wrong);
                wrong = core; wrong.result_id = 99; compare(wrong);
                wrong = core; wrong.values[0].literal = 1; compare(wrong);
                wrong = core; wrong.values[3].producer = 9; compare(wrong);
                if op != 0 {
                    wrong = core; wrong.values[core.result_id].left_id = core.result_id; compare(wrong);
                    wrong = core; wrong.values[core.result_id].type_id = 99; compare(wrong);
                    wrong = core; wrong.values[core.result_id].op_id = 3; compare(wrong);
                }
            }
        }
    }
    var blocks = work::Meter { core_blocks: 4096 };
    let blocked = scalar_core_metered::make(1, 0, 0, 0, 0, 0, blocks);
    assert(blocked.status == 3 && blocked.receipt.quantity == 6 && blocked.core.value_count == 0);
    var operations = work::Meter { core_operations: 65536 };
    let denied = scalar_core_metered::make(1, 0, 0, 0, 0, 0, operations);
    assert(denied.status == 3 && denied.receipt.quantity == 5 && denied.core.value_count == 0);
    var semantic = work::Meter { semantic: 1048576 };
    let limited = scalar_core_metered::make(1, 0, 0, 0, 0, 0, semantic);
    assert(limited.status == 2 && limited.core.value_count == 0);
    var invalid = work::Meter {};
    assert(scalar_core_metered::make(2, 0, 0, 0, 0, 0, invalid).status == 1 && invalid.semantic == 0);
    assert(scalar_core_metered::validate(scalar_core::ScalarCore {}, invalid, 3).status == 4);
    print("metered scalar Core laws passed");
}
