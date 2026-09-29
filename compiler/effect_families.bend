import Base
import ./model.bend as M
import ./resolvers.bend as Resolvers
import ./types.bend as T
import ./state_specialize.bend as State
import ./closures.bend as Closures
import ./monomorph.bend as Mono
import ./type_data.bend as TypeData

type Work is Data:
  Expression{value: M.Expr}
  Expressions{values: List<&2, M.Expr>, reversed: List<&2, M.Expr>}

type Rewritten is Data:
  Rewritten{expressions: List<&2, M.Expr>, instances: List<&2, M.Operation>}

type RewrittenFunctions is Data:
  RewrittenFunctions{functions: List<&2, M.Function>, instances: List<&2, M.Operation>}

type RewrittenConstants is Data:
  RewrittenConstants{constants: List<&2, M.Constant>, instances: List<&2, M.Operation>}

def instance_error(identity: M.TypeId, message: String) -> M.Diagnostic:
  M.Diagnostic{"effect_instance", M.type_id_show(identity), message}

# Type keys include nominal module ownership and length-delimited arguments.
def keyed_identity(found: Result<&2, &2, M.Diagnostic, String>, template: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match found template:
    case Done{key} M.TypeId{module_name, declaration}:
      Done{M.TypeId{module_name, declaration ++ "<" ++ key ++ ">"}}
    case Fail{error} template:
      Fail{instance_error(template, "effect type arguments must be concrete and have a supported closed type")}

def identity(template: M.TypeId, arguments: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  keyed_identity(State.type_key(65536n, State.TypesKey{arguments}), template)

def template(operations: List<&2, M.Operation>, +wanted: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match operations:
    case Nil{}:
      Fail{instance_error(wanted, "no declaration defines this effect operation")}
    case M.OperationTemplate{+identity, +parameters, parameter, result} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Operation>, M.type_id_equal(identity, wanted), Done{M.OperationTemplate{identity, parameters, parameter, result}}, template(tail, wanted))
    case head <> tail:
      template(tail, wanted)

def concrete(operations: List<&2, M.Operation>) -> List<&2, M.Operation>:
  match operations:
    case Nil{}:
      Nil{}
    case M.Operation{identity, parameter, result} <> tail:
      M.Operation{identity, parameter, result} <> concrete(tail)
    case head <> tail:
      concrete(tail)

def templates(operations: List<&2, M.Operation>) -> List<&2, M.Operation>:
  match operations:
    case Nil{}:
      Nil{}
    case +operation <> tail:
      match operation:
        case M.OperationTemplate{identity, parameters, parameter, result}:
          operation <> templates(tail)
        case _:
          templates(tail)

def contains(operations: List<&2, M.Operation>, +wanted: M.TypeId) -> Bool:
  match operations:
    case Nil{}:
      False{}
    case M.Operation{identity, parameter, result} <> tail:
      Bool.or(M.type_id_equal(identity, wanted), contains(tail, wanted))
    case head <> tail:
      contains(tail, wanted)

def instantiate_checked(correct_arity: Bool, declared_identity: M.TypeId, parameter: M.Ty, result: M.Ty, +arguments: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match correct_arity:
    case False{}:
      Fail{instance_error(declared_identity, "effect operation has the wrong number of type arguments")}
    case True{}:
      do Result<&2, &2, M.Diagnostic, M.Operation>:
        specialized : M.TypeId <- identity(declared_identity, arguments)
        parameter_type : M.Ty <- T.parameters(arguments, 0n, parameter)
        result_type : M.Ty <- T.parameters(arguments, 0n, result)
        return M.Operation{specialized, parameter_type, result_type}

def instantiate_declaration(declaration: M.Operation, template_identity: M.TypeId, +arguments: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match declaration:
    case M.OperationTemplate{declared_identity, parameters, parameter, result}:
      instantiate_checked(Nat.is_eq(parameters, List.length(&2, M.Ty, arguments)), declared_identity, parameter, result, arguments)
    case _:
      Fail{instance_error(template_identity, "expected a parameterized effect declaration")}

def instantiate(declarations: List<&2, M.Operation>, +template_identity: M.TypeId, arguments: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  do Result<&2, &2, M.Diagnostic, M.Operation>:
    declaration : M.Operation <- template(declarations, template_identity)
    instantiate_declaration(declaration, template_identity, arguments)

def add_instance(operation: M.Operation, declared: List<&2, M.Operation>, +instances: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match operation:
    case M.Operation{+identity, parameter, result}:
      Bool.pick(Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>, contains(declared, identity), Fail{instance_error(identity, "generated operation conflicts with an existing effect declaration")}, Done{Bool.pick(List<&2, M.Operation>, contains(instances, identity), instances, operation <> instances)})
    case _:
      Fail{M.Diagnostic{"internal_error", "effect", "expected a concrete effect operation"}}

def one(expressions: List<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match expressions:
    case expression <> Nil{}:
      Done{expression}
    case _:
      Fail{M.Diagnostic{"internal_error", "effect", "effect specialization lost an expression"}}

def rebuilt(original: M.Expr, rewritten: Rewritten) -> Result<&2, &2, M.Diagnostic, Rewritten>:
  match rewritten:
    case Rewritten{children, instances}:
      do Result<&2, &2, M.Diagnostic, Rewritten>:
        value : M.Expr <- Mono.rebuild(original, children, 0n)
        return Rewritten{[value], instances}

def instances_of(rewritten: Rewritten) -> List<&2, M.Operation>:
  match rewritten:
    case Rewritten{expressions, instances}:
      instances

def expression_of(rewritten: Rewritten) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match rewritten:
    case Rewritten{expressions, instances}:
      one(expressions)

def function_instances(rewritten: RewrittenFunctions) -> List<&2, M.Operation>:
  match rewritten:
    case RewrittenFunctions{functions, instances}:
      instances

def prepend_function(function: M.Function, rewritten: RewrittenFunctions) -> RewrittenFunctions:
  match rewritten:
    case RewrittenFunctions{functions, instances}:
      RewrittenFunctions{function <> functions, instances}

def prepend_constant(constant: M.Constant, rewritten: RewrittenConstants) -> RewrittenConstants:
  match rewritten:
    case RewrittenConstants{constants, instances}:
      RewrittenConstants{constant <> constants, instances}

def template_present(operations: List<&2, M.Operation>, +wanted: M.TypeId) -> Bool:
  match operations:
    case Nil{}:
      False{}
    case M.OperationTemplate{identity, parameters, parameter, result} <> tail:
      Bool.or(M.type_id_equal(identity, wanted), template_present(tail, wanted))
    case head <> tail:
      template_present(tail, wanted)

def unique_template(duplicate: Bool, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  match duplicate:
    case False{}:
      Done{Unit{}}
    case True{}:
      Fail{M.Diagnostic{"duplicate_type", M.type_id_show(identity), "duplicate nominal effect identity"}}

def rewrite(+fuel: Nat, work: Work, +declarations: List<&2, M.Operation>, +declared: List<&2, M.Operation>, instances: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, Rewritten>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "effect", "effect specialization exceeded its structural limit"}}
    case 1n+rest Expression{M.SpecializeOperationExpr{template_identity, arguments, body}}:
      do Result<&2, &2, M.Diagnostic, Rewritten>:
        operation : M.Operation <- instantiate(declarations, template_identity, arguments)
        next : List<&2, M.Operation> <- add_instance(operation, declared, instances)
        rewrite(rest, Expression{body}, declarations, declared, next)
    case 1n+rest Expression{+original}:
      do Result<&2, &2, M.Diagnostic, Rewritten>:
        rewritten : Rewritten <- rewrite(rest, Expressions{Closures.children(original), Nil{}}, declarations, declared, instances)
        rebuilt(original, rewritten)
    case 1n+rest Expressions{Nil{}, reversed}:
      Done{Rewritten{List.reverse(&2, M.Expr, reversed), instances}}
    case 1n+rest Expressions{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Rewritten>:
        +first : Rewritten <- rewrite(rest, Expression{head}, declarations, declared, instances)
        value : M.Expr <- expression_of(first)
        rewrite(rest, Expressions{tail, value <> reversed}, declarations, declared, instances_of(first))

def rewrite_functions(+fuel: Nat, functions: List<&2, M.Function>, +declarations: List<&2, M.Operation>, +declared: List<&2, M.Operation>, instances: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, RewrittenFunctions>:
  match fuel functions:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "effect", "effect function list exceeds its structural limit"}}
    case 1n+rest Nil{}:
      Done{RewrittenFunctions{Nil{}, instances}}
    case 1n+rest M.Function{name, exported, parameter, parameter_type, result_type, body} <> tail:
      do Result<&2, &2, M.Diagnostic, RewrittenFunctions>:
        +rewritten : Rewritten <- rewrite(65536n, Expression{body}, declarations, declared, instances)
        value : M.Expr <- expression_of(rewritten)
        remaining : RewrittenFunctions <- rewrite_functions(rest, tail, declarations, declared, instances_of(rewritten))
        return prepend_function(M.Function{name, exported, parameter, parameter_type, result_type, value}, remaining)

def rewrite_constants(+fuel: Nat, constants: List<&2, M.Constant>, +declarations: List<&2, M.Operation>, +declared: List<&2, M.Operation>, instances: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, RewrittenConstants>:
  match fuel constants:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "effect", "effect constant list exceeds its structural limit"}}
    case 1n+rest Nil{}:
      Done{RewrittenConstants{Nil{}, instances}}
    case 1n+rest M.Constant{name, exported, annotation, value} <> tail:
      do Result<&2, &2, M.Diagnostic, RewrittenConstants>:
        +rewritten : Rewritten <- rewrite(65536n, Expression{value}, declarations, declared, instances)
        specialized : M.Expr <- expression_of(rewritten)
        remaining : RewrittenConstants <- rewrite_constants(rest, tail, declarations, declared, instances_of(rewritten))
        return prepend_constant(M.Constant{name, exported, annotation, specialized}, remaining)

def validate_templates(operations: List<&2, M.Operation>, +declared: List<&2, M.Operation>, +types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match operations:
    case Nil{}:
      Done{Unit{}}
    case M.OperationTemplate{+identity, +parameters, parameter, result} <> +tail:
      +subject = M.type_id_show(identity)
      do Result<&2, &2, M.Diagnostic, Unit>:
        unique : Unit <- unique_template(Bool.or(template_present(tail, identity), contains(declared, identity)), identity)
        valid_identity : Unit <- TypeData.valid_operation_identity(identity)
        valid_parameter : Unit <- TypeData.validate_template(parameter, Some{parameters}, declared, types, subject)
        valid_result : Unit <- TypeData.validate_template(result, Some{parameters}, declared, types, subject)
        validate_templates(tail, declared, types)
    case head <> tail:
      validate_templates(tail, declared, types)

def collect_instances(+fuel: Nat, operations: List<&2, M.Operation>, +declarations: List<&2, M.Operation>, +declared: List<&2, M.Operation>, instances: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match fuel operations:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "effect", "effect instance list exceeds its structural limit"}}
    case 1n+rest Nil{}:
      Done{instances}
    case 1n+rest M.OperationInstance{template_identity, arguments} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
        operation : M.Operation <- instantiate(declarations, template_identity, arguments)
        next : List<&2, M.Operation> <- add_instance(operation, declared, instances)
        collect_instances(rest, tail, declarations, declared, next)
    case 1n+rest head <> tail:
      collect_instances(rest, tail, declarations, declared, instances)

def has_family(operations: List<&2, M.Operation>) -> Bool:
  match operations:
    case Nil{}:
      False{}
    case M.OperationTemplate{identity, parameters, parameter, result} <> tail:
      True{}
    case M.OperationInstance{template, arguments} <> tail:
      True{}
    case head <> tail:
      has_family(tail)

def has_marker(+fuel: Nat, pending: List<&2, M.Expr>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      False{}
    case 0n _:
      True{}
    case 1n+rest M.SpecializeOperationExpr{template, arguments, body} <> tail:
      True{}
    case 1n+rest head <> tail:
      has_marker(rest, List.reverse.go(&2, M.Expr, List.reverse(&2, M.Expr, Closures.children(head)), tail))

def function_markers(functions: List<&2, M.Function>) -> Bool:
  match functions:
    case Nil{}:
      False{}
    case M.Function{name, exported, parameter, parameter_type, result_type, body} <> tail:
      Bool.or(has_marker(65536n, [body]), function_markers(tail))

def constant_markers(constants: List<&2, M.Constant>) -> Bool:
  match constants:
    case Nil{}:
      False{}
    case M.Constant{name, exported, annotation, value} <> tail:
      Bool.or(has_marker(65536n, [value]), constant_markers(tail))

def body_markers(family: Bool, functions: List<&2, M.Function>, constants: List<&2, M.Constant>) -> Bool:
  match family:
    case True{}:
      True{}
    case False{}:
      Bool.or(function_markers(functions), constant_markers(constants))

def required(module: M.Module) -> Bool:
  M.Module{constants, functions, types, operations} = module
  body_markers(has_family(operations), functions, constants)

def finish(module: M.Module, functions: RewrittenFunctions, constants: RewrittenConstants, declared: List<&2, M.Operation>) -> M.Module:
  match module functions constants:
    case M.Module{old_constants, old_functions, types, operations} RewrittenFunctions{specialized_functions, earlier} RewrittenConstants{specialized_constants, instances}:
      M.Module{specialized_constants, specialized_functions, types, List.append(&2, M.Operation, templates(operations), List.append(&2, M.Operation, declared, List.reverse(&2, M.Operation, instances)))}

def prepare_full(module: M.Module) -> Result<&2, &2, M.Diagnostic, M.Module>:
  M.Module{+constants, +functions, +data_types, +declarations} = module
  +declared = concrete(declarations)
  do Result<&2, &2, M.Diagnostic, M.Module>:
    +registered : List<&2, M.Operation> <- collect_instances(65536n, declarations, declarations, declared, Nil{})
    valid : Unit <- validate_templates(declarations, List.append(&2, M.Operation, declared, registered), data_types)
    +rewritten_functions : RewrittenFunctions <- rewrite_functions(65536n, functions, declarations, declared, registered)
    rewritten_constants : RewrittenConstants <- rewrite_constants(65536n, constants, declarations, declared, function_instances(rewritten_functions))
    return finish(M.Module{constants, functions, data_types, declarations}, rewritten_functions, rewritten_constants, declared)

def prepare_if(needed: Bool, module: M.Module) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match needed:
    case False{}:
      Done{module}
    case True{}:
      prepare_full(module)

def prepare(original: M.Module) -> Result<&2, &2, M.Diagnostic, M.Module>:
  do Result<&2, &2, M.Diagnostic, M.Module>:
    +module : M.Module <- Resolvers.prepare(original)
    prepare_if(required(module), module)
