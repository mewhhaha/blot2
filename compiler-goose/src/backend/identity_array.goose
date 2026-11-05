// Identity generation shares immutable storage under the same ownership proof.
namespace blot_backend_identity_array;
import check.core;
import check.types;
import .known_call;
import support.option;
type Module = blot_check_core::Module;
type ArrayOp = blot_check_core::ArrayOp;
struct Plan { source: u32 = 0,binding: u32 = 0,dependencies: blot_check_core::BindingRef[12] = [blot_check_core::BindingRef {..};12],dependency_count: i64 = 0 }
struct Operands { values: u32[3] = [0;3],count: i64 = 0 }
recursive fn primitive(units: const Module[:],unit: u32,id: u32,op: ArrayOp,plan: Plan&,depth: i64) -> blot_support::Option<Operands> {
    if depth == 4 { return blot_support::none<Operands>(); } let source .= units[unit - 1];
    if source.node(id).tag == blot_check_core::Tag.array_op { if source.arrayOperation(id) != op { return blot_support::none<Operands>(); } let children = source.children(id); if children.len > 3 { return blot_support::none<Operands>(); } var result = Operands { count: children.len , ..}; for child,index in children { result.values[index] = child; } return blot_support::some(result); }
    let call = blot_backend_known_call::resolve(units,unit,id); if !call.present { return blot_support::none<Operands>(); } let wrapper = blot_backend_known_call::wrapper(units,unit,call.value); if !wrapper.present || plan.dependency_count == 12 || call.value.count > 3 { return blot_support::none<Operands>(); } plan.dependencies[plan.dependency_count] = wrapper.value.target; plan.dependency_count++;
    let inner = primitive(units,wrapper.value.target.unit,wrapper.value.body.root,op,plan,depth + 1); if !inner.present || inner.value.count != call.value.count { return blot_support::none<Operands>(); } let producer .= units[wrapper.value.target.unit - 1]; var result = Operands { count: inner.value.count , ..}; var used: u8 = 0;
    for operand,index in inner.value.values[..inner.value.count] { let position = blot_backend_known_call::parameterPosition(producer,wrapper.value.target.unit,producer.bodyParameters(wrapper.value.body),operand,used); if !position.present { return blot_support::none<Operands>(); } result.values[index] = call.value.arguments[position.value]; } return blot_support::some(result);
}
fn binding(source: const Module&,id: u32) -> blot_support::Option<u32> {
    if source.node(id).tag != blot_check_core::Tag.reference { return blot_support::none<u32>(); } let reference = source.reference(id); if reference.unit != 0 || reference.binding == 0 { return blot_support::none<u32>(); } let kind = source.binding(reference.binding).kind;
    if kind != blot_check_core::BindingKind.local && kind != blot_check_core::BindingKind.parameter { return blot_support::none<u32>(); } return blot_support::some(reference.binding);
}
fn analyze(units: const Module[:],unit: u32,id: u32) -> blot_support::Option<Plan> {
    let source .= units[unit - 1]; let node = source.node(id); if node.tag != blot_check_core::Tag.array_op && node.tag != blot_check_core::Tag.call && node.tag != blot_check_core::Tag.apply { return blot_support::none<Plan>(); } if source.types.node(node.ty).tag != blot_check_types::Tag.array { return blot_support::none<Plan>(); } var plan = Plan {..};
    let generate = primitive(units,unit,id,ArrayOp.generate,plan,0); if !generate.present || generate.value.count != 2 || source.node(generate.value.values[1]).tag != blot_check_core::Tag.closure { return blot_support::none<Plan>(); } let length = primitive(units,unit,generate.value.values[0],ArrayOp.length,plan,0); if !length.present || length.value.count != 1 || source.types.node(source.typeOf(length.value.values[0])).tag != blot_check_types::Tag.array { return blot_support::none<Plan>(); }
    plan.source = length.value.values[0]; let input = binding(source,plan.source); if !input.present { return blot_support::none<Plan>(); } plan.binding = input.value; let closure = source.closure(generate.value.values[1]); if closure.parameter.binding == 0 { return blot_support::none<Plan>(); } let get = primitive(units,unit,closure.body,ArrayOp.get,plan,0); if !get.present || get.value.count != 2 { return blot_support::none<Plan>(); } let collection = binding(source,get.value.values[0]); let index = binding(source,get.value.values[1]); if !collection.present || collection.value != plan.binding || !index.present || index.value != closure.parameter.binding { return blot_support::none<Plan>(); } return blot_support::some(plan);
}
