import core;

fn main() {
    let identity = core::make_function(1, 0);
    let constant = core::make_function(2, 4294967295);
    assert(core::validate_interface(identity.interface) == 0);
    assert(core::validate_function(identity) == 0);
    assert(core::validate_function(constant) == 0);
    assert(core::validate_plan(core::make_plan(identity)) == 0);
    assert(core::validate_plan(core::make_plan(constant)) == 0);
    assert(core::validate_function(core::make_function(0, 0)) == 1);
    assert(core::validate_function(core::make_function(3, 0)) == 1);
    assert(core::validate_function(core::make_function(1, 1)) == 1);

    var i = core::CheckedInterface {};
    i.header.edition = 2; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.header.semantic_policy = 2; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.header.optimizer_policy = 2; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.header.abi = 2; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.header.schema = 2; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.parameter_type = 2; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.result_type = 2; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.parameter_count = 0; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.call_mode = 2; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.effects = 1; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.binders = 1; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.captures = 1; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.requires_count = 1; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.ensures_count = 1; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.depth = 0; assert(core::validate_interface(i) == 1); i = core::CheckedInterface {};
    i.frame_bytes = 1; assert(core::validate_interface(i) == 1);

    var f = identity;
    f.interface.parameter_type = 2; assert(core::validate_function(f) == 1); f = identity;
    f.block_count = 2; assert(core::validate_function(f) == 1); f = identity;
    f.entry_block = 2; assert(core::validate_function(f) == 1); f = identity;
    f.parameter_value = 2; assert(core::validate_function(f) == 1); f = identity;
    f.operation_kind = 3; assert(core::validate_function(f) == 1); f = identity;
    f.operation_result = 2; assert(core::validate_function(f) == 1); f = identity;
    f.return_value = 2; assert(core::validate_function(f) == 1); f = identity;
    f.terminator = 2; assert(core::validate_function(f) == 1); f = identity;
    f.literal = 1; assert(core::validate_function(f) == 1); f = identity;
    f.call_count = 1; assert(core::validate_function(f) == 1); f = identity;
    f.evidence_count = 1; assert(core::validate_function(f) == 1); f = identity;
    f.ownership_count = 1; assert(core::validate_function(f) == 1); f = identity;
    f.static_count = 1; assert(core::validate_function(f) == 1); f = constant;
    f.operation_result = 1; assert(core::validate_function(f) == 1); f = constant;
    f.return_value = 1; assert(core::validate_function(f) == 1);

    let base = core::make_plan(identity);
    var p = base;
    p.function.interface.depth = 0; assert(core::validate_plan(p) == 1); p = base;
    p.function.return_value = 2; assert(core::validate_plan(p) == 1); p = base;
    p.abi = 2; assert(core::validate_plan(p) == 1); p = base;
    p.optimization_policy = 2; assert(core::validate_plan(p) == 1); p = base;
    p.parameter_representation = 2; assert(core::validate_plan(p) == 1); p = base;
    p.result_representation = 2; assert(core::validate_plan(p) == 1); p = base;
    p.environment_parameter = 0; assert(core::validate_plan(p) == 1); p = base;
    p.result_slot = 1; assert(core::validate_plan(p) == 1); p = base;
    p.adapter_count = 1; assert(core::validate_plan(p) == 1); p = base;
    p.helper_count = 1; assert(core::validate_plan(p) == 1); p = base;
    p.backing_allocation = 1; assert(core::validate_plan(p) == 1); p = base;
    p.memory_grow = 1; assert(core::validate_plan(p) == 1); p = base;
    p.memory_initial_pages = 274; assert(core::validate_plan(p) == 1); p = base;
    p.memory_maximum_pages = 276; assert(core::validate_plan(p) == 1); p = base;
    p.depth = 2; assert(core::validate_plan(p) == 1); p = base;
    p.frame_bytes = 4; assert(core::validate_plan(p) == 1);
    print("scalar transient core: passed");
}
