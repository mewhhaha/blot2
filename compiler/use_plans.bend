import Base
import ./model.bend as M
import ./types.bend as T
import ./constraints.bend as C

# Scheme type variables and every predicate share the same transformation.
# Source identity is supplied separately by the expression-cloning caller.
def transform(plan: C.UsePlan, +change: C.Transform, site: Nat) -> Result<&2, &2, M.Diagnostic, C.UsePlan>:
  C.UsePlan{old_site, subject, ty, predicates} = plan
  do Result<&2, &2, M.Diagnostic, C.UsePlan>:
    changed_type : M.Ty <- C.transform_type(ty, change)
    changed_predicates : List<&2, M.Predicate> <- C.transform_list(predicates, change)
    return C.UsePlan{site, subject, changed_type, changed_predicates}

def transform_types(plans: List<&2, C.UsePlan>, +change: C.Transform) -> Result<&2, &2, M.Diagnostic, List<&2, C.UsePlan>>:
  match plans:
    case Nil{}:
      Done{Nil{}}
    case C.UsePlan{+site, subject, ty, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.UsePlan>>:
        first : C.UsePlan <- transform(C.UsePlan{site, subject, ty, predicates}, change, site)
        rest : List<&2, C.UsePlan> <- transform_types(tail, change)
        return first <> rest

def free(plans: List<&2, C.UsePlan>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match plans:
    case Nil{}:
      Done{Nil{}}
    case C.UsePlan{site, subject, ty, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        type_vars : List<&2, Nat> <- T.free(ty)
        predicate_vars : List<&2, Nat> <- C.free_list(predicates)
        rest : List<&2, Nat> <- free(tail)
        return T.union(type_vars, T.union(predicate_vars, rest))
