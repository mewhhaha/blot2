// Compile-owned facts guide generation without authorizing semantic reuse.
namespace blot_backend_function_facts;
import dictionary;
import check.core;
import check.types;
import eval.region_arena;
import .collection_ops;
import .inline_body;
import support.error;
import support.option;
let small_limit: i64 = 8;
struct Behavior { unknown: bool = false,effects: bool = false,traps: bool = false,diverges: bool = false,allocates: bool = false }
fn movable(value: Behavior) -> bool { return !value.unknown && !value.effects && !value.traps && !value.diverges && !value.allocates; }
fn merge(destination: Behavior&,source: Behavior) { destination.unknown = destination.unknown || source.unknown; destination.effects = destination.effects || source.effects; destination.traps = destination.traps || source.traps; destination.diverges = destination.diverges || source.diverges; destination.allocates = destination.allocates || source.allocates; }
enum Length { unknown,constant { value: u32 },parameter { value: u8 } }
struct Facts { inline_cost: blot_support::Option<u16>,behavior: Behavior = Behavior { unknown: true , ..},length: Length = Length.unknown,borrowed_collections: u16 = 0 }
struct Stats {
    requested: i64 = 0,reused: i64 = 0,analyzed: i64 = 0,small_collections: i64 = 0,exact_builders: i64 = 0,layout_requests: i64 = 0,layout_reused: i64 = 0,region_requests: i64 = 0,evidence_import_requests: i64 = 0,evidence_import_reused: i64 = 0,closed_source_imports: i64 = 0,closed_source_reused: i64 = 0,split_attempts: i64 = 0,split_accepted: i64 = 0,split_declined: i64 = 0,region_reused: i64 = 0,region_retained_bytes: i64 = 0,region_arena: blot_eval_region_arena::Stats,
}
struct Store { entries: dictionary<blot_check_core::BindingRef,Facts>&,stats: Stats }
fn deinit(store: Store&) { store.entries.clear(); store.stats = Stats {..}; }
fn get(store: Store&,units: const blot_check_core::Module[:],target: blot_check_core::BindingRef) -> Facts,blot_error::Error {
    store.stats.requested++; { let known .= store.entries.get(target); if known != null { store.stats.reused++; return known,blot_error::Error.none; } }
    let module .= units[target.unit - 1]; let body .= module.body(target.binding); if body == null { return Facts {..},blot_error::Error.none; } let size = blot_backend_inline_body::cost(module,body.root); var facts = Facts { inline_cost: size , ..};
    if size.present { var budget: i64 = 256; facts.behavior = behavior(module,body.root,budget); let parameters = module.bodyParameters(body); let node = module.node(body.root);
        if node.tag == blot_check_core::Tag.array { facts.length = Length.constant { module.children(body.root).len as u32 , ..}; }
        if node.tag == blot_check_core::Tag.reference { for parameter,index in parameters { if index < 16 && local(module,body.root,parameter.binding) { facts.length = Length.parameter { index as u8 , ..}; } } }
        for parameter,index in parameters { if index >= 16 { break; } let ty = module.types.node(parameter.ty).tag; if ty != blot_check_types::Tag.array && ty != blot_check_types::Tag.list { continue; } if privateBinding(module,body.root,parameter.binding) { facts.borrowed_collections |= (1 as u16) << index as u32; } }
    }
    store.entries.insert(target,facts); store.stats.analyzed++; return facts,blot_error::Error.none;
}
fn local(module: const blot_check_core::Module&,id: u32,binding: u32) -> bool { if module.node(id).tag != blot_check_core::Tag.reference { return false; } let reference = module.reference(id); return (reference.unit == 0 || reference.unit == module.unit) && reference.binding == binding; }
recursive fn borrowed(module: const blot_check_core::Module&,id: u32,binding: u32,allow: bool,budget: i64&) -> bool {
    if id == 0 { return true; } if budget == 0 { return false; } budget--; let node = module.node(id);
    match node.tag {
        reference=>{ return allow || !local(module,id,binding); },constant,panic,primitive_function,constructor_function=>{ return true; },
        scalar,logical,associated,apply=>{ return borrowed(module,node.a,binding,false,budget) && borrowed(module,node.b,binding,false,budget); },project,return_=>{ return borrowed(module,node.a,binding,false,budget); },bind,construct=>{ return borrowed(module,node.b,binding,false,budget); },
        pattern_bind=>{ return borrowed(module,node.b,binding,false,budget) && borrowed(module,node.c,binding,false,budget); },if_value,if_stmt=>{ return borrowed(module,node.a,binding,false,budget) && borrowed(module,node.b,binding,false,budget) && borrowed(module,node.c,binding,false,budget); },
        loop_=>{ let loop_ = module.loopInfo(id); for carry in module.loopCarries(id) { if carry.incoming == binding { return false; } } return borrowed(module,loop_.first,binding,loop_.kind == blot_check_core::LoopKind.array,budget) && borrowed(module,loop_.end,binding,false,budget) && borrowed(module,loop_.body,binding,false,budget); },
        array_op=>{ let length = module.arrayOperation(id) == blot_backend_collection_ops::Op.length; for child in module.children(id) { if !borrowed(module,child,binding,length,budget) { return false; } } return true; },
        block_,suite,array,product,record=>{ for child in module.children(id) { if !borrowed(module,child,binding,false,budget) { return false; } } return true; },
        call=>{ for child in module.call(id).arguments { if !borrowed(module,child,binding,false,budget) { return false; } } return true; },_=>{ return false; },
    }
}
fn privateBinding(module: const blot_check_core::Module&,suite: u32,binding: u32) -> bool { for merge in module.merges { if merge.then_binding == binding || merge.else_binding == binding { return false; } } for carry in module.loop_carries { if carry.incoming == binding || carry.iteration == binding || carry.backedge == binding || carry.outgoing == binding { return false; } } var budget: i64 = 256; return borrowed(module,suite,binding,false,budget); }
recursive fn behavior(module: const blot_check_core::Module&,id: u32,budget: i64&) -> Behavior {
    if id == 0 { return Behavior {..}; } if budget == 0 { return Behavior { unknown: true , ..}; } budget--; let node = module.node(id); var result = Behavior {..};
    match node.tag {
        constant,reference=>{},scalar=>{ result = behavior(module,node.a,budget); result.merge(behavior(module,node.b,budget)); if node.c != 0 { result.unknown = true; } if (node.op == blot_check_core::Op.div || node.op == blot_check_core::Op.rem) && module.types.node(module.typeOf(node.a)).tag != blot_check_types::Tag.floating32 { result.traps = true; } },
        logical=>{ result = behavior(module,node.a,budget); result.merge(behavior(module,node.b,budget)); },if_value,if_stmt=>{ result = behavior(module,node.a,budget); result.merge(behavior(module,node.b,budget)); result.merge(behavior(module,node.c,budget)); },return_=>{ result = behavior(module,node.a,budget); },bind=>{ result = behavior(module,node.b,budget); },
        array,product,record,array_op,block_,suite=>{ for child in module.children(id) { result.merge(behavior(module,child,budget)); } if node.tag == blot_check_core::Tag.array || node.tag == blot_check_core::Tag.product || node.tag == blot_check_core::Tag.record { result.allocates = true; }
            if node.tag == blot_check_core::Tag.array_op { match module.arrayOperation(id) { length,identity,cursor_has=>{},get,cursor_value=>{ result.traps = true; },generate=>{ result = Behavior { unknown: true, traps: true, allocates: true, .. }; },_=>{ result.allocates = true; result.traps = true; }, } }
        },
        loop_=>{ let loop_ = module.loopInfo(id); result = behavior(module,loop_.first,budget); result.merge(behavior(module,loop_.end,budget)); result.merge(behavior(module,loop_.body,budget)); result.diverges = result.diverges || loop_.kind == blot_check_core::LoopKind.forever; },
        panic=>{ result.traps = true; },closure,constructor_function,primitive_function=>{ result.allocates = true; },construct=>{ result = behavior(module,node.b,budget); result.allocates = true; },
        effect_scope,operation_value,effect_provider,state_provider,handle,request_loop,request_decision,resolver_op=>{ result = Behavior { unknown: true,effects: true , ..}; },_=>{ result.unknown = true; },
    } return result;
}
