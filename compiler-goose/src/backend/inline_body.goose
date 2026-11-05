// Ordinary and numeric adapters have separate bounded expansion budgets.
namespace blot_backend_inline_body;
import check.core;
import support.option;
fn admits(module: const blot_check_core::Module&,id: u32,expose_data: bool) -> bool { let size = cost(module,id); if !size.present { return false; } var limit: u16 = 4; if expose_data { limit = 64; } return size.value <= limit; }
fn cost(module: const blot_check_core::Module&,id: u32) -> blot_support::Option<u16> { return boundedCost(module,id,64); }
fn numericCost(module: const blot_check_core::Module&,id: u32) -> blot_support::Option<u16> { return boundedCost(module,id,128); }
fn boundedCost(module: const blot_check_core::Module&,id: u32,limit: i64) -> blot_support::Option<u16> { var budget = limit; if visit(module,id,budget) { return blot_support::some((limit - budget) as u16); } return blot_support::none<u16>(); }
recursive fn visit(module: const blot_check_core::Module&,id: u32,budget: i64&) -> bool {
    if id == 0 { return true; } if budget == 0 { return false; } budget--; let node = module.node(id);
    match node.tag {
        constant,reference,panic,constructor_function,primitive_function,break_=>{ return true; },
        scalar,associated,apply,logical=>{ return visit(module,node.a,budget) && visit(module,node.b,budget); },
        if_value,if_stmt=>{ return visit(module,node.a,budget) && visit(module,node.b,budget) && visit(module,node.c,budget); },
        project,return_=>{ return visit(module,node.a,budget); },construct,bind=>{ return visit(module,node.b,budget); },pattern_bind=>{ return visit(module,node.b,budget) && visit(module,node.c,budget); },
        match_=>{ for input in module.matchInputs(id) { if !visit(module,input,budget) { return false; } } for arm in module.matchArms(id) { if !visit(module,arm.guard,budget) || !visit(module,arm.body,budget) { return false; } } return true; },
        loop_=>{ let loop = module.loopInfo(id); return visit(module,loop.first,budget) && visit(module,loop.end,budget) && visit(module,loop.body,budget); },
        product,record,array,array_op,block_,suite=>{ for child in module.children(id) { if !visit(module,child,budget) { return false; } } return true; },
        call=>{ for child in module.call(id).arguments { if !visit(module,child,budget) { return false; } } return true; },closure=>{ return visit(module,module.closures[node.a].body,budget); },_=>{ return false; },
    }
}
