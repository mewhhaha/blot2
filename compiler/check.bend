import Base
import ./demand_elaboration.bend as Demand
import ./model.bend as M
import ./types.bend as T
import ./constraints.bend as C
import ./infer.bend as I
import ./effects.bend as E
import ./effect_rows.bend as R
import ./globals.bend as G
import ./dependency.bend as D
import ./type_data.bend as TD
import ./patterns.bend as P
import ./index.bend as Index

def IdentitySet() -> Data:
  Map<&2, Set()>

def identity_members(index: IdentitySet(), module_name: String) -> Set():
  Index.get(Set(), index, module_name, Set.new())

def identity_present(index: IdentitySet(), identity: M.TypeId) -> Bool:
  M.TypeId{module_name, declaration} = identity
  D.member(identity_members(index, module_name), declaration)

def identity_add(+index: IdentitySet(), identity: M.TypeId) -> IdentitySet():
  M.TypeId{+module_name, declaration} = identity
  Index.set(Set(), index, module_name, Set.add(identity_members(index, module_name), declaration))

def identity_mark(present: Bool, index: IdentitySet(), identity: M.TypeId) -> IdentitySet():
  match present:
    case False{}:
      index
    case True{}:
      identity_add(index, identity)

def repeated_identities(identities: List<&2, M.TypeId>, +seen: IdentitySet(), repeated: IdentitySet()) -> IdentitySet():
  match identities:
    case Nil{}:
      repeated
    case +head <> tail:
      repeated_identities(tail, identity_add(seen, head), identity_mark(identity_present(seen, head), repeated, head))


def require_unique_identity(repeated: Bool, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  match repeated:
    case False{}:
      Done{Unit{}}
    case True{}:
      Fail{M.Diagnostic{"duplicate_type", M.type_id_show(identity), "duplicate nominal identity"}}

def unique_identities(identities: List<&2, M.TypeId>, +repeated: IdentitySet()) -> Result<&2, &2, M.Diagnostic, Unit>:
  match identities:
    case Nil{}:
      Done{Unit{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        unique : Unit <- require_unique_identity(identity_present(repeated, head), head)
        unique_identities(tail, repeated)


def name_present(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}:
      False{}
    case head <> tail:
      E.or_else(M.name_equal(head, name), _ => name_present(tail, name))


def repeated_names(names: List<&2, String>, +seen: Set(), repeated: Set()) -> Set():
  match names:
    case Nil{}:
      repeated
    case +head <> tail:
      repeated_names(tail, Set.add(seen, head), D.mark(D.member(seen, head), repeated, head))

def require_unique_name(repeated: Bool, name: String, code: String, message: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match repeated:
    case False{}:
      Done{Unit{}}
    case True{}:
      Fail{M.Diagnostic{code, name, message}}

# Diagnose the earliest first occurrence with a duplicate, not the earliest
# second occurrence: [a, b, b, a] must still identify a.
def unique_names_indexed(names: List<&2, String>, +repeated: Set(), +code: String, +message: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match names:
    case Nil{}:
      Done{Unit{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        unique : Unit <- require_unique_name(D.member(repeated, head), head, code, message)
        unique_names_indexed(tail, repeated, code, message)

def unique_names(+names: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Unit>:
  unique_names_indexed(names, repeated_names(names, Set.new(), Set.new()), "duplicate_name", "duplicate top-level definition")


def constructor_names(constructors: List<&2, M.Constructor>) -> List<&2, String>:
  match constructors:
    case Nil{}:
      Nil{}
    case M.Constructor{name, payload, fields} <> tail:
      name <> constructor_names(tail)

def all_constructor_names(types: List<&2, M.DataType>) -> List<&2, String>:
  match types:
    case Nil{}:
      Nil{}
    case M.DataType{identity, parameters, constructors} <> tail:
      List.append(&2, String, constructor_names(constructors), all_constructor_names(tail))


def type_identities(types: List<&2, M.DataType>) -> List<&2, M.TypeId>:
  match types:
    case Nil{}:
      Nil{}
    case M.DataType{identity, parameters, constructors} <> tail:
      identity <> type_identities(tail)

def operation_identities(operations: List<&2, M.Operation>) -> List<&2, M.TypeId>:
  match operations:
    case Nil{}:
      Nil{}
    case M.Operation{identity, parameter, result} <> tail:
      identity <> operation_identities(tail)
    case head <> tail:
      operation_identities(tail)

def validate_types_indexed(pending: List<&2, M.DataType>, +types: List<&2, M.DataType>, +operations: List<&2, M.Operation>, +repeated: IdentitySet()) -> Result<&2, &2, M.Diagnostic, Unit>:
  match pending:
    case Nil{}:
      Done{Unit{}}
    case M.DataType{+identity, parameters, +constructors} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        unique : Unit <- require_unique_identity(identity_present(repeated, identity), identity)
        inhabited : Unit <- TD.require(Bool.not(List.is_empty(&2, M.Constructor, constructors)), M.type_id_show(identity), "data declarations need at least one constructor")
        valid : Unit <- TD.validate_constructors(constructors, parameters, operations, types)
        validate_types_indexed(tail, types, operations, repeated)

def validate_types(+pending: List<&2, M.DataType>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, Unit>:
  repeated = repeated_identities(type_identities(pending), Map.new(&2, Set()), Map.new(&2, Set()))
  validate_types_indexed(pending, types, operations, repeated)

def validate_operations_indexed(pending: List<&2, M.Operation>, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +repeated: IdentitySet()) -> Result<&2, &2, M.Diagnostic, Unit>:
  match pending:
    case Nil{}:
      Done{Unit{}}
    case M.Operation{+identity, parameter, result} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        allowed : Unit <- TD.valid_operation_identity(identity)
        unique : Unit <- require_unique_identity(identity_present(repeated, identity), identity)
        p : Unit <- TD.validate_template(parameter, None{}, operations, types, M.type_id_show(identity))
        r : Unit <- TD.validate_template(result, None{}, operations, types, M.type_id_show(identity))
        validate_operations_indexed(tail, operations, types, repeated)
    case M.OperationTemplate{+identity, +parameters, parameter, result} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        allowed : Unit <- TD.valid_operation_identity(identity)
        p : Unit <- TD.validate_template(parameter, Some{parameters}, operations, types, M.type_id_show(identity))
        r : Unit <- TD.validate_template(result, Some{parameters}, operations, types, M.type_id_show(identity))
        validate_operations_indexed(tail, operations, types, repeated)
    case head <> tail:
      Fail{M.Diagnostic{"unspecialized_effect", "effect", "effect instances must be specialized before checking"}}

def validate_operations(+operations: List<&2, M.Operation>, types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Unit>:
  repeated = repeated_identities(operation_identities(operations), Map.new(&2, Set()), Map.new(&2, Set()))
  validate_operations_indexed(operations, operations, types, repeated)

def lambda_ids(nodes: List<&2, D.Node>) -> List<&2, Nat>:
  match nodes:
    case Nil{}:
      Nil{}
    case D.Node{name, references, lambdas} <> tail:
      List.append(&2, Nat, lambdas, lambda_ids(tail))

def lambda_names(identities: List<&2, Nat>) -> List<&2, String>:
  match identities:
    case Nil{}:
      Nil{}
    case head <> tail:
      Nat.show(head) <> lambda_names(tail)

def unique_lambdas(identities: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, Unit>:
  +names = lambda_names(identities)
  unique_names_indexed(names, repeated_names(names, Set.new(), Set.new()), "duplicate_lambda", "lambda identity must be unique within its module")


def validate_module(module: M.Module) -> Result<&2, &2, M.Diagnostic, Unit>:
  M.Module{+constants, +functions, +types, +operations} = module
  +declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  do Result<&2, &2, M.Diagnostic, Unit>:
    valid_types : Unit <- validate_types(types, types, operations)
    valid_operations : Unit <- validate_operations(operations, types)
    unique_names(List.append(&2, String, G.names(declarations), all_constructor_names(types)))

# The planner calls module_graph before creating checking jobs. Its group
# subsets retain the same declarations and catalog, so their dependency graphs
# can be rebuilt without validating the full catalog for every group.
def module_graph_validated(module: M.Module) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  M.Module{constants, functions, types, operations} = module
  do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
    fns : List<&2, D.Node> <- D.function_nodes(functions)
    consts : List<&2, D.Node> <- D.constant_nodes(constants)
    +graph : List<&2, D.Node> = List.append(&2, D.Node, fns, consts)
    lambdas : Unit <- unique_lambdas(lambda_ids(graph))
    return graph

def module_graph(+module: M.Module) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
    valid : Unit <- validate_module(module)
    module_graph_validated(module)

def checked_signature(ty: M.Ty, name: String, variables: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, M.Signature>:
  match ty:
    case M.FunctionTy{parameter, result, effects}:
      Done{M.Signature{name, parameter, result, variables, R.canonical(effects)}}
    case other:
      Fail{M.Diagnostic{"internal_error", name, "function does not have an arrow type"}}

def resolve_binding(found: Maybe<&2, I.Binding>, +substitutions: T.Substitutions, subject: String) -> Result<&2, &2, M.Diagnostic, I.Binding>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", subject, "missing inferred binding"}}
    case Some{I.Binding{name, ty, variables, predicates}}:
      do Result<&2, &2, M.Diagnostic, I.Binding>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        needs : List<&2, M.Predicate> <- C.resolve_list(substitutions, predicates)
        return I.Binding{name, resolved, variables, needs}

def binding_signature(binding: I.Binding) -> Result<&2, &2, M.Diagnostic, M.Signature>:
  I.Binding{name, ty, variables, predicates} = binding
  checked_signature(ty, name, variables)

def signature_effects(signature: M.Signature) -> List<&2, M.Effect>:
  M.Signature{name, parameter, result, variables, effects} = signature
  R.metadata(R.operation_set(effects))

def function_results(functions: List<&2, M.Function>, +bindings: List<&2, I.Binding>, +substitutions: T.Substitutions, +calls: Set()) -> Result<&2, &2, M.Diagnostic, List<&2, M.CheckedFunction>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.CheckedFunction>>:
        binding : I.Binding <- resolve_binding(I.lookup_binding(bindings, name), substitutions, name)
        +signature : M.Signature <- binding_signature(binding)
        rest : List<&2, M.CheckedFunction> <- function_results(tail, bindings, substitutions, calls)
        prepared : M.Expr <- Demand.expression(body, calls)
        return M.CheckedFunction{M.Function{name, exported, parameter, p, r, prepared}, signature, signature_effects(signature)} <> rest

def checked_constant(constant: M.Constant, binding: I.Binding) -> M.CheckedConstant:
  I.Binding{name, ty, variables, predicates} = binding
  M.CheckedConstant{constant, ty, variables}

def constant_results(constants: List<&2, M.Constant>, +bindings: List<&2, I.Binding>, +substitutions: T.Substitutions, +calls: Set()) -> Result<&2, &2, M.Diagnostic, List<&2, M.CheckedConstant>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.Constant{+name, exported, annotation, value} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.CheckedConstant>>:
        binding : I.Binding <- resolve_binding(I.lookup_binding(bindings, name), substitutions, name)
        rest : List<&2, M.CheckedConstant> <- constant_results(tail, bindings, substitutions, calls)
        prepared : M.Expr <- Demand.expression(value, calls)
        return checked_constant(M.Constant{name, exported, annotation, prepared}, binding) <> rest

def coverage_constraints(definitions: List<&2, I.Definition>) -> List<&2, I.Coverage>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      List.append(&2, I.Coverage, coverage, coverage_constraints(tail))

def reflection_constraints(definitions: List<&2, I.Definition>) -> List<&2, I.Reflection>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      List.append(&2, I.Reflection, reflections, reflection_constraints(tail))

def reflected_type(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match ty:
    case M.FunctionTy{parameter, result, M.EffectRow{operations, M.ClosedRow{}}}:
      Done{Unit{}}
    case M.FunctionTy{parameter, result, effects}:
      Fail{M.Diagnostic{"open_effect_descriptor", subject, "effect reflection requires a closed function effect row"}}
    case other:
      Fail{M.Diagnostic{"invalid_effect_descriptor", subject, "effect reflection requires a named function"}}

def reflected_binding(binding: I.Binding, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  I.Binding{name, ty, variables, predicates} = binding
  reflected_type(ty, subject)

def check_reflections(reflections: List<&2, I.Reflection>, +bindings: List<&2, I.Binding>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, Unit>:
  match reflections:
    case Nil{}:
      Done{Unit{}}
    case I.Reflection{callee, +subject, instantiated_type, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        resolved : M.Ty <- T.resolve(substitutions, instantiated_type)
        closed : Unit <- reflected_type(resolved, subject)
        check_reflections(tail, bindings, substitutions)

def require_let_pure(effects: List<&2, M.Effect>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match effects:
    case Nil{}:
      Done{Unit{}}
    case M.OperationEffect{identity} <> tail:
      Fail{M.Diagnostic{"let_effect", subject, "let requires a pure RHS; bind effectful computations with use name <- expression"}}

def finish(module: M.Module, +environment: G.Environment) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  M.Module{constants, functions, +types, operations} = module
  do Result<&2, &2, M.Diagnostic, M.CheckedModule>:
    +definitions : List<&2, I.Definition> = G.env_definitions(environment)
    +bindings : List<&2, I.Binding> = G.env_bindings(environment)
    +substitutions : T.Substitutions = I.substitutions_of(G.env_state(environment))
    coverage : Unit <- P.check(coverage_constraints(definitions), substitutions, types)
    reflection : Unit <- check_reflections(reflection_constraints(definitions), bindings, substitutions)
    +calls : Set() = Demand.sites(coverage_constraints(definitions), Set.new())
    checked_fns : List<&2, M.CheckedFunction> <- function_results(functions, bindings, substitutions, calls)
    checked_consts : List<&2, M.CheckedConstant> <- constant_results(constants, bindings, substitutions, calls)
    return M.CheckedModule{checked_consts, checked_fns, types, operations}

def check_module(+module: M.Module) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  M.Module{constants, functions, types, operations} = module
  declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  do Result<&2, &2, M.Diagnostic, M.CheckedModule>:
    graph : List<&2, D.Node> <- module_graph(module)
    environment : G.Environment <- G.infer(declarations, graph, operations, types)
    finish(module, environment)
