// Rectangular finite append regions retain written evaluation order.
namespace blot_backend_exact_builder;
import check.core;
import check.types;
import .collection_ops;
import .function_facts;
import support.option;
struct Plan { initial: u32,append: u32 = 0,value: u32 = 0,conversion: u32 = 0,loops: u32[4],loop_count: i64 = 0,aliases: u32[16],alias_count: i64 = 0 }
fn add(plan: Plan&,binding: u32) -> bool { if plan.alias_count == 16 { return false; } plan.aliases[plan.alias_count] = binding; plan.alias_count++; return true; }
fn alias(plan: const Plan&,binding: u32) -> bool { for value in plan.aliases[..plan.alias_count] { if binding == value { return true; } } return false; }
recursive fn region(plan: Plan&,module: const blot_check_core::Module&,id: u32,incoming: u32) -> blot_support::Option<u32> {
    if module.node(id).tag != blot_check_core::Tag.loop_ || plan.loop_count == 4 { return blot_support::none<u32>(); } let loop = module.loopInfo(id); if loop.kind == blot_check_core::LoopKind.forever || loop.can_exit { return blot_support::none<u32>(); } let carries = module.loopCarries(id); if carries.len != 1 || carries[0].incoming != incoming { return blot_support::none<u32>(); } let carry = carries[0];
    if !plan.add(carry.iteration) || !plan.add(carry.backedge) || !plan.add(carry.outgoing) { return blot_support::none<u32>(); } plan.loops[plan.loop_count] = id; plan.loop_count++; let children = module.children(loop.body); if children.len != 1 { return blot_support::none<u32>(); } let node = module.node(children[0]);
    if node.tag == blot_check_core::Tag.loop_ { let nested = region(plan,module,children[0],carry.iteration); if !nested.present || nested.value != carry.backedge { return blot_support::none<u32>(); } }
    else {
        if node.tag != blot_check_core::Tag.bind || node.a != carry.backedge { return blot_support::none<u32>(); }
        if module.node(node.b).tag == blot_check_core::Tag.array_op && module.arrayOperation(node.b) == blot_backend_collection_ops::Op.append { if !blot_backend_function_facts::local(module,module.children(node.b)[0],carry.iteration) { return blot_support::none<u32>(); } plan.append = node.b; plan.value = module.children(node.b)[1]; }
        else {
            if module.node(node.b).tag != blot_check_core::Tag.block_ { return blot_support::none<u32>(); } let steps = module.children(node.b); if steps.len != 3 { return blot_support::none<u32>(); } let receiver = module.node(steps[0]); let value = module.node(steps[1]); let returned = module.node(steps[2]);
            if receiver.tag != blot_check_core::Tag.bind || value.tag != blot_check_core::Tag.bind || returned.tag != blot_check_core::Tag.return_ || returned.b != node.b { return blot_support::none<u32>(); } if !blot_backend_function_facts::local(module,receiver.b,carry.iteration) || !plan.add(receiver.a) { return blot_support::none<u32>(); }
            if module.node(returned.a).tag != blot_check_core::Tag.array_op || module.arrayOperation(returned.a) != blot_backend_collection_ops::Op.append { return blot_support::none<u32>(); } let operands = module.children(returned.a); if !blot_backend_function_facts::local(module,operands[0],receiver.a) || !blot_backend_function_facts::local(module,operands[1],value.a) { return blot_support::none<u32>(); } plan.append = returned.a; plan.value = value.b;
        }
    } return blot_support::some(carry.outgoing);
}
recursive fn patternContains(module: const blot_check_core::Module&,id: u32,binding: u32,depth: i64) -> bool {
    if id == 0 { return false; } if depth > 32 { return true; } let pattern = module.pattern(id); match pattern.tag { bind=>{ return pattern.a == binding; },product=>{ for child in module.extra[pattern.a..pattern.a + pattern.b] { if patternContains(module,child,binding,depth + 1) { return true; } } return false; },constructor,record_payload=>{ return patternContains(module,pattern.b,binding,depth + 1); },wildcard,constant=>{ return false; },_=>{ return true; }, }
}
recursive fn bound(plan: const Plan&,module: const blot_check_core::Module&,id: u32,budget: i64&) -> bool {
    if id == 0 { return true; } if budget == 0 { return false; } budget--; let node = module.node(id); match node.tag {
        constant=>{ return true; },reference=>{ let reference = module.reference(id); if reference.unit != 0 && reference.unit != module.unit { return false; } let kind = module.binding(reference.binding).kind; if (kind != blot_check_core::BindingKind.local && kind != blot_check_core::BindingKind.parameter) || plan.alias(reference.binding) { return false; } for loop in plan.loops[..plan.loop_count] { if patternContains(module,module.loopInfo(loop).pattern,reference.binding,0) { return false; } } return true; },
        scalar=>{ return node.c == 0 && bound(plan,module,node.a,budget) && bound(plan,module,node.b,budget); },_=>{ return false; },
    }
}
recursive fn independent(plan: const Plan&,module: const blot_check_core::Module&,id: u32,budget: i64&) -> bool {
    if id == 0 { return true; } if budget == 0 { return false; } budget--; let node = module.node(id); match node.tag {
        constant,panic=>{ return true; },reference=>{ let reference = module.reference(id); return (reference.unit != 0 && reference.unit != module.unit) || !plan.alias(reference.binding); },
        scalar,associated,apply,logical=>{ return independent(plan,module,node.a,budget) && independent(plan,module,node.b,budget); },project=>{ return independent(plan,module,node.a,budget); },construct=>{ return independent(plan,module,node.b,budget); },if_value=>{ return independent(plan,module,node.a,budget) && independent(plan,module,node.b,budget) && independent(plan,module,node.c,budget); },
        array,array_op,product,record=>{ for child in module.children(id) { if !independent(plan,module,child,budget) { return false; } } return true; },call=>{ for argument in module.call(id).arguments { if !independent(plan,module,argument,budget) { return false; } } return true; },_=>{ return false; },
    }
}
fn analyze(module: const blot_check_core::Module&,id: u32) -> blot_support::Option<Plan> {
    if module.node(id).tag != blot_check_core::Tag.block_ { return blot_support::none<Plan>(); } let statements = module.children(id); if statements.len != 3 { return blot_support::none<Plan>(); } let initial = module.node(statements[0]); let returned = module.node(statements[2]); if initial.tag != blot_check_core::Tag.bind || returned.tag != blot_check_core::Tag.return_ || returned.b != id { return blot_support::none<Plan>(); }
    if module.node(initial.b).tag != blot_check_core::Tag.array || module.children(initial.b).len != 0 || module.types.node(module.typeOf(initial.b)).tag != blot_check_types::Tag.list { return blot_support::none<Plan>(); } var plan = Plan { initial: initial.b , ..}; if !plan.add(initial.a) { return blot_support::none<Plan>(); } let outgoing = region(plan,module,statements[1],initial.a); if !outgoing.present { return blot_support::none<Plan>(); } var result = returned.a;
    if module.node(result).tag == blot_check_core::Tag.array_op && module.arrayOperation(result) == blot_backend_collection_ops::Op.convert { plan.conversion = result; result = module.children(result)[0]; } if !blot_backend_function_facts::local(module,result,outgoing.value) { return blot_support::none<Plan>(); }
    for loop_id in plan.loops[..plan.loop_count] { let loop = module.loopInfo(loop_id); var budget: i64 = 128; if !bound(plan,module,loop.first,budget) || !bound(plan,module,loop.end,budget) { return blot_support::none<Plan>(); } budget = 128; if !blot_backend_function_facts::behavior(module,loop.first,budget).movable() || !blot_backend_function_facts::behavior(module,loop.end,budget).movable() { return blot_support::none<Plan>(); } }
    var budget: i64 = 128; if !independent(plan,module,plan.value,budget) { return blot_support::none<Plan>(); } return blot_support::some(plan);
}
