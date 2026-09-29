import Base
import ./model.bend as M
import ./types.bend as T
import ./infer.bend as I
import ./nat_index.bend as NatIndex
import ./constraints.bend as C
import ./use_plans.bend as Uses

# A retained inference result is useful only when all its type-bearing evidence
# moves with the scheme. Identity renaming is supplied by the caller that also
# clones the expression body; this module does not claim to clone typed bodies.
# Subjects, reflection callee names, nominal IDs, pattern syntax and ordered
# effect labels remain attached to their original source declarations.
type Instantiated is Data:
  Instantiated{inference: I.Inference, next: Nat}

type Rewrite is Data:
  Alpha{types: NatIndex.Index<Nat>, identities: NatIndex.Index<Nat>}
  Sequential{old: Nat, fresh: Nat}
  Identities{mapping: NatIndex.Index<Nat>}

def rewrite_type(ty: M.Ty, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match rewrite:
    case Alpha{mapping, identities}:
      T.rename_type(ty, mapping)
    case Sequential{old, fresh}:
      T.replace(ty, old, M.VariableTy{fresh})
    case Identities{mapping}:
      Done{ty}

def rewrite_row(row: M.EffectRow, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, M.EffectRow>:
  match rewrite:
    case Alpha{mapping, identities}:
      Done{T.rename_row(row, mapping)}
    case Sequential{old, fresh}:
      T.rewrite_row(row, T.ReplaceVariable{old, M.VariableTy{fresh}})
    case Identities{mapping}:
      Done{row}

def rewrite_invocation(invocation: Maybe<&2, M.EffectRow>, rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
  match invocation:
    case None{}:
      Done{None{}}
    case Some{row}:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, M.EffectRow>>:
        next : M.EffectRow <- rewrite_row(row, rewrite)
        return Some{next}

def rewrite_identity(identity: Nat, +rewrite: Rewrite) -> Nat:
  match rewrite:
    case Alpha{mapping, identities}:
      T.renamed_variable(identities, identity)
    case Sequential{old, fresh}:
      identity
    case Identities{mapping}:
      T.renamed_variable(mapping, identity)

def rewrite_predicate(predicate: M.Predicate, rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, M.Predicate>:
  match rewrite:
    case Alpha{mapping, identities}:
      C.rename(mapping, predicate)
    case Sequential{old, fresh}:
      C.transform(predicate, C.ReplaceVariable{old, fresh})
    case Identities{mapping}:
      Done{predicate}

def rewrite_predicates(predicates: List<&2, M.Predicate>, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
  match predicates:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>:
        first : M.Predicate <- rewrite_predicate(head, rewrite)
        rest : List<&2, M.Predicate> <- rewrite_predicates(tail, rewrite)
        return first <> rest

def rewrite_uses(uses: List<&2, C.UsePlan>, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, List<&2, C.UsePlan>>:
  match uses:
    case Nil{}:
      Done{Nil{}}
    case C.UsePlan{site, subject, ty, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.UsePlan>>:
        next_type : M.Ty <- rewrite_type(ty, rewrite)
        next_predicates : List<&2, M.Predicate> <- rewrite_predicates(predicates, rewrite)
        rest : List<&2, C.UsePlan> <- rewrite_uses(tail, rewrite)
        return C.UsePlan{rewrite_identity(site, rewrite), subject, next_type, next_predicates} <> rest

def rewrite_reflections(reflections: List<&2, I.Reflection>, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, List<&2, I.Reflection>>:
  match reflections:
    case Nil{}:
      Done{Nil{}}
    case I.Reflection{callee, subject, ty, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Reflection>>:
        next_type : M.Ty <- rewrite_type(ty, rewrite)
        next_predicates : List<&2, M.Predicate> <- rewrite_predicates(predicates, rewrite)
        rest : List<&2, I.Reflection> <- rewrite_reflections(tail, rewrite)
        return I.Reflection{callee, subject, next_type, next_predicates} <> rest

def rewrite_types(values: List<&2, M.Ty>, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match values:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        first : M.Ty <- rewrite_type(head, rewrite)
        rest : List<&2, M.Ty> <- rewrite_types(tail, rewrite)
        return first <> rest

def rewrite_coverage(value: I.Coverage, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, I.Coverage>:
  match value:
    case I.DemandCall{site}:
      Done{I.DemandCall{rewrite_identity(site, rewrite)}}
    case I.QualifiedBoundary{offset, declared, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        needs : List<&2, M.Predicate> <- rewrite_predicates(declared, rewrite)
        return I.QualifiedBoundary{offset, needs, subject}
    case I.QualifiedNeed{site, predicate, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        next : M.Predicate <- rewrite_predicate(predicate, rewrite)
        return I.QualifiedNeed{rewrite_identity(site, rewrite), next, subject}
    case I.OperationNeed{identity, template, arguments, function_type, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        args : List<&2, M.Ty> <- rewrite_types(arguments, rewrite)
        function : M.Ty <- rewrite_type(function_type, rewrite)
        return I.OperationNeed{rewrite_identity(identity, rewrite), template, args, function, subject}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        l : M.Ty <- rewrite_type(left, rewrite)
        r : M.Ty <- rewrite_type(right, rewrite)
        value : M.Ty <- rewrite_type(result, rewrite)
        selected : Maybe<&2, M.EffectRow> <- rewrite_invocation(invocation, rewrite)
        row : M.EffectRow <- rewrite_row(ambient, rewrite)
        return I.AssociatedNeed{rewrite_identity(identity, rewrite), dispatch, member, templates, l, r, value, selected, row, subject}
    case I.ValuePatternType{inferred_type, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        ty : M.Ty <- rewrite_type(inferred_type, rewrite)
        return I.ValuePatternType{ty, subject}
    case I.Coverage{inferred_types, patterns, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        types : List<&2, M.Ty> <- rewrite_types(inferred_types, rewrite)
        return I.Coverage{types, patterns, subject}
    case I.LetGeneralized{witness}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        ty : M.Ty <- rewrite_type(witness, rewrite)
        return I.LetGeneralized{ty}

def rewrite_coverages(values: List<&2, I.Coverage>, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, List<&2, I.Coverage>>:
  match values:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Coverage>>:
        first : I.Coverage <- rewrite_coverage(head, rewrite)
        rest : List<&2, I.Coverage> <- rewrite_coverages(tail, rewrite)
        return first <> rest

def rewrite_exits(exits: List<&2, Nat>, +rewrite: Rewrite) -> List<&2, Nat>:
  match exits:
    case Nil{}:
      Nil{}
    case head <> tail:
      rewrite_identity(head, rewrite) <> rewrite_exits(tail, rewrite)

def rewrite_inference(inference: I.Inference, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, I.Inference>:
  I.Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  do Result<&2, &2, M.Diagnostic, I.Inference>:
    result : M.Ty <- rewrite_type(ty, rewrite)
    needs : List<&2, I.Coverage> <- rewrite_coverages(coverage, rewrite)
    next_predicates : List<&2, M.Predicate> <- rewrite_predicates(predicates, rewrite)
    next_uses : List<&2, C.UsePlan> <- rewrite_uses(uses, rewrite)
    next_reflections : List<&2, I.Reflection> <- rewrite_reflections(reflections, rewrite)
    return I.Inference{result, needs, rewrite_exits(exits, rewrite), next_reflections, next_predicates, next_uses}

# The fallback exactly retains the old left-to-right substitution behavior for
# duplicate quantified IDs and allocation collisions. It remaps source IDs once
# after all type substitutions so IDs never depend on binder count.
def sequential(variables: List<&2, Nat>, inference: I.Inference, +next: Nat, identities: NatIndex.Index<Nat>) -> Result<&2, &2, M.Diagnostic, Instantiated>:
  match variables:
    case Nil{}:
      do Result<&2, &2, M.Diagnostic, Instantiated>:
        remapped : I.Inference <- rewrite_inference(inference, Identities{identities})
        return Instantiated{remapped, next}
    case old <> tail:
      do Result<&2, &2, M.Diagnostic, Instantiated>:
        rewritten : I.Inference <- rewrite_inference(inference, Sequential{old, next})
        sequential(tail, rewritten, 1n+next, identities)

def instantiate_with_renaming(renaming: T.Renaming, variables: List<&2, Nat>, inference: I.Inference, next: Nat, identities: NatIndex.Index<Nat>) -> Result<&2, &2, M.Diagnostic, Instantiated>:
  match renaming:
    case T.Renaming{types, fresh_next, True{}}:
      do Result<&2, &2, M.Diagnostic, Instantiated>:
        rewritten : I.Inference <- rewrite_inference(inference, Alpha{types, identities})
        return Instantiated{rewritten, fresh_next}
    case T.Renaming{types, fresh_next, False{}}:
      sequential(variables, inference, next, identities)

def instantiate(inference: I.Inference, +variables: List<&2, Nat>, +next: Nat, identities: NatIndex.Index<Nat>) -> Result<&2, &2, M.Diagnostic, Instantiated>:
  instantiate_with_renaming(T.renaming(variables, next), variables, inference, next, identities)
