import Base
import ./model.bend as M
import ./cst.bend as C

type Pattern is Data:
  Binding{source: String}
  TuplePattern{elements: List<&2, Pattern>}
  ArrayPattern{elements: List<&2, Pattern>}
  RecordPattern{names: List<&2, String>, fields: List<&2, Pattern>}

# Source arguments may contain several types without becoming several calls.
# Constructors stay here until saturated; runtime inference only sees types.
type Value is Data:
  Concrete{value: M.Ty}
  TupleValue{elements: List<&2, Value>}
  ArrayValue{elements: List<&2, Value>}
  RecordValue{names: List<&2, String>, fields: List<&2, Value>}
  ConstructorValue{identity: M.TypeId, parameters: List<&2, Pattern>, bound: List<&2, M.Ty>}
  ArrayConstructorValue{}

type TypeWork is Data:
  ValueType{value: Value}
  ValueTypes{values: List<&2, Value>}

def one(types: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match types:
    case ty <> Nil{}:
      Done{ty}
    case _:
      Fail{M.Diagnostic{"internal_cst", "parser", "expected one type"}}

def product(elements: List<&2, M.Ty>) -> M.Ty:
  match elements:
    case Nil{}:
      M.UnitTy{}
    case first <> Nil{}:
      first
    case elements:
      M.ProductTy{elements}

def types(+fuel: Nat, work: TypeWork, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match fuel work:
    case 0n _:
      Fail{C.diagnostic(node, "type_argument", "type argument exceeds the source-tree limit")}
    case 1n+rest ValueType{Concrete{ty}}:
      Done{[ty]}
    case 1n+rest ValueType{TupleValue{elements}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        fields : List<&2, M.Ty> <- types(rest, ValueTypes{elements}, node)
        return [product(fields)]
    case 1n+rest ValueType{ConstructorValue{identity, parameters, bound}}:
      Fail{C.diagnostic(node, "type_arity", "partially applied type constructor requires another argument")}
    case 1n+rest ValueType{ArrayConstructorValue{}}:
      Fail{C.diagnostic(node, "type_arity", "Array requires one element type")}
    case 1n+rest ValueType{value}:
      Fail{C.diagnostic(node, "type_argument", "expected a type; structural arguments must match a constructor parameter")}
    case 1n+rest ValueTypes{Nil{}}:
      Done{Nil{}}
    case 1n+rest ValueTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        first : List<&2, M.Ty> <- types(rest, ValueType{head}, node)
        following : List<&2, M.Ty> <- types(rest, ValueTypes{tail}, node)
        return List.append(&2, M.Ty, first, following)

def as_type(value: Value, node: C.Cst) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  do Result<&2, &2, M.Diagnostic, M.Ty>:
    values : List<&2, M.Ty> <- types(65536n, ValueType{value}, node)
    one(values)

def field(names: List<&2, String>, values: List<&2, Value>, +wanted: String, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Value>:
  match names values:
    case name <> tail value <> rest:
      Bool.pick(Result<&2, &2, M.Diagnostic, Value>, M.name_equal(name, wanted), Done{value}, field(tail, rest, wanted, node))
    case _ _:
      Fail{C.diagnostic(node, "type_argument", "missing type argument field: " ++ wanted)}

type MatchWork is Data:
  Argument{pattern: Pattern, value: Value}
  Arguments{patterns: List<&2, Pattern>, values: List<&2, Value>}
  Fields{names: List<&2, String>, patterns: List<&2, Pattern>, actual_names: List<&2, String>, values: List<&2, Value>}

def match_argument(+fuel: Nat, work: MatchWork, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match fuel work:
    case 0n _:
      Fail{C.diagnostic(node, "type_argument", "type parameter pattern exceeds the source-tree limit")}
    case 1n+rest Argument{Binding{source}, value}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        ty : M.Ty <- as_type(value, node)
        return [ty]
    case 1n+rest Argument{TuplePattern{patterns}, TupleValue{values}}:
      match_argument(rest, Arguments{patterns, values}, node)
    case 1n+rest Argument{ArrayPattern{patterns}, ArrayValue{values}}:
      match_argument(rest, Arguments{patterns, values}, node)
    case 1n+rest Argument{RecordPattern{+names, patterns}, RecordValue{+actual_names, values}}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        valid : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, Nat.is_eq(List.length(&2, String, names), List.length(&2, String, actual_names)), Done{Unit{}}, Fail{C.diagnostic(node, "type_argument", "record type argument has the wrong fields")})
        match_argument(rest, Fields{names, patterns, actual_names, values}, node)
    case 1n+rest Argument{pattern, value}:
      Fail{C.diagnostic(node, "type_argument", "type argument does not match its parameter pattern")}
    case 1n+rest Arguments{Nil{}, Nil{}}:
      Done{Nil{}}
    case 1n+rest Arguments{pattern <> patterns, value <> values}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        first : List<&2, M.Ty> <- match_argument(rest, Argument{pattern, value}, node)
        following : List<&2, M.Ty> <- match_argument(rest, Arguments{patterns, values}, node)
        return List.append(&2, M.Ty, first, following)
    case 1n+rest Arguments{patterns, values}:
      Fail{C.diagnostic(node, "type_argument", "type argument has the wrong number of elements")}
    case 1n+rest Fields{Nil{}, Nil{}, actual_names, values}:
      Done{Nil{}}
    case 1n+rest Fields{name <> names, pattern <> patterns, +actual_names, +values}:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        value : Value <- field(actual_names, values, name, node)
        first : List<&2, M.Ty> <- match_argument(rest, Argument{pattern, value}, node)
        following : List<&2, M.Ty> <- match_argument(rest, Fields{names, patterns, actual_names, values}, node)
        return List.append(&2, M.Ty, first, following)
    case 1n+rest Fields{names, patterns, actual_names, values}:
      Fail{C.diagnostic(node, "internal_cst", "type record lost a field pattern")}

def constructor(parameters: List<&2, Pattern>, identity: M.TypeId, bound: List<&2, M.Ty>) -> Value:
  match parameters:
    case Nil{}:
      Concrete{M.AppliedTy{identity, bound}}
    case parameters:
      ConstructorValue{identity, parameters, bound}

def apply_one(callee: Value, argument: Value, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Value>:
  match callee:
    case ConstructorValue{identity, pattern <> rest, bound}:
      do Result<&2, &2, M.Diagnostic, Value>:
        arguments : List<&2, M.Ty> <- match_argument(65536n, Argument{pattern, argument}, node)
        return constructor(rest, identity, List.append(&2, M.Ty, bound, arguments))
    case ArrayConstructorValue{}:
      do Result<&2, &2, M.Diagnostic, Value>:
        ty : M.Ty <- as_type(argument, node)
        return Concrete{M.ArrayTy{ty}}
    case _:
      Fail{C.diagnostic(node, "type_arity", "type does not accept another argument; currying must be explicit in its declaration")}

def apply(arguments: List<&2, Value>, callee: Value, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Value>:
  match arguments:
    case Nil{}:
      Done{callee}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Value>:
        next : Value <- apply_one(callee, head, node)
        apply(tail, next, node)

def bind(parameters: List<&2, Pattern>, values: List<&2, Value>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match parameters values:
    case Nil{} Nil{}:
      Done{Nil{}}
    case pattern <> rest value <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        first : List<&2, M.Ty> <- match_argument(65536n, Argument{pattern, value}, node)
        following : List<&2, M.Ty> <- bind(rest, tail, node)
        return List.append(&2, M.Ty, first, following)
    case _ _:
      Fail{C.diagnostic(node, "type_arity", "wrong number of type arguments")}

type PatternKind is Data:
  BinderNode{}
  WrapperNode{}
  ExpressionNode{}
  ApplicationNode{}
  TupleNode{}
  ArrayNode{}
  RecordNode{}
  FieldNode{}

type PatternWork is Data:
  PatternNode{kind: PatternKind, node: C.Cst}
  PatternNodes{nodes: List<&2, C.Cst>}
  PatternField{node: C.Cst, values: List<&2, C.Cst>}
  PatternApplication{node: C.Cst, extra: List<&2, C.Cst>}

def pattern_kind(+kind: String) -> PatternKind:
  Bool.pick(PatternKind, M.name_equal(kind, "type_atom"), WrapperNode{},
    Bool.pick(PatternKind, M.name_equal(kind, "type_expression"), ExpressionNode{},
    Bool.pick(PatternKind, M.name_equal(kind, "type_application"), ApplicationNode{},
    Bool.pick(PatternKind, M.name_equal(kind, "type_group"), TupleNode{},
    Bool.pick(PatternKind, M.name_equal(kind, "type_array"), ArrayNode{},
    Bool.pick(PatternKind, M.name_equal(kind, "type_record"), RecordNode{},
    Bool.pick(PatternKind, M.name_equal(kind, "type_field"), FieldNode{}, BinderNode{})))))))

def lowercase_name(name: String) -> Bool:
  match name:
    case SCon{Chr{+initial}, tail}:
      Bool.or(U32.is_eq(initial, 95), Bool.and(U32.is_ge(initial, 97), U32.is_le(initial, 122)))
    case SNil{}:
      False{}

def binding_pattern(+node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
  +name = C.type_name(node)
  Bool.pick(Result<&2, &2, M.Diagnostic, List<&2, Pattern>>, Bool.and(lowercase_name(name), List.is_empty(&2, C.Cst, C.field_values(node, "rest"))), Done{[Binding{name}]}, Fail{C.diagnostic(node, "type_parameter", "a type parameter pattern binds lowercase names")})

def field_names(nodes: List<&2, C.Cst>) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, String>>:
        name : C.Cst <- C.one(C.field_values(node, "name"))
        rest : List<&2, String> <- field_names(tail)
        return C.type_name(name) <> rest

def contains(names: List<&2, String>, +wanted: String) -> Bool:
  match names:
    case Nil{}:
      False{}
    case name <> tail:
      Bool.or(M.name_equal(name, wanted), contains(tail, wanted))

def unique(names: List<&2, String>, +node: C.Cst) -> Result<&2, &2, M.Diagnostic, Unit>:
  match names:
    case Nil{}:
      Done{Unit{}}
    case +name <> +tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        valid : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, contains(tail, name), Fail{C.diagnostic(node, "duplicate_type_field", "duplicate type argument field: " ++ name)}, Done{Unit{}})
        unique(tail, node)

def tuple_pattern(patterns: List<&2, Pattern>) -> Pattern:
  match patterns:
    case head <> Nil{}:
      head
    case patterns:
      TuplePattern{patterns}

def parse_patterns(+fuel: Nat, work: PatternWork) -> Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"type_argument", "type", "type parameter pattern exceeds the source-tree limit"}}
    case 1n+rest PatternNodes{Nil{}}:
      Done{Nil{}}
    case 1n+rest PatternNodes{+head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
        first : List<&2, Pattern> <- parse_patterns(rest, PatternNode{pattern_kind(C.kind_of(head)), head})
        following : List<&2, Pattern> <- parse_patterns(rest, PatternNodes{tail})
        return List.append(&2, Pattern, first, following)
    case 1n+rest PatternNode{BinderNode{}, node}:
      binding_pattern(node)
    case 1n+rest PatternNode{WrapperNode{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
        +child : C.Cst <- C.one(C.children_of(node))
        parse_patterns(rest, PatternNode{pattern_kind(C.kind_of(child)), child})
    case 1n+rest PatternNode{ExpressionNode{}, +node}:
      parse_patterns(rest, PatternApplication{node, List.append(&2, C.Cst, C.field_values(node, "results"), C.field_values(node, "effects"))})
    case 1n+rest PatternNode{ApplicationNode{}, +node}:
      parse_patterns(rest, PatternApplication{node, C.field_values(node, "arguments")})
    case 1n+rest PatternApplication{node, Nil{}}:
      parse_patterns(rest, PatternNodes{C.field_values(node, "head")})
    case 1n+rest PatternApplication{node, extra}:
      Fail{C.diagnostic(node, "type_parameter", "a type parameter is one binding or a structural pattern")}
    case 1n+rest PatternNode{TupleNode{}, node}:
      do Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
        elements : List<&2, Pattern> <- parse_patterns(rest, PatternNodes{C.field_values(node, "value")})
        return [tuple_pattern(elements)]
    case 1n+rest PatternNode{ArrayNode{}, node}:
      do Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
        elements : List<&2, Pattern> <- parse_patterns(rest, PatternNodes{C.field_values(node, "elements")})
        return [ArrayPattern{elements}]
    case 1n+rest PatternNode{RecordNode{}, +node}:
      do Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
        +fields : List<&2, C.Cst> <- Done{C.field_values(node, "fields")}
        +names : List<&2, String> <- field_names(fields)
        valid : Unit <- unique(names, node)
        patterns : List<&2, Pattern> <- parse_patterns(rest, PatternNodes{fields})
        return [RecordPattern{names, patterns}]
    case 1n+rest PatternNode{FieldNode{}, +node}:
      parse_patterns(rest, PatternField{node, C.field_values(node, "value")})
    case 1n+rest PatternField{node, Nil{}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
        name : C.Cst <- C.one(C.field_values(node, "name"))
        return [Binding{C.type_name(name)}]
    case 1n+rest PatternField{node, values}:
      parse_patterns(rest, PatternNodes{values})

def binding_names(fuel: Nat, patterns: List<&2, Pattern>) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match fuel patterns:
    case 0n _:
      Fail{M.Diagnostic{"type_argument", "type", "type parameter pattern exceeds the source-tree limit"}}
    case 1n+rest Nil{}:
      Done{Nil{}}
    case 1n+rest Binding{name} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, String>>:
        names : List<&2, String> <- binding_names(rest, tail)
        return name <> names
    case 1n+rest TuplePattern{elements} <> tail:
      binding_names(rest, List.append(&2, Pattern, elements, tail))
    case 1n+rest ArrayPattern{elements} <> tail:
      binding_names(rest, List.append(&2, Pattern, elements, tail))
    case 1n+rest RecordPattern{names, fields} <> tail:
      binding_names(rest, List.append(&2, Pattern, fields, tail))

def parameters(+node: C.Cst) -> Result<&2, &2, M.Diagnostic, List<&2, Pattern>>:
  parse_patterns(65536n, PatternNodes{C.field_values(node, "parameters")})
