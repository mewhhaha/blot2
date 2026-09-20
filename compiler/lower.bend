import Base
import ./model.bend as M
import ./cst.bend as C
import ./source_types.bend as T
import ./operators.bend as O
import ./index.bend as Index

type Local is Data:
  Local{source: String, core: String}

type GlobalKind is Data:
  ConstantName{}
  FunctionName{}
  ConstructorName{}

type Global is Data:
  Global{source: String, core: String, kind: GlobalKind}

type Context is Data:
  Context{globals: Map<&2, Global>, headers: Map<&2, T.Header>, fixities: List<&2, O.Fixity>, locals: List<&2, Local>, return_label: Maybe<&2, Nat>}

type NodeKind is Data:
  Wrapper{}
  Integer{}
  Truth{}
  Falsehood{}
  Name{}
  Intrinsic{}
  FunctionNode{}
  ConstantNode{}
  DataNode{}
  SymbolicFixity{}
  NamedFixity{}
  GroupNode{}
  ApplicationNode{}
  InfixNode{}
  LambdaNode{}
  CaseNode{}
  Block{}
  Binding{}
  EffectBinding{}
  Return{}
  Conditional{}
  PatternConditional{}
  PatternWrapper{}
  PatternGroup{}
  PatternConstructor{}
  PatternPayload{}
  PatternChildren{}
  PatternName{}
  Unsupported{}

type Primitive is Data:
  ScalarPrimitive{}
  StorageRead{}
  StorageWrite{}
  StorageInsert{}

type Work is Data:
  Expression{kind: NodeKind, node: C.Cst}
  Group{nodes: List<&2, C.Cst>, offset: Nat}
  Arguments{callee: M.Expr, nodes: List<&2, C.Cst>, offset: Nat}
  ApplicationHead{kind: NodeKind, head: C.Cst, arguments: List<&2, C.Cst>, offset: Nat}
  PrimitiveCall{primitive: Primitive, head: C.Cst, arguments: List<&2, C.Cst>, offset: Nat}
  InfixTails{head: M.Expr, nodes: List<&2, C.Cst>, tails: List<&2, O.Tail>}
  Arms{value: M.Expr, nodes: List<&2, C.Cst>, arms: List<&2, M.MatchArm<M.Expr>>}
  Statements{nodes: List<&2, C.Cst>}
  Statement{kind: NodeKind, node: C.Cst, tail: List<&2, C.Cst>}

type Parameter is Data:
  Parameter{source: String, core: String, annotation: Maybe<&2, M.Ty>}

type PatternResult is Data:
  PatternResult{pattern: M.Pattern, locals: List<&2, Local>}

# Small enums avoid multiplying each branch by bootstrap String pattern tests.
def classify(+kind: String) -> NodeKind:
  Bool.pick(NodeKind, M.name_equal(kind, "expression"), Wrapper{},
    Bool.pick(NodeKind, M.name_equal(kind, "atom"), Wrapper{},
    Bool.pick(NodeKind, M.name_equal(kind, "INTEGER"), Integer{},
    Bool.pick(NodeKind, M.name_equal(kind, "True"), Truth{},
    Bool.pick(NodeKind, M.name_equal(kind, "False"), Falsehood{},
    Bool.pick(NodeKind, M.name_equal(kind, "qualified_name"), Name{},
    Bool.pick(NodeKind, M.name_equal(kind, "INTRINSIC"), Intrinsic{},
    Bool.pick(NodeKind, M.name_equal(kind, "function"), FunctionNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "constant"), ConstantNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "data_type"), DataNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "symbolic_fixity"), SymbolicFixity{},
    Bool.pick(NodeKind, M.name_equal(kind, "named_fixity"), NamedFixity{},
    Bool.pick(NodeKind, M.name_equal(kind, "group"), GroupNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "application"), ApplicationNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "infix_expression"), InfixNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "lambda"), LambdaNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "case_expression"), CaseNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "do_block"), Block{},
    Bool.pick(NodeKind, M.name_equal(kind, "binding"), Binding{},
    Bool.pick(NodeKind, M.name_equal(kind, "effect_binding"), EffectBinding{},
    Bool.pick(NodeKind, M.name_equal(kind, "effect_step"), EffectBinding{},
    Bool.pick(NodeKind, M.name_equal(kind, "result"), Return{},
    Bool.pick(NodeKind, M.name_equal(kind, "conditional"), Conditional{},
    Bool.pick(NodeKind, M.name_equal(kind, "pattern_conditional"), PatternConditional{},
    Bool.pick(NodeKind, M.name_equal(kind, "pattern"), PatternWrapper{},
    Bool.pick(NodeKind, M.name_equal(kind, "pattern_group"), PatternGroup{},
    Bool.pick(NodeKind, M.name_equal(kind, "constructor_pattern"), PatternConstructor{},
    Bool.pick(NodeKind, M.name_equal(kind, "IDENT"), PatternName{}, Unsupported{}))))))))))))))))))))))))))))

def visit(+node: C.Cst) -> Work:
  Expression{classify(C.kind_of(node)), node}

def lookup_local_work(locals: List<&2, Local>, +name: String, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match locals found:
    case _ Some{core}:
      Some{core}
    case Nil{} None{}:
      None{}
    case Local{source, core} <> tail None{}:
      lookup_local_work(tail, name, Bool.pick(Maybe<&2, String>, M.name_equal(source, name), Some{core}, None{}))

def lookup_local(locals: List<&2, Local>, name: String) -> Maybe<&2, String>:
  lookup_local_work(locals, name, None{})

def lookup_global(globals: Map<&2, Global>, name: String) -> Maybe<&2, Global>:
  Index.find(Global, globals, name)

def global_value(found: Maybe<&2, Global>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{Global{source, core, ConstantName{}}}:
      Done{M.ConstantExpr{core}}
    case Some{Global{source, core, FunctionName{}}}:
      Done{M.FunctionExpr{core}}
    case Some{Global{source, core, ConstructorName{}}}:
      Done{M.ConstructorRefExpr{core}}
    case None{}:
      Fail{C.diagnostic(node, "unknown_value", "unknown value: " ++ C.name_of(node))}

def resolved(local: Maybe<&2, String>, globals: Map<&2, Global>, name: String, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match local:
    case Some{core}:
      Done{M.LocalExpr{core}}
    case None{}:
      global_value(lookup_global(globals, name), node)

def resolve(context: Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  Context{globals, headers, fixities, locals, label} = context
  +name = C.name_of(node)
  resolved(lookup_local(locals, name), globals, name, node)

def bind(+context: Context, target: Local) -> Context:
  Context{+globals, +headers, +fixities, locals, +label} = context
  Local{+source, core} = target
  Bool.pick(Context, M.name_equal(source, "_"), context, Context{globals, headers, fixities, Local{source, core} <> locals, label})

def bind_all(locals: List<&2, Local>, context: Context) -> Context:
  match locals:
    case Nil{}:
      context
    case local <> rest:
      bind_all(rest, bind(context, local))

def with_label(context: Context, label: Maybe<&2, Nat>) -> Context:
  Context{globals, headers, fixities, locals, old_label} = context
  Context{globals, headers, fixities, locals, label}

def unique_name(+node: C.Cst) -> String:
  C.text_of(node) ++ "$" ++ Nat.show(C.offset_of(node))

def source_annotation(nodes: List<&2, C.Cst>, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  Context{globals, headers, fixities, locals, label} = context
  T.annotation(nodes, fuel, headers, Nil{})

def parameter_fields(names: List<&2, C.Cst>, annotations: List<&2, C.Cst>, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, Parameter>:
  match names:
    case Nil{}:
      Done{Parameter{"_", "$unit", Some{M.UnitTy{}}}}
    case +name <> Nil{}:
      do Result<&2, &2, M.Diagnostic, Parameter>:
        ty : Maybe<&2, M.Ty> <- source_annotation(annotations, fuel, context)
        return Parameter{C.text_of(name), unique_name(name), ty}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid parameter"}}

def lower_parameter(+node: C.Cst, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, Parameter>:
  parameter_fields(C.field_values(node, "name"), C.field_values(node, "annotation"), fuel, context)

def bind_parameter(context: Context, param: Parameter) -> Context:
  Parameter{source, core, annotation} = param
  bind(context, Local{source, core})

def located(offset: Nat, value: M.Expr) -> M.Expr:
  M.SourceExpr{offset, None{}, value}

def intrinsic(+name: String, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.ScalarOp>:
  Bool.pick(Result<&2, &2, M.Diagnostic, M.ScalarOp>, M.name_equal(name, "@u32.add"), Done{M.Add{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, M.ScalarOp>, M.name_equal(name, "@u32.sub"), Done{M.Subtract{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, M.ScalarOp>, M.name_equal(name, "@u32.mul"), Done{M.Multiply{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, M.ScalarOp>, M.name_equal(name, "@u32.eq"), Done{M.Equal{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, M.ScalarOp>, M.name_equal(name, "@u32.lt"), Done{M.LessThan{}},
      Fail{C.diagnostic(node, "unknown_intrinsic", "unknown scalar intrinsic " ++ name)})))))

def primitive_kind(+name: String) -> Primitive:
  Bool.pick(Primitive, M.name_equal(name, "@ecs.get"), StorageRead{},
    Bool.pick(Primitive, M.name_equal(name, "@ecs.set"), StorageWrite{},
      Bool.pick(Primitive, M.name_equal(name, "@ecs.insert"), StorageInsert{}, ScalarPrimitive{})))

def storage_header(found: Maybe<&2, T.Header>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match found:
    case Some{T.Header{name, identity, 0n}}:
      Done{identity}
    case Some{T.Header{name, identity, arity}}:
      Fail{C.diagnostic(node, "generic_storage_type", "ECS storage requires a concrete non-generic data type")}
    case None{}:
      Fail{C.diagnostic(node, "storage_type", "@ecs.get expects the name of a declared data type")}

def storage_identity(+node: C.Cst, context: Context) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  Context{globals, headers, fixities, locals, label} = context
  do Result<&2, &2, M.Diagnostic, M.TypeId>:
    target : C.Cst <- C.one(C.children_of(node))
    storage_header(T.lookup_header(headers, C.name_of(target)), node)

def storage_update(primitive: Primitive, value: M.Expr) -> M.Expr:
  match primitive:
    case StorageInsert{}:
      M.InsertExpr{value}
    case _:
      M.WriteExpr{value}

def constructor_name(value: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match value:
    case M.ConstructorRefExpr{constructor}:
      Done{constructor}
    case _:
      Fail{C.diagnostic(node, "unknown_constructor", "expected a data constructor")}

def pattern_name(+node: C.Cst) -> PatternResult:
  +source = C.text_of(node)
  +core = unique_name(node)
  Bool.pick(PatternResult, M.name_equal(source, "_"), PatternResult{M.WildcardPattern{}, Nil{}}, PatternResult{M.BindingPattern{core}, [Local{source, core}]})

def pattern_constructor(constructor: String, result: PatternResult) -> PatternResult:
  PatternResult{pattern, locals} = result
  PatternResult{M.ConstructorPattern{constructor, Some{pattern}}, locals}

def lower_pattern(+fuel: Nat, kind: NodeKind, +node: C.Cst, +context: Context) -> Result<&2, &2, M.Diagnostic, PatternResult>:
  match fuel:
    case 0n:
      Fail{C.diagnostic(node, "internal_cst", "pattern exhausted its node-count bound")}
    case 1n+remaining:
      match kind:
        case PatternWrapper{}:
          do Result<&2, &2, M.Diagnostic, PatternResult>:
            +child : C.Cst <- C.one(C.children_of(node))
            lower_pattern(remaining, classify(C.kind_of(child)), child, context)
        case PatternGroup{}:
          lower_pattern(remaining, PatternChildren{}, C.Cst{"", "", "", C.offset_of(node), C.field_values(node, "value")}, context)
        case PatternChildren{}:
          match node:
            case C.Cst{kind, field, text, offset, Nil{}}:
              Done{PatternResult{M.UnitPattern{}, Nil{}}}
            case C.Cst{kind, field, text, offset, +child <> Nil{}}:
              lower_pattern(remaining, classify(C.kind_of(child)), child, context)
            case _:
              Fail{M.Diagnostic{"internal_cst", "parser", "invalid grouped pattern"}}
        case PatternPayload{}:
          match node:
            case C.Cst{kind, constructor, text, offset, Nil{}}:
              Done{PatternResult{M.ConstructorPattern{constructor, None{}}, Nil{}}}
            case C.Cst{kind, constructor, text, offset, +child <> Nil{}}:
              do Result<&2, &2, M.Diagnostic, PatternResult>:
                result : PatternResult <- lower_pattern(remaining, classify(C.kind_of(child)), child, context)
                return pattern_constructor(constructor, result)
            case _:
              Fail{M.Diagnostic{"internal_cst", "parser", "invalid constructor pattern"}}
        case PatternName{}:
          Done{pattern_name(node)}
        case Integer{}:
          do Result<&2, &2, M.Diagnostic, PatternResult>:
            number : U32 <- C.integer(node)
            return PatternResult{M.U32Pattern{number}, Nil{}}
        case Truth{}:
          Done{PatternResult{M.BoolPattern{True{}}, Nil{}}}
        case Falsehood{}:
          Done{PatternResult{M.BoolPattern{False{}}, Nil{}}}
        case PatternConstructor{}:
          do Result<&2, &2, M.Diagnostic, PatternResult>:
            +name : C.Cst <- C.one(C.field_values(node, "name"))
            +target : M.Expr <- resolve(context, C.Cst{"qualified_name", "", "", C.offset_of(name), [name]})
            constructor : String <- constructor_name(target, node)
            lower_pattern(remaining, PatternPayload{}, C.Cst{"payload", constructor, "", C.offset_of(node), C.field_values(node, "payload")}, context)
        case _:
          Fail{C.diagnostic(node, "unsupported_pattern", "unsupported pattern")}

def statement_nodes(node: C.Cst) -> List<&2, C.Cst>:
  C.field_values(node, "statements")

def else_statements(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
        suite : C.Cst <- C.one(C.field_values(node, "alternative"))
        return statement_nodes(suite)
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid else field"}}

def reachable(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match nodes:
    case Nil{}:
      Done{Unit{}}
    case node <> tail:
      Fail{C.diagnostic(node, "unreachable_statement", "statement after return in the same suite")}

def require_plain_do(resolvers: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match resolvers:
    case Nil{}:
      Done{Unit{}}
    case node <> tail:
      Fail{C.diagnostic(node, "unsupported_resolver", "resolver-valued do is parsed, but effect/resolver lowering is not implemented")}

def require_plain_return(markers: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match markers:
    case Nil{}:
      Done{Unit{}}
    case node <> tail:
      Fail{C.diagnostic(node, "resolver_required", "return $ requires a resolver-valued do block; plain do returns values directly")}

def returning(context: Context, value: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match context:
    case Context{globals, headers, fixities, locals, Some{label}}:
      Done{M.ReturnExpr{label, value}}
    case _:
      Fail{C.diagnostic(node, "return_scope", "return requires an enclosing do block in this function")}

def lambda(identity: Nat, param: Parameter, result: Maybe<&2, M.Ty>, body: M.Expr) -> M.Expr:
  Parameter{source, core, annotation} = param
  M.LambdaExpr{identity, core, annotation, result, body}

def plain_binding(pattern: M.Pattern, value: M.Expr, body: M.Expr, offset: Nat) -> M.Expr:
  match pattern:
    case M.BindingPattern{name}:
      M.LetExpr{name, value, body}
    case M.WildcardPattern{}:
      M.LetExpr{"$discard$" ++ Nat.show(offset), value, body}
    case pattern:
      +temporary = "$pattern$" ++ Nat.show(offset)
      M.LetExpr{temporary, value, M.MatchExpr{M.LocalExpr{temporary}, [M.MatchArm{pattern, body}]}}

def binding(guarded: Bool, pattern: M.Pattern, value: M.Expr, alternative: M.Expr, body: M.Expr, offset: Nat) -> M.Expr:
  match guarded:
    case True{}:
      M.GuardExpr{pattern, value, alternative, body}
    case False{}:
      plain_binding(pattern, value, body, offset)

def effect_target(names: List<&2, C.Cst>, offset: Nat) -> Result<&2, &2, M.Diagnostic, Local>:
  match names:
    case Nil{}:
      Done{Local{"_", "$discard$" ++ Nat.show(offset)}}
    case +name <> Nil{}:
      Done{Local{C.text_of(name), unique_name(name)}}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid use binding"}}

def effect_binding(target: Local, value: M.Expr, body: M.Expr) -> M.Expr:
  Local{source, core} = target
  M.UseExpr{core, value, body}

def pattern_of(result: PatternResult) -> M.Pattern:
  PatternResult{pattern, locals} = result
  pattern

def pattern_scope(context: Context, result: PatternResult) -> Context:
  PatternResult{pattern, locals} = result
  bind_all(locals, context)

def symbolic_operator(found: Maybe<&2, O.Fixity>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, O.Operator>:
  match found:
    case Some{fixity}:
      Done{O.from_fixity(fixity, C.offset_of(node))}
    case None{}:
      Fail{C.diagnostic(node, "unknown_operator", "operator has no source fixity declaration: " ++ C.text_of(node))}

def named_operator(found: Maybe<&2, O.Fixity>, target: M.Expr, offset: Nat) -> O.Operator:
  match found:
    case Some{O.Fixity{name, named, precedence, association, ignored}}:
      O.Operator{precedence, association, target, offset}
    case None{}:
      O.Operator{80, O.Left{}, target, offset}

def context_fixities(context: Context) -> List<&2, O.Fixity>:
  Context{globals, headers, fixities, locals, label} = context
  fixities

def source_operator(kind: NodeKind, +node: C.Cst, +context: Context) -> Result<&2, &2, M.Diagnostic, O.Operator>:
  match kind:
    case NamedFixity{}:
      do Result<&2, &2, M.Diagnostic, O.Operator>:
        +name : C.Cst <- C.one(C.field_values(node, "name"))
        target : M.Expr <- resolve(context, name)
        return named_operator(O.lookup(context_fixities(context), C.name_of(name), True{}), target, C.offset_of(node))
    case _:
      symbolic_operator(O.lookup(context_fixities(context), C.text_of(node), False{}), node)

def operator_kind(+node: C.Cst) -> NodeKind:
  Bool.pick(NodeKind, M.name_equal(C.kind_of(node), "named_operator"), NamedFixity{}, SymbolicFixity{})

# Expression and statement recursion share an explicit work type. Each branch
# consumes source-tree fuel; block exits stay explicit rather than copying tails.
def lower(+fuel: Nat, work: Work, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match fuel:
    case 0n:
      Fail{M.Diagnostic{"internal_cst", "parser", "source tree exhausted its node-count bound"}}
    case 1n+remaining:
      match work:
        case Expression{Wrapper{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            child : C.Cst <- C.one(C.children_of(node))
            lower(remaining, visit(child), context)
        case Expression{Integer{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            number : U32 <- C.integer(node)
            return located(C.offset_of(node), M.U32Expr{number})
        case Expression{Truth{}, node}:
          Done{located(C.offset_of(node), M.BoolExpr{True{}})}
        case Expression{Falsehood{}, node}:
          Done{located(C.offset_of(node), M.BoolExpr{False{}})}
        case Expression{Name{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- resolve(context, node)
            return located(C.offset_of(node), value)
        case Expression{GroupNode{}, +node}:
          lower(remaining, Group{C.field_values(node, "value"), C.offset_of(node)}, context)
        case Group{Nil{}, offset}:
          Done{located(offset, M.UnitExpr{})}
        case Group{node <> rest, offset}:
          lower(remaining, visit(node), context)
        case Expression{ApplicationNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            head : C.Cst <- C.one(C.field_values(node, "head"))
            +target : C.Cst <- C.one(C.children_of(head))
            lower(remaining, ApplicationHead{classify(C.kind_of(target)), target, C.field_values(node, "arguments"), C.offset_of(node)}, context)
        case ApplicationHead{Intrinsic{}, +head, arguments, offset}:
          lower(remaining, PrimitiveCall{primitive_kind(C.text_of(head)), head, arguments, offset}, context)
        case PrimitiveCall{ScalarPrimitive{}, +head, left <> right <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            operation : M.ScalarOp <- intrinsic(C.text_of(head), head)
            l : M.Expr <- lower(remaining, visit(left), context)
            r : M.Expr <- lower(remaining, visit(right), context)
            return located(offset, M.ScalarExpr{operation, l, r})
        case PrimitiveCall{ScalarPrimitive{}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "scalar intrinsics require exactly two arguments")}
        case PrimitiveCall{StorageRead{}, head, argument <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            identity : M.TypeId <- storage_identity(argument, context)
            return located(offset, M.ReadExpr{identity})
        case PrimitiveCall{StorageRead{}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "@ecs.get requires exactly one data type name")}
        case PrimitiveCall{primitive, head, argument <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- lower(remaining, visit(argument), context)
            return located(offset, storage_update(primitive, value))
        case PrimitiveCall{primitive, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "ECS updates require exactly one component or resource value")}
        case ApplicationHead{Name{}, head, arguments, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            callee : M.Expr <- resolve(context, head)
            lower(remaining, Arguments{callee, arguments, offset}, context)
        case ApplicationHead{kind, head, arguments, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            callee : M.Expr <- lower(remaining, Expression{kind, head}, context)
            lower(remaining, Arguments{callee, arguments, offset}, context)
        case Arguments{callee, Nil{}, offset}:
          Done{located(offset, callee)}
        case Arguments{callee, head <> rest, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            argument : M.Expr <- lower(remaining, visit(head), context)
            lower(remaining, Arguments{O.invoke(callee, argument), rest, offset}, context)
        case Expression{InfixNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            first : C.Cst <- C.one(C.field_values(node, "head"))
            head : M.Expr <- lower(remaining, visit(first), context)
            lower(remaining, InfixTails{head, C.field_values(node, "tails"), Nil{}}, context)
        case InfixTails{head, Nil{}, tails}:
          O.resolve(Nat.mul(fuel, 4n), O.Read{List.reverse(&2, O.Tail, tails)}, [head], Nil{})
        case InfixTails{head, +node <> rest, tails}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +op_node : C.Cst <- C.one(C.field_values(node, "operator"))
            op : O.Operator <- source_operator(operator_kind(op_node), op_node, context)
            right_node : C.Cst <- C.one(C.field_values(node, "argument"))
            right : M.Expr <- lower(remaining, visit(right_node), context)
            lower(remaining, InfixTails{head, rest, O.Tail{op, right} <> tails}, context)
        case Expression{LambdaNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            param_node : C.Cst <- C.one(C.field_values(node, "parameter"))
            +param : Parameter <- lower_parameter(param_node, remaining, context)
            result : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "result"), remaining, context)
            body_node : C.Cst <- C.one(C.field_values(node, "body"))
            body : M.Expr <- lower(remaining, visit(body_node), with_label(bind_parameter(context, param), None{}))
            return located(C.offset_of(node), lambda(C.offset_of(node), param, result, body))
        case Expression{CaseNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            suite : C.Cst <- C.one(C.field_values(node, "body"))
            value : M.Expr <- lower(remaining, visit(value_node), context)
            result : M.Expr <- lower(remaining, Arms{value, C.field_values(suite, "arms"), Nil{}}, context)
            return located(C.offset_of(node), result)
        case Arms{value, Nil{}, arms}:
          Done{M.MatchExpr{value, List.reverse(&2, M.MatchArm<M.Expr>, arms)}}
        case Arms{value, +node <> rest, arms}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +pattern_node : C.Cst <- C.one(C.field_values(node, "pattern"))
            +pat : PatternResult <- lower_pattern(remaining, classify(C.kind_of(pattern_node)), pattern_node, context)
            body_node : C.Cst <- C.one(C.field_values(node, "body"))
            body : M.Expr <- lower(remaining, visit(body_node), pattern_scope(context, pat))
            lower(remaining, Arms{value, rest, M.MatchArm{pattern_of(pat), body} <> arms}, context)
        case Expression{Block{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            valid : Unit <- require_plain_do(C.field_values(node, "resolver"))
            suite : C.Cst <- C.one(C.field_values(node, "body"))
            body : M.Expr <- lower(remaining, Statements{statement_nodes(suite)}, with_label(context, Some{C.offset_of(node)}))
            return located(C.offset_of(node), M.BlockExpr{C.offset_of(node), body})
        case Expression{kind, node}:
          Fail{C.diagnostic(node, "unsupported_expression", "expression is not implemented in the executable core")}
        case Statements{Nil{}}:
          Done{M.UnitExpr{}}
        case Statements{statement <> tail}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +node : C.Cst <- C.one(C.field_values(statement, "value"))
            lower(remaining, Statement{classify(C.kind_of(node)), node, tail}, context)
        case Statement{Binding{}, +node, tail}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +pattern_node : C.Cst <- C.one(C.field_values(node, "pattern"))
            +pat : PatternResult <- lower_pattern(remaining, classify(C.kind_of(pattern_node)), pattern_node, context)
            ty : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "annotation"), remaining, context)
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            value : M.Expr <- lower(remaining, visit(value_node), context)
            otherwise : List<&2, C.Cst> <- else_statements(C.field_values(node, "fallback"))
            alternative : M.Expr <- lower(remaining, Statements{otherwise}, context)
            body : M.Expr <- lower(remaining, Statements{tail}, pattern_scope(context, pat))
            return located(C.offset_of(node), binding(C.present(C.field_values(node, "fallback")), pattern_of(pat), M.SourceExpr{C.offset_of(node), ty, value}, alternative, body, C.offset_of(node)))
        case Statement{EffectBinding{}, +node, tail}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +target : Local <- effect_target(C.field_values(node, "name"), C.offset_of(node))
            ty : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "annotation"), remaining, context)
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            value : M.Expr <- lower(remaining, visit(value_node), context)
            body : M.Expr <- lower(remaining, Statements{tail}, bind(context, target))
            return located(C.offset_of(node), effect_binding(target, M.SourceExpr{C.offset_of(node), ty, value}, body))
        case Statement{Return{}, +node, tail}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            valid : Unit <- reachable(tail)
            plain : Unit <- require_plain_return(C.field_values(node, "forwarding"))
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            value : M.Expr <- lower(remaining, visit(value_node), context)
            result : M.Expr <- returning(context, value, node)
            return located(C.offset_of(node), result)
        case Statement{Conditional{}, +node, tail}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            test : C.Cst <- C.one(C.field_values(node, "condition"))
            yes : C.Cst <- C.one(C.field_values(node, "consequence"))
            no : List<&2, C.Cst> <- else_statements(C.field_values(node, "fallback"))
            condition : M.Expr <- lower(remaining, visit(test), context)
            consequent : M.Expr <- lower(remaining, Statements{statement_nodes(yes)}, context)
            alternative : M.Expr <- lower(remaining, Statements{no}, context)
            next : M.Expr <- lower(remaining, Statements{tail}, context)
            return M.SequenceExpr{located(C.offset_of(node), M.IfExpr{condition, consequent, alternative}), next}
        case Statement{PatternConditional{}, +node, tail}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +pattern_node : C.Cst <- C.one(C.field_values(node, "pattern"))
            +pat : PatternResult <- lower_pattern(remaining, classify(C.kind_of(pattern_node)), pattern_node, context)
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            yes : C.Cst <- C.one(C.field_values(node, "consequence"))
            no : List<&2, C.Cst> <- else_statements(C.field_values(node, "fallback"))
            value : M.Expr <- lower(remaining, visit(value_node), context)
            consequent : M.Expr <- lower(remaining, Statements{statement_nodes(yes)}, pattern_scope(context, pat))
            alternative : M.Expr <- lower(remaining, Statements{no}, context)
            next : M.Expr <- lower(remaining, Statements{tail}, context)
            +temporary : String <- Done{"$if$" ++ Nat.show(C.offset_of(node))}
            return M.SequenceExpr{located(C.offset_of(node), M.LetExpr{temporary, value, M.MatchExpr{M.LocalExpr{temporary}, [M.MatchArm{pattern_of(pat), consequent}, M.MatchArm{M.WildcardPattern{}, alternative}]}}), next}
        case Statement{kind, node, tail}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            first : M.Expr <- lower(remaining, Expression{kind, node}, context)
            next : M.Expr <- lower(remaining, Statements{tail}, context)
            return M.SequenceExpr{first, next}

def declaration_name(node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  do Result<&2, &2, M.Diagnostic, String>:
    +name : C.Cst <- C.one(C.field_values(node, "name"))
    return Bool.pick(String, M.name_equal(C.kind_of(name), "qualified_name"), C.name_of(name), C.text_of(name))

def require_fresh(found: Maybe<&2, Global>, context: Context, global: Global, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Context>:
  match found context global:
    case None{} Context{globals, headers, fixities, locals, label} Global{+source, core, kind}:
      Done{Context{Map.set(&2, Global, globals, source, Global{source, core, kind}), headers, fixities, locals, label}}
    case _ _ _:
      Fail{C.diagnostic(node, "duplicate_name", "duplicate value or constructor declaration")}

def add_global(+context: Context, +source: String, core: String, kind: GlobalKind, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Context>:
  Context{globals, headers, fixities, locals, label} = context
  require_fresh(lookup_global(globals, source), context, Global{source, core, kind}, node)

def add_header(found: Maybe<&2, T.Header>, context: Context, header: T.Header, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Context>:
  match found context header:
    case None{} Context{globals, headers, fixities, locals, label} T.Header{+source, identity, arity}:
      Done{Context{globals, Map.set(&2, T.Header, headers, source, T.Header{source, identity, arity}), fixities, locals, label}}
    case _ _ _:
      Fail{C.diagnostic(node, "duplicate_type", "duplicate type declaration")}

def collect_constructors(nodes: List<&2, C.Cst>, +prefix: String, context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match nodes:
    case Nil{}:
      Done{context}
    case +node <> rest:
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        next : Context <- add_global(context, name, prefix ++ name, ConstructorName{}, node)
        collect_constructors(rest, prefix, next)

def named_declaration(kind: NodeKind, +node: C.Cst, +prefix: String, module_name: String, +context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match kind:
    case FunctionNode{}:
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        add_global(context, name, prefix ++ name, FunctionName{}, node)
    case ConstantNode{}:
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        add_global(context, name, prefix ++ name, ConstantName{}, node)
    case DataNode{}:
      Context{globals, +headers, fixities, locals, label} = context
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        next : Context <- add_header(T.lookup_header(headers, name), context, T.Header{name, M.TypeId{module_name, name}, List.length(&2, C.Cst, C.field_values(node, "parameters"))}, node)
        collect_constructors(C.field_values(node, "constructors"), prefix, next)
    case _:
      Done{context}

def visible_declaration(visible: Bool, +node: C.Cst, prefix: String, module_name: String, context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match visible:
    case False{}:
      Done{context}
    case True{}:
      named_declaration(classify(C.kind_of(node)), node, prefix, module_name, context)

def collect_names(nodes: List<&2, C.Cst>, +prefix: String, +module_name: String, +public_only: Bool) -> Result<&2, &2, M.Diagnostic, Context>:
  match nodes:
    case Nil{}:
      Done{Context{MTip{}, MTip{}, Nil{}, Nil{}, None{}}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, Context>:
        node : C.Cst <- C.one(C.field_values(head, "value"))
        rest : Context <- collect_names(tail, prefix, module_name, public_only)
        visible_declaration(Bool.or(Bool.not(public_only), C.present(C.field_values(head, "exported"))), node, prefix, module_name, rest)

def combine_context(own: Context, inherited: Context) -> Context:
  Context{globals, headers, fixities, locals, label} = own
  Context{base_globals, base_headers, base_fixities, base_locals, base_label} = inherited
  Context{Map.union(&2, Global, base_globals, globals), Map.union(&2, T.Header, base_headers, headers), List.append(&2, O.Fixity, fixities, base_fixities), locals, label}

def require_header_order(seen_value: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match seen_value:
    case False{}:
      Done{Unit{}}
    case True{}:
      Fail{C.diagnostic(node, "operator_header_order", "operator declarations must precede values and data declarations")}

def fixity_name(kind: NodeKind, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match kind:
    case SymbolicFixity{}:
      do Result<&2, &2, M.Diagnostic, String>:
        symbol : C.Cst <- C.one(C.field_values(node, "symbol"))
        return C.text_of(symbol)
    case _:
      do Result<&2, &2, M.Diagnostic, String>:
        target : C.Cst <- C.one(C.field_values(node, "target"))
        return C.name_of(target)

def require_fixity(found: Maybe<&2, O.Fixity>, valid_precedence: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found valid_precedence:
    case None{} True{}:
      Done{Unit{}}
    case None{} False{}:
      Fail{C.diagnostic(node, "operator_precedence", "operator precedence must be between 0 and 255")}
    case _ _:
      Fail{C.diagnostic(node, "duplicate_operator", "duplicate operator fixity declaration")}

def fixity(kind: NodeKind, +node: C.Cst, context: Context, +rest: List<&2, O.Fixity>) -> Result<&2, &2, M.Diagnostic, List<&2, O.Fixity>>:
  do Result<&2, &2, M.Diagnostic, List<&2, O.Fixity>>:
    +name : String <- fixity_name(kind, node)
    +named : Bool <- Done{M.name_equal(C.kind_of(node), "named_fixity")}
    precedence_node : C.Cst <- C.one(C.field_values(node, "precedence"))
    +precedence : U32 <- C.integer(precedence_node)
    valid : Unit <- require_fixity(O.lookup(rest, name, named), U32.is_le(precedence, 255), node)
    association_node : C.Cst <- C.one(C.field_values(node, "associativity"))
    target_node : C.Cst <- C.one(C.field_values(node, "target"))
    target : M.Expr <- resolve(context, target_node)
    return O.Fixity{name, named, precedence, O.parse_associativity(C.text_of(association_node)), target} <> rest

def is_fixity(kind: NodeKind) -> Bool:
  match kind:
    case SymbolicFixity{}:
      True{}
    case NamedFixity{}:
      True{}
    case _:
      False{}

def collect_header(yes: Bool, +node: C.Cst, seen_value: Bool, context: Context, rest: List<&2, O.Fixity>) -> Result<&2, &2, M.Diagnostic, List<&2, O.Fixity>>:
  match yes:
    case False{}:
      Done{rest}
    case True{}:
      do Result<&2, &2, M.Diagnostic, List<&2, O.Fixity>>:
        valid : Unit <- require_header_order(seen_value, node)
        fixity(classify(C.kind_of(node)), node, context, rest)

def collect_fixities(nodes: List<&2, C.Cst>, +context: Context, +seen_value: Bool) -> Result<&2, &2, M.Diagnostic, List<&2, O.Fixity>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, O.Fixity>>:
        +node : C.Cst <- C.one(C.field_values(head, "value"))
        +header : Bool <- Done{is_fixity(classify(C.kind_of(node)))}
        rest : List<&2, O.Fixity> <- collect_fixities(tail, context, Bool.or(seen_value, Bool.not(header)))
        collect_header(header, node, seen_value, context, rest)

def with_fixities(context: Context, fixities: List<&2, O.Fixity>) -> Context:
  Context{globals, headers, base_fixities, locals, label} = context
  Context{globals, headers, List.append(&2, O.Fixity, fixities, base_fixities), locals, label}

def function_value(name: String, exported: Bool, param: Parameter, result: Maybe<&2, M.Ty>, body: M.Expr) -> M.Function:
  Parameter{source, core, annotation} = param
  M.Function{name, exported, core, annotation, result, body}

def lower_function(+node: C.Cst, name: String, exported: Bool, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Function>:
  do Result<&2, &2, M.Diagnostic, M.Function>:
    parameter_node : C.Cst <- C.one(C.field_values(node, "parameter"))
    +param : Parameter <- lower_parameter(parameter_node, fuel, context)
    result : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "result"), fuel, context)
    body_node : C.Cst <- C.one(C.field_values(node, "body"))
    body : M.Expr <- lower(fuel, visit(body_node), bind_parameter(context, param))
    return function_value(name, exported, param, result, body)

def lower_constant(+node: C.Cst, name: String, exported: Bool, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Constant>:
  do Result<&2, &2, M.Diagnostic, M.Constant>:
    ty : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "annotation"), fuel, context)
    value_node : C.Cst <- C.one(C.field_values(node, "value"))
    value : M.Expr <- lower(fuel, visit(value_node), context)
    return M.Constant{name, exported, ty, value}

def require_parameter(found: Maybe<&2, M.Ty>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case _:
      Fail{C.diagnostic(node, "duplicate_type_parameter", "duplicate type parameter")}

def type_variables(nodes: List<&2, C.Cst>, +index: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
        +rest : List<&2, T.Variable> <- type_variables(tail, 1n+index)
        valid : Unit <- require_parameter(T.lookup_variable(rest, C.text_of(head)), head)
        return T.Variable{C.text_of(head), index} <> rest

def lower_constructors(nodes: List<&2, C.Cst>, +prefix: String, +fuel: Nat, +headers: Map<&2, T.Header>, +variables: List<&2, T.Variable>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Constructor>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Constructor>>:
        name : String <- declaration_name(node)
        payload : Maybe<&2, M.Ty> <- T.annotation(C.field_values(node, "payload"), fuel, headers, variables)
        rest : List<&2, M.Constructor> <- lower_constructors(tail, prefix, fuel, headers, variables)
        return M.Constructor{prefix ++ name, payload} <> rest

def lower_data(+node: C.Cst, name: String, prefix: String, module_name: String, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.DataType>:
  Context{globals, headers, fixities, locals, label} = context
  do Result<&2, &2, M.Diagnostic, M.DataType>:
    variables : List<&2, T.Variable> <- type_variables(C.field_values(node, "parameters"), 0n)
    constructors : List<&2, M.Constructor> <- lower_constructors(C.field_values(node, "constructors"), prefix, fuel, headers, variables)
    return M.DataType{M.TypeId{module_name, name}, List.length(&2, C.Cst, C.field_values(node, "parameters")), constructors}

def add_function(module: M.Module, fn: M.Function) -> M.Module:
  M.Module{descriptors, constants, functions, data_types} = module
  M.Module{descriptors, constants, fn <> functions, data_types}

def add_constant(module: M.Module, constant: M.Constant) -> M.Module:
  M.Module{descriptors, constants, functions, data_types} = module
  M.Module{descriptors, constant <> constants, functions, data_types}

def add_data(module: M.Module, ty: M.DataType) -> M.Module:
  M.Module{descriptors, constants, functions, data_types} = module
  M.Module{descriptors, constants, functions, ty <> data_types}

def declaration(kind: NodeKind, +node: C.Cst, +prefix: String, module_name: String, exported: Bool, rest: M.Module, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match kind:
    case FunctionNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        name : String <- declaration_name(node)
        fn : M.Function <- lower_function(node, prefix ++ name, exported, fuel, context)
        return add_function(rest, fn)
    case ConstantNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        name : String <- declaration_name(node)
        value : M.Constant <- lower_constant(node, prefix ++ name, exported, fuel, context)
        return add_constant(rest, value)
    case DataNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        name : String <- declaration_name(node)
        ty : M.DataType <- lower_data(node, name, prefix, module_name, fuel, context)
        return add_data(rest, ty)
    case _:
      Done{rest}

def storage_attribute(+node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Storage>:
  do Result<&2, &2, M.Diagnostic, M.Storage>:
    target : C.Cst <- C.one(C.field_values(node, "name"))
    +name : String <- Done{C.name_of(target)}
    Bool.pick(Result<&2, &2, M.Diagnostic, M.Storage>, M.name_equal(name, "component"), Done{M.Component{}},
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Storage>, M.name_equal(name, "resource"), Done{M.Resource{}},
        Fail{C.diagnostic(node, "unsupported_attribute", "only #[component] and #[resource] are implemented in the ECS bootstrap")}))

def add_storage(module: M.Module, identity: M.TypeId, storage: M.Storage) -> M.Module:
  M.Module{descriptors, constants, functions, types} = module
  M.Module{M.Descriptor{identity, storage} <> descriptors, constants, functions, types}

def declaration_storage(attributes: List<&2, C.Cst>, kind: NodeKind, +node: C.Cst, module_name: String, module: M.Module) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match attributes kind:
    case Nil{} _:
      Done{module}
    case attribute <> Nil{} DataNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        storage : M.Storage <- storage_attribute(attribute)
        name : String <- declaration_name(node)
        return add_storage(module, M.TypeId{module_name, name}, storage)
    case _ DataNode{}:
      Fail{C.diagnostic(node, "storage_attribute", "a data declaration has exactly one storage classification")}
    case _ _:
      Fail{C.diagnostic(node, "storage_attribute", "storage attributes apply only to data declarations")}

def lower_declarations(nodes: List<&2, C.Cst>, +prefix: String, +module_name: String, +allow_exports: Bool, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match nodes:
    case Nil{}:
      Done{M.Module{Nil{}, Nil{}, Nil{}, Nil{}}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +node : C.Cst <- C.one(C.field_values(head, "value"))
        rest : M.Module <- lower_declarations(tail, prefix, module_name, allow_exports, fuel, context)
        described : M.Module <- declaration_storage(C.field_values(head, "attributes"), classify(C.kind_of(node)), node, module_name, rest)
        declaration(classify(C.kind_of(node)), node, prefix, module_name, Bool.and(allow_exports, C.present(C.field_values(head, "exported"))), described, fuel, context)

def combine_modules(prelude: M.Module, module: M.Module) -> M.Module:
  M.Module{pd, pc, pf, pt} = prelude
  M.Module{md, mc, mf, mt} = module
  M.Module{List.append(&2, M.Descriptor, pd, md), List.append(&2, M.Constant, pc, mc), List.append(&2, M.Function, pf, mf), List.append(&2, M.DataType, pt, mt)}

type Prelude is Data:
  Prelude{module: M.Module, scope: Context}

type SourcePlan is Data:
  SourcePlan{prelude: M.Module, scope: Context, declarations: List<&2, C.Cst>}

def prepare_prelude(prelude: C.Cst, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, Prelude>:
  +prelude_nodes = C.field_values(prelude, "declarations")
  do Result<&2, &2, M.Diagnostic, Prelude>:
    +prelude_scope : Context <- collect_names(prelude_nodes, "$prelude.", "std/prelude", False{})
    +prelude_fixities : List<&2, O.Fixity> <- collect_fixities(prelude_nodes, prelude_scope, False{})
    prelude_module : M.Module <- lower_declarations(prelude_nodes, "$prelude.", "std/prelude", False{}, fuel, with_fixities(prelude_scope, prelude_fixities))
    public_scope : Context <- collect_names(prelude_nodes, "$prelude.", "std/prelude", True{})
    return Prelude{prelude_module, with_fixities(public_scope, prelude_fixities)}

def prepare_source(root: C.Cst, prepared: Prelude) -> Result<&2, &2, M.Diagnostic, SourcePlan>:
  Prelude{prelude_module, public_scope} = prepared
  +nodes = C.field_values(root, "declarations")
  do Result<&2, &2, M.Diagnostic, SourcePlan>:
    local_scope : Context <- collect_names(nodes, "", "main", False{})
    +scope : Context <- Done{combine_context(local_scope, public_scope)}
    fixities : List<&2, O.Fixity> <- collect_fixities(nodes, scope, False{})
    return SourcePlan{prelude_module, with_fixities(scope, fixities), nodes}

def lower_source_declaration(node: C.Cst, context: Context, fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  lower_declarations([node], "", "main", True{}, fuel, context)

def lower_plan(plan: SourcePlan, fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  SourcePlan{prelude_module, scope, nodes} = plan
  do Result<&2, &2, M.Diagnostic, M.Module>:
    module : M.Module <- lower_declarations(nodes, "", "main", True{}, fuel, scope)
    return combine_modules(prelude_module, module)

def source_module(root: C.Cst, prelude: C.Cst, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, M.Module>:
  do Result<&2, &2, M.Diagnostic, M.Module>:
    prepared : Prelude <- prepare_prelude(prelude, fuel)
    plan : SourcePlan <- prepare_source(root, prepared)
    lower_plan(plan, fuel)
