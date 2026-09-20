import Base
import ./model.bend as M
import ./types.bend as T

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
    case M.Constructor{declared, payload} <> tail None{}:
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

def fresh_arguments(count: Nat, +start: Nat) -> List<&2, M.Ty>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      M.VariableTy{start} <> fresh_arguments(rest, 1n+start)

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

def known_storage_work(descriptors: List<&2, M.Descriptor>, +identity: M.TypeId, found: Bool) -> Bool:
  match descriptors found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case M.Descriptor{declared, storage} <> tail False{}:
      known_storage_work(tail, identity, M.type_id_equal(declared, identity))

def known_storage(descriptors: List<&2, M.Descriptor>, identity: M.TypeId) -> Bool:
  known_storage_work(descriptors, identity, False{})

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

def require_storage(known: Bool, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  match known:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"unknown_storage", M.type_id_show(identity), "no component or resource descriptor for this type"}}

def storage_type(declaration: Maybe<&2, M.DataType>, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match declaration:
    case None{}:
      Done{M.NominalTy{identity}}
    case Some{M.DataType{declared, 0n, constructors}}:
      Done{M.AppliedTy{identity, Nil{}}}
    case Some{M.DataType{declared, 1n+parameters, constructors}}:
      Fail{M.Diagnostic{"generic_storage_type", M.type_id_show(identity), "component and resource registrations require a data type with no type parameters"}}

def opaque_annotation(declaration: Maybe<&2, M.DataType>, registered: Bool, identity: M.TypeId) -> Result<&2, &2, M.Diagnostic, Unit>:
  match declaration:
    case None{}:
      require_storage(registered, identity)
    case Some{declared}:
      Fail{M.Diagnostic{"invalid_annotation", M.type_id_show(identity), "declared data types use AppliedTy; NominalTy is reserved for opaque storage types"}}

def valid_arity(found: Maybe<&2, M.DataType>, count: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"unknown_type", subject, "unknown nominal data type"}}
    case Some{M.DataType{identity, arity, constructors}}:
      require(Nat.is_eq(arity, count), subject, "wrong number of type arguments")

def validate_work(+fuel: Nat, work: T.TypeWork, +parameters: Maybe<&2, Nat>, +descriptors: List<&2, M.Descriptor>, +types: List<&2, M.DataType>, +subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match fuel work:
    case 0n _:
      Fail{T.complexity()}
    case 1n+rest T.OneType{M.VariableTy{index}}:
      Fail{M.Diagnostic{"invalid_annotation", subject, "inference variables are compiler-owned"}}
    case 1n+rest T.OneType{M.NeverTy{}}:
      Fail{M.Diagnostic{"invalid_annotation", subject, "Never is an internal control-flow type"}}
    case 1n+rest T.OneType{M.ParameterTy{index}}:
      require(valid_parameter(parameters, index), subject, "type parameter index is outside its data declaration")
    case 1n+rest T.OneType{M.NominalTy{+identity}}:
      opaque_annotation(lookup(types, identity), known_storage(descriptors, identity), identity)
    case 1n+rest T.OneType{M.AppliedTy{identity, +arguments}}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        arity : Unit <- valid_arity(lookup(types, identity), List.length(&2, M.Ty, arguments), subject)
        validate_work(rest, T.ManyTypes{arguments}, parameters, descriptors, types, subject)
    case 1n+rest T.OneType{M.FunctionTy{parameter, result}}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        p : Unit <- validate_work(rest, T.OneType{parameter}, parameters, descriptors, types, subject)
        validate_work(rest, T.OneType{result}, parameters, descriptors, types, subject)
    case 1n+rest T.OneType{scalar}:
      Done{Unit{}}
    case 1n+rest T.ManyTypes{Nil{}}:
      Done{Unit{}}
    case 1n+rest T.ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, Unit>:
        h : Unit <- validate_work(rest, T.OneType{head}, parameters, descriptors, types, subject)
        validate_work(rest, T.ManyTypes{tail}, parameters, descriptors, types, subject)

def annotation(value: Maybe<&2, M.Ty>, descriptors: List<&2, M.Descriptor>, types: List<&2, M.DataType>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match value:
    case None{}:
      Done{Unit{}}
    case Some{ty}:
      validate_work(Nat.mul(256n, 256n), T.OneType{ty}, None{}, descriptors, types, subject)

def validate_constructors(constructors: List<&2, M.Constructor>, +parameters: Nat, +descriptors: List<&2, M.Descriptor>, +types: List<&2, M.DataType>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match constructors:
    case Nil{}:
      Done{Unit{}}
    case M.Constructor{name, None{}} <> tail:
      validate_constructors(tail, parameters, descriptors, types)
    case M.Constructor{name, Some{payload}} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        valid : Unit <- validate_work(Nat.mul(256n, 256n), T.OneType{payload}, Some{parameters}, descriptors, types, name)
        validate_constructors(tail, parameters, descriptors, types)
