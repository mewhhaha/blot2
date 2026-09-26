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

type Job is Data:
  Job{members: List<&2, String>, dependencies: List<&2, String>, type_dependencies: List<&2, M.TypeId>}

type InterfaceKind is Data:
  FunctionInterface{}
  ConstantInterface{}

# ParameterTy indices bind within this interface, never within another job's
# inference state. An interface contains no unresolved monomorphic variables.
type Interface is Data:
  Interface{name: String, kind: InterfaceKind, template: M.Ty, parameters: Nat, effects: List<&2, M.Effect>}

type CheckedGroup is Data:
  CheckedGroup{checked: M.CheckedModule, interfaces: List<&2, Interface>}

def interface_names(interfaces: List<&2, Interface>) -> List<&2, String>:
  match interfaces:
    case Nil{}:
      Nil{}
    case Interface{name, kind, template, parameters, effects} <> tail:
      name <> interface_names(tail)

def interface_functions(interfaces: List<&2, Interface>) -> List<&2, String>:
  match interfaces:
    case Nil{}:
      Nil{}
    case Interface{name, FunctionInterface{}, template, parameters, effects} <> tail:
      name <> interface_functions(tail)
    case head <> tail:
      interface_functions(tail)

def indices(count: Nat, +start: Nat) -> List<&2, Nat>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      start <> indices(rest, 1n+start)

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

def import_interfaces(interfaces: List<&2, Interface>, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +start: Nat) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match interfaces:
    case Nil{}:
      Done{G.Environment{Nil{}, Nil{}, I.State{T.empty(), start, MTip{}}}}
    case Interface{+name, +kind, +template, +parameters, +effects} <> tail:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        valid : Unit <- TD.validate_template(template, Some{parameters}, operations, types, name)
        compatible : Unit <- valid_interface_kind(kind, template, parameters, effects, name)
        +ty : M.Ty <- T.parameters(TD.fresh_arguments(parameters, start), 0n, template)
        +rest : G.Environment <- import_interfaces(tail, operations, types, Nat.add(start, parameters))
        return G.Environment{I.Binding{name, ty, indices(parameters, start)} <> G.env_bindings(rest), I.Definition{name, I.pure(ty)} <> G.env_definitions(rest), G.env_state(rest)}

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

def closed_interface(open: List<&2, Nat>, +variables: List<&2, Nat>, name: String, kind: InterfaceKind, ty: M.Ty, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match open:
    case Nil{}:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        template : M.Ty <- template_type(variables, 0n, ty)
        return [Interface{name, kind, template, List.length(&2, Nat, variables), E.canonical(effects)}]
    case head <> tail:
      Fail{M.Diagnostic{"invalid_interface", name, "a dependency interface cannot expose an unquantified inference variable"}}

def export_interface(name: String, kind: InterfaceKind, ty: M.Ty, variables: List<&2, Nat>, effects: List<&2, M.Effect>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
    normalized : List<&2, M.Ty> <- canonical_work(Nat.mul(256n, 256n), T.OneType{ty})
    +canonical : M.Ty <- T.first_type(normalized)
    +free : List<&2, Nat> <- T.free(canonical)
    closed_interface(T.difference(free, variables), free, name, kind, canonical, effects)

def function_interfaces(functions: List<&2, M.CheckedFunction>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedFunction{function, M.Signature{name, parameter, result, variables, row}, effects} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        head : List<&2, Interface> <- export_interface(name, FunctionInterface{}, M.FunctionTy{parameter, result, row}, variables, effects)
        rest : List<&2, Interface> <- function_interfaces(tail)
        return List.append(&2, Interface, head, rest)

def constant_interfaces(constants: List<&2, M.CheckedConstant>) -> Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Interface>>:
        head : List<&2, Interface> <- export_interface(name, ConstantInterface{}, ty, variables, Nil{})
        rest : List<&2, Interface> <- constant_interfaces(tail)
        return List.append(&2, Interface, head, rest)

def checked_group(+checked: M.CheckedModule) -> Result<&2, &2, M.Diagnostic, CheckedGroup>:
  M.CheckedModule{constants, functions, types, operations} = checked
  do Result<&2, &2, M.Diagnostic, CheckedGroup>:
    fns : List<&2, Interface> <- function_interfaces(functions)
    consts : List<&2, Interface> <- constant_interfaces(constants)
    return CheckedGroup{checked, List.append(&2, Interface, fns, consts)}

# The deferred dispatch requirements of one checked group. Their types are
# resolved against the group's final substitution; every variable they still
# mention is numbered below `next`, and variables are shared only within the
# group (an SCC is inferred with one state).
type Resolution is Data:
  Resolution{declaration: String, identity: Nat, dispatch: M.Dispatch, member: String, templates: List<&2, M.TypeId>, left: M.Ty, right: M.Ty, result: M.Ty, ambient: M.EffectRow}

# `members` holds the group's own declaration types under the same numbering,
# so a resolution can tell whether its unifications refine an interface.
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

def resolved_need(left: Result<&2, &2, M.Diagnostic, M.Ty>, right: Result<&2, &2, M.Diagnostic, M.Ty>, result: Result<&2, &2, M.Diagnostic, M.Ty>, declaration: String, identity: Nat, dispatch: M.Dispatch, member: String, templates: List<&2, M.TypeId>, ambient: M.EffectRow, rest: List<&2, Resolution>) -> List<&2, Resolution>:
  match left right result:
    case Done{l} Done{r} Done{value}:
      Resolution{declaration, identity, dispatch, member, templates, l, r, value, ambient} <> rest
    case _ _ _:
      rest

def coverage_needs(coverage: List<&2, I.Coverage>, +declaration: String, +substitutions: T.Substitutions, reversed: List<&2, Resolution>) -> List<&2, Resolution>:
  match coverage:
    case Nil{}:
      List.reverse(&2, Resolution, reversed)
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, ambient, subject} <> tail:
      coverage_needs(tail, declaration, substitutions, resolved_need(T.resolve(substitutions, left), T.resolve(substitutions, right), T.resolve(substitutions, result), declaration, identity, dispatch, member, templates, T.resolve_row(substitutions, ambient), reversed))
    case head <> tail:
      coverage_needs(tail, declaration, substitutions, reversed)

def definition_needs(definitions: List<&2, I.Definition>, +substitutions: T.Substitutions) -> List<&2, Resolution>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections}} <> tail:
      List.append(&2, Resolution, coverage_needs(coverage, name, substitutions, Nil{}), definition_needs(tail, substitutions))

def member_binding(member: Bool, name: String, resolved: Result<&2, &2, M.Diagnostic, M.Ty>, rest: List<&2, I.Binding>) -> List<&2, I.Binding>:
  match member resolved:
    case True{} Done{ty}:
      I.Binding{name, ty, Nil{}} <> rest
    case _ _:
      rest

# Member types before generalization: generalization closes unconstrained
# rows, which would hide an effect a resolved call adds to the interface.
def member_bindings(definitions: List<&2, I.Definition>, +members: Set(), +substitutions: T.Substitutions) -> List<&2, I.Binding>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{+name, I.Inference{ty, coverage, exits, reflections}} <> tail:
      +rest = member_bindings(tail, members, substitutions)
      member_binding(D.member(members, name), name, T.resolve(substitutions, ty), rest)

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
    case I.Definition{name, I.Inference{ty, coverage, exits, reflections}} <> tail:
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
    group : CheckedGroup <- checked_group(checked)
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
  ExpressionsUsage{values: List<&2, M.Expr>}
  CollectedExpressionsUsage{values: List<&2, M.Expr>, reversed: List<&2, Usage>}
  CollectedPatternsUsage{values: List<&2, M.Pattern>, reversed: List<&2, Usage>}
  CollectedTypesUsage{values: List<&2, M.Ty>, reversed: List<&2, Usage>}
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
      constructor_index_entries(tail, identity, Map.set(&2, M.TypeId, index, name, identity))

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

# Wide arrays, tuple patterns and annotations must not grow the JS stack.
# Preserve the recursive walk's sibling fuel and right-associated merge order.
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
        return combine_usage(a, b)
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
      type_set(tail, Map.set(&2, M.TypeId, found, type_key(head), head))

def type_set_excluding_found(present: Maybe<&2, M.TypeId>, head: M.TypeId, key: String, found: TypeSet()) -> TypeSet():
  match present:
    case Some{value}:
      found
    case None{}:
      Map.set(&2, M.TypeId, found, key, head)

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
      publish_summary(tail, summary, Map.set(&2, TypeSet(), summaries, head, summary))

def usage_seeds(usages: List<&2, DeclarationUsage>, +shared: TypeSet(), seeds: Map<&2, TypeSet()>) -> Map<&2, TypeSet()>:
  match usages:
    case Nil{}:
      seeds
    case DeclarationUsage{name, Usage{nominals}} <> tail:
      usage_seeds(tail, shared, Map.set(&2, TypeSet(), seeds, name, type_set_excluding(nominals, shared, Map.new(&2, M.TypeId))))

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
      nominal_seeds(tail, Map.set(&2, TypeSet(), seeds, type_key(identity), type_set(identity <> references, Map.new(&2, M.TypeId))))

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
