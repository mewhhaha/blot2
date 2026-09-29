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

# Several branches can inspect different bits of the same character. Check
# the distance first so a zero-distance advance leaves the suffix untouched.
def advance_suffix(distance: Nat, remaining: String) -> String:
  match distance remaining:
    case 0n suffix:
      suffix
    case 1n+rest SNil{}:
      SNil{}
    case 1n+rest SCon{head, tail}:
      advance_suffix(rest, tail)

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
      +suffix = advance_suffix(Nat.sub(character, cursor), remaining)
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

# Return the first differing Base.Map bit, or None for equal strings. Preserve
# both roots while cursors move so native character reads remain borrowed.
type KeyDifference is Data:
  KeyDifference{position: Maybe<&2, Nat>, left: String, right: String}

def differing_bit(delta: U32, position: Nat) -> Maybe<&2, Nat>:
  match delta:
    case 0: None{}
    case value: Some{Nat.add(position, Map.diff.chr(value))}

def difference_walk(left_root: String, right_root: String, left: String, right: String, +position: Nat, different: Maybe<&2, Nat>) -> KeyDifference:
  match left right different:
    case _ _ Some{at}:
      KeyDifference{Some{at}, left_root, right_root}
    case SNil{} SNil{} None{}:
      KeyDifference{None{}, left_root, right_root}
    case SCon{Chr{x}, left_tail} SCon{Chr{y}, right_tail} None{}:
      difference_walk(left_root, right_root, left_tail, right_tail, Nat.add(position, 33n), differing_bit(U32.xor(x, y), position))
    case _ _ None{}:
      KeyDifference{Some{position}, left_root, right_root}

def difference_result(value: KeyDifference) -> Maybe<&2, Nat>:
  KeyDifference{position, left, right} = value
  position

def difference(+left: String, +right: String) -> Maybe<&2, Nat>:
  difference_result(difference_walk(left, right, left, right, 0n, None{}))

# A zipper records only the sibling and position at each visited branch. Seek
# once, then rebuild once; Base.Map.set reconstructs a search result and starts
# over to insert/update it. Branch positions increase toward the leaves.
type InsertFrame<-V: Data> is Data:
  LeftFrame{position: Nat, right: Map<&2, V>}
  RightFrame{position: Nat, left: Map<&2, V>}

def rebuild(-V: Data, frames: List<&2, InsertFrame<V>>, node: Map<&2, V>) -> Map<&2, V>:
  match frames:
    case Nil{}: node
    case LeftFrame{position, right} <> tail:
      rebuild(V, tail, MNode{position, node, right})
    case RightFrame{position, left} <> tail:
      rebuild(V, tail, MNode{position, left, node})

def splice_bit(-V: Data, high: Bool, position: Nat, key: String, value: V, previous: Map<&2, V>) -> Map<&2, V>:
  match high:
    case False{}: MNode{position, MLeaf{key, value}, previous}
    case True{}: MNode{position, previous, MLeaf{key, value}}

def splice(-V: Data, +position: Nat, +key: String, value: V, previous: Map<&2, V>) -> Map<&2, V>:
  splice_bit(V, string_bit(key, Nat.div(position, 33n), Nat.mod(position, 33n)), position, key, value, previous)

def above_split(-V: Data, frames: List<&2, InsertFrame<V>>, split: Nat) -> Bool:
  match frames:
    case Nil{}: True{}
    case LeftFrame{position, right} <> tail: Nat.is_lt(position, split)
    case RightFrame{position, left} <> tail: Nat.is_lt(position, split)

# Rebuild deeper branches before splicing the new leaf. Stop as soon as the
# remaining parent precedes the new split; its direction is already recorded.
def insert_above(-V: Data, fuel: Nat, ready: Bool, frames: List<&2, InsertFrame<V>>, node: Map<&2, V>, key: String, value: V, +split: Nat) -> Map<&2, V>:
  match fuel ready frames:
    case _ True{} rest:
      rebuild(V, rest, splice(V, split, key, value, node))
    case 0n False{} rest:
      Map.set(&2, V, rebuild(V, rest, node), key, value)
    case 1n+fuel False{} Nil{}:
      splice(V, split, key, value, node)
    case 1n+fuel False{} LeftFrame{position, right} <> +tail:
      insert_above(V, fuel, above_split(V, tail, split), tail, MNode{position, node, right}, key, value, split)
    case 1n+fuel False{} RightFrame{position, left} <> +tail:
      insert_above(V, fuel, above_split(V, tail, split), tail, MNode{position, left, node}, key, value, split)

def set_leaf(-V: Data, split: Maybe<&2, Nat>, previous_key: String, previous_value: V, key: String, value: V, +frames: List<&2, InsertFrame<V>>) -> Map<&2, V>:
  match split:
    case None{}:
      rebuild(V, frames, MLeaf{previous_key, value})
    case Some{+position}:
      insert_above(V, M.max_nat(), above_split(V, frames, position), frames, MLeaf{previous_key, previous_value}, key, value, position)

type InsertPath<-V: Data> is Data:
  InsertPath{node: Map<&2, V>, frames: List<&2, InsertFrame<V>>}

def descend(-V: Data, high: Bool, position: Nat, left: Map<&2, V>, right: Map<&2, V>, frames: List<&2, InsertFrame<V>>) -> InsertPath<V>:
  match high:
    case False{}: InsertPath{left, LeftFrame{position, right} <> frames}
    case True{}: InsertPath{right, RightFrame{position, left} <> frames}

def set_loop(-V: Data, fuel: Nat, path: InsertPath<V>, +key: String, value: V, remaining: String, cursor: Nat) -> Map<&2, V>:
  match fuel path:
    case 0n InsertPath{original, frames}:
      Map.set(&2, V, rebuild(V, frames, original), key, value)
    case 1n+rest InsertPath{MTip{}, frames}:
      MLeaf{key, value}
    case 1n+rest InsertPath{MLeaf{+previous_key, previous_value}, frames}:
      set_leaf(V, difference(key, previous_key), previous_key, previous_value, key, value, frames)
    case 1n+rest InsertPath{MNode{+position, left, right}, frames}:
      +character = Nat.div(position, 33n)
      +suffix = advance_suffix(Nat.sub(character, cursor), remaining)
      set_loop(V, rest, descend(V, string_bit(suffix, 0n, Nat.mod(position, 33n)), position, left, right, frames), key, value, suffix, character)

# Compiler indexes are Data-valued maps. Preserve Base.Map's Patricia shape,
# iteration order and replacement semantics, including persistent snapshots.
def set(-V: Data, index: Map<&2, V>, +key: String, value: V) -> Map<&2, V>:
  set_loop(V, M.max_nat(), InsertPath{index, Nil{}}, key, value, key, 0n)

def set_reference(-V: Data, index: Map<&2, V>, key: String, value: V) -> Map<&2, V>:
  Map.set(&2, V, index, key, value)
