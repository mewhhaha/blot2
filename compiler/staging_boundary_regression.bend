import Base
import ./model.bend as M
import ./infer.bend as I
import ./types.bend as T
import ./globals.bend as G
import ./staging_scheme.bend as Staging

def absent(found: Maybe<&2, G.Environment>) -> Bool:
  match found:
    case None{}: True{}
    case Some{environment}: False{}

# The replay allocation needs eight more IDs, but only one Nat48 ID remains.
# This must reject before constructing an out-of-range mapping or increment.
def valid() -> Bool:
  +source = {M.Function{"$prelude.Type.eq", False{}, "value", None{}, None{}, M.U32Expr{0}} : M.Function}
  +inference = {I.Inference{M.U32Ty{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}} : I.Inference}
  +scheme = {Staging.Scheme{source, inference, Nil{}, 11n, Nil{}} : Staging.Scheme}
  +placeholder = {Staging.Placeholder{0n, 1n, 2n, M.FunctionTy{M.VariableTy{0n}, M.VariableTy{1n}, M.EffectRow{Nil{}, M.RowVariable{2n}}}} : Staging.Placeholder}
  +environment = {G.Environment{Nil{}, Nil{}, I.State{T.empty(), Nat.sub(Staging.max_nat48(), 1n), MTip{}}} : G.Environment}
  absent(Staging.replay_placeholder(Some{placeholder}, scheme, source, Staging.CloneName{0n, "$prelude.Type.eq"}, 256n, environment))
