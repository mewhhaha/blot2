import Base
import ./model.bend as M
import ./cst.bend as C
import ./index.bend as Index
import ./source_arguments.bend as A

type Header is Data:
  Header{source: String, identity: M.TypeId, parameters: List<&2, A.Pattern>}

type VariableKind is Data:
  TypeKind{}
  RowKind{}

type Variable is Data:
  Variable{source: String, value: M.Ty, kind: VariableKind}

type NodeKind is Data:
  Expression{}
  Application{}
  Wrapper{}
  Group{}
  ArrayNode{}
  RecordNode{}
  FieldNode{}
  InfixNode{}
  PrefixNode{}
  Name{}

type Work is Data:
  Node{kind: NodeKind, node: C.Cst}
  Nodes{nodes: List<&2, C.Cst>}
  Field{node: C.Cst, values: List<&2, C.Cst>}
  Infix{node: C.Cst, tails: List<&2, C.Cst>}
  Prefix{node: C.Cst, operators: List<&2, C.Cst>}

def classify(+kind: String) -> NodeKind:
  Bool.pick(NodeKind, Bool.or(M.name_equal(kind, "type_expression"), M.name_equal(kind, "effect_signature")), Expression{},
    Bool.pick(NodeKind, Bool.or(M.name_equal(kind, "type_application"), Bool.or(M.name_equal(kind, "application"), M.name_equal(kind, "effect_signature_application"))), Application{},
    Bool.pick(NodeKind, Bool.or(M.name_equal(kind, "type_atom"), Bool.or(M.name_equal(kind, "atom"), Bool.or(M.name_equal(kind, "expression"), M.name_equal(kind, "effect_signature_atom")))), Wrapper{},
    Bool.pick(NodeKind, Bool.or(M.name_equal(kind, "type_group"), M.name_equal(kind, "group")), Group{},
    Bool.pick(NodeKind, Bool.or(M.name_equal(kind, "type_array"), M.name_equal(kind, "array")), ArrayNode{},
    Bool.pick(NodeKind, Bool.or(M.name_equal(kind, "type_record"), M.name_equal(kind, "record_values")), RecordNode{},
    Bool.pick(NodeKind, Bool.or(M.name_equal(kind, "type_field"), M.name_equal(kind, "record_value")), FieldNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "infix_expression"), InfixNode{},
    Bool.pick(NodeKind, M.name_equal(kind, "prefix_expression"), PrefixNode{}, Name{})))))))))

def visit(+node: C.Cst) -> Work:
  Node{classify(C.kind_of(node)), node}

def one(types: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  A.one(types)

def one_value(values: List<&2, A.Value>) -> Result<&2, &2, M.Diagnostic, A.Value>:
  match values:
    case value <> Nil{}:
      Done{value}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "expected one type value"}}

def grouped(values: List<&2, A.Value>) -> A.Value:
  match values:
    case value <> Nil{}:
      value
    case values:
      A.TupleValue{values}

def lookup_variable(variables: List<&2, Variable>, +name: String) -> Maybe<&2, M.Ty>:
  match variables:
    case Nil{}:
      None{}
    case Variable{source, value, TypeKind{}} <> rest:
      Bool.pick(Maybe<&2, M.Ty>, M.name_equal(source, name), Some{value}, lookup_variable(rest, name))
    case Variable{source, value, RowKind{}} <> rest:
      lookup_variable(rest, name)

def lookup_row(variables: List<&2, Variable>, +name: String) -> Maybe<&2, M.RowTail>:
  match variables:
    case Nil{}:
      None{}
    case Variable{source, M.FreeTy{scope, variable}, RowKind{}} <> rest:
      Bool.pick(Maybe<&2, M.RowTail>, M.name_equal(source, name), Some{M.FreeRow{scope, variable}}, lookup_row(rest, name))
    case head <> rest:
      lookup_row(rest, name)

def lookup_header(headers: Map<&2, Header>, name: String) -> Maybe<&2, Header>:
  Index.find(Header, headers, name)

def builtin(array: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, A.Value>:
  match array:
    case True{}:
      Done{A.ArrayConstructorValue{}}
    case False{}:
      do Result<&2, &2, M.Diagnostic, A.Value>:
        ty : M.Ty <- C.scalar_type(node)
        return A.Concrete{ty}

def named(found: Maybe<&2, Header>, variable: Maybe<&2, M.Ty>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, A.Value>:
  match found variable:
    case Some{Header{source, identity, parameters}} Some{M.FreeTy{scope, name}}:
      Done{A.constructor(parameters, identity, Nil{})}
    case _ Some{ty}:
      Done{A.Concrete{ty}}
    case Some{Header{source, identity, parameters}} None{}:
      Done{A.constructor(parameters, identity, Nil{})}
    case None{} None{}:
      builtin(M.name_equal(C.type_name(node), "Array"), node)

def arrow(types: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match types:
    case Nil{}:
      Fail{M.Diagnostic{"internal_cst", "parser", "empty function type"}}
    case head <> Nil{}:
      Done{head}
    case head <> next <> tail:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        result : M.Ty <- arrow(next <> tail)
        return M.FunctionTy{head, result, M.empty_row()}

def without_arrows(nodes: List<&2, C.Cst>) -> List<&2, C.Cst>:
  match nodes:
    case Nil{}:
      Nil{}
    case +head <> tail:
      +rest = without_arrows(tail)
      Bool.pick(List<&2, C.Cst>, M.name_equal(C.kind_of(head), "->"), rest, head <> rest)

type RowLabel is Data:
  RowLabel{name: String, arguments: List<&2, C.Cst>, node: C.Cst}

# Collect applications through grouping before resolving the effect name.
# Arguments remain source values until the declared pattern binds them.
def row_label(fuel: Nat, work: Work, arguments: List<&2, C.Cst>, +original: C.Cst) -> Result<&2, &2, M.Diagnostic, RowLabel>:
  match fuel work:
    case 0n _:
      Fail{C.diagnostic(original, "type_argument", "effect application exceeds the source-tree limit")}
    case 1n+rest Node{Application{}, +node}:
      row_label(rest, Nodes{C.field_values(node, "head")}, List.append(&2, C.Cst, C.field_values(node, "arguments"), arguments), original)
    case 1n+rest Node{Wrapper{}, node}:
      row_label(rest, Nodes{C.children_of(node)}, arguments, original)
    case 1n+rest Node{Group{}, node}:
      row_label(rest, Nodes{C.field_values(node, "value")}, arguments, original)
    case 1n+rest Node{Expression{}, +node}:
      children = Bool.pick(List<&2, C.Cst>, Bool.and(List.is_empty(&2, C.Cst, C.field_values(node, "results")), List.is_empty(&2, C.Cst, C.field_values(node, "effects"))), C.field_values(node, "head"), Nil{})
      row_label(rest, Nodes{children}, arguments, original)
    case 1n+rest Nodes{node <> Nil{}}:
      row_label(rest, visit(node), arguments, original)
    case 1n+rest Node{Name{}, node}:
      Done{RowLabel{C.type_name(node), arguments, original}}
    case _ _:
      Fail{C.diagnostic(original, "unknown_effect", "effect rows require a declared operation or family application")}

def row_applications(nodes: List<&2, C.Cst>, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, RowLabel>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, RowLabel>>:
        label : RowLabel <- row_label(fuel, visit(node), Nil{}, node)
        following : List<&2, RowLabel> <- row_applications(tail, fuel)
        return label <> following

def row_nodes(nodes: List<&2, C.Cst>) -> List<&2, C.Cst>:
  match nodes:
    case Nil{}:
      Nil{}
    case node <> tail:
      List.append(&2, C.Cst, C.field_values(node, "labels"), row_nodes(tail))

def row_argument_nodes(nodes: List<&2, RowLabel>) -> List<&2, C.Cst>:
  match nodes:
    case Nil{}:
      Nil{}
    case RowLabel{name, arguments, node} <> tail:
      List.append(&2, C.Cst, arguments, row_argument_nodes(tail))

type Split is Data:
  Split{arguments: List<&2, A.Value>, following: List<&2, A.Value>}

def split_arguments(value: Split) -> List<&2, A.Value>:
  Split{arguments, following} = value
  arguments

def split_following(value: Split) -> List<&2, A.Value>:
  Split{arguments, following} = value
  following

def split(count: Nat, values: List<&2, A.Value>) -> Result<&2, &2, M.Diagnostic, Split>:
  match count values:
    case 0n values:
      Done{Split{Nil{}, values}}
    case 1n+rest head <> tail:
      do Result<&2, &2, M.Diagnostic, Split>:
        +parts : Split <- split(rest, tail)
        return Split{head <> split_arguments(parts), split_following(parts)}
    case _ _:
      Fail{M.Diagnostic{"internal_cst", "parser", "effect row lost its type arguments"}}

def row_labels(~Scope: Data, ~resolve_effect: Scope -> String -> List<&2, A.Value> -> C.Cst -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>, nodes: List<&2, RowLabel>, values: List<&2, A.Value>, +scope: Scope) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case RowLabel{name, arguments, node} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
        +parts : Split <- split(List.length(&2, C.Cst, arguments), values)
        identities : List<&2, M.TypeId> <- resolve_effect(scope, name, split_arguments(parts), node)
        remaining : List<&2, M.TypeId> <- row_labels(~Scope, ~resolve_effect, tail, split_following(parts), scope)
        return List.append(&2, M.TypeId, identities, remaining)

def row_has_tail(nodes: List<&2, C.Cst>) -> Bool:
  match nodes:
    case Nil{}:
      False{}
    case node <> tail:
      Bool.or(C.present(C.field_values(node, "tail")), row_has_tail(tail))

def checked_row_labels(found: Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>, rows: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>:
  match found rows:
    case Done{labels} _:
      Done{labels}
    case Fail{M.Diagnostic{+code, subject, message}} +row <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>, Bool.and(M.name_equal(code, "effect_instance"), row_has_tail(row <> tail)), Fail{C.diagnostic(row, "unsupported_polymorphic_effect_label", "open rows currently require concrete effect operation labels")}, Fail{M.Diagnostic{code, subject, message}})
    case Fail{error} Nil{}:
      Fail{error}

def row_tail_found(found: Maybe<&2, M.RowTail>, name: C.Cst) -> Result<&2, &2, M.Diagnostic, M.RowTail>:
  match found:
    case Some{row}:
      Done{row}
    case None{}:
      Fail{C.diagnostic(name, "invalid_effect_annotation", "effect row tail has no row-variable binding")}

def row_tail_names(nodes: List<&2, C.Cst>, variables: List<&2, Variable>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.RowTail>:
  match nodes:
    case Nil{}:
      Done{M.ClosedRow{}}
    case +name <> Nil{}:
      row_tail_found(lookup_row(variables, C.text_of(name)), name)
    case _:
      Fail{C.diagnostic(node, "invalid_effect_annotation", "effect row has more than one tail")}

def row_tail(nodes: List<&2, C.Cst>, variables: List<&2, Variable>) -> Result<&2, &2, M.Diagnostic, M.RowTail>:
  match nodes:
    case Nil{}:
      Done{M.ClosedRow{}}
    case +node <> Nil{}:
      row_tail_names(C.field_values(node, "tail"), variables, node)
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "expected one effect row"}}

def with_row(+nodes: List<&2, C.Cst>, ty: M.Ty, labels: List<&2, M.TypeId>, variables: List<&2, Variable>, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match nodes ty:
    case Nil{} ty:
      Done{ty}
    case _ M.FunctionTy{parameter, result, previous}:
      do Result<&2, &2, M.Diagnostic, M.Ty>:
        tail : M.RowTail <- row_tail(nodes, variables)
        return M.FunctionTy{parameter, result, M.EffectRow{labels, tail}}
    case _ _:
      Fail{C.diagnostic(node, "invalid_effect_annotation", "an effect row annotates a function arrow, not a value type")}

def expression_value(values: List<&2, A.Value>, +effects: List<&2, C.Cst>, labels: List<&2, M.TypeId>, variables: List<&2, Variable>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
  match values effects:
    case value <> Nil{} Nil{}:
      Done{[value]}
    case values _:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        types : List<&2, M.Ty> <- A.types(65536n, A.ValueTypes{values}, node)
        ty : M.Ty <- arrow(types)
        annotated : M.Ty <- with_row(effects, ty, labels, variables, node)
        return [A.Concrete{annotated}]

def evaluate(~Scope: Data, ~resolve_effect: Scope -> String -> List<&2, A.Value> -> C.Cst -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>, +fuel: Nat, work: Work, +headers: Map<&2, Header>, +variables: List<&2, Variable>, +scope: Scope) -> Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"type_argument", "parser", "type source tree exhausted its node-count bound"}}
    case 1n+remaining Nodes{Nil{}}:
      Done{Nil{}}
    case 1n+remaining Nodes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        first : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, visit(head), headers, variables, scope)
        rest : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, Nodes{tail}, headers, variables, scope)
        return List.append(&2, A.Value, first, rest)
    case 1n+remaining Node{Expression{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        +values : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, Nodes{List.append(&2, C.Cst, C.field_values(node, "head"), without_arrows(C.field_values(node, "results")))}, headers, variables, scope)
        +effects : List<&2, C.Cst> <- Done{C.field_values(node, "effects")}
        +labels : List<&2, RowLabel> <- row_applications(row_nodes(effects), remaining)
        arguments : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, Nodes{row_argument_nodes(labels)}, headers, variables, scope)
        identities : List<&2, M.TypeId> <- checked_row_labels(row_labels(~Scope, ~resolve_effect, labels, arguments, scope), effects)
        expression_value(values, effects, identities, variables, node)
    case 1n+remaining Node{Application{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        head : C.Cst <- C.one(C.field_values(node, "head"))
        values : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, visit(head), headers, variables, scope)
        callee : A.Value <- one_value(values)
        arguments : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, Nodes{C.field_values(node, "arguments")}, headers, variables, scope)
        value : A.Value <- A.apply(arguments, callee, node)
        return [value]
    case 1n+remaining Node{Wrapper{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        child : C.Cst <- C.one(C.children_of(node))
        evaluate(~Scope, ~resolve_effect, remaining, visit(child), headers, variables, scope)
    case 1n+remaining Node{Group{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        elements : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, Nodes{C.field_values(node, "value")}, headers, variables, scope)
        return [grouped(elements)]
    case 1n+remaining Node{ArrayNode{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        elements : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, Nodes{C.field_values(node, "elements")}, headers, variables, scope)
        return [A.ArrayValue{elements}]
    case 1n+remaining Node{RecordNode{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        +fields : List<&2, C.Cst> <- Done{C.field_values(node, "fields")}
        +names : List<&2, String> <- A.field_names(fields)
        valid : Unit <- A.unique(names, node)
        values : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, remaining, Nodes{fields}, headers, variables, scope)
        return [A.RecordValue{names, values}]
    case 1n+remaining Node{FieldNode{}, +node}:
      evaluate(~Scope, ~resolve_effect, remaining, Field{node, C.field_values(node, "value")}, headers, variables, scope)
    case 1n+remaining Field{node, Nil{}}:
      evaluate(~Scope, ~resolve_effect, remaining, Nodes{C.field_values(node, "name")}, headers, variables, scope)
    case 1n+remaining Field{node, values}:
      evaluate(~Scope, ~resolve_effect, remaining, Nodes{values}, headers, variables, scope)
    case 1n+remaining Node{InfixNode{}, +node}:
      evaluate(~Scope, ~resolve_effect, remaining, Infix{node, C.field_values(node, "tails")}, headers, variables, scope)
    case 1n+remaining Infix{node, Nil{}}:
      evaluate(~Scope, ~resolve_effect, remaining, Nodes{C.field_values(node, "head")}, headers, variables, scope)
    case 1n+remaining Node{PrefixNode{}, +node}:
      evaluate(~Scope, ~resolve_effect, remaining, Prefix{node, C.field_values(node, "operator")}, headers, variables, scope)
    case 1n+remaining Prefix{node, Nil{}}:
      evaluate(~Scope, ~resolve_effect, remaining, Nodes{C.field_values(node, "value")}, headers, variables, scope)
    case 1n+remaining Node{Name{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, A.Value>>:
        value : A.Value <- named(lookup_header(headers, C.type_name(node)), lookup_variable(variables, C.type_name(node)), node)
        return [value]
    case _ Infix{node, tails}:
      Fail{C.diagnostic(node, "type_argument", "type arguments cannot contain value operators")}
    case _ Prefix{node, operators}:
      Fail{C.diagnostic(node, "type_argument", "type arguments cannot contain value operators")}

def row(~Scope: Data, ~resolve_effect: Scope -> String -> List<&2, A.Value> -> C.Cst -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>, +node: C.Cst, +fuel: Nat, headers: Map<&2, Header>, +variables: List<&2, Variable>, +scope: Scope) -> Result<&2, &2, M.Diagnostic, M.EffectRow>:
  do Result<&2, &2, M.Diagnostic, M.EffectRow>:
    +applications : List<&2, RowLabel> <- row_applications(C.field_values(node, "labels"), fuel)
    arguments : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, fuel, Nodes{row_argument_nodes(applications)}, headers, variables, scope)
    labels : List<&2, M.TypeId> <- checked_row_labels(row_labels(~Scope, ~resolve_effect, applications, arguments, scope), [node])
    tail : M.RowTail <- row_tail([node], variables)
    return M.EffectRow{labels, tail}

def origin(work: Work) -> C.Cst:
  match work:
    case Node{kind, node}:
      node
    case Nodes{head <> tail}:
      head
    case Nodes{Nil{}}:
      C.Cst{"", "", "", 0n, Nil{}}
    case Field{node, values}:
      node
    case Infix{node, tails}:
      node
    case Prefix{node, operators}:
      node

def lower(~Scope: Data, ~resolve_effect: Scope -> String -> List<&2, A.Value> -> C.Cst -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>, +fuel: Nat, +work: Work, headers: Map<&2, Header>, variables: List<&2, Variable>, scope: Scope) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
    values : List<&2, A.Value> <- evaluate(~Scope, ~resolve_effect, fuel, work, headers, variables, scope)
    A.types(fuel, A.ValueTypes{values}, origin(work))

def annotation(~Scope: Data, ~resolve_effect: Scope -> String -> List<&2, A.Value> -> C.Cst -> Result<&2, &2, M.Diagnostic, List<&2, M.TypeId>>, nodes: List<&2, C.Cst>, fuel: Nat, headers: Map<&2, Header>, variables: List<&2, Variable>, scope: Scope) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  match nodes:
    case Nil{}:
      Done{None{}}
    case node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
        types : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, fuel, visit(node), headers, variables, scope)
        ty : M.Ty <- one(types)
        return Some{ty}
    case marker <> node <> Nil{}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
        types : List<&2, M.Ty> <- lower(~Scope, ~resolve_effect, fuel, visit(node), headers, variables, scope)
        ty : M.Ty <- one(types)
        return Some{ty}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid type annotation field"}}

# Whole-tree callers retain the original scan. Lowering uses RootScope once;
# only its descendants stop at a nested binding's independently owned scope.
type VariableBoundary is Data:
  WholeTree{}
  RootScope{}
  NestedScope{}

type VariableScan is Data:
  VariableScan{nodes: List<&2, C.Cst>, annotation: Bool, boundary: VariableBoundary}

def descendant_boundary(boundary: VariableBoundary) -> VariableBoundary:
  match boundary:
    case WholeTree{}:
      WholeTree{}
    case _:
      NestedScope{}

def variable_children(node: C.Cst, boundary: VariableBoundary) -> List<&2, C.Cst>:
  match node boundary:
    case C.Cst{"binding", field, text, offset, children} NestedScope{}:
      Nil{}
    case C.Cst{kind, field, text, offset, children} _:
      children

def variable_kind(variable: Variable) -> VariableKind:
  Variable{source, value, kind} = variable
  kind

def found_variable(variables: List<&2, Variable>, +name: String) -> Maybe<&2, Variable>:
  match variables:
    case Nil{}:
      None{}
    case Variable{+source, value, kind} <> rest:
      Bool.pick(Maybe<&2, Variable>, M.name_equal(source, name), Some{Variable{source, value, kind}}, found_variable(rest, name))

def same_kind(left: VariableKind, right: VariableKind) -> Bool:
  match left right:
    case TypeKind{} TypeKind{}:
      True{}
    case RowKind{} RowKind{}:
      True{}
    case _ _:
      False{}

def add_variable_found(found: Maybe<&2, Variable>, kind: VariableKind, +node: C.Cst, scope: String, +variables: List<&2, Variable>) -> Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
  match found:
    case None{}:
      +name = C.text_of(node)
      Done{Variable{name, M.FreeTy{scope, name}, kind} <> variables}
    case Some{previous}:
      Bool.pick(Result<&2, &2, M.Diagnostic, List<&2, Variable>>, same_kind(variable_kind(previous), kind), Done{variables}, Fail{C.diagnostic(node, "annotation_kind_mismatch", "one annotation name cannot be both a type and an effect-row variable")})

def add_variable(kind: VariableKind, +node: C.Cst, scope: String, +variables: List<&2, Variable>) -> Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
  add_variable_found(found_variable(variables, C.text_of(node)), kind, node, scope, variables)

def scan_row_arguments(nodes: List<&2, C.Cst>) -> List<&2, C.Cst>:
  match nodes:
    case Nil{}:
      Nil{}
    case node <> tail:
      List.append(&2, C.Cst, C.field_values(node, "arguments"), scan_row_arguments(tail))

def predicate_arguments_kind(kinds: List<&2, C.Cst>, +arguments: List<&2, C.Cst>) -> List<&2, C.Cst>:
  match kinds arguments:
    case kind <> Nil{} first <> rest:
      Bool.pick(List<&2, C.Cst>, M.name_equal(C.text_of(kind), "operation"), rest, arguments)
    case _ _:
      arguments

def predicate_arguments(+node: C.Cst) -> List<&2, C.Cst>:
  predicate_arguments_kind(C.field_values(node, "kind"), C.field_values(node, "arguments"))

def scan_type_name(found: Bool, node: C.Cst, scope: String, variables: List<&2, Variable>) -> Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
  match found:
    case True{}:
      add_variable(TypeKind{}, node, scope, variables)
    case False{}:
      Done{variables}

# Each annotation scope collects type and row names before lowering. A local
# `let` supplies a new scope; row tails never become ordinary type arguments.
def scan_row_tail(nodes: List<&2, C.Cst>, variables: List<&2, Variable>, scope: String) -> Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
  match nodes:
    case Nil{}:
      Done{variables}
    case node <> Nil{}:
      add_variable(RowKind{}, node, scope, variables)
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "invalid row tail field"}}

def scan_variables(fuel: Nat, pending: List<&2, VariableScan>, variables: List<&2, Variable>, +scope: String) -> Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
  match fuel pending:
    case 0n _:
      Fail{M.Diagnostic{"type_argument", "parser", "annotation scope exceeds the source-tree limit"}}
    case 1n+rest Nil{}:
      Done{variables}
    case 1n+rest VariableScan{Nil{}, annotation, boundary} <> tail:
      scan_variables(rest, tail, variables, scope)
    case 1n+rest VariableScan{C.Cst{"effect_row", field, text, offset, children} <> siblings, +annotation, +boundary} <> tail:
      +node = {C.Cst{"effect_row", field, text, offset, children} : C.Cst}
      do Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
        arguments : List<&2, C.Cst> = scan_row_arguments(C.field_values(node, "labels"))
        next : List<&2, Variable> <- scan_row_tail(C.field_values(node, "tail"), variables, scope)
        scan_variables(rest, VariableScan{arguments, True{}, descendant_boundary(boundary)} <> VariableScan{siblings, annotation, boundary} <> tail, next, scope)
    case 1n+rest VariableScan{C.Cst{"constraint_predicate", field, text, offset, children} <> siblings, +annotation, +boundary} <> tail:
      +node = {C.Cst{"constraint_predicate", field, text, offset, children} : C.Cst}
      +arguments = predicate_arguments(node)
      scan_variables(rest, VariableScan{arguments, True{}, descendant_boundary(boundary)} <> VariableScan{C.field_values(node, "effects"), False{}, descendant_boundary(boundary)} <> VariableScan{siblings, annotation, boundary} <> tail, variables, scope)
    case 1n+rest VariableScan{+node <> siblings, +annotation, +boundary} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
        +kind : String = C.kind_of(node)
        +nested : Bool = Bool.or(annotation, M.name_equal(kind, "type_expression"))
        next : List<&2, Variable> <- scan_type_name(Bool.and(nested, M.name_equal(kind, "IDENT")), node, scope, variables)
        scan_variables(rest, VariableScan{variable_children(node, boundary), nested, descendant_boundary(boundary)} <> VariableScan{siblings, annotation, boundary} <> tail, next, scope)

def free_variables(node: C.Cst, scope: String) -> Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
  scan_variables(1048576n, [VariableScan{[node], False{}, WholeTree{}}], Nil{}, scope)

# Fuse scope pruning with variable collection. Do not clone the complete CST
# merely to erase nested let children before immediately scanning it again.
def scoped_free_variables(node: C.Cst, scope: String) -> Result<&2, &2, M.Diagnostic, List<&2, Variable>>:
  scan_variables(1048576n, [VariableScan{[node], False{}, RootScope{}}], Nil{}, scope)
