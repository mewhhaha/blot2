// Retained staged values remain tied to their checked source owners.
namespace blot_check_staging_snapshot;
import backend.runtime_ir;
import check.core;
import check.effects;
import check.typed_staging;
import check.types;
import eval.core_eval;
import eval.type_evidence;
import support.error;
import support.option;

import eval.eval_values;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Snapshot = blot_eval_core_eval::Snapshot;
type Closure = blot_eval_core_eval::ClosureValue;
type Tag = blot_eval_type_evidence::Tag;
type Kind = blot_eval_core_eval::ValueKind;
struct Nominal { unit: u32, index: u32 }
fn require(value: bool) -> Error { if !value { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
fn failure(err: Error) -> Error { if err == blot_error::Error.out_of_memory { return err; } return blot_error::Error.invalid_artifact; }
struct Shapes<Units> {
    units: Units,
    snapshot: const Snapshot&,
    store: blot_eval_type_evidence::Store&,
    imported: u32[:],
    remaining: i64 = 1000000,
    formal: blot_support::Option<u32>   = blot_support::none<u32>()
}
fn step(self_: Shapes&, depth: i64) -> Error { if depth >= 128 || self_.remaining == 0 { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; return blot_error::Error.none; }
fn nominal(self_: Shapes&, unit: u32, decl: u32, arguments: i64) -> Nominal, Error {
    if unit == 0 || unit > self_.units.len || decl == 0 { return default<Nominal>(), blot_error::Error.invalid_artifact; } let module .= self_.units[unit - 1].core; var found = blot_support::none<u32>();
    for family, index in module.nominals { let err = self_.step(0); if err != blot_error::Error.none { return default<Nominal>(), err; } if family.identity.decl != decl || (family.identity.unit != 0 && family.identity.unit != unit) { continue; }
        if found.present || family.parameters.len != arguments { return default<Nominal>(), blot_error::Error.invalid_artifact; } found = blot_support::some(index as u32);
    } if !found.present { return default<Nominal>(), blot_error::Error.invalid_artifact; } return Nominal { unit, found.value , ..}, blot_error::Error.none;
}
fn row(self_: Shapes&, id: u32, depth: i64) -> u32, Error {
    let err = self_.step(depth); if err != blot_error::Error.none { return 0, err; } var labels: u32[>..<]; let view = self_.snapshot.evidence.view().effects;
    for label in view.rowLabels(id) { let operation = view.operation(label); if operation.instance.unit == 0 && operation.instance.decl != 0 { return 0, blot_error::Error.invalid_artifact; } var arguments: u32[>..<];
        for argument in view.operationArguments(label) { let imported, err = self_.evidence(argument, depth + 1); if err != blot_error::Error.none { return 0, err; } arguments.append(imported); }
        let imported, err = self_.store.effects.internOperationInstance(operation.identity, arguments, operation.instance); if err != blot_error::Error.none { return 0, failure(err); } labels.append(imported);
    } let result, err = self_.store.effects.internRow(labels); if err != blot_error::Error.none { return 0, failure(err); } return result, blot_error::Error.none;
}
fn evidence(self_: Shapes&, id: u32, depth: i64) -> u32, Error {
    let err = self_.step(depth); if err != blot_error::Error.none { return 0, err; } if id == 0 || id >= self_.imported.len { return 0, blot_error::Error.invalid_artifact; }
    let view = self_.snapshot.evidence.view(); let n = view.node(id);
    if n.tag == blot_eval_type_evidence::Tag.bound && (!self_.formal.present || n.a >= self_.formal.value || n.b != 0 || n.c != 0) { return 0, blot_error::Error.invalid_artifact; }
    if self_.imported[id] != 0 { return self_.imported[id], blot_error::Error.none; } var result: u32 = 0;
    match n.tag {
        unit, boolean, unsigned32, floating32, never => { result = id; },
        bound => { let value, err = self_.store.intern(blot_eval_type_evidence::Tag.bound, n.a, 0, []); if err != blot_error::Error.none { return 0, failure(err); } result = value; },
        existential => { if self_.formal.present { return 0, blot_error::Error.invalid_artifact; } self_.formal = blot_support::some(n.b); let body, err = self_.evidence(n.a, depth + 1); self_.formal = blot_support::none<u32>(); if err != blot_error::Error.none { return 0, err; } let value, err = self_.store.intern(blot_eval_type_evidence::Tag.existential, body, n.b, []); if err != blot_error::Error.none { return 0, failure(err); } result = value; },
        function => { let a, err = self_.evidence(n.a, depth + 1); if err != blot_error::Error.none { return 0, err; } let b, err = self_.evidence(n.b, depth + 1); if err != blot_error::Error.none { return 0, err; } let row, err = self_.row(n.c, depth + 1); if err != blot_error::Error.none { return 0, err; } let value, err = self_.store.internWithEffects(n.tag, a, b, row, []); if err != blot_error::Error.none { return 0, failure(err); } result = value; },
        array, list => { let child, err = self_.evidence(n.a, depth + 1); if err != blot_error::Error.none { return 0, err; } let value, err = self_.store.intern(n.tag, child, 0, []); if err != blot_error::Error.none { return 0, failure(err); } result = value; },
        product, record, nominal => { if n.tag == blot_eval_type_evidence::Tag.nominal && !blot_check_typed_staging::isIdentity(n.a, n.b) { let owner, err = self_.nominal(n.a, n.b, view.children(id).len); if err != blot_error::Error.none { return 0, err; } }
            var children: u32[>..<]; for child, index in view.children(id) { if n.tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 { children.append(child); } else { let value, err = self_.evidence(child, depth + 1); if err != blot_error::Error.none { return 0, err; } children.append(value); } }
            var a: u32 = 0; var b: u32 = 0; if n.tag == blot_eval_type_evidence::Tag.nominal { a = n.a; b = n.b; } let value, err = self_.store.intern(n.tag, a, b, children); if err != blot_error::Error.none { return 0, failure(err); } result = value;
        },
        _ => { return 0, blot_error::Error.invalid_artifact; },
    } self_.imported[id] = result; return result, blot_error::Error.none;
}
fn admitted(self_: Shapes&, id: u32, depth: i64) -> Error {
    let err = self_.step(depth); if err != blot_error::Error.none { return err; } let n = self_.store.node(id);
    match n.tag {
        unit, boolean, unsigned32, floating32, never => {},
        existential => { let err = self_.store.view().body(n.a, self_.store.children(id), depth + 1, self_.remaining, null); if err != blot_error::Error.none { return failure(err); } },
        array, list => { let err = self_.admitted(n.a, depth + 1); if err != blot_error::Error.none { return err; } },
        function => { let err = self_.admitted(n.a, depth + 1); if err != blot_error::Error.none { return err; } let err = self_.admitted(n.b, depth + 1); if err != blot_error::Error.none { return err; } },
        product, record, nominal => { if n.tag == blot_eval_type_evidence::Tag.nominal && !blot_check_typed_staging::isIdentity(n.a, n.b) { let owner, err = self_.nominal(n.a, n.b, self_.store.children(id).len); if err != blot_error::Error.none { return err; } } for child, index in self_.store.children(id) { if n.tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 { continue; } let err = self_.admitted(child, depth + 1); if err != blot_error::Error.none { return err; } } },
        _ => { return blot_error::Error.invalid_artifact; },
    }
    if n.tag == blot_eval_type_evidence::Tag.function { for label in self_.store.effects.view().rowLabels(n.c) { let operation = self_.store.effects.view().operation(label); if operation.instance.unit == 0 && operation.instance.decl != 0 { return blot_error::Error.invalid_artifact; } for argument in self_.store.effects.view().operationArguments(label) { let err = self_.admitted(argument, depth + 1); if err != blot_error::Error.none { return err; } } } } return blot_error::Error.none;
}
fn source(self_: Shapes&, producer: const Module&, closure: Closure, ty: u32) -> u32, Error {
    var mappings: blot_eval_type_evidence::Mapping[>..<]; var rows: blot_eval_type_evidence::RowMapping[>..<];
    for mapping in self_.snapshot.type_mappings[closure.mappings.start..closure.mappings.start + closure.mappings.len] { if mapping.variable >= producer.types.nodes.len { return 0, blot_error::Error.invalid_artifact; } let node = producer.types.node(mapping.variable);
        if node.tag != blot_check_types::Tag.variable && !(node.tag == blot_check_types::Tag.bound && node.b == 0 && node.c == 0) { continue; } for prior in mappings { if prior.variable == mapping.variable { return 0, blot_error::Error.invalid_artifact; } }
        let value, err = self_.evidence(mapping.evidence, 0); if err != blot_error::Error.none { return 0, err; } mappings.push(blot_eval_type_evidence::Mapping { mapping.variable, value , ..});
    }
    for mapping in self_.snapshot.row_mappings[closure.row_mappings.start..closure.row_mappings.start + closure.row_mappings.len] { for prior in rows { if prior.variable == mapping.variable { return 0, blot_error::Error.invalid_artifact; } } let value, err = self_.row(mapping.evidence, 0); if err != blot_error::Error.none { return 0, err; } rows.push(blot_eval_type_evidence::RowMapping { mapping.variable, value , ..}); }
    let result, err = self_.store.projectWithBudget(producer.types, ty, mappings, rows, self_.remaining); if err != blot_error::Error.none { return 0, failure(err); } let err = self_.admitted(result, 0); return result, err;
}
fn value(self_: Shapes&, id: u32, expected: u32, depth: i64) -> Error {
    let err = self_.step(depth); if err != blot_error::Error.none { return err; } let value = self_.snapshot.values[id]; let shape = self_.store.node(expected); let children = self_.snapshot.children[value.start..value.start + value.len];
    match shape.tag {
        unit, boolean, unsigned32, floating32 => { if value.kind != blot_eval_eval_values::ValueKind.scalar || children.len != 0 || value.nominal != 0 { return blot_error::Error.invalid_artifact; } var scalar = blot_backend_runtime_ir::SC_unit; if shape.tag == blot_eval_type_evidence::Tag.boolean { scalar = blot_backend_runtime_ir::SC_bool; } if shape.tag == blot_eval_type_evidence::Tag.unsigned32 { scalar = blot_backend_runtime_ir::SC_u32; } if shape.tag == blot_eval_type_evidence::Tag.floating32 { scalar = blot_backend_runtime_ir::SC_f32; } if value.scalar != scalar || (shape.tag == blot_eval_type_evidence::Tag.unit && value.bits != 0) || (shape.tag == blot_eval_type_evidence::Tag.boolean && value.bits > 1) { return blot_error::Error.invalid_artifact; } },
        product => { if value.kind != blot_eval_eval_values::ValueKind.product { return blot_error::Error.invalid_artifact; } let types = self_.store.children(expected); if children.len != types.len { return blot_error::Error.invalid_artifact; } for child, index in children { if child >= id { return blot_error::Error.invalid_artifact; } let err = self_.value(child, types[index], depth + 1); if err != blot_error::Error.none { return err; } } },
        record => { if value.kind != blot_eval_eval_values::ValueKind.record { return blot_error::Error.invalid_artifact; } let types = self_.store.children(expected); let layout = self_.snapshot.record_layouts[self_.snapshot.value_records[id]]; let names = self_.snapshot.field_names[layout.start..layout.start + layout.len]; if children.len != types.len / 2 || names.len != children.len { return blot_error::Error.invalid_artifact; }
            for child, index in children { var field = blot_support::none<u32>(); for i in 0..types.len / 2 { if types[i * 2] == names[index] { field = blot_support::some(types[i * 2 + 1]); break; } } if !field.present || child >= id { return blot_error::Error.invalid_artifact; } let err = self_.value(child, field.value, depth + 1); if err != blot_error::Error.none { return err; } for prior in names[..index] { if prior == names[index] { return blot_error::Error.invalid_artifact; } } }
        },
        array, list => { if !((shape.tag == blot_eval_type_evidence::Tag.array && value.kind == blot_eval_eval_values::ValueKind.array) || (shape.tag == blot_eval_type_evidence::Tag.list && value.kind == blot_eval_eval_values::ValueKind.list)) { return blot_error::Error.invalid_artifact; } for child in children { if child >= id { return blot_error::Error.invalid_artifact; } let err = self_.value(child, shape.a, depth + 1); if err != blot_error::Error.none { return err; } } },
        nominal => {
            if blot_check_typed_staging::isIdentity(shape.a, shape.b) { if shape.b != blot_check_typed_staging::code_identity.decl || value.kind != blot_eval_eval_values::ValueKind.code { return blot_error::Error.invalid_artifact; } let closure = self_.snapshot.closures[value.bits]; if closure.unit == 0 || closure.unit > self_.units.len { return blot_error::Error.invalid_artifact; } let projected, err = self_.source(self_.units[closure.unit - 1].core, closure, closure.ty); if err != blot_error::Error.none { return err; } if expected != projected { return blot_error::Error.invalid_artifact; } }
            else {
                if value.kind != blot_eval_eval_values::ValueKind.nominal || value.nominal != ((shape.a as u64) << 32 | shape.b) { return blot_error::Error.invalid_artifact; } let owner, err = self_.nominal(shape.a, shape.b, self_.store.children(expected).len); if err != blot_error::Error.none { return err; } let family = self_.units[owner.unit - 1].core.nominals[owner.index]; if value.bits >= family.constructors.len { return blot_error::Error.invalid_artifact; }
                let constructor = self_.units[owner.unit - 1].core.constructors[self_.units[owner.unit - 1].core.nominalConstructors(owner.index)[value.bits]]; if constructor.nominal != owner.index || constructor.tag != value.bits || constructor.scheme.obligations.len != 0 || constructor.scheme.row_variables.len != 0 || constructor.scheme.generative.len != 0 { return blot_error::Error.invalid_artifact; }
                var result_type = constructor.scheme.root; var parameter_type: u32 = 0; var payload_count: i64 = 0;
                if constructor.payload != 0 { payload_count = 1; let arrow = self_.units[owner.unit - 1].core.types.node(result_type); if arrow.tag != blot_check_types::Tag.function { return blot_error::Error.invalid_artifact; } let row = self_.units[owner.unit - 1].core.types.effects.node(arrow.c); if row.labels.len != 0 || row.tail != blot_check_effects::Tail.closed { return blot_error::Error.invalid_artifact; } parameter_type = arrow.a; result_type = arrow.b; }
                if children.len != payload_count { return blot_error::Error.invalid_artifact; } var mappings: blot_eval_type_evidence::Mapping[>..<]; var rows: blot_eval_type_evidence::RowMapping[>..<]; let matched, err = self_.store.matchWithRowsBudget(self_.units[owner.unit - 1].core.types, result_type, expected, mappings, rows, self_.remaining); if err != blot_error::Error.none { return failure(err); } if !matched || rows.len != 0 { return blot_error::Error.invalid_artifact; }
                for mapping in mappings { var variable = false; for v in self_.units[owner.unit - 1].core.types.list(constructor.scheme.variables) { if v == mapping.variable { variable = true; break; } } if !variable { return blot_error::Error.invalid_artifact; } variable = false; for v in self_.units[owner.unit - 1].core.types.list(family.variables) { if v == mapping.variable { variable = true; break; } } if !variable { return blot_error::Error.invalid_artifact; } }
                let projected, err = self_.store.projectWithBudget(self_.units[owner.unit - 1].core.types, result_type, mappings, rows, self_.remaining); if err != blot_error::Error.none { return failure(err); } if expected != projected { return blot_error::Error.invalid_artifact; }
                if constructor.payload != 0 { let payload, err = self_.store.projectWithBudget(self_.units[owner.unit - 1].core.types, constructor.payload, mappings, rows, self_.remaining); if err != blot_error::Error.none { return failure(err); } let parameter, err = self_.store.projectWithBudget(self_.units[owner.unit - 1].core.types, parameter_type, mappings, rows, self_.remaining); if err != blot_error::Error.none { return failure(err); } let storage = self_.store.node(payload);
                    if family.is_opaque { if parameter != payload { return blot_error::Error.invalid_artifact; } } else if storage.tag == blot_eval_type_evidence::Tag.record { let fields = self_.store.children(payload); if fields.len == 2 { if parameter != fields[1] { return blot_error::Error.invalid_artifact; } } else { if self_.store.node(parameter).tag != blot_eval_type_evidence::Tag.product { return blot_error::Error.invalid_artifact; } let parts = self_.store.children(parameter); if parts.len != fields.len / 2 { return blot_error::Error.invalid_artifact; } for part, index in parts { if part != fields[index * 2 + 1] { return blot_error::Error.invalid_artifact; } } } } else if parameter != payload { return blot_error::Error.invalid_artifact; }
                    let err = self_.admitted(payload, depth + 1); if err != blot_error::Error.none { return err; } if children[0] >= id { return blot_error::Error.invalid_artifact; } let err = self_.value(children[0], payload, depth + 1); if err != blot_error::Error.none { return err; }
                }
            }
        },
        _ => { return blot_error::Error.invalid_artifact; },
    }
    if self_.snapshot.value_evidence[id] != 0 { let actual, err = self_.evidence(self_.snapshot.value_evidence[id], 0); if err != blot_error::Error.none { return err; } if expected != actual { return blot_error::Error.invalid_artifact; } } return blot_error::Error.none;
}
struct Context<Units> { units: Units, snapshot: const Snapshot& }
fn withShapes(context: Context&, store: blot_eval_type_evidence::Store&) -> Error {
    let snapshot .= context.snapshot; var imported: u32[>..<]; imported.resize(snapshot.evidence.nodes.len); for &value in imported { value = 0; }
    var shapes = Shapes { units: context.units, snapshot: snapshot, store: store, imported: imported , ..}; let evidence = snapshot.evidence.view();
    for value, id in snapshot.values {
        if value.kind == blot_eval_eval_values::ValueKind.descriptor { if value.nominal == 0 || value.nominal >= evidence.nodes.len || value.len != 0 || value.bits != 0 { return blot_error::Error.invalid_artifact; } if snapshot.value_evidence[id] != 0 { let ty = evidence.node(snapshot.value_evidence[id]); if ty.tag != blot_eval_type_evidence::Tag.nominal || ty.a != blot_check_typed_staging::descriptor_identity.unit || ty.b != blot_check_typed_staging::descriptor_identity.decl { return blot_error::Error.invalid_artifact; } let args = evidence.children(snapshot.value_evidence[id]); if args.len != 1 || args[0] != value.nominal { return blot_error::Error.invalid_artifact; } } let imported, err = shapes.evidence(value.nominal as u32, 0); if err != blot_error::Error.none { return err; } }
        if value.kind != blot_eval_eval_values::ValueKind.code { continue; } if value.bits >= snapshot.closures.len { return blot_error::Error.invalid_artifact; } let closure = snapshot.closures[value.bits];
        if closure.unit == 0 || closure.unit > context.units.len || closure.origin != blot_eval_eval_values::ClosureOrigin.anonymous || closure.applied != 0 || closure.staged != 0 { return blot_error::Error.invalid_artifact; } let producer .= context.units[closure.unit - 1].core;
        if closure.identity == 0 || closure.identity >= producer.nodes.len || value.nominal != closure.identity || closure.ty >= producer.types.nodes.len || !blot_check_typed_staging::codeInfo(producer.types, closure.ty).present { return blot_error::Error.invalid_artifact; }
        var introduced = false; for node in producer.nodes { if node.tag == blot_check_core::Tag.staging && node.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.quote) && node.a == closure.identity && node.ty == closure.ty { introduced = true; break; } } if !introduced { return blot_error::Error.invalid_artifact; }
        if snapshot.value_evidence[id] != 0 { let ty = evidence.node(snapshot.value_evidence[id]); if ty.tag != blot_eval_type_evidence::Tag.nominal || ty.a != blot_check_typed_staging::code_identity.unit || ty.b != blot_check_typed_staging::code_identity.decl { return blot_error::Error.invalid_artifact; } let args = evidence.children(snapshot.value_evidence[id]); if args.len != 2 { return blot_error::Error.invalid_artifact; } let latent = evidence.node(args[1]); if latent.tag != blot_eval_type_evidence::Tag.function || latent.a != blot_check_types::unit || latent.b != blot_check_types::unit { return blot_error::Error.invalid_artifact; } }
        let expected, err = shapes.source(producer, closure, closure.ty); if err != blot_error::Error.none { return err; } if snapshot.value_evidence[id] != 0 { let actual, err = shapes.evidence(snapshot.value_evidence[id], 0); if err != blot_error::Error.none { return err; } if expected != actual { return blot_error::Error.invalid_artifact; } }
        let children = snapshot.children[value.start..value.start + value.len]; for child, ordinal in children { let replacement = snapshot.values[child]; if child >= id || replacement.kind != blot_eval_eval_values::ValueKind.staged_value || replacement.nominal == 0 || replacement.nominal >= producer.nodes.len || replacement.len != 1 { return blot_error::Error.invalid_artifact; } let node = producer.nodes[replacement.nominal as u32]; if node.tag != blot_check_core::Tag.staging || node.c != replacement.bits || (node.c != blot_check_typed_staging::opCode(blot_check_typed_staging::Op.lift) && node.c != blot_check_typed_staging::opCode(blot_check_typed_staging::Op.splice)) { return blot_error::Error.invalid_artifact; } for previous in children[..ordinal] { if snapshot.values[previous].nominal == replacement.nominal { return blot_error::Error.invalid_artifact; } }
            let payload = snapshot.children[replacement.start]; if payload >= child { return blot_error::Error.invalid_artifact; } var payload_type = node.ty; if node.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.splice) { payload_type = producer.typeOf(node.a); } let expected, err = shapes.source(producer, closure, payload_type); if err != blot_error::Error.none { return err; } let err = shapes.value(payload, expected, 0); if err != blot_error::Error.none { return err; }
        }
    } return blot_error::Error.none;
}
fn validate(snapshot: const Snapshot&, units) -> Error {
    var previous: u32 = 0; for origin in snapshot.code_origins { if origin.value == 0 || origin.value <= previous || origin.value >= snapshot.values.len || snapshot.values[origin.value].kind != blot_eval_eval_values::ValueKind.code || origin.generator.unit == 0 || origin.generator.unit > units.len { return blot_error::Error.invalid_artifact; } let owner .= units[origin.generator.unit - 1].core; if origin.generator.node == 0 || origin.generator.node >= owner.nodes.len || origin.generator.node >= owner.spans.len { return blot_error::Error.invalid_artifact; } previous = origin.value; }
    for closure in snapshot.closures { if closure.staged >= snapshot.values.len || (closure.staged != 0 && snapshot.values[closure.staged].kind != blot_eval_eval_values::ValueKind.code) { return blot_error::Error.invalid_artifact; } }
    var staged = false; for value in snapshot.values { if value.kind == blot_eval_eval_values::ValueKind.code || value.kind == blot_eval_eval_values::ValueKind.descriptor { staged = true; break; } } if !staged { return blot_error::Error.none; }
    var context = Context { units, snapshot , ..}; return blot_eval_type_evidence::withStore<Context>(context,withShapes);
}
