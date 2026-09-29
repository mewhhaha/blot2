import Base
import ./model.bend as M
import ./types.bend as T
import ./constraints.bend as C

def rebuild_arms(arms: List<&2, M.MatchArm<M.Expr>>, bodies: List<&2, M.Expr>) -> List<&2, M.MatchArm<M.Expr>>:
  match arms bodies:
    case M.MatchArm{patterns, old} <> tail body <> remaining:
      M.MatchArm{patterns, body} <> rebuild_arms(tail, remaining)
    case _ _:
      Nil{}

# A clone owns a disjoint range of lambda, return-label and dispatch identities.
def identity(base: Nat, original: Nat) -> Nat:
  Nat.add(base, original)

def relocate_annotation(annotation: Maybe<&2, M.Ty>, +base: Nat) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
  match annotation base:
    case annotation 0n:
      Done{annotation}
    case None{} _:
      Done{None{}}
    case Some{ty} _:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.Ty>>:
        types : List<&2, M.Ty> <- T.rewrite(65536n, T.OneType{ty}, T.RelocateFree{"$mono[" ++ Nat.show(base) ++ "]"})
        relocated : M.Ty <- T.first_type(types)
        return Some{relocated}

def relocate_arguments(arguments: List<&2, M.Ty>, base: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match base:
    case 0n:
      Done{arguments}
    case base:
      T.rewrite(65536n, T.ManyTypes{arguments}, T.RelocateFree{"$mono[" ++ Nat.show(base) ++ "]"})

def relocate_predicates(predicates: List<&2, M.Predicate>, base: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match base:
    case 0n:
      Done{predicates}
    case base:
      C.relocate_free(predicates, "$mono[" ++ Nat.show(base) ++ "]")

def rebuild(original: M.Expr, children: List<&2, M.Expr>, +base: Nat) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match original children:
    case M.ConstructExpr{constructor, Some{payload}} a <> Nil{}:
      Done{M.ConstructExpr{constructor, Some{a}}}
    case M.ProductExpr{elements} children:
      Done{M.ProductExpr{children}}
    case M.ArrayExpr{elements} children:
      Done{M.ArrayExpr{children}}
    case M.ProjectExpr{value, index} a <> Nil{}:
      Done{M.ProjectExpr{a, index}}
    case M.LambdaExpr{old, parameter, p, r, body} a <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        parameter_type : Maybe<&2, M.Ty> <- relocate_annotation(p, base)
        result_type : Maybe<&2, M.Ty> <- relocate_annotation(r, base)
        return M.LambdaExpr{identity(base, old), parameter, parameter_type, result_type, a}
    case M.MemoExpr{computation} a <> Nil{}:
      Done{M.MemoExpr{a}}
    case M.ForceExpr{value} a <> Nil{}:
      Done{M.ForceExpr{a}}
    case M.ApplyExpr{callee, argument} a <> b <> Nil{}:
      Done{M.ApplyExpr{a, b}}
    case M.TagExpr{offset, callee, argument} a <> b <> Nil{}:
      Done{M.TagExpr{offset, a, b}}
    case M.CallExpr{callee, argument} a <> Nil{}:
      Done{M.CallExpr{callee, a}}
    case M.ScalarExpr{operator, left, right} a <> b <> Nil{}:
      Done{M.ScalarExpr{operator, a, b}}
    case M.GenericOperationExpr{old, template, arguments} Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        relocated : List<&2, M.Ty> <- relocate_arguments(arguments, base)
        return M.GenericOperationExpr{identity(base, old), template, relocated}
    case M.AssociatedExpr{old, dispatch, member, templates, left, right} a <> b <> Nil{}:
      Done{M.AssociatedExpr{identity(base, old), dispatch, member, templates, a, b}}
    case M.UnaryExpr{operator, value} a <> Nil{}:
      Done{M.UnaryExpr{operator, a}}
    case M.LetExpr{name, value, body} a <> b <> Nil{}:
      Done{M.LetExpr{name, a, b}}
    case M.UseExpr{name, value, body} a <> b <> Nil{}:
      Done{M.UseExpr{name, a, b}}
    case M.IfExpr{condition, consequent, alternative} a <> b <> c <> Nil{}:
      Done{M.IfExpr{a, b, c}}
    case M.SequenceExpr{first, next} a <> b <> Nil{}:
      Done{M.SequenceExpr{a, b}}
    case M.GuardExpr{pattern, value, alternative, body} a <> b <> c <> Nil{}:
      Done{M.GuardExpr{pattern, a, b, c}}
    case M.BlockExpr{label, body} a <> Nil{}:
      Done{M.BlockExpr{identity(base, label), a}}
    case M.ReturnExpr{label, value} a <> Nil{}:
      Done{M.ReturnExpr{identity(base, label), a}}
    case M.RuntimeInitExpr{value} a <> Nil{}:
      Done{M.RuntimeInitExpr{a}}
    case M.SourceExpr{offset, annotation, value} a <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        relocated : Maybe<&2, M.Ty> <- relocate_annotation(annotation, base)
        return M.SourceExpr{offset, relocated, a}
    case M.QualifiedExpr{offset, annotation, predicates, value} a <> Nil{}:
      do Result<&2, &2, M.Diagnostic, M.Expr>:
        types : List<&2, M.Ty> <- relocate_arguments([annotation], base)
        relocated : M.Ty <- T.first_type(types)
        requirements : List<&2, M.Predicate> <- relocate_predicates(predicates, base)
        return M.QualifiedExpr{offset, relocated, requirements, a}
    case M.InstantiationExpr{site, value} a <> Nil{}:
      Done{M.InstantiationExpr{identity(base, site), a}}
    case M.StateProviderExpr{read, write, initial} a <> Nil{}:
      Done{M.StateProviderExpr{read, write, a}}
    case M.ProviderExpr{operation, implementation} a <> Nil{}:
      Done{M.ProviderExpr{operation, a}}
    case M.HandleExpr{provider, body} a <> b <> Nil{}:
      Done{M.HandleExpr{a, b}}
    case M.EffectHasExpr{set, operation} a <> b <> Nil{}:
      Done{M.EffectHasExpr{a, b}}
    case M.EffectCountExpr{set} a <> Nil{}:
      Done{M.EffectCountExpr{a}}
    case M.EffectSameExpr{left, right} a <> b <> Nil{}:
      Done{M.EffectSameExpr{a, b}}
    case M.ForExpr{index, start, end, state, initial, body} a <> b <> c <> d <> Nil{}:
      Done{M.ForExpr{index, a, b, state, c, d}}
    case M.ForeverExpr{state, initial, body} a <> b <> Nil{}:
      Done{M.ForeverExpr{state, a, b}}
    case M.ArrayGenerateExpr{count, generator} a <> b <> Nil{}:
      Done{M.ArrayGenerateExpr{a, b}}
    case M.ArrayFillExpr{count, value} a <> b <> Nil{}:
      Done{M.ArrayFillExpr{a, b}}
    case M.ArrayGetExpr{array, index} a <> b <> Nil{}:
      Done{M.ArrayGetExpr{a, b}}
    case M.ArraySetExpr{array, index, value} a <> b <> c <> Nil{}:
      Done{M.ArraySetExpr{a, b, c}}
    case M.ArrayLengthExpr{array} a <> Nil{}:
      Done{M.ArrayLengthExpr{a}}
    case M.MatchExpr{+values, arms} +children:
      Done{M.MatchExpr{List.take(&2, M.Expr, children, List.length(&2, M.Expr, values)), rebuild_arms(arms, List.drop(&2, M.Expr, children, List.length(&2, M.Expr, values)))}}
    case original Nil{}:
      Done{original}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "monomorphization", "expression children differ from their parent"}}
