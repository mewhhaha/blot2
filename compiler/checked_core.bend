import Base
import ./model.bend as M
import ./groups.bend as Groups
import ./index.bend as Index
import ./core_compare.bend as Compare
import ./globals.bend as Globals
import ./closures.bend as Closures
import ./constraints.bend as C

# A certificate comes from a successful independent check of one complete SCC.
# Its imported principal schemes are frozen at that boundary.
# Caller-constrained specialization environments never issue certificates.
type Certificate is Data:
  Certificate{module: M.Module, checked: Groups.CheckedGroup, imports: List<&2, Groups.Interface>}

type Prepared is Data:
  Prepared{module: M.Module, certificates: List<&2, Certificate>}

def prepared_module(prepared: Prepared) -> M.Module:
  Prepared{module, certificates} = prepared
  module

def prepared_certificates(prepared: Prepared) -> List<&2, Certificate>:
  Prepared{module, certificates} = prepared
  certificates

def deferred(fuel: Nat, pending: List<&2, M.Expr>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      False{}
    case 0n _:
      True{}
    case 1n+rest M.AssociatedExpr{identity, dispatch, member, templates, left, right} <> tail:
      True{}
    case 1n+rest M.GenericOperationExpr{identity, template, arguments} <> tail:
      True{}
    case 1n+rest M.SpecializeOperationExpr{template, arguments, body} <> tail:
      True{}
    case 1n+rest M.QualifiedExpr{offset, annotation, predicates, body} <> tail:
      True{}
    case 1n+rest head <> tail:
      deferred(rest, List.reverse.go(&2, M.Expr, List.reverse(&2, M.Expr, Closures.children(head)), tail))

def deferred_functions(functions: List<&2, M.Function>) -> Bool:
  match functions:
    case Nil{}:
      False{}
    case M.Function{name, exported, parameter, p, r, body} <> tail:
      Bool.or(deferred(65536n, [body]), deferred_functions(tail))

def deferred_constants(constants: List<&2, M.Constant>) -> Bool:
  match constants:
    case Nil{}:
      False{}
    case M.Constant{name, exported, annotation, value} <> tail:
      Bool.or(deferred(65536n, [value]), deferred_constants(tail))

def source_ready(module: M.Module) -> Bool:
  M.Module{constants, functions, types, operations} = module
  Bool.not(Bool.or(deferred_functions(functions), deferred_constants(constants)))

def pending_uses(plans: List<&2, C.UsePlan>) -> Bool:
  match plans:
    case Nil{}:
      False{}
    case C.UsePlan{site, subject, ty, predicates} <> tail:
      Bool.or(Bool.not(List.is_empty(&2, M.Predicate, predicates)), pending_uses(tail))

def pending_interfaces(interfaces: List<&2, Groups.Interface>) -> Bool:
  match interfaces:
    case Nil{}:
      False{}
    case Groups.Interface{name, kind, template, parameters, effects, predicates} <> tail:
      Bool.or(Bool.not(List.is_empty(&2, M.Predicate, predicates)), pending_interfaces(tail))

def ready_group(group: Groups.CheckedGroup) -> Bool:
  Groups.CheckedGroup{checked, interfaces, uses} = group
  Bool.not(Bool.or(pending_uses(uses), pending_interfaces(interfaces)))

# Final-check reuse accepts only groups whose source needs no specialization.
def ready_certificates(certificates: List<&2, Certificate>) -> List<&2, Certificate>:
  match certificates:
    case Nil{}:
      Nil{}
    case +certificate <> tail:
      Certificate{module, checked, imports} = certificate
      +rest = ready_certificates(tail)
      Bool.pick(List<&2, Certificate>, Bool.and(source_ready(module), ready_group(checked)), certificate <> rest, rest)

def type_identity(ty: M.DataType) -> M.TypeId:
  M.DataType{identity, parameters, constructors} = ty
  identity

def find_type(+identity: M.TypeId, types: List<&2, M.DataType>) -> Maybe<&2, M.DataType>:
  match types:
    case Nil{}:
      None{}
    case M.DataType{+found, parameters, constructors} <> tail:
      Bool.pick(Maybe<&2, M.DataType>, M.type_id_equal(identity, found), Some{M.DataType{found, parameters, constructors}}, find_type(identity, tail))

def matches_type(ty: M.DataType, found: Maybe<&2, M.DataType>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{candidate}:
      Compare.same_type(ty, candidate)

def same_types(wanted: List<&2, M.DataType>, +available: List<&2, M.DataType>) -> Bool:
  match wanted:
    case Nil{}:
      True{}
    case +ty <> tail:
      Bool.and(matches_type(ty, find_type(type_identity(ty), available)), same_types(tail, available))

def operation_identity(operation: M.Operation) -> M.TypeId:
  match operation:
    case M.Operation{identity, parameter, result}:
      identity
    case M.OperationTemplate{identity, parameters, parameter, result}:
      identity
    case M.OperationInstance{template, arguments}:
      template

# Build from the tail so a duplicate identity retains the same first match
# that the original left-to-right `find_type` and `find_operation` would see.
# Group certificates carry the full operation catalog; constructing these
# indexes once avoids rescanning it for every certificate and operation.
def first_type_index(types: List<&2, M.DataType>, indexed: Map<&2, M.DataType>) -> Map<&2, M.DataType>:
  match types:
    case Nil{}:
      indexed
    case +head <> tail:
      Map.set(&2, M.DataType, first_type_index(tail, indexed), Groups.type_key(type_identity(head)), head)

def first_operation_index(operations: List<&2, M.Operation>, indexed: Map<&2, M.Operation>) -> Map<&2, M.Operation>:
  match operations:
    case Nil{}:
      indexed
    case +head <> tail:
      Map.set(&2, M.Operation, first_operation_index(tail, indexed), Groups.type_key(operation_identity(head)), head)

def find_operation(+identity: M.TypeId, operations: List<&2, M.Operation>) -> Maybe<&2, M.Operation>:
  match operations:
    case Nil{}:
      None{}
    case +head <> tail:
      Bool.pick(Maybe<&2, M.Operation>, M.type_id_equal(identity, operation_identity(head)), Some{head}, find_operation(identity, tail))

def matches_operation(operation: M.Operation, found: Maybe<&2, M.Operation>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{candidate}:
      Compare.same_operation(operation, candidate)

def same_operations(required: List<&2, M.Operation>, +available: List<&2, M.Operation>) -> Bool:
  match required:
    case Nil{}:
      True{}
    case M.OperationTemplate{identity, parameters, parameter, result} <> tail:
      same_operations(tail, available)
    case M.OperationInstance{template, arguments} <> tail:
      same_operations(tail, available)
    case +operation <> tail:
      Bool.and(matches_operation(operation, find_operation(operation_identity(operation), available)), same_operations(tail, available))

def valid_catalog(certificate: Certificate, +types: List<&2, M.DataType>, +operations: List<&2, M.Operation>) -> Bool:
  Certificate{M.Module{constants, functions, original_types, original_operations}, checked, imports} = certificate
  Bool.and(same_types(original_types, types), same_operations(original_operations, operations))

def indexed_types(wanted: List<&2, M.DataType>, +available: Map<&2, M.DataType>) -> Bool:
  match wanted:
    case Nil{}:
      True{}
    case +ty <> tail:
      Bool.and(matches_type(ty, Index.find(M.DataType, available, Groups.type_key(type_identity(ty)))), indexed_types(tail, available))

def indexed_operations(required: List<&2, M.Operation>, +available: Map<&2, M.Operation>) -> Bool:
  match required:
    case Nil{}:
      True{}
    case M.OperationTemplate{identity, parameters, parameter, result} <> tail:
      indexed_operations(tail, available)
    case M.OperationInstance{template, arguments} <> tail:
      indexed_operations(tail, available)
    case +operation <> tail:
      Bool.and(matches_operation(operation, Index.find(M.Operation, available, Groups.type_key(operation_identity(operation)))), indexed_operations(tail, available))

def valid_indexed_catalog(certificate: Certificate, +types: Map<&2, M.DataType>, +operations: Map<&2, M.Operation>) -> Bool:
  Certificate{M.Module{constants, functions, original_types, original_operations}, checked, imports} = certificate
  Bool.and(indexed_types(original_types, types), indexed_operations(original_operations, operations))

def indexed_catalog_certificates(certificates: List<&2, Certificate>, +types: Map<&2, M.DataType>, +operations: Map<&2, M.Operation>) -> List<&2, Certificate>:
  match certificates:
    case Nil{}:
      Nil{}
    case +certificate <> tail:
      +rest = indexed_catalog_certificates(tail, types, operations)
      Bool.pick(List<&2, Certificate>, valid_indexed_catalog(certificate, types, operations), certificate <> rest, rest)

def catalog_certificates(certificates: List<&2, Certificate>, +types: List<&2, M.DataType>, +operations: List<&2, M.Operation>) -> List<&2, Certificate>:
  match certificates:
    case Nil{}:
      Nil{}
    case +certificate <> tail:
      +rest = catalog_certificates(tail, types, operations)
      Bool.pick(List<&2, Certificate>, valid_catalog(certificate, types, operations), certificate <> rest, rest)

def names(module: M.Module) -> List<&2, String>:
  M.Module{constants, functions, types, operations} = module
  Globals.names(List.append(&2, Globals.Declaration, Globals.function_declarations(functions), Globals.constant_declarations(constants)))

def insert(+certificate: Certificate, +indexed: Map<&2, List<&2, Certificate>>, name: String, previous: Maybe<&2, List<&2, Certificate>>) -> Map<&2, List<&2, Certificate>>:
  match previous:
    case None{}:
      Map.set(&2, List<&2, Certificate>, indexed, name, [certificate])
    case Some{old}:
      Map.set(&2, List<&2, Certificate>, indexed, name, certificate <> old)

def add_names(members: List<&2, String>, +certificate: Certificate, +indexed: Map<&2, List<&2, Certificate>>) -> Map<&2, List<&2, Certificate>>:
  match members:
    case Nil{}:
      indexed
    case +name <> tail:
      add_names(tail, certificate, insert(certificate, indexed, name, Index.find(List<&2, Certificate>, indexed, name)))

def index(certificates: List<&2, Certificate>) -> Map<&2, List<&2, Certificate>>:
  match certificates:
    case Nil{}:
      Map.new(&2, List<&2, Certificate>)
    case Certificate{+module, checked, imports} <> tail:
      add_names(names(module), Certificate{module, checked, imports}, index(tail))

def index_for_nonempty(final_module: M.Module, certificates: List<&2, Certificate>) -> Map<&2, List<&2, Certificate>>:
  M.Module{constants, functions, types, operations} = final_module
  available_types = first_type_index(types, Map.new(&2, M.DataType))
  available_operations = first_operation_index(operations, Map.new(&2, M.Operation))
  index(indexed_catalog_certificates(certificates, available_types, available_operations))

def index_for(final_module: M.Module, certificates: List<&2, Certificate>) -> Map<&2, List<&2, Certificate>>:
  match certificates:
    case Nil{}:
      Map.new(&2, List<&2, Certificate>)
    case head <> tail:
      index_for_nonempty(final_module, head <> tail)

def same_kind(left: Groups.InterfaceKind, right: Groups.InterfaceKind) -> Bool:
  match left right:
    case Groups.FunctionInterface{} Groups.FunctionInterface{}:
      True{}
    case Groups.ConstantInterface{} Groups.ConstantInterface{}:
      True{}
    case _ _:
      False{}

def same_predicates_work(left: List<&2, M.Predicate>, right: List<&2, M.Predicate>, equal: Bool) -> Bool:
  match left right equal:
    case _ _ False{}:
      False{}
    case Nil{} Nil{} True{}:
      True{}
    case a <> rest b <> following True{}:
      same_predicates_work(rest, following, C.same_predicate(a, b))
    case _ _ _:
      False{}

def same_predicates(left: List<&2, M.Predicate>, right: List<&2, M.Predicate>) -> Bool:
  same_predicates_work(left, right, True{})

def same_interface(left: Groups.Interface, right: Groups.Interface) -> Bool:
  Groups.Interface{a_name, a_kind, a_type, a_parameters, a_effects, a_predicates} = left
  Groups.Interface{b_name, b_kind, b_type, b_parameters, b_effects, b_predicates} = right
  Bool.and(M.name_equal(a_name, b_name), Bool.and(same_kind(a_kind, b_kind), Bool.and(Nat.is_eq(a_parameters, b_parameters), Bool.and(Groups.same_effects(a_effects, b_effects), Bool.and(Compare.same_ty(a_type, b_type), same_predicates(a_predicates, b_predicates))))))

def same_imports(left: List<&2, Groups.Interface>, right: List<&2, Groups.Interface>) -> Bool:
  match left right:
    case Nil{} Nil{}:
      True{}
    case a <> rest b <> following:
      Bool.and(same_interface(a, b), same_imports(rest, following))
    case _ _:
      False{}

def same_declarations(left: M.Module, right: M.Module) -> Bool:
  M.Module{a_constants, a_functions, a_types, a_operations} = left
  M.Module{b_constants, b_functions, b_types, b_operations} = right
  Compare.same_module(M.Module{a_constants, a_functions, Nil{}, Nil{}}, M.Module{b_constants, b_functions, Nil{}, Nil{}})

def matching_certificate(certificate: Certificate, +subset: M.Module, imports: List<&2, Groups.Interface>) -> Maybe<&2, Groups.CheckedGroup>:
  Certificate{old_module, Groups.CheckedGroup{M.CheckedModule{old_constants, old_functions, old_types, old_operations}, interfaces, uses}, old_imports} = certificate
  M.Module{constants, functions, types, operations} = subset
  +valid = Bool.and(same_declarations(old_module, subset), same_imports(old_imports, imports))
  Bool.pick(Maybe<&2, Groups.CheckedGroup>, valid, Some{Groups.CheckedGroup{M.CheckedModule{old_constants, old_functions, types, operations}, interfaces, uses}}, None{})

def candidates_work(available: List<&2, Certificate>, +subset: M.Module, +imports: List<&2, Groups.Interface>, found: Maybe<&2, Groups.CheckedGroup>) -> Maybe<&2, Groups.CheckedGroup>:
  match available found:
    case _ Some{group}:
      Some{group}
    case Nil{} None{}:
      None{}
    case +certificate <> tail None{}:
      candidates_work(tail, subset, imports, matching_certificate(certificate, subset, imports))

def candidates(available: List<&2, Certificate>, subset: M.Module, imports: List<&2, Groups.Interface>) -> Maybe<&2, Groups.CheckedGroup>:
  candidates_work(available, subset, imports, None{})

def available_candidates(found: Maybe<&2, List<&2, Certificate>>, subset: M.Module, imports: List<&2, Groups.Interface>) -> Maybe<&2, Groups.CheckedGroup>:
  match found:
    case None{}:
      None{}
    case Some{available}:
      candidates(available, subset, imports)

def lookup(indexed: Map<&2, List<&2, Certificate>>, job: Groups.Job, subset: M.Module, imports: List<&2, Groups.Interface>) -> Maybe<&2, Groups.CheckedGroup>:
  Groups.Job{members, dependencies, types} = job
  match members:
    case Nil{}:
      None{}
    case name <> tail:
      available_candidates(Index.find(List<&2, Certificate>, indexed, name), subset, imports)
