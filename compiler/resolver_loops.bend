import Base
import ./model.bend as M

# A loop passes the following iteration as a callback. A source bind may omit
# that callback, so failure skips both later iterations and the block suffix.
def body(+name: String, identity: Nat, forever: Bool) -> M.Expr:
  +index = {M.LocalExpr{"$loop$index"} : M.Expr}
  +end = {M.LocalExpr{"$loop$end"} : M.Expr}
  +state = {M.LocalExpr{"$loop$state"} : M.Expr}
  +step = {M.LocalExpr{"$loop$step"} : M.Expr}
  +done = {M.LocalExpr{"$loop$done"} : M.Expr}
  recur = {M.ApplyExpr{M.ApplyExpr{M.FunctionExpr{name}, M.LocalExpr{"$resolver$left"}}, M.ProductExpr{[M.ScalarExpr{M.Add{}, index, M.U32Expr{1}}, end, M.LocalExpr{"$loop$next"}, step, done]}} : M.Expr}
  action = {M.ApplyExpr{M.ApplyExpr{M.ApplyExpr{step, index}, state}, M.LambdaExpr{identity, "$loop$next", None{}, None{}, recur}} : M.Expr}
  +action = action
  branch = Bool.pick(M.Expr, forever, action, M.IfExpr{M.ScalarExpr{M.LessThan{}, index, end}, action, M.ApplyExpr{done, state}})
  M.MatchExpr{[M.LocalExpr{"$resolver$right"}], [M.MatchArm{[M.ProductPattern{[M.BindingPattern{"$loop$index"}, M.BindingPattern{"$loop$end"}, M.BindingPattern{"$loop$state"}, M.BindingPattern{"$loop$step"}, M.BindingPattern{"$loop$done"}]}], branch}]}
