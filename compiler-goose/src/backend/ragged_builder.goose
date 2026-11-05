// Private finite append regions use already selected primitive and field facts.
namespace blot_backend_ragged_builder;
import check.core;
import check.types;
import .exact_builder;
import .function_facts;
import .collection_ops;
import support.option;
let probe_limit: u32 = 1048576;
fn maximumCount(words: u32,is_list: bool) -> blot_support::Option<u32> { let width = max(1,words); if is_list { return blot_support::some(268435456 / width); } if width > 4294967295 / 4 { return blot_support::none<u32>(); } return blot_support::some(min(268435456,(4294967295 - 4) / (width * 4))); }
struct Plan { storage: blot_backend_exact_builder::Plan,root: u32,payload_binding: u32 = 0,expressions: u32[32],expression_count: i64 = 0,qualifier_count: i64 = 0 }
fn alias(plan: const Plan&,binding: u32) -> bool { return plan.storage.alias(binding); }
fn add(plan: Plan&,binding: u32) -> bool { if plan.alias(binding) { return true; } return plan.storage.add(binding); }
fn expression(plan: Plan&,id: u32) -> bool { if id == 0 { return true; } if plan.expression_count == 32 { return false; } plan.expressions[plan.expression_count] = id; plan.expression_count++; return true; }
struct Analyzer<F> { source: const blot_check_core::Module&,facts: F,plan: Plan,remaining: i64 = 256 }
fn step<F>(analyzer: Analyzer<F>&) -> bool { if analyzer.remaining == 0 { return false; } analyzer.remaining--; return true; }
recursive fn suite<F>(analyzer: Analyzer<F>&,id: u32,incoming: u32) -> blot_support::Option<u32> { if id == 0 { return blot_support::some(incoming); } if !analyzer.step() { return blot_support::none<u32>(); } let node = analyzer.source.node(id); if node.tag != blot_check_core::Tag.suite && node.tag != blot_check_core::Tag.block_ { return region(analyzer,id,incoming); } var current = incoming; for child in analyzer.source.children(id) { let selected = region(analyzer,child,current); if !selected.present { return blot_support::none<u32>(); } current = selected.value; } return blot_support::some(current); }
fn append<F>(analyzer: Analyzer<F>&,id: u32,incoming: u32) -> bool {
    let module .= analyzer.source; var append_id = id; var payload: u32 = 0; var receiver = incoming;
    if module.node(id).tag == blot_check_core::Tag.block_ {
        let children = module.children(id); if children.len != 3 { return false; } let first = module.node(children[0]); let second = module.node(children[1]); let last = module.node(children[2]); if first.tag != blot_check_core::Tag.bind || second.tag != blot_check_core::Tag.bind || last.tag != blot_check_core::Tag.return_ || last.b != id { return false; }
        if !blot_backend_function_facts::local(module,first.b,incoming) || !analyzer.plan.add(first.a) { return false; } receiver = first.a; payload = second.b; analyzer.plan.payload_binding = second.a; append_id = last.a;
        if module.node(append_id).tag != blot_check_core::Tag.array_op || module.arrayOperation(append_id) != blot_backend_collection_ops::Op.append { return false; } if !blot_backend_function_facts::local(module,module.children(append_id)[1],second.a) { return false; }
    }
    if module.node(append_id).tag != blot_check_core::Tag.array_op || module.arrayOperation(append_id) != blot_backend_collection_ops::Op.append { return false; } let arguments = module.children(append_id); if arguments.len != 2 || !blot_backend_function_facts::local(module,arguments[0],receiver) || analyzer.plan.storage.append != 0 { return false; } analyzer.plan.storage.append = append_id; if payload == 0 { payload = arguments[1]; } analyzer.plan.storage.value = payload; return true;
}
recursive fn region<F>(analyzer: Analyzer<F>&,id: u32,incoming: u32) -> blot_support::Option<u32> {
    if !analyzer.step() { return blot_support::none<u32>(); } let module .= analyzer.source; let node = module.node(id);
    match node.tag {
        loop_=>{ let loop = module.loopInfo(id); if loop.kind == blot_check_core::LoopKind.forever || loop.can_exit || !analyzer.facts.pattern(id) { return blot_support::none<u32>(); } let carries = module.loopCarries(id); if carries.len != 1 || carries[0].incoming != incoming || analyzer.plan.storage.loop_count == 4 { return blot_support::none<u32>(); }
            analyzer.plan.storage.loops[analyzer.plan.storage.loop_count] = id; analyzer.plan.storage.loop_count++; let carry = carries[0]; if !analyzer.plan.add(carry.iteration) || !analyzer.plan.add(carry.backedge) || !analyzer.plan.add(carry.outgoing) { return blot_support::none<u32>(); } if !analyzer.plan.expression(loop.first) || !analyzer.plan.expression(loop.end) { return blot_support::none<u32>(); } let body = suite(analyzer,loop.body,carry.iteration); if !body.present || body.value != carry.backedge { return blot_support::none<u32>(); } return blot_support::some(carry.outgoing);
        },
        if_stmt=>{ if analyzer.plan.qualifier_count == 16 { return blot_support::none<u32>(); } analyzer.plan.qualifier_count++; if !analyzer.plan.expression(node.a) { return blot_support::none<u32>(); } let merges = module.branchMerges(id); if merges.len != 1 || merges[0].else_binding != incoming { return blot_support::none<u32>(); } let alternate = suite(analyzer,node.c,incoming); if !alternate.present || alternate.value != incoming { return blot_support::none<u32>(); } let selected = suite(analyzer,node.b,incoming); if !selected.present || selected.value != merges[0].then_binding || !analyzer.plan.add(merges[0].result) { return blot_support::none<u32>(); } return blot_support::some(merges[0].result); },
        bind=>{ if append(analyzer,node.b,incoming) { if !analyzer.plan.add(node.a) { return blot_support::none<u32>(); } return blot_support::some(node.a); } if blot_backend_function_facts::local(module,node.b,incoming) { if !analyzer.plan.add(node.a) { return blot_support::none<u32>(); } return blot_support::some(node.a); }
            if analyzer.plan.qualifier_count == 16 || analyzer.plan.alias(node.a) { return blot_support::none<u32>(); } analyzer.plan.qualifier_count++; if !analyzer.plan.expression(node.b) { return blot_support::none<u32>(); } return blot_support::some(incoming);
        },_=>{ return blot_support::none<u32>(); },
    }
}
recursive fn pure<F>(analyzer: Analyzer<F>&,id: u32) -> bool {
    if id == 0 { return true; } if !analyzer.step() { return false; } let module .= analyzer.source; let node = module.node(id);
    match node.tag {
        constant=>{ return true; },reference=>{ let reference = module.reference(id); return !analyzer.plan.alias(reference.binding) && analyzer.facts.reference(id); },
        scalar,associated=>{ if !analyzer.facts.primitive(id) || node.op == blot_check_core::Op.div || node.op == blot_check_core::Op.rem || node.op == blot_check_core::Op.convert_f32_u32 { return false; } return pure(analyzer,node.a) && pure(analyzer,node.b); },
        call=>{ if !analyzer.facts.primitive(id) { return false; } let arguments = module.children(id); return arguments.len == 2 && pure(analyzer,arguments[0]) && pure(analyzer,arguments[1]); },logical=>{ return pure(analyzer,node.a) && pure(analyzer,node.b); },if_value=>{ return pure(analyzer,node.a) && pure(analyzer,node.b) && pure(analyzer,node.c); },project=>{ return analyzer.facts.field(id) && pure(analyzer,node.a); },
        array_op=>{ return module.arrayOperation(id) == blot_backend_collection_ops::Op.length && pure(analyzer,module.children(id)[0]); },_=>{ return false; },
    }
}
fn analyze<F>(module: const blot_check_core::Module&,id: u32,selected: F) -> blot_support::Option<Plan> {
    if module.node(id).tag != blot_check_core::Tag.block_ { return blot_support::none<Plan>(); } let statements = module.children(id); if statements.len < 3 || statements.len > 19 { return blot_support::none<Plan>(); } let initial = module.node(statements[0]); let returned = module.node(statements[statements.len - 1]);
    if initial.tag != blot_check_core::Tag.bind || returned.tag != blot_check_core::Tag.return_ || returned.b != id || module.node(initial.b).tag != blot_check_core::Tag.array || module.children(initial.b).len != 0 || module.types.node(module.typeOf(initial.b)).tag != blot_check_types::Tag.list { return blot_support::none<Plan>(); }
    var analyzer = Analyzer<F> { source: module,facts: selected,plan: Plan { root: id,storage: blot_backend_exact_builder::Plan { initial: initial.b , ..} , ..} , ..}; if !analyzer.plan.add(initial.a) { return blot_support::none<Plan>(); } var outgoing = initial.a;
    for statement in statements[1..statements.len - 1] { let result = region(analyzer,statement,outgoing); if !result.present { return blot_support::none<Plan>(); } outgoing = result.value; } if analyzer.plan.storage.loop_count == 0 || analyzer.plan.storage.append == 0 { return blot_support::none<Plan>(); } var result = returned.a;
    if module.node(result).tag == blot_check_core::Tag.array_op && module.arrayOperation(result) == blot_backend_collection_ops::Op.convert { analyzer.plan.storage.conversion = result; result = module.children(result)[0]; } if !blot_backend_function_facts::local(module,result,outgoing) { return blot_support::none<Plan>(); }
    for expression in analyzer.plan.expressions[..analyzer.plan.expression_count] { if !pure(analyzer,expression) { return blot_support::none<Plan>(); } } if !pure(analyzer,analyzer.plan.storage.value) { return blot_support::none<Plan>(); } return blot_support::some(analyzer.plan);
}
