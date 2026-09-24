import Base
import ./model.bend as M
import ./types.bend as T
import ./index.bend as Index

type ConstructorType is Data:
  ConstructorType{result: M.Ty, payload: Maybe<&2, M.Ty>, next: Nat}

type ConstructorDefinition is Data:
  ConstructorDefinition{identity: M.TypeId, parameters: Nat, payload: Maybe<&2, M.Ty>}

def lookup_work(types: List<&2, M.DataType>, +identity: M.TypeId, found: Maybe<&2, M.DataType>) -> Maybe<&2, M.DataType>:
  match types found:
    case _ Some{declaration}:
      Some{declaration}
    case Nil{} None{}:
      None{}
    case M.DataType{+declared, parameters, constructors} <> tail None{}:
      lookup_work(tail, identity, Bool.pick(Maybe<&2, M.DataType>, M.type_id_equal(declared, identity), Some{M.DataType{declared, parameters, constructors}}, None{}))

def lookup(types: List<&2, M.DataType>, identity: M.TypeId) -> Maybe<&2, M.DataType>:
  lookup_work(types, identity, None{})

def constructor_in_work(constructors: List<&2, M.Constructor>, +name: String, +identity: M.TypeId, +parameters: Nat, found: Maybe<&2, ConstructorDefinition>) -> Maybe<&2, ConstructorDefinition>:
  match constructors found:
    case _ Some{declaration}:
      Some{declaration}
    case Nil{} None{}:
      None{}
    case M.Constructor{declared, payload, fields} <> tail None{}:
      constructor_in_work(tail, name, identity, parameters, Bool.pick(Maybe<&2, ConstructorDefinition>, M.name_equal(declared, name), Some{ConstructorDefinition{identity, parameters, payload}}, None{}))

def constructor_in(constructors: List<&2, M.Constructor>, name: String, identity: M.TypeId, parameters: Nat) -> Maybe<&2, ConstructorDefinition>:
  constructor_in_work(constructors, name, identity, parameters, None{})

def constructor_work(types: List<&2, M.DataType>, +name: String, found: Maybe<&2, ConstructorDefinition>) -> Maybe<&2, ConstructorDefinition>:
  match types found:
    case _ Some{declaration}:
      Some{declaration}
    case Nil{} None{}:
      None{}
    case M.DataType{identity, parameters, constructors} <> tail None{}:
      constructor_work(tail, name, constructor_in(constructors, name, identity, parameters))

def constructor(types: List<&2, M.DataType>, name: String) -> Maybe<&2, ConstructorDefinition>:
  constructor_work(types, name, None{})

def fresh_arguments_accumulated(count: Nat, +start: Nat, reversed: List<&2, M.Ty>) -> List<&2, M.Ty>:
  match count:
    case 0n:
      List.reverse(&2, M.Ty, reversed)
    case 1n+rest:
      fresh_arguments_accumulated(rest, 1n+start, M.VariableTy{start} <> reversed)

def fresh_arguments(count: Nat, start: Nat) -> List<&2, M.Ty>:
  fresh_arguments_accumulated(count, start, Nil{})

def instance_payload(payload: Maybe<&2, M.Ty>, arguments: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  match payload:
    case None{}:
      Done{None{}}
    case Some{ty}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
        value : M.Ty <- T.parameters(arguments, 0n, ty)
        return Some{value}

def instantiate(found: Maybe<&2, ConstructorDefinition>, name: String, +start: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, ConstructorType>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"unknown_constructor", subject, "unknown constructor " ++ name}}
    case Some{ConstructorDefinition{identity, +count, payload}}:
      +arguments = fresh_arguments(count, start)
      do Result<&2, &2, M.Diagnostic, ConstructorType>:
        value : Maybe<&2, M.Ty> <- instance_payload(payload, arguments)
        return ConstructorType{M.AppliedTy{identity, arguments}, value, Nat.add(start, count)}

def operation_work(operations: List<&2, M.Operation>, +identity: M.TypeId, found: Maybe<&2, M.Operation>) -> Maybe<&2, M.Operation>:
  match operations found:
    case _ Some{declaration}:
      Some{declaration}
    case Nil{} None{}:
      None{}
    case M.Operation{+declared, parameter, result} <> tail None{}:
      operation_work(tail, identity, Bool.pick(Maybe<&2, M.Operation>, M.type_id_equal(declared, identity), Some{M.Operation{declared, parameter, result}}, None{}))
    case head <> tail None{}:
      operation_work(tail, identity, None{})

def operation(operations: List<&2, M.Operation>, identity: M.TypeId) -> Maybe<&2, M.Operation>:
  operation_work(operations, identity, None{})

def require_unsealed_operation(sealed: Bool, found: Maybe<&2, M.Operation>, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match sealed:
    case True{}:
      Fail{M.Diagnostic{"sealed_effect", M.type_id_show(identity), "Foreign is a compiler effect label, not a callable or providable operation"}}
    case False{}:
      match found:
        case Some{declaration}:
          Done{declaration}
        case None{}:
          Fail{M.Diagnostic{"unknown_operation", M.type_id_show(identity), "unknown effect operation"}}

def require_operation(found: Maybe<&2, M.Operation>, +identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  require_unsealed_operation(M.is_foreign(identity), found, identity)

def require_effect_label(sealed: Bool, found: Maybe<&2, M.Operation>, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  match sealed:
    case True{}:
      Done{Unit{}}
    case False{}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        declared : M.Operation <- require_operation(found, identity)
        return Unit{}

def valid_effect_label(operations: List<&2, M.Operation>, +identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  require_effect_label(M.is_foreign(identity), operation(operations, identity), identity)

def unsealed_declaration(sealed: Bool, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  match sealed:
    case False{}:
      Done{Unit{}}
    case True{}:
      Fail{M.Diagnostic{"sealed_effect", M.type_id_show(identity), "the compiler-reserved Foreign effect cannot be declared as an operation"}}

def valid_operation_identity(+identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  unsealed_declaration(M.is_foreign(identity), identity)

def valid_parameter(parameters: Maybe<&2, Nat>, index: Nat) -> Bool:
  match parameters:
    case None{}:
      False{}
    case Some{count}:
      Nat.is_lt(index, count)

def require(valid: Bool, subject: String, message: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match valid:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"invalid_annotation", subject, message}}

def valid_arity(found: Maybe<&2, M.DataType>, count: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"unknown_type", subject, "unknown nominal data type"}}
    case Some{M.DataType{identity, arity, constructors}}:
      require(Nat.is_eq(arity, count), subject, "wrong number of type arguments")

def valid_row_tail(tail: M.RowTail, parameters: Maybe<&2, Nat>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match tail:
    case M.ClosedRow{}:
      Done{Unit{}}
    case M.RowParameter{index}:
      require(valid_parameter(parameters, index), subject, "effect parameter index is outside its quantified scope")
    case M.RowVariable{index}:
      Fail{M.Diagnostic{"invalid_annotation", subject, "effect inference variables are compiler-owned"}}

def valid_row_operations(identities: List<&2, M.TypeId>, +operations: List<&2, M.Operation>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match identities:
    case Nil{}:
      Done{Unit{}}
    case +identity <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        known : Unit <- valid_effect_label(operations, identity)
        valid_row_operations(tail, operations)

def validate_row(row: M.EffectRow, parameters: Maybe<&2, Nat>, operations: List<&2, M.Operation>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  M.EffectRow{identities, tail} = row
  do Result<&2, &2, M.Diagnostic, Unit>:
    valid : Unit <- valid_row_tail(tail, parameters, subject)
    valid_row_operations(identities, operations)

def require_product_arity(count: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match count:
    case 0n:
      Fail{M.Diagnostic{"product_arity", subject, "products require at least two elements; use Unit for an empty value"}}
    case 1n:
      Fail{M.Diagnostic{"product_arity", subject, "products require at least two elements; a single value does not need a product"}}
    case 2n+rest:
      Done{Unit{}}

def free_annotation(parameters: Maybe<&2, Nat>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match parameters:
    case None{}:
      Done{Unit{}}
    case Some{count}:
      Fail{M.Diagnostic{"invalid_annotation", subject, "free annotation names cannot escape into quantified type declarations"}}

def validate_work(+fuel: Nat, work: T.TypeWork, +parameters: Maybe<&2, Nat>, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match fuel work:
    case 0n _:
      Fail{T.complexity()}
    case 1n+rest T.OneType{M.VariableTy{index}}:
      Fail{M.Diagnostic{"invalid_annotation", subject, "inference variables are compiler-owned"}}
    case 1n+rest T.OneType{M.NeverTy{}}:
      Fail{M.Diagnostic{"invalid_annotation", subject, "Never is an internal control-flow type"}}
    case 1n+rest T.OneType{M.FreeTy{scope, name}}:
      free_annotation(parameters, subject)
    case 1n+rest T.OneType{M.ParameterTy{index}}:
      require(valid_parameter(parameters, index), subject, "type parameter index is outside its data declaration")
    case 1n+rest T.OneType{M.AppliedTy{identity, +arguments}}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        arity : Unit <- valid_arity(lookup(types, identity), List.length(&2, M.Ty, arguments), subject)
        validate_work(rest, T.ManyTypes{arguments}, parameters, operations, types, subject)
    case 1n+rest T.OneType{M.ProductTy{+elements}}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        arity : Unit <- require_product_arity(List.length(&2, M.Ty, elements), subject)
        validate_work(rest, T.ManyTypes{elements}, parameters, operations, types, subject)
    case 1n+rest T.OneType{M.ArrayTy{element}}:
      validate_work(rest, T.OneType{element}, parameters, operations, types, subject)
    case 1n+rest T.OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        row : Unit <- validate_row(effects, parameters, operations, subject)
        p : Unit <- validate_work(rest, T.OneType{parameter}, parameters, operations, types, subject)
        validate_work(rest, T.OneType{result}, parameters, operations, types, subject)
    case 1n+rest T.OneType{M.StateProviderTy{+read, +write, state}}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        reader : M.Operation <- require_operation(operation(operations, read), read)
        writer : M.Operation <- require_operation(operation(operations, write), write)
        validate_work(rest, T.OneType{state}, parameters, operations, types, subject)
    case 1n+rest T.OneType{M.ProviderTy{+identity, effects}}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        known : M.Operation <- require_operation(operation(operations, identity), identity)
        validate_row(effects, parameters, operations, subject)
    case 1n+rest T.OneType{scalar}:
      Done{Unit{}}
    case 1n+rest T.ManyTypes{Nil{}}:
      Done{Unit{}}
    case 1n+rest T.ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        h : Unit <- validate_work(rest, T.OneType{head}, parameters, operations, types, subject)
        validate_work(rest, T.ManyTypes{tail}, parameters, operations, types, subject)

def validate_template(+ty: M.Ty, parameters: Maybe<&2, Nat>, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, +subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  do Result<&2, &2, M.Diagnostic, Unit>:
    valid : Unit <- validate_work(U32.to_nat(65536), T.OneType{ty}, parameters, operations, types, subject)
    kinds : T.ParameterKinds <- T.parameter_kinds(U32.to_nat(65536), T.OneType{ty})
    T.kind_check(kinds, subject)

def annotation(value: Maybe<&2, M.Ty>, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match value:
    case None{}:
      Done{Unit{}}
    case Some{ty}:
      validate_template(ty, None{}, operations, types, subject)

def datatype_parameter_kinds(kinds: T.ParameterKinds, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match kinds:
    case T.ParameterKinds{types, Nil{}}:
      Done{Unit{}}
    case T.ParameterKinds{types, head <> tail}:
      Fail{M.Diagnostic{"kind_mismatch", subject, "data declaration parameters are value types, not effect rows"}}

def field_shape(fields: List<&2, String>, payload: Maybe<&2, M.Ty>) -> Bool:
  match fields payload:
    case Nil{} _:
      True{}
    case name <> Nil{} Some{ty}:
      True{}
    case +fields Some{M.ProductTy{elements}}:
      Nat.is_eq(List.length(&2, String, fields), List.length(&2, M.Ty, elements))
    case _ _:
      False{}

def unique_fields(fields: List<&2, String>, +subject: String, +seen: Set()) -> Result<&2, &2, M.Diagnostic, Unit>:
  match fields:
    case Nil{}:
      Done{Unit{}}
    case +head <> +tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        valid : Unit <- require(Bool.not(Maybe.is_some(&2, Unit, Index.find(Unit, seen, head))), subject, "record field names must be unique")
        unique_fields(tail, subject, Set.add(seen, head))

def validate_constructors(constructors: List<&2, M.Constructor>, +parameters: Nat, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match constructors:
    case Nil{}:
      Done{Unit{}}
    case M.Constructor{+name, None{}, fields} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        valid : Unit <- require(field_shape(fields, None{}), name, "record fields require a payload")
        validate_constructors(tail, parameters, operations, types)
    case M.Constructor{+name, Some{+payload}, +fields} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        shape : Unit <- require(field_shape(fields, Some{payload}), name, "record fields must match the constructor payload")
        unique : Unit <- unique_fields(fields, name, Set.new())
        valid : Unit <- validate_work(U32.to_nat(65536), T.OneType{payload}, Some{parameters}, operations, types, name)
        kinds : T.ParameterKinds <- T.parameter_kinds(U32.to_nat(65536), T.OneType{payload})
        values : Unit <- datatype_parameter_kinds(kinds, name)
        validate_constructors(tail, parameters, operations, types)
