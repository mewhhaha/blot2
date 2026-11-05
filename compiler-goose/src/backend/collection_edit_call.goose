// Exact source wrappers preserve a collection primitive's consuming operand.
namespace blot_backend_collection_edit_call;
import check.core;
import check.types;
import .known_call;
import .collection_ops;
import support.option;
struct Plan { target: blot_check_core::BindingRef,forwarded_target: blot_support::Option<blot_check_core::BindingRef>,op: blot_backend_collection_ops::Op,positions: i64[3],count: i64,receiver: u32,edit: u32,success: blot_support::Option<u32>,arguments: u32[3] }
fn analyze(units: const blot_check_core::Module[:],owner: u32,id: u32) -> blot_support::Option<Plan> {
    let resolved = blot_backend_known_call::resolve(units,owner,id); if !resolved.present || resolved.value.count < 2 || resolved.value.count > 3 { return blot_support::none<Plan>(); } let call = resolved.value; var target = call.target; if target.unit == 0 { target.unit = owner; }
    var outer_target = blot_support::none<blot_check_core::BindingRef>(); var forwarded_target = blot_support::none<blot_check_core::BindingRef>(); var forwarded_positions: i64[3] = [0,1,2];
    for iteration in 0..16 {
        if target.unit == 0 || target.unit > units.len { return blot_support::none<Plan>(); } let source .= units[target.unit - 1]; if target.binding == 0 || target.binding >= source.bindings.len { return blot_support::none<Plan>(); } let binding = source.binding(target.binding);
        if binding.kind == blot_check_core::BindingKind.external { let previous = target.unit; target = binding.target; if target.unit == 0 { target.unit = previous; } continue; }
        let body .= source.body(target.binding); if body == null { return blot_support::none<Plan>(); }
        if source.types.node(binding.ty).tag == blot_check_types::Tag.function && body.parameters.len == 0 && source.node(body.root).tag == blot_check_core::Tag.reference { let previous = target.unit; target = source.reference(body.root); if target.unit == 0 { target.unit = previous; } continue; }
        if !body.is_function || body.parameters.len != call.count { return blot_support::none<Plan>(); } if !outer_target.present { outer_target = blot_support::some(target); }
        if source.node(body.root).tag == blot_check_core::Tag.call && !forwarded_target.present {
            let forwarded = blot_backend_known_call::resolve(units,target.unit,body.root); if !forwarded.present || forwarded.value.count != call.count { return blot_support::none<Plan>(); } var used: u8 = 0; var next_positions: i64[3] = [0,1,2];
            for argument,index in forwarded.value.arguments[..forwarded.value.count] { let position = blot_backend_known_call::parameterPosition(source,target.unit,source.bodyParameters(body),argument,used); if !position.present { return blot_support::none<Plan>(); } next_positions[index] = forwarded_positions[position.value]; }
            forwarded_positions = next_positions; forwarded_target = blot_support::some(target); let previous = target.unit; target = forwarded.value.target; if target.unit == 0 { target.unit = previous; } continue;
        }
        var edit = body.root; var condition: u32 = 0; var success = blot_support::none<u32>();
        if source.node(edit).tag == blot_check_core::Tag.block_ {
            if forwarded_target.present { return blot_support::none<Plan>(); } let statements = source.children(edit); if statements.len != 2 { return blot_support::none<Plan>(); } let branch = source.node(statements[0]); let fallback = source.node(statements[1]); if branch.tag != blot_check_core::Tag.if_stmt || branch.c != 0 || fallback.tag != blot_check_core::Tag.return_ { return blot_support::none<Plan>(); }
            let failure = source.node(fallback.a); if failure.tag != blot_check_core::Tag.construct || failure.b != 0 { return blot_support::none<Plan>(); } let selected = source.children(branch.b); if selected.len != 1 || source.node(selected[0]).tag != blot_check_core::Tag.return_ { return blot_support::none<Plan>(); } let returned = source.node(source.node(selected[0]).a); if returned.tag != blot_check_core::Tag.construct || returned.b == 0 || returned.c != 0 { return blot_support::none<Plan>(); } condition = branch.a; success = blot_support::some(returned.a); edit = returned.b;
        }
        if source.node(edit).tag != blot_check_core::Tag.array_op { return blot_support::none<Plan>(); } let op = source.arrayOperation(edit); if op != blot_backend_collection_ops::Op.set && op != blot_backend_collection_ops::Op.append && op != blot_backend_collection_ops::Op.prepend && op != blot_backend_collection_ops::Op.simd_store { return blot_support::none<Plan>(); }
        let operands = source.children(edit); let count = blot_backend_collection_ops::arity(op) as i64; if operands.len != count || call.count != count { return blot_support::none<Plan>(); } var positions: i64[3] = [0;3]; var used: u8 = 0;
        for operand,index in operands { if source.node(operand).tag != blot_check_core::Tag.reference { return blot_support::none<Plan>(); } let reference = source.reference(operand); if reference.unit != 0 && reference.unit != target.unit { return blot_support::none<Plan>(); } var found = false;
            for parameter,parameter_index in source.bodyParameters(body) { if parameter.binding != 0 && parameter.binding == reference.binding { positions[index] = forwarded_positions[parameter_index]; found = true; break; } } if !found { return blot_support::none<Plan>(); } let bit = (1 as u8) << positions[index] as u32; if (used & bit) != 0 { return blot_support::none<Plan>(); } used |= bit;
        }
        if condition != 0 && !borrowPredicate(units,target.unit,condition,source.bodyParameters(body)[positions[0]].binding,0) { return blot_support::none<Plan>(); } var forwarded = blot_support::none<blot_check_core::BindingRef>(); if forwarded_target.present { forwarded = blot_support::some(target); }
        return blot_support::some(Plan { target: outer_target.value,forwarded_target: forwarded,op,positions,count,receiver: call.arguments[positions[0]],edit,success,arguments: [call.arguments[0],call.arguments[1],call.arguments[2]] });
    } return blot_support::none<Plan>();
}
recursive fn borrowPredicate(units: const blot_check_core::Module[:],unit: u32,id: u32,receiver: u32,depth: i64) -> bool {
    if depth >= 32 { return false; } let module .= units[unit - 1]; let node = module.node(id);
    match node.tag {
        constant=>{ return true; },reference=>{ let reference = module.reference(id); let ty = module.types.node(node.ty).tag; return reference.unit == 0 && reference.binding != receiver && (ty == blot_check_types::Tag.unsigned32 || ty == blot_check_types::Tag.boolean || ty == blot_check_types::Tag.floating32); },
        scalar=>{ return borrowPredicate(units,unit,node.a,receiver,depth + 1) && (node.b == 0 || borrowPredicate(units,unit,node.b,receiver,depth + 1)); },
        array_op=>{ if module.arrayOperation(id) != blot_backend_collection_ops::Op.length { return false; } let input = module.node(module.children(id)[0]); if input.tag != blot_check_core::Tag.reference { return false; } let reference = module.references[input.a]; return reference.unit == 0 && reference.binding == receiver; },
        call=>{ let call = module.call(id); var scalars = true; for argument in call.arguments { if !borrowPredicate(units,unit,argument,receiver,depth + 1) { scalars = false; break; } } if scalars { return true; } if call.arguments.len != 1 { return false; } let input = module.node(call.arguments[0]); if input.tag != blot_check_core::Tag.reference { return false; } let reference = module.references[input.a]; if reference.unit != 0 || reference.binding != receiver { return false; } var target = call.target; if target.unit == 0 { target.unit = unit; }
            for iteration in 0..16 { let producer .= units[target.unit - 1]; let binding = producer.binding(target.binding); if binding.kind == blot_check_core::BindingKind.external { let previous = target.unit; target = binding.target; if target.unit == 0 { target.unit = previous; } continue; } let body .= producer.body(target.binding); if body == null || body.parameters.len != 1 { return false; } return borrowPredicate(units,target.unit,body.root,producer.bodyParameters(body)[0].binding,depth + 1); } return false;
        },_=>{ return false; },
    }
}
