// Linear mixed-graph traversal keeps executable/control links out of cycle edges.
namespace squid_check_frozen_core_validation;
import reuse.principal_interface;

import check.check_packet_owner;
import check.core;
import check.types;
import support.error;
import support.option;

import .frozen_core_validation;
import .frozen_core_bounds;
enum Kind { type_,row,operation,node,pattern,closure,match_,arm,pattern_row,update,update_step,loop_,spark,operation_value,scheme,obligation }
let kind_count: i64=16;
fn kindCode(kind: Kind) -> i64 { match kind { type_=>0,row=>1,operation=>2,node=>3,pattern=>4,closure=>5,match_=>6,arm=>7,pattern_row=>8,update=>9,update_step=>10,loop_=>11,spark=>12,operation_value=>13,scheme=>14,obligation=>15 } }
let kinds=[Kind.type_,Kind.row,Kind.operation,Kind.node,Kind.pattern,Kind.closure,Kind.match_,Kind.arm,Kind.pattern_row,Kind.update,Kind.update_step,Kind.loop_,Kind.spark,Kind.operation_value,Kind.scheme,Kind.obligation];
struct Frame { vertex: i64, edge: i64=0 }
struct Scratch { colors: u8[:], path: Frame[:] }
struct Requirements { colors: i64, path: i64 }
struct Item { kind: Kind, id: i64 }
struct Graph { m: const Module&, starts: i64[17] }
fn initGraph(m: const Module&) -> Graph,Error {
    var graph=Graph{m,[0;17], ..}; let counts=[m.types.nodes.len,m.types.effects.rows.len,m.types.operations.len,m.nodes.len,m.patterns.len,m.closures.len,m.matches.len,m.match_arms.len,m.pattern_rows.len,m.updates.len,m.update_steps.len,m.loops.len,m.sparks.len,m.operation_values.len,m.bindings.len,m.obligations.len];
    for size,i in counts { let value,error=sum(graph.starts[i],size); if error != squid_error::Error.none { return graph,error; } graph.starts[i+1]=value; } return graph,squid_error::Error.none;
}
fn vertex(self_: Graph,kind: Kind,id: i64) -> i64 { return self_.starts[kindCode(kind)]+id; }
fn count(self_: Graph) -> i64 { return self_.starts[kind_count]; }
fn item(self_: const Graph&,vertex: i64) -> Item { assert(vertex >= 0 && vertex < self_.count()); var k: i64=0; while vertex >= self_.starts[k+1] { k++; } return Item{kinds[k],vertex-self_.starts[k], ..}; }
fn to(self_: Graph,kind: Kind,id: i64) -> squid_support::Option<i64> { return squid_support::some(self_.vertex(kind,id)); }
fn edge(self_: const Graph&,vertex: i64,slot: i64) -> squid_support::Option<i64> {
    let no=squid_support::none<i64>(); let part=self_.item(vertex); let id=part.id; let m .= self_.m;
    match part.kind {
        type_ => {
            let v=m.types.nodes[id]; match v.tag {
                forall,existential => { if slot == 0 { return self_.to(Kind.type_,v.a); } if slot-1 < v.c { return self_.to(Kind.type_,m.types.extra[v.b+slot-1]); } },
                function => { if slot == 0 { return self_.to(Kind.type_,v.a); } if slot == 1 { return self_.to(Kind.type_,v.b); } if slot == 2 && m.types.effects.rows.len != 0 { return self_.to(Kind.row,v.c); } },
                product => { if slot < v.b { return self_.to(Kind.type_,m.types.extra[v.a+slot]); } },
                record => { if slot < v.b { return self_.to(Kind.type_,m.types.extra[v.a+slot*2+1]); } },
                nominal,instance_selection => { if slot < m.types.extra[v.c] { return self_.to(Kind.type_,m.types.extra[v.c+1+slot]); } },
                projection => { let argument_count=m.types.extra[v.c]; if slot < argument_count { return self_.to(Kind.type_,m.types.extra[v.c+1+slot]); } if slot != argument_count { return no; } let name=m.types.extra[v.c+1+argument_count]; for member in m.contract_members { if member.contract.unit == v.a && member.contract.decl == v.b && member.name == name && member.kind == squid_reuse_principal_interface::ContractMemberKind.defined_type { return self_.to(Kind.type_,member.root); } } },
                usage => { if slot == 0 { return self_.to(Kind.type_,v.a); } if slot == 1 && v.c != 0 { return self_.to(Kind.type_,v.c); } },
                scoped => { if slot == 0 { return self_.to(Kind.type_,v.a); } if slot == 1 && v.b == 0 { return self_.to(Kind.type_,v.c); } },
                array,list,cursor,resolver => { if slot == 0 { return self_.to(Kind.type_,v.a); } },
                provider => { if slot == 0 { return self_.to(Kind.type_,v.a); } if slot == 1 && m.types.effects.rows.len != 0 { return self_.to(Kind.row,v.c); } },
                state_provider => { if slot == 0 { return self_.to(Kind.type_,v.a); } if slot == 1 { return self_.to(Kind.type_,v.b); } if slot == 2 { return self_.to(Kind.type_,v.c); } },
                _ => {},
            }
        },
        row => { let list=m.types.effects.rows[id].labels; if slot < list.len { return self_.to(Kind.operation,m.types.effects.labels[list.start+slot]); } },
        operation => { let list=m.types.operations[id].arguments; if slot < list.len { return self_.to(Kind.type_,m.types.extra[list.start+slot]); } },
        node => { let v=m.nodes[id]; match v.tag {
            staging,scalar,logical,apply,associated,type_same,effect_provider,handle => { if slot == 0 { return self_.to(Kind.node,v.a); } if slot == 1 { return self_.to(Kind.node,v.b); } },
            if_value,if_stmt,state_provider,comptime_if => { if slot == 0 { return self_.to(Kind.node,v.a); } if slot == 1 { return self_.to(Kind.node,v.b); } if slot == 2 { return self_.to(Kind.node,v.c); } },
            with_handle => { if slot == 0 { return self_.to(Kind.node,v.a); } if slot - 1 < v.c { return self_.to(Kind.node,m.extra[v.b + slot - 1]); } },
            comptime_for => { if slot == 0 { return self_.to(Kind.node,v.b); } },
            comptime_meta => { if v.c == 0 && slot == 0 { return self_.to(Kind.node,v.a); } if (v.c == 8 || v.c == 9) && slot == 0 { return self_.to(Kind.node,v.b); } },
            spark => { if slot == 0 { return self_.to(Kind.spark,v.a); } },
            flat_op => { if v.c <= squid_check_core::flat_op_process_binding_hash && slot == 0 { return self_.to(Kind.node,v.a); } },
            block_,suite,product,record,array,array_op,storage => { if slot < v.b { return self_.to(Kind.node,m.extra[v.a+slot]); } },
            call,contract_method,break_ => { if slot < v.c { return self_.to(Kind.node,m.extra[v.b+slot]); } },
            bind,construct => { if slot == 0 { return self_.to(Kind.node,v.b); } },
            return_,project,result_associated,fork_ => { if slot == 0 { return self_.to(Kind.node,v.a); } },
            closure => { if slot == 0 { return self_.to(Kind.closure,v.a); } }, match_ => { if slot == 0 { return self_.to(Kind.match_,v.a); } },
            pattern_bind => { if slot == 0 { return self_.to(Kind.pattern,v.a); } if slot == 1 { return self_.to(Kind.node,v.b); } if slot == 2 { return self_.to(Kind.node,v.c); } },
            update => { if slot == 0 { return self_.to(Kind.update,v.a); } }, loop_ => { if slot == 0 { return self_.to(Kind.loop_,v.a); } }, operation_value => { if slot == 0 { return self_.to(Kind.operation_value,v.a); } },
            effect_reflection => { if v.a == squid_check_check::reflectionKindCode(squid_check_check::ReflectionKind.count) { if slot == 0 { return self_.to(Kind.node,v.b); } } else if v.a == squid_check_check::reflectionKindCode(squid_check_check::ReflectionKind.has) || v.a == squid_check_check::reflectionKindCode(squid_check_check::ReflectionKind.same) { if slot == 0 { return self_.to(Kind.node,v.b); } if slot == 1 { return self_.to(Kind.node,v.c); } } },
            _ => {},
        } },
        pattern => { let v=m.patterns[id]; match v.tag { value => { if slot == 0 { return self_.to(Kind.node,v.a); } }, product => { if slot < v.b { return self_.to(Kind.pattern,m.extra[v.a+slot]); } }, constructor,record_payload => { if slot == 0 { return self_.to(Kind.pattern,v.b); } }, _=>{} } },
        closure => { if slot == 0 { return self_.to(Kind.node,m.closures[id].body); } },
        match_ => { let v=m.matches[id]; if slot < v.inputs.len { return self_.to(Kind.node,m.extra[v.inputs.start+slot]); } let arm=slot-v.inputs.len; if arm < v.arms.len { return self_.to(Kind.arm,v.arms.start+arm); } },
        arm => { let v=m.match_arms[id]; if slot == 0 { return self_.to(Kind.node,v.guard_); } if slot == 1 { return self_.to(Kind.node,v.body); } if slot-2 < v.rows.len { return self_.to(Kind.pattern_row,v.rows.start+slot-2); } },
        pattern_row => { let list=m.pattern_rows[id].patterns; if slot < list.len { return self_.to(Kind.pattern,m.extra[list.start+slot]); } },
        update => { let v=m.updates[id]; if slot == 0 { return self_.to(Kind.node,v.root); } if slot == 1 { return self_.to(Kind.node,v.value); } let step=slot-2; if step < v.selectors.len { return self_.to(Kind.update_step,v.selectors.start+step); } },
        update_step => {
            let step=m.update_steps[id];
            // A comptime field references its binder, with no executable child.
            if slot == 0 && step.kind == squid_check_core::UpdateKind.index { return self_.to(Kind.node,step.index); }
        },
        loop_ => { let v=m.loops[id]; if slot == 0 { return self_.to(Kind.node,v.first); } if slot == 1 { return self_.to(Kind.node,v.end); } if slot == 2 { return self_.to(Kind.node,v.body); } if slot == 3 && v.pattern != 0 { return self_.to(Kind.pattern,v.pattern); } },
        spark => { let v=m.sparks[id]; if slot == 0 { return self_.to(Kind.node,v.source); } if slot == 1 { return self_.to(Kind.node,v.end); } if slot == 2 { return self_.to(Kind.node,v.body); } if slot == 3 && v.pattern != 0 { return self_.to(Kind.pattern,v.pattern); } },
        operation_value => { if slot == 0 { return self_.to(Kind.node,m.operation_values[id].witness); } if slot == 1 { return self_.to(Kind.node,m.operation_values[id].capability); } },
        scheme => { let list=m.bindings[id].scheme.obligations; if slot < list.len { return self_.to(Kind.obligation,list.start+slot); } },
        obligation => { let value=m.obligations[id]; if slot == 0 && value.kind == squid_check_types::ObligationKind.callee_use { return self_.to(Kind.scheme,value.identity.decl); } },
    } return no;
}
fn scratchRequirements(module: const Module&) -> Requirements,Error {
    let graph,error=initGraph(module); if error != squid_error::Error.none { return Requirements{0,0, ..},error; }
    let extras,extra_error=sum(module.types.extra.len,module.extra.len); if extra_error != squid_error::Error.none { return Requirements{0,0, ..},extra_error; }
    let stage,stage_error=sum(extras,stagingBindingCount(module)); if stage_error != squid_error::Error.none { return Requirements{0,0, ..},stage_error; }
    let colors,color_error=sum(graph.count(),stage); if color_error != squid_error::Error.none { return Requirements{0,0, ..},color_error; } return Requirements{colors,graph.count(), ..},squid_error::Error.none;
}
fn scratchSize(module: const Module&) -> i64,Error { let needed,error=scratchRequirements(module); if error != squid_error::Error.none { return 0,error; } return max(needed.colors,needed.path),squid_error::Error.none; }
fn cycles(graph: Graph,scratch: Scratch) -> Error {
    let count=graph.count(); { let propagated_error = require(scratch.colors.len >= count && scratch.path.len >= count); if propagated_error != squid_error::Error.none { return propagated_error; } } for &color in scratch.colors[..count] { color=0; }
    for root in count { if scratch.colors[root] != 0 { continue; } var depth: i64=1; scratch.path[0]=Frame{root, ..}; scratch.colors[root]=1;
        while depth != 0 { let top: Frame& =scratch.path[depth-1]; let child=graph.edge(top.vertex,top.edge);
            if child.present { top.edge++; match scratch.colors[child.value] { 0=>{scratch.colors[child.value]=1; scratch.path[depth]=Frame{child.value, ..}; depth++;},1=>{return squid_error::Error.invalid_artifact;},2=>{},_=>{abort("invalid traversal color");} } }
            else { scratch.colors[top.vertex]=2; depth--; }
        }
    } return squid_error::Error.none;
}
// Role codes are local scratch labels, not a serialized enum.
let role_type: u8=1; let role_symbol: u8=2; let role_row_variable: u8=3; let role_row: u8=4; let role_count: u8=5; let role_node: u8=6; let role_binding: u8=7; let role_pattern: u8=8; let role_constructor: u8=9; let role_projection: u8=10; let role_destination: u8=11;
fn mark(roles: u8[:],start: u32,len: u32,role: u8) -> Error { { let propagated_error = range(roles.len,start,len); if propagated_error != squid_error::Error.none { return propagated_error; } } for &slot in roles[start..start+len] { { let propagated_error = require(slot == 0 || slot == role); if propagated_error != squid_error::Error.none { return propagated_error; } } slot=role; } return squid_error::Error.none; }
fn markScheme(roles: u8[:],scheme: squid_check_types::Scheme) -> Error { { let propagated_error = mark(roles,scheme.variables.start,scheme.variables.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(roles,scheme.row_variables.start,scheme.row_variables.len,role_row_variable); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(roles,scheme.closed_rows.start,scheme.closed_rows.len,role_row_variable); if propagated_error != squid_error::Error.none { return propagated_error; } } return mark(roles,scheme.generative.start,scheme.generative.len,role_type); }
fn listRoles(m: const Module&,type_roles: u8[:],core_roles: u8[:]) -> Error {
    for &role in type_roles { role=0; } for &role in core_roles { role=0; }
    for n in m.types.nodes { match n.tag {
        forall,existential=>{{ let propagated_error = mark(type_roles,n.b,n.c,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } }}, product=>{{ let propagated_error = mark(type_roles,n.a,n.b,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } }},
        record=>{for i in 0..n.b{{ let propagated_error = mark(type_roles,n.a+i*2,1,role_symbol); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,n.a+i*2+1,1,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } }}},
        nominal,projection,instance_selection=>{{ let propagated_error = mark(type_roles,n.c,1,role_count); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,n.c+1,m.types.extra[n.c],role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } if n.tag == squid_check_types::Tag.projection {{ let propagated_error = mark(type_roles,n.c+1+m.types.extra[n.c],1,role_symbol); if propagated_error != squid_error::Error.none { return propagated_error; } }}},_=>{}
    } }
    for o in m.types.operations { { let propagated_error = mark(type_roles,o.arguments.start,o.arguments.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for b in m.bindings { { let propagated_error = markScheme(type_roles,b.scheme); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,b.public_variables.start,b.public_variables.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,b.public_rows.start,b.public_rows.len,role_row_variable); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for b in m.bodies { { let propagated_error = markScheme(type_roles,b.scheme); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,b.closed_rows.start,b.closed_rows.len,role_row_variable); if propagated_error != squid_error::Error.none { return propagated_error; } } } for c in m.constructors { { let propagated_error = markScheme(type_roles,c.scheme); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for c in m.contracts { { let propagated_error = mark(type_roles,c.parameters.start,c.parameters.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,c.variables.start,c.variables.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,c.row_variables.start,c.row_variables.len,role_row_variable); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,c.row_parameters.start,c.row_parameters.len,role_row); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,c.row_parameter_names.start,c.row_parameter_names.len,role_symbol); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for i in m.implementations { { let propagated_error = mark(type_roles,i.head.start,i.head.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.variables.start,i.variables.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.parameter_names.start,i.parameter_names.len,role_symbol); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.row_variables.start,i.row_variables.len,role_row_variable); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.row_parameters.start,i.row_parameters.len,role_row); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,i.row_parameter_names.start,i.row_parameter_names.len,role_symbol); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for t in m.member_templates { { let propagated_error = mark(type_roles,t.arguments.start,t.arguments.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for n in m.nominals { { let propagated_error = mark(type_roles,n.parameters.start,n.parameters.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,n.variables.start,n.variables.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(core_roles,n.constructors.start,n.constructors.len,role_constructor); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for o in m.operation_names { { let propagated_error = mark(type_roles,o.variables.start,o.variables.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(type_roles,o.parameters.start,o.parameters.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for c in m.closures { { let propagated_error = mark(type_roles,c.closed_rows.start,c.closed_rows.len,role_row_variable); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(core_roles,c.captures.start,c.captures.len,role_binding); if propagated_error != squid_error::Error.none { return propagated_error; } } } for s in m.sparks { { let propagated_error = mark(core_roles,s.captures.start,s.captures.len,role_binding); if propagated_error != squid_error::Error.none { return propagated_error; } } } for o in m.operation_values { { let propagated_error = mark(type_roles,o.arguments.start,o.arguments.len,role_type); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for n in m.nodes { match n.tag {
        block_,suite,product,array,array_op,storage=>{{ let propagated_error = mark(core_roles,n.a,n.b,role_node); if propagated_error != squid_error::Error.none { return propagated_error; } }},
        record=>{{ let propagated_error = mark(core_roles,n.a,n.b,role_node); if propagated_error != squid_error::Error.none { return propagated_error; } } { let propagated_error = mark(core_roles,n.c,n.b,role_destination); if propagated_error != squid_error::Error.none { return propagated_error; } }}, call,break_,with_handle=>{{ let propagated_error = mark(core_roles,n.b,n.c,role_node); if propagated_error != squid_error::Error.none { return propagated_error; } }},
        comptime_for=>{{ let propagated_error = mark(core_roles,n.c,3,role_count); if propagated_error != squid_error::Error.none { return propagated_error; } }},_=>{}
    } }
    for p in m.patterns { if p.tag == squid_check_core::PatternTag.product { { let propagated_error = mark(core_roles,p.a,p.b,role_pattern); if propagated_error != squid_error::Error.none { return propagated_error; } } } } for p in m.pattern_rows { { let propagated_error = mark(core_roles,p.patterns.start,p.patterns.len,role_pattern); if propagated_error != squid_error::Error.none { return propagated_error; } } }
    for v in m.matches { { let propagated_error = mark(core_roles,v.inputs.start,v.inputs.len,role_node); if propagated_error != squid_error::Error.none { return propagated_error; } } } for u in m.updates { { let propagated_error = mark(core_roles,u.path.start,u.path.len,role_projection); if propagated_error != squid_error::Error.none { return propagated_error; } } } return squid_error::Error.none;
}
