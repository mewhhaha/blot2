import Base
import ../../../compiler/model.bend as M
import ../../../compiler/types.bend as Types
import ../../../compiler/core_compare.bend as Compare

def Seed.read() -> IO(U32):
  import "./free_oracle_seed.c"
  import "./free_oracle_seed.js"

def same_types(left: List<&2, M.Ty>, right: List<&2, M.Ty>) -> Bool:
  match left right:
    case Nil{} Nil{}:
      True{}
    case a <> aa b <> bb:
      Bool.and(Compare.same_ty(a, b), same_types(aa, bb))
    case _ _:
      False{}

def same_result(left: Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>, right: Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>) -> Bool:
  match left right:
    case Done{a} Done{b}:
      same_types(a, b)
    case Fail{M.Diagnostic{a, b, c}} Fail{M.Diagnostic{x, y, z}}:
      Bool.and(M.name_equal(a, x), Bool.and(M.name_equal(b, y), M.name_equal(c, z)))
    case _ _:
      False{}

def check_jobs(jobs: List<&2, Types.TypeWork>, +substitutions: Types.Substitutions, +fuel: Nat) -> Bool:
  match jobs:
    case Nil{}:
      True{}
    case +job <> tail:
      Bool.and(same_result(Types.resolve_work(substitutions, fuel, job), Types.resolve_work_reference(substitutions, fuel, job)), check_jobs(tail, substitutions, fuel))

def wide(+count: Nat) -> List<&2, M.Ty>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      M.U32Ty{} <> wide(rest)

def jobs(+seed: Nat) -> List<&2, Types.TypeWork>:
  +id : M.TypeId = M.TypeId{"oracle", "N"}
  +closed : M.EffectRow = M.EffectRow{[id, id], M.ClosedRow{}}
  +open : M.EffectRow = M.EffectRow{[id, id], M.RowVariable{2n}}
  [
    Types.OneType{M.U32Ty{}},
    Types.OneType{M.ParameterTy{seed}},
    Types.OneType{M.FunctionTy{M.U32Ty{}, M.BoolTy{}, closed}},
    Types.OneType{M.FunctionTy{M.VariableTy{0n}, M.U32Ty{}, closed}},
    Types.OneType{M.ArrayTy{M.VariableTy{0n}}},
    Types.OneType{M.ProductTy{[M.VariableTy{0n}, M.U32Ty{}]}},
    Types.OneType{M.AppliedTy{id, [M.U32Ty{}, M.VariableTy{0n}]}},
    Types.OneType{M.StateProviderTy{id, id, M.VariableTy{0n}}},
    Types.OneType{M.FunctionTy{M.U32Ty{}, M.BoolTy{}, open}},
    Types.OneType{M.ProviderTy{id, closed}},
    Types.OneType{M.ProviderTy{id, open}},
    Types.OneType{M.StateProviderTy{id, id, M.ProductTy{[M.U32Ty{}, M.BoolTy{}]}}},
    Types.OneType{M.AppliedTy{id, [M.ArrayTy{M.U32Ty{}}, M.ProductTy{[M.BoolTy{}, M.ParameterTy{seed}]}]}},
    Types.OneType{M.ProductTy{wide(520n)}},
    Types.ManyTypes{[M.U32Ty{}, M.ArrayTy{M.BoolTy{}}, M.ParameterTy{seed}]},
    Types.ManyTypes{[M.U32Ty{}, M.VariableTy{0n}, M.FunctionTy{M.BoolTy{}, M.U32Ty{}, open}]},
  ]

def check_fuel(+jobs: List<&2, Types.TypeWork>, +seed: Nat, +fuel: Nat) -> Bool:
  +closed : M.EffectRow = M.EffectRow{[M.TypeId{"oracle", "E"}, M.TypeId{"oracle", "E"}], M.ClosedRow{}}
  +s0 = Types.empty()
  +s1 = Types.from_list([Types.Substitution{0n, M.BoolTy{}}])
  +s2 = Types.from_list([Types.Substitution{0n, M.VariableTy{1n}}, Types.Substitution{1n, M.U32Ty{}}, Types.RowSubstitution{2n, closed}])
  +s3 = Types.from_list([Types.Substitution{0n, M.VariableTy{seed}}, Types.Substitution{0n, M.ArrayTy{M.U32Ty{}}}, Types.RowSubstitution{2n, closed}])
  Bool.and(check_jobs(jobs, s0, fuel), Bool.and(check_jobs(jobs, s1, fuel), Bool.and(check_jobs(jobs, s2, fuel), check_jobs(jobs, s3, fuel))))

def check_fuels(+jobs: List<&2, Types.TypeWork>, +seed: Nat, fuels: List<&2, Nat>) -> Bool:
  match fuels:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(check_fuel(jobs, seed, head), check_fuels(jobs, seed, tail))

def main() -> IO(Unit):
  do IO<Unit>:
    seed : U32 <- Seed.read()
    +id : Nat = U32.to_nat(seed)
    IO.print(Bool.show(check_fuels(jobs(id), id, [0n, 1n, 2n, 3n, 4n, 8n, 65536n])))
