import Base
import ./model.bend as M
import ./types.bend as T
import ./infer.bend as I
import ./dependency.bend as D

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

def lookup(declarations: List<&2, Declaration>, +name: String) -> Result<&2, &2, M.Diagnostic, Declaration>:
  match declarations:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", name, "missing top-level declaration"}}
    case +head <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, Declaration>, M.name_equal(declaration_name(head), name), Done{head}, lookup(tail, name))

def initial_bindings(declarations: List<&2, Declaration>, +index: Nat) -> List<&2, I.Binding>:
  match declarations:
    case Nil{}:
      Nil{}
    case FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}} <> tail:
      I.Binding{name, M.FunctionTy{M.VariableTy{index}, M.VariableTy{1n+index}}, Nil{}} <> initial_bindings(tail, 2n+index)
    case ConstantDeclaration{M.Constant{name, exported, annotation, value}} <> tail:
      I.Binding{name, M.VariableTy{index}, Nil{}} <> initial_bindings(tail, 1n+index)

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
    case Some{I.Binding{name, ty, variables}}:
      Done{ty}

def function_parameter(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match ty:
    case M.FunctionTy{parameter, result}:
      Done{parameter}
    case other:
      Fail{M.Diagnostic{"internal_error", subject, "named function binding is not an arrow"}}

def function_result(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match ty:
    case M.FunctionTy{parameter, result}:
      Done{result}
    case other:
      Fail{M.Diagnostic{"internal_error", subject, "named function binding is not an arrow"}}

def definition_inference(value: I.Inference, ty: M.Ty) -> I.Inference:
  I.Inference{old, requirements, purity, coverage, exits} = value
  I.Inference{ty, requirements, purity, coverage, exits}

def infer_declaration(declaration: Declaration, +environment: Environment, +descriptors: List<&2, M.Descriptor>, +types: List<&2, M.DataType>, functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  match declaration:
    case FunctionDeclaration{M.Function{+name, exported, parameter, p, r, body}}:
      +bindings = env_bindings(environment)
      +context = {I.Context{bindings, Nil{}, Nil{}, descriptors, types, name, functions} : I.Context}
      do Result<&2, &2, M.Diagnostic, Environment>:
        +ty : M.Ty <- binding_type(I.lookup_binding(bindings, name), name)
        +param : M.Ty <- function_parameter(ty, name)
        +result : M.Ty <- function_result(ty, name)
        s1 : I.State <- I.annotation(p, param, env_state(environment), context)
        s2 : I.State <- I.annotation(r, result, s1, context)
        +value : I.Typing <- I.expr(body, I.extend(context, [I.Binding{parameter, param, Nil{}}]), s2)
        state : I.State <- I.unify(I.type_of(value), result, I.state_of(value), name)
        return Environment{bindings, I.Definition{name, definition_inference(I.inference_of(value), ty)} <> env_definitions(environment), state}
    case ConstantDeclaration{M.Constant{+name, exported, ann, value}}:
      +bindings = env_bindings(environment)
      +context = {I.Context{bindings, Nil{}, Nil{}, descriptors, types, name, functions} : I.Context}
      do Result<&2, &2, M.Diagnostic, Environment>:
        +ty : M.Ty <- binding_type(I.lookup_binding(bindings, name), name)
        s1 : I.State <- I.annotation(ann, ty, env_state(environment), context)
        +value : I.Typing <- I.expr(value, context, s1)
        state : I.State <- I.unify(I.type_of(value), ty, I.state_of(value), name)
        return Environment{bindings, I.Definition{name, definition_inference(I.inference_of(value), ty)} <> env_definitions(environment), state}

def infer_component(names: List<&2, String>, +declarations: List<&2, Declaration>, environment: Environment, +descriptors: List<&2, M.Descriptor>, +types: List<&2, M.DataType>, +functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  match names:
    case Nil{}:
      Done{environment}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Environment>:
        declaration : Declaration <- lookup(declarations, head)
        next : Environment <- infer_declaration(declaration, environment, descriptors, types, functions)
        infer_component(tail, declarations, next, descriptors, types, functions)

def outside(bindings: List<&2, I.Binding>, +members: List<&2, String>, +references: List<&2, String>) -> List<&2, I.Binding>:
  match bindings:
    case Nil{}:
      Nil{}
    case I.Binding{+name, +ty, +variables} <> tail:
      +rest = outside(tail, members, references)
      Bool.pick(List<&2, I.Binding>, Bool.and(D.contains(references, name), Bool.not(D.contains(members, name))), I.Binding{name, ty, variables} <> rest, rest)

def external_names(members: List<&2, String>, +nodes: List<&2, D.Node>) -> List<&2, String>:
  match members:
    case Nil{}:
      Nil{}
    case head <> tail:
      List.append(&2, String, D.lookup(nodes, head), external_names(tail, nodes))

def lookup_requirements(definitions: List<&2, I.Definition>, +name: String) -> List<&2, I.Requirement>:
  match definitions:
    case Nil{}:
      Nil{}
    case I.Definition{found, I.Inference{ty, requirements, purity, coverage, exits}} <> tail:
      Bool.pick(List<&2, I.Requirement>, M.name_equal(found, name), requirements, lookup_requirements(tail, name))

def accesses(requirements: List<&2, I.Requirement>) -> Bool:
  match requirements:
    case Nil{}:
      False{}
    case I.AccessRequirement{access, target} <> tail:
      True{}
    case head <> tail:
      accesses(tail)

def callees(requirements: List<&2, I.Requirement>) -> List<&2, String>:
  match requirements:
    case Nil{}:
      Nil{}
    case I.CallRequirement{callee} <> tail:
      callee <> callees(tail)
    case I.ConstantRequirement{name} <> tail:
      name <> callees(tail)
    case head <> tail:
      callees(tail)

def effect_edge_count(definitions: List<&2, I.Definition>) -> Nat:
  match definitions:
    case Nil{}:
      0n
    case I.Definition{name, I.Inference{ty, requirements, purity, coverage, exits}} <> tail:
      Nat.add(List.length(&2, String, callees(requirements)), effect_edge_count(tail))

def effectful_work(fuel: Nat, pending: List<&2, String>, +definitions: List<&2, I.Definition>, +visited: List<&2, String>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      False{}
    case 0n _:
      True{}
    case 1n+rest +head <> tail:
      +requirements = lookup_requirements(definitions, head)
      Bool.or(accesses(requirements), effectful_work(rest, D.next_work(D.contains(visited, head), callees(requirements), tail), definitions, head <> visited))

def any_access(definitions: List<&2, I.Definition>) -> Bool:
  match definitions:
    case Nil{}:
      False{}
    case I.Definition{name, I.Inference{ty, requirements, purity, coverage, exits}} <> tail:
      Bool.or(accesses(requirements), any_access(tail))

def effectful_graph(has_access: Bool, fuel: Nat, pending: List<&2, String>, definitions: List<&2, I.Definition>, visited: List<&2, String>) -> Bool:
  match has_access:
    case False{}:
      False{}
    case True{}:
      effectful_work(fuel, pending, definitions, visited)

def effectful(fuel: Nat, pending: List<&2, String>, +definitions: List<&2, I.Definition>, visited: List<&2, String>) -> Bool:
  # Pure modules are common; do not rewalk their complete call chain per scheme.
  effectful_graph(any_access(definitions), fuel, pending, definitions, visited)

def generalize_pure(effectful: Bool, binding: I.Binding, context: I.Context, state: I.State) -> Result<&2, &2, M.Diagnostic, I.Binding>:
  match effectful:
    case True{}:
      Done{binding}
    case False{}:
      I.Binding{name, ty, variables} = binding
      I.generalize(ty, context, state, name)

def generalize_member(member: Bool, binding: I.Binding, context: I.Context, state: I.State, definitions: List<&2, I.Definition>, fuel: Nat) -> Result<&2, &2, M.Diagnostic, I.Binding>:
  match member:
    case False{}:
      Done{binding}
    case True{}:
      I.Binding{+name, ty, variables} = binding
      generalize_pure(effectful(fuel, [name], definitions, Nil{}), I.Binding{name, ty, variables}, context, state)

def generalize_bindings(bindings: List<&2, I.Binding>, +members: List<&2, String>, +context: I.Context, +state: I.State, +definitions: List<&2, I.Definition>, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  match bindings:
    case Nil{}:
      Done{Nil{}}
    case I.Binding{+name, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
        head : I.Binding <- generalize_member(D.contains(members, name), I.Binding{name, ty, variables}, context, state, definitions, fuel)
        rest : List<&2, I.Binding> <- generalize_bindings(tail, members, context, state, definitions, fuel)
        return head <> rest

def generalize_component(environment: Environment, +members: List<&2, String>, descriptors: List<&2, M.Descriptor>, types: List<&2, M.DataType>, nodes: List<&2, D.Node>) -> Result<&2, &2, M.Diagnostic, Environment>:
  Environment{+bindings, +definitions, +state} = environment
  # A closed top-level component can share metavariables only with referenced
  # globals. Unrelated declarations have disjoint fresh variables; scanning
  # their entire types here would make independent modules cubic to infer.
  +context = {I.Context{outside(bindings, members, external_names(members, nodes)), Nil{}, Nil{}, descriptors, types, "module", Nil{}} : I.Context}
  do Result<&2, &2, M.Diagnostic, Environment>:
    next : List<&2, I.Binding> <- generalize_bindings(bindings, members, context, state, definitions, 1n+effect_edge_count(definitions))
    return Environment{next, definitions, state}

def infer_groups(groups: List<&2, List<&2, String>>, +nodes: List<&2, D.Node>, +declarations: List<&2, Declaration>, environment: Environment, +descriptors: List<&2, M.Descriptor>, +types: List<&2, M.DataType>, +functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  match groups:
    case Nil{}:
      Done{environment}
    case +members <> tail:
      do Result<&2, &2, M.Diagnostic, Environment>:
        inferred : Environment <- infer_component(members, declarations, environment, descriptors, types, functions)
        generalized : Environment <- generalize_component(inferred, members, descriptors, types, nodes)
        infer_groups(tail, nodes, declarations, generalized, descriptors, types, functions)

def infer_with(declarations: List<&2, Declaration>, +nodes: List<&2, D.Node>, descriptors: List<&2, M.Descriptor>, types: List<&2, M.DataType>, imported: Environment, imported_functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  Environment{external_bindings, external_definitions, I.State{substitutions, +start}} = imported
  +decls = declarations
  +count = List.length(&2, Declaration, decls)
  +bindings = List.append(&2, I.Binding, initial_bindings(decls, start), external_bindings)
  do Result<&2, &2, M.Diagnostic, Environment>:
    groups : List<&2, List<&2, String>> <- D.components(nodes)
    infer_groups(groups, nodes, decls, Environment{bindings, external_definitions, I.State{substitutions, Nat.add(start, Nat.mul(2n, count))}}, descriptors, types, List.append(&2, String, function_names(decls), imported_functions))

def infer(declarations: List<&2, Declaration>, nodes: List<&2, D.Node>, descriptors: List<&2, M.Descriptor>, types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Environment>:
  infer_with(declarations, nodes, descriptors, types, Environment{Nil{}, Nil{}, I.State{Nil{}, 0n}}, Nil{})
