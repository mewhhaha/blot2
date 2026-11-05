// Retained staged values remain tied to their checked source owners.
namespace blot_check_staging_snapshot;
import support.error;
import support.option;
import .core;
import .types;
import .effects;
import .typed_staging;
import eval.core_eval;
import eval.type_evidence;
import eval.eval_values;
import backend.runtime_ir;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Snapshot = blot_eval_core_eval::Snapshot;
type Closure = blot_eval_core_eval::ClosureValue;
type Tag = blot_eval_type_evidence::Tag;
type Kind = blot_eval_core_eval::ValueKind;
struct Nominal { unit: u32, index: u32 }
fn require(value: bool) -> Error { if !value { return Error.invalid_artifact; } return Error.none; }
fn failure(err: Error) -> Error { if err == Error.out_of_memory { return err; } return Error.invalid_artifact; }
struct Shapes<Units> {
    units: Units,
    snapshot: const Snapshot&,
    store: blot_eval_type_evidence::Store&,
    imported: u32[:],
    remaining: i64 = 1000000,
    formal: blot_support::Option<u32> = blot_support::none<u32>()
}
fn step(self: Shapes&, depth: i64) -> Error { if depth >= 128 || self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; return Error.none; }
fn nominal(self: Shapes&, unit: u32, decl: u32, arguments: i64) -> Nominal, Error {
    if unit == 0 || unit > self.units.len || decl == 0 { return default<Nominal>(), Error.invalid_artifact; } let module .= self.units[unit - 1].core; var found = blot_support::none<u32>();
    for family, index in module.nominals { let err = self.step(0); if err != Error.none { return default<Nominal>(), err; } if family.identity.decl != decl || (family.identity.unit != 0 && family.identity.unit != unit) { continue; }
        if found.present || family.parameters.len != arguments { return default<Nominal>(), Error.invalid_artifact; } found = blot_support::some(index as u32);
    } if !found.present { return default<Nominal>(), Error.invalid_artifact; } return Nominal { unit, found.value , ..}, Error.none;
}
fn row(self: Shapes&, id: u32, depth: i64) -> u32, Error {
    let err = self.step(depth); if err != Error.none { return 0, err; } var labels: u32[>..<]; let view = self.snapshot.evidence.view().effects;
    for label in view.rowLabels(id) { let operation = view.operation(label); if operation.instance.unit == 0 && operation.instance.decl != 0 { return 0, Error.invalid_artifact; } var arguments: u32[>..<];
        for argument in view.operationArguments(label) { let imported, err = self.evidence(argument, depth + 1); if err != Error.none { return 0, err; } arguments.append(imported); }
        let imported, err = self.store.effects.internOperationInstance(operation.identity, arguments, operation.instance); if err != Error.none { return 0, failure(err); } labels.append(imported);
    } let result, err = self.store.effects.internRow(labels); if err != Error.none { return 0, failure(err); } return result, Error.none;
}
fn evidence(self: Shapes&, id: u32, depth: i64) -> u32, Error {
    let err = self.step(depth); if err != Error.none { return 0, err; } if id == 0 || id >= self.imported.len { return 0, Error.invalid_artifact; }
    let view = self.snapshot.evidence.view(); let n = view.node(id);
    if n.tag == Tag.bound && (!self.formal.present || n.a >= self.formal.value || n.b != 0 || n.c != 0) { return 0, Error.invalid_artifact; }
    if self.imported[id] != 0 { return self.imported[id], Error.none; } var result: u32 = 0;
    match n.tag {
        Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never => { result = id; },
        Tag.bound => { let value, err = self.store.intern(Tag.bound, n.a, 0, []); if err != Error.none { return 0, failure(err); } result = value; },
        Tag.existential => { if self.formal.present { return 0, Error.invalid_artifact; } self.formal = blot_support::some(n.b); let body, err = self.evidence(n.a, depth + 1); self.formal = blot_support::none<u32>(); if err != Error.none { return 0, err; } let value, err = self.store.intern(Tag.existential, body, n.b, []); if err != Error.none { return 0, failure(err); } result = value; },
        Tag.function => { let a, err = self.evidence(n.a, depth + 1); if err != Error.none { return 0, err; } let b, err = self.evidence(n.b, depth + 1); if err != Error.none { return 0, err; } let row, err = self.row(n.c, depth + 1); if err != Error.none { return 0, err; } let value, err = self.store.internWithEffects(n.tag, a, b, row, []); if err != Error.none { return 0, failure(err); } result = value; },
        Tag.array, Tag.list => { let child, err = self.evidence(n.a, depth + 1); if err != Error.none { return 0, err; } let value, err = self.store.intern(n.tag, child, 0, []); if err != Error.none { return 0, failure(err); } result = value; },
        Tag.product, Tag.record, Tag.nominal => { if n.tag == Tag.nominal && !blot_check_typed_staging::isIdentity(n.a, n.b) { let owner, err = self.nominal(n.a, n.b, view.children(id).len); if err != Error.none { return 0, err; } }
            var children: u32[>..<]; for child, index in view.children(id) { if n.tag == Tag.record && index % 2 == 0 { children.append(child); } else { let value, err = self.evidence(child, depth + 1); if err != Error.none { return 0, err; } children.append(value); } }
            var a: u32 = 0; var b: u32 = 0; if n.tag == Tag.nominal { a = n.a; b = n.b; } let value, err = self.store.intern(n.tag, a, b, children); if err != Error.none { return 0, failure(err); } result = value;
        },
        _ => { return 0, Error.invalid_artifact; },
    } self.imported[id] = result; return result, Error.none;
}
fn admitted(self: Shapes&, id: u32, depth: i64) -> Error {
    let err = self.step(depth); if err != Error.none { return err; } let n = self.store.node(id);
    match n.tag {
        Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never => {},
        Tag.existential => { let err = self.store.view().body(n.a, self.store.children(id), depth + 1, self.remaining, null); if err != Error.none { return failure(err); } },
        Tag.array, Tag.list => { let err = self.admitted(n.a, depth + 1); if err != Error.none { return err; } },
        Tag.function => { let err = self.admitted(n.a, depth + 1); if err != Error.none { return err; } let err = self.admitted(n.b, depth + 1); if err != Error.none { return err; } },
        Tag.product, Tag.record, Tag.nominal => { if n.tag == Tag.nominal && !blot_check_typed_staging::isIdentity(n.a, n.b) { let owner, err = self.nominal(n.a, n.b, self.store.children(id).len); if err != Error.none { return err; } } for child, index in self.store.children(id) { if n.tag == Tag.record && index % 2 == 0 { continue; } let err = self.admitted(child, depth + 1); if err != Error.none { return err; } } },
        _ => { return Error.invalid_artifact; },
    }
    if n.tag == Tag.function { for label in self.store.effects.view().rowLabels(n.c) { let operation = self.store.effects.view().operation(label); if operation.instance.unit == 0 && operation.instance.decl != 0 { return Error.invalid_artifact; } for argument in self.store.effects.view().operationArguments(label) { let err = self.admitted(argument, depth + 1); if err != Error.none { return err; } } } } return Error.none;
}
fn source(self: Shapes&, producer: const Module&, closure: Closure, ty: u32) -> u32, Error {
    var mappings: blot_eval_type_evidence::Mapping[>..<]; var rows: blot_eval_type_evidence::RowMapping[>..<];
    for mapping in self.snapshot.type_mappings[closure.mappings.start..closure.mappings.start + closure.mappings.len] { if mapping.variable >= producer.types.nodes.len { return 0, Error.invalid_artifact; } let node = producer.types.node(mapping.variable);
        if node.tag != blot_check_types::Tag.variable && !(node.tag == blot_check_types::Tag.bound && node.b == 0 && node.c == 0) { continue; } for prior in mappings { if prior.variable == mapping.variable { return 0, Error.invalid_artifact; } }
        let value, err = self.evidence(mapping.evidence, 0); if err != Error.none { return 0, err; } mappings.append(blot_eval_type_evidence::Mapping { mapping.variable, value , ..});
    }
    for mapping in self.snapshot.row_mappings[closure.row_mappings.start..closure.row_mappings.start + closure.row_mappings.len] { for prior in rows { if prior.variable == mapping.variable { return 0, Error.invalid_artifact; } } let value, err = self.row(mapping.evidence, 0); if err != Error.none { return 0, err; } rows.append(blot_eval_type_evidence::RowMapping { mapping.variable, value , ..}); }
    let result, err = self.store.projectWithBudget(producer.types, ty, mappings, rows, self.remaining); if err != Error.none { return 0, failure(err); } let err = self.admitted(result, 0); return result, err;
}
fn value(self: Shapes&, id: u32, expected: u32, depth: i64) -> Error {
    let err = self.step(depth); if err != Error.none { return err; } let value = self.snapshot.values[id]; let shape = self.store.node(expected); let children = self.snapshot.children[value.start..value.start + value.len];
    match shape.tag {
        Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32 => { if value.kind != Kind.scalar || children.len != 0 || value.nominal != 0 { return Error.invalid_artifact; } var scalar = blot_backend_runtime_ir::SC_unit; if shape.tag == Tag.boolean { scalar = blot_backend_runtime_ir::SC_bool; } if shape.tag == Tag.unsigned32 { scalar = blot_backend_runtime_ir::SC_u32; } if shape.tag == Tag.floating32 { scalar = blot_backend_runtime_ir::SC_f32; } if value.scalar != scalar || (shape.tag == Tag.unit && value.bits != 0) || (shape.tag == Tag.boolean && value.bits > 1) { return Error.invalid_artifact; } },
        Tag.product => { if value.kind != Kind.product { return Error.invalid_artifact; } let types = self.store.children(expected); if children.len != types.len { return Error.invalid_artifact; } for child, index in children { if child >= id { return Error.invalid_artifact; } let err = self.value(child, types[index], depth + 1); if err != Error.none { return err; } } },
        Tag.record => { if value.kind != Kind.record { return Error.invalid_artifact; } let types = self.store.children(expected); let layout = self.snapshot.record_layouts[self.snapshot.value_records[id]]; let names = self.snapshot.field_names[layout.start..layout.start + layout.len]; if children.len != types.len / 2 || names.len != children.len { return Error.invalid_artifact; }
            for child, index in children { var field = blot_support::none<u32>(); for i in 0..types.len / 2 { if types[i * 2] == names[index] { field = blot_support::some(types[i * 2 + 1]); break; } } if !field.present || child >= id { return Error.invalid_artifact; } let err = self.value(child, field.value, depth + 1); if err != Error.none { return err; } for prior in names[..index] { if prior == names[index] { return Error.invalid_artifact; } } }
        },
        Tag.array, Tag.list => { if !((shape.tag == Tag.array && value.kind == Kind.array) || (shape.tag == Tag.list && value.kind == Kind.list)) { return Error.invalid_artifact; } for child in children { if child >= id { return Error.invalid_artifact; } let err = self.value(child, shape.a, depth + 1); if err != Error.none { return err; } } },
        Tag.nominal => {
            if blot_check_typed_staging::isIdentity(shape.a, shape.b) { if shape.b != blot_check_typed_staging::code_identity.decl || value.kind != Kind.code { return Error.invalid_artifact; } let closure = self.snapshot.closures[value.bits]; if closure.unit == 0 || closure.unit > self.units.len { return Error.invalid_artifact; } let projected, err = self.source(self.units[closure.unit - 1].core, closure, closure.ty); if err != Error.none { return err; } if expected != projected { return Error.invalid_artifact; } }
            else {
                if value.kind != Kind.nominal || value.nominal != ((shape.a as u64) << 32 | shape.b) { return Error.invalid_artifact; } let owner, err = self.nominal(shape.a, shape.b, self.store.children(expected).len); if err != Error.none { return err; } let family = self.units[owner.unit - 1].core.nominals[owner.index]; if value.bits >= family.constructors.len { return Error.invalid_artifact; }
                let constructor = self.units[owner.unit - 1].core.constructors[self.units[owner.unit - 1].core.nominalConstructors(owner.index)[value.bits]]; if constructor.nominal != owner.index || constructor.tag != value.bits || constructor.scheme.obligations.len != 0 || constructor.scheme.row_variables.len != 0 || constructor.scheme.generative.len != 0 { return Error.invalid_artifact; }
                var result_type = constructor.scheme.root; var parameter_type: u32 = 0; var payload_count: i64 = 0;
                if constructor.payload != 0 { payload_count = 1; let arrow = self.units[owner.unit - 1].core.types.node(result_type); if arrow.tag != blot_check_types::Tag.function { return Error.invalid_artifact; } let row = self.units[owner.unit - 1].core.types.effects.node(arrow.c); if row.labels.len != 0 || row.tail != blot_check_effects::Tail.closed { return Error.invalid_artifact; } parameter_type = arrow.a; result_type = arrow.b; }
                if children.len != payload_count { return Error.invalid_artifact; } var mappings: blot_eval_type_evidence::Mapping[>..<]; var rows: blot_eval_type_evidence::RowMapping[>..<]; let matched, err = self.store.matchWithRowsBudget(self.units[owner.unit - 1].core.types, result_type, expected, mappings, rows, self.remaining); if err != Error.none { return failure(err); } if !matched || rows.len != 0 { return Error.invalid_artifact; }
                for mapping in mappings { var variable = false; for v in self.units[owner.unit - 1].core.types.list(constructor.scheme.variables) { if v == mapping.variable { variable = true; break; } } if !variable { return Error.invalid_artifact; } variable = false; for v in self.units[owner.unit - 1].core.types.list(family.variables) { if v == mapping.variable { variable = true; break; } } if !variable { return Error.invalid_artifact; } }
                let projected, err = self.store.projectWithBudget(self.units[owner.unit - 1].core.types, result_type, mappings, rows, self.remaining); if err != Error.none { return failure(err); } if expected != projected { return Error.invalid_artifact; }
                if constructor.payload != 0 { let payload, err = self.store.projectWithBudget(self.units[owner.unit - 1].core.types, constructor.payload, mappings, rows, self.remaining); if err != Error.none { return failure(err); } let parameter, err = self.store.projectWithBudget(self.units[owner.unit - 1].core.types, parameter_type, mappings, rows, self.remaining); if err != Error.none { return failure(err); } let storage = self.store.node(payload);
                    if family.is_opaque { if parameter != payload { return Error.invalid_artifact; } } else if storage.tag == Tag.record { let fields = self.store.children(payload); if fields.len == 2 { if parameter != fields[1] { return Error.invalid_artifact; } } else { if self.store.node(parameter).tag != Tag.product { return Error.invalid_artifact; } let parts = self.store.children(parameter); if parts.len != fields.len / 2 { return Error.invalid_artifact; } for part, index in parts { if part != fields[index * 2 + 1] { return Error.invalid_artifact; } } } } else if parameter != payload { return Error.invalid_artifact; }
                    let err = self.admitted(payload, depth + 1); if err != Error.none { return err; } if children[0] >= id { return Error.invalid_artifact; } let err = self.value(children[0], payload, depth + 1); if err != Error.none { return err; }
                }
            }
        },
        _ => { return Error.invalid_artifact; },
    }
    if self.snapshot.value_evidence[id] != 0 { let actual, err = self.evidence(self.snapshot.value_evidence[id], 0); if err != Error.none { return err; } if expected != actual { return Error.invalid_artifact; } } return Error.none;
}
struct Context<Units> { units: Units, snapshot: const Snapshot& }
fn withShapes(context: Context&, store: blot_eval_type_evidence::Store&) -> Error {
    let snapshot .= context.snapshot; var imported: u32[>..<]; imported.resize(snapshot.evidence.nodes.len); for &value in imported { value = 0; }
    var shapes = Shapes { units: context.units, snapshot: snapshot, store: store, imported: imported , ..}; let evidence = snapshot.evidence.view();
    for value, id in snapshot.values {
        if value.kind == Kind.descriptor { if value.nominal == 0 || value.nominal >= evidence.nodes.len || value.len != 0 || value.bits != 0 { return Error.invalid_artifact; } if snapshot.value_evidence[id] != 0 { let ty = evidence.node(snapshot.value_evidence[id]); if ty.tag != Tag.nominal || ty.a != blot_check_typed_staging::descriptor_identity.unit || ty.b != blot_check_typed_staging::descriptor_identity.decl { return Error.invalid_artifact; } let args = evidence.children(snapshot.value_evidence[id]); if args.len != 1 || args[0] != value.nominal { return Error.invalid_artifact; } } let imported, err = shapes.evidence(value.nominal as u32, 0); if err != Error.none { return err; } }
        if value.kind != Kind.code { continue; } if value.bits >= snapshot.closures.len { return Error.invalid_artifact; } let closure = snapshot.closures[value.bits];
        if closure.unit == 0 || closure.unit > context.units.len || closure.origin != blot_eval_core_eval::ClosureOrigin.anonymous || closure.applied != 0 || closure.staged != 0 { return Error.invalid_artifact; } let producer .= context.units[closure.unit - 1].core;
        if closure.identity == 0 || closure.identity >= producer.nodes.len || value.nominal != closure.identity || closure.ty >= producer.types.nodes.len || !blot_check_typed_staging::codeInfo(producer.types, closure.ty).present { return Error.invalid_artifact; }
        var introduced = false; for node in producer.nodes { if node.tag == blot_check_core::Tag.staging && node.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.quote) && node.a == closure.identity && node.ty == closure.ty { introduced = true; break; } } if !introduced { return Error.invalid_artifact; }
        if snapshot.value_evidence[id] != 0 { let ty = evidence.node(snapshot.value_evidence[id]); if ty.tag != Tag.nominal || ty.a != blot_check_typed_staging::code_identity.unit || ty.b != blot_check_typed_staging::code_identity.decl { return Error.invalid_artifact; } let args = evidence.children(snapshot.value_evidence[id]); if args.len != 2 { return Error.invalid_artifact; } let latent = evidence.node(args[1]); if latent.tag != Tag.function || latent.a != blot_check_types::unit || latent.b != blot_check_types::unit { return Error.invalid_artifact; } }
        let expected, err = shapes.source(producer, closure, closure.ty); if err != Error.none { return err; } if snapshot.value_evidence[id] != 0 { let actual, err = shapes.evidence(snapshot.value_evidence[id], 0); if err != Error.none { return err; } if expected != actual { return Error.invalid_artifact; } }
        let children = snapshot.children[value.start..value.start + value.len]; for child, ordinal in children { let replacement = snapshot.values[child]; if child >= id || replacement.kind != Kind.staged_value || replacement.nominal == 0 || replacement.nominal >= producer.nodes.len || replacement.len != 1 { return Error.invalid_artifact; } let node = producer.nodes[replacement.nominal as u32]; if node.tag != blot_check_core::Tag.staging || node.c != replacement.bits || (node.c != blot_check_typed_staging::opCode(blot_check_typed_staging::Op.lift) && node.c != blot_check_typed_staging::opCode(blot_check_typed_staging::Op.splice)) { return Error.invalid_artifact; } for previous in children[..ordinal] { if snapshot.values[previous].nominal == replacement.nominal { return Error.invalid_artifact; } }
            let payload = snapshot.children[replacement.start]; if payload >= child { return Error.invalid_artifact; } var payload_type = node.ty; if node.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.splice) { payload_type = producer.typeOf(node.a); } let expected, err = shapes.source(producer, closure, payload_type); if err != Error.none { return err; } let err = shapes.value(payload, expected, 0); if err != Error.none { return err; }
        }
    } return Error.none;
}
fn validate(snapshot: const Snapshot&, units) -> Error {
    var previous: u32 = 0; for origin in snapshot.code_origins { if origin.value == 0 || origin.value <= previous || origin.value >= snapshot.values.len || snapshot.values[origin.value].kind != Kind.code || origin.generator.unit == 0 || origin.generator.unit > units.len { return Error.invalid_artifact; } let owner .= units[origin.generator.unit - 1].core; if origin.generator.node == 0 || origin.generator.node >= owner.nodes.len || origin.generator.node >= owner.spans.len { return Error.invalid_artifact; } previous = origin.value; }
    for closure in snapshot.closures { if closure.staged >= snapshot.values.len || (closure.staged != 0 && snapshot.values[closure.staged].kind != Kind.code) { return Error.invalid_artifact; } }
    var staged = false; for value in snapshot.values { if value.kind == Kind.code || value.kind == Kind.descriptor { staged = true; break; } } if !staged { return Error.none; }
    var context = Context { units, snapshot , ..}; return blot_eval_type_evidence::withStore<Context,withShapes>(context);
}
