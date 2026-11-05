// Only two-parameter capture-free forwarding spines qualify as scalar adapters.
namespace blot_check_primitive_operator;
import support.option;
struct Operation { op: blot_check_core::Op, reverse: bool = false, dependencies: blot_check_core::BindingRef[8] = [default<blot_check_core::BindingRef>(); 8], dependency_count: i64 = 0 }
fn analyze(units: const blot_check_core::Module[:], target: blot_check_core::BindingRef) -> blot_support::Option<Operation> {
    return visit(units, target, blot_support::Option<blot_backend_runtime_ir::Scalar> { false, 0 , ..}, 8);
}
fn analyzeTyped(units: const blot_check_core::Module[:], target: blot_check_core::BindingRef, machine: blot_backend_runtime_ir::Scalar) -> blot_support::Option<Operation> {
    return visit(units, target, blot_support::Option<blot_backend_runtime_ir::Scalar> { true, machine , ..}, 8);
}
fn source(units: const blot_check_core::Module[:], target: blot_check_core::BindingRef) -> const blot_check_core::Module? {
    for &unit, index in units { var logical = unit.unit; if logical == 0 { logical = (index + 1) as u32; } if logical == target.unit { return unit; } } return null;
}
recursive fn visit(units: const blot_check_core::Module[:], target_: blot_check_core::BindingRef,
                   machine: blot_support::Option<blot_backend_runtime_ir::Scalar>, remaining: i64) -> blot_support::Option<Operation> {
    if remaining == 0 { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
    let target = normalize(units, target_, 8); if !target.present { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
    let owner = source(units, target.value); if !owner { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
    let body = owner.body(target.value.binding); if !body || !body.is_function || body.parameters.len != 2 { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
    let parameters = owner.bodyParameters(body); let root = owner.node(body.root);
    var args: blot_check_core::Id[2] = [0; 2]; var result = default<Operation>();
    if root.tag == blot_check_core::Tag.scalar && root.c == 0 && root.b != 0 { args = [root.a, root.b]; result = Operation { root.op , ..}; }
    else if root.tag == blot_check_core::Tag.call {
        let call = owner.call(body.root); if call.arguments.len != 2 { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
        var next = call.target; if next.unit == 0 { next.unit = target.value.unit; }
        let selected = visit(units, next, machine, remaining - 1); if !selected.present { return selected; } result = selected.value; args = [call.arguments[0], call.arguments[1]];
    } else if root.tag == blot_check_core::Tag.associated || (root.tag == blot_check_core::Tag.scalar && root.c != 0) {
        if !machine.present { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
        let selected = associated(owner, target.value.unit, machine.value, root); if !selected.present { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
        let next = visit(units, selected.value, machine, remaining - 1); if !next.present { return next; } result = next.value; args = [root.a, root.b];
    } else { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
    var reverse = false;
    if blot_backend_function_facts::local(owner, args[0], parameters[0].binding) && blot_backend_function_facts::local(owner, args[1], parameters[1].binding) { reverse = false; }
    else if blot_backend_function_facts::local(owner, args[0], parameters[1].binding) && blot_backend_function_facts::local(owner, args[1], parameters[0].binding) { reverse = true; }
    else { return blot_support::Option<Operation> { false, default<Operation>() , ..}; }
    result.reverse = result.reverse != reverse; result.dependencies[result.dependency_count] = target.value; result.dependency_count += 1;
    return blot_support::Option<Operation> { true, result , ..};
}
fn total(operation: Operation) -> bool { return operation.op != blot_check_core::Op.div && operation.op != blot_check_core::Op.rem && operation.op != blot_check_core::Op.convert_f32_u32; }
fn resolve(units: const blot_check_core::Module[:], target: blot_check_core::BindingRef) -> blot_support::Option<blot_check_core::BindingRef> { return normalize(units, target, 8); }
recursive fn normalize(units: const blot_check_core::Module[:], target_: blot_check_core::BindingRef, remaining: i64) -> blot_support::Option<blot_check_core::BindingRef> {
    if remaining == 0 { return blot_support::Option<blot_check_core::BindingRef> { false, default<blot_check_core::BindingRef>() , ..}; }
    let owner = source(units, target_); if !owner || target_.binding == 0 || target_.binding >= owner.bindings.len { return blot_support::Option<blot_check_core::BindingRef> { false, default<blot_check_core::BindingRef>() , ..}; }
    let binding = owner.binding(target_.binding); if binding.kind != blot_check_check::Kind.external { return blot_support::Option<blot_check_core::BindingRef> { true, target_ , ..}; }
    var next = binding.target; if next.unit == 0 { next.unit = target_.unit; } return normalize(units, next, remaining - 1);
}
fn associated(source: const blot_check_core::Module&, origin: u32, scalar: blot_backend_runtime_ir::Scalar,
               node: blot_check_core::Node) -> blot_support::Option<blot_check_core::BindingRef> {
    var decl: u32 = 0;
    if scalar == blot_backend_runtime_ir::SC_u32 { decl = blot_check_types::u32_type; }
    else if scalar == blot_backend_runtime_ir::SC_f32 { decl = blot_check_types::f32_type; }
    else if scalar == blot_backend_runtime_ir::SC_bool { decl = blot_check_types::boolean; }
    else { return blot_support::Option<blot_check_core::BindingRef> { false, default<blot_check_core::BindingRef>() , ..}; }
    for method in source.associated {
        if method.identity.unit != 0 || method.identity.decl != decl { continue; }
        if node.tag == blot_check_core::Tag.associated { if method.member != node.c { continue; } }
        else if method.operator != operator(node.op) { continue; }
        var target = method.target; if target.unit == 0 { target.unit = origin; }
        return blot_support::Option<blot_check_core::BindingRef> { true, target , ..};
    }
    return blot_support::Option<blot_check_core::BindingRef> { false, default<blot_check_core::BindingRef>() , ..};
}
fn operator(op: blot_check_core::Op) -> blot_check_types::Operator {
    match op {
        add => { return blot_check_types::Operator.add; }, sub => { return blot_check_types::Operator.sub; }, mul => { return blot_check_types::Operator.mul; }, div => { return blot_check_types::Operator.div; }, rem => { return blot_check_types::Operator.rem; },
        equal => { return blot_check_types::Operator.equal; }, not_equal => { return blot_check_types::Operator.not_equal; }, less => { return blot_check_types::Operator.less; }, less_equal => { return blot_check_types::Operator.less_equal; }, greater => { return blot_check_types::Operator.greater; }, greater_equal => { return blot_check_types::Operator.greater_equal; },
        bit_and => { return blot_check_types::Operator.bit_and; }, bit_or => { return blot_check_types::Operator.bit_or; }, bit_xor => { return blot_check_types::Operator.bit_xor; }, shift_left => { return blot_check_types::Operator.shift_left; }, shift_right => { return blot_check_types::Operator.shift_right; }, _ => { return blot_check_types::Operator.none; },
    }
}
