import Base
import ../../../compiler/model.bend as M
import ../../../compiler/types.bend as T

def nested() -> M.Ty:
  M.FunctionTy{
    M.ProductTy{[M.ArrayTy{M.VariableTy{1n}}, M.U32Ty{}]},
    M.AppliedTy{M.TypeId{"regression", "Box"}, [M.VariableTy{2n}]},
    M.EffectRow{Nil{}, M.ClosedRow{}}
  }

def shown(result: Result<&2, &2, M.Diagnostic, M.Ty>) -> String:
  match result:
    case Done{ty}:
      M.type_show(ty)
    case Fail{M.Diagnostic{code, subject, message}}:
      "FAIL " ++ code ++ " " ++ message

def shown_work(result: Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>) -> String:
  match result:
    case Done{head <> Nil{}}:
      M.type_show(head)
    case Done{other}:
      "FAIL wrong work width"
    case Fail{M.Diagnostic{code, subject, message}}:
      "FAIL " ++ code ++ " " ++ message

def index(args: List<String>) -> Nat:
  match args:
    case Nil{}:
      0n
    case head <> tail:
      1n

def report(+variable: Nat) -> String:
  shown(T.resolve(T.from_list([T.Substitution{0n, nested()}]), M.VariableTy{variable})) ++ "\n" ++
  shown(T.resolve(T.from_list([T.Substitution{0n, nested()}, T.Substitution{1n, M.BoolTy{}}, T.Substitution{2n, M.F32Ty{}}]), M.VariableTy{variable})) ++ "\n" ++
  shown(T.resolve(T.from_list([T.Substitution{0n, M.VariableTy{1n}}, T.Substitution{0n, M.BoolTy{}}, T.Substitution{1n, M.F32Ty{}}]), M.VariableTy{variable})) ++ "\n" ++
  shown_work(T.resolve_work(T.from_list([T.Substitution{0n, nested()}]), 1n, T.OneType{M.FunctionTy{M.VariableTy{variable}, M.U32Ty{}, M.EffectRow{Nil{}, M.ClosedRow{}}}}))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    IO.print(report(index(args)))
