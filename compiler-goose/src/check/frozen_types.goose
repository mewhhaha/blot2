// Frozen sources contain no substitutions, cursors, caches or caller evidence.
namespace blot_check_frozen_types;
struct Graph {
    nodes: const blot_check_types::Node[:], extra: const blot_check_types::Id[:],
    rows: const blot_check_effects::Row[:], labels: const blot_check_effects::Label[:],
    operations: const blot_check_types::Operation[:], row_variable_count: u32,
    quantifier_goals: const blot_check_types::QuantifierGoals[:],
    quantifier_obligations: const blot_check_types::Obligation[:],
}
enum Source { store { value: const blot_check_types::Store& }, frozen { value: const Graph& } }
fn quantifierGoals(self: Source, owner: blot_check_types::Id) -> const blot_check_types::Obligation[:] {
    match self {
        store s => { return s.value.quantifierGoals(owner); },
        frozen s => { return blot_check_quantifier_goals::get(s.value.quantifier_goals, s.value.quantifier_obligations, owner); },
    }
}
fn head(self: Source, id: blot_check_types::Id, at: blot_check_types::Cursor) -> blot_check_types::Id {
    match self { store s => { return s.value.head(id, at); }, frozen => { return id; } }
}
fn node(self: Source, id: blot_check_types::Id) -> blot_check_types::Node {
    match self { store s => { return s.value.node(id); }, frozen s => { return s.value.nodes[id]; } }
}
fn list(self: Source, span: blot_check_types::List) -> const blot_check_types::Id[:] {
    match self { store s => { return s.value.list(span); }, frozen s => { return s.value.extra[span.start..span.start + span.len]; } }
}
fn nominalArguments(self: Source, value: blot_check_types::Node) -> const blot_check_types::Id[:] {
    match self {
        store s => { return s.value.nominalArguments(value); },
        frozen s => { return s.value.extra[value.c + 1..value.c + 1 + s.value.extra[value.c]]; },
    }
}
fn projectionMember(self: Source, value: blot_check_types::Node) -> u32 {
    return list(self, blot_check_types::List { value.c + 1 + nominalArguments(self, value).len as u32, 1 })[0];
}
fn recordField(self: Source, value: blot_check_types::Node, index: i64) -> blot_check_types::Field {
    match self {
        store s => { return s.value.recordField(value, index); },
        frozen s => { return blot_check_types::Field { s.value.extra[value.a + index * 2], s.value.extra[value.a + index * 2 + 1] }; },
    }
}
fn operationCount(self: Source) -> i64 {
    match self { store s => { return s.value.operations.len; }, frozen s => { return s.value.operations.len; } }
}
fn operation(self: Source, id: blot_check_effects::Label) -> blot_check_types::Operation {
    match self { store s => { return s.value.operations[id]; }, frozen s => { return s.value.operations[id]; } }
}
fn row(self: Source, id: blot_check_effects::Id) -> blot_check_effects::Row {
    match self { store s => { return s.value.effects.node(id); }, frozen s => { return s.value.rows[id]; } }
}
fn rowLabels(self: Source, span: blot_check_effects::List) -> const blot_check_effects::Label[:] {
    match self { store s => { return s.value.effects.list(span); }, frozen s => { return s.value.labels[span.start..span.start + span.len]; } }
}
struct PatternGraph { nodes: const blot_check_parameter_patterns::Node[:], extra: const u32[:] }
enum Patterns { store { value: const blot_check_parameter_patterns::Store& }, frozen { value: const PatternGraph& } }
fn node(self: Patterns, id: blot_check_parameter_patterns::Id) -> blot_check_parameter_patterns::Node {
    match self { store s => { return s.value.node(id); }, frozen s => { return s.value.nodes[id]; } }
}
fn list(self: Patterns, span: blot_check_parameter_patterns::List) -> const blot_check_parameter_patterns::Id[:] {
    match self { store s => { return s.value.list(span); }, frozen s => { return s.value.extra[span.start..span.start + span.len]; } }
}
fn field(self: Patterns, value: blot_check_parameter_patterns::Node, index: i64) -> blot_check_parameter_patterns::Field {
    match self {
        store s => { return s.value.field(value, index); },
        frozen s => { return blot_check_parameter_patterns::Field { s.value.extra[value.a + index * 2], s.value.extra[value.a + index * 2 + 1] }; },
    }
}
