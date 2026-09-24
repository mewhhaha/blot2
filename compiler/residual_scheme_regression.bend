import Base
import ./model.bend as M
import ./types.bend as T
import ./infer.bend as I
import ./residual_scheme.bend as S
import ./nat_index.bend as N
import ./core_compare.bend as CoreCompare
import ./groups.bend as Groups

def identity() -> M.TypeId:
  M.TypeId{"regression", "Clock"}

def labels() -> List<&2, M.TypeId>:
  [identity(), identity()]

def row(variable: Nat) -> M.EffectRow:
  M.EffectRow{labels(), M.RowVariable{variable}}

def type_before() -> M.Ty:
  M.ProductTy{[
    M.UnitTy{}, M.U32Ty{}, M.BoolTy{}, M.NeverTy{}, M.F32Ty{},
    M.EffectDescriptorTy{}, M.EffectSetTy{}, M.ParameterTy{7n},
    M.FreeTy{"scope", "free"}, M.VariableTy{2n}, M.VariableTy{9n},
    M.AppliedTy{identity(), [M.VariableTy{7n}, M.ArrayTy{M.VariableTy{2n}}]},
    M.FunctionTy{M.ProviderTy{identity(), row(7n)}, M.StateProviderTy{identity(), identity(), M.VariableTy{2n}}, row(2n)},
    M.ProductTy{[M.VariableTy{7n}, M.FunctionTy{M.VariableTy{2n}, M.UnitTy{}, M.EffectRow{Nil{}, M.RowParameter{3n}}}]}
  ]}

def type_after() -> M.Ty:
  M.ProductTy{[
    M.UnitTy{}, M.U32Ty{}, M.BoolTy{}, M.NeverTy{}, M.F32Ty{},
    M.EffectDescriptorTy{}, M.EffectSetTy{}, M.ParameterTy{7n},
    M.FreeTy{"scope", "free"}, M.VariableTy{21n}, M.VariableTy{9n},
    M.AppliedTy{identity(), [M.VariableTy{20n}, M.ArrayTy{M.VariableTy{21n}}]},
    M.FunctionTy{M.ProviderTy{identity(), row(20n)}, M.StateProviderTy{identity(), identity(), M.VariableTy{21n}}, row(21n)},
    M.ProductTy{[M.VariableTy{20n}, M.FunctionTy{M.VariableTy{21n}, M.UnitTy{}, M.EffectRow{Nil{}, M.RowParameter{3n}}}]}
  ]}

def type_matches(found: Result<&2, &2, M.Diagnostic, I.SchemeInstance>, expected: M.Ty, next: Nat) -> Bool:
  match found:
    case Done{I.SchemeInstance{ty, actual_next}}:
      Bool.and(CoreCompare.same_ty(ty, expected), Nat.is_eq(actual_next, next))
    case _:
      False{}

def type_checks() -> Bool:
  +before = type_before()
  Bool.and(type_matches(I.instance([7n, 2n], before, 20n), type_after(), 22n),
    Bool.and(type_matches(I.instance(Nil{}, before, 20n), before, 20n),
    Bool.and(type_matches(I.instance([2n, 2n], M.VariableTy{2n}, 20n), M.VariableTy{20n}, 22n),
      type_matches(I.instance([0n, 20n], M.VariableTy{0n}, 20n), M.VariableTy{21n}, 22n))))

def scoped_leaf_valid(found: Result<&2, &2, M.Diagnostic, M.Ty>) -> Bool:
  match found:
    case Done{M.FreeTy{"scope", "free"}}:
      True{}
    case _:
      False{}

def unchanged_scope_with(renaming: T.Renaming) -> Bool:
  match renaming:
    case T.Renaming{mapping, next, safe}:
      scoped_leaf_valid(T.rename_type(M.FreeTy{"scope", "free"}, mapping))

def unchanged_scope() -> Bool:
  unchanged_scope_with(T.renaming([7n], 20n))

def original_inference() -> I.Inference:
  I.Inference{
    M.FunctionTy{M.VariableTy{2n}, M.VariableTy{7n}, row(7n)},
    [I.OperationNeed{5n, identity(), [M.VariableTy{2n}], M.FunctionTy{M.VariableTy{2n}, M.VariableTy{7n}, row(7n)}, "operation source"},
     I.AssociatedNeed{6n, M.MemberDispatch{}, "member", [identity()], M.VariableTy{2n}, M.VariableTy{7n}, M.VariableTy{2n}, row(7n), "member source"},
     I.ValuePatternType{M.VariableTy{7n}, "value source"},
     I.Coverage{[M.VariableTy{2n}, M.VariableTy{7n}], [[M.WildcardPattern{}, M.U32Pattern{42}]], "pattern source"}],
    [5n, 7n], [I.Reflection{"callee", "reflection source"}]}

def identity_map() -> N.Index<Nat>:
  N.set(Nat, N.set(Nat, N.set(Nat, N.new(Nat), 5n, 50n), 6n, 60n), 7n, 70n)

def operation_valid(value: I.Coverage) -> Bool:
  match value:
    case I.OperationNeed{50n, _, M.VariableTy{20n} <> Nil{}, M.FunctionTy{M.VariableTy{20n}, M.VariableTy{21n}, effects}, "operation source"}:
      CoreCompare.same_ty(M.ProviderTy{identity(), effects}, M.ProviderTy{identity(), row(21n)})
    case _:
      False{}

def associated_valid(value: I.Coverage) -> Bool:
  match value:
    case I.AssociatedNeed{60n, M.MemberDispatch{}, "member", _, M.VariableTy{20n}, M.VariableTy{21n}, M.VariableTy{20n}, effects, "member source"}:
      CoreCompare.same_ty(M.ProviderTy{identity(), effects}, M.ProviderTy{identity(), row(21n)})
    case _:
      False{}

def value_valid(value: I.Coverage) -> Bool:
  match value:
    case I.ValuePatternType{M.VariableTy{21n}, "value source"}:
      True{}
    case _:
      False{}

def pattern_valid(value: I.Coverage) -> Bool:
  match value:
    case I.Coverage{M.VariableTy{20n} <> M.VariableTy{21n} <> Nil{}, (M.WildcardPattern{} <> M.U32Pattern{42} <> Nil{}) <> Nil{}, "pattern source"}:
      True{}
    case _:
      False{}

def coverages_valid(values: List<&2, I.Coverage>) -> Bool:
  match values:
    case operation <> associated <> value <> pattern <> Nil{}:
      Bool.and(operation_valid(operation), Bool.and(associated_valid(associated), Bool.and(value_valid(value), pattern_valid(pattern))))
    case _:
      False{}

def exits_valid(values: List<&2, Nat>) -> Bool:
  match values:
    case 50n <> 70n <> Nil{}:
      True{}
    case _:
      False{}

def reflections_valid(values: List<&2, I.Reflection>) -> Bool:
  match values:
    case I.Reflection{"callee", "reflection source"} <> Nil{}:
      True{}
    case _:
      False{}

def evidence_matches(found: Result<&2, &2, M.Diagnostic, S.Instantiated>) -> Bool:
  match found:
    case Done{S.Instantiated{I.Inference{ty, coverage, exits, reflections}, next}}:
      Bool.and(Nat.is_eq(next, 22n), Bool.and(CoreCompare.same_ty(ty, M.FunctionTy{M.VariableTy{20n}, M.VariableTy{21n}, row(21n)}), Bool.and(coverages_valid(coverage), Bool.and(exits_valid(exits), reflections_valid(reflections)))))
    case _:
      False{}

def fallback_matches(found: Result<&2, &2, M.Diagnostic, S.Instantiated>) -> Bool:
  match found:
    case Done{S.Instantiated{I.Inference{M.VariableTy{21n}, Nil{}, 50n <> Nil{}, Nil{}}, 22n}}:
      True{}
    case _:
      False{}

def fallback_valid() -> Bool:
  fallback_matches(S.instantiate(I.Inference{M.VariableTy{0n}, Nil{}, [5n], Nil{}}, [0n, 20n], 20n, identity_map()))

# Exercise every Ty constructor over 224 bounded inputs, including ordered
# duplicate rows, noncontiguous binders, repeated binders and target collisions.
def generated_case(choice: Nat, +index: Nat) -> M.Ty:
  match choice:
    case 0n:
      M.UnitTy{}
    case 1n:
      M.U32Ty{}
    case 2n:
      M.BoolTy{}
    case 3n:
      M.NeverTy{}
    case 4n:
      M.F32Ty{}
    case 5n:
      M.EffectDescriptorTy{}
    case 6n:
      M.EffectSetTy{}
    case 7n:
      M.ParameterTy{index}
    case 8n:
      M.FreeTy{"generated", "free"}
    case 9n:
      M.VariableTy{index}
    case 10n:
      M.AppliedTy{identity(), [M.VariableTy{index}, M.ArrayTy{M.VariableTy{2n}}]}
    case 11n:
      M.FunctionTy{M.VariableTy{index}, M.VariableTy{7n}, row(index)}
    case 12n:
      M.ProviderTy{identity(), row(index)}
    case 13n:
      M.StateProviderTy{identity(), identity(), M.VariableTy{index}}
    case 14n:
      M.ProductTy{[M.VariableTy{index}, M.FunctionTy{M.VariableTy{2n}, M.VariableTy{7n}, row(index)}]}
    case 15n:
      M.ArrayTy{M.VariableTy{index}}
    case _:
      M.FunctionTy{M.AppliedTy{identity(), [M.VariableTy{index}]}, M.ProviderTy{identity(), row(7n)}, M.EffectRow{labels(), M.RowParameter{index}}}

def generated(+seed: Nat) -> M.Ty:
  generated_case(Nat.mod(seed, 17n), Nat.mod(seed, 23n))

def binders(choice: Nat) -> List<&2, Nat>:
  match choice:
    case 0n:
      Nil{}
    case 1n:
      [7n, 2n]
    case 2n:
      [2n, 2n]
    case 3n:
      [0n, 20n]
    case _:
      [9n, 2n, 7n]

def same_instances(left: Result<&2, &2, M.Diagnostic, I.SchemeInstance>, right: Result<&2, &2, M.Diagnostic, I.SchemeInstance>) -> Bool:
  match left right:
    case Done{I.SchemeInstance{a, an}} Done{I.SchemeInstance{b, bn}}:
      Bool.and(Nat.is_eq(an, bn), CoreCompare.same_ty(a, b))
    case _ _:
      False{}

def differential_case(+seed: Nat) -> Bool:
  +ty = generated(seed)
  +variables = binders(Nat.mod(seed, 5n))
  same_instances(I.instance(variables, ty, 20n), I.instance_sequential(variables, ty, 20n))

def same_templates(left: Result<&2, &2, M.Diagnostic, M.Ty>, right: Result<&2, &2, M.Diagnostic, M.Ty>) -> Bool:
  match left right:
    case Done{a} Done{b}:
      CoreCompare.same_ty(a, b)
    case _ _:
      False{}

def template_case(+seed: Nat) -> Bool:
  +ty = generated(seed)
  +variables = binders(Nat.mod(seed, 5n))
  same_templates(Groups.template_type(variables, 0n, ty), Groups.template_type_sequential(variables, 0n, ty))

def differential_cases(remaining: Nat, +seed: Nat) -> Bool:
  match remaining:
    case 0n:
      True{}
    case 1n+rest:
      Bool.and(differential_case(seed), Bool.and(template_case(seed), differential_cases(rest, 1n+seed)))

def valid() -> Bool:
  Bool.and(type_checks(), Bool.and(unchanged_scope(), Bool.and(evidence_matches(S.instantiate(original_inference(), [2n, 7n], 20n, identity_map())), Bool.and(fallback_valid(), differential_cases(224n, 0n)))))

def finish(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "residual scheme renaming regression failed")

def main() -> IO(Unit):
  finish(valid())
