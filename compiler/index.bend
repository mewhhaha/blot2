import Base
import ./model.bend as M

# Read-only compiler indexes do not need Map.get's reconstructed map or key.
def character_bit(character: Char, offset: Nat) -> Bool:
  match character offset:
    case Chr{value} 0n:
      True{}
    case Chr{value} 1n+bit:
      U32.is_ne(U32.and(U32.shrn(value, Nat.sub(31n, bit)), 1), 0)

def string_bit(name: String, character: Nat, +offset: Nat) -> Bool:
  match name character:
    case SNil{} _:
      False{}
    case SCon{head, tail} 0n:
      character_bit(head, offset)
    case SCon{head, tail} 1n+rest:
      string_bit(tail, rest, offset)

def selected(-V: Data, high: Bool, right: Unit -> Maybe<&2, V>, left: Unit -> Maybe<&2, V>) -> Maybe<&2, V>:
  match high:
    case True{}:
      right(Unit{})
    case False{}:
      left(Unit{})

def find(-V: Data, index: Map<&2, V>, +name: String) -> Maybe<&2, V>:
  match index:
    case MTip{}:
      None{}
    case MLeaf{key, value}:
      Bool.pick(Maybe<&2, V>, M.name_equal(key, name), Some{value}, None{})
    case MNode{+position, left, right}:
      selected(V, string_bit(name, Nat.div(position, 33n), Nat.mod(position, 33n)), unit => find(V, right, name), unit => find(V, left, name))

def fallback(-V: Data, found: Maybe<&2, V>, otherwise: V) -> V:
  match found:
    case None{}:
      otherwise
    case Some{value}:
      value

def get(-V: Data, index: Map<&2, V>, name: String, otherwise: V) -> V:
  fallback(V, find(V, index, name), otherwise)
