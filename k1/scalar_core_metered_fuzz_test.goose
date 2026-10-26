import work;
import scalar_core;
import scalar_core_metered;

fn random(state: u32&) -> u32 {
    state ^= state << 13; state ^= state >> 17; state ^= state << 5;
    return state;
}
fn main() {
    var state: u32 = 0x9e3779b9;
    for round in 12000 {
        let op: i64 = random(state) % 3;
        let result_type: i64 = if op == 2 { 2 } else { 1 };
        let lkind: i64 = random(state) % 2;
        let rkind: i64 = if op == 0 { 0 } else { random(state) % 2 };
        let lv: u32 = if lkind == 0 { 0 } else { random(state) };
        let rv: u32 = if rkind == 0 { 0 } else { random(state) };
        var c = scalar_core::build(result_type, op, lkind, lv, rkind, rv);
        c.name_start = 4; c.name_end = 5; c.parameter_start = 24; c.parameter_end = 25;
        c.left_start = 36; c.left_end = 37;
        if op != 0 { c.operator_start = 38; c.operator_end = 39; c.right_start = 40; c.right_end = 41; }
        // Deterministically mutate structural tags, indices, origins or slots.
        let changes = random(state) % 4;
        for change in changes {
            let field = random(state) % 17;
            let value: i64 = (random(state) % 9) as i64 - 2;
            let index = (random(state) % 4) as i64;
            if field == 0 { c.value_count = value; }
            else if field == 1 { c.result_type = value; }
            else if field == 2 { c.result_id = value; }
            else if field == 3 { c.terminator = value; }
            else if field == 4 { c.name_start = value; }
            else if field == 5 { c.name_end = value; }
            else if field == 6 { c.parameter_start = value; }
            else if field == 7 { c.parameter_end = value; }
            else if field == 8 { c.left_start = value; }
            else if field == 9 { c.operator_start = value; }
            else if field == 10 { c.right_end = value; }
            else if field == 11 { c.values[index].producer = value; }
            else if field == 12 { c.values[index].type_id = value; }
            else if field == 13 { c.values[index].op_id = value; }
            else if field == 14 { c.values[index].left_id = value; }
            else if field == 15 { c.values[index].right_id = value; }
            else { c.values[index].literal = random(state); }
        }
        let expected = scalar_core::validate_structure(c);
        var meter = work::Meter {};
        let got = scalar_core_metered::validate(c, meter, 5);
        if (got.status == 0) != expected { print("Core structural mismatch at case ", round); abort("structural mismatch"); }
    }
    print("metered scalar Core differential laws passed");
}
