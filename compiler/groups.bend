import Base
import ./model.bend as M
import ./types.bend as T
import ./type_data.bend as TD
import ./infer.bend as I
import ./globals.bend as G
import ./check.bend as Check
import ./dependency.bend as D
import ./effects.bend as E
import ./effect_rows.bend as R
import ./index.bend as Index
import ./constraints.bend as C

type Job is Data:
  Job{members: List<&2, String>, dependencies: List<&2, String>, type_dependencies: List<&2, M.TypeId>}

type InterfaceKind is Data:
  FunctionInterface{}
  ConstantInterface{}

# ParameterTy indices bind within this interface, never within another job's
# inference state. An interface contains no unresolved monomorphic variables.
type Interface is Data:
  Interface{name: String, kind: InterfaceKind, template: M.Ty, parameters: Nat, effects: List<&2, M.Effect>, predicates: List<&2, M.Predicate>}

type CheckedGroup is Data:
  CheckedGroup{checked: M.CheckedModule, interfaces: List<&2, Interface>, uses: List<&2, C.UsePlan>}

def checked_interfaces(group: CheckedGroup) -> List<&2, Interface>:
  CheckedGroup{checked, interfaces, uses} = group
  interfaces

def checked_uses(group: CheckedGroup) -> List<&2, C.UsePlan>:
  CheckedGroup{checked, interfaces, uses} = group
  uses

def interface_names(interfaces: List<&2, Interface>) -> List<&2, String>:
  match interfaces:
    case Nil{}:
      Nil{}
    case Interface{name, kind, template, parameters, effects, predicates} <> tail:
      name <> interface_names(tail)

def interface_functions(interfaces: List<&2, Interface>) -> List<&2, String>:
  match interfaces:
    case Nil{}:
      Nil{}
    case Interface{name, FunctionInterface{}, template, parameters, effects, predicates} <> tail:
      name <> interface_functions(tail)
    case head <> tail:
      interface_functions(tail)

def indices_accumulated(count: Nat, +start: Nat, reversed: List<&2, Nat>) -> List<&2, Nat>:
  match count:
    case 0n:
      List.reverse(&2, Nat, reversed)
    case 1n+rest:
      indices_accumulated(rest, 1n+start, start <> reversed)

def indices(count: Nat, start: Nat) -> List<&2, Nat>:
  indices_accumulated(count, start, Nil{})

def same_effects(left: List<&2, M.Effect>, right: List<&2, M.Effect>) -> Bool:
  match left right:
    case Nil{} Nil{}:
      True{}
    case a <> left b <> right:
      Bool.and(E.effect_equal(a, b), same_effects(left, right))
    case _ _:
      False{}

def valid_interface_effects(consistent: Bool, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match consistent:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"invalid_interface", subject, "dependency effect metadata differs from its function row"}}

def valid_interface_kind(kind: InterfaceKind, template: M.Ty, parameters: Nat, effects: List<&2, M.Effect>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match kind template effects:
    case FunctionInterface{} M.FunctionTy{parameter, result, row} metadata:
      valid_interface_effects(same_effects(E.canonical(metadata), R.metadata(R.operation_set(row))), subject)
    case ConstantInterface{} _ Nil{}:
      Done{Unit{}}
    case _ _ _:
      Fail{M.Diagnostic{"invalid_interface", subject, "dependencies require pure constant initializers or function interfaces"}}

def validate_predicate_templates(templates: List<&2, M.TypeId>, +operations: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match templates:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        declared : M.Operation <- I.operation_template(operations, head)
        validate_predicate_templates(tail, operations)

def validate_operation_arity(declared: M.Operation, count: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match declared:
    case M.OperationTemplate{identity, parameters, parameter, result}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, Nat.is_eq(parameters, count), Done{Unit{}}, Fail{M.Diagnostic{"invalid_interface", subject, "qualified operation predicate has the wrong number of type arguments"}})
    case _:
      Fail{M.Diagnostic{"invalid_interface", subject, "qualified operation predicate does not name a generic operation template"}}

def validate_predicate_arity(predicate: M.Predicate, operations: List<&2, M.Operation>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match predicate:
    case M.OperationPredicate{template, +arguments, function_type}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        declared : M.Operation <- I.operation_template(operations, template)
        validate_operation_arity(declared, List.length(&2, M.Ty, arguments), subject)
    case _:
      Done{Unit{}}

def validate_predicates(predicates: List<&2, M.Predicate>, +parameters: Nat, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match predicates:
    case Nil{}:
      Done{Unit{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        valid : Unit <- TD.validate_template(C.shape_type(head), Some{parameters}, operations, types, subject)
        source_names : List<&2, Nat> <- C.free(head)
        known : Unit <- validate_predicate_templates(C.predicate_templates([head]), operations)
        arity : Unit <- validate_predicate_arity(head, operations, subject)
        validate_predicates(tail, parameters, operations, types, subject)

def predicate_shapes_accumulated(predicates: List<&2, M.Predicate>, reversed: List<&2, M.Ty>) -> List<&2, M.Ty>:
  match predicates:
    case Nil{}:
      List.reverse(&2, M.Ty, reversed)
    case head <> tail:
      predicate_shapes_accumulated(tail, C.shape_type(head) <> reversed)

def predicate_shapes(predicates: List<&2, M.Predicate>) -> List<&2, M.Ty>:
  predicate_shapes_accumulated(predicates, Nil{})

# T.parameter_kinds(ManyTypes) checks each head with the same remaining fuel
# used by the list tail, then right-folds merge_kinds. Keep its per-branch
# complexity limit and first-error order while avoiding nested Result binds
# for a dependency interface with thousands of predicates.
def scheme_kind_groups(+fuel: Nat, pending: List<&2, M.Ty>, reversed: List<&2, T.ParameterKinds>) -> Result<&2, &2, M.Diagnostic, List<&2, T.ParameterKinds>>:
  match fuel pending:
    case 0n _:
      Fail{T.complexity()}
    case 1n+rest Nil{}:
      Done{reversed}
    case 1n+ +rest head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, T.ParameterKinds>>:
        first : T.ParameterKinds <- T.parameter_kinds(rest, T.OneType{head})
        scheme_kind_groups(rest, tail, first <> reversed)

def scheme_kind_merge(reversed: List<&2, T.ParameterKinds>, merged: T.ParameterKinds) -> T.ParameterKinds:
  match reversed:
    case Nil{}:
      merged
    case head <> tail:
      scheme_kind_merge(tail, T.merge_kinds(head, merged))

def scheme_kinds(fuel: Nat, pending: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, T.ParameterKinds>:
  do Result<&2, &2, M.Diagnostic, T.ParameterKinds>:
    reversed : List<&2, T.ParameterKinds> <- scheme_kind_groups(fuel, pending, Nil{})
    return scheme_kind_merge(reversed, T.ParameterKinds{Nil{}, Nil{}})

# A quantified index has one kind across the entire imported scheme. Checking
# the template and predicates separately misses a type/row collision between
# them, even though each individual tree is well formed.
def validate_scheme_kinds(template: M.Ty, predicates: List<&2, M.Predicate>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  do Result<&2, &2, M.Diagnostic, Unit>:
    kinds : T.ParameterKinds <- scheme_kinds(U32.to_nat(65536), template <> predicate_shapes(predicates))
    T.kind_check(kinds, subject)

def import_interfaces(interfaces: List<&2, Interface>, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +start: Nat) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match interfaces:
    case Nil{}:
      Done{G.Environment{Nil{}, Nil{}, I.State{T.empty(), start, MTip{}}}}
    case Interface{+name, +kind, +template, +parameters, +effects, +predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        valid : Unit <- TD.validate_template(template, Some{parameters}, operations, types, name)
        source_names : List<&2, Nat> <- C.free(M.TypeRepPredicate{template})
        compatible : Unit <- valid_interface_kind(kind, template, parameters, effects, name)
        valid_needs : Unit <- validate_predicates(predicates, parameters, operations, types, name)
        kinds : Unit <- validate_scheme_kinds(template, predicates, name)
        +arguments : List<&2, M.Ty> = TD.fresh_arguments(parameters, start)
        +ty : M.Ty <- T.parameters(arguments, 0n, template)
        needs : List<&2, M.Predicate> <- C.instantiate_parameters(arguments, predicates, 0n)
        +rest : G.Environment <- import_interfaces(tail, operations, types, Nat.add(start, parameters))
        return G.Environment{I.Binding{name, ty, indices(parameters, start), needs} <> G.env_bindings(rest), I.Definition{name, I.pure(ty)} <> G.env_definitions(rest), G.env_state(rest)}

def template_type_sequential(variables: List<&2, Nat>, +index: Nat, ty: M.Ty) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match variables:
    case Nil{}:
      Done{ty}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        replaced : M.Ty <- T.replace(ty, head, M.ParameterTy{index})
        template_type_sequential(tail, 1n+index, replaced)

def template_type(variables: List<&2, Nat>, index: Nat, ty: M.Ty) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match variables:
    case Nil{}:
      Done{ty}
    case head <> Nil{}:
      T.replace(ty, head, M.ParameterTy{index})
    case head <> tail:
      T.parameterize_type(ty, T.parameter_mapping(head <> tail, index))

def canonical_work(+fuel: Nat, work: T.TypeWork) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match fuel work:
    case 0n _:
      Fail{T.complexity()}
    case 1n+rest T.OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        ps : List<&2, M.Ty> <- canonical_work(rest, T.OneType{parameter})
        rs : List<&2, M.Ty> <- canonical_work(rest, T.OneType{result})
        p : M.Ty <- T.first_type(ps)
        r : M.Ty <- T.first_type(rs)
        return [M.FunctionTy{p, r, R.canonical(effects)}]
    case 1n+rest T.OneType{M.StateProviderTy{read, write, state}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        values : List<&2, M.Ty> <- canonical_work(rest, T.OneType{state})
        value : M.Ty <- T.first_type(values)
        return [M.StateProviderTy{read, write, value}]
    case 1n+rest T.OneType{M.ProviderTy{identity, effects}}:
      Done{[M.ProviderTy{identity, R.canonical(effects)}]}
    case 1n+rest T.OneType{M.AppliedTy{identity, arguments}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        values : List<&2, M.Ty> <- canonical_work(rest, T.ManyTypes{arguments})
        return [M.AppliedTy{identity, values}]
    case 1n+rest T.OneType{M.ProductTy{elements}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        values : List<&2, M.Ty> <- canonical_work(rest, T.ManyTypes{elements})
        return [M.ProductTy{values}]
    case 1n+rest T.OneType{M.ArrayTy{element}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        values : List<&2, M.Ty> <- canonical_work(rest, T.OneType{element})
        value : M.Ty <- T.first_type(values)
        return [M.ArrayTy{value}]
    case 1n+rest T.OneType{other}:
      Done{[other]}
    case 1n+rest T.ManyTypes{Nil{}}:
      Done{Nil{}}
    case 1n+rest T.ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        hs : List<&2, M.Ty> <- canonical_work(rest, T.OneType{head})
        h : M.Ty <- T.first_type(hs)
        ts : List<&2, M.Ty> <- canonical_work(rest, T.ManyTypes{tail})
        return h <> ts

# Interface variable lists can be much wider than the host stack. Keep the
# count local to this export path; Bend Base's generic List.length is unchanged.
def interface_variable_count(variables: List<&2, Nat>, count: Nat) -> Nat:
  match variables:
    case Nil{}:
      count
    case head <> tail:
      interface_variable_count(tail, Nat.add(count, 1n))

def closed_interface(open: List<&2, Nat>, +variables: List<&2, Nat>, name: String, kind: InterfaceKind, ty: M.Ty, effects: List<&2, M.Effect>, predicates: List<&2, M.Predicate>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match open:
    case Nil{}:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        template : M.Ty <- template_type(variables, 0n, ty)
        needs : List<&2, M.Predicate> <- C.parameterize_list(T.parameter_mapping(variables, 0n), predicates)
        return [Interface{name, kind, template, interface_variable_count(variables, 0n), E.canonical(effects), needs}]
    case head <> tail:
      Fail{M.Diagnostic{"invalid_interface", name, "a dependency interface cannot expose an unquantified inference variable"}}

def export_interface(name: String, kind: InterfaceKind, ty: M.Ty, +variables: List<&2, Nat>, effects: List<&2, M.Effect>, predicates: List<&2, M.Predicate>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
    normalized : List<&2, M.Ty> <- canonical_work(Nat.mul(256n, 256n), T.OneType{ty})
    +canonical : M.Ty <- T.first_type(normalized)
    type_free : List<&2, Nat> <- T.free(canonical)
    +needs : List<&2, M.Predicate> = C.canonical_predicates(predicates, Nil{})
    predicate_free : List<&2, Nat> <- C.free_list(needs)
    +free : List<&2, Nat> = T.union(type_free, predicate_free)
    closed_interface(T.difference(free, variables), free, name, kind, canonical, effects, needs)

def binding_predicates_found(found: Maybe<&2, I.Binding>, substitutions: T.Substitutions, name: String) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "checked interface is missing its qualified binding"}}
    case Some{I.Binding{found, ty, variables, predicates}}:
      C.resolve_list(substitutions, predicates)

def binding_predicates(bindings: List<&2, I.Binding>, +name: String, substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  binding_predicates_found(I.lookup_binding(bindings, name), substitutions, name)

def function_interfaces(functions: List<&2, M.CheckedFunction>, +bindings: List<&2, I.Binding>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedFunction{function, M.Signature{+name, parameter, result, variables, row}, effects} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        predicates : List<&2, M.Predicate> <- binding_predicates(bindings, name, substitutions)
        head : List<&2, Interface> <- export_interface(name, FunctionInterface{}, M.FunctionTy{parameter, result, row}, variables, effects, predicates)
        rest : List<&2, Interface> <- function_interfaces(tail, bindings, substitutions)
        return List.append(&2, Interface, head, rest)

def constant_interfaces(constants: List<&2, M.CheckedConstant>, +bindings: List<&2, I.Binding>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedConstant{M.Constant{+name, exported, annotation, value}, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        predicates : List<&2, M.Predicate> <- binding_predicates(bindings, name, substitutions)
        head : List<&2, Interface> <- export_interface(name, ConstantInterface{}, ty, variables, Nil{}, predicates)
        rest : List<&2, Interface> <- constant_interfaces(tail, bindings, substitutions)
        return List.append(&2, Interface, head, rest)

def checked_function_names(functions: List<&2, M.CheckedFunction>) -> List<&2, String>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{M.Function{name, exported, parameter, p, r, body}, signature, effects} <> tail:
      name <> checked_function_names(tail)

def checked_constant_names(constants: List<&2, M.CheckedConstant>) -> List<&2, String>:
  match constants:
    case Nil{}:
      Nil{}
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> tail:
      name <> checked_constant_names(tail)

def append_own_uses(owned: Bool, inference: I.Inference, rest: List<&2, C.UsePlan>, substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, C.UsePlan>>:
  match owned:
    case False{}:
      Done{rest}
    case True{}:
      do Result<&2, &2, M.Diagnostic, List<&2, C.UsePlan>>:
        current : List<&2, C.UsePlan> <- C.resolve_uses(I.inference_uses(inference), substitutions)
        return List.append(&2, C.UsePlan, current, rest)

def own_uses(definitions: List<&2, I.Definition>, +names: List<&2, String>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, C.UsePlan>>:
  match definitions:
    case Nil{}:
      Done{Nil{}}
    case I.Definition{+name, inference} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.UsePlan>>:
        rest : List<&2, C.UsePlan> <- own_uses(tail, names, substitutions)
        append_own_uses(D.contains(names, name), inference, rest, substitutions)

def checked_group(+checked: M.CheckedModule, +environment: G.Environment) -> Result<&2, &2, M.Diagnostic, CheckedGroup>:
  M.CheckedModule{+constants, +functions, types, operations} = checked
  +bindings = G.env_bindings(environment)
  +substitutions = I.substitutions_of(G.env_state(environment))
  do Result<&2, &2, M.Diagnostic, CheckedGroup>:
    fns : List<&2, Interface> <- function_interfaces(functions, bindings, substitutions)
    consts : List<&2, Interface> <- constant_interfaces(constants, bindings, substitutions)
    uses : List<&2, C.UsePlan> <- own_uses(G.env_definitions(environment), List.append(&2, String, checked_function_names(functions), checked_constant_names(constants)), substitutions)
    return CheckedGroup{checked, List.append(&2, Interface, fns, consts), uses}

# The deferred dispatch requirements of one checked group. Their types are
# resolved against the group's final substitution; every variable they still
# mention is numbered below `next`, and variables are shared only within the
# group (an SCC is inferred with one state).
type Resolution is Data:
  Resolution{declaration: String, identity: Nat, dispatch: M.Dispatch, member: String, templates: List<&2, M.TypeId>, left: M.Ty, right: M.Ty, result: M.Ty, invocation: Maybe<&2, M.EffectRow>, ambient: M.EffectRow}

# `members` holds the group's own declaration types and residual predicates
# under the same numbering, so resolution can detect changes to either.
# `generalized` holds the variables local lets generalized that a requirement
# mentions: binding one would change a local scheme, which no interface shows.
type GroupNeeds is Data:
  GroupNeeds{next: Nat, needs: List<&2, Resolution>, members: List<&2, I.Binding>, generalized: List<&2, Nat>}

type Resolving is Data:
  Resolving{group: CheckedGroup, needs: List<&2, GroupNeeds>}

def resolving_group(value: Resolving) -> CheckedGroup:
  Resolving{group, needs} = value
  group

# A closed type mentions no inference, generalized, annotation or row variable,
# so no caller can instantiate it differently.
def closed_types(fuel: Nat, pending: List<&2, M.Ty>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      True{}
    case 0n _:
      False{}
    case 1n+rest M.VariableTy{index} <> tail:
      False{}
    case 1n+rest M.ParameterTy{index} <> tail:
      False{}
    case 1n+rest M.FreeTy{scope, name} <> tail:
      False{}
    case 1n+rest M.FunctionTy{parameter, result, M.EffectRow{operations, M.ClosedRow{}}} <> tail:
      closed_types(rest, parameter <> result <> tail)
    case 1n+rest M.FunctionTy{parameter, result, row} <> tail:
      False{}
    case 1n+rest M.ProviderTy{identity, M.EffectRow{operations, M.ClosedRow{}}} <> tail:
      closed_types(rest, tail)
    case 1n+rest M.ProviderTy{identity, row} <> tail:
      False{}
    case 1n+rest M.StateProviderTy{read, write, state} <> tail:
      closed_types(rest, state <> tail)
    case 1n+rest M.AppliedTy{identity, arguments} <> tail:
      closed_types(rest, List.append(&2, M.Ty, arguments, tail))
    case 1n+rest M.ProductTy{elements} <> tail:
      closed_types(rest, List.append(&2, M.Ty, elements, tail))
    case 1n+rest M.ArrayTy{element} <> tail:
      closed_types(rest, element <> tail)
    case 1n+rest head <> tail:
      closed_types(rest, tail)

def resolved_invocation(invocation: Maybe<&2, M.EffectRow>, substitutions: T.Substitutions) -> Maybe<&2, M.EffectRow>:
  match invocation:
    case None{}:
      None{}
    case Some{row}:
      Some{T.resolve_row(substitutions, row)}

def resolved_need(left: Result<&2, &2, M.Diagnostic, M.Ty>, right: Result<&2, &2, M.Diagnostic, M.Ty>, result: Result<&2, &2, M.Diagnostic, M.Ty>, declaration: String, identity: Nat, dispatch: M.Dispatch, member: String, templates: List<&2, M.TypeId>, invocation: Maybe<&2, M.EffectRow>, ambient: M.EffectRow, rest: List<&2, Resolution>) -> List<&2, Resolution>:
  match left right result:
    case Done{l} Done{r} Done{value}:
      Resolution{declaration, identity, dispatch, member, templates, l, r, value, invocation, ambient} <> rest
    case _ _ _:
      rest

def coverage_needs(coverage: List<&2, I.Coverage>, +declaration: String, +substitutions: T.Substitutions, reversed: List<&2, Resolution>) -> List<&2, Resolution>:
  match coverage:
    case Nil{}:
      List.reverse(&2, Resolution, reversed)
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      coverage_needs(tail, declaration, substitutions, resolved_need(T.resolve(substitutions, left), T.resolve(substitutions, right), T.resolve(substitutions, result), declaration, identity, dispatch, member, templates, resolved_invocation(invocation, substitutions), T.resolve_row(substitutions, ambient), reversed))
    case head <> tail:
      coverage_needs(tail, declaration, substitutions, reversed)

def definition_needs(definitions: List<&2, I.Definition>, +substitutions: T.Substitutions) -> List<&2, Resolution>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      List.append(&2, Resolution, coverage_needs(coverage, name, substitutions, Nil{}), definition_needs(tail, substitutions))

def member_resolved(name: String, resolved: Result<&2, &2, M.Diagnostic, M.Ty>, predicates: Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>, rest: List<&2, I.Binding>) -> List<&2, I.Binding>:
  match resolved predicates:
    case Done{ty} Done{resolved_predicates}:
      I.Binding{name, ty, Nil{}, resolved_predicates} <> rest
    case _ _:
      rest

def member_binding(member: Bool, name: String, ty: M.Ty, predicates: List<&2, M.Predicate>, +substitutions: T.Substitutions, rest: List<&2, I.Binding>) -> List<&2, I.Binding>:
  match member:
    case False{}:
      rest
    case True{}:
      member_resolved(name, T.resolve(substitutions, ty), C.resolve_list(substitutions, predicates), rest)

# Member types and predicates before generalization: generalization closes
# unconstrained rows, which could hide an effect a resolved call adds.
def member_bindings(definitions: List<&2, I.Definition>, +members: Set(), +substitutions: T.Substitutions) -> List<&2, I.Binding>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{+name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      +rest = member_bindings(tail, members, substitutions)
      member_binding(D.member(members, name), name, ty, predicates, substitutions, rest)

# The let-generalized variables under the group's final substitution. A
# witness that cannot be resolved leaves the group without requirements, so
# resolution never rewrites a group whose local schemes it cannot see.
def witness_variables(free: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, found: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    variables : List<&2, Nat> <- free
    return T.union(variables, found)

def coverage_generalized(coverage: List<&2, I.Coverage>, +substitutions: T.Substitutions, found: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match coverage:
    case Nil{}:
      Done{found}
    case I.LetGeneralized{witness} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : M.Ty <- T.resolve(substitutions, witness)
        variables : List<&2, Nat> <- witness_variables(T.free(resolved), found)
        coverage_generalized(tail, substitutions, variables)
    case head <> tail:
      coverage_generalized(tail, substitutions, found)

def definition_generalized(definitions: List<&2, I.Definition>, +substitutions: T.Substitutions, found: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match definitions:
    case Nil{}:
      Done{found}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections, predicates, uses}} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        variables : List<&2, Nat> <- coverage_generalized(coverage, substitutions, found)
        definition_generalized(tail, substitutions, variables)

def group_needs(needs: List<&2, Resolution>, next: Nat, members: List<&2, I.Binding>, generalized: Result<&2, &2, M.Diagnostic, List<&2, Nat>>) -> List<&2, GroupNeeds>:
  match needs generalized:
    case Nil{} _:
      Nil{}
    case _ Fail{diagnostic}:
      Nil{}
    case head <> tail Done{variables}:
      [GroupNeeds{next, head <> tail, members, variables}]

def environment_needs(collect: Bool, environment: G.Environment, names: List<&2, String>) -> List<&2, GroupNeeds>:
  match collect:
    case False{}:
      Nil{}
    case True{}:
      G.Environment{bindings, +definitions, +state} = environment
      +substitutions = I.substitutions_of(state)
      group_needs(definition_needs(definitions, substitutions), I.next_of(state), member_bindings(definitions, Set.from_list(names), substitutions), definition_generalized(definitions, substitutions, Nil{}))

def check_group_resolving_graph(+module: M.Module, +dependencies: List<&2, Interface>, graph_result: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>, collect: Bool) -> Result<&2, &2, M.Diagnostic, Resolving>:
  M.Module{constants, functions, +types, +operations} = module
  +declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  do Result<&2, &2, M.Diagnostic, Resolving>:
    graph : List<&2, D.Node> <- graph_result
    unique : Unit <- Check.unique_names(List.append(&2, String, interface_names(dependencies), List.append(&2, String, G.names(declarations), Check.all_constructor_names(types))))
    imported : G.Environment <- import_interfaces(dependencies, operations, types, 0n)
    +environment : G.Environment <- G.infer_with(declarations, graph, operations, types, imported, interface_functions(dependencies))
    checked : M.CheckedModule <- Check.finish(module, environment)
    group : CheckedGroup <- checked_group(checked, environment)
    return Resolving{group, environment_needs(collect, environment, G.names(declarations))}

def check_group_graph(+module: M.Module, +dependencies: List<&2, Interface>, graph_result: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>) -> Result<&2, &2, M.Diagnostic, CheckedGroup>:
  do Result<&2, &2, M.Diagnostic, CheckedGroup>:
    resolved : Resolving <- check_group_resolving_graph(module, dependencies, graph_result, False{})
    return resolving_group(resolved)

def check_group(+module: M.Module, +dependencies: List<&2, Interface>) -> Result<&2, &2, M.Diagnostic, CheckedGroup>:
  check_group_graph(module, dependencies, Check.module_graph(module))

# Only scheduler jobs derived from a successful whole-module graph may use this
# path. Keep imported-interface validation and local inference/coverage checks.
def check_group_planned(+module: M.Module, +dependencies: List<&2, Interface>) -> Result<&2, &2, M.Diagnostic, CheckedGroup>:
  check_group_graph(module, dependencies, Check.module_graph_validated(module))

# Dispatch resolution also asks for the closed requirements left in the group.
def check_group_resolving(+module: M.Module, +dependencies: List<&2, Interface>) -> Result<&2, &2, M.Diagnostic, Resolving>:
  check_group_resolving_graph(module, dependencies, Check.module_graph(module), True{})

def check_group_resolving_planned(+module: M.Module, +dependencies: List<&2, Interface>) -> Result<&2, &2, M.Diagnostic, Resolving>:
  check_group_resolving_graph(module, dependencies, Check.module_graph_validated(module), True{})

type Usage is Data:
  Usage{nominals: List<&2, M.TypeId>}

type UsageWork is Data:
  ExpressionUsage{value: M.Expr}
  ArmsUsage{values: List<&2, M.MatchArm<M.Expr>>}
  PatternUsage{value: M.Pattern}
  PatternsUsage{values: List<&2, M.Pattern>}
  TypeUsage{value: M.Ty}
  TypesUsage{values: List<&2, M.Ty>}
  PredicateUsage{value: M.Predicate}
  PredicatesUsage{values: List<&2, M.Predicate>}
  ExpressionsUsage{values: List<&2, M.Expr>}
  CollectedExpressionsUsage{values: List<&2, M.Expr>, reversed: List<&2, Usage>}
  CollectedPatternsUsage{values: List<&2, M.Pattern>, reversed: List<&2, Usage>}
  CollectedTypesUsage{values: List<&2, M.Ty>, reversed: List<&2, Usage>}
  CollectedPredicatesUsage{values: List<&2, M.Predicate>, reversed: List<&2, Usage>}
  CollectedArmsUsage{values: List<&2, M.MatchArm<M.Expr>>, reversed: List<&2, Usage>}

def contains_type(identities: List<&2, M.TypeId>, +identity: M.TypeId) -> Bool:
  match identities:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(M.type_id_equal(head, identity), contains_type(tail, identity))

def put_type_if(present: Bool, identities: List<&2, M.TypeId>, identity: M.TypeId) -> List<&2, M.TypeId>:
  match present:
    case True{}:
      identities
    case False{}:
      identity <> identities

def union_types(left: List<&2, M.TypeId>, +right: List<&2, M.TypeId>) -> List<&2, M.TypeId>:
  match left:
    case Nil{}:
      right
    case +head <> tail:
      union_types(tail, put_type_if(contains_type(right, head), right, head))

def combine_usage(left: Usage, right: Usage) -> Usage:
  Usage{lt} = left
  Usage{rt} = right
  Usage{union_types(lt, rt)}

def constructor_usage(found: Maybe<&2, M.TypeId>) -> Usage:
  match found:
    case None{}:
      Usage{Nil{}}
    case Some{identity}:
      Usage{[identity]}

def constructor_index_entries(constructors: List<&2, M.Constructor>, +identity: M.TypeId, index: Map<&2, M.TypeId>) -> Map<&2, M.TypeId>:
  match constructors:
    case Nil{}:
      index
    case M.Constructor{name, payload, fields} <> tail:
      constructor_index_entries(tail, identity, Index.set(M.TypeId, index, name, identity))

def constructor_index(types: List<&2, M.DataType>, index: Map<&2, M.TypeId>) -> Map<&2, M.TypeId>:
  match types:
    case Nil{}:
      index
    case M.DataType{identity, parameters, constructors} <> tail:
      constructor_index(tail, constructor_index_entries(constructors, identity, index))

def optional_type(ty: Maybe<&2, M.Ty>) -> M.Ty:
  match ty:
    case None{}:
      M.UnitTy{}
    case Some{value}:
      value

def optional_pattern(pattern: Maybe<&2, M.Pattern>) -> M.Pattern:
  match pattern:
    case None{}:
      M.WildcardPattern{}
    case Some{value}:
      value

def collected_usage(reversed: List<&2, Usage>, result: Usage) -> Usage:
  match reversed:
    case Nil{}:
      result
    case head <> tail:
      collected_usage(tail, combine_usage(head, result))

def row_identities(rows: List<&2, M.EffectRow>) -> List<&2, M.TypeId>:
  match rows:
    case Nil{}:
      Nil{}
    case M.EffectRow{operations, tail} <> rest:
      List.append(&2, M.TypeId, operations, row_identities(rest))

# Wide arrays, tuple patterns and annotations must not grow the JS stack.
# Preserve the recursive walk's sibling fuel and right-associated merge order.
def effect_row_usage(row: M.EffectRow) -> Usage:
  M.EffectRow{operations, tail} = row
  Usage{operations}

def usage(+fuel: Nat, work: UsageWork, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, Usage>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "inference", "dependency metadata exceeded compiler traversal limit"}}
    case 1n+rest CollectedExpressionsUsage{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, ExpressionUsage{head}, types)
        usage(rest, CollectedExpressionsUsage{tail, found <> reversed}, types)
    case 1n+rest CollectedPatternsUsage{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, PatternUsage{head}, types)
        usage(rest, CollectedPatternsUsage{tail, found <> reversed}, types)
    case 1n+rest CollectedTypesUsage{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, TypeUsage{head}, types)
        usage(rest, CollectedTypesUsage{tail, found <> reversed}, types)
    case 1n+rest CollectedPredicatesUsage{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, PredicateUsage{head}, types)
        usage(rest, CollectedPredicatesUsage{tail, found <> reversed}, types)
    case 1n+rest CollectedArmsUsage{M.MatchArm{patterns, body} <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found_patterns : Usage <- usage(rest, PatternsUsage{patterns}, types)
        found_body : Usage <- usage(rest, ExpressionUsage{body}, types)
        usage(rest, CollectedArmsUsage{tail, found_body <> found_patterns <> reversed}, types)
    case 1n+rest CollectedExpressionsUsage{Nil{}, reversed}:
      Done{collected_usage(reversed, Usage{Nil{}})}
    case 1n+rest CollectedPatternsUsage{Nil{}, reversed}:
      Done{collected_usage(reversed, Usage{Nil{}})}
    case 1n+rest CollectedTypesUsage{Nil{}, reversed}:
      Done{collected_usage(reversed, Usage{Nil{}})}
    case 1n+rest CollectedPredicatesUsage{Nil{}, reversed}:
      Done{collected_usage(reversed, Usage{Nil{}})}
    case 1n+rest CollectedArmsUsage{Nil{}, reversed}:
      Done{collected_usage(reversed, Usage{Nil{}})}
    case 1n+rest ExpressionUsage{M.ConstructorRefExpr{constructor}}:
      Done{constructor_usage(Index.find(M.TypeId, types, constructor))}
    case 1n+rest ExpressionUsage{M.ConstructExpr{constructor, payload}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        nested : Usage <- usage(rest, ExpressionUsage{D.payload_expression(payload)}, types)
        return combine_usage(constructor_usage(Index.find(M.TypeId, types, constructor)), nested)
    case 1n+rest ExpressionUsage{M.ProductExpr{elements}}:
      usage(rest, ExpressionsUsage{elements}, types)
    case 1n+rest ExpressionUsage{M.ProjectExpr{value, index}}:
      usage(rest, ExpressionUsage{value}, types)
    case 1n+rest ExpressionUsage{M.ArrayExpr{elements}}:
      usage(rest, ExpressionsUsage{elements}, types)
    case 1n+rest ExpressionUsage{M.ForExpr{index, start, end, state, initial, body}}:
      usage(rest, ExpressionsUsage{[start, end, initial, body]}, types)
    case 1n+rest ExpressionUsage{M.ForeverExpr{state, initial, body}}:
      usage(rest, ExpressionsUsage{[initial, body]}, types)
    case 1n+rest ExpressionUsage{M.ArrayGenerateExpr{count, generator}}:
      usage(rest, ExpressionsUsage{[count, generator]}, types)
    case 1n+rest ExpressionUsage{M.ArrayFillExpr{count, value}}:
      usage(rest, ExpressionsUsage{[count, value]}, types)
    case 1n+rest ExpressionUsage{M.ArrayGetExpr{array, index}}:
      usage(rest, ExpressionsUsage{[array, index]}, types)
    case 1n+rest ExpressionUsage{M.ArraySetExpr{array, index, value}}:
      usage(rest, ExpressionsUsage{[array, index, value]}, types)
    case 1n+rest ExpressionUsage{M.AssociatedExpr{identity, dispatch, member, templates, left, right}}:
      usage(rest, ExpressionsUsage{[left, right]}, types)
    case 1n+rest ExpressionUsage{M.GenericOperationExpr{identity, template, arguments}}:
      usage(rest, TypesUsage{arguments}, types)
    case 1n+rest ExpressionUsage{M.ArrayLengthExpr{array}}:
      usage(rest, ExpressionUsage{array}, types)
    case 1n+rest ExpressionUsage{M.LambdaExpr{identity, parameter, p, r, body}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        annotations : Usage <- usage(rest, TypesUsage{[optional_type(p), optional_type(r)]}, types)
        nested : Usage <- usage(rest, ExpressionUsage{body}, types)
        return combine_usage(annotations, nested)
    case 1n+rest ExpressionUsage{M.ApplyExpr{callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{callee}, types)
        b : Usage <- usage(rest, ExpressionUsage{argument}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.CallExpr{callee, argument}}:
      usage(rest, ExpressionUsage{argument}, types)
    case 1n+rest ExpressionUsage{M.StateProviderExpr{read, write, initial}}:
      usage(rest, ExpressionUsage{initial}, types)
    case 1n+rest ExpressionUsage{M.ProviderExpr{identity, implementation}}:
      usage(rest, ExpressionUsage{implementation}, types)
    case 1n+rest ExpressionUsage{M.HandleExpr{provider, body}}:
      usage(rest, ExpressionsUsage{[provider, body]}, types)
    case 1n+rest ExpressionUsage{M.EffectHasExpr{set, operation}}:
      usage(rest, ExpressionsUsage{[set, operation]}, types)
    case 1n+rest ExpressionUsage{M.EffectCountExpr{set}}:
      usage(rest, ExpressionUsage{set}, types)
    case 1n+rest ExpressionUsage{M.EffectSameExpr{left, right}}:
      usage(rest, ExpressionsUsage{[left, right]}, types)
    case 1n+rest ExpressionUsage{M.ScalarExpr{operator, left, right}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{left}, types)
        b : Usage <- usage(rest, ExpressionUsage{right}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.UnaryExpr{operator, value}}:
      usage(rest, ExpressionUsage{value}, types)
    case 1n+rest ExpressionUsage{M.LetExpr{name, value, body}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{value}, types)
        b : Usage <- usage(rest, ExpressionUsage{body}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.UseExpr{name, value, body}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{value}, types)
        b : Usage <- usage(rest, ExpressionUsage{body}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.SequenceExpr{first, next}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{first}, types)
        b : Usage <- usage(rest, ExpressionUsage{next}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.IfExpr{condition, consequent, alternative}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{condition}, types)
        b : Usage <- usage(rest, ExpressionUsage{consequent}, types)
        c : Usage <- usage(rest, ExpressionUsage{alternative}, types)
        return combine_usage(a, combine_usage(b, c))
    case 1n+rest ExpressionUsage{M.MatchExpr{values, arms}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionsUsage{values}, types)
        b : Usage <- usage(rest, ArmsUsage{arms}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.GuardExpr{pattern, value, alternative, body}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        p : Usage <- usage(rest, PatternUsage{pattern}, types)
        a : Usage <- usage(rest, ExpressionUsage{value}, types)
        b : Usage <- usage(rest, ExpressionUsage{alternative}, types)
        c : Usage <- usage(rest, ExpressionUsage{body}, types)
        return combine_usage(p, combine_usage(a, combine_usage(b, c)))
    case 1n+rest ExpressionUsage{M.BlockExpr{label, body}}:
      usage(rest, ExpressionUsage{body}, types)
    case 1n+rest ExpressionUsage{M.ReturnExpr{label, value}}:
      usage(rest, ExpressionUsage{value}, types)
    case 1n+rest ExpressionUsage{M.RuntimeInitExpr{value}}:
      usage(rest, ExpressionUsage{value}, types)
    case 1n+rest ExpressionUsage{M.SourceExpr{offset, annotation, value}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, TypeUsage{optional_type(annotation)}, types)
        b : Usage <- usage(rest, ExpressionUsage{value}, types)
        return combine_usage(a, b)
    case 1n+rest ExpressionUsage{M.QualifiedExpr{offset, annotation, +predicates, value}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, TypeUsage{annotation}, types)
        b : Usage <- usage(rest, PredicatesUsage{predicates}, types)
        c : Usage <- usage(rest, ExpressionUsage{value}, types)
        return combine_usage(a, combine_usage(b, c))
    case 1n+rest ExpressionUsage{M.InstantiationExpr{site, value}}:
      usage(rest, ExpressionUsage{value}, types)
    case 1n+rest ExpressionUsage{M.TagExpr{offset, callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, ExpressionUsage{callee}, types)
        b : Usage <- usage(rest, ExpressionUsage{argument}, types)
        return combine_usage(a, b)
    case 1n+rest ArmsUsage{M.MatchArm{patterns, body} <> tail}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found_patterns : Usage <- usage(rest, PatternsUsage{patterns}, types)
        found_body : Usage <- usage(rest, ExpressionUsage{body}, types)
        usage(rest, CollectedArmsUsage{tail, [found_body, found_patterns]}, types)
    case 1n+rest PatternsUsage{head <> tail}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, PatternUsage{head}, types)
        usage(rest, CollectedPatternsUsage{tail, [found]}, types)
    case 1n+rest PatternUsage{M.ConstructorPattern{constructor, payload}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        nested : Usage <- usage(rest, PatternUsage{optional_pattern(payload)}, types)
        return combine_usage(constructor_usage(Index.find(M.TypeId, types, constructor)), nested)
    case 1n+rest PatternUsage{M.ProductPattern{elements}}:
      usage(rest, PatternsUsage{elements}, types)
    case 1n+rest TypeUsage{M.AppliedTy{identity, arguments}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        nested : Usage <- usage(rest, TypesUsage{arguments}, types)
        return combine_usage(Usage{[identity]}, nested)
    case 1n+rest TypeUsage{M.ProductTy{elements}}:
      usage(rest, TypesUsage{elements}, types)
    case 1n+rest TypeUsage{M.StateProviderTy{read, write, state}}:
      usage(rest, TypeUsage{state}, types)
    case 1n+rest TypeUsage{M.ArrayTy{element}}:
      usage(rest, TypeUsage{element}, types)
    case 1n+rest TypeUsage{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        a : Usage <- usage(rest, TypeUsage{parameter}, types)
        b : Usage <- usage(rest, TypeUsage{result}, types)
        return combine_usage(effect_row_usage(effects), combine_usage(a, b))
    case 1n+rest TypeUsage{M.ProviderTy{identity, M.EffectRow{operations, tail}}}:
      Done{Usage{identity <> operations}}
    case 1n+rest PredicateUsage{+predicate}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        from_types : Usage <- usage(rest, TypesUsage{C.predicate_types(predicate)}, types)
        return combine_usage(Usage{List.append(&2, M.TypeId, C.predicate_templates([predicate]), row_identities(C.predicate_rows(predicate)))}, from_types)
    case 1n+rest PredicatesUsage{head <> tail}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, PredicateUsage{head}, types)
        usage(rest, CollectedPredicatesUsage{tail, [found]}, types)
    case 1n+rest TypesUsage{head <> tail}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, TypeUsage{head}, types)
        usage(rest, CollectedTypesUsage{tail, [found]}, types)
    case 1n+rest ExpressionsUsage{head <> tail}:
      do Result<&2, &2, M.Diagnostic, Usage>:
        found : Usage <- usage(rest, ExpressionUsage{head}, types)
        usage(rest, CollectedExpressionsUsage{tail, [found]}, types)
    case 1n+rest _:
      Done{Usage{Nil{}}}

type DeclarationUsage is Data:
  DeclarationUsage{name: String, usage: Usage}

def declaration_usage(declaration: G.Declaration, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, DeclarationUsage>:
  match declaration:
    case G.FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}}:
      do Result<&2, &2, M.Diagnostic, DeclarationUsage>:
        annotations : Usage <- usage(Nat.mul(256n, 256n), TypesUsage{[optional_type(p), optional_type(r)]}, types)
        nested : Usage <- usage(Nat.mul(256n, 256n), ExpressionUsage{body}, types)
        return DeclarationUsage{name, combine_usage(annotations, nested)}
    case G.ConstantDeclaration{M.Constant{name, exported, annotation, value}}:
      do Result<&2, &2, M.Diagnostic, DeclarationUsage>:
        annotations : Usage <- usage(Nat.mul(256n, 256n), TypeUsage{optional_type(annotation)}, types)
        nested : Usage <- usage(Nat.mul(256n, 256n), ExpressionUsage{value}, types)
        return DeclarationUsage{name, combine_usage(annotations, nested)}

def declaration_usages(declarations: List<&2, G.Declaration>, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, List<&2, DeclarationUsage>>:
  match declarations:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, DeclarationUsage>>:
        found : DeclarationUsage <- declaration_usage(head, types)
        rest : List<&2, DeclarationUsage> <- declaration_usages(tail, types)
        return found <> rest

type TypeDependencies is Data:
  TypeDependencies{identity: M.TypeId, references: List<&2, M.TypeId>}

def usage_types(found: Usage) -> List<&2, M.TypeId>:
  Usage{nominals} = found
  nominals

def operation_types(operations: List<&2, M.Operation>, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match operations:
    case Nil{}:
      Done{Nil{}}
    case M.Operation{identity, parameter, result} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        found : Usage <- usage(Nat.mul(256n, 256n), TypesUsage{[parameter, result]}, types)
        rest : List<&2, M.TypeId> <- operation_types(tail, types)
        return union_types(usage_types(found), rest)
    case M.OperationTemplate{identity, parameters, parameter, result} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        found : Usage <- usage(Nat.mul(256n, 256n), TypesUsage{[parameter, result]}, types)
        rest : List<&2, M.TypeId> <- operation_types(tail, types)
        return union_types(usage_types(found), rest)
    case head <> tail:
      Fail{M.Diagnostic{"unspecialized_effect", "effect", "effect instances must be specialized before dependency analysis"}}

# Each job validates the shared operation catalog, including unused signatures.
def shared_operation_types(usages: List<&2, DeclarationUsage>, +required: List<&2, M.TypeId>) -> List<&2, DeclarationUsage>:
  match usages:
    case Nil{}:
      Nil{}
    case DeclarationUsage{name, Usage{nominals}} <> tail:
      DeclarationUsage{name, Usage{union_types(required, nominals)}} <> shared_operation_types(tail, required)

def constructor_types(constructors: List<&2, M.Constructor>, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match constructors:
    case Nil{}:
      Done{Nil{}}
    case M.Constructor{name, payload, fields} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        found : Usage <- usage(Nat.mul(256n, 256n), TypeUsage{optional_type(payload)}, types)
        rest : List<&2, M.TypeId> <- constructor_types(tail, types)
        return union_types(usage_types(found), rest)

def type_dependencies(pending: List<&2, M.DataType>, +types: Map<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, List<&2, TypeDependencies>>:
  match pending:
    case Nil{}:
      Done{Nil{}}
    case M.DataType{identity, parameters, constructors} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, TypeDependencies>>:
        refs : List<&2, M.TypeId> <- constructor_types(constructors, types)
        rest : List<&2, TypeDependencies> <- type_dependencies(tail, types)
        return TypeDependencies{identity, refs} <> rest



def external_references(references: List<&2, String>, +known: Set(), +members: Set(), +found: Set()) -> Set():
  match references:
    case Nil{}:
      found
    case +head <> tail:
      external_references(tail, known, members, D.mark(Bool.and(D.member(known, head), Bool.not(D.member(members, head))), found, head))

def job_dependencies(members: List<&2, String>, +edges: Map<&2, List<&2, String>>, +known: Set(), +owned: Set(), found: Set()) -> List<&2, String>:
  match members:
    case Nil{}:
      Set.to_list(found)
    case head <> tail:
      job_dependencies(tail, edges, known, owned, external_references(D.neighbors(edges, head), known, owned, found))

# A display name is not a key: modules and declarations may contain separators.
# Prefixing the module's character length makes the two-part identity injective.
def type_key(identity: M.TypeId) -> String:
  M.TypeId{+module_name, declaration} = identity
  Nat.show(String.length(module_name)) ++ ":" ++ module_name ++ declaration

def TypeSet() -> Data:
  Map<&2, M.TypeId>

def type_set(identities: List<&2, M.TypeId>, found: TypeSet()) -> TypeSet():
  match identities:
    case Nil{}:
      found
    case +head <> tail:
      type_set(tail, Index.set(M.TypeId, found, type_key(head), head))

def type_set_excluding_found(present: Maybe<&2, M.TypeId>, head: M.TypeId, key: String, found: TypeSet()) -> TypeSet():
  match present:
    case Some{value}:
      found
    case None{}:
      Index.set(M.TypeId, found, key, head)

def type_set_excluding(identities: List<&2, M.TypeId>, +excluded: TypeSet(), found: TypeSet()) -> TypeSet():
  match identities:
    case Nil{}:
      found
    case +head <> tail:
      +key = type_key(head)
      type_set_excluding(tail, excluded, type_set_excluding_found(Index.find(M.TypeId, excluded, key), head, key, found))

def type_keys(identities: List<&2, M.TypeId>) -> List<&2, String>:
  match identities:
    case Nil{}:
      Nil{}
    case head <> tail:
      type_key(head) <> type_keys(tail)

def type_identity_le(left: M.TypeId, right: M.TypeId) -> Bool:
  R.operation_le(left, right)

def type_seed(seeds: Map<&2, TypeSet()>, name: String) -> TypeSet():
  Index.get(TypeSet(), seeds, name, Map.new(&2, M.TypeId))

def combine_seeds(names: List<&2, String>, +seeds: Map<&2, TypeSet()>, found: TypeSet()) -> TypeSet():
  match names:
    case Nil{}:
      found
    case head <> tail:
      combine_seeds(tail, seeds, Map.union(&2, M.TypeId, found, type_seed(seeds, head)))

def publish_summary(names: List<&2, String>, +summary: TypeSet(), summaries: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match names:
    case Nil{}:
      summaries
    case head <> tail:
      publish_summary(tail, summary, Index.set(TypeSet(), summaries, head, summary))

def usage_seeds(usages: List<&2, DeclarationUsage>, +shared: TypeSet(), seeds: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match usages:
    case Nil{}:
      seeds
    case DeclarationUsage{name, Usage{nominals}} <> tail:
      usage_seeds(tail, shared, Index.set(TypeSet(), seeds, name, type_set_excluding(nominals, shared, Map.new(&2, M.TypeId))))

def nominal_nodes(types: List<&2, TypeDependencies>) -> List<&2, D.Node>:
  match types:
    case Nil{}:
      Nil{}
    case TypeDependencies{identity, Nil{}} <> tail:
      # Leaf closures are already represented by every user's direct seed.
      nominal_nodes(tail)
    case TypeDependencies{identity, references} <> tail:
      D.Node{type_key(identity), type_keys(references), Nil{}} <> nominal_nodes(tail)

def nominal_seeds(types: List<&2, TypeDependencies>, seeds: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match types:
    case Nil{}:
      seeds
    case TypeDependencies{identity, Nil{}} <> tail:
      nominal_seeds(tail, seeds)
    case TypeDependencies{+identity, references} <> tail:
      # Leaf declarations have no graph node but remain in closures.
      nominal_seeds(tail, Index.set(TypeSet(), seeds, type_key(identity), type_set(identity <> references, Map.new(&2, M.TypeId))))

def nominal_summaries(components: List<&2, List<&2, String>>, +edges: Map<&2, List<&2, String>>, +seeds: Map<&2, TypeSet()>, +known: Set(), +summaries: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match components:
    case Nil{}:
      summaries
    case +members <> tail:
      dependencies = job_dependencies(members, edges, known, Set.from_list(members), Set.new())
      own = combine_seeds(members, seeds, Map.new(&2, M.TypeId))
      summary = combine_seeds(dependencies, summaries, own)
      nominal_summaries(tail, edges, seeds, known, publish_summary(members, summary, summaries))

def close_nominals(identities: List<&2, M.TypeId>, +summaries: Map<&2, TypeSet()>, found: TypeSet()) -> TypeSet():
  match identities:
    case Nil{}:
      found
    case head <> tail:
      close_nominals(tail, summaries, Map.union(&2, M.TypeId, found, type_seed(summaries, type_key(head))))

# SCC interfaces include all nominal types reachable through their dependencies.
# The dependency-first order shares those closures instead of rescanning bodies.
# Both inputs are sorted by type_identity_le and contain unique identities.
# Keep the existing common catalog and sort only this SCC's extra identities.
def merge_required(+common: List<&2, M.TypeId>, +specific: List<&2, M.TypeId>) -> List<&2, M.TypeId>:
  match common specific:
    case Nil{} other:
      other
    case other Nil{}:
      other
    case +left <> left_rest +right <> right_rest:
      +xs = {left <> left_rest : List<&2, M.TypeId>}
      +ys = {right <> right_rest : List<&2, M.TypeId>}
      List.merge.go(~M.TypeId, ~type_identity_le, Nat.add(List.length(&2, M.TypeId, xs), List.length(&2, M.TypeId, ys)), (Nil{}, xs, ys))

def required_for_summary(summary: TypeSet(), +shared: TypeSet(), common: List<&2, M.TypeId>) -> List<&2, M.TypeId>:
  match summary shared:
    case MTip{} _:
      common
    case other MTip{}:
      List.sort(~M.TypeId, ~type_identity_le, Map.values(&2, M.TypeId, other))
    case other available:
      +specific = type_set_excluding(Map.values(&2, M.TypeId, other), available, Map.new(&2, M.TypeId))
      merge_required(common, List.sort(~M.TypeId, ~type_identity_le, Map.values(&2, M.TypeId, specific)))

def make_jobs(components: List<&2, List<&2, String>>, +edges: Map<&2, List<&2, String>>, +known: Set(), +seeds: Map<&2, TypeSet()>, +nominals: Map<&2, TypeSet()>, +shared: TypeSet(), +common: List<&2, M.TypeId>, +summaries: Map<&2, TypeSet()>) -> List<&2, Job>:
  match components:
    case Nil{}:
      Nil{}
    case +members <> tail:
      +dependencies = job_dependencies(members, edges, known, Set.from_list(members), Set.new())
      +own = combine_seeds(members, seeds, Map.new(&2, M.TypeId))
      closed = close_nominals(Map.values(&2, M.TypeId, own), nominals, own)
      +summary = combine_seeds(dependencies, summaries, closed)
      required = required_for_summary(summary, shared, common)
      Job{members, dependencies, required} <> make_jobs(tail, edges, known, seeds, nominals, shared, common, publish_summary(members, summary, summaries))

type Planning is Data:
  Planning{nodes: List<&2, D.Node>, usages: List<&2, DeclarationUsage>, type_dependencies: List<&2, TypeDependencies>, shared_operation_types: List<&2, M.TypeId>}

def planning_nodes(nodes: List<&2, D.Node>) -> List<&2, D.Node>:
  match nodes:
    case Nil{}:
      Nil{}
    case D.Node{name, references, lambdas} <> tail:
      # Lambda identities have already been validated and do not affect jobs.
      D.Node{name, Set.to_list(Set.from_list(references)), Nil{}} <> planning_nodes(tail)

def planning_usages(usages: List<&2, DeclarationUsage>) -> List<&2, DeclarationUsage>:
  match usages:
    case Nil{}:
      Nil{}
    case DeclarationUsage{name, Usage{nominals}} <> tail:
      DeclarationUsage{name, Usage{List.sort(~M.TypeId, ~type_identity_le, nominals)}} <> planning_usages(tail)



def planning_types(types: List<&2, TypeDependencies>) -> List<&2, TypeDependencies>:
  match types:
    case Nil{}:
      Nil{}
    case TypeDependencies{identity, references} <> tail:
      TypeDependencies{identity, List.sort(~M.TypeId, ~type_identity_le, references)} <> planning_types(tail)

# Global validation still runs for every revision, including unused declarations.
# The result retains semantic dependencies but no expression bodies, allowing a
# body-only edit to reuse SCC planning and transitive catalog selection.
def prepare_plan_usages(module: M.Module, graph: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>, scanned: Result<&2, &2, M.Diagnostic, List<&2, DeclarationUsage>>) -> Result<&2, &2, M.Diagnostic, Planning>:
  M.Module{constants, functions, +types, operations} = module
  do Result<&2, &2, M.Diagnostic, Planning>:
    nodes : List<&2, D.Node> <- graph
    +constructors : Map<&2, M.TypeId> = constructor_index(types, Map.new(&2, M.TypeId))
    usages : List<&2, DeclarationUsage> <- scanned
    required : List<&2, M.TypeId> <- operation_types(operations, constructors)
    nominal_graph : List<&2, TypeDependencies> <- type_dependencies(types, constructors)
    return Planning{planning_nodes(nodes), planning_usages(usages), planning_types(nominal_graph), List.sort(~M.TypeId, ~type_identity_le, required)}

def prepare_plan_graph(module: M.Module, graph: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>) -> Result<&2, &2, M.Diagnostic, Planning>:
  M.Module{constants, functions, +types, operations} = module
  declarations = List.append(&2, G.Declaration, G.function_declarations(functions), G.constant_declarations(constants))
  do Result<&2, &2, M.Diagnostic, Planning>:
    nodes : List<&2, D.Node> <- graph
    +constructors : Map<&2, M.TypeId> = constructor_index(types, Map.new(&2, M.TypeId))
    usages : List<&2, DeclarationUsage> <- declaration_usages(declarations, constructors)
    required : List<&2, M.TypeId> <- operation_types(operations, constructors)
    nominal_graph : List<&2, TypeDependencies> <- type_dependencies(types, constructors)
    return Planning{planning_nodes(nodes), planning_usages(usages), planning_types(nominal_graph), List.sort(~M.TypeId, ~type_identity_le, required)}

def prepare_plan(+module: M.Module) -> Result<&2, &2, M.Diagnostic, Planning>:
  prepare_plan_graph(module, Check.module_graph(module))

def substantial_graph(nodes: List<&2, D.Node>, required: Nat) -> Bool:
  match nodes required:
    case _ 0n:
      True{}
    case Nil{} _:
      False{}
    case head <> tail 1n+rest:
      substantial_graph(tail, rest)

def component_pair(nodes: List<&2, D.Node>, nominals: List<&2, D.Node>, parallel: Bool) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>> & Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
  match parallel:
    case False{}:
      (D.components(nodes), D.components(nominals))
    case True{}:
      values types = D.components(nodes) D.components(nominals)
      (values, types)

def finish_components(pair: Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>> & Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>, +nodes: List<&2, D.Node>, usages: List<&2, DeclarationUsage>, nominal_graph: List<&2, TypeDependencies>, +nominal_graph_nodes: List<&2, D.Node>, +shared_operation_types: List<&2, M.TypeId>) -> Result<&2, &2, M.Diagnostic, List<&2, Job>>:
  (value_components, type_components) = pair
  do Result<&2, &2, M.Diagnostic, List<&2, Job>>:
    components : List<&2, List<&2, String>> <- value_components
    nominal_components : List<&2, List<&2, String>> <- type_components
    +closures : Map<&2, TypeSet()> = nominal_summaries(nominal_components, D.adjacency(nominal_graph_nodes, Map.new(&2, List<&2, String>)), nominal_seeds(nominal_graph, Map.new(&2, TypeSet())), Set.from_list(D.node_names(nominal_graph_nodes)), Map.new(&2, TypeSet()))
    +shared : TypeSet() = close_nominals(shared_operation_types, closures, type_set(shared_operation_types, Map.new(&2, M.TypeId)))
    common : List<&2, M.TypeId> = List.sort(~M.TypeId, ~type_identity_le, Map.values(&2, M.TypeId, shared))
    return make_jobs(components, D.adjacency(nodes, Map.new(&2, List<&2, String>)), Set.from_list(D.node_names(nodes)), usage_seeds(usages, shared, Map.new(&2, TypeSet())), closures, shared, common, Map.new(&2, TypeSet()))

def finish_plan(planning: Planning) -> Result<&2, &2, M.Diagnostic, List<&2, Job>>:
  Planning{+nodes, usages, +nominal_graph, shared_operation_types} = planning
  +nominal_graph_nodes = nominal_nodes(nominal_graph)
  pair = component_pair(nodes, nominal_graph_nodes, Bool.and(substantial_graph(nodes, 32n), substantial_graph(nominal_graph_nodes, 32n)))
  finish_components(pair, nodes, usages, nominal_graph, nominal_graph_nodes, shared_operation_types)

def plan(module: M.Module) -> Result<&2, &2, M.Diagnostic, List<&2, Job>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Job>>:
    prepared : Planning <- prepare_plan(module)
    finish_plan(prepared)

def select_functions(functions: List<&2, M.Function>, +members: List<&2, String>) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      Nil{}
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      +rest = select_functions(tail, members)
      Bool.pick(List<&2, M.Function>, D.contains(members, name), M.Function{name, exported, parameter, p, r, body} <> rest, rest)

def select_constants(constants: List<&2, M.Constant>, +members: List<&2, String>) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{+name, exported, annotation, value} <> tail:
      +rest = select_constants(tail, members)
      Bool.pick(List<&2, M.Constant>, D.contains(members, name), M.Constant{name, exported, annotation, value} <> rest, rest)

def select_types(types: List<&2, M.DataType>, +required: List<&2, M.TypeId>) -> List<&2, M.DataType>:
  match types:
    case Nil{}:
      Nil{}
    case M.DataType{+identity, parameters, constructors} <> tail:
      +rest = select_types(tail, required)
      Bool.pick(List<&2, M.DataType>, contains_type(required, identity), M.DataType{identity, parameters, constructors} <> rest, rest)



def job_module(module: M.Module, job: Job) -> Result<&2, &2, M.Diagnostic, M.Module>:
  M.Module{constants, functions, types, operations} = module
  Job{+members, dependencies, +required} = job
  Done{M.Module{select_constants(constants, members), select_functions(functions, members), select_types(types, required), operations}}
