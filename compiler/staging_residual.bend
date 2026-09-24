import Base
import ./model.bend as M
import ./types.bend as T
import ./infer.bend as I
import ./nat_index.bend as NatIndex

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
  IdentityOffset{base: Nat}
  Resolution{substitutions: T.Substitutions}

def rewrite_type(ty: M.Ty, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match rewrite:
    case Alpha{mapping, identities}:
      T.rename_type(ty, mapping)
    case Sequential{old, fresh}:
      T.replace(ty, old, M.VariableTy{fresh})
    case Identities{mapping}:
      Done{ty}
    case IdentityOffset{base}:
      Done{ty}
    case Resolution{substitutions}:
      T.resolve(substitutions, ty)

def rewrite_row(row: M.EffectRow, +rewrite: Rewrite) -> Result<&2, &2, M.Diagnostic, M.EffectRow>:
  match rewrite:
    case Alpha{mapping, identities}:
      Done{T.rename_row(row, mapping)}
    case Sequential{old, fresh}:
      T.rewrite_row(row, T.ReplaceVariable{old, M.VariableTy{fresh}})
    case Identities{mapping}:
      Done{row}
    case IdentityOffset{base}:
      Done{row}
    case Resolution{substitutions}:
      Done{T.resolve_row(substitutions, row)}

def rewrite_identity(identity: Nat, +rewrite: Rewrite) -> Nat:
  match rewrite:
    case Alpha{mapping, identities}:
      T.renamed_variable(identities, identity)
    case Sequential{old, fresh}:
      identity
    case Identities{mapping}:
      T.renamed_variable(mapping, identity)
    case IdentityOffset{base}:
      Nat.add(base, identity)
    case Resolution{substitutions}:
      identity

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
    case I.OperationNeed{identity, template, arguments, function_type, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        args : List<&2, M.Ty> <- rewrite_types(arguments, rewrite)
        function : M.Ty <- rewrite_type(function_type, rewrite)
        return I.OperationNeed{rewrite_identity(identity, rewrite), template, args, function, subject}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, ambient, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        l : M.Ty <- rewrite_type(left, rewrite)
        r : M.Ty <- rewrite_type(right, rewrite)
        value : M.Ty <- rewrite_type(result, rewrite)
        row : M.EffectRow <- rewrite_row(ambient, rewrite)
        return I.AssociatedNeed{rewrite_identity(identity, rewrite), dispatch, member, templates, l, r, value, row, subject}
    case I.ValuePatternType{inferred_type, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        ty : M.Ty <- rewrite_type(inferred_type, rewrite)
        return I.ValuePatternType{ty, subject}
    case I.Coverage{inferred_types, patterns, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        types : List<&2, M.Ty> <- rewrite_types(inferred_types, rewrite)
        return I.Coverage{types, patterns, subject}

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
  I.Inference{ty, coverage, exits, reflections} = inference
  do Result<&2, &2, M.Diagnostic, I.Inference>:
    result : M.Ty <- rewrite_type(ty, rewrite)
    needs : List<&2, I.Coverage> <- rewrite_coverages(coverage, rewrite)
    return I.Inference{result, needs, rewrite_exits(exits, rewrite), reflections}

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

def resolve(inference: I.Inference, substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, I.Inference>:
  rewrite_inference(inference, Resolution{substitutions})

def offset_identities(inference: I.Inference, base: Nat) -> Result<&2, &2, M.Diagnostic, I.Inference>:
  rewrite_inference(inference, IdentityOffset{base})

def types_free(values: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match values:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        a : List<&2, Nat> <- T.free(head)
        b : List<&2, Nat> <- types_free(tail)
        return T.union(a, b)

def coverage_free(value: I.Coverage) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match value:
    case I.OperationNeed{identity, template, arguments, function_type, subject}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        a : List<&2, Nat> <- types_free(arguments)
        f : List<&2, Nat> <- T.free(function_type)
        return T.union(a, f)
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, ambient, subject}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        a : List<&2, Nat> <- T.free(left)
        b : List<&2, Nat> <- T.free(right)
        c : List<&2, Nat> <- T.free(result)
        return T.union(T.row_free(ambient), T.union(a, T.union(b, c)))
    case I.ValuePatternType{inferred_type, subject}:
      T.free(inferred_type)
    case I.Coverage{inferred_types, patterns, subject}:
      types_free(inferred_types)

def coverages_free(values: List<&2, I.Coverage>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match values:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        a : List<&2, Nat> <- coverage_free(head)
        b : List<&2, Nat> <- coverages_free(tail)
        return T.union(a, b)

def free(inference: I.Inference) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  I.Inference{ty, coverage, exits, reflections} = inference
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    a : List<&2, Nat> <- T.free(ty)
    b : List<&2, Nat> <- coverages_free(coverage)
    return T.union(a, b)
