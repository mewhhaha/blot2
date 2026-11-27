// Frozen sources contain no substitutions, cursors, caches or caller evidence.
namespace squid_check_frozen_types;
import support.option;

import check.effects;
import check.parameter_patterns;
import check.types;

struct Graph {
    nodes: const squid_check_types::Node[:], extra: const squid_check_types::Id[:],
    rows: const squid_check_effects::Row[:], labels: const squid_check_effects::Label[:],
    operations: const squid_check_types::Operation[:], row_variable_count: u32,
}
enum Source { inactive, store { lease:u32,generation:u64 }, frozen { value: Graph } }
// Reader keys keep observation authority without retaining mutation-capable headers.
fn fromStore(store:const squid_check_types::Store&)->Source {let canonical=squid_check_types::checkedView(store);return Source.store{lease:canonical.lease,generation:canonical.owner_generation};}
fn validSource(source:Source)->bool {match source {inactive=>{return false;},store key=>{return squid_check_types::validLease(key.lease,key.generation);},frozen=>{return true;},}}
fn fromPatterns(store:squid_check_parameter_patterns::Store)->Patterns {let canonical=squid_check_parameter_patterns::checkedView(store);return Patterns.store{lease:canonical.lease,generation:canonical.generation};}
fn validPatterns(source:Patterns)->bool {match source {inactive=>{return false;},store key=>{return squid_check_parameter_patterns::validLease(key.lease,key.generation);},frozen=>{return true;},}}
fn head(self_: Source, id: squid_check_types::Id, at: squid_check_types::Cursor) -> squid_check_types::Id {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.head(id, at); }, frozen => { return id; }, }
}
fn node(self_: Source, id: squid_check_types::Id) -> squid_check_types::Node {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.node(id); }, frozen s => { return s.value.nodes[id]; }, }
}
fn list(self_: Source, span: squid_check_types::List) -> const squid_check_types::Id[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.extra.items[span.start..span.start + span.len]; }, frozen s => { return s.value.extra[span.start..span.start + span.len]; }, }
}
fn nominalArguments(self_: Source, value: squid_check_types::Node) -> const squid_check_types::Id[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); },
        store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.nominalArguments(value); },
        frozen s => { return s.value.extra[value.c + 1..value.c + 1 + s.value.extra[value.c]]; },
    }
}
fn projectionMember(self_: Source, value: squid_check_types::Node) -> u32 {
    return list(self_, squid_check_types::List { value.c + 1 + nominalArguments(self_, value).len as u32, 1 , ..})[0];
}
fn recordField(self_: Source, value: squid_check_types::Node, index: i64) -> squid_check_types::Field {
    match self_ { inactive => { abort("inactive frozen source descriptor"); },
        store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.recordField(value, index); },
        frozen s => { return squid_check_types::Field { s.value.extra[value.a + index * 2], s.value.extra[value.a + index * 2 + 1] , ..}; },
    }
}
fn operationCount(self_: Source) -> i64 {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.operations.len; }, frozen s => { return s.value.operations.len; }, }
}
fn operation(self_: Source, id: squid_check_effects::Label) -> squid_check_types::Operation {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.operations.items[id]; }, frozen s => { return s.value.operations[id]; }, }
}
fn row(self_: Source, id: squid_check_effects::Id) -> squid_check_effects::Row {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.effects.node(id); }, frozen s => { return s.value.rows[id]; }, }
}
fn rowLabels(self_: Source, span: squid_check_effects::List) -> const squid_check_effects::Label[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view:const squid_check_types::Store& =squid_check_types::canonical(s.lease,s.generation);return view.effects.list(span); }, frozen s => { return s.value.labels[span.start..span.start + span.len]; }, }
}
struct PatternGraph { nodes: const squid_check_parameter_patterns::Node[:], extra: const u32[:] }
enum Patterns { inactive, store { lease:u32,generation:u64 }, frozen { value: PatternGraph } }
fn node(self_: Patterns, id: squid_check_parameter_patterns::Id) -> squid_check_parameter_patterns::Node {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view=squid_check_parameter_patterns::canonical(s.lease,s.generation);return view.node(id); }, frozen s => { return s.value.nodes[id]; }, }
}
fn list(self_: Patterns, span: squid_check_parameter_patterns::List) -> const squid_check_parameter_patterns::Id[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { let view=squid_check_parameter_patterns::canonical(s.lease,s.generation);return view.extra().items[span.start..span.start + span.len]; }, frozen s => { return s.value.extra[span.start..span.start + span.len]; }, }
}
fn field(self_: Patterns, value: squid_check_parameter_patterns::Node, index: i64) -> squid_check_parameter_patterns::Field {
    match self_ { inactive => { abort("inactive frozen source descriptor"); },
        store s => { let view=squid_check_parameter_patterns::canonical(s.lease,s.generation);return view.field(value, index); },
        frozen s => { return squid_check_parameter_patterns::Field { s.value.extra[value.a + index * 2], s.value.extra[value.a + index * 2 + 1] , ..}; },
    }
}

fn rowLabels(self_: Source, id: squid_check_effects::Id) -> const squid_check_effects::Label[:] { return self_.rowLabels(self_.row(id).labels); }

fn sameStorage(left:Graph,right:Graph)->bool {if left.nodes.len==0 || right.nodes.len==0 {return false;}return squid_support::same_slice_identity(left.nodes,right.nodes) && squid_support::same_slice_identity(left.extra,right.extra) && squid_support::same_slice_identity(left.rows,right.rows) && squid_support::same_slice_identity(left.labels,right.labels) && squid_support::same_slice_identity(left.operations,right.operations) && left.row_variable_count==right.row_variable_count;}
fn sameStorage(left:PatternGraph,right:PatternGraph)->bool {if left.nodes.len==0 || right.nodes.len==0 {return false;}return squid_support::same_slice_identity(left.nodes,right.nodes) && squid_support::same_slice_identity(left.extra,right.extra);}
