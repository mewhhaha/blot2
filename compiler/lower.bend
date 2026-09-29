import Base
import ./model.bend as M
import ./types.bend as CoreTypes
import ./cst.bend as C
import ./postfix.bend as Postfix
import ./source_types.bend as T
import ./source_arguments.bend as A
import ./operators.bend as O
import ./index.bend as Index
import ./effect_families.bend as Families
import ./dependency.bend as D
import ./closures.bend as Closures
import ./resolvers.bend as Resolvers

type Local is Data:
  Local{source: String, core: String}

type GlobalKind is Data:
  ConstantName{}
  FunctionName{}
  ConstructorName{}
  RecordConstructorName{fields: List<&2, String>}
  OperationName{identity: M.TypeId}
  OperationTemplateName{identity: M.TypeId, parameters: List<&2, A.Pattern>}
  EffectFamilyName{members: List<&2, M.TypeId>, parameters: List<&2, A.Pattern>}

type Global is Data:
  Global{source: String, core: String, kind: GlobalKind}

type Context is Data:
  Context{globals: Map<&2, Global>, headers: Map<&2, T.Header>, fixities: List<&2, O.Fixity>, locals: List<&2, Local>, return_label: Maybe<&2, Nat>, annotation_variables: List<&2, T.Variable>}

type NodeKind is Data:
  Wrapper{}
  Integer{}
  Float{}
  PrefixNode{}
  Truth{}
  Falsehood{}
  Name{}
  MarkedConstructor{}
  Intrinsic{}
  ValueDeclaration{}
  DataNode{}
  EffectNode{}
  EffectTypeNode{}
  SymbolicFixity{}
  NamedFixity{}
  GroupNode{}
  ArrayNode{}
  RecordNode{}
  ApplicationNode{}
  MemberNode{}
  SelectorNode{}
  TypeWitnessNode{}
  IfValueNode{}
  IndexNode{}
  InfixNode{}
  LambdaNode{}
  CaseNode{}
  Block{}
  Binding{}
  Rebinding{}
  ForLoop{}
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
  PatternValue{}
  Unsupported{}

type Primitive is Data:
  AssociatedPrimitive{}
  ResultPrimitive{}
  ForcePrimitive{}
  DeferredPrimitive{member: String, arity: Nat}
  EffectFamilyPrimitive{member: String, templates: Nat, operands: Nat}
  ScalarPrimitive{operator: M.ScalarOp}
  UnaryPrimitive{operator: M.UnaryOp}
  ProviderPrimitive{}
  StateProviderPrimitive{}
  OperationDescriptorPrimitive{}
  FunctionEffectsPrimitive{}
  EffectHasPrimitive{}
  EffectCountPrimitive{}
  EffectSamePrimitive{}
  PanicPrimitive{}
  ProjectPrimitive{}
  ArrayGeneratePrimitive{}
  ArrayFillPrimitive{}
  ArrayGetPrimitive{}
  ArraySetPrimitive{}
  ArrayLengthPrimitive{}

type RecordTarget is Data:
  RecordTarget{constructor: String, fields: List<&2, String>}

type RecordElement is Data:
  RecordElement{field: String, binding: String, value: M.Expr}

type TypedArguments is Data:
  TypedArguments{types: List<&2, M.Ty>, values: List<&2, C.Cst>}

type TypedCall is Data:
  TypedCall{callee: M.Expr, values: List<&2, C.Cst>}

type TemplateReference is Data:
  TemplateReference{identity: M.TypeId, parameters: List<&2, A.Pattern>}

type OperationTarget is Data:
  OperationTarget{identity: M.TypeId, template: Maybe<&2, M.TypeId>, arguments: List<&2, M.Ty>}

type PatternRow is Data:
  PatternRow{patterns: List<&2, M.Pattern>, locals: List<&2, Local>}

type SurfaceArm is Data:
  SurfaceArm{rows: List<&2, PatternRow>, guarded: Bool, guard: M.Expr, body: M.Expr, offset: Nat}

type Work is Data:
  Expression{kind: NodeKind, node: C.Cst}
  ConstructorExpression{kind: NodeKind, node: C.Cst}
  Group{nodes: List<&2, C.Cst>, offset: Nat}
  ProductElements{nodes: List<&2, C.Cst>, reversed: List<&2, M.Expr>, offset: Nat}
  ArrayElements{nodes: List<&2, C.Cst>, reversed: List<&2, M.Expr>, offset: Nat}
  RecordElements{constructor: String, fields: List<&2, String>, nodes: List<&2, C.Cst>, reversed: List<&2, RecordElement>, seen: Set(), node: C.Cst}
  Arguments{callee: M.Expr, nodes: List<&2, C.Cst>, offset: Nat}
  UpdatePath{receiver: M.Expr, nodes: List<&2, C.Cst>, value: C.Cst, offset: Nat}
  UpdateSelector{kind: String, receiver: M.Expr, node: C.Cst, tail: List<&2, C.Cst>, value: C.Cst, offset: Nat}
  ApplicationHead{kind: NodeKind, head: C.Cst, arguments: List<&2, C.Cst>, offset: Nat}
  GroupedApplication{call: Maybe<&2, TypedCall>, kind: NodeKind, head: C.Cst, arguments: List<&2, C.Cst>, offset: Nat}
  RecordApplication{template: Maybe<&2, TemplateReference>, head: C.Cst, fields: C.Cst, arguments: List<&2, C.Cst>, offset: Nat, node: C.Cst}
  ApplicationTemplate{template: Maybe<&2, TemplateReference>, head: C.Cst, arguments: List<&2, C.Cst>, offset: Nat}
  PrimitiveCall{primitive: Primitive, head: C.Cst, arguments: List<&2, C.Cst>, offset: Nat}
  DescriptorOperation{sealed: Bool, operation: C.Cst, offset: Nat}
  DescriptorArgument{sealed: Bool, node: C.Cst}
  InfixTails{head: M.Expr, nodes: List<&2, C.Cst>, tails: List<&2, O.Tail>}
  CaseValues{nodes: List<&2, C.Cst>, reversed: List<&2, M.Expr>, arms: List<&2, C.Cst>}
  Arms{values: List<&2, M.Expr>, nodes: List<&2, C.Cst>, arms: List<&2, SurfaceArm>}
  ArmGuard{values: List<&2, M.Expr>, rest: List<&2, C.Cst>, arms: List<&2, SurfaceArm>, rows: List<&2, PatternRow>, guard: List<&2, C.Cst>, body: M.Expr, node: C.Cst}
  ResolvedBlock{resolvers: List<&2, C.Cst>, body: M.Expr, offset: Nat}
  ForStart{ever: Bool, node: C.Cst, pattern: M.Pattern, initial: M.Expr, body: M.Expr, prefix: String}
  ForRange{ends: List<&2, C.Cst>, pattern: M.Pattern, start: M.Expr, initial: M.Expr, body: M.Expr, prefix: String, offset: Nat}
  Statements{nodes: List<&2, C.Cst>, carried: List<&2, Local>}
  Statement{kind: NodeKind, node: C.Cst, tail: List<&2, C.Cst>, carried: List<&2, Local>}

type Parameter is Data:
  Parameter{source: String, core: String, annotation: Maybe<&2, M.Ty>}

type PatternResult is Data:
  PatternResult{pattern: M.Pattern, locals: List<&2, Local>}

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
      Bool.pick(NodeKind, M.name_equal(kind, "binding"), Binding{}, Bool.pick(NodeKind, M.name_equal(kind, "boolean_constructor_pattern"), PatternGroup{}, Unsupported{}))
    case 'c':
      Bool.pick(NodeKind, M.name_equal(kind, "call_expression"), ApplicationNode{}, Bool.pick(NodeKind, M.name_equal(kind, "case_expression"), CaseNode{}, Bool.pick(NodeKind, M.name_equal(kind, "conditional"), Conditional{}, Bool.pick(NodeKind, M.name_equal(kind, "constructor_pattern"), PatternConstructor{}, Bool.pick(NodeKind, M.name_equal(kind, "constructor_reference"), MarkedConstructor{}, Unsupported{})))))
    case 'd':
      Bool.pick(NodeKind, M.name_equal(kind, "data_type"), DataNode{}, Bool.pick(NodeKind, M.name_equal(kind, "do_block"), Block{}, Unsupported{}))
    case 'e':
      Bool.pick(NodeKind, M.name_equal(kind, "ever_statement"), ForLoop{}, Bool.pick(NodeKind, M.name_equal(kind, "expression"), Wrapper{}, Bool.pick(NodeKind, M.name_equal(kind, "effect_binding"), EffectBinding{}, Bool.pick(NodeKind, M.name_equal(kind, "effect_step"), EffectBinding{}, Bool.pick(NodeKind, M.name_equal(kind, "effect_declaration"), EffectNode{}, Bool.pick(NodeKind, M.name_equal(kind, "effect_type"), EffectTypeNode{}, Unsupported{}))))))
    case 'f':
      Bool.pick(NodeKind, M.name_equal(kind, "for_statement"), ForLoop{}, Unsupported{})
    case 'g':
      Bool.pick(NodeKind, M.name_equal(kind, "group"), GroupNode{}, Unsupported{})
    case 'i':
      Bool.pick(NodeKind, M.name_equal(kind, "if_expression"), IfValueNode{}, Bool.pick(NodeKind, M.name_equal(kind, "infix_expression"), InfixNode{}, Bool.pick(NodeKind, M.name_equal(kind, "index_expression"), IndexNode{}, Unsupported{})))
    case 'l':
      Bool.pick(NodeKind, M.name_equal(kind, "lambda"), LambdaNode{}, Unsupported{})
    case 'm':
      Bool.pick(NodeKind, M.name_equal(kind, "member_expression"), MemberNode{}, Unsupported{})
    case 'n':
      Bool.pick(NodeKind, M.name_equal(kind, "named_fixity"), NamedFixity{}, Unsupported{})
    case 'p':
      Bool.pick(NodeKind, M.name_equal(kind, "prefix_expression"), PrefixNode{}, Bool.pick(NodeKind, M.name_equal(kind, "pattern_conditional"), PatternConditional{}, Bool.pick(NodeKind, M.name_equal(kind, "pattern"), PatternWrapper{}, Bool.pick(NodeKind, M.name_equal(kind, "pattern_group"), PatternGroup{}, Unsupported{}))))
    case 'v':
      Bool.pick(NodeKind, M.name_equal(kind, "value_pattern"), PatternValue{}, Bool.pick(NodeKind, M.name_equal(kind, "value_declaration"), ValueDeclaration{}, Unsupported{}))
    case 'q':
      Bool.pick(NodeKind, M.name_equal(kind, "qualified_name"), Name{}, Unsupported{})
    case 'r':
      Bool.pick(NodeKind, M.name_equal(kind, "range_statement"), ForLoop{}, Bool.pick(NodeKind, M.name_equal(kind, "record"), RecordNode{}, Bool.pick(NodeKind, M.name_equal(kind, "result"), Return{}, Bool.pick(NodeKind, M.name_equal(kind, "rebinding"), Rebinding{}, Unsupported{}))))
    case 's':
      Bool.pick(NodeKind, M.name_equal(kind, "selector"), SelectorNode{}, Bool.pick(NodeKind, M.name_equal(kind, "symbolic_fixity"), SymbolicFixity{}, Unsupported{}))
    case 't':
      Bool.pick(NodeKind, M.name_equal(kind, "type_witness"), TypeWitnessNode{}, Unsupported{})
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

# Each source token has sixteen distinct semantic lanes. A reference, its
# enclosing call, and a bound member can share an offset without sharing a use.
def instantiate_at(offset: Nat, lane: Nat, value: M.Expr) -> M.Expr:
  M.InstantiationExpr{Nat.add(Nat.mul(offset, 16n), lane), value}

def global_value(found: Maybe<&2, Global>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{Global{source, core, ConstantName{}}}:
      Done{instantiate_at(C.offset_of(node), 0n, M.ConstantExpr{core})}
    case Some{Global{source, core, FunctionName{}}}:
      Done{instantiate_at(C.offset_of(node), 0n, M.FunctionExpr{core})}
    case Some{Global{source, core, ConstructorName{}}}:
      Done{instantiate_at(C.offset_of(node), 0n, M.ConstructorRefExpr{core})}
    case Some{Global{source, core, RecordConstructorName{fields}}}:
      Done{instantiate_at(C.offset_of(node), 0n, M.ConstructorRefExpr{core})}
    case Some{Global{source, core, OperationName{identity}}}:
      Done{M.OperationExpr{identity}}
    case Some{Global{source, core, OperationTemplateName{identity, parameters}}}:
      Done{M.GenericOperationExpr{C.offset_of(node), identity, Nil{}}}
    case Some{Global{source, core, EffectFamilyName{members, parameters}}}:
      Fail{C.diagnostic(node, "effect_member", "effect family requires an operation member")}
    case None{}:
      Fail{C.diagnostic(node, "unknown_value", "unknown value: " ++ C.name_of(node))}

def located(offset: Nat, value: M.Expr) -> M.Expr:
  M.SourceExpr{offset, None{}, value}

def member_path(nodes: List<&2, C.Cst>, receiver: M.Expr) -> M.Expr:
  match nodes:
    case Nil{}:
      receiver
    case C.Cst{kind, field, ".", offset, children} <> tail:
      member_path(tail, receiver)
    case C.Cst{kind, field, member, +offset, children} <> tail:
      member_path(tail, located(offset, instantiate_at(offset, 2n, M.AssociatedExpr{offset, M.MemberDispatch{}, member, Nil{}, receiver, M.UnitExpr{}})))

type GlobalPrefix is Data:
  GlobalPrefix{global: Global, remaining: List<&2, C.Cst>}

def prefix_candidate(found: Maybe<&2, Global>, tail: List<&2, C.Cst>, previous: Maybe<&2, GlobalPrefix>) -> Maybe<&2, GlobalPrefix>:
  match found:
    case Some{global}:
      Some{GlobalPrefix{global, tail}}
    case None{}:
      previous

def global_prefix(nodes: List<&2, C.Cst>, +globals: Map<&2, Global>, prefix: String, best: Maybe<&2, GlobalPrefix>) -> Maybe<&2, GlobalPrefix>:
  match nodes:
    case Nil{}:
      best
    case C.Cst{kind, field, ".", offset, children} <> tail:
      global_prefix(tail, globals, prefix ++ ".", best)
    case C.Cst{kind, field, text, offset, children} <> +tail:
      +name = prefix ++ text
      global_prefix(tail, globals, name, prefix_candidate(lookup_global(globals, name), tail, best))

def global_member(found: Maybe<&2, GlobalPrefix>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{GlobalPrefix{global, remaining}}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        receiver : M.Expr <- global_value(Some{global}, node)
        return member_path(remaining, receiver)
    case None{}:
      global_value(None{}, node)

def resolve_root(found: Maybe<&2, String>, root: C.Cst, nodes: List<&2, C.Cst>, globals: Map<&2, Global>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{core}:
      Done{member_path(nodes, instantiate_at(C.offset_of(root), 0n, M.LocalExpr{core}))}
    case None{}:
      global_member(global_prefix(C.children_of(node), globals, "", None{}), node)

def resolve_parts(nodes: List<&2, C.Cst>, context: Context, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match nodes context:
    case +root <> tail Context{globals, headers, fixities, locals, label, variables}:
      resolve_root(lookup_local(locals, C.text_of(root)), root, tail, globals, node)
    case _ _:
      Fail{C.diagnostic(node, "internal_cst", "qualified name has no root")}

def resolve(context: Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  resolve_parts(C.children_of(node), context, node)

def require_value_marker(value: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match value:
    case M.InstantiationExpr{site, inner}:
      require_value_marker(inner, node)
    case M.SourceExpr{offset, annotation, inner}:
      require_value_marker(inner, node)
    case M.ConstructorRefExpr{constructor}:
      Fail{C.diagnostic(node, "constructor_marker", "data constructors require # before the name")}
    case M.AssociatedExpr{site, dispatch, member, candidates, receiver, argument}:
      require_value_marker(receiver, node)
    case _:
      Done{Unit{}}

def resolve_ordinary_value(+context: Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  do Result<&2, &2, M.Diagnostic, M.Expr>:
    +value : M.Expr <- resolve(context, node)
    checked : Unit <- require_value_marker(value, node)
    return value

# Types may be passed as ordinary values without confusing their unmarked name
# with the explicitly marked constructor. Locals and ordinary globals win.
def type_value_shadow(found: Maybe<&2, Global>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{Global{source, core, ConstructorName{}}}:
      False{}
    case Some{Global{source, core, RecordConstructorName{fields}}}:
      False{}
    case _:
      True{}

def resolve_type_value(found: Maybe<&2, T.Header>, shadowed: Bool, context: Context, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found shadowed:
    case Some{T.Header{source, identity, parameters}} False{}:
      Done{Resolvers.token_value(identity)}
    case _ _:
      resolve_ordinary_value(context, node)

def type_value_local(locals: List<&2, Local>, nodes: List<&2, C.Cst>) -> Bool:
  match nodes:
    case root <> tail:
      Maybe.is_some(&2, String, lookup_local(locals, C.text_of(root)))
    case Nil{}:
      False{}

def resolve_value(+context: Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  Context{globals, headers, fixities, locals, label, variables} = context
  +name = C.name_of(node)
  resolve_type_value(T.lookup_header(headers, name), Bool.or(type_value_local(locals, C.children_of(node)), type_value_shadow(lookup_global(globals, name))), context, node)

def template_reference(local: Maybe<&2, String>, found: Maybe<&2, Global>) -> Maybe<&2, TemplateReference>:
  match local found:
    case None{} Some{Global{source, core, OperationTemplateName{identity, parameters}}}:
      Some{TemplateReference{identity, parameters}}
    case _ _:
      None{}

def effect_template_found(found: Maybe<&2, Global>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match found:
    case Some{Global{source, core, OperationTemplateName{identity, A.Binding{parameter} <> Nil{}}}}:
      Done{identity}
    case Some{Global{source, core, OperationTemplateName{identity, parameters}}}:
      Fail{C.diagnostic(node, "type_arity", "generic effect operation requires exactly one type parameter")}
    case _:
      Fail{C.diagnostic(node, "operation_target", "expected a declared parameterized effect operation")}

def effect_template_child(children: List<&2, C.Cst>, +node: C.Cst, context: Context) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  match children:
    case +name <> Nil{}:
      Context{globals, headers, fixities, locals, label, annotation_variables} = context
      Bool.pick(Result<&2, &2, M.Diagnostic, M.TypeId>, M.name_equal(C.kind_of(name), "qualified_name"), effect_template_found(lookup_global(globals, C.name_of(name)), node), Fail{C.diagnostic(node, "operation_target", "expected a declared parameterized effect operation name")})
    case _:
      Fail{C.diagnostic(node, "operation_target", "expected a declared parameterized effect operation name")}

def effect_template_name(+node: C.Cst, context: Context) -> Result<&2, &2, M.Diagnostic, M.TypeId>:
  effect_template_child(C.children_of(node), node, context)

def family_contains(members: List<&2, M.TypeId>, +wanted: M.TypeId) -> Bool:
  match members:
    case Nil{}:
      False{}
    case member <> rest:
      Bool.or(M.type_id_equal(member, wanted), family_contains(rest, wanted))

def family_pair(globals: List<&2, Global>, +reader: M.TypeId, +writer: M.TypeId) -> Bool:
  match globals:
    case Nil{}:
      False{}
    case Global{source, core, EffectFamilyName{+members, parameters}} <> rest:
      Bool.or(Bool.and(family_contains(members, reader), family_contains(members, writer)), family_pair(rest, reader, writer))
    case other <> rest:
      family_pair(rest, reader, writer)

def require_family_pair(context: Context, +reader: M.TypeId, +writer: M.TypeId, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, family_pair(Map.values(&2, Global, globals), reader, writer), Done{Unit{}}, Fail{C.diagnostic(node, "effect_family", "read and write operations must belong to the same declared effect family")})

def effect_member_instances(templates: List<&2, M.TypeId>, +arguments: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match templates:
    case Nil{}:
      Done{Nil{}}
    case template <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        identity : M.TypeId <- Families.identity(template, arguments)
        following : List<&2, M.TypeId> <- effect_member_instances(rest, arguments)
        return identity <> following

def lookup_effect_resolved(sealed: Bool, found: Maybe<&2, Global>, +name: String, values: List<&2, A.Value>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match sealed found:
    case True{} _:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        arguments : List<&2, M.Ty> <- A.bind(Nil{}, values, node)
        return [M.foreign_identity()]
    case False{} Some{Global{source, core, OperationName{identity}}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        arguments : List<&2, M.Ty> <- A.bind(Nil{}, values, node)
        return [identity]
    case False{} Some{Global{source, core, OperationTemplateName{identity, parameters}}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        arguments : List<&2, M.Ty> <- A.bind(parameters, values, node)
        concrete : M.TypeId <- Families.identity(identity, arguments)
        return [concrete]
    case False{} Some{Global{source, core, EffectFamilyName{members, parameters}}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        arguments : List<&2, M.Ty> <- A.bind(parameters, values, node)
        effect_member_instances(members, arguments)
    case _ _:
      Fail{M.Diagnostic{"unknown_effect", name, "effect rows require Foreign or a declared effect operation or family"}}

def lookup_effect(globals: Map<&2, Global>, name: String, arguments: List<&2, A.Value>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  +lookup_name = name
  lookup_effect_resolved(M.name_equal(lookup_name, "Foreign"), lookup_global(globals, lookup_name), lookup_name, arguments, node)

def type_value(fuel: Nat, node: C.Cst, context: Context) -> Result<&2, &2, M.Diagnostic, A.Value>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  do Result<&2, &2, M.Diagnostic, A.Value>:
    values : List<&2, A.Value> <- T.evaluate(~Map<&2, Global>, ~lookup_effect, fuel, T.visit(node), headers, annotation_variables, globals)
    T.one_value(values)

def type_term(fuel: Nat, +node: C.Cst, context: Context) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  do Result<&2, &2, M.Diagnostic, M.Ty>:
    value : A.Value <- type_value(fuel, node, context)
    A.as_type(value, node)

def typed_arguments(parameters: List<&2, A.Pattern>, nodes: List<&2, C.Cst>, +fuel: Nat, +context: Context, +reversed: List<&2, M.Ty>, +head: C.Cst) -> Result<&2, &2, M.Diagnostic, TypedArguments>:
  match parameters nodes:
    case Nil{} rest:
      Done{TypedArguments{List.reverse(&2, M.Ty, reversed), rest}}
    case pattern <> remaining Nil{}:
      Fail{C.diagnostic(head, "type_arity", "effect operation requires another type argument")}
    case pattern <> remaining +node <> rest:
      do Result<&2, &2, M.Diagnostic, TypedArguments>:
        value : A.Value <- type_value(fuel, node, context)
        types : List<&2, M.Ty> <- A.match_argument(fuel, A.Argument{pattern, value}, node)
        typed_arguments(remaining, rest, fuel, context, List.reverse.go(&2, M.Ty, types, reversed), head)

def typed_operation(template: TemplateReference, nodes: List<&2, C.Cst>, fuel: Nat, context: Context, head: C.Cst) -> Result<&2, &2, M.Diagnostic, TypedArguments>:
  TemplateReference{identity, parameters} = template
  typed_arguments(parameters, nodes, fuel, context, Nil{}, head)

def builtin_type_name(+name: String) -> Bool:
  Bool.or(M.name_equal(name, "Unit"), Bool.or(M.name_equal(name, "U32"), Bool.or(M.name_equal(name, "F32"), Bool.or(M.name_equal(name, "Bool"), M.name_equal(name, "Array")))))

def extra_type_argument_child(children: List<&2, C.Cst>, context: Context) -> Bool:
  match children:
    case +name <> Nil{}:
      Context{globals, headers, fixities, locals, label, annotation_variables} = context
      +source = C.type_name(name)
      Bool.and(M.name_equal(C.kind_of(name), "qualified_name"), Bool.and(Bool.or(builtin_type_name(source), Maybe.is_some(&2, T.Header, T.lookup_header(headers, source))), Bool.not(Maybe.is_some(&2, Global, lookup_global(globals, source)))))
    case _:
      False{}

def extra_type_argument(nodes: List<&2, C.Cst>, context: Context) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case +node <> tail:
      extra_type_argument_child(C.children_of(node), context)

def local_operation_argument(fuel: Nat, work: T.Work, +context: Context) -> Bool:
  match fuel work:
    case 1n+rest T.Node{T.Name{}, node}:
      Context{globals, headers, fixities, locals, label, annotation_variables} = context
      Maybe.is_some(&2, String, lookup_local(locals, C.type_name(node)))
    case 1n+rest T.Node{T.Wrapper{}, node}:
      local_operation_argument(rest, T.Nodes{C.children_of(node)}, context)
    case 1n+rest T.Node{T.Group{}, node}:
      local_operation_argument(rest, T.Nodes{C.field_values(node, "value")}, context)
    case 1n+rest T.Node{T.Application{}, +node}:
      local_operation_argument(rest, T.Nodes{List.append(&2, C.Cst, C.field_values(node, "head"), C.field_values(node, "arguments"))}, context)
    case 1n+rest T.Node{T.ArrayNode{}, node}:
      local_operation_argument(rest, T.Nodes{C.field_values(node, "elements")}, context)
    case 1n+rest T.Node{T.RecordNode{}, node}:
      local_operation_argument(rest, T.Nodes{C.field_values(node, "fields")}, context)
    case 1n+rest T.Node{T.FieldNode{}, +node}:
      local_operation_argument(rest, T.Field{node, C.field_values(node, "value")}, context)
    case 1n+rest T.Field{node, Nil{}}:
      local_operation_argument(rest, T.Nodes{C.field_values(node, "name")}, context)
    case 1n+rest T.Field{node, values}:
      local_operation_argument(rest, T.Nodes{values}, context)
    case 1n+rest T.Node{T.InfixNode{}, +node}:
      Bool.and(List.is_empty(&2, C.Cst, C.field_values(node, "tails")), local_operation_argument(rest, T.Nodes{C.field_values(node, "head")}, context))
    case 1n+rest T.Node{T.PrefixNode{}, +node}:
      Bool.and(List.is_empty(&2, C.Cst, C.field_values(node, "operator")), local_operation_argument(rest, T.Nodes{C.field_values(node, "value")}, context))
    case 1n+ +rest T.Nodes{+node <> tail}:
      Bool.or(local_operation_argument(rest, T.visit(node), context), local_operation_argument(rest, T.Nodes{tail}, context))
    case _ _:
      False{}

def operation_argument_matches(matched: Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>) -> Bool:
  match matched:
    case Done{types}:
      True{}
    case Fail{diagnostic}:
      False{}

def operation_value_is_explicit(value: Result<&2, &2, M.Diagnostic, A.Value>, has_runtime_argument: Bool, parameters: List<&2, A.Pattern>, fuel: Nat, node: C.Cst) -> Bool:
  match value parameters:
    case Done{A.TupleValue{Nil{}}} _:
      has_runtime_argument
    case Done{value} pattern <> tail:
      operation_argument_matches(A.match_argument(fuel, A.Argument{pattern, value}, node))
    case _ _:
      False{}

def empty_operation_pattern(parameters: List<&2, A.Pattern>) -> Bool:
  match parameters:
    case A.TuplePattern{Nil{}} <> tail:
      True{}
    case _:
      False{}

def operation_arguments_explicit(arguments: List<&2, C.Cst>, +parameters: List<&2, A.Pattern>, +fuel: Nat, +context: Context) -> Bool:
  match arguments:
    case Nil{}:
      False{}
    case +head <> +tail:
      +has_runtime_argument = Nat.is_ge(List.length(&2, C.Cst, tail), List.length(&2, A.Pattern, parameters))
      Bool.and(Bool.or(has_runtime_argument, Bool.not(local_operation_argument(fuel, T.visit(head), context))), operation_value_is_explicit(type_value(fuel, head, context), Bool.or(empty_operation_pattern(parameters), has_runtime_argument), parameters, fuel, head))

def specialized_operation_named(concrete: Bool, +identity: M.TypeId, +arguments: List<&2, M.Ty>, head: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match concrete:
    case False{}:
      Done{M.GenericOperationExpr{C.offset_of(head), identity, arguments}}
    case True{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        concrete : M.TypeId <- Families.identity(identity, arguments)
        return M.SpecializeOperationExpr{identity, arguments, M.OperationExpr{concrete}}

def specialized_operation_value(identity: M.TypeId, +arguments: List<&2, M.Ty>, head: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  do Result<&2, &2, M.Diagnostic, M.Expr>:
    names : List<&2, M.Ty> <- CoreTypes.annotation_names(65536n, CoreTypes.ManyTypes{arguments})
    specialized_operation_named(List.is_empty(&2, M.Ty, names), identity, arguments, head)

def typed_operation_parsed(parsed: TypedArguments, +identity: M.TypeId, context: Context, +head: C.Cst) -> Result<&2, &2, M.Diagnostic, TypedCall>:
  match parsed:
    case TypedArguments{+types, +values}:
      do Result<&2, &2, M.Diagnostic, TypedCall>:
        extra : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, extra_type_argument(values, context), Fail{C.diagnostic(head, "type_arity", "too many effect type arguments")}, Done{Unit{}})
        callee : M.Expr <- specialized_operation_value(identity, types, head)
        return TypedCall{callee, values}

def operation_application(explicit: Bool, +template: TemplateReference, arguments: List<&2, C.Cst>, fuel: Nat, +context: Context, +head: C.Cst) -> Result<&2, &2, M.Diagnostic, TypedCall>:
  match explicit:
    case False{}:
      TemplateReference{identity, parameters} = template
      Done{TypedCall{M.GenericOperationExpr{C.offset_of(head), identity, Nil{}}, arguments}}
    case True{}:
      TemplateReference{identity, parameters} = template
      do Result<&2, &2, M.Diagnostic, TypedCall>:
        parsed : TypedArguments <- typed_operation(template, arguments, fuel, context, head)
        typed_operation_parsed(parsed, identity, context, head)

def typed_operation_value(+template: TemplateReference, +arguments: List<&2, C.Cst>, +fuel: Nat, +context: Context, head: C.Cst) -> Result<&2, &2, M.Diagnostic, TypedCall>:
  TemplateReference{identity, parameters} = template
  operation_application(operation_arguments_explicit(arguments, parameters, fuel, context), template, arguments, fuel, context, head)

def typed_call_work(typed: TypedCall, offset: Nat) -> Work:
  TypedCall{callee, values} = typed
  Arguments{callee, values, offset}

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
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
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
  Context{+globals, +headers, +fixities, locals, +label, +annotation_variables} = context
  Local{+source, core} = target
  Bool.pick(Context, M.name_equal(source, "_"), context, Context{globals, headers, fixities, Local{source, core} <> locals, label, annotation_variables})

def bind_all(locals: List<&2, Local>, context: Context) -> Context:
  match locals:
    case Nil{}:
      context
    case local <> rest:
      bind_all(rest, bind(context, local))

def rebinding_scope(found: Maybe<&2, String>, context: Context, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Context>:
  match found:
    case Some{core}:
      Done{bind(context, Local{"self", core})}
    case None{}:
      Fail{C.diagnostic(node, "unknown_rebinding", ":= requires an existing local binding: " ++ C.text_of(node))}

def self_local(found: Maybe<&2, String>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found:
    case Some{core}:
      Done{M.LocalExpr{core}}
    case None{}:
      Fail{M.Diagnostic{"internal_error", "rebinding", "rebinding scope lost self"}}

def self_value(context: Context) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  Context{globals, headers, fixities, locals, label, variables} = context
  self_local(lookup_local(locals, "self"))

def with_label(context: Context, label: Maybe<&2, Nat>) -> Context:
  Context{globals, headers, fixities, locals, old_label, annotation_variables} = context
  Context{globals, headers, fixities, locals, label, annotation_variables}

def block_scope(context: Context, +label: Nat, resolved: Bool) -> Context:
  match resolved:
    case False{}:
      with_label(context, Some{label})
    case True{}:
      bind(with_label(context, Some{label}), Local{"$resolver", Resolvers.scope(label)})

def resolver_scope(found: Maybe<&2, String>, label: Maybe<&2, Nat>) -> Bool:
  match found label:
    case Some{name} Some{label}:
      M.name_equal(name, Resolvers.scope(label))
    case _ _:
      False{}

def has_resolver(context: Context) -> Bool:
  Context{globals, headers, fixities, locals, label, variables} = context
  resolver_scope(lookup_local(locals, "$resolver"), label)

def unique_name(+node: C.Cst) -> String:
  C.text_of(node) ++ "$" ++ Nat.show(C.offset_of(node))

# Type traversal looks up only actual row labels in the existing indexed scope.
def source_annotation(nodes: List<&2, C.Cst>, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  match nodes:
    case Nil{}:
      Done{None{}}
    case head <> tail:
      Context{globals, headers, fixities, locals, label, annotation_variables} = context
      T.annotation(~Map<&2, Global>, ~lookup_effect, head <> tail, fuel, headers, annotation_variables, globals)

def constraint_type(node: C.Cst, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  do Result<&2, &2, M.Diagnostic, M.Ty>:
    types : List<&2, M.Ty> <- T.lower(~Map<&2, Global>, ~lookup_effect, fuel, T.visit(node), headers, annotation_variables, globals)
    T.one(types)

def constraint_types(nodes: List<&2, C.Cst>, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        value : M.Ty <- constraint_type(node, fuel, context)
        rest : List<&2, M.Ty> <- constraint_types(tail, fuel, context)
        return value <> rest

def constraint_row(node: C.Cst, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.EffectRow>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  T.row(~Map<&2, Global>, ~lookup_effect, node, fuel, headers, annotation_variables, globals)

def constraint_invocation(nodes: List<&2, C.Cst>, fuel: Nat, context: Context, scope: String, origin: C.Cst) -> Result<&2, &2, M.Diagnostic, M.EffectRow>:
  match nodes:
    case Nil{}:
      Done{M.EffectRow{Nil{}, M.FreeRow{scope, "$predicate$" ++ Nat.show(C.offset_of(origin))}}}
    case row <> Nil{}:
      constraint_row(row, fuel, context)
    case _:
      Fail{C.diagnostic(origin, "invalid_constraint", "a predicate has more than one invocation row")}

def constraint_no_row(nodes: List<&2, C.Cst>, origin: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match nodes:
    case Nil{}:
      Done{Unit{}}
    case _:
      Fail{C.diagnostic(origin, "invalid_constraint", "this predicate does not accept an invocation row")}

def constraint_member(nodes: List<&2, C.Cst>, origin: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match nodes:
    case literal <> Nil{}:
      C.literal(literal)
    case _:
      Fail{C.diagnostic(origin, "invalid_constraint", "this predicate needs one quoted member name")}

def constraint_name_children(children: List<&2, C.Cst>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match children:
    case +name <> Nil{}:
      Bool.pick(Result<&2, &2, M.Diagnostic, String>, M.name_equal(C.kind_of(name), "qualified_name"), Done{C.name_of(name)}, Fail{C.diagnostic(node, "invalid_constraint", "operation predicate needs a qualified operation name")})
    case _:
      Fail{C.diagnostic(node, "invalid_constraint", "operation predicate needs a qualified operation name")}

def constraint_name(+node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  constraint_name_children(C.children_of(node), node)

def constraint_global(context: Context, target: String) -> Maybe<&2, Global>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  lookup_global(globals, target)

def constraint_operation(found: Maybe<&2, Global>, arguments: List<&2, C.Cst>, fuel: Nat, context: Context, scope: String, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  match found:
    case Some{Global{source, core, OperationTemplateName{identity, parameters}}}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        types : List<&2, M.Ty> <- constraint_types(arguments, fuel, context)
        return M.OperationPredicate{identity, types, M.FreeTy{scope, "$operation$" ++ Nat.show(C.offset_of(node))}}
    case _:
      Fail{C.diagnostic(node, "invalid_constraint", "operation predicate needs a declared generic effect operation")}

def constraint_operation_arguments(nodes: List<&2, C.Cst>, fuel: Nat, +context: Context, scope: String, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  match nodes:
    case name <> arguments:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        target : String <- constraint_name(name)
        constraint_operation(constraint_global(context, target), arguments, fuel, context, scope, node)
    case Nil{}:
      Fail{C.diagnostic(node, "invalid_constraint", "operation predicate needs an effect operation name")}

type ConstraintKind is Data:
  AssociatedConstraint{}
  ReceiverConstraint{}
  FieldConstraint{}
  UpdateConstraint{}
  OperationConstraint{}
  TypeRepConstraint{}
  EffectRepConstraint{}
  UnknownConstraint{}

def constraint_kind(+name: String) -> ConstraintKind:
  Bool.pick(ConstraintKind, M.name_equal(name, "associated"), AssociatedConstraint{},
    Bool.pick(ConstraintKind, M.name_equal(name, "receiver"), ReceiverConstraint{},
      Bool.pick(ConstraintKind, M.name_equal(name, "field"), FieldConstraint{},
        Bool.pick(ConstraintKind, M.name_equal(name, "update"), UpdateConstraint{},
          Bool.pick(ConstraintKind, M.name_equal(name, "operation"), OperationConstraint{},
            Bool.pick(ConstraintKind, M.name_equal(name, "type_rep"), TypeRepConstraint{},
              Bool.pick(ConstraintKind, M.name_equal(name, "effect_rep"), EffectRepConstraint{}, UnknownConstraint{})))))))

def constraint_predicate_parts(kind: ConstraintKind, member: String, types: List<&2, M.Ty>, effects: List<&2, C.Cst>, fuel: Nat, context: Context, scope: String, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  match kind types:
    case AssociatedConstraint{} left <> right <> result <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        invocation : M.EffectRow <- constraint_invocation(effects, fuel, context, scope, node)
        return M.AssociatedPredicate{member, Nil{}, left, right, result, invocation}
    case ReceiverConstraint{} receiver <> argument <> result <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        invocation : M.EffectRow <- constraint_invocation(effects, fuel, context, scope, node)
        return M.ReceiverPredicate{member, Nil{}, receiver, argument, result, invocation}
    case FieldConstraint{} receiver <> result <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        valid : Unit <- constraint_no_row(effects, node)
        return M.FieldPredicate{member, receiver, result}
    case UpdateConstraint{} receiver <> assigned <> result <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        invocation : M.EffectRow <- constraint_invocation(effects, fuel, context, scope, node)
        return M.UpdatePredicate{member, receiver, assigned, result, invocation}
    case _ _:
      Fail{C.diagnostic(node, "invalid_constraint", "predicate has the wrong kind or number of type arguments")}

def constraint_simple_parts(kind: ConstraintKind, types: List<&2, M.Ty>, effects: List<&2, C.Cst>, fuel: Nat, context: Context, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  match kind types effects:
    case TypeRepConstraint{} represented <> Nil{} Nil{}:
      Done{M.TypeRepPredicate{represented}}
    case EffectRepConstraint{} Nil{} row <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        value : M.EffectRow <- constraint_row(row, fuel, context)
        return M.EffectRepPredicate{value}
    case _ _ _:
      Fail{C.diagnostic(node, "invalid_constraint", "predicate has the wrong argument shape")}

def constraint_no_member(nodes: List<&2, C.Cst>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match nodes:
    case Nil{}:
      Done{Unit{}}
    case _:
      Fail{C.diagnostic(node, "invalid_constraint", "this predicate does not accept a member name")}

def lower_constraint_parts(+kind: ConstraintKind, +node: C.Cst, +fuel: Nat, +context: Context, scope: String, arguments: List<&2, C.Cst>, effects: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  match kind:
    case OperationConstraint{}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        valid_member : Unit <- constraint_no_member(C.field_values(node, "member"), node)
        valid : Unit <- constraint_no_row(effects, node)
        constraint_operation_arguments(arguments, fuel, context, scope, node)
    case TypeRepConstraint{}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        valid : Unit <- constraint_no_member(C.field_values(node, "member"), node)
        types : List<&2, M.Ty> <- constraint_types(arguments, fuel, context)
        constraint_simple_parts(kind, types, effects, fuel, context, node)
    case EffectRepConstraint{}:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        valid : Unit <- constraint_no_member(C.field_values(node, "member"), node)
        types : List<&2, M.Ty> <- constraint_types(arguments, fuel, context)
        constraint_simple_parts(kind, types, effects, fuel, context, node)
    case _:
      do Result<&2, &2, M.Diagnostic, M.Predicate>:
        member : String <- constraint_member(C.field_values(node, "member"), node)
        types : List<&2, M.Ty> <- constraint_types(arguments, fuel, context)
        constraint_predicate_parts(kind, member, types, effects, fuel, context, scope, node)

def lower_constraint_kind(kind: ConstraintKind, +node: C.Cst, fuel: Nat, context: Context, scope: String) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  lower_constraint_parts(kind, node, fuel, context, scope, C.field_values(node, "arguments"), C.field_values(node, "effects"))

def constraint_diagnostic(found: Result<&2, &2, M.Diagnostic, M.Predicate>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  match found:
    case Done{predicate}:
      Done{predicate}
    case Fail{M.Diagnostic{+code, subject, message}}:
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Predicate>, M.name_equal(code, "effect_instance"), Fail{C.diagnostic(node, "unsupported_polymorphic_effect_label", "explicit predicate rows currently require concrete effect operation labels")}, Fail{C.diagnostic(node, code, message)})

def lower_constraint_raw(+node: C.Cst, fuel: Nat, context: Context, scope: String) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  do Result<&2, &2, M.Diagnostic, M.Predicate>:
    kind_node : C.Cst <- C.one(C.field_values(node, "kind"))
    lower_constraint_kind(constraint_kind(C.text_of(kind_node)), node, fuel, context, scope)

def lower_constraint(+node: C.Cst, fuel: Nat, context: Context, scope: String) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  constraint_diagnostic(lower_constraint_raw(node, fuel, context, scope), node)


def lower_constraints(nodes: List<&2, C.Cst>, +fuel: Nat, +context: Context, +scope: String) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
        first : M.Predicate <- lower_constraint(node, fuel, context, scope)
        rest : List<&2, M.Predicate> <- lower_constraints(tail, fuel, context, scope)
        return first <> rest

def where_clause(annotation: Maybe<&2, M.Ty>, nodes: List<&2, C.Cst>, value: M.Expr, fuel: Nat, context: Context, scope: String) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match annotation nodes:
    case _ Nil{}:
      Done{value}
    case None{} node <> Nil{}:
      Fail{C.diagnostic(node, "invalid_constraint", "where requires a complete binding type annotation")}
    case Some{ty} +node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        +marker : C.Cst <- C.one(C.field_values(node, "marker"))
        valid : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, M.name_equal(C.text_of(marker), "where"), Done{Unit{}}, Fail{C.diagnostic(marker, "invalid_constraint", "expected where before predicate block")})
        predicates : List<&2, M.Predicate> <- lower_constraints(C.field_values(node, "predicates"), fuel, context, scope)
        return M.QualifiedExpr{C.offset_of(node), ty, predicates, value}
    case _ _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid where clause field"}}

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

def parameter_rank(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match nodes:
    case Nil{}:
      Done{Unit{}}
    case clause <> tail:
      Fail{C.diagnostic(clause, "higher_rank_constraint", "where clauses are supported on bindings, not parameter annotations")}

def demand_result(annotation: Maybe<&2, M.Ty>, scope: String) -> M.Ty:
  match annotation:
    case None{}:
      M.FreeTy{scope, "value"}
    case Some{ty}:
      ty

def demand_parameter(markers: List<&2, C.Cst>, parameter: Parameter, offset: Nat) -> Parameter:
  match markers parameter:
    case Nil{} parameter:
      parameter
    case _ Parameter{source, core, annotation}:
      +scope = "$demand$" ++ Nat.show(offset)
      result = demand_result(annotation, scope)
      Parameter{source, core, Some{M.demand_type(M.FunctionTy{M.UnitTy{}, result, M.EffectRow{Nil{}, M.FreeRow{scope, "effects"}}})}}

def lower_parameter(+node: C.Cst, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, Parameter>:
  do Result<&2, &2, M.Diagnostic, Parameter>:
    valid : Unit <- parameter_rank(C.field_values(node, "where"))
    param : Parameter <- parameter_fields(C.field_values(node, "name"), C.field_values(node, "annotation"), fuel, context)
    return demand_parameter(C.field_values(node, "demand"), param, C.offset_of(node))

def bind_parameter(context: Context, param: Parameter) -> Context:
  Parameter{source, core, annotation} = param
  bind(context, Local{source, core})


def scalar_intrinsic(+name: String, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Primitive>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.div"), Done{ScalarPrimitive{M.U32Divide{}}},
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.rem"), Done{ScalarPrimitive{M.U32Remainder{}}},
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.bit_and"), Done{ScalarPrimitive{M.U32BitAnd{}}},
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.bit_or"), Done{ScalarPrimitive{M.U32BitOr{}}},
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.bit_xor"), Done{ScalarPrimitive{M.U32BitXor{}}},
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.shl"), Done{ScalarPrimitive{M.U32ShiftLeft{}}},
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@u32.shr"), Done{ScalarPrimitive{M.U32ShiftRight{}}},
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
      Fail{C.diagnostic(node, "unknown_intrinsic", "unknown compiler intrinsic " ++ name)})))))))))))))))))))))))))))))))

def ordinary_intrinsic(+name: String, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Primitive>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@force"), Done{ForcePrimitive{}},
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@product.get"), Done{ProjectPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@array.generate"), Done{ArrayGeneratePrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@array.fill"), Done{ArrayFillPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@array.get"), Done{ArrayGetPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@array.set"), Done{ArraySetPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@array.length"), Done{ArrayLengthPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.state"), Done{StateProviderPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.provider"), Done{ProviderPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.descriptor"), Done{OperationDescriptorPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.of"), Done{FunctionEffectsPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.has"), Done{EffectHasPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.count"), Done{EffectCountPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.same"), Done{EffectSamePrimitive{}},
      scalar_intrinsic(name, node)))))))))))))))

def effect_family_intrinsic(+name: String, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Primitive>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.run"), Done{EffectFamilyPrimitive{name, 2n, 2n}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.reader"), Done{EffectFamilyPrimitive{name, 1n, 3n}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@effect.writer"), Done{EffectFamilyPrimitive{name, 1n, 3n}}, ordinary_intrinsic(name, node))))

def existing_deferred_intrinsic(+name: String, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Primitive>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@type.same"), Done{DeferredPrimitive{name, 2n}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@state.get"), Done{DeferredPrimitive{name, 1n}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@state.set"), Done{DeferredPrimitive{name, 1n}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@state.run"), Done{DeferredPrimitive{name, 2n}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@state.reader"), Done{DeferredPrimitive{name, 3n}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@state.writer"), Done{DeferredPrimitive{name, 3n}}, effect_family_intrinsic(name, node)))))))

def deferred_intrinsic(+name: String, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Primitive>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@do.monad"), Done{DeferredPrimitive{name, 1n}}, existing_deferred_intrinsic(name, node))

def intrinsic(+name: String, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Primitive>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@type.result"), Done{ResultPrimitive{}},
    Bool.pick(Result<&2, &2, M.Diagnostic, Primitive>, M.name_equal(name, "@type.call"), Done{AssociatedPrimitive{}}, deferred_intrinsic(name, node)))


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

def operation_specialized_target(target: OperationTarget, template: M.TypeId, +arguments: List<&2, M.Ty>) -> OperationTarget:
  match target:
    case OperationTarget{identity, previous, old_arguments}:
      OperationTarget{identity, Some{template}, arguments}

def operation_reference(value: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, OperationTarget>:
  match value:
    case M.SourceExpr{offset, annotation, inner}:
      operation_reference(inner, node)
    case M.SpecializeOperationExpr{template, arguments, body}:
      do Result<&2, &2, M.Diagnostic, OperationTarget>:
        target : OperationTarget <- operation_reference(body, node)
        return operation_specialized_target(target, template, arguments)
    case M.OperationExpr{identity}:
      Done{OperationTarget{identity, None{}, Nil{}}}
    case _:
      Fail{C.diagnostic(node, "operation_target", "expected the name of a declared effect operation")}

def operation_target_identity(target: OperationTarget) -> M.TypeId:
  OperationTarget{identity, template, arguments} = target
  identity

def wrap_operation_target(target: OperationTarget, body: M.Expr) -> M.Expr:
  match target:
    case OperationTarget{identity, None{}, arguments}:
      body
    case OperationTarget{identity, Some{template}, arguments}:
      M.SpecializeOperationExpr{template, arguments, body}

def foreign_argument_children(nodes: List<&2, C.Cst>) -> Bool:
  match nodes:
    case +node <> Nil{}:
      Bool.and(M.name_equal(C.kind_of(node), "qualified_name"), M.name_equal(C.name_of(node), "Foreign"))
    case _:
      False{}

def foreign_argument(node: C.Cst) -> Bool:
  foreign_argument_children(C.children_of(node))

def require_unsealed_operation(sealed: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match sealed:
    case True{}:
      Fail{C.diagnostic(node, "sealed_effect", "Foreign is a compiler effect label, not a callable or providable operation")}
    case False{}:
      Done{Unit{}}

def function_reference(value: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  match value:
    case M.InstantiationExpr{site, inner}:
      function_reference(inner, node)
    case M.SourceExpr{offset, annotation, inner}:
      function_reference(inner, node)
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
    case M.InstantiationExpr{site, inner}:
      constructor_name(inner, node)
    case M.SourceExpr{offset, annotation, inner}:
      constructor_name(inner, node)
    case M.ConstructorRefExpr{constructor}:
      Done{constructor}
    case _:
      Fail{C.diagnostic(node, "unknown_constructor", "expected a data constructor")}

def selector_value(names: List<&2, C.Cst>, receiver: M.Expr) -> M.Expr:
  match names:
    case Nil{}:
      receiver
    case +name <> rest:
      +offset = C.offset_of(name)
      selector_value(rest, instantiate_at(offset, 2n, M.AssociatedExpr{offset, M.MemberDispatch{}, C.text_of(name), Nil{}, receiver, M.UnitExpr{}}))

def pattern_name(+node: C.Cst) -> PatternResult:
  +source = C.text_of(node)
  +core = unique_name(node)
  Bool.pick(PatternResult, M.name_equal(source, "_"), PatternResult{M.WildcardPattern{}, Nil{}}, PatternResult{M.BindingPattern{core}, [Local{source, core}]})

def value_pattern(reference: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, PatternResult>:
  match reference:
    case M.InstantiationExpr{site, inner}:
      value_pattern(inner, node)
    case M.SourceExpr{offset, annotation, inner}:
      value_pattern(inner, node)
    case M.LocalExpr{name}:
      Done{PatternResult{M.ValuePattern{M.LocalReference{name}}, Nil{}}}
    case M.ConstantExpr{name}:
      Done{PatternResult{M.ValuePattern{M.ConstantReference{name}}, Nil{}}}
    case _:
      Fail{C.diagnostic(node, "value_pattern_reference", "a value pattern requires a constant, parameter, or existing let binding")}

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
    return PatternRecordFields{constructor, fields, Index.set(M.Pattern, patterns, C.text_of(name), pattern), List.append(&2, Local, locals, previous)}

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
        case PatternValue{}:
          do Result<&2, &2, M.Diagnostic, PatternResult>:
            name : C.Cst <- C.one(C.field_values(node, "name"))
            reference : M.Expr <- resolve(context, name)
            value_pattern(reference, node)
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

def row_locals(row: PatternRow) -> List<&2, Local>:
  PatternRow{patterns, locals} = row
  locals

def same_local_names(locals: List<&2, Local>, +other: List<&2, Local>) -> Bool:
  match locals:
    case Nil{}:
      True{}
    case Local{source, core} <> tail:
      Bool.and(Maybe.is_some(&2, String, lookup_local(other, source)), same_local_names(tail, other))

def alternative_names(valid: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match valid:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{C.diagnostic(node, "alternative_bindings", "alternative patterns must bind the same names")}

def lower_alternatives(nodes: List<&2, C.Cst>, +canonical: PatternRow, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, List<&2, PatternRow>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, PatternRow>>:
        +row : PatternRow <- lower_pattern_row(C.field_values(node, "patterns"), fuel, context)
        valid : Unit <- alternative_names(Bool.and(same_local_names(row_locals(canonical), row_locals(row)), same_local_names(row_locals(row), row_locals(canonical))), node)
        rest : List<&2, PatternRow> <- lower_alternatives(tail, canonical, fuel, context)
        return row <> rest

def lower_arm_rows(nodes: List<&2, C.Cst>, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, List<&2, PatternRow>>:
  match nodes:
    case +first <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, PatternRow>>:
        +canonical : PatternRow <- lower_pattern_row(C.field_values(first, "patterns"), fuel, context)
        rows : List<&2, PatternRow> <- lower_alternatives(tail, canonical, fuel, context)
        return canonical <> rows
    case Nil{}:
      Fail{M.Diagnostic{"internal_cst", "case", "case arm requires a pattern row"}}

def arm_scope(context: Context, rows: List<&2, PatternRow>) -> Context:
  match rows:
    case first <> rest:
      row_scope(context, first)
    case Nil{}:
      context

def descriptor_argument(+fuel: Nat, value: M.Expr) -> M.Expr:
  match fuel value:
    case 1n+rest M.SourceExpr{offset, annotation, inner}:
      M.SourceExpr{offset, annotation, descriptor_argument(rest, inner)}
    case 1n+rest M.SpecializeOperationExpr{template, arguments, inner}:
      M.SpecializeOperationExpr{template, arguments, descriptor_argument(rest, inner)}
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
      Fail{C.diagnostic(node, "resolver_required", "return $ requires a monad resolver on the nearest do block")}

def require_resolved_return(markers: List<&2, C.Cst>, resolved: Bool) -> Result<&2, &2, M.Diagnostic, Unit>:
  match resolved:
    case True{}:
      Done{Unit{}}
    case False{}:
      require_plain_return(markers)

def forwarded(context: Context, yes: Bool, value: M.Expr, offset: Nat) -> M.Expr:
  match context yes:
    case Context{globals, headers, fixities, locals, Some{label}, variables} True{}:
      Resolvers.call(label, offset, "forward", value)
    case _ _:
      value

def returning(context: Context, value: M.Expr, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match context:
    case Context{globals, headers, fixities, locals, Some{label}, annotation_variables}:
      Done{M.ReturnExpr{label, value}}
    case _:
      Fail{C.diagnostic(node, "return_scope", "return requires an enclosing do block in this function")}

def lambda(identity: Nat, param: Parameter, result: Maybe<&2, M.Ty>, body: M.Expr) -> M.Expr:
  Parameter{source, core, annotation} = param
  M.LambdaExpr{Nat.mul(identity, 16n), core, annotation, result, body}

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
      Done{Local{"_", "$use$discard$" ++ Nat.show(offset)}}
    case +name <> Nil{}:
      Done{Local{C.text_of(name), "$use$" ++ unique_name(name)}}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid use binding"}}

def effect_binding(target: Local, value: M.Expr, body: M.Expr) -> M.Expr:
  Local{source, core} = target
  M.UseExpr{core, value, body}

def pattern_of(result: PatternResult) -> M.Pattern:
  PatternResult{pattern, locals} = result
  pattern

def loop_pattern(fuel: Nat, nodes: List<&2, C.Cst>, context: Context) -> Result<&2, &2, M.Diagnostic, PatternResult>:
  match nodes:
    case Nil{}:
      Done{PatternResult{M.WildcardPattern{}, Nil{}}}
    case +node <> Nil{}:
      lower_pattern(fuel, classify(C.kind_of(node)), node, context)
    case _:
      Fail{M.Diagnostic{"internal_cst", "for", "invalid loop pattern"}}

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
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
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

def pattern_locals(result: PatternResult) -> List<&2, Local>:
  PatternResult{pattern, locals} = result
  locals

def shadow_names(locals: List<&2, Local>, shadowed: Set()) -> Set():
  match locals:
    case Nil{}:
      shadowed
    case Local{source, core} <> tail:
      shadow_names(tail, Set.add(shadowed, source))

def target_name(+name: String, +shadowed: Set(), +targets: Set()) -> Set():
  Bool.pick(Set(), Maybe.is_some(&2, Unit, Index.find(Unit, shadowed, name)), targets, Set.add(targets, name))

# Successors flow through loops and conditional suites. A nested do block
# introduces its own scope; locally declared names never escape their suite.
type LoopTargetsWork is Data:
  LoopTargets{nodes: List<&2, C.Cst>}
  LoopTarget{kind: NodeKind, node: C.Cst, tail: List<&2, C.Cst>}

def loop_targets(+fuel: Nat, work: LoopTargetsWork, +context: Context, +shadowed: Set(), +targets: Set()) -> Result<&2, &2, M.Diagnostic, Set()>:
  match fuel work:
    case _ LoopTargets{Nil{}}:
      Done{targets}
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "for", "loop binding analysis exceeded its source-tree bound"}}
    case 1n+rest LoopTargets{statement <> tail}:
      do Result<&2, &2, M.Diagnostic, Set()>:
        +node : C.Cst <- C.one(C.field_values(statement, "value"))
        loop_targets(rest, LoopTarget{classify(C.kind_of(node)), node, tail}, context, shadowed, targets)
    case 1n+rest LoopTarget{Rebinding{}, node, tail}:
      do Result<&2, &2, M.Diagnostic, Set()>:
        name : C.Cst <- C.one(C.field_values(node, "name"))
        loop_targets(rest, LoopTargets{tail}, context, shadowed, target_name(C.text_of(name), shadowed, targets))
    case 1n+rest LoopTarget{Binding{}, node, tail}:
      do Result<&2, &2, M.Diagnostic, Set()>:
        +pattern : C.Cst <- C.one(C.field_values(node, "pattern"))
        +parsed : PatternResult <- lower_pattern(rest, classify(C.kind_of(pattern)), pattern, context)
        loop_targets(rest, LoopTargets{tail}, pattern_scope(context, parsed), shadow_names(pattern_locals(parsed), shadowed), targets)
    case 1n+rest LoopTarget{EffectBinding{}, +node, tail}:
      do Result<&2, &2, M.Diagnostic, Set()>:
        +target : Local <- effect_target(C.field_values(node, "name"), C.offset_of(node))
        loop_targets(rest, LoopTargets{tail}, bind(context, target), shadow_names([target], shadowed), targets)
    case 1n+rest LoopTarget{ForLoop{}, +node, tail}:
      do Result<&2, &2, M.Diagnostic, Set()>:
        +parsed : PatternResult <- loop_pattern(rest, C.field_values(node, "pattern"), context)
        suite : C.Cst <- C.one(C.field_values(node, "body"))
        nested : Set() <- loop_targets(rest, LoopTargets{statement_nodes(suite)}, pattern_scope(context, parsed), shadow_names(pattern_locals(parsed), shadowed), targets)
        loop_targets(rest, LoopTargets{tail}, context, shadowed, nested)
    case 1n+rest LoopTarget{Conditional{}, +node, tail}:
      do Result<&2, &2, M.Diagnostic, Set()>:
        yes : C.Cst <- C.one(C.field_values(node, "consequence"))
        no : List<&2, C.Cst> <- else_statements(C.field_values(node, "fallback"))
        left : Set() <- loop_targets(rest, LoopTargets{statement_nodes(yes)}, context, shadowed, targets)
        both : Set() <- loop_targets(rest, LoopTargets{no}, context, shadowed, left)
        loop_targets(rest, LoopTargets{tail}, context, shadowed, both)
    case 1n+rest LoopTarget{PatternConditional{}, +node, tail}:
      do Result<&2, &2, M.Diagnostic, Set()>:
        +pattern : C.Cst <- C.one(C.field_values(node, "pattern"))
        +parsed : PatternResult <- lower_pattern(rest, classify(C.kind_of(pattern)), pattern, context)
        yes : C.Cst <- C.one(C.field_values(node, "consequence"))
        no : List<&2, C.Cst> <- else_statements(C.field_values(node, "fallback"))
        left : Set() <- loop_targets(rest, LoopTargets{statement_nodes(yes)}, pattern_scope(context, parsed), shadow_names(pattern_locals(parsed), shadowed), targets)
        both : Set() <- loop_targets(rest, LoopTargets{no}, context, shadowed, left)
        loop_targets(rest, LoopTargets{tail}, context, shadowed, both)
    case 1n+rest LoopTarget{kind, node, tail}:
      loop_targets(rest, LoopTargets{tail}, context, shadowed, targets)

def carried_locals(locals: List<&2, Local>, +targets: Set(), +seen: Set()) -> List<&2, Local>:
  match locals:
    case Nil{}:
      Nil{}
    case +local <> tail:
      Local{+source, core} = local
      +keep = Bool.and(Maybe.is_some(&2, Unit, Index.find(Unit, targets, source)), Bool.not(Maybe.is_some(&2, Unit, Index.find(Unit, seen, source))))
      +rest = carried_locals(tail, targets, Set.add(seen, source))
      Bool.pick(List<&2, Local>, keep, local <> rest, rest)

def loop_locals(context: Context, targets: Set()) -> List<&2, Local>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  carried_locals(locals, targets, Set.new())

def loop_value(elements: List<&2, M.Expr>) -> M.Expr:
  match elements:
    case Nil{}:
      M.UnitExpr{}
    case value <> Nil{}:
      value
    case elements:
      M.ProductExpr{elements}

def local_values(locals: List<&2, Local>) -> List<&2, M.Expr>:
  match locals:
    case Nil{}:
      Nil{}
    case Local{source, core} <> tail:
      M.LocalExpr{core} <> local_values(tail)

def loop_versions(locals: List<&2, Local>, +prefix: String) -> List<&2, Local>:
  match locals:
    case Nil{}:
      Nil{}
    case Local{+source, core} <> tail:
      Local{source, prefix ++ source} <> loop_versions(tail, prefix)

def loop_bindings(locals: List<&2, Local>, +state: String, +index: Nat, +single: Bool, body: M.Expr) -> M.Expr:
  match locals:
    case Nil{}:
      body
    case Local{source, core} <> tail:
      M.UseExpr{core, Bool.pick(M.Expr, single, M.LocalExpr{state}, M.ProjectExpr{M.LocalExpr{state}, index}), loop_bindings(tail, state, 1n+index, single, body)}

def successor_carried(carried: List<&2, Local>, +previous: Maybe<&2, String>, +next: String) -> List<&2, Local>:
  match carried previous:
    case Nil{} _:
      Nil{}
    case carried None{}:
      carried
    case Local{source, +core} <> tail Some{old}:
      Local{source, Bool.pick(String, M.name_equal(core, old), next, core)} <> successor_carried(tail, previous, next)

def loop_carried(originals: List<&2, Local>, versions: List<&2, Local>, carried: List<&2, Local>) -> List<&2, Local>:
  match originals versions:
    case Local{source, previous} <> old_tail Local{next_source, next} <> next_tail:
      loop_carried(old_tail, next_tail, successor_carried(carried, Some{previous}, next))
    case _ _:
      carried

# Or-patterns share one body. Each candidate yields bindings in the first
# row's name order; a failed candidate exits its arm's private skip block.
# Guard failure likewise falls through without reevaluating any scrutinee.
def canonical_locals(rows: List<&2, PatternRow>) -> List<&2, Local>:
  match rows:
    case first <> rest:
      row_locals(first)
    case Nil{}:
      Nil{}

def canonical_value(found: Maybe<&2, String>) -> M.Expr:
  match found:
    case Some{name}:
      M.LocalExpr{name}
    case None{}:
      M.PanicExpr{"invalid alternative binding"}

def row_values(locals: List<&2, Local>, +row: List<&2, Local>) -> List<&2, M.Expr>:
  match locals:
    case Nil{}:
      Nil{}
    case Local{source, core} <> rest:
      canonical_value(lookup_local(row, source)) <> row_values(rest, row)

def binding_arms(rows: List<&2, PatternRow>, +canonical: List<&2, Local>) -> List<&2, M.MatchArm<M.Expr>>:
  match rows:
    case Nil{}:
      Nil{}
    case PatternRow{patterns, locals} <> rest:
      M.MatchArm{patterns, loop_value(row_values(canonical, locals))} <> binding_arms(rest, canonical)

def wildcard_patterns(values: List<&2, M.Expr>) -> List<&2, M.Pattern>:
  match values:
    case Nil{}:
      Nil{}
    case head <> tail:
      M.WildcardPattern{} <> wildcard_patterns(tail)

def coverage_rows(rows: List<&2, PatternRow>) -> List<&2, M.MatchArm<M.Expr>>:
  match rows:
    case Nil{}:
      Nil{}
    case PatternRow{patterns, locals} <> rest:
      M.MatchArm{patterns, M.PanicExpr{"unreachable coverage check"}} <> coverage_rows(rest)

def coverage_arms(arms: List<&2, SurfaceArm>) -> List<&2, M.MatchArm<M.Expr>>:
  match arms:
    case Nil{}:
      Nil{}
    case SurfaceArm{rows, True{}, guard, body, offset} <> rest:
      coverage_arms(rest)
    case SurfaceArm{rows, False{}, guard, body, offset} <> rest:
      List.append(&2, M.MatchArm<M.Expr>, coverage_rows(rows), coverage_arms(rest))

def simple_arms(arms: List<&2, SurfaceArm>) -> Maybe<&2, List<&2, M.MatchArm<M.Expr>>>:
  match arms:
    case Nil{}:
      Some{Nil{}}
    case SurfaceArm{PatternRow{patterns, locals} <> Nil{}, False{}, guard, body, offset} <> rest:
      Maybe.map(&2, List<&2, M.MatchArm<M.Expr>>, List<&2, M.MatchArm<M.Expr>>, tail => M.MatchArm{patterns, body} <> tail, simple_arms(rest))
    case _:
      None{}

def guarded_arms(arms: List<&2, SurfaceArm>, +values: List<&2, M.Expr>, +label: Nat) -> M.Expr:
  match arms:
    case Nil{}:
      M.PanicExpr{"case did not match"}
    case SurfaceArm{+rows, guarded, guard, body, +offset} <> rest:
      +skip = {1n+offset : Nat}
      +locals = canonical_locals(rows)
      +name = "$case$bindings$" ++ Nat.show(offset)
      selected = {M.MatchExpr{values, List.append(&2, M.MatchArm<M.Expr>, binding_arms(rows, locals), [M.MatchArm{wildcard_patterns(values), M.ReturnExpr{skip, M.UnitExpr{}}}])} : M.Expr}
      action = {M.IfExpr{guard, M.ReturnExpr{label, body}, M.UnitExpr{}} : M.Expr}
      block = {M.BlockExpr{skip, M.UseExpr{name, selected, loop_bindings(locals, name, 0n, Nat.is_eq(List.length(&2, Local, locals), 1n), action)}} : M.Expr}
      M.SequenceExpr{block, guarded_arms(rest, values, label)}

def case_locals(values: List<&2, M.Expr>, +prefix: String, +index: Nat) -> List<&2, Local>:
  match values:
    case Nil{}:
      Nil{}
    case head <> rest:
      Local{"", prefix ++ Nat.show(index)} <> case_locals(rest, prefix, 1n+index)

def case_bindings(values: List<&2, M.Expr>, locals: List<&2, Local>, body: M.Expr) -> M.Expr:
  match values locals:
    case head <> rest Local{source, name} <> tail:
      M.UseExpr{name, head, case_bindings(rest, tail, body)}
    case _ _:
      body

def complex_case(values: List<&2, M.Expr>, arms: List<&2, SurfaceArm>) -> M.Expr:
  match arms:
    case Nil{}:
      M.MatchExpr{values, Nil{}}
    case SurfaceArm{rows, guarded, guard, body, +offset} <> rest:
      +all = {SurfaceArm{rows, guarded, guard, body, offset} <> rest : List<&2, SurfaceArm>}
      +input = values
      +locals = case_locals(input, "$case$" ++ Nat.show(offset) ++ "$", 0n)
      +references = local_values(locals)
      +label = offset
      # Check coverage using only unguarded rows. The constant-false branch
      # is checked before optimization and never evaluates at runtime.
      checked = {M.IfExpr{M.BoolExpr{False{}}, M.MatchExpr{references, coverage_arms(all)}, M.BlockExpr{label, guarded_arms(all, references, label)}} : M.Expr}
      case_bindings(input, locals, checked)

def finished_case(simple: Maybe<&2, List<&2, M.MatchArm<M.Expr>>>, values: List<&2, M.Expr>, arms: List<&2, SurfaceArm>) -> M.Expr:
  match simple:
    case Some{rows}:
      M.MatchExpr{values, rows}
    case None{}:
      complex_case(values, arms)

# Branches without outgoing local successors retain the ordinary sequencing
# form, including the checked source shape used by schema specialization.
def conditional_successors(successors: List<&2, Local>, +prefix: String, branch: M.Expr, next: M.Expr) -> M.Expr:
  match successors:
    case Nil{}:
      M.SequenceExpr{branch, next}
    case +locals:
      M.UseExpr{prefix ++ "result", branch, loop_bindings(locals, prefix ++ "result", 0n, Nat.is_eq(List.length(&2, Local, locals), 1n), next)}

def application_children(kind: NodeKind, +node: C.Cst) -> List<&2, C.Cst>:
  match kind:
    case Wrapper{}:
      C.children_of(node)
    case GroupNode{}:
      C.field_values(node, "value")
    case InfixNode{}:
      Bool.pick(List<&2, C.Cst>, List.is_empty(&2, C.Cst, C.field_values(node, "tails")), C.field_values(node, "head"), Nil{})
    case PrefixNode{}:
      Bool.pick(List<&2, C.Cst>, List.is_empty(&2, C.Cst, C.field_values(node, "operator")), C.field_values(node, "value"), Nil{})
    case _:
      Nil{}

type GroupedOperation is Data:
  OperationHead{kind: NodeKind, node: C.Cst}
  OperationChildren{nodes: List<&2, C.Cst>}
  OperationTemplate{template: Maybe<&2, TemplateReference>, node: C.Cst}

# Only type application crosses grouping here. Runtime calls keep their original
# boundaries, including calls to functions returned by fixed-arity intrinsics.
def grouped_operation(fuel: Nat, work: GroupedOperation, arguments: List<&2, C.Cst>, +context: Context) -> Result<&2, &2, M.Diagnostic, Maybe<&2, TypedCall>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"type_argument", "parser", "effect application exceeds the source-tree limit"}}
    case 1n+rest OperationHead{ApplicationNode{}, +node}:
      grouped_operation(rest, OperationChildren{C.field_values(node, "head")}, List.append(&2, C.Cst, C.field_values(node, "arguments"), arguments), context)
    case 1n+rest OperationHead{RecordNode{}, +node}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, TypedCall>>:
        fields : C.Cst <- C.one(C.field_values(node, "fields"))
        grouped_operation(rest, OperationChildren{C.field_values(node, "name")}, fields <> arguments, context)
    case 1n+rest OperationHead{Name{}, +node}:
      Context{globals, headers, fixities, locals, label, annotation_variables} = context
      grouped_operation(rest, OperationTemplate{template_reference(lookup_local(locals, C.name_of(node)), lookup_global(globals, C.name_of(node))), node}, arguments, context)
    case 1n+rest OperationHead{kind, node}:
      grouped_operation(rest, OperationChildren{application_children(kind, node)}, arguments, context)
    case 1n+rest OperationChildren{+node <> Nil{}}:
      grouped_operation(rest, OperationHead{classify(C.kind_of(node)), node}, arguments, context)
    case 1n+rest OperationChildren{nodes}:
      Done{None{}}
    case 1n+rest OperationTemplate{None{}, node}:
      Done{None{}}
    case 1n+rest OperationTemplate{Some{template}, node}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, TypedCall>>:
        call : TypedCall <- typed_operation_value(template, arguments, rest, context, node)
        return Some{call}

# Terminal field replacement need not read the old value when `self` is unused.
# Array getters retain their read because bounds traps must precede the RHS.
def terminal_update_field(free: Result<&2, &2, M.Diagnostic, List<&2, String>>, +name: String, receiver: M.Expr, +value: M.Expr) -> M.Expr:
  match free:
    case Done{names}:
      Bool.pick(M.Expr, Closures.contains(names, name), M.UseExpr{name, receiver, value}, value)
    case Fail{diagnostic}:
      M.UseExpr{name, receiver, value}

def terminal_update_value(receiver: M.Expr, +name: String, +value: M.Expr) -> M.Expr:
  match receiver:
    case M.AssociatedExpr{identity, M.MemberDispatch{}, member, templates, left, right}:
      terminal_update_field(Closures.free(4096n, Closures.ExpressionWork{value, Nil{}}), name, M.AssociatedExpr{identity, M.MemberDispatch{}, member, templates, left, right}, value)
    case other:
      M.UseExpr{name, other, value}

# Expression and statement recursion share an explicit work type. Each branch
# consumes source-tree fuel; block exits stay explicit rather than copying tails.
type AnnotationScan is Data:
  ScanNode{node: C.Cst, root: Bool}
  ScanNodes{nodes: List<&2, C.Cst>, reversed: List<&2, C.Cst>}

# A nested let owns its annotation names. The declaration's broad CST scan
# must not capture those names before the let gets its own $let$ scope.
def annotation_scan_work(+fuel: Nat, work: AnnotationScan) -> Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"type_argument", "parser", "annotation scope exceeds the source-tree limit"}}
    case 1n+rest ScanNode{C.Cst{"binding", field, text, offset, children}, False{}}:
      Done{[C.Cst{"binding", field, text, offset, Nil{}}]}
    case 1n+rest ScanNode{C.Cst{kind, field, text, offset, children}, root}:
      do Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
        scoped : List<&2, C.Cst> <- annotation_scan_work(rest, ScanNodes{children, Nil{}})
        return [C.Cst{kind, field, text, offset, scoped}]
    case 1n+rest ScanNodes{Nil{}, reversed}:
      Done{List.reverse(&2, C.Cst, reversed)}
    case 1n+rest ScanNodes{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
        scanned : List<&2, C.Cst> <- annotation_scan_work(rest, ScanNode{head, False{}})
        node : C.Cst <- C.one(scanned)
        annotation_scan_work(rest, ScanNodes{tail, node <> reversed})

def inherited_annotation_kind(same: Bool, source: String, value: M.Ty, kind: T.VariableKind, node: C.Cst) -> Result<&2, &2, M.Diagnostic, T.Variable>:
  match same:
    case True{}:
      Done{T.Variable{source, value, kind}}
    case False{}:
      Fail{C.diagnostic(node, "annotation_kind_mismatch", "one annotation name cannot be both a type and an effect-row variable")}

def inherited_annotation_variable(found: Maybe<&2, T.Variable>, scanned: T.Variable, node: C.Cst) -> Result<&2, &2, M.Diagnostic, T.Variable>:
  match found scanned:
    case None{} variable:
      Done{variable}
    case Some{T.Variable{previous_name, previous_value, previous_kind}} T.Variable{source, value, +kind}:
      inherited_annotation_kind(T.same_kind(previous_kind, kind), source, previous_value, kind, node)

def inherited_annotation_variables(scanned: List<&2, T.Variable>, +previous: List<&2, T.Variable>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
  match scanned:
    case Nil{}:
      Done{previous}
    case T.Variable{+source, value, kind} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
        variable : T.Variable <- inherited_annotation_variable(T.found_variable(previous, source), T.Variable{source, value, kind}, node)
        rest : List<&2, T.Variable> <- inherited_annotation_variables(tail, previous, node)
        return variable <> rest

def annotation_scope(+node: C.Cst, context: Context, scope: String) -> Result<&2, &2, M.Diagnostic, Context>:
  Context{globals, headers, fixities, locals, label, previous} = context
  do Result<&2, &2, M.Diagnostic, Context>:
    scanned : List<&2, T.Variable> <- T.scoped_free_variables(node, scope)
    variables : List<&2, T.Variable> <- inherited_annotation_variables(scanned, previous, node)
    return Context{globals, headers, fixities, locals, label, variables}

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
            value : M.Expr <- resolve_value(context, node)
            return located(C.offset_of(node), value)
        case Expression{MarkedConstructor{}, node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +child : C.Cst <- C.one(C.field_values(node, "value"))
            lower(remaining, ConstructorExpression{classify(C.kind_of(child)), child}, context)
        case ConstructorExpression{RecordNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            name : C.Cst <- C.one(C.field_values(node, "name"))
            fields : C.Cst <- C.one(C.field_values(node, "fields"))
            target : RecordTarget <- record_target(context, name)
            lower(remaining, record_elements(target, fields, node), context)
        case ConstructorExpression{Truth{}, node}:
          Done{located(C.offset_of(node), M.BoolExpr{True{}})}
        case ConstructorExpression{Falsehood{}, node}:
          Done{located(C.offset_of(node), M.BoolExpr{False{}})}
        case ConstructorExpression{kind, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- resolve(context, node)
            constructor : String <- constructor_name(value, node)
            return located(C.offset_of(node), instantiate_at(C.offset_of(node), 0n, M.ConstructorRefExpr{constructor}))
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
          lower(remaining, ApplicationHead{RecordNode{}, node, Nil{}, C.offset_of(node)}, context)
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
        case Expression{SelectorNode{}, +node}:
          +offset = C.offset_of(node)
          +parameter = "$selector$" ++ Nat.show(offset)
          Done{located(offset, M.LambdaExpr{Nat.mul(offset, 16n), parameter, None{}, None{}, selector_value(C.field_values(node, "name"), M.LocalExpr{parameter})})}
        case Expression{TypeWitnessNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            child : C.Cst <- C.one(C.field_values(node, "value"))
            value : M.Expr <- lower(remaining, visit(child), context)
            +offset : Nat = C.offset_of(node)
            constructor : M.Expr <- resolve(context, C.Cst{"qualified_name", "", "", offset, [C.Cst{"TYPE_IDENT", "root", "Type", offset, Nil{}}]})
            return located(offset, M.ApplyExpr{constructor, value})
        case Expression{IfValueNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            test : C.Cst <- C.one(C.field_values(node, "condition"))
            yes : C.Cst <- C.one(C.field_values(node, "consequence"))
            no : C.Cst <- C.one(C.field_values(node, "alternative"))
            condition : M.Expr <- lower(remaining, visit(test), context)
            consequent : M.Expr <- lower(remaining, visit(yes), context)
            alternative : M.Expr <- lower(remaining, visit(no), context)
            return located(C.offset_of(node), M.IfExpr{condition, consequent, alternative})
        case Expression{MemberNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            receiver_node : C.Cst <- C.one(C.field_values(node, "receiver"))
            +name : C.Cst <- C.one(C.field_values(node, "name"))
            receiver : M.Expr <- lower(remaining, visit(receiver_node), context)
            +offset : Nat = C.offset_of(name)
            return located(offset, instantiate_at(offset, 2n, M.AssociatedExpr{offset, M.MemberDispatch{}, C.text_of(name), Nil{}, receiver, M.UnitExpr{}}))
        case Expression{IndexNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            receiver_node : C.Cst <- C.one(C.field_values(node, "receiver"))
            index_node : C.Cst <- C.one(C.field_values(node, "index"))
            receiver : M.Expr <- lower(remaining, visit(receiver_node), context)
            index : M.Expr <- lower(remaining, visit(index_node), context)
            return located(C.offset_of(node), M.ArrayGetExpr{receiver, index})
        case Expression{ApplicationNode{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +parts : Postfix.Parts <- Postfix.application(node)
            +target : C.Cst <- C.one(C.children_of(Postfix.head(parts)))
            lower(remaining, ApplicationHead{classify(C.kind_of(target)), target, Postfix.arguments(parts), C.offset_of(node)}, context)
        case ApplicationHead{RecordNode{}, +node, arguments, offset}:
          Context{globals, headers, fixities, locals, label, annotation_variables} = context
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +name : C.Cst <- C.one(C.field_values(node, "name"))
            fields : C.Cst <- C.one(C.field_values(node, "fields"))
            lower(remaining, RecordApplication{template_reference(lookup_local(locals, C.name_of(name)), lookup_global(globals, C.name_of(name))), name, fields, arguments, offset, node}, context)
        case RecordApplication{Some{operation}, head, fields, arguments, offset, node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            typed : TypedCall <- typed_operation_value(operation, fields <> arguments, remaining, context, head)
            lower(remaining, typed_call_work(typed, offset), context)
        case RecordApplication{None{}, head, fields, arguments, offset, node}:
          Fail{C.diagnostic(node, "constructor_marker", "record constructors require # before the name")}
        case ApplicationHead{Intrinsic{}, +head, arguments, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            primitive : Primitive <- intrinsic(C.text_of(head), head)
            lower(remaining, PrimitiveCall{primitive, head, arguments, offset}, context)
        case PrimitiveCall{ForcePrimitive{}, head, value <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            forced : M.Expr <- lower(remaining, visit(value), context)
            return located(offset, M.ForceExpr{forced})
        case PrimitiveCall{ForcePrimitive{}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "@force requires one suspended computation")}
        case PrimitiveCall{ResultPrimitive{}, head, member <> operand <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            name : String <- literal_argument(member)
            value : M.Expr <- lower(remaining, visit(operand), context)
            # The uncalled thunk carries the destination type through ordinary
            # qualified schemes. Its result is tied to this call by inference.
            witness : M.Expr = M.LambdaExpr{Nat.add(Nat.mul(offset, 16n), 6n), "$result$witness", Some{M.UnitTy{}}, None{}, M.PanicExpr{"uncalled result witness"}}
            return located(offset, M.AssociatedExpr{offset, M.BinaryDispatch{}, "@result." ++ name, Nil{}, value, witness})
        case PrimitiveCall{ResultPrimitive{}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "@type.result requires a literal member name and one operand")}
        case PrimitiveCall{AssociatedPrimitive{}, head, member <> left <> right <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            name : String <- literal_argument(member)
            l : M.Expr <- lower(remaining, visit(left), context)
            r : M.Expr <- lower(remaining, visit(right), context)
            return located(offset, M.AssociatedExpr{offset, M.BinaryDispatch{}, name, Nil{}, l, r})
        case PrimitiveCall{AssociatedPrimitive{}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", "@type.call requires a literal member name and two operands")}
        case PrimitiveCall{EffectFamilyPrimitive{member, 1n, 1n}, head, operation <> operand <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            template : M.TypeId <- effect_template_name(operation, context)
            value : M.Expr <- lower(remaining, visit(operand), context)
            return located(offset, M.AssociatedExpr{offset, M.BinaryDispatch{}, member, [template], value, M.UnitExpr{}})
        case PrimitiveCall{EffectFamilyPrimitive{member, 2n, 2n}, head, read <> write <> initial <> action <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +reader : M.TypeId <- effect_template_name(read, context)
            +writer : M.TypeId <- effect_template_name(write, context)
            valid : Unit <- require_family_pair(context, reader, writer, head)
            value : M.Expr <- lower(remaining, visit(initial), context)
            body : M.Expr <- lower(remaining, visit(action), context)
            return located(offset, M.AssociatedExpr{offset, M.BinaryDispatch{}, member, [reader, writer], value, body})
        case PrimitiveCall{EffectFamilyPrimitive{member, 1n, 3n}, head, operation <> witness <> implementation <> action <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            template : M.TypeId <- effect_template_name(operation, context)
            subject : M.Expr <- lower(remaining, visit(witness), context)
            provider : M.Expr <- lower(remaining, visit(implementation), context)
            body : M.Expr <- lower(remaining, visit(action), context)
            return located(offset, M.AssociatedExpr{offset, M.BinaryDispatch{}, member, [template], subject, M.ProductExpr{[provider, body]}})
        case PrimitiveCall{EffectFamilyPrimitive{member, templates, operands}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", member ++ " requires " ++ Nat.show(Nat.add(templates, operands)) ++ " arguments")}
        case PrimitiveCall{DeferredPrimitive{member, 1n}, head, left <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            value : M.Expr <- lower(remaining, visit(left), context)
            return located(offset, M.AssociatedExpr{offset, M.BinaryDispatch{}, member, Nil{}, value, M.UnitExpr{}})
        case PrimitiveCall{DeferredPrimitive{member, 2n}, head, left <> right <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            a : M.Expr <- lower(remaining, visit(left), context)
            b : M.Expr <- lower(remaining, visit(right), context)
            return located(offset, M.AssociatedExpr{offset, M.BinaryDispatch{}, member, Nil{}, a, b})
        case PrimitiveCall{DeferredPrimitive{member, 3n}, head, witness <> implementation <> action <> Nil{}, +offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            w : M.Expr <- lower(remaining, visit(witness), context)
            i : M.Expr <- lower(remaining, visit(implementation), context)
            a : M.Expr <- lower(remaining, visit(action), context)
            return located(offset, M.AssociatedExpr{offset, M.BinaryDispatch{}, member, Nil{}, w, M.ProductExpr{[i, a]}})
        case PrimitiveCall{DeferredPrimitive{member, arity}, head, arguments, offset}:
          Fail{C.diagnostic(head, "call_arity", member ++ " requires " ++ Nat.show(arity) ++ " arguments")}
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
        case PrimitiveCall{ArrayGeneratePrimitive{}, head, count_node <> generator_node <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            count : M.Expr <- lower(remaining, visit(count_node), context)
            generator : M.Expr <- lower(remaining, visit(generator_node), context)
            return located(offset, M.ArrayGenerateExpr{count, generator})
        case PrimitiveCall{ArrayFillPrimitive{}, head, count_node <> value_node <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            count : M.Expr <- lower(remaining, visit(count_node), context)
            value : M.Expr <- lower(remaining, visit(value_node), context)
            return located(offset, M.ArrayFillExpr{count, value})
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
        case PrimitiveCall{StateProviderPrimitive{}, head, +read <> +write <> initial <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            valid_read : Unit <- require_unsealed_operation(foreign_argument(read), read)
            valid_write : Unit <- require_unsealed_operation(foreign_argument(write), write)
            read_value : M.Expr <- lower(remaining, visit(read), context)
            write_value : M.Expr <- lower(remaining, visit(write), context)
            +reader : OperationTarget <- operation_reference(read_value, read)
            +writer : OperationTarget <- operation_reference(write_value, write)
            value : M.Expr <- lower(remaining, visit(initial), context)
            return located(offset, wrap_operation_target(reader, wrap_operation_target(writer, M.StateProviderExpr{operation_target_identity(reader), operation_target_identity(writer), value})))
        case PrimitiveCall{ProviderPrimitive{}, head, +operation <> implementation <> Nil{}, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            valid : Unit <- require_unsealed_operation(foreign_argument(operation), operation)
            operation_value : M.Expr <- lower(remaining, visit(operation), context)
            +target : OperationTarget <- operation_reference(operation_value, operation)
            value : M.Expr <- lower(remaining, visit(implementation), context)
            return located(offset, wrap_operation_target(target, M.ProviderExpr{operation_target_identity(target), value}))
        case PrimitiveCall{OperationDescriptorPrimitive{}, head, +operation <> Nil{}, offset}:
          lower(remaining, DescriptorOperation{foreign_argument(operation), operation, offset}, context)
        case DescriptorOperation{True{}, operation, offset}:
          Done{located(offset, M.OperationDescriptorExpr{M.foreign_identity()})}
        case DescriptorOperation{False{}, +operation, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            operation_value : M.Expr <- lower(remaining, visit(operation), context)
            +target : OperationTarget <- operation_reference(operation_value, operation)
            return located(offset, wrap_operation_target(target, M.OperationDescriptorExpr{operation_target_identity(target)}))
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
        case ApplicationHead{Name{}, +head, arguments, offset}:
          Context{globals, headers, fixities, locals, label, annotation_variables} = context
          lower(remaining, ApplicationTemplate{template_reference(lookup_local(locals, C.name_of(head)), lookup_global(globals, C.name_of(head))), head, arguments, offset}, context)
        case ApplicationTemplate{Some{operation}, head, arguments, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            typed : TypedCall <- typed_operation_value(operation, arguments, remaining, context, head)
            lower(remaining, typed_call_work(typed, offset), context)
        case ApplicationTemplate{None{}, head, arguments, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            callee : M.Expr <- resolve_value(context, head)
            lower(remaining, Arguments{callee, arguments, offset}, context)
        case ApplicationHead{+kind, +head, +arguments, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            call : Maybe<&2, TypedCall> <- grouped_operation(remaining, OperationHead{kind, head}, arguments, context)
            lower(remaining, GroupedApplication{call, kind, head, arguments, offset}, context)
        case GroupedApplication{Some{call}, kind, head, arguments, offset}:
          lower(remaining, typed_call_work(call, offset), context)
        case GroupedApplication{None{}, kind, head, arguments, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            callee : M.Expr <- lower(remaining, Expression{kind, head}, context)
            lower(remaining, Arguments{callee, arguments, offset}, context)
        case Arguments{callee, Nil{}, offset}:
          Done{located(offset, callee)}
        case Arguments{callee, +head <> rest, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            argument : M.Expr <- lower(remaining, visit(head), context)
            lower(remaining, Arguments{instantiate_at(C.offset_of(head), 1n, O.invoke(callee, argument)), rest, offset}, context)
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
          +ordered = List.reverse(&2, SurfaceArm, arms)
          Done{finished_case(simple_arms(ordered), values, ordered)}
        case Arms{values, +node <> rest, arms}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +rows : List<&2, PatternRow> <- lower_arm_rows(C.field_values(node, "alternatives"), remaining, context)
            body_node : C.Cst <- C.one(C.field_values(node, "body"))
            body : M.Expr <- lower(remaining, visit(body_node), arm_scope(context, rows))
            lower(remaining, ArmGuard{values, rest, arms, rows, C.field_values(node, "guard"), body, node}, context)
        case ArmGuard{values, rest, arms, rows, Nil{}, body, node}:
          lower(remaining, Arms{values, rest, SurfaceArm{rows, False{}, M.BoolExpr{True{}}, body, C.offset_of(node)} <> arms}, context)
        case ArmGuard{values, rest, arms, +rows, guard_node <> Nil{}, body, node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            guard : M.Expr <- lower(remaining, visit(guard_node), arm_scope(context, rows))
            lower(remaining, Arms{values, rest, SurfaceArm{rows, True{}, guard, body, C.offset_of(node)} <> arms}, context)
        case ArmGuard{values, rest, arms, rows, guards, body, node}:
          Fail{C.diagnostic(node, "internal_cst", "invalid case guard")}
        case Expression{Block{}, +node}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            suite : C.Cst <- C.one(C.field_values(node, "body"))
            body : M.Expr <- lower(remaining, Statements{statement_nodes(suite), Nil{}}, block_scope(context, C.offset_of(node), C.present(C.field_values(node, "resolver"))))
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
        case Statements{Nil{}, carried}:
          Done{loop_value(local_values(carried))}
        case Statements{statement <> tail, carried}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +node : C.Cst <- C.one(C.field_values(statement, "value"))
            lower(remaining, Statement{classify(C.kind_of(node)), node, tail, carried}, context)
        case Statement{Binding{}, +node, tail, carried}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +scope : String = "$let$" ++ Nat.show(C.offset_of(node))
            +annotated : Context <- annotation_scope(node, context, scope)
            +pattern_node : C.Cst <- C.one(C.field_values(node, "pattern"))
            +pat : PatternResult <- lower_pattern(remaining, classify(C.kind_of(pattern_node)), pattern_node, context)
            +ty : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "annotation"), remaining, annotated)
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            value : M.Expr <- lower(remaining, visit(value_node), annotated)
            qualified : M.Expr <- where_clause(ty, C.field_values(node, "where"), value, remaining, annotated, scope)
            otherwise : List<&2, C.Cst> <- else_statements(C.field_values(node, "fallback"))
            alternative : M.Expr <- lower(remaining, Statements{otherwise, Nil{}}, context)
            body : M.Expr <- lower(remaining, Statements{tail, carried}, pattern_scope(context, pat))
            old_annotation : Maybe<&2, M.Ty> = Bool.pick(Maybe<&2, M.Ty>, C.present(C.field_values(node, "where")), None{}, ty)
            return located(C.offset_of(node), binding(C.present(C.field_values(node, "fallback")), pattern_of(pat), M.SourceExpr{C.offset_of(node), old_annotation, qualified}, alternative, body, C.offset_of(node)))
        case Statement{ForLoop{}, +node, tail, carried}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +pat : PatternResult <- loop_pattern(remaining, C.field_values(node, "pattern"), context)
            +suite : C.Cst <- C.one(C.field_values(node, "body"))
            targets : Set() <- loop_targets(remaining, LoopTargets{statement_nodes(suite)}, context, shadow_names(pattern_locals(pat), Set.new()), Set.new())
            +originals : List<&2, Local> <- Done{loop_locals(context, targets)}
            +prefix : String <- Done{"$for$" ++ Nat.show(C.offset_of(node)) ++ "$"}
            +versions : List<&2, Local> <- Done{loop_versions(originals, prefix)}
            +scope : Context <- Done{bind_all(versions, context)}
            +successors : List<&2, Local> <- Done{loop_versions(originals, prefix ++ "next$")}
            body : M.Expr <- lower(remaining, Statements{statement_nodes(suite), versions}, pattern_scope(scope, pat))
            next : M.Expr <- lower(remaining, Statements{tail, loop_carried(originals, successors, carried)}, bind_all(successors, context))
            +single : Bool <- Done{Nat.is_eq(List.length(&2, Local, versions), 1n)}
            loop : M.Expr <- lower(remaining, ForStart{M.name_equal(C.kind_of(node), "ever_statement"), node, pattern_of(pat), loop_value(local_values(originals)), loop_bindings(versions, prefix ++ "state", 0n, single, body), prefix}, context)
            return located(C.offset_of(node), M.UseExpr{prefix ++ "result", loop, loop_bindings(successors, prefix ++ "result", 0n, single, next)})
        case ForStart{True{}, node, pattern, initial, body, +prefix}:
          Done{M.ForeverExpr{prefix ++ "state", initial, body}}
        case ForStart{False{}, +node, pattern, initial, body, +prefix}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            start_node : C.Cst <- C.one(C.field_values(node, "start"))
            start : M.Expr <- lower(remaining, visit(start_node), context)
            lower(remaining, ForRange{C.field_values(node, "end"), pattern, start, initial, body, prefix, C.offset_of(node)}, context)
        case ForRange{Nil{}, pattern, array, initial, body, +prefix, offset}:
          Done{M.UseExpr{prefix ++ "array", array, M.ForExpr{prefix ++ "index", M.U32Expr{0}, M.ArrayLengthExpr{M.LocalExpr{prefix ++ "array"}}, prefix ++ "state", initial, plain_binding(pattern, M.ArrayGetExpr{M.LocalExpr{prefix ++ "array"}, M.LocalExpr{prefix ++ "index"}}, body, offset)}}}
        case ForRange{end_node <> Nil{}, pattern, start, initial, body, +prefix, offset}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            end : M.Expr <- lower(remaining, visit(end_node), context)
            return M.ForExpr{prefix ++ "index", start, end, prefix ++ "state", initial, plain_binding(pattern, M.LocalExpr{prefix ++ "index"}, body, offset)}
        case ForRange{nodes, pattern, start, initial, body, prefix, offset}:
          Fail{M.Diagnostic{"internal_cst", "for", "invalid range endpoint"}}
        case Statement{Rebinding{}, +node, tail, carried}:
          Context{globals, headers, fixities, locals, label, annotation_variables} = context
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +name : C.Cst <- C.one(C.field_values(node, "name"))
            +scope : Context <- rebinding_scope(lookup_local(locals, C.text_of(name)), context, name)
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            receiver : M.Expr <- self_value(scope)
            value : M.Expr <- lower(remaining, UpdatePath{receiver, C.field_values(node, "path"), value_node, C.offset_of(node)}, scope)
            body : M.Expr <- lower(remaining, Statements{tail, successor_carried(carried, lookup_local(locals, C.text_of(name)), unique_name(name))}, bind(context, Local{C.text_of(name), unique_name(name)}))
            return located(C.offset_of(node), M.LetExpr{unique_name(name), value, body})
        case UpdatePath{M.LocalExpr{core}, Nil{}, value_node, offset}:
          lower(remaining, visit(value_node), bind(context, Local{"self", core}))
        case UpdatePath{receiver, Nil{}, value_node, offset}:
          +name = "$update$self$" ++ Nat.show(offset)
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +value : M.Expr <- lower(remaining, visit(value_node), bind(context, Local{"self", name}))
            return terminal_update_value(receiver, name, value)
        case UpdatePath{receiver, +node <> tail, value, offset}:
          lower(remaining, UpdateSelector{C.kind_of(node), receiver, node, tail, value, offset}, context)
        case UpdateSelector{"member_access", receiver, +node, tail, value_node, offset}:
          +parent = "$update$parent$" ++ Nat.show(C.offset_of(node))
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +name : C.Cst <- C.one(C.field_values(node, "name"))
            value : M.Expr <- lower(remaining, UpdatePath{M.AssociatedExpr{C.offset_of(name), M.MemberDispatch{}, C.text_of(name), Nil{}, M.LocalExpr{parent}, M.UnitExpr{}}, tail, value_node, offset}, context)
            return M.UseExpr{parent, receiver, located(C.offset_of(node), M.AssociatedExpr{C.offset_of(node), M.FieldUpdateDispatch{}, C.text_of(name), Nil{}, M.LocalExpr{parent}, value})}
        case UpdateSelector{"index_access", receiver, +node, tail, value_node, offset}:
          +parent = "$update$parent$" ++ Nat.show(C.offset_of(node))
          +index_name = "$update$index$" ++ Nat.show(C.offset_of(node))
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            index_node : C.Cst <- C.one(C.field_values(node, "index"))
            index : M.Expr <- lower(remaining, visit(index_node), context)
            value : M.Expr <- lower(remaining, UpdatePath{M.ArrayGetExpr{M.LocalExpr{parent}, M.LocalExpr{index_name}}, tail, value_node, offset}, context)
            return M.UseExpr{parent, receiver, M.UseExpr{index_name, index, located(C.offset_of(node), M.ArraySetExpr{M.LocalExpr{parent}, M.LocalExpr{index_name}, value})}}
        case UpdateSelector{kind, receiver, node, tail, value, offset}:
          Fail{C.diagnostic(node, "internal_cst", "unknown update selector")}
        case Statement{EffectBinding{}, +node, tail, carried}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +target : Local <- effect_target(C.field_values(node, "name"), C.offset_of(node))
            ty : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "annotation"), remaining, context)
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            value : M.Expr <- lower(remaining, visit(value_node), context)
            body : M.Expr <- lower(remaining, Statements{tail, carried}, bind(context, target))
            return located(C.offset_of(node), effect_binding(target, M.SourceExpr{C.offset_of(node), ty, value}, body))
        case Statement{Return{}, +node, tail, carried}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            valid : Unit <- reachable(tail)
            plain : Unit <- require_resolved_return(C.field_values(node, "forwarding"), has_resolver(context))
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            value : M.Expr <- lower(remaining, visit(value_node), context)
            result : M.Expr <- returning(context, forwarded(context, C.present(C.field_values(node, "forwarding")), value, C.offset_of(node)), node)
            return located(C.offset_of(node), result)
        case Statement{Conditional{}, +node, tail, carried}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            test : C.Cst <- C.one(C.field_values(node, "condition"))
            yes : C.Cst <- C.one(C.field_values(node, "consequence"))
            no : List<&2, C.Cst> <- else_statements(C.field_values(node, "fallback"))
            targets : Set() <- loop_targets(remaining, LoopTarget{Conditional{}, node, Nil{}}, context, Set.new(), Set.new())
            +originals : List<&2, Local> = loop_locals(context, targets)
            +prefix : String = "$if$" ++ Nat.show(C.offset_of(node)) ++ "$"
            +successors : List<&2, Local> = loop_versions(originals, prefix)
            condition : M.Expr <- lower(remaining, visit(test), context)
            consequent : M.Expr <- lower(remaining, Statements{statement_nodes(yes), originals}, context)
            alternative : M.Expr <- lower(remaining, Statements{no, originals}, context)
            next : M.Expr <- lower(remaining, Statements{tail, loop_carried(originals, successors, carried)}, bind_all(successors, context))
            return conditional_successors(successors, prefix, located(C.offset_of(node), M.IfExpr{condition, consequent, alternative}), next)
        case Statement{PatternConditional{}, +node, tail, carried}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            +pattern_node : C.Cst <- C.one(C.field_values(node, "pattern"))
            +pat : PatternResult <- lower_pattern(remaining, classify(C.kind_of(pattern_node)), pattern_node, context)
            value_node : C.Cst <- C.one(C.field_values(node, "value"))
            yes : C.Cst <- C.one(C.field_values(node, "consequence"))
            no : List<&2, C.Cst> <- else_statements(C.field_values(node, "fallback"))
            targets : Set() <- loop_targets(remaining, LoopTarget{PatternConditional{}, node, Nil{}}, context, Set.new(), Set.new())
            +originals : List<&2, Local> = loop_locals(context, targets)
            +prefix : String = "$if$" ++ Nat.show(C.offset_of(node)) ++ "$"
            +successors : List<&2, Local> = loop_versions(originals, prefix)
            value : M.Expr <- lower(remaining, visit(value_node), context)
            consequent : M.Expr <- lower(remaining, Statements{statement_nodes(yes), originals}, pattern_scope(context, pat))
            alternative : M.Expr <- lower(remaining, Statements{no, originals}, context)
            next : M.Expr <- lower(remaining, Statements{tail, loop_carried(originals, successors, carried)}, bind_all(successors, context))
            branch : M.Expr = M.LetExpr{prefix ++ "value", value, M.MatchExpr{[M.LocalExpr{prefix ++ "value"}], [M.MatchArm{[pattern_of(pat)], consequent}, M.MatchArm{[M.WildcardPattern{}], alternative}]}}
            return conditional_successors(successors, prefix, located(C.offset_of(node), branch), next)
        case Statement{kind, node, tail, carried}:
          do Result<&2, &2, M.Diagnostic, M.Expr>:
            first : M.Expr <- lower(remaining, Expression{kind, node}, context)
            next : M.Expr <- lower(remaining, Statements{tail, carried}, context)
            return M.SequenceExpr{first, next}

def declaration_name(node: C.Cst) -> Result<&2, &2, M.Diagnostic, String>:
  do Result<&2, &2, M.Diagnostic, String>:
    +name : C.Cst <- C.one(C.field_values(node, "name"))
    return Bool.pick(String, M.name_equal(C.kind_of(name), "qualified_name"), C.name_of(name), C.text_of(name))

def require_fresh(found: Maybe<&2, Global>, context: Context, global: Global, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Context>:
  match found context global:
    case None{} Context{globals, headers, fixities, locals, label, annotation_variables} Global{+source, core, kind}:
      Done{Context{Index.set(Global, globals, source, Global{source, core, kind}), headers, fixities, locals, label, annotation_variables}}
    case _ _ _:
      Fail{C.diagnostic(node, "duplicate_name", "duplicate value or constructor declaration")}

def add_global(+context: Context, +source: String, core: String, kind: GlobalKind, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Context>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  require_fresh(lookup_global(globals, source), context, Global{source, core, kind}, node)

def add_header(found: Maybe<&2, T.Header>, context: Context, header: T.Header, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Context>:
  match found context header:
    case None{} Context{globals, headers, fixities, locals, label, annotation_variables} T.Header{+source, identity, parameters}:
      Done{Context{globals, Index.set(T.Header, headers, source, T.Header{source, identity, parameters}), fixities, locals, label, annotation_variables}}
    case _ _ _:
      Fail{C.diagnostic(node, "duplicate_type", "duplicate type declaration")}

# The same record syntax describes a constructor payload and a type argument.
# Only a record directly at the payload root declares named constructor fields.
def constructor_fields(fuel: Nat, nodes: List<&2, C.Cst>) -> List<&2, C.Cst>:
  match fuel nodes:
    case 1n+rest +node <> Nil{}:
      Bool.pick(List<&2, C.Cst>, M.name_equal(C.kind_of(node), "type_record"), [node], constructor_fields(rest, C.children_of(node)))
    case _ _:
      Nil{}

def collect_constructors(nodes: List<&2, C.Cst>, +prefix: String, context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match nodes:
    case Nil{}:
      Done{context}
    case +node <> rest:
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        kind : GlobalKind <- record_kind(constructor_fields(65536n, C.field_values(node, "payload")))
        next : Context <- add_global(context, name, prefix ++ name, kind, node)
        collect_constructors(rest, prefix, next)

def effect_member_nodes(nodes: List<&2, C.Cst>) -> List<&2, C.Cst>:
  match nodes:
    case Nil{}:
      Nil{}
    case group <> Nil{}:
      C.field_values(group, "fields")
    case _:
      Nil{}

def effect_member_identities(nodes: List<&2, C.Cst>, +family: String, +module_name: String) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +node <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        +name : String <- declaration_name(node)
        +following : List<&2, M.TypeId> <- effect_member_identities(rest, family, module_name)
        return M.TypeId{module_name, family ++ "." ++ name} <> following

def operation_kind(identity: M.TypeId, parameters: List<&2, A.Pattern>) -> GlobalKind:
  match parameters:
    case Nil{}:
      OperationName{identity}
    case _:
      OperationTemplateName{identity, parameters}

def collect_effect_members(nodes: List<&2, C.Cst>, +family: String, +prefix: String, +module_name: String, +parameters: List<&2, A.Pattern>, context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match nodes:
    case Nil{}:
      Done{context}
    case +node <> rest:
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        +source : String <- Done{family ++ "." ++ name}
        +identity : M.TypeId <- Done{M.TypeId{module_name, source}}
        next : Context <- add_global(context, source, prefix ++ source, operation_kind(identity, parameters), node)
        collect_effect_members(rest, family, prefix, module_name, parameters, next)

def collect_effect_type_body(groups: List<&2, C.Cst>, +name: String, +prefix: String, +module_name: String, +parameters: List<&2, A.Pattern>, +node: C.Cst, with_header: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match groups:
    case Nil{}:
      add_global(with_header, name, prefix ++ name, operation_kind(M.TypeId{module_name, name}, parameters), node)
    case groups:
      do Result<&2, &2, M.Diagnostic, Context>:
        +members : List<&2, C.Cst> <- Done{effect_member_nodes(groups)}
        identities : List<&2, M.TypeId> <- effect_member_identities(members, name, module_name)
        with_family : Context <- add_global(with_header, name, prefix ++ name, EffectFamilyName{identities, parameters}, node)
        collect_effect_members(members, name, prefix, module_name, parameters, with_family)

def valid_effect_name(reserved: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match reserved:
    case True{}:
      Fail{C.diagnostic(node, "sealed_effect", "Foreign is reserved for the compiler's host-call effect label")}
    case False{}:
      Done{Unit{}}

def collect_effect_type(+node: C.Cst, +prefix: String, +module_name: String, +context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  Context{globals, +headers, fixities, locals, label, annotation_variables} = context
  do Result<&2, &2, M.Diagnostic, Context>:
    +name : String <- declaration_name(node)
    valid : Unit <- valid_effect_name(M.name_equal(name, "Foreign"), node)
    +parameters : List<&2, A.Pattern> <- A.parameters(node)
    +identity : M.TypeId <- Done{M.TypeId{module_name, name}}
    with_header : Context <- add_header(T.lookup_header(headers, name), context, T.Header{name, identity, parameters}, node)
    collect_effect_type_body(C.field_values(node, "operations"), name, prefix, module_name, parameters, node, with_header)

def declaration_lambda_children(kind: NodeKind, +node: C.Cst) -> List<&2, C.Cst>:
  match kind:
    case ApplicationNode{}:
      Bool.pick(List<&2, C.Cst>, List.is_empty(&2, C.Cst, C.field_values(node, "arguments")), C.field_values(node, "head"), Nil{})
    case kind:
      application_children(kind, node)

type DeclarationInitializer is Data:
  InitializerNode{kind: NodeKind, node: C.Cst}
  InitializerChildren{nodes: List<&2, C.Cst>}

def declaration_lambda(fuel: Nat, work: DeclarationInitializer) -> Result<&2, &2, M.Diagnostic, Maybe<&2, C.Cst>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"internal_cst", "parser", "value initializer exceeds the source-tree limit"}}
    case 1n+rest InitializerNode{LambdaNode{}, node}:
      Done{Some{node}}
    case 1n+rest InitializerNode{kind, node}:
      declaration_lambda(rest, InitializerChildren{declaration_lambda_children(kind, node)})
    case 1n+rest InitializerChildren{+node <> Nil{}}:
      declaration_lambda(rest, InitializerNode{classify(C.kind_of(node)), node})
    case _ _:
      Done{None{}}

def named_declaration(kind: NodeKind, +node: C.Cst, attributes: List<&2, C.Cst>, +prefix: String, module_name: String, +context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match kind:
    case ValueDeclaration{}:
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        +initializer : C.Cst <- C.one(C.field_values(node, "value"))
        function : Maybe<&2, C.Cst> <- declaration_lambda(65536n, InitializerChildren{[initializer]})
        kind : GlobalKind = Bool.pick(GlobalKind, Bool.and(Maybe.is_some(&2, C.Cst, function), List.is_empty(&2, C.Cst, attributes)), FunctionName{}, ConstantName{})
        add_global(context, name, prefix ++ name, kind, node)
    case EffectNode{}:
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        valid : Unit <- valid_effect_name(M.name_equal(name, "Foreign"), node)
        add_global(context, name, prefix ++ name, OperationName{M.TypeId{module_name, name}}, node)
    case EffectTypeNode{}:
      collect_effect_type(node, prefix, module_name, context)
    case DataNode{}:
      Context{globals, +headers, fixities, locals, label, annotation_variables} = context
      do Result<&2, &2, M.Diagnostic, Context>:
        +name : String <- declaration_name(node)
        parameters : List<&2, A.Pattern> <- A.parameters(node)
        next : Context <- add_header(T.lookup_header(headers, name), context, T.Header{name, M.TypeId{module_name, name}, parameters}, node)
        collect_constructors(C.field_values(node, "constructors"), prefix, next)
    case _:
      Done{context}

def collect_names(nodes: List<&2, C.Cst>, +prefix: String, +module_name: String) -> Result<&2, &2, M.Diagnostic, Context>:
  match nodes:
    case Nil{}:
      Done{Context{MTip{}, MTip{}, Nil{}, Nil{}, None{}, Nil{}}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, Context>:
        +node : C.Cst <- C.one(C.field_values(head, "value"))
        rest : Context <- collect_names(tail, prefix, module_name)
        named_declaration(classify(C.kind_of(node)), node, C.field_values(head, "attributes"), prefix, module_name, rest)

def combine_context(own: Context, inherited: Context) -> Context:
  Context{globals, headers, fixities, locals, label, annotation_variables} = own
  Context{base_globals, base_headers, base_fixities, base_locals, base_label, base_annotation_variables} = inherited
  Context{Map.union(&2, Global, base_globals, globals), Map.union(&2, T.Header, base_headers, headers), List.append(&2, O.Fixity, fixities, base_fixities), locals, label, annotation_variables}

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
  Context{globals, headers, base_fixities, locals, label, annotation_variables} = context
  Context{globals, headers, List.append(&2, O.Fixity, fixities, base_fixities), locals, label, annotation_variables}

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

def tag_lowered(value: Result<&2, &2, M.Diagnostic, M.Expr>, tag: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match value:
    case Done{expression}:
      Done{expression}
    case Fail{M.Diagnostic{code, subject, message}}:
      Fail{C.diagnostic(tag, code, message)}

def tag_body(value: Result<&2, &2, M.Diagnostic, C.Cst>, tag: C.Cst, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match value:
    case Fail{error}:
      Fail{error}
    case Done{expression}:
      tag_lowered(lower(fuel, visit(expression), context), tag)

def tag_expression_body(value: Result<&2, &2, M.Diagnostic, C.Cst>, tag: C.Cst, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match value:
    case Fail{error}:
      Fail{error}
    case Done{body}:
      tag_body(C.one(C.field_values(body, "value")), tag, fuel, context)

def tag_expression(+tag: C.Cst, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  tag_expression_body(C.one(C.field_values(tag, "body")), tag, fuel, context)

# Recurse through the source-ordered list first: the nearest tag runs first.
# TagExpr carries an explicit origin through inference and const evaluation.
def tag_application(offset: Nat, function: M.Expr, value: M.Expr) -> M.Expr:
  M.TagExpr{offset, function, value}

def apply_tags(tags: List<&2, C.Cst>, value: M.Expr, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match tags:
    case Nil{}:
      Done{value}
    case +tag <> tail:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        inner : M.Expr <- apply_tags(tail, value, fuel, context)
        function : M.Expr <- tag_expression(tag, fuel, context)
        return tag_application(C.offset_of(tag), function, inner)

def reject_recursive_tag_found(found: Bool, tag: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case True{}:
      Fail{C.diagnostic(tag, "recursive_tag", "a tagged declaration cannot refer to its own bound name")}
    case False{}:
      Done{Unit{}}

def reject_recursive_tag(tags: List<&2, C.Cst>, name: String, value: M.Expr) -> Result<&2, &2, M.Diagnostic, Unit>:
  match tags:
    case Nil{}:
      Done{Unit{}}
    case tag <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        refs : D.References <- D.references(65536n, D.Expression{value})
        reject_recursive_tag_found(D.contains(D.names_of(refs), name), tag)

# An exported qualified declaration is itself a concrete host use. Lane 3 is
# reserved for that root; ordinary references and calls use lanes 0-2.
def qualified_root(exported: Bool, constrained: Bool, offset: Nat, value: M.Expr) -> M.Expr:
  match exported constrained:
    case True{} True{}:
      instantiate_at(offset, 3n, value)
    case _ _:
      value

def lower_constant(+node: C.Cst, +attributes: List<&2, C.Cst>, +name: String, +exported: Bool, +fuel: Nat, base_context: Context) -> Result<&2, &2, M.Diagnostic, M.Constant>:
  do Result<&2, &2, M.Diagnostic, M.Constant>:
    +context : Context <- annotation_scope(node, base_context, name)
    +ty : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "annotation"), fuel, context)
    value_node : C.Cst <- C.one(C.field_values(node, "value"))
    +initial : M.Expr <- lower(fuel, visit(value_node), context)
    +value : M.Expr <- apply_tags(attributes, initial, fuel, context)
    valid : Unit <- reject_recursive_tag(attributes, name, value)
    +qualified : M.Expr <- where_clause(ty, C.field_values(node, "where"), value, fuel, context, name)
    keyword : C.Cst <- C.one(C.field_values(node, "kind"))
    old_annotation : Maybe<&2, M.Ty> = Bool.pick(Maybe<&2, M.Ty>, C.present(C.field_values(node, "where")), None{}, ty)
    +root : M.Expr = qualified_root(exported, C.present(C.field_values(node, "where")), C.offset_of(node), qualified)
    return M.Constant{name, exported, old_annotation, Bool.pick(M.Expr, M.name_equal(C.text_of(keyword), "let"), M.RuntimeInitExpr{root}, root)}

def annotated_function(annotation: Maybe<&2, M.Ty>, function: M.Function, +node: C.Cst) -> M.Function:
  match annotation function:
    case None{} function:
      function
    case Some{ty} M.Function{name, exported, +parameter, p, r, body}:
      +offset = C.offset_of(node)
      M.Function{name, exported, parameter, None{}, None{}, M.ApplyExpr{M.SourceExpr{offset, Some{ty}, M.LambdaExpr{Nat.mul(offset, 16n), parameter, p, r, body}}, M.LocalExpr{parameter}}}

def qualified_function(annotation: Maybe<&2, M.Ty>, function: M.Function, +node: C.Cst, fuel: Nat, context: Context, scope: String) -> Result<&2, &2, M.Diagnostic, M.Function>:
  match function:
    case M.Function{name, +exported, +parameter, p, r, body}:
      do Result<&2, &2, M.Diagnostic, M.Function>:
        +offset : Nat = C.offset_of(node)
        qualified : M.Expr <- where_clause(annotation, C.field_values(node, "where"), M.LambdaExpr{Nat.mul(offset, 16n), parameter, p, r, body}, fuel, context, scope)
        return M.Function{name, exported, parameter, None{}, None{}, M.ApplyExpr{qualified_root(exported, True{}, offset, qualified), M.LocalExpr{parameter}}}

def binding_function_found(found: Bool, annotation: Maybe<&2, M.Ty>, function: M.Function, node: C.Cst, fuel: Nat, context: Context, scope: String) -> Result<&2, &2, M.Diagnostic, M.Function>:
  match found:
    case True{}:
      qualified_function(annotation, function, node, fuel, context, scope)
    case False{}:
      Done{annotated_function(annotation, function, node)}

def binding_function(annotation: Maybe<&2, M.Ty>, function: M.Function, +node: C.Cst, fuel: Nat, context: Context, scope: String) -> Result<&2, &2, M.Diagnostic, M.Function>:
  binding_function_found(C.present(C.field_values(node, "where")), annotation, function, node, fuel, context, scope)

def value_function_phase(runtime: Bool, function: M.Function) -> M.Function:
  match runtime function:
    case False{} function:
      function
    case True{} M.Function{name, exported, parameter, p, r, body}:
      M.Function{name, exported, parameter, p, r, M.RuntimeInitExpr{body}}

def lower_value_function(+binding: C.Cst, node: C.Cst, +name: String, exported: Bool, +fuel: Nat, base_context: Context) -> Result<&2, &2, M.Diagnostic, M.Function>:
  do Result<&2, &2, M.Diagnostic, M.Function>:
    +context : Context <- annotation_scope(binding, base_context, name)
    annotation : Maybe<&2, M.Ty> <- source_annotation(C.field_values(binding, "annotation"), fuel, context)
    function : M.Function <- lower_function(node, name, exported, fuel, context)
    keyword : C.Cst <- C.one(C.field_values(binding, "kind"))
    qualified : M.Function <- binding_function(annotation, function, binding, fuel, context, name)
    return value_function_phase(M.name_equal(C.text_of(keyword), "let"), qualified)

def require_parameter(found: Maybe<&2, M.Ty>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case _:
      Fail{C.diagnostic(node, "duplicate_type_parameter", "duplicate type parameter")}

def named_type_variables(names: List<&2, String>, +index: Nat, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
        +rest : List<&2, T.Variable> <- named_type_variables(tail, 1n+index, node)
        valid : Unit <- require_parameter(T.lookup_variable(rest, name), node)
        return T.Variable{name, M.ParameterTy{index}, T.TypeKind{}} <> rest

def type_variables(+node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
  do Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
    patterns : List<&2, A.Pattern> <- A.parameters(node)
    names : List<&2, String> <- A.binding_names(65536n, patterns)
    named_type_variables(names, 0n, node)

def record_annotation(nodes: List<&2, C.Cst>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match nodes:
    case Nil{}:
      C.one(C.field_values(node, "name"))
    case nodes:
      C.one(nodes)

def lower_record_types(nodes: List<&2, C.Cst>, reversed: List<&2, M.Ty>, +fuel: Nat, +headers: Map<&2, T.Header>, +variables: List<&2, T.Variable>, +globals: Map<&2, Global>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match nodes:
    case Nil{}:
      Done{List.reverse(&2, M.Ty, reversed)}
    case +node <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        ty_node : C.Cst <- record_annotation(C.field_values(node, "value"), node)
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

def constructor_field_names(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case node <> Nil{}:
      record_field_names(C.field_values(node, "fields"), Set.new(), Nil{})
    case _:
      Fail{M.Diagnostic{"internal_cst", "record", "invalid constructor record fields"}}

def lower_constructors(nodes: List<&2, C.Cst>, +prefix: String, +fuel: Nat, +headers: Map<&2, T.Header>, +variables: List<&2, T.Variable>, +globals: Map<&2, Global>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Constructor>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Constructor>>:
        name : String <- declaration_name(node)
        payload : Maybe<&2, M.Ty> <- constructor_payload(constructor_fields(65536n, C.field_values(node, "payload")), C.field_values(node, "payload"), fuel, headers, variables, globals)
        fields : List<&2, String> <- constructor_field_names(constructor_fields(65536n, C.field_values(node, "payload")))
        rest : List<&2, M.Constructor> <- lower_constructors(tail, prefix, fuel, headers, variables, globals)
        return M.Constructor{prefix ++ name, payload, fields} <> rest

def lower_data(+node: C.Cst, name: String, prefix: String, module_name: String, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.DataType>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  do Result<&2, &2, M.Diagnostic, M.DataType>:
    +variables : List<&2, T.Variable> <- type_variables(node)
    constructors : List<&2, M.Constructor> <- lower_constructors(C.field_values(node, "constructors"), prefix, fuel, headers, variables, globals)
    return M.DataType{M.TypeId{module_name, name}, List.length(&2, T.Variable, variables), constructors}

def operation_signature(signature: Maybe<&2, M.Ty>, identity: M.TypeId, parameters: Maybe<&2, Nat>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match signature:
    case Some{M.FunctionTy{parameter, result, M.EffectRow{Nil{}, M.ClosedRow{}}}}:
      match parameters:
        case None{}:
          Done{M.Operation{identity, parameter, result}}
        case Some{count}:
          Done{M.OperationTemplate{identity, count, parameter, result}}
    case Some{M.FunctionTy{parameter, result, row}}:
      Fail{C.diagnostic(node, "operation_signature", "an operation declaration specifies parameter and result types, not an outer latent effect row")}
    case _:
      Fail{C.diagnostic(node, "operation_signature", "an effect operation requires a unary signature: Parameter -> Result")}

def lower_operation(+node: C.Cst, identity: M.TypeId, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  do Result<&2, &2, M.Diagnostic, M.Operation>:
    signature : Maybe<&2, M.Ty> <- source_annotation(C.field_values(node, "signature"), fuel, context)
    operation_signature(signature, identity, None{}, node)

def lower_effect_signature(+node: C.Cst, identity: M.TypeId, +variables: List<&2, T.Variable>, fuel: Nat, context: Context, parameters: Maybe<&2, Nat>) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  Context{globals, headers, fixities, locals, label, annotation_variables} = context
  do Result<&2, &2, M.Diagnostic, M.Operation>:
    signature : Maybe<&2, M.Ty> <- T.annotation(~Map<&2, Global>, ~lookup_effect, C.field_values(node, "signature"), fuel, headers, variables, globals)
    operation_signature(signature, identity, parameters, node)

def lower_effect_members(nodes: List<&2, C.Cst>, +family: String, +module_name: String, +variables: List<&2, T.Variable>, +fuel: Nat, +context: Context, +parameters: Maybe<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +node <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
        +name : String <- declaration_name(node)
        operation : M.Operation <- lower_effect_signature(node, M.TypeId{module_name, family ++ "." ++ name}, variables, fuel, context, parameters)
        following : List<&2, M.Operation> <- lower_effect_members(rest, family, module_name, variables, fuel, context, parameters)
        return operation <> following

def lower_effect_type_members(members: List<&2, C.Cst>, node: C.Cst, name: String, module_name: String, variables: List<&2, T.Variable>, fuel: Nat, context: Context, parameters: Maybe<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match members:
    case Nil{}:
      Fail{C.diagnostic(node, "empty_effect", "an effect group requires at least one operation")}
    case _:
      lower_effect_members(members, name, module_name, variables, fuel, context, parameters)

def lower_effect_type_body(groups: List<&2, C.Cst>, +node: C.Cst, name: String, module_name: String, variables: List<&2, T.Variable>, fuel: Nat, context: Context, parameters: Maybe<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match groups:
    case Nil{}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
        operation : M.Operation <- lower_effect_signature(node, M.TypeId{module_name, name}, variables, fuel, context, parameters)
        return [operation]
    case _:
      lower_effect_type_members(effect_member_nodes(groups), node, name, module_name, variables, fuel, context, parameters)

def lower_effect_type(+node: C.Cst, +name: String, +module_name: String, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  do Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
    +variables : List<&2, T.Variable> <- type_variables(node)
    parameters : Maybe<&2, Nat> = Bool.pick(Maybe<&2, Nat>, C.present(C.field_values(node, "parameters")), Some{List.length(&2, T.Variable, variables)}, None{})
    lower_effect_type_body(C.field_values(node, "operations"), node, name, module_name, variables, fuel, context, parameters)

def add_operation(module: M.Module, operation: M.Operation) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constants, functions, data_types, operation <> operations}

def add_operations(module: M.Module, incoming: List<&2, M.Operation>) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constants, functions, data_types, List.append(&2, M.Operation, incoming, operations)}

def add_function(module: M.Module, fn: M.Function) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constants, fn <> functions, data_types, operations}

def add_constant(module: M.Module, constant: M.Constant) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constant <> constants, functions, data_types, operations}

def add_data(module: M.Module, ty: M.DataType) -> M.Module:
  M.Module{constants, functions, data_types, operations} = module
  M.Module{constants, functions, ty <> data_types, operations}

def lower_value_declaration(function: Maybe<&2, C.Cst>, node: C.Cst, attributes: List<&2, C.Cst>, name: String, exported: Bool, rest: M.Module, fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match function:
    case Some{lambda}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        value : M.Function <- lower_value_function(node, lambda, name, exported, fuel, context)
        return add_function(rest, value)
    case None{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        value : M.Constant <- lower_constant(node, attributes, name, exported, fuel, context)
        return add_constant(rest, value)

# `entry` is a contextual keyword: the grammar accepts any identifier before
# `const` or `let`, and only `entry` is a declaration modifier. It marks a host
# entrypoint (a Wasm export and a dead-code root), so it belongs to the entry
# module; it never changes which declarations other Blot modules may import.
def entry_modifier(entry: Bool, entry_module: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, Bool>:
  match entry entry_module:
    case False{} _:
      Fail{C.diagnostic(node, "unknown_modifier", "only `entry` may precede `const` or `let`")}
    case True{} True{}:
      Done{True{}}
    case True{} False{}:
      Fail{C.diagnostic(node, "entry_outside_entry_module", "`entry` marks a host entrypoint and is only allowed in the entry module; other modules' declarations stay importable without it")}

def declaration_modifier(modifiers: List<&2, C.Cst>, entry_module: Bool) -> Result<&2, &2, M.Diagnostic, Bool>:
  match modifiers:
    case Nil{}:
      Done{False{}}
    case +node <> Nil{}:
      entry_modifier(M.name_equal(C.text_of(node), "entry"), entry_module, node)
    case node <> tail:
      Fail{C.diagnostic(node, "internal_cst", "a declaration has at most one modifier")}

def reject_attributes(attributes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match attributes:
    case Nil{}:
      Done{Unit{}}
    case node <> tail:
      Fail{C.diagnostic(node, "unsupported_attribute", "expression tags apply only to const and let declarations")}

def declaration(kind: NodeKind, +node: C.Cst, +attributes: List<&2, C.Cst>, +prefix: String, module_name: String, entry_module: Bool, rest: M.Module, +fuel: Nat, context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match kind:
    case ValueDeclaration{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +name : String <- declaration_name(node)
        entry : Bool <- declaration_modifier(C.field_values(node, "modifier"), entry_module)
        initializer : C.Cst <- C.one(C.field_values(node, "value"))
        function : Maybe<&2, C.Cst> <- declaration_lambda(fuel, InitializerChildren{[initializer]})
        lower_value_declaration(Bool.pick(Maybe<&2, C.Cst>, List.is_empty(&2, C.Cst, attributes), function, None{}), node, attributes, prefix ++ name, entry, rest, fuel, context)
    case EffectNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        valid : Unit <- reject_attributes(attributes)
        name : String <- declaration_name(node)
        operation : M.Operation <- lower_operation(node, M.TypeId{module_name, name}, fuel, context)
        return add_operation(rest, operation)
    case EffectTypeNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        valid : Unit <- reject_attributes(attributes)
        name : String <- declaration_name(node)
        operations : List<&2, M.Operation> <- lower_effect_type(node, name, module_name, fuel, context)
        return add_operations(rest, operations)
    case DataNode{}:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        valid : Unit <- reject_attributes(attributes)
        name : String <- declaration_name(node)
        ty : M.DataType <- lower_data(node, name, prefix, module_name, fuel, context)
        return add_data(rest, ty)
    case _:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        valid : Unit <- reject_attributes(attributes)
        return rest


def lower_declarations_sequential(nodes: List<&2, C.Cst>, +prefix: String, +module_name: String, +entry_module: Bool, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match nodes:
    case Nil{}:
      Done{M.Module{Nil{}, Nil{}, Nil{}, Nil{}}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, M.Module>:
        +node : C.Cst <- C.one(C.field_values(head, "value"))
        rest : M.Module <- lower_declarations_sequential(tail, prefix, module_name, entry_module, fuel, context)
        declaration(classify(C.kind_of(node)), node, C.field_values(head, "attributes"), prefix, module_name, entry_module, rest, fuel, context)

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

def lower_declaration_batch(batch: DeclarationBatch, +prefix: String, +module_name: String, +entry_module: Bool, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  match batch:
    case DeclarationLeaf{nodes}:
      lower_declarations_sequential(nodes, prefix, module_name, entry_module, fuel, context)
    # Bend 2.0.21 drains 16 contiguous lanes per worker. Expose eight balanced
    # branches so a small binary tree does not occupy only two worker chunks.
    case DeclarationFork{DeclarationFork{DeclarationFork{a, b}, DeclarationFork{c, d}}, DeclarationFork{DeclarationFork{e, f}, DeclarationFork{g, h}}}:
      ra rb rc rd re rf rg rh = lower_declaration_batch(a, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(b, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(c, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(d, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(e, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(f, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(g, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(h, prefix, module_name, entry_module, fuel, context)
      merge_declarations(merge_declarations(merge_declarations(ra, rb), merge_declarations(rc, rd)), merge_declarations(merge_declarations(re, rf), merge_declarations(rg, rh)))
    case DeclarationFork{DeclarationFork{a, b}, DeclarationFork{c, d}}:
      ra rb rc rd = lower_declaration_batch(a, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(b, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(c, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(d, prefix, module_name, entry_module, fuel, context)
      merge_declarations(merge_declarations(ra, rb), merge_declarations(rc, rd))
    case DeclarationFork{left, right}:
      a b = lower_declaration_batch(left, prefix, module_name, entry_module, fuel, context) lower_declaration_batch(right, prefix, module_name, entry_module, fuel, context)
      merge_declarations(a, b)

def validate_declaration_nodes(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match nodes:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        node : C.Cst <- C.one(C.field_values(head, "value"))
        validate_declaration_nodes(tail)

def effect_member_requests(templates: List<&2, M.TypeId>, +arguments: List<&2, M.Ty>) -> List<&2, M.Operation>:
  match templates:
    case Nil{}:
      Nil{}
    case template <> rest:
      M.OperationInstance{template, arguments} <> effect_member_requests(rest, arguments)

def row_label_requests_found(found: Maybe<&2, Global>, arguments: List<&2, M.Ty>) -> List<&2, M.Operation>:
  match found:
    case Some{Global{source, core, OperationTemplateName{identity, parameters}}}:
      [M.OperationInstance{identity, arguments}]
    case Some{Global{source, core, EffectFamilyName{members, parameters}}}:
      effect_member_requests(members, arguments)
    case _:
      Nil{}

def row_arguments(found: Maybe<&2, Global>, values: List<&2, A.Value>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match found:
    case Some{Global{source, core, OperationTemplateName{identity, parameters}}}:
      A.bind(parameters, values, node)
    case Some{Global{source, core, EffectFamilyName{members, parameters}}}:
      A.bind(parameters, values, node)
    case _:
      A.bind(Nil{}, values, node)

def row_label_requests(application: T.RowLabel, fuel: Nat, context: Context, variables: List<&2, T.Variable>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  T.RowLabel{name, nodes, node} = application
  Context{+globals, headers, fixities, locals, label, annotation_variables} = context
  do Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
    values : List<&2, A.Value> <- T.evaluate(~Map<&2, Global>, ~lookup_effect, fuel, T.Nodes{nodes}, headers, variables, globals)
    +found : Maybe<&2, Global> <- Done{lookup_global(globals, name)}
    arguments : List<&2, M.Ty> <- row_arguments(found, values, node)
    return row_label_requests_found(found, arguments)

def row_labels_requests(nodes: List<&2, C.Cst>, +fuel: Nat, +context: Context, +variables: List<&2, T.Variable>, +reversed: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match nodes:
    case Nil{}:
      Done{List.reverse(&2, M.Operation, reversed)}
    case +node <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
        application : T.RowLabel <- T.row_label(fuel, T.visit(node), Nil{}, node)
        requests : List<&2, M.Operation> <- row_label_requests(application, fuel, context, variables)
        row_labels_requests(rest, fuel, context, variables, List.reverse.go(&2, M.Operation, requests, reversed))

def row_requests_of(is_row: Bool, node: C.Cst, fuel: Nat, context: Context, variables: List<&2, T.Variable>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match is_row:
    case True{}:
      row_labels_requests(C.field_values(node, "labels"), fuel, context, variables, Nil{})
    case False{}:
      Done{Nil{}}

def declaration_row_requests(fuel: Nat, nodes: List<&2, C.Cst>, +context: Context, +variables: List<&2, T.Variable>, +reversed: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match fuel nodes:
    case 0n _:
      Fail{M.Diagnostic{"internal_cst", "parser", "effect-row source tree exhausted its node-count bound"}}
    case 1n+rest Nil{}:
      Done{List.reverse(&2, M.Operation, reversed)}
    case 1n+ +rest +node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
        requests : List<&2, M.Operation> <- row_requests_of(M.name_equal(C.kind_of(node), "effect_row"), node, rest, context, variables)
        declaration_row_requests(rest, List.reverse.go(&2, C.Cst, List.reverse(&2, C.Cst, C.children_of(node)), tail), context, variables, List.reverse.go(&2, M.Operation, requests, reversed))

def declaration_type_variables(kind: NodeKind, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, T.Variable>>:
  match kind:
    case DataNode{}:
      type_variables(node)
    case EffectTypeNode{}:
      type_variables(node)
    case _:
      T.free_variables(node, "")

def declarations_row_requests(nodes: List<&2, C.Cst>, +fuel: Nat, +context: Context, +reversed: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
  match nodes:
    case Nil{}:
      Done{List.reverse(&2, M.Operation, reversed)}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Operation>>:
        +node : C.Cst <- C.one(C.field_values(head, "value"))
        variables : List<&2, T.Variable> <- declaration_type_variables(classify(C.kind_of(node)), node)
        first : List<&2, M.Operation> <- declaration_row_requests(fuel, [node], context, variables, Nil{})
        declarations_row_requests(tail, fuel, context, List.reverse.go(&2, M.Operation, first, reversed))

def lower_declarations(+nodes: List<&2, C.Cst>, prefix: String, module_name: String, entry_module: Bool, +fuel: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, M.Module>:
  +count = List.length(&2, C.Cst, nodes)
  do Result<&2, &2, M.Diagnostic, M.Module>:
    # Structural failures precede semantic failures in the serial traversal.
    valid : Unit <- validate_declaration_nodes(nodes)
    module : M.Module <- lower_declaration_batch(declaration_batches(48n, nodes, count, Nat.is_le(count, 4n)), prefix, module_name, entry_module, fuel, context)
    requests : List<&2, M.Operation> <- declarations_row_requests(nodes, fuel, context, Nil{})
    return add_operations(module, requests)

type Prelude is Data:
  Prelude{module: M.Module, scope: Context}

type SourcePlan is Data:
  SourcePlan{prelude: M.Module, scope: Context, declarations: List<&2, C.Cst>}

def prepare_prelude(prelude: C.Cst, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, Prelude>:
  +prelude_nodes = C.field_values(prelude, "declarations")
  do Result<&2, &2, M.Diagnostic, Prelude>:
    +prelude_scope : Context <- collect_names(prelude_nodes, "$prelude.", "std/prelude")
    +prelude_fixities : List<&2, O.Fixity> <- collect_fixities(prelude_nodes, prelude_scope, False{})
    prelude_module : M.Module <- lower_declarations(prelude_nodes, "$prelude.", "std/prelude", False{}, fuel, with_fixities(prelude_scope, prelude_fixities))
    return Prelude{prelude_module, with_fixities(prelude_scope, prelude_fixities)}

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
    local_scope : Context <- collect_names(nodes, "", "main")
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
