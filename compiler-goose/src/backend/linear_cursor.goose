// One advance consumes the loop version and supplies its sole backedge.
namespace blot_backend_linear_cursor;
import check.core;
import .unit_index;
import .private_cursor;
import support.option;
type Module = blot_check_core::Module;
type Uses = blot_backend_unit_index::Uses;
struct Plan { advance: u32,loop_: u32 }
fn own(source: const Module&,reference: blot_check_core::BindingRef) -> bool { reference.unit == 0 || reference.unit == source.unit }
fn alias(source: const Module&,uses: const Uses&,start: u32,target: u32) -> bool {
    var binding = start; for ignored in 0..64 { if binding == target { return true; } let definitions = uses.definitions.get(binding); if definitions.len != 1 { return false; } let input = source.node(definitions[0]).b; if source.node(input).tag != blot_check_core::Tag.reference { return false; } let reference = source.reference(input); if !own(source,reference) { return false; } binding = reference.binding; } return false;
}
struct Search { source: const Module&,target: u32,count: i64 = 0,budget: i64 = 4096 }
recursive fn pattern(search: Search&,id: u32,depth: i64) -> bool {
    if id == 0 { return true; } if depth == 128 || search.budget == 0 { return false; } search.budget--; let value = search.source.pattern(id);
    match value.tag { wildcard,constant,bind=>{ return true; },value=>{ return visit(search,value.a,depth + 1); },constructor,record_payload=>{ return pattern(search,value.b,depth + 1); },product=>{ for child in search.source.patternChildren(id) { if !pattern(search,child,depth + 1) { return false; } } return true; },invalid=>{ return false; }, }
}
recursive fn visit(search: Search&,id: u32,depth: i64) -> bool {
    if id == 0 { return true; } if depth == 128 || search.budget == 0 { return false; } search.budget--; if id == search.target { search.count++; if search.count != 1 { return false; } } let node = search.source.node(id);
    match node.tag {
        block_,suite,call,product,record,array,array_op=>{ for child in search.source.children(id) { if !visit(search,child,depth + 1) { return false; } } },
        loop_=>{ let loop_ = search.source.loopInfo(id); if !pattern(search,loop_.pattern,depth + 1) || !visit(search,loop_.first,depth + 1) || !visit(search,loop_.end,depth + 1) || !visit(search,loop_.body,depth + 1) { return false; } },
        if_stmt,if_value=>{ if !visit(search,node.a,depth + 1) || !visit(search,node.b,depth + 1) || !visit(search,node.c,depth + 1) { return false; } },
        return_,project,result_associated=>{ if !visit(search,node.a,depth + 1) { return false; } },bind,construct=>{ if !visit(search,node.b,depth + 1) { return false; } },
        pattern_bind=>{ if !pattern(search,node.a,depth + 1) || !visit(search,node.b,depth + 1) || !visit(search,node.c,depth + 1) { return false; } },
        scalar,logical,apply,associated,record_merge=>{ if !visit(search,node.a,depth + 1) || !visit(search,node.b,depth + 1) { return false; } },
        constant,reference,panic,constructor_function,primitive_function,type_constructor,closure,break_=>{},_=>{ return false; },
    } return true;
}
fn check(source: const Module&,uses: const Uses&,root: u32,creation: u32) -> blot_support::Option<Plan> {
    let binding = source.node(creation).a; let family = blot_backend_private_cursor::checkSteps(source,uses,root,binding,[]); if !family.present { return blot_support::none<Plan>(); } var carry_index = blot_support::none<u32>(); var advance = blot_support::none<u32>(); var creator_count: i64 = 0;
    for member in family.value.bindings[..family.value.len] {
        for index in uses.carries.get(member) { if carry_index.present { if carry_index.value != index { return blot_support::none<Plan>(); } } else { carry_index = blot_support::some(index); } }
        for id in uses.definitions.get(member) { if id == creation { creator_count++; continue; } let input = source.node(source.node(id).b); if input.tag == blot_check_core::Tag.reference { continue; } if input.tag != blot_check_core::Tag.array_op || source.arrayOperation(source.node(id).b) != blot_backend_collection_ops::Op.cursor_advance { return blot_support::none<Plan>(); } if advance.present && advance.value != id { return blot_support::none<Plan>(); } advance = blot_support::some(id); }
    }
    if creator_count != 1 || !carry_index.present || !advance.present { return blot_support::none<Plan>(); } let selected_carry = carry_index.value; let selected_advance = advance.value; let carry = source.loop_carries[selected_carry]; let loop_ = uses.carry_loops[selected_carry].loop_; if loop_ == 0 || !alias(source,uses,carry.incoming,binding) { return blot_support::none<Plan>(); }
    let operand = source.children(source.node(selected_advance).b)[0]; if source.node(operand).tag != blot_check_core::Tag.reference { return blot_support::none<Plan>(); } let reference = source.reference(operand); if !own(source,reference) || !alias(source,uses,reference.binding,carry.iteration) || !alias(source,uses,carry.backedge,source.node(selected_advance).a) { return blot_support::none<Plan>(); }
    let created_at = uses.parentOf(creation); let loop_at = uses.parentOf(loop_); let advanced_at = uses.parentOf(selected_advance); if created_at.count != 1 || loop_at.count != 1 || advanced_at.count != 1 || created_at.node != loop_at.node || created_at.position >= loop_at.position || advanced_at.node != source.loopInfo(loop_).body { return blot_support::none<Plan>(); } var search = Search { source: source,target: created_at.node , ..}; if !visit(search,root,0) || search.count != 1 { return blot_support::none<Plan>(); } return blot_support::some(Plan { advance: selected_advance,loop_: loop_ , ..});
}
