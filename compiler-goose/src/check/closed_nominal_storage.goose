// Conditional closed storage is independent of affine and repeatable usage.
namespace blot_check_closed_nominal_storage;
import support.error;
import support.structural;
import .types;
import .usage_check;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type Tag = blot_check_types::Tag;
type Work = blot_check_usage_check::Work;
fn bounded(store, id: Id) -> bool { return id < store.nodes.len; }
fn validList(store, list: blot_check_types::List) -> bool { return list.start <= store.extra.len && list.len <= store.extra.len - list.start; }
recursive fn expression(store, nominals, owner: i64, root: Id, work: Work&, depth: i64) -> bool, Error {
    let error = work.charge(1); if error != Error.none { return false, error; } if depth >= 128 || !bounded(store, root) { return false, Error.type_limit; } let id = store.head(root, 0); if !bounded(store, id) { return false, Error.type_limit; }
    let n = store.node(id); let error = blot_check_usage_check::nominalShape(store, nominals, n, work); if error != Error.none { return false, error; }
    match n.tag {
        Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32 { return n.a == 0 && n.b == 0 && n.c == 0, Error.none; }
        Tag.variable, Tag.bound { if !validList(store, nominals[owner].variables) { return false, Error.type_limit; }
            for variable in store.list(nominals[owner].variables) { let error = work.charge(1); if error != Error.none { return false, error; } if !bounded(store, variable) { return false, Error.type_limit; } let formal = store.node(store.head(variable, 0));
                if n.tag == Tag.variable && formal.tag == Tag.variable && n.a == formal.a { return true, Error.none; } if n.tag == Tag.bound && formal.tag == Tag.bound && id == variable && n.b == 0 { return true, Error.none; }
            } return false, Error.none;
        }
        Tag.array, Tag.list { if n.b != 0 || n.c != 0 { return false, Error.none; } return expression(store, nominals, owner, n.a, work, depth + 1); }
        Tag.product { if n.c != 0 { return false, Error.none; } for child in store.list(blot_check_types::List { n.a, n.b }) { let closed, error = expression(store, nominals, owner, child, work, depth + 1); if error != Error.none || !closed { return closed, error; } } return true, Error.none; }
        Tag.record { if n.c != 0 { return false, Error.none; } for index in 0..n.b { let closed, error = expression(store, nominals, owner, store.recordField(n, index).ty, work, depth + 1); if error != Error.none || !closed { return closed, error; } } return true, Error.none; }
        Tag.nominal { var index = owner; for attempt in 0..nominals.len { let error = work.charge(1); if error != Error.none { return false, error; } let nominal = nominals[index]; if index == 0 { index = nominals.len; } index -= 1;
                if nominal.identity.unit != n.a || nominal.identity.decl != n.b { continue; } if !nominal.closed_storage || nominal.has_usage { return false, Error.none; } let arguments = store.nominalArguments(n); if arguments.len != nominal.parameters.len { return false, Error.none; }
                for argument in arguments { let closed, error = expression(store, nominals, owner, argument, work, depth + 1); if error != Error.none || !closed { return closed, error; } } return true, Error.none;
            } return false, Error.none;
        }
        else { return false, Error.none; }
    }
}
fn facts(store, nominals, constructors, unit: u32, work: Work&) -> Error {
    for &nominal in nominals { let error = work.charge(1); if error != Error.none { return error; } if nominal.identity.unit == unit { nominal.closed_storage = false; } }
    for constructor in constructors { let error = work.charge(1); if error != Error.none { return error; } if constructor.nominal >= nominals.len || !bounded(store, constructor.payload) { return Error.type_limit; } let nominal = nominals[constructor.nominal]; if nominal.identity.unit == unit && !nominal.has_usage { nominals[constructor.nominal].closed_storage = true; } }
    for iteration in 0..nominals.len { let error = work.charge(1); if error != Error.none { return error; } var changed = false;
        for constructor in constructors { let error = work.charge(1); if error != Error.none { return error; } let nominal = nominals[constructor.nominal]; if constructor.payload == 0 || nominal.identity.unit != unit || !nominal.closed_storage { continue; }
            let closed, error = expression(store, nominals, constructor.nominal, constructor.payload, work, 0); if error != Error.none { return error; } if closed { continue; } nominals[constructor.nominal].closed_storage = false; changed = true;
        } if !changed { break; }
    } return Error.none;
}
fn validate(module: const blot_check_core::Module&) -> Error {
    var claimed = false; for nominal, index in module.nominals { if nominal.closed_storage && (index == 0 || nominal.identity.unit == 0 || nominal.identity.decl == 0 || nominal.has_usage) { return Error.invalid_artifact; } claimed = claimed || nominal.closed_storage; }
    if !claimed { return Error.none; } if module.nominals.len > 4096 { return Error.invalid_artifact; }
    var storage: blot_check_core::Nominal[4096]; let proved = storage[..module.nominals.len]; for nominal, index in module.nominals { proved[index] = nominal; } var work = Work {};
    for nominal, owner in proved { let error = work.charge(1); if error != Error.none { return Error.invalid_artifact; } if !nominal.closed_storage { continue; }
        if !validList(module.types, nominal.variables) || !validList(module.types, nominal.parameters) { return Error.invalid_artifact; }
        for variable in module.types.list(nominal.variables) { let error = work.charge(1); if error != Error.none || !bounded(module.types, variable) { return Error.invalid_artifact; } }
        if nominal.storage.kind == blot_backend_opaque_storage::Kind.parameter && nominal.storage.parameter >= nominal.parameters.len { return Error.invalid_artifact; }
        for parameter in module.types.list(nominal.parameters) { let closed, error = expression(module.types, proved, owner, parameter, work, 0); if error != Error.none || !closed { return Error.invalid_artifact; } }
    }
    let error = facts(module.types, proved, module.constructors, module.unit, work); if error != Error.none { return Error.invalid_artifact; }
    for declared, index in module.nominals { if declared.closed_storage && !proved[index].closed_storage { return Error.invalid_artifact; } }
    for &nominal in proved { if nominal.identity.unit == module.unit && nominal.is_opaque { nominal.storage = blot_backend_opaque_storage::Storage {}; } }
    let graph = blot_check_associated_admission::graphView(module.types);
    for iteration in 0..proved.len { let error = work.charge(1); if error != Error.none { return Error.invalid_artifact; } var changed = false;
        for &nominal, index in proved { let error = work.charge(1); if error != Error.none { return Error.invalid_artifact; } if !nominal.closed_storage || !nominal.is_opaque || nominal.identity.unit != module.unit { continue; }
            if !validList(module.types, nominal.parameters) || nominal.constructors.len != 1 || nominal.constructors.start >= module.extra.len { return Error.invalid_artifact; } let id = module.extra[nominal.constructors.start];
            if id == 0 || id >= module.constructors.len || module.constructors[id].nominal != index { return Error.invalid_artifact; }
            let inferred = blot_backend_opaque_storage::inferPayload(blot_check_frozen_types::Source.frozen { graph }, proved, module.constructors, module.constructors[id].payload, nominal.parameters, work.remaining);
            if work.remaining == 0 { return Error.invalid_artifact; } if inferred != nominal.storage { nominal.storage = inferred; changed = true; }
        } if !changed { break; }
    }
    for declared, index in module.nominals { let inferred = proved[index]; if inferred.closed_storage && inferred.is_opaque && inferred.identity.unit == module.unit && declared.storage != inferred.storage { return Error.invalid_artifact; } }
    for node in module.nodes { let error = work.charge(1); if error != Error.none { return Error.invalid_artifact; } if node.tag != blot_check_core::Tag.constant { continue; }
        if node.op != blot_check_core::Op.none || node.b != 0 || node.c != 0 || !bounded(module.types, node.ty) { return Error.invalid_artifact; } var ty = module.types.node(node.ty); if ty.tag == Tag.usage { if !bounded(module.types, ty.a) { return Error.invalid_artifact; } ty = module.types.node(ty.a); }
        if ty.tag != Tag.unit && ty.tag != Tag.boolean && ty.tag != Tag.unsigned32 && ty.tag != Tag.floating32 { return Error.invalid_artifact; }
    } return Error.none;
}
struct Matcher { module: const blot_check_core::Module&, owner: i64, work: Work&, formal: Id[128], actual: Id[128], count: i64 = 0 }
recursive fn matchTypes(self: Matcher&, expected: Id, actual: Id, replace: bool, depth: i64) -> bool, Error {
    let error = self.work.charge(1); if error != Error.none { return false, error; } let types = self.module.types;
    if depth >= 128 || !bounded(types, expected) || !bounded(types, actual) { return false, Error.type_limit; } let left = types.node(expected); let right = types.node(actual);
    let error = blot_check_usage_check::nominalShape(types, self.module.nominals, left, self.work); if error != Error.none { return false, error; } let error = blot_check_usage_check::nominalShape(types, self.module.nominals, right, self.work); if error != Error.none { return false, error; }
    if replace && left.tag == Tag.variable { let variables = self.module.nominals[self.owner].variables; if !validList(types, variables) { return false, Error.type_limit; } var owned = false;
        for variable in types.list(variables) { let error = self.work.charge(1); if error != Error.none { return false, error; } if !bounded(types, variable) { return false, Error.type_limit; } let leaf = types.node(variable); if leaf.tag == Tag.variable && leaf.a == left.a { owned = true; } } if !owned { return false, Error.none; }
        for index in 0..self.count { let error = self.work.charge(1); if error != Error.none { return false, error; } if types.node(self.formal[index]).a == left.a { return matchTypes(self, self.actual[index], actual, false, depth + 1); } }
        if self.count == self.formal.len { return false, Error.type_limit; } self.formal[self.count] = expected; self.actual[self.count] = actual; self.count += 1; return true, Error.none;
    }
    if left.tag != right.tag { return false, Error.none; }
    match left.tag {
        Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32 { return left.a == 0 && left.b == 0 && left.c == 0 && right.a == 0 && right.b == 0 && right.c == 0, Error.none; }
        Tag.array, Tag.list { return matchTypes(self, left.a, right.a, replace, depth + 1); }
        Tag.product { if left.b != right.b { return false, Error.none; } let xs = types.list(blot_check_types::List { left.a, left.b }); let ys = types.list(blot_check_types::List { right.a, right.b }); for x, index in xs { let equal, error = matchTypes(self, x, ys[index], replace, depth + 1); if error != Error.none || !equal { return equal, error; } } }
        Tag.record { if left.b != right.b { return false, Error.none; } for index in 0..left.b { let field = types.recordField(left, index); var found = false; for other in 0..right.b { let error = self.work.charge(1); if error != Error.none { return false, error; } let candidate = types.recordField(right, other); if candidate.name != field.name { continue; } if found { return false, Error.none; } let equal, error = matchTypes(self, field.ty, candidate.ty, replace, depth + 1); if error != Error.none || !equal { return equal, error; } found = true; } if !found { return false, Error.none; } } }
        Tag.nominal { if left.a != right.a || left.b != right.b { return false, Error.none; } let xs = types.nominalArguments(left); let ys = types.nominalArguments(right); if xs.len != ys.len { return false, Error.none; } for x, index in xs { let equal, error = matchTypes(self, x, ys[index], replace, depth + 1); if error != Error.none || !equal { return equal, error; } } }
        else { return false, Error.none; }
    } return true, Error.none;
}
fn construction(module: const blot_check_core::Module&, node: blot_check_core::Node, work: Work&) -> bool, Error {
    if node.a == 0 || node.a >= module.constructors.len || !bounded(module.types, node.ty) || node.op != blot_check_core::Op.none || node.c > 1 { return false, Error.type_limit; } let constructor = module.constructors[node.a]; if constructor.nominal >= module.nominals.len { return false, Error.type_limit; } let family = module.nominals[constructor.nominal]; var output = module.types.node(node.ty);
    if output.tag == Tag.usage { if !bounded(module.types, output.a) { return false, Error.type_limit; } output = module.types.node(output.a); }
    let error = blot_check_usage_check::nominalShape(module.types, module.nominals, output, work); if error != Error.none { return false, error; }
    if output.tag != Tag.nominal || output.a != family.identity.unit || output.b != family.identity.decl || !family.closed_storage { return false, Error.none; }
    var matcher = Matcher { module, constructor.nominal, work }; if !validList(module.types, family.parameters) { return false, Error.type_limit; } let actuals = module.types.nominalArguments(output); if family.parameters.len != actuals.len { return false, Error.none; }
    for formal, index in module.types.list(family.parameters) { let equal, error = matchTypes(matcher, formal, actuals[index], true, 0); if error != Error.none || !equal { return equal, error; } }
    if node.b == 0 { return constructor.payload == 0 && node.c == 0, Error.none; } if node.b >= module.nodes.len || !bounded(module.types, constructor.payload) { return false, Error.type_limit; }
    var expected = constructor.payload; let actual = module.typeOf(node.b);
    if node.c != 0 { let record = module.types.node(expected); if family.is_opaque || record.tag != Tag.record || record.b == 0 { return false, Error.none; } let error = blot_check_usage_check::nominalShape(module.types, module.nominals, record, work); if error != Error.none { return false, error; }
        if record.b == 1 { expected = module.types.recordField(record, 0).ty; }
        else { if !bounded(module.types, actual) { return false, Error.type_limit; } let tuple = module.types.node(actual); let error = blot_check_usage_check::nominalShape(module.types, module.nominals, tuple, work); if error != Error.none { return false, error; } if tuple.tag != Tag.product || tuple.b != record.b { return false, Error.none; }
            for field, index in module.types.list(blot_check_types::List { tuple.a, tuple.b }) { let equal, error = matchTypes(matcher, module.types.recordField(record, index).ty, field, true, 0); if error != Error.none || !equal { return equal, error; } } return true, Error.none;
        }
    } return matchTypes(matcher, expected, actual, true, 0);
}
