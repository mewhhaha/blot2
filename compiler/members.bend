import Base
import ./model.bend as M
import ./type_data.bend as Types

def position_work(fields: List<&2, String>, +member: String, +index: Nat, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match fields found:
    case _ Some{index}:
      Some{index}
    case Nil{} None{}:
      None{}
    case field <> tail None{}:
      position_work(tail, member, 1n+index, Bool.pick(Maybe<&2, Nat>, M.name_equal(field, member), Some{index}, None{}))

def position(fields: List<&2, String>, member: String, index: Nat) -> Maybe<&2, Nat>:
  position_work(fields, member, index, None{})

def shared(constructors: List<&2, M.Constructor>, +member: String) -> Bool:
  match constructors:
    case Nil{}:
      True{}
    case M.Constructor{name, payload, fields} <> tail:
      Bool.and(Maybe.is_some(&2, Nat, position(fields, member, 0n)), shared(tail, member))

def projection(single: Bool, index: Nat) -> M.Expr:
  match single:
    case True{}:
      M.LocalExpr{"$field.payload"}
    case False{}:
      M.ProjectExpr{M.LocalExpr{"$field.payload"}, index}

def replacements(fields: List<&2, String>, +member: String, +single: Bool, +index: Nat) -> List<&2, M.Expr>:
  match fields:
    case Nil{}:
      Nil{}
    case field <> tail:
      Bool.pick(M.Expr, M.name_equal(field, member), M.LocalExpr{"$field.replacement"}, projection(single, index)) <> replacements(tail, member, single, 1n+index)

def payload(elements: List<&2, M.Expr>) -> M.Expr:
  match elements:
    case value <> Nil{}:
      value
    case elements:
      M.ProductExpr{elements}

def access_at(found: Maybe<&2, Nat>, dispatch: M.Dispatch, constructor: String, +fields: List<&2, String>, +member: String) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match found dispatch:
    case None{} _:
      Fail{M.Diagnostic{"internal_error", member, "record field disappeared during member selection"}}
    case Some{index} M.FieldUpdateDispatch{}:
      Done{M.ConstructExpr{constructor, Some{payload(replacements(fields, member, Nat.is_eq(List.length(&2, String, fields), 1n), 0n))}}}
    case Some{index} _:
      Done{projection(Nat.is_eq(List.length(&2, String, fields), 1n), index)}

def arms(constructors: List<&2, M.Constructor>, +dispatch: M.Dispatch, +member: String) -> Result<&2, &2, M.Diagnostic, List<&2, M.MatchArm<M.Expr>>>:
  match constructors:
    case Nil{}:
      Done{Nil{}}
    case M.Constructor{+constructor, ty, +fields} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.MatchArm<M.Expr>>>:
        body : M.Expr <- access_at(position(fields, member, 0n), dispatch, constructor, fields, member)
        following : List<&2, M.MatchArm<M.Expr>> <- arms(tail, dispatch, member)
        return M.MatchArm{[M.ConstructorPattern{constructor, Some{M.BindingPattern{"$field.payload"}}}], body} <> following

def body(dispatch: M.Dispatch, branches: List<&2, M.MatchArm<M.Expr>>, identity: Nat) -> M.Expr:
  match dispatch:
    case M.FieldUpdateDispatch{}:
      M.LambdaExpr{identity, "$field.replacement", None{}, None{}, M.MatchExpr{[M.LocalExpr{"$field.receiver"}], branches}}
    case _:
      M.MatchExpr{[M.LocalExpr{"$field.receiver"}], branches}

def function(constructors: List<&2, M.Constructor>, +dispatch: M.Dispatch, member: String, name: String, identity: Nat) -> Result<&2, &2, M.Diagnostic, M.Function>:
  do Result<&2, &2, M.Diagnostic, M.Function>:
    branches : List<&2, M.MatchArm<M.Expr>> <- arms(constructors, dispatch, member)
    return M.Function{name, False{}, "$field.receiver", None{}, None{}, body(dispatch, branches, identity)}

def declared_constructors(found: Maybe<&2, M.DataType>) -> List<&2, M.Constructor>:
  match found:
    case Some{M.DataType{identity, parameters, constructors}}:
      constructors
    case None{}:
      Nil{}

def constructors(ty: M.Ty, types: List<&2, M.DataType>) -> List<&2, M.Constructor>:
  match ty:
    case M.AppliedTy{identity, arguments}:
      declared_constructors(Types.lookup(types, identity))
    case _:
      Nil{}

def has_field(constructors: List<&2, M.Constructor>, member: String) -> Bool:
  match constructors:
    case Nil{}:
      False{}
    case constructors:
      shared(constructors, member)
