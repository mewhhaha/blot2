import Base
import ./model.bend as M
import ./infer.bend as I
import ./types.bend as T
import ./dependency.bend as D
import ./global_bindings.bend as Bindings
import ./closures.bend as Closures
import ./constraints.bend as C

type Declaration is Data:
  FunctionDeclaration{value: M.Function}
  ConstantDeclaration{value: M.Constant}

type Environment is Data:
  Environment{bindings: List<&2, I.Binding>, definitions: List<&2, I.Definition>, state: I.State}

def function_declarations(functions: List<&2, M.Function>) -> List<&2, Declaration>:
  match functions:
    case Nil{}:
      Nil{}
    case head <> tail:
      FunctionDeclaration{head} <> function_declarations(tail)

def constant_declarations(constants: List<&2, M.Constant>) -> List<&2, Declaration>:
  match constants:
    case Nil{}:
      Nil{}
    case head <> tail:
      ConstantDeclaration{head} <> constant_declarations(tail)

def declaration_name(declaration: Declaration) -> String:
  match declaration:
    case FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}}:
      name
    case ConstantDeclaration{M.Constant{name, exported, annotation, value}}:
      name

def names(declarations: List<&2, Declaration>) -> List<&2, String>:
  match declarations:
    case Nil{}:
      Nil{}
    case head <> tail:
      declaration_name(head) <> names(tail)

def function_names(declarations: List<&2, Declaration>) -> List<&2, String>:
  match declarations:
    case Nil{}:
      Nil{}
    case FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}} <> tail:
      name <> function_names(tail)
    case ConstantDeclaration{value} <> tail:
      function_names(tail)

def lookup_work(declarations: List<&2, Declaration>, +name: String, found: Maybe<&2, Declaration>) -> Result<&2, &2, M.Diagnostic, Declaration>:
  match declarations found:
    case _ Some{value}:
      Done{value}
    case Nil{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "missing top-level declaration"}}
    case +head <> tail None{}:
      lookup_work(tail, name, Bool.pick(Maybe<&2, Declaration>, M.name_equal(declaration_name(head), name), Some{head}, None{}))

def lookup(declarations: List<&2, Declaration>, name: String) -> Result<&2, &2, M.Diagnostic, Declaration>:
  lookup_work(declarations, name, None{})

def initial_bindings(declarations: List<&2, Declaration>, +index: Nat) -> List<&2, I.Binding>:
  match declarations:
    case Nil{}:
      Nil{}
    case FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}} <> tail:
      I.Binding{name, M.FunctionTy{M.VariableTy{index}, M.VariableTy{1n+index}, M.EffectRow{Nil{}, M.RowVariable{2n+index}}}, Nil{}, Nil{}} <> initial_bindings(tail, 3n+index)
    case ConstantDeclaration{M.Constant{name, exported, annotation, value}} <> tail:
      I.Binding{name, M.VariableTy{index}, Nil{}, Nil{}} <> initial_bindings(tail, 1n+index)

def initial_next(declarations: List<&2, Declaration>, index: Nat) -> Nat:
  match declarations:
    case Nil{}:
      index
    case FunctionDeclaration{value} <> tail:
      initial_next(tail, 3n+index)
    case ConstantDeclaration{value} <> tail:
      initial_next(tail, 1n+index)

def env_bindings(environment: Environment) -> List<&2, I.Binding>:
  Environment{bindings, definitions, state} = environment
  bindings

def env_definitions(environment: Environment) -> List<&2, I.Definition>:
  Environment{bindings, definitions, state} = environment
  definitions

def env_state(environment: Environment) -> I.State:
  Environment{bindings, definitions, state} = environment
  state

def binding_type(found: Maybe<&2, I.Binding>, subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", subject, "missing top-level type binding"}}
    case Some{I.Binding{name, ty, variables, predicates}}:
      Done{ty}

def function_parameter(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match ty:
    case M.FunctionTy{parameter, result, effects}:
      Done{parameter}
    case other:
      Fail{M.Diagnostic{"internal_error", subject, "named function binding is not an arrow"}}

def function_result(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match ty:
    case M.FunctionTy{parameter, result, effects}:
      Done{result}
    case other:
      Fail{M.Diagnostic{"internal_error", subject, "named function binding is not an arrow"}}

def function_effects(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, M.EffectRow>:
  match ty:
    case M.FunctionTy{parameter, result, effects}:
      Done{effects}
    case other:
      Fail{M.Diagnostic{"internal_error", subject, "named function binding is not an arrow"}}

def definition_inference(value: I.Inference, ty: M.Ty) -> I.Inference:
  I.Inference{old, coverage, exits, reflections, predicates, uses} = value
  I.Inference{ty, coverage, exits, reflections, predicates, uses}

def reference_set(names: List<&2, String>, found: Set()) -> Set():
  match names:
    case Nil{}:
      found
    case head <> tail:
      reference_set(tail, Set.add(found, head))

def referenced_bindings_indexed(bindings: List<&2, I.Binding>, +names: Set()) -> List<&2, I.Binding>:
  match bindings:
    case Nil{}:
      Nil{}
    case +binding <> tail:
      I.Binding{name, ty, variables, predicates} = binding
      +rest = referenced_bindings_indexed(tail, names)
      Bool.pick(List<&2, I.Binding>, D.member(names, name), binding <> rest, rest)

def referenced_bindings(bindings: List<&2, I.Binding>, names: List<&2, String>) -> List<&2, I.Binding>:
  referenced_bindings_indexed(bindings, reference_set(names, Set.new()))

# Local generalization must exclude shared variables from referenced globals.
# Unrelated declarations have no path to those variables; retaining every
# expanded declaration here makes each local binding rescan the entire program.
def declaration_bindings(name: String, body: M.Expr, bindings: List<&2, I.Binding>) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  do Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
    references : D.References <- D.references(Nat.mul(256n, 256n), D.Expression{body})
    return referenced_bindings(bindings, name <> D.names_of(references))

def reference_bindings_prepared(index: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>, bindings: List<&2, I.Binding>, names: List<&2, String>) -> List<&2, I.Binding>:
  match index:
    case None{}:
      referenced_bindings(bindings, names)
    case Some{known}:
      Bindings.referenced(known, names)

def declaration_bindings_prepared(name: String, body: M.Expr, bindings: List<&2, I.Binding>, index: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  do Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
    references : D.References <- D.references(Nat.mul(256n, 256n), D.Expression{body})
    return reference_bindings_prepared(index, bindings, name <> D.names_of(references))

def initializer_effect_code(value: M.Expr) -> String:
  match value:
    case M.RuntimeInitExpr{expression}:
      "initializer_effect"
    case _:
      "const_effect"

def infer_declaration_prepared(declaration: Declaration, +environment: Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, functions: List<&2, String>, index: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, Environment>:
  match declaration:
    case FunctionDeclaration{M.Function{+name, exported, parameter, p, r, +body}}:
      +bindings = env_bindings(environment)
      do Result<&2, &2, M.Diagnostic, Environment>:
        +ty : M.Ty <- binding_type(I.lookup_binding(bindings, name), name)
        +param : M.Ty <- function_parameter(ty, name)
        +result : M.Ty <- function_result(ty, name)
        ambient : M.EffectRow <- function_effects(ty, name)
        visible : List<&2, I.Binding> <- declaration_bindings_prepared(name, body, bindings, index)
        +context : I.Context = I.Context{visible, Nil{}, Nil{}, types, operations, name, functions, ambient}
        s1 : I.State <- I.annotation(p, param, env_state(environment), context)
        s2 : I.State <- I.annotation(r, result, s1, context)
        +value : I.Typing <- I.expr(body, I.extend(context, [I.Binding{parameter, param, Nil{}, Nil{}}]), s2)
        state : I.State <- I.unify(I.type_of(value), result, I.state_of(value), name)
        return Environment{bindings, I.Definition{name, definition_inference(I.inference_of(value), ty)} <> env_definitions(environment), I.clear_annotations(state)}
    case ConstantDeclaration{M.Constant{+name, exported, ann, +value}}:
      +bindings = env_bindings(environment)
      +ambient = {M.EffectRow{Nil{}, M.RowVariable{I.next_of(env_state(environment))}} : M.EffectRow}
      do Result<&2, &2, M.Diagnostic, Environment>:
        visible : List<&2, I.Binding> <- declaration_bindings_prepared(name, value, bindings, index)
        +context : I.Context = I.Context{visible, Nil{}, Nil{}, types, operations, name, functions, ambient}
        +ty : M.Ty <- binding_type(I.lookup_binding(bindings, name), name)
        s1 : I.State <- I.annotation(ann, ty, I.with_next(env_state(environment), 1n+I.next_of(env_state(environment))), context)
        effect_code : String = initializer_effect_code(value)
        +value : I.Typing <- I.expr(value, context, s1)
        unified : I.State <- I.unify(I.type_of(value), ty, I.state_of(value), name)
        state : I.State <- I.require_pure(ambient, unified, name, effect_code)
        return Environment{bindings, I.Definition{name, definition_inference(I.inference_of(value), ty)} <> env_definitions(environment), I.clear_annotations(state)}

def infer_declaration(declaration: Declaration, environment: Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  infer_declaration_prepared(declaration, environment, operations, types, functions, None{})

def component_bindings(names: List<&2, String>, bindings: List<&2, I.Binding>) -> Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>:
  match names:
    case a <> b <> c <> d <> rest:
      Some{Bindings.build(bindings, 0n, MTip{})}
    case _:
      None{}

def infer_component_prepared(names: List<&2, String>, +declarations: List<&2, Declaration>, environment: Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +functions: List<&2, String>, +index: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, Environment>:
  match names:
    case Nil{}:
      Done{environment}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Environment>:
        declaration : Declaration <- lookup(declarations, head)
        next : Environment <- infer_declaration_prepared(declaration, environment, operations, types, functions, index)
        infer_component_prepared(tail, declarations, next, operations, types, functions, index)

def infer_component(+names: List<&2, String>, declarations: List<&2, Declaration>, +environment: Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  infer_component_prepared(names, declarations, environment, operations, types, functions, component_bindings(names, env_bindings(environment)))

def outside_indexed(bindings: List<&2, I.Binding>, +members: Set(), +references: Set()) -> List<&2, I.Binding>:
  match bindings:
    case Nil{}:
      Nil{}
    case I.Binding{+name, +ty, +variables, +predicates} <> tail:
      +rest = outside_indexed(tail, members, references)
      Bool.pick(List<&2, I.Binding>, Bool.and(D.member(references, name), Bool.not(D.member(members, name))), I.Binding{name, ty, variables, predicates} <> rest, rest)

def outside(bindings: List<&2, I.Binding>, members: List<&2, String>, references: List<&2, String>) -> List<&2, I.Binding>:
  outside_indexed(bindings, reference_set(members, Set.new()), reference_set(references, Set.new()))

def external_names(members: List<&2, String>, +nodes: List<&2, D.Node>) -> List<&2, String>:
  match members:
    case Nil{}:
      Nil{}
    case head <> tail:
      List.append(&2, String, D.lookup(nodes, head), external_names(tail, nodes))

# A matching definition with no predicates still wins over every later
# definition. Carry a separate matched flag rather than using an empty result.
def definition_predicates_work(definitions: List<&2, I.Definition>, +wanted: String, matched: Bool, found: List<&2, M.Predicate>) -> List<&2, M.Predicate>:
  match definitions matched:
    case _ True{}:
      found
    case Nil{} False{}:
      Nil{}
    case I.Definition{name, inference} <> tail False{}:
      definition_predicates_work(tail, wanted, M.name_equal(name, wanted), I.inference_predicates(inference))

def definition_predicates(definitions: List<&2, I.Definition>, wanted: String) -> List<&2, M.Predicate>:
  definition_predicates_work(definitions, wanted, False{}, Nil{})

def generalize_member(member: Bool, binding: I.Binding, +definitions: List<&2, I.Definition>, context: I.Context, state: I.State) -> Result<&2, &2, M.Diagnostic, I.Binding>:
  match member:
    case False{}:
      Done{binding}
    case True{}:
      I.Binding{+name, ty, variables, predicates} = binding
      I.generalize_qualified(ty, definition_predicates(definitions, name), context, state, name)

def generalize_bindings_indexed(bindings: List<&2, I.Binding>, +members: Set(), +definitions: List<&2, I.Definition>, +context: I.Context, +state: I.State) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  match bindings:
    case Nil{}:
      Done{Nil{}}
    case I.Binding{+name, ty, variables, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
        head : I.Binding <- generalize_member(D.member(members, name), I.Binding{name, ty, variables, predicates}, definitions, context, state)
        rest : List<&2, I.Binding> <- generalize_bindings_indexed(tail, members, definitions, context, state)
        return head <> rest

def generalize_bindings(bindings: List<&2, I.Binding>, members: List<&2, String>, context: I.Context, state: I.State) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  generalize_bindings_indexed(bindings, reference_set(members, Set.new()), Nil{}, context, state)

def generalize_component(environment: Environment, +members: List<&2, String>, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, nodes: List<&2, D.Node>) -> Result<&2, &2, M.Diagnostic, Environment>:
  Environment{+bindings, +definitions, +state} = environment
  # A closed top-level component can share metavariables only with referenced
  # globals. Unrelated declarations have disjoint fresh variables; scanning
  # their entire types here would make independent modules cubic to infer.
  +member_names = reference_set(members, Set.new())
  referenced_names = reference_set(external_names(members, nodes), Set.new())
  +context = {I.Context{outside_indexed(bindings, member_names, referenced_names), Nil{}, Nil{}, types, operations, "module", Nil{}, M.empty_row()} : I.Context}
  do Result<&2, &2, M.Diagnostic, Environment>:
    next : List<&2, I.Binding> <- generalize_bindings_indexed(bindings, member_names, definitions, context, state)
    return Environment{next, definitions, state}

# SCC bindings are monomorphic until generalize_component. Every callable
# reference in the component therefore shares the first check's variable IDs,
# including variables mentioned only by a predicate. Site plans are recorded
# even when the callee's predicates have not been inferred yet.
type SccSite is Data:
  SccSite{site: Maybe<&2, Nat>, callee: String, boundary: Maybe<&2, Nat>}

type SccNode is Data:
  SccNode{name: String, sites: List<&2, SccSite>}

type SccWork is Data:
  SccExpressions{values: List<&2, M.Expr>, boundary: Maybe<&2, Nat>}

def scc_scan(fuel: Nat, pending: List<&2, SccWork>, reversed: List<&2, SccSite>) -> Result<&2, &2, M.Diagnostic, List<&2, SccSite>>:
  match fuel pending:
    case _ Nil{}:
      Done{List.reverse(&2, SccSite, reversed)}
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "inference", "recursive callable scan exceeded its work limit"}}
    case 1n+rest SccExpressions{Nil{}, boundary} <> tail:
      scc_scan(rest, tail, reversed)
    case 1n+rest SccExpressions{M.QualifiedExpr{offset, annotation, predicates, value} <> values, boundary} <> tail:
      scc_scan(rest, SccExpressions{[value], Some{offset}} <> SccExpressions{values, boundary} <> tail, reversed)
    case 1n+rest SccExpressions{M.InstantiationExpr{site, M.FunctionExpr{name}} <> values, +boundary} <> tail:
      scc_scan(rest, SccExpressions{values, boundary} <> tail, SccSite{Some{site}, name, boundary} <> reversed)
    case 1n+rest SccExpressions{M.InstantiationExpr{site, M.ConstantExpr{name}} <> values, +boundary} <> tail:
      scc_scan(rest, SccExpressions{values, boundary} <> tail, SccSite{Some{site}, name, boundary} <> reversed)
    case 1n+rest SccExpressions{M.InstantiationExpr{site, M.CallExpr{name, argument}} <> values, +boundary} <> tail:
      scc_scan(rest, SccExpressions{[argument], boundary} <> SccExpressions{values, boundary} <> tail, SccSite{Some{site}, name, boundary} <> reversed)
    case 1n+rest SccExpressions{M.FunctionExpr{name} <> values, +boundary} <> tail:
      scc_scan(rest, SccExpressions{values, boundary} <> tail, SccSite{None{}, name, boundary} <> reversed)
    case 1n+rest SccExpressions{M.ConstantExpr{name} <> values, +boundary} <> tail:
      scc_scan(rest, SccExpressions{values, boundary} <> tail, SccSite{None{}, name, boundary} <> reversed)
    case 1n+rest SccExpressions{M.CallExpr{name, argument} <> values, +boundary} <> tail:
      scc_scan(rest, SccExpressions{[argument], boundary} <> SccExpressions{values, boundary} <> tail, SccSite{None{}, name, boundary} <> reversed)
    case 1n+rest SccExpressions{expression <> values, +boundary} <> tail:
      scc_scan(rest, SccExpressions{Closures.children(expression), boundary} <> SccExpressions{values, boundary} <> tail, reversed)

def scc_sites(value: M.Expr) -> Result<&2, &2, M.Diagnostic, List<&2, SccSite>>:
  scc_scan(Nat.mul(256n, 256n), [SccExpressions{[value], None{}}], Nil{})

def scc_declaration_sites(declaration: Declaration) -> Result<&2, &2, M.Diagnostic, List<&2, SccSite>>:
  match declaration:
    case FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}}:
      scc_sites(body)
    case ConstantDeclaration{M.Constant{name, exported, annotation, value}}:
      scc_sites(value)

def scc_nodes(members: List<&2, String>, +declarations: List<&2, Declaration>) -> Result<&2, &2, M.Diagnostic, List<&2, SccNode>>:
  match members:
    case Nil{}:
      Done{Nil{}}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, SccNode>>:
        declaration : Declaration <- lookup(declarations, name)
        sites : List<&2, SccSite> <- scc_declaration_sites(declaration)
        rest : List<&2, SccNode> <- scc_nodes(tail, declarations)
        return SccNode{name, sites} <> rest

def scc_node_sites(nodes: List<&2, SccNode>, +wanted: String) -> List<&2, SccSite>:
  match nodes:
    case Nil{}:
      Nil{}
    case SccNode{name, +sites} <> tail:
      Bool.pick(List<&2, SccSite>, M.name_equal(name, wanted), sites, scc_node_sites(tail, wanted))

def scc_peers(sites: List<&2, SccSite>, +members: Set()) -> List<&2, String>:
  match sites:
    case Nil{}:
      Nil{}
    case SccSite{site, +callee, boundary} <> tail:
      +rest = scc_peers(tail, members)
      Bool.pick(List<&2, String>, D.member(members, callee), callee <> rest, rest)

def scc_seen(pending: List<&2, String>, +visited: Set()) -> Bool:
  match pending:
    case Nil{}:
      False{}
    case name <> tail:
      D.member(visited, name)

def scc_closure_walk(fuel: Nat, pending: List<&2, String>, +members: Set(), +nodes: List<&2, SccNode>, +definitions: List<&2, I.Definition>, +substitutions: T.Substitutions, +visited: Set(), gathered: List<&2, M.Predicate>, seen: Bool) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match fuel pending seen:
    case _ Nil{} _:
      Done{C.canonical_predicates(List.reverse(&2, M.Predicate, gathered), Nil{})}
    case 0n _ _:
      Fail{M.Diagnostic{"expression_complexity", "inference", "recursive predicate closure exceeded its work limit"}}
    case 1n+rest name <> +tail True{}:
      scc_closure_walk(rest, tail, members, nodes, definitions, substitutions, visited, gathered, scc_seen(tail, visited))
    case 1n+rest +name <> tail False{}:
      +peers = {scc_peers(scc_node_sites(nodes, name), members) : List<&2, String>}
      +queued = {List.reverse.go(&2, String, List.reverse(&2, String, peers), tail) : List<&2, String>}
      +next_visited = {Set.add(visited, name) : Set()}
      do Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
        own : List<&2, M.Predicate> <- C.resolve_list(substitutions, definition_predicates(definitions, name))
        scc_closure_walk(rest, queued, members, nodes, definitions, substitutions, next_visited, List.reverse.go(&2, M.Predicate, own, gathered), scc_seen(queued, next_visited))

type SccClosure is Data:
  SccClosure{name: String, predicates: List<&2, M.Predicate>}

def scc_closures(members: List<&2, String>, +member_set: Set(), +nodes: List<&2, SccNode>, +definitions: List<&2, I.Definition>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, SccClosure>>:
  match members:
    case Nil{}:
      Done{Nil{}}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, SccClosure>>:
        own : List<&2, M.Predicate> <- scc_closure_walk(Nat.mul(256n, 256n), [name], member_set, nodes, definitions, substitutions, Set.new(), Nil{}, False{})
        rest : List<&2, SccClosure> <- scc_closures(tail, member_set, nodes, definitions, substitutions)
        return SccClosure{name, own} <> rest

def scc_predicates(closures: List<&2, SccClosure>, +name: String) -> List<&2, M.Predicate>:
  match closures:
    case Nil{}:
      Nil{}
    case SccClosure{found, +predicates} <> tail:
      Bool.pick(List<&2, M.Predicate>, M.name_equal(found, name), predicates, scc_predicates(tail, name))

def scc_site_callee(sites: List<&2, SccSite>, +site: Nat) -> Maybe<&2, String>:
  match sites:
    case Nil{}:
      None{}
    case SccSite{None{}, callee, boundary} <> tail:
      scc_site_callee(tail, site)
    case SccSite{Some{identity}, +callee, boundary} <> tail:
      Bool.pick(Maybe<&2, String>, Nat.is_eq(identity, site), Some{callee}, scc_site_callee(tail, site))

def scc_same_boundary(found: Maybe<&2, Nat>, wanted: Nat) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{offset}:
      Nat.is_eq(offset, wanted)

def scc_boundary_predicates(sites: List<&2, SccSite>, +offset: Nat, +members: Set(), +closures: List<&2, SccClosure>) -> List<&2, M.Predicate>:
  match sites:
    case Nil{}:
      Nil{}
    case SccSite{site, +callee, boundary} <> tail:
      +rest = scc_boundary_predicates(tail, offset, members, closures)
      Bool.pick(List<&2, M.Predicate>, Bool.and(scc_same_boundary(boundary, offset), D.member(members, callee)), List.append(&2, M.Predicate, scc_predicates(closures, callee), rest), rest)

def scc_site_in_boundary(sites: List<&2, SccSite>, +site: Nat, +offset: Nat) -> Bool:
  match sites:
    case Nil{}:
      False{}
    case SccSite{None{}, callee, boundary} <> tail:
      scc_site_in_boundary(tail, site, offset)
    case SccSite{Some{identity}, callee, boundary} <> tail:
      Bool.or(Bool.and(Nat.is_eq(identity, site), scc_same_boundary(boundary, offset)), scc_site_in_boundary(tail, site, offset))

def scc_boundary_plans(plans: List<&2, C.UsePlan>, +sites: List<&2, SccSite>, +offset: Nat) -> List<&2, C.UsePlan>:
  match plans:
    case Nil{}:
      Nil{}
    case C.UsePlan{+site, subject, ty, predicates} <> tail:
      +rest = scc_boundary_plans(tail, sites, offset)
      Bool.pick(List<&2, C.UsePlan>, scc_site_in_boundary(sites, site, offset), C.UsePlan{site, subject, ty, predicates} <> rest, rest)

def scc_plan_for(found: Maybe<&2, String>, plan: C.UsePlan, +closures: List<&2, SccClosure>) -> C.UsePlan:
  match found plan:
    case None{} plan:
      plan
    case Some{callee} C.UsePlan{site, subject, ty, predicates}:
      C.UsePlan{site, subject, ty, C.canonical_predicates(List.append(&2, M.Predicate, predicates, scc_predicates(closures, callee)), Nil{})}

def scc_plans(plans: List<&2, C.UsePlan>, +sites: List<&2, SccSite>, +closures: List<&2, SccClosure>) -> List<&2, C.UsePlan>:
  match plans:
    case Nil{}:
      Nil{}
    case C.UsePlan{+site, subject, ty, predicates} <> tail:
      scc_plan_for(scc_site_callee(sites, site), C.UsePlan{site, subject, ty, predicates}, closures) <> scc_plans(tail, sites, closures)

# Recheck each local where boundary after peers have their transitive SCC
# predicates. The marker retained the original first-pass annotation IDs;
# selecting only sites nearest this boundary keeps nested clauses independent.
def scc_check_boundaries(coverage: List<&2, I.Coverage>, +sites: List<&2, SccSite>, +plans: List<&2, C.UsePlan>, +members: Set(), +closures: List<&2, SccClosure>, state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match coverage:
    case Nil{}:
      Done{state}
    case I.QualifiedBoundary{+offset, declared, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        next : I.State <- I.entail_all(scc_boundary_predicates(sites, offset, members, closures), Nil{}, scc_boundary_plans(plans, sites, offset), declared, state, subject)
        scc_check_boundaries(tail, sites, plans, members, closures, next)
    case head <> tail:
      scc_check_boundaries(tail, sites, plans, members, closures, state)

def scc_definition(definitions: List<&2, I.Definition>, +wanted: String) -> Result<&2, &2, M.Diagnostic, I.Inference>:
  match definitions:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", wanted, "missing inferred SCC member"}}
    case I.Definition{name, inference} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, I.Inference>, M.name_equal(name, wanted), Done{inference}, scc_definition(tail, wanted))

def scc_validate(members: List<&2, String>, +definitions: List<&2, I.Definition>, +nodes: List<&2, SccNode>, +closures: List<&2, SccClosure>, +member_set: Set(), state: I.State) -> Result<&2, &2, M.Diagnostic, I.State>:
  match members:
    case Nil{}:
      Done{state}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, I.State>:
        +inference : I.Inference <- scc_definition(definitions, name)
        +sites : List<&2, SccSite> = scc_node_sites(nodes, name)
        +plans : List<&2, C.UsePlan> = scc_plans(I.inference_uses(inference), sites, closures)
        next : I.State <- scc_check_boundaries(I.inference_coverage(inference), sites, plans, member_set, closures, state)
        scc_validate(tail, definitions, nodes, closures, member_set, next)

def scc_update_definition(included: Bool, +name: String, inference: I.Inference, +sites: List<&2, SccSite>, +closures: List<&2, SccClosure>) -> I.Definition:
  match included:
    case False{}:
      I.Definition{name, inference}
    case True{}:
      I.Inference{ty, coverage, exits, reflections, predicates, +uses} = inference
      +closure = {scc_predicates(closures, name) : List<&2, M.Predicate>}
      +plans = {scc_plans(uses, sites, closures) : List<&2, C.UsePlan>}
      I.Definition{name, I.Inference{ty, coverage, exits, reflections, closure, plans}}

def scc_update_definitions(definitions: List<&2, I.Definition>, +members: Set(), +nodes: List<&2, SccNode>, +closures: List<&2, SccClosure>) -> List<&2, I.Definition>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{+name, +inference} <> tail:
      +rest = {scc_update_definitions(tail, members, nodes, closures) : List<&2, I.Definition>}
      scc_update_definition(D.member(members, name), name, inference, scc_node_sites(nodes, name), closures) <> rest

def scc_needed(members: List<&2, String>, +nodes: List<&2, D.Node>) -> Bool:
  match members:
    case Nil{}:
      False{}
    case +name <> Nil{}:
      D.contains(D.lookup(nodes, name), name)
    case _:
      True{}

def close_component(needed: Bool, environment: Environment, +members: List<&2, String>, +declarations: List<&2, Declaration>) -> Result<&2, &2, M.Diagnostic, Environment>:
  match needed:
    case False{}:
      Done{environment}
    case True{}:
      Environment{+bindings, +definitions, +state} = environment
      do Result<&2, &2, M.Diagnostic, Environment>:
        +nodes : List<&2, SccNode> <- scc_nodes(members, declarations)
        +member_set : Set() = reference_set(members, Set.new())
        +closures : List<&2, SccClosure> <- scc_closures(members, member_set, nodes, definitions, I.substitutions_of(state))
        checked : I.State <- scc_validate(members, definitions, nodes, closures, member_set, state)
        return Environment{bindings, scc_update_definitions(definitions, member_set, nodes, closures), checked}

def infer_groups(groups: List<&2, List<&2, String>>, +nodes: List<&2, D.Node>, +declarations: List<&2, Declaration>, environment: Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  match groups:
    case Nil{}:
      Done{environment}
    case +members <> tail:
      do Result<&2, &2, M.Diagnostic, Environment>:
        inferred : Environment <- infer_component(members, declarations, environment, operations, types, functions)
        closed : Environment <- close_component(scc_needed(members, nodes), inferred, members, declarations)
        generalized : Environment <- generalize_component(closed, members, operations, types, nodes)
        infer_groups(tail, nodes, declarations, generalized, operations, types, functions)

def infer_with(declarations: List<&2, Declaration>, +nodes: List<&2, D.Node>, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, imported: Environment, imported_functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  Environment{external_bindings, external_definitions, I.State{substitutions, +start, annotations}} = imported
  +decls = declarations
  created = initial_bindings(decls, start)
  next = initial_next(decls, start)
  +bindings = List.append(&2, I.Binding, created, external_bindings)
  do Result<&2, &2, M.Diagnostic, Environment>:
    groups : List<&2, List<&2, String>> <- D.components(nodes)
    infer_groups(groups, nodes, decls, Environment{bindings, external_definitions, I.State{substitutions, next, annotations}}, operations, types, List.append(&2, String, function_names(decls), imported_functions))

def infer(declarations: List<&2, Declaration>, nodes: List<&2, D.Node>, operations: List<&2, M.Operation>, types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Environment>:
  infer_with(declarations, nodes, operations, types, Environment{Nil{}, Nil{}, I.State{T.empty(), 0n, MTip{}}}, Nil{})
