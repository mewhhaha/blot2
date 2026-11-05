namespace blot_backend_known_call;
import check.core;
import check.types;
import support.option;

struct Call { target: blot_check_core::BindingRef, arguments: blot_check_core::Id[16] = [0; 16], count: i64 = 0, signature: blot_check_types::Id = 0 }
struct Wrapper { target: blot_check_core::BindingRef, body: blot_check_core::Body }
fn resolve(units: const blot_check_core::Module[:], unit: u32, id: blot_check_core::Id) -> blot_support::Option<Call> {
    let source .= units[unit - 1];
    if source.node(id).tag == blot_check_core::Tag.call {
        let call = source.call(id); if call.arguments.len > 16 { return blot_support::none<Call>(); }
        var result = Call { target: call.target, count: call.arguments.len, signature: call.callee_type , ..};
        for argument, index in call.arguments { result.arguments[index] = argument; } return blot_support::some(result);
    }
    var result = Call {..}; var reverse: blot_check_core::Id[16] = [0; 16]; var root = id;
    while source.node(root).tag == blot_check_core::Tag.apply {
        if result.count == 16 { return blot_support::none<Call>(); }
        reverse[result.count] = source.node(root).b; result.count++; root = source.node(root).a;
    }
    let node = source.node(root);
    if node.tag == blot_check_core::Tag.reference {
        let reference = source.reference(root);
        if reference.unit == 0 && source.binding(reference.binding).kind != blot_check_core::BindingKind.global && source.binding(reference.binding).kind != blot_check_core::BindingKind.external { return blot_support::none<Call>(); }
        result.target = reference; result.signature = node.ty;
    } else if node.tag == blot_check_core::Tag.project {
        if result.count == 16 || source.projectionVariants(node.b).len != 0 { return blot_support::none<Call>(); }
        let ty = source.types.node(source.typeOf(node.a));
        if ty.tag != blot_check_types::Tag.array && ty.tag != blot_check_types::Tag.list && ty.tag != blot_check_types::Tag.cursor { return blot_support::none<Call>(); }
        var subtraction: u32 = 0; if ty.tag == blot_check_types::Tag.cursor { subtraction = 2; } else if ty.tag == blot_check_types::Tag.list { subtraction = 1; }
        let identity = blot_check_types::NominalIdentity { unit: 0, decl: 4294967295 - subtraction , ..}; let projection = source.projection(node.b); var found = false;
        for method in source.associated { if method.member == projection.field && method.identity == identity { result.target = method.target; found = true; break; } }
        if !found { return blot_support::none<Call>(); }
        result.signature = source.dispatchSignature(root); reverse[result.count] = node.a; result.count++;
    } else { return blot_support::none<Call>(); }
    for index in 0..result.count { result.arguments[index] = reverse[result.count - index - 1]; }
    return blot_support::some(result);
}
fn wrapper(units: const blot_check_core::Module[:], owner: u32, call: Call) -> blot_support::Option<Wrapper> {
    var target = call.target; if target.unit == 0 { target.unit = owner; }
    for index in 0..16 {
        if target.unit == 0 || target.unit > units.len { return blot_support::none<Wrapper>(); }
        let source .= units[target.unit - 1]; if target.binding == 0 || target.binding >= source.bindings.len { return blot_support::none<Wrapper>(); }
        let binding = source.binding(target.binding);
        if binding.kind == blot_check_core::BindingKind.external { let previous = target.unit; target = binding.target; if target.unit == 0 { target.unit = previous; } continue; }
        let body .= source.body(target.binding); if body == null { return blot_support::none<Wrapper>(); }
        if source.types.node(binding.ty).tag == blot_check_types::Tag.function && body.parameters.len == 0 && source.node(body.root).tag == blot_check_core::Tag.reference {
            let previous = target.unit; target = source.reference(body.root); if target.unit == 0 { target.unit = previous; } continue;
        }
        if !body.is_function || body.parameters.len != call.count { return blot_support::none<Wrapper>(); }
        return blot_support::some(Wrapper { target: target, body: body , ..});
    }
    return blot_support::none<Wrapper>();
}
fn parameterPosition(source: const blot_check_core::Module&, unit: u32, parameters: const blot_check_core::Parameter[:], operand: blot_check_core::Id, used: u8&) -> blot_support::Option<i64> {
    if source.node(operand).tag != blot_check_core::Tag.reference { return blot_support::none<i64>(); }
    let reference = source.reference(operand); if reference.unit != 0 && reference.unit != unit { return blot_support::none<i64>(); }
    for parameter, index in parameters {
        if parameter.binding == 0 || parameter.binding != reference.binding { continue; }
        let bit = 1 as u8 << index; if (used & bit) != 0 { return blot_support::none<i64>(); } used |= bit; return blot_support::some(index);
    }
    return blot_support::none<i64>();
}
