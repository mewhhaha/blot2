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

# Patricia branch positions increase down the tree. Keep the suffix already
# reached instead of walking a long qualified name from its start at each hop.
def found_value(-V: Data, equal: Bool, value: V) -> Maybe<&2, V>:
  match equal:
    case False{}:
      None{}
    case True{}:
      Some{value}

# Select the child as data, then move the key and suffix into one tail call.
# Branch closures duplicate both strings and allocate continuations per hop.
# Fuel proves termination of the computed child; the full Nat address range
# exceeds the number of nodes in any representable in-memory map.
def find_loop(-V: Data, fuel: Nat, index: Map<&2, V>, name: String, remaining: String, cursor: Nat) -> Maybe<&2, V>:
  match fuel index:
    case 0n _:
      None{}
    case 1n+rest MTip{}:
      None{}
    case 1n+rest MLeaf{key, value}:
      found_value(V, M.name_equal(key, name), value)
    case 1n+rest MNode{+position, left, right}:
      +character = Nat.div(position, 33n)
      +suffix = String.drop(remaining, Nat.sub(character, cursor))
      next = Bool.pick(Map<&2, V>, string_bit(suffix, 0n, Nat.mod(position, 33n)), right, left)
      find_loop(V, rest, next, name, suffix, character)

def find_work(-V: Data, index: Map<&2, V>, name: String, remaining: String, cursor: Nat) -> Maybe<&2, V>:
  find_loop(V, M.max_nat(), index, name, remaining, cursor)

def find(-V: Data, index: Map<&2, V>, +name: String) -> Maybe<&2, V>:
  find_work(V, index, name, name, 0n)

def fallback(-V: Data, found: Maybe<&2, V>, otherwise: V) -> V:
  match found:
    case None{}:
      otherwise
    case Some{value}:
      value

def get(-V: Data, index: Map<&2, V>, name: String, otherwise: V) -> V:
  fallback(V, find(V, index, name), otherwise)
