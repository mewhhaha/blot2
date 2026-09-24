import Base
import ../../../compiler/model.bend as M
import ../../../compiler/types.bend as Types

def Seed.read() -> IO(U32):
  import "./free_oracle_seed.c"
  import "./free_oracle_seed.js"

# Independent source-level oracle. The C specialization patches only
# Types.free_work; this copy keeps its original recursive ownership behavior.
def reference(+fuel: Nat, work: Types.TypeWork) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match fuel work:
    case 0n _:
      Fail{Types.complexity()}
    case 1n+rest Types.OneType{M.VariableTy{index}}:
      Done{[index]}
    case 1n+rest Types.OneType{M.FunctionTy{parameter, result, effects}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        p : List<&2, Nat> <- reference(rest, Types.OneType{parameter})
        r : List<&2, Nat> <- reference(rest, Types.OneType{result})
        return Types.union(Types.row_free(effects), Types.union(p, r))
    case 1n+rest Types.OneType{M.StateProviderTy{read, write, state}}:
      reference(rest, Types.OneType{state})
    case 1n+rest Types.OneType{M.ProviderTy{identity, effects}}:
      Done{Types.row_free(effects)}
    case 1n+rest Types.OneType{M.AppliedTy{identity, arguments}}:
      reference(rest, Types.ManyTypes{arguments})
    case 1n+rest Types.OneType{M.ProductTy{elements}}:
      reference(rest, Types.ManyTypes{elements})
    case 1n+rest Types.OneType{M.ArrayTy{element}}:
      reference(rest, Types.OneType{element})
    case 1n+rest Types.OneType{other}:
      Done{Nil{}}
    case 1n+rest Types.ManyTypes{Nil{}}:
      Done{Nil{}}
    case 1n+rest Types.ManyTypes{head <> tail}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        h : List<&2, Nat> <- reference(rest, Types.OneType{head})
        t : List<&2, Nat> <- reference(rest, Types.ManyTypes{tail})
        return Types.union(h, t)

def same_list(left: List<&2, Nat>, right: List<&2, Nat>) -> Bool:
  match left right:
    case Nil{} Nil{}:
      True{}
    case a <> aa b <> bb:
      Bool.and(Nat.is_eq(a, b), same_list(aa, bb))
    case _ _:
      False{}

def same_result(left: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, right: Result<&2, &2, M.Diagnostic, List<&2, Nat>>) -> Bool:
  match left right:
    case Done{a} Done{b}:
      same_list(a, b)
    case Fail{M.Diagnostic{a, b, c}} Fail{M.Diagnostic{x, y, z}}:
      Bool.and(M.name_equal(a, x), Bool.and(M.name_equal(b, y), M.name_equal(c, z)))
    case _ _:
      False{}

def check_all(types: List<&2, M.Ty>, +fuel: Nat) -> Bool:
  match types:
    case Nil{}:
      True{}
    case +head <> tail:
      Bool.and(same_result(Types.free_work(fuel, Types.OneType{head}), reference(fuel, Types.OneType{head})), check_all(tail, fuel))

def check_fuels(+types: List<&2, M.Ty>, fuels: List<&2, Nat>) -> Bool:
  match fuels:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(check_all(types, head), check_fuels(types, tail))

def generated(+depth: Nat, branch: Nat, +seed: Nat) -> M.Ty:
  match depth:
    case 0n:
      M.VariableTy{Nat.mod(seed, 23n)}
    case 1n+rest:
      match branch:
        case 0n:
          M.FunctionTy{generated(rest, Nat.mod(Nat.add(seed, 1n), 6n), Nat.add(seed, 1n)), generated(rest, Nat.mod(Nat.add(seed, 2n), 6n), Nat.add(seed, 2n)), M.EffectRow{[M.TypeId{"oracle", "E"}, M.TypeId{"oracle", "E"}], M.RowVariable{Nat.mod(seed, 23n)}}}
        case 1n:
          M.ProductTy{[generated(rest, Nat.mod(Nat.add(seed, 3n), 6n), Nat.add(seed, 3n)), generated(rest, Nat.mod(Nat.add(seed, 4n), 6n), Nat.add(seed, 4n)), generated(rest, Nat.mod(Nat.add(seed, 5n), 6n), Nat.add(seed, 5n))]}
        case 2n:
          M.AppliedTy{M.TypeId{"oracle", "G"}, [generated(rest, Nat.mod(Nat.add(seed, 6n), 6n), Nat.add(seed, 6n)), generated(rest, Nat.mod(Nat.add(seed, 7n), 6n), Nat.add(seed, 7n))]}
        case 3n:
          M.ArrayTy{generated(rest, Nat.mod(Nat.add(seed, 8n), 6n), Nat.add(seed, 8n))}
        case 4n:
          M.StateProviderTy{M.TypeId{"oracle", "Read"}, M.TypeId{"oracle", "Write"}, generated(rest, Nat.mod(Nat.add(seed, 9n), 6n), Nat.add(seed, 9n))}
        case _:
          M.ProviderTy{M.TypeId{"oracle", "P"}, M.EffectRow{Nil{}, M.RowVariable{Nat.mod(seed, 23n)}}}

def wide(+count: Nat, +seed: Nat) -> List<&2, M.Ty>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      M.VariableTy{Nat.mod(Nat.add(seed, rest), 64n)} <> wide(rest, seed)

def examples(+seed: Nat) -> List<&2, M.Ty>:
  +id : M.TypeId = M.TypeId{"oracle", "T"}
  +row : M.EffectRow = M.EffectRow{[id, id], M.RowVariable{3n}}
  [
    M.VariableTy{seed},
    M.VariableTy{1n+4294967295n},
    M.U32Ty{},
    M.FunctionTy{M.VariableTy{1n}, M.VariableTy{2n}, row},
    M.ProductTy{[M.VariableTy{1n}, M.VariableTy{2n}, M.VariableTy{1n}]},
    M.ProductTy{[M.ProductTy{[M.VariableTy{1n}, M.VariableTy{2n}]}, M.VariableTy{3n}]},
    M.AppliedTy{id, [M.VariableTy{4n}, M.ArrayTy{M.VariableTy{5n}}]},
    M.ProviderTy{id, row},
    M.StateProviderTy{id, id, M.ArrayTy{M.VariableTy{6n}}},
    M.FunctionTy{M.FunctionTy{M.VariableTy{1n}, M.VariableTy{2n}, row}, M.ProductTy{[M.VariableTy{3n}, M.VariableTy{1n}]}, row},
    generated(3n, Nat.mod(seed, 6n), seed),
    generated(4n, Nat.mod(Nat.add(seed, 1n), 6n), Nat.add(seed, 1n)),
    generated(5n, Nat.mod(Nat.add(seed, 2n), 6n), Nat.add(seed, 2n)),
    generated(7n, 0n, seed),
    M.ProductTy{wide(520n, seed)},
  ]

def main() -> IO(Unit):
  do IO<Unit>:
    seed : U32 <- Seed.read()
    IO.print(Bool.show(check_fuels(examples(U32.to_nat(seed)), [0n, 1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 16n, 65536n])))
