// Move scalar work only where skipping or reordering it is unobservable.
namespace blot_backend_safe_local_sinking;
import check.core;
import check.types;
import .unit_index;
import .function_facts;
import .resolved_body;
import support.error;
import support.option;
recursive fn stableInput(module: const blot_check_core::Module&,uses: const blot_backend_unit_index::Uses&,id: u32,budget: i64&) -> bool {
    if id == 0 { return true; } if budget == 0 { return false; } budget--; let node = module.node(id);
    match node.tag {
        constant=>{ return true; },reference=>{ let reference = module.reference(id); if reference.unit != 0 && reference.unit != module.unit { return false; } if reference.binding >= module.bindings.len { return false; } let kind = module.binding(reference.binding).kind; if kind != blot_reuse_principal_interface::Kind.local && kind != blot_reuse_principal_interface::Kind.parameter { return false; } let flags = uses.flagsOf(reference.binding); return !flags.carried && !flags.captured && !flags.merge_branch && !flags.merge_result; },
        scalar,logical=>{ return stableInput(module,uses,node.a,budget) && stableInput(module,uses,node.b,budget); },_=>{ return false; },
    }
}
fn addCount(total: u8&,next: blot_support::Option<u8>) -> bool { if !next.present { return false; } let value = next.value; if value > 1 || total > 1 - value { return false; } total += value; return true; }
recursive fn reads(module: const blot_check_core::Module&,id: u32,wanted: u32,budget: i64&) -> blot_support::Option<u8> {
    if id == 0 { return blot_support::some(0 as u8); } if budget == 0 { return blot_support::none<u8>(); } budget--; if id == wanted { return blot_support::some(1 as u8); } let node = module.node(id); var count: u8 = 0;
    match node.tag {
        constant,reference,panic=>{},
        block_,suite,array,product,record,array_op,call,contract_method,break_=>{ for child in module.children(id) { if !addCount(count,reads(module,child,wanted,budget)) { return blot_support::none<u8>(); } } },
        bind,construct,project,return_=>{ var child = node.a; if node.tag == blot_check_core::Tag.bind || node.tag == blot_check_core::Tag.construct { child = node.b; } if !addCount(count,reads(module,child,wanted,budget)) { return blot_support::none<u8>(); } },
        scalar,logical,associated,apply,record_merge,type_same=>{ if !addCount(count,reads(module,node.a,wanted,budget)) || !addCount(count,reads(module,node.b,wanted,budget)) { return blot_support::none<u8>(); } },
        if_stmt,if_value=>{ if !addCount(count,reads(module,node.a,wanted,budget)) || !addCount(count,reads(module,node.b,wanted,budget)) || !addCount(count,reads(module,node.c,wanted,budget)) { return blot_support::none<u8>(); } },
        pattern_bind=>{ if !addCount(count,reads(module,node.b,wanted,budget)) || !addCount(count,reads(module,node.c,wanted,budget)) { return blot_support::none<u8>(); } },_=>{ return blot_support::none<u8>(); },
    } return blot_support::some(count);
}
fn plan<E>(module: const blot_check_core::Module&,uses: const blot_backend_unit_index::Uses&,root: u32,prepared: blot_backend_resolved_body::Store<E>&,body: u32) -> blot_error::Error {
    var scope = root; let outer = module.node(scope); if outer.tag == blot_check_core::Tag.block_ && module.children(scope).len == 1 { let completion = module.node(module.children(scope)[0]); if completion.tag == blot_check_core::Tag.return_ && module.node(completion.a).tag == blot_check_core::Tag.block_ { scope = completion.a; } }
    let tag = module.node(scope).tag; if tag != blot_check_core::Tag.block_ && tag != blot_check_core::Tag.suite { return blot_error::Error.none; } let statements = module.children(scope); if statements.len > 256 { return blot_error::Error.none; }
    for statement,position in statements {
        let node = module.node(statement); if node.tag != blot_check_core::Tag.bind || node.a >= module.bindings.len { continue; } if prepared.contains(body,statement) { continue; } let binding = module.binding(node.a);
        if binding.kind != blot_reuse_principal_interface::Kind.local || binding.scheme.variables.len != 0 || binding.scheme.row_variables.len != 0 { continue; } let ty = module.types.node(binding.ty).tag; if ty != blot_check_types::Tag.unsigned32 && ty != blot_check_types::Tag.floating32 && ty != blot_check_types::Tag.boolean { continue; }
        let flags = uses.flagsOf(node.a); if flags.captured || flags.carried || flags.merge_branch || flags.merge_result { continue; } let references = uses.references.get(node.a); if references.len != 1 { continue; } let reference = references[0];
        if position + 1 < statements.len { let next = statements[position + 1]; let consumer = module.node(next); if (consumer.tag == blot_check_core::Tag.return_ && consumer.a == reference) || (consumer.tag == blot_check_core::Tag.if_stmt && consumer.a == reference && module.branchMerges(next).len == 0) { prepared.setSink(body,node.a,node.b); continue; } }
        var proof_budget: i64 = 128; if !stableInput(module,uses,node.b,proof_budget) { continue; } proof_budget = 128; if !blot_backend_function_facts::behavior(module,node.b,proof_budget).movable() { continue; }
        var scan_budget: i64 = 512; var count: u8 = 0; var admitted = true; for later in statements[position + 1..] { if !addCount(count,reads(module,later,reference,scan_budget)) { admitted = false; break; } } if admitted && count == 1 { prepared.setSink(body,node.a,node.b); }
    } return blot_error::Error.none;
}
