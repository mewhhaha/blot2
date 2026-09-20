import Base
import ./model.bend as M

def effect_equal(left: M.Effect, right: M.Effect) -> Bool:
  M.OperationEffect{a} = left
  M.OperationEffect{b} = right
  M.type_id_equal(a, b)

def or_else(found: Bool, next: Unit -> Bool) -> Bool:
  match found:
    case True{}:
      True{}
    case False{}:
      next(Unit{})

def contains(effects: List<&2, M.Effect>, +effect: M.Effect) -> Bool:
  match effects:
    case Nil{}:
      False{}
    case head <> tail:
      or_else(effect_equal(head, effect), _ => contains(tail, effect))

def put_if(present: Bool, effects: List<&2, M.Effect>, effect: M.Effect) -> List<&2, M.Effect>:
  match present:
    case True{}:
      effects
    case False{}:
      effect <> effects

def put(+effects: List<&2, M.Effect>, +effect: M.Effect) -> List<&2, M.Effect>:
  put_if(contains(effects, effect), effects, effect)

def effect_le(left: M.Effect, right: M.Effect) -> Bool:
  M.OperationEffect{M.TypeId{+lm, ln}} = left
  M.OperationEffect{M.TypeId{+rm, rn}} = right
  Bool.or(String.is_lt(lm, rm), Bool.and(M.name_equal(lm, rm), String.is_le(ln, rn)))

def repeated(previous: Maybe<&2, M.Effect>, effect: M.Effect) -> Bool:
  match previous:
    case None{}:
      False{}
    case Some{last}:
      effect_equal(last, effect)

def deduplicate(sorted: List<&2, M.Effect>, previous: Maybe<&2, M.Effect>, reversed: List<&2, M.Effect>) -> List<&2, M.Effect>:
  match sorted:
    case Nil{}:
      List.reverse(&2, M.Effect, reversed)
    case +head <> tail:
      deduplicate(tail, Some{head}, put_if(repeated(previous, head), reversed, head))

# Reflection exposes sets. Scoped row multiplicity belongs to EffectRow, not
# this closed metadata representation.
def canonical(effects: List<&2, M.Effect>) -> List<&2, M.Effect>:
  deduplicate(List.sort(~M.Effect, ~effect_le, effects), None{}, Nil{})

def union(left: List<&2, M.Effect>, right: List<&2, M.Effect>) -> List<&2, M.Effect>:
  canonical(List.append(&2, M.Effect, left, right))
