// Frozen sources contain no substitutions, cursors, caches or caller evidence.
namespace blot_check_frozen_types;
import support.option;

import check.effects;
import check.parameter_patterns;
import check.quantifier_goals;
import check.types;

struct Graph {
    nodes: const blot_check_types::Node[:], extra: const blot_check_types::Id[:],
    rows: const blot_check_effects::Row[:], labels: const blot_check_effects::Label[:],
    operations: const blot_check_types::Operation[:], row_variable_count: u32,
    quantifier_goals: const blot_check_types::QuantifierGoals[:],
    quantifier_obligations: const blot_check_types::Obligation[:],
}
enum Source { inactive, store { value: const blot_check_types::Store& }, frozen { value: Graph } }
fn quantifierGoals(self_: Source, owner: blot_check_types::Id) -> const blot_check_types::Obligation[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); },
        store s => { return s.value.quantifierGoals(owner); },
        frozen s => { return blot_check_quantifier_goals::get(s.value.quantifier_goals, s.value.quantifier_obligations, owner); },
    }
}
fn head(self_: Source, id: blot_check_types::Id, at: blot_check_types::Cursor) -> blot_check_types::Id {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.head(id, at); }, frozen => { return id; }, }
}
fn node(self_: Source, id: blot_check_types::Id) -> blot_check_types::Node {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.node(id); }, frozen s => { return s.value.nodes[id]; }, }
}
fn list(self_: Source, span: blot_check_types::List) -> const blot_check_types::Id[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.extra.items[span.start..span.start + span.len]; }, frozen s => { return s.value.extra[span.start..span.start + span.len]; }, }
}
fn nominalArguments(self_: Source, value: blot_check_types::Node) -> const blot_check_types::Id[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); },
        store s => { return s.value.nominalArguments(value); },
        frozen s => { return s.value.extra[value.c + 1..value.c + 1 + s.value.extra[value.c]]; },
    }
}
fn projectionMember(self_: Source, value: blot_check_types::Node) -> u32 {
    return list(self_, blot_check_types::List { value.c + 1 + nominalArguments(self_, value).len as u32, 1 , ..})[0];
}
fn recordField(self_: Source, value: blot_check_types::Node, index: i64) -> blot_check_types::Field {
    match self_ { inactive => { abort("inactive frozen source descriptor"); },
        store s => { return s.value.recordField(value, index); },
        frozen s => { return blot_check_types::Field { s.value.extra[value.a + index * 2], s.value.extra[value.a + index * 2 + 1] , ..}; },
    }
}
fn operationCount(self_: Source) -> i64 {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.operations.len; }, frozen s => { return s.value.operations.len; }, }
}
fn operation(self_: Source, id: blot_check_effects::Label) -> blot_check_types::Operation {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.operations.items[id]; }, frozen s => { return s.value.operations[id]; }, }
}
fn row(self_: Source, id: blot_check_effects::Id) -> blot_check_effects::Row {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.effects.node(id); }, frozen s => { return s.value.rows[id]; }, }
}
fn rowLabels(self_: Source, span: blot_check_effects::List) -> const blot_check_effects::Label[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.effects.list(span); }, frozen s => { return s.value.labels[span.start..span.start + span.len]; }, }
}
struct PatternGraph { nodes: const blot_check_parameter_patterns::Node[:], extra: const u32[:] }
enum Patterns { inactive, store { value: blot_check_parameter_patterns::Store }, frozen { value: PatternGraph } }
fn node(self_: Patterns, id: blot_check_parameter_patterns::Id) -> blot_check_parameter_patterns::Node {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.node(id); }, frozen s => { return s.value.nodes[id]; }, }
}
fn list(self_: Patterns, span: blot_check_parameter_patterns::List) -> const blot_check_parameter_patterns::Id[:] {
    match self_ { inactive => { abort("inactive frozen source descriptor"); }, store s => { return s.value.extra.items[span.start..span.start + span.len]; }, frozen s => { return s.value.extra[span.start..span.start + span.len]; }, }
}
fn field(self_: Patterns, value: blot_check_parameter_patterns::Node, index: i64) -> blot_check_parameter_patterns::Field {
    match self_ { inactive => { abort("inactive frozen source descriptor"); },
        store s => { return s.value.field(value, index); },
        frozen s => { return blot_check_parameter_patterns::Field { s.value.extra[value.a + index * 2], s.value.extra[value.a + index * 2 + 1] , ..}; },
    }
}

fn rowLabels(self_: Source, id: blot_check_effects::Id) -> const blot_check_effects::Label[:] { return self_.rowLabels(self_.row(id).labels); }

fn sameStorage(left:Graph,right:Graph)->bool {if left.nodes.len==0 || right.nodes.len==0 {return false;}return blot_support::same_slice_identity(left.nodes,right.nodes) && blot_support::same_slice_identity(left.extra,right.extra) && blot_support::same_slice_identity(left.rows,right.rows) && blot_support::same_slice_identity(left.labels,right.labels) && blot_support::same_slice_identity(left.operations,right.operations) && left.row_variable_count==right.row_variable_count && blot_support::same_slice_identity(left.quantifier_goals,right.quantifier_goals) && blot_support::same_slice_identity(left.quantifier_obligations,right.quantifier_obligations);}
fn sameStorage(left:PatternGraph,right:PatternGraph)->bool {if left.nodes.len==0 || right.nodes.len==0 {return false;}return blot_support::same_slice_identity(left.nodes,right.nodes) && blot_support::same_slice_identity(left.extra,right.extra);}
