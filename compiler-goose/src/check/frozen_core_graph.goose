// Linear mixed-graph traversal keeps executable/control links out of cycle edges.
namespace blot_check_frozen_core_validation;
import .frozen_core_validation;
import .frozen_core_bounds;
import support.option;
enum Kind { type_,row,operation,node,pattern,closure,match_,arm,pattern_row,update,update_step,loop_,request_loop,request_arm,resolver,operation_value,scheme,obligation }
let kind_count: i64=18;
fn kindCode(kind: Kind) -> i64 { match kind { Kind.type_=>0,Kind.row=>1,Kind.operation=>2,Kind.node=>3,Kind.pattern=>4,Kind.closure=>5,Kind.match_=>6,Kind.arm=>7,Kind.pattern_row=>8,Kind.update=>9,Kind.update_step=>10,Kind.loop_=>11,Kind.request_loop=>12,Kind.request_arm=>13,Kind.resolver=>14,Kind.operation_value=>15,Kind.scheme=>16,Kind.obligation=>17 } }
let kinds=[Kind.type_,Kind.row,Kind.operation,Kind.node,Kind.pattern,Kind.closure,Kind.match_,Kind.arm,Kind.pattern_row,Kind.update,Kind.update_step,Kind.loop_,Kind.request_loop,Kind.request_arm,Kind.resolver,Kind.operation_value,Kind.scheme,Kind.obligation];
struct Frame { vertex: i64, edge: i64=0 }
struct Scratch { colors: u8[:], path: Frame[:] }
struct Requirements { colors: i64, path: i64 }
struct Item { kind: Kind, id: i64 }
struct Graph { m: const Module&, starts: i64[19] }
fn initGraph(m: const Module&) -> Graph,Error {
    var graph=Graph{m,[0;19], ..}; let counts=[m.types.nodes.len,m.types.effects.rows.len,m.types.operations.len,m.nodes.len,m.patterns.len,m.closures.len,m.matches.len,m.match_arms.len,m.pattern_rows.len,m.updates.len,m.update_steps.len,m.loops.len,m.request_loops.len,m.request_arms.len,m.resolver_ops.len,m.operation_values.len,m.bindings.len,m.obligations.len];
    for size,i in counts { let value,error=sum(graph.starts[i],size); if error != Error.none { return graph,error; } graph.starts[i+1]=value; } return graph,Error.none;
}
fn vertex(self: Graph,kind: Kind,id: i64) -> i64 { return self.starts[kindCode(kind)]+id; }
fn count(self: Graph) -> i64 { return self.starts[kind_count]; }
fn item(self: const Graph&,vertex: i64) -> Item { assert(vertex >= 0 && vertex < self.count()); var k: i64=0; while vertex >= self.starts[k+1] { k++; } return Item{kinds[k],vertex-self.starts[k], ..}; }
fn to(self: Graph,kind: Kind,id: i64) -> blot_support::Option<i64> { return blot_support::some(self.vertex(kind,id)); }
fn edge(self: const Graph&,vertex: i64,slot: i64) -> blot_support::Option<i64> {
    let no=blot_support::none<i64>(); let part=self.item(vertex); let id=part.id; let m .= self.m;
    match part.kind {
        Kind.type_ => {
            let v=m.types.nodes[id]; match v.tag {
                TypeTag.forall,TypeTag.existential => { if slot == 0 { return self.to(Kind.type_,v.a); } if slot-1 < v.c { return self.to(Kind.type_,m.types.extra[v.b+slot-1]); } let goals=m.types.quantifierGoals(id as u32); let goal_slot=slot-1-v.c; if goal_slot/4 >= goals.len { return no; } let goal=goals[goal_slot/4]; let children=[goal.ty,goal.other,goal.result,goal.signature]; return self.to(Kind.type_,children[goal_slot%4]); },
                TypeTag.function => { if slot == 0 { return self.to(Kind.type_,v.a); } if slot == 1 { return self.to(Kind.type_,v.b); } if slot == 2 && m.types.effects.rows.len != 0 { return self.to(Kind.row,v.c); } },
                TypeTag.product => { if slot < v.b { return self.to(Kind.type_,m.types.extra[v.a+slot]); } },
                TypeTag.record => { if slot < v.b { return self.to(Kind.type_,m.types.extra[v.a+slot*2+1]); } },
                TypeTag.nominal,TypeTag.instance_selection => { if slot < m.types.extra[v.c] { return self.to(Kind.type_,m.types.extra[v.c+1+slot]); } },
                TypeTag.projection => { let argument_count=m.types.extra[v.c]; if slot < argument_count { return self.to(Kind.type_,m.types.extra[v.c+1+slot]); } if slot != argument_count { return no; } let name=m.types.extra[v.c+1+argument_count]; for member in m.contract_members { if member.contract.unit == v.a && member.contract.decl == v.b && member.name == name && member.kind == blot_check_core::ContractMemberKind.defined_type { return self.to(Kind.type_,member.root); } } },
                TypeTag.usage => { if slot == 0 { return self.to(Kind.type_,v.a); } if slot == 1 && v.c != 0 { return self.to(Kind.type_,v.c); } },
                TypeTag.scoped => { if slot == 0 { return self.to(Kind.type_,v.a); } if slot == 1 && v.b == 0 { return self.to(Kind.type_,v.c); } },
                TypeTag.array,TypeTag.list,TypeTag.cursor,TypeTag.resolver => { if slot == 0 { return self.to(Kind.type_,v.a); } },
                TypeTag.provider => { if slot == 0 { return self.to(Kind.type_,v.a); } if slot == 1 && m.types.effects.rows.len != 0 { return self.to(Kind.row,v.c); } },
                TypeTag.state_provider => { if slot == 0 { return self.to(Kind.type_,v.a); } if slot == 1 { return self.to(Kind.type_,v.b); } if slot == 2 { return self.to(Kind.type_,v.c); } },
                _ => {},
            }
        },
        Kind.row => { let list=m.types.effects.rows[id].labels; if slot < list.len { return self.to(Kind.operation,m.types.effects.labels[list.start+slot]); } },
        Kind.operation => { let list=m.types.operations[id].arguments; if slot < list.len { return self.to(Kind.type_,m.types.extra[list.start+slot]); } },
        Kind.node => { let v=m.nodes[id]; match v.tag {
            CoreTag.resource_acquire,CoreTag.usage_borrow,CoreTag.staging,CoreTag.scalar,CoreTag.logical,CoreTag.apply,CoreTag.associated,CoreTag.record_merge,CoreTag.type_same,CoreTag.effect_provider,CoreTag.handle,CoreTag.proof_guard => { if slot == 0 { return self.to(Kind.node,v.a); } if slot == 1 { return self.to(Kind.node,v.b); } },
            CoreTag.resource_scope,CoreTag.if_value,CoreTag.if_stmt,CoreTag.state_provider => { if slot == 0 { return self.to(Kind.node,v.a); } if slot == 1 { return self.to(Kind.node,v.b); } if slot == 2 { return self.to(Kind.node,v.c); } },
            CoreTag.task,CoreTag.block_,CoreTag.suite,CoreTag.product,CoreTag.record,CoreTag.array,CoreTag.array_op,CoreTag.storage => { if slot < v.b { return self.to(Kind.node,m.extra[v.a+slot]); } },
            CoreTag.call,CoreTag.contract_method,CoreTag.break_ => { if slot < v.c { return self.to(Kind.node,m.extra[v.b+slot]); } },
            CoreTag.bind,CoreTag.construct => { if slot == 0 { return self.to(Kind.node,v.b); } },
            CoreTag.package_unpack => { if slot == 0 { return self.to(Kind.node,v.a); } if slot == 1 { return self.to(Kind.node,m.extra[v.c]); } },
            CoreTag.package_pack => { let children=m.children(id as u32); if slot < children.len { return self.to(Kind.node,children[slot]); } },
            CoreTag.resource_release,CoreTag.usage_share,CoreTag.usage_read,CoreTag.return_,CoreTag.project,CoreTag.result_associated,CoreTag.computation,CoreTag.effect_scope => { if slot == 0 { return self.to(Kind.node,v.a); } },
            CoreTag.closure => { if slot == 0 { return self.to(Kind.closure,v.a); } }, CoreTag.match_ => { if slot == 0 { return self.to(Kind.match_,v.a); } },
            CoreTag.pattern_bind => { if slot == 0 { return self.to(Kind.pattern,v.a); } if slot == 1 { return self.to(Kind.node,v.b); } if slot == 2 { return self.to(Kind.node,v.c); } },
            CoreTag.update => { if slot == 0 { return self.to(Kind.update,v.a); } }, CoreTag.loop_ => { if slot == 0 { return self.to(Kind.loop_,v.a); } }, CoreTag.request_loop => { if slot == 0 { return self.to(Kind.request_loop,v.a); } }, CoreTag.resolver_op => { if slot == 0 { return self.to(Kind.resolver,v.a); } }, CoreTag.operation_value => { if slot == 0 { return self.to(Kind.operation_value,v.a); } },
            CoreTag.request_decision => { if slot == 0 { return self.to(Kind.node,v.b); } if slot == 1 { return self.to(Kind.node,v.c); } },
            CoreTag.effect_reflection => { if v.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.count) { if slot == 0 { return self.to(Kind.node,v.b); } } else if v.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.has) || v.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.same) { if slot == 0 { return self.to(Kind.node,v.b); } if slot == 1 { return self.to(Kind.node,v.c); } } },
            _ => {},
        } },
        Kind.pattern => { let v=m.patterns[id]; match v.tag { blot_check_core::PatternTag.value => { if slot == 0 { return self.to(Kind.node,v.a); } }, blot_check_core::PatternTag.product => { if slot < v.b { return self.to(Kind.pattern,m.extra[v.a+slot]); } }, blot_check_core::PatternTag.constructor,blot_check_core::PatternTag.record_payload => { if slot == 0 { return self.to(Kind.pattern,v.b); } }, _=>{} } },
        Kind.closure => { if slot == 0 { return self.to(Kind.node,m.closures[id].body); } },
        Kind.match_ => { let v=m.matches[id]; if slot < v.inputs.len { return self.to(Kind.node,m.extra[v.inputs.start+slot]); } let arm=slot-v.inputs.len; if arm < v.arms.len { return self.to(Kind.arm,v.arms.start+arm); } },
        Kind.arm => { let v=m.match_arms[id]; if slot == 0 { return self.to(Kind.node,v.guard); } if slot == 1 { return self.to(Kind.node,v.body); } if slot-2 < v.rows.len { return self.to(Kind.pattern_row,v.rows.start+slot-2); } },
        Kind.pattern_row => { let list=m.pattern_rows[id].patterns; if slot < list.len { return self.to(Kind.pattern,m.extra[list.start+slot]); } },
        Kind.update => { let v=m.updates[id]; if slot == 0 { return self.to(Kind.node,v.root); } if slot == 1 { return self.to(Kind.node,v.value); } let step=slot-2; if step < v.selectors.len { return self.to(Kind.update_step,v.selectors.start+step); } },
        Kind.update_step => { if slot == 0 && m.update_steps[id].kind == blot_check_core::UpdateKind.index { return self.to(Kind.node,m.update_steps[id].index); } },
        Kind.loop_ => { let v=m.loops[id]; if slot == 0 { return self.to(Kind.node,v.first); } if slot == 1 { return self.to(Kind.node,v.end); } if slot == 2 { return self.to(Kind.node,v.body); } if slot == 3 && v.pattern != 0 { return self.to(Kind.pattern,v.pattern); } },
        Kind.request_loop => { let v=m.request_loops[id]; if slot == 0 { return self.to(Kind.node,v.computation); } if slot == 1 { return self.to(Kind.node,v.completion_body); } if slot-2 < v.arms.len { return self.to(Kind.request_arm,v.arms.start+slot-2); } if slot-2 == v.arms.len && v.completion_pattern != 0 { return self.to(Kind.pattern,v.completion_pattern); } },
        Kind.request_arm => { if slot == 0 { return self.to(Kind.node,m.request_arms[id].callback); } if slot == 1 { return self.to(Kind.node,m.request_arms[id].selector); } },
        Kind.resolver => { let v=m.resolver_ops[id]; if slot == 0 { return self.to(Kind.node,v.resolver); } if slot-1 < v.arguments.len { return self.to(Kind.node,m.extra[v.arguments.start+slot-1]); } },
        Kind.operation_value => { if slot == 0 { return self.to(Kind.node,m.operation_values[id].witness); } if slot == 1 { return self.to(Kind.node,m.operation_values[id].capability); } },
        Kind.scheme => { let list=m.bindings[id].scheme.obligations; if slot < list.len { return self.to(Kind.obligation,list.start+slot); } },
        Kind.obligation => { let value=m.obligations[id]; if slot == 0 && value.kind == ObligationKind.callee_use { return self.to(Kind.scheme,value.identity.decl); } },
    } return no;
}
fn scratchRequirements(module: const Module&) -> Requirements,Error {
    let graph,error=initGraph(module); if error != Error.none { return Requirements{0,0, ..},error; }
    let extras,extra_error=sum(module.types.extra.len,module.extra.len); if extra_error != Error.none { return Requirements{0,0, ..},extra_error; }
    let stage,stage_error=sum(extras,stagingBindingCount(module)); if stage_error != Error.none { return Requirements{0,0, ..},stage_error; }
    let colors,color_error=sum(graph.count(),stage); if color_error != Error.none { return Requirements{0,0, ..},color_error; } return Requirements{colors,graph.count(), ..},Error.none;
}
fn scratchSize(module: const Module&) -> i64,Error { let needed,error=scratchRequirements(module); if error != Error.none { return 0,error; } return max(needed.colors,needed.path),Error.none; }
fn cycles(graph: Graph,scratch: Scratch) -> Error {
    let count=graph.count(); { let propagated_error = require(scratch.colors.len >= count && scratch.path.len >= count); if propagated_error != Error.none { return propagated_error; } } for &color in scratch.colors[..count] { color=0; }
    for root in count { if scratch.colors[root] != 0 { continue; } var depth: i64=1; scratch.path[0]=Frame{root, ..}; scratch.colors[root]=1;
        while depth != 0 { let top: Frame&=scratch.path[depth-1]; let child=graph.edge(top.vertex,top.edge);
            if child.present { top.edge++; match scratch.colors[child.value] { 0=>{scratch.colors[child.value]=1; scratch.path[depth]=Frame{child.value, ..}; depth++;},1=>{return Error.invalid_artifact;},2=>{},_=>{abort("invalid traversal color");} } }
            else { scratch.colors[top.vertex]=2; depth--; }
        }
    } return Error.none;
}
// Role codes are local scratch labels, not a serialized enum.
let role_type: u8=1; let role_symbol: u8=2; let role_row_variable: u8=3; let role_row: u8=4; let role_count: u8=5; let role_node: u8=6; let role_binding: u8=7; let role_pattern: u8=8; let role_constructor: u8=9; let role_projection: u8=10; let role_destination: u8=11;
fn mark(roles: u8[:],start: u32,len: u32,role: u8) -> Error { { let propagated_error = range(roles.len,start,len); if propagated_error != Error.none { return propagated_error; } } for &slot in roles[start..start+len] { { let propagated_error = require(slot == 0 || slot == role); if propagated_error != Error.none { return propagated_error; } } slot=role; } return Error.none; }
fn markScheme(roles: u8[:],scheme: blot_check_types::Scheme) -> Error { { let propagated_error = mark(roles,scheme.variables.start,scheme.variables.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(roles,scheme.row_variables.start,scheme.row_variables.len,role_row_variable); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(roles,scheme.closed_rows.start,scheme.closed_rows.len,role_row_variable); if propagated_error != Error.none { return propagated_error; } } return mark(roles,scheme.generative.start,scheme.generative.len,role_type); }
fn listRoles(m: const Module&,type_roles: u8[:],core_roles: u8[:]) -> Error {
    for &role in type_roles { role=0; } for &role in core_roles { role=0; }
    for n in m.types.nodes { match n.tag {
        TypeTag.forall,TypeTag.existential=>{{ let propagated_error = mark(type_roles,n.b,n.c,role_type); if propagated_error != Error.none { return propagated_error; } }}, TypeTag.product=>{{ let propagated_error = mark(type_roles,n.a,n.b,role_type); if propagated_error != Error.none { return propagated_error; } }},
        TypeTag.record=>{for i in 0..n.b{{ let propagated_error = mark(type_roles,n.a+i*2,1,role_symbol); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,n.a+i*2+1,1,role_type); if propagated_error != Error.none { return propagated_error; } }}},
        TypeTag.nominal,TypeTag.projection,TypeTag.instance_selection=>{{ let propagated_error = mark(type_roles,n.c,1,role_count); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,n.c+1,m.types.extra[n.c],role_type); if propagated_error != Error.none { return propagated_error; } } if n.tag == TypeTag.projection {{ let propagated_error = mark(type_roles,n.c+1+m.types.extra[n.c],1,role_symbol); if propagated_error != Error.none { return propagated_error; } }}},_=>{}
    } }
    for o in m.types.operations { { let propagated_error = mark(type_roles,o.arguments.start,o.arguments.len,role_type); if propagated_error != Error.none { return propagated_error; } } }
    for b in m.bindings { { let propagated_error = markScheme(type_roles,b.scheme); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,b.public_variables.start,b.public_variables.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,b.public_rows.start,b.public_rows.len,role_row_variable); if propagated_error != Error.none { return propagated_error; } } }
    for b in m.bodies { { let propagated_error = markScheme(type_roles,b.scheme); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,b.closed_rows.start,b.closed_rows.len,role_row_variable); if propagated_error != Error.none { return propagated_error; } } } for c in m.constructors { { let propagated_error = markScheme(type_roles,c.scheme); if propagated_error != Error.none { return propagated_error; } } }
    for c in m.contracts { { let propagated_error = mark(type_roles,c.parameters.start,c.parameters.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,c.variables.start,c.variables.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,c.row_variables.start,c.row_variables.len,role_row_variable); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,c.row_parameters.start,c.row_parameters.len,role_row); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,c.row_parameter_names.start,c.row_parameter_names.len,role_symbol); if propagated_error != Error.none { return propagated_error; } } }
    for i in m.implementations { { let propagated_error = mark(type_roles,i.head.start,i.head.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.variables.start,i.variables.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.parameter_names.start,i.parameter_names.len,role_symbol); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.row_variables.start,i.row_variables.len,role_row_variable); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.row_parameters.start,i.row_parameters.len,role_row); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.row_parameter_names.start,i.row_parameter_names.len,role_symbol); if propagated_error != Error.none { return propagated_error; } } }
    for t in m.member_templates { { let propagated_error = mark(type_roles,t.arguments.start,t.arguments.len,role_type); if propagated_error != Error.none { return propagated_error; } } } for p in m.selected_proofs { { let propagated_error = mark(type_roles,p.arguments.start,p.arguments.len,role_type); if propagated_error != Error.none { return propagated_error; } } }
    for s in m.dictionary_selections { match s.proof { blot_check_core::DictionaryProof.selected=>{},blot_check_core::DictionaryProof.given given=>{{ let propagated_error = mark(type_roles,given.value.arguments.start,given.value.arguments.len,role_type); if propagated_error != Error.none { return propagated_error; } }} } { let propagated_error = mark(core_roles,s.members.start,s.members.len,role_node); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(core_roles,s.contents.start,s.contents.len,role_node); if propagated_error != Error.none { return propagated_error; } } }
    for n in m.nominals { { let propagated_error = mark(type_roles,n.parameters.start,n.parameters.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,n.variables.start,n.variables.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(core_roles,n.constructors.start,n.constructors.len,role_constructor); if propagated_error != Error.none { return propagated_error; } } }
    for o in m.operation_names { { let propagated_error = mark(type_roles,o.variables.start,o.variables.len,role_type); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,o.parameters.start,o.parameters.len,role_type); if propagated_error != Error.none { return propagated_error; } } }
    for c in m.closures { { let propagated_error = mark(type_roles,c.closed_rows.start,c.closed_rows.len,role_row_variable); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(core_roles,c.captures.start,c.captures.len,role_binding); if propagated_error != Error.none { return propagated_error; } } } for o in m.operation_values { { let propagated_error = mark(type_roles,o.arguments.start,o.arguments.len,role_type); if propagated_error != Error.none { return propagated_error; } } }
    for n in m.nodes { match n.tag {
        CoreTag.task,CoreTag.block_,CoreTag.suite,CoreTag.product,CoreTag.array,CoreTag.array_op,CoreTag.storage=>{{ let propagated_error = mark(core_roles,n.a,n.b,role_node); if propagated_error != Error.none { return propagated_error; } }},
        CoreTag.record=>{{ let propagated_error = mark(core_roles,n.a,n.b,role_node); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(core_roles,n.c,n.b,role_destination); if propagated_error != Error.none { return propagated_error; } }}, CoreTag.call,CoreTag.break_=>{{ let propagated_error = mark(core_roles,n.b,n.c,role_node); if propagated_error != Error.none { return propagated_error; } }},
        CoreTag.package_pack=>{{ let propagated_error = mark(type_roles,n.b,n.c,role_type); if propagated_error != Error.none { return propagated_error; } }}, CoreTag.package_unpack=>{{ let propagated_error = mark(core_roles,n.c,1,role_node); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(core_roles,n.c+1,2,role_count); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,m.extra[n.c+1],m.extra[n.c+2],role_type); if propagated_error != Error.none { return propagated_error; } }},_=>{}
    } }
    for p in m.patterns { if p.tag == blot_check_core::PatternTag.product { { let propagated_error = mark(core_roles,p.a,p.b,role_pattern); if propagated_error != Error.none { return propagated_error; } } } } for p in m.pattern_rows { { let propagated_error = mark(core_roles,p.patterns.start,p.patterns.len,role_pattern); if propagated_error != Error.none { return propagated_error; } } }
    for v in m.matches { { let propagated_error = mark(core_roles,v.inputs.start,v.inputs.len,role_node); if propagated_error != Error.none { return propagated_error; } } } for u in m.updates { { let propagated_error = mark(core_roles,u.path.start,u.path.len,role_projection); if propagated_error != Error.none { return propagated_error; } } } for r in m.resolver_ops { { let propagated_error = mark(core_roles,r.arguments.start,r.arguments.len,role_node); if propagated_error != Error.none { return propagated_error; } } } for r in m.request_loops { { let propagated_error = mark(core_roles,r.completion_state_bindings.start,r.completion_state_bindings.len,role_binding); if propagated_error != Error.none { return propagated_error; } } } return Error.none;
}
