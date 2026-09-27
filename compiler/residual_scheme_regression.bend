import Base
import ./model.bend as M
import ./types.bend as T
import ./infer.bend as I
import ./residual_scheme.bend as S
import ./nat_index.bend as N
import ./core_compare.bend as CoreCompare
import ./groups.bend as Groups
import ./constraints.bend as C
import ./staging_residual.bend as Staging
import ./parallel_infer.bend as Parallel

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
    case Done{I.SchemeInstance{ty, Nil{}, actual_next}}:
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

def predicates(+left: Nat, +right: Nat) -> List<&2, M.Predicate>:
  [M.AssociatedPredicate{"+", [identity()], M.VariableTy{left}, M.VariableTy{right}, M.VariableTy{left}, row(right)},
   M.ReceiverPredicate{"method", [identity()], M.VariableTy{left}, M.VariableTy{right}, M.VariableTy{left}, row(right)},
   M.FieldPredicate{"field", M.VariableTy{left}, M.VariableTy{right}},
   M.UpdatePredicate{"field", M.VariableTy{left}, M.VariableTy{right}, M.ArrayTy{M.VariableTy{right}}, row(left)},
   M.OperationPredicate{identity(), [M.VariableTy{left}], M.FunctionTy{M.VariableTy{left}, M.FunctionTy{M.VariableTy{right}, M.VariableTy{9n}, row(left)}, row(right)}},
   M.TypeRepPredicate{M.ProductTy{[M.VariableTy{left}, M.VariableTy{9n}]}},
   M.EffectRepPredicate{row(right)}]

def same_predicates(left: List<&2, M.Predicate>, right: List<&2, M.Predicate>) -> Bool:
  match left right:
    case Nil{} Nil{}:
      True{}
    case a <> xs b <> ys:
      Bool.and(CoreCompare.same_predicate(a, b), same_predicates(xs, ys))
    case _ _:
      False{}

def qualified_type(+left: Nat, +right: Nat) -> M.Ty:
  M.FunctionTy{M.VariableTy{left}, M.VariableTy{right}, row(right)}

def original_inference() -> I.Inference:
  I.Inference{
    M.FunctionTy{M.VariableTy{2n}, M.VariableTy{7n}, row(7n)},
    [I.OperationNeed{5n, identity(), [M.VariableTy{2n}], M.FunctionTy{M.VariableTy{2n}, M.VariableTy{7n}, row(7n)}, "operation source"},
     I.AssociatedNeed{6n, M.MemberDispatch{}, "member", [identity()], M.VariableTy{2n}, M.VariableTy{7n}, M.VariableTy{2n}, Some{row(7n)}, row(7n), "member source"},
     I.ValuePatternType{M.VariableTy{7n}, "value source"},
     I.Coverage{[M.VariableTy{2n}, M.VariableTy{7n}], [[M.WildcardPattern{}, M.U32Pattern{42}]], "pattern source"},
     I.QualifiedNeed{7n, M.EffectRepPredicate{row(7n)}, "qualified source"}],
    [5n, 7n], [I.Reflection{"callee", "reflection source", qualified_type(2n, 7n), predicates(2n, 7n)}], predicates(2n, 7n),
    [C.UsePlan{5n, "first use", qualified_type(2n, 7n), predicates(2n, 7n)}, C.UsePlan{6n, "second use", M.VariableTy{7n}, [M.TypeRepPredicate{M.VariableTy{2n}}]}]}

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
    case I.AssociatedNeed{60n, M.MemberDispatch{}, "member", _, M.VariableTy{20n}, M.VariableTy{21n}, M.VariableTy{20n}, Some{invocation}, effects, "member source"}:
      Bool.and(CoreCompare.same_ty(M.ProviderTy{identity(), invocation}, M.ProviderTy{identity(), row(21n)}), CoreCompare.same_ty(M.ProviderTy{identity(), effects}, M.ProviderTy{identity(), row(21n)}))
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

def qualified_valid(value: I.Coverage) -> Bool:
  match value:
    case I.QualifiedNeed{70n, predicate, "qualified source"}:
      CoreCompare.same_predicate(predicate, M.EffectRepPredicate{row(21n)})
    case _:
      False{}

def coverages_valid(values: List<&2, I.Coverage>) -> Bool:
  match values:
    case operation <> associated <> value <> pattern <> qualified <> Nil{}:
      Bool.and(operation_valid(operation), Bool.and(associated_valid(associated), Bool.and(value_valid(value), Bool.and(pattern_valid(pattern), qualified_valid(qualified)))))
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
    case I.Reflection{"callee", "reflection source", ty, needs} <> Nil{}:
      Bool.and(CoreCompare.same_ty(ty, qualified_type(20n, 21n)), same_predicates(needs, predicates(20n, 21n)))
    case _:
      False{}

def uses_valid(values: List<&2, C.UsePlan>, first: Nat, second: Nat) -> Bool:
  match values:
    case C.UsePlan{a, "first use", ty, needs} <> C.UsePlan{b, "second use", M.VariableTy{21n}, M.TypeRepPredicate{M.VariableTy{20n}} <> Nil{}} <> Nil{}:
      Bool.and(Nat.is_eq(a, first), Bool.and(Nat.is_eq(b, second), Bool.and(CoreCompare.same_ty(ty, qualified_type(20n, 21n)), same_predicates(needs, predicates(20n, 21n)))))
    case _:
      False{}

def evidence_valid(inference: I.Inference) -> Bool:
  I.Inference{ty, coverage, exits, reflections, needs, uses} = inference
  Bool.and(CoreCompare.same_ty(ty, qualified_type(20n, 21n)), Bool.and(coverages_valid(coverage), Bool.and(exits_valid(exits), Bool.and(reflections_valid(reflections), Bool.and(same_predicates(needs, predicates(20n, 21n)), uses_valid(uses, 50n, 60n))))))

def evidence_matches(found: Result<&2, &2, M.Diagnostic, S.Instantiated>) -> Bool:
  match found:
    case Done{S.Instantiated{inference, next}}:
      Bool.and(Nat.is_eq(next, 22n), evidence_valid(inference))
    case _:
      False{}

def fallback_matches(found: Result<&2, &2, M.Diagnostic, S.Instantiated>) -> Bool:
  match found:
    case Done{S.Instantiated{I.Inference{M.VariableTy{21n}, Nil{}, 50n <> Nil{}, Nil{}, Nil{}, Nil{}}, 22n}}:
      True{}
    case _:
      False{}

def fallback_valid() -> Bool:
  fallback_matches(S.instantiate(I.Inference{M.VariableTy{0n}, Nil{}, [5n], Nil{}, Nil{}, Nil{}}, [0n, 20n], 20n, identity_map()))

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
    case Done{I.SchemeInstance{a, ap, an}} Done{I.SchemeInstance{b, bp, bn}}:
      Bool.and(Nat.is_eq(an, bn), Bool.and(CoreCompare.same_ty(a, b), same_predicates(ap, bp)))
    case _ _:
      False{}

def differential_case(+seed: Nat) -> Bool:
  +ty = generated(seed)
  +variables = binders(Nat.mod(seed, 5n))
  same_instances(I.instance_qualified(variables, ty, predicates(2n, 7n), 20n), I.instance_sequential(variables, ty, predicates(2n, 7n), 20n))

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

def staging_matches(found: Result<&2, &2, M.Diagnostic, Staging.Instantiated>) -> Bool:
  match found:
    case Done{Staging.Instantiated{inference, 22n}}:
      evidence_valid(inference)
    case _:
      False{}

def type_map() -> N.Index<Nat>:
  N.set(Nat, N.set(Nat, N.new(Nat), 2n, 20n), 7n, 21n)

def parallel_matches(found: Result<&2, &2, M.Diagnostic, I.Definition>) -> Bool:
  match found:
    case Done{I.Definition{"qualified", I.Inference{ty, I.OperationNeed{5n, _, _, _, _} <> I.AssociatedNeed{6n, _, _, _, _, _, _, _, _, _} <> _ <> _ <> I.QualifiedNeed{7n, predicate, "qualified source"} <> Nil{}, 5n <> 7n <> Nil{}, reflections, needs, uses}}}:
      Bool.and(CoreCompare.same_ty(ty, qualified_type(20n, 21n)), Bool.and(CoreCompare.same_predicate(predicate, M.EffectRepPredicate{row(21n)}), Bool.and(reflections_valid(reflections), Bool.and(same_predicates(needs, predicates(20n, 21n)), uses_valid(uses, 5n, 6n)))))
    case _:
      False{}

# Every variable here appears only in metadata. Parallel read/write guards and
# staged scheme quantification must still observe all five dependencies.
def metadata_only() -> I.Inference:
  I.Inference{M.UnitTy{}, Nil{}, Nil{}, [I.Reflection{"callee", "reflection", M.VariableTy{31n}, [M.TypeRepPredicate{M.VariableTy{32n}}]}],
    [M.EffectRepPredicate{row(35n)}], [C.UsePlan{5n, "use", M.VariableTy{33n}, [M.TypeRepPredicate{M.VariableTy{34n}}]}]}

def metadata_free_valid(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>) -> Bool:
  match found:
    case Done{+variables}:
      Bool.and(Nat.is_eq(List.length(&2, Nat, variables), 5n), Bool.and(T.contains(variables, 31n), Bool.and(T.contains(variables, 32n), Bool.and(T.contains(variables, 33n), Bool.and(T.contains(variables, 34n), T.contains(variables, 35n))))))
    case _:
      False{}

def qualified_replay_valid() -> Bool:
  Bool.and(staging_matches(Staging.instantiate(original_inference(), [2n, 7n], 20n, identity_map())),
    Bool.and(parallel_matches(Parallel.rename_definition(I.Definition{"qualified", original_inference()}, type_map())),
    Bool.and(metadata_free_valid(Staging.free(metadata_only())), metadata_free_valid(Parallel.definition_free(I.Definition{"qualified", metadata_only()})))))

def valid() -> Bool:
  Bool.and(qualified_replay_valid(), Bool.and(type_checks(), Bool.and(unchanged_scope(), Bool.and(evidence_matches(S.instantiate(original_inference(), [2n, 7n], 20n, identity_map())), Bool.and(fallback_valid(), differential_cases(224n, 0n))))))

def finish(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "residual scheme renaming regression failed")

def main() -> IO(Unit):
  finish(valid())
