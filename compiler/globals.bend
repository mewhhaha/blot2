import Base
import ./model.bend as M
import ./infer.bend as I
import ./types.bend as T
import ./dependency.bend as D
import ./global_bindings.bend as Bindings

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
      I.Binding{name, M.FunctionTy{M.VariableTy{index}, M.VariableTy{1n+index}, M.EffectRow{Nil{}, M.RowVariable{2n+index}}}, Nil{}} <> initial_bindings(tail, 3n+index)
    case ConstantDeclaration{M.Constant{name, exported, annotation, value}} <> tail:
      I.Binding{name, M.VariableTy{index}, Nil{}} <> initial_bindings(tail, 1n+index)

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
    case Some{I.Binding{name, ty, variables}}:
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
  I.Inference{old, coverage, exits, reflections} = value
  I.Inference{ty, coverage, exits, reflections}

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
      I.Binding{name, ty, variables} = binding
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
        +value : I.Typing <- I.expr(body, I.extend(context, [I.Binding{parameter, param, Nil{}}]), s2)
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
    case I.Binding{+name, +ty, +variables} <> tail:
      +rest = outside_indexed(tail, members, references)
      Bool.pick(List<&2, I.Binding>, Bool.and(D.member(references, name), Bool.not(D.member(members, name))), I.Binding{name, ty, variables} <> rest, rest)

def outside(bindings: List<&2, I.Binding>, members: List<&2, String>, references: List<&2, String>) -> List<&2, I.Binding>:
  outside_indexed(bindings, reference_set(members, Set.new()), reference_set(references, Set.new()))

def external_names(members: List<&2, String>, +nodes: List<&2, D.Node>) -> List<&2, String>:
  match members:
    case Nil{}:
      Nil{}
    case head <> tail:
      List.append(&2, String, D.lookup(nodes, head), external_names(tail, nodes))

def generalize_member(member: Bool, binding: I.Binding, context: I.Context, state: I.State) -> Result<&2, &2, M.Diagnostic, I.Binding>:
  match member:
    case False{}:
      Done{binding}
    case True{}:
      I.Binding{name, ty, variables} = binding
      I.generalize(ty, context, state, name)

def generalize_bindings_indexed(bindings: List<&2, I.Binding>, +members: Set(), +context: I.Context, +state: I.State) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  match bindings:
    case Nil{}:
      Done{Nil{}}
    case I.Binding{+name, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
        head : I.Binding <- generalize_member(D.member(members, name), I.Binding{name, ty, variables}, context, state)
        rest : List<&2, I.Binding> <- generalize_bindings_indexed(tail, members, context, state)
        return head <> rest

def generalize_bindings(bindings: List<&2, I.Binding>, members: List<&2, String>, context: I.Context, state: I.State) -> Result<&2, &2, M.Diagnostic, List<&2, I.Binding>>:
  generalize_bindings_indexed(bindings, reference_set(members, Set.new()), context, state)

def generalize_component(environment: Environment, +members: List<&2, String>, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, nodes: List<&2, D.Node>) -> Result<&2, &2, M.Diagnostic, Environment>:
  Environment{+bindings, +definitions, +state} = environment
  # A closed top-level component can share metavariables only with referenced
  # globals. Unrelated declarations have disjoint fresh variables; scanning
  # their entire types here would make independent modules cubic to infer.
  +member_names = reference_set(members, Set.new())
  referenced_names = reference_set(external_names(members, nodes), Set.new())
  +context = {I.Context{outside_indexed(bindings, member_names, referenced_names), Nil{}, Nil{}, types, operations, "module", Nil{}, M.empty_row()} : I.Context}
  do Result<&2, &2, M.Diagnostic, Environment>:
    next : List<&2, I.Binding> <- generalize_bindings_indexed(bindings, member_names, context, state)
    return Environment{next, definitions, state}

def infer_groups(groups: List<&2, List<&2, String>>, +nodes: List<&2, D.Node>, +declarations: List<&2, Declaration>, environment: Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Environment>:
  match groups:
    case Nil{}:
      Done{environment}
    case +members <> tail:
      do Result<&2, &2, M.Diagnostic, Environment>:
        inferred : Environment <- infer_component(members, declarations, environment, operations, types, functions)
        generalized : Environment <- generalize_component(inferred, members, operations, types, nodes)
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
