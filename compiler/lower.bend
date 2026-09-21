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
  RecordConstructorName{fields: List<&2, String>}
  OperationName{identity: M.TypeId}

type Global is Data:
  Global{source: String, core: String, kind: GlobalKind}

type Context is Data:
  Context{globals: Map<&2, Global>, headers: Map<&2, T.Header>, fixities: List<&2, O.Fixity>, locals: List<&2, Local>, return_label: Maybe<&2, Nat>}

type NodeKind is Data:
  Wrapper{}
  Integer{}
  Float{}
  PrefixNode{}
  Truth{}
  Falsehood{}
  Name{}
  Intrinsic{}
  FunctionNode{}
  ConstantNode{}
  DataNode{}
  EffectNode{}
  SymbolicFixity{}
  NamedFixity{}
  GroupNode{}
  ArrayNode{}
  RecordNode{}
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
  PatternConstructorForm{fields: List<&2, C.Cst>}
  PatternPayload{}
  PatternChildren{}
  PatternElements{reversed: List<&2, M.Pattern>, locals: List<&2, Local>}
  PatternRecordFields{constructor: String, fields: List<&2, String>, patterns: Map<&2, M.Pattern>, locals: List<&2, Local>}
  PatternName{}
  Unsupported{}

type Primitive is Data:
  ScalarPrimitive{operator: M.ScalarOp}
  UnaryPrimitive{operator: M.UnaryOp}
  ProviderPrimitive{}
  OperationDescriptorPrimitive{}
  FunctionEffectsPrimitive{}
  EffectHasPrimitive{}
  EffectCountPrimitive{}
  EffectSamePrimitive{}
  PanicPrimitive{}
  ProjectPrimitive{}
  ArrayGetPrimitive{}
  ArraySetPrimitive{}
  ArrayLengthPrimitive{}

type RecordTarget is Data:
  RecordTarget{constructor: String, fields: List<&2, String>}

type RecordElement is Data:
  RecordElement{field: String, binding: String, value: M.Expr}

type Work is Data:
  Expression{kind: NodeKind, node: C.Cst}
  Group{nodes: List<&2, C.Cst>, offset: Nat}
  ProductElements{nodes: List<&2, C.Cst>, reversed: List<&2, M.Expr>, offset: Nat}
  ArrayElements{nodes: List<&2, C.Cst>, reversed: List<&2, M.Expr>, offset: Nat}
  RecordElements{constructor: String, fields: List<&2, String>, nodes: List<&2, C.Cst>, reversed: List<&2, RecordElement>, seen: Set(), node: C.Cst}
  Arguments{callee: M.Expr, nodes: List<&2, C.Cst>, offset: Nat}
  ApplicationHead{kind: NodeKind, head: C.Cst, arguments: List<&2, C.Cst>, offset: Nat}
  PrimitiveCall{primitive: Primitive, head: C.Cst, arguments: List<&2, C.Cst>, offset: Nat}
  DescriptorArgument{sealed: Bool, node: C.Cst}
  InfixTails{head: M.Expr, nodes: List<&2, C.Cst>, tails: List<&2, O.Tail>}
  CaseValues{nodes: List<&2, C.Cst>, reversed: List<&2, M.Expr>, arms: List<&2, C.Cst>}
  Arms{values: List<&2, M.Expr>, nodes: List<&2, C.Cst>, arms: List<&2, M.MatchArm<M.Expr>>}
  ResolvedBlock{resolvers: List<&2, C.Cst>, body: M.Expr, offset: Nat}
  Statements{nodes: List<&2, C.Cst>}
  Statement{kind: NodeKind, node: C.Cst, tail: List<&2, C.Cst>}

type Parameter is Data:
  Parameter{source: String, core: String, annotation: Maybe<&2, M.Ty>}

type PatternResult is Data:
  PatternResult{pattern: M.Pattern, locals: List<&2, Local>}

type PatternRow is Data:
  PatternRow{patterns: List<&2, M.Pattern>, locals: List<&2, Local>}

# Keep small enums, but do not eagerly compare every node with all 33 labels.
# Dispatching on the initial leaves at most four full, exact comparisons.
def classify_initial(initial: Char, +kind: String) -> NodeKind:
  match initial:
    case 'I':
      Bool.pick(NodeKind, M.name_equal(kind, "INTEGER"), Integer{}, Bool.pick(NodeKind, M.name_equal(kind, "INTRINSIC"), Intrinsic{}, Bool.pick(NodeKind, M.name_equal(kind, "IDENT"), PatternName{}, Unsupported{})))
    case 'F':
      Bool.pick(NodeKind, M.name_equal(kind, "FLOAT"), Float{}, Bool.pick(NodeKind, M.name_equal(kind, "False"), Falsehood{}, Unsupported{}))
    case 'T':
      Bool.pick(NodeKind, M.name_equal(kind, "True"), Truth{}, Unsupported{})
    case 'a':
      Bool.pick(NodeKind, M.name_equal(kind, "atom"), Wrapper{}, Bool.pick(NodeKind, M.name_equal(kind, "array"), ArrayNode{}, Bool.pick(NodeKind, M.name_equal(kind, "application"), ApplicationNode{}, Unsupported{})))
    case 'b':
      Bool.pick(NodeKind, M.name_equal(kind, "binding"), Binding{}, Unsupported{})
    case 'c':
      Bool.pick(NodeKind, M.name_equal(kind, "constant"), ConstantNode{}, Bool.pick(NodeKind, M.name_equal(kind, "case_expression"), CaseNode{}, Bool.pick(NodeKind, M.name_equal(kind, "conditional"), Conditional{}, Bool.pick(NodeKind, M.name_equal(kind, "constructor_pattern"), PatternConstructor{}, Unsupported{}))))
    case 'd':
      Bool.pick(NodeKind, M.name_equal(kind, "data_type"), DataNode{}, Bool.pick(NodeKind, M.name_equal(kind, "do_block"), Block{}, Unsupported{}))
    case 'e':
      Bool.pick(NodeKind, M.name_equal(kind, "expression"), Wrapper{}, Bool.pick(NodeKind, M.name_equal(kind, "effect_binding"), EffectBinding{}, Bool.pick(NodeKind, M.name_equal(kind, "effect_step"), EffectBinding{}, Bool.pick(NodeKind, M.name_equal(kind, "effect_declaration"), EffectNode{}, Unsupported{}))))
    case 'f':
      Bool.pick(NodeKind, M.name_equal(kind, "function"), FunctionNode{}, Unsupported{})
    case 'g':
      Bool.pick(NodeKind, M.name_equal(kind, "group"), GroupNode{}, Unsupported{})
    case 'i':
      Bool.pick(NodeKind, M.name_equal(kind, "infix_expression"), InfixNode{}, Unsupported{})
    case 'l':
      Bool.pick(NodeKind, M.name_equal(kind, "lambda"), LambdaNode{}, Unsupported{})
    case 'n':
      Bool.pick(NodeKind, M.name_equal(kind, "named_fixity"), NamedFixity{}, Unsupported{})
    case 'p':
      Bool.pick(NodeKind, M.name_equal(kind, "prefix_expression"), PrefixNode{}, Bool.pick(NodeKind, M.name_equal(kind, "pattern_conditional"), PatternConditional{}, Bool.pick(NodeKind, M.name_equal(kind, "pattern"), PatternWrapper{}, Bool.pick(NodeKind, M.name_equal(kind, "pattern_group"), PatternGroup{}, Unsupported{}))))
    case 'q':
      Bool.pick(NodeKind, M.name_equal(kind, "qualified_name"), Name{}, Unsupported{})
    case 'r':
      Bool.pick(NodeKind, M.name_equal(kind, "record"), RecordNode{}, Bool.pick(NodeKind, M.name_equal(kind, "result"), Return{}, Unsupported{}))
    case 's':
      Bool.pick(NodeKind, M.name_equal(kind, "symbolic_fixity"), SymbolicFixity{}, Unsupported{})
    case _:
      Unsupported{}

def classify(+kind: String) -> NodeKind:
  match kind:
    case SNil{}:
      Unsupported{}
    case SCon{initial, tail}:
      classify_initial(initial, kind)

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
    case Some{Global{source, core, RecordConstructorName{fields}}}:
      Done{M.ConstructorRefExpr{core}}
    case Some{Global{source, core, OperationName{identity}}}:
      Done{M.OperationExpr{identity}}
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

def record_name(node: C.Cst) -> String:
  match node:
    case C.Cst{kind, field, text, offset, Nil{}}:
      text
    case C.Cst{kind, field, text, offset, children}:
      C.texts(children)

def record_global(local: Maybe<&2, String>, found: Maybe<&2, Global>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, RecordTarget>:
  match local found:
    case None{} Some{Global{source, core, RecordConstructorName{fields}}}:
      Done{RecordTarget{core, fields}}
    case None{} None{}:
      Fail{C.diagnostic(node, "unknown_constructor", "unknown record constructor: " ++ record_name(node))}
    case _ _:
      Fail{C.diagnostic(node, "record_constructor", "named fields require a declared record constructor")}

def record_target(context: Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, RecordTarget>:
  Context{globals, headers, fixities, locals, label} = context
  +name = record_name(node)
  record_global(lookup_local(locals, name), lookup_global(globals, name), node)

def record_field_present(fields: List<&2, String>, +name: String) -> Bool:
  match fields:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(M.name_equal(head, name), record_field_present(tail, name))

def record_field_valid(known: Bool, duplicate: Bool, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match known duplicate:
    case False{} _:
      Fail{C.diagnostic(node, "unknown_record_field", "record has no field named " ++ C.text_of(node))}
    case True{} True{}:
      Fail{C.diagnostic(node, "duplicate_record_field", "record field is supplied more than once: " ++ C.text_of(node))}
    case True{} False{}:
      Done{Unit{}}

def record_field_names(nodes: List<&2, C.Cst>, +seen: Set(), reversed: List<&2, String>) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match nodes:
    case Nil{}:
      Done{List.reverse(&2, String, reversed)}
    case node <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, String>>:
        +name_node : C.Cst <- C.one(C.field_values(node, "name"))
        +name : String <- Done{C.text_of(name_node)}
        valid : Unit <- record_field_valid(True{}, Maybe.is_some(&2, Unit, Index.find(Unit, seen, name)), name_node)
        record_field_names(rest, Set.add(seen, name), name <> reversed)

def record_kind(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, GlobalKind>:
  match nodes:
    case Nil{}:
      Done{ConstructorName{}}
    case node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, GlobalKind>:
        fields : List<&2, String> <- record_field_names(C.field_values(node, "fields"), MTip{}, Nil{})
        return RecordConstructorName{fields}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid record declaration fields"}}

def record_value_node(values: List<&2, C.Cst>, +name: C.Cst) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match values:
    case Nil{}:
      Done{C.Cst{"qualified_name", "value", "", C.offset_of(name), [name]}}
    case value <> Nil{}:
      Done{value}
    case _:
      Fail{C.diagnostic(name, "internal_cst", "invalid record field value")}

def record_element_binding(elements: List<&2, RecordElement>, +field: String) -> Maybe<&2, String>:
  match elements:
    case Nil{}:
      None{}
    case RecordElement{label, binding, value} <> rest:
      Bool.pick(Maybe<&2, String>, M.name_equal(field, label), Some{binding}, record_element_binding(rest, field))

def require_record_element(found: Maybe<&2, String>, field: String, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{binding}:
      Done{M.LocalExpr{binding}}
    case None{}:
      Fail{C.diagnostic(node, "missing_record_field", "missing record field: " ++ field)}

def record_payload_elements(fields: List<&2, String>, +elements: List<&2, RecordElement>, +node: C.Cst, reversed: List<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
  match fields:
    case Nil{}:
      Done{List.reverse(&2, M.Expr, reversed)}
    case +field <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Expr>>:
        value : M.Expr <- require_record_element(record_element_binding(elements, field), field, node)
        record_payload_elements(rest, elements, node, value <> reversed)

def record_payload(values: List<&2, M.Expr>) -> Maybe<&2, M.Expr>:
  match values:
    case Nil{}:
      None{}
    case value <> Nil{}:
      Some{value}
    case first <> second <> rest:
      Some{M.ProductExpr{first <> second <> rest}}

# Bind in source order before arranging the payload in declaration order.
def record_bindings(reversed: List<&2, RecordElement>, body: M.Expr) -> M.Expr:
  match reversed:
    case Nil{}:
      body
    case RecordElement{field, binding, value} <> rest:
      record_bindings(rest, M.UseExpr{binding, value, body})

def record_elements(target: RecordTarget, fields: C.Cst, node: C.Cst) -> Work:
  RecordTarget{constructor, names} = target
  RecordElements{constructor, names, C.field_values(fields, "fields"), Nil{}, MTip{}, node}

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

def effect_name(found: Maybe<&2, Global>) -> Maybe<&2, M.TypeId>:
  match found:
    case Some{Global{source, core, OperationName{identity}}}:
      Some{identity}
    case _:
      None{}

def lookup_effect(globals: Map<&2, Global>, name: String) -> Maybe<&2, M.TypeId>:
  effect_name(lookup_global(globals, name))

# Type traversal looks up only actual row labels in the existing indexed scope.
def source_annotation(nodes: List<&2, C.Cst>, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  match nodes:
    case Nil{}:
      Done{None{}}
    case head <> tail:
      Context{globals, headers, fixities, locals, label} = context
      T.annotation(~Map<&2, Global>, ~lookup_effect, head <> tail, fuel, headers, Nil{}, globals)

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

def scalar_intrinsic(+name: String, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Primitive>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.add"), Done{ScalarPrimitive{M.Add{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.sub"), Done{ScalarPrimitive{M.Subtract{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.mul"), Done{ScalarPrimitive{M.Multiply{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.eq"), Done{ScalarPrimitive{M.Equal{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.lt"), Done{ScalarPrimitive{M.LessThan{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.add"), Done{ScalarPrimitive{M.F32Add{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.sub"), Done{ScalarPrimitive{M.F32Subtract{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.mul"), Done{ScalarPrimitive{M.F32Multiply{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.div"), Done{ScalarPrimitive{M.F32Divide{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.eq"), Done{ScalarPrimitive{M.F32Equal{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.ne"), Done{ScalarPrimitive{M.F32NotEqual{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.lt"), Done{ScalarPrimitive{M.F32LessThan{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.le"), Done{ScalarPrimitive{M.F32LessEqual{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.gt"), Done{ScalarPrimitive{M.F32GreaterThan{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.ge"), Done{ScalarPrimitive{M.F32GreaterEqual{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.neg"), Done{UnaryPrimitive{M.F32Negate{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.abs"), Done{UnaryPrimitive{M.F32Absolute{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.sqrt"), Done{UnaryPrimitive{M.F32SquareRoot{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.floor"), Done{UnaryPrimitive{M.F32Floor{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.ceil"), Done{UnaryPrimitive{M.F32Ceiling{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.trunc"), Done{UnaryPrimitive{M.F32Truncate{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.to_f32"), Done{UnaryPrimitive{M.U32ToF32{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@f32.to_u32"), Done{UnaryPrimitive{M.F32ToU32{}}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@panic"), Done{PanicPrimitive{}},
      Fail{C.diagnostic(node, "unknown_intrinsic", "unknown compiler intrinsic " ++ name)}))))))))))))))))))))))))

def intrinsic(+name: String, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Primitive>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@product.get"), Done{ProjectPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@array.get"), Done{ArrayGetPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@array.set"), Done{ArraySetPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@array.length"), Done{ArrayLengthPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.provider"), Done{ProviderPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.descriptor"), Done{OperationDescriptorPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.of"), Done{FunctionEffectsPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.has"), Done{EffectHasPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.count"), Done{EffectCountPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.same"), Done{EffectSamePrimitive{}},
      scalar_intrinsic(name, node)))))))))))

def projection_index_kind(valid: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match valid:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{C.diagnostic(node, "product_index_literal", "product projection requires a literal zero-based index")}

def projection_index_children(children: List<&2, C.Cst>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Nat>:
  match children:
    case +child <> Nil{}:
      do Result<&2, &2, M.Diagnostic, Nat>:
        valid : Unit <- projection_index_kind(M.name_equal(C.kind_of(child), "INTEGER"), node)
        index : U32 <- C.integer(child)
        return U32.to_nat(index)
    case _:
      Fail{C.diagnostic(node, "product_index_literal", "product projection requires a literal zero-based index")}

def literal_token(valid: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match valid:
    case True{}:
      C.literal(node)
    case False{}:
      Fail{C.diagnostic(node, "literal_required", "this intrinsic requires a literal string argument")}

def literal_children(children: List<&2, C.Cst>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match children:
    case +child <> Nil{}:
      literal_token(M.name_equal(C.kind_of(child), "STRING"), child)
    case _:
      Fail{C.diagnostic(node, "literal_required", "this intrinsic requires a literal string argument")}

def literal_argument(+node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  literal_children(C.children_of(node), node)

def operation_reference(value: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match value:
    case M.OperationExpr{identity}:
      Done{identity}
    case _:
      Fail{C.diagnostic(node, "operation_target", "expected the name of a declared effect operation")}

def foreign_argument_children(nodes: List<&2, C.Cst>) -> Bool:
  match nodes:
    case +node <> Nil{}:
      Bool.and(M.name_equal(C.kind_of(node), "qualified_name"), M.name_equal(C.name_of(node), "Foreign"))
    case _:
      False{}

def foreign_argument(node: C.Cst) -> Bool:
  foreign_argument_children(C.children_of(node))

def operation_target(sealed: Bool, node: C.Cst, +context: Context) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match sealed:
    case True{}:
      Fail{C.diagnostic(node, "sealed_effect", "Foreign is a compiler effect label, not a callable or providable operation")}
    case False{}:
      do Result<&2, &2, M.Diagnostic, M.TypeId>:
        +target : C.Cst <- C.one(C.children_of(node))
        value : M.Expr <- resolve(context, target)
        operation_reference(value, target)

def operation_name(+node: C.Cst, context: Context) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  operation_target(foreign_argument(node), node, context)

def descriptor_target(sealed: Bool, node: C.Cst, context: Context) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match sealed:
    case True{}:
      Done{M.foreign_identity()}
    case False{}:
      operation_name(node, context)

def descriptor_name(+node: C.Cst, context: Context) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  descriptor_target(foreign_argument(node), node, context)

def function_reference(value: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match value:
    case M.FunctionExpr{callee}:
      Done{callee}
    case _:
      Fail{C.diagnostic(node, "function_target", "effect reflection requires a statically named top-level function")}

def function_name(node: C.Cst, +context: Context) -> Result<&2, &2, M.Diagnostic, String>:
  do Result<&2, &2, M.Diagnostic, String>:
    +target : C.Cst <- C.one(C.children_of(node))
    value : M.Expr <- resolve(context, target)
    function_reference(value, target)

def prefix(operators: List<&2, C.Cst>, value: M.Expr) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match operators:
    case Nil{}:
      Done{value}
    case C.Cst{kind, field, "-", offset, children} <> Nil{}:
      Done{located(offset, M.UnaryExpr{M.F32Negate{}, value})}
    case node <> rest:
      Fail{C.diagnostic(node, "unsupported_prefix", "only F32 prefix negation (-) is supported")}

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

def unique_pattern_local(found: Maybe<&2, String>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case Some{core}:
      Fail{C.diagnostic(node, "duplicate_pattern_binding", "a pattern cannot bind the same name more than once")}

def unique_pattern_locals(locals: List<&2, Local>, +previous: List<&2, Local>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match locals:
    case Nil{}:
      Done{Unit{}}
    case Local{source, core} <> rest:
      do Result<&2, &2, M.Diagnostic, Unit>:
        valid : Unit <- unique_pattern_local(lookup_local(previous, source), node)
        unique_pattern_locals(rest, previous, node)

def pattern_element(result: PatternResult, reversed: List<&2, M.Pattern>, +previous: List<&2, Local>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, NodeKind>:
  PatternResult{pattern, +locals} = result
  do Result<&2, &2, M.Diagnostic, NodeKind>:
    valid : Unit <- unique_pattern_locals(locals, previous, node)
    return PatternElements{pattern <> reversed, List.append(&2, Local, locals, previous)}

def record_pattern_start(target: RecordTarget) -> NodeKind:
  RecordTarget{constructor, fields} = target
  PatternRecordFields{constructor, fields, MTip{}, Nil{}}

def record_pattern_value(values: List<&2, C.Cst>, name: C.Cst) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match values:
    case Nil{}:
      Done{name}
    case value <> Nil{}:
      Done{value}
    case _:
      Fail{C.diagnostic(name, "internal_cst", "record pattern field has multiple patterns")}

def record_pattern_field(result: PatternResult, constructor: String, fields: List<&2, String>, patterns: Map<&2, M.Pattern>, +previous: List<&2, Local>, +name: C.Cst) -> Result<&2, &2, M.Diagnostic, NodeKind>:
  PatternResult{pattern, +locals} = result
  do Result<&2, &2, M.Diagnostic, NodeKind>:
    valid : Unit <- unique_pattern_locals(locals, previous, name)
    return PatternRecordFields{constructor, fields, Map.set(&2, M.Pattern, patterns, C.text_of(name), pattern), List.append(&2, Local, locals, previous)}

def record_pattern_fields(fields: List<&2, String>, +patterns: Map<&2, M.Pattern>) -> List<&2, M.Pattern>:
  match fields:
    case Nil{}:
      Nil{}
    case name <> tail:
      Index.get(M.Pattern, patterns, name, M.WildcardPattern{}) <> record_pattern_fields(tail, patterns)

def record_pattern_result(elements: List<&2, M.Pattern>, constructor: String, locals: List<&2, Local>) -> PatternResult:
  match elements:
    case Nil{}:
      PatternResult{M.ConstructorPattern{constructor, None{}}, locals}
    case element <> Nil{}:
      PatternResult{M.ConstructorPattern{constructor, Some{element}}, locals}
    case first <> second <> tail:
      PatternResult{M.ConstructorPattern{constructor, Some{M.ProductPattern{first <> second <> tail}}}, locals}

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
            case C.Cst{kind, field, text, offset, first <> second <> tail}:
              lower_pattern(remaining, PatternElements{Nil{}, Nil{}}, C.Cst{kind, field, text, offset, first <> second <> tail}, context)
        case PatternElements{reversed, locals}:
          match node:
            case C.Cst{kind, field, text, offset, Nil{}}:
              Done{PatternResult{M.ProductPattern{List.reverse(&2, M.Pattern, reversed)}, locals}}
            case C.Cst{kind, field, text, offset, +child <> tail}:
              do Result<&2, &2, M.Diagnostic, PatternResult>:
                result : PatternResult <- lower_pattern(remaining, classify(C.kind_of(child)), child, context)
                next : NodeKind <- pattern_element(result, reversed, locals, child)
                lower_pattern(remaining, next, C.Cst{kind, field, text, offset, tail}, context)
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
          lower_pattern(remaining, PatternConstructorForm{C.field_values(node, "fields")}, node, context)
        case PatternConstructorForm{Nil{}}:
          do Result<&2, &2, M.Diagnostic, PatternResult>:
            +name : C.Cst <- C.one(C.field_values(node, "name"))
            name_node : C.Cst <- Done{Bool.pick(C.Cst, M.name_equal(C.kind_of(name), "TYPE_IDENT"), C.Cst{"qualified_name", "", "", C.offset_of(name), [name]}, name)}
            target : M.Expr <- resolve(context, name_node)
            constructor : String <- constructor_name(target, node)
            lower_pattern(remaining, PatternPayload{}, C.Cst{"payload", constructor, "", C.offset_of(node), C.field_values(node, "payload")}, context)
        case PatternConstructorForm{+fields <> Nil{}}:
          do Result<&2, &2, M.Diagnostic, PatternResult>:
            name : C.Cst <- C.one(C.field_values(node, "name"))
            target : RecordTarget <- record_target(context, name)
            lower_pattern(remaining, record_pattern_start(target), C.Cst{"record_pattern", "", "", C.offset_of(fields), C.field_values(fields, "fields")}, context)
        case PatternConstructorForm{fields}:
          Fail{C.diagnostic(node, "internal_cst", "constructor pattern has multiple field groups")}
        case PatternRecordFields{constructor, +fields, +patterns, locals}:
          match node:
            case C.Cst{kind, field, text, offset, Nil{}}:
              Done{record_pattern_result(record_pattern_fields(fields, patterns), constructor, locals)}
            case C.Cst{kind, field, text, offset, +child <> tail}:
              do Result<&2, &2, M.Diagnostic, PatternResult>:
                +name : C.Cst <- C.one(C.field_values(child, "name"))
                valid : Unit <- record_field_valid(record_field_present(fields, C.text_of(name)), Maybe.is_some(&2, M.Pattern, Index.find(M.Pattern, patterns, C.text_of(name))), name)
                +value : C.Cst <- record_pattern_value(C.field_values(child, "value"), name)
                result : PatternResult <- lower_pattern(remaining, classify(C.kind_of(value)), value, context)
                next : NodeKind <- record_pattern_field(result, constructor, fields, patterns, locals, name)
                lower_pattern(remaining, next, C.Cst{kind, field, text, offset, tail}, context)
        case _:
          Fail{C.diagnostic(node, "unsupported_pattern", "unsupported pattern")}

def combine_pattern_row(first: PatternResult, next: PatternRow, node: C.Cst) -> Result<&2, &2, M.Diagnostic, PatternRow>:
  PatternResult{pattern, +locals} = first
  PatternRow{patterns, +following} = next
  do Result<&2, &2, M.Diagnostic, PatternRow>:
    valid : Unit <- unique_pattern_locals(locals, following, node)
    return PatternRow{pattern <> patterns, List.append(&2, Local, locals, following)}

def row_patterns(row: PatternRow) -> List<&2, M.Pattern>:
  PatternRow{patterns, locals} = row
  patterns

def row_scope(context: Context, row: PatternRow) -> Context:
  PatternRow{patterns, locals} = row
  bind_all(locals, context)

def lower_pattern_row(nodes: List<&2, C.Cst>, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, PatternRow>:
  match nodes:
    case Nil{}:
      Done{PatternRow{Nil{}, Nil{}}}
    case +node <> tail:
      do Result<&2, &2, M.Diagnostic, PatternRow>:
        first : PatternResult <- lower_pattern(fuel, classify(C.kind_of(node)), node, context)
        next : PatternRow <- lower_pattern_row(tail, fuel, context)
        combine_pattern_row(first, next, node)

def descriptor_argument(+fuel: Nat, value: M.Expr) -> M.Expr:
  match fuel value:
    case 1n+rest M.SourceExpr{offset, annotation, inner}:
      M.SourceExpr{offset, annotation, descriptor_argument(rest, inner)}
    case _ M.OperationExpr{identity}:
      M.OperationDescriptorExpr{identity}
    case _ other:
      other

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

def require_plain_return(markers: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match markers:
    case Nil{}:
      Done{Unit{}}
    case node <> tail:
      Fail{C.diagnostic(node, "resolver_required", "return $ requires monad resolution, which is not implemented; provider blocks return plain values")}

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
      M.LetExpr{temporary, value, M.MatchExpr{[M.LocalExpr{temporary}], [M.MatchArm{[pattern], body}]}}

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
        case Expression{Float{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            number : F32 <- C.float(node)
            return located(C.offset_of(node), M.F32Expr{number})
        case Expression{PrefixNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            child : C.Cst <- C.one(C.field_values(node, "value"))
            value : M.Expr <- lower(remaining, visit(child), context)
            prefix(C.field_values(node, "operator"), value)
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
        case Group{node <> Nil{}, offset}:
          lower(remaining, visit(node), context)
        case Group{head <> next <> rest, offset}:
          lower(remaining, ProductElements{head <> next <> rest, Nil{}, offset}, context)
        case ProductElements{Nil{}, reversed, offset}:
          Done{located(offset, M.ProductExpr{List.reverse(&2, M.Expr, reversed)})}
        case ProductElements{head <> tail, reversed, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            element : M.Expr <- lower(remaining, visit(head), context)
            lower(remaining, ProductElements{tail, element <> reversed, offset}, context)
        case Expression{ArrayNode{}, +node}:
          lower(remaining, ArrayElements{C.field_values(node, "elements"), Nil{}, C.offset_of(node)}, context)
        case ArrayElements{Nil{}, reversed, offset}:
          Done{located(offset, M.ArrayExpr{List.reverse(&2, M.Expr, reversed)})}
        case ArrayElements{head <> tail, reversed, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            element : M.Expr <- lower(remaining, visit(head), context)
            lower(remaining, ArrayElements{tail, element <> reversed, offset}, context)
        case Expression{RecordNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            name : C.Cst <- C.one(C.field_values(node, "name"))
            target : RecordTarget <- record_target(context, name)
            fields : C.Cst <- C.one(C.field_values(node, "fields"))
            lower(remaining, record_elements(target, fields, node), context)
        case RecordElements{constructor, fields, Nil{}, +reversed, seen, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            payload : List<&2, M.Expr> <- record_payload_elements(fields, reversed, node, Nil{})
            return located(C.offset_of(node), record_bindings(reversed, M.ConstructExpr{constructor, record_payload(payload)}))
        case RecordElements{constructor, +fields, +field <> tail, reversed, +seen, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +name_node : C.Cst <- C.one(C.field_values(field, "name"))
            +name : String <- Done{C.text_of(name_node)}
            valid : Unit <- record_field_valid(record_field_present(fields, name), Maybe.is_some(&2, Unit, Index.find(Unit, seen, name)), name_node)
            value_node : C.Cst <- record_value_node(C.field_values(field, "value"), name_node)
            value : M.Expr <- lower(remaining, visit(value_node), context)
            temporary : String <- Done{"$record$" ++ Nat.show(C.offset_of(field))}
            lower(remaining, RecordElements{constructor, fields, tail, RecordElement{name, temporary, value} <> reversed, Set.add(seen, name), node}, context)
        case Expression{ApplicationNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            head : C.Cst <- C.one(C.field_values(node, "head"))
            +target : C.Cst <- C.one(C.children_of(head))
            lower(remaining, ApplicationHead{classify(C.kind_of(target)), target, C.field_values(node, "arguments"), C.offset_of(node)}, context)
        case ApplicationHead{Intrinsic{}, +head, arguments, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            primitive : Primitive <- intrinsic(C.text_of(head), head)
            lower(remaining, PrimitiveCall{primitive, head, arguments, offset}, context)
        case PrimitiveCall{ScalarPrimitive{operation}, head, left <> right <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            l : M.Expr <- lower(remaining, visit(left), context)
            r : M.Expr <- lower(remaining, visit(right), context)
            return located(offset, M.ScalarExpr{operation, l, r})
        case PrimitiveCall{ScalarPrimitive{operator}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "scalar intrinsics require exactly two arguments")}
        case PrimitiveCall{UnaryPrimitive{operator}, head, argument <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- lower(remaining, visit(argument), context)
            return located(offset, M.UnaryExpr{operator, value})
        case PrimitiveCall{UnaryPrimitive{operator}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "unary intrinsics require exactly one argument")}
        case PrimitiveCall{ProjectPrimitive{}, head, argument <> +index_node <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- lower(remaining, visit(argument), context)
            index : Nat <- projection_index_children(C.children_of(index_node), index_node)
            return located(offset, M.ProjectExpr{value, index})
        case PrimitiveCall{ArrayGetPrimitive{}, head, array_node <> index_node <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            array : M.Expr <- lower(remaining, visit(array_node), context)
            index : M.Expr <- lower(remaining, visit(index_node), context)
            return located(offset, M.ArrayGetExpr{array, index})
        case PrimitiveCall{ArraySetPrimitive{}, head, array_node <> index_node <> value_node <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            array : M.Expr <- lower(remaining, visit(array_node), context)
            index : M.Expr <- lower(remaining, visit(index_node), context)
            value : M.Expr <- lower(remaining, visit(value_node), context)
            return located(offset, M.ArraySetExpr{array, index, value})
        case PrimitiveCall{ArrayLengthPrimitive{}, head, array_node <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            array : M.Expr <- lower(remaining, visit(array_node), context)
            return located(offset, M.ArrayLengthExpr{array})
        case PrimitiveCall{ProviderPrimitive{}, head, operation <> implementation <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            identity : M.TypeId <- operation_name(operation, context)
            value : M.Expr <- lower(remaining, visit(implementation), context)
            return located(offset, M.ProviderExpr{identity, value})
        case PrimitiveCall{OperationDescriptorPrimitive{}, head, operation <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            identity : M.TypeId <- descriptor_name(operation, context)
            return located(offset, M.OperationDescriptorExpr{identity})
        case PrimitiveCall{FunctionEffectsPrimitive{}, head, target <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            callee : String <- function_name(target, context)
            return located(offset, M.FunctionEffectsExpr{callee})
        case PrimitiveCall{EffectHasPrimitive{}, head, set <> +operation <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- lower(remaining, visit(set), context)
            target : M.Expr <- lower(remaining, DescriptorArgument{foreign_argument(operation), operation}, context)
            return located(offset, M.EffectHasExpr{value, target})
        case DescriptorArgument{True{}, node}:
          Done{located(C.offset_of(node), M.OperationDescriptorExpr{M.foreign_identity()})}
        case DescriptorArgument{False{}, node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            target : M.Expr <- lower(remaining, visit(node), context)
            return descriptor_argument(remaining, target)
        case PrimitiveCall{EffectCountPrimitive{}, head, set <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- lower(remaining, visit(set), context)
            return located(offset, M.EffectCountExpr{value})
        case PrimitiveCall{EffectSamePrimitive{}, head, left <> right <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            l : M.Expr <- lower(remaining, visit(left), context)
            r : M.Expr <- lower(remaining, visit(right), context)
            return located(offset, M.EffectSameExpr{l, r})
        case PrimitiveCall{PanicPrimitive{}, head, argument <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            message : String <- literal_argument(argument)
            return located(offset, M.PanicExpr{message})
        case PrimitiveCall{PanicPrimitive{}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "@panic requires exactly one literal message")}
        case PrimitiveCall{primitive, +head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "wrong number of arguments to compiler primitive " ++ C.text_of(head))}
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
            suite : C.Cst <- C.one(C.field_values(node, "body"))
            result : M.Expr <- lower(remaining, CaseValues{C.field_values(node, "values"), Nil{}, C.field_values(suite, "arms")}, context)
            return located(C.offset_of(node), result)
        case CaseValues{Nil{}, reversed, arms}:
          lower(remaining, Arms{List.reverse(&2, M.Expr, reversed), arms, Nil{}}, context)
        case CaseValues{head <> tail, reversed, arms}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- lower(remaining, visit(head), context)
            lower(remaining, CaseValues{tail, value <> reversed, arms}, context)
        case Arms{values, Nil{}, arms}:
          Done{M.MatchExpr{values, List.reverse(&2, M.MatchArm<M.Expr>, arms)}}
        case Arms{values, +node <> rest, arms}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +row : PatternRow <- lower_pattern_row(C.field_values(node, "patterns"), remaining, context)
            body_node : C.Cst <- C.one(C.field_values(node, "body"))
            body : M.Expr <- lower(remaining, visit(body_node), row_scope(context, row))
            lower(remaining, Arms{values, rest, M.MatchArm{row_patterns(row), body} <> arms}, context)
        case Expression{Block{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            suite : C.Cst <- C.one(C.field_values(node, "body"))
            body : M.Expr <- lower(remaining, Statements{statement_nodes(suite)}, with_label(context, Some{C.offset_of(node)}))
            lower(remaining, ResolvedBlock{C.field_values(node, "resolver"), body, C.offset_of(node)}, context)
        case ResolvedBlock{Nil{}, body, +offset}:
          Done{located(offset, M.BlockExpr{offset, body})}
        case ResolvedBlock{provider_node <> Nil{}, body, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            provider : M.Expr <- lower(remaining, visit(provider_node), context)
            return located(offset, M.HandleExpr{provider, M.BlockExpr{offset, body}})
        case ResolvedBlock{nodes, body, offset}:
          Fail{M.Diagnostic{"internal_cst", "parser", "invalid do resolver field"}}
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
            return M.SequenceExpr{located(C.offset_of(node), M.LetExpr{temporary, value, M.MatchExpr{[M.LocalExpr{temporary}], [M.MatchArm{[pattern_of(pat)], consequent}, M.MatchArm{[M.WildcardPattern{}], alternative}]}}), next}
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
        kind : GlobalKind <- record_kind(C.field_values(node, "fields"))
        next : Context <- add_global(context, name, prefix ++ name, kind, node)
        collect_constructors(rest, prefix, next)

def valid_effect_name(reserved: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match reserved:
    case True{}:
      Fail{C.diagnostic(node, "sealed_effect", "Foreign is reserved for the compiler's host-call effect label")}
    case False{}:
      Done{Unit{}}

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
    case EffectNode{}:
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        valid : Unit <- valid_effect_name(M.name_equal(name, "Foreign"), node)
        add_global(context, name, prefix ++ name, OperationName{M.TypeId{module_name, name}}, node)
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

def lower_record_types(nodes: List<&2, C.Cst>, reversed: List<&2, M.Ty>, +fuel: Nat, +headers: Map<&2, T.Header>, +variables: List<&2, T.Variable>, +globals: Map<&2, Global>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match nodes:
    case Nil{}:
      Done{List.reverse(&2, M.Ty, reversed)}
    case node <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        ty_node : C.Cst <- C.one(C.field_values(node, "annotation"))
        types : List<&2, M.Ty> <- T.lower(~Map<&2, Global>, ~lookup_effect, fuel, T.visit(ty_node), headers, variables, globals)
        ty : M.Ty <- T.one(types)
        lower_record_types(rest, ty <> reversed, fuel, headers, variables, globals)

def record_payload_type(types: List<&2, M.Ty>) -> Maybe<&2, M.Ty>:
  match types:
    case Nil{}:
      None{}
    case ty <> Nil{}:
      Some{ty}
    case first <> second <> rest:
      Some{M.ProductTy{first <> second <> rest}}

def constructor_payload(nodes: List<&2, C.Cst>, payload: List<&2, C.Cst>, fuel: Nat, headers: Map<&2, T.Header>, variables: List<&2, T.Variable>, globals: Map<&2, Global>) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  match nodes:
    case Nil{}:
      T.annotation(~Map<&2, Global>, ~lookup_effect, payload, fuel, headers, variables, globals)
    case node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
        types : List<&2, M.Ty> <- lower_record_types(C.field_values(node, "fields"), Nil{}, fuel, headers, variables, globals)
        return record_payload_type(types)
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid record declaration fields"}}

def lower_constructors(nodes: List<&2, C.Cst>, +prefix: String, +fuel: Nat, +headers: Map<&2, T.Header>, +variables: List<&2, T.Variable>, +globals: Map<&2, Global>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Constructor>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Constructor>>:
        name : String <- declaration_name(node)
        payload : Maybe<&2, M.Ty> <- constructor_payload(C.field_values(node, "fields"), C.field_values(node, "payload"), fuel, headers, variables, globals)
        rest : List<&2, M.Constructor> <- lower_constructors(tail, prefix, fuel, headers, variables, globals)
        return M.Constructor{prefix ++ name, payload} <> rest

def lower_data(+node: C.Cst, name: String, prefix: String, module_name: String, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.DataType>:
  Context{globals, headers, fixities, locals, label} = context
  do Result<&2, &2, M.Diagnostic, M.DataType>:
    variables : List<&2, T.Variable> <- type_variables(C.field_values(node, "parameters"), 0n)
    constructors : List<&2, M.Constructor> <- lower_constructors(C.field_values(node, "constructors"), prefix, fuel, headers, variables, globals)
    return M.DataType{M.TypeId{module_name, name}, List.length(&2, C.Cst, C.field_values(node, "parameters")), constructors}

def operation_signature(signature: Maybe<&2, M.Ty>, identity: M.TypeId, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match signature:
    case Some{M.FunctionTy{parameter, result, M.EffectRow{Nil{}, M.ClosedRow{}}}}:
      Done{M.Operation{identity, parameter, result}}
    case Some{M.FunctionTy{parameter, result, row}}:
      Fail{C.diagnostic(node, "operation_signature", "an operation declaration specifies parameter and result types, not an outer latent effect row")}
    case _:
      Fail{C.diagnostic(node, "operation_signature", "an effect operation requires a unary signature: Parameter -> Result")}

def lower_operation(+node: C.Cst, identity: M.TypeId, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  do Result<&2, &2, M.Diagnostic, M.Operation>:
    signature : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "signature"), fuel, context)
    operation_signature(signature, identity, node)

def add_operation(module: M.Module, operation: M.Operation) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constants, functions, data_types, operation <> operations}

def add_function(module: M.Module, fn: M.Function) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constants, fn <> functions, data_types, operations}

def add_constant(module: M.Module, constant: M.Constant) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constant <> constants, functions, data_types, operations}

def add_data(module: M.Module, ty: M.DataType) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constants, functions, ty <> data_types, operations}

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
    case EffectNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        name : String <- declaration_name(node)
        operation : M.Operation <- lower_operation(node, M.TypeId{module_name, name}, fuel, context)
        return add_operation(rest, operation)
    case DataNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        name : String <- declaration_name(node)
        ty : M.DataType <- lower_data(node, name, prefix, module_name, fuel, context)
        return add_data(rest, ty)
    case _:
      Done{rest}

def reject_attributes(attributes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match attributes:
    case Nil{}:
      Done{Unit{}}
    case node <> tail:
      Fail{C.diagnostic(node, "unsupported_attribute", "source declaration transforms are not implemented yet")}

def lower_declarations_sequential(nodes: List<&2, C.Cst>, +prefix: String, +module_name: String, +allow_exports: Bool, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match nodes:
    case Nil{}:
      Done{M.Module{Nil{}, Nil{}, Nil{}, Nil{}}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +node : C.Cst <- C.one(C.field_values(head, "value"))
        rest : M.Module <- lower_declarations_sequential(tail, prefix, module_name, allow_exports, fuel, context)
        valid : Unit <- reject_attributes(C.field_values(head, "attributes"))
        declaration(classify(C.kind_of(node)), node, prefix, module_name, Bool.and(allow_exports, C.present(C.field_values(head, "exported"))), rest, fuel, context)

def combine_modules(prelude: M.Module, module: M.Module) -> M.Module:
  M.Module{pc, pf, pt, po} = prelude
  M.Module{mc, mf, mt, mo} = module
  M.Module{List.append(&2, M.Constant, pc, mc), List.append(&2, M.Function, pf, mf), List.append(&2, M.DataType, pt, mt), List.append(&2, M.Operation, po, mo)}

type DeclarationBatch is Data:
  DeclarationLeaf{nodes: List<&2, C.Cst>}
  DeclarationFork{left: DeclarationBatch, right: DeclarationBatch}

type WeightedDeclaration is Data:
  WeightedDeclaration{node: C.Cst, cost: Nat}

type CostNode is Data:
  CostNode{node: C.Cst, pending: List<&2, List<&2, C.Cst>>}

def next_cost_node(pending: List<&2, List<&2, C.Cst>>) -> Maybe<&2, CostNode>:
  match pending:
    case Nil{}:
      None{}
    case Nil{} <> tail:
      next_cost_node(tail)
    case (head <> siblings) <> tail:
      Some{CostNode{head, siblings <> tail}}

def declaration_cost_walk(fuel: Nat, pending: Maybe<&2, CostNode>, cost: Nat) -> Nat:
  match fuel pending:
    case 0n _:
      cost
    case _ None{}:
      cost
    case 1n+rest Some{CostNode{C.Cst{kind, field, text, offset, children}, tail}}:
      declaration_cost_walk(rest, next_cost_node(children <> tail), 1n+cost)

def declaration_cost(fuel: Nat, pending: List<&2, C.Cst>, cost: Nat) -> Nat:
  match fuel:
    case 0n:
      cost
    case 1n+rest:
      declaration_cost_walk(1n+rest, next_cost_node([pending]), cost)

def weigh_declarations(nodes: List<&2, C.Cst>, reversed: List<&2, WeightedDeclaration>) -> List<&2, WeightedDeclaration>:
  match nodes:
    case Nil{}:
      List.reverse(&2, WeightedDeclaration, reversed)
    case +node <> tail:
      weigh_declarations(tail, WeightedDeclaration{node, declaration_cost(U32.to_nat(65536), [node], 0n)} <> reversed)

def declaration_nodes(nodes: List<&2, WeightedDeclaration>, reversed: List<&2, C.Cst>) -> List<&2, C.Cst>:
  match nodes:
    case Nil{}:
      List.reverse(&2, C.Cst, reversed)
    case WeightedDeclaration{node, cost} <> tail:
      declaration_nodes(tail, node <> reversed)

def declaration_weight(nodes: List<&2, WeightedDeclaration>, weight: Nat) -> Nat:
  match nodes:
    case Nil{}:
      weight
    case WeightedDeclaration{node, cost} <> tail:
      declaration_weight(tail, Nat.add(weight, cost))

def nearer_declaration_boundary(previous: Bool, count: Nat) -> Nat:
  match previous:
    case True{}:
      count
    case False{}:
      1n+count

# Choose the nearer cumulative-cost boundary, keeping at least one declaration
# on either side. The final entry cannot move into the left partition.
def declaration_boundary(nodes: List<&2, WeightedDeclaration>, +target: Nat, +weight: Nat, +count: Nat, ready: Bool) -> Nat:
  match nodes ready:
    case _ True{}:
      count
    case Nil{} False{}:
      count
    case head <> Nil{} False{}:
      count
    case WeightedDeclaration{node, cost} <> tail False{}:
      +next = Nat.add(weight, cost)
      declaration_boundary(tail, target, next, nearer_declaration_boundary(Bool.and(Nat.is_gt(count, 0n), Nat.is_le(Nat.sub(target, weight), Nat.sub(next, target))), count), Nat.is_ge(next, target))

def weighted_declaration_batches(+depth: Nat, +nodes: List<&2, WeightedDeclaration>, +count: Nat, +weight: Nat, small: Bool) -> DeclarationBatch:
  match depth small:
    case 1n+rest False{}:
      +half = declaration_boundary(nodes, Nat.div(weight, 2n), 0n, 0n, False{})
      +remaining = Nat.sub(count, half)
      +left = List.take(&2, WeightedDeclaration, nodes, half)
      right = List.drop(&2, WeightedDeclaration, nodes, half)
      +left_weight = declaration_weight(left, 0n)
      +right_weight = Nat.sub(weight, left_weight)
      # Large declarations must not stop in a four-node leaf: that hides the
      # wide fork when expensive declarations cluster near one end of a range.
      DeclarationFork{weighted_declaration_batches(rest, left, half, left_weight, Bool.or(Nat.is_le(half, 1n), Bool.and(Nat.is_le(half, 4n), Nat.is_le(left_weight, U32.to_nat(512))))), weighted_declaration_batches(rest, right, remaining, right_weight, Bool.or(Nat.is_le(remaining, 1n), Bool.and(Nat.is_le(remaining, 4n), Nat.is_le(right_weight, U32.to_nat(512)))))}
    case _ _:
      DeclarationLeaf{declaration_nodes(nodes, Nil{})}

def declaration_batches(depth: Nat, nodes: List<&2, C.Cst>, count: Nat, small: Bool) -> DeclarationBatch:
  match small:
    case True{}:
      DeclarationLeaf{nodes}
    case False{}:
      +weighted = weigh_declarations(nodes, Nil{})
      weighted_declaration_batches(depth, weighted, count, declaration_weight(weighted, 0n), False{})

# The serial traversal lowers the tail first. Keep that diagnostic priority
# while joining successful modules in source order.
def merge_declarations(left: Result<&2, &2, M.Diagnostic, M.Module>, right: Result<&2, &2, M.Diagnostic, M.Module>) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match right:
    case Fail{error}:
      Fail{error}
    case Done{b}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        a : M.Module <- left
        return combine_modules(a, b)

def lower_declaration_batch(batch: DeclarationBatch, +prefix: String, +module_name: String, +allow_exports: Bool, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match batch:
    case DeclarationLeaf{nodes}:
      lower_declarations_sequential(nodes, prefix, module_name, allow_exports, fuel, context)
    # Bend 2.0.21 drains 16 contiguous lanes per worker. Expose eight balanced
    # branches so a small binary tree does not occupy only two worker chunks.
    case DeclarationFork{DeclarationFork{DeclarationFork{a, b}, DeclarationFork{c, d}}, DeclarationFork{DeclarationFork{e, f}, DeclarationFork{g, h}}}:
      ra rb rc rd re rf rg rh = lower_declaration_batch(a, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(b, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(c, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(d, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(e, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(f, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(g, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(h, prefix, module_name, allow_exports, fuel, context)
      merge_declarations(merge_declarations(merge_declarations(ra, rb), merge_declarations(rc, rd)), merge_declarations(merge_declarations(re, rf), merge_declarations(rg, rh)))
    case DeclarationFork{DeclarationFork{a, b}, DeclarationFork{c, d}}:
      ra rb rc rd = lower_declaration_batch(a, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(b, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(c, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(d, prefix, module_name, allow_exports, fuel, context)
      merge_declarations(merge_declarations(ra, rb), merge_declarations(rc, rd))
    case DeclarationFork{left, right}:
      a b = lower_declaration_batch(left, prefix, module_name, allow_exports, fuel, context) lower_declaration_batch(right, prefix, module_name, allow_exports, fuel, context)
      merge_declarations(a, b)

def validate_declaration_nodes(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match nodes:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        node : C.Cst <- C.one(C.field_values(head, "value"))
        validate_declaration_nodes(tail)

def lower_declarations(+nodes: List<&2, C.Cst>, prefix: String, module_name: String, allow_exports: Bool, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  +count = List.length(&2, C.Cst, nodes)
  do Result<&2, &2, M.Diagnostic, M.Module>:
    # Structural failures precede semantic failures in the serial traversal.
    valid : Unit <- validate_declaration_nodes(nodes)
    lower_declaration_batch(declaration_batches(48n, nodes, count, Nat.is_le(count, 4n)), prefix, module_name, allow_exports, fuel, context)

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

def require_resolved_imports(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match nodes:
    case Nil{}:
      Done{Unit{}}
    case node <> tail:
      Fail{C.diagnostic(node, "module_loader_required", "compile a source project to resolve file imports")}

def prepare_source(+root: C.Cst, prepared: Prelude) -> Result<&2, &2, M.Diagnostic, SourcePlan>:
  Prelude{prelude_module, public_scope} = prepared
  +nodes = C.field_values(root, "declarations")
  do Result<&2, &2, M.Diagnostic, SourcePlan>:
    imports : Unit <- require_resolved_imports(C.field_values(root, "imports"))
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
