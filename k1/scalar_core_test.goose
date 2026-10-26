import scalar_core;

fn spans(c: scalar_core::ScalarCore, binary: bool) -> scalar_core::ScalarCore {
    var x = c;
    x.name_start = 4; x.name_end = 6;
    x.parameter_start = 24; x.parameter_end = 25;
    x.left_start = 36; x.left_end = 37;
    if binary {
        x.operator_start = 38; x.operator_end = 39;
        x.right_start = 40; x.right_end = 41;
    }
    return x;
}

fn main() {
    let id = spans(scalar_core::build(1, 0, 0, 0, 0, 0), false);
    let literal = spans(scalar_core::build(1, 0, 1, 4294967295, 0, 0), false);
    let bits = spans(scalar_core::build(1, 1, 1, 23, 1, 23), true);
    let less = spans(scalar_core::build(2, 2, 0, 0, 1, 4294967295), true);
    assert(scalar_core::validate_structure(id));
    assert(scalar_core::validate_structure(literal));
    assert(scalar_core::validate_structure(bits));
    assert(scalar_core::validate_structure(less));
    assert(id.value_count == 1 && id.result_id == 0);
    assert(literal.value_count == 2 && literal.result_id == 1);
    assert(bits.value_count == 4 && bits.result_id == 3 &&
           bits.values[3].left_id == 1 && bits.values[3].right_id == 2);
    assert(less.value_count == 3 && less.values[2].left_id == 0 && less.values[2].right_id == 1);
    assert(scalar_core::build(2, 1, 0, 0, 0, 0).value_count == 0);
    assert(scalar_core::build(1, 2, 0, 0, 0, 0).value_count == 0);
    assert(scalar_core::build(2, 0, 0, 0, 0, 0).value_count == 0);
    assert(scalar_core::build(1, 3, 0, 0, 0, 0).value_count == 0);
    assert(scalar_core::build(1, 1, 0, 1, 0, 0).value_count == 0);
    assert(scalar_core::build(1, 0, 0, 0, 1, 0).value_count == 0);

    var x = bits;
    x.value_count = 5; assert(!scalar_core::validate_structure(x)); x = bits;
    x.result_id = 4; assert(!scalar_core::validate_structure(x)); x = bits;
    x.result_type = 2; assert(!scalar_core::validate_structure(x)); x = bits;
    x.terminator = 2; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[0].producer = 2; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[0].type_id = 2; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[0].literal = 1; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[1].op_id = 1; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[1].left_id = 1; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[3].op_id = 2; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[3].type_id = 2; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[3].literal = 1; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[3].left_id = 3; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[3].right_id = -1; assert(!scalar_core::validate_structure(x)); x = bits;
    x.values[3].right_id = 1; assert(!scalar_core::validate_structure(x)); x = bits;
    x.operator_end = x.operator_start; assert(!scalar_core::validate_structure(x)); x = bits;
    x.right_end = x.right_start; assert(!scalar_core::validate_structure(x)); x = id;
    x.values[3].literal = 1; assert(!scalar_core::validate_structure(x)); x = id;
    x.operator_start = 1; assert(!scalar_core::validate_structure(x)); x = id;
    x.right_start = 1; assert(!scalar_core::validate_structure(x)); x = id;
    x.name_start = -1; assert(!scalar_core::validate_structure(x)); x = id;
    x.parameter_end = x.parameter_start; assert(!scalar_core::validate_structure(x));
    print("typed scalar Core: passed");
}
