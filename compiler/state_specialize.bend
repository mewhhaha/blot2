import Base
import ./model.bend as M
import ./effects.bend as E

type Request is Data:
  Read{}
  Write{}
  Run{}
  Reader{}
  Writer{}

def request(+member: String) -> Maybe<&2, Request>:
  Bool.pick(Maybe<&2, Request>, M.name_equal(member, "@state.get"), Some{Read{}},
    Bool.pick(Maybe<&2, Request>, M.name_equal(member, "@state.set"), Some{Write{}},
    Bool.pick(Maybe<&2, Request>, Bool.or(M.name_equal(member, "@state.run"), M.name_equal(member, "@effect.run")), Some{Run{}},
    Bool.pick(Maybe<&2, Request>, Bool.or(M.name_equal(member, "@state.reader"), M.name_equal(member, "@effect.reader")), Some{Reader{}},
    Bool.pick(Maybe<&2, Request>, Bool.or(M.name_equal(member, "@state.writer"), M.name_equal(member, "@effect.writer")), Some{Writer{}}, None{})))))

def witness(fuel: Nat, ty: M.Ty) -> M.Ty:
  match fuel ty:
    case 1n+rest M.FunctionTy{parameter, result, effects}:
      witness(rest, result)
    case _ other:
      other

def state_type(request: Request, left: M.Ty) -> M.Ty:
  match request:
    case Write{}:
      left
    case Run{}:
      left
    case _:
      witness(65536n, left)

type KeyWork is Data:
  TypeKey{ty: M.Ty}
  TypesKey{types: List<&2, M.Ty>}

def packed(+value: String) -> String:
  Nat.show(String.length(value)) ++ ":" ++ value

def nominal(identity: M.TypeId) -> String:
  M.TypeId{module_name, declaration} = identity
  packed(module_name) ++ packed(declaration)

def operation_keys(operations: List<&2, M.TypeId>) -> String:
  match operations:
    case Nil{}:
      ""
    case head <> tail:
      packed(nominal(head)) ++ operation_keys(tail)

def operation_less(left: M.TypeId, right: M.TypeId) -> Bool:
  E.effect_le(M.OperationEffect{left}, M.OperationEffect{right})

def row_key(row: M.EffectRow) -> Result<&2, &2, M.Diagnostic, String>:
  match row:
    case M.EffectRow{operations, M.ClosedRow{}}:
      Done{operation_keys(List.sort(~M.TypeId, ~operation_less, operations))}
    case _:
      Fail{M.Diagnostic{"ambiguous_state", "state", "state identity requires closed effect rows"}}


# Length-delimited structural keys preserve nominal ownership and type arguments.
def type_key(+fuel: Nat, work: KeyWork) -> Result<&2, &2, M.Diagnostic, String>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"specialization_limit", "state", "state type exceeds its structural limit"}}
    case 1n+rest TypeKey{M.UnitTy{}}:
      Done{"u"}
    case 1n+rest TypeKey{M.U32Ty{}}:
      Done{"i"}
    case 1n+rest TypeKey{M.F32Ty{}}:
      Done{"f"}
    case 1n+rest TypeKey{M.BoolTy{}}:
      Done{"b"}
    case 1n+rest TypeKey{M.AppliedTy{identity, arguments}}:
      do Result<&2, &2, M.Diagnostic, String>:
        args : String <- type_key(rest, TypesKey{arguments})
        return "n" ++ nominal(identity) ++ packed(args)
    case 1n+rest TypeKey{M.ArrayTy{element}}:
      do Result<&2, &2, M.Diagnostic, String>:
        value : String <- type_key(rest, TypeKey{element})
        return "a" ++ packed(value)
    case 1n+rest TypeKey{M.ProductTy{elements}}:
      do Result<&2, &2, M.Diagnostic, String>:
        values : String <- type_key(rest, TypesKey{elements})
        return "p" ++ packed(values)
    case 1n+rest TypeKey{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, String>:
        p : String <- type_key(rest, TypeKey{parameter})
        r : String <- type_key(rest, TypeKey{result})
        e : String <- row_key(effects)
        return "c" ++ packed(p) ++ packed(r) ++ packed(e)
    case 1n+rest TypesKey{Nil{}}:
      Done{""}
    case 1n+rest TypesKey{head <> tail}:
      do Result<&2, &2, M.Diagnostic, String>:
        value : String <- type_key(rest, TypeKey{head})
        remaining : String <- type_key(rest, TypesKey{tail})
        return packed(value) ++ remaining
    case _ _:
      Fail{M.Diagnostic{"ambiguous_state", "state", "state requires a concrete runtime value type"}}

def read_identity(key: String) -> M.TypeId:
  M.TypeId{"blot:state", "read:" ++ key}

def write_identity(key: String) -> M.TypeId:
  M.TypeId{"blot:state", "write:" ++ key}

def contains_step(equal: Bool, remaining: Unit -> Bool) -> Bool:
  match equal:
    case True{}:
      True{}
    case False{}:
      remaining(Unit{})

def contains(operations: List<&2, M.Operation>, +identity: M.TypeId) -> Bool:
  match operations:
    case Nil{}:
      False{}
    case M.Operation{found, parameter, result} <> tail:
      contains_step(M.type_id_equal(found, identity), unit => contains(tail, identity))
    case head <> tail:
      contains(tail, identity)

def concrete(operations: List<&2, M.Operation>) -> List<&2, M.Operation>:
  match operations:
    case Nil{}:
      Nil{}
    case M.Operation{identity, parameter, result} <> tail:
      M.Operation{identity, parameter, result} <> concrete(tail)
    case head <> tail:
      concrete(tail)

def merge_operation(present: Bool, operations: List<&2, M.Operation>, operation: M.Operation) -> List<&2, M.Operation>:
  match present:
    case True{}:
      operations
    case False{}:
      List.append(&2, M.Operation, operations, [operation])

def merge(incoming: List<&2, M.Operation>, +operations: List<&2, M.Operation>) -> List<&2, M.Operation>:
  match incoming:
    case Nil{}:
      operations
    case M.Operation{+identity, parameter, result} <> tail:
      +operation : M.Operation = M.Operation{identity, parameter, result}
      merge(tail, merge_operation(contains(operations, identity), operations, operation))
    case head <> tail:
      merge(tail, operations)

def operations(+key: String, +ty: M.Ty, existing: List<&2, M.Operation>) -> List<&2, M.Operation>:
  merge([M.Operation{read_identity(key), M.UnitTy{}, ty}, M.Operation{write_identity(key), ty, M.UnitTy{}}], existing)

def body(request: Request, +read: M.TypeId, +write: M.TypeId) -> M.Expr:
  match request:
    case Read{}:
      M.ApplyExpr{M.OperationExpr{read}, M.UnitExpr{}}
    case Write{}:
      M.ApplyExpr{M.OperationExpr{write}, M.LocalExpr{"$state.left"}}
    case Run{}:
      M.HandleExpr{M.StateProviderExpr{read, write, M.LocalExpr{"$state.left"}}, M.ApplyExpr{M.LocalExpr{"$state.right"}, M.UnitExpr{}}}
    case Reader{}:
      M.MatchExpr{[M.LocalExpr{"$state.right"}], [M.MatchArm{[M.ProductPattern{[M.BindingPattern{"$state.implementation"}, M.BindingPattern{"$state.action"}]}], M.HandleExpr{M.ProviderExpr{read, M.LocalExpr{"$state.implementation"}}, M.ApplyExpr{M.LocalExpr{"$state.action"}, M.UnitExpr{}}}}]}
    case Writer{}:
      M.MatchExpr{[M.LocalExpr{"$state.right"}], [M.MatchArm{[M.ProductPattern{[M.BindingPattern{"$state.implementation"}, M.BindingPattern{"$state.action"}]}], M.HandleExpr{M.ProviderExpr{write, M.LocalExpr{"$state.implementation"}}, M.ApplyExpr{M.LocalExpr{"$state.action"}, M.UnitExpr{}}}}]}

def function_for(request: Request, read: M.TypeId, write: M.TypeId, name: String, identity: Nat) -> M.Function:
  M.Function{name, False{}, "$state.left", None{}, None{}, M.LambdaExpr{identity, "$state.right", None{}, None{}, body(request, read, write)}}

def function(request: Request, +key: String, name: String, identity: Nat) -> M.Function:
  function_for(request, read_identity(key), write_identity(key), name, identity)
