// A bounded closed family of local cursor versions owns private fields.
namespace blot_backend_private_cursor;
import check.core;
import .unit_index;
import .collection_ops;
import support.option;
struct Step { node: u32,pattern: u32,input: u32,rest: u32 }
struct Family { bindings: u32[64],len: i64 }
struct Proof { source: const blot_check_core::Module&,steps: const Step[:],bindings: u32[64],len: i64 = 0,budget: i64 = 4096 }
fn contains(values: const u32[:],wanted: u32) -> bool { for value in values { if value == wanted { return true; } } return false; }
fn contains(proof: const Proof&,binding: u32) -> bool { return contains(proof.bindings[..proof.len],binding); }
fn add(proof: Proof&,binding: u32) -> bool { if proof.contains(binding) { return true; } if proof.len == 64 { return false; } proof.bindings[proof.len] = binding; proof.len++; return true; }
fn carry(proof: Proof&,value: blot_check_core::LoopCarry) -> bool { let bindings = [value.incoming,value.iteration,value.backedge,value.outgoing]; var connected = false; for binding in bindings { connected = connected || proof.contains(binding); } if connected { for binding in bindings { if !proof.add(binding) { return false; } } } return true; }
fn bind(proof: Proof&,id: u32) -> bool {
    let source .= proof.source; let node = source.node(id); var input = node.b; if source.node(input).tag == blot_check_core::Tag.array_op && source.arrayOperation(input) == blot_backend_collection_ops::Op.cursor_advance { input = source.children(input)[0]; }
    if source.node(input).tag != blot_check_core::Tag.reference { return true; } let reference = source.reference(input); if reference.unit != 0 && reference.unit != source.unit { return true; } if proof.contains(reference.binding) || proof.contains(node.a) { if !proof.add(reference.binding) || !proof.add(node.a) { return false; } } return true;
}
fn cursor(proof: const Proof&,id: u32) -> bool { if id == 0 || proof.source.node(id).tag != blot_check_core::Tag.reference { return false; } let reference = proof.source.reference(id); return (reference.unit == 0 || reference.unit == proof.source.unit) && proof.contains(reference.binding); }
fn exitAt(proof: Proof&,id: u32,position: u32) -> bool {
    let source .= proof.source; let values = source.breakValues(id); let carries = source.loopCarries(source.node(id).a); if position >= values.len || position >= carries.len { return true; } let value = values[position]; let held = carries[position];
    if !proof.contains(held.outgoing) && !proof.cursor(value) { return true; } if source.node(value).tag != blot_check_core::Tag.reference { return false; } let reference = source.reference(value); if reference.unit != 0 && reference.unit != source.unit { return false; }
    if !proof.add(reference.binding) { return false; } for member in [held.incoming,held.iteration,held.backedge,held.outgoing] { if !proof.add(member) { return false; } } return true;
}
recursive fn pattern(proof: Proof&,id: u32,depth: i64) -> bool {
    if id == 0 { return true; } if depth == 128 || proof.budget == 0 { return false; } proof.budget--; let value = proof.source.pattern(id);
    match value.tag { wildcard,constant,bind=>{ return true; },value=>{ return visit(proof,value.a,depth + 1); },constructor,record_payload=>{ return pattern(proof,value.b,depth + 1); },product=>{ for child in proof.source.patternChildren(id) { if !pattern(proof,child,depth + 1) { return false; } } return true; },invalid=>{ return false; }, }
}
recursive fn escaped(proof: Proof&,id: u32,depth: i64) -> bool {
    if proof.cursor(id) { return true; } if depth >= 128 || proof.budget == 0 { return false; } proof.budget--; let node = proof.source.node(id);
    match node.tag { construct=>{ return node.b == 0 || escaped(proof,node.b,depth + 1); },product,record=>{ for child in proof.source.children(id) { if !escaped(proof,child,depth + 1) { return false; } } return true; },_=>{ return visit(proof,id,depth + 1); }, }
}
recursive fn visit(proof: Proof&,id: u32,depth: i64) -> bool {
    if id == 0 { return true; } if depth == 128 || proof.budget == 0 { return false; } proof.budget--; let source .= proof.source; let node = source.node(id);
    for step in proof.steps { if proof.contains(step.input) { if id == step.node { return true; } if id == step.pattern { return visit(proof,node.c,depth + 1); } } }
    match node.tag {
        constant,panic,constructor_function,primitive_function,type_constructor,closure=>{ return true; },reference=>{ return !proof.cursor(id); },
        bind=>{ if proof.contains(node.a) { if proof.cursor(node.b) { return true; } if source.node(node.b).tag == blot_check_core::Tag.array_op && source.arrayOperation(node.b) == blot_backend_collection_ops::Op.cursor_advance && proof.cursor(source.children(node.b)[0]) { return true; } } return visit(proof,node.b,depth + 1); },
        array_op=>{ let op = source.arrayOperation(id); if op == blot_backend_collection_ops::Op.cursor_has || op == blot_backend_collection_ops::Op.cursor_value || op == blot_backend_collection_ops::Op.cursor_advance { if proof.cursor(source.children(id)[0]) { return op != blot_backend_collection_ops::Op.cursor_advance; } } for child in source.children(id) { if !visit(proof,child,depth + 1) { return false; } } return true; },
        return_=>{ if proof.steps.len != 0 { return escaped(proof,node.a,depth + 1); } return visit(proof,node.a,depth + 1); },
        break_=>{ if proof.steps.len == 0 { return false; } for value in source.breakValues(id) { if !proof.cursor(value) && !visit(proof,value,depth + 1) { return false; } } return true; },
        project,result_associated=>{ return visit(proof,node.a,depth + 1); },construct=>{ return visit(proof,node.b,depth + 1); },
        scalar,logical,apply,associated,record_merge=>{ return visit(proof,node.a,depth + 1) && visit(proof,node.b,depth + 1); },if_value,if_stmt=>{ return visit(proof,node.a,depth + 1) && visit(proof,node.b,depth + 1) && visit(proof,node.c,depth + 1); },
        loop_=>{ let loop_ = source.loopInfo(id); return pattern(proof,loop_.pattern,depth + 1) && visit(proof,loop_.first,depth + 1) && visit(proof,loop_.end,depth + 1) && visit(proof,loop_.body,depth + 1); },
        block_,suite,call,product,record,array=>{ for child in source.children(id) { if !visit(proof,child,depth + 1) { return false; } } return true; },
        pattern_bind=>{ return pattern(proof,node.a,depth + 1) && visit(proof,node.b,depth + 1); },_=>{ return false; },
    }
}
fn collect(nodes: u32[1024]&,count: i64&,id: u32) -> bool { if contains(nodes[..count],id) { return true; } if count == 1024 { return false; } nodes[count] = id; count++; return true; }
fn sort(values: u32[:]) { var gap = values.len / 2; while gap > 0 { for index in gap..values.len { let value = values[index]; var position = index; while position >= gap && values[position - gap] > value { values[position] = values[position - gap]; position -= gap; } values[position] = value; } gap /= 2; } }
fn check(source: const blot_check_core::Module&,uses: const blot_backend_unit_index::Uses&,root: u32,binding: u32) -> bool { return checkSteps(source,uses,root,binding,[]).present; }
fn checkSteps(source: const blot_check_core::Module&,uses: const blot_backend_unit_index::Uses&,root: u32,binding: u32,steps: const Step[:]) -> blot_support::Option<Family> {
    var closure = Proof { source,steps , ..}; if !closure.add(binding) { return blot_support::none<Family>(); } var next: i64 = 0;
    while next < closure.len {
        let member = closure.bindings[next]; next++; for step in steps { if step.input == member && step.rest != 0 && !closure.add(step.rest) { return blot_support::none<Family>(); } }
        for index in uses.carries.get(member) { if !closure.carry(source.loop_carries[index]) { return blot_support::none<Family>(); } }
        for id in uses.definitions.get(member) { if !closure.bind(id) { return blot_support::none<Family>(); } } for id in uses.inputs.get(member) { if !closure.bind(id) { return blot_support::none<Family>(); } }
        if steps.len == 0 { continue; }
        for index in uses.carries.get(member) { if source.loop_carries[index].outgoing != member { continue; } let owner = uses.carry_loops[index]; for exit in uses.exits.get(owner.loop_) { if !closure.exitAt(exit,owner.position) { return blot_support::none<Family>(); } } }
        for id in uses.references.get(member) { if !closure.cursor(id) { continue; } for entry in uses.values.get(id) { if source.node(source.node(entry.exit).a).tag != blot_check_core::Tag.loop_ { continue; } if !closure.exitAt(entry.exit,entry.position) { return blot_support::none<Family>(); } } }
    }
    var carries: u32[256] = default<u32[256]>(); var carry_count: i64 = 0; var nodes: u32[1024] = default<u32[1024]>(); var node_count: i64 = 0;
    for member in closure.bindings[..closure.len] {
        for index in uses.carries.get(member) { if contains(carries[..carry_count],index) { continue; } if carry_count == 256 { return blot_support::none<Family>(); } carries[carry_count] = index; carry_count++; if steps.len == 0 { continue; } for exit in uses.exits.get(uses.carry_loops[index].loop_) { if !collect(nodes,node_count,exit) { return blot_support::none<Family>(); } } }
        for id in uses.definitions.get(member) { if !collect(nodes,node_count,id) { return blot_support::none<Family>(); } } for id in uses.inputs.get(member) { if !collect(nodes,node_count,id) { return blot_support::none<Family>(); } }
        if steps.len == 0 { continue; } for id in uses.references.get(member) { for entry in uses.values.get(id) { if !collect(nodes,node_count,entry.exit) { return blot_support::none<Family>(); } } }
    }
    sort(carries[..carry_count]); sort(nodes[..node_count]); var proof = Proof { source,steps , ..}; if !proof.add(binding) { return blot_support::none<Family>(); } var previous: i64 = 0;
    while previous != proof.len { previous = proof.len; for step in steps { if proof.contains(step.input) && step.rest != 0 && !proof.add(step.rest) { return blot_support::none<Family>(); } } for index in carries[..carry_count] { if !proof.carry(source.loop_carries[index]) { return blot_support::none<Family>(); } }
        for id in nodes[..node_count] { let node = source.node(id); if steps.len != 0 && node.tag == blot_check_core::Tag.break_ && source.node(node.a).tag == blot_check_core::Tag.loop_ { for position in 0..source.breakValues(id).len { if !proof.exitAt(id,position as u32) { return blot_support::none<Family>(); } } } if node.tag == blot_check_core::Tag.bind && !proof.bind(id) { return blot_support::none<Family>(); } }
    }
    for member in proof.bindings[..proof.len] { let flags = uses.flagsOf(member); if flags.merge_branch || flags.merge_result || flags.captured { return blot_support::none<Family>(); } }
    if !proof.visit(root,0) { return blot_support::none<Family>(); } return blot_support::some(Family { proof.bindings,proof.len , ..});
}
