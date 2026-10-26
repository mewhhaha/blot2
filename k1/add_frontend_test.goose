import add_frontend;
import add_source;
import frontend;
import scalar_core;
import validate;
import catalog;

fn accepted(source: u8[:]) -> scalar_core::ScalarCore {
    let result = add_frontend::parse(source);
    assert(result.status == 0 && add_source::validate(source, result.core) == 0);
    assert(result.core.value_count == 3 && result.core.values[2].op_id == 3);
    // Op 3 cannot slip through the existing v2 structural/source checks.
    assert(!scalar_core::validate_structure(result.core));
    assert(validate::scalar_v2(source, result.core, catalog::edition(), catalog::semantic_policy(),
        catalog::optimization_policy(), catalog::wasm_abi()) != 0);
    return result.core;
}
fn rejected(source: u8[:], status: i64) {
    let result = add_frontend::parse(source);
    assert(result.status == status && result.core.value_count == 0);
}
fn main() {
    let source = "let f: U32 -> U32 = fn x => return x + 0";
    var core = accepted(source);
    let body = accepted("let f: U32 -> U32 = fn x => do:\n  return x + 0\n");
    let value_block = accepted("let f: U32 -> U32 = fn x => return do:\n  break x + 0\n");
    let nested = accepted("let f: U32 -> U32 = fn x => do:\n  return do:\n    return x + 00\n");
    assert(body.values[2].op_id == 3 && value_block.values[2].op_id == 3 && nested.values[2].op_id == 3);
    rejected("let f: U32 -> U32 = fn x => return x + 1", 10);
    rejected("let f: U32 -> U32 = fn x => return x + 4294967295", 10);
    rejected("let f: U32 -> U32 = fn x => return x + x", 10);
    rejected("let f: U32 -> U32 = fn x => return 0 + x", 10);
    rejected("let f: U32 -> U32 = fn x => return 0 + 0", 10);
    rejected("let f: U32 -> U32 = fn x => return y + 0", 3);
    rejected("let f: U32 -> U32 = fn x => return x + y", 3);
    rejected("let f: U32 -> Bool = fn x => return x + 0", 7);
    rejected("let f: U32 -> U32 = fn x => do:\n  break x + 0", 6);
    rejected("let f: U32 -> U32 = fn x => return x + 4294967296", 1);
    rejected("let f: U32 -> U32 = fn x => return x +", 1);
    rejected("let f: U32 -> U32 = fn x => return x + 0 + 1", 2);
    rejected("let f: U32 -> U32 = fn x => return x & 0", 2);
    rejected("let f: U32 -> U32 = fn x => return x + 0 & 1", 2);
    rejected("let f: U32 -> U32 = fn x => return x // + 0", 2);
    let prior = core;
    core.operator_start = -1; assert(add_source::validate(source, core) != 0); core = prior;
    core.operator_end = source.len + 1; assert(add_source::validate(source, core) != 0); core = prior;
    core.name_start = -1; assert(add_source::validate(source, core) != 0); core = prior;
    core.parameter_end += 1; assert(add_source::validate(source, core) != 0); core = prior;
    core.left_start += 1; assert(add_source::validate(source, core) != 0); core = prior;
    core.right_end -= 1; assert(add_source::validate(source, core) != 0); core = prior;
    core.values[0].type_id = 2; assert(add_source::validate(source, core) != 0); core = prior;
    core.values[1].literal = 1; assert(add_source::validate(source, core) != 0); core = prior;
    core.values[2].op_id = 1; assert(add_source::validate(source, core) != 0); core = prior;
    core.values[2].left_id = 1; assert(add_source::validate(source, core) != 0); core = prior;
    core.values[2].right_id = 0; assert(add_source::validate(source, core) != 0); core = prior;
    core.values[3].producer = 1; assert(add_source::validate(source, core) != 0); core = prior;
    assert(add_source::validate("let f: U32 -> U32 = fn x => return x + 1", core) != 0);
    assert(add_source::validate("let f: U32 -> U32 = fn x => return x & 0", core) != 0);
    assert(add_source::validate("let f: U32 -> U32 = fn y => return x + 0", core) != 0);
    print("checked-add source recognition: passed");
}
